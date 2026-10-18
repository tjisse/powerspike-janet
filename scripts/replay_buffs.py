"""Extract observed buff lifecycles; unknown names/behavior stay explicit.

Only three exact-build packet classes are supported. This is not proof that
every buff is replicated by these classes. No expiry or counter value deletes
an entry: explicit matching removals are required.
"""
import argparse
import bisect
from collections import Counter, defaultdict
import gzip
import json
from pathlib import Path
import time

from replay_framing import iter_blocks
from replay_native import NativeDecoder, BUILD, PROTOCOL
from replay_recovery import digest, load


def wire_key(event_id):
    stream, chunk, offset = event_id.split(':')
    if stream != 'gameChunk':
        raise ValueError('Only gameplay ordering is supported')
    return int(chunk), int(offset)


class BuffLedger:
    def __init__(self):
        self.active = defaultdict(dict)
        self.issues = defaultdict(list)
        self.counts = Counter()
        self.previous = None

    def invalidate(self, entity, event_id, reason):
        self.issues[entity].append({'event-id': event_id, 'reason': reason})

    def apply(self, row):
        key = wire_key(row['event-id'])
        if self.previous is not None and key <= self.previous:
            raise ValueError('Buff events must be in original gameplay wire order')
        self.previous = key
        entity, token, name = row['entity'], row['slot-token'], row['name-hash']
        active = self.active[entity]
        old = active.get(token)
        kind = row['kind']
        self.counts[kind] += 1
        if kind == 'add':
            if old and old['name-hash'] != name:
                self.counts['replacement-without-removal'] += 1
                self.invalidate(entity, row['event-id'], 'replacement-without-removal')
            active[token] = dict(row)
        elif kind in ('counter', 'remove'):
            if old is None or old['name-hash'] != name:
                self.counts[kind + '-without-matching-add'] += 1
                self.invalidate(entity, row['event-id'], kind + '-without-matching-add')
                return
            self.counts[kind + '-matched'] += 1
            if kind == 'remove':
                del active[token]
            else:
                # Preserve add identity and timestamp separately from updates.
                old['counter-update'] = dict(row)
        else:
            raise ValueError('Unknown lifecycle kind')

    def snapshot(self, entity):
        return {'observed-active': [dict(row) for _, row in sorted(self.active[entity].items())],
                'lifecycle-issues': list(self.issues[entity]),
                'complete-buff-state': False}


def ward_counter_check(rows, summary, match, timeline, include_herald=False):
    """Independent API correlation, not proof of the buff's complete behavior.

    The Herald extension was discovered AFTER inspecting the second game's
    discrepancies. It must not be reported as a sealed held-out result.
    """
    participants = {(p['championName'], p['teamId']): p['participantId']
                    for p in match['info']['participants']}
    ids = {summary['champion-entity-start'] + p['slot']: participants[p['champion'], p['team']]
           for p in summary['roster']}
    events = defaultdict(list)
    for frame in timeline['info']['frames']:
        for event in frame['events']:
            if event['type'] == 'WARD_PLACED' and event['wardType'] in (
                    'YELLOW_TRINKET', 'BLUE_TRINKET', 'SIGHT_WARD'):
                events[event['creatorId']].append(event['timestamp'])
            elif include_herald and event['type'] == 'ITEM_DESTROYED' and event['itemId'] == 3513:
                events[event['participantId']].append(event['timestamp'])
    for timestamps in events.values():
        timestamps.sort()
    checks = []
    for row in rows:
        if row['kind'] != 'counter' or row['name-hash'] != 205256130:
            continue
        participant = ids[row['entity']]
        expected = bisect.bisect_right(events[participant], round(row['timestamp'] * 1000) + 1)
        checks.append({'event-id': row['event-id'], 'timestamp': row['timestamp'],
                       'entity': row['entity'], 'decoded-counter': row['counter'],
                       'api-event-count': expected, 'consistent': row['counter'] == expected})
    return {'checks': len(checks), 'consistent': sum(r['consistent'] for r in checks),
            'rows': checks, 'api-timestamp-tolerance-ms': 1,
            'includes-herald-consumption': include_herald,
            'scope': 'Candidate non-control ward/trinket-use counter correlation; no damage behavior or exact internal name inferred'}


def decode(replay_path, image, profile_path, output, champion_start):
    from rofllens import ReplayReader
    from unicorn import UcError
    output = Path(output)
    if output.exists():
        raise ValueError('Choose a fresh output directory')
    started = time.monotonic()
    decoder = NativeDecoder(image, load(profile_path))
    ledger, counts, failures = BuffLedger(), Counter(), Counter()
    rejected = []
    with ReplayReader.open(replay_path) as replay:
        if replay.header.client_version != BUILD or replay.header.protocol_digest != PROTOCOL:
            raise ValueError('Replay exact build/protocol mismatch')
        output.mkdir(parents=True)
        with gzip.open(output / 'buffs.jsonl.gz', 'wt') as handle:
            for b in iter_blocks(replay, streams={'gameChunk'},
                                 opcodes={435, 262, 430}, include_payload=True):
                if not champion_start <= b.param < champion_start + 10:
                    continue
                event_id = f'{b.stream}:{b.chunk_id}:{b.block_offset}'
                common = {'event-id': event_id, 'timestamp': b.timestamp,
                          'entity': b.param, 'opcode': b.packet_id,
                          'raw-payload-hex': b.payload.hex()}
                counts[str(b.packet_id)] += 1
                try:
                    row = {**common, **decoder.buff(b.packet_id, b.payload)}
                    ledger.apply(row)
                    handle.write(json.dumps(row, allow_nan=False) + '\n')
                except (ValueError, RuntimeError, UcError) as error:
                    failures[str(error)] += 1
                    rejected.append({**common, 'reason': str(error)})
                    ledger.invalidate(b.param, event_id, 'decode-rejected')
    report = {'format': 'powerspike-replay-buffs', 'version': 1,
              'client-build': BUILD, 'protocol-digest': PROTOCOL,
              'replay-sha256': digest(replay_path), 'image-sha256': digest(image),
              'profile-sha256': digest(profile_path),
              'adapters': {name: digest(Path(__file__).with_name(name)) for name in
                           ('replay_buffs.py', 'replay_native.py', 'replay_framing.py')},
              'counts': dict(counts), 'lifecycle': dict(ledger.counts),
              'archives': {'buffs.jsonl.gz': digest(output / 'buffs.jsonl.gz')},
              'failures': dict(failures), 'rejected': rejected,
              'complete-buff-state': False,
              'scope': 'Observed add/remove/counter associations only; no global buff absence, type or behavior inferred',
              'cost': {'wall-seconds': time.monotonic() - started}}
    (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('replay', 'image', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--profile', type=Path, default=Path(__file__).resolve().parents[1] /
                        'observations/replays/16.20.824.8524-native-profile.json')
    parser.add_argument('--champion-start', type=lambda s: int(s, 0), required=True)
    args = parser.parse_args()
    report = decode(args.replay, args.image, args.profile, args.output, args.champion_start)
    print(json.dumps({key: report[key] for key in ('counts', 'lifecycle', 'failures', 'cost')}))
    return bool(report['failures'])


if __name__ == '__main__':
    raise SystemExit(main())

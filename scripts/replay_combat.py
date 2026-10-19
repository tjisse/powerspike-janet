"""Decode exact-build damage and partial last-observed state to private JSONL.

API files are optional independent validation inputs, never decoder inputs.
This tool deliberately admits zero model comparisons until attribution and all
required pre-hit conditions are supported. No credentials or network are used.
"""
import argparse
import bisect
from collections import Counter, defaultdict
import gzip
import importlib.metadata
import json
import math
from pathlib import Path
import struct
import time

from replay_framing import iter_blocks
from replay_native import NativeDecoder, BUILD, PROTOCOL
from replay_recovery import bind_api, champion_start, digest, load
from replay_state import ObservedState, NAMED_FIELDS, replication_records


def add_damage_total(total, amount):
    """Match the exact client's binary32 numeric-stat addition (ADDSS).

    Round the operands and every sum to binary32, not just the final total.
    The wider intermediate preserves the binary32 rounding decision here.
    This does not change individual decoded damage or the API tolerance.
    """
    if (type(total) not in (int, float) or type(amount) not in (int, float)
            or not math.isfinite(total) or not math.isfinite(amount)
            or total < 0 or amount < 0):
        raise ValueError('Damage accumulation requires finite nonnegative scalars')
    try:
        left = struct.unpack('<f', struct.pack('<f', total))[0]
        right = struct.unpack('<f', struct.pack('<f', amount))[0]
        result = struct.unpack('<f', struct.pack('<f', left + right))[0]
    except (OverflowError, struct.error) as error:
        raise ValueError('Damage accumulation exceeds binary32 range') from error
    if not math.isfinite(result):
        raise ValueError('Damage accumulation exceeds binary32 range')
    return result


def totals_check(totals, roster, start, slots, match):
    rows = []
    participants = {p['participantId']: p for p in match['info']['participants']}
    for player in roster:
        entity = start + player['slot']
        truth = participants[slots[player['slot']]]
        for metric, api in [('incoming', 'totalDamageTaken'),
                            ('outgoing-champions', 'totalDamageDealtToChampions'),
                            ('physical', 'physicalDamageTaken'),
                            ('magic', 'magicDamageTaken'), ('true', 'trueDamageTaken')]:
            observed = totals[entity][metric]
            error = observed - truth[api]
            rows.append({'slot': player['slot'], 'metric': metric,
                         'decoded': observed, 'api': truth[api], 'difference': error,
                         'within-one': abs(error) < 1})
    return {'checks': len(rows), 'within-one': sum(r['within-one'] for r in rows),
            'max-absolute-error': max(abs(r['difference']) for r in rows), 'rows': rows,
            'scope': 'Aggregate decoder checks; not independently labelled individual hits or model checks'}


def snapshots_check(history, slots, start, timeline):
    fields = {'health': 'health', 'health-max': 'healthMax',
              'armor': 'armor', 'magic-resist': 'magicResist'}
    rows, counts = [], {name: Counter() for name in fields}
    reverse = {participant: start + slot for slot, participant in slots.items()}
    for frame in timeline['info']['frames']:
        timestamp = frame['timestamp'] / 1000
        for participant, player in frame['participantFrames'].items():
            entity = reverse[int(participant)]
            for name, api in fields.items():
                samples = history.get((entity, name), [])
                # Equal timestamps include state updates at that replay time;
                # no interpolation or nearest-future sample is permitted.
                i = bisect.bisect_right(samples, (timestamp, float('inf'), float('inf'))) - 1
                counts[name]['checks'] += 1
                if i < 0:
                    counts[name]['missing'] += 1
                    continue
                t, order, value = samples[i]
                if value is None:
                    counts[name]['missing'] += 1
                    continue
                expected = player['championStats'][api]
                difference = value - expected
                good = abs(difference) < 1
                counts[name]['within-one'] += good
                counts[name]['different'] += not good
                rows.append({'timestamp': timestamp, 'participant-slot':
                             next(s for s, p in slots.items() if p == int(participant)),
                             'field': name, 'decoded': value, 'api': expected,
                             'difference': difference, 'sample-timestamp': t,
                             'age-seconds': timestamp - t})
    return {'fields': {k: dict(v) for k, v in counts.items()}, 'rows': rows,
            'scope': 'Last-observed replay values versus periodic API snapshots; differences retained, not corrected'}


def decode(replay_path, image_path, profile_path, output, match_path=None, timeline_path=None):
    from rofllens import ReplayReader
    from unicorn import UcError
    if (match_path is None) != (timeline_path is None):
        raise ValueError('Supply both match and timeline, or neither')
    output = Path(output)
    if output.exists():
        raise ValueError('Output directory already exists; choose a fresh evidence directory')
    started = time.monotonic()
    profile = load(profile_path)
    decoder = NativeDecoder(image_path, profile)
    entities, history = {}, defaultdict(list)
    counts, failures = Counter(), Counter()
    rejected = []
    totals = defaultdict(Counter)
    state = ObservedState()
    ages = []
    with ReplayReader.open(replay_path) as replay:
        if replay.header.client_version != BUILD or replay.header.protocol_digest != PROTOCOL:
            raise ValueError('Replay exact build/protocol differs from native decoder')
        duration = replay.metadata.game_length / 1000
        metadata = replay.metadata.participants
        roster = [{'slot': i, 'champion': p['SKIN'], 'team': int(p['TEAM'])}
                  for i, p in enumerate(metadata)]
        if len(roster) != 10 or len({(p['champion'], p['team']) for p in roster}) != 10:
            raise ValueError('Combat adapter currently requires ten distinct champion/team pairs')
        for b in iter_blocks(replay, streams={'gameChunk'}):
            counts['gameplay-blocks'] += 1
            if b.param >= 0x40000000:
                e = entities.setdefault(b.param, {'first': b.timestamp, 'last': b.timestamp, 'opcodes': set()})
                e['first'] = min(e['first'], b.timestamp)
                e['last'] = max(e['last'], b.timestamp)
                e['opcodes'].add(b.packet_id)
        start, candidates = champion_start(entities, 10, duration)
        champions = set(range(start, start + 10))
        output.mkdir(parents=True)
        previous = -1.
        with gzip.open(output / 'damage.jsonl.gz', 'wt') as damages, \
                gzip.open(output / 'state.jsonl.gz', 'wt') as updates:
            for order, b in enumerate(iter_blocks(replay, streams={'gameChunk'},
                                                  opcodes={150, 287}, include_payload=True)):
                if b.timestamp < previous:
                    raise ValueError('Non-monotonic packet time; causal ordering unresolved')
                previous = b.timestamp
                kind = 'damage' if b.packet_id == 150 else 'state'
                counts[kind + '-packets'] += 1
                event_id = f'{b.stream}:{b.chunk_id}:{b.block_offset}'
                common = {'event-id': event_id, 'timestamp': b.timestamp, 'order': order,
                          'opcode': b.packet_id, 'raw-payload-hex': b.payload.hex()}
                try:
                    if kind == 'state':
                        buf = decoder.state_buffer(b.payload)
                        records = replication_records(buf, champions)
                        counts['state-records'] += len(records)
                        players = [r for r in records if r['entity'] in champions]
                        state.apply(players, b.timestamp, order, event_id)
                        for r in players:
                            for name, value in r['fields'].items():
                                history[r['entity'], name].append((b.timestamp, order, value))
                        counts['champion-state-records'] += len(players)
                        row = {**common, 'decoded-buffer-hex': buf.hex(), 'champions': players}
                    else:
                        row = {**common, **decoder.damage(b.payload, b.param)}
                        for role in ('source', 'target'):
                            row[role + '-last-observed'] = state.before(row[role], b.timestamp, order)
                        row['model-admissible'] = False
                        amount = row['amount']
                        if row['target'] in champions:
                            totals[row['target']]['incoming'] = add_damage_total(totals[row['target']]['incoming'], amount)
                            if row['damage-type']:
                                totals[row['target']][row['damage-type']] = add_damage_total(totals[row['target']][row['damage-type']], amount)
                            counts['champion-target-damage'] += 1
                            snapshot = row['target-last-observed']
                            counts['champion-target-with-all-partial-fields'] += all(n in snapshot for n in NAMED_FIELDS)
                            if 'health' in snapshot:
                                ages.append(snapshot['health']['age-seconds'])
                        if row['source'] in champions and row['target'] in champions:
                            totals[row['source']]['outgoing-champions'] = add_damage_total(totals[row['source']]['outgoing-champions'], amount)
                        counts['unknown-damage-type'] += row['damage-type'] is None
                    counts[kind + '-accepted'] += 1
                    handle = damages if kind == 'damage' else updates
                    handle.write(json.dumps(row, separators=(',', ':'), allow_nan=False) + '\n')
                except (ValueError, RuntimeError, UcError) as error:
                    reason = str(error)
                    failures[kind + ': ' + reason] += 1
                    rejected.append({**common, 'reason': reason})
                    if kind == 'state':
                        state.invalidate()
                        for entity in champions:
                            for name in NAMED_FIELDS:
                                history[entity, name].append((b.timestamp, order, None))
        stats = {(p['SKIN'], int(p['TEAM'])): tuple(int(p[k]) for k in
                 ('CHAMPIONS_KILLED', 'NUM_DEATHS', 'ASSISTS')) for p in metadata}
    ages.sort()
    report = {'format': 'powerspike-replay-combat', 'version': 1,
              'client-build': BUILD, 'protocol-digest': PROTOCOL,
              'replay-sha256': digest(replay_path), 'image-sha256': digest(image_path),
              'profile-sha256': digest(profile_path),
              'damage-accumulation': {'policy': 'ordered-binary32-v1',
                                      'order': 'original gameplay wire order, independently per metric',
                                      'rounding': 'IEEE binary32 after every addition',
                                      'api-comparison': 'unchanged strict absolute difference < 1'},
              'adapters': {name: digest(Path(__file__).with_name(name)) for name in
                           ('replay_combat.py', 'replay_native.py', 'replay_state.py', 'replay_framing.py', 'replay_recovery.py')},
              'dependencies': {name: importlib.metadata.version(name) for name in ('rofllens', 'unicorn')},
              'duration-seconds': duration, 'roster': roster,
              'champion-entity-start': start, 'counts': dict(counts),
              'failures': dict(failures), 'rejected': rejected,
              'health-observation-age-seconds': {str(q): ages[min(len(ages) - 1, int(q * len(ages)))]
                                                if ages else None for q in (.5, .9, .99, 1.)},
              'coverage': {'model-comparisons': 0, 'exact-pre-hit-states': 0,
                           'fields': list(NAMED_FIELDS), 'shield-semantics': 'candidate, not API-verified',
                           'missing': ['complete inventories', 'buffs/debuffs', 'ability ranks',
                                       'cast-to-damage attribution', 'full offensive stats', 'exact hit-time health/shields']},
              'cost': {'wall-seconds': time.monotonic() - started,
                       'output-bytes': sum(p.stat().st_size for p in output.iterdir())}}
    if match_path is not None:
        match, timeline = load(match_path), load(timeline_path)
        slots = bind_api({**report, 'events': []}, stats, match, timeline)
        report['validation'] = {'match-sha256': digest(match_path),
                                'timeline-sha256': digest(timeline_path),
                                'damage-totals': totals_check(totals, roster, start, slots, match),
                                'state-snapshots': snapshots_check(history, slots, start, timeline)}
    (output / 'summary.json').write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('replay', 'image', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--profile', type=Path, default=Path(__file__).resolve().parents[1] /
                        'observations/replays/16.20.824.8524-native-profile.json')
    parser.add_argument('--match', type=Path)
    parser.add_argument('--timeline', type=Path)
    args = parser.parse_args()
    if bool(args.match) != bool(args.timeline):
        parser.error('Supply both --match and --timeline, or neither')
    report = decode(args.replay, args.image, args.profile, args.output,
                    args.match, args.timeline)
    print(json.dumps({'counts': report['counts'], 'failures': report['failures'], 'cost': report['cost']}))
    return 1 if report['failures'] or ('validation' in report and
               report['validation']['damage-totals']['within-one'] != 50) else 0


if __name__ == '__main__':
    raise SystemExit(main())

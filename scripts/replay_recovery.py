"""Recover exact-build death/skill events offline; optionally check a Riot timeline.

No API credentials, game executable or emulator are used. Timeline data is only
read by validation, after replay events have been recovered using a frozen
profile. This research adapter does not admit damage-model comparisons.
"""
import argparse
from collections import Counter
import hashlib
import importlib.metadata
import json
from pathlib import Path
import time

from replay_framing import iter_blocks


def digest(path):
    with Path(path).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def load(path):
    return json.loads(Path(path).read_text())


def champion_start(entities, count, duration):
    candidates = []
    for start in sorted(entities):
        run = [entities.get(i) for i in range(start, start + count)]
        if all(e is not None and e['first'] <= 90 and e['last'] >= duration - 90 for e in run):
            candidates.append((sum(len(e['opcodes']) for e in run), start))
    candidates.sort(reverse=True)
    if not candidates or len(candidates) > 1 and candidates[0][0] == candidates[1][0]:
        raise ValueError('Champion entity run is absent or ambiguous')
    return candidates[0][1], candidates


def recover(path, profile):
    from rofllens import ReplayReader
    if profile.get('format') != 'powerspike-replay-recovery-profile' or profile.get('version') != 1:
        raise ValueError('Unsupported recovery profile')
    entities, packets = {}, []
    kinds = {config['opcode']: kind for kind, config in profile['events'].items()}
    if len(kinds) != len(profile['events']) or set(kinds.values()) - {'champion-death', 'skill-upgrade'}:
        raise ValueError('Unsupported or ambiguous event configuration')
    started = time.monotonic()
    with ReplayReader.open(path) as replay:
        if replay.header.client_version != profile['client-build'] or replay.header.protocol_digest != profile['protocol-digest']:
            raise ValueError('Exact replay build/protocol does not match the frozen profile')
        duration = replay.metadata.game_length / 1000
        metadata = replay.metadata.participants
        roster = [{'slot': i, 'champion': p['SKIN'], 'team': int(p['TEAM'])}
                  for i, p in enumerate(metadata)]
        if len(roster) != 10 or len({(p['champion'], p['team']) for p in roster}) != 10:
            raise ValueError('Recovery currently requires ten distinct champion/team pairs')
        total = 0
        for b in iter_blocks(replay, streams={'gameChunk'}, include_payload=True):
            total += 1
            if b.param >= 0x40000000:
                e = entities.setdefault(b.param, {'first': b.timestamp, 'last': b.timestamp, 'opcodes': set()})
                e['last'] = max(e['last'], b.timestamp)
                e['first'] = min(e['first'], b.timestamp)
                e['opcodes'].add(b.packet_id)
            if b.packet_id in kinds:
                packets.append(b)
        start, candidates = champion_start(entities, len(roster), duration)
        events, rejected = [], []
        for b in packets:
            event_id = f'{b.stream}:{b.chunk_id}:{b.block_offset}'
            slot = b.param - start
            if not 0 <= slot < len(roster):
                rejected.append({'event-id': event_id, 'reason': 'subject-outside-champion-run'})
                continue
            kind = kinds[b.packet_id]
            event = {'event-id': event_id, 'kind': kind, 'timestamp': b.timestamp,
                     'subject-slot': slot, 'subject-entity-id': b.param,
                     'raw-payload-hex': b.payload.hex()}
            if kind == 'champion-death':
                event['victim-slot'] = slot
            else:
                fields = profile['events'][kind]['payload-codebook'].get(b.payload.hex())
                event['decode-status'] = 'known-payload' if fields is not None else 'unknown-payload'
                if fields is not None:
                    event.update(fields)
            events.append(event)
        report = {
            'format': 'powerspike-replay-recovery', 'version': 1,
            'replay-sha256': digest(path), 'client-build': replay.header.client_version,
            'protocol-digest': replay.header.protocol_digest, 'duration-seconds': duration,
            'framing-adapter-sha256': digest(Path(__file__).with_name('replay_framing.py')),
            'recovery-adapter-sha256': digest(__file__),
            'rofllens-version': importlib.metadata.version('rofllens'),
            'roster': roster, 'champion-entity-start': start,
            'champion-run-candidates': [{'score': score, 'start': base} for score, base in candidates],
            'gameplay-blocks': total, 'events': events, 'rejected-events': rejected,
            'coverage': {'recovered-death-events': sum(e['kind'] == 'champion-death' for e in events),
                         'recovered-skill-upgrade-packets': sum(e['kind'] == 'skill-upgrade' for e in events),
                         'skill-upgrades-with-labels': sum(e.get('decode-status') == 'known-payload' for e in events),
                         'skill-upgrades-without-labels': sum(e.get('decode-status') == 'unknown-payload' for e in events),
                         'verified-damage-events': 0,
                         'model-comparisons': 0},
            'cost': {'recovery-wall-seconds': time.monotonic() - started},
        }
        # Keep private identity-bearing metadata out of the recovery report.
        expected_stats = {(p['SKIN'], int(p['TEAM'])):
                          tuple(int(p[k]) for k in ('CHAMPIONS_KILLED', 'NUM_DEATHS', 'ASSISTS'))
                          for p in metadata}
    return report, expected_stats


def match_deaths(events, truth, tolerance, label_fields=()):
    """Require unique one-to-one matches; do not merge duplicates or hide extras."""
    if not 0 < tolerance <= .1:
        raise ValueError('Invalid death validation tolerance')
    remaining = set(range(len(truth)))
    matched, extra, ambiguous = [], [], []
    for event in sorted(events, key=lambda e: e['timestamp']):
        found = [i for i in remaining
                 if truth[i]['victimId'] == event['victimId']
                 and abs(truth[i]['timestamp'] / 1000 - event['timestamp']) <= tolerance
                 and all(truth[i][key] == event[key] for key in label_fields)]
        if len(found) == 1:
            i = found[0]
            remaining.remove(i)
            matched.append(abs(truth[i]['timestamp'] / 1000 - event['timestamp']))
        elif found:
            ambiguous.append(event['event-id'])
        else:
            extra.append(event['event-id'])
    return {'expected': len(truth), 'recovered': len(events), 'matched': len(matched),
            'unexpected': len(extra), 'missing': len(remaining), 'ambiguous': len(ambiguous),
            'max-timestamp-error-seconds': max(matched, default=None),
            'tolerance-seconds': tolerance,
            'passed': not extra and not remaining and not ambiguous and len(matched) > 0}


def bind_api(report, expected_stats, match, timeline):
    """Bind independent API labels only after replay recovery has completed."""
    if match['metadata']['matchId'] != timeline['metadata']['matchId']:
        raise ValueError('Match and timeline identities differ')
    info = match['info']
    if info['gameVersion'] != report['client-build'] or abs(info['gameDuration'] - report['duration-seconds']) >= 3:
        raise ValueError('Match build/duration differs from replay')
    participants = info['participants']
    api_stats = {(p['championName'], p['teamId']): (p['kills'], p['deaths'], p['assists'])
                 for p in participants}
    if api_stats != expected_stats or len(participants) != 10:
        raise ValueError('Match champion/team/KDA roster differs from replay')
    if set(timeline['metadata']['participants']) != {p['puuid'] for p in participants}:
        raise ValueError('Timeline participant identities differ from match')
    by_champion = {(p['championName'], p['teamId']): p['participantId'] for p in participants}
    slots = {p['slot']: by_champion[(p['champion'], p['team'])] for p in report['roster']}
    return slots


def validate(report, expected_stats, match, timeline, tolerance):
    slots = bind_api(report, expected_stats, match, timeline)
    # This maps metadata labels into API labels for comparison only. Neither
    # packet discovery nor replay event recovery reads the timeline or match.
    observed = [{**e, 'victimId': slots[e['victim-slot']]} for e in report['events']
                if e['kind'] == 'champion-death']
    all_events = [e for f in timeline['info']['frames'] for e in f['events']]
    deaths = [e for e in all_events if e['type'] == 'CHAMPION_KILL']
    result = match_deaths(observed, deaths, tolerance)
    result['scope'] = 'Death timestamp and victim only; killer, assists, damage, and combat model unchecked'
    result['match-roster-build-duration-checked'] = True
    result['timeline-event-counts'] = dict(Counter(e['type'] for e in all_events))
    result['timeline-stat-snapshots'] = sum(len(f['participantFrames']) for f in timeline['info']['frames'])
    result['timeline-death-recap-damage-rows'] = sum(len(e.get('victimDamageReceived', [])) + len(e.get('victimDamageDealt', [])) for e in deaths)
    upgrades = [e for e in report['events'] if e['kind'] == 'skill-upgrade']
    if upgrades:
        known = [{**e, 'victimId': slots[e['subject-slot']], 'skillSlot': e['skill-slot'],
                  'levelUpType': e['level-up-type']} for e in upgrades if e['decode-status'] == 'known-payload']
        truth = [{**e, 'victimId': e['participantId']} for e in all_events if e['type'] == 'SKILL_LEVEL_UP']
        skills = match_deaths(known, truth, tolerance, ('skillSlot', 'levelUpType'))
        skills['recovered-packets'] = len(upgrades)
        skills['unknown-payloads'] = len(upgrades) - len(known)
        skills['complete'] = skills['passed']
        skills['known-predictions-consistent'] = skills['unexpected'] == 0 and skills['ambiguous'] == 0 and skills['matched'] > 0
        skills['scope'] = 'Timestamp, actor, skill slot and upgrade type for known whole-payload patterns only; no rank or cast decoding'
        result['skill-upgrades'] = skills
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replay', type=Path, required=True)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--match', type=Path)
    parser.add_argument('--timeline', type=Path)
    args = parser.parse_args()
    if bool(args.match) != bool(args.timeline):
        parser.error('--match and --timeline must be supplied together')
    profile = load(args.profile)
    report, stats = recover(args.replay, profile)
    report['profile-sha256'] = digest(args.profile)
    report['role'] = ('discovery' if report['replay-sha256'] == profile['discovery-replay-sha256'] else 'held-out')
    if args.match:
        report['validation'] = validate(report, stats, load(args.match), load(args.timeline),
                                        profile['validation-tolerance-seconds'])
        report['match-sha256'] = digest(args.match)
        report['timeline-sha256'] = digest(args.timeline)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    print(json.dumps({k: report[k] for k in ('role', 'coverage', 'cost')}
                     | {'validation': report.get('validation')}))
    validation = report.get('validation', {})
    return 1 if (validation.get('passed') is False or report['rejected-events']
                 or validation.get('skill-upgrades', {}).get('known-predictions-consistent') is False) else 0


if __name__ == '__main__':
    raise SystemExit(main())

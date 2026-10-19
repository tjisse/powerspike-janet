"""Archive-bound attack/buff timing diagnostics, never server-timing admission.

All causal announcements remain candidates. No nearest match, damage amount,
model prediction, inferred expiry or fitted timing parameter selects a row.
"""
import argparse
from collections import Counter, defaultdict
import gzip
import json
import math
from pathlib import Path

from replay_actions import candidates
from replay_attack_review import archive
from replay_buffs import wire_key
from replay_native import BUILD, PROTOCOL, IMAGE_SHA256
from replay_recovery import digest, load

ROOT = Path(__file__).resolve().parents[1]


def brief(row):
    return {k: row[k] for k in ('event-id', 'timestamp', 'kind', 'source', 'target',
                               'entity', 'effect-hash', 'name-hash', 'slot-token') if k in row}


def context(hit, actions, buffs, window=2):
    found = candidates(hit, actions, window)
    updates = [r for r in buffs if r['entity'] == hit['source']
               and abs(r['timestamp'] - hit['timestamp']) <= window]
    return {'damage': brief(hit), 'action-candidates': [brief(r) for r in found],
            'status': 'unique-candidate' if len(found) == 1 else 'ambiguous' if found else 'no-candidate',
            'announcement-to-damage-seconds': [hit['timestamp'] - r['timestamp'] for r in found],
            'buff-updates': [{**brief(r), 'offset-from-damage-seconds': r['timestamp'] - hit['timestamp'],
                              'wire-position': 'before' if wire_key(r['event-id']) < wire_key(hit['event-id']) else 'after'}
                             for r in updates],
            'server-timing-resolved': False, 'model-admissible': False}


def removals_context(buffs, damage, actions, effects, window=2):
    """Audit every explicit removal, including those with no selected damage."""
    active, rows = {}, []
    for buff in buffs:
        token = buff['slot-token']
        if buff['kind'] == 'add':
            active[token] = buff
        elif buff['kind'] == 'remove':
            added = active.pop(token, None)
            hits = [r for r in damage if r['source'] == buff['entity']
                    and r['effect-hash'] in effects and r['timestamp'] == buff['timestamp']]
            announcements = [r for r in actions if r['source'] == buff['entity']
                             and wire_key(r['event-id']) < wire_key(buff['event-id'])
                             and 0 <= buff['timestamp'] - r['timestamp'] <= window]
            rows.append({'removal': brief(buff), 'matching-observed-add': brief(added) if added else None,
                         'observed-lifetime-seconds': buff['timestamp'] - added['timestamp'] if added else None,
                         'same-timestamp-damage-candidates': [brief(r) for r in hits],
                         'preceding-announcements': [brief(r) for r in announcements],
                         'consumption-or-expiry-resolved': False})
    return rows


def checked_archive(folder, name, report):
    expected = report.get('archives', {}).get(name)
    if not expected or digest(folder / name) != expected:
        raise ValueError('Archive receipt mismatch')
    return list(archive(folder / name))


def review(actions_dir, buffs_dir, combat_dir, entity, effects, buff_hash, output,
           expected_damage, window=2):
    if not math.isfinite(window) or not 0 < window <= 10:
        raise ValueError('Invalid candidate search window')
    if (type(entity) is not int or type(buff_hash) is not int or not effects
            or any(type(h) is not int or not 0 <= h <= 0xffffffff for h in [entity, buff_hash, *effects])):
        raise ValueError('Require explicit entity, effect and buff hashes')
    actions_dir, buffs_dir, combat_dir, output = map(Path, (actions_dir, buffs_dir, combat_dir, output))
    if output.exists():
        raise ValueError('Choose a fresh timing dossier directory')
    folders = {'actions': actions_dir, 'buffs': buffs_dir, 'combat': combat_dir}
    reports = {k: load(p / 'summary.json') for k, p in folders.items()}
    formats = {'actions': 'powerspike-replay-actions', 'buffs': 'powerspike-replay-buffs',
               'combat': 'powerspike-replay-combat'}
    required = {'actions': {'replay_actions.py', 'replay_native.py', 'replay_framing.py'},
                'buffs': {'replay_buffs.py', 'replay_native.py', 'replay_framing.py'},
                'combat': {'replay_combat.py', 'replay_native.py', 'replay_state.py',
                           'replay_framing.py', 'replay_recovery.py'}}
    for key, report in reports.items():
        if (report.get('format') != formats[key] or report.get('version') != 1
                or report.get('client-build') != BUILD or report.get('protocol-digest') != PROTOCOL
                or report.get('image-sha256') != IMAGE_SHA256 or report.get('failures')
                or not required[key].issubset(report.get('adapters', {}))):
            raise ValueError('Unsupported or incomplete native extraction')
        for name, expected in report['adapters'].items():
            if Path(name).name != name or digest(ROOT / 'scripts' / name) != expected:
                raise ValueError('Extraction adapter changed')
    for field in ('replay-sha256', 'profile-sha256'):
        if len({r[field] for r in reports.values()}) != 1:
            raise ValueError('Mixed replay or profile identities')
    if reports['actions']['champion-entity-start'] != reports['combat']['champion-entity-start']:
        raise ValueError('Action and combat rosters disagree')
    start = reports['combat']['champion-entity-start']
    if not start <= entity < start + len(reports['combat']['roster']):
        raise ValueError('Entity is outside the bound roster')
    actions = checked_archive(actions_dir, 'actions.jsonl.gz', reports['actions'])
    buffs = checked_archive(buffs_dir, 'buffs.jsonl.gz', reports['buffs'])
    damage_path = combat_dir / 'damage.jsonl.gz'
    if digest(damage_path) != expected_damage:
        raise ValueError('Damage archive differs from explicit SHA-256')
    damage = list(archive(damage_path))
    for rows in (actions, buffs, damage):
        if any(type(r['timestamp']) not in (int, float) or not math.isfinite(r['timestamp'])
               or r['timestamp'] < 0 for r in rows):
            raise ValueError('Invalid packet timestamp')
    for key, rows in [('actions', actions), ('buffs', buffs)]:
        if dict(Counter(str(r['opcode']) for r in rows)) != reports[key]['counts']:
            raise ValueError('Packet counts differ from extraction receipt')
    if len(damage) != reports['combat']['counts']['damage-accepted']:
        raise ValueError('Damage count differs from extraction receipt')
    actions = [r for r in actions if r['source'] == entity]
    buffs = [r for r in buffs if r['entity'] == entity and r['name-hash'] == buff_hash]
    selected = [r for r in damage if r['source'] == entity and r['effect-hash'] in effects]
    rows = [context(hit, actions, buffs, window) for hit in selected]
    counts, intervals = defaultdict(Counter), defaultdict(list)
    for row in rows:
        h = str(row['damage']['effect-hash'])
        counts[h]['selected-damage-packets'] += 1
        counts[h][row['status']] += 1
        removes = [r for r in row['buff-updates'] if r['kind'] == 'remove']
        counts[h]['with-same-timestamp-removal'] += any(r['offset-from-damage-seconds'] == 0 for r in removes)
        if row['status'] == 'unique-candidate':
            intervals[h].extend(row['announcement-to-damage-seconds'])
    removals = removals_context(buffs, damage, actions, effects, window)
    output.mkdir(parents=True)
    with gzip.open(output / 'timing.jsonl.gz', 'wt') as handle:
        for row in rows:
            handle.write(json.dumps(row, allow_nan=False) + '\n')
    with gzip.open(output / 'removals.jsonl.gz', 'wt') as handle:
        for row in removals:
            handle.write(json.dumps(row, allow_nan=False) + '\n')
    report = {'format': 'powerspike-replay-timing-context', 'version': 1,
              'client-build': BUILD, 'protocol-digest': PROTOCOL,
              'replay-sha256': reports['combat']['replay-sha256'],
              'entity': entity, 'effect-hashes': sorted(effects), 'buff-hash': buff_hash,
              'candidate-window-seconds': window,
              'counts-by-effect-hash': {h: dict(c) for h, c in counts.items()},
              'unique-announcement-intervals': {h: {'count': len(v), 'minimum': min(v), 'maximum': max(v)}
                                                for h, v in intervals.items()},
              'selected-buff-update-counts': dict(Counter(r['kind'] for r in buffs)),
              'removal-context': {'removals': len(removals),
                                  'with-matching-observed-add': sum(r['matching-observed-add'] is not None for r in removals),
                                  'with-same-timestamp-damage': sum(bool(r['same-timestamp-damage-candidates']) for r in removals),
                                  'without-same-timestamp-damage': sum(not r['same-timestamp-damage-candidates'] for r in removals)},
              'global-buff-lifecycle-diagnostics': reports['buffs']['lifecycle'],
              'inputs': {k: digest(p / 'summary.json') for k, p in folders.items()},
              'damage-archive-sha256': expected_damage,
              'adapters': {name: digest(ROOT / 'scripts' / name) for name in
                           ('replay_timing.py', 'replay_actions.py', 'replay_attack_review.py', 'replay_buffs.py')},
              'archives': {name: digest(output / name) for name in ('timing.jsonl.gz', 'removals.jsonl.gz')},
              'model-admissible-cases': 0, 'server-timing-resolved': False,
              'scope': 'Packet-time context only. Hash labels, release/launch meaning, cancellation, replication lag, '
                       'distance, server sampling and complete buff state remain unverified. No damage amounts or '
                       'predictions select matches; every causal candidate and nearby buff update is retained.'}
    (output / 'summary.json').write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('actions', 'buffs', 'combat', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ('entity', 'buff'):
        parser.add_argument('--' + name, type=lambda x: int(x, 0), required=True)
    parser.add_argument('--effects', type=lambda x: int(x, 0), nargs='+', required=True)
    parser.add_argument('--damage-sha256', required=True)
    parser.add_argument('--window', type=float, default=2)
    args = parser.parse_args()
    report = review(args.actions, args.buffs, args.combat, args.entity, set(args.effects),
                    args.buff, args.output, args.damage_sha256, args.window)
    print(json.dumps({k: report[k] for k in ('counts-by-effect-hash', 'unique-announcement-intervals',
                                           'selected-buff-update-counts', 'model-admissible-cases')}))

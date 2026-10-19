"""Bind action candidates to retained attacks and audit observed stat continuity.

This is an evidence dossier, not automatic semantic review or model admission.
No damage prediction or prediction error is used to select an action.
"""
import argparse
import bisect
from collections import Counter, defaultdict
import gzip
import json
import math
from pathlib import Path
import time

from replay_actions import candidates
from replay_buffs import wire_key
from replay_native import BUILD, PROTOCOL
from replay_recovery import digest, load
from replay_state import AD_INPUTS, replication_records

ROOT = Path(__file__).resolve().parents[1]
DEPENDENCIES = {'source': (*AD_INPUTS, 'crit-chance', 'flat-armor-penetration',
                           'armor-remaining-fraction', 'physical-lethality',
                           'bonus-armor-remaining-fraction'), 'target': ('armor',)}


def archive(path):
    previous = None
    with gzip.open(path, 'rt') as handle:
        for line in handle:
            row = json.loads(line)
            key = wire_key(row['event-id'])
            if previous is not None and key <= previous:
                raise ValueError('Archive is not in unique gameplay wire order')
            previous = key
            yield row


def continuity(case, action, history):
    start, end = wire_key(action['event-id']), wire_key(case['event-id'])
    if start >= end:
        raise ValueError('Action must precede damage in wire order')
    result = []
    for role, fields in DEPENDENCIES.items():
        for field in fields:
            samples = history.get((case[role], field), [])
            keys = [row['wire-key'] for row in samples]
            before = bisect.bisect_right(keys, start) - 1
            after = bisect.bisect_left(keys, end)
            initial = samples[before] if before >= 0 else None
            updates = samples[before + 1:after]
            previous = initial
            changes = []
            for sample in updates:
                if previous is None or previous['value'] != sample['value']:
                    changes.append(sample)
                previous = sample
            result.append({'role': role, 'field': field, 'before-action': initial,
                           'updates-before-damage': updates, 'value-changes': changes,
                           'observed-stable': initial is not None and not changes})
    return {'fields': result, 'complete-observed-inputs': all(r['before-action'] is not None for r in result),
            'observed-stable': all(r['observed-stable'] for r in result),
            'server-sampling-resolved': False,
            'scope': 'Continuity of decoded client observations between announcement and damage; not proof of unchanged server inputs or a server sampling instant.'}


def review(actions_dir, audit_dir, combat_dir, output, window=2):
    started = time.monotonic()
    actions_dir, audit_dir, combat_dir, output = map(Path, (actions_dir, audit_dir, combat_dir, output))
    if output.exists():
        raise ValueError('Choose a fresh review dossier directory')
    if not math.isfinite(window) or not 0 < window <= 10:
        raise ValueError('Invalid candidate search window')
    actions_summary, gap, combat = [load(p / 'summary.json') for p in (actions_dir, audit_dir, combat_dir)]
    for report in (actions_summary, gap, combat):
        if report.get('client-build') != BUILD or report.get('protocol-digest') != PROTOCOL:
            raise ValueError('Unsupported build/protocol')
    if len({r['replay-sha256'] for r in (actions_summary, gap, combat)}) != 1:
        raise ValueError('Action, case and state archives belong to different replays')
    if (combat.get('failures') or actions_summary['image-sha256'] != combat['image-sha256']
            or actions_summary['champion-entity-start'] != combat['champion-entity-start']):
        raise ValueError('Incomplete state extraction or mismatched native inputs/roster')
    receipts = [(actions_dir, actions_summary['archives']), (audit_dir, gap['evidence-files']),
                (combat_dir, gap['source-files'])]
    for folder, files in receipts:
        for name, expected in files.items():
            if Path(name).name != name or digest(folder / name) != expected:
                raise ValueError('Archive receipt mismatch')
    actions = list(archive(actions_dir / 'actions.jsonl.gz'))
    accepted = Counter(str(row['opcode']) for row in actions)
    if any(accepted[op] + actions_summary['failures'].get(op, 0) != count
           for op, count in actions_summary['counts'].items()):
        raise ValueError('Action counts disagree with extraction receipt')
    cases = list(archive(audit_dir / 'cases.jsonl.gz'))
    if len(cases) != gap['counts']['champion-to-champion-events']:
        raise ValueError('Case count differs from gap audit')
    history = defaultdict(list)
    entities = {case[role] for case in cases for role in ('source', 'target')}
    for row in archive(combat_dir / 'state.jsonl.gz'):
        for record in replication_records(bytes.fromhex(row['decoded-buffer-hex']), entities):
            if record['entity'] in entities:
                for field, value in record['fields'].items():
                    history[record['entity'], field].append({'wire-key': wire_key(row['event-id']),
                        'event-id': row['event-id'], 'timestamp': row['timestamp'], 'value': value})
    selected_witness = load(audit_dir / 'candidate-witness.json') if gap.get('candidate-witness') else None
    if selected_witness and digest(audit_dir / 'candidate-witness.json') != gap['candidate-witness']['sha256']:
        raise ValueError('Original witness receipt mismatch')
    output.mkdir(parents=True)
    counts = Counter()
    witness = None
    rejected = load(actions_dir / 'rejected.json')
    with gzip.open(output / 'attack-context.jsonl.gz', 'wt') as handle:
        for case in cases:
            if case['effect-kind'] != 'basic-attack-candidate' or case['damage-type'] != 'physical':
                continue
            counts['ordinary-candidates'] += 1
            found = candidates(case, actions, window)
            row = {'event-id': case['event-id'], 'source': case['source'], 'target': case['target'],
                   'timestamp': case['timestamp'], 'action-candidates': found,
                   'status': 'no-candidate' if not found else 'unique-candidate' if len(found) == 1 else 'ambiguous',
                   'model-admissible': False, 'resolved-semantic-blockers': []}
            counts[row['status']] += 1
            if not case['data-gaps']:
                counts['numeric-ready'] += 1
                counts['numeric-ready:' + row['status']] += 1
            if len(found) == 1:
                row['announcement-to-damage-seconds'] = case['timestamp'] - found[0]['timestamp']
                row['stat-continuity'] = continuity(case, found[0], history)
                row['decode-failures-in-window'] = [r for r in rejected
                    if wire_key(found[0]['event-id']) <= wire_key(r['event-id']) < wire_key(case['event-id'])]
                counts['observed-stable'] += row['stat-continuity']['observed-stable']
                if not case['data-gaps']:
                    counts['numeric-ready:observed-stable'] += row['stat-continuity']['observed-stable']
            if selected_witness and row['event-id'] == selected_witness['case']['event-id']:
                witness = {**row, 'original-witness-sha256': digest(audit_dir / 'candidate-witness.json'),
                           'remaining-semantic-blockers': case['semantic-gaps'],
                           'health-bracket-diagnostic': {key: selected_witness[key] for key in
                               ('health-before', 'health-after', 'damage-between-health-samples', 'health-drop')}}
            handle.write(json.dumps(row, allow_nan=False) + '\n')
    if witness is not None:
        (output / 'witness.json').write_text(json.dumps(witness, indent=2) + '\n')
    report = {'format': 'powerspike-replay-attack-review', 'version': 1,
              'client-build': BUILD, 'protocol-digest': PROTOCOL,
              'replay-sha256': gap['replay-sha256'], 'counts': dict(counts),
              'action-packets-decoded': len(actions), 'action-failures': sum(actions_summary['failures'].values()),
              'candidate-search-window-seconds': window,
              'selection': 'All retained ordinary physical candidates. Fixed announcement search window; no damage magnitude, model prediction, prediction error or nearest-match selection.',
              'model-admissible-cases': 0, 'resolved-semantic-blockers': [],
              'scope': 'Unique action candidates and observed stat continuity strengthen context. They do not prove attack completion, hit/crit outcome, complete buffs, exact server sampling, shields or amount semantics.',
              'inputs': {label: digest(folder / 'summary.json') for label, folder in
                         [('actions', actions_dir), ('gap-audit', audit_dir), ('combat', combat_dir)]},
              'adapters': {name: digest(ROOT / 'scripts' / name) for name in
                           ('replay_attack_review.py', 'replay_actions.py', 'replay_state.py')},
              'evidence-files': {p.name: digest(p) for p in output.iterdir()},
              'cost': {'wall-seconds': time.monotonic() - started}}
    (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actions', type=Path, required=True)
    parser.add_argument('--audit', type=Path, required=True)
    parser.add_argument('--combat', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--window', type=float, default=2)
    args = parser.parse_args()
    result = review(args.actions, args.audit, args.combat, args.output, args.window)
    print(json.dumps({key: result[key] for key in ('counts', 'action-packets-decoded', 'model-admissible-cases', 'cost')}))

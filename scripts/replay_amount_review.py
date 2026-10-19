"""Corroborate one native damage amount against independent health observations.

This case-specific metric review uses no model prediction. It does not assign
general semantics to shielded, lethal, healing-overlap or multi-hit packets.
"""
import argparse
import json
from pathlib import Path
import time

from replay_actions import PROFILE
from replay_attack_review import archive
from replay_buffs import wire_key
from replay_first_hit_review import GAME, EVENT, health_closure
from replay_native import NativeDecoder
from replay_recovery import digest, load
from replay_state import replication_records

ROOT = Path(__file__).resolve().parents[1]
EFFECT_REVIEW = ROOT / 'observations/replays/first-hit-effect-review-2026-10-18.json'
AMOUNT_GATE = 'damage-packet-amount-semantics-incomplete'


def bracket(case, history, damage, capacities):
    if case['replay-sha256'] != GAME or case['event-id'] != EVENT or case['damage-type'] != 'physical':
        raise ValueError('Amount review is restricted to the frozen physical witness')
    hit = wire_key(EVENT)
    keys = [wire_key(r['event-id']) for r in history]
    if keys != sorted(set(keys)):
        raise ValueError('Health observations must be unique and causal')
    before = [r for r in history if wire_key(r['event-id']) < hit]
    after = [r for r in history if wire_key(r['event-id']) > hit]
    if not before or not after:
        raise ValueError('Missing independent health bracket')
    before, after = before[-1], after[0]
    capacity_keys = [wire_key(r['event-id']) for r in capacities]
    if capacity_keys != sorted(set(capacity_keys)):
        raise ValueError('Capacity observations must be unique and causal')
    initial_capacity = [r for r in capacities if wire_key(r['event-id']) <= wire_key(before['event-id'])]
    changes = [r for r in capacities if wire_key(before['event-id']) < wire_key(r['event-id'])
               <= wire_key(after['event-id']) and r['health-max'] != before['health-max']]
    if not initial_capacity or initial_capacity[-1]['health-max'] != before['health-max'] or changes:
        raise ValueError('Health capacity is missing or changed within the bracket')
    if (before['timestamp'] > case['timestamp'] or after['timestamp'] < case['timestamp']
            or before['health'] != before['health-max'] or after['health'] <= 0
            or before['health-max'] != after['health-max']
            or case['recorded-amount'] >= before['health']):
        raise ValueError('Outside reviewed full-health, nonlethal, unchanged-capacity context')
    between = [r for r in damage if r['target'] == case['target']
               and wire_key(before['event-id']) < wire_key(r['event-id']) < wire_key(after['event-id'])]
    if len(between) != 1 or any(between[0][k] != case[v] for k, v in
            (('event-id', 'event-id'), ('source', 'source'), ('effect-hash', 'effect-hash'),
             ('amount', 'recorded-amount'), ('damage-type', 'damage-type'))):
        raise ValueError('Health bracket is not isolated to the selected damage packet')
    witness = {'case': case, 'health-before': before, 'health-after': after,
               'damage-between-health-samples': between}
    closure = health_closure(witness)
    return {'status': 'corroborated-health-damage-amount-for-this-case',
            'health-before': before, 'health-after': after,
            'damage-between-health-samples': between,
            'closure': closure, 'amount-means': 'Damage delivered to target health for this isolated shield-free, nonlethal hit, within float32 measurement precision.',
            'scope': 'Independent observation metric only. Does not prove pre-mitigation amount, universal result-code meanings, shield absorption, overkill handling or a model-error tolerance.'}


def review(base, image, output):
    base, image, output = map(Path, (base, image, output))
    started = time.monotonic()
    if output.exists():
        raise ValueError('Choose a fresh amount review path')
    effect = load(EFFECT_REVIEW)
    if (effect['replay-sha256'] != GAME or effect['event-id'] != EVENT
            or effect['reviewer-adapter-sha256'] != digest(ROOT / 'scripts/replay_effect_review.py')
            or effect['model-admissible'] is not False
            or effect['shield-context-review']['status'] != 'reviewed-no-eligible-shield-source-for-this-case'
            or AMOUNT_GATE not in effect['remaining-semantic-blockers']):
        raise ValueError('Missing current shield-free review for the selected case')
    first_path = ROOT / 'observations/replays/first-hit-review-2026-10-18.json'
    if digest(first_path) != effect['inputs']['first-review']:
        raise ValueError('Original review receipt mismatch')
    witness_path = base / 'gaps-discovery-v3/candidate-witness.json'
    if digest(witness_path) != effect['inputs']['witness']:
        raise ValueError('Original witness receipt mismatch')
    case = load(witness_path)['case']
    combat_dir = base / 'combat-discovery-v2'
    gap_path = base / 'gaps-discovery-v3/summary.json'
    first = load(first_path)
    outcome_path = base / 'outcomes-discovery-v1/summary.json'
    if (digest(outcome_path) != first['inputs']['outcomes']
            or digest(gap_path) != load(outcome_path)['inputs']['audit']):
        raise ValueError('Original gap audit receipt mismatch')
    gap, combat = load(gap_path), load(combat_dir / 'summary.json')
    for name, expected in gap['source-files'].items():
        if Path(name).name != name or digest(combat_dir / name) != expected:
            raise ValueError('State/damage archive receipt mismatch')
    if (digest(image) != combat['image-sha256'] or digest(PROFILE) != combat['profile-sha256']
            or combat['replay-sha256'] != GAME or combat['failures']):
        raise ValueError('Native input mismatch or incomplete combat extraction')
    decoder = NativeDecoder(image, load(PROFILE))
    # Re-run the native reader on original payloads, then independently parse
    # health/capacity fields. Do not just copy the earlier derived bracket.
    history, capacities, last, read_count = [], [], {}, 0
    for row in archive(combat_dir / 'state.jsonl.gz'):
        data = decoder.state_buffer(bytes.fromhex(row['raw-payload-hex']))
        if data.hex() != row['decoded-buffer-hex']:
            raise ValueError('Native state differs from retained decoded bytes')
        read_count += 1
        records = replication_records(data, {case['target']})
        target_records = [r for r in records if r['entity'] == case['target']]
        if len(target_records) > 1:
            raise ValueError('Duplicate target state within one packet')
        for record in target_records:
            fields = record['fields']
            last.update(fields)
            if 'health-max' in fields:
                capacities.append({'event-id': row['event-id'], 'timestamp': row['timestamp'],
                                   'health-max': fields['health-max']})
            if 'health' in fields:
                if 'health-max' not in last:
                    raise ValueError('Health capacity not observed')
                history.append({'event-id': row['event-id'], 'timestamp': row['timestamp'],
                                'health': fields['health'], 'health-max': last['health-max']})
        if history and wire_key(history[-1]['event-id']) > wire_key(EVENT):
            break
    damage = []
    end = wire_key(history[-1]['event-id']) if history else wire_key(EVENT)
    for row in archive(combat_dir / 'damage.jsonl.gz'):
        if wire_key(row['event-id']) >= end:
            break
        native = decoder.damage(bytes.fromhex(row['raw-payload-hex']), row['target'])
        for key in ('source', 'target', 'amount', 'damage-type', 'effect-hash'):
            if native[key] != row[key]:
                raise ValueError('Native damage differs from retained observation')
        damage.append({k: row[k] for k in ('event-id', 'timestamp', 'source', 'target', 'amount', 'damage-type', 'effect-hash')})
    metric = bracket(case, history, damage, capacities)
    old = first['health-landing-corroboration']
    if metric['closure'] != old:
        raise ValueError('Independent bracket differs from the original health diagnostic')
    remaining = sorted(set(effect['remaining-semantic-blockers']) - {AMOUNT_GATE})
    report = {'format': 'powerspike-first-hit-amount-review', 'version': 1,
        'replay-sha256': GAME, 'event-id': EVENT, 'client-build': combat['client-build'],
        'amount-review': metric, 'native-state-packets-rechecked': read_count,
        'target-health-prefix': history, 'target-capacity-prefix': capacities, 'native-damage-prefix': damage,
        'resolved-semantic-blockers': [AMOUNT_GATE], 'remaining-semantic-blockers': remaining,
        'cumulative-resolved-semantic-blockers': sorted(effect['cumulative-resolved-semantic-blockers'] + [AMOUNT_GATE]),
        'model-admissible': False,
        'inputs': {'effect-review': digest(EFFECT_REVIEW), 'witness': digest(witness_path),
                   'gap-audit': digest(gap_path), 'combat': digest(combat_dir / 'summary.json'),
                   'image': digest(image), 'profile': digest(PROFILE)},
        'adapters': {name: digest(ROOT / 'scripts' / name) for name in
                     ('replay_amount_review.py', 'replay_native.py', 'replay_state.py', 'replay_first_hit_review.py')},
        'cost': {'wall-seconds': time.monotonic() - started, 'new-requests': 0, 'new-download-bytes': 0,
                 'scope': 'Final retained-payload review pass only; excludes exploratory research, development, tests and manual review.'},
        'annotation': {'reason': 'Exact-build native replay payloads rechecked: sole physical packet agrees with independently re-read health loss within a float32 measurement bound, in the already-reviewed shield-free, nonlethal case. No model prediction or model tolerance used. Active effects and server sampling remain blocked.',
                       'changes': {'blockers': remaining}}}
    output.write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('base', 'image', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    result = review(args.base, args.image, args.output)
    print(json.dumps({k: result[k] for k in ('resolved-semantic-blockers', 'remaining-semantic-blockers', 'model-admissible')}))

"""Audit champion-target damage gaps using retained bytes, without the model.

No damage formula, expected hit amount or API damage amount influences candidate
selection. API stat snapshots check field interpretation; recap spell names only
offer candidate effect labels. Every case remains inadmissible while relevant
buffs, sampling and packet semantics are unresolved.
"""
import argparse
import bisect
from collections import Counter, defaultdict
import gzip
import heapq
import json
from pathlib import Path
import re
import time

from replay_native import BUILD, PROTOCOL
from replay_recovery import digest, load
from replay_state import ObservedState, AD_INPUTS, replication_records, derived_stats


def elf32(name):
    value = 0
    for byte in name.lower().encode('utf-8'):
        value = (value << 4) + byte
        high = value & 0xf0000000
        if high:
            value ^= high >> 24
        value &= ~high
    return value


def effect_labels(timeline):
    """Dictionary unique is not proof of global hash uniqueness or ordinary hits."""
    labels = defaultdict(set)
    for frame in timeline['info']['frames']:
        for event in frame['events']:
            for key in ('victimDamageReceived', 'victimDamageDealt'):
                for row in event.get(key, []):
                    name = row.get('spellName', '').lower()
                    if name:
                        labels[elf32(name)].add(name)
    return labels


def effect_kind(effect_hash, champion, labels):
    names = labels.get(effect_hash, set())
    if len(names) != 1:
        return 'ambiguous-effect' if names else 'unknown-effect', sorted(names)
    name = next(iter(names))
    prefix = re.escape(champion.lower())
    if re.fullmatch(prefix + r'basicattack(?:ranged)?\d*', name):
        return 'basic-attack-candidate', [name]
    if re.fullmatch(prefix + r'critattack\d*', name):
        return 'critical-attack-candidate', [name]
    return 'other-effect', [name]


REQUIRED = ('attack-damage', 'crit-chance', 'flat-armor-penetration',
            'armor-remaining-fraction', 'physical-lethality',
            'bonus-armor-remaining-fraction')
SEMANTIC_GAPS = ('buff-and-on-hit-context-unresolved',
                 'inventory-and-rune-state-unresolved',
                 'attack-classification-not-independently-verified',
                 'stat-sampling-window-unresolved',
                 'shield-semantics-not-independently-verified',
                 'damage-packet-amount-semantics-incomplete')


def classify(event, source, target, champion, labels):
    kind, names = effect_kind(event['effect-hash'], champion, labels)
    gaps = [f'missing-source:{key}' for key in REQUIRED if key not in source]
    if 'armor' not in target:
        gaps.append('missing-target:armor')
    for name in ('shield-all-candidate', 'shield-physical-candidate'):
        if name not in target:
            gaps.append('missing-target:' + name)
        elif target[name]['value'] != 0:
            gaps.append('observed-shield-candidate-nonzero')
    if kind != 'basic-attack-candidate':
        gaps.append(kind)
    if source.get('crit-chance', {}).get('value', 0) != 0:
        gaps.append('critical-outcome-unresolved')
    if source.get('physical-lethality', {}).get('value', 0) != 0:
        gaps.append('nonzero-lethality-semantics-unverified')
    if source.get('bonus-armor-remaining-fraction', {}).get('value', 1) != 1:
        gaps.append('bonus-armor-penetration-semantics-unverified')
    if event['damage-type'] != 'physical':
        gaps.append('outside-first-mechanic:nonphysical')
    return {'effect-kind': kind, 'candidate-names': names,
            'data-gaps': sorted(set(gaps)), 'semantic-gaps': list(SEMANTIC_GAPS),
            'model-admissible': False}


def ordered_rows(path, kind):
    previous = -1
    with gzip.open(path, 'rt') as f:
        for line in f:
            row = json.loads(line)
            if type(row.get('order')) is not int or row['order'] <= previous:
                raise ValueError('Non-monotonic/duplicate archive order')
            previous = row['order']
            yield row['order'], kind, row


def check_offensive_snapshots(history, summary, match, timeline):
    participants = {(p['championName'], p['teamId']): p['participantId']
                    for p in match['info']['participants']}
    by_id = {participants[p['champion'], p['team']]: summary['champion-entity-start'] + p['slot']
             for p in summary['roster']}
    metrics = {'attack-damage': ('attackDamage', 1, False),
               'ability-power': ('abilityPower', 1, False),
               'flat-armor-penetration': ('armorPen', 1, False),
               'armor-remaining-fraction': ('armorPenPercent', 100, True),
               'flat-magic-penetration': ('magicPen', 1, False),
               'magic-resist-remaining-fraction': ('magicPenPercent', 100, True),
               'bonus-armor-remaining-fraction': ('bonusArmorPenPercent', 100, True),
               'bonus-magic-resist-remaining-fraction': ('bonusMagicPenPercent', 100, True)}
    counts = {key: Counter() for key in metrics}
    rows = []
    for frame in timeline['info']['frames']:
        t = frame['timestamp'] / 1000
        for participant, pf in frame['participantFrames'].items():
            entity = by_id[int(participant)]
            for key, (api_key, scale, remaining) in metrics.items():
                counts[key]['checks'] += 1
                samples = history.get((entity, key), [])
                idx = bisect.bisect_right(samples, (t, float('inf'), float('inf'))) - 1
                if idx < 0:
                    counts[key]['missing'] += 1
                    continue
                timestamp, order, value = samples[idx]
                value = (1 - value) * scale if remaining else value
                observed = pf['championStats'][api_key]
                counts[key]['api-nonzero-checks'] += observed != 0
                diff = value - observed
                counts[key]['within-one'] += abs(diff) < 1
                counts[key]['different'] += abs(diff) >= 1
                rows.append({'timestamp': t, 'slot': entity - summary['champion-entity-start'],
                             'field': key, 'replay-value-api-units': value,
                             'api': observed, 'difference': diff,
                             'sample-timestamp': timestamp})
    return {'fields': {key: dict(value) for key, value in counts.items()}, 'rows': rows,
            'scope': 'Replayed observed stat components, not model-derived build stats; lethality and crit have no independent API fields here'}


def append_derived_history(history, entity, derived):
    for key, sample in derived.items():
        # Recomputing AD on a health-only update must not make its inputs appear
        # newly observed. Every older component still has its own provenance.
        latest = max((p['timestamp'], p['order']) for p in sample['inputs'].values())
        rows = history[entity, key]
        if not rows or rows[-1][:2] != latest:
            rows.append((*latest, sample['value']))


def candidate_witness(case, folder):
    """Keep a selected hit and independent health samples; never fill pre-hit HP.

    Later samples are retrospective decoder diagnostics, not model inputs.
    A matching loss cannot prove missing effects were absent.
    """
    entity, order = case['target'], case['order']
    before, after = None, None
    for _, _, row in ordered_rows(Path(folder) / 'state.jsonl.gz', 'state'):
        for rec in row['champions']:
            if rec['entity'] != entity or 'health' not in rec['fields']:
                continue
            sample = {'event-id': row['event-id'], 'timestamp': row['timestamp'],
                      'order': row['order'], 'health': rec['fields']['health']}
            if row['order'] < order:
                before = sample
            elif after is None:
                after = sample
        if after is not None:
            break
    interval_damage = []
    if before and after:
        for _, _, row in ordered_rows(Path(folder) / 'damage.jsonl.gz', 'damage'):
            if row['order'] > after['order']:
                break
            if before['order'] < row['order'] < after['order'] and row['target'] == entity:
                interval_damage.append({'event-id': row['event-id'], 'amount': row['amount']})
    return {'case': case, 'health-before': before, 'health-after': after,
            'damage-between-health-samples': interval_damage,
            'health-drop': before['health'] - after['health'] if before and after else None,
            'model-admissible': False, 'scope': 'Retrospective decoder diagnostic only; no shield/buff absence or exact sampling inferred from numeric agreement'}


def witness_api_context(case, summary, match, timeline):
    by_champion = {(p['championName'], p['teamId']): p for p in match['info']['participants']}
    roster = {summary['champion-entity-start'] + p['slot']: p for p in summary['roster']}
    result = {}
    for role in ('source', 'target'):
        p = roster[case[role]]
        player = by_champion[p['champion'], p['team']]
        events = [e for f in timeline['info']['frames'] for e in f['events']
                  if e.get('participantId') == player['participantId']
                  and e['timestamp'] / 1000 <= case['timestamp']]
        result[role] = {
            'champion': p['champion'],
            'runes': [selection['perk'] for style in player['perks']['styles'] for selection in style['selections']],
            'shards': player['perks']['statPerks'],
            'summoner-spell-ids': [player['summoner1Id'], player['summoner2Id']],
            'events-before-hit': [{k: e[k] for k in ('timestamp', 'type', 'itemId', 'beforeId', 'afterId',
                                                    'skillSlot', 'levelUpType', 'level') if k in e}
                                  for e in events if e['type'] in
                                  ('SKILL_LEVEL_UP', 'LEVEL_UP', 'ITEM_PURCHASED', 'ITEM_SOLD', 'ITEM_DESTROYED', 'ITEM_UNDO')],
            'scope': 'Recorded API context; event prefix is not a complete inventory/buff reconstruction'}
    return result


def audit(folder, output, match_path=None, timeline_path=None):
    started = time.monotonic()
    folder, output = Path(folder), Path(output)
    summary = load(folder / 'summary.json')
    if summary.get('client-build') != BUILD or summary.get('protocol-digest') != PROTOCOL:
        raise ValueError('Unsupported archive build/protocol')
    if summary.get('failures'):
        raise ValueError('Audit requires a complete source extraction without decode failures')
    if output.exists():
        raise ValueError('Choose a fresh output directory')
    if bool(match_path) != bool(timeline_path):
        raise ValueError('Supply match and timeline together')
    labels, match, timeline = {}, None, None
    if match_path:
        validation = summary.get('validation', {})
        if (digest(match_path) != validation.get('match-sha256')
                or digest(timeline_path) != validation.get('timeline-sha256')):
            raise ValueError('API inputs differ from the archive identity-binding receipt')
        match, timeline = load(match_path), load(timeline_path)
        labels = effect_labels(timeline)
    source_files = {name: digest(folder / name) for name in
                    ('summary.json', 'state.jsonl.gz', 'damage.jsonl.gz')}
    output.mkdir(parents=True)
    state = ObservedState()
    start = summary['champion-entity-start']
    champions = {start + p['slot']: p['champion'] for p in summary['roster']}
    history = defaultdict(list)
    counts, gaps, effects = Counter(), Counter(), Counter()
    seed_candidates = []
    best_case = None
    previous_order, previous_time = -1, -1.
    streams = [ordered_rows(folder / 'state.jsonl.gz', 'state'),
               ordered_rows(folder / 'damage.jsonl.gz', 'damage')]
    with gzip.open(output / 'cases.jsonl.gz', 'wt') as cases:
        for order, kind, row in heapq.merge(*streams, key=lambda x: x[0]):
            t = row['timestamp']
            if order <= previous_order or t < previous_time:
                raise ValueError('Combined archive ordering is ambiguous')
            previous_order, previous_time = order, t
            if kind == 'state':
                records = replication_records(bytes.fromhex(row['decoded-buffer-hex']), set(champions))
                players = [r for r in records if r['entity'] in champions]
                state.apply(players, t, order, row['event-id'])
                counts['state-packets'] += 1
                for rec in players:
                    entity = rec['entity']
                    for key, value in rec['fields'].items():
                        history[entity, key].append((t, order, value))
                    append_derived_history(history, entity, derived_stats(state.entities[entity]))
                continue
            counts['all-damage-packets'] += 1
            if row['target'] not in champions:
                continue
            counts['champion-target-events'] += 1
            if row['source'] not in champions:
                counts['outside-scope:nonchampion-source'] += 1
                continue
            counts['champion-to-champion-events'] += 1
            before = row.get('source-last-observed', {})
            counts['source-ad-present-before-audit'] += 'attack-damage' in before
            source = state.before(row['source'], t, order)
            target = state.before(row['target'], t, order)
            result = classify(row, source, target, champions[row['source']], labels)
            counts['source-ad-present-after-audit'] += 'attack-damage' in source
            counts['source-ap-present-after-audit'] += 'ability-power' in source
            counts['complete-first-mechanic-stat-inputs'] += all(k in source for k in REQUIRED) and 'armor' in target
            counts['physical-events'] += row['damage-type'] == 'physical'
            effects[result['effect-kind']] += 1
            gaps.update(result['data-gaps'])
            case = {'event-id': row['event-id'], 'timestamp': t, 'order': order,
                    'replay-sha256': summary['replay-sha256'], 'source': row['source'],
                    'target': row['target'], 'effect-hash': row['effect-hash'],
                    'damage-type': row['damage-type'], 'recorded-amount': row['amount'],
                    'source-observed': source, 'target-observed': target, **result}
            cases.write(json.dumps(case, separators=(',', ':'), allow_nan=False) + '\n')
            if result['effect-kind'] == 'basic-attack-candidate' and row['damage-type'] == 'physical':
                # Rank without predicted or observed damage magnitude. Zero crit
                # chance is useful context, not proof of an ordinary outcome.
                score = (len(result['data-gaps']), t, row['event-id'])
                seed_candidates.append((score, {'event-id': row['event-id'], 'timestamp': t,
                                       'source-champion': champions[row['source']],
                                       'target-champion': champions[row['target']], **result}))
                if best_case is None or score < best_case[0]:
                    best_case = score, case
    if (counts['all-damage-packets'] != summary['counts']['damage-accepted']
            or counts['state-packets'] != summary['counts']['state-accepted']):
        raise ValueError('Archive packet counts disagree with source summary')
    report = {'format': 'powerspike-replay-gap-audit', 'version': 1,
              'client-build': BUILD, 'protocol-digest': PROTOCOL,
              'replay-sha256': summary['replay-sha256'], 'source-files': source_files,
              'adapters': {name: digest(Path(__file__).with_name(name)) for name in
                           ('replay_gaps.py', 'replay_state.py')},
              'counts': dict(counts), 'effect-label-counts': dict(effects),
              'data-gap-counts': dict(gaps),
              'semantic-gaps-for-every-candidate': list(SEMANTIC_GAPS),
              'model-comparisons': 0, 'admissible-cases': 0,
              'first-candidates': [c for score, c in sorted(seed_candidates)[:20]],
              'cost': {'wall-seconds': time.monotonic() - started},
              'limits': 'Post-hoc gap audit. API recap names are hash-label candidates, not verified cast/attack attribution. No missing buff, shield or item state is assumed absent. Offensive totals compose replay inputs and do not validate the model.'}
    if timeline:
        report['offensive-stat-checks'] = check_offensive_snapshots(history, summary, match, timeline)
        report['api-context'] = {'match-sha256': digest(match_path), 'timeline-sha256': digest(timeline_path),
                                 'uses': ['spell name dictionary', 'stat snapshot checks'],
                                 'damage-amounts-used': False}
    if best_case:
        witness = candidate_witness(best_case[1], folder)
        if timeline:
            witness['api-context'] = witness_api_context(best_case[1], summary, match, timeline)
        (output / 'candidate-witness.json').write_text(json.dumps(witness, indent=2, allow_nan=False) + '\n')
        report['candidate-witness'] = {'event-id': best_case[1]['event-id'],
                                        'sha256': digest(output / 'candidate-witness.json'),
                                        'model-admissible': False}
    report['evidence-files'] = {'cases.jsonl.gz': digest(output / 'cases.jsonl.gz')}
    report['cost']['wall-seconds'] = time.monotonic() - started
    report['cost']['evidence-bytes'] = sum(p.stat().st_size for p in output.iterdir())
    (output / 'summary.json').write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('input', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--match', type=Path)
    parser.add_argument('--timeline', type=Path)
    args = parser.parse_args()
    report = audit(args.input, args.output, args.match, args.timeline)
    print(json.dumps({'counts': report['counts'], 'labels': report['effect-label-counts'],
                      'gaps': report['data-gap-counts'], 'cost': report['cost']}))


if __name__ == '__main__':
    main()

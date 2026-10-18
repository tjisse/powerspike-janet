"""Resolve naming/context and run narrow current-patch stat model checks.

Damage admission is deliberately separate. Naming hints, transient effects and
unmatched buff events cannot be promoted to complete pre-hit state by agreement.
This pilot accepts the two champions and early purchases documented in the
discovery witness, rather than pretending to reconstruct arbitrary inventories.
"""
import argparse
from collections import defaultdict
import gzip
import json
from pathlib import Path
import subprocess
import tempfile

from jdn import dumps
from replay_buffs import BuffLedger, wire_key
from replay_gaps import elf32
from replay_recovery import digest, load

ROOT = Path(__file__).resolve().parents[1]


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)
    elif isinstance(value, dict):
        for key, item in value.items():
            yield key
            yield from strings(item)


def names_from_sources(folder, wanted):
    names = defaultdict(list)
    for path in sorted(Path(folder).glob('*.bin.json')):
        source_hash = digest(path)
        for name in sorted(set(strings(load(path)))):
            if elf32(name) in wanted:
                names[elf32(name)].append({'name': name, 'source': path.name,
                                          'source-sha256': source_hash,
                                          'status': 'hash-label-candidate'})
    return names


def champion_input(data, name):
    record = data[f'Characters/{name}/CharacterRecords/Root']
    def value(key):
        return record[key]['baseValue']
    # Only AD, armor, MR and selected HP totals are checked. AS is not evidence.
    return {'patch': '16.20.1', 'id': name,
            'base': {'ad': value('baseDamageModifiable'),
                     'armor': value('baseArmorModifiable'), 'mr': value('baseMR'),
                     'hp': value('baseHPModifiable')},
            'growth': {'ad': value('damagePerLevelModifiable'),
                       'armor': value('armorPerLevelModifiable'), 'mr': value('mrPerLevel'),
                       'hp': value('hpPerLevelModifiable')},
            'attack-speed-base': value('attackSpeedModifiable'),
            'attack-speed-ratio': value('attackSpeedRatioModifiable'),
            'attack-speed-growth': value('attackSpeedPerLevelModifiable') / 100,
            'attack-speed-cap': 2.5,  # unused by checked fields; harness constant
            'crit-damage': record['critDamageMultiplier']}


def item_input(data, item_id):
    # Explicit narrow early-game subset. New items require a separate review.
    if item_id not in (1036, 1120, 2003, 2031, 3340):
        raise ValueError('Item outside reviewed early stat subset')
    item = data['data'][str(item_id)]
    mapping = {'FlatPhysicalDamageMod': 'ad', 'FlatHPPoolMod': 'hp',
               'FlatArmorMod': 'armor', 'FlatSpellBlockMod': 'mr'}
    if set(item['stats']) - set(mapping):
        raise ValueError('Unmapped item stat')
    return {'id': str(item_id), 'patch': '16.20.1', 'supported': True,
            'stats': {mapping[k]: v for k, v in item['stats'].items()}}


def early_inventory(events):
    items = []
    for event in events:
        kind = event['type']
        if kind == 'ITEM_PURCHASED':
            items.append(event['itemId'])
        elif kind in ('ITEM_DESTROYED', 'ITEM_SOLD'):
            try:
                items.remove(event['itemId'])
            except ValueError as error:
                raise ValueError('Inventory removal without purchase') from error
        elif kind == 'ITEM_UNDO':
            raise ValueError('Inventory undo outside this pilot subset')
    return items


def run_model(inputs, janet):
    with tempfile.TemporaryDirectory(prefix='powerspike-stat-component-') as temp:
        path = Path(temp) / 'inputs.jdn'
        path.write_text(dumps(inputs))
        result = subprocess.run([str(Path(janet).resolve()), str(ROOT / 'scripts/replay_stat_model.janet'),
                                 str(path)], cwd=ROOT, check=True, capture_output=True,
                                text=True, timeout=30)
    values = {}
    for line in result.stdout.splitlines():
        case, field, value = line.split('\t')
        if (case, field) in values:
            raise ValueError('Duplicate model output')
        values[case, field] = float(value)
    expected_keys = {(r['id'], f) for r in inputs['cases'] for f in r['fields']}
    expected_keys.update((r['id'], 'damage') for r in inputs.get('hits', []))
    if set(values) != expected_keys:
        raise ValueError('Missing/unexpected model output')
    return values


def audit(base, janet, output):
    base, output = Path(base), Path(output)
    if output.exists():
        raise ValueError('Choose a fresh context report path')
    sources = base / 'context-research'
    extraction = load(base / 'combat-discovery-v2/summary.json')
    gap_summary = load(base / 'gaps-discovery-v3/summary.json')
    witness_path = base / 'gaps-discovery-v3/candidate-witness.json'
    if digest(witness_path) != gap_summary['candidate-witness']['sha256']:
        raise ValueError('Witness differs from original selection receipt')
    for name, expected_hash in gap_summary['source-files'].items():
        if digest(base / 'combat-discovery-v2' / name) != expected_hash:
            raise ValueError('Original combat archive receipt mismatch')
    witness = load(witness_path)
    case = witness['case']
    match_path, timeline_path = (base / 'timeline-research' / n for n in
                                 ('match.private.json', 'timeline.private.json'))
    for key, path in (('match-sha256', match_path), ('timeline-sha256', timeline_path)):
        if digest(path) != extraction['validation'][key]:
            raise ValueError('API input identity differs from extraction receipt')
    if case['replay-sha256'] != extraction['replay-sha256']:
        raise ValueError('Witness replay mismatch')
    # The raw sources are pinned by receipts; fail on replacements or mixed patch.
    for receipt in load(sources / 'source-receipts.json') + load(sources / 'global-source-receipts.json'):
        if '16.20' not in receipt['url']:
            raise ValueError('Source patch mismatch')
        name = receipt['url'].rsplit('/', 1)[-1]
        name = 'items.json' if name == 'item.json' else name
        if digest(sources / name) != receipt['sha256']:
            raise ValueError('Patch source receipt mismatch')
    timeline = load(timeline_path)
    match = load(match_path)
    buffs_summary = load(base / 'buffs-discovery-v3/summary.json')
    if buffs_summary['replay-sha256'] != case['replay-sha256'] or buffs_summary['failures']:
        raise ValueError('Buff archive identity/failure mismatch')
    buff_path = base / 'buffs-discovery-v3/buffs.jsonl.gz'
    if digest(buff_path) != buffs_summary['archives']['buffs.jsonl.gz']:
        raise ValueError('Buff archive receipt mismatch')
    ledger = BuffLedger()
    with gzip.open(buff_path, 'rt') as handle:
        for line in handle:
            row = json.loads(line)
            if wire_key(row['event-id']) >= wire_key(case['event-id']):
                break
            ledger.apply(row)
    snapshots = {role: ledger.snapshot(case[role]) for role in ('source', 'target')}
    wanted = {r['name-hash'] for snapshot in snapshots.values() for r in snapshot['observed-active']}
    names = names_from_sources(sources, wanted)
    for snapshot in snapshots.values():
        for row in snapshot['observed-active']:
            row['name-candidates'] = names.get(row['name-hash'], [])
        snapshot['unlabelled-active-hashes'] = sorted({r['name-hash'] for r in
            snapshot['observed-active'] if not r['name-candidates']})
    # A separate static-stat comparison at the first periodic API snapshot.
    # Its observed values NEVER enter the model input or the pre-hit snapshot.
    frame = timeline['info']['frames'][1]
    inputs, observations = {'cases': []}, []
    for role in ('source', 'target'):
        name = witness['api-context'][role]['champion']
        if name not in ('Sion', 'KSante'):
            raise ValueError('Champion outside this context pilot')
        roster = next(p for p in extraction['roster'] if
                      extraction['champion-entity-start'] + p['slot'] == case[role])
        if roster['champion'] != name:
            raise ValueError('Witness champion/entity binding mismatch')
        player = next(p for p in match['info']['participants'] if
                      (p['championName'], p['teamId']) == (name, roster['team']))
        participant = player['participantId']
        api = frame['participantFrames'][str(participant)]
        if api['level'] != 1 or api['xp'] != 0:
            raise ValueError('Pilot requires level one, zero XP')
        events = [e for f in timeline['info']['frames'] for e in f['events']
                  if e.get('participantId') == participant and e['timestamp'] <= frame['timestamp']]
        inventory = early_inventory(events)
        if inventory != early_inventory(witness['api-context'][role]['events-before-hit']):
            raise ValueError('Inventory changed between selected hit and stat snapshot')
        fields = ['ad', 'armor', 'mr'] + (['hp'] if name == 'KSante' else [])
        inputs['cases'].append({'id': role, 'champion': champion_input(
            load(sources / (name.lower() + '.bin.json')), name), 'level': 1,
            'items': [item_input(load(sources / 'items.json'), i) for i in inventory],
            'fields': fields})
        observations.append({'id': role, 'champion': name, 'inventory': inventory,
                             'timestamp': frame['timestamp'] / 1000,
                             'observed': {field: api['championStats'][key] for field, key in
                                          [('ad', 'attackDamage'), ('armor', 'armor'),
                                           ('mr', 'magicResist'), ('hp', 'healthMax')]
                                          if field in fields}})
    inputs['hits'] = [{'id': 'first-attack-conditional', 'source': 'source', 'target': 'target'}]
    expected = run_model(inputs, janet)
    predicted_hit = expected['first-attack-conditional', 'damage']
    checks = [{'role': r['id'], 'champion': r['champion'], 'timestamp': r['timestamp'],
               'stat': field, 'model': expected[r['id'], field], 'observed': actual,
               'difference': expected[r['id'], field] - actual,
               'consistent': abs(expected[r['id'], field] - actual) < 1}
              for r in observations for field, actual in r['observed'].items()]
    report = {'format': 'powerspike-replay-context-pilot', 'version': 1,
              'patch': '16.20.1', 'replay-sha256': case['replay-sha256'],
              'witness-event-id': case['event-id'], 'witness-buffs-before-event': snapshots,
              'input-receipts': {'combat-summary-sha256': digest(base / 'combat-discovery-v2/summary.json'),
                                 'gap-summary-sha256': digest(base / 'gaps-discovery-v3/summary.json'),
                                 'witness-sha256': digest(witness_path),
                                 'buff-summary-sha256': digest(base / 'buffs-discovery-v3/summary.json'),
                                 'buff-archive-sha256': digest(buff_path)},
              'sources': load(sources / 'source-receipts.json') +
                         load(sources / 'global-source-receipts.json'),
              'stat-model-inputs': inputs, 'stat-observations': observations,
              'stat-checks': checks, 'stat-check-count': len(checks),
              'conditional-damage-check': {
                  'model': predicted_hit, 'recorded': case['recorded-amount'],
                  'difference': predicted_hit - case['recorded-amount'],
                  'tolerance': 0.001,
                  'consistent-under-assumptions': abs(predicted_hit - case['recorded-amount']) < 0.001,
                  'model-admissible': False,
                  'assumptions': 'Ordinary noncritical physical attack, unchanged level-one stats, no other damage modifiers or shield absorption. Buff/protocol and attribution review still required; agreement does not discharge these assumptions.'},
              'stat-mismatches': sum(not r['consistent'] for r in checks),
              'stat-scope': 'Seven conditional static-stat checks at one periodic snapshot in one discovery game; not damage, timing, full loadout or held-out validation. Sion HP excluded because scaling-health shard is outside this harness.',
              'model-admissible-damage-cases': 0,
              'remaining-damage-blockers': ['unlabelled-or-behavior-unreviewed-buffs',
                  'unmatched-counter-records', 'full-buff-protocol-coverage-unproven',
                  'attack-to-damage-attribution', 'exact-stat-sampling-window',
                  'shield-and-packet-amount-semantics'],
              'adapters': {name: digest(ROOT / 'scripts' / name) for name in
                           ('replay_context.py', 'replay_stat_model.janet', 'replay_buffs.py')},
              'model': {name: digest(ROOT / 'src/powerspike' / name) for name in
                        ('stats.janet', 'damage.janet', 'validation.janet')}}
    output.write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--janet', type=Path, default=ROOT / 'build/janet')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.base, args.janet, args.output)
    print(json.dumps({k: result[k] for k in ('stat-check-count', 'stat-mismatches',
                                           'model-admissible-damage-cases')}))
    raise SystemExit(bool(result['stat-mismatches']))

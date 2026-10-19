"""Close the frozen first hit's relevant-effect and conditional-input gates.

This is a bounded declared-mechanic review for conditional ordinary physical
damage. It does not decode all buff scripts or locate a server sampling instant.
No predicted damage is consulted. Unknown labels remain retained metadata.
"""
import argparse
import json
from pathlib import Path
import time

from replay_actions import PROFILE
from replay_attack_review import archive, continuity
from replay_buffs import BuffLedger, wire_key
from replay_first_hit_review import GAME, EVENT, causal_skills
from replay_native import NativeDecoder
from replay_recovery import digest, load
from replay_review_fields import fields
from replay_state import replication_records

ROOT = Path(__file__).resolve().parents[1]
AMOUNT = ROOT / 'observations/replays/first-hit-amount-review-2026-10-18.json'
SOURCE = 1073742003
TARGET = 1073741998
RENGAR = 1073742006
GATES = {'buff-and-on-hit-context-unresolved', 'stat-sampling-window-unresolved'}
LOADOUTS = {
    'Sion': ([1036, 3340, 2031], [12, 4], [8230, 8226, 8234, 8236, 8321, 8410]),
    'Ivern': ([1102], [4, 11], [8214, 8275, 8210, 8232, 8347, 8321]),
    'Teemo': ([1082, 2031], [4, 14], [8005, 9111, 9104, 8299, 8106, 8143]),
    'Rengar': ([1055, 3340, 2003], [4, 3], [8021, 9111, 9104, 8017, 8453, 8429]),
    'Janna': ([2003, 2003], [4, 7], [8214, 8224, 8234, 8237, 8463, 8453]),
}


def inventory(events):
    result = []
    for event in events:
        kind = event['type']
        if kind == 'ITEM_PURCHASED': result.append(event['itemId'])
        elif kind in ('ITEM_DESTROYED', 'ITEM_SOLD'): result.remove(event['itemId'])
        elif kind == 'ITEM_UNDO':
            # Only undoing an ordinary purchase, with the declared item's full
            # gold returned, is in this witness prefix. No upgrade/sale undo.
            expected = {2003: 50, 1086: 400}
            if (event['afterId'] != 0 or event['beforeId'] not in expected
                    or event['goldGain'] != expected[event['beforeId']]):
                raise ValueError('Unreviewed inventory undo')
            result.remove(event['beforeId'])
        else: raise ValueError('Unreviewed inventory mutation')
    return result


def invariant(samples, expected, start=None):
    if not samples or (start is not None and wire_key(samples[0]['event-id']) > wire_key(start)):
        raise ValueError('Missing causal initial observation')
    if any(s['value'] != expected for s in samples):
        raise ValueError('Observed state changes outside reviewed context')


def scope_check(players, histories, actions, stats, deaths):
    if len(players) != 5 or {p['champion'] for p in players} != set(LOADOUTS) or deaths:
        raise ValueError('Unreviewed roster or prior death')
    for p in players:
        items, summoners, runes = LOADOUTS[p['champion']]
        expected_skills = [{'timestamp': 2.553, 'slot': 1}] if p['champion'] == 'Rengar' else []
        if (p['items'] != items or p['summoners'] != summoners or p['runes'] != runes
                or p['skills'] != expected_skills or p['team'] != 200):
            raise ValueError('Unreviewed source-team capability')
    # Entire prefix, including basic actions: no missing prerequisite-generating
    # Rengar action or Exhaust cast may be added and inherit this review.
    from replay_gaps import elf32
    if [(a['event-id'], a['kind'], a['source'], a.get('target'), a.get('effect-hash')) for a in actions] != [
        ('gameChunk:4:23998', 'spell-cast-announcement-candidate', 1073742007, None, elf32('TrinketTotemLvl1')),
        ('gameChunk:4:34433', 'spell-cast-announcement-candidate', TARGET, None, elf32('KSanteQ')),
        ('gameChunk:4:36830', 'basic-attack-announcement-candidate', TARGET, SOURCE, None),
        ('gameChunk:4:41399', 'spell-cast-announcement-candidate', 1073741999, None, elf32('TrinketTotemLvl1')),
        ('gameChunk:4:42928', 'basic-attack-announcement-candidate', SOURCE, TARGET, None)]:
        raise ValueError('Unreviewed action prefix')
    invariant(histories[RENGAR, 'primary-resource'], 0., 'gameChunk:3:12575')
    invariant(histories[RENGAR, 'primary-resource-max'], 4., 'gameChunk:3:12575')
    for actor in (SOURCE, TARGET):
        invariant(histories[actor, 'physical-damage-percentage-modifier'], 0., 'gameChunk:3:12575')
        # Control words are not interpreted with an old bit enum. Require the
        # post-initialization prefix to remain at the actual observed baseline.
        for name, expected in [('action-state-code', 16777231), ('action-state2-code', 4), ('status-flags-code', 0)]:
            settled = [s for s in histories[actor, name] if s['timestamp'] >= 6 or s is histories[actor, name][-1]]
            invariant(settled, expected)
    if (not stats['observed-stable'] or not stats['complete-observed-inputs']
            or len(stats['fields']) != 11):
        raise ValueError('Conditional damage inputs not fully observed and invariant')
    expected = {('source', 'base-attack-damage'): 68., ('source', 'flat-attack-damage'): 10.,
                ('source', 'percent-attack-damage'): 0., ('source', 'percent-bonus-attack-damage'): 0.,
                ('source', 'percent-base-attack-damage-as-bonus'): 0., ('source', 'crit-chance'): 0.,
                ('source', 'flat-armor-penetration'): 0., ('source', 'armor-remaining-fraction'): 1.,
                ('source', 'physical-lethality'): 0., ('source', 'bonus-armor-remaining-fraction'): 1.,
                ('target', 'armor'): 44.}
    actual = {(r['role'], r['field']): r['before-action']['value'] for r in stats['fields']}
    if actual != expected:
        raise ValueError('Observed scalars contradict the reviewed early loadout')


def review(base, image, output):
    base, image, output = map(Path, (base, image, output))
    if output.exists(): raise ValueError('Choose a fresh final review path')
    started = time.monotonic()
    amount = load(AMOUNT)
    if (amount['replay-sha256'] != GAME or amount['event-id'] != EVENT
            or set(amount['remaining-semantic-blockers']) != GATES):
        raise ValueError('Wrong prior review scope')
    for name, expected in amount['adapters'].items():
        if Path(name).name != name or digest(ROOT / 'scripts' / name) != expected:
            raise ValueError('Prior review adapter revision mismatch')
    effect_path = ROOT / 'observations/replays/first-hit-effect-review-2026-10-18.json'
    if digest(effect_path) != amount['inputs']['effect-review']: raise ValueError('Shield review receipt mismatch')
    effect = load(effect_path)
    first_path = ROOT / 'observations/replays/first-hit-review-2026-10-18.json'
    if digest(first_path) != effect['inputs']['first-review']: raise ValueError('First review receipt mismatch')
    first = load(first_path)
    for name, filename in [('match', 'match.private.json'), ('timeline', 'timeline.private.json')]:
        if digest(base / 'timeline-research' / filename) != first['inputs'][name]:
            raise ValueError('Riot causal input mismatch')
    match, timeline = [load(base / 'timeline-research' / f) for f in ('match.private.json', 'timeline.private.json')]
    if match['info']['gameMode'] != 'CLASSIC' or match['info']['gameType'] != 'MATCHED_GAME':
        raise ValueError('Alternate game rules outside review')
    witness_path = base / 'gaps-discovery-v3/candidate-witness.json'
    if digest(witness_path) != amount['inputs']['witness']: raise ValueError('Witness receipt mismatch')
    case = load(witness_path)['case']
    if case['timestamp'] >= 39 or case['source'] != SOURCE or case['target'] != TARGET:
        raise ValueError('Wrong first-hit identity/time')
    sources = base / 'context-research'
    for receipt in first['sources']:
        name = receipt['url'].rsplit('/', 1)[-1]; name = 'items.json' if name == 'item.json' else name
        if digest(sources / name) != receipt['sha256']: raise ValueError('Patch capability source mismatch')
    perks = {r['id']: r for r in load(sources / 'perks.json')}
    items = load(sources / 'items.json')['data']
    players, capabilities = [], []
    for p in match['info']['participants']:
        if p['teamId'] != 200: continue
        name = p['championName']
        prior = next(r for r in first['remaining-effect-review-inputs']['champions'] if r['champion'] == name)
        kit_path = base / 'outcome-research/kits-16.20.1' / (name + '.json')
        if digest(kit_path) != prior['source']['sha256']: raise ValueError('Champion source mismatch')
        kit = load(kit_path)['data'][name]
        events = [e for f in timeline['info']['frames'] for e in f['events']
                  if e.get('participantId') == p['participantId'] and e['timestamp'] / 1000 <= case['timestamp']
                  and e['type'].startswith('ITEM_')]
        players.append({'champion': name, 'team': 200, 'items': inventory(events),
            'summoners': [p['summoner1Id'], p['summoner2Id']],
            'runes': [s['perk'] for st in p['perks']['styles'] for s in st['selections']],
            'skills': causal_skills(timeline, p['participantId'], case['timestamp'])})
        capabilities.append({'champion': name, 'source': prior['source'], 'passive': kit['passive']['description'],
                             'abilities': [{'id': s['id'], 'description': s['description']} for s in kit['spells']]})
    deaths = [e for f in timeline['info']['frames'] for e in f['events']
              if e['type'] in ('CHAMPION_KILL', 'ELITE_MONSTER_KILL', 'BUILDING_KILL') and e['timestamp'] / 1000 <= case['timestamp']]
    gap_path = base / 'gaps-discovery-v3/summary.json'
    if digest(gap_path) != amount['inputs']['gap-audit']: raise ValueError('Gap receipt mismatch')
    combat_dir = base / 'combat-discovery-v2'; combat = load(combat_dir / 'summary.json')
    for name, expected in load(gap_path)['source-files'].items():
        if Path(name).name != name or digest(combat_dir / name) != expected: raise ValueError('Combat archive mismatch')
    if digest(image) != amount['inputs']['image'] or digest(PROFILE) != amount['inputs']['profile']:
        raise ValueError('Native image/profile mismatch')
    decoder = NativeDecoder(image, load(PROFILE))
    histories, observations = {}, 0
    for row in archive(combat_dir / 'state.jsonl.gz'):
        if wire_key(row['event-id']) >= wire_key(EVENT): break
        data = decoder.state_buffer(bytes.fromhex(row['raw-payload-hex']))
        if data.hex() != row['decoded-buffer-hex']: raise ValueError('Native state mismatch')
        observations += 1
        for record in replication_records(data, set(range(1073741998, 1073742008))):
            if not 1073741998 <= record['entity'] < 1073742008: continue
            values = dict(record['fields'])
            for component in record['components']: values.update(fields(component))
            for name, value in values.items():
                histories.setdefault((record['entity'], name), []).append({'event-id': row['event-id'],
                    'wire-key': wire_key(row['event-id']), 'timestamp': row['timestamp'], 'value': value})
    actions_dir = base / 'actions-discovery-v2'
    if digest(actions_dir / 'summary.json') != effect['inputs']['actions']: raise ValueError('Action receipt mismatch')
    for name, expected in load(actions_dir / 'summary.json')['archives'].items():
        if Path(name).name != name or digest(actions_dir / name) != expected: raise ValueError('Action archive mismatch')
    actions = [r for r in archive(actions_dir / 'actions.jsonl.gz') if wire_key(r['event-id']) < wire_key(EVENT)]
    stats = continuity(case, first['action'], histories)
    scope_check(players, histories, actions, stats, deaths)
    resource_checks = []
    combat_roster = {(r['champion'], r['team']): combat['champion-entity-start'] + r['slot'] for r in combat['roster']}
    for p in match['info']['participants']:
        actor = combat_roster[p['championName'], p['teamId']]
        api = timeline['info']['frames'][0]['participantFrames'][str(p['participantId'])]['championStats']
        for field, oracle in [('primary-resource', 'power'), ('primary-resource-max', 'powerMax')]:
            value = histories[actor, field][0]['value']
            if value != api[oracle]: raise ValueError('Independent initial resource oracle mismatch')
            resource_checks.append({'champion': p['championName'], 'field': field, 'native-observation': value, 'api': api[oracle]})
    buffs_dir = base / 'buffs-discovery-v4'
    if digest(buffs_dir / 'summary.json') != effect['inputs']['buffs']: raise ValueError('Buff receipt mismatch')
    for name, expected in load(buffs_dir / 'summary.json')['archives'].items():
        if Path(name).name != name or digest(buffs_dir / name) != expected: raise ValueError('Buff archive mismatch')
    ledger = BuffLedger()
    for row in archive(buffs_dir / 'buffs.jsonl.gz'):
        if wire_key(row['event-id']) >= wire_key(EVENT): break
        ledger.apply(row)
    report = {'format': 'powerspike-first-hit-final-review', 'version': 1, 'replay-sha256': GAME,
        'event-id': EVENT, 'client-build': first['client-build'], 'layer': 'conditional-damage',
        'source-team': players, 'source-capabilities': capabilities,
        'source-loadout-capabilities': {'items': {str(i): {'name': items[str(i)]['name'], 'description': items[str(i)]['description']} for p in players for i in p['items']},
            'runes': {str(i): {'name': perks[i]['name'], 'description': perks[i]['longDesc']} for p in players for i in p['runes']}},
        'effect-review': {
            'Sion': 'No prior death, no learned ability, ordinary attack asset/slot and zero crit already reviewed. Long Sword supplies AD; the selected source runes affect movement, mana, gold or post-10-minute stats, not this early attack multiplier.',
            'ally-buffs': 'Janna E and Ivern W/E are unlearned; passive descriptions confer no ally AD/on-hit buff. Teemo and Rengar passives modify their own attacks, not Sion\'s.',
            'Glacial-Augment': 'Blitzcrank has no learned immobilizing ability and no action in the complete observed prefix; no triggering immobilization is mechanically available to him in this context.',
            'Unflinching': 'Source team has no learned CC spell. Rengar has only Q, observed Ferocity zero of four throughout the prefix and no generating attack/cast; empowered E is excluded by resource/prerequisite evidence, not rank zero alone. The selected Exhaust has no cast in the prefix. No eligible trigger for the target\'s temporary resistance bonus.',
            'target-other-effects': 'K\'Sante W/E/R are unlearned. Grasp, Last Stand and Demolish affect target outgoing attacks/healing or towers; Second Wind heals. They do not modify the source\'s physical attack multiplier. Capacity, positive landing and shield-free metric were independently reviewed.',
            'opaque-records': 'Exact names for three counter/buff hashes and complete lifecycle behavior remain unknown. Their metadata is retained. The gate is discharged by reviewing every relevant declared capability in this frozen ordinary-match context, not by relabelling hashes or assuming complete buff decoding.'},
        'sampling-review': {'status': 'sampling-instant-irrelevant-for-invariant-conditional-inputs',
            'observations': stats, 'server-sampling-instant-known': False,
            'reason': 'All eleven observed scalar inputs are present before the attack and unchanged through damage. Causal loadouts/ranks, no deaths/rewards, zero Ferocity, absence of prerequisite actions and declared mechanic review exclude relevant transient changes. Any sampling point in the reviewed attack interval yields the same conditional inputs.',
            'scope': 'Only conditional ordinary physical damage from observed scalars; not full build/stat generation, arbitrary snapshot timing or sequence verification.'},
        'native-state-packets-rechecked': observations, 'resource-oracle-checks': resource_checks,
        'supporting-histories': [{'entity': actor, 'field': field, 'observations': rows} for (actor, field), rows in histories.items()
            if (actor == RENGAR and field.startswith('primary-resource')) or (actor in (SOURCE, TARGET) and field in ('action-state-code', 'action-state2-code', 'status-flags-code', 'physical-damage-percentage-modifier'))],
        'buff-metadata-retained': {role: ledger.snapshot(actor) for role, actor in [('source', SOURCE), ('target', TARGET)]},
        'resolved-semantic-blockers': sorted(GATES), 'remaining-semantic-blockers': [],
        'cumulative-resolved-semantic-blockers': sorted(amount['cumulative-resolved-semantic-blockers'] + list(GATES)),
        'ready-for-conditional-comparison': True, 'admitted-model-comparisons': 0,
        'model-admissible': False,
        'admission-status': 'Observation review complete; a conditional-input comparison adapter must bind this receipt before model admission/evaluation. Full simulation is outside this review.',
        'scope': 'Six reviewed gates for one conditional-input case only. Full buff interpreter, exact server timing and whole-model accuracy remain unclaimed. Review alone is not model evaluation or admission.',
        'inputs': {'amount-review': digest(AMOUNT), 'match': first['inputs']['match'], 'timeline': first['inputs']['timeline'], 'image': digest(image), 'profile': digest(PROFILE)},
        'adapters': {n: digest(ROOT / 'scripts' / n) for n in ('replay_final_review.py', 'replay_review_fields.py', 'replay_native.py', 'replay_state.py', 'replay_attack_review.py', 'replay_buffs.py')},
        'cost': {'wall-seconds': time.monotonic() - started, 'new-requests': 0, 'new-download-bytes': 0},
        'annotation': {'reason': 'Case-specific declared-mechanic and prerequisite review, independently corroborated zero Ferocity, and invariant causal scalar inputs discharge the last two gates for conditional ordinary physical damage. Unknown buff metadata and exact server sampling instant remain explicitly unclaimed; no prediction error used.', 'changes': {'blockers': []}}}
    output.write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('base', 'image', 'output'): parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args(); result = review(args.base, args.image, args.output)
    print(json.dumps({k: result[k] for k in ('resolved-semantic-blockers', 'remaining-semantic-blockers', 'ready-for-conditional-comparison')}))

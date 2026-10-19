"""Review two evidence gates for the retained first Sion/K'Sante witness.

This deliberately narrow review does not admit damage comparisons. It does not
turn historical enum values, name correlations or a matching prediction into
proof of complete effect/shield state.
"""
import argparse
import json
import math
from pathlib import Path
import struct

from replay_attack_review import archive
from replay_actions import candidates
from replay_context import early_inventory
from replay_gaps import elf32, SEMANTIC_GAPS
from replay_recovery import digest, load

ROOT = Path(__file__).resolve().parents[1]
GAME = '670abf1ef2a4fd005cf4ee1a36560078fc99e90aeee5ef263532e59105f2888c'
EVENT = 'gameChunk:4:43918'
RESOLVED = ('attack-classification-not-independently-verified', 'inventory-and-rune-state-unresolved')


def attack_identity(case, action, result, spell):
    if (case['event-id'] != EVENT or case['replay-sha256'] != GAME
            or case['damage-type'] != 'physical'
            or candidates(case, [action]) != [action]
            or action['auxiliary-cast-count'] != 0
            or action['source'] != case['source'] or action['target'] != case['target']
            or action['attack-slot'] != 64 or result['result-code'] != 5
            or result['source'] != case['source'] or result['target'] != case['target']
            or result['amount'] != case['recorded-amount'] or result['amount'] <= 0
            or result['effect-hash'] != case['effect-hash']
            or spell['mScriptName'] != 'SionBasicAttack'
            or elf32(spell['mScriptName']) != case['effect-hash']
            or case['source-observed']['crit-chance']['value'] != 0):
        raise ValueError('Witness does not satisfy the reviewed ordinary-attack identity scope')
    return {'status': 'corroborated-for-this-case', 'native-attack-slot': 64, 'native-result-code': 5,
            'source-spell': spell['mScriptName'], 'source-spell-hash': case['effect-hash'],
            'source-crit-chance-observed': 0,
            'reason': 'One causally prior targeted announcement, ordinary Sion attack asset, zero observed crit chance, positive independently decoded damage and health loss. No prediction error was used.',
            'limit': 'This does not identify every slot/result code, prove universal hash uniqueness or establish absence of on-hit/incoming modifiers.'}


def health_closure(witness):
    before, after = witness['health-before']['health'], witness['health-after']['health']
    amount = witness['case']['recorded-amount']
    def ulp(value):
        if not math.isfinite(value) or not 0 < value < 1e7:
            raise ValueError('Health closure requires bounded positive float32 observations')
        bits = struct.unpack('<I', struct.pack('<f', value))[0]
        return struct.unpack('<f', struct.pack('<I', bits + 1))[0] - struct.unpack('<f', struct.pack('<I', bits))[0]
    bound = sum(ulp(value) / 2 for value in (before, after, amount))
    difference = (before - after) - amount
    if (before <= after or abs(difference) > bound
            or len(witness['damage-between-health-samples']) != 1
            or witness['damage-between-health-samples'][0]['event-id'] != EVENT):
        raise ValueError('Independent health bracket does not close at float32 measurement precision')
    return {'health-before': before, 'health-after': after, 'wire-damage': amount,
            'difference': difference, 'measurement-bound': bound,
            'bound-policy': 'Sum of half a float32 ULP for the three observed values, not fitted to damage error.',
            'scope': 'Corroborates positive health loss for this bracket; does not by itself establish shield absorption semantics or a model tolerance.'}


def inventory_context(events, items):
    # A closed early subset: no item upgrades, transformations, undo or rewards
    # are inferred. Both inventories are explicitly bound to their purchase prefix.
    allowed = {1036, 1120, 2003, 2031, 3340}
    inventory = early_inventory(events)
    if any(item not in allowed or str(item) not in items['data'] for item in inventory):
        raise ValueError('Inventory outside reviewed early-game subset')
    if any(event['type'] not in ('ITEM_PURCHASED', 'ITEM_DESTROYED', 'ITEM_SOLD', 'SKILL_LEVEL_UP') for event in events):
        raise ValueError('Unreviewed inventory event')
    return [{'id': item, 'name': items['data'][str(item)]['name'],
             'declared-stats': items['data'][str(item)]['stats']} for item in inventory]


def causal_skills(timeline, participant, timestamp):
    return [{'timestamp': event['timestamp'] / 1000, 'slot': event['skillSlot']}
            for frame in timeline['info']['frames'] for event in frame['events']
            if event['type'] == 'SKILL_LEVEL_UP' and event.get('participantId') == participant
            and event['timestamp'] / 1000 <= timestamp]


def review(base, outcomes_dir, output):
    base, outcomes_dir, output = map(Path, (base, outcomes_dir, output))
    if output.exists():
        raise ValueError('Choose a fresh first-hit review path')
    gap = load(base / 'gaps-discovery-v3/summary.json')
    combat = load(base / 'combat-discovery-v2/summary.json')
    outcome = load(outcomes_dir / 'summary.json')
    dossier_path = base / 'attack-review-discovery-v2/witness.json'
    dossier_summary = load(dossier_path.parent / 'summary.json')
    dossier = load(dossier_path)
    witness_path = base / 'gaps-discovery-v3/candidate-witness.json'
    witness = load(witness_path)
    case = witness['case']
    if (digest(witness_path) != gap['candidate-witness']['sha256']
            or digest(dossier_path) != dossier_summary['evidence-files']['witness.json']
            or any(report['replay-sha256'] != GAME for report in (gap, combat, outcome))
            or outcome['inputs']['audit'] != digest(base / 'gaps-discovery-v3/summary.json')
            or outcome['inputs']['combat'] != digest(base / 'combat-discovery-v2/summary.json')
            or dossier['status'] != 'unique-candidate' or dossier['event-id'] != EVENT):
        raise ValueError('Original witness/outcome/dossier identity mismatch')
    for name, expected in outcome['archives'].items():
        if Path(name).name != name or digest(outcomes_dir / name) != expected:
            raise ValueError('Outcome archive receipt mismatch')
    for name, expected in outcome['adapters'].items():
        if Path(name).name != name or digest(ROOT / 'scripts' / name) != expected:
            raise ValueError('Outcome decoder revision mismatch')
    action_id = dossier['action-candidates'][0]['event-id']
    actions = [r for r in archive(outcomes_dir / 'action-slots.jsonl.gz') if r['event-id'] == action_id]
    results = [r for r in archive(outcomes_dir / 'damage-outcomes.jsonl.gz') if r['event-id'] == EVENT]
    if len(actions) != 1 or len(results) != 1:
        raise ValueError('Missing or duplicate witness action/outcome')
    sources = base / 'context-research'
    receipts = load(sources / 'source-receipts.json') + load(sources / 'global-source-receipts.json')
    for receipt in receipts:
        name = receipt['url'].rsplit('/', 1)[-1]
        name = 'items.json' if name == 'item.json' else name
        if '16.20' not in receipt['url'] or digest(sources / name) != receipt['sha256']:
            raise ValueError('Matching patch source receipt mismatch')
    sion = load(sources / 'sion.bin.json')
    spell = sion['Characters/Sion/Spells/SionBasicAttack']
    hashes = {path for path, entry in sion.items()
              if isinstance(entry, dict) and entry.get('mScriptName') and elf32(entry['mScriptName']) == case['effect-hash']}
    if hashes != {'Characters/Sion/Spells/SionBasicAttack'}:
        raise ValueError('Ambiguous attack hash in retained Sion spell scope')
    identity_review = attack_identity(case, actions[0], results[0], spell)
    health_review = health_closure(witness)
    match_path, timeline_path = (base / 'timeline-research' / name for name in
                                 ('match.private.json', 'timeline.private.json'))
    if (digest(match_path) != combat['validation']['match-sha256']
            or digest(timeline_path) != combat['validation']['timeline-sha256']):
        raise ValueError('Riot loadout/timeline input identity mismatch')
    match, timeline = load(match_path), load(timeline_path)
    if match['info']['gameVersion'] != outcome['client-build'] or match['info']['mapId'] != 11:
        raise ValueError('Wrong source game build or map')
    items, perks = load(sources / 'items.json'), load(sources / 'perks.json')
    perks = {row['id']: row for row in perks}
    roster = {combat['champion-entity-start'] + row['slot']: row for row in combat['roster']}
    loadouts = {}
    for role, expected in (('source', 'Sion'), ('target', 'KSante')):
        actor = roster[case[role]]
        players = [p for p in match['info']['participants'] if (p['championName'], p['teamId']) == (expected, actor['team'])]
        if actor['champion'] != expected or len(players) != 1:
            raise ValueError('Riot player/champion binding mismatch')
        player = players[0]
        events = [event for frame in timeline['info']['frames'] for event in frame['events']
                  if event.get('participantId') == player['participantId']
                  and event['timestamp'] / 1000 <= case['timestamp']
                  and event['type'] in ('ITEM_PURCHASED', 'ITEM_DESTROYED', 'ITEM_SOLD', 'ITEM_UNDO', 'SKILL_LEVEL_UP')]
        current_items = inventory_context(events, items)
        if [r['id'] for r in current_items] != early_inventory(witness['api-context'][role]['events-before-hit']):
            raise ValueError('Recorded inventory prefix mismatch')
        rune_ids = [s['perk'] for style in player['perks']['styles'] for s in style['selections']]
        if rune_ids != witness['api-context'][role]['runes'] or set(rune_ids) - perks.keys():
            raise ValueError('Rune selection missing or mismatched')
        if (player['perks']['statPerks'] != witness['api-context'][role]['shards']
                or [player['summoner1Id'], player['summoner2Id']] != witness['api-context'][role]['summoner-spell-ids']):
            raise ValueError('Shard or summoner selection mismatch')
        loadouts[role] = {'champion': expected, 'items': current_items, 'item-events': events,
            'runes': [{'id': key, 'current-patch-name': perks[key]['name']} for key in rune_ids],
            'shards': player['perks']['statPerks'],
            'summoner-spell-ids': [player['summoner1Id'], player['summoner2Id']],
            'scope': 'Recorded early item prefix and static selections only; activation, buff state and effect behavior remain separate review gates.'}
    kit_dir = base / 'outcome-research/kits-16.20.1'
    kit_receipts = load(kit_dir / 'receipts.json')
    kit_sources = {row['file']: row for row in kit_receipts['sources']}
    ability_context = []
    for player in match['info']['participants']:
        name = player['championName']
        filename = name + '.json'
        receipt = kit_sources[filename]
        if (receipt['url'] != f'https://ddragon.leagueoflegends.com/cdn/16.20.1/data/en_US/champion/{filename}'
                or digest(kit_dir / filename) != receipt['sha256']):
            raise ValueError('Matching-patch champion kit receipt mismatch')
        data = load(kit_dir / filename)
        if data['version'] != '16.20.1' or set(data['data']) != {name}:
            raise ValueError('Champion kit identity mismatch')
        ability_context.append({'champion': name, 'team': player['teamId'],
            'skill-upgrades-before-hit': causal_skills(timeline, player['participantId'], case['timestamp']),
            'passive-description': data['data'][name]['passive']['description'],
            'source': receipt})
    remaining = sorted(set(SEMANTIC_GAPS) - set(RESOLVED))
    report = {'format': 'powerspike-first-hit-semantic-review', 'version': 1,
              'replay-sha256': GAME, 'event-id': EVENT, 'client-build': outcome['client-build'],
              'attack-identity-review': identity_review, 'action': actions[0], 'damage-outcome': results[0],
              'health-landing-corroboration': health_review,
              'loadout-review': loadouts, 'resolved-semantic-blockers': list(RESOLVED),
              'remaining-effect-review-inputs': {'champions': ability_context,
                  'scope': 'Causal skill upgrades and current-patch passive descriptions narrow the remaining effect/shield review. Descriptions are not executable behavior or proof of complete buff state.'},
              'remaining-semantic-blockers': remaining, 'model-admissible': False,
              'scope': 'Case-specific ordinary/noncritical identity and recorded loadout selection. This does not admit damage evidence or verify effect/shield/sampling/amount semantics.',
              'enum-warning': 'Historical normal-result value 4 is not assigned to current code 5. Classification uses this case\'s independent slot/asset/crit/health observations; other result codes remain unlabelled.',
              'sources': receipts,
              'inputs': {'witness': digest(witness_path), 'outcomes': digest(outcomes_dir / 'summary.json'),
                         'context-witness': digest(dossier_path), 'match': digest(match_path), 'timeline': digest(timeline_path)},
              'reviewer-adapter-sha256': digest(__file__),
              'annotation': {'reason': 'Case-specific ordinary/noncritical identity and recorded early inventory/rune selections reviewed against native codecs, causal action, current Sion asset and retained Riot receipts; other semantics remain blocked.',
                             'changes': {'blockers': remaining}}}
    output.write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--outcomes', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = review(args.base, args.outcomes, args.output)
    print(json.dumps({key: result[key] for key in ('resolved-semantic-blockers', 'remaining-semantic-blockers', 'model-admissible')}))

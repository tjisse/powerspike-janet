"""Review shield eligibility for one frozen first-hit context, without the model.

This is a capability exclusion, not a shield-field calibration. It deliberately
does not admit damage, resolve every buff, or establish shield absorption rules.
"""
import argparse
import json
from pathlib import Path
import time

from replay_attack_review import archive
from replay_buffs import BuffLedger, wire_key
from replay_context import early_inventory
from replay_first_hit_review import GAME, EVENT, causal_skills
from replay_gaps import elf32
from replay_recovery import digest, load

ROOT = Path(__file__).resolve().parents[1]
FIRST_REVIEW = ROOT / 'observations/replays/first-hit-review-2026-10-18.json'
SHIELD_GATE = 'shield-semantics-not-independently-verified'
TARGET_LOADOUTS = {
    'KSante': ([1120, 2003, 3340], [4, 12], [8437, 8446, 8444, 8242, 8299, 9105]),
    'Diana': ([1103, 3340], [4, 11], [8010, 9111, 9104, 8017, 8304, 8347]),
    'Yasuo': ([1086, 2003, 2003, 3340], [14, 4], [8008, 9101, 9104, 8299, 8444, 8401]),
    'Tristana': ([1086, 2003, 2003, 3340], [4, 21], [8008, 9111, 9104, 8014, 8139, 8135]),
    'Blitzcrank': ([2003, 2003, 3364], [14, 4], [8351, 8306, 8345, 8347, 8275, 8234]),
}


def eligible_shield_context(players, timestamp, actions, target_snapshot, target_observed):
    """Fail closed outside the manually reviewed capability set, even one case."""
    if not 38 < timestamp < 39 or len(players) != 5 or {r['champion'] for r in players} != set(TARGET_LOADOUTS):
        raise ValueError('Outside reviewed first-hit roster/time scope')
    for row in players:
        items, summoners, runes = TARGET_LOADOUTS[row['champion']]
        if (row['items'] != items or row['summoner-spell-ids'] != summoners or row['rune-ids'] != runes
                or row['team'] != 100):
            raise ValueError('Unreviewed shield capability in loadout or team')
        skills = row['skill-upgrades-before-hit']
        if row['champion'] == 'KSante':
            if skills != [{'timestamp': 36.422, 'slot': 1}]:
                raise ValueError('Target may have a defensive ability available')
        elif skills:
            raise ValueError('Ally may have an unreviewed ability available')
    # The whole observed spell prefix is fixed, not only casts by the target.
    # No summoner Teleport or unknown cast is silently dropped.
    spells = [(r['source'], r['effect-hash']) for r in actions
              if r['kind'] == 'spell-cast-announcement-candidate']
    if spells != [(1073742007, elf32('TrinketTotemLvl1')),
                  (1073741998, elf32('KSanteQ')), (1073741999, elf32('TrinketTotemLvl1'))]:
        raise ValueError('Unreviewed pre-hit spell prefix')
    quest = [r for r in target_snapshot['observed-active']
             if r['name-hash'] == elf32('SR_2026_S1_RoleBound_Top_Quest')]
    if (len(quest) != 1 or quest[0].get('counter-update', {}).get('counter') != 0
            or any(r['name-hash'] == elf32('SR_2026_S1_RoleBound_Top_QuestCompleted')
                   for r in target_snapshot['observed-active'])):
        raise ValueError('Quest reward eligibility outside reviewed early scope')
    for field in ('shield-all-candidate', 'shield-physical-candidate', 'shield-magic-candidate'):
        if target_observed[field]['value'] != 0:
            raise ValueError('Shield candidate observation contradicts capability exclusion')
    return {
        'status': 'reviewed-no-eligible-shield-source-for-this-case',
        'target-self': "K'Sante E (shield), W (reduction) and R (transformation) are unlearned; Q and the passive describe outgoing effects.",
        'target-allies': 'Diana and Blitzcrank shields protect themselves, as do Yasuo passive and Tristana Barrier. Their abilities are unlearned and none grants a passive shield to K\'Sante.',
        'items-and-runes': 'The exact five-player prefixes contain starter items, potions and trinkets; no ally shield item or Guardian/Aery selection on the target team. Shield Bash is an outgoing proc on Yasuo, not a shield grant to K\'Sante.',
        'teleport-quest': 'The target has the unfinished quest with counter zero and no observed Teleport cast; the matching-patch tooltip makes the Teleport shield a quest reward.',
        'scope': 'Shield-free eligibility for this frozen ordinary match context only. This does not verify shield field meanings, nonzero shields, absorption, complete buff replication or other cases.',
    }


def review(base, output):
    started = time.monotonic()
    base, output = Path(base), Path(output)
    if output.exists():
        raise ValueError('Choose a fresh effect review path')
    first = load(FIRST_REVIEW)
    if (first['replay-sha256'] != GAME or first['event-id'] != EVENT
            or first['model-admissible'] is not False or SHIELD_GATE not in first['remaining-semantic-blockers']):
        raise ValueError('Wrong original semantic review')
    witness_path = base / 'gaps-discovery-v3/candidate-witness.json'
    match_path, timeline_path = (base / 'timeline-research' / n for n in ('match.private.json', 'timeline.private.json'))
    for key, path in (('witness', witness_path), ('match', match_path), ('timeline', timeline_path)):
        if digest(path) != first['inputs'][key]:
            raise ValueError('Original causal source receipt mismatch')
    witness, match, timeline = load(witness_path), load(match_path), load(timeline_path)
    case = witness['case']
    if (case['event-id'] != EVENT or case['replay-sha256'] != GAME
            or case['target'] != 1073741998 or match['info']['mapId'] != 11
            or match['info']['gameVersion'] != first['client-build']):
        raise ValueError('Review subject/build/map mismatch')
    sources = base / 'context-research'
    for receipt in first['sources']:
        filename = receipt['url'].rsplit('/', 1)[-1]
        filename = 'items.json' if filename == 'item.json' else filename
        if digest(sources / filename) != receipt['sha256']:
            raise ValueError('Patch source receipt mismatch')
    items, perks = load(sources / 'items.json'), load(sources / 'perks.json')
    perks = {p['id']: p for p in perks}
    string_receipt = load(sources / 'strings-source-receipt.json')
    if (string_receipt['url'] != 'https://raw.communitydragon.org/16.20/game/en_us/data/menu/en_us/lol.stringtable.json'
            or digest(sources / 'lol.stringtable.json') != string_receipt['sha256']):
        raise ValueError('Quest tooltip receipt mismatch')
    tooltip = load(sources / 'lol.stringtable.json')['entries']['buff_desc_sr_2026_s1_rolebound_top']
    if 'Enhanced Teleport to grant a shield' not in tooltip:
        raise ValueError('Quest shield behavior requires renewed review')
    summoner_path = base / 'outcome-research/summoner-16.20.1.json'
    summoner_receipt = load(base / 'outcome-research/summoner-16.20.1-receipt.json')
    if (summoner_receipt['url'] != 'https://ddragon.leagueoflegends.com/cdn/16.20.1/data/en_US/summoner.json'
            or digest(summoner_path) != summoner_receipt['sha256']):
        raise ValueError('Summoner capability source receipt mismatch')
    summoners = load(summoner_path)
    if summoners['version'] != '16.20.1':
        raise ValueError('Summoner patch mismatch')
    summoners = {int(s['key']): s for s in summoners['data'].values()}
    reward_events = [e for f in timeline['info']['frames'] for e in f['events']
                     if e['timestamp'] / 1000 <= case['timestamp']
                     and e['type'] in ('CHAMPION_KILL', 'ELITE_MONSTER_KILL', 'BUILDING_KILL')]
    if reward_events:
        raise ValueError('Early reward context requires renewed review')
    players, kits = [], []
    for player in match['info']['participants']:
        if player['teamId'] != 100:
            continue
        name = player['championName']
        prior = next(r for r in first['remaining-effect-review-inputs']['champions'] if r['champion'] == name)
        kit_path = base / 'outcome-research/kits-16.20.1' / (name + '.json')
        if digest(kit_path) != prior['source']['sha256']:
            raise ValueError('Champion capability source receipt mismatch')
        kit = load(kit_path)['data'][name]
        kits.append({'champion': name, 'source': prior['source'], 'passive': kit['passive']['description'],
                     'abilities': [{'id': s['id'], 'description': s['description']} for s in kit['spells']]})
        events = [e for f in timeline['info']['frames'] for e in f['events']
                  if e.get('participantId') == player['participantId'] and e['timestamp'] / 1000 <= case['timestamp']
                  and e['type'].startswith('ITEM_')]
        if any(e['type'] not in ('ITEM_PURCHASED', 'ITEM_DESTROYED', 'ITEM_SOLD', 'ITEM_UNDO') for e in events):
            raise ValueError('Unreviewed inventory mutation')
        players.append({'champion': name, 'team': player['teamId'], 'items': early_inventory(events),
            'summoner-spell-ids': [player['summoner1Id'], player['summoner2Id']],
            'rune-ids': [s['perk'] for st in player['perks']['styles'] for s in st['selections']],
            'skill-upgrades-before-hit': causal_skills(timeline, player['participantId'], case['timestamp'])})
    action_dir, buff_dir = base / 'actions-discovery-v2', base / 'buffs-discovery-v4'
    summaries = [load(p / 'summary.json') for p in (action_dir, buff_dir)]
    for directory, summary in zip((action_dir, buff_dir), summaries):
        if summary['replay-sha256'] != GAME or summary['failures']:
            raise ValueError('Incomplete or different-game effect extraction')
        for name, expected in summary['archives'].items():
            if Path(name).name != name or digest(directory / name) != expected:
                raise ValueError('Effect archive receipt mismatch')
        for name, expected in summary['adapters'].items():
            if Path(name).name != name or digest(ROOT / 'scripts' / name) != expected:
                raise ValueError('Effect decoder revision mismatch')
    actions = [r for r in archive(action_dir / 'actions.jsonl.gz') if wire_key(r['event-id']) < wire_key(EVENT)]
    if any(r['timestamp'] > case['timestamp'] for r in actions):
        raise ValueError('Noncausal action timestamp')
    ledger = BuffLedger()
    for row in archive(buff_dir / 'buffs.jsonl.gz'):
        if wire_key(row['event-id']) >= wire_key(EVENT):
            break
        ledger.apply(row)
    snapshot = ledger.snapshot(case['target'])
    shield = eligible_shield_context(players, case['timestamp'], actions, snapshot, case['target-observed'])
    remaining = sorted(set(first['remaining-semantic-blockers']) - {SHIELD_GATE})
    report = {'format': 'powerspike-first-hit-effect-review', 'version': 1,
        'replay-sha256': GAME, 'event-id': EVENT, 'client-build': first['client-build'],
        'shield-context-review': shield, 'target-team': players, 'champion-capabilities': kits,
        'loadout-capabilities': {'items': {str(i): {'name': items['data'][str(i)]['name'],
            'description': items['data'][str(i)]['description']} for r in players for i in r['items']},
            'runes': {str(i): {'name': perks[i]['name'], 'description': perks[i]['longDesc']}
                      for r in players for i in r['rune-ids']},
            'summoners': {str(i): {'name': summoners[i]['name'], 'description': summoners[i]['description']}
                          for r in players for i in r['summoner-spell-ids']},
            'summoner-source': summoner_receipt},
        'observed-pre-hit-actions': [{k: v for k, v in r.items() if k != 'raw-payload-hex'} for r in actions],
        'quest-tooltip': {'text': tooltip, 'source': string_receipt},
        'target-buff-snapshot': snapshot,
        'prior-quest-reward-events': reward_events,
        'effect-review-still-open': [
            'Glacial Augment can reduce outgoing damage to allies; Blitzcrank has no learned immobilizing ability or observed cast, but this must remain explicit in the effect review.',
            'Unflinching requires a causal CC review; unchanged replicated armor alone does not establish server state.',
            'Generated ward-counter, Demolish-ready and Second Wind name hypotheses do not prove full buff behavior. Existing unmatched counters are preserved.',
            'Client stat continuity does not locate a server sampling instant; independent health closure alone does not prove packet amount semantics.'],
        'resolved-semantic-blockers': [SHIELD_GATE], 'remaining-semantic-blockers': remaining,
        'cumulative-resolved-semantic-blockers': sorted(first['resolved-semantic-blockers'] + [SHIELD_GATE]),
        'model-admissible': False, 'complete-buff-state': False,
        'inputs': {'first-review': digest(FIRST_REVIEW), 'witness': digest(witness_path),
            'match': digest(match_path), 'timeline': digest(timeline_path),
            'actions': digest(action_dir / 'summary.json'), 'buffs': digest(buff_dir / 'summary.json')},
        'reviewer-adapter-sha256': digest(__file__),
        'cost': {'wall-seconds': time.monotonic() - started, 'new-requests': 0, 'new-download-bytes': 0,
                 'scope': 'Retained-source review pass only; excludes development, tests and unmeasured manual review.'},
        'annotation': {'reason': 'Frozen first-hit shield eligibility reviewed against exact target-team loadouts, causal skill upgrades, observed spell prefix, quest context and retained matching-patch capabilities. Resolves shield-free context only, not nonzero shield/absorption mechanics; three gates remain.',
                       'changes': {'blockers': remaining}}}
    output.write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = review(args.base, args.output)
    print(json.dumps({k: result[k] for k in ('resolved-semantic-blockers', 'remaining-semantic-blockers', 'model-admissible')}))

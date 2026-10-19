"""Frozen case-specific review of the first indexed four-candidate batch.

This reviews declared mechanic eligibility, not arbitrary buff scripts. No model
prediction enters selection, health measurement checks or the review decisions.
New event IDs require a new review; these rules are not a generic auto-admitter.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import time

from replay_actions import PROFILE
from replay_conditional_compare import save_new
from replay_coverage import identity, require
from replay_evidence import EvidenceStore
from replay_first_hit_review import GAME
from replay_gaps import SEMANTIC_GAPS, elf32
from replay_native import NativeDecoder
from replay_recovery import digest, load

ROOT = Path(__file__).resolve().parents[1]
STUDY = ROOT / 'observations/replays/evidence-store-study-2026-10-18.json'
CASES = {'gameChunk:5:96537': ('Tristana', 'Janna', 'TristanaBasicAttack', 64),
         'gameChunk:6:400687': ('KSante', 'Sion', 'KSanteBasicAttack', 64),
         'gameChunk:10:2417': ('Sion', 'KSante', 'SionBasicAttack2', 65),
         'gameChunk:15:363291': ('Sion', 'KSante', 'SionBasicAttack3', 66)}
SCOPE = ('Conditional ordinary physical damage from reviewed observed scalars. '
         'Does not validate build-stat generation, complete attack/on-hit totals, '
         'shields, critical outcomes, penetration, exact server timing or sequences.')


def ulp(value):
    require(type(value) in (int, float) and math.isfinite(value) and 0 < value < 1e7,
            'Outside positive bounded float32 measurement domain')
    bits = struct.unpack('<I', struct.pack('<f', value))[0]
    return struct.unpack('<f', struct.pack('<I', bits + 1))[0] - struct.unpack('<f', struct.pack('<I', bits))[0]


def health_measurement(package):
    h = package['target-health-interval']
    require(h is not None, 'Missing health bracket')
    before, after = h['before']['value'], h['after']['value']
    amount = package['damage-outcome']['amount']
    delta = before - after
    bound = sum(ulp(v) / 2 for v in (before, after, amount))
    packets = h['damage-packets-between']
    isolated = len(packets) == 1 and packets[0]['event-id'] == package['event-id']
    return {'before': h['before'], 'after': h['after'], 'observed-health-loss': delta,
            'wire-damage': amount, 'residual': delta - amount, 'measurement-bound': bound,
            'isolated': isolated, 'nonlethal': 0 < after < before and amount < before,
            'closes': isolated and abs(delta - amount) <= bound,
            'other-damage-event-ids': [r['event-id'] for r in packets if r['event-id'] != package['event-id']],
            'policy': 'Sum of half float32 ULPs of health-before, health-after and packet; independent of model error.'}


def spell(data, name):
    found = [v for v in data.values() if isinstance(v, dict) and v.get('mScriptName') == name]
    require(len(found) == 1, 'Missing/ambiguous current-patch spell asset: ' + name)
    return found[0]


def value(data, name, field):
    rows = [r for r in spell(data, name)['mSpell']['DataValues'] if r['name'] == field]
    require(len(rows) == 1 and len(set(rows[0]['values'])) == 1, 'Unreviewed rank-varying timing')
    return rows[0]['values'][0]


def context_players(package):
    result = {}
    for entity, selection in package['api-context']['selections'].items():
        events = [r for r in package['api-context']['events-through-api-time']
                  if r.get('actors', {}).get('participantId') == int(entity)]
        result[selection['champion']] = {**selection, 'entity': int(entity),
            'skills': [r['skillSlot'] for r in events if r['type'] == 'SKILL_LEVEL_UP'],
            'item-events': [r for r in events if r['type'].startswith('ITEM_')]}
    require(len(result) == 10, 'Complete recorded roster selections required')
    return result


def inventory(events):
    result, unmatched = [], []
    for r in events:
        if r['type'] == 'ITEM_PURCHASED': result.append(r['itemId'])
        elif r['type'] in ('ITEM_DESTROYED', 'ITEM_SOLD'):
            if r['itemId'] in result: result.remove(r['itemId'])
            else: unmatched.append(r)
        elif r['type'] == 'ITEM_UNDO':
            require(r['afterId'] == 0 and r['beforeId'] in result, 'Unreviewed item undo')
            result.remove(r['beforeId'])
        else: raise ValueError('Unreviewed inventory mutation')
    return result, unmatched


def review_mechanics(package, store, assets, perks):
    c = package['case']; event = c['event-id']; t = c['timestamp']
    players = context_players(package)
    roster = package['observed-before-hit']
    source, target = (roster[str(c[r])] for r in ('source', 'target'))
    actions = store.history('action', event)
    casts = [r for r in actions if r['kind'] == 'spell-cast-announcement-candidate']
    def cast_rows(actor, name):
        return [r for r in casts if r['source'] == actor and r['effect-hash'] == elf32(name)]
    def last_cast(actor, name):
        rows = cast_rows(actor, name)
        return rows[-1]['timestamp'] if rows else None
    proof = {'source-inventory': inventory(players[source['champion']]['item-events']),
             'target-inventory': inventory(players[target['champion']]['item-events'])}
    if event == 'gameChunk:5:96537':
        require(players['Tristana']['skills'] == [] and not [r for r in casts if r['source'] == c['source']],
                'Tristana learned/cast ability outside frozen review')
        require(3 not in players['Janna']['skills'] and players['Ivern']['skills'] == [1],
                'Unreviewed ally shield capability')
        require(proof['source-inventory'] == ([1086, 2003, 2003, 3340], [])
                and proof['target-inventory'] == ([2003, 2003], []), 'Unreviewed early inventory')
        tempo = perks['Perks/Styles/Precision/LethalTempo']
        script = tempo['mScript']['mSpellScriptName']
        require(tempo['mScript']['mSpellScriptData']['mEffectAmount']['MaxStacks'] == 6, 'Lethal Tempo changed')
        rows = [r for r in store.history('buff', event, c['source']) if r['name-hash'] == elf32(script)]
        require([r['kind'] for r in rows] == ['add', 'counter'] and rows[1]['counter'] == 1,
                'Unreviewed Lethal Tempo activation')
        hp = package['target-health-interval']
        maximum = target['last-observed']['health-max']['value']
        require(min(hp['before']['value'], hp['after']['value']) > .4 * maximum,
                'Coup de Grace may be active')
        proof.update({'lethal-tempo-prefix': rows, 'lethal-tempo-max-stacks': 6,
            'coup-de-grace': 'Target remains above 40% health throughout the isolated bracket.',
            'shield-eligibility': 'Janna E and Ivern E/W unlearned; Sion W is self-only. Target has potions, no Barrier, and no shield-granting item/Guardian. Aery has no eligible ally shield cast.',
            'modifiers': 'No learned Tristana abilities; passive changes range. Lethal Tempo has one of six stacks, below its damage activation. Other source runes heal, grant gold or attack speed. Enemy team has no Glacial Augment.',
            'quest': 'No source-team Teleport or ally shield capability can shield Janna in this prefix.'})
    elif event == 'gameChunk:6:400687':
        require(players['KSante']['skills'] == [1, 2] and players['Ivern']['skills'] == [1],
                'Unreviewed learned ability')
        require(proof['source-inventory'] == ([1120, 2003, 3340], [])
                and proof['target-inventory'] == ([1036, 3340, 2031], []), 'Unreviewed early inventory')
        start, _ = store.before(package['action-outcome']['event-id'])
        for observed in (start.stats[str(c['source'])], source['last-observed']):
            require(observed['health']['value'] > .6 * observed['health-max']['value'], 'Last Stand may be active')
        recent = [r for r in store.history('damage', event, c['source'])
                  if r['target'] == c['target'] and r['timestamp'] >= t - 5]
        require(not recent, 'Recent damage could have applied the passive mark')
        duration = value(assets['Sion'], 'SionW', 'ShieldDuration')
        previous = last_cast(c['target'], 'SionW')
        require(duration == 6 and previous is not None and previous + duration < package['action-outcome']['timestamp'],
                'Sion self shield may remain active')
        janna = players['Janna']['entity']
        shield = cast_rows(janna, 'EyeOfTheStorm')
        recipients = [r for r in store.history('buff', event)
                      if r['kind'] == 'add' and r.get('caster') == janna
                      and r['name-hash'] == elf32('EyeOfTheStorm') and r['timestamp'] >= t - 4]
        require(len(shield) == 1 and len(recipients) == 1
                and recipients[0]['entity'] == players['Rengar']['entity']
                and recipients[0]['timestamp'] == shield[0]['timestamp'], 'Janna shield recipient unresolved')
        require(not cast_rows(c['target'], 'SummonerTeleport'), 'Target quest shield requires review')
        proof.update({'last-sion-shield-cast': previous, 'sion-shield-duration': duration,
            'janna-shield-recipient': recipients[0],
            'passive-mark': 'No K\'Sante damage to Sion in the previous five seconds; the current asset declares a four-second mark. Ordinary attack asset/slot rather than empowered passive asset.',
            'last-stand': 'Source remains above 60% health at announcement and before damage.',
            'shield-eligibility': 'Sion W expired; Janna E and its Aery shield target Rengar, not Sion; Ivern E/W unlearned. Source/target item prefixes and target summoners add no shield. No target Teleport cast.',
            'modifiers': 'All Out unlearned. Grasp supplies a separate magic component, not an ordinary physical multiplier; this isolated bracket contains only the selected physical packet. Target runes do not reduce incoming physical damage. Glacial owner Blitzcrank is on the source team.'})
    elif event == 'gameChunk:10:2417':
        require(proof['source-inventory'] == ([1036, 3340, 2031, 1083], [])
                and proof['target-inventory'] == ([1120, 2003, 3340, 1029, 1029], []), 'Unreviewed later inventory')
        require(4 not in players['KSante']['skills'], 'All Out requires review')
        start = package['action-outcome']['timestamp']
        timings = {}
        for name, field, expected in [('KSanteW', 'MaxDuration', 1.), ('KSanteE', 'ShieldDuration', 2.)]:
            duration = value(assets['KSante'], name, field)
            # Include all current asset variants of the relevant spell family.
            hashes = {elf32(v['mScriptName']) for v in assets['KSante'].values()
                      if isinstance(v, dict) and v.get('mScriptName', '').startswith(name)}
            rows = [r for r in casts if r['source'] == c['target'] and r['effect-hash'] in hashes]
            require(duration == expected and rows and rows[-1]['timestamp'] + duration + 1 < start,
                    'K\'Sante defensive window may remain active')
            timings[name] = {'last-cast': rows[-1]['timestamp'], 'duration': duration,
                             'extra-arrival-margin-seconds': 1}
        blitz = players['Blitzcrank']['entity']
        glacial = perks['Perks/Styles/Inspiration/GlacialAugment']
        require(glacial['mScript']['mSpellScriptData']['mEffectAmount']['SlowZoneDuration'] == 3
                and value(assets['Blitzcrank'], 'PowerFist', 'CCDuration') == 1, 'Glacial/CC timing changed')
        champions = {p['entity'] for p in store.manifest['roster']}
        damage = [r for r in store.history('damage', event, blitz) if r['target'] in champions and r['timestamp'] > t - 25]
        require([r['effect-hash'] for r in damage] == [elf32('PowerFistAttack'), elf32('BlitzcrankBasicAttack2')]
                and damage[0]['timestamp'] + 1 + 3 < start, 'Unreviewed Glacial trigger window')
        incoming = [r for r in store.history('damage', event) if r['target'] == c['target']
                    and r['source'] in champions and r['timestamp'] >= start - 5]
        exhaust = cast_rows(players['Rengar']['entity'], 'SummonerExhaust')
        require(value(assets['Shared'], 'SummonerExhaust', 'DebuffDuration') == 3, 'Exhaust duration changed')
        require(all(r['source'] == c['source'] and r['effect-hash'] == elf32('SionW') for r in incoming)
                and (not exhaust or exhaust[-1]['timestamp'] + 3 + 2 < start),
                'Recent CC/Exhaust could change conditional inputs')
        proof.update({'target-defensive-windows': timings, 'last-blitz-champion-damage': damage,
            'glacial': 'The only recent immobilizing Blitzcrank hit is Power Fist; one-second knockup plus three-second zone expired long before this attack. Subsequent basic attack is not an immobilizing asset.',
            'sampling': 'The only recent champion damage is Sion W, which supplies no CC. Rengar Exhaust ended long before the attack, including the two-second Unflinching extension. No new CC prerequisite; all eleven scalar inputs remain invariant through the attack.',
            'recent-target-champion-damage': incoming, 'last-rengar-exhaust': exhaust[-1]['timestamp'] if exhaust else None,
            'shield-eligibility': 'K\'Sante E expired before the attack; Diana/Yasuo/Blitzcrank shields and Tristana Barrier are self-only. No target-team Aery/Guardian or shield item. No recent target Teleport.',
            'modifiers': 'Normal Sion attack asset excludes death-passive attack. Source runes have no early physical multiplier. Cull heals source; other items only supply the observed stats. Ivern W is a separate magic component, not this physical packet. Conditional observed AD includes any ally AD; build-stat generation is not being validated.'})
    else:
        raise ValueError('No completed mechanic review for this case')
    return proof


def review(base, store_dir, batch_dir, output):
    started = time.monotonic()
    base, batch_dir = Path(base), Path(batch_dir)
    store = EvidenceStore(store_dir)
    try:
        study = load(STUDY)
        require(store.manifest['identity'] == study['store-identity'], 'Store differs from frozen selection')
        selected = {r['event-id']: r for r in study['batch']['records']}
        for label in ('audit', 'actions', 'buffs', 'outcomes'):
            summary = load(store.manifest['sources'][label + '/summary.json']['path'])
            for name, expected in summary['adapters'].items():
                require(Path(name).name == name and digest(ROOT / 'scripts' / name) == expected,
                        'Extraction adapter revision mismatch')
        assets, receipts = {}, []
        for filename in ('source-receipts.json', 'global-source-receipts.json'):
            for r in load(base / 'context-research' / filename):
                name = r['url'].rsplit('/', 1)[-1]
                name = 'items.json' if name == 'item.json' else name
                require('16.20' in r['url'] and digest(base / 'context-research' / name) == r['sha256'], 'Static source mismatch')
                receipts.append(r)
        for name in ('Sion', 'KSante'):
            assets[name] = load(base / 'context-research' / (name.lower() + '.bin.json'))
        for r in load(base / 'batch-review-research/receipts.json'):
            require(r['url'] == f"https://raw.communitydragon.org/16.20/game/data/characters/{r['file'][:-9]}/{r['file']}"
                    and digest(base / 'batch-review-research' / r['file']) == r['sha256'], 'New patch asset receipt mismatch')
            assets[{'tristana.bin.json': 'Tristana', 'blitzcrank.bin.json': 'Blitzcrank'}[r['file']]] = load(base / 'batch-review-research' / r['file'])
            receipts.append(r)
        perks = load(base / 'context-research/perks.cdtb.bin.json')
        assets['Shared'] = load(base / 'context-research/shared.cdtb.bin.json')
        r = load(base / 'outcome-research/summoner-16.20.1-receipt.json')
        require(digest(base / 'outcome-research/summoner-16.20.1.json') == r['sha256'], 'Summoner receipt mismatch')
        assets['Summoners'] = load(base / 'outcome-research/summoner-16.20.1.json')
        receipts.append(r)
        first = load(ROOT / 'observations/replays/first-hit-review-2026-10-18.json')
        for r in first['remaining-effect-review-inputs']['champions']:
            require(digest(base / 'outcome-research/kits-16.20.1' / (r['champion'] + '.json')) == r['source']['sha256'],
                    'Champion capability receipt mismatch')
            receipts.append(r['source'])
        match_path = store.manifest['sources']['api/match']['path']
        require(digest(match_path) == store.manifest['sources']['api/match']['sha256'], 'Game rules source mismatch')
        info = load(match_path)['info']
        require(info['mapId'] == 11 and info['gameMode'] == 'CLASSIC' and info['gameType'] == 'MATCHED_GAME'
                and info['gameVersion'] == store.manifest['client-build'], 'Unreviewed game rules')
        results = []
        native_decoder, native_checks = None, {}
        for event, (source, target, asset, slot) in CASES.items():
            path = batch_dir / (event.replace(':', '-') + '.json')
            require(digest(path) == selected[event]['package-file-sha256'], 'Package differs from frozen selection')
            p = load(path)
            require(identity(p) == identity(store.package(event)), 'Package differs from indexed evidence')
            c, native, action = p['case'], p['damage-outcome'], p['action-outcome']
            require(p['replay-sha256'] == GAME and c['damage-type'] == native['damage-type'] == 'physical'
                    and c['effect-kind'] == 'basic-attack-candidate' and p['attack-context']['status'] == 'unique-candidate'
                    and native['amount'] == c['recorded-amount'] > 0 and native['result-code'] == 5
                    and action['attack-slot'] == slot and action['auxiliary-cast-count'] == 0
                    and all(action[k] == c[k] == native[k] for k in ('source', 'target'))
                    and elf32(spell(assets[source], asset)['mScriptName']) == c['effect-hash'], 'Attack identity outside frozen scope')
            stats = p['recomputed-continuity']
            require(stats['observed-stable'] and stats['complete-observed-inputs'] and len(stats['fields']) == 11,
                    'Conditional inputs not invariant')
            scalar = {(r['role'], r['field']): r['before-action']['value'] for r in stats['fields']}
            require(all(scalar['source', n] == 0 for n in ('crit-chance', 'flat-armor-penetration', 'physical-lethality'))
                    and all(scalar['source', n] == 1 for n in ('armor-remaining-fraction', 'bonus-armor-remaining-fraction')),
                    'Outside noncritical zero-penetration scope')
            actors = {role: p['observed-before-hit'][str(c[role])] for role in ('source', 'target')}
            require(actors['source']['champion'] == source and actors['target']['champion'] == target, 'Roster binding mismatch')
            for actor in actors.values():
                require(actor['last-observed']['physical-damage-percentage-modifier']['value'] == 0, 'Unreviewed physical modifier')
            for name in ('shield-all-candidate', 'shield-physical-candidate'):
                require(actors['target']['last-observed'][name]['value'] == 0, 'Shield observation contradicts review')
            measurement = health_measurement(p)
            row = {'event-id': event, 'case': GAME + ':' + event, 'source': source, 'target': target,
                   'package-file-sha256': digest(path), 'evidence-sha256': p['evidence-sha256'],
                   'ordinary-attack-asset': asset, 'native-attack-slot': slot, 'native-result-code': 5,
                   'health-measurement': measurement, 'sampling-observations': stats,
                   'buff-metadata-complete': False, 'scope': SCOPE}
            if not measurement['closes'] or not measurement['nonlethal']:
                row.update({'ready-for-conditional-comparison': False,
                    'remaining-semantic-blockers': list(SEMANTIC_GAPS), 'resolved-semantic-blockers': [],
                    'reason': 'Multiple damage packets and nonclosing health bracket; healing/shield/timing overlap unresolved. No model execution or admission.'})
            else:
                # The original combat archive predates current field naming.
                # Recheck only referenced state packets with the exact current
                # native image; never replay the prefix or reread gzip archives.
                if native_decoder is None:
                    image = base / 'damage-research/LeagueofLegends-16.20-x64.macho'
                    combat = load(store.manifest['sources']['combat/summary.json']['path'])
                    require(digest(image) == combat['image-sha256'] and digest(PROFILE) == combat['profile-sha256'],
                            'Native recheck image/profile mismatch')
                    native_decoder = NativeDecoder(image, load(PROFILE))
                ids = {r['before-action']['event-id'] for r in stats['fields']}
                ids.update(measurement[k]['event-id'] for k in ('before', 'after'))
                ids.update(a['last-observed'][n]['event-id'] for a in actors.values()
                           for n in ('health-max', 'physical-damage-percentage-modifier'))
                for packet in sorted(ids):
                    if packet in native_checks: continue
                    update = store.event('state', packet)
                    decoded = native_decoder.state_buffer(bytes.fromhex(update['raw-payload-hex']))
                    require(decoded.hex() == update['decoded-buffer-hex'], 'Current native state recheck differs')
                    native_checks[packet] = {'event-id': packet, 'state-buffer-sha256': hashlib.sha256(decoded).hexdigest()}
                capacity = actors['target']['last-observed']['health-max']['value']
                updates = store.history('state', measurement['after']['event-id'], after=measurement['before']['event-id'])
                updates.append(store.event('state', measurement['after']['event-id']))
                require(all(r['fields'].get('health-max', capacity) == capacity for update in updates
                            for r in update['observations'] if r['entity'] == c['target']), 'Capacity changed in health bracket')
                row.update({'mechanic-review': review_mechanics(p, store, assets, perks),
                    'ready-for-conditional-comparison': True, 'remaining-semantic-blockers': [],
                    'resolved-semantic-blockers': sorted(SEMANTIC_GAPS),
                    'reason': 'Frozen case-specific asset, loadout, effect eligibility, isolated health metric and invariant conditional-input review; no model prediction used.'})
            results.append(row)
        report = {'format': 'powerspike-indexed-batch-conditional-review', 'version': 1,
                  'replay-sha256': GAME, 'client-build': store.manifest['client-build'], 'patch': '16.20.1',
                  'store-identity': store.manifest['identity'], 'selection-study-sha256': digest(STUDY),
                  'cases': results, 'sources': receipts,
                  'native-state-packets-rechecked': list(native_checks.values()),
                  'adapters': {n: digest(ROOT / 'scripts' / n) for n in ('replay_batch_review.py', 'replay_evidence.py',
                      'replay_conditional_compare.py', 'replay_gaps.py', 'replay_native.py', 'replay_state.py')},
                  'scope': SCOPE, 'model-comparisons': 0,
                  'cost': {'wall-seconds': time.monotonic() - started, 'raw-replay-reads': 0,
                           'source-archive-reads': 0, 'native-decode-calls': len(native_checks),
                           'scope': 'Review adapter execution only; manual investigation and static-source acquisition excluded.'}}
        save_new(output, report)
        return report
    finally:
        store.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('base', 'store', 'batch', 'output'): parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    r = review(args.base, args.store, args.batch, args.output)
    print(json.dumps({'ready': sum(c['ready-for-conditional-comparison'] for c in r['cases']),
                      'blocked': sum(not c['ready-for-conditional-comparison'] for c in r['cases'])}))

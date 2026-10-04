"""Import the complete pinned patch as explicitly unvalidated catalog data.

The core's curated snapshot is deliberately untouched. Retain source bytes/hashes,
derive ordinary stats only, and keep unknown/conditional effects as limitations.
Run once to fetch missing sources; --check re-derives locally without a network.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import html
import json
from pathlib import Path
import re
import time
import urllib.request

from jdn import dumps

ROOT = Path(__file__).resolve().parents[1] / 'data/16.19.1/catalog'
PATCH = '16.19.1'
STRUCTURED = {
    'FlatHPPoolMod': 'hp', 'FlatMPPoolMod': 'mp', 'FlatPhysicalDamageMod': 'ad',
    'FlatMagicDamageMod': 'ap', 'FlatArmorMod': 'armor', 'FlatSpellBlockMod': 'mr',
    'FlatMovementSpeedMod': 'move-speed', 'PercentMovementSpeedMod': 'move-speed-percent',
    'PercentAttackSpeedMod': 'attack-speed-bonus', 'FlatCritChanceMod': 'crit-chance',
}
BLOCK_FIELDS = {
    'Health': ('hp', 1), 'Mana': ('mp', 1), 'Attack Damage': ('ad', 1),
    'Ability Power': ('ap', 1), 'Armor': ('armor', 1), 'Magic Resist': ('mr', 1),
    'Ability Haste': ('ability-haste', 1), 'Lethality': ('armor-pen-flat', 1),
    'Magic Penetration': ('magic-pen-flat', 1),
    '% Magic Penetration': ('magic-pen-percent', .01),
    '% Armor Penetration': ('armor-pen-percent', .01),
    '% Attack Speed': ('attack-speed-bonus', .01),
    '% Critical Strike Chance': ('crit-chance', .01),
    '% Critical Strike Damage': ('crit-damage-bonus', .01),
    'Move Speed': ('move-speed', 1), '% Move Speed': ('move-speed-percent', .01),
    'Health Regen per 5 seconds': ('hp-regen', 1), 'Mana Regen per 5 seconds': ('mp-regen', 1),
}


def plain(value):
    return ' '.join(html.unescape(re.sub(r'<[^>]+>', ' ', value)).split())


def digest(data):
    return hashlib.sha256(data).hexdigest()


def retrieve(url):
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 Powerspike/1'})
            with urllib.request.urlopen(request, timeout=40) as response:
                return response.read()
        except OSError:
            if attempt == 2:
                raise
            time.sleep(.5 * (attempt + 1))


def character_source(champion):
    path = ROOT / 'sources/characters' / (champion['id'] + '.json')
    if path.exists():
        return json.loads(path.read_text())
    url = ('https://raw.communitydragon.org/16.19/game/data/characters/'
           + champion['id'].lower() + '/' + champion['id'].lower() + '.bin.json')
    # A fixed query also avoids stale CDN error responses for this pinned patch.
    raw = retrieve(url + '?powerspike=1')
    objects = json.loads(raw)
    roots = [(key, value) for key, value in objects.items()
             if isinstance(value, dict) and value.get('__type') == 'CharacterRecord'
             and key.endswith('/CharacterRecords/Root')]
    if len(roots) != 1:
        raise ValueError('Expected one current character root for ' + champion['id'])
    source = {'url': url, 'sha256': digest(raw), 'path': roots[0][0], 'record': roots[0][1]}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(source, indent=2) + '\n')
    return source


def normalize_champion(champion, source):
    record = source['record']
    fallbacks = []
    fallback_fields = {
        'attackSpeedPerLevelModifiable': ('attackspeedperlevel', 1),
        'hpRegenPerLevelModifiable': ('hpregenperlevel', .2),
        'baseStaticHPRegenModifiable': ('hpregen', .2),
        'damagePerLevelModifiable': ('attackdamageperlevel', 1),
        'armorPerLevelModifiable': ('armorperlevel', 1),
    }
    def field(key):
        if key not in record:
            source_key, scale = fallback_fields[key]
            fallbacks.append('Missing character field ' + key + '; using Data Dragon ' + source_key + '.')
            return round(champion['stats'][source_key] * scale, 6)
        value = record[key]
        return round(value['baseValue'] if isinstance(value, dict) else value, 6)
    base, growth = {}, {}
    for stat, first, per_level in [
        ('hp', 'baseHPModifiable', 'hpPerLevelModifiable'),
        ('ad', 'baseDamageModifiable', 'damagePerLevelModifiable'),
        ('armor', 'baseArmorModifiable', 'armorPerLevelModifiable'),
        ('mr', 'baseMR', 'mrPerLevel'),
        ('hp-regen', 'baseStaticHPRegenModifiable', 'hpRegenPerLevelModifiable'),
    ]:
        scale = 5 if stat == 'hp-regen' else 1
        base[stat], growth[stat] = round(field(first) * scale, 6), round(field(per_level) * scale, 6)
    base['move-speed'] = field('baseMoveSpeedModifiable')
    for stat, first, per_level in [('mp', 'mp', 'mpperlevel'), ('mp-regen', 'mpregen', 'mpregenperlevel')]:
        base[stat], growth[stat] = champion['stats'][first], champion['stats'][per_level]
    return {'patch': PATCH, 'id': champion['id'], 'name': champion['name'],
            'icon': champion['image']['full'].removesuffix('.png'),
            'title': champion['title'], 'tags': champion['tags'], 'resource': champion['partype'],
            'status': 'unvalidated', 'base': base, 'growth': growth,
            'attack-speed-base': field('attackSpeedModifiable'),
            'attack-speed-ratio': field('attackSpeedRatioModifiable'),
            'attack-speed-growth': field('attackSpeedPerLevelModifiable') / 100,
            'attack-speed-cap': 2.5, 'crit-damage': field('critDamageMultiplier'),
            'limitations': ['Ordinary basic attacks only; champion abilities, passives and special attack rules excluded.',
                            'Attack-speed cap 2.5, windup 30% and projectile travel zero are assumptions.'] + fallbacks}


def normalize_item(item_id, item):
    stats = {STRUCTURED[key]: value for key, value in item['stats'].items() if key in STRUCTURED}
    omitted = [key for key in item['stats'] if key not in STRUCTURED]
    # Data Dragon's flat HP regeneration is per second; the core uses per five seconds.
    if 'FlatHPRegenMod' in item['stats']:
        stats['hp-regen'] = item['stats']['FlatHPRegenMod'] * 5
        omitted.remove('FlatHPRegenMod')
    block = re.search(r'<stats>(.*?)</stats>', item['description'], re.S)
    unhandled = []
    if block:
        for line in re.split(r'<br\s*/?>', block[1]):
            text = plain(line)
            if not text:
                continue
            match = re.fullmatch(r'(\d+(?:\.\d+)?)\s*(%?)\s*(.+)', text)
            rule = BLOCK_FIELDS.get((('% ' if match[2] else '') + match[3]) if match else '')
            if rule:
                stats[rule[0]] = float(match[1]) * rule[1]
            else:
                unhandled.append(text)
    text = plain(item['description'])
    limitations = []
    remainder = re.sub(r'<stats>.*?</stats>', '', item['description'], flags=re.S)
    if plain(remainder):
        limitations.append('Passive and active effects excluded, except explicitly curated static modifiers.')
    if omitted:
        limitations.append('Unmodeled source stats: ' + ', '.join(omitted))
    if unhandled:
        limitations.append('Unmodeled stat lines: ' + '; '.join(unhandled))
    if not stats:
        limitations.append('No modeled permanent stats; this entry contributes no stats or effects.')
    maps = [int(key) for key, enabled in item['maps'].items() if enabled]
    return {'patch': PATCH, 'id': item_id, 'name': item['name'],
            'icon': item['image']['full'].removesuffix('.png'), 'status': 'unvalidated',
            'gold': item['gold']['total'], 'purchasable': item['gold']['purchasable'],
            'in-store': item.get('inStore', True), 'maps': maps,
            'tags': item['tags'], 'description': text, 'stats': stats,
            'supported': True, 'stackable': True, 'groups': [],
            'required-champion': item.get('requiredChampion', ''),
            'limitations': limitations, 'from': item.get('from', []), 'into': item.get('into', [])}


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument('--check', action='store_true', help='Verify retained hashes and reproducible normalization offline')
    options = args.parse_args()
    sources = ROOT / 'sources'
    pins = json.loads((ROOT.parent / 'manifest.json').read_text())['sources'][:2]
    data = []
    for name, pin in zip(['champions-ddragon.json', 'items-ddragon.json'], pins):
        path = sources / name
        if not path.exists() and not options.check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(retrieve(pin['url']))
        raw = path.read_bytes()
        if digest(raw) != pin['sha256']:
            raise ValueError('Full Data Dragon source hash mismatch: ' + name)
        obj = json.loads(raw)
        if obj['version'] != PATCH:
            raise ValueError('Unexpected patch: ' + name)
        data.append(obj['data'])
    champions, items = data
    if not options.check:
        with ThreadPoolExecutor(max_workers=8) as pool:
            futures = {pool.submit(character_source, champion): key for key, champion in champions.items()}
            for index, future in enumerate(as_completed(futures), 1):
                future.result()
                if index % 25 == 0 or index == len(futures):
                    print('Character records:', index, '/', len(futures), flush=True)
    normalized = {
        'patch': PATCH,
        'champions': [normalize_champion(champions[key], json.loads((sources / 'characters' / (key + '.json')).read_text())) for key in sorted(champions)],
        'items': [normalize_item(key, items[key]) for key in sorted(items, key=int)],
    }
    content = (dumps(normalized) + '\n').encode()
    path = ROOT / 'catalog.jdn'
    retained = [{'path': str(p.relative_to(ROOT)), 'sha256': digest(p.read_bytes())}
                for p in sorted(sources.rglob('*.json'))]
    manifest = {'patch': PATCH, 'communitydragon_patch': '16.19', 'status': 'unvalidated',
                'counts': {'champions': len(champions), 'items': len(items)},
                'sources': pins, 'retained': retained, 'catalog_sha256': digest(content),
                'scope': 'All catalog entries; permanent modeled stats and generic attacks only. No inferred champion kits or item procs.'}
    manifest_path = ROOT / 'manifest.json'
    if options.check:
        if path.read_bytes() != content or json.loads(manifest_path.read_text()) != manifest:
            raise ValueError('Catalog or provenance differs from retained source derivation')
        print('Full catalog hashes and normalization verified offline.')
    else:
        path.write_bytes(content)
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
        print('Imported', len(champions), 'champions and', len(items), 'items; all unvalidated.')


if __name__ == '__main__':
    main()

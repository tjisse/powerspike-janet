"""Verify retained provenance and compare normalized Janet data with source-derived facts."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from jdn import dumps

ROOT = Path(__file__).resolve().parents[1]
STAT_FIELDS = {
    'FlatHPPoolMod': 'hp', 'FlatMPPoolMod': 'mp', 'FlatPhysicalDamageMod': 'ad',
    'FlatMagicDamageMod': 'ap', 'FlatArmorMod': 'armor', 'FlatSpellBlockMod': 'mr',
    'FlatMovementSpeedMod': 'move-speed', 'PercentMovementSpeedMod': 'move-speed-percent',
    'PercentAttackSpeedMod': 'attack-speed-bonus', 'FlatCritChanceMod': 'crit-chance',
}


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def facts(data_root):
    manifest = load(data_root / 'manifest.json')
    for excerpt in manifest['retained_excerpts']:
        raw = (data_root / excerpt['path']).read_bytes()
        if hashlib.sha256(raw).hexdigest() != excerpt['sha256']:
            raise ValueError('retained source hash mismatch: ' + excerpt['path'])
    source_dir = data_root / 'sources'
    dragon = load(source_dir / 'champions-ddragon.json')
    champions = []
    for name in manifest['coverage']['champions']:
        root = load(source_dir / (name.lower() + '-character-record.json'))
        def field(key):
            value = root[key]
            return value['baseValue'] if isinstance(value, dict) else value
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
        base['move-speed'] = round(field('baseMoveSpeedModifiable'), 6)
        # Resource fields use named DDragon values, not unresolved record hashes.
        for stat, first, per_level in [('mp', 'mp', 'mpperlevel'), ('mp-regen', 'mpregen', 'mpregenperlevel')]:
            base[stat], growth[stat] = dragon[name]['stats'][first], dragon[name]['stats'][per_level]
        champions.append({
            'id': name, 'patch': dragon[name]['version'], 'base': base, 'growth': growth,
            'attack-speed-base': round(field('attackSpeedModifiable'), 6),
            'attack-speed-ratio': round(field('attackSpeedRatioModifiable'), 6),
            'attack-speed-growth': round(field('attackSpeedPerLevelModifiable'), 6) / 100,
            'crit-damage': field('critDamageMultiplier'),
        })
    annie = load(source_dir / 'annie-character-record.json')
    spells = load(source_dir / 'annie-q-w-spells.json')
    if set(spells) != set(annie['spells'][:2]):
        raise ValueError('retained Q/W objects do not match current champion references')
    abilities = []
    for path in annie['spells'][:2]:
        obj = spells[path]
        spell = obj['mSpell']
        values = {v['name']: v['values'] for v in spell['DataValues']}
        abilities.append({
            'id': obj['ObjectName'], 'source-path': path,
            'base-damage': values['BaseDamage'][1:6],
            'scalings': {'ap': round(values['APRatio'][1], 6)},
            'cost': spell['mana'][:5], 'cooldown': spell['cooldownTime'][:5],
            'cast-time': spell['spellCastTime'], 'missile-speed': spell['missileSpeed'],
        })
    r_spell = load(source_dir / 'annie-r-passive.json')
    r_path = annie['spells'][3]
    if set(r_spell) != {r_path}:
        raise ValueError('retained R object does not match current champion reference')
    r_values = next(v['values'] for v in r_spell[r_path]['mSpell']['DataValues'] if v['name'] == 'RPercentPenBuff')
    items = []
    for item_id, item in load(source_dir / 'items-ddragon.json').items():
        stats = {}
        for key, value in item['stats'].items():
            if key not in STAT_FIELDS:
                raise ValueError('unhandled structured item source stat: ' + key)
            stats[STAT_FIELDS[key]] = value
        # Limited, explicit patterns for this curated snapshot, not a general tooltip parser.
        text = re.sub(r'<[^>]+>', '', item['description'])
        patterns = [
            ('ability-haste', r'(\d+(?:\.\d+)?) Ability Haste', 1),
            ('armor-pen-flat', r'(\d+(?:\.\d+)?) Lethality', 1),
            ('magic-pen-percent', r'(\d+(?:\.\d+)?)% Magic Penetration', .01),
            ('magic-pen-flat', r'(\d+(?:\.\d+)?) Magic Penetration', 1),
            ('crit-damage-bonus', r'(\d+(?:\.\d+)?)% Critical Strike Damage', .01),
            ('ap-multiplier', r'Increases your total Ability Power by (\d+(?:\.\d+)?)%', .01),
        ]
        for key, pattern, scale in patterns:
            match = re.search(pattern, text)
            if match:
                stats[key] = float(match[1]) * scale + (1 if key == 'ap-multiplier' else 0)
        items.append({'id': item_id, 'name': item['name'], 'gold': item['gold']['total'],
                      'purchasable': item['gold']['purchasable'], 'stats': stats,
                      'maps': [int(key) for key, enabled in item['maps'].items() if enabled]})
    if {i['id'] for i in items} != set(manifest['coverage']['items']):
        raise ValueError('item source coverage does not match manifest')
    perks = {p['id']: p for p in load(source_dir / 'observed-perks.json')}
    shard_rules = {
        5005: ('attack-speed-bonus', r'\+(\d+(?:\.\d+)?)% Attack Speed', .01),
        5010: ('move-speed-percent', r'\+(\d+(?:\.\d+)?)% Move Speed', .01),
        5011: ('hp', r'\+(\d+(?:\.\d+)?) Health', 1),
    }
    shards = []
    for shard_id in manifest['coverage']['stat_shards']:
        key, pattern, scale = shard_rules[shard_id]
        text = re.sub(r'<[^>]+>', '', perks[shard_id]['longDesc'])
        match = re.fullmatch(pattern, text)
        if not match:
            raise ValueError('unrecognized retained stat shard description: ' + str(shard_id))
        shards.append({'id': shard_id, 'patch': manifest['patch'], 'stats': {key: float(match[1]) * scale}})
    return {'patch': manifest['patch'], 'champions': champions, 'items': items,
            'abilities': abilities, 'stat-shards': shards,
            'annie-r-penetration': [0] + [round(v, 6) for v in r_values[1:4]]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--janet', default=str(ROOT / 'build/janet'))
    args = parser.parse_args()
    evidence = facts(ROOT / 'data/16.19.1')
    with tempfile.TemporaryDirectory(prefix='powerspike-source-check-') as temp:
        path = Path(temp) / 'facts.jdn'
        path.write_text(dumps(evidence) + '\n', encoding='utf-8')
        subprocess.run([args.janet, str(ROOT / 'scripts/verify_snapshot.janet'), str(path)], cwd=ROOT, check=True)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print('Source verification failed: %s' % error, file=sys.stderr)
        sys.exit(1)

"""Read Riot's local API or import a saved response. Python 3, standard library only."""
import argparse
import datetime
import hashlib
import json
import math
from pathlib import Path
import ssl
import sys
import time
import urllib.error
import urllib.request

from jdn import dumps


SCALAR_FIELDS = {
    'attackDamage': 'ad', 'abilityPower': 'ap', 'maxHealth': 'hp',
    'armor': 'armor', 'magicResist': 'mr', 'attackSpeed': 'attack-speed',
    'moveSpeed': 'move-speed', 'abilityHaste': 'ability-haste',
    'magicPenetrationFlat': 'magic-pen-flat',
}
UNIT_FIELDS = {
    'critChance': ('crit-chance', {'fraction', 'percent'}),
    'critDamage': ('crit-damage', {'multiplier', 'percent'}),
    'armorPenetrationPercent': ('armor-pen-percent', {'fraction', 'percent', 'remaining-fraction'}),
    'magicPenetrationPercent': ('magic-pen-percent', {'fraction', 'percent', 'remaining-fraction'}),
}


def number(value, name):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError('%s must be a finite number' % name)
    return value


def validate_units(units):
    if not isinstance(units, dict):
        raise ValueError('unit mapping must be a JSON object')
    for field, unit in units.items():
        if field not in UNIT_FIELDS or not isinstance(unit, str) or unit not in UNIT_FIELDS[field][1]:
            raise ValueError('unsupported unit mapping: %s=%s' % (field, unit))


def active_player(data):
    active = data['activePlayer']
    for identity in ('riotId', 'summonerName'):
        value = active.get(identity)
        if value:
            matches = [p for p in data['allPlayers'] if p.get(identity) == value]
            if len(matches) == 1:
                return active, matches[0]
            if matches:
                raise ValueError('active player identity is ambiguous')
    raise ValueError('could not match active player to inventory/champion record')


def normalize(data, patch, client_build, units, source):
    validate_units(units)
    active, player = active_player(data)
    level = number(active['level'], 'level')
    if int(level) != level or not 1 <= level <= 18:
        raise ValueError('level must be an integer between 1 and 18')
    if player.get('level') != level:
        raise ValueError('active player and inventory record disagree on level; retry capture')
    raw_name = player.get('rawChampionName', '')
    prefix = 'game_character_displayname_'
    if not raw_name.startswith(prefix) or not raw_name[len(prefix):]:
        raise ValueError('missing canonical rawChampionName; do not infer an ID from translated text')
    ranks = {}
    for slot in ('Q', 'W', 'E', 'R'):
        rank = number(active['abilities'][slot]['abilityLevel'], slot + ' rank')
        if int(rank) != rank or not 0 <= rank <= (3 if slot == 'R' else 5):
            raise ValueError('invalid ability rank')
        ranks[slot.lower()] = int(rank)
    stats = active['championStats']
    observed = {target: number(stats[field], field)
                for field, target in SCALAR_FIELDS.items() if field in stats}
    unmapped = []
    for field, (target, _) in UNIT_FIELDS.items():
        if field not in stats or field not in units:
            unmapped.append(field)
            continue
        value = number(stats[field], field)
        unit = units[field]
        if unit == 'percent':
            value /= 100
        elif unit == 'remaining-fraction':
            value = 1 - value
        if target != 'crit-damage' and not 0 <= value <= 1:
            raise ValueError('%s is outside [0,1] after explicit unit conversion' % field)
        if target == 'crit-damage' and value < 1:
            raise ValueError('critical damage multiplier must be at least one')
        observed[target] = value
    if stats.get('resourceType') == 'MANA' and 'resourceMax' in stats:
        observed['mp'] = number(stats['resourceMax'], 'resourceMax')
    items, ignored = [], []
    for item in player['items']:
        numeric_id = number(item['itemID'], 'itemID')
        if int(numeric_id) != numeric_id or numeric_id <= 0:
            raise ValueError('itemID must be a positive integer')
        item_id = str(int(numeric_id))
        count = number(item.get('count', 1), 'item count')
        if int(count) != count or not 1 <= count <= 6:
            raise ValueError('item count must be an integer between 1 and 6 for this inventory model')
        if item.get('slot') == 6:
            ignored.append(item_id)  # Separate trinket slot; retained in raw JSON.
        else:
            items.extend([item_id] * int(count))
    runes = active.get('fullRunes', {})
    game = data['gameData']
    return {
        'schema-version': 1, 'source': source, 'patch': patch,
        'patch-origin': 'operator-declared', 'client-build': client_build,
        'champion': raw_name[len(prefix):], 'level': int(level), 'ranks': ranks,
        'item-ids': items, 'ignored-trinket-ids': ignored,
        'map-id': game.get('mapNumber'), 'game-mode': game.get('gameMode'),
        'game-time': game.get('gameTime'), 'is-dead': player.get('isDead'),
        'rune-ids': [r['id'] for r in runes.get('generalRunes', [])],
        'shard-ids': [r['id'] for r in runes.get('statRunes', [])],
        'field-units': units, 'unmapped-fields': unmapped, 'observed': observed,
        'context-reviewed': False, 'buffs': None, 'role-quest-state': None,
        'excluded-stats': [], 'notes': '',
        'tolerances': {'default': {'absolute': .01, 'relative': .00001},
                       'attack-speed': {'absolute': .00001, 'relative': .00001}},
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path, help='new directory for raw.json and observation.jdn')
    parser.add_argument('--patch', required=True, help='actual static-data build, e.g. 16.19.1; operator-declared')
    parser.add_argument('--client-build', required=True, help='actual client build/version, recorded separately')
    parser.add_argument('--units', type=Path, help='JSON mapping for explicitly checked crit/penetration units')
    parser.add_argument('--input', type=Path, help='import saved allgamedata JSON instead of contacting a game')
    parser.add_argument('--insecure-localhost', action='store_true', help='accept the local game certificate for this request only')
    parser.add_argument('--ca-file', type=Path, help='trusted Riot certificate file')
    args = parser.parse_args(argv)
    units = json.loads(args.units.read_text(encoding='utf-8')) if args.units else {}
    validate_units(units)
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    monotonic_start = time.monotonic()
    if args.input:
        raw = args.input.read_bytes()
        source = 'imported-api-response'
    else:
        context = ssl.create_default_context(cafile=str(args.ca_file) if args.ca_file else None)
        if args.insecure_localhost:
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
        # Fixed loopback endpoint, no proxy or redirects to another host.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *unused):
                return None
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}),
                    urllib.request.HTTPSHandler(context=context), NoRedirect())
        with opener.open('https://127.0.0.1:2999/liveclientdata/allgamedata', timeout=5) as response:
            raw = response.read()
        source = 'live-client-api'
    elapsed = time.monotonic() - monotonic_start
    record = normalize(json.loads(raw), args.patch, args.client_build, units, source)
    record.update({'collection-started-at': started, 'collection-seconds': elapsed,
                   'raw-sha256': hashlib.sha256(raw).hexdigest()})
    encoded = dumps(record) + '\n'
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / 'raw.json').write_bytes(raw)
    (args.output / 'observation.jdn').write_text(encoded, encoding='utf-8')
    print('Saved raw response and observation to %s' % args.output)
    print('Patch is operator-declared; context is unreviewed; %d fields await unit mapping.' % len(record['unmapped-fields']))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, urllib.error.URLError) as error:
        print('Capture failed: %s' % error, file=sys.stderr)
        sys.exit(1)

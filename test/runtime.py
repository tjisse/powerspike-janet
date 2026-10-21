"""Exercise only a copied executable in an empty directory, with no project files."""
import argparse
from contextlib import contextmanager
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.timeline = None
        self.scenario = None
        self.matchup = None
        self.assets = set()
        self.text = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get('id') == 'timeline':
            self.timeline = attrs
        if attrs.get('id') == 'scenario-data':
            self.scenario = attrs
        if 'data-matchup-result' in attrs:
            self.matchup = json.loads(attrs['data-matchup-result'])
        for name in ['href', 'src']:
            if attrs.get(name, '').startswith('/assets/'):
                self.assets.add(attrs[name])

    def handle_data(self, data):
        self.text.append(data)


def port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def clean_env(**settings):
    result = {key: value for key, value in os.environ.items()
              if not key.startswith(('JANET_', 'PS_'))}
    result.update(settings)
    return result


@contextmanager
def running(binary, cwd, args, env, chosen):
    with tempfile.TemporaryFile() as log:
        process = subprocess.Popen([str(binary), *args], cwd=cwd, env=env,
                                   stdout=log, stderr=log)
        base = 'http://127.0.0.1:' + str(chosen)
        try:
            # A cold RPM seed can contain thousands of icons. Allow its first
            # copy on a slower mounted filesystem without weakening HTTP checks.
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    log.seek(0)
                    raise AssertionError('Runtime exited: ' + log.read().decode(errors='replace'))
                try:
                    with urllib.request.urlopen(base + '/healthz', timeout=.2) as response:
                        assert response.read() == b'ok\n'
                    break
                except (OSError, urllib.error.URLError):
                    time.sleep(.05)
            else:
                log.seek(0)
                raise AssertionError('Runtime never became ready: ' + log.read().decode(errors='replace'))
            yield base
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def get(base, path, headers=None):
    with urllib.request.urlopen(urllib.request.Request(base + path, headers=headers or {}), timeout=10) as response:
        return response.headers, response.read()


def verify(binary_path, seed_path=None, parry_fixture=None, level_scaling_fixture=None, control_fixture=None, reset_fixture=None, resource_fixture=None, health_fixture=None, movement_fixture=None, changing_fixture=None, health_cost_fixture=None):
    source = Path(binary_path).resolve()
    seed_source = Path(seed_path or 'dist/share/powerspike/seed').resolve()
    with tempfile.TemporaryDirectory(prefix='powerspike-runtime-') as temp:
        cwd = Path(temp)
        binary = cwd / 'powerspike'
        shutil.copyfile(source, binary)
        binary.chmod(0o755)
        seed = cwd / 'seed'
        shutil.copytree(seed_source, seed)
        def configuration(**settings):
            return clean_env(PS_DATA_DIR=str(cwd / 'data'), PS_SEED_DIR=str(seed), **settings)
        version = subprocess.check_output([str(binary), '--version'], cwd=cwd, env=configuration(), text=True)
        assert version.startswith('PowerSpike ')
        help_text = subprocess.check_output([str(binary), '--help'], cwd=cwd, env=configuration(PS_PORT='invalid'), text=True)
        assert 'PS_PORT' in help_text
        for invalid in ['bad', '8090.5', '1023', '65536']:
            bad = subprocess.run([str(binary)], cwd=cwd, env=configuration(PS_PORT=invalid), capture_output=True, timeout=10)
            assert bad.returncode != 0 and b'1024' in bad.stderr, (invalid, bad.stderr)
        for invalid in ['invalid', '0', '1801']:
            bad = subprocess.run([str(binary)], cwd=cwd, env=configuration(PS_PATCH_TIMEOUT_SECONDS=invalid),
                                 capture_output=True, timeout=10)
            assert bad.returncode != 0 and b'PS_PATCH_TIMEOUT_SECONDS' in bad.stderr, (invalid, bad.stderr)
        if parry_fixture:
            # Load an old raw-source snapshot with the copied executable and no
            # checkout access. Cast-start defense and proc consumption must be
            # embedded in the runtime, rather than read from fixture files.
            with tempfile.TemporaryDirectory(prefix='parry-', dir=cwd) as check:
                check = Path(check)
                fixture = Path(parry_fixture).resolve()
                shutil.copytree(fixture / 'seed', check / 'seed')
                shutil.copyfile(fixture / 'scenario.json', check / 'scenario.json')
                env = clean_env(PS_SEED_DIR=str(check / 'seed'), PS_DATA_DIR=str(check / 'data'))
                outcome = json.loads(subprocess.check_output(
                    [str(binary), '--simulate', str(check / 'scenario.json')], cwd=check,
                    env=env, text=True, timeout=10))
                assert outcome['metrics']['damage'] == 0
                assert abs(outcome['actors'][1]['parry-until'] - .75) < 1e-6
                assert outcome['actors'][0]['buff-counts']['spellblade'] == 0
                assert any('return stab' in note for note in outcome['coverage'])
                assert sum(event['kind'] == 'parried' and event['source'] == 'item/3100/hit'
                           for event in outcome['trace']) == 1
        if level_scaling_fixture:
            # The synthetic carrier retains a real source formula and the old
            # linear AST. Its numerical repair must also be in the executable.
            with tempfile.TemporaryDirectory(prefix='level-scaling-', dir=cwd) as check:
                check = Path(check)
                fixture = Path(level_scaling_fixture).resolve()
                shutil.copytree(fixture / 'seed', check / 'seed')
                shutil.copyfile(fixture / 'scenario.json', check / 'scenario.json')
                env = clean_env(PS_SEED_DIR=str(check / 'seed'), PS_DATA_DIR=str(check / 'data'))
                outcome = json.loads(subprocess.check_output(
                    [str(binary), '--simulate', str(check / 'scenario.json')], cwd=check,
                    env=env, text=True, timeout=10))
                assert abs(outcome['metrics']['damage'] - 25.35) < 1e-6
        for label, fixture_path in (('control', control_fixture), ('reset', reset_fixture), ('resource', resource_fixture), ('health', health_fixture), ('movement', movement_fixture), ('changing', changing_fixture), ('health-cost', health_cost_fixture)):
            if not fixture_path:
                continue
            # Retained fixtures test the scheduler in a copied runtime.
            # Synthetic carriers explicitly label any invented mechanics.
            with tempfile.TemporaryDirectory(prefix=label+'-', dir=cwd) as check:
                check = Path(check)
                fixture = Path(fixture_path).resolve()
                shutil.copytree(fixture / 'seed', check / 'seed')
                document = json.loads((fixture / 'scenario.json').read_text())
                env = clean_env(PS_SEED_DIR=str(check / 'seed'), PS_DATA_DIR=str(check / 'data'))
                for reverse in (False, True):
                    if reverse:
                        a, b = document['scenario']['player'], document['scenario']['target']
                        document['scenario']['player'] = {key: value for key, value in b.items() if key != 'kind'}
                        document['scenario']['target'] = {**a, 'kind': 'champion'}
                    path = check / 'scenario.json'
                    path.write_text(json.dumps(document))
                    outcome = json.loads(subprocess.check_output([str(binary), '--simulate', str(path)],
                        cwd=check, env=env, text=True, timeout=10))
                    if label == 'control':
                        casts = [event for event in outcome['trace'] if event['kind'] == 'cast' and event['source'] == 'fixture-q']
                        assert len(casts) == 2
                        assert abs(casts[1]['at'] - (.013 + .437)) < 1e-6
                        assert outcome['actors'][int(reverse)]['damage-dealt'] == 20
                    elif label == 'reset':
                        starts = [event for event in outcome['trace'] if event['kind'] == 'attack']
                        hits = [event for event in outcome['trace'] if event['kind'] == 'damage' and event['source'] == 'attack']
                        assert len(starts) == len(hits) == 2
                        for event, expected in zip(starts, (.01, .337)):
                            assert abs(event['at'] - expected) < 1e-6
                        for event, expected in zip(hits, (.51, .837)):
                            assert abs(event['at'] - expected) < 1e-6
                        actor = outcome['actors'][int(reverse)]
                        assert abs(actor['damage-dealt'] - 2 * actor['stats']['ad']) < 1e-6
                    elif label == 'resource':
                        actor = outcome['actors'][int(reverse)]
                        ability = next(row for row in actor['abilities'] if row['id'] == 'AnnieQ')
                        cost = ability['cost']['values'][actor['ranks']['q'] + ability['cost']['offset']]
                        ready = (cost - .1 * actor['stats']['mp']) / (actor['stats']['mp-regen'] / 5)
                        casts = [event for event in outcome['trace'] if event['kind'] == 'cast' and event['source'] == 'AnnieQ']
                        hits = [event for event in outcome['trace'] if event['kind'] == 'damage' and event['source'] == 'AnnieQ']
                        assert len(casts) == len(hits) == 1
                        assert abs(casts[0]['at'] - ready) < 1e-6
                        assert abs(hits[0]['at'] - ready - ability['cast-time']) < 1e-6
                        assert actor['damage-dealt'] > 0 and actor['resource'] >= 0
                    elif label == 'health':
                        actor = outcome['actors'][int(reverse)]
                        ability = next(row for row in actor['abilities'] if row['id'] == 'AnnieQ')
                        shot = [event for event in outcome['trace'] if event['kind'] == 'damage' and event['source'] == 'attack']
                        casts = [event for event in outcome['trace'] if event['kind'] == 'cast' and event['source'] == 'AnnieQ']
                        hits = [event for event in outcome['trace'] if event['kind'] == 'damage' and event['source'] == 'AnnieQ']
                        assert len(shot) == len(casts) == len(hits) == 1
                        ready = actor['windup-fraction'] / actor['stats']['attack-speed'] + 200 / actor['attack-missile-speed']
                        assert abs(shot[0]['at'] - ready) < 1e-6
                        assert casts[0]['at'] == shot[0]['at']
                        assert abs(hits[0]['at'] - ready - ability['cast-time'] - 200 / ability['missile-speed']) < 1e-6
                        assert actor['damage-dealt'] > shot[0]['damage']
                    elif label == 'movement':
                        actor = outcome['actors'][int(reverse)]
                        ability = next(row for row in actor['abilities'] if row['id'] == 'AnnieQ')
                        ready = (700 - actor['attack-range']) / actor['stats']['move-speed']
                        casts = [event for event in outcome['trace'] if event['kind'] == 'cast' and event['source'] == 'AnnieQ']
                        hits = [event for event in outcome['trace'] if event['kind'] == 'damage' and event['source'] == 'AnnieQ']
                        assert len(casts) == len(hits) == 1
                        assert abs(casts[0]['at'] - ready) < 1e-6
                        assert abs(hits[0]['at'] - ready - ability['cast-time'] - actor['attack-range'] / ability['missile-speed']) < 1e-6
                        assert abs(actor['position'] - (625 if reverse else 75)) < 1e-6
                        assert actor['damage-dealt'] > 0
                    elif label == 'changing':
                        casts = [event for event in outcome['trace'] if event['kind'] == 'cast' and event['source'] == 'fixture-q']
                        hits = [event for event in outcome['trace'] if event['kind'] == 'damage' and event['source'] == 'fixture-q']
                        assert len(casts) == len(hits) == 1
                        assert abs(casts[0]['at'] - .487) < 1e-6
                        assert abs(hits[0]['at'] - (.487 + .04)) < 1e-6
                        assert outcome['actors'][int(reverse)]['damage-dealt'] == 10
                        assert outcome['unsupported'] == outcome['coverage']
                    else:
                        coefficient = .079999998211860657
                        actor = outcome['actors'][int(reverse)]
                        casts = [event for event in outcome['trace'] if event['kind'] == 'cast' and event['source'] == 'fixture-health']
                        hits = [event for event in outcome['trace'] if event['kind'] == 'damage' and event['source'] == 'fixture-health']
                        assert len(casts) == len(hits) == 1
                        ready = (1 / (1 - coefficient) - 1) / (actor['stats']['hp-regen'] / 5)
                        assert abs(casts[0]['at'] - ready) < 1e-6
                        assert abs(hits[0]['at'] - ready - .25) < 1e-6
                        assert abs(casts[0]['cost'] - coefficient * casts[0]['before'][int(reverse)]['health']) < 1e-6
                        assert casts[0]['participants'][int(reverse)]['health'] >= 1
                        assert actor['damage-dealt'] == 1
                        assert outcome['unsupported'] == outcome['coverage']
        chosen = port()
        with running(binary, cwd, [], configuration(PS_PORT=str(chosen), PS_HOST='127.0.0.1'), chosen) as base:
            _, verification_raw = get(base, '/api/verification')
            verification = json.loads(verification_raw)
            assert verification['format'] == 'powerspike-verification-progress'
            assert verification['pipeline']['events'] >= verification['pipeline']['admitted']
            _, verification_page = get(base, '/verification')
            assert verification_page.startswith(b'<!doctype html>') and b'Verification progress' in verification_page
            retained = next(path.name for path in (seed / '16.19.1').iterdir() if path.is_dir() and len(path.name) == 64)
            for kind, count in [('items', 870), ('champions', 173)]:
                catalog_headers, catalog_bytes = get(base, '/catalog?'+urllib.parse.urlencode(
                    {'kind': kind, 'patch': '16.19.1', 'snapshot': retained}))
                catalog = json.loads(catalog_bytes)
                assert catalog_headers['Content-Type'] == 'application/json'
                assert catalog['snapshot'] == retained and catalog['kind'] == kind
                assert len(catalog['records']) == count and len(catalog_bytes) < 1024*1024
            _, matchup_raw = get(base, '/?' + urllib.parse.urlencode({'snapshot': retained}))
            assert len(matchup_raw) < 1024*1024, 'Initial retained matchup embedded a full catalog again.'
            matchup = Page()
            matchup.feed(matchup_raw.decode())
            assert matchup.matchup['names'] == ['Annie', 'Garen']
            assert {event['actor'] for event in matchup.matchup['trace'] if event['kind'] == 'damage'} == {'player', 'opponent'}
            assert b'name="armor"' not in matchup_raw
            assert b'Optimize items' in matchup_raw and '/assets/matchup.js' in matchup.assets
            headers, raw = get(base, '/?' + urllib.parse.urlencode({'mode': 'practice', 'snapshot': retained}))
            assert headers['Content-Type'].startswith('text/html')
            page = Page()
            page.feed(raw.decode())
            events = json.loads(page.timeline['data-events'])
            assert {'AnnieQ', 'AnnieW', 'attack'} <= {event['source'] for event in events}
            # Annie's retained 625-unit range avoids the old melee approach at
            # 300 distance. Three attacks arrive within five seconds alongside
            # two Qs and one W; the fourth projectile arrives after the window.
            attacks = [event for event in events if event['source'] == 'attack']
            assert len(attacks) == 3
            assert abs(attacks[0]['at'] - (.5 + .3 / .7545 + 300 / 1500)) < 1e-6
            expected_damage = (2 * 494 + 464) / 1.264 + 3 * 95.05 / 1.8
            assert abs(float(page.timeline['data-total']) - expected_damage) < 1e-6
            initial_scenario = json.loads(page.scenario['data-json'])['scenario']
            _, ready_raw = get(base, '/?' + urllib.parse.urlencode({
                'mode': 'practice', 'champion': 'Annie', 'selected': 'custom', 'slot1': '3158',
                'level': 1, 'attacks': 'false', 'abilities': 'true', 'movement': 'hold',
                'distance': 300, 'duration': 12, 'snapshot': initial_scenario['snapshot'], 'snapshotlocked': 'true'}))
            ready_page = Page()
            ready_page.feed(ready_raw.decode())
            ready_file = cwd / 'ability-readiness.json'
            ready_file.write_text(ready_page.scenario['data-json'])
            ready_result = json.loads(subprocess.check_output([str(binary), '--simulate', str(ready_file)],
                cwd=cwd, env=configuration(), text=True, timeout=10))
            haste = ready_result['actors'][0]['stats']['ability-haste']
            assert haste > 0
            ready_casts = [event for event in ready_result['trace'] if event['kind'] == 'cast' and event['source'] == 'AnnieQ']
            assert len(ready_casts) == 4
            for index, event in enumerate(ready_casts):
                assert abs(event['at'] - index * 4 / (1 + haste / 100)) < 1e-6
            ready_file.unlink()
            assert initial_scenario['target']['hp'] == 2500
            assert '173 champions' in ''.join(page.text) and '870 items' in ''.join(page.text)
            # Bundled rune/shard sources and champion adaptive preferences must
            # work when the executable has no access to the project directory.
            _, rune_raw = get(base, '/?' + urllib.parse.urlencode({
                'mode': 'practice', 'champion': 'Annie', 'selected': 'custom', 'level': 6, 'snapshot': retained,
                'shards': '5008,5008,5011', 'runes': '8210,8237'}))
            rune_page = Page()
            rune_page.feed(rune_raw.decode())
            rune_document = json.loads(rune_page.scenario['data-json'])
            assert rune_document['scenario']['player']['loadout']['shards'] == [5008,5008,5011]
            rune_input = cwd / 'runes.json'
            rune_input.write_text(json.dumps(rune_document))
            rune_result = json.loads(subprocess.check_output(
                [str(binary), '--simulate', str(rune_input)], cwd=cwd, env=configuration(), text=True, timeout=10))
            assert abs(rune_result['metrics']['damage'] - float(rune_page.timeline['data-total'])) < 1e-6
            rune_input.unlink()
            # The relocated binary repairs old seed caps without modifying its
            # retained snapshot, and exports the same capped fight used by CLI.
            fast_fields = {'mode':'practice', 'champion':'Gnar', 'form':'mini', 'selected':'custom',
                           'level':18, 'duration':1.2, 'samples':1, 'seed':7, 'abilities':'false',
                           'movement':'hold', 'distance':0, 'targethealth':1000000,
                           'snapshot':retained, 'snapshotlocked':'true'}
            fast_fields.update({f'slot{index}':item for index,item in enumerate(['3046','3115','3091','3032','2512','6675'],1)})
            _, fast_raw = get(base, '/?'+urllib.parse.urlencode(fast_fields))
            fast_page = Page()
            fast_page.feed(fast_raw.decode())
            fast_file = cwd/'attack-limit.json'
            fast_file.write_text(fast_page.scenario['data-json'])
            fast_result = json.loads(subprocess.check_output([str(binary), '--simulate', str(fast_file)],
                cwd=cwd, env=configuration(), text=True, timeout=10))
            assert fast_result['actors'][0]['attack-speed-cap'] == 3
            assert fast_result['actors'][0]['stats']['attack-speed'] == 3
            assert fast_result['actors'][0]['stats']['attack-speed-uncapped'] > 3
            fast_hits = [event for event in fast_result['events'] if event['source']=='attack']
            assert len(fast_hits) == 4
            for index,event in enumerate(fast_hits):
                assert abs(event['at']-(.3/3+index/3)) < 1e-6
            assert abs(fast_result['metrics']['damage']-float(fast_page.timeline['data-total'])) < 1e-6
            fast_file.unlink()
            for path in ['/assets/champion/Ahri.png', '/assets/champion/MonkeyKing.png',
                         '/assets/item/222051.png', '/assets/spell/AnnieQ.png']:
                headers, image = get(base, path)
                assert headers['Content-Type'] == 'image/png' and image.startswith(b'\x89PNG')
            for path in ['/assets/app.css', '/assets/app.js', '/assets/hud.js', '/assets/matchup.js', '/assets/datastar.js']:
                _, content = get(base, path)
                assert len(content) > 100
            # Pin the retained seed for this offline basic-attack regression.
            # Automatic download/navigation is covered separately; it must not
            # race the packaged scenario checks or depend on provider timing.
            _, raw = get(base, '/?' + urllib.parse.urlencode({
                'mode': 'practice', 'champion': 'Ahri', 'selected': 'custom', 'slot1': '3031',
                'level': 1, 'abilities': 'false', 'movement': 'hold', 'distance': 350,
                'armor': 97, 'snapshot': initial_scenario['snapshot']}))
            ahri = Page()
            ahri.feed(raw.decode())
            ahri_events = json.loads(ahri.timeline['data-events'])
            assert ahri_events and all(event['source'] == 'attack' for event in ahri_events)
            # Baseline range permits attacks while holding at 350 units. The
            # bundled projectile profile delays impact without source-tree IO.
            assert abs(ahri_events[0]['at'] - (.2 / .668 + 350 / 1750)) < 1e-6
            for index, event in enumerate(ahri_events):
                assert abs(event['at'] - ((index + .2) / .668 + 350 / 1750)) < 1e-6
            assert ahri.timeline['data-label'] == 'Basic attacks over time'
            assert b'location.assign(next)' not in raw
            _, viktor_raw = get(base, '/?' + urllib.parse.urlencode({
                'mode': 'practice', 'champion': 'Viktor', 'selected': 'custom',
                'level': 1, 'abilities': 'false', 'movement': 'hold', 'distance': 500,
                'snapshot': initial_scenario['snapshot']}))
            viktor = Page()
            viktor.feed(viktor_raw.decode())
            viktor_events = json.loads(viktor.timeline['data-events'])
            assert viktor_events and all(event['source'] == 'attack' for event in viktor_events)
            assert abs(viktor_events[0]['at'] - (.3 / .658 + 500 / 2300)) < 1e-6
            for index, event in enumerate(viktor_events):
                assert abs(event['at'] - ((index + .3) / .658 + 500 / 2300)) < 1e-6
            # The packed model must retain attack identities when loading both
            # current seeds and older snapshots with no attack-style field.
            for champion, level, ranged, attack_range in [
                    ('Lillia', 1, False, 325), ('Ahri', 1, True, 550), ('Elise', 1, None, 550),
                    ('Kayle', 1, False, 175), ('Kayle', 5, False, 175), ('Kayle', 6, True, 525),
                    ('Kayle', 15, True, 525), ('Kayle', 16, True, 625), ('Kayle', 18, True, 625)]:
                _, identity_raw = get(base, '/?' + urllib.parse.urlencode({
                    'mode': 'practice', 'champion': champion, 'selected': 'custom',
                    'slot1': '3153', 'level': level, 'abilities': 'false', 'movement': 'hold',
                    'distance': attack_range, 'duration': 1, 'snapshot': initial_scenario['snapshot']}))
                identity_page = Page()
                identity_page.feed(identity_raw.decode())
                identity_file = cwd / 'attack-identity.json'
                identity_file.write_text(identity_page.scenario['data-json'])
                identity_result = json.loads(subprocess.check_output(
                    [str(binary), '--simulate', str(identity_file)], cwd=cwd,
                    env=configuration(), text=True, timeout=10))
                assert identity_result['actors'][0].get('ranged') is ranged
                assert identity_result['actors'][0]['attack-range'] == attack_range
                assert identity_result['actors'][0]['stats']['attack-range'] == attack_range
                assert any(event['source'] == 'attack' for event in identity_result['events'])
                if ranged is None:
                    assert any("Mist's Edge on-hit damage is excluded" in note
                               for note in identity_result['coverage'])
                    assert not any(event['source'] == 'item/3153/mist'
                                   for event in identity_result['events'])
                identity_file.unlink()
            for champion, form, level, ranged, attack_range in [('Nidalee', 'human', 1, True, 525), ('Nidalee', 'cougar', 1, False, 125),
                                                               ('Jayce', 'hammer', 1, False, 125), ('Jayce', 'cannon', 1, True, 500),
                                                               ('Jayce', 'hammer', 6, False, 125), ('Jayce', 'hammer', 11, False, 125),
                                                               ('Jayce', 'hammer', 16, False, 125),
                                                               ('Elise', 'human', 1, True, 550), ('Elise', 'spider', 1, False, 125),
                                                               ('Elise', 'spider', 6, False, 125), ('Elise', 'spider', 11, False, 125),
                                                               ('Elise', 'spider', 16, False, 125),
                                                               ('Gnar', 'mini', 1, True, 400), ('Gnar', 'mega', 1, False, 175),
                                                               ('Gnar', 'mini', 15, True, 400 + 1400 / 17),
                                                               ('Gnar', 'mini', 16, True, 400 + 1500 / 17),
                                                               ('Gnar', 'mini', 18, True, 500), ('Gnar', 'mega', 18, False, 175)]:
                _, form_raw = get(base, '/?' + urllib.parse.urlencode({
                    'mode': 'practice', 'champion': champion, 'form': form, 'selected': 'custom',
                    'level': level, 'abilities': 'false', 'movement': 'hold', 'distance': attack_range,
                    'duration': 1, 'healthfraction': .5, 'snapshot': initial_scenario['snapshot']}))
                form_page = Page()
                form_page.feed(form_raw.decode())
                form_file = cwd / 'attack-form.json'
                form_file.write_text(form_page.scenario['data-json'])
                assert json.loads(form_page.scenario['data-json'])['scenario']['player']['form'] == form
                form_result = json.loads(subprocess.check_output(
                    [str(binary), '--simulate', str(form_file)], cwd=cwd,
                    env=configuration(), text=True, timeout=10))
                assert form_result['actors'][0]['form'] == form
                assert form_result['actors'][0]['ranged'] is ranged
                assert form_result['actors'][0]['attack-range'] == attack_range
                if champion in ('Nidalee', 'Elise', 'Jayce'):
                    actor = form_result['actors'][0]
                    speed = {'Nidalee': 2500, 'Elise': 1600, 'Jayce': 2000}[champion] if form in ('human', 'cannon') else 0
                    assert actor['attack-missile-speed'] == speed
                    first = next(event for event in form_result['events'] if event['source'] == 'attack')
                    expected = .3 / actor['stats']['attack-speed'] + (attack_range / speed if speed else 0)
                    assert abs(first['at'] - expected) < 1e-6
                if champion == 'Jayce':
                    # The source adds 7 Hammer armor/MR at levels 6, 11 and 16.
                    for stat in ('armor', 'mr'):
                        actor = form_result['actors'][0]
                        assert abs(actor['stats'][stat] - actor['base'][stat] - (5 + 7 * ((level - 1) // 5) if form == 'hammer' else 0)) < 1e-6
                if champion == 'Elise':
                    assert form_result['actors'][0]['stats']['move-speed'] == (355 if form == 'spider' else 330)
                    passive = [event for event in form_result['events'] if event['source'] == 'EliseSpiderQueen']
                    healing = [event for event in form_result['trace'] if event.get('source') == 'EliseSpiderQueenHeal']
                    if form == 'spider':
                        rank = 1 + (level >= 6) + (level >= 11) + (level >= 16)
                        assert len(passive) == len(healing) == 1
                        assert abs(passive[0]['raw'] - (4 + 10 * rank)) < 1e-6
                        assert abs(healing[0]['amount'] - (4 + 2 * rank)) < 1e-6
                        assert b'Spider Queen' in form_raw
                        assert b'Additional R points (free first rank included)' in form_raw
                    else:
                        assert not passive and not healing
                if champion == 'Gnar':
                    actor = form_result['actors'][0]
                    n = level - 1
                    factor = .7025 * n + .0175 * n * n
                    mega = form == 'mega'
                    for stat, base_stat, growth in ([('hp', 640, 122), ('ad', 66, 5.7), ('armor', 35.5, 6.7), ('mr', 33.5, 4.8)] if mega else
                                                    [('hp', 540, 79), ('ad', 60, 3.2), ('armor', 32, 3.7), ('mr', 30, 1.3)]):
                        assert abs(actor['stats'][stat] - base_stat - growth * factor) < 1e-4
                        assert abs(actor['base'][stat] - actor['stats'][stat]) < 1e-6
                    expected_ms = 335 if mega else 335 + (n if level <= 15 else {16:16,17:18,18:20}[level])
                    assert actor['stats']['move-speed'] == expected_ms
                    assert abs(actor['stats']['attack-speed'] - .625 * (1 + (.005 if mega else .06) * factor)) < 1e-6
                    assert b'Rage, automatic transformations' in form_raw
                assert any(event['source'] == 'attack' for event in form_result['events'])
                form_file.unlink()
            signals = {'champion': 'Annie', 'selected': 'custom', 'slot1': '3089', 'duration': 6.5, 'mr': 97}
            path = '/evaluate?' + urllib.parse.urlencode({'datastar': json.dumps(signals)})
            headers, body = get(base, path, {'Datastar-Request': 'true', 'Accept': 'text/event-stream'})
            assert headers['Content-Type'].startswith('text/event-stream')
            assert b'datastar-patch-elements' in body and b'id="results"' in body and b'data-duration="6.5"' in body
            assert b'id="scenario-data"' in body
            assert b'id="verification-progress"' not in body and b'id="source-evidence"' not in body
            _, developer = get(base, '/developer')
            assert b'Developer tools' in developer and b'Snapshot SHA-256' in developer
            assert b'id="verification-progress"' in developer and b'selected patch differs' in developer
            # The packaged commands consume the same versioned document as the UI.
            scenario_page = Page()
            scenario_page.feed(body.decode())
            document = scenario_page.scenario['data-json']
            input_file = cwd / 'scenario.json'
            input_file.write_text(document)
            outcome = json.loads(subprocess.check_output([str(binary), '--simulate', str(input_file)], cwd=cwd,
                                env=configuration(), text=True, timeout=10))
            assert outcome['scenario']['snapshot'] == json.loads(document)['scenario']['snapshot']
            search_file = cwd / 'search.json'
            search_file.write_text(json.dumps({'format':'powerspike-optimization','version':1,
                'scenario-document':json.loads(document),'constraints':{'searchpool':'Amplifying Tome',
                'searchbudget':400,'searchslots':1,'searchseconds':5}}))
            searched = json.loads(subprocess.check_output([str(binary), '--optimize', str(search_file)], cwd=cwd,
                                env=configuration(), text=True, timeout=10))
            assert searched['complete'] and searched['rows'][0]['ids'] == ['1052']
            calibration_file = cwd / 'calibration.json'
            calibration_file.write_text(json.dumps({'format':'powerspike-calibration','version':1,'family':'isolated-damage'}))
            checked = json.loads(subprocess.check_output([str(binary), '--calibrate', str(calibration_file)], cwd=cwd,
                                env=configuration(), text=True, timeout=10))
            assert checked['status'] == 'unmeasured' and not checked['checked']
            for fixture in (input_file, search_file, calibration_file):
                fixture.unlink()
            # A client disappearing midway through SSE must not kill the service.
            with socket.create_connection(('127.0.0.1', chosen)) as sock:
                sock.sendall(('GET ' + path + ' HTTP/1.1\r\nHost: localhost\r\nDatastar-Request: true\r\n\r\n').encode())
            get(base, '/healthz')
        # CLI port overrides even an invalid environment value at runtime.
        chosen = port()
        progress_file = cwd / 'data' / 'verification.json'
        progress_file.write_text(json.dumps(verification))
        with running(binary, cwd, ['--port', str(chosen)], configuration(
                PS_PORT='invalid', PS_VERIFICATION_REPORT=str(progress_file)), chosen) as base:
            get(base, '/healthz')
            verification['generated-at'] = 'runtime-reload-regression'
            progress_file.write_text(json.dumps(verification))
            assert json.loads(get(base, '/api/verification')[1])['generated-at'] == 'runtime-reload-regression'
            progress_file.write_text('{invalid report')
            try:
                get(base, '/api/verification')
            except urllib.error.HTTPError as error:
                assert error.code == 503
                assert json.loads(error.read()) == {'error': 'Verification report unavailable.'}
            else:
                raise AssertionError('Malformed override must not silently fall back to old evidence')
            assert b'Verification report unavailable' in get(base, '/verification')[1]
        assert set(cwd.iterdir()) == {binary, seed, cwd / 'data'}, 'Runtime wrote outside its data directory'
    print('Relocated executable: runtime config, catalog/art/assets, Q/W, control/reset timings, SSE, verification snapshot/reload and failure checks passed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary')
    parser.add_argument('--parry-fixture')
    parser.add_argument('--level-scaling-fixture')
    parser.add_argument('--control-fixture')
    parser.add_argument('--reset-fixture')
    parser.add_argument('--resource-fixture')
    parser.add_argument('--health-fixture')
    parser.add_argument('--movement-fixture')
    parser.add_argument('--changing-fixture')
    parser.add_argument('--health-cost-fixture')
    args = parser.parse_args()
    verify(args.binary, parry_fixture=args.parry_fixture, level_scaling_fixture=args.level_scaling_fixture,
           control_fixture=args.control_fixture, reset_fixture=args.reset_fixture, resource_fixture=args.resource_fixture,
           health_fixture=args.health_fixture, movement_fixture=args.movement_fixture, changing_fixture=args.changing_fixture,
           health_cost_fixture=args.health_cost_fixture)

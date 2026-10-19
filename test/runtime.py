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


def verify(binary_path, seed_path=None):
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
        chosen = port()
        with running(binary, cwd, [], configuration(PS_PORT=str(chosen), PS_HOST='127.0.0.1'), chosen) as base:
            _, verification_raw = get(base, '/api/verification')
            verification = json.loads(verification_raw)
            assert verification['format'] == 'powerspike-verification-progress'
            assert verification['pipeline']['events'] >= verification['pipeline']['admitted']
            _, verification_page = get(base, '/verification')
            assert verification_page.startswith(b'<!doctype html>') and b'Verification progress' in verification_page
            retained = next(path.name for path in (seed / '16.19.1').iterdir() if path.is_dir() and len(path.name) == 64)
            _, matchup_raw = get(base, '/?' + urllib.parse.urlencode({'snapshot': retained}))
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
            # The packed model must retain attack identities when loading both
            # current seeds and older snapshots with no attack-style field.
            for champion, ranged in [('Lillia', False), ('Ahri', True), ('Elise', None), ('Kayle', None)]:
                _, identity_raw = get(base, '/?' + urllib.parse.urlencode({
                    'mode': 'practice', 'champion': champion, 'selected': 'custom',
                    'slot1': '3153', 'level': 1, 'abilities': 'false', 'movement': 'hold',
                    'distance': 0, 'duration': 1, 'snapshot': initial_scenario['snapshot']}))
                identity_page = Page()
                identity_page.feed(identity_raw.decode())
                identity_file = cwd / 'attack-identity.json'
                identity_file.write_text(identity_page.scenario['data-json'])
                identity_result = json.loads(subprocess.check_output(
                    [str(binary), '--simulate', str(identity_file)], cwd=cwd,
                    env=configuration(), text=True, timeout=10))
                assert identity_result['actors'][0].get('ranged') is ranged
                if ranged is None:
                    assert any("Mist's Edge on-hit damage is excluded" in note
                               for note in identity_result['coverage'])
                    assert not any(event['source'] == 'item/3153/mist'
                                   for event in identity_result['events'])
                identity_file.unlink()
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
    print('Relocated executable: runtime config, catalog/art/assets, Q/W, SSE, verification snapshot/reload and failure checks passed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary')
    verify(parser.parse_args().binary)

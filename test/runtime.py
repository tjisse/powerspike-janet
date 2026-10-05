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
        self.assets = set()
        self.text = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get('id') == 'timeline':
            self.timeline = attrs
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
            for _ in range(100):
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
                raise AssertionError('Runtime never became ready')
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
            headers, raw = get(base, '/')
            assert headers['Content-Type'].startswith('text/html')
            page = Page()
            page.feed(raw.decode())
            events = json.loads(page.timeline['data-events'])
            assert {'AnnieQ', 'AnnieW', 'attack'} <= {event['source'] for event in events}
            assert abs(float(page.timeline['data-total']) - 1307.15084388186) < 1e-6
            assert '173 champions' in ''.join(page.text) and '870 items' in ''.join(page.text)
            for path in ['/assets/champion/Ahri.png', '/assets/champion/MonkeyKing.png',
                         '/assets/item/222051.png', '/assets/spell/AnnieQ.png']:
                headers, image = get(base, path)
                assert headers['Content-Type'] == 'image/png' and image.startswith(b'\x89PNG')
            for path in ['/assets/app.css', '/assets/app.js', '/assets/datastar.js']:
                _, content = get(base, path)
                assert len(content) > 100
            _, raw = get(base, '/?champion=Ahri&selected=custom&slot1=3031&armor=97')
            ahri = Page()
            ahri.feed(raw.decode())
            assert all(event['source'] == 'attack' for event in json.loads(ahri.timeline['data-events']))
            assert ahri.timeline['data-label'] == 'Basic attacks over time'
            signals = {'champion': 'Annie', 'selected': 'custom', 'slot1': '3089', 'duration': 6.5, 'mr': 97}
            path = '/evaluate?' + urllib.parse.urlencode({'datastar': json.dumps(signals)})
            headers, body = get(base, path, {'Datastar-Request': 'true', 'Accept': 'text/event-stream'})
            assert headers['Content-Type'].startswith('text/event-stream')
            assert b'datastar-patch-elements' in body and b'id="results"' in body and b'data-duration="6.5"' in body
            # A client disappearing midway through SSE must not kill the service.
            with socket.create_connection(('127.0.0.1', chosen)) as sock:
                sock.sendall(('GET ' + path + ' HTTP/1.1\r\nHost: localhost\r\nDatastar-Request: true\r\n\r\n').encode())
            get(base, '/healthz')
        # CLI port overrides even an invalid environment value at runtime.
        chosen = port()
        with running(binary, cwd, ['--port', str(chosen)], configuration(PS_PORT='invalid'), chosen) as base:
            get(base, '/healthz')
        assert set(cwd.iterdir()) == {binary, seed, cwd / 'data'}, 'Runtime wrote outside its data directory'
    print('Relocated executable: runtime config, embedded catalog/art/assets, Q/W, SSE and disconnect checks passed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary')
    verify(parser.parse_args().binary)

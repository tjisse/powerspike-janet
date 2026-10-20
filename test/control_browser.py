"""Synthetic control timings through the packaged UI; not champion evidence."""
import json
import tempfile
import urllib.parse
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
from runtime import port, running, clean_env


def verify(binary_path, fixture_path):
    root = Path.cwd()
    binary, fixture = Path(binary_path).resolve(), Path(fixture_path).resolve()
    snapshot = json.loads((fixture / 'scenario.json').read_text())['scenario']['snapshot']
    with tempfile.TemporaryDirectory(prefix='powerspike-control-browser-') as data:
        chosen = port()
        with running(binary, root, [], clean_env(PS_PORT=str(chosen), PS_HOST='127.0.0.1',
                     PS_DATA_DIR=data, PS_SEED_DIR=str(fixture / 'seed')), chosen) as base:
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch(headless=True)
                for reverse in (False, True):
                    page = browser.new_page(viewport={'width': 1200, 'height': 1000})
                    errors = []
                    page.on('pageerror', lambda error: errors.append(str(error)))
                    query = {'mode': 'duel', 'champion': 'Lux' if reverse else 'Annie',
                             'opponent': 'Annie' if reverse else 'Lux', 'selected': 'custom',
                             'level': 1, 'opponentlevel': 1, 'duration': .5, 'distance': 100,
                             'skillorder': 'q', 'opponentskillorder': 'q', 'priority': 'q', 'opponentpriority': 'q',
                             'attacks': 'false', 'opponentattacks': 'false', 'abilities': 'true', 'opponentabilities': 'true',
                             'movement': 'hold', 'opponentmovement': 'hold', 'snapshot': snapshot, 'samples': 1}
                    page.goto(base + '/?' + urllib.parse.urlencode(query), wait_until='domcontentloaded')
                    expect(page.locator('#matchup-chart svg')).to_be_visible()
                    trace = json.loads(page.locator('#results').get_attribute('data-matchup-result'))['trace']
                    who = 'opponent' if reverse else 'player'
                    casts = [row for row in trace if row['kind'] == 'cast' and row['source'] == 'fixture-q']
                    assert len(casts) == 2 and all(row['actor'] == who for row in casts)
                    control = next(row for row in trace if row['kind'] == 'control' and row['target'] == who)
                    assert control['control'] == 'silence'
                    assert abs(control['at'] - .013) < 1e-6
                    assert abs(casts[1]['at'] - (control['at'] + control['duration'])) < 1e-6
                    assert sum(row['damage'] for row in trace if row['kind'] == 'damage' and row['source'] == 'fixture-q') == 20
                    page.set_viewport_size({'width': 320, 'height': 1000})
                    page.wait_for_function('document.documentElement.scrollWidth <= innerWidth + 1')
                    assert not errors, errors
                    page.close()
                browser.close()
    print('Browser: synthetic silence expiry, exact resumption/impacts, both participants and mobile layout passed.')

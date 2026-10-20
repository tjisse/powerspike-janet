"""Retained health-cost formula on an explicitly synthetic carrier; not game evidence."""
import json
import tempfile
import urllib.parse
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
from runtime import port, running, clean_env


def verify(binary_path, fixture_path):
    root = Path.cwd()
    binary, fixture = Path(binary_path).resolve(), Path(fixture_path).resolve()
    document = json.loads((fixture / 'scenario.json').read_text())['scenario']
    coefficient = .079999998211860657
    with tempfile.TemporaryDirectory(prefix='powerspike-health-cost-browser-') as data:
        chosen = port()
        with running(binary, root, [], clean_env(PS_PORT=str(chosen), PS_HOST='127.0.0.1',
                     PS_DATA_DIR=data, PS_SEED_DIR=str(fixture / 'seed')), chosen) as base:
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch(headless=True)
                for reverse in (False, True):
                    page = browser.new_page(viewport={'width': 1200, 'height': 1000})
                    errors = []
                    page.on('pageerror', lambda error: errors.append(str(error)))
                    query = {'mode': 'duel', 'champion': 'Annie', 'opponent': 'Annie', 'selected': 'custom',
                             'patch': document['patch'], 'snapshot': document['snapshot'],
                             'level': 1, 'opponentlevel': 1, 'duration': .592, 'distance': 0,
                             'skillorder': 'q', 'opponentskillorder': 'q', 'priority': 'q', 'opponentpriority': 'q',
                             'attacks': 'false', 'opponentattacks': 'false',
                             'abilities': 'false' if reverse else 'true', 'opponentabilities': 'true' if reverse else 'false',
                             'healthfraction': 1 if reverse else .1, 'opponenthealthfraction': .1 if reverse else 1,
                             'movement': 'hold', 'opponentmovement': 'hold', 'samples': 1}
                    page.goto(base + '/?' + urllib.parse.urlencode(query), wait_until='domcontentloaded')
                    expect(page.locator('#matchup-chart svg')).to_be_visible()
                    exported = json.loads(page.locator('#scenario-data').get_attribute('data-json'))['scenario']
                    assert exported['patch'] == '16.18.1' and exported['snapshot'] == document['snapshot']
                    assert exported['target' if reverse else 'player']['health-fraction'] == .1
                    trace = json.loads(page.locator('#results').get_attribute('data-matchup-result'))['trace']
                    who = 'opponent' if reverse else 'player'
                    casts = [row for row in trace if row['kind'] == 'cast' and row['source'] == 'fixture-health']
                    hits = [row for row in trace if row['kind'] == 'damage' and row['source'] == 'fixture-health']
                    assert len(casts) == len(hits) == 1
                    assert casts[0]['actor'] == hits[0]['actor'] == who
                    assert abs(casts[0]['at'] - .337) < 1e-6
                    assert abs(hits[0]['at'] - (.337 + .25)) < 1e-6
                    assert abs(casts[0]['cost'] - coefficient * casts[0]['before'][int(reverse)]['health']) < 1e-6
                    assert casts[0]['participants'][int(reverse)]['health'] >= 1
                    assert hits[0]['damage'] == 1
                    page.set_viewport_size({'width': 320, 'height': 1000})
                    page.wait_for_function('document.documentElement.scrollWidth <= innerWidth + 1')
                    assert not errors, errors
                    page.close()
                browser.close()
    print('Browser: retained current-health cost, synthetic carrier readiness/payment/reserve, both participants and mobile layout passed.')

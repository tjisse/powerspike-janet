"""Exercise retained ability scenarios through the packaged matchup UI."""
import json
from pathlib import Path
import sys
import tempfile
import urllib.parse
from playwright.sync_api import expect, sync_playwright
from runtime import clean_env, port, running


def verify(binary_path, fixture_path):
    fixture = Path(fixture_path).resolve()
    cases = json.loads((fixture / 'cases.json').read_text())
    with tempfile.TemporaryDirectory(prefix='powerspike-ability-browser-') as data:
        chosen = port()
        with running(Path(binary_path).resolve(), Path.cwd(), [],
                     clean_env(PS_PORT=str(chosen), PS_HOST='127.0.0.1', PS_DATA_DIR=data,
                               PS_SEED_DIR=str(fixture / 'seed')), chosen) as base:
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch()
                page = browser.new_page(viewport={'width': 1200, 'height': 1000})
                errors = []
                page.on('pageerror', lambda error: errors.append(str(error)))
                for patch in {case['document']['scenario']['patch'] for case in cases}:
                    page.route(f'**/assets/{patch}/**', lambda route: route.abort())
                for case in cases:
                    query = urllib.parse.quote(json.dumps(case['document'], separators=(',', ':')))
                    response = page.goto(base + '/?scenario=' + query, wait_until='domcontentloaded')
                    assert response.ok, page.locator('main').inner_text()[:2500]
                    expect(page.locator('#matchup-chart svg')).to_be_visible()
                    saved = json.loads(page.locator('#scenario-data').get_attribute('data-json'))['scenario']
                    for side in ('player', 'target'):
                        for field in ('champion', 'ranks', 'skill-order', 'level'):
                            if field in case['document']['scenario'][side]:
                                assert saved[side].get(field) == case['document']['scenario'][side][field], (side, field)
                    result = json.loads(page.locator('#results').get_attribute('data-matchup-result'))
                    for check in case.get('tooltips', []):
                        tile = page.locator(f'#{check["side"]}-card [data-ability-slot="{check["slot"]}"]')
                        payload = json.loads(tile.get_attribute('data-details'))
                        text = ''.join(segment['text'] for line in payload['body-rich'] for segment in line)
                        assert check['contains'] in text, (check, text)
                        for expected in check.get('stats', []):
                            assert expected in payload['stats']
                    if case.get('passive-side'):
                        side = case['passive-side']
                        prefix = 'enemy' if side == 'opponent' else ''
                        expect(page.locator(f'#{side}-card [name="{prefix}wafter"]')).to_be_disabled()
                        assert any(status['effect'] == 'Silver Bolts' for status in result['statuses'])
                    for source in case['sources']:
                        assert any(row['kind'] == 'damage' and row.get('source') == source for row in result['trace'])
                    for check in case.get('trace-counts', []):
                        assert sum(row['kind'] == check['kind'] and row.get('source') == check['source']
                                   for row in result['trace']) == check['count'], check
                    for width in (1200, 390, 320):
                        page.set_viewport_size({'width': width, 'height': 1000})
                        page.wait_for_function('document.documentElement.scrollWidth <= innerWidth + 1')
                        represented = page.locator('[data-trace-events]').evaluate_all(
                            'nodes => nodes.flatMap(node => JSON.parse(node.dataset.traceEvents))')
                        expected = [row for row in result['trace'] if row['at'] <= result['end'] and row['kind'] in
                                    ('damage', 'heal', 'shield', 'control', 'death', 'parry-start', 'parried')]
                        assert sorted(represented) == list(range(len(expected)))
                assert not errors, errors
                browser.close()
    print(f'Browser: {len(cases)} reviewed ability scenarios, complete timeline representation and mobile layout passed.')


if __name__ == '__main__':
    verify(*sys.argv[1:])

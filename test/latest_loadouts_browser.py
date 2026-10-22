"""Latest-patch form controls and saved loadouts through the packaged UI."""
import json
from pathlib import Path
import tempfile
from urllib.parse import urlencode
from playwright.sync_api import expect, sync_playwright
from runtime import clean_env, port, running


def verify(binary_path, fixture_path):
    root = Path.cwd()
    binary, fixture = Path(binary_path).resolve(), Path(fixture_path).resolve()
    cases = json.loads((fixture / 'cases.json').read_text())
    with tempfile.TemporaryDirectory(prefix='powerspike-loadouts-browser-') as data:
        chosen = port()
        with running(binary, root, [], clean_env(PS_PORT=str(chosen), PS_HOST='127.0.0.1',
                     PS_DATA_DIR=data, PS_SEED_DIR=str(fixture / 'seed')), chosen) as base:
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch()
                page = browser.new_page(viewport={'width':1200, 'height':1000})
                errors = []
                page.on('pageerror', lambda error: errors.append(str(error)))
                changed = set()
                for case in cases:
                    scenario = case['document']['scenario']
                    if scenario['target']['kind'] != 'champion':
                        continue
                    response = page.goto(base + '/?' + urlencode({'scenario':json.dumps(case['document'])}),
                                         wait_until='domcontentloaded')
                    assert response.status == 200
                    expect(page.locator('#matchup-chart svg')).to_be_visible()
                    restored = json.loads(page.locator('#scenario-data').get_attribute('data-json'))['scenario']
                    assert restored['patch'] == scenario['patch']
                    assert restored['snapshot'] == scenario['snapshot']
                    for index, (side, name) in enumerate([('player', 'form'), ('opponent', 'opponentform')]):
                        stats = dict(json.loads(page.locator(f'#{side}-card button[data-details]').first.get_attribute('data-details'))['stats'])
                        assert float(stats['Attack range']) == case['actors'][index]['attack-range']
                        if 'form' in case['actors'][index]:
                            assert page.locator(f'#{side}-card [name={name}]').input_value() == case['actors'][index]['form']
                    # Exercise changing a newly available form and rerunning,
                    # preserving the completed result until the explicit run.
                    if scenario['player']['champion'] == 'Nidalee' and scenario['patch'] not in changed:
                        before = page.locator('#results').get_attribute('data-run-id')
                        page.locator('#player-card [name=form]').select_option('cougar')
                        page.wait_for_function('JSON.parse(document.querySelector("#configuration-data").dataset.json).scenario.player.form === "cougar"')
                        assert page.locator('#results').get_attribute('data-run-id') == before
                        page.locator('.matchup-run').click()
                        page.wait_for_function('(before)=>document.querySelector("#results").dataset.runId !== before', arg=before)
                        page.set_viewport_size({'width':320, 'height':1000})
                        page.wait_for_function('document.documentElement.scrollWidth <= innerWidth + 1')
                        page.set_viewport_size({'width':1200, 'height':1000})
                        changed.add(scenario['patch'])
                assert changed == {'16.20.1', '16.21.1'}
                assert not errors, errors
                browser.close()
    print('Browser: latest-patch Kayle boundaries, all fixed-form controls, both participants, saved snapshots, explicit reruns and mobile layout passed.')

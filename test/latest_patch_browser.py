"""Default fights using snapshots rebuilt through an explicit patch refresh."""
import json
import tempfile
from pathlib import Path
from playwright.sync_api import expect, sync_playwright
from runtime import clean_env, port, running


def verify(binary_path, fixture_path):
    root = Path.cwd()
    binary, fixture = Path(binary_path).resolve(), Path(fixture_path).resolve()
    with tempfile.TemporaryDirectory(prefix='powerspike-latest-patch-browser-') as data:
        chosen = port()
        with running(binary, root, [], clean_env(PS_PORT=str(chosen), PS_HOST='127.0.0.1',
                     PS_DATA_DIR=data, PS_SEED_DIR=str(fixture / 'seed')), chosen) as base:
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch()
                page = browser.new_page(viewport={'width':1200, 'height':1000})
                errors, refreshes = [], []
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.on('request', lambda request: refreshes.append(request.url)
                        if '/patches?refresh=true' in request.url else None)
                page.goto(base+'/?patch=16.21.1&snapshotlocked=true', wait_until='domcontentloaded')

                def check(patch):
                    expect(page.locator('#matchup-chart svg')).to_be_visible()
                    document = json.loads(page.locator('#scenario-data').get_attribute('data-json'))['scenario']
                    assert document['patch'] == patch
                    result = json.loads(page.locator('#results').get_attribute('data-matchup-result'))
                    casts = {(event.get('actor'), event.get('source')) for event in result['trace'] if event['kind']=='cast'}
                    assert {('player', 'AnnieQ'), ('player', 'AnnieW'), ('opponent', 'GarenQ'), ('opponent', 'GarenW')} <= casts
                    assert result['sources']['AnnieQ']['icon'].endswith('/spell/AnnieQ.png')
                    assert result['sources']['GarenQ']['icon'].endswith('/spell/GarenQ.png')
                    assert 'Unknown stat/formula mapping' not in page.locator('#coverage').inner_text()
                    return result

                original = check('16.21.1')
                previous = page.locator('#results').get_attribute('data-run-id')
                page.locator('.matchup-run').click()
                page.wait_for_function('old=>document.querySelector("#results").dataset.runId!==old', arg=previous)
                assert check('16.21.1') == original
                page.locator('#patch-settings > summary').click()
                page.locator('#patch-panel select').select_option('16.20.1')
                page.wait_for_url('**/?**patch=16.20.1**')
                check('16.20.1')
                for width in (736,390,320):
                    page.set_viewport_size({'width':width, 'height':1000})
                    page.wait_for_function('document.documentElement.scrollWidth<=innerWidth+1')
                page.locator('#results').screenshot(path='build/latest-patch-mobile.png')
                assert not errors, errors
                assert not refreshes, refreshes
                browser.close()
    print('Browser: refreshed latest-patch casts, exact rerun, patch switching, timeline sources and mobile layout passed.')

"""Latest-patch saved scenarios retain the reviewed impacts through the UI."""
import json
import tempfile
from pathlib import Path
from urllib.parse import urlencode
from playwright.sync_api import expect, sync_playwright
from runtime import clean_env, port, running


def verify(binary_path, fixture_path):
    root = Path.cwd()
    binary, fixture = Path(binary_path).resolve(), Path(fixture_path).resolve()
    cases = json.loads((fixture/'cases.json').read_text())
    with tempfile.TemporaryDirectory(prefix='powerspike-latest-attacks-browser-') as data:
        chosen = port()
        with running(binary, root, [], clean_env(PS_PORT=str(chosen), PS_HOST='127.0.0.1',
                     PS_DATA_DIR=data, PS_SEED_DIR=str(fixture/'seed')), chosen) as base:
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch()
                page = browser.new_page(viewport={'width':1200, 'height':1000})
                errors = []
                page.on('pageerror', lambda error: errors.append(str(error)))
                for case in cases:
                    response = page.goto(base+'/?'+urlencode({'scenario':json.dumps(case['document'])}), wait_until='domcontentloaded')
                    assert response.status == 200
                    expect(page.locator('#timeline')).to_be_visible()
                    events = json.loads(page.locator('#timeline').get_attribute('data-events'))
                    if 'first-impact' in case:
                        assert abs(events[0]['at'] - case['first-impact']) < 1e-6
                    else:
                        for source, expected in [('ViktorQ', case['empowered-at']), ('attack', case['ordinary-at'])]:
                            assert any(event['source'] == source and abs(event['at'] - expected) < 1e-6 for event in events)
                    original = json.loads(page.locator('#scenario-data').get_attribute('data-json'))['scenario']
                    assert original['patch'] == case['document']['scenario']['patch']
                    assert original['snapshot'] == case['document']['scenario']['snapshot']
                    for width in (390,320):
                        page.set_viewport_size({'width':width, 'height':1000})
                        page.wait_for_function('document.documentElement.scrollWidth <= innerWidth+1')
                    page.set_viewport_size({'width':1200, 'height':1000})
                assert not errors, errors
                browser.close()
    print('Browser: latest-patch mage ordinary/empowered impacts, exact saved snapshots and mobile layouts passed.')

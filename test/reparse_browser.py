"""Reparse retained raw files with provider network access deliberately unavailable."""
import hashlib
import json
import tempfile
from pathlib import Path
from urllib.parse import urlencode
from playwright.sync_api import expect, sync_playwright
from runtime import clean_env, port, running


def verify(binary_path, fixture_path):
    root = Path.cwd()
    binary, fixture = Path(binary_path).resolve(), Path(fixture_path).resolve()
    document = json.loads((fixture/'fixture.json').read_text())
    fields = document['fields']
    with tempfile.TemporaryDirectory(prefix='powerspike-reparse-browser-') as data:
        chosen = port()
        # The service cannot download provider sources or artwork. Browser code
        # and all simulation/reparse requests still use the local server.
        proxy = 'http://127.0.0.1:1'
        env = clean_env(PS_PORT=str(chosen), PS_HOST='127.0.0.1', PS_DATA_DIR=data,
                        PS_SEED_DIR=str(fixture/'seed'), HTTPS_PROXY=proxy, https_proxy=proxy,
                        ALL_PROXY=proxy, all_proxy=proxy, NO_PROXY='127.0.0.1,localhost', no_proxy='127.0.0.1,localhost')
        with running(binary, root, [], env, chosen) as base:
            snapshot = Path(data)/'patches'/document['patch']/document['snapshot']
            pointer = snapshot.parent/'current'
            original = (snapshot/'package.jdn').read_bytes()
            hashes = {p.relative_to(snapshot):hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in (snapshot/'sources').rglob('*') if p.is_file()}
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch()
                page = browser.new_page(viewport={'width':1200, 'height':1000})
                errors, refreshes, reparses = [], [], []
                page.on('pageerror', lambda error: errors.append(str(error)))
                def request_seen(request):
                    if '/patches?refresh=true' in request.url:
                        refreshes.append(request.url)
                    if request.url.endswith('/patches/reparse'):
                        reparses.append(request.url)
                page.on('request', request_seen)
                old_url = base+'/?'+urlencode({key:str(value).lower() if isinstance(value,bool) else value for key,value in fields.items()})
                response = page.goto(old_url, wait_until='domcontentloaded')
                assert response.status == 200
                warning = page.locator('#parser-warning')
                expect(warning).to_be_visible()
                assert warning.evaluate('node => node.closest("#workspace-messages") !== null')
                expect(warning).to_contain_text('Saved parser 6; current parser 7')
                expect(warning.get_by_role('button', name='Reparse saved data', exact=True)).to_be_enabled()
                assert pointer.read_text().strip() == document['snapshot']
                assert not reparses and not refreshes
                page.locator('[name=duration]').click()
                expect(page.locator('#patch-settings')).not_to_have_attribute('open', '')
                page.locator('[name=duration]').fill('6')
                page.locator('[name=duration]').press('Tab')
                page.wait_for_function('JSON.parse(document.querySelector("#configuration-data").dataset.json).scenario.duration===6')
                page.screenshot(path='build/reparse-warning-desktop.png', full_page=True)
                with page.expect_navigation(wait_until='domcontentloaded'):
                    warning.get_by_role('button', name='Reparse saved data', exact=True).click()
                expect(warning).not_to_be_visible()
                expect(page.locator('#workspace-messages')).to_have_attribute('data-active', 'false')
                expect(page.locator('.workspace-ready')).to_be_visible()
                scenario = json.loads(page.locator('#scenario-data').get_attribute('data-json'))['scenario']
                assert scenario['snapshot'] != document['snapshot']
                assert scenario['duration'] == 6
                assert scenario['player']['champion'] == 'Annie' and scenario['target']['champion'] == 'Garen'
                result = json.loads(page.locator('#results').get_attribute('data-matchup-result'))
                casts = {(e.get('actor'), e.get('source')) for e in result['trace'] if e['kind']=='cast'}
                assert {('player','AnnieQ'), ('player','AnnieW'), ('opponent','GarenQ')} <= casts
                assert len(reparses) == 1 and not refreshes
                current = pointer.read_text().strip()
                assert current == scenario['snapshot']
                assert (snapshot/'package.jdn').read_bytes() == original
                for path, digest in hashes.items():
                    assert hashlib.sha256((snapshot/path).read_bytes()).hexdigest() == digest
                # An old saved link remains pinned; simply viewing it never
                # reparses data or silently switches to the newer snapshot.
                page.goto(old_url, wait_until='domcontentloaded')
                expect(warning).to_be_visible()
                assert warning.evaluate('node => node.closest("#workspace-messages") !== null')
                assert pointer.read_text().strip() == current
                assert json.loads(page.locator('#scenario-data').get_attribute('data-json'))['scenario']['snapshot'] == document['snapshot']
                for width in (736,390,320):
                    page.set_viewport_size({'width':width, 'height':1000})
                    page.wait_for_function('document.documentElement.scrollWidth<=innerWidth+1')
                    expect(warning.get_by_role('button', name='Reparse saved data', exact=True)).to_be_visible()
                warning.screenshot(path='build/reparse-warning-mobile.png')
                # A corrupt optional source must fail visibly, preserve the
                # completed fight/current pointer and offer a retry.
                source = snapshot/'sources/characters/Annie.json'
                retained = source.read_bytes()
                source.write_bytes(b'{}')
                before = page.locator('#results').get_attribute('data-matchup-result')
                warning.get_by_role('button', name='Reparse saved data', exact=True).click()
                expect(warning.locator('.parser-reparse-status')).to_contain_text('integrity check failed', timeout=15000)
                expect(warning.get_by_role('button', name='Reparse saved data', exact=True)).to_be_enabled()
                assert page.locator('#results').get_attribute('data-matchup-result') == before
                assert pointer.read_text().strip() == current
                source.write_bytes(retained)
                page.goto(base+'/?champion=Annie&patch=16.19.1&snapshotlocked=true', wait_until='domcontentloaded')
                expect(warning).to_contain_text('Saved raw data is unavailable')
                assert warning.get_by_role('button', name='Reparse saved data', exact=True).count() == 0
                assert not errors, errors
                assert not refreshes
                browser.close()
    print('Browser: parser mismatch, explicit offline reparse, preserved configuration, restored casts, pinned snapshots, corrupt-source recovery and mobile warnings passed.')

"""Exercise visible parry outcomes using a real cached champion/item fixture."""
import argparse
import json
import tempfile
import urllib.parse
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
from runtime import port, running, clean_env


def verify(binary_path, fixture_path):
    root = Path.cwd()
    binary, fixture = Path(binary_path).resolve(), Path(fixture_path).resolve()
    scenario = json.loads((fixture / 'scenario.json').read_text())['scenario']
    query = {'mode': 'duel', 'champion': 'Ahri', 'opponent': 'Fiora', 'selected': 'custom',
             'slot1': '3100', 'level': 1, 'opponentlevel': 1, 'duration': .74, 'distance': 100,
             'skillorder': 'q', 'opponentskillorder': 'w', 'priority': 'q', 'opponentpriority': 'w',
             'opponentattacks': 'false', 'movement': 'hold', 'opponentmovement': 'hold',
             'snapshot': scenario['snapshot'], 'samples': 1}
    with tempfile.TemporaryDirectory(prefix='powerspike-parry-browser-') as data:
        chosen = port()
        with running(binary, root, [], clean_env(PS_PORT=str(chosen), PS_HOST='127.0.0.1',
                     PS_DATA_DIR=data, PS_SEED_DIR=str(fixture / 'seed')), chosen) as base:
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch(headless=True)
                page = browser.new_page(viewport={'width': 1200, 'height': 1000})
                errors = []
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.goto(base + '/?' + urllib.parse.urlencode(query), wait_until='domcontentloaded')
                expect(page.locator('#matchup-chart svg')).to_be_visible()
                payload = json.loads(page.locator('#results').get_attribute('data-matchup-result'))
                trace = payload['trace']
                parries = [r for r in trace if r['kind'] == 'parried']
                assert parries and any(r['source'] == 'item/3100/hit' for r in parries)
                assert sum(r.get('damage', 0) for r in trace if r['kind'] == 'damage') == 0
                expect(page.locator('.matchup-parry-hint')).to_contain_text('Parried hit')
                assert page.locator('#verification-progress, #source-evidence').count() == 0
                visible_kinds = {'damage', 'heal', 'shield', 'control', 'death', 'parried', 'parry-start'}
                expected = sum(r['kind'] in visible_kinds for r in trace)
                expect(page.locator('.matchup-event-select option')).to_have_count(expected + 1)
                # Pick events by gameplay labels, including a crowded proc at the
                # same instant as the basic attack. Every event stays selectable.
                options = page.locator('.matchup-event-select option')
                begin = options.filter(has_text='Riposte begins').first.get_attribute('value')
                page.locator('.matchup-event-select').select_option(begin)
                expect(page.locator('.matchup-event-detail')).to_contain_text('Defense active for 0.75 s')
                lich = options.filter(has_text='Lich Bane · parried by Fiora').first.get_attribute('value')
                page.locator('.matchup-event-select').select_option(lich)
                expect(page.locator('.matchup-event-detail')).to_contain_text('0 damage')
                expect(page.locator('.matchup-event-detail')).to_contain_text('Spellblade consumed')
                expect(page.locator(f'[data-trace-event="{lich}"][aria-pressed=true]')).to_have_text('×')
                assert 'item/3100/hit' not in page.locator('.matchup-event-detail').inner_text()
                page.locator('#results').screenshot(path='build/parry-events-desktop.png')
                for width in (736, 390, 320):
                    page.set_viewport_size({'width': width, 'height': 1000})
                    page.wait_for_timeout(100)
                    page.locator('.matchup-event-select').select_option(lich)
                    expect(page.locator('.matchup-event-detail')).to_contain_text('Spellblade consumed')
                    assert page.evaluate('document.documentElement.scrollWidth <= innerWidth + 1'), width
                page.locator('#results').screenshot(path='build/parry-events-mobile.png')
                # Retained Lich Bane damage appears only in the equipped build.
                page.set_viewport_size({'width':1200, 'height':1000})
                query.update({'opponentabilities':'false', 'duration':2})
                page.goto(base+'/?'+urllib.parse.urlencode(query), wait_until='domcontentloaded')
                document = json.loads(page.locator('#scenario-data').get_attribute('data-json'))
                document.update({'format':'powerspike-comparison', 'pinned-items':[]})
                page.goto(base+'/?'+urllib.parse.urlencode({'scenario':json.dumps(document)}), wait_until='domcontentloaded')
                page.get_by_text('Damage by source', exact=True).click()
                proc = page.locator('.comparison-source-table [data-source="item/3100/hit"]')
                expect(proc.locator('th')).to_contain_text('Lich Bane')
                expect(proc.locator('td').first).to_have_text('0.00')
                trace = json.loads(page.locator('#results').get_attribute('data-matchup-result'))['trace']
                damage = sum(row['damage'] for row in trace if row['kind'] == 'damage' and row['actor'] == 'player' and row['source'] == 'item/3100/hit')
                assert damage > 0
                assert abs(float(proc.locator('td').nth(1).inner_text()) - damage) < .005
                assert abs(float(proc.locator('td').nth(2).inner_text()) - damage) < .005
                page.locator('#item-comparison').screenshot(path='build/damage-sources-proc.png')
                page.set_viewport_size({'width':320, 'height':1000})
                page.wait_for_function('document.documentElement.scrollWidth <= innerWidth + 1')
                assert not errors, errors
                browser.close()
    print('Browser: sourced Riposte events, Spellblade consumption, crowded selection, Lich Bane source comparison and mobile layouts passed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', default='dist/bin/powerspike')
    parser.add_argument('--fixture', default='build/parry-runtime-fixture')
    args = parser.parse_args()
    verify(args.binary, args.fixture)

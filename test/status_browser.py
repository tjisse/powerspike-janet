"""Render synthetic production-engine intervals; no new champion evidence."""
import json
from pathlib import Path
from playwright.sync_api import expect


def verify(browser, base):
    fixtures = json.loads(Path('build/status-timeline-browser.json').read_text())
    page = browser.new_page(viewport={'width': 1200, 'height': 1000})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.goto(base+'/?snapshotlocked=true', wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    original = json.loads(page.locator('#results').get_attribute('data-matchup-result'))

    def show(name):
        payload = {**original, **fixtures[name]}
        payload['actors'] = [{**actor, 'hp': 1000} for actor in original['actors']]
        page.locator('#results').evaluate('''(node, payload) => {
            node.dataset.matchupResult = JSON.stringify(payload);
            node.dataset.runId = 'status-fixture-' + Math.random();
        }''', payload)
        payload['statuses'] = [{**status, 'end':min(status['end'], payload['end'])}
                               for status in payload['statuses'] if status['start'] < payload['end']]
        expect(page.locator('.matchup-status-band')).to_have_count(len(payload['statuses']))
        return payload

    colors = {}
    for name in ('controls', 'buffs', 'cutoff'):
        payload = show(name)
        for width in (1200, 736, 390, 320):
            page.set_viewport_size({'width': width, 'height': 1000})
            page.wait_for_function('document.documentElement.scrollWidth <= innerWidth+1')
            for index, status in enumerate(payload['statuses']):
                band = page.locator(f'[data-status-index="{index}"]')
                who = next(i for i, actor in enumerate(payload['actors']) if actor['id'] == status['actor'])
                track = page.locator('.matchup-event-track').nth(who)
                page.wait_for_function('''({index, who, start, end, duration}) => {
                    const band = document.querySelector(`[data-status-index="${index}"]`).getBoundingClientRect();
                    const track = document.querySelectorAll('.matchup-event-track')[who].getBoundingClientRect();
                    return Math.abs(band.x-track.x-start/duration*track.width)<1 &&
                        Math.abs(band.width-(end-start)/duration*track.width)<1;
                }''', arg={'index':index, 'who':who, 'start':status['start'], 'end':status['end'], 'duration':payload['duration']})
                assert band.locator('..').evaluate('node => node.classList.contains("matchup-event-track")')
                assert track.locator(f'[data-status-index="{index}"]').count() == 1
                color = band.evaluate('node => node.style.getPropertyValue("--status-color").trim()')
                assert colors.setdefault(status['effect'], color) == color, (name, width, status['effect'], color, colors)
                assert band.get_attribute('aria-label')
            # Overlapping types occupy separate strips inside the same lane.
            if name == 'controls':
                stun = page.locator('[data-status-effect="stun"]').bounding_box()
                silence = page.locator('[data-status-effect="silence"]').bounding_box()
                assert abs(stun['y'] - silence['y']) >= min(stun['height'], silence['height']) - 1
        assert len(set(colors.values())) == len(colors)
        bands = page.locator('.matchup-status-band')
        band = bands.first
        page.locator('.matchup-event-select').focus()
        band.focus()
        tooltip = page.locator('#combat-event-tooltip')
        expect(tooltip).to_be_visible()
        expect(tooltip).to_contain_text('s active')
        before = page.locator('#results').bounding_box()
        page.keyboard.press('Escape')
        expect(tooltip).not_to_be_visible()
        after = page.locator('#results').bounding_box()
        assert before == after
        page.locator('#results').screenshot(path=f'build/status-{name}-mobile.png')

    show('empty')
    expect(page.locator('.matchup-status-legend')).not_to_be_visible()
    # Restore real combat and confirm its artwork remains above the bands.
    page.goto(base+'/?snapshotlocked=true', wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    marker = page.locator('[data-trace-event]').first
    marker.focus()
    expect(page.locator('#combat-event-tooltip')).to_be_visible()
    expect(marker).to_have_css('z-index', '1')
    assert not errors, errors
    page.close()

    touch = browser.new_page(viewport={'width':390, 'height':844}, is_mobile=True, has_touch=True)
    touch.goto(base+'/?snapshotlocked=true', wait_until='domcontentloaded')
    expect(touch.locator('#matchup-chart svg')).to_be_visible()
    payload = {**original, **fixtures['controls']}
    touch.locator('#results').evaluate('''(node, payload) => {
        node.dataset.matchupResult = JSON.stringify(payload); node.dataset.runId = 'touch-status';
    }''', payload)
    expect(touch.locator('.matchup-status-band')).to_have_count(len(payload['statuses']))
    root = touch.locator('[data-status-effect="root"]')
    root.tap(position={'x':30, 'y':8})
    expect(touch.locator('#combat-event-tooltip')).to_contain_text('Root')
    touch.locator('.matchup-health').tap()
    expect(touch.locator('#combat-event-tooltip')).not_to_be_visible()
    touch.close()
    print('Browser: engine-backed status spans, per-champion lanes, overlap/colors, exact geometry, stable tooltips, touch and mobile layouts passed.')

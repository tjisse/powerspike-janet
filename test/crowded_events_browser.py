"""The reported fight uses W/E milliseconds apart; grouping must reveal both."""
import json
from pathlib import Path
from playwright.sync_api import expect


def verify(browser, base):
    fixture = json.loads(Path('test/fixtures/seraphine-garen-timeline.json').read_text())
    events = [row for row in fixture['trace'] if row['at'] <= fixture['end'] and row['kind'] in
              ('damage', 'heal', 'shield', 'control', 'death', 'parry-start', 'parried')]
    w = next(i for i, row in enumerate(events) if row.get('source') == 'SeraphineW' and row['kind'] == 'shield')
    e = next(i for i, row in enumerate(events) if row.get('source') == 'SeraphineE' and row['kind'] == 'damage')
    assert events[w]['at'] == .01 and events[e]['at'] == .02
    errors = []

    def prepare(page):
        page.on('pageerror', lambda error: errors.append(str(error)))
        # This observed trace's remote cache is intentionally not needed by
        # the local presentation fixture. Missing artwork must remain usable.
        page.route('**/assets/16.21.1/**', lambda route: route.abort())
        page.goto(base + '/?snapshotlocked=true', wait_until='domcontentloaded')
        expect(page.locator('#matchup-chart svg')).to_be_visible()
        page.locator('#results').evaluate('''(node, payload) => {
            node.dataset.matchupResult = JSON.stringify(payload);
            node.dataset.runId = 'reported-seraphine-crowding';
        }''', fixture)
        expect(page.locator('.matchup-event-select option')).to_have_count(len(events) + 1)

    def containing(page, index):
        return page.locator('[data-trace-events]').evaluate_all(
            '(nodes, index) => nodes.find(node => JSON.parse(node.dataset.traceEvents).includes(index))?.dataset.traceEvent', index)

    page = browser.new_page(viewport={'width':1200, 'height':1000})
    prepare(page)
    for width in (1200, 736, 390, 320):
        page.set_viewport_size({'width':width, 'height':1000})
        page.wait_for_function('document.documentElement.scrollWidth <= innerWidth + 1')
        # Every event belongs to exactly one visible marker group. Old code
        # silently discarded neighboring markers unless individually selected.
        represented = page.locator('[data-trace-events]').evaluate_all(
            'nodes => nodes.flatMap(node => JSON.parse(node.dataset.traceEvents))')
        assert sorted(represented) == list(range(len(events)))
        index = containing(page, w)
        marker = page.locator(f'[data-trace-event="{index}"]')
        members = json.loads(marker.get_attribute('data-trace-events'))
        assert w in members and e in members
        expect(marker.locator('.matchup-event-count')).to_have_text(f'+{len(members)-1}')
        marker.hover()
        tooltip = page.locator('#combat-event-tooltip')
        expect(tooltip).to_contain_text('Surround Sound')
        expect(tooltip).to_contain_text('Beat Drop')
        expect(tooltip).to_contain_text('shield')
        expect(tooltip).to_contain_text('damage')
        page.keyboard.press('Escape')
        marker.focus()
        expect(tooltip).to_be_visible()
        before = page.locator('#results').bounding_box()
        for index, label in ((w, 'W'), (e, 'E')):
            page.locator('.matchup-event-select').select_option(str(index))
            selected = page.locator(f'[data-trace-event="{index}"]')
            expect(selected).to_have_attribute('aria-pressed', 'true')
            expect(selected.locator('.matchup-event-label')).to_have_text(label)
            assert page.locator('#results').bounding_box() == before
        page.screenshot(path=f'build/crowded-events-{width}.png', full_page=True)
    page.close()
    touch = browser.new_page(viewport={'width':390, 'height':844}, is_mobile=True, has_touch=True)
    prepare(touch)
    marker = touch.locator(f'[data-trace-event="{containing(touch, w)}"]')
    marker.tap()
    expect(touch.locator('#combat-event-tooltip')).to_contain_text('Surround Sound')
    expect(touch.locator('#combat-event-tooltip')).to_contain_text('Beat Drop')
    touch.locator('.matchup-health').tap()
    expect(touch.locator('#combat-event-tooltip')).not_to_be_visible()
    touch.close()
    assert not errors, errors
    print('Browser: all crowded events represented, reported Seraphine W/E revealed, exact selection, stable layout, keyboard/touch and mobile passed.')

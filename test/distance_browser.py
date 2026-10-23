"""Inspect production-engine position keyframes through the shared fight chart."""
import json
import math
from pathlib import Path
from playwright.sync_api import expect


def verify(browser, base):
    fixtures = json.loads(Path('build/distance-browser.json').read_text())
    page = browser.new_page(viewport={'width': 1200, 'height': 1000})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.goto(base+'/?snapshotlocked=true', wait_until='domcontentloaded')
    chart = page.locator('#matchup-chart')
    expect(chart.locator('svg')).to_be_visible()
    original = json.loads(page.locator('#results').get_attribute('data-matchup-result'))
    assert original['positions'], 'Real matchup responses must include movement keyframes.'
    expect(page.locator('[data-matchup-metric=distance]')).to_be_enabled()

    def show(name, **extra):
        payload = {**original, **fixtures[name], **extra}
        page.locator('#results').evaluate('''(node, payload) => {
            node.dataset.matchupResult = JSON.stringify(payload);
            node.dataset.runId = 'distance-fixture-' + Math.random();
        }''', payload)
        page.wait_for_function("document.querySelector('#matchup-chart').dataset.renderedRun===document.querySelector('#results').dataset.runId")
        expect(page.locator('[data-matchup-metric=distance]')).to_be_enabled()
        page.locator('[data-matchup-metric=distance]').click()
        expect(chart.locator('svg')).to_have_attribute('aria-label', distance_label)
        return payload

    # A regex keeps champion names supplied by the real response in the label.
    import re
    distance_label = re.compile(r'^Distance between champions \(units\)')

    def geometry(selector):
        return page.locator(selector).evaluate('node=>{const r=node.getBoundingClientRect();return [r.x+scrollX,r.y+scrollY,r.width,r.height]}')

    def at(t, expected):
        chart.focus()
        chart.press('Home')
        for _ in range(int(t)):
            chart.press('Shift+ArrowRight')
        for _ in range(round((t-int(t))*10)):
            chart.press('ArrowRight')
        page.wait_for_function('''expected => Math.abs(Number(document.querySelector('.matchup-distance output').dataset.distance)-expected)<1e-6''', arg=expected)
        assert math.isclose(float(chart.get_attribute('aria-valuenow')), t, abs_tol=1e-6)
        expect(page.locator('.matchup-distance')).to_contain_text('units')

    show('chase')
    chart.scroll_into_view_if_needed()
    bounds = chart.locator('svg').bounding_box()
    page.mouse.move(bounds['x']+76+(bounds['width']-99)*.25, bounds['y']+70)
    page.wait_for_function("Math.abs(Number(document.querySelector('.matchup-distance output').dataset.distance)-375)<.01")
    at(1.5, 350)
    for width in (1200, 736, 390, 320):
        page.set_viewport_size({'width': width, 'height': 1000})
        page.wait_for_function('document.documentElement.scrollWidth <= innerWidth+1')
        at(1.5, 350)
        before = [geometry(s) for s in ('#matchup-chart', '.matchup-health', '.matchup-inspection')]
        for metric in ('health', 'damage', 'distance'):
            page.locator(f'[data-matchup-metric={metric}]').click()
            assert math.isclose(float(page.locator('.matchup-distance output').get_attribute('data-distance')),350,abs_tol=1e-6)
            after = [geometry(s) for s in ('#matchup-chart', '.matchup-health', '.matchup-inspection')]
            assert before == after, (width, metric, before, after)
        assert chart.locator('.matchup-line').count() == 1
        expect(page.locator('[data-distance-legend]')).to_be_visible()
        expect(page.locator('[data-champion-legend]').first).not_to_be_visible()
        chart.focus()
        chart.press('End')
        page.wait_for_function("Math.abs(Number(document.querySelector('.matchup-distance output').dataset.distance)-100)<1e-6")
        page.locator('#results').screenshot(path=f'build/distance-{width}.png')

    page.set_viewport_size({'width': 1200, 'height': 1000})
    show('rooted')
    at(1.5, 400)
    at(2.5, 350)
    show('windup')
    at(0.1, 500)
    at(1.1, 570)
    # Event selection shares the same cursor and distance lookup.
    select = page.locator('.matchup-event-select')
    index = select.locator('option').evaluate_all("nodes => nodes.find(node => node.textContent.startsWith('0.30 s')).value")
    select.select_option(index)
    page.wait_for_function("Math.abs(Number(document.querySelector('#matchup-chart').getAttribute('aria-valuenow'))-.3)<1e-6")
    assert math.isclose(float(page.locator('.matchup-distance output').get_attribute('data-distance')), 500, abs_tol=1e-6)
    show('jumped')
    at(0.9, 500)
    at(1, 375)
    path = chart.locator('.matchup-line.distance').get_attribute('d')
    points = [(float(x), float(y)) for x,y in re.findall(r'[ML] ([\d.e+-]+) ([\d.e+-]+)', path)]
    assert any(a[0] == b[0] and a[1] != b[1] for a,b in zip(points, points[1:])), path
    show('still')
    at(2, 0)
    assert 'NaN' not in chart.locator('svg').inner_html()
    show('chase', end=2.4)
    chart.focus()
    chart.press('End')
    page.wait_for_function("Math.abs(Number(document.querySelector('.matchup-distance output').dataset.distance)-260)<1e-6")
    path = chart.locator('.matchup-line.distance').get_attribute('d')
    coordinates = [(float(x), float(y)) for x,y in re.findall(r'[ML] ([\d.e+-]+) ([\d.e+-]+)', path)]
    width = chart.evaluate('node=>Math.max(220,node.clientWidth)')
    assert math.isclose(coordinates[-1][0], 76+2.4/5*(width-23-76), abs_tol=1e-6)
    # Missing old result telemetry is unavailable, never a fabricated zero.
    old = {**original, 'positions': []}
    page.locator('#results').evaluate('''(node,payload)=>{node.dataset.matchupResult=JSON.stringify(payload);node.dataset.runId='without-position-data';}''', old)
    expect(page.locator('[data-matchup-metric=distance]')).to_be_disabled()
    expect(page.locator('.matchup-distance output')).to_have_text('—')
    assert not errors, errors
    page.close()

    touch = browser.new_page(viewport={'width':390,'height':844}, is_mobile=True, has_touch=True)
    touch.goto(base+'/?snapshotlocked=true', wait_until='domcontentloaded')
    expect(touch.locator('#matchup-chart svg')).to_be_visible()
    touch.locator('[data-matchup-metric=distance]').tap()
    expect(touch.locator('#matchup-chart svg')).to_have_attribute('aria-label', distance_label)
    svg = touch.locator('#matchup-chart svg')
    box = svg.bounding_box()
    svg.tap(position={'x':76+(box['width']-99)*0.25, 'y':70})
    assert touch.locator('.matchup-distance output').get_attribute('data-distance')
    touch.wait_for_function('document.documentElement.scrollWidth<=innerWidth+1')
    touch.close()
    print('Browser: distance graph, exact shared cursor values, linear motion/jumps, event selection, KO cutoff, stable metrics, unavailable telemetry and touch/mobile passed.')

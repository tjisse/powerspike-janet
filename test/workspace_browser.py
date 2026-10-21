"""Keep the workspace anchored while inspecting and configuring a fight."""
from playwright.sync_api import expect


def verify(browser, base):
    page = browser.new_page(viewport={'width':1200, 'height':1000})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.goto(base+'/?snapshotlocked=true&selected=custom&slot1=1052', wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    assert page.locator('[data-collapse], .matchup-scrubber').count() == 0

    def geometry(selector):
        return page.locator(selector).evaluate('node => {const r=node.getBoundingClientRect(); return [r.x+scrollX,r.y+scrollY,r.width,r.height]}')

    def anchored(before, selector):
        after = geometry(selector)
        assert all(abs(a-b) < 1 for a,b in zip(before, after)), (selector, before, after)

    for width in (1200,736,390,320):
        page.set_viewport_size({'width':width, 'height':1000})
        page.wait_for_timeout(80)
        card, fight = geometry('#player-card'), geometry('#matchup-fightbar')
        for tab in ('runes','abilities','sequence','items'):
            page.locator(f'#player-card [data-tab={tab}]').click()
            expect(page.locator(f'#player-panel-{tab}')).to_be_visible()
            anchored(card, '#player-card')
            anchored(fight, '#matchup-fightbar')
        page.locator('#player-card [data-tab=sequence]').click()
        if not page.locator('#player-advanced').evaluate('node => node.open'):
            page.locator('#player-advanced > summary').click()
        expect(page.locator('[name=healthfraction]')).to_be_visible()
        anchored(fight, '#matchup-fightbar')
        page.locator('#player-card [data-tab=items]').click()
        assert geometry('#player-card .item-slot img')[2:] == [32,32]
        assert page.locator('#player-panel-items').evaluate('node => node.scrollWidth <= node.clientWidth+1')
        before = geometry('#loadout-tray')
        page.locator('#patch-settings > summary').click()
        expect(page.locator('#patch-panel select')).to_be_visible()
        anchored(before, '#loadout-tray')
        assert page.locator('#patch-settings').evaluate('node => !!node.closest("header.top")')
        page.keyboard.press('Escape')
        expect(page.locator('#patch-panel')).not_to_be_visible()
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth+1')

    slot = page.locator('#player-card .item-slot').first
    slot.hover()
    expect(page.locator('#detail-popover')).to_be_visible()
    anchor, preview = slot.bounding_box(), page.locator('#detail-popover').bounding_box()
    assert (preview['x']+preview['width'] <= anchor['x'] or preview['x'] >= anchor['x']+anchor['width']
            or preview['y']+preview['height'] <= anchor['y'] or preview['y'] >= anchor['y']+anchor['height'])
    slot.click()
    expect(page.locator('#item-picker')).to_have_attribute('data-catalog-ready', 'true')
    catalog = geometry('#item-picker')
    page.locator('#item-picker .catalog-search').fill('no-item-can-match-this')
    expect(page.locator('#item-picker .picker-empty')).to_be_visible()
    anchored(catalog, '#item-picker')
    page.locator('#item-picker .catalog-search').fill('')
    expect(page.locator('#item-picker .picker-empty')).not_to_be_visible()
    anchored(catalog, '#item-picker')
    page.locator('#item-picker .catalog-close').click()
    page.set_viewport_size({'width':1200, 'height':1000})
    chart = page.locator('#matchup-chart')
    chart.focus()
    chart.press('Home')
    expect(chart).to_have_attribute('aria-valuenow', '0.00')
    chart.press('ArrowRight')
    expect(chart).to_have_attribute('aria-valuenow', '0.10')
    detail = geometry('.matchup-event-detail')
    page.locator('.matchup-event-select').select_option('0')
    anchored(detail, '.matchup-event-detail')
    assert page.locator('.matchup-visual #matchup-events').count() == 1
    swap, player, opponent = (geometry(s) for s in ('[data-swap-champions]','#player-card','#opponent-card'))
    assert player[0]+player[2] <= swap[0] < swap[0]+swap[2] <= opponent[0]

    page.locator('[data-search-open=player]').click()
    modal, footer = geometry('#optimizer-dialog'), geometry('.optimizer-actions')
    page.locator('[name=searchbudget]').fill('1500')
    page.locator('.optimizer-advanced > summary').click()
    anchored(modal, '#optimizer-dialog')
    anchored(footer, '.optimizer-actions')
    page.locator('[name=searchslots]').fill('3')
    page.locator('[name=searchpool]').fill('1052,1036,1042')
    page.locator('#search-start').click()
    anchored(modal, '#optimizer-dialog')
    anchored(footer, '.optimizer-actions')
    page.wait_for_function("document.querySelector('#search-panel').dataset.status==='done'", timeout=30000)
    anchored(modal, '#optimizer-dialog')
    anchored(footer, '.optimizer-actions')
    for width in (1200,736,390,320):
        page.set_viewport_size({'width':width, 'height':1000})
        for selector in ('#optimizer','#search-panel'):
            pane = page.locator(selector)
            assert pane.evaluate('node => getComputedStyle(node).overflowY') == 'scroll'
            assert pane.evaluate('node => getComputedStyle(node).scrollbarGutter') == 'stable'
            assert pane.evaluate('node => node.scrollWidth <= node.clientWidth+1'), (width,selector)
        recommendation = page.locator('.search-alternative').first
        icons = recommendation.locator('.inventory').bounding_box()
        metrics = recommendation.locator(':scope > .search-metrics').bounding_box()
        more = recommendation.locator('.search-build-details').bounding_box()
        assert icons['y']+icons['height'] <= metrics['y'], (width, icons, metrics)
        assert metrics['y']+metrics['height'] <= more['y'], (width, metrics, more)
        last = page.locator('[data-apply-build]').last
        last.scroll_into_view_if_needed()
        box, bounds = last.bounding_box(), page.locator('#search-panel').bounding_box()
        assert bounds['x'] <= box['x'] and box['x']+box['width'] <= bounds['x']+bounds['width']
        expect(last).to_be_enabled()
        footer = geometry('.optimizer-actions')
        page.locator('.search-build-details > summary').last.click()
        anchored(footer, '.optimizer-actions')
    assert not errors, errors
    page.close()
    touch = browser.new_page(viewport={'width':390, 'height':844}, is_mobile=True, has_touch=True)
    touch.goto(base+'/?snapshotlocked=true&slot1=1052', wait_until='domcontentloaded')
    expect(touch.locator('#matchup-chart svg')).to_be_visible()
    for tab in ('runes','abilities','sequence','items'):
        touch.locator(f'#player-card [data-tab={tab}]').tap()
        expect(touch.locator(f'#player-panel-{tab}')).to_be_visible()
    touch.locator('[data-search-open=player]').tap()
    expect(touch.locator('#search-start')).to_be_visible()
    assert touch.locator('#optimizer-dialog').evaluate('node => node.scrollWidth <= node.clientWidth+1')
    touch.close()
    print('Browser: anchored tabs, patch dropdown, compact icons, keyboard timeline and bounded optimizer scrolling/results passed.')

"""Action-needed messages share a visible location and resolve without moving the fight."""
from playwright.sync_api import expect


def verify(browser, base):
    page = browser.new_page(viewport={'width':1200, 'height':1000})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.goto(base+'/?snapshotlocked=true', wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    messages = page.locator('#workspace-messages')
    expect(page.locator('#workspace-messages #parser-warning')).to_be_visible()
    assert page.locator('#patch-settings #parser-warning, #results .matchup-stale').count() == 0
    def geometry(selector):
        return page.locator(selector).evaluate('node => {const r=node.getBoundingClientRect(); return [r.y+scrollY,r.height]}')
    before = geometry('#loadout-tray')
    page.locator('[name=duration]').fill('9')
    page.locator('[name=duration]').press('Tab')
    expect(page.locator('#workspace-messages .matchup-stale')).to_be_visible()
    assert geometry('#loadout-tray') == before
    expect(messages).to_have_attribute('data-active', 'true')
    for width in (1200,736,390,320):
        page.set_viewport_size({'width':width,'height':1000})
        page.wait_for_timeout(80)
        for selector in ('#parser-warning .apply', '.matchup-stale .apply'):
            button = messages.locator(selector)
            bounds, frame = button.bounding_box(), page.locator('.workspace-message-list').bounding_box()
            assert frame['y'] <= bounds['y'] and bounds['y']+bounds['height'] <= frame['y']+frame['height']+1, (width,selector,bounds,frame)
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth+1')
    messages.screenshot(path='build/workspace-messages-mobile.png')
    before = geometry('#loadout-tray')
    previous = page.locator('#results').get_attribute('data-run-id')
    messages.locator('.matchup-stale .apply').click()
    page.wait_for_function('old => document.querySelector("#results").dataset.runId !== old', arg=previous)
    expect(messages.locator('.matchup-stale')).not_to_be_visible()
    assert geometry('#loadout-tray') == before
    # Invalid incoming scenarios explain their recovery in the same place.
    page.goto(base+'/?mode=practice&level=1&qrank=5&snapshotlocked=true', wait_until='domcontentloaded')
    expect(messages.locator('#evaluation-notice')).to_be_visible()
    expect(page.locator('#results')).to_be_empty()
    messages.get_by_role('button', name='Run again', exact=True).click()
    expect(messages.locator('#evaluation-notice')).not_to_be_visible()
    # Storage failures need attention; ordinary success acknowledgements stay local.
    page.goto(base+'/?snapshotlocked=true', wait_until='domcontentloaded')
    page.get_by_text('Saved scenarios',exact=True).click()
    page.evaluate('()=>{window.originalSetItem=Storage.prototype.setItem; Storage.prototype.setItem=function(){throw new Error("Storage blocked")};}')
    page.get_by_role('button', name='Save locally',exact=True).click()
    expect(messages.locator('#workspace-feedback')).to_contain_text('Storage blocked')
    expect(messages.locator('#workspace-feedback')).to_be_visible()
    messages.get_by_role('button', name='Open saves', exact=True).click()
    assert page.locator('#scenario-tools').evaluate('node => node.open')
    page.evaluate('()=>{Storage.prototype.setItem=window.originalSetItem}')
    page.get_by_role('button', name='Save locally',exact=True).click()
    expect(messages.locator('#workspace-feedback')).not_to_be_visible()
    assert not errors, errors
    page.close()
    print('Browser: unified action messages, visible simultaneous prompts, stable layout, direct rerun, error recovery and storage feedback passed.')

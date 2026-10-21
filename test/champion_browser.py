"""Champion presets preserve draft settings without replacing completed combat."""
import json
from playwright.sync_api import expect


def verify(browser, base):
    page = browser.new_page(viewport={'width':1200,'height':1000})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    url = (base+'/?mode=duel&champion=Annie&opponent=Nidalee&opponentform=cougar&selected=custom'
           '&snapshotlocked=true&level=6&opponentlevel=9&slot2=1052&enemyslot6=1036'
           '&shard1=0&shard2=0&shard3=0&enemyshard1=0&enemyshard2=0&enemyshard3=0'
           '&movement=hold&opponentmovement=hold&distance=0&duration=2&samples=1')
    page.goto(url, wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    def documents():
        return json.loads(page.locator('#champion-configurations').get_attribute('data-json'))
    def open_slots(who):
        page.locator(f'[data-champion-slots={who}]').click()
        expect(page.locator('#champion-slots-dialog')).to_be_visible()
    def close_slots():
        page.get_by_role('button', name='Close champion save slots', exact=True).click()
    def action(kind, slot):
        page.locator(f'[data-champion-slot-action={kind}][data-slot="{slot}"]').click()
    def wait_champion(who, champion, level):
        page.wait_for_function('([who,id,level])=>{const data=JSON.parse(document.querySelector("#champion-configurations").dataset.json)[who];return data.champion.champion===id && data.champion.level===level}', arg=[who,champion,level])
        page.wait_for_function('!document.querySelector("#powerspike").classList.contains("is-pending")')
    first_run = page.locator('#results').get_attribute('data-run-id')
    original = documents()
    assert original['opponent']['champion']['loadout']['items'] == ['1036']
    page.locator('[name=level]').select_option('7')
    wait_champion('player', 'Annie', 7)
    draft = documents()['player']
    open_slots('player')
    page.locator('#champion-slot-name-0').fill('Annie draft <Q>')
    action('save', 0)
    expect(page.locator('#champion-slots-status')).to_contain_text('Saved Annie draft <Q>')
    assert page.locator('#results').get_attribute('data-run-id') == first_run
    close_slots()
    open_slots('opponent')
    action('save', 1)
    expect(page.locator('#champion-slots-status')).to_contain_text('slot 2')
    close_slots()
    page.reload(wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    restored_run = page.locator('#results').get_attribute('data-run-id')
    open_slots('player')
    expect(page.locator('#champion-slot-name-0')).to_have_value('Annie draft <Q>')
    action('load', 0)
    wait_champion('player', 'Annie', 7)
    assert documents()['player'] == draft
    assert documents()['opponent'] == original['opponent']
    assert page.locator('#results').get_attribute('data-run-id') == restored_run
    expect(page.locator('.matchup-stale')).to_be_visible()
    open_slots('player')
    action('load', 1)
    wait_champion('player', 'Nidalee', 9)
    assert documents()['player'] == original['opponent']
    expect(page.locator('[name=form]')).to_have_value('cougar')
    assert json.loads(page.locator('#player-card').get_attribute('data-items')) == ['', '', '', '', '', '1036']
    # Swapping twice restores the entire configuration, including inventory holes.
    page.goto(url, wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    before = documents()
    trace = page.locator('#results').get_attribute('data-matchup-result')
    page.get_by_role('button', name='⇄ Swap champions', exact=True).click()
    wait_champion('player', 'Nidalee', 9)
    assert documents() == {'player':before['opponent'], 'opponent':before['player']}
    assert page.locator('#results').get_attribute('data-matchup-result') == trace
    expect(page.locator('#champion-action-status')).to_contain_text('Run matchup')
    page.get_by_role('button', name='⇄ Swap champions', exact=True).click()
    wait_champion('player', 'Annie', 6)
    assert documents() == before
    # Both sides expose the same four slots. Replacement and removal persist.
    open_slots('player')
    page.locator('#champion-slot-name-0').fill('Replacement')
    action('save', 0)
    expect(page.locator('#champion-slots-status')).to_contain_text('Saved Replacement')
    action('clear', 1)
    expect(page.locator('#champion-slots-status')).to_have_text('Slot 2 cleared.')
    for index in (1,2,3):
        expect(page.locator(f'[data-champion-slot-action=load][data-slot="{index}"]')).to_be_disabled()
    # A blocked storage write must retain the previous save and report failure.
    saved = page.evaluate('localStorage.getItem("powerspike.champions.v1")')
    page.evaluate('()=>{window.originalSetItem=Storage.prototype.setItem;Storage.prototype.setItem=function(){throw new Error("Storage blocked")};}')
    action('save', 2)
    expect(page.locator('#champion-slots-status')).to_have_text('Storage blocked')
    assert page.evaluate('localStorage.getItem("powerspike.champions.v1")') == saved
    page.evaluate('()=>{Storage.prototype.setItem=window.originalSetItem}')
    action('save', 0)
    expect(page.locator('#champion-slots-status')).to_contain_text('Saved Replacement')
    for width in (736,390,320):
        page.set_viewport_size({'width':width,'height':1000})
        page.wait_for_function('document.documentElement.scrollWidth<=innerWidth+1')
        assert page.locator('#champion-slots-dialog').evaluate('(node)=>node.scrollWidth<=node.clientWidth+1')
        expect(page.locator('[data-champion-slot-action=load][data-slot="0"]')).to_be_visible()
    page.locator('#champion-slots-dialog').screenshot(path='build/champion-slots-mobile.png')
    page.set_viewport_size({'width':1200,'height':1000})
    page.locator('#champion-slots-dialog').screenshot(path='build/champion-slots-desktop.png')
    close_slots()
    page.set_viewport_size({'width':320,'height':1000})
    page.wait_for_function('document.documentElement.scrollWidth<=innerWidth+1')
    page.locator('.matchup-fightbar').screenshot(path='build/champion-swap-mobile.png')
    page.set_viewport_size({'width':1200,'height':1000})
    # Patch mismatch is visible and cannot silently mix retained data.
    collection = json.loads(saved)
    invalid = json.loads(collection['slots'][0]['document'])
    invalid['snapshot'] = '0'*64
    collection['slots'][0]['document'] = json.dumps(invalid)
    page.evaluate('value=>localStorage.setItem("powerspike.champions.v1",value)', json.dumps(collection))
    open_slots('opponent')
    expect(page.locator('[data-champion-slot-action=load][data-slot="0"]')).to_be_disabled()
    expect(page.locator('#champion-slots-list')).to_contain_text('Switch to the saved patch snapshot')
    close_slots()
    page.evaluate('value=>localStorage.setItem("powerspike.champions.v1",value)', saved)
    # A corrupt but same-snapshot participant reaches server validation.
    collection = json.loads(saved)
    invalid = json.loads(collection['slots'][0]['document'])
    invalid['champion']['level'] = 99
    collection['slots'][0]['document'] = json.dumps(invalid)
    page.evaluate('value=>localStorage.setItem("powerspike.champions.v1",value)', json.dumps(collection))
    open_slots('player'); action('load', 0)
    expect(page.locator('#config-status')).not_to_be_empty()
    assert documents() == before
    assert page.locator('#results').get_attribute('data-matchup-result') == trace
    page.evaluate('value=>localStorage.setItem("powerspike.champions.v1",value)', saved)
    # Recovery after a rejected save must allow the next valid load.
    open_slots('player'); action('load', 0)
    expect(page.locator('#champion-slots-dialog')).not_to_be_visible()
    expect(page.locator('#config-status')).to_be_empty()
    previous = page.locator('#results').get_attribute('data-run-id')
    page.locator('.matchup-run').click()
    page.wait_for_function('(previous)=>document.querySelector("#results").dataset.runId!==previous', arg=previous)
    assert page.locator('#results').get_attribute('data-matchup-result') == trace
    page.goto(url.replace('selected=custom', 'selected=penetration'), wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    preset = documents()
    assert preset['player']['slots'] == ['3089','3135','3020','','','']
    page.get_by_role('button', name='⇄ Swap champions', exact=True).click()
    wait_champion('player', 'Nidalee', 9)
    assert documents() == {'player':preset['opponent'], 'opponent':preset['player']}
    assert not errors, errors
    page.close()
    print('Browser: four champion slots, draft saves, cross-side loading, reload/replace/clear, exact swap, forms/holes, mobile and storage/validation recovery passed.')

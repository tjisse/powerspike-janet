"""Lazy pickers retain search, exact snapshots, error recovery and safe text."""
import json
import time
from urllib.parse import parse_qs, urlsplit
from playwright.sync_api import Error, expect


def verify(browser, base):
    url = base+'/?mode=duel&champion=Annie&opponent=Nidalee&opponentform=cougar&selected=custom&snapshotlocked=true&duration=2&samples=1'
    page = browser.new_page(viewport={'width':1200, 'height':1000})
    errors, requests = [], []
    page.on('pageerror', lambda error: errors.append(str(error)))
    failed = True
    def catalog(route):
        nonlocal failed
        requests.append(parse_qs(urlsplit(route.request.url).query))
        if failed:
            failed = False
            route.abort()
        else:
            route.continue_()
    page.route('**/catalog?*', catalog)
    page.goto(url, wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    assert requests == []
    assert page.locator('.catalog-card').count() == 0
    run = page.locator('#results').get_attribute('data-run-id')
    page.locator('#player-card .item-slot').first.click()
    expect(page.locator('#item-picker .catalog-status')).to_have_text('Could not load items. Please retry.')
    assert page.locator('#item-picker .catalog-card').count() == 0
    page.locator('#item-picker .catalog-retry').click()
    expect(page.locator('#item-picker')).to_have_attribute('data-catalog-ready', 'true')
    assert page.locator('#item-picker .catalog-card').count() == 870
    assert len(requests) == 2
    page.locator('#item-picker .catalog-search').fill('amplifying tome')
    expect(page.locator('#item-picker [data-item-id="1052"]')).to_be_visible()
    page.locator('#item-picker .catalog-scope').select_option('all')
    assert page.locator('#item-picker .catalog-card:visible').count() >= 1
    # A missing tooltip must not leave fabricated/default build values visible.
    page.route('**/details/item?*', lambda route: route.abort())
    page.locator('#item-picker [data-item-id="1052"]').focus()
    expect(page.locator('#detail-popover')).to_contain_text('Item description unavailable.')
    assert page.locator('#detail-popover .tooltip-value').count() == 0
    page.unroute('**/details/item?*')
    page.locator('#item-picker .catalog-search').focus()
    with page.expect_response(lambda response: urlsplit(response.url).path == '/details/item') as tooltip:
        page.locator('#item-picker [data-item-id="1052"]').focus()
    assert tooltip.value.status == 200
    expect(page.locator('#detail-popover')).to_contain_text('Ability power')
    document_text = page.locator('#configuration-data').get_attribute('data-json')
    page.evaluate('text => {document.getElementById("configuration-data").dataset.json=text+" "}', document_text)
    expect(page.locator('#detail-popover')).not_to_be_visible()
    page.evaluate('text => {document.getElementById("configuration-data").dataset.json=text}', document_text)
    page.locator('#item-picker [data-item-id="1052"]').press('Enter')
    page.wait_for_function('JSON.parse(document.querySelector("#champion-configurations").dataset.json).player.slots[0] === "1052"')
    assert page.locator('#results').get_attribute('data-run-id') == run
    page.locator('#player-card .item-slot').first.click()
    expect(page.locator('#item-picker')).to_have_attribute('data-catalog-ready', 'true')
    assert len(requests) == 2, 'Reopening the same snapshot downloaded the catalog again.'
    expect(page.locator('#item-picker .catalog-search')).to_have_value('amplifying tome')
    page.locator('#item-picker .catalog-close').click()
    page.get_by_role('button', name='Select opponent', exact=True).click()
    expect(page.locator('#champion-picker')).to_have_attribute('data-catalog-ready', 'true')
    assert page.locator('#champion-picker .catalog-card').count() == 173
    page.locator('#champion-picker .catalog-search').fill('ahri')
    expect(page.locator('#champion-picker [data-champion-id=Ahri]')).to_be_visible()
    page.locator('#champion-picker [data-champion-id=Ahri] img').click()
    page.wait_for_function('JSON.parse(document.querySelector("#champion-configurations").dataset.json).opponent.champion.champion === "Ahri"')
    assert page.locator('#results').get_attribute('data-run-id') == run
    assert not errors, errors
    page.close()

    # Synthetic response races check DOM/state isolation, not game mechanics.
    race = browser.new_page(viewport={'width':390, 'height':1000})
    race.goto(url, wait_until='domcontentloaded')
    expect(race.locator('#matchup-chart svg')).to_be_visible()
    document = json.loads(race.locator('#configuration-data').get_attribute('data-json'))
    old_snapshot = document['scenario']['snapshot']
    new_snapshot = 'b'*64
    pending = []
    def racing(route):
        query = parse_qs(urlsplit(route.request.url).query)
        snapshot = query['snapshot'][0]
        if snapshot == old_snapshot:
            pending.append(route)
            return
        record = {'id':'1052', 'name':'New <img src=x onerror="window.catalogInjected=true">',
                  'icon':f'/assets/16.19.1/{old_snapshot}/item/1052.png', 'gold':123,
                  'rift':True, 'description':'Fixture metadata', 'tags':[]}
        route.fulfill(json={'patch':'16.19.1', 'snapshot':snapshot, 'kind':'items', 'records':[record]})
    race.route('**/catalog?*', racing)
    race.locator('#player-card .item-slot').first.click()
    expect(race.locator('#item-picker .catalog-status')).to_have_text('Loading items…')
    deadline = time.monotonic()+3
    while not pending and time.monotonic() < deadline:
        race.wait_for_timeout(10)
    assert len(pending) == 1
    document['scenario']['snapshot'] = new_snapshot
    race.evaluate('text => {document.getElementById("configuration-data").dataset.json=text}', json.dumps(document))
    expect(race.locator('#item-picker')).to_have_attribute('data-catalog-ready', 'true')
    expect(race.locator('#item-picker .catalog-card span')).to_have_text('New <img src=x onerror="window.catalogInjected=true">')
    try:
        pending[0].fulfill(json={'patch':'16.19.1', 'snapshot':old_snapshot, 'kind':'items', 'records':[]})
    except Error:
        pass  # Aborting an obsolete in-flight response is expected.
    assert race.locator('#item-picker .catalog-card').count() == 1
    assert race.locator('#item-picker .catalog-card img').count() == 1
    assert not race.evaluate('Boolean(window.catalogInjected)')
    race.close()

    wrong = browser.new_page()
    wrong.goto(url, wait_until='domcontentloaded')
    expect(wrong.locator('#matchup-chart svg')).to_be_visible()
    wrong.route('**/catalog?*', lambda route: route.fulfill(json={
        'patch':'16.19.1', 'snapshot':'0'*64, 'kind':'items', 'records':[]}))
    wrong.locator('#player-card .item-slot').first.click()
    expect(wrong.locator('#item-picker .catalog-status')).to_contain_text('Could not load items.')
    assert wrong.locator('#item-picker .catalog-card').count() == 0
    wrong.unroute('**/catalog?*')
    wrong.locator('#item-picker .catalog-retry').click()
    expect(wrong.locator('#item-picker')).to_have_attribute('data-catalog-ready', 'true')
    assert wrong.locator('#item-picker .catalog-card').count() == 870
    wrong.close()
    legacy = browser.new_page()
    legacy.goto(base+'/?mode=legacy&champion=Annie&selected=custom&snapshotlocked=true', wait_until='domcontentloaded')
    expect(legacy.locator('#timeline')).to_be_visible()
    assert legacy.locator('#scenario-data').count() == 0
    legacy.locator('#loadout-tray .item-slot').first.click()
    expect(legacy.locator('#item-picker')).to_have_attribute('data-catalog-ready', 'true')
    legacy.locator('#item-picker [data-item-id="1052"]').focus()
    expect(legacy.locator('#detail-popover')).to_contain_text('Build-specific values are not available in this legacy view.')
    expect(legacy.locator('#detail-popover')).not_to_contain_text('Loading item description')
    legacy.locator('#item-picker [data-item-id="1052"]').press('Enter')
    expect(legacy.locator('#loadout-tray .item-slot').first).to_have_attribute('data-item-id', '1052')
    legacy.close()
    print('Browser: lazy catalog loading/reuse, search/scope, retry, server tooltip recovery, keyboard/nested selection, snapshot races and safe provider text passed.')

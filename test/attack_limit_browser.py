"""The visible stats and both timelines use the reviewed baseline speed cap."""
import json
from urllib.parse import urlencode
from playwright.sync_api import expect


def verify(browser, base):
    page = browser.new_page(viewport={'width':1200, 'height':1000})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    fields = {'mode':'duel', 'champion':'Gnar', 'opponent':'Gnar', 'form':'mini', 'opponentform':'mini',
              'level':18, 'opponentlevel':18, 'selected':'custom', 'snapshotlocked':'true',
              'duration':0.8, 'distance':0, 'samples':1, 'seed':7, 'movement':'hold', 'opponentmovement':'hold',
              'abilities':'false', 'opponentabilities':'false'}
    fields.update({prefix+f'shard{index}':0 for prefix in ('','enemy') for index in (1,2,3)})
    for index, item in enumerate(['3046','3115','3091','3032','2512','6675'], 1):
        fields[f'slot{index}'] = item
        fields[f'enemyslot{index}'] = item
    page.goto(base+'/?'+urlencode(fields), wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    result = json.loads(page.locator('#results').get_attribute('data-matchup-result'))
    for owner, card in [('player','player'), ('opponent','opponent')]:
        detail = json.loads(page.locator(f'#{card}-card button[data-details]').first.get_attribute('data-details'))
        assert float(dict(detail['stats'])['Attack speed']) == 3
        hits = [event for event in result['trace'] if event['kind']=='damage' and event['source']=='attack' and event['actor']==owner]
        assert len(hits) == 3
        for index, event in enumerate(hits):
            assert abs(event['at'] - (0.3/3 + index/3)) < 1e-6
    assert 'cap 2.5' not in page.locator('#coverage').inner_text()
    # An explicit rerun must preserve the exported fight and seeded outcomes.
    document = page.locator('#workspace-data').get_attribute('data-json')
    assert page.locator('#scenario').evaluate('(form)=>form.checkValidity()')
    previous = page.locator('#results').get_attribute('data-run-id')
    page.locator('.matchup-run').click()
    page.wait_for_function('previous=>document.querySelector("#results").dataset.runId!==previous', arg=previous)
    page.wait_for_function('!document.querySelector("#powerspike").classList.contains("is-pending")')
    assert json.loads(page.locator('#results').get_attribute('data-matchup-result')) == result
    assert page.locator('#workspace-data').get_attribute('data-json') == document
    page.set_viewport_size({'width':320, 'height':1000})
    page.wait_for_function('document.documentElement.scrollWidth <= innerWidth+1')
    assert not errors, errors
    page.close()
    # Native practice forms accept the same fractional duration as saved fights.
    native = browser.new_page(java_script_enabled=False)
    native.goto(base+'/?'+urlencode({**fields, 'mode':'practice'}), wait_until='domcontentloaded')
    assert native.locator('#duration').input_value() == '0.8'
    assert native.locator('#scenario').evaluate('(form)=>form.checkValidity()')
    native.close()
    print('Browser: reviewed 3.0 attack-speed stats, both capped timelines, exact reruns and mobile layout passed.')

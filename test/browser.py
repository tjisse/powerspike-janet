from playwright.sync_api import expect, sync_playwright
import playwright
import argparse, json, os, subprocess, tempfile, time, urllib.parse, urllib.request
from pathlib import Path
from runtime import port, running, clean_env

def verify_fixed_forms(browser, base, champion, ranged_form, melee_form, ranged_name, melee_name):
    page = browser.new_page(viewport={'width':1200,'height':1000})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    url = (base+f'/?mode=duel&champion={champion}&opponent={champion}&selected=custom&snapshotlocked=true'
           f'&form={ranged_form}&opponentform={melee_form}&level=1&opponentlevel=1'
           '&movement=hold&opponentmovement=hold&distance=200&duration=1')
    if champion == 'Jayce':
        url += '&slot1=1036&enemyslot1=1036'
    page.goto(url, wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    def result():
        return json.loads(page.locator('#results').get_attribute('data-matchup-result'))
    def document():
        return json.loads(page.locator('#scenario-data').get_attribute('data-json'))['scenario']
    def change(who, form):
        previous = page.locator('#results').get_attribute('data-run-id')
        name = 'form' if who == 'player' else 'opponentform'
        side = 'player' if who == 'player' else 'target'
        page.locator(f'#{who}-card [name={name}]').select_option(form)
        page.wait_for_function('([side,form])=>JSON.parse(document.querySelector("#configuration-data").dataset.json).scenario[side].form === form', arg=[side,form])
        assert page.locator('#results').get_attribute('data-run-id') == previous
        page.locator('.matchup-run').click()
        page.wait_for_function('(previous)=>document.querySelector("#results").dataset.runId !== previous', arg=previous)
    assert result()['names'] == [f'{champion} ({ranged_name})', f'{champion} ({melee_name})']
    def stats_for(who):
        return dict(json.loads(page.locator(f'#{who}-card button[data-details]').first.get_attribute('data-details'))['stats'])
    if champion == 'Jayce':
        for label in ('Armor', 'Magic resist'):
            assert abs(float(stats_for('opponent')[label]) - float(stats_for('player')[label]) - 5.75) < .01
    if champion == 'Elise':
        assert float(stats_for('player')['Move speed']) == 330
        assert float(stats_for('opponent')['Move speed']) == 355
        expect(page.locator('[name=rrank]').locator('..')).to_contain_text('Additional R points (free first rank included)')
    if champion in ('Nidalee', 'Elise', 'Jayce'):
        speed = {'Nidalee': 2500, 'Elise': 1600, 'Jayce': 2000}[champion]
        attack_speed = {'Nidalee': .638, 'Elise': .625, 'Jayce': .658}[champion]
        hit = next(row for row in result()['trace'] if row['kind'] == 'damage' and row['source'] == 'attack')
        assert abs(hit['at'] - (.3 / attack_speed + 200 / speed)) < 1e-6
    if champion == 'Nidalee':
        page.goto(base+'/?mode=duel&champion=Nidalee&opponent=Nidalee&form=human&opponentform=human'
                  '&level=1&opponentlevel=1&selected=custom&snapshotlocked=true&abilities=false&opponentabilities=false'
                  '&movement=hold&opponentmovement=hold&distance=300&duration=5.3', wait_until='domcontentloaded')
        expect(page.locator('#matchup-chart svg')).to_be_visible()
        for who in ('player', 'opponent'):
            hits = [row for row in result()['trace'] if row['kind'] == 'damage' and row['source'] == 'attack' and row['actor'] == who]
            assert len(hits) == 4
            for index, hit in enumerate(hits):
                assert abs(hit['at'] - ((index + .3) / .638 + 300 / 2500)) < 1e-6
        # Restore this case's original forms before the existing UI checks.
        page.goto(url, wait_until='domcontentloaded')
        expect(page.locator('#matchup-chart svg')).to_be_visible()
    if champion == 'Gnar':
        for who, expected in [('player', {'Health':540, 'Attack damage':60, 'Armor':32, 'Magic resist':30, 'Attack range':400}),
                              ('opponent', {'Health':640, 'Attack damage':66, 'Armor':35.5, 'Magic resist':33.5, 'Attack range':175})]:
            for label, value in expected.items():
                assert float(stats_for(who)[label]) == value
    assert 'Downloading ability data' not in page.locator('#results').inner_text()
    assert all(row['actor'] == 'player' for row in result()['trace'] if row['kind'] == 'damage')
    assert any(row['kind'] == 'damage' for row in result()['trace'])
    change('player', melee_form)
    assert not any(row['kind'] == 'damage' for row in result()['trace'])
    change('opponent', ranged_form)
    assert any(row['kind'] == 'damage' and row['actor'] == 'opponent' for row in result()['trace'])
    if champion in ('Nidalee', 'Elise', 'Jayce'):
        hit = next(row for row in result()['trace'] if row['kind'] == 'damage' and row['source'] == 'attack')
        assert abs(hit['at'] - (.3 / attack_speed + 200 / speed)) < 1e-6
    assert document()['player']['form'] == melee_form
    assert document()['target']['form'] == ranged_form
    page.get_by_text('Saved scenarios',exact=True).click()
    page.get_by_role('button', name='Create share link', exact=True).click()
    shared = browser.new_page()
    shared.goto(page.locator('#scenario-link').input_value(), wait_until='domcontentloaded')
    expect(shared.locator('#matchup-chart svg')).to_be_visible()
    assert json.loads(shared.locator('#results').get_attribute('data-matchup-result')) == result()
    shared.close()
    page.locator('#results').screenshot(path=f'build/{champion.lower()}-forms-desktop.png')
    for width in (736,390,320):
        page.set_viewport_size({'width':width,'height':1000})
        page.wait_for_function('document.documentElement.scrollWidth <= innerWidth + 1')
        expect(page.locator('#player-card [name=form]')).to_be_visible()
        expect(page.locator('#opponent-card [name=opponentform]')).to_be_visible()
    page.locator('#results').screenshot(path=f'build/{champion.lower()}-forms-mobile.png')
    page.goto(base+f'/?mode=practice&champion={champion}&form={ranged_form}&level=1&selected=custom&snapshotlocked=true'
              '&abilities=false&movement=hold&distance=200&duration=1', wait_until='domcontentloaded')
    expect(page.locator('#timeline')).to_be_visible()
    assert json.loads(page.locator('#timeline').get_attribute('data-events'))
    expect(page.locator('#ranks')).to_contain_text('Active abilities excluded in this fixed form')
    page.locator('#scenario [name=form]').select_option(melee_form)
    page.wait_for_function('(form)=>JSON.parse(document.querySelector("#scenario-data").dataset.json).scenario.player.form === form', arg=melee_form)
    assert not json.loads(page.locator('#timeline').get_attribute('data-events'))
    expect(page.locator('.chart-coverage')).to_contain_text('Fixed form · ordinary attacks')
    page.wait_for_function('document.documentElement.scrollWidth <= innerWidth + 1')
    page.locator('#loadout-tray').screenshot(path=f'build/{champion.lower()}-form-practice-mobile.png')
    if champion == 'Jayce':
        for next_champion in ('Nidalee', 'Jayce'):
            page.get_by_role('button', name='Change champion', exact=True).click()
            page.locator(f'#champion-picker [data-champion-id={next_champion}]').click()
            page.wait_for_function('(id)=>JSON.parse(document.querySelector("#scenario-data").dataset.json).scenario.player.champion === id', arg=next_champion)
            assert 'form' not in document()['player']
            expect(page.locator('#scenario [name=form]')).to_have_value('')
            if next_champion == 'Nidalee':
                page.locator('#scenario [name=form]').select_option('human')
                page.wait_for_function('JSON.parse(document.querySelector("#scenario-data").dataset.json).scenario.player.form === "human"')
    if champion == 'Elise':
        page.set_viewport_size({'width':1200,'height':1000})
        page.goto(base+'/?mode=practice&champion=Elise&form=spider&level=1&selected=custom&snapshotlocked=true'
                  '&abilities=false&movement=hold&distance=0&duration=1&healthfraction=0.5&mr=0', wait_until='domcontentloaded')
        expect(page.locator('#timeline')).to_be_visible()
        events = json.loads(page.locator('#timeline').get_attribute('data-events'))
        assert len([event for event in events if event['source'] == 'EliseSpiderQueen']) == 1
        expect(page.locator('#results')).to_contain_text('Spider Queen')
        assert 'EliseSpiderQueen' not in page.locator('#results').inner_text()
        page.get_by_text('Runes & spells', exact=True).click()
        page.get_by_text('Strategies, ranks & activation rules', exact=True).click()
        expect(page.locator('[name=rrank]').locator('..')).to_contain_text('Additional R points (free first rank included)')
        page.locator('#results').screenshot(path='build/elise-spider-queen-desktop.png')
    if champion == 'Gnar':
        page.set_viewport_size({'width':1200,'height':1000})
        page.goto(base+'/?mode=practice&champion=Gnar&form=mini&level=15&selected=custom&snapshotlocked=true'
                  '&abilities=false&movement=hold&distance=200&duration=1', wait_until='domcontentloaded')
        expect(page.locator('#timeline')).to_be_visible()
        def practice_stats():
            return dict(json.loads(page.locator('#champion-display button[data-details]').get_attribute('data-details'))['stats'])
        assert float(practice_stats()['Move speed']) == 349
        assert abs(float(practice_stats()['Attack range']) - (400 + 1400 / 17)) < .01
        page.locator('#level').select_option('16')
        page.wait_for_function('JSON.parse(document.querySelector("#scenario-data").dataset.json).scenario.player.level === 16')
        assert float(practice_stats()['Move speed']) == 351
        page.locator('#level').select_option('18')
        page.wait_for_function('JSON.parse(document.querySelector("#scenario-data").dataset.json).scenario.player.level === 18')
        assert float(practice_stats()['Move speed']) == 355
        assert float(practice_stats()['Attack range']) == 500
        page.locator('#scenario [name=form]').select_option('mega')
        page.wait_for_function('JSON.parse(document.querySelector("#scenario-data").dataset.json).scenario.player.form === "mega"')
        assert float(practice_stats()['Move speed']) == 335
        assert float(practice_stats()['Health']) == 2714
        assert abs(float(practice_stats()['Attack damage']) - 162.9) < .01
        assert not json.loads(page.locator('#timeline').get_attribute('data-events'))
        page.locator('#coverage > summary').click()
        expect(page.locator('#coverage')).to_contain_text('Rage, automatic transformations')
        expect(page.locator('#coverage')).to_contain_text('15-second duration')
        page.locator('#loadout-tray').screenshot(path='build/gnar-form-level18.png')
    assert not errors, errors
    page.close()
    native_context = browser.new_context(java_script_enabled=False)
    native = native_context.new_page()
    native.goto(url,wait_until='domcontentloaded')
    native.locator('#player-card [name=form]').select_option(melee_form)
    native.locator('.matchup-run').click()
    native.wait_for_url(f'**form={melee_form}**', wait_until='domcontentloaded')
    assert json.loads(native.locator('#scenario-data').get_attribute('data-json'))['scenario']['player']['form'] == melee_form
    native_context.close()
    print(f'Browser: {champion} fixed forms, explicit reruns, shared reproduction, practice controls, native submission and mobile layouts passed.')

def verify_kayle_levels(browser, base):
    page = browser.new_page(viewport={'width':1200,'height':1000})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.goto(base+'/?mode=duel&champion=Kayle&opponent=Kayle&selected=custom'
              '&level=5&opponentlevel=16&slot1=3153&enemyslot1=3153'
              '&abilities=false&opponentabilities=false&movement=hold&opponentmovement=hold'
              '&distance=200&duration=1', wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    payload = json.loads(page.locator('#results').get_attribute('data-matchup-result'))
    damage = [row for row in payload['trace'] if row['kind'] == 'damage']
    assert damage and all(row['actor'] == 'opponent' for row in damage)
    assert any(row['source'] == 'attack' for row in damage)
    def range_for(who):
        data = json.loads(page.locator(f'#{who}-card button[data-details]').first.get_attribute('data-details'))
        return float(next(value for caption,value in data['stats'] if caption == 'Attack range'))
    assert range_for('player') == 175
    assert range_for('opponent') == 625
    before = page.locator('#results').get_attribute('data-run-id')
    page.locator('#player-card [name=level]').select_option('6')
    page.wait_for_function('JSON.parse(document.querySelector("#configuration-data").dataset.json).scenario.player.level === 6')
    page.locator('.matchup-run').click()
    page.wait_for_function('(previous)=>document.querySelector("#results").dataset.runId !== previous', arg=before)
    payload = json.loads(page.locator('#results').get_attribute('data-matchup-result'))
    for who in ('player', 'opponent'):
        assert any(row['kind'] == 'damage' and row['actor'] == who and row['source'] == 'attack'
                   for row in payload['trace'])
    assert range_for('player') == 525
    before = page.locator('#results').get_attribute('data-run-id')
    page.locator('#opponent-card [name=opponentlevel]').select_option('5')
    page.wait_for_function('JSON.parse(document.querySelector("#configuration-data").dataset.json).scenario.target.level === 5')
    page.locator('.matchup-run').click()
    page.wait_for_function('(previous)=>document.querySelector("#results").dataset.runId !== previous', arg=before)
    payload = json.loads(page.locator('#results').get_attribute('data-matchup-result'))
    damage = [row for row in payload['trace'] if row['kind'] == 'damage']
    assert damage and all(row['actor'] == 'player' for row in damage)
    assert range_for('opponent') == 175
    assert page.locator('#verification-progress, #source-evidence').count() == 0
    for width in (736,390,320):
        page.set_viewport_size({'width':width,'height':1000})
        page.wait_for_function('document.documentElement.scrollWidth <= innerWidth + 1')
    assert not errors, errors
    page.close()
    print('Browser: Kayle level changes, both participants, range details, attack events and mobile layouts passed.')

def verify_practice_controls(browser, base):
    page = browser.new_page(viewport={'width':1440,'height':1080})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.goto(base+'/?mode=practice&champion=Annie&selected=custom', wait_until='domcontentloaded')
    assert page.locator('#item-comparison, .coverage-link').count() == 0
    page.get_by_role('button', name='Goal: burst', exact=True).click()
    assert page.locator('#optimizer-dialog').evaluate('(node)=>node.open')
    page.get_by_role('button', name='Close optimization', exact=True).click()
    page.locator('#coverage > summary').click()
    assert page.locator('#coverage').evaluate('(node)=>node.open')
    assert not page.locator('#patch-settings').evaluate('(node)=>node.open')
    page.locator('#level').select_option('1')
    page.wait_for_function("document.querySelector('#ranks [data-ability-slot=q]').dataset.rank === '1'")
    page.get_by_text('Runes & spells', exact=True).click()
    page.get_by_text('Strategies, ranks & activation rules', exact=True).click()
    page.locator('[name=qrank]').select_option('5')
    page.locator('#results[data-evaluation-error=true]').wait_for(state='attached')
    expect(page.locator('#workspace-messages #evaluation-notice')).to_be_visible()
    page.get_by_text('Saved scenarios', exact=True).click()
    for name in ['Save locally', 'Export JSON', 'Create share link']:
        expect(page.get_by_role('button', name=name, exact=True)).to_be_disabled()
    page.get_by_role('button', name='Report a problem', exact=True).click()
    expect(page.locator('#problem-report-form')).to_be_hidden()
    expect(page.locator('#problem-report-status')).to_contain_text('Fix the scenario and rerun')
    page.keyboard.press('Escape')
    page.locator('[name=qrank]').select_option('-1')
    page.locator('#timeline').wait_for()
    expect(page.get_by_role('button', name='Save locally', exact=True)).to_be_enabled()
    assert not errors, errors
    page.close()

def verify_runes(browser, base):
    page = browser.new_page(viewport={'width':1440,'height':1080})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.goto(base+'/?mode=practice&champion=Annie&selected=custom&level=6&shard1=5008&shard2=5008&shard3=5011&runepage1=8210&runepage2=8237', wait_until='domcontentloaded')
    page.locator('#timeline').wait_for()
    assert page.locator('#loadout-tray .shard').count() == 3
    page.locator('#loadout-tray .shard').first.hover()
    assert '9.00' in page.locator('#detail-popover').inner_text()
    page.locator('#ranks [data-ability-slot=q]').hover()
    assert page.locator('#detail-popover .tooltip-value').first.inner_text() == '184.4'
    page.get_by_text('Runes & spells', exact=True).click()
    page.locator('#rune-editor summary').click()
    page.locator('#rune-editor [name=shard1]').select_option('5005')
    page.wait_for_function("JSON.parse(document.querySelector('#scenario-data').dataset.json).scenario.player.loadout.shards[0] === 5005")
    page.locator('#ranks [data-ability-slot=q]').hover()
    assert page.locator('#detail-popover .tooltip-value').first.inner_text() == '177.2'
    page.locator('.brand').hover()
    document = json.loads(page.locator('#scenario-data').get_attribute('data-json'))
    assert document['scenario']['player']['loadout']['shards'] == [5005,5008,5011]
    assert document['scenario']['player']['loadout']['runes'] == [8210,8237]
    damage = page.locator('#timeline').get_attribute('data-total')
    page.get_by_text('Saved scenarios', exact=True).click()
    page.get_by_role('button', name='Create share link', exact=True).click()
    shared = browser.new_page()
    shared.goto(page.locator('#scenario-link').input_value(), wait_until='domcontentloaded')
    assert shared.locator('#timeline').get_attribute('data-total') == damage
    assert json.loads(shared.locator('#scenario-data').get_attribute('data-json'))['scenario']['player']['loadout'] == document['scenario']['player']['loadout']
    shared.close()
    with page.expect_download() as download:
        page.get_by_role('button', name='Export JSON', exact=True).click()
    assert json.loads(Path(download.value.path()).read_text()) == document
    page.goto(base+'/?champion=Annie&selected=custom&mode=duel&opponent=Annie&enemyshard1=5005&enemyshard2=5010&enemyshard3=5001', wait_until='domcontentloaded')
    assert json.loads(page.locator('#scenario-data').get_attribute('data-json'))['scenario']['target']['loadout']['shards'] == [5005,5010,5001]
    assert not errors, errors
    page.close()


def verify_timeline_icons(browser, base):
    page = browser.new_page(viewport={'width':1200,'height':1000})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    url = (base+'/?mode=duel&champion=Annie&opponent=Garen&selected=custom&snapshotlocked=true'
           '&level=6&opponentlevel=6&movement=hold&opponentmovement=hold&distance=0&duration=5')
    page.goto(url, wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    result = json.loads(page.locator('#results').get_attribute('data-matchup-result'))
    scenario = json.loads(page.locator('#scenario-data').get_attribute('data-json'))['scenario']
    prefix = f"/assets/{scenario['patch']}/{scenario['snapshot']}/"
    for actor, champion in zip(result['actors'], ('Annie', 'Garen')):
        assert actor['icon'] == prefix+f'champion/{champion}.png'
    events = [row for row in result['trace'] if row['at'] <= result['end'] and row['kind'] in
              ('damage', 'heal', 'shield', 'control', 'death', 'parry-start', 'parried')]
    select = page.locator('.matchup-event-select')
    assert select.locator('option').count() == len(events)+1
    for source, slot in (('AnnieQ','Q'), ('AnnieW','W'), ('attack','AA')):
        index = next(index for index, row in enumerate(events) if row['source'] == source and row['actor'] == 'player')
        select.select_option(str(index))
        marker = page.locator(f'[data-trace-event="{index}"]')
        expect(marker).to_be_visible()
        expect(marker).to_have_attribute('aria-pressed', 'true')
        expect(marker.locator('.matchup-event-label')).to_have_text(slot)
        expected_icon = result['actors'][0]['icon'] if source == 'attack' else result['sources'][source]['icon']
        assert expected_icon.startswith(prefix)
        expect(marker.locator('img')).to_have_attribute('src', expected_icon)
        page.wait_for_function('(index)=>{const img=document.querySelector(`[data-trace-event="${index}"] img`);return img?.complete && img.naturalWidth>0}', arg=index)
        assert 'seconds, Annie' in marker.get_attribute('aria-label')
        marker.focus()
        marker.press('Enter')
        expect(marker).to_be_focused()
        expect(page.locator('.matchup-event-detail')).to_be_visible()
    # Configuration edits leave the completed result and its artwork intact.
    previous = page.locator('#results').get_attribute('data-matchup-result')
    page.locator('[name=opponentlevel]').select_option('7')
    expect(page.locator('.matchup-stale')).to_be_visible()
    assert page.locator('#results').get_attribute('data-matchup-result') == previous
    page.locator('#results').screenshot(path='build/timeline-icons-desktop.png')
    for width in (736,390,320):
        page.set_viewport_size({'width':width,'height':1000})
        page.wait_for_function('document.documentElement.scrollWidth <= innerWidth + 1')
        for source in ('AnnieQ','AnnieW'):
            index = next(index for index, row in enumerate(events) if row['source'] == source)
            select.select_option(str(index))
            expect(page.locator(f'[data-trace-event="{index}"] img')).to_be_visible()
    page.locator('#results').screenshot(path='build/timeline-icons-mobile.png')
    assert not errors, errors
    page.close()
    # Missing artwork must leave a usable, named marker rather than a broken image.
    fallback = browser.new_page(viewport={'width':390,'height':1000}, has_touch=True, is_mobile=True)
    failed = []
    def fail_icon(route):
        failed.append(route.request.url)
        route.abort()
    fallback.route('**/spell/Annie*.png', fail_icon)
    fallback.goto(url, wait_until='domcontentloaded')
    expect(fallback.locator('#matchup-chart svg')).to_be_visible()
    index = next(index for index, row in enumerate(events) if row['source'] == 'AnnieQ')
    fallback.locator('.matchup-event-select').select_option(str(index))
    marker = fallback.locator(f'[data-trace-event="{index}"]')
    expect(marker.locator('img')).to_have_count(0)
    expect(marker).to_have_text('Q')
    # ResizeObserver can replace the marker between locator resolution and
    # Playwright's geometry request. Measure the current visible touch target
    # in one browser task, retrying while the redraw finishes.
    fallback.wait_for_function('''index => {
        const marker = document.querySelector(`[data-trace-event="${index}"]`);
        const box = marker?.getBoundingClientRect();
        return box && box.width >= 44 && box.height >= 44;
    }''', arg=index, timeout=5000)
    attempts = len(failed)
    fallback.locator('[data-matchup-metric=damage]').click()
    expect(marker).to_have_text('Q')
    expect(marker.locator('img')).to_have_count(0)
    assert len(failed) == attempts
    marker.click()
    expect(fallback.locator('.matchup-event-detail')).to_contain_text(result['sources']['AnnieQ']['name'])
    fallback.close()
    print('Browser: snapshot-scoped timeline artwork, keyboard selection, crowded events, responsive layout and missing-icon fallback passed.')

def verify_ability_readiness(browser, base):
    page = browser.new_page(viewport={'width':1200,'height':1000})
    page.goto(base+'/?mode=duel&champion=Annie&opponent=Annie&selected=custom&snapshotlocked=true'
              '&level=1&opponentlevel=1&slot1=3158&enemyslot1=3158&attacks=false&opponentattacks=false'
              '&abilities=true&opponentabilities=true&movement=hold&opponentmovement=hold&distance=300&duration=12',
              wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    result = json.loads(page.locator('#results').get_attribute('data-matchup-result'))
    for who in ('player', 'opponent'):
        stats = dict(json.loads(page.locator(f'#{who}-card button[data-details]').first.get_attribute('data-details'))['stats'])
        haste = float(stats['Ability haste'])
        assert haste > 0
        casts = [row for row in result['trace'] if row['kind'] == 'cast' and row['actor'] == who and row['source'] == 'AnnieQ']
        assert len(casts) == 4
        for index, event in enumerate(casts):
            assert abs(event['at'] - index * 4 / (1 + haste / 100)) < 1e-6
    page.close()
    print('Browser: exact hasted ability cooldowns for both duel participants passed.')

def verify_resource_readiness(browser, base):
    page = browser.new_page(viewport={'width':1200,'height':1000})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    url = (base+'/?mode=duel&champion=Annie&opponent=Annie&selected=custom&snapshotlocked=true'
           '&level=1&opponentlevel=1&attacks=false&opponentattacks=false&abilities=true&opponentabilities=true'
           '&priority=q&opponentpriority=q&movement=hold&opponentmovement=hold&distance=0')
    page.goto(url+'&duration=1', wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    initial = json.loads(page.locator('#results').get_attribute('data-matchup-result'))['trace']
    deadlines = {}
    for who in ('player', 'opponent'):
        stats = dict(json.loads(page.locator(f'#{who}-card button[data-details]').first.get_attribute('data-details'))['stats'])
        cost = next(row['cost'] for row in initial if row['kind'] == 'cast' and row['actor'] == who and row['source'] == 'AnnieQ')
        deadlines[who] = (cost - .1 * float(stats['Mana'])) / (float(stats['Mana regeneration / 5 s']) / 5)
    page.goto(url+f'&resourcefraction=0.1&opponentresourcefraction=0.1&duration={max(deadlines.values())+.26}',
              wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    trace = json.loads(page.locator('#results').get_attribute('data-matchup-result'))['trace']
    for who, deadline in deadlines.items():
        casts = [row for row in trace if row['kind'] == 'cast' and row['actor'] == who and row['source'] == 'AnnieQ']
        hits = [row for row in trace if row['kind'] == 'damage' and row['actor'] == who and row['source'] == 'AnnieQ']
        assert len(casts) == len(hits) == 1
        assert abs(casts[0]['at'] - deadline) < 1e-6
        assert abs(hits[0]['at'] - deadline - .25) < 1e-6
        assert hits[0]['damage'] > 0
    page.set_viewport_size({'width':320,'height':1000})
    page.wait_for_function('document.documentElement.scrollWidth <= innerWidth + 1')
    assert not errors, errors
    page.close()
    print('Browser: source-derived mana recovery, exact affordable casts/impacts, both participants and mobile layout passed.')

def verify_health_activation(browser, base):
    page = browser.new_page(viewport={'width':1200,'height':1000})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    for who in ('player', 'opponent'):
        prefix = 'opponent' if who == 'opponent' else ''
        query = {'mode': 'duel', 'champion': 'Annie', 'opponent': 'Annie', 'selected': 'custom',
                 'snapshotlocked': 'true', 'level': 1, 'opponentlevel': 1, 'distance': 200, 'duration': 1,
                 'attacks': 'false', 'opponentattacks': 'false', 'abilities': 'false', 'opponentabilities': 'false',
                 'priority': 'q', 'opponentpriority': 'q', 'movement': 'hold', 'opponentmovement': 'hold'}
        query[prefix+'attacks'] = 'true'
        query[('enemy' if who == 'opponent' else '')+'qtargetbelow'] = .95
        page.goto(base+'/?'+urllib.parse.urlencode(query), wait_until='domcontentloaded')
        expect(page.locator('#matchup-chart svg')).to_be_visible()
        stats = dict(json.loads(page.locator(f'#{who}-card button[data-details]').first.get_attribute('data-details'))['stats'])
        # Retained Annie windup, ordinary projectile and Q delivery policies.
        ready = .3 / float(stats['Attack speed']) + 200 / 1500
        impact = ready + .25 + 200 / 1400
        query[prefix+'abilities'] = 'true'
        query['duration'] = impact + .005
        page.goto(base+'/?'+urllib.parse.urlencode(query), wait_until='domcontentloaded')
        expect(page.locator('#matchup-chart svg')).to_be_visible()
        document = json.loads(page.locator('#scenario-data').get_attribute('data-json'))['scenario']
        side = 'target' if who == 'opponent' else 'player'
        assert document[side]['strategy']['activation']['q']['target-health-below'] == .95
        trace = json.loads(page.locator('#results').get_attribute('data-matchup-result'))['trace']
        shot = [row for row in trace if row['kind'] == 'damage' and row['source'] == 'attack' and row['actor'] == who]
        casts = [row for row in trace if row['kind'] == 'cast' and row['source'] == 'AnnieQ' and row['actor'] == who]
        hits = [row for row in trace if row['kind'] == 'damage' and row['source'] == 'AnnieQ' and row['actor'] == who]
        assert len(shot) == len(casts) == len(hits) == 1
        assert abs(shot[0]['at'] - ready) < 1e-6
        assert casts[0]['at'] == shot[0]['at']
        assert abs(hits[0]['at'] - impact) < 1e-6
        page.set_viewport_size({'width':320,'height':1000})
        page.wait_for_function('document.documentElement.scrollWidth <= innerWidth + 1')
    assert not errors, errors
    page.close()
    print('Browser: target-health activation at projectile impact, source timing, both participants and mobile layout passed.')

def verify_movement_readiness(browser, base):
    page = browser.new_page(viewport={'width':1200,'height':1000})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    for who in ('player', 'opponent'):
        prefix = 'opponent' if who == 'opponent' else ''
        query = {'mode': 'duel', 'champion': 'Annie', 'opponent': 'Annie', 'selected': 'custom',
                 'snapshotlocked': 'true', 'level': 1, 'opponentlevel': 1, 'distance': 700, 'duration': 2,
                 'attacks': 'false', 'opponentattacks': 'false', 'abilities': 'false', 'opponentabilities': 'false',
                 'priority': 'q', 'opponentpriority': 'q', 'movement': 'hold', 'opponentmovement': 'hold'}
        query[prefix+'movement'] = 'approach'
        page.goto(base+'/?'+urllib.parse.urlencode(query), wait_until='domcontentloaded')
        expect(page.locator('#matchup-chart svg')).to_be_visible()
        stats = dict(json.loads(page.locator(f'#{who}-card button[data-details]').first.get_attribute('data-details'))['stats'])
        attack_range = float(stats['Attack range'])
        ready = (700 - attack_range) / float(stats['Move speed'])
        # Retained Annie Q cast and missile timing, unchanged by movement work.
        impact = ready + .25 + attack_range / 1400
        query[prefix+'abilities'] = 'true'
        query['duration'] = impact + .005
        page.goto(base+'/?'+urllib.parse.urlencode(query), wait_until='domcontentloaded')
        expect(page.locator('#matchup-chart svg')).to_be_visible()
        document = json.loads(page.locator('#scenario-data').get_attribute('data-json'))['scenario']
        assert document['target' if who == 'opponent' else 'player']['strategy']['movement'] == 'approach'
        trace = json.loads(page.locator('#results').get_attribute('data-matchup-result'))['trace']
        casts = [row for row in trace if row['kind'] == 'cast' and row['source'] == 'AnnieQ' and row['actor'] == who]
        hits = [row for row in trace if row['kind'] == 'damage' and row['source'] == 'AnnieQ' and row['actor'] == who]
        assert len(casts) == len(hits) == 1
        assert abs(casts[0]['at'] - ready) < 1e-6
        assert abs(hits[0]['at'] - impact) < 1e-6
        positions = [row['position'] for row in hits[0]['participants']]
        assert abs(abs(positions[1] - positions[0]) - attack_range) < 1e-6
        page.set_viewport_size({'width':320,'height':1000})
        page.wait_for_function('document.documentElement.scrollWidth <= innerWidth + 1')
    assert not errors, errors
    page.close()
    print('Browser: movement/range deadlines, stopped distance, source travel, both participants and mobile layout passed.')

def verify(base):
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        from messages_browser import verify as verify_messages
        verify_messages(browser, base)
        from workspace_browser import verify as verify_workspace
        native_scrollbars = p.chromium.launch(headless=True, ignore_default_args=['--hide-scrollbars'])
        verify_workspace(native_scrollbars, base)
        native_scrollbars.close()
        from report_browser import verify as verify_reports
        verify_reports(browser, base)
        from attack_limit_browser import verify as verify_attack_limits
        verify_attack_limits(browser, base)
        from catalog_browser import verify as verify_catalogs
        verify_catalogs(browser, base)
        from champion_browser import verify as verify_champion_configs
        verify_champion_configs(browser, base)
        verify_timeline_icons(browser, base)
        verify_ability_readiness(browser, base)
        verify_resource_readiness(browser, base)
        verify_health_activation(browser, base)
        verify_movement_readiness(browser, base)
        verify_practice_controls(browser, base)
        verify_kayle_levels(browser, base)
        verify_fixed_forms(browser, base, 'Nidalee', 'human', 'cougar', 'Human', 'Cougar')
        verify_fixed_forms(browser, base, 'Jayce', 'cannon', 'hammer', 'Cannon', 'Hammer')
        verify_fixed_forms(browser, base, 'Elise', 'human', 'spider', 'Human', 'Spider')
        verify_fixed_forms(browser, base, 'Gnar', 'mini', 'mega', 'Mini', 'Mega')
        verify_runes(browser, base)
        page = browser.new_page(viewport={'width':1440,'height':1080})
        errors=[]
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.goto(base+'/?mode=practice&champion=Annie&selected=custom', wait_until='domcontentloaded')
        page.locator('#timeline').wait_for()
        # Calculated tooltip values support hover, keyboard focus and click.
        q_tile=page.locator('#ranks [data-ability-slot=q]')
        q_tile.hover()
        q_value=page.locator('#detail-popover .tooltip-value').first
        q_value.wait_for()
        assert q_value.inner_text()=='260'
        q_value.hover()
        calculation=page.locator('.tooltip-calculation:popover-open')
        calculation.wait_for(state='visible')
        assert '260 (rank 5)' in calculation.inner_text()
        assert 'ability power' in calculation.inner_text()
        assert 'before mitigation' in calculation.inner_text()
        q_value.focus()
        assert q_value.get_attribute('aria-expanded')=='true'
        q_value.click()
        page.locator('.brand').hover()
        assert calculation.is_visible()
        page.keyboard.press('Escape')
        assert page.locator('.tooltip-calculation:popover-open').count()==0
        # Picker details are calculated on the server for the displayed scenario.
        page.locator('#loadout-tray .item-slot').first.click()
        with page.expect_response(lambda response: '/details/item?id=3089&who=player' in response.url) as details_response:
            page.locator('#item-picker [data-detail-item="3089"]').hover()
        assert details_response.value.status==200
        assert details_response.value.json()['name']=="Rabadon's Deathcap"
        page.locator('#detail-popover').get_by_role('button',name='Close details',exact=True).click()
        page.locator('#item-picker .catalog-close').click()
        # Level changes apply the explicit skill order, independently of cast priority.
        page.get_by_text('Runes & spells',exact=True).click()
        page.get_by_text('Strategies, ranks & activation rules',exact=True).click()
        skill_order=page.get_by_label('Player skill order',exact=True)
        default_order=skill_order.input_value()
        chosen_order='w,q,w,e,w,r,w,q,w,q,r,q,q,e,e,r,e,e'
        skill_order.fill(chosen_order)
        skill_order.press('Tab')
        page.wait_for_function("JSON.parse(document.getElementById('scenario-data').dataset.json).scenario.player['skill-order'][0] === 'w'")
        page.locator('#level').select_option('1')
        page.wait_for_function("document.querySelector('#ranks [data-ability-slot=q]').dataset.unlocked === 'false' && document.querySelector('#ranks [data-ability-slot=w]').dataset.rank === '1'")
        assert 'locked' in page.locator('#ranks [data-ability-slot=q]').get_attribute('aria-label')
        def tile_bounds(slot):
            # Page scrolling is independent of movement within the loadout tray.
            return page.locator(f'#ranks [data-ability-slot={slot}]').evaluate('''node => {
                const tile=node.getBoundingClientRect(), tray=node.closest('#loadout-tray').getBoundingClientRect();
                return {x:tile.x-tray.x, y:tile.y-tray.y, width:tile.width, height:tile.height};
            }''')
        locked_bounds=tile_bounds('q')
        neighbor_bounds=tile_bounds('w')
        page.locator('#level').select_option('3')
        page.wait_for_function("document.querySelector('#ranks [data-ability-slot=w]').dataset.rank === '2'")
        assert tile_bounds('q')==locked_bounds
        assert tile_bounds('w')==neighbor_bounds
        page.locator('#level').select_option('1')
        page.wait_for_function("document.querySelector('#ranks [data-ability-slot=q]').dataset.unlocked === 'false'")
        page.get_by_label('Player skill order',exact=True).fill(default_order)
        page.get_by_label('Player skill order',exact=True).press('Tab')
        page.wait_for_function("document.querySelector('#ranks [data-ability-slot=q]').dataset.rank === '1'")
        page.locator('#level').select_option('18')
        page.wait_for_function("document.querySelector('#ranks [data-ability-slot=q]').dataset.rank === '5'")
        # Inspect one real event across all charts, then pin it with the keyboard.
        original_damage=page.locator('#timeline').get_attribute('data-total')
        first_event=json.loads(page.locator('#timeline').get_attribute('data-events'))[0]
        event_button=page.locator('#attack-events [data-event]').first
        event_button.hover()
        assert page.locator('.chart-hover-guide').evaluate_all('(nodes)=>nodes.every(node=>getComputedStyle(node).display!=="none")')
        assert str(round(first_event['damage'])) in page.locator('#event-detail').inner_text().replace(',','')
        event_button.focus()
        event_button.press('Enter')
        page.locator('.brand').hover()
        expect(page.locator('#event-detail')).to_contain_text('pinned')
        page.keyboard.press('Escape')
        assert page.locator('#timeline').get_attribute('data-total')==original_damage
        assert not page.locator('#fight-settings').evaluate('(node)=>node.open')
        page.get_by_text('Opponent & fight',exact=True).click()
        page.locator('#duration').fill('7')
        page.locator('#duration').press('Tab')
        page.wait_for_function("document.querySelector('#timeline').dataset.duration === '7'")
        # Opening settings is passive; only Run search starts optimization.
        searches=[]
        page.on('request', lambda request: searches.append(request.url) if request.method=='POST' and request.url.endswith('/search') else None)
        page.get_by_role('button', name='Optimize build', exact=True).click()
        assert page.locator('#optimizer-dialog').evaluate('(node)=>node.open')
        page.wait_for_timeout(500)
        assert not searches
        assert page.locator('#search-panel').get_attribute('data-status')=='idle'
        page.get_by_role('button', name='Run search', exact=True).click()
        page.get_by_role('button', name='Cancel search', exact=True).wait_for()
        assert len(searches)==1
        assert page.locator('#results').evaluate('(node)=>getComputedStyle(node).opacity')=='1'
        page.get_by_role('button', name='Cancel search', exact=True).click()
        page.wait_for_function("document.querySelector('#search-panel').dataset.status==='cancelled'")
        page.get_by_role('button',name='Close optimization',exact=True).click()
        page.get_by_text('Optimization & restrictions',exact=True).click()
        page.get_by_text('Options, locks & candidate items',exact=True).click()
        page.get_by_label('Candidate items (comma-separated names or IDs; blank uses the full shop)',exact=True).fill('not-an-item')
        page.get_by_role('button', name='Run search', exact=True).click()
        page.locator('#search-panel[data-error="true"]').wait_for()
        assert 'Unknown' in page.locator('#search-panel').inner_text() and 'not-an-item' in page.locator('#search-panel').inner_text()
        assert page.locator('#optimizer-dialog').evaluate('(node)=>node.open')
        page.get_by_label('Candidate items (comma-separated names or IDs; blank uses the full shop)',exact=True).fill('Amplifying Tome, Blasting Wand')
        page.get_by_label('Search gold budget',exact=True).fill('400')
        page.get_by_label('Inventory slots',exact=True).fill('1')
        page.get_by_role('button', name='Run search', exact=True).click()
        page.wait_for_function("document.querySelector('#search-panel').textContent.includes('done')", timeout=30000)
        assert 'Optimal within selected pool' in page.locator('#search-panel').inner_text()
        assert page.locator('#search-panel svg').count()==0
        assert 1<=page.locator('.search-alternative').count()<=10
        page.locator('.search-item').first.hover()
        assert 'Amplifying Tome' in page.locator('#detail-popover').inner_text()
        assert page.locator('#detail-popover').evaluate('(node)=>node.parentElement.id')=='optimizer-dialog'
        assert page.locator('#detail-popover').count()==1
        page.locator('.search-item').first.click()
        page.get_by_role('button',name='Close details',exact=True).click()
        assert page.locator('#optimizer-dialog').evaluate('(node)=>node.open')
        assert page.locator('#optimizer-dialog').evaluate('(node)=>node.open')
        completed_job=page.locator('#search-panel').get_attribute('data-job')
        page.get_by_role('button', name='Run search', exact=True).click()
        page.wait_for_function("previous=>document.querySelector('#search-panel').dataset.job!==previous && document.querySelector('#search-panel').dataset.status==='done'",arg=completed_job,timeout=30000)
        assert 'results reused' in page.locator('#search-panel').inner_text()
        assert '0 new simulations' in page.locator('#search-panel').inner_text()
        page.get_by_role('button', name='Apply & inspect').first.click()
        page.wait_for_function("!document.getElementById('optimizer-dialog').open")
        page.wait_for_function("document.querySelector('#loadout-tray .item-slot img')?.src.endsWith('/1052.png')")
        page.locator('#loadout-tray .item-slot').first.hover()
        assert 'Amplifying Tome' in page.locator('#detail-popover').inner_text()
        assert 'Ability power' in page.locator('#detail-popover').inner_text()
        page.keyboard.press('Escape')
        q_tile.hover()
        assert page.locator('#detail-popover .tooltip-value').first.inner_text()=='276'
        page.keyboard.press('Escape')
        page.get_by_text('Optimization & restrictions',exact=True).click()
        page.get_by_label('Candidate items (comma-separated names or IDs; blank uses the full shop)',exact=True).fill('')
        page.get_by_label('Search gold budget',exact=True).fill('10000')
        page.get_by_label('Inventory slots',exact=True).fill('6')
        page.get_by_label('Compute budget',exact=False).select_option('30')
        page.get_by_role('button', name='Run search', exact=True).click()
        page.get_by_role('button', name='Cancel search', exact=True).wait_for()
        job=page.locator('#search-panel').get_attribute('data-job')
        page.get_by_role('button',name='Close optimization',exact=True).click()
        page.get_by_role('button',name='Optimize build',exact=True).click()
        assert page.locator('#search-panel').get_attribute('data-job')==job
        started=time.monotonic()
        assert urllib.request.urlopen(base+'/healthz', timeout=2).read()==b'ok\n'
        assert time.monotonic()-started<1
        page.get_by_role('button', name='Cancel search', exact=True).click()
        page.wait_for_function("document.querySelector('#search-panel').textContent.includes('cancelled')",timeout=10000)
        page.keyboard.press('Escape')
        assert not page.locator('#optimizer-dialog').evaluate('(node)=>node.open')
        # Persist the completed canonical scenario, then reproduce it through
        # local storage, a URL and a versioned file in independent browser pages.
        document = page.locator('#workspace-data').get_attribute('data-json')
        damage = page.locator('#timeline').get_attribute('data-total')
        page.get_by_text('Saved scenarios',exact=True).click()
        page.get_by_label('Scenario name', exact=True).fill('Browser regression')
        page.get_by_role('button', name='Save locally', exact=True).click()
        page.wait_for_function("document.getElementById('saved-scenarios').options.length === 2")
        page.get_by_role('button', name='Create share link', exact=True).click()
        link=page.locator('#scenario-link').input_value()
        shared=browser.new_page()
        shared.goto(link,wait_until='domcontentloaded')
        assert shared.locator('#timeline').get_attribute('data-total')==damage
        shared.close()
        with page.expect_download() as download:
            page.get_by_role('button', name='Export JSON', exact=True).click()
        exported=Path(download.value.path()).read_text()
        assert exported==document
        page.locator('#duration').fill('8')
        page.locator('#duration').press('Tab')
        page.wait_for_function("document.querySelector('#timeline').dataset.duration === '8'")
        page.get_by_label('Locally saved scenarios').select_option(index=1)
        page.get_by_role('button', name='Load saved', exact=True).click()
        page.wait_for_function("document.querySelector('#timeline').dataset.duration === '7'")
        assert page.locator('#timeline').get_attribute('data-total')==damage
        page.get_by_text('Import a scenario',exact=True).click()
        page.locator('#scenario-file').set_input_files({'name':'scenario.json','mimeType':'application/json','buffer':exported.encode()})
        page.wait_for_function("document.getElementById('scenario-json').value.length > 0")
        page.get_by_role('button',name='Load scenario',exact=True).click()
        page.wait_for_function("document.getElementById('scenario-json').value === ''")
        assert page.locator('#timeline').get_attribute('data-total')==damage
        page.locator('#patch-settings > summary').click()
        assert page.locator('#verification-progress, #source-evidence, #evidence').count() == 0
        developer=browser.new_page()
        developer.goto(base+'/developer',wait_until='domcontentloaded')
        expect(developer.get_by_role('heading',name='Developer tools',exact=True)).to_be_visible()
        developer.get_by_text('Source records & model identity',exact=True).click()
        assert 'Snapshot SHA-256' in developer.locator('#source-evidence').inner_text()
        assert developer.locator('#verification-progress').count()==1
        developer.close()
        page.screenshot(path='build/browser-verification.png', full_page=True)
        page.get_by_text('Optimization & restrictions',exact=True).click()
        for width in [736,360,320]:
            page.set_viewport_size({'width':width,'height':1080})
            page.wait_for_timeout(100)
            assert not page.evaluate('document.documentElement.scrollWidth>innerWidth'), width
            assert page.locator('#optimizer-dialog').evaluate('(node)=>node.scrollWidth<=node.clientWidth'), width
        assert not errors, errors
        print('Browser: failed-evaluation recovery, linked graphs, loadout details, responsive layout, optimize/apply/cancel, save/share and exact reproduction passed.')
        browser.close()
    # Exercise the paired interface in the same release/CI browser gate using
    # Playwright's bundled runtime; the app itself has no Node dependency.
    driver = Path(playwright.__file__).parent / 'driver'
    subprocess.run([str(driver / ('node.exe' if os.name == 'nt' else 'node')),
                    str(Path(__file__).with_name('matchup-browser.cjs').resolve())],
                   env={**os.environ, 'PLAYWRIGHT_MODULE': str(driver / 'package'),
                        'PS_TEST_URL': base}, check=True)

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--url')
    parser.add_argument('--binary', default='dist/bin/powerspike')
    parser.add_argument('--parry-fixture', help='Also check sourced Riposte outcomes using an exported cached fixture')
    parser.add_argument('--control-fixture', help='Also check synthetic control resumption using an exported fixture')
    parser.add_argument('--changing-fixture', help='Also check synthetic changing costs/ranges using an exported fixture')
    parser.add_argument('--health-cost-fixture', help='Also check a retained health-cost formula on a synthetic carrier')
    parser.add_argument('--latest-patch-fixture', help='Also check refreshed 16.20/16.21 default matchups')
    parser.add_argument('--reparse-fixture', help='Also check parser warnings and explicit offline raw-data reparsing')
    parser.add_argument('--latest-attack-fixture', help='Also check latest-patch mage attack timings from saved snapshots')
    args=parser.parse_args()
    if args.url:
        verify(args.url)
    else:
        root=Path.cwd()
        chosen=port()
        # Use an isolated cache, as the relocated runtime check does. Reusing a
        # prior test's partially copied seed can hide cold-start failures.
        with tempfile.TemporaryDirectory(prefix='powerspike-browser-') as data:
            with running(Path(args.binary).resolve(), root, [], clean_env(PS_PORT=str(chosen), PS_HOST='127.0.0.1',
                         PS_DATA_DIR=data, PS_SEED_DIR=str(root/'dist/share/powerspike/seed')), chosen) as base:
                verify(base)

    if args.parry_fixture:
        from parry_browser import verify as verify_parry
        verify_parry(args.binary, args.parry_fixture)
    if args.control_fixture:
        from control_browser import verify as verify_control
        verify_control(args.binary, args.control_fixture)
    if args.changing_fixture:
        from changing_browser import verify as verify_changing
        verify_changing(args.binary, args.changing_fixture)
    if args.health_cost_fixture:
        from health_cost_browser import verify as verify_health_cost
        verify_health_cost(args.binary, args.health_cost_fixture)
    if args.latest_patch_fixture:
        from latest_patch_browser import verify as verify_latest_patch
        verify_latest_patch(args.binary, args.latest_patch_fixture)
    if args.reparse_fixture:
        from reparse_browser import verify as verify_reparse
        verify_reparse(args.binary, args.reparse_fixture)
    if args.latest_attack_fixture:
        from latest_attack_browser import verify as verify_latest_attacks
        verify_latest_attacks(args.binary, args.latest_attack_fixture)

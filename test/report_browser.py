"""Local report downloads preserve inputs and reproduce both compared builds."""
import json
from pathlib import Path
from urllib.parse import urlencode
from playwright.sync_api import expect


def verify(browser, base):
    page = browser.new_page(viewport={'width':1200, 'height':1000})
    errors, requests = [], []
    page.on('pageerror', lambda error: errors.append(str(error)))
    query = {'mode':'duel', 'champion':'Annie', 'opponent':'Garen', 'selected':'custom',
             'snapshotlocked':'true', 'level':6, 'opponentlevel':6, 'duration':2,
             'samples':4, 'seed':6, 'slot1':'1052', 'distance':200}
    page.goto(base+'/?'+urlencode(query), wait_until='domcontentloaded')
    expect(page.locator('#matchup-chart svg')).to_be_visible()
    query.update(referencejson=page.locator('#scenario-data').get_attribute('data-json'), slot1='1028')
    page.goto(base+'/?'+urlencode(query)+'&private-marker=not-for-the-report', wait_until='domcontentloaded')
    expect(page.locator('.item-comparison-table')).to_be_visible()
    page.wait_for_function('!document.querySelector("#powerspike").classList.contains("is-pending")')
    workspace = json.loads(page.locator('#workspace-data').get_attribute('data-json'))
    observed = json.loads(page.locator('#problem-report-data').get_attribute('data-json'))['observed']
    original = json.loads(page.locator('#results').get_attribute('data-matchup-result'))
    page.evaluate('localStorage.setItem("private-save", "unrelated-browser-data")')
    page.on('request', lambda request: requests.append(request.url))
    opener = page.get_by_role('button', name='Report a problem', exact=True)
    opener.click()
    dialog = page.get_by_role('dialog', name='Report a problem', exact=True)
    expect(dialog).to_be_visible()
    expect(page.locator('#problem-report-context')).to_have_text('Annie vs Garen · Patch 16.19.1 · 4 trials')
    expect(dialog).not_to_contain_text(workspace['scenario']['model'])
    # Required fields and whitespace cannot produce an empty report.
    page.get_by_role('button', name='Download report', exact=True).click()
    assert not page.locator('#problem-report-form').evaluate('(form)=>form.checkValidity()')
    actual = 'The item result looks wrong <script>window.reportExecuted=true</script>'
    page.get_by_label('What happened?', exact=True).fill(actual)
    page.get_by_label('What did you expect?', exact=True).fill('   ')
    page.get_by_role('button', name='Download report', exact=True).click()
    expect(page.locator('#problem-report-status')).to_contain_text('Describe what happened')
    page.get_by_label('What did you expect?', exact=True).fill('A survival tradeoff')
    page.get_by_label('Steps to reproduce (optional)', exact=True).fill('Pin Tome, then swap to Ruby Crystal.')
    with page.expect_download() as download:
        page.get_by_role('button', name='Download report', exact=True).click()
    assert download.value.suggested_filename == 'powerspike-problem-report.json'
    exported = Path(download.value.path()).read_text()
    report = json.loads(exported)
    assert report['format'] == 'powerspike-problem-report' and report['version'] == 1
    assert report['workspace'] == workspace and report['observed'] == observed
    assert report['actual'] == actual and report['expected'] == 'A survival tradeoff'
    assert report['created-at'].endswith('Z') and report['release']
    assert all(value not in exported for value in (base, 'not-for-the-report', 'unrelated-browser-data'))
    assert not page.evaluate('window.reportExecuted || false')
    assert not requests, requests
    page.screenshot(path='build/problem-report-desktop.png')
    for width in (736,390,320):
        page.set_viewport_size({'width':width, 'height':1000})
        assert dialog.evaluate('(node)=>node.scrollWidth <= node.clientWidth + 1')
        # Charts resize through ResizeObserver and the next animation frame.
        page.wait_for_function('document.documentElement.scrollWidth <= innerWidth + 1', timeout=5000)
    page.screenshot(path='build/problem-report-mobile.png')
    page.keyboard.press('Escape')
    expect(opener).to_be_focused()
    opener.click()
    expect(page.get_by_label('What happened?', exact=True)).to_have_value(actual)
    page.get_by_role('button', name='Close problem report', exact=True).click()
    # Edits retain the completed result, but cannot be reported as that result.
    page.locator('[name=level]').select_option('7')
    page.wait_for_function('document.querySelector("#powerspike").dataset.stale === "true" && !document.querySelector("#powerspike").classList.contains("is-pending")')
    opener.click()
    expect(page.locator('#problem-report-form')).to_be_hidden()
    expect(page.locator('#problem-report-status')).to_contain_text('Run the matchup')
    page.keyboard.press('Escape')
    previous = page.locator('#results').get_attribute('data-run-id')
    page.locator('.matchup-run').click()
    page.wait_for_function('(previous)=>document.querySelector("#results").dataset.runId !== previous && !document.querySelector("#powerspike").classList.contains("is-pending")', arg=previous)
    opener.click()
    expect(page.locator('#problem-report-form')).to_be_visible()
    # Results changing in another task while the dialog is open require reopening.
    page.locator('#problem-report-data').evaluate('(node)=>{const data=JSON.parse(node.dataset.json);data.release="changed";node.dataset.json=JSON.stringify(data)}')
    page.get_by_role('button', name='Download report', exact=True).click()
    expect(page.locator('#problem-report-status')).to_contain_text('Close and reopen')
    page.keyboard.press('Escape')
    # Import the untouched artifact on the other layout and reproduce the result.
    other = browser.new_page()
    other.on('pageerror', lambda error: errors.append(str(error)))
    other.goto(base+'/?mode=practice&champion=Annie&selected=custom', wait_until='domcontentloaded')
    other.get_by_text('Saved scenarios', exact=True).click()
    other.get_by_text('Import a scenario', exact=True).click()
    other.locator('#scenario-file').set_input_files({'name':'report.json', 'mimeType':'application/json', 'buffer':exported.encode()})
    expect(other.locator('#scenario-json')).to_have_value(exported)
    other.get_by_role('button', name='Load scenario', exact=True).click()
    other.wait_for_function('document.querySelector("#powerspike").dataset.layout === "matchup"')
    assert json.loads(other.locator('#workspace-data').get_attribute('data-json')) == workspace
    assert json.loads(other.locator('#results').get_attribute('data-matchup-result')) == original
    assert json.loads(other.locator('#problem-report-data').get_attribute('data-json'))['observed'] == observed
    assert not errors, errors
    other.close()
    page.close()
    # Touch layout: usable inputs, close and download actions meet target sizes.
    touch = browser.new_context(viewport={'width':390, 'height':844}, is_mobile=True, has_touch=True)
    page = touch.new_page()
    page.goto(base+'/?mode=practice&champion=Annie&selected=custom', wait_until='domcontentloaded')
    page.get_by_role('button', name='Report a problem', exact=True).click()
    assert page.locator('#problem-report textarea').evaluate_all('(nodes)=>nodes.every(node=>parseFloat(getComputedStyle(node).fontSize)>=16)')
    assert page.locator('#problem-report button').evaluate_all('(nodes)=>nodes.every(node=>node.getBoundingClientRect().height>=44)')
    touch.close()
    print('Browser: private local reports, exact comparison reproduction, stale-result guards, draft retention, desktop and touch layouts passed.')

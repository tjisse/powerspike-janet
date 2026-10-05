from playwright.sync_api import sync_playwright
import argparse, json, os, tempfile, time, urllib.request
from pathlib import Path
from runtime import port, running, clean_env
def verify(base):
 with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={'width':1440,'height':1080})
        errors=[]
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.goto(base+'/?champion=Annie&selected=custom', wait_until='domcontentloaded')
        page.locator('#timeline').wait_for()
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
        assert 'pinned' in page.locator('#event-detail').inner_text()
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
        document = page.locator('#scenario-data').get_attribute('data-json')
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
        page.get_by_text('Patch & evidence',exact=True).click()
        page.get_by_text('Source records & model identity',exact=True).click()
        assert 'Snapshot SHA-256' in page.locator('#source-evidence').inner_text()
        page.screenshot(path='build/browser-verification.png', full_page=True)
        page.get_by_text('Optimization & restrictions',exact=True).click()
        for width in [736,360,320]:
            page.set_viewport_size({'width':width,'height':1080})
            page.wait_for_timeout(100)
            assert not page.evaluate('document.documentElement.scrollWidth>innerWidth'), width
            assert page.locator('#optimizer-dialog').evaluate('(node)=>node.scrollWidth<=node.clientWidth'), width
        assert not errors, errors
        print('Browser: linked graph hover/pinning, loadout popovers, responsive layout, configure, optimize, apply, cancel, save, share and exact reproduction passed.')
        browser.close()

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--url')
    parser.add_argument('--binary', default='dist/bin/powerspike')
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

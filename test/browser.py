from playwright.sync_api import sync_playwright
import argparse, os, time, urllib.request
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
        page.locator('#duration').fill('7')
        page.locator('#duration').press('Tab')
        page.wait_for_function("document.querySelector('#timeline').dataset.duration === '7'")
        page.get_by_text('Locks & candidate items',exact=True).click()
        page.get_by_label('Candidate items (comma-separated names or IDs; blank uses the full shop)',exact=True).fill('Amplifying Tome, Blasting Wand')
        page.get_by_label('Gold budget',exact=True).fill('400')
        page.get_by_label('Inventory slots',exact=True).fill('1')
        page.get_by_role('button', name='Find builds', exact=True).click()
        page.wait_for_function("document.querySelector('#search-panel').textContent.includes('done')", timeout=30000)
        assert 'Optimal within selected pool' in page.locator('#search-panel').inner_text()
        page.get_by_role('button', name='Apply & inspect').first.click()
        page.wait_for_function("document.querySelector('#results .item-slot img')?.src.endsWith('/1052.png')")
        page.get_by_label('Candidate items (comma-separated names or IDs; blank uses the full shop)',exact=True).fill('')
        page.get_by_label('Gold budget',exact=True).fill('10000')
        page.get_by_label('Inventory slots',exact=True).fill('6')
        page.get_by_label('Compute budget',exact=False).select_option('30')
        page.get_by_role('button', name='Find builds', exact=True).click()
        page.get_by_role('button', name='Cancel search', exact=True).wait_for()
        started=time.monotonic()
        assert urllib.request.urlopen(base+'/healthz', timeout=2).read()==b'ok\n'
        assert time.monotonic()-started<1
        page.get_by_role('button', name='Cancel search', exact=True).click()
        page.wait_for_function("document.querySelector('#search-panel').textContent.includes('cancelled')",timeout=10000)
        page.screenshot(path='build/browser-verification.png', full_page=True)
        assert not errors, errors
        print('Browser: bindings, exact search, recommendation application, compute responsiveness and cancellation passed.')
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
        with running(Path(args.binary).resolve(), root, [], clean_env(PS_PORT=str(chosen), PS_HOST='127.0.0.1',
                     PS_DATA_DIR=str(root/'build/browser-data'), PS_SEED_DIR=str(root/'dist/share/powerspike/seed')), chosen) as base:
            verify(base)

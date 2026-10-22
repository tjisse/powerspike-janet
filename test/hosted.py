"""Small, opt-in deployment smoke check; no production address is retained."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import tempfile
import time
import urllib.parse
import urllib.request

from runtime import Page
from concurrency import Search


USER_AGENT = 'Mozilla/5.0 PowerSpike hosted smoke check'


def verify_http(base):
    def request(path, signals=None, stream=False):
        headers = {'User-Agent': USER_AGENT}
        body = None
        if signals is not None:
            body = json.dumps(signals).encode()
            headers.update({'Content-Type': 'application/json', 'Datastar-Request': 'true'})
        if stream or signals is not None:
            headers['Accept'] = 'text/event-stream'
        started = time.monotonic()
        with urllib.request.urlopen(urllib.request.Request(base+path, data=body, headers=headers), timeout=20) as response:
            first = response.read(1)
            first_byte = time.monotonic()-started
            payload = first+response.read(8*1024*1024)
            assert len(payload) < 8*1024*1024, 'Unexpectedly large smoke response.'
            assert response.status == 200
            controls = set(response.headers.get('Cache-Control', '').lower().replace(' ', '').split(','))
            # The SSE adapter uses no-cache; complete pages use no-store.
            assert controls & ({'no-cache', 'no-store'} if stream or signals is not None else {'no-store'}), 'Missing dynamic cache policy.'
            assert response.headers.get('CF-Cache-Status', '').upper() not in ('HIT', 'STALE', 'UPDATING')
            if stream or signals is not None:
                assert response.headers.get('Content-Type', '').startswith('text/event-stream')
                assert b'event: datastar-patch-' in payload
            return payload, {'first_byte_seconds': round(first_byte, 3),
                             'total_seconds': round(time.monotonic()-started, 3),
                             'cache_control': response.headers.get('Cache-Control', ''),
                             'edge_cache_status': response.headers.get('CF-Cache-Status', '')}

    def health():
        payload, timing = request('/healthz')
        assert payload == b'ok\n'
        return timing['total_seconds']

    query = {'mode': 'practice', 'champion': 'Annie', 'selected': 'custom', 'level': 6,
             'samples': 1, 'seed': 4242, 'duration': 3, 'targethealth': 1000000,
             'abilities': 'false', 'movement': 'hold', 'distance': 0, 'snapshotlocked': 'true'}

    def simulation(change=None, stream=False):
        fields = {**query, **(change or {})}
        path = ('/evaluate?'+urllib.parse.urlencode({'datastar': json.dumps(fields)}) if stream
                else '/?'+urllib.parse.urlencode(fields))
        payload, timing = request(path, stream=stream)
        page = Page()
        page.feed(payload.decode())
        assert page.timeline and page.scenario
        return (float(page.timeline['data-total']), page.scenario['data-json']), timing

    latencies = [health()]
    with ThreadPoolExecutor(max_workers=3) as pool:
        first = pool.submit(simulation)
        variant = pool.submit(simulation, {'slot1': '1036'})
        probe = pool.submit(health)
        baseline, page_timing = first.result()
        changed, _ = variant.result()
        latencies.append(probe.result())
    assert changed[0] > baseline[0], 'A separate client inventory did not change attack damage.'
    assert simulation()[0] == baseline, 'Concurrent requests changed the reproducible result.'
    rerun, sse_timing = simulation(stream=True)
    assert rerun == baseline, 'Public SSE rerun differs from the completed page.'

    def search(path, signals, post=True):
        payload, _ = (request(path, signals) if post else
                      request(path+'?'+urllib.parse.urlencode({'datastar': json.dumps(signals)}), stream=True))
        page = Search()
        page.feed(payload.decode())
        assert hasattr(page, 'result')
        return page.result

    # Bound production work to two seconds; cancel only jobs created here.
    signals = {**query, 'searchseconds': 2, 'searchslots': 6,
               'searchbudget': 10000, 'searchpool': ''}
    job = search('/search', signals)
    identifier = job['data-job']
    try:
        cancelled = search('/jobs/cancel?id='+identifier, signals)
        end = time.monotonic()+10
        while cancelled['data-status'] not in ('cancelled', 'done', 'failed'):
            assert time.monotonic() < end, 'Own bounded search did not finish cancellation.'
            latencies.append(health())
            time.sleep(.2)
            cancelled = search('/search/status', {**signals, 'searchjob': identifier}, post=False)
        assert cancelled['data-status'] in ('cancelled', 'done'), cancelled['data-status']
    finally:
        # Cleanup is idempotent, including when an assertion fails mid-check.
        search('/jobs/cancel?id='+identifier, signals)
    assert simulation()[0] == baseline, 'Cancelling an independent search changed the cached simulation.'
    latencies.append(health())
    return {'page': page_timing, 'sse': sse_timing, 'health_probes': len(latencies),
            'max_health_seconds': max(latencies), 'search_terminal_status': cancelled['data-status']}


def verify_browser(base, output, expected_model=None):
    from playwright.sync_api import expect, sync_playwright
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        context = browser.new_context(viewport={'width': 1200, 'height': 1000})
        page = context.new_page()
        page.set_default_timeout(15000)
        errors, streams = [], []
        page.on('pageerror', lambda error: errors.append(str(error)))
        def response_seen(response):
            path = urllib.parse.urlsplit(response.url).path
            if path in ('/configure', '/evaluate', '/champions/configure'):
                streams.append({'path': path, 'status': response.status,
                                'content_type': response.headers.get('content-type', ''),
                                'cache_control': response.headers.get('cache-control', '')})
        page.on('response', response_seen)
        query = ('/?mode=duel&champion=Annie&opponent=Nidalee&opponentform=cougar&selected=custom'
                 '&snapshotlocked=true&level=6&opponentlevel=6&movement=hold&opponentmovement=hold'
                 '&distance=0&duration=5&samples=1&seed=4242')
        response = page.goto(base+query, wait_until='domcontentloaded', timeout=30000)
        assert response.status == 200
        expect(page.locator('#matchup-chart svg')).to_be_visible()
        assert page.locator('.coverage-link, #item-comparison').count() == 0
        assert page.locator('#verification-progress, #source-evidence, #evidence').count() == 0
        def configurations():
            return json.loads(page.locator('#champion-configurations').get_attribute('data-json'))
        original = configurations()
        model = original['player']['model']
        if expected_model:
            assert model == expected_model, 'Deployment model differs from the expected release.'
        completed = page.locator('#results').get_attribute('data-matchup-result')
        run = page.locator('#results').get_attribute('data-run-id')
        page.locator('#player-card .item-slot').first.click()
        page.locator('#item-picker [data-item-id="1052"]').click()
        page.wait_for_function('JSON.parse(document.querySelector("#champion-configurations").dataset.json).player.slots[0] === "1052"')
        expect(page.locator('.matchup-stale')).to_be_visible()
        assert page.locator('#results').get_attribute('data-matchup-result') == completed
        page.locator('[data-champion-slots=player]').click()
        page.locator('#champion-slot-name-0').fill('Deployment smoke')
        page.locator('[data-champion-slot-action=save][data-slot="0"]').click()
        expect(page.locator('#champion-slots-status')).to_contain_text('Saved Deployment smoke')
        page.get_by_role('button', name='Close champion save slots', exact=True).click()
        draft = configurations()
        for expected in ({'player': draft['opponent'], 'opponent': draft['player']}, draft):
            page.get_by_role('button', name='Swap champions', exact=True).click()
            page.wait_for_function('expected => {const actual=JSON.parse(document.querySelector("#champion-configurations").dataset.json); return actual.player.champion.champion===expected.player.champion.champion && actual.opponent.champion.champion===expected.opponent.champion.champion}', arg=expected)
            page.wait_for_function('!document.querySelector("#powerspike").classList.contains("is-pending")')
            assert configurations() == expected
            assert page.locator('#results').get_attribute('data-matchup-result') == completed
        page.locator('.matchup-run').click()
        page.wait_for_function('previous => document.querySelector("#results").dataset.runId !== previous', arg=run)
        expect(page.locator('.matchup-stale')).not_to_be_visible()
        scenario = json.loads(page.locator('#scenario-data').get_attribute('data-json'))['scenario']
        assert scenario['player']['loadout']['items'] == ['1052']
        result = json.loads(page.locator('#results').get_attribute('data-matchup-result'))
        def damage(trace):
            return sum(event['damage'] for event in trace if event['kind'] == 'damage' and event['actor'] == 'player')
        assert damage(result['trace']) > damage(json.loads(completed)['trace'])
        # Saved slots remain local to this disposable browser context. Loading
        # onto the other side must preserve the last completed simulation.
        page.locator('[data-champion-slots=opponent]').click()
        page.locator('[data-champion-slot-action=load][data-slot="0"]').click()
        page.wait_for_function('JSON.parse(document.querySelector("#champion-configurations").dataset.json).opponent.champion.champion === "Annie"')
        assert configurations()['opponent'] == draft['player']
        assert json.loads(page.locator('#results').get_attribute('data-matchup-result')) == result
        page.locator('#results').screenshot(path=str(output/'desktop.png'))
        for width in (736, 390, 320):
            page.set_viewport_size({'width': width, 'height': 1000})
            page.wait_for_function('document.documentElement.scrollWidth <= innerWidth+1')
        page.locator('#results').screenshot(path=str(output/'mobile.png'))
        # A separate touch context checks real image loads and 44px controls.
        touch = browser.new_context(viewport={'width': 390, 'height': 1000}, has_touch=True, is_mobile=True)
        mobile = touch.new_page()
        mobile.on('pageerror', lambda error: errors.append(str(error)))
        mobile.goto(base+query, wait_until='domcontentloaded', timeout=30000)
        expect(mobile.locator('#matchup-chart svg')).to_be_visible()
        expect(mobile.locator('#player-loadout')).to_be_visible()
        mobile_result = json.loads(mobile.locator('#results').get_attribute('data-matchup-result'))
        source = next(info for identifier, info in mobile_result['sources'].items()
                      if info.get('slot') == 'q' and any(event.get('source') == identifier and event.get('actor') == 'player'
                                                       for event in mobile_result['trace']))
        options = mobile.locator('.matchup-event-select option').evaluate_all('options => options.map(option => ({value:option.value,text:option.textContent}))')
        option = next(option for option in options if source['name'] in option['text'])
        mobile.locator('.matchup-event-select').scroll_into_view_if_needed()
        mobile.locator('.matchup-event-select').select_option(option['value'])
        mobile.wait_for_function('index => {const marker=document.querySelector(`[data-trace-event="${index}"]`); const rect=marker?.getBoundingClientRect(); const img=marker?.querySelector("img"); return rect?.width>=44 && rect.height>=44 && img?.complete && img.naturalWidth>0}', arg=option['value'])
        expect(mobile.locator('.matchup-event-detail')).to_contain_text(source['name'])
        mobile.locator('#matchup-events').screenshot(path=str(output/'touch-events.png'))
        assert not errors, errors
        assert {stream['path'] for stream in streams} >= {'/configure', '/evaluate', '/champions/configure'}
        assert all(stream['status'] == 200 and stream['content_type'].startswith('text/event-stream')
                   and any(control in stream['cache_control'] for control in ('no-cache', 'no-store'))
                   for stream in streams), streams
        browser.close()
    return {'model': model, 'streams_checked': len(streams), 'javascript_errors': len(errors),
            'viewport_widths': [1200, 736, 390, 320], 'touch_timeline': 'passed'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default=os.environ.get('PS_TEST_URL'), help='Deployment URL, provided only at run time')
    parser.add_argument('--expected-model', help='Optional release model fingerprint')
    parser.add_argument('--output-dir', type=Path, help='Screenshots; defaults to a temporary directory outside the checkout')
    args = parser.parse_args()
    if not args.url or urllib.parse.urlsplit(args.url).scheme not in ('http', 'https'):
        parser.error('Provide an HTTP(S) deployment URL with --url or PS_TEST_URL.')
    base = args.url.rstrip('/')
    output = args.output_dir or Path(tempfile.mkdtemp(prefix='powerspike-hosted-'))
    output.mkdir(parents=True, exist_ok=True)
    report = {'http': verify_http(base), 'browser': verify_browser(base, output, args.expected_model)}
    print(json.dumps(report, indent=2))
    print('Hosted smoke passed. Screenshots: '+str(output))

"""Local multi-client smoke gate against a real packaged service."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from html.parser import HTMLParser
import json
from pathlib import Path
import tempfile
import threading
import time
import urllib.parse
import urllib.request
from runtime import Page, clean_env, port, running


class Search(HTMLParser):
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get('id') == 'search-panel':
            self.result = attrs


def verify(binary_path):
    root, binary = Path.cwd(), Path(binary_path).resolve()
    chosen = port()
    with tempfile.TemporaryDirectory(prefix='powerspike-concurrency-') as data:
        with running(binary, root, [], clean_env(PS_HOST='127.0.0.1', PS_PORT=str(chosen),
                     PS_DATA_DIR=data, PS_SEED_DIR=str(root/'dist/share/powerspike/seed')), chosen) as base:
            def request(path, signals=None, timeout=60):
                headers = {}
                body = None
                if signals is not None:
                    body = json.dumps(signals).encode()
                    headers = {'Content-Type':'application/json', 'Datastar-Request':'true', 'Accept':'text/event-stream'}
                with urllib.request.urlopen(urllib.request.Request(base+path, data=body, headers=headers), timeout=timeout) as response:
                    return response.read()

            def simulation(query, fragment=False):
                page = Page()
                path = ('/evaluate?'+urllib.parse.urlencode({'datastar':json.dumps(query)}) if fragment
                        else '/?'+urllib.parse.urlencode(query))
                page.feed(request(path).decode())
                assert page.timeline and page.scenario
                return float(page.timeline['data-total']), page.scenario['data-json']

            latencies = []
            def health():
                started = time.monotonic()
                assert request('/healthz', timeout=3) == b'ok\n'
                elapsed = time.monotonic()-started
                latencies.append(elapsed)
                assert elapsed < 2, 'HTTP service blocked while compute or rendering work ran.'

            query = {'mode':'practice', 'champion':'Garen', 'selected':'custom', 'level':18,
                     'samples':64, 'seed':4242, 'duration':60, 'targethealth':1000000,
                     'abilities':'false', 'movement':'hold', 'distance':0, 'snapshotlocked':'true'}
            start = threading.Barrier(6)
            def concurrent(change):
                start.wait(timeout=10)
                return simulation({**query, **change})
            with ThreadPoolExecutor(max_workers=5) as pool:
                futures = [pool.submit(concurrent, {}) for _ in range(4)]
                variant = pool.submit(concurrent, {'slot1':'1036'})
                start.wait(timeout=10)
                probes = 0
                while not all(future.done() for future in [*futures, variant]):
                    health()
                    probes += 1
                    time.sleep(.02)
                results = [future.result() for future in futures]
                assert probes > 0
                assert all(result == results[0] for result in results)
                assert variant.result()[0] > results[0][0]
            assert simulation(query) == results[0], 'Concurrent requests changed the reproducible result.'
            # Browser reruns use SSE fragments. They must use the same render
            # lane and keep each request's inventory/result separate too.
            with ThreadPoolExecutor(max_workers=2) as pool:
                updates = [pool.submit(simulation, query, True),
                           pool.submit(simulation, {**query, 'slot1':'1036'}, True)]
                while not all(update.done() for update in updates):
                    health()
                    time.sleep(.02)
                assert updates[0].result() == results[0]
                assert updates[1].result() == variant.result()

            def search(path, signals, post=True):
                if post:
                    body = request(path, signals)
                else:
                    body = request(path+'?'+urllib.parse.urlencode({'datastar':json.dumps(signals)}))
                page = Search()
                page.feed(body.decode())
                assert hasattr(page, 'result'), body[:200]
                return page.result

            signals = {**query, 'duration':5, 'samples':1, 'searchseconds':30,
                       'searchslots':6, 'searchbudget':10000, 'searchpool':''}
            first = search('/search', signals)
            other_signals = {**signals, 'searchpool':'1036,1052', 'searchslots':1, 'searchseconds':5}
            other = search('/search', other_signals)
            queued = search('/search', signals)
            assert len({first['data-job'], other['data-job'], queued['data-job']}) == 3
            assert queued['data-status'] == 'queued'
            cancelled = search('/jobs/cancel?id='+queued['data-job'], signals)
            assert cancelled['data-status'] == 'cancelled'
            search('/jobs/cancel?id='+first['data-job'], signals)
            deadline = time.monotonic()+15
            while True:
                health()
                a = search('/search/status', {**signals, 'searchjob':first['data-job']}, post=False)
                b = search('/search/status', {**other_signals, 'searchjob':other['data-job']}, post=False)
                if a['data-status'] == 'cancelled' and b['data-status'] == 'done':
                    break
                assert time.monotonic() < deadline, (a, b)
                assert b['data-status'] not in ('cancelled','failed'), b
                time.sleep(.02)
            assert simulation(query) == results[0]
            health()
    print('Concurrent HTTP: four shared simulations, independent inventory, SSE reruns, queued/running search cancellation and unaffected neighbor passed. '
          f'{len(latencies)} health probes; maximum local latency {max(latencies):.3f}s (limit 2s).')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('binary', nargs='?', default='dist/bin/powerspike')
    verify(parser.parse_args().binary)

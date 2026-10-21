# Hosted deployment smoke check

`test/hosted.py` is an opt-in check of a running deployment. It takes the origin
from `PS_TEST_URL` or `--url`; no deployment address belongs in source files,
examples, configuration committed to Git, or this record. It does not run as
part of CI or select a production target by default.

Use a Python environment with the pinned Playwright/Chromium tooling from the
browser gate. Provide `PS_TEST_URL` privately in the process environment, then:

```sh
python test/hosted.py --output-dir /tmp/powerspike-hosted-check
```

`--expected-model` optionally checks a known release model fingerprint. Without
`--output-dir`, screenshots go to a new temporary directory outside the
checkout. Keep any redirected logs there too. The report contains timings,
relative routes and model identity, without the origin.

The check uses two small cached-patch simulations, compares their different
inventories and repeats the original scenario to check isolation. The same
scenario must reproduce through the public Datastar SSE route. Complete pages
must use `no-store`; SSE must use `no-cache` or `no-store`, without an edge cache
hit. A search receives a two-second compute budget and is cancelled using only
its own returned job identifier. Cleanup also requests cancellation if a check
fails. Existing cached snapshots and server configuration are unchanged.

Fresh browser contexts exercise item editing, explicit reruns, champion
save/load across sides, swapping twice and preserving completed results while
configuration changes. Player pages retain the simulation label and keep
developer diagnostics out of the main view. Desktop and 736/390/320-pixel
layouts must fit. A separate touch context checks actual ability artwork,
event selection and the 44-pixel timeline control. Screenshots support visual
review. Browser storage is confined to these disposable contexts.

## Observed deployment results, 21 October 2026

The deployed model matched v0.20.1. Two-client simulation isolation, exact SSE
reproduction, cancellation, save/load, swap, timeline artwork and responsive
checks passed. Five browser SSE responses completed with the expected content
type/cache policy, with no JavaScript errors. Screenshots were visually reviewed.

Four health probes had a maximum observed response time of 0.208 seconds.
The ordinary simulated-page check took 8.947 seconds to its first byte; its SSE
rerun took 1.057 seconds. Follow-up sequential requests reproduced the page
delay:

| Request | First byte | Total | HTML/file bytes |
| --- | ---: | ---: | ---: |
| Practice, 3 seconds, one trial | 8.769 s | 8.863 s | 3,429,022 |
| Duel, 5 seconds, one trial | 10.720 s | 11.055 s | 3,579,832 |
| Application CSS | 0.134 s | 0.136 s | 50,649 |

The next priority is profiling page generation and reducing the initial catalog
payload. These observations do not identify the exact slow function or separate
origin time from proxy time. The source currently renders the entire item
catalog and its detail payloads into each page; that is a profiling candidate,
not a measured attribution of the delay.

The edge rejected the default Python user agent with HTTP 403/error 1010, while
Chromium and the explicitly named smoke-check user agent succeeded. The helper
uses that identifying user agent; it does not change edge policies.

This is a small live software smoke check. It covers finite SSE updates and
ordinary browser interactions, rather than establishing peak throughput or
long-lived stream flushing. Controlled provider outages, cold refreshes,
quota exhaustion and longer-running memory/disk behavior through the proxy
remain staging/deployment checks. No game-mechanics evidence is added.

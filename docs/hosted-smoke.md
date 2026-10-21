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

## v0.20.1 deployment baseline, 21 October 2026

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

These observations prompted profiling page generation and reducing the initial
catalog payload. At that point the source rendered the entire item catalog and
its detail payloads into each page. The subsequent retained-data profile and
implementation are documented in [catalog loading](catalog-loading.md).

The edge rejected the default Python user agent with HTTP 403/error 1010, while
Chromium and the explicitly named smoke-check user agent succeeded. The helper
uses that identifying user agent; it does not change edge policies.

This is a small live software smoke check. It covers finite SSE updates and
ordinary browser interactions, rather than establishing peak throughput or
long-lived stream flushing. Controlled provider outages, cold refreshes,
quota exhaustion and longer-running memory/disk behavior through the proxy
remain staging/deployment checks. No game-mechanics evidence is added.

## v0.21.0 deployment follow-up, 21 October 2026

After the upgrade, the same bounded hosted smoke passed simulation isolation,
exact SSE reproduction, own-job cancellation, champion save/load, swapping,
timeline artwork and desktop/touch layouts. Five browser SSE responses passed
content-type/cache-policy checks with zero JavaScript errors. Four health probes
had a maximum observed response time of 0.469 seconds. The concurrent page check
took 6.662 seconds to first byte; its SSE rerun took 1.161 seconds. The combat
model still matched the release fingerprint.

A separate disposable browser context confirmed the declared release was
0.21.0 and that item cards were absent before opening the catalog. The first
open loaded 870 items; reopening reused them with one catalog request in total.
Search found Amplifying Tome. A local report download included the completed
workspace and observed outcomes exactly, declared release 0.21.0, and omitted
the page origin. The mobile report and desktop catalog screenshots were
visually reviewed. No report was submitted.

Three sequential warm requests per case produced:

| Request | Median first byte | First-byte range | HTML bytes |
| --- | ---: | ---: | ---: |
| Practice, 3 seconds, one trial | 3.072 s | 2.929–3.129 s | 531,662 |
| Duel, 5 seconds, one trial | 4.459 s | 4.118–4.665 s | 682,616 |

The new sequential cases used a level-six Annie practice scenario and an
Annie versus Cougar Nidalee duel, with fixed seeds and cached snapshots.
Page configurations differ from the earlier sequential baseline; these timings
are small live samples. Initial pages are substantially smaller and faster than
the earlier 9–11-second observations, while 3–5-second warm first-byte times
still leave room for further work. The retained local benchmark provides the
controlled before/after comparison for the catalog change.

All live-check scripts, logs, downloaded reports and screenshots stayed under
temporary directories outside the checkout. Only this origin-free summary is
retained. The throughput, long-running resource use and controlled outage limits
of the original smoke check still apply.

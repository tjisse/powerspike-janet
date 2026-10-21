# Catalog loading and initial page cost

The hosted smoke check found 9–11-second warm page responses with roughly
3.4 MB of uncompressed HTML. A retained-data profile isolated a major source
of that work: closed champion/item dialogs rendered every card, description,
tooltip payload and repeated selection expression into each page. Their
2,738,724 bytes accounted for about 81% of the retained matchup's initial HTML.
The same five-second, one-trial duel simulation took about 0.03 seconds locally.

The dialogs now start as small shells. Opening one requests compact presentation
records from `/catalog` for the current configuration's exact patch and snapshot.
The server builds the JSON on the bounded render worker, independently of
simulation and network jobs. Identical active catalog requests can share work;
the response contains no user-specific configuration. The response uses
`no-store`, and each dialog reuses its records until the selected snapshot changes.

The browser builds named buttons and images with DOM/text APIs. Search keeps
name, ID, description and tag matching, including the Rift/all-modes selector.
Selection is delegated through the dialog's existing Datastar configuration
flow. Provider strings are values, never executable selection expressions.
Both champion sides, physical item slots and explicit matchup reruns retain
their previous behavior. Complete native inventory forms remain in the page
for users with JavaScript disabled.

Item cards fetch build-specific descriptions only on hover/focus, through the
existing scenario-scoped tooltip route. Loading and failed descriptions are
explicit; no provisional numerical tooltip replaces the requested build values.
The server still computes all values. Configuration changes close obsolete
picker tooltips, and late tooltip responses cannot attach to another scenario
or participant.

The original legacy view identifies its snapshot through the form when no
canonical scenario document exists. It retains plain patch descriptions with
an explicit notice that build-specific tooltip values are unavailable there.

Catalog requests share one pending attempt per dialog/snapshot. Loading has an
announced status and `aria-busy`; failure or the 15-second browser request timer
offers an explicit retry. Closing/reopening a loaded dialog preserves its search
and scope. A snapshot change aborts obsolete requests, clears old choices and
tooltips, and verifies the response identity before accepting new cards. The
browser retains only the current catalog for each dialog, with at most 5,000
records accepted per response. Existing worker queue/history bounds remain.

## Local measurements

Using the same retained 16.19.1 seed and duel inputs in one local process:

| Output | Before | After |
| --- | ---: | ---: |
| Closed dialog HTML | 2,738,724 bytes | 4,697 bytes |
| Complete initial HTML | 3,368,478 bytes | about 634,450 bytes |
| Warm complete-page generation | 2.89–2.92 s | 0.89–0.90 s |

That is about 81% less initial HTML and 69% less local page-generation time.
These are local comparisons, not a measurement of the upgraded public service.
The native forms now account for most remaining initial HTML; changing them
requires preserving the existing no-JavaScript workflow.

A second check compared the downloaded v0.20.1 executable with the optimized
standalone build on identical local seed data. After one warm-up request, three
requests per executable gave these results:

| Standalone executable | Initial HTML | Median first byte |
| --- | ---: | ---: |
| Published v0.20.1 | 3,388,909 bytes | 2.2665 s |
| Optimized build | 654,882 bytes | 0.7726 s |

All eight runs, including warm-ups, produced identical simulation results.
Fetching the 870 item records used 350,600 bytes and 0.0257 seconds locally;
the 173 champion records used 28,985 bytes and 0.0157 seconds. These requests
occur only on first opening the corresponding picker for a selected snapshot.

## Retained verification

`test/pickers.janet` checks small initial shells, all 173 champions and 870 items,
snapshot-scoped artwork, invalid-request recovery and isolation between an old
snapshot and a newly published synthetic revision. `test/catalog_browser.py`
checks first-open loading, reuse, search/scope, failure/retry, unavailable and
recovered server tooltips, configuration invalidation, keyboard/nested-element
selection, delayed snapshot responses, mismatched identities and safe provider
text. It runs inside the normal browser gate.

The relocated-runtime gate also loads both catalogs from the standalone
executable and limits its standard retained matchup page to 1 MiB. The broader
browser gate preserves comparisons, optimizer apply/Undo, champion save slots,
swapping, timeline artwork, desktop/touch layouts, native forms and retained
combat fixtures. Combat formulas, model identity and scenario formats are
unchanged. No in-game combat evidence is added.

`make test` passed 83 core cases, retained source/catalog checks and 170 Python
cases (8 skipped). `make test-web` passed 44 frontend cases and the existing
combat/optimizer suites, plus the new catalog API cases. `make test-runtime`
passed the standalone catalog and page-size checks, retained combat fixtures
and 363 concurrent health probes, with a maximum observed local latency of
0.049 seconds (two-second limit).

The complete browser gate and final focused catalog/legacy cases passed.
Loading, retry and loaded picker screenshots at desktop/mobile sizes were
visually reviewed. The final RPM passed extracted-payload, runtime, configuration
and service/lifecycle checks. Formatting, Python syntax, Git diff and unchanged
model-fingerprint checks also passed. Deployment addresses remain outside
repository files; public performance must be rechecked after release/upgrade.

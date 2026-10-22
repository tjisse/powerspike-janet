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

## Native item-option rendering, 22 October 2026

The remaining native inventory controls repeated the full 870-item option tree
six times in practice mode and twelve times in a duel. The HTML library's
option-list rendering repeatedly concatenated the growing immutable string.
Local profiling put practice's native inventory at about 0.36 seconds and the
duel loadout at about 0.75 seconds, despite much cheaper simulation work.

`web/select-options.janet` now constructs one escaped option template using a
buffer and records where each option's selected marker belongs. Each inventory
slot receives a fresh selected string from that template. Practice and duel
keep their existing labels, full catalogs, physical empty slots and native
forms. Both values and captions use the existing HTML escaping. The template
lives only for the current render: it adds no global cache, expiry policy,
snapshot invalidation or user-specific response reuse. Dynamic responses keep
their existing cache policy and rendering stays on its bounded worker.

The [retained measurements](benchmarks/page-loading-2026-10-22.json) use the same
16.19.1 seed, level-six Annie scenarios, model, snapshot and simulation inputs.
Each local case has one warm-up and three sequential samples. Median complete
page-generation time fell from **0.544 to 0.185 seconds** for practice and
**0.914 to 0.234 seconds** for a duel. Simulation metrics and model identity are
unchanged. The duel's page size is unchanged; practice adds 75 bytes for a
missing native-form marker described below. The large native catalog payload
still travels with the page, so this change reduces rendering cost rather than
claiming another download-size reduction.

A copied-executable HTTP comparison reduced median warm first-byte time from
**0.479 to 0.179 seconds** for practice and **0.763 to 0.202 seconds** for duels;
its samples are retained with the profile. Those are local software
measurements. Three small sequential requests to the deployed practice page
before deployment of this change returned 542,070 bytes and first-byte times
of 5.955, 3.993 and 3.800 seconds. The deployed version was not checked in that
small timing sample. These measurements establish remaining hosted latency,
not a measured public improvement from this implementation.

The expanded native browser checks found a separate existing reliability bug:
practice forms submitted checkbox values as `on` without the native-form
marker, causing an invalid on/off error. The marker now appears inside
`noscript` in both layouts. Native requests normalize checked/unchecked combat
and objective controls, while JavaScript-enabled form navigation keeps explicit
false values. Item changes, physical holes and both champions' selected
options round-trip correctly. JavaScript forms do not submit a native marker.

`test/select-options.janet` checks escaped provider text/values, exactly one
selection, immutable template reuse and separate templates for changed data.
The browser gate checks all 871 choices per slot, edits on both duel sides,
practice checkbox settings, empty-slot preservation and mobile native forms.
The concurrency gate adds four distinct matchup pages with independent native
selections while health checks continue. The opt-in hosted smoke check uses the
completed snapshot's Q metadata for its touch event and scrolls the selector
into view before inspecting the anchored tooltip.

The remaining deployment work is to remeasure after release/upgrade and run
controlled provider-outage and longer memory/disk checks in staging. Initial
payload size and first-use catalog/artwork latency remain profiling targets.

Core/source/Python, frontend, combat, standalone runtime, expanded concurrency
and full browser gates passed. The concurrent check completed 358 health
probes with a maximum local latency of 0.280 seconds (two-second limit).
The deployment smoke helper also passed against a fresh local packaged service:
independent inventories, finite SSE reruns, dynamic cache headers, own-job
cancellation, five browser SSE responses, zero JavaScript errors and desktop/
touch layouts. Its four health probes had a maximum of 0.018 seconds. This
local helper check does not establish reverse-proxy outage behavior or capacity.

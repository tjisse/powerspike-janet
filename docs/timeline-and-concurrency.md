# Timeline artwork and concurrent requests

The duel timeline again shows ability artwork, item/rune artwork where a source
has it, and the acting champion's portrait for ordinary attacks. Each URL is
scoped to the completed result's exact patch and snapshot. Editing the next
fight's configuration leaves the completed result and its artwork intact.
Ability-slot metadata also supplies Q/W/E/R labels when an internal spell ID
does not end in that letter.

Markers remain named buttons with event times, source labels and selection
state. Artwork is decorative; keyboard activation preserves focus after the
chart redraw. Missing images fall back to readable labels, and redraws do not
keep requesting a failed image. Parried effects retain their crossed-out
appearance and consumption details. Crowded markers remain available through
the complete event selector, including on narrow screens.

## Status duration bands

The same champion lanes now show colored intervals for applied controls, named
buffs, temporary stat effects, shields, parry and ready empowered attacks.
Overlapping effect types occupy separate strips within the fixed-height lane;
ability markers remain above them. A compact key identifies the colors. Hover,
keyboard focus and touch inspection expose the affected champion and the
interval's start, end and active duration without changing result layout.

`status-timeline.janet` observes actor state after each engine event, only when
tracing is enabled. It does not schedule events or change combat calculations.
Intervals account for tenacity, reapplication, selective cleanse, buff stacks
and consumption, depleted shields, empowerment consumption at release, expiry
and death. Known expiry times bound intervals even when no expiry event is
scheduled. The UI clips them at the displayed fight end and uses the graph's
time scale. Colors remain consistent across participants and redraws. Only
effects actually modeled and applied are shown; excluded effects gain no new
mechanics from this presentation change.

`test/status-timeline.janet` checks these boundaries with explicit synthetic
engine scenarios and scoring parity with tracing disabled. Its generated
browser fixture checks exact band geometry, overlap, colors, empty results,
fight-end clipping, keyboard/touch tooltips and layouts down to 320 px.
These synthetic cases are UI/engine checks, not new champion evidence. The
retained control and Riposte browser fixtures also check real response payloads
and their rendered silence/parry bands through the packaged executable.

## Reliability fixes

Cancelling a queued job previously marked its record cancelled but left its
queue slot, task and payload occupied until a worker became available. The
queue regression first reproduced this failure with a held compute worker and
all eight waiting slots filled. Cancellation now removes the job immediately
and releases its task/input. Repeated cancellation remains safe.

Deduplication previously let a new request attach to an already-cancelling
job with the same key. A retry now receives a fresh job, while identical active
requests continue to share their computation.

The HTTP smoke test also exposed a rendering stall. Five simultaneous page
requests for a 60-second, 64-trial attack scenario produced roughly 3.4 MB of
HTML each. Computation ran off the event loop, but HTML construction still ran
on it; a diagnostic health request waited about 9.9 seconds as results rendered.
Full player pages and completed-result SSE fragments now render on one separate
worker. The existing shared eight-slot waiting queue bounds pending work, and
only one render job runs at a time. Rendering does not wait for a long item
search or a provider download. Unkeyed render jobs never share another
request's HTML. The render payload references the immutable package by identity
instead of copying the complete package into each job.

These changes add no combat formulas or game evidence. Model identity,
simulation results and scenario/export formats are unchanged.

## Verification and limits

`test/job-queue.janet` uses channel barriers to check full-queue rejection,
immediate cancellation/cleanup, shared active work, fresh retries, repeated
cancellation and independent compute/render/network lanes. It also checks that
cancelling one job leaves its neighbor's result intact.

`test/concurrency.py`, included in `make test-runtime`, starts an isolated real
packaged service with retained data. Four identical clients and one different
inventory run simultaneously. It checks exact result/scenario reproduction,
the inventory's expected damage change, simultaneous browser-style SSE reruns,
queued and running search cancellation, and an unaffected neighboring search.
Health requests must complete within two seconds throughout. The packaged
runtime gate passed 892 probes with a maximum observed local latency of
0.086 seconds.

The browser regression loads actual retained Annie Q/W and champion portrait
images, checks keyboard activation and preserved results after configuration
edits, selects crowded events at 736/390/320-pixel widths, and deliberately
fails spell-image requests to check the text fallback and touch targets.
Desktop/mobile screenshots were visually reviewed.

`make test` passed 83 core cases, retained source/catalog checks and 170 Python
cases (8 skipped). `make test-web` passed 44 frontend cases and the existing
combat, parser, cache and optimizer suites, including the new queue regression.
`make test-runtime` regenerated the retained fixtures and passed the relocated
executable and concurrent HTTP gates.
The complete browser gate passed, including optimization/apply/cancel/undo,
error recovery, save/share/import, both duel participants, responsive layouts
and the retained parry/control/changing-cost/health-cost fixtures. Python syntax,
Janet formatting and Git diff checks passed.

This is a local software reliability check with a small number of clients. It
does not establish production throughput, proxy behavior, provider outage
handling or a memory/storage capacity budget. Those checks remain on the
[next-improvement list](next-improvements.md).

## Two shared CPU slots (22 October 2026)

After v0.24.0, rendering and combat work share **two active CPU slots**, with
**at most one optimizer**. Previously all simulations waited behind the active
optimizer, even when the rendering lane was idle. A running optimizer now leaves
a slot available for ordinary fights and views. Queued interactive work takes
priority over a queued search, preserving FIFO within each class. Running jobs
are not preempted; a search can wait while interactive requests keep arriving.

Provider downloads and offline reparse/publication retain their single separate
lane. That worker can also use CPU when parsing downloaded records. This keeps
managed publication serialized while network waits do not occupy either of the
two render/combat slots. The eight-job waiting limit, shared identical work,
64-record history bound and request-specific HTML remain unchanged.

Active jobs are now tracked by job ID. A cancelling worker retains its occupied
slot until it finishes, so a retry cannot create an extra active worker. Both
failure and success release exactly that job's slot. The event loop continues
to handle health checks and SSE progress while native threads perform work.
Threads are still created per job; this change does not introduce a persistent
worker pool or a new server configuration setting.

The deterministic queue gate now holds both CPU slots and verifies the shared
limit across rendering/simulation, one optimizer, interactive queue priority,
serialized downloads/reparse, cancellation cleanup, retry isolation and recovery
after a worker failure. The packaged HTTP gate also requires an ordinary fight
and its HTML to finish while a 30-second optimizer is still running. The local
run completed that fight in **0.322 seconds**, with 243 health probes and a
maximum health latency of **0.375 seconds** (two-second limit).

A separate short local burst used four clients to request 20 distinct duel
pages during one optimizer. `/proc/<pid>/status` showed 22.94 MiB initial RSS
and a **306.75 MiB** high-water mark, still retained immediately after the burst.
Browser verification ran concurrently in a different process, so this is a
per-process memory sample, not an uncontended throughput benchmark. It does not
establish a long-running memory bound or production capacity. Check deployed
latency and sustained resource use separately on the two-core host.

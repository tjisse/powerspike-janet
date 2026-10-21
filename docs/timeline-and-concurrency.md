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

# Patch refresh deadlines

A patch refresh previously limited each HTTPS request to 45 seconds, but gave
the whole job no deadline. Optional source failures were retained as coverage
gaps and downloading continued. With hundreds of champion/source requests, a
partially unavailable provider could occupy the only network worker for hours.

Refreshes now share a monotonic active-work deadline. The default budget is
300 seconds; `PS_PATCH_TIMEOUT_SECONDS` accepts whole seconds from 1 to 1800
and invalid values fail service startup. The budget starts inside the download
worker, so queued time does not consume it. Each HTTPS request uses the remaining
time, capped at the existing 45 seconds. Connection establishment remains capped
at five seconds. Progress and byte callbacks check cancellation and deadline
expiry, including when a provider stops sending bytes. Already-expired requests
never start.

The downloader checks the deadline before and after provider requests, during
champion processing, after normalization/encoding, and before publication.
Expiry and cancellation stop the job even if the active source is optional;
they cannot become ordinary coverage gaps followed by a partial publication.
The final check runs inside the shared storage guard, after waiting for other
writes and checking quota, before moving staging or changing the current pointer.

The job reports `Patch refresh timed out. Cached patches remain available. Try
again.` Existing job handling marks it failed, removes staging and releases the
network worker. Completed current and explicitly retained snapshots remain
usable, and a retry receives a new job and a fresh budget. Unrelated optional
provider errors within the budget retain the existing explicit coverage behavior.
No automatic retry loop or snapshot eviction is added.

This is a cooperative refresh deadline with bounded HTTPS waits, not a hard
operating-system kill timer. Synchronous parsing, filesystem operations and
cleanup finish before the next checkpoint; a blocked filesystem can delay them.
Version discovery and individual artwork downloads keep their separate request
limits. Actual proxy behavior and production throughput are separate checks.

## Retained checks

`test/patch-deadline.janet` uses synthetic sources and an injected monotonic
clock to check cumulative optional failures, late required responses,
cancellation of an optional request and unchanged cached pointers. A channel
barrier holds the writer guard until expiry, proving that a waiting publisher
rechecks before moving staging or updating the pointer.

`test/https.py` drives the real HTTPS client and background jobs through a
trusted loopback TLS fixture. Required catalogs succeed, one optional response
waits 0.75 seconds, and the next stalls for six seconds. A two-second refresh
budget must fail and release the worker within 3.5 seconds, without publishing
the new patch or keeping staging. Request counts prove that both required
catalogs and both optional requests were reached. Recovery then successfully
publishes the same patch through a fresh job. Separate cases check a short
request deadline without a cancellation callback and no request after expiry.
The fixture overrides addresses/trust only in its test process; production
provider restrictions and TLS verification stay enabled.

The relocated-runtime gate also rejects invalid deadline settings with a clear
configuration error. These are software reliability checks, not additional
in-game combat evidence. Successful normalized package bytes and combat
formulas are unchanged. The model fingerprint advances because the package
loader participates in that fingerprint; older saved-model notices still apply.

`make test` passed 83 core cases, retained source/catalog verification and 170
Python cases (8 skipped). `make test-web` passed 44 frontend cases and the
existing combat/optimizer suites, plus the new deadline and extended TLS cases.
`make test-runtime` passed the relocated executable and regenerated retained
fixtures, including invalid deadline-setting rejection. Its concurrent HTTP
gate passed 679 health probes with a maximum local latency of 0.041 seconds
(two-second limit). Formatting, Python syntax and Git diff checks passed.
The rebuilt RPM also passed extracted-payload, permissions, preserved
configuration, service/lifecycle and relocated-executable verification.

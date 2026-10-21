# Storage limits and artwork failures

Managed cache writes now check the current file-byte total while holding one
shared guard. Patch and artwork downloads use the same guard across their
worker VMs. The gate is created in the running service before workers start;
the executable image contains no build-time channel instance.

The allowance comes from `PS_DATA_LIMIT_MB`: default 5120 MiB, with the existing
100–1048576 MiB accepted range. Accounting covers retained sources, artwork,
normalized packages, manifests, version-list persistence and atomic pointer
updates. Atomic replacement reserves the entire temporary file while the old
file still exists. Failed writes/renames clean their temporary file and release
the guard. Publication reserves pointer space before moving staging, so quota
exhaustion leaves the previous current pointer intact.

Seed copying checks the whole version's additional size under the same guard.
An unaffordable optional seed import is skipped so existing usable cached
patches can still start. A fresh cache that cannot import any seed fails
explicitly. Lowering the allowance does not delete cached data or prevent
cached reads; new writes are rejected until space is reclaimed or the allowance raised.
Patch-download failure/cancellation cleans staging through the shared guard.

This is a budget for logical file contents, not filesystem blocks, directories,
journals or memory. It coordinates writers in one running service process.
Use one writing PowerSpike process per data directory; independent processes
sharing a writable directory are not covered by this guard. No automatic
eviction of reproducible snapshots is introduced.

## Reproduced storage discrepancy

Previously a patch download checked its initial cache size plus downloaded raw
source bytes, leaving an 8 MiB margin. Artwork could complete after that initial
observation. Normalized package and manifest files also bypassed the check.

The regression starts with 9 MiB free under a 100 MiB allowance. Its synthetic
provider completes 8.5 MiB of separate artwork writes before returning a catalog
with 600,000 padding bytes. The previous downloader exceeds the allowance; the
same regression against the guarded writer rejects the catalog before writing
it and preserves the cached snapshot. Separate cases exhaust space exactly
before normalized-package and manifest writes, then reclaim space and publish
a fresh revision successfully. These fixtures test software behavior, not game
mechanics or production capacity.

## Repeated artwork failures

Requests for the same missing artwork share an in-flight attempt. After a
provider, format, size or storage failure, that exact asset path retains a
failure for 30 seconds. Waiting and subsequent requests reuse the failure,
instead of taking turns retrying the provider. After expiry the next request
can retry; an already-cached file always takes precedence.

Failure metadata is capped at 256 entries, with at most 1024 error bytes per
entry and expired entries reclaimed on insertion. The existing eight active
downloads and 128 waiting-request bounds remain. Download payloads remain
limited to 1 MiB and must have the PNG signature before they can be cached.

The HTTP layer returns `503`, `Cache-Control: no-store` and a positive
`Retry-After` for transient failures. Queue saturation gets a one-second retry;
retained failures report the remaining retry window. Successful cached assets
keep their immutable one-year cache header. The combat timeline's existing
readable fallback handles missing artwork; no simulation result depends on
whether its artwork downloads.

## Checks

`test/storage.janet` holds the guard with a channel barrier while eight real
worker VMs contend for a 2500-byte allowance. Exactly two 1000-byte writes fit.
It checks replacement peak space, unchanged old files, reserved publication
space, rename-error cleanup and guard release.

`test/storage-packages.janet` checks the interleaved-write reproduction,
normalized/manifest accounting, immutable current pointers, restart at quota
and successful publication after reclaim. Sparse filler keeps the test's
physical disk use small while exercising the real 100 MiB setting.

`test/assets.janet` checks shared success/failure behavior, retry expiry,
cached reads above the allowance, invalid/oversized payloads, concurrent
distinct-asset quota enforcement, bounded failure retention, backpressure and
HTTP retry headers. The local TLS fixture independently confirms that six
simultaneous asset requests cause one real failed provider request, and that
expiry/recovery causes one successful retry.

Combat formulas and immutable game-package bytes are unchanged. The model
fingerprint advances because the package-loading module participates in that
fingerprint. Existing older-model scenario notices remain applicable; this
work supplies no additional in-game verification evidence.

`make test` passed 83 core cases, retained source/catalog verification and
170 Python cases (8 skipped). `make test-web` passed 44 frontend cases and the
existing combat/optimizer suites, plus the new storage/artwork regressions and
extended local TLS gate. The interleaved-quota regression also failed against
the previous downloader at its total-byte assertion, establishing the original
overrun before checking the correction.

`make test-runtime` passed the relocated executable, regenerated retained
fixtures and concurrent HTTP gate: 625 health probes with a maximum observed
local latency of 0.049 seconds. The complete browser gate passed, including
champion save slots/swapping, real timeline icons and missing-artwork fallback,
optimization/apply/Undo, error recovery, save/share/import, responsive layouts
and retained combat fixtures. Final-build champion/timeline browser checks and
cached-artwork reads without provider metadata also passed. Formatting, Python
syntax and Git diff checks passed.

The [refresh-deadline follow-up](patch-refresh-deadlines.md) bounds cumulative
provider waits and checks timeout cleanup/recovery. Actual reverse-proxy
behavior and longer-running memory/disk use under player traffic remain
deployment checks.

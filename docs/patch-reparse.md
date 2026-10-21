# Reparse saved patch data

When a snapshot's parser revision differs from the app's current revision,
PowerSpike marks the active patch in the header and shows **Patch data needs
reparsing** inside its dropdown. The
warning identifies both revisions and offers **Reparse saved data** when the
snapshot retains the required raw catalogs. This is a manual action. Opening,
editing or rerunning a mismatched snapshot does not automatically reparse it.

The action reads the selected snapshot's retained source files and normalizes
them with the current parser. It uses the same normalization pipeline as
**Refresh patch data**, without requesting any provider data. If raw data was
never retained, including the curated initial seed, the warning instead directs
the user to the existing patch settings and download action. Missing optional
inputs remain coverage gaps; reparsing cannot supply data that was never saved.

Reparsing runs as a cancellable background job in the shared patch-work lane,
keeping simulations and rendering in their own lanes. Duplicate requests for
the same patch and source snapshot share active work. Queue limits and the
existing patch timeout/storage allowance apply. After completion, the app opens
the resulting snapshot with the current champion, inventories and fight
configuration. The warning disappears when that snapshot uses the current
parser. Saved scenarios and explicit snapshot links retain their original
revision. Reparsing opens a new revision in the active workspace and does not
overwrite saved documents.

## Integrity and publication

Before reading raw inputs, the source descriptors in the manifest must match
those in the hash-verified package. Source paths stay under `sources/`, and each
input's bytes must match its recorded SHA-256. Retained inputs also keep the
provider reader's 64 MiB per-file bound. A missing or corrupt file listed in the
manifest fails the job, even when that source was originally optional; it never
silently turns into a coverage gap or a network fallback.

The job stages copied raw files and freshly parsed data, then publishes the
current pointer last through the existing storage guard. Successful output keeps
the original source URLs/hashes and download timestamp. A newly published
manifest records `reparsed_from` and `reparsed_at`. If identical parsed output
already exists, publication reuses that immutable snapshot and its manifest.
Original snapshots, manifests and raw files remain unchanged. Failed or
cancelled jobs clean staging; failures before publication preserve the current
pointer. Cancellation arriving after publication cannot undo that completed
atomic action, and the original snapshot remains available either way.

Source reparsing is independent of the artwork cache. Uncached icons continue
to use its existing download/fallback behavior.

## Checks

`test/reparse.janet` uses retained 16.21 Annie/Garen responses and a parser-6
snapshot. It verifies mismatch/current/future revision detection, no automatic
job, seed fallback, explicit job tracking/navigation, fresh/reparsed champion
parity, immutable old files, preserved raw hashes and download timestamp,
manifest tampering, missing/corrupt sources, cancellation before and during
parsing, duplicate/queued job cancellation/retry, independent simulation work
and quota failure cleanup.

`test/reparse_browser.py` runs the compiled service with provider access blocked
by an unavailable proxy. It checks the warning/action, successful offline
reparse, preservation of edited configuration, restored champion casts, warning
removal, pinned old snapshots, visible corruption errors with retry, missing-raw
fallback and layouts down to 320 px. Both are included in the normal release/CI
checks; the browser gate uses `--reparse-fixture`.

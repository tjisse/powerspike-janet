# Champion save slots and side swapping

Each champion card opens the same four browser-local slots. A slot can be named,
saved from either side, loaded onto either side, replaced or cleared. Saving
uses the latest server-validated configuration preview, including edits that
have not been simulated. Pending or invalid edits must finish updating first.
The previous completed fight is not used as the save source.

Each version-one `powerspike-champion` document retains the exact patch,
snapshot and model identity, the canonical participant specification, and six
physical item positions. It preserves level, fixed form, runes, shards, adaptive
force, summoner spells, skill order, automatic/manual ranks, activation rules,
priority, attacks/abilities, movement and starting health/resources/hit chance.
Shared duration, distance, trials and seed belong to the current fight.

Loading validates the participant against the current retained snapshot before
changing configuration. Another patch/snapshot is visibly incompatible and is
also rejected by the server. A different saved model receives a rerun notice.
The server rejects unknown fields, unsupported versions, invalid champions or
ranks, and inconsistent item lists/positions. Each document is limited to 16 KB;
the four-slot collection is bounded and writes report local storage failures.
There is no account sync; deleting browser storage removes these slots. Existing
scenario/comparison saves and exports retain their separate format and controls.

Swap exchanges complete participant settings and inventory positions in one
server operation. Swapping twice restores the configuration. The last completed
result stays visible, with the existing stale-result notice when settings differ;
only Run matchup replaces it. Pinned comparison items remain valid when the
player champion stays the same, and are cleared when the player champion changes.
Optimizer item locks and Undo state reset after a load/swap so they cannot target
the previous champion's inventory.

## Later-slot inventory correction

Preservation checks exposed an existing discrepancy in URL parsing. With only
`enemyslot6=1036`, the card displayed Long Sword but the opponent's compiled item
list was empty, because parsing checked only whether `enemyslot1` was present.
Any explicit enemy slot now selects the physical-slot inventory. The saved
configuration, preview stats and actual combat participant use the same items.
The correction changes affected URL inputs; combat formulas and engine identity
are unchanged.

## Provider reliability

The HTTPS client previously checked cancellation in its byte-stream callback
and after the request completed. A provider that sent headers and then stalled
could hold the network worker until bytes arrived or the 45-second request
timeout elapsed. The transfer-progress callback now checks cancellation during
idle transfers too. HTTPS-only providers, certificate/hostname verification,
redirect rejection, byte limits, the five-second connect timeout and the
45-second request timeout remain enforced.

`test/https.py` creates a temporary trusted certificate and a loopback TLS
provider. Test-process connection overrides send the real production client to
that fixture; production provider addresses and trust settings are unchanged.
Cases cover normal data, HTTP 503, redirects, oversized bodies and six-second
stalled bodies. Cancellation after 150 ms must return within three seconds in
this fixture. A real background patch job must cancel, release the network lane,
remove staging and preserve the cached snapshot. A subsequent HTTP outage must
fail without publishing a pointer, and later requests must still work.

These are local transport/storage-integrity regressions. They do not establish
a production capacity limit, a universal cancellation latency, a total patch
refresh deadline or reverse-proxy behavior. Concurrent storage quotas, repeated
asset failures and partial-provider outage duration remain follow-up work.

## Verification

The champion configuration regression covers both load directions, complete
participant reversal, physical item holes, fixed forms, automatic/manual ranks,
activation/strategy settings, shared fight settings, swap symmetry, malformed
documents, named preset inventories and pinned comparison handling.

The browser regression checks saving an unsimulated level change, persistence
after reload, cross-side loading, replacement/deletion, unchanged completed
traces, fixed forms, swapping twice, blocked storage writes, snapshot mismatch
and recovery after server rejection. Dialogs and the swap bar are checked at
736/390/320-pixel widths, with desktop/mobile screenshots retained under `build/`.
The screenshots were visually reviewed after matching the dialog's controls
and spacing to the existing HUD.

`make test` passed 83 core cases, retained source/catalog checks and 170 Python
cases (8 skipped). `make test-web` passed 44 frontend cases and the existing
combat/optimizer suites, including the new champion and TLS regressions.
`make test-runtime` passed the relocated executable and concurrent HTTP gate:
893 health probes, with a maximum observed local latency of 0.062 seconds.
The complete browser gate passed, covering both inventories, optimization and
Undo, error recovery, save/share/import, responsive layouts and retained combat
fixtures. Final-build champion browser and named-preset preservation checks
also passed. Janet formatting, Python syntax and Git diff checks passed.

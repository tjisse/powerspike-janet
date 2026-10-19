# Player beta rollout

The first audience is League players comparing items and fight outcomes. Preserve the Rift HUD and make the central task easy: choose a champion, configure the fight, compare item choices, and inspect what explains the difference.

Trustworthy results are a release requirement. Players should see a clear simulated outcome under their chosen conditions, without having to interpret verification progress, source hashes or engineering confidence labels. Calling something a simulation does not excuse incorrect calculations. A missing mechanic must be implemented or its absence must be explicit in the simulated fight; it must never silently contribute a fabricated value.

Verification, source provenance and model diagnostics belong in the developer view at `/developer`. It also accepts the comparison page's champion/patch query parameters or an exported `scenario` document. The full verification dashboard remains at `/verification`. These routes separate the UI audiences; they do not add authentication.

## Current improvement

In practice and objective simulations, players can pin an inventory and compare it with edited or optimized items. Paired matchups retain their current-versus-proposed item comparisons in the optimizer. Both inventories are evaluated by the same Janet engine with the current fight settings and trial seeds. The comparison reports damage, DPS and gold differences without claiming that a damage increase makes a build universally better. Only items are pinned; runes, skills and fight controls apply to both builds. References from another champion or snapshot cannot silently influence the result.

Simulation details are reachable beside the headline metrics. Current results and pinned results retain their separate omissions and inventory notes. Verification-only annotations stay in the developer view. Failed scenario evaluations disable save, export and share actions until a successful evaluation replaces them. The saved artifact remains a single reproducible scenario; comparisons live in the open page session.

## Remaining rollout priorities

1. **Establish combat evidence.** Admit reviewed basic attacks and isolated spell hits through the existing verification workflow. Start with mechanics that affect common item decisions: mitigation, penetration, crit, attack timing, cooldowns and supported item triggers. Track exact patch/model identities and unresolved hit context. The five Annie stat captures and replay decoder agreement do not establish combat accuracy.
2. **Close simulation gaps before rollout.** Implement missing interactions needed for the supported player decisions and check their behavior. Keep actual simulation scope understandable to players. Verification status and evidence sufficiency are developer responsibilities.
3. **Exercise representative player decisions.** Check a component purchase, a completed item swap, an equal-gold comparison and a champion duel. Include low-health starts, short windows, resource limits and no-damage outcomes. Check both survival and damage tradeoffs.
4. **Test the hosted environment.** Use the packaged runtime checks and Chromium suite, then exercise the actual reverse proxy with slow requests, failed downloads, simultaneous users, cancellation and bounded storage. Verify the cached-data experience when providers are unavailable.
5. **Run a small player beta.** Collect concrete scenario exports with reported mismatches and confusing interactions. Reproduce reports against the retained data before changing mechanics or defaults. Expand supported scope as evidence improves.

## Verification

`make test test-web` covers core calculations, retained sources, replay tooling, model/rendering regressions and the comparison cases. `python test/browser.py` runs against the packaged binary, or accepts `--url` for a running app. Its comparison flow checks pinning, item changes, recomputation against an independent result, replacement/removal, responsive layouts, coverage navigation, failed-evaluation recovery and retaining pinned items after applying optimization.

Screenshots from browser verification are written under ignored `build/`. Run `make test-runtime` to check the executable independently of the source tree before preparing a release.

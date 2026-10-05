# Optimizer performance fixes

This follows the [Clojure/Janet comparison](optimizer-comparison.md). It addresses measured search overhead while retaining the combat model, declared scenario and scoring procedure.

## Changes

- Cancellation uses a separate buffered thread channel per job. Search and combat loops check its in-memory count. Repeated cancellation is idempotent; queued jobs and concurrent users retain independent cancellation. The worker closes its channel on completion.
- A process-level LRU fitness cache holds up to 2,048 entries and 8 MB of encoded payload. The key covers the complete normalized scenario, exact patch/snapshot, engine/compiler identity and trial count. Completed metrics, uncertainty and coverage are frozen before storage. The cache is ephemeral and never writes into patch packages.
- Workers inherit cached results and return bounded updates to the coordinator for later jobs. The runner and task share an explicit dynamic cache state because Janet marshals their environments separately. Partially completed trials are never cached. Injected custom evaluators bypass the real-engine cache.
- Legality and scoring are computed again on every cache hit. Budget, exclusions, locks, next-purchase credit and scoring presets therefore cannot be bypassed by reusing combat metrics. One-trial screening and larger finalist schedules have separate cache entries.
- Search uses a metrics-only path through the same chronological engine. It avoids generating the graph trace and full compiled-actor identity for each candidate. Applying/inspecting a build still requests the full trace. Nontracing trials also skip constructing unused damage-event summaries.
- Item ordering hashes are precomputed once per ordering rather than recomputed in every sort comparison. Progress messages are limited to ten per second, with immediate first and final updates. Frontend result-cache lookups use complete state/package/model identities without recompiling actors first.
- The optimization panel reports reused results and new simulations. `evaluated` still includes cached assessments. A five-second search uses that budget to explore more builds; a repeated small exhaustive search can finish immediately from cached results.

The engine fingerprint now includes scenario compilation, skill rules, purchase rules and the curated default skill data alongside the existing combat dependencies. Saved scenarios from an older fingerprint continue to display the compatibility warning and use their retained data.

## Verification

The cache tests cover immutability, LRU eviction, byte limits, scenario/patch/snapshot/trial separation, changed purchase constraints and scoring, cancelled partial trials, cross-worker reuse, and independent cancellation. A three-candidate exhaustive search computes three results when cold and performs zero new simulations on repetition. Ordinary simulation and trace-free fitness agree on aggregate metrics, uncertainty and unsupported effects; seeded combat tests also compare damage breakdowns.

The real ten-item/four-slot Annie reference still agrees with exhaustive enumeration: Phantom Dancer, Statikk Shiv, Alternator and BORK produce 3,302.2 modeled damage at 9,950 gold. The exhaustive reference enumerates 249 legal inventories. This checks search/model consistency, not game accuracy.

In the final isolated local worker measurement using the retained 16.18.1 snapshot and default five-second search budget:

| Run | Evaluations | New simulations | Reused results | Wall time |
| --- | ---: | ---: | ---: | ---: |
| Previous worker baseline | 105 | 105 | 0 | 4.88 s |
| Updated worker, cold cache | 520 | 519 | 1 | 4.42 s |
| Updated worker, repeated search | 934 | 418 | 516 | 4.39 s |

The baseline's leader reported 2,867.3 modeled damage; the updated cold search found 3,498.8 and the repeat found 3,534.5. These are heuristic outcomes on one WSL host with source/data under `/mnt/c`, not guarantees for another host or patch. Counts vary with elapsed-time cutoffs. The remaining missing effects and dummy assumptions still limit recommendation accuracy.

The [retained measurements](benchmarks/optimizer-performance-2026-10-05.json) include exact snapshot/model identities and source hashes. The formatter/source-integrity checks, 16 Python checks, frontend/cache/engine/storage suites, 83 curated/core regressions including all five Annie captures, relocated executable checks and packaged browser checks pass. Browser verification includes repeating a completed search with zero new simulations, cancellation, applying a result, saved/share/JSON reproduction and responsive layouts. Worker tests also verify independent cancellation of concurrent requests.

## Repeat

With the exact snapshot already cached, run benchmarks sequentially from the repository root:

```sh
JANET_PATH=build/web-modules build/janet scripts/benchmarks/worker.janet
JANET_PATH=build/web-modules build/janet scripts/benchmarks/quality.janet
JANET_PATH=build/web-modules build/janet scripts/benchmarks/optimizer.janet
```

`worker.janet` clears the cache, runs two actual background searches, and reports reuse, timing and model identity. `quality.janet` compares against exhaustive real-item simulation. `optimizer.janet` isolates callback overhead with a fresh cache for each mode and reports ordinary/fitness evaluation cost. `PS_DATA_DIR`, `PS_SEED_DIR`, `PS_BENCH_PATCH` and `PS_BENCH_SNAPSHOT` select the retained data. None of these scripts treats the model's damage as a measured game result.

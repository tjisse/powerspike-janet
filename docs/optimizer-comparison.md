# Clojure and Janet optimizer comparison

Measured on 2026-10-05. The current recommendations have three separate problems: a costly cancellation check in the local worker, a different optimization problem from the old application, and incomplete combat effects that distort rankings. The search algorithm also needs broader quality benchmarks, but replacing it alone would leave those problems in place.

This records the baseline before the subsequent [optimizer performance fixes](optimizer-performance.md). The original measurements and source identities are retained for comparison.

The previous improvement figures compared Janet `search-2` with Janet `search-3`. They did not compare against Clojure. This investigation reads and executes the original Clojure implementation.

## Scope and identities

- Reference: [`tjisse/powerspike-core`, commit `bdea6197916167593c97927dec93fd840652f771`](https://github.com/tjisse/powerspike-core/tree/bdea6197916167593c97927dec93fd840652f771).
- Current: working tree based on `f50fc67`, search version `search-3`, engine identity `d0d934f2f3d3c1e194557d12b2d729ddc7815d2391fb93a559aac8ad21715839`.
- Current search source SHA-256: `03836e377a0ac239fd0737d0766507fff1139fcfcf145b0cf913d4c678ad5c43`.
- Shared retained data: patch `16.18.1`, snapshot `c97e185fd040c973d8f702f2dba2c558ad65c7092420e4324fd82fd2d8b2321c`.
- Runtimes: Janet 1.42.1; Clojure 1.11.1 on OpenJDK 17, Cheshire 5.11.0. A preliminary Clojure 1.12 run gave similar throughput; the reference figures below use its declared 1.11.1 version.
- Host: Linux/WSL, project and data under `/mnt/c`. Filesystem timings are specific to this environment. The deployed Linux service needs its own measurement.

Clojure received unchanged retained Data Dragon champion/item JSON and full CommunityDragon character records in its expected cache filenames. Its mechanics, parser and GA were executed unchanged. Network access was disabled in the harness; cached JSON used the actual Cheshire parser. A seeded random source and a generation-boundary time limit were supplied for repeatable throughput probes. This does not reconstruct the old application's historical combination of 14/15 Data Dragon data and unversioned `latest` spell caches.

The [machine-readable observations](benchmarks/optimizer-2026-10-05.json) retain settings, timings, damage breakdowns, reference outputs and a repeated performance run.

## What each application optimizes

| Aspect | Original Clojure UI | Current Janet UI |
| --- | --- | --- |
| Default goal | `total`, with separate `ability` and `ad` modes | `burst`: all modeled damage in the selected scenario |
| Default fight window | 10 seconds for total; 5 for ability/AD | 5 seconds |
| Inventory | Six completed items, exactly one pair of boots | Up to six items, including components and consumables |
| Budget | No gold limit | 10,000 gold by default |
| Pool | Completed items; mode-specific tag filters for ability/AD | Full source-legal shop; prioritizes implemented triggers and completed items |
| Scoring | Expected auto-attack DPS plus a separate ability rotation | Chronological combat simulation with casts displacing attacks |
| Target | Fixed 80 armor / 80 MR in fitness | Configured dummy, champion or objective; default dummy has 10,000 HP and 80/80 defenses |
| Search | Population GA, tournaments, elites, mutations, crossover, independent restarts | Singleton screening, greedy/stat-family seeds, mutations/crossover of several leaders; exhaustive small pools |
| Search limit | Fixed generations/runs | Five-second default compute budget; 30-second option |
| Randomness | Analytical expected crit damage | Usually one seeded screening trial, then 16 trials for finalists |
| Reuse | Fitness cache survives generations, runs and requests | Deduplicates within a search; no persistent candidate-fitness cache across searches |
| Restrictions | Duplicate names and boots, map/purchasable filters | Gold, slots, locks, exclusions, champion/group/shop/unlock restrictions and recipe credit |

The original UI's total mode requests 300 generations, population 150 and ten runs: roughly 450,000 population positions, with many repeated cached scores. This is not 450,000 distinct combat evaluations. Its cache key omits patch/content identities, so that cache cannot safely be copied unchanged.

The two current presets `burst` and `sustained` rank builds identically when the scenario window is fixed: dividing every damage score by the same duration does not change the ranking. An ability-focused strategy can already disable attacks, but the optimizer has no corresponding prominent ability/attack goal selector.

## Measured performance

For the controlled Janet search: Annie level 18, full health/resource, empty starting inventory, five-second fight, 10,000-HP dummy, 80 armor/MR, distance 300, seed 1, six slots, 10,000 gold. Runes and summoners remain empty. The direct search uses a no-op progress sink to isolate computation.

| Cancellation callback, same five-second budget | Evaluations completed | Best finalist modeled damage |
| --- | ---: | ---: |
| In-memory callback | 468 | 3,498.8 |
| File check under the project's mounted data directory | 121 | 2,867.3 |
| File check under `/tmp` | 464 | 3,498.8 |

The mounted-file run made 3,784 cancellation checks. Separately, 10,000 missing-file `os/stat` calls took 8.830 seconds under the project directory and 0.00563 seconds under `/tmp`. The real worker supplies this file check to both the search loops and combat engine. The same search therefore explores about four times fewer candidates locally, which also harms recommendation quality. The compute budget means it need not run four times longer.

The actual background job, without browser rendering or icon downloads, completed 105 evaluations and found the same 2,867.3-damage leader. With the selected patch already loaded, submission took 0.075 seconds, first observed progress arrived after 0.228 seconds, and completion took 4.878 seconds. With the patch initially unloaded, a separate run took about 6.0 seconds including 1.2 seconds of submission/setup. UI polling can add up to approximately another second before the user sees completion.

Separate warm fixed-build timing, Annie with Deathcap/Void Staff/Luden's Echo:

| Work | Measured average |
| --- | ---: |
| Original uncached fitness, original local JSON loader | 4.76 ms |
| Original fitness with the character record already in memory | 0.312 ms |
| Current scenario compilation | 0.136 ms |
| Current one-trial engine evaluation | 4.67 ms |
| Current scenario identity generation, isolated run | 1.57 ms |
| Current full one-trial simulation | 7.27 ms |

These are separate short timing loops, not additive profiler samples. They show that current work includes appreciable identity/serialization overhead as well as the event engine; compilation itself is relatively cheap. The engine handles more state and effects than the old arithmetic. These measurements do not establish a general Clojure-versus-Janet language speed comparison.

Five-second Clojure GA probes, with a fresh fitness cache for each mode, completed 1,136–1,174 distinct uncached fitness calculations and approximately 17,000–21,000 total fitness calls. Each probe stopped at a generation boundary after about 5.0–5.1 seconds, still in its first restart. Their highest cached builds cost 13,000–13,600 gold, exceeding the current default budget; some used unlock-dependent boots. Those scores cannot be treated as legal recommendations for the current scenario.

## Why the recommendations diverge

### The dummy and effect coverage strongly favor on-hit damage

The current item trigger handlers cover Hextech Alternator, Blade of the Ruined King and Sheen for the supported recent patch families. Some special item stats, such as Deathcap's AP amplification and Infinity Edge's crit modifier, are also modeled. Most other item passive/active effects remain excluded, even when their descriptions and formulas are available. Rune and exceptional champion coverage is similarly incomplete.

For the tested Annie inventory—Doran's Bow, Refillable Potion, Phantom Dancer, Hextech Alternator, Blade of the Ruined King and Serpent's Fang—the current engine reports 3,498.8 damage. BORK supplies 1,748.8 of that damage. Removing just its on-hit trigger in a diagnostic evaluation reduces the same inventory to 1,750.0 damage. With a 2,000-HP target, that trigger contributes only 155.1 damage. These are model sensitivity measurements, not in-game validation of BORK or dummy-specific damage rules.

With attacks disabled, the full-shop search instead recommended Needlessly Large Rod, Sorcerer's Shoes, Deathcap, Void Staff and Hextech Alternator, costing 9,900 gold. It reported 2,046.5 ability-focused damage. This demonstrates the influence of the declared strategy and scenario; it does not verify that build against the game.

Unknown effects are disclosed, but disclosure does not correct their influence on rankings: their contribution is excluded while supported competing effects receive a score. Higher search throughput can optimize that incomplete model more effectively without improving game accuracy.

### The old formulas are not an accuracy reference

Running the old parser on the retained records confirmed concrete problems:

- It assigns Annie's R and Garen's R to E, and Ashe's Enchanted Crystal Arrow to W, by looking for letters in spell names rather than using ability references.
- Its `DataValues` extraction expects `mName`/`mValues`; these records contain `name`/`values`. Named base values consequently disappear from calculations.
- It broadly sums selected spell calculations, including calculations that can describe alternatives or unrelated effects.
- It infers damage channel from names and stats, and adds uninterrupted auto DPS to its ability rotation.
- It hardcodes Deathcap/Infinity Edge constants, uses a separate approximate skill-rank allocation, and omits several purchase/group restrictions.

For the identical Deathcap/Void Staff/Luden inventory and five-second window, the old total scorer reports 794.9 DPS for Annie and 86.3 DPS for Ahri; the current 16-trial engine reports 390.2 and 357.2 DPS respectively. The direction of disagreement changes between champions. Neither model's larger number establishes accuracy; the traces, source semantics and isolated game measurements must explain the difference. The existing Annie stat fixtures do not validate all these combat effects.

### Search quality has a useful reference point

A real-item ten-item pool was tested with Annie, four slots, 10,000 gold, the same scenario and 16-trial finalist schedule. The pool included Deathcap, Void Staff, Luden's Echo, Sorcerer's Shoes, BORK, Phantom Dancer, Infinity Edge, Alternator, Serpent's Fang and Statikk Shiv.

The heuristic evaluated 171 candidates and found Phantom Dancer/Statikk Shiv/Alternator/BORK: 3,302.2 modeled damage at 9,950 gold. Enumerating every legal inventory evaluated 249 candidates in 16.95 seconds and found the same winner and score. This is evidence for one controlled search, not a full-shop guarantee or a game accuracy check. Large-pool quality and sensitivity to screening randomness still need a benchmark suite.

## Recommended order of work

1. **Remove filesystem checks from the hot loops.** Use a worker cancellation channel or a throttled check with a specified responsiveness bound. Verify cancellation/isolation and compare worker throughput on WSL and deployed Linux. Preserve the data directory and its cache semantics.
2. **Make the intended build problem explicit.** Provide ability-focused, attack-focused and mixed-combat presets, plus completed-build versus budget-purchase searches. Use realistic champion/objective presets while keeping dummy calibration scenarios accessible. Display the target, window, budget and strategy next to every recommendation.
3. **Implement effects that materially change item rankings.** Complete common damage procs, spellblade upgrades, penetration/crit behavior, sustain and relevant champion interactions by mechanic family. Retain unresolved coverage and add targeted calibration. Avoid grading unknown effects as verified zero.
4. **Make repeated evaluation cheaper.** Cache invariant scenario work and bounded candidate metrics using complete data/model/scenario/trial identities. Avoid repeatedly generating traces and full actor identities for candidates whose only required output is fitness. Keep finalists and frontend inspection on the shared engine.
5. **Benchmark exploration before selecting the next search algorithm.** Compare the current heuristic and the old population/restart strategy through the same scorer and legal constraints. Track quality versus elapsed time on AP, AD/crit, on-hit, defense and objective cases; retain exhaustive small-pool references. Control screening noise and rescore a broader finalist set. A GA is a useful candidate, not an accuracy guarantee.

## Repeating the checks

The retained snapshot must already exist in the runtime cache. From the repository root:

```sh
JANET_PATH=build/web-modules build/janet scripts/benchmarks/optimizer.janet
JANET_PATH=build/web-modules build/janet scripts/benchmarks/quality.janet
```

The scripts emit JSON lines. `PS_DATA_DIR` and `PS_SEED_DIR` override cache/seed directories; `PS_BENCH_PATCH` and `PS_BENCH_SNAPSHOT` select an exact retained package. Run benchmarks sequentially without other searches to reduce contention. The performance script uses absent test cancellation paths and does not cancel real jobs.

`scripts/benchmarks/clojure.clj` retains the original execution probe. Put the pinned reference's `powerspike-core/src` and its declared dependencies on the classpath. Set `PS_BENCH_CLOJURE_CACHE` to a cache containing the retained `16.18.1-champion.json`, `16.18.1-item.json` and `bin-Annie.json`, `bin-Ahri.json`, `bin-Ashe.json`, `bin-Garen.json`. Those come directly from this snapshot's `sources/champions.json`, `sources/items.json` and `sources/characters/*.json`. This probe deliberately uses patch 16.18.1 and a common five-second scoring window; it does not run the old UI's complete default search.

Raw investigation output and the pinned reference checkout are under the ignored `build/` directory. Production optimizer behavior has not been changed by this comparison.

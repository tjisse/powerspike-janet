# Audit of the Clojure reference

The source repository is `tjisse/powerspike-core`. The inspected commit is recorded in the snapshot manifest. Its README and game-mechanics reference describe intended behavior; these are not treated as a verified specification.

The [optimizer comparison](optimizer-comparison.md) executes the original implementation against a retained recent snapshot and measures the current search, worker overhead and recommendation differences.

| Location in original | Finding | Effect on the rebuild |
| --- | --- | --- |
| `core.clj / ensure-data` | Prefers version strings starting with 14 or 15, even when newer data exists | Use a declared snapshot |
| `mechanics/parsing.clj / cdragon-base-url` | Fetches `latest`; cache filenames have no patch | Do not mix old Riot data and newer spells |
| `mechanics.clj / get-item-stats` | Crit fallback carries a fractional Riot value while downstream divides by 100 | Normalize units once |
| `mechanics.clj / calculate-champion-as` | Treats base AS as the AS ratio | Retain distinct source fields |
| `mechanics.clj / get-total-stats` | Uses stale Deathcap and Infinity Edge constants | Curate patch-specific item semantics |
| `mechanics.clj / apply-resistances` | Clamps all effective resistance to zero | Preserve negative resistance caused by reductions |
| `mechanics.clj / get-spell-rank` | Can allocate Q rank 2 at level 2 and rank 5 at level 5 | Validate a legal skill order |
| `mechanics.clj / get-spell-damage` | Sums broadly selected formula entries; components can be alternatives, ratios or duplicates | Champion adapters select actual effects |
| `mechanics/parsing.clj / get-damage-type` | Infers damage type from names and AD/AP | Damage channel belongs to the effect, not its scaling stat |
| `mechanics/parsing.clj / resolve-part` | Unknown structures fall back to empty damage | Unsupported structures must be explicit failures |
| `mechanics.clj / calculate-ability-burst-dps` | Later casts can overlap other actions; generic recast heuristics replace champion semantics | Evaluate a shared explicit action schedule |
| `optimization.clj / calculate-effective-dps` | Adds uninterrupted attack DPS to ability burst DPS | Score attacks displaced by casting |
| `optimization.clj / fix-build` | Always forces boots; lacks several unique groups | Explicit candidate-pool restrictions |
| `optimization.clj / fitness-cache` | Global cache key omits patch/content identity | No global fitness cache in the baseline |
| README / optimization comments | Genetic restarts are described as guaranteeing a global optimum | Heuristic search cannot make that guarantee |

Several doc constants also disagree with the code or retained game data, including critical damage and item passive values. The reference's growth table uses level instead of level minus one, while its code correctly subtracts one.

The most serious problem is semantic: extracting more game formulas does not establish which effects occur, when they occur, their damage channel, or whether they describe alternative outcomes. The rebuild puts those choices in small champion/item adapters and retains a transparent event trace.

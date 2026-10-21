# Next improvements after v0.21.0

The order below prioritizes trustworthy build and fight comparisons, then the
remaining work needed for a small player beta. Players continue to see a clear
simulation and its actual omissions. Verification records and engineering
diagnostics remain in the developer tools.

The [16.20/16.21 ability correction](latest-patch-abilities.md) resolves the
reported default-matchup regression: newly discovered patches had been offered
even though their stat formulas were outside the parser's reviewed scope.
Future patch work should check actual learned ability execution against retained
matching sources, including manual refreshes, before treating downloads as ready
for build comparisons. AP, AD and health are now reviewed on those two patches;
other mappings and complete champion kits still need their own review.

1. **Attack timing and projectile behavior.** Measure isolated ordinary and
   empowered attacks, review the remaining 30% windup assumption, and resolve
   ranged Spellblade consumption at launch versus impact. Use matching-patch sources
   and reviewed replay context; retain discrepancies instead of fitting timing
   to the desired result. The [baseline attack-speed cap correction](attack-speed-cap.md)
   now replaces the old 2.5 assumption with Riot's published 3.0 baseline on
   16.19.1, across cached data, temporary buffs, both actors and optimization.
   Windup values and special cap rules still need their own review.
   Finish with reproducible release/impact cases before
   expanding the projectile profiles. The first [source-level corrections](attack-timing.md)
   now supply Ahri's reviewed windup and resolve Annie's projectile fields;
   the [Viktor follow-up](viktor-attacks.md) adds ordinary projectile travel while
   preserving empowered Q's explicit zero-travel assumption. The
   [Human-form projectile follow-up](form-projectiles.md) adds ordinary and
   critical travel for selected Nidalee and Elise forms; the same review now
   supplies Jayce's ordinary Cannon projectile while excluding Hammer,
   transformation and Hyper Charge records. Windup assumptions remain. Gnar's
   Mini projectiles still need variant review: the named third attack is absent
   under both its path and entry hash in the retained source. The
   [attack-cadence correction](attack-cadence.md) now checks exact ordinary
   readiness and removes cumulative polling drift. The
   [ability readiness correction](ability-readiness.md) extends this to cooldowns,
   recast/charge timing and fixed activation times, and prevents main cooldowns
   from bypassing recast delays. The [control resumption correction](control-resumption.md)
   now wakes ready actions at control expiry or applied cleanse, including short
   effects between polls. The [attack reset correction](attack-resets.md) also
   wakes enabled attacks when an applied reset shortens their future deadline,
   while preserving current action locks and in-flight projectiles.
   The [resource readiness correction](resource-readiness.md) forecasts when
   continuous regeneration makes a fixed-cost ability affordable, including
   changes to regeneration and health-cost healing. The
   [health activation correction](health-activation.md) wakes ready abilities
   when damage, health costs or maximum-health changes satisfy their configured
   low-health rules, and rechecks healing/control/death before casting.
   The [movement readiness correction](movement-readiness.md) now forecasts
   relative movement into ordinary and fixed ability range, stops at the chosen
   distance, and updates trajectories at speed/control/lock changes.
   The [changing readiness correction](changing-readiness.md) extends forecasts
   to costs and ranges using stats or buffs, recalculates when their values
   change, and evaluates recast costs consistently. The
   [health-cost readiness correction](health-cost-readiness.md) now solves
   supported affine costs paid from current health, including their existing
   reserve, and checks the retained Mundo/Zac formulas. Health-dependent ranges,
   costs paid from another pool, nonlinear/nonmonotone formulas and nonpositive
   regeneration retain polling. The [retained range audit](item-survival-comparisons.md)
   found 44 fixed spell ranges and no health-dependent ranges in the retained
   kits; further range forecasting waits for a supported source case. The
   [replay timing study](replay-attack-timing.md) now corroborates impact-time
   consumption for ordinary ranged hits and records a possible parry interaction.
   The [Riposte defense handler](fiora-parry.md) now models the champion-only
   parry window and shared Spellblade consumption. Its return stab, shield
   ordering, exceptional interactions, exact release timing and complete
   expiry/refresh context remain next. A two-replay shield screen found no
   positive overlap with observed Riposte windows; it leaves ordering unresolved.
2. **Level and form transitions.** Kayle's [fixed-level attack type and range](kayle-levels.md)
   now drive both participants and supported item scaling on 16.19.1, with her
   remaining passive effects explicit. Nidalee now has [fixed Human/Cougar forms](nidalee-forms.md)
   for ordinary attacks and supported item scaling. Jayce now has [fixed Hammer/Cannon forms](jayce-forms.md),
   including Hammer's level/bonus-AD resistance scaling. Elise now has
   [fixed Human/Spider forms](elise-forms.md), including movement speed and
   Spider Queen's champion/practice on-hit damage and healing. Gnar now has
   [fixed Mini/Mega forms](gnar-forms.md), including level-scaled range, movement,
   attack speed and base stats. All five ambiguous ordinary attack identities
   now have fixed-level/form handling. Automatic transitions and the remaining
   passive/ability effects still need reviewed handlers. Extend them only when
   the selected state drives damage, range, tooltips and both optimizer
   perspectives consistently; remove an omission only after its replacement
   is implemented and checked. The [general interpolation audit](level-scaling.md)
   now corrects named and hashed stat-progression flags, including retained
   cached formulas. Gnar's fixed-form stats were already correct. The remaining
   passive triggers and automatic transitions still require their own evidence.
3. **Broader combat regression evidence.** Expand reviewed comparisons across
   independent games and common build decisions: armor/penetration, critical
   hits, current-health on-hits, shields and changing health. Keep exact patch
   and model identities, pre-hit inputs, mismatches and exclusions. Decoder
   agreement and aggregate totals remain separate from model accuracy.
4. **Comparison usability and visual polish.** Exercise component purchases,
   completed-item swaps, equal-gold alternatives and survival tradeoffs. Make
   the reason for a difference easy to inspect and keep controls, explanations
   and comparisons readable on mobile. Preserve reproducible scenario exports
   and the existing Rift HUD. The duel timeline now exposes parry activation,
   blocked effects and Spellblade consumption, with all crowded events available
   through the selector.
   [Item survival comparisons](item-survival-comparisons.md) now expose health
   remaining, defeat time and survived-trial counts beside damage and gold,
   including equal-gold offense/survival tradeoffs, mobile summaries and the
   comparison panel in duel results. Saved comparisons now preserve both
   inventories and their shared fight settings through local saves, exports,
   share links and imports. [Damage-source comparisons](damage-source-comparisons.md)
   now show which abilities, attacks, item effects or rune effects drive the
   difference, using averages across every trial. [Trial variation](trial-variation.md)
   now shows observed damage changes within matching trials, including when
   the advantage changes sides, with a direct trial-count control.
   [Timeline artwork](timeline-and-concurrency.md) now restores snapshot-scoped
   ability, item and rune icons and attacker portraits, with keyboard selection,
   readable missing-artwork fallbacks and the full crowded-event selector.
   [Champion configurations](champion-configurations.md) now add four reusable
   browser save slots and an atomic side swap, preserving forms, ranks, item
   positions and strategies while keeping the completed fight until a rerun.
5. **Hosted reliability.** Exercise simultaneous simulations, cancellation,
   slow or unavailable providers, offline cached data and bounded cache/storage
   use. Check the packaged service through the actual reverse proxy before
   treating deployment behavior as covered. The [local concurrency audit](timeline-and-concurrency.md)
   now checks simultaneous simulations and SSE reruns, cancellation isolation,
   queue capacity and responsive health checks. It fixes cancelled queue slots,
   retries attaching to cancelling jobs, and long-result rendering on the HTTP
   event loop. The [TLS provider follow-up](champion-configurations.md#provider-reliability)
   now exercises real HTTP outages and stalled bodies through a local TLS
   fixture. Idle downloads observe cancellation even when no bytes arrive;
   cancelled/failed refreshes release their worker and staging without
   replacing cached data. The [storage/artwork follow-up](storage-and-artwork.md)
   now serializes managed writes against the current file-byte total, accounts
   for normalized packages/manifests/atomic replacements, and preserves cached
   reads at the allowance. Artwork failures share a bounded 30-second retry
   window with HTTP retry guidance. [Refresh deadlines](patch-refresh-deadlines.md)
   now bound cumulative provider waits with one active-job budget, preserve
   cached snapshots on expiry, and check successful retry after recovery.
   The [hosted smoke check](hosted-smoke.md) now exercises the deployed proxy,
   two-client isolation, finite SSE updates, bounded search cancellation and
   desktop/touch configuration flows. It found repeatable 9–11-second page
   responses with about 3.4 MB of initial HTML, despite fast health/CSS requests.
   The [lazy catalog follow-up](catalog-loading.md) now removes eager closed
   dialog rendering, reducing the retained page from 3.37 MB to 0.63 MB and
   local page generation from about 2.9 seconds to 0.9 seconds. It preserves
   exact-snapshot selection, server tooltip values and native forms. A
   [v0.21.0 deployment follow-up](hosted-smoke.md#v0210-deployment-follow-up-21-october-2026)
   now confirms live catalog reuse, local report downloads and smaller initial
   pages. Three warm samples per case observed median first-byte times of
   3.072 seconds for practice and 4.459 seconds for a duel; initial loading
   remains a performance improvement opportunity.
   Controlled slow/provider-outage proxy checks, longer-running memory/disk
   usage remain beta checks.
6. **Player beta readiness.** The [comparison walkthrough and problem reports](problem-reports.md)
   now provide local report downloads with the completed scenario, pinned items,
   player notes and recorded outcomes. The existing importer reproduces both
   builds without treating those recorded outcomes as inputs. Collect concrete
   player reports to prioritize mismatches and confusing interactions, then
   reproduce them against the retained data before changing mechanics.

Evidence needed for each item may change its implementation details. Accuracy
fixes discovered during this work take priority over adding more supported
champions or cosmetic features.

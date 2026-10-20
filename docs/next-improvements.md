# Next improvements after v0.19.0

The order below prioritizes trustworthy build and fight comparisons, then the
remaining work needed for a small player beta. Players continue to see a clear
simulation and its actual omissions. Verification records and engineering
diagnostics remain in the developer tools.

1. **Attack timing and projectile behavior.** Measure isolated ordinary and
   empowered attacks, review the remaining 30% windup assumption, and resolve
   ranged Spellblade consumption at launch versus impact. Use matching-patch sources
   and reviewed replay context; retain discrepancies instead of fitting timing
   to the desired result. Finish with reproducible release/impact cases before
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
   from bypassing recast delays. Dynamic thresholds, movement and control expiry
   retain their existing polling policy. The
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
5. **Hosted reliability.** Exercise simultaneous simulations, cancellation,
   slow or unavailable providers, offline cached data and bounded cache/storage
   use. Check the packaged service through the actual reverse proxy before
   treating deployment behavior as covered.
6. **Player beta readiness.** Prepare a short comparison walkthrough and a
   repeatable issue-report flow that includes a scenario export. Use concrete
   player reports to prioritize mismatches and confusing interactions, then
   reproduce them against the retained data before changing mechanics.

Evidence needed for each item may change its implementation details. Accuracy
fixes discovered during this work take priority over adding more supported
champions or cosmetic features.

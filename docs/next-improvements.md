# Next improvements after v0.18.0

The order below prioritizes trustworthy build and fight comparisons, then the
remaining work needed for a small player beta. Players continue to see a clear
simulation and its actual omissions. Verification records and engineering
diagnostics remain in the developer tools.

1. **Attack timing and projectile behavior.** Start with isolated ordinary
   attacks and the remaining 30% windup assumption. Resolve Annie's conflicting
   projectile fields, Viktor's ordinary versus empowered attacks, and ranged
   Spellblade consumption at launch versus impact. Use matching-patch sources
   and reviewed replay context; retain discrepancies instead of fitting timing
   to the desired result. Finish with reproducible release/impact cases before
   expanding the projectile profiles. The first [source-level corrections](attack-timing.md)
   now supply Ahri's reviewed windup and resolve Annie's projectile fields;
   matching replay measurements and the remaining timing policies are still next.
2. **Level and form transitions.** Start with Kayle's level-dependent attack
   type and range, then add explicit supported forms for Elise, Gnar, Jayce and
   Nidalee. The selected form/level must drive damage, range, tooltips and both
   optimizer perspectives consistently. Remove an omission only when its
   replacement is implemented and checked.
3. **Broader combat regression evidence.** Expand reviewed comparisons across
   independent games and common build decisions: armor/penetration, critical
   hits, current-health on-hits, shields and changing health. Keep exact patch
   and model identities, pre-hit inputs, mismatches and exclusions. Decoder
   agreement and aggregate totals remain separate from model accuracy.
4. **Comparison usability and visual polish.** Exercise component purchases,
   completed-item swaps, equal-gold alternatives and survival tradeoffs. Make
   the reason for a difference easy to inspect and keep controls, explanations
   and comparisons readable on mobile. Preserve reproducible scenario exports
   and the existing Rift HUD.
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

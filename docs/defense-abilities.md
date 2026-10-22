# Shield timing and Ground Slam — 23 October 2026

This fourth completeness batch covers **Riven E, Jarvan IV W and Malphite E on
16.21.1**. Complete matching raw character/description pairs and localized
excerpts are retained in `data/ability-fixtures/16.21.1/defenses/`. The manifest
checks their original response hashes against the all-champion audit receipts.

Riven E's generic shield had no duration because its tooltip uses literal text
rather than a duration variable. The reviewed rule uses `ShieldDuration` and
`TotalShield` directly and grants the shield at cast start. The dash and animation
cancels remain excluded. With rank 1, 150 total AD and 100 base AD, the shield is
`70 + 1.1 * (150 - 100) = 125` for 1.5 seconds. At rank 5 it is 225. Damage
before expiry is absorbed; damage exactly at expiry is not.

Jarvan W now uses `Effect4Amount` for its four-second shield and `Effect5Amount`
for its two-second slow. These are distinct source fields. The spell always
grants its base shield; the sole nearby champion adds `BonusShield` and receives
the source's slow. At 1,000 maximum health and 50 bonus AD, rank 1 gives
`60 + .7 * 50 + .013 * 1000 = 108` shield with the opponent within the selected
patch's 625-unit range, or 95 without one. The 15% slow reduces 100 movement
speed to 85. Shield duration starts on the model's source-derived cast release.
The self-cast is not blocked by the opponent being out of range or by the
configured skillshot hit chance. Additional enemies remain outside the duel.

Malphite E's `EDamageCalc` uses total armor (stat 1/formula 0). The reviewed
scope is attached only while compiling this rule; generic stat mappings on
unreviewed abilities and future patches remain unresolved. Tooltip values use
the same reviewed scope. Rank 1 with 100 armor and 100 AP gives
`60 + .4 * 100 + .6 * 100 = 160` magic damage and 30% attack-speed reduction
for three seconds. Rank 5 gives 300 damage and 50% reduction. Granite Shield
and Thunderclap's passive armor are still excluded; the cast uses the modeled
armor total rather than pretending those passives are included.

The existing semantic-rule compiler gains optional strength scaling,
nearby-champion shield bonuses and explicit self-casts. Snapshot source records,
bytes and current pointers remain unchanged. Parser version remains 7. The
model identity changes; there is no automatic refresh, migration or repair.

`test/defense-abilities.janet` checks the independent equations, exact simulated
shield expiry, nearby range boundaries, out-of-range self-casts, reduced hit
chance, both matchup positions, immutable package bytes and optimizer equality.
It verifies the armor mapping does not leak into generic parsing. Exported
scenarios run through the relocated executable and shared desktop/mobile
ability browser check, including shields that do not deal damage.

This is source-backed simulation coverage, not complete-kit or live-game timing
verification. Mobility, remaining champion passives and other source omissions
remain visible in simulation details.

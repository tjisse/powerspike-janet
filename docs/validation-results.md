# Measured validation results

## Annie, level 1, no items — 2026-10-04

The user collected this snapshot in Practice Tool after following the no-purchase, no-combat instructions. Game Version: 26.19. League Client Version: 16.19.823.0722. Matching model data: 16.19.1. Capture game time: 121.1977005 seconds. These version identifiers remain operator-declared.

The raw response SHA-256 is `fde130a178c86cd951f858e4fba2a0b4266ce0493ed3bb15d6227ddd6566c564`. The original raw and normalized files remain unchanged under `observations/local/annie-01/`. A separate `reviewed.jdn` records the review; the shareable, identity-free measured fixture is [annie-level1-no-items.jdn](../observations/16.19.1/annie-level1-no-items.jdn).

Observed context: map 11, `PRACTICETOOL`, alive, zero ranks in all abilities, only the separate ward trinket, position `NONE`. User completion of the setup supplies the no-combat/no-temporary-buff context; the API is not a complete buff or quest-state log.

Selected stat shards: 5005 (10% attack speed), 5010 (2.5% movement speed), 5011 (65 health). Selected runes: Deathfire Touch, Manaflow Band, Celerity, Scorch, Cut Down and Legend: Haste. No Manaflow or Legend stacks are inferred from ID selection alone; the reviewed setup has not earned any. Basic-ability haste from Legend is a separate future mechanic from general haste.

The numeric shard values come from retained, hashed [matching CommunityDragon perk data](https://raw.communitydragon.org/16.19/plugins/rcp-be-lol-game-data/global/default/v1/perks.json). They were not fitted to the observation.

| Checked stat | Prediction | Observation |
| --- | --- | --- |
| AD | 50 | 50 |
| AP | 0 | 0 |
| Health | 560 + 65 = 625 | 625 |
| Armor | 23 | 23 |
| Magic resistance | 30 | 30 |
| Attack speed | 0.61 + 0.625 × 0.10 = 0.6725 | 0.6725000143 |
| General ability haste | 0 | 0 |
| Mana maximum | 418 | 418 |
| Flat magic penetration | 0 | 0 |
| Critical damage multiplier | 2.0 | API reports 200; explicitly normalized from percent |

Result: **consistent for 10 checked stats**, using the record's explicit tolerances. The comparison now accepts the actual `PRACTICETOOL` mode on map 11; its previous `CLASSIC`-only restriction was a tooling error uncovered by this capture.

Movement speed is **excluded** because Celerity's amplification rules are not implemented. The observation is 346.7249756. Adding its described 1% base bonus to the 2.5% shard gives 335 × 1.035 = 346.725 for this snapshot, but this does not validate the rune's 7% amplification across other movement bonuses. We retain that distinction rather than adding a fitted correction.

Crit chance was zero in this baseline, so this capture alone did not resolve its fraction-versus-percent representation. The Cloak capture below resolves it. Both percentage penetration fields report 1.0 with no penetration source, suggesting resistance remaining rather than penetration gained. A nonzero-penetration capture is required before applying that mapping generally. These three fields were not counted as checked coverage in this initial review.

This snapshot validates a limited static scenario. It does not validate level growth, item interactions, casts, damage mitigation, critical-hit outcomes, combat rune procs or any timing assumption.

## Annie, level 1, one Cloak of Agility — 2026-10-04

The second capture has the same patch/client identifiers, level, unspent ranks, rune page and shards as the baseline. Its game time is 89.2266693 seconds, so these are separate controlled snapshots rather than an assumed uninterrupted game timeline. Inventory contains one Cloak of Agility (1018), plus the separate ward trinket.

Raw response SHA-256: `96535cf4a5d0a2defef58ceb96b6332fcb875781c87bf844160e3c161c850da3`. Originals remain unchanged under `observations/local/annie-02/`; the separate review and [measured fixture](../observations/16.19.1/annie-level1-cloak.jdn) retain their provenance.

The retained item data predicts **15% crit chance**. The API reports `critChance = 0.15000000596046448`, establishing **fraction units** for this field. It continues to report `critDamage = 200`, whose unit is **percent**. The two fields therefore need different conversions. All other raw champion stats match the no-item baseline.

Result: **consistent for 11 checked stats**, with zero mismatches. Movement speed remains excluded for the same Celerity limitation. This checks a static item effect and unit interpretation; it does not test the distribution of critical attacks or stacking multiple crit items.

The local unit mappings at this stage include `critChance: fraction` and `critDamage: percent`. The Void Staff capture below resolves magic penetration's representation.

## Annie, level 1, one Void Staff — 2026-10-04

The third capture retains the same level, unspent ranks, runes and shards. Actual inventory is **Void Staff alone**, plus the separate ward trinket. The Cloak is absent; the review uses the actual recorded inventory. Kills, assists and creep score are zero. Game time: 507.5943909 seconds.

Raw response SHA-256: `2bbd62f119ecfd41401b55ea6a9d9e99b3d9064ff6ee68697a65bf271c4adec7`. Originals remain unchanged under `observations/local/annie-03/`; the separate review and [measured fixture](../observations/16.19.1/annie-level1-void-staff.jdn) retain their provenance.

| Item effect | Prediction | API observation | Normalized observation |
| --- | --- | --- | --- |
| AP | 95 | 95 | 95 |
| Magic penetration | 0.40 | `magicPenetrationPercent = 0.6000000238418579` | `1 - raw = 0.3999999761581421` |

With no penetration source, the earlier captures report 1.0 in this field. Void Staff establishes that the field reports **resistance remaining** for these cases, rather than penetration gained. The collector's explicit mapping is `magicPenetrationPercent: remaining-fraction`. Armor percentage penetration remains unverified.

Result: **consistent for 12 checked stats**, zero mismatches. Crit chance returns to zero following removal of the Cloak. Movement speed remains excluded, and no damage-mitigation or combat timing measurement has been made.

The inventory API also reports Void Staff's `price` as 1050, matching its retained recipe base cost, while its total cost is 3000. The optimizer continues to use retained total cost; this observation does not establish the meaning of `price` for every inventory item.

## Annie, level 6, Void Staff, R unlearned and learned — 2026-10-04

The user completed the prescribed pair: raise Annie to level 6 with all skill points unspent, capture, then learn one point in R without casting and capture again. Recorded inventories contain only Void Staff plus the separate ward trinket. Rune IDs and shards match earlier captures. Both show map 11, `PRACTICETOOL`, alive, position `NONE`, and zero kills, deaths, assists and creep score. The no-combat/no-temporary-buff context remains operator-supplied; the API does not provide a complete buff or cast log.

Original raw and normalized files remain unchanged under `observations/local/annie-04/` and `annie-05/`. Separate reviews and identity-free fixtures retain provenance:

| Capture | Game time | Raw response SHA-256 | Measured fixture |
| --- | --- | --- | --- |
| All abilities unlearned | 1012.9445190 s | `f4cdaf09c9aa8a2511d6330f298cddfcb38f38832fa304dbf87c58934d93acdf` | [annie-level6-void-staff.jdn](../observations/16.19.1/annie-level6-void-staff.jdn) |
| R rank one, Q/W/E unlearned | 1029.9543457 s | `f3181f2e9fd48cb895e65fa4d93d6d9c80005bbf222614eb1d95793604818abb` | [annie-level6-void-staff-r1.jdn](../observations/16.19.1/annie-level6-void-staff-r1.jdn) |

The source-derived growth factor is `(6 - 1) × (0.7025 + 0.0175 × (6 - 1)) = 3.95`. Predictions were documented before collection, and no parameters were fitted to these measurements.

| Checked growth stat | Prediction | Observation in both captures |
| --- | --- | --- |
| Health, including +65 shard | 1004.2 | 1004.2000122 |
| AD | 60.4675 | 60.4674988 |
| Armor | 38.8 | 38.8000031 |
| Magic resistance | 35.135 | 35.1350021 |
| Mana maximum | 516.75 | 516.75 |
| Attack speed, including +10% shard | 0.706075 | 0.7060750127 |

Before learning R, the API reports magic resistance remaining as `0.6000000238418579`, agreeing with Void Staff's 40% penetration. After learning R, it reports `0.5400000214576721`, agreeing with **46% total penetration**: `1 - (1 - 0.40) × (1 - 0.10) = 0.46`. Among all raw champion-stat fields, only this field changes between the two captures. This checks the rank-one passive without a cast and its multiplicative combination with Void Staff.

Each capture is **consistent for 12 checked stats**, with zero mismatches and zero missing checked stats. Movement speed remains explicitly excluded for Celerity; armor percentage penetration remains unmapped. The rank-two/rank-three passive, other levels, actual target damage and combat timing have not been measured.

## Further controlled comparisons

Additional stat checks can cover other items, higher levels and R ranks. Validate armor penetration's representation with a separate supported source; do not assume it shares the magic-penetration mapping merely because the names are similar.

Damage and timing measurements should use isolated attacks and Q/W casts with known target resistance and health. The current rune page includes Deathfire Touch, Scorch and Cut Down, whose damage effects are not implemented; these need explicit control or modeling before total damage can serve as evidence for the base spell implementation.

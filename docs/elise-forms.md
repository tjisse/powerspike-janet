# Elise's fixed Human and Spider forms

On 16.19.1, either participant can select a fixed form:

| Form | Attack type | Attack range | Base movement speed |
| --- | --- | --- | --- |
| Human | Ranged | 550 | 330 |
| Spider | Melee | 125 | 355 |

Spider attacks against champions and practice targets also deal Spider Queen's
bonus magic damage and restore Elise's health. At effective R ranks 1–4, damage
is 14 / 24 / 34 / 44 plus 15% AP, and healing is 6 / 8 / 10 / 12 plus 8% AP.
These are separate from the physical attack: the magic damage uses the target's
MR and does not crit. Healing respects missing health and healing modifiers.
Both amounts use live AP, including temporary modifiers and their expiry.

Elise starts with a free first R rank. The scenario's ordinary R allocation
counts additional points, so an allocation of zero still gives Spider rank 1.
Automatic allocations at levels 6, 11 and 16 increase the effective rank to
2, 3 and 4. Withholding those points retains a lower passive rank. Both control
views label this explicitly; no scenario schema change is required.

The form drives attack reach, movement, supported melee/ranged item effects,
item explanations, champion Details, combat metrics and item search. Both
participants choose independently. Export/import and share links preserve the
choices, and optimization keeps them fixed. Charts name the selected forms
and identify the passive as Spider Queen and Spider Queen healing.

## Scope

This mode includes ordinary attacks, supported item/rune/summoner effects, form
movement speed and the champion/practice passive above. It excludes active
abilities, Spiderlings, Rappel amplification, conditional movement bonuses,
form switching and Spider Queen effects against objectives. Spider W's passive
attack speed belongs to Spiderlings; it is not applied to Elise. Selecting a
form does not imply a recent transformation or an ability cast.

Only successful ordinary attack impacts trigger Spider Queen. Misses,
interrupted windups and parried attacks produce neither its damage nor healing.
Generated proc damage does not recursively trigger it. Existing item-trigger
order remains unchanged, with Spider Queen following item and rune triggers.
Shield and damage-immune interactions inherit the shared engine's behavior;
this work does not independently establish their in-game ordering.

Ordinary windup remains the existing 30% assumption. Human attacks now use
[reviewed projectile travel at 1,600 units/s](form-projectiles.md). Scenarios with no selected form
retain their unknown attack type and conditional item-effect exclusions.
Immutable catalog bytes remain unchanged.

## Sources and discrepancy resolution

[The retained manifest](../data/form-fixtures/16.19.1/elise-manifest.json) records
matching-patch complete character-source hashes and a hashed localization
excerpt. The Human and Spider roots give range and movement speed. Matching
tooltips establish melee/ranged identity and the free first ultimate rank.
The canonical `EliseR` calculation supplies `PassiveTotalDamage` and
`PassiveTotalHealing`, using named rank arrays and AP coefficients of
approximately 0.15 and 0.08. The handler preserves their source float precision.

The alternate `EliseRSpider` tooltip-only damage array still contains
12 / 22 / 32 / 42. [Riot's patch 26.19 notes](https://www.leagueoflegends.com/en-us/news/game-updates/league-of-legends-patch-26-19-notes/)
explicitly change Spider Queen from those values to 14 / 24 / 34 / 44, agreeing
with canonical `EliseR`. The handler therefore uses the canonical formula and
retains both complete records so this discrepancy remains inspectable.

Import guards check hashes, patch, identities, range, movement speed, equal
remaining permanent stats, formula shape, rank values, AP coefficients and
tooltip references. These retained values are embedded in the executable and
contribute to model identity and optimizer cache invalidation. Other patches
cannot silently inherit the profile.

## Checks

The form suite checks both participant roles, attack reach, item scaling and
tooltips, effective rank boundaries and withheld points, independent damage
and healing arithmetic, MR, critical attacks, healing caps, live AP and expiry,
movement speed and distance, misses, interrupts, parries, objective exclusions,
direct/fitness parity, both optimizer perspectives, scenario/UI round trips and
immutable cached catalogs. Existing Nidalee and Jayce cases remain in the suite.

Packaged runtime checks export and simulate both forms and every passive rank
from an empty relocated directory. Browser checks cover independent selectors,
draft versus completed results, explicit reruns, shared reproduction, practice
controls, readable passive names, R allocation labels, native submission and
mobile layouts. These checks validate implementation against retained source
formulas; they do not admit new in-game observations or establish complete
champion or timing support.

Core/source checks, all 170 Python tests (162 passed, eight optional skips),
web/combat regressions, formatting, the relocated runtime and full desktop/mobile
browser suite passed. After the final UI wording update, web checks and the
browser suite passed again. The final executable also passed the runtime suite
with the published v0.18.0 seed and the separate sourced Riposte fixture.

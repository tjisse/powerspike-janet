# Gnar's fixed Mini and Mega forms

On 16.19.1, either participant can select Mini or Mega Gnar. The choice stays
fixed for the entire simulation and item search. This completes the fixed
attack-identity pass for the five ambiguous champions: Kayle, Nidalee, Jayce,
Elise and Gnar. It does not establish complete champion kits or transformations.

For level `L`, let `n = L - 1` and `g = n × (0.7025 + 0.0175 × n)`, the existing
stat growth progression. Rounded source coefficients are shown below:

| Stat | Mini | Mega |
| --- | --- | --- |
| Attack type | Ranged | Melee |
| Attack range | 400 + 100 × n / 17 | 175 |
| Health | 540 + 79 × g | 640 + 122 × g |
| Attack damage | 60 + 3.2 × g | 66 + 5.7 × g |
| Armor | 32 + 3.7 × g | 35.5 + 6.7 × g |
| Magic resist | 30 + 1.3 × g | 33.5 + 4.8 × g |
| Attack speed, before items/shards | 0.625 × (1 + 0.06 × g) | 0.625 × (1 + 0.005 × g) |
| Movement speed, before modifiers | 335 + n through level 15; 351 / 353 / 355 at levels 16 / 17 / 18 | 335 |
| Health regeneration / 5 s | 4.5 + 1.25 × g | 4.5 + 1.25 × g |

Mega's passive increases base stats, including base AD. Supported Spellblade
therefore uses the transformed base AD; bonus-AD expressions do not mistake it
for item AD. Item/shard stats apply afterwards. Starting health is the selected
fraction of that form's maximum health, with no extra transformation heal.

Attack reach, supported melee/ranged item rates, tooltip explanations, champion
Details, comparison metrics and optimizer fitness share the compiled actor.
The two participants choose independently. Export/import and share links retain
both choices, and completed charts label them Mini and Mega. Changing champion
clears an incompatible form; imports remain strict. Unselected forms retain the
previous unknown attack type and conditional item-effect exclusions. Catalog
snapshot bytes stay unchanged.

## Scope

The mode includes ordinary attacks, level-scaled form stats and supported item,
rune and summoner effects. Rage generation/decay, automatic transformations,
transformation healing, Hyper's damage/movement trigger, active ability casts
and form switching are excluded. The selected form persists even beyond Mega's
usual 15-second duration; Simulation details states this explicitly.

Ordinary windup remains the existing assumed 30%, and Mini projectile travel
remains the existing zero-travel assumption. This work adds no attack timing
profile or in-game combat observation. Fixed forms are controlled comparison
conditions, rather than a model of a complete Gnar fight.

## Sources and conflicting records

[The retained manifest](../data/form-fixtures/16.19.1/gnar-manifest.json) binds
complete matching-patch Gnar/GnarBig records and a localization excerpt to their
SHA-256 hashes. The original Gnar source hash matches the existing catalog
receipt. Formula shapes, level breakpoints, named values, attack-speed growth,
identity text and reviewed semantic choices are guarded during import. The
executable embeds the profiles; source files are not required after relocation.
All retained inputs and the handler contribute to model/cache identity.

The current Mini root supplies its permanent stats and 6% attack-speed growth.
The Mega root supplies 175 range, melee identity and 0.5% attack-speed growth.
The named `GnarPassive` calculations supply Mega's base-stat additions:
100 + 43 × g health, 6 + 2.5 × g AD, 3.5 + 3 × g armor and 3.5 + 3.5 × g MR.
`mScaleByStatProgressionMultiplier` distinguishes these from linear range
scaling; the named health endpoints use the same stat progression.
The [general formula parser](level-scaling.md) now honors this flag for tooltip
expressions too; the fixed-form profile already used the correct curve.

The alternate GnarBig root instead retains AD growth 5.5 and rounded base
armor/MR 36/33. Applying the named passive to Mini gives effective AD growth
5.7 and defenses 35.5/33.5. The handler follows those explicit passive additions,
not the conflicting alternate defaults. [Riot's 11.13 notes](https://www.leagueoflegends.com/en-us/news/game-updates/patch-11-13-notes/)
also document a fix making Mega's passive base AD agree with its tooltip.

Mini's `TotalAttackRange` calculation supplies only a 0–100 linear increase.
The reviewed 400 baseline comes from Riot's 6.13 patch notes, whose original
URL now redirects to the news index. [The contemporary full reprint](https://www.surrenderat20.net/2016/06/patch-613-notes.html)
preserves Riot's stated 400–500 range endpoints and the form identities.
The matching calculation supplies the current 100-unit span. This is an
explicit patch-bounded semantic rule, not a range threshold or an inference
from the spell's unrelated cast range.

Mini's `TotalAS` tooltip is not stacked onto its character growth. Riot's 4.20
notes explain that Mini's passive attack-speed bonus was folded into the 6%
growth stat; [the original Riot-authored notes are preserved in this reprint](https://www.nerfplz.com/2014/11/official-patch-420-notes-released.html).
The current form roots independently retain 6% and 0.5%. Historical numeric
health/defense values are not imported from that article. [Riot's 10.4 notes](https://www.leagueoflegends.com/en-us/news/game-updates/patch-10-4-notes/)
confirm base movement speed 335 and Mini's 0–20 bonus. The current `TotalMS`
breakpoint calculation supplies its level-16 step change.

## Checks

The form suite independently checks every level's health, AD, armor, MR,
regeneration, movement, attack speed and range, including fractional ranges
and the movement breakpoint. It checks both participant roles, exact reach,
source-backed item rates/tooltips, actual Sheen damage from transformed base AD,
starting health, scenario/UI round trips, both optimizer perspectives,
direct/fitness parity, patch isolation and unchanged cached catalog bytes.
Existing Nidalee, Jayce and Elise cases remain in the same gate.

Packaged checks export and simulate both forms, including levels 15, 16 and 18.
Browser checks cover independent choices, draft/results separation, explicit
reruns, shared reproduction, changing levels and their displayed stats,
practice controls, omissions, native submission and layouts down to 320 pixels.
These checks establish software/source agreement, not new in-game validation.

Core/source checks, all 170 Python tests (162 passed, eight optional skips),
web/combat regressions, formatting, the relocated runtime and full desktop/mobile
browser suite passed. The final executable also passed the runtime suite with
the published v0.18.0 seed and the separate sourced Riposte fixture.

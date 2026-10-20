# Nidalee's fixed ordinary-attack forms

On 16.19.1, players can select Human or Cougar form independently for either
participant. The selected form stays fixed during the fight:

| Form | Attack type | Attack range |
| --- | --- | --- |
| Human | Ranged | 525 |
| Cougar | Melee | 125 |

Supported melee/ranged item effects, item tooltip calculations, attack reach,
comparisons and optimizer fitness use that same compiled form. The result chart
identifies the completed forms, including a Nidalee-versus-Nidalee duel. Champion
Details retains the selected actor's range.

The form control appears beside the selected champion in practice and duel
views. Duel edits remain drafts until Run fight is pressed. Scenario JSON and
share links retain both choices. Optimization holds the configured form fixed;
it does not search transformations or change the opponent's form.

## Scope and compatibility

This handler supports ordinary attacks and supported item effects. Nidalee's
abilities, Hunt/Prowl and switching forms are excluded in this fixed-form mode,
as Simulation details explains. A selected Cougar actor cannot inherit Human
spells from a fetched kit. Summoner spells retain their existing support.
Ordinary Human attacks now use [reviewed projectile travel at 2,500 units/s](form-projectiles.md);
windup remains the existing 30% assumption. This is source-derived timing,
rather than a new in-game measurement.
The app does not start an automatic ability download for a selected fixed form.
A duel opponent without a fixed form still gets the existing data-loading flow.

Scenarios with no selected form retain the existing unknown attack type and
conditional item-effect exclusions. This preserves older scenario meanings.
An explicit unsupported form, champion or patch is rejected when compiling or
importing a scenario. The UI clears a stale form when changing to a champion
without form support. The retained catalog and snapshot bytes remain unchanged.

The version-1 scenario envelope gains an optional participant `form` string,
currently `human` or `cougar` for Nidalee on this patch. Other fields, patch,
snapshot and model identity requirements remain in force. New form scenarios
require this model; older executables reject their unknown field.

## Developer evidence

[The source manifest](../data/form-fixtures/16.19.1/manifest.json) retains the
complete matching-patch Nidalee and NidaleeCougar character records and a small
localization excerpt. The Human source hash matches the record already
identified in the catalog. The two roots supply their respective ranges; the
matching Aspect of the Cougar tooltip maps Human to ranged and Cougar to melee.
Both roots list both purchase identities, so those lists alone cannot classify
the selected form. The tooltip interpretation and explicit form choice supply
the missing context.

The loader checks retained hashes, names, fallback identity, ranges, tooltip
interpretation and equality of the permanent combat stat fields shared by both
roots. Other form bonuses cannot be silently inherited from a future source.
Loading during module import also embeds the reviewed projection in the
standalone executable. The handler and retained source inputs contribute to
combat model identity and fitness cache invalidation.

`test/forms.janet` uses a cached catalog predating attack-style metadata and a
real source-backed Blade of the Ruined King. It checks both forms at levels 1,
6 and 18, both participant roles, exact range boundaries, independent on-hit
arithmetic, numeric item tooltips, fixed-form ability exclusion, direct/fitness
parity, optimizer preservation from both perspectives, exact scenario/UI round
trips, invalid forms, patch isolation and immutable package bytes.

Runtime checks exercise both forms through packaged HTTP exports and CLI
simulation from an empty relocated directory. Browser checks cover independent
selection, draft versus completed results, explicit reruns, share-link
reproduction, native form submission and mobile controls. The browser seed
keeps stat-only item effects unchanged; sourced item arithmetic is checked in
the separate Janet suite. These are software regressions, not new in-game
measurements or verification-ledger admissions.

Core/source checks, all 170 Python tests (162 passed, eight optional skips),
web/combat and source-backed form regressions, relocated runtime and the full
packaged browser suite passed. The final executable also passed the runtime
suite with the published v0.18.0 seed and the separate parry fixture.

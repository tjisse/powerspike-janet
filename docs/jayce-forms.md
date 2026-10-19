# Jayce's fixed ordinary-attack forms

On 16.19.1, either participant can select Hammer or Cannon form. The selected
form stays fixed throughout the fight and item search:

| Form | Attack type | Attack range | Additional armor and magic resist |
| --- | --- | --- | --- |
| Hammer | Melee | 125 | 5 / 12 / 19 / 26 at levels 1 / 6 / 11 / 16, plus 7.5% bonus AD |
| Cannon | Ranged | 500 | None |

Ordinary attack reach, supported melee/ranged item effects, item calculations,
champion Details, comparison metrics and optimizer fitness use the same compiled
actor. Hammer's resistance bonus includes item and shard AD. Temporary AD buffs
also update the resistance bonus during combat; expiry restores the previous
stats. Armor/MR modifiers apply after this derived form bonus.

The existing form selector supports both participants in practice and duel
views. Completed charts identify the forms. Export/import and share links
retain them, and item optimization preserves both choices. Switching between
Nidalee and Jayce clears a previous champion's incompatible form choice. The
scenario compiler and importer still reject invalid champion/form combinations.

## Scope and sources

The mode includes ordinary attacks, supported item effects and Hammer's
resistance passive. Jayce's ability casts, Hextech Capacitor, transformation
attack bonuses and form switching remain excluded and are listed in Simulation
details. Selecting a form does not imply a recent transformation. Hyper Charge,
the empowered Hammer hit and Cannon's resistance shred are not fabricated.
Existing standard skill-rank validation remains; six-rank basic abilities and
exceptional leveling need a separate handler before supporting those casts.
Hammer resistances follow champion level, independently of the R rank entered.

Cannon projectile travel remains the existing zero-travel assumption, and
ordinary windup remains the existing 30% assumption. These are not new timing
measurements. Scenarios with no form keep the previous unknown attack type and
conditional item-effect exclusions; existing snapshot bytes remain unchanged.

[The retained manifest](../data/form-fixtures/16.19.1/jayce-manifest.json)
records complete matching-patch character-source and localization hashes plus
the retained excerpt hash. The character source hash matches the source already
identified by the catalog. The root gives 125 attack range; the transformation
record supplies a 375-unit Cannon increase. Matching form-buff tooltips identify
Hammer as melee and Cannon as ranged. Neither identity is inferred from a range
threshold.

The same transformation record's `Resists` calculation supplies a level-1 base
of 5, additions of 7 at levels 6, 11 and 16, and a coefficient of approximately
0.075 on bonus AD (`mStat = 2`, `mStatFormula = 2`). The handler uses the retained
coefficient, including its source float precision. Source hashes, formula shape,
breakpoints, names, range and identity text are checked during import. Only the
reviewed 16.19.1 rule is applied. These values and the handler are embedded in
the executable and contribute to model identity and fitness cache invalidation.

## Checks

`test/forms.janet` checks both forms at each level boundary, exact attack reach,
source-backed item rates and tooltip values, both participant roles, independent
Hammer resistance arithmetic, mitigation during temporary AD and armor/MR
modifiers, repeated refreshes and expiry, R-rank independence, direct/fitness
parity, both optimizer perspectives, scenario/UI round trips and immutable
cached catalogs. Nidalee's existing cases remain in that suite.

Packaged runtime checks export and simulate both forms from an empty relocated
directory. Browser checks cover both participants, Hammer stats with a Long
Sword, draft versus completed results, explicit reruns, shared reproduction,
practice controls, native submission, mobile layouts and changing champions
without carrying an incompatible form.

These checks validate software behavior against the retained source formulas;
they do not admit new in-game combat observations or independently establish
timing or complete champion support.

Core/source checks, all 170 Python tests (162 passed, eight optional skips),
web/combat regressions, the relocated runtime and full desktop/mobile browser
suite passed. The final executable also passed with the published v0.18.0 seed,
including each Hammer resistance breakpoint and the separate parry fixture.

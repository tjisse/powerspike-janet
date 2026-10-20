# Reviewed fixed-form ordinary attack projectiles

On the retained 16.19.1 snapshot, explicit Human-form selections give Nidalee
and Elise ordinary attack travel time. Jayce's selected Cannon form now does
too. Previously these attacks hit at release under the generic zero-travel
assumption.

| Champion / selected form | Projectile speed | First impact at 300 distance and 1 attack/s |
| --- | --- | --- |
| Nidalee / Human | 2,500 units/s | 0.42 s |
| Elise / Human | 1,600 units/s | 0.4875 s |
| Jayce / Cannon | 2,000 units/s | 0.45 s |

The examples include the existing assumed 30% windup. Travel is distance at
release divided by projectile speed. At level 1 and maximum range, without
items or shards, the corresponding first impacts are approximately 0.68022 s
for Nidalee, 0.82375 s for Elise and 0.70593 s for Jayce. Hits exactly at the
simulation endpoint remain excluded. Ordinary and critical attacks use the same
reviewed movement.

The selection applies independently to either participant, practice comparisons,
item searches, shared scenarios and the packaged executable. Cougar, Spider and
Hammer forms cannot inherit the ranged projectile, including when an already
projected record is passed through form selection again. Scenarios without an explicit
form retain the previous unknown attack type and zero-travel assumption. The
snapshot bytes are unchanged; the current combat model supplies the reviewed
interpretation.

## Source review

[The explicit review](../data/attack-fixtures/16.19.1/reviewed-form-projectiles.jdn)
binds each complete source record to its SHA-256 and enumerates the reviewed
spell paths. Every path is under `Characters/<champion>/Spells/`:

| Source | Ordinary variants | Critical variants |
| --- | --- | --- |
| [Nidalee](../data/form-fixtures/16.19.1/Nidalee-characters.json) | `NidaleeBasicAttack`, `NidaleeBasicAttack2` | `NidaleeCritAttack` |
| [Elise](../data/form-fixtures/16.19.1/Elise-characters.json) | `EliseBasicAttack`, `EliseBasicAttack2`, `EliseBasicAttack3` | `EliseCritAttack` |
| [Jayce](../data/form-fixtures/16.19.1/Jayce-characters.json) | `JayceRangedAttack`, `JayceRangedAttack2` | `JayceRangedCritAttack` |

Each spell's `mSpell/mMissileSpec/movementComponent` is `FixedSpeedMovement`.
Its `mSpeed` and legacy `missileSpeed` agree with the speed above. The loader
checks every variant, the reviewed speed, character identity and complete source
hash. Missing, conflicting or unsupported movement cannot silently become a
speed. The form mappings follow the selected-form interpretations in the
[Nidalee manifest](../data/form-fixtures/16.19.1/manifest.json) and
[Elise manifest](../data/form-fixtures/16.19.1/elise-manifest.json), together with
the [Jayce manifest](../data/form-fixtures/16.19.1/jayce-manifest.json), which retain
the source URLs and matching localized form descriptions.

The reviewed source hashes are
`ebb70f0ada28ae79a32b9c1fec4be6f5f4df5059a851411eae5eec87278585b7`
for Nidalee and
`3bc5c29e36ff90f2eab159bb2ed37d7700d69120c14eb8a1f029729a3695eb29`
for Elise, and
`8debded310692c6edc508f33cb243f03d0c84cb56108c45af77a82ad49bf6212`
for Jayce. No new data download, patch substitution or in-game timing measurement
is involved. Profiles resolve during module import and are embedded in the
relocated executable. The review joins the existing source records in model
identity, preventing old optimizer cache values from crossing this correction.

## Boundaries and checks

Windup remains the explicit 30% assumption; this change does not derive windup
from cast-offset fields. Launch geometry, collision size and target movement
during flight retain the existing approximations. Attack speed samples at
attack start, and the existing 50 ms decision polling remains. Travel changes
impact time without postponing attack starts. Supported Spellblade damage and
consumption occur at impact under the existing shared handler.

These are ordinary attack profiles. Nidalee's Takedown, other empowered attacks,
active ability casts and form switching remain excluded from fixed-form mode.
Spider Queen's existing champion/practice damage and healing stay attached to
Spider attacks. Gnar's Mini projectile behavior remains separate review work:
its root names an additional ordinary variant without a matching spell record
in the retained source.

Jayce's review selects the three attack-damage records with the Cannon
animations `ranged_attack1`, `ranged_attack2` and `ranged_crit`. This is an
explicit source interpretation for the configured form, rather than a general
name-based selector or a measured server-script trace. The legacy alternate
name `GravesBasicAttack`, individual spell cast ranges and cast-time fields do
not override the reviewed 500 attack range or the declared windup assumption.
The root's `JayceCritAttack` is a different record with a legacy speed of 2,500;
it does not select the Cannon critical projectile.

The excluded transformation attack
`JaycePassiveAbility/JaycePassiveRangedAttack` also has speed 2,000, so speed
agreement alone cannot classify an ordinary attack. The review explicitly
excludes it, Hammer/root variants and
`JayceHyperChargeAbility/JayceHyperChargeRangedAttack` (speed 1,800). The loader
rejects selecting any of those excluded records. Selecting Cannon therefore
adds no post-transformation resistance shred, attack reset or Hyper Charge
damage/speed bonus; those omissions remain in the existing fixed-form scope.

`test/forms.janet` checks all three source hashes, all ten variants, exact patch
bounds, unselected/alternate forms, removal of stale cached zero-travel notes,
both participant roles and optimizer parity. It independently checks first
impact and endpoint exclusion at several attack speeds with ordinary/guaranteed
critical attacks, compares subsequent attack starts against zero-travel
scheduling, and checks primed Sheen while in flight and after impact consumption.
Existing reach, form stats, item rates, export/import and cache-byte checks stay
in the same gate. The Jayce cases also reject each excluded variant, including
the same-speed transformation hit, and preserve the absence of ability casts
and the transformation-bonus omission.

The relocated runtime checks the reviewed ranged projectile speeds and first-hit times
from exported HTTP scenarios. Browser checks verify first hits for each
participant alongside form changes, reruns, shared reproduction and responsive
layouts. These checks establish source/software agreement; they do not admit a
new measured combat observation.

Formatting, core/source/catalog checks, all 170 Python tests (162 passed and
eight optional skips), web/combat regressions, the relocated executable with
the retained parry and level-scaling fixtures, and the complete desktop/mobile
browser suite passed.

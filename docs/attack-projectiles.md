# Ordinary attack range and projectile timing

The catalog importer previously discarded Data Dragon's `attackrange`.
Initial catalog actors consequently fell back to the engine's 125-unit range.
Ranged champions could walk into melee
distance before attacking, or never attack when holding position. This affected
both fight outcomes and melee/ranged item scaling.

The importer now preserves baseline range for all 173 champions. Loading an
existing 16.19.1 snapshot fills a missing range from the matching, hash-checked
Data Dragon source. Existing configured ranges are preserved. Snapshot bytes
and identifiers do not change. New seeds include the range directly; catalog
changes now trigger the seed build. Missing ranges on another patch are not
filled from 16.19.1. Temporary range changes and exceptional weapon/form rules
still need their respective champion handlers.

Ahri's ordinary attacks now also use the retained fixed projectile movement:
`AhriBasicAttack`, `AhriBasicAttack2` and `AhriCritAttack` all specify 1,750 units/second in
`mMissileSpec.movementComponent.mSpeed` and the legacy `missileSpeed` field.
The source is the complete, hash-checked
`data/combat-fixtures/16.19.1/Ahri-characters.json`, recorded in its manifest.
The profile applies only to Ahri on 16.19.1. Cached and newly fetched snapshots,
either duel participant and optimizer fitness receive the same semantics.

Damage is scheduled at release time plus distance at release divided by speed.
A projectile still in flight contributes no early damage, and an impact at the
fight's endpoint is excluded. Travel does not delay the next attack's timer.
The initial profile used the 30% windup assumption. The subsequent
[mage timing correction](attack-timing.md) supplies Ahri's reviewed 20% fraction:
at one attack/second and 350 distance, the first impact is now at 0.4 seconds.

This is source-derived simulation behavior, not a newly admitted in-game timing
measurement. Unreviewed windups retain the configured 30% assumption. Movement during
flight, collision geometry, launch offsets and Spellblade's launch-versus-impact
consumption still need review. The player interface continues to call the result
a simulation; source hashes and review details remain developer information.

Annie's movement speed (1,500) conflicts with its legacy speed (1,200); the
[reviewed timing correction](attack-timing.md) now resolves that specific case
using Riot's patch notes and exact source guards. The [Viktor follow-up](viktor-attacks.md)
adds his 2,300 ordinary projectile speed and preserves empowered Q's explicit
zero-travel assumption separately. Ranged actors
without a supported profile report the zero-travel
assumption in Simulation details.

`test/attack-projectiles.janet` checks all 173 retained baseline ranges, missing
range repair, exact patch isolation, invalid data, source hashes, inconsistent
movement/variants, idempotent cached semantics, both duel participants,
in-range/out-of-range attacks, half-open impact boundaries and direct/fitness
agreement. Model identity includes the new handler and retained sources, so
cached fitness results and saved model identities cannot silently cross this
change.

Formatting, core/source/Python suites, frontend and combat regressions passed.
The relocated executable checks Ahri holding at 350 units and its first impact
against the independent windup-plus-travel calculation. The initial Annie
comparison checked four attacks at the correct range plus two Qs and one W;
the subsequent projectile correction moves the fourth impact beyond five seconds.
Packaged
Chromium practice comparisons, paired matchups, optimizer apply/undo, mobile
layouts and native form checks also passed.

# Viktor ordinary and empowered attacks

On the retained 16.19.1 snapshot, ordinary Viktor attacks now travel at
2,300 units/second. His Q replacement keeps its existing zero-travel policy
separately, so adding an ordinary projectile cannot delay the empowered attack
or its on-hit effects. This affects either participant, practice comparisons,
optimizer fitness and the standalone executable.

## Source boundary

The complete retained `Viktor-characters.json` is bound to both the combat
fixture manifest and the explicit SHA-256 in
`data/attack-fixtures/16.19.1/reviewed-timing.jdn`.
`ViktorBasicAttack`, `ViktorBasicAttack2` and `ViktorCritAttack` all specify
`FixedSpeedMovement.mSpeed = 2300` and legacy `missileSpeed = 2300`.
All variants must agree. The ordinary projectile profile applies only to
16.19.1; cached snapshot bytes remain untouched.

`ViktorQAbility/ViktorQBuff` is a separate spell record with no
`mMissileSpec`, a different attack animation and legacy `missileSpeed = 25000`.
That absence does **not** establish exact server hit timing. The review guards
both its missing movement component and its legacy value, but does not turn
25,000 into an ordinary projectile speed or assert that missing data proves an
instantaneous hit. The existing empowered zero-travel behavior is retained as
an explicit `:attack-delivery :release` policy and reported as an assumption in
Simulation details. Viktor's 30% windup remains an assumption too.

No new measured combat case is admitted. The cached discovery roster includes
a Viktor game on 16.20, but there is no reviewed, matching-patch ordinary or
empowered timing capture yet. Exact empowered windup/delivery, critical-strike
interactions, Q evolution, launch geometry and movement during flight remain
outside this source review. Verification hashes and engineering details stay
in developer records.

## Scheduling

Only a live, selected replacement damage modifier can override delivery.
Expired, consumed or unselected modifiers cannot change an ordinary attack.
Bonus effects on that attack share its impact time, and existing on-hit triggers
run there once per attack origin. Replacement selection happens after hit and
interruption checks. A missed or interrupted attack retains its empowerment.
Casting an ability whose only enemy effects are future attack empowerments no
longer incorrectly rolls a hit check before the attack itself.

Ordinary travel is release distance divided by 2,300. At one attack/second and
500 distance, the assumed 30% windup gives an ordinary impact at about 0.51739
seconds after attack start. An empowered replacement under the explicit
zero-travel policy hits at 0.3 seconds instead. Impacts exactly at the endpoint
are excluded. Travel does not postpone the next attack's ready time.

Attack speed and period still sample at attack start, decisions poll every
50ms while waiting, and Spellblade consumption still occurs at successful
impact. This change does not establish launch-versus-impact consumption rules.

## Checks

`test/attack-projectiles.janet` covers the complete source hash, all ordinary
and critical variants, exact patch bounds, cached semantic repair and ordinary
impact timing. `test/engine.janet` covers release delivery, ordinary replacement
travel, bonus/on-hit ordering, both actors, expiry, unselected modifiers,
misses, interrupted windups, malformed overrides and endpoint exclusion.
`test/mage-burst.janet` compiles the real retained Viktor kit with Lich Bane,
checks empowered and following ordinary impact times independently and checks
simulation/optimizer equality. The relocated runtime checks Viktor at 500
units without access to the source tree.

The character source and reviewed policy contribute to model identity, so
older fitness caches cannot cross this change silently.

Core/source checks, all 166 Python tests (eight optional skips), frontend and
combat regressions, the standalone runtime and packaged Chromium desktop/mobile
flows passed. The relocated executable also passed against the published
v0.18.0 RPM's older seed in an empty directory.

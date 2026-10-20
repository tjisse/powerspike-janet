# Movement and range deadlines

The one-dimensional movement model now requests a decision when relative
movement reaches an ordinary attack range, a fixed ability range or the
participant's chosen stopping distance. Ready actions no longer wait for the
next 50 ms poll after entering range. Approach stops at ordinary attack range;
hold-range moves toward its configured preferred distance, retaining the
one-unit hysteresis for starting movement.

## Forecasts and state changes

The engine derives both participants' current velocity after each live event.
It uses their relative velocity to forecast a crossing, including a moving
target entering a stationary participant's range. Slows, movement-speed buffs,
their expiry, roots, cleanses, other movement-blocking controls and action locks
change the trajectory at their actual event times. A moving participant also
requests a decision at the end of its current action lock. Two approaching
points stop at their meeting point rather than passing through one another.
Chasing integrates both participants against the same elapsed interval; it no
longer clamps a faster chaser to the target's previous position. Coincident
participants use opposite steering directions when separating.

Range forecasts cover the enabled ordinary attack and learned, modeled enemy
abilities whose range expression depends only on constants, rank or level.
They share the bounded fixed-expression classifier with resource forecasts.
Self-only abilities need no range crossing. State-dependent ability ranges
retain normal evaluation during decisions rather than freezing a changing
range into an invalid forecast.

Forecasts round forward to a nanosecond grid. Actual distance comparisons stay
strictly inclusive, without extra range tolerance. Deadlines request the same
coalesced decision used for other readiness boundaries. A speed change can
leave an obsolete earlier wake in the queue; it rechecks the actual position
and cannot cast out of range. Priority, cooldown, recast, charges, activation,
resources, control, action locks and survival remain binding. Effects and deaths
at the boundary run before the decision. The simulation window remains
half-open: actions at its exact end are excluded.

## Reproduced software difference

[The movement suite](../test/movement-readiness.janet) uses the unmodified
16.19.1 package
`1f774c1b65886f768cc2dca3628fe3ece2971a5719b4f3bfb862844e230c5928`.
Both participants are level-1 Annie with no items, runes or shards. The active
participant enables Q, disables ordinary attacks, and approaches from distance
700; its opponent holds with attacks and abilities disabled.

The retained inputs give movement speed 335, ordinary attack and Q range 625,
Q cast time 0.25 s and missile speed 1,400. The independent entry reference is
`(700 - 625) / 335 = 0.223880597 s`; Q impact is that time plus
`0.25 + 625 / 1400 = 0.920309168 s`. The test window ends at `0.925309168 s`.

Comparison against engine revision `de57483` uses identical compiled actors:

| Quantity | Previous engine | Corrected engine |
| --- | ---: | ---: |
| Q starts | 0.250000 s | 0.223881 s |
| Movement distance | 83.750000 | 75.000000 |
| Distance at release | 616.250000 | 625.000000 |
| Q hits | Outside window (0.940179 s) | 0.920309 s |
| Damage inside window | 0 | 61.538462 |

Both versions pay 60 mana and use the same damage expression. The corrected
engine stops at the declared range and includes Q's hit inside the window.
The remaining position difference is below one millionth of a unit from forward
time rounding. This is a retained-input software regression, not measured game
movement, pathing or player reaction time; no combat observation is added.

## Checks and boundaries

Independent arithmetic checks cover both actor roles, ordinary and ability
range, a moving target, both participants moving, different stopping ranges,
hold-range approach/retreat/hysteresis, chasing, mirrored coordinates, meeting
points and separation from coincident positions, between-poll speed
changes, slow expiry, roots, cleanse, silence, stun, cast locks, priority,
activation time, affordability, health rules, unlearned abilities, dynamic
ranges, same-time death and half-open endpoints. Trace-free metrics match traced
simulation metrics. The retained Annie case reverses participant roles, checks
release/travel arithmetic, preserves package bytes and agrees with optimizer
fitness. The copied executable exercises the same export in both orders;
browser checks exercise both movement controls, cast/impact times, stopping
distance and 320 px layout.

This remains a point-based, one-dimensional strategy model. Champion radii,
pathfinding, terrain, dashes, real player latency and new movement mechanics
are outside this change. State-dependent ranges and costs still use periodic
checks between known deadlines. Ordinary attack period/windup sampling,
cast-lock policy and distance-at-release projectile travel stay as declared.
Source packages and scenario schema stay unchanged. The engine fingerprint
changes, separating optimizer caches and preserving saved scenarios' model-change
notice.

Formatting, 83 core regressions, retained source/catalog checks, all 170 Python
tests (162 passed, eight optional skips), web/combat/optimizer suites and the
rebuilt relocated executable passed. The complete desktop/mobile browser suite
passed against the final executable, including the new movement cases, fixed
forms, both inventories, comparisons, optimization/apply/Undo, sharing, scenario
reproduction, sourced Riposte and control resumption.

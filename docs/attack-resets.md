# Attack reset readiness

An applied reset that shortens a future ordinary attack deadline now requests a
decision immediately, constrained by the actor's current action lock. Both the
explicit `:reset` effect and an attack empowerment's existing `:reset true`
flag use this path. Previously they updated `attack-ready`, but could leave the
actor waiting for a periodic decision. An instant empowerment could also wait
for the default 10 ms post-action check.

Resetting an already-ready attack does not add a decision. Disabled attacks
still receive the existing readiness-state update without a wake. Requests
reuse the [coalesced decision scheduler](control-resumption.md), so repeated
resets cannot introduce parallel attack loops. The ordinary decision still
checks action locks, control, range, survival and ability priority. A reset
does not cancel an existing windup or remove a projectile already in flight.
The next attack samples its usual speed, windup and projectile policy.

## Reproduced software difference

[The reset suite](../test/attack-resets.janet) exports a labeled synthetic
package using retained champion stats as carriers. Its invented ability has
zero cast time and applies a delayed self reset at 0.337 s. The carrier's
attack speed is explicitly set to one attack/second; the existing 30% windup
assumption and reviewed Annie projectile speed of 1,500 units/s supply delivery.
Distance is 300, the opponent holds position with zero armor, and the scoring
window is 0.843 s. The initial spell leaves the existing first attack at 0.010 s.

A comparison against engine revision `d865f17` uses identical compiled actors:

| Quantity | Previous engine | Corrected engine |
| --- | ---: | ---: |
| First attack hits | 0.510 s | 0.510 s |
| Reset applies | 0.337 s | 0.337 s |
| Second attack starts | 0.360 s | 0.337 s |
| Second attack hits | Outside window (0.860 s) | 0.837 s |
| Damage inside window | 50 | 100 |

The independent impact reference is
`attack_start + 0.3 / attack_speed + distance / projectile_speed`.
The damage difference comes from the second hit entering the configured window.
This is a software regression, not a measured champion fight or a new claim
about Annie's abilities. The synthetic package is not added to the observations
ledger.

## Checks and remaining scope

Tests cover fractional attack speeds, instant/projectile delivery, both actor
positions, independent start/impact arithmetic, metrics without traces,
resets during windup, repeated/coincident resets, ability priority and extended
locks, same-time stun/death, silence/root permissions, disabled attacks,
already-ready attacks and half-open fight endpoints. The compiled synthetic
case reverses participants, compares direct simulation with optimizer fitness,
checks unchanged snapshot bytes, and runs through the copied executable with
no checkout access.

Seven retained empowered-attack records already carry `Trait_AttackReset`:
Yorick, Jax, Blitzcrank, Darius, Trundle, Leona and Xin Zhao. The suite checks
their parsed/normalized reset behavior with configured cast times of zero and
0.1 s. Those cast times are regression inputs, not measured timing for these
champions. No new reset tags or damage coefficients are introduced.

The current model preserves action locks when resetting. Champion-specific
windup cancellation, alternate reset timing and other missing activation
handlers still require reviewed mechanics evidence. The subsequent
[resource readiness correction](resource-readiness.md) forecasts fixed-cost
affordability under continuous recovery. The [health activation correction](health-activation.md)
adds wakes when discrete health changes satisfy configured low-health rules.
State-dependent costs and range crossings continue to poll between known deadlines.
The source and scenario schemas stay unchanged. The engine fingerprint changes,
separating optimizer cache entries and preserving the saved-scenario model-change
notice.

Formatting, 83 core regressions, retained source/catalog checks, all 170 Python
tests (162 passed, eight optional skips), web/combat/optimizer suites and the
rebuilt relocated executable passed. The complete desktop/mobile browser suite
also passed, including comparisons, optimize/apply/Undo, sharing, fixed forms,
the sourced Riposte fixture and synthetic control resumption.

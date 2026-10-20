# Ability readiness

Ability cooldowns, recast delays, recast-window expiry, charge reuse/recovery
and explicit strategy `activation.after` times now wake the existing combat
decision at their known deadline. They no longer accumulate rounding delays
from the 50 ms condition poll. This extends the
[ordinary attack correction](attack-cadence.md) to abilities in practice fights,
duels and optimizer scoring.

Readiness still passes through ability priority, cast locks, costs, range,
target immunity, activation conditions, control and actor/target survival.
Charge recovery runs before a decision at the same timestamp. The next
recharge deadline advances with recovery and clears when charges are full.
Only future deadlines schedule a wake, preventing a resource-blocked ability
from retrying forever at one timestamp. Each actor retains one pending decision.

An active recast now uses its own delay exclusively. Previously, a shorter
main cooldown could bypass that delay, allowing premature recasts and additional
base casts. Expiry returns to the base cooldown and base resource cost; a
recast whose delay ends exactly at expiry is already expired.

Definitions, learned ranks and priority order stay fixed during the current
fight model. A private ordered list prepares those once per simulation for
selection and readiness scans. Dynamic costs, stats, conditions, range and
control are still checked at decision time. This list is not added to exported
actors or scenarios.

## Reproduced software differences

A comparison against engine revision `3bfe889` used identical compiled actors.
The cached level-1 Annie subset, with Ionian Boots (10 ability haste), attacks
disabled, Q enabled and 12 seconds against a stationary practice target, gave:

| Q cast | Previous engine | Corrected engine |
| --- | ---: | ---: |
| First | 0 s | 0 s |
| Second | 3.65 s | 3.636364 s |
| Third | 7.30 s | 7.272727 s |
| Fourth | 10.95 s | 10.909091 s |

The independent interval is `4 / (1 + 10 / 100)` seconds. Damage remains 320
in this window; shorter endpoints can change which casts or impacts count.

A synthetic ability with a 0.173 s main cooldown, 0.04 s cast time, two recasts,
0.37 s recast delay and 2 s recast window previously cast eight times within
0.75 s. It now casts at 0, 0.37 and 0.74 s. Its last impact at 0.78 s falls
outside that window. These are reproducible engine regressions, not measured
in-game fights or new champion mechanics evidence.

## Scope and checks

Condition thresholds, movement/range crossings and resource recovery thresholds
still use periodic checks between known deadlines. The subsequent
[control resumption correction](control-resumption.md) adds exact control-expiry
and applied-cleanse wakes. The
existing minimum cooldown/charge reuse of 50 ms and default post-action
check of 10 ms remain; a future readiness deadline can wake earlier, subject
to the action lock. Haste and cooldown origin retain their existing
cast-time sampling rules. This does not establish missing champion timing,
retroactive cooldown adjustment or automatic form changes. The subsequent
[attack reset correction](attack-resets.md) adds wakes when an applied reset
shortens a future ordinary attack deadline.

The engine fingerprint includes the changed source. Existing saved scenarios
therefore show their model-change notice, and optimizer caches cannot reuse
old metrics. Retained package bytes and the scenario schema are unchanged.

[The readiness suite](../test/ability-readiness.janet) checks independent haste
arithmetic, unhasted abilities, start/end cooldown origins, both participants,
separate ability phases, explicit activation, priority, extended locks, exact
endpoint exclusion, mana/health costs, disabled/unlearned abilities, recast
delay/expiry, charge reuse/recovery and same-timestamp silence/death. The cached
Annie case checks direct/fitness equality and immutable package bytes.
Relocated executable and browser checks exercise hasted Annie Q timing through
scenario export and both duel participants.

The existing two-second mage search comparison also exposed a floating-point
edge case: two builds both killed a 2,500-health target, but their summed damage
was `2500.0000000000005` versus `2500.0000000000009`. That comparison now allows
one millionth of a damage point and reports full-precision values on failure.
The search budget and combat scoring are unchanged.

Formatting, 83 core regressions, retained source/catalog checks, all 170 Python
tests (162 passed, eight optional skips), web/combat/optimizer suites and the
rebuilt relocated executable passed. The complete desktop/mobile browser suite
also passed, including both inventories, comparisons, optimization/apply/Undo,
sharing, fixed forms and the sourced Riposte fixture.

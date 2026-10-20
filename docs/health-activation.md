# Health-based ability activation

An enabled ability with a configured self- or target-health limit now requests
a combat decision when a discrete health change makes its health conditions
true. Damage, health-cost payments and changes to maximum health can enable
these low-health rules. The participant no longer waits for a later 50 ms poll
when the action is otherwise ready.

The comparison remains inclusive: health fraction must be at or below the
configured limit. The duel controls now say "at most" to match this boundary.
Self and target conditions must both hold. Learned abilities
with modeled effects are watched only when their strategy enables abilities
and at least one health limit is below the default of 1. Default strategies
do not acquire health-triggered decisions on every hit.

## State changes and ordering

The engine samples the relevant predicates immediately before a health mutation,
then checks whether any changed from false to true. Sampling avoids a cached
predicate becoming stale after regeneration or an intervening heal. An unchanged
predicate does not add a decision. Actual damage after mitigation and shields,
positive applied healing, health-cost payments and maximum-health changes share
this check; misses, parries and absorbed damage cannot invent a health loss.

Wakes reuse the [coalesced scheduler](control-resumption.md) and respect the
configured activation time and current action lock. They request a normal
decision rather than casting directly. Priority, cooldown/recast/charge state,
range, resources, control and survival remain binding. Health costs set the
payer's action lock before notifying either participant.

Healing can invalidate a queued low-health response. The health conditions are
checked again at decision time, after same-timestamp effects and deaths.
Regeneration during an action lock can likewise make the response ineligible.
Multiple threshold crossings at one timestamp coalesce, and ability priority
still determines which eligible spell casts first.

## Reproduced software difference

[The activation suite](../test/health-activation.janet) uses the retained 16.19.1
Annie Q subset and unmodified package
`1f774c1b65886f768cc2dca3628fe3ece2971a5719b4f3bfb862844e230c5928`.
Both champions are level 1 with no items, runes or shards, holding at distance
200. The player enables ordinary attacks and Q, with Q requiring the target to
have at most 95% health. The opponent disables attacks and abilities.

The existing inputs give attack speed 0.61, assumed windup 30%, ordinary
projectile speed 1,500, Q cast time 0.25 s and Q missile speed 1,400. The first
ordinary hit therefore arrives at
`0.3 / 0.61 + 200 / 1500 = 0.625136612 s`. It makes the target-health rule true.
The independent Q impact reference is that time plus `0.25 + 200 / 1400`, or
`1.017993755 s`. The window ends at `1.022993755 s`.

A comparison against engine revision `cc6ea91` uses identical compiled actors:

| Quantity | Previous engine | Corrected engine |
| --- | ---: | ---: |
| First ordinary hit | 0.625137 s | 0.625137 s |
| Q starts | 0.641803 s | 0.625137 s |
| Q hits | Outside window (1.034660 s) | 1.017994 s |
| Damage inside window | 40.650407 | 102.188868 |

Both versions pay the same 60-mana cost. Casting earlier also permits slightly
more regeneration after payment. The damage difference comes from including
the Q hit, rather than changing its formula. This is a software regression
using retained source inputs, not a new measured game fight. Windup and other
existing timing assumptions remain; no observation is added to the ledger.

## Checks and remaining scope

Tests cover self/target limits in both actor roles, inclusive equality, combined
conditions, healing at the trigger timestamp, repeated crossings after healing
or regeneration, pending responses invalidated by regeneration, extended action
locks, cooldowns, activation times, resource recovery, same-time control/death,
health-cost notifications to both participants, maximum-health changes/expiry,
priority/coalescing, shields, immunity, parry, misses, disabled/unlearned/out-of-range
abilities, unchanged predicates and half-open endpoints.

The retained projectile case reverses participant roles, checks independent
release/travel arithmetic and direct/optimizer parity, and verifies unchanged
package bytes. The copied executable runs the same export in both orders
without checkout access. Browser checks verify that each side's target-health
setting reaches the exported scenario, its Q starts at the triggering hit,
its impact falls inside the window, and the 320 px layout remains usable.

Movement/range crossings and state-dependent cost forecasts remain separate
work. This adds no general prediction for health limits crossed solely by
continuous health loss, nor new champion reaction rules or player decision
latency. The declared strategy still reacts as soon as the model permits.
Source packages and scenario schema stay unchanged. The engine fingerprint
changes, separating optimizer cache entries and preserving the saved-scenario
model-change notice.

Formatting, 83 core regressions, retained source/catalog checks, all 170 Python
tests (162 passed, eight optional skips), web/combat/optimizer suites and the
rebuilt relocated executable passed. The complete desktop/mobile browser suite
passed, including the new paired health-activation case, comparisons,
optimization/apply/Undo, sharing, fixed forms, Riposte and control resumption.
After clarifying the inclusive labels, the executable was rebuilt and the paired
frontend suite plus focused desktop/mobile activation checks passed again.

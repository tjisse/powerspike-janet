# Changing ability costs and ranges

Ability cost and range expressions can now use stats and buffs without falling
back to 50 ms polling for every readiness boundary. Expressions that remain
constant between applied events participate in regeneration and relative-range
forecasts. When an applied event changes their evaluated value, the engine
requests a normal decision and updates the forecast.

## Safe expression inputs

The supported group includes constant/rank/level values, own total/base/bonus
stats, target stats, buff counters, supported buff-condition branches, and
sums/products/rank overrides built from these inputs. Maximum health and mana
are stats; they change only at explicit stat events. Current health, health
fractions and missing health can change during continuous regeneration and are
excluded, including expressions with a health-dependent conditional branch.
Unknown or unresolved formulas remain excluded from forecasts.

This distinction is based on the existing evaluator and retained source inputs.
An audit of the 16.18.1 parser fixtures found current-health costs in Dr. Mundo W
and Zac Q/W/E. Their compiled formulas continue to use current health at decision
time; this change does not freeze their cost at the initial health. It does not
add champion handlers or claim that their full kits have been verified.

## Changes and ordering

The engine prepares private watchers only for learned, modeled abilities whose
strategy enables them. Fixed expressions need no watchers. After stats or buffs
are refreshed, each watched expression is reevaluated; only a changed effective
value requests a decision. Unrelated stats, identical branch values and stale
buff-expiry events do not create additional decision streams. Both participants'
watchers are considered, so target-stat formulas react to changes on the other
participant. Buff application, consumption, refresh and expiry use the same path.

Changing a still-unaffordable cost also requests a decision: the regeneration
deadline must be recalculated even when the change does not immediately permit
casting. Updated range values feed the existing relative-movement forecasts.
Stationary participants also wake when a range change can affect eligibility.
Failed evaluation cannot retain a previously valid range forecast or grant a
free cast. Actual selection still evaluates the expression through its protected
path and reports unsupported inputs.

Recast costs now pass through the same expression evaluator and nonnegative
clamp as first-cast costs. Previously a dictionary-valued recast cost was used
as a raw number, preventing the recast from selecting successfully.

Wakes share the coalesced scheduler. Ability priority, cooldown/recast/charge
state, activation conditions, resource reserves, action locks, control and
survival remain binding. A cast sets its action lock before a cast-start effect
can request another decision. Same-timestamp reversals, silence and death are
checked before acting. Forecasts keep forward nanosecond rounding and strict
affordability/range comparisons; the scoring window remains half-open.

## Reproduced software difference

[The regression suite](../test/changing-readiness.janet) exports a synthetic
16.19.1 package with snapshot
`fff73cd694a0da233f2215d7ccc8ac2e1bcb004d64ae9f4d4d950522bdbe8383`.
Annie and Lux are carriers for explicitly invented test abilities. The response
initially costs 1,000 mana and has zero range. The other participant applies a
buff at 0.487 s that changes its cost to zero and range to 500. At distance 100,
the ready response has a 0.04 s cast time, zero travel and 10 true damage. The
window ends at 0.532 s. Both inventories are empty and movement/attacks disabled.

The comparison against engine revision `21cf05e` uses identical compiled actors:

| Quantity | Previous engine | Corrected engine |
| --- | ---: | ---: |
| Buff applies | 0.487 s | 0.487 s |
| Response starts | 0.500 s | 0.487 s |
| Response hits | Outside window (0.540 s) | 0.527 s |
| Damage inside window | 0 | 10 |

This fixture is a scheduler regression, not measured game combat or new champion
mechanics evidence. Its metadata and tooltip explicitly identify the invention.
It is not added to the combat observation ledger. Retained source packages stay
unchanged.

## Checks and remaining work

Independent arithmetic tests cover regeneration with own/base/bonus/target stats,
cost increases/decreases and expiry, buff counters, conditional/inverted branches,
buff refresh/consumption, health-cost reserves, expression-valued recasts,
stationary and moving range changes, range contraction, unrelated changes,
same-time reversals/control/death, cast-start locks, activation times,
disabled/unlearned abilities, half-open endpoints and trace-free metric parity.
Existing resource, movement, health and control suites retain explicit
continuous-health fallback cases. The retained current-health cost formulas are
checked against the safe forecast classification.

The synthetic compiled case reverses participant roles, matches optimizer
fitness, verifies no engine omissions beyond the declared source coverage, and
preserves package bytes. The copied executable runs the export in both orders
without checkout access. Browser checks exercise the exported snapshot,
buff-to-cast and cast-to-hit arithmetic, both participants and 320 px layout.
The build workflow includes the fixture in its runtime and browser gates.

The subsequent [health-cost correction](health-cost-readiness.md) solves
supported affine costs paid from the caster's health. Other continuously
changing costs and ranges still use periodic checks between known deadlines;
their moving boundaries must not be treated as fixed merely because an initial
value can be evaluated. Source and scenario schemas stay unchanged.
The engine fingerprint changes, separating optimizer cache entries and preserving
the saved-scenario model-change notice.

Formatting, 83 core regressions, retained source/catalog checks, all 170 Python
tests (162 passed, eight optional skips), web/combat/optimizer suites and the
rebuilt relocated executable passed. The complete desktop/mobile browser suite
passed, including both inventories, comparisons, optimization/apply/Undo,
sharing, exact scenario reproduction, fixed forms, sourced Riposte, control
resumption and the new synthetic cost/range fixture.

# Current-health cost readiness

Health-paying abilities can now forecast affordability when their cost is
affine in the caster's current health. Regeneration changes both available
health and the cost, so treating the cost as a constant gives the wrong deadline.
Selection and payment still evaluate the original expression at the actual cast
time. The model's existing one-health-point reserve stays binding.

## Threshold and safe scope

For cost `max(0, a*h+b)`, the eligibility test is
`h - max(0, a*h+b) >= 1`. When `a < 1`, this is monotone in health and its
threshold is `max(1, (b+1)/(1-a))`. With current health `h0`, positive effective
regeneration `r` and sufficient maximum health, the reference deadline is
`now + (threshold-h0)/r`. Forecasts round forward to nanoseconds and retain the
strict comparison at selection; no extra health or affordability tolerance is
introduced. A maximum-health cap below the threshold cannot enable the cast.

Supported expressions include own current/missing health and their fractions,
sums, products with at most one health-dependent factor, rank overrides and
supported buff-condition branches. The remaining factors can use the existing
event-stable stats, rank/level values and buffs. The engine derives coefficients
algebraically, without sampling a numerical derivative. It watches changes to
the coefficient pair rather than the continuously changing cost value.

Stat or buff changes recalculate coefficients, including changes on a target
whose ordinary stats enter a coefficient. Regeneration, healing multiplier and
maximum-health changes recalculate the deadline. Positive healing can enable a
cast immediately. Damage or another expense can invalidate a forecast; actual
health and the current cost are checked again before casting.

This step covers health costs paid from the caster's health. Costs paid from
another resource but depending on health, target-current-health inputs,
nonlinear expressions, slopes at least one and nonpositive regeneration retain
periodic checks. Unsafe/non-finite coefficient arithmetic also falls back to
ordinary evaluation. It cannot invent an unsupported effect when the actual
cost expression itself remains evaluable. Health-dependent range forecasts
remain separate work.

Normal ability priority, cooldown/recast/charge state, activation conditions,
range, action locks, control and survival still bind. Applied heals and changes
reuse the coalesced decision scheduler. Effects and deaths at the deadline run
before the decision. The scoring interval remains half-open.

## Retained formulas and reproduced difference

[The health-cost suite](../test/health-cost-readiness.janet) uses the unmodified
16.18.1 parser fixtures. Dr. Mundo W and Zac Q retain the coefficient
`0.079999998211860657`; Zac W/E retain `0.039999999105930328`. Independent
arithmetic checks each original cost AST against `h >= 1/(1-coefficient)` at
configured low starting health. This does not add their full champion handlers
or validate the rest of their kits.

The compiled/runtime/browser fixture carries the exact retained Mundo W cost
on an explicitly synthetic Annie ability on the same 16.18.1 patch. Maximum
health is configured to 10, starting health is 10% (1), and regeneration is
configured as `(1/(1-coefficient)-1)/0.337`, or `1.290156078` health per five
seconds. These stats and the one-true-damage effect are test inputs, not Annie
mechanics. Cast time is configured to 0.25 s with zero projectile travel. The
opponent holds with abilities and attacks disabled; both inventories are empty.

The synthetic package snapshot is
`3136589113f899d3f3bfdc46fb3c3eac58d9d43917ca8fe95320e4bace2e99ff`.
Comparison against engine revision `15e5a0e` uses identical compiled actors and
a scoring window ending at 0.592 s:

| Quantity | Previous engine | Corrected engine |
| --- | ---: | ---: |
| Cast starts | 0.350 s | 0.337 s |
| Health cost paid | 0.087224872 | 0.086956520 |
| Hit arrives | Outside window (0.600 s) | 0.587 s |
| Damage inside window | 0 | 1 |

The corrected cast occurs one nanosecond after the arithmetic reference. Its
lower cost follows from evaluating the same percentage at an earlier health
value. This is a software regression using a retained cost formula, not an
observed game fight. No observation is added to the combat ledger, and retained
source bytes remain unchanged.

## Checks

Independent arithmetic checks cover both roles, multiple slopes and regeneration
rates, constant terms, health fractions/missing health, negative coefficients
and zero-cost clamping, rank overrides, changing coefficients and buff branches,
rate changes/expiry, health caps, healing, same-time damage/control/death,
activation, action locks, recasts, charges, repeated spending and half-open
endpoints. Unrelated stat changes do not create a wake from unchanged
coefficients. Nonlinear, nonmonotone, target-health and overflowing-coefficient
cases explicitly exercise fallback. Traced and trace-free metrics agree.

The compiled fixture reverses actor roles, agrees with optimizer fitness and
verifies immutable package bytes. The copied executable runs the export in both
orders without checkout access. Browser checks verify the selected health
fraction, exact cast/impact times, actual percentage payment, health reserve,
both participants and 320 px layout. The fixture is included in the runtime and
browser build gates. Source and scenario schemas stay unchanged; the engine
fingerprint changes and preserves saved-scenario model-change notices.

Formatting, 83 core regressions, retained source/catalog checks, all 170 Python
tests (162 passed, eight optional skips), web/combat/optimizer suites and the
rebuilt relocated executable passed. The complete desktop/mobile browser suite
passed, including both inventories, comparisons, optimization/apply/Undo,
sharing, scenario reproduction, fixed forms, sourced Riposte, control resumption,
changing stat/buff readiness and the new health-cost fixture.

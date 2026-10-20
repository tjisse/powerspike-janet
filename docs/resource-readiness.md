# Resource recovery readiness

When an otherwise eligible ability lacks resources for a fixed cost, the engine
now predicts when its existing continuous regeneration can make that cost
affordable. It requests the ordinary combat decision at that deadline instead
of waiting for a later 50 ms poll. This covers mana/resource costs and health
costs, including the model's existing one-health-point reserve.

For current pool `p`, required pool `c` and positive regeneration rate `r`, the
reference deadline is `now + (c - p) / r`. A forecast is possible only if `c`
fits the pool's maximum. Mana regeneration remains the source's per-five-second
value divided by five. Health regeneration also uses the existing healing
multiplier. No regeneration value, cost or damage coefficient is changed.

## Eligibility and changing inputs

Fixed costs include numeric constants, rank/level values, level interpolation
and sums/products/rank overrides containing only those forms. This classification
is prepared once per fight. Costs depending on stats, current health, target
state, buffs or unresolved formulas retain periodic checks. In particular, the
change does not freeze a percentage-health cost at its starting value.

Forecasts are made through the existing protected selection path, after the
ability's cooldown/recast delay, activation, range/immunity and charge checks.
They reuse the [coalesced scheduler](control-resumption.md). A competing action
may postpone a wake until its action lock ends. Priority, control, survival and
the strict affordability comparison are all checked again before casting.

Rate and maximum-pool changes request a new decision for actors with a relevant
fixed-cost ability. This includes regeneration buffs expiring between polls and
changes to the healing multiplier. A positive applied heal similarly wakes a
health-cost actor. Damage or another resource expense can invalidate an earlier
forecast; the actual pool is checked again, so a prediction cannot grant free
resources or revive a dead actor. A recast can have a different fixed cost, and
charges retain their recovery/reuse gates.

Forecasts round upward to a nanosecond grid and advance by at least one
nanosecond. This keeps floating-point roundoff from putting a forecast just
before a nominal same-time damage/control event, and avoids repeated decisions
at one timestamp when a pool is still microscopically short. The cost check is
unchanged: there is no affordability tolerance or synthetic resource credit.

## Reproduced software difference

[The resource suite](../test/resource-readiness.janet) uses the retained 16.19.1
Annie Q subset and unmodified cached package
`1f774c1b65886f768cc2dca3628fe3ece2971a5719b4f3bfb862844e230c5928`.
Annie is level 1 with no items, runes or shards, 10% starting mana, ordinary
attacks disabled and Q as her only enabled priority. The opposing level-1
Annie holds position with attacks/abilities disabled. Distance is zero and the
window is 11.635 seconds.

Maximum mana is 418, starting mana 41.8, Q costs 60, and mana regeneration is
8 per five seconds. The independent recovery reference is
`(60 - 41.8) / (8 / 5) = 11.375 s`. With the existing 0.25 s cast time and zero
distance, its impact reference is 11.625 s.

A comparison against engine revision `96d80a9` uses identical compiled actors:

| Quantity | Previous engine | Corrected engine |
| --- | ---: | ---: |
| Q starts | 11.400 s | 11.375 s |
| Q hits | Outside window (11.650 s) | 11.625 s |
| Damage inside window | 0 | 61.538462 |
| Remaining mana | 0.416 | 0.416 |

The corrected trace is one nanosecond after the arithmetic reference because
of upward rounding. Damage changes because the hit now reaches the 30-MR
opponent inside the window. This is a software regression using retained source
inputs, not a new in-game observation or a measurement of live regeneration
cadence. It is not added to the observations ledger.

## Checks and remaining scope

Tests cover both pools and participant roles; four regeneration rates;
independent affordability arithmetic; rank/level/arithmetic costs; periodic
fallback for stat-dependent costs; repeated spending and floating-point
boundaries; priority and action locks; cooldown/activation/recast/charge gates;
rate boosts and expiry; zero-to-positive recovery; fractional healing multipliers;
maximum-pool changes; applied healing; same-time damage/death/silence; unreachable
costs and nonpositive regeneration; disabled/unlearned/out-of-range abilities;
changing percentage-health costs; and half-open scoring endpoints. The source-backed Annie case checks direct
simulation against optimizer fitness and unchanged package bytes.

The copied executable exercises that same exported scenario in both participant
orders without checkout access. Browser checks derive readiness from the
displayed mana/regeneration and actual Q cost, then verify each participant's
first cast and impact from 10% mana, including a 320 px layout.

The subsequent [health activation correction](health-activation.md) adds wakes
when discrete health changes satisfy a configured low-health rule.
The [movement correction](movement-readiness.md) now forecasts ordinary/fixed
ability range crossings and stopping distances. State-dependent costs and ranges,
resource-specific discrete recovery mechanics and missing champion handlers
still require separate work.
Source packages and scenario schema stay unchanged.
The engine fingerprint changes, separating optimizer cache entries and retaining
the saved-scenario model-change notice.

Formatting, 83 core regressions, retained source/catalog checks, all 170 Python
tests (162 passed, eight optional skips), web/combat/optimizer suites and the
rebuilt relocated executable passed. The complete desktop/mobile browser suite
also passed, including the new paired mana-recovery case, comparisons,
optimization/apply/Undo, sharing, fixed forms, Riposte and control resumption.

# Control expiry and action resumption

When a modeled control effect expires or an applied cleanse removes it, the
affected participant now requests a combat decision at that time, constrained
by its current action lock. Previously the expiry refreshed stats, but the
participant waited for its next periodic decision. This could delay an otherwise
ready attack or ability by almost 50 ms. Expiry now also checks the movement
strategy immediately. Short effects could start and end entirely between two
polls.

The expiry event carries the control kind and wakes only if its timestamp
matches that control's current deadline. An old event cannot release an extended
effect or wake a previously cleansed control. Zero-duration and immune effects
do not introduce expiry wakes. A cleanse requests a decision only when it
actually removes an active listed control.

Requests share one private pending deadline per participant. An earlier wake
supersedes the queued periodic decision; superseded events are skipped before
advancing combat time. Equal requests coalesce. The queued entries still count
toward the existing pending/processed-event limits, and cancellation checks
remain active. The deadline bookkeeping stays out of exported actor state.

The existing decision path enforces remaining controls, ability priority,
cooldowns, resources, activation conditions, range, cast locks and survival.
Expiry has priority 0, effects 10, death 20 and decisions 30. Reapplication or
death at the expiry timestamp therefore takes precedence over resumption.
Silence still permits ordinary attacks; root still permits stationary attacks
and spells. This change does not revise control permissions, tenacity policy,
cast interruption or the ability to activate a cleanse while controlled.

## Reproduced difference

The synthetic fixture in [the control suite](../test/control-resumption.janet)
uses retained champion stats as carriers for explicitly invented abilities.
The damage spell has a 0.173 s cooldown, 0.04 s cast time, zero travel and
10 true damage. The opposing ability applies silence at 0.013 s for 0.437 s.
Both participants hold position and disable ordinary attacks. The window is
0.5 s, with half-open endpoint scoring.

A software comparison against engine revision `1acbeb3` uses identical compiled
actors:

| Quantity | Previous engine | Corrected engine |
| --- | ---: | ---: |
| Silence ends | 0.450 s | 0.450 s |
| Second spell starts | 0.473 s | 0.450 s |
| Second spell hits | Outside window (0.513 s) | 0.490 s |
| Damage inside window | 10 | 20 |

The same fixture reverses participants and checks trace-free optimizer fitness
against direct simulation. Its manifest labels it synthetic. Neither its
timings nor its totals are champion accuracy evidence, and it is not added to
the observations ledger.

## Checks and remaining scope

The suite covers stun, charm, fear, airborne, suppression and silence; 13 ms
effects between polls; both actor positions; independent tenacity arithmetic
with the existing airborne/suppression exemptions; same-type refresh and
different overlapping controls; partial cleanse; cast locks; spell/attack
priority; cooldown and resource gates; silence/root permissions; immunity;
zero duration; exact movement resumption; simultaneous expiry coalescing;
unchanged cadence after resumption; same-time reapplication/death; endpoint
exclusion; immutable fixture bytes; and compiled/fitness equality.

The relocated executable checks the exported synthetic fixture without checkout
access, in both participant orders. The browser checks the silence timestamp,
expiry-to-cast arithmetic, both resulting hits, reversed roles and a 320 px
layout. The build workflow includes these checks.

Health/resource thresholds, range crossings and other changing conditions still
poll between known deadlines. Automatic form transitions, missing champion
control handlers and attack resets need separate work. Existing source and
scenario schemas remain unchanged; the engine fingerprint changes, separating
optimizer cache entries and retaining saved scenarios' model-change notice.

Formatting, 83 core regressions, retained source/catalog checks, all 170 Python
tests (162 passed, eight optional skips), web/combat/optimizer checks and the
rebuilt relocated executable passed. The complete existing desktop/mobile
browser suite and the new synthetic control fixture passed, including both
participant orders. The fixture supplies explicit display metadata and waits
for the chart's responsive resize before checking the mobile viewport.

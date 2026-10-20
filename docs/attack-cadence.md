# Ordinary attack readiness

The combat engine now checks an enabled ordinary attack at its known ready
time instead of rounding readiness up to a later 50 ms decision poll. This
corrects cumulative attack-cadence drift in practice fights, duels and item
optimization. Windup fractions and projectile delivery policies are unchanged.

Previously, at two attacks/second with a 30% windup, the engine could begin
the second attack at 0.55 seconds instead of 0.50. The first windup ended at
0.15; subsequent 0.05-second polls could reach a floating-point value just
below 0.50, then advance to 0.55. Other attack speeds also rounded their ready
times up to the next poll, even without that floating-point boundary case.
Small delays accumulated over successive attacks and could exclude a hit from
the configured fight window.

The next decision time is now the earlier of the normal check and the future
attack deadline, with the latter constrained by the current action lock.
It runs the existing decision path, rather than directly firing an attack:
ability priority, control, range, movement, resources, actor death and cast
locks still apply. There is one pending decision per actor; no parallel stream
of attack events is added. A deadline must be strictly in the future to avoid
same-timestamp retry loops.

## Reproduced effect

A software comparison against the previous committed engine, `c943115`, used
identical compiled actors: Human Nidalee at level 1, no items/runes/shards,
held at 300 distance from a 10,000-health practice target with zero armor/MR.
The window is 5.3 seconds. Attack speed is 0.638, assumed windup is 30%, and the
reviewed projectile speed is 2,500 units/s.

| Quantity | Previous engine | Corrected engine |
| --- | --- | --- |
| First hit | 0.590219 s | 0.590219 s |
| Second hit | 2.160439 s | 2.157618 s |
| Third hit | 3.730658 s | 3.725016 s |
| Fourth hit inside window | No | 5.292414 s |
| Ordinary damage | 174 | 232 |

This is an engine regression example, rather than a new measured game fight.
The independent reference for hit `n`, starting at zero, is
`(n + windup_fraction) / attack_speed + distance / projectile_speed`.
Damage changes because the fourth 58-AD attack now arrives inside the window;
no damage coefficient or champion stat was adjusted to fit the example.

## Remaining timing policies

Condition and movement checks still poll periodically between known deadlines.
The subsequent [ability readiness correction](ability-readiness.md) adds exact
cooldown, recast, charge and fixed activation deadlines. The
[control resumption correction](control-resumption.md) also wakes at expiry
and applied cleanse. [Attack resets](attack-resets.md) now wake when they shorten
a future readiness deadline. [Resource recovery](resource-readiness.md) now
forecasts fixed-cost affordability. Health activation thresholds, state-dependent
costs and range crossings retain their polling policy.
A known attack wake can also observe an eligible ability, which retains
priority over the attack.
Ordinary attacks are not allowed through a same-timestamp stun or death.

Attack period and windup still sample speed at attack start. A speed buff or
expiry does not retroactively rescale a period already in progress; the next
attack samples the then-current speed. Cast locks can postpone readiness, and
projectiles can remain in flight while another attack begins. Existing
half-open scoring excludes an impact exactly at the endpoint.

The model fingerprint already includes the engine source, so saved scenarios
retain their existing model-change notice and old optimizer values cannot
cross this correction. Cached package bytes and scenario schema stay unchanged.

## Checks and the unresolved Gnar review

[The cadence suite](../test/attack-cadence.janet) checks seven attack speeds,
stationary instant/projectile delivery, both actor positions, multiple periods,
independent start/impact arithmetic and trace/scoring parity. It covers exact
endpoint exclusion, ability priority at readiness, extended action locks,
same-timestamp stun/death, speed changes/expiry, the source-backed Nidalee
example, both optimizer perspectives and unchanged package bytes.

Relocated runtime checks inspect every ordinary Ahri and Viktor hit against
their independent cadence references. Browser checks reproduce four hits for
each Human Nidalee participant in the 5.3-second duel, alongside the existing
form, comparison, sharing, parry and mobile-layout regressions.

Gnar's Mini projectile remains unresolved. In the complete retained 16.19 record,
the root names `GnarBasicAttack3`, but neither
`Characters/Gnar/Spells/GnarBasicAttack3` nor its lowercase FNV-1a entry hash
`{5ac8f22e}` is present. Ordinary variants 1/2 and critical variants 1/2 do have
fixed 1,500-unit/s movement. That agreement does not establish delivery for
the missing named variant. This inspection adds no profile or combat observation;
the existing source hash is recorded in the
[Gnar manifest](../data/form-fixtures/16.19.1/gnar-manifest.json).

Formatting, core/source/catalog checks, all 170 Python tests (162 passed and
eight optional skips), web/combat regressions, relocated runtime checks with
the retained parry/level-scaling fixtures, and the complete desktop/mobile
browser suite passed.

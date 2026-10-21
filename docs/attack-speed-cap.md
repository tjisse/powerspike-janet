# Baseline attack-speed cap

The retained 16.19.1, 16.20.1 and 16.21.1 models use a baseline cap of
**3.0 attacks/second**.
The previous generic 2.5 cap clipped high-attack-speed builds and temporary
attack-speed buffs too early, changing attack windups, cadence and fight totals.

## Source and scope

[Riot's 2025.S1.3 patch notes](https://www.leagueoflegends.com/en-us/news/game-updates/patch-2025-s1-3-notes/),
published 4 February 2025, explicitly raised the baseline from 2.5 to 3.0.
[The retained review](../data/attack-fixtures/16.19.1/reviewed-speed-cap.jdn)
records that named value, its reference and the supported model patch. It selects
the ordinary Summoner's Rift baseline; the same article has a separate ARURF
limit which does not apply to these simulations.

This is a correction to the published baseline. Sub-millisecond cap precision,
server tick quantization, attack-speed changes during an attack and special
champion/rune cap overrides still need separate evidence and handlers. No
in-game measurement is admitted. The downloaded 16.19 global client-data dump
did not expose a named attack-speed or minimum-attack-delay field, so this
correction is bound to Riot's published value and does not claim a raw server
constant or newly measured timing precision.

The supported patch list is explicit. Other patches keep their existing declared
limits. Exceptional declared limits, such as a synthetic 1.5 or 90 cap, are
preserved. Generic 2.5 values in older supported data are reinterpreted as the new
baseline when calculating stats or loading a kit. Special champion attacks,
passives, transformations and cap-changing effects still have their existing
coverage notes until their own handlers are supported.

The 16.20/16.21 follow-up reviewed Riot's [26.20 notes](https://www.leagueoflegends.com/en-us/news/game-updates/league-of-legends-patch-26-20-notes/)
and [26.21 notes](https://www.leagueoflegends.com/en-us/news/game-updates/league-of-legends-patch-26-21-notes/).
Their Summoner's Rift changes announce no replacement global baseline. Applying
the published 3.0 value to these two retained patches is an explicit continuation
of that rule, not a new measurement or a recovered server constant. The review
records both references and dates; later patches remain outside its scope.

## Shared behavior

`attack-limits.janet` supplies the same cap to curated-core stat calculations,
new normalization, cached-kit repair and both scenario actors. The engine's
existing temporary-stat logic then uses the actor's cap for effects such as
Lich Bane's attack-speed bonus. Uncapped speed stays available separately so
priming, consumption and expiry can restore the correct capped speed.

For a raw speed of 2.9 attacks/second and a temporary increase of 0.25, the
temporary speed is now capped at 3.0; consumption restores 2.9. At the old cap
both values were clipped to 2.5. When a character's current windup fraction is
the existing assumed 30%, a capped ordinary attack at zero distance launches
after 0.1 seconds, with subsequent starts one third of a second apart. The
configured attack period still samples speed at attack start.

The short-window browser case also exposed a form constraint: the server and
saved scenarios accept arbitrary finite durations from 0.5 to 120 seconds, but
the HTML controls required half-second increments. A valid 0.8-second saved
fight displayed a result and then failed native form validation on rerun. Both
duration controls now accept fractional seconds throughout the server's range.

The legal six-item Mini Gnar case in the regressions has 3.10625 uncapped
attacks/second at level 18 and reaches the new 3.0 cap. In a 1.2-second attack-only
window, four ordinary attacks arrive; the old 2.5 cap allowed three. This case
checks the modeled ordinary attacks and item stats, with Gnar's unsupported
passive and ability effects still excluded.

Snapshot bytes are unchanged. Loading the cached seed applies the correction
without downloading data or creating a replacement snapshot. Obsolete 2.5-cap
assumption text is removed while windup and projectile assumptions remain.
The review and shared limit module join the combat-model fingerprint, keeping
older saved-model notices and optimizer cache separation intact.

## Checks

`test/attack-limits.janet` checks patch bounds, declared alternative caps,
idempotent cached repair, all 173 retained champion caps, below/above-cap stat
totals, exact ordinary/critical impact boundaries, both duel participants,
unchanged snapshot bytes and optimizer/direct parity around a locked high-speed
inventory. It preserves the bundled seed's restriction to curated optimizer
purchases. The existing scenario checks cover saved-model compatibility notices.

`test/lich-bane.janet` checks the temporary bonus below and across the new cap,
first windups, consumption and expiry while retaining its explicit synthetic
2.5-cap control. The relocated runtime checks high-speed HTTP export and CLI
reproduction without access to the source tree. The browser checks displayed
attack speed, both timelines, explicit reruns and mobile layout.

The correction passed 83 core cases, retained source/catalog checks and 170
Python tests (eight optional skips). The web gate passed 45 frontend cases and
the full combat/optimizer suites. Standalone runtime and concurrency checks
passed, with 427 health probes and a maximum observed local latency of 0.030
seconds against a two-second limit. The complete browser gate passed, including
retained Riposte, control, changing-readiness and health-cost fixtures, both
capped timelines and fractional-duration reruns/native forms. Formatting,
Python syntax and Git diff checks passed.

The model fingerprint at this correction is
`e96375e739815cb01c1560fde1a442d659ccb432aafb59c753c6ab86d0ce753c`.

## Latest-patch follow-up

`test/latest-attacks.janet` now reconstructs parser-7 snapshots carrying the old
2.5 cap and checks fresh/loaded agreement on both latest patches. The retained
champions' real base attack speed and ratio feed synthetic stat-bonus stress
cases below, at and above the cap. Those bonuses are laboratory inputs, not
claims about newly reviewed items or champion abilities. Ordinary and critical
cadence, half-open impact boundaries, temporary bonus recapping and expiry are
checked independently. Both compiled combatants carry the same reviewed cap;
direct simulation and optimizer scoring still agree.

The eight exported saved scenarios continue to check ordinary and empowered
timing in the relocated executable, now also asserting that snapshots with an
old generic cap produce actors capped at 3.0. The UI import checks verify that
obsolete 2.5-cap assumptions are removed while remaining timing omissions stay
visible. `test/attack-limits.janet` checks all three supported patch identifiers,
preserved explicit alternative caps and abstention on unreviewed patches.

# Survival in item comparisons

Pinned item comparisons now show the player's health remaining and survival
alongside damage, DPS and gold. A component that increases damage can still
cause the player to lose the configured fight; the comparison now makes that
tradeoff visible without opening each build separately.

For one trial, survival reads "Survived" or "Defeated", with the defeat time
when applicable. A survival change also appears above the table, including on
mobile. The difference row names the change without declaring an overall best
build. Health is measured at the end of the configured window, matching the
simulation metric rather than the chart's first-death endpoint.

For multiple trials, health is the mean across all trials and survival reports
the number of trials survived. Differences report additional/fewer surviving
trials, not a probability of winning a live game. A first-trial death is not
substituted for the aggregate outcome. Fractional health below one is shown as
"<1" instead of rounding a surviving participant to zero. Missing metrics are
shown as unavailable.

The comparison is now available beneath duel results as well as practice
results. The extra columns stay within the comparison's horizontal scroll area.
It is named and keyboard-focusable, with a visible focus outline and a mobile
scroll hint. Build names remain fixed while scrolling. The survival-change
summary stays visible without horizontal scrolling. The existing Rift HUD,
colors and item controls are retained.

## Reproduced comparison

The frontend/browser checks use the retained 16.19.1 snapshot
`1f774c1b65886f768cc2dca3628fe3ece2971a5719b4f3bfb862844e230c5928`.
Level-1 Annie fights another level-1 Annie for one second at distance zero.
Only Q is enabled in either priority, attacks and movement are disabled, and the
player starts at 10% health. Runes and shards are empty. The pinned build has
Amplifying Tome; the current build swaps it for Ruby Crystal. Both cost 400 gold.

| Player outcome | Tome | Ruby Crystal |
| --- | ---: | ---: |
| Damage | 73.846154 | 61.538462 |
| Health left | 0 | 10.561538 |
| Survival | Defeated at 0.25 s | Survived |
| Gold | 400 | 400 |

The existing simulation gives these outcomes before and after the presentation
change. The new table exposes the health/survival tradeoff that the old
damage/DPS/gold table omitted. This is a software/UI regression using declared
fight inputs, not measured game evidence. Combat formulas, source packages and
the engine fingerprint are unchanged.

A second case runs four trials with seed 6 and a 50% opponent Q hit chance. The
pinned build dies in trial zero, but survives three of the four trials; its mean
health is 42.825. Ruby Crystal survives all four, with mean health 56.715385.
The table reports "3 / 4 trials" versus "4 / 4 trials", a difference of one
surviving trial. It does not report the representative trial as the full result.

## Retained range audit

Before this improvement, the developer audit examined the normalized Q/W/E/R
range expressions in every retained champion kit with ability fixtures:

| Source group | Kits | Ability slots | Fixed ranges | Health-dependent ranges |
| --- | ---: | ---: | ---: | ---: |
| 16.18.1 parser fixtures | 7 | 28 | 28 | 0 |
| 16.19.1 combat fixtures | 3 | 12 | 12 | 0 |
| 16.19.1 Fiora fixtures | 1 | 4 | 4 | 0 |
| Total | 11 | 44 | 44 | 0 |

[The audit command](../scripts/audit_range_timing.janet) verifies the retained
source hashes before normalizing and classifying these ranges:

```
JANET_PATH=build/web-modules build/janet scripts/audit_range_timing.janet
```

The groups include Annie/Ahri on both patches, Garen, Aatrox, Dr. Mundo, Zac,
Kha'Zix, Viktor and Fiora. Passives and unmodeled alternate spells are outside
the count. Fixed-form handlers currently provide ordinary attacks without
executable champion abilities; the initial Annie subset also uses fixed range.
The audit describes retained inputs, not every League spell or future provider
snapshot. It leaves health-dependent range forecasts on their declared fallback
and avoids adding a scheduler extension with no retained consumer.

Frontend checks cover the equal-gold tradeoff, aggregate outcomes that differ
from trial zero, health/difference formatting and identical survival. Browser
checks exercise pinning, item swaps in both directions, defeat time, aggregate
trial counts, the responsive summary, keyboard focus and horizontal scrolling
without viewport overflow.

## Validation

Passed `make test-web` (35 frontend cases plus the existing web, combat and
optimizer checks), the rebuilt executable's relocated runtime checks, and
`make format-check`. After adding the comparison to the duel results, the
35 frontend cases and relocated runtime gate passed again on the final build.

The full Playwright gate passed, including the paired interface, source-backed
Riposte fixture, synthetic control and changing-value fixtures, and retained
health-cost fixture. The new comparison case passed at desktop width and at
736, 390 and 320 pixels, including native keyboard scrolling. Desktop and mobile
screenshots were visually reviewed. The source-hash range audit reports all
44 retained ability slots as fixed-range expressions.

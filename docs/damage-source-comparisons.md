# Damage-source comparisons

The item comparison now includes an expandable **Damage by source** table in
practice and duel results. It shows pinned damage, current damage and their
difference for each source, with the largest absolute changes first. Ties use
the source ID for stable ordering. A source present in only one build shows
zero for the other build. Total damage remains visible beneath the rows.

The table uses the existing engine's `damage-breakdown`, which already averages
each source across every configured trial. It does not reconstruct an average
from the representative trace. Both sides use the same fight window and seeds,
including when one champion dies before the configured window ends. The source
attribution describes simulated damage; it does not isolate the causal value
of one item's stats or replace the survival/gold comparison.

Stat bonuses and damage modifiers remain attributed to the sources they affect.
The table explains this so that an AP increase is not presented as a separate
item proc. Actual item and rune damage triggers retain their own rows. Names
come from the result's exact package and modeled ability/trigger settings;
unknown sources retain their escaped identifier. The initial Q/W subset uses
slot labels where it lacks a localized ability name.

Values use two decimal places. Nonzero values below 0.01 are shown as `<0.01`,
with the appropriate sign for differences. A rounding note explains small
displayed-total differences. Missing attribution is unavailable, distinct from
two empty breakdowns. The native details element supports keyboard activation
and retains its expansion when results update. Its named table region supports
keyboard/horizontal scrolling and keeps source names fixed on narrow screens.
Saved/shared comparisons reproduce the source table along with the main table.

## Retained regression examples

Level-1 Annie uses only Q and ordinary attacks against the default practice
target for three seconds at distance zero, holding position. Four trials use
seed 6 and 50% hit chance. Pinned Amplifying Tome is replaced with Long
Sword, using the retained initial 16.19.1 snapshot. No runes or shards are set.

| Mean damage | Tome | Long Sword | Change |
| --- | ---: | ---: | ---: |
| Ordinary attacks | 34.722222 | 41.666667 | +6.944444 |
| Q | 13.333333 | 11.111111 | −2.222222 |
| Total | 48.055556 | 52.777778 | +4.722222 |

The corresponding first-trial totals are 55.555556 and 66.666667, so substituting
trial zero would fail the regression. Source sums reconcile with both mean
totals before presentation rounding.

The retained Riposte browser fixture supplies a second example: level-1 Ahri
with Lich Bane fights a stationary Fiora for two seconds at distance 100, with
opponent attacks and abilities disabled. Compared with an empty pinned
inventory, Lich Bane's proc contributes 64.20 displayed damage in its own row.
Q and ordinary attacks also change. The browser checks the proc against the
player's damage events, verifies zero on the unequipped side and checks mobile
layout. These are source-backed software regressions, not new game captures.

Combat formulas, source packages, save formats and engine identity are unchanged.

## Validation

Passed `make test-web` with 41 frontend cases and the existing web, combat and
optimizer gates, plus the rebuilt executable's relocated runtime gate. Frontend
cases check averaged source sums, values differing from trial zero, sources
present on only one side, retained item/rune names, stable sorting, fractional
formatting, escaped identifiers and missing versus empty attribution.

The full Playwright gate passed, including saved/shared source tables, keyboard
activation and scrolling, expansion after result updates, 736/390/320-pixel
layouts, the paired interface and all retained browser fixtures. The Lich Bane
case checks its row against player damage events. Desktop, mobile and proc
comparison screenshots were visually reviewed. Formatting and diff checks pass.

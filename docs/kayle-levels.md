# Kayle's fixed-level attack type and range

Practice and duel scenarios now resolve Kayle's ordinary attack type and range
from the selected level on the retained 16.19.1 snapshot:

| Level | Attack type | Attack range |
| --- | --- | --- |
| 1–5 | Melee | 175 |
| 6–15 | Ranged | 525 |
| 16–18 | Ranged | 625 |

Both participants, item tooltip calculations, comparisons and optimizer fitness
use the same compiled actor. Blade of the Ruined King's supported Mist's Edge
effect now uses its source melee or ranged rate for Kayle instead of excluding
the conditional damage. Champion Details shows the actor's attack range.
An item from a stat-only catalog remains stat-only; this handler does not add
effects that the loaded item does not support.

## Source boundary

[The retained manifest](../data/attack-fixtures/16.19.1/kayle-manifest.json)
identifies the complete character source and the matching localization excerpt,
including original and excerpt hashes. The complete source hash matches the
character source already identified by the catalog receipt. The root supplies
175 range and both purchase identities. The passive supplies the level 6 and
16 thresholds and 525/625 ranges; matching tooltip tokens identify Arisen and
Transcendent. Riot's [11.10 patch notes](https://www.leagueoflegends.com/en-us/news/game-updates/patch-11-10-notes/)
also document the level-16 range increase to 625. The ranged identity at Arisen
is the interpretation of these source records; range alone does not classify
other champions.

The tooltip ties ascension to gaining levels and spending skill points. The
supported projection requires all skill points to be assigned at level 6 or
higher, and rejects underallocated scenarios with an actionable message. It
does not infer ascension from ultimate rank: a valid fully allocated build with
no ultimate rank still becomes ranged. Delayed skill-point spending and
level-ups during a fight are outside this projection.

Only ordinary attack type and range are added. Divine Ascent's attack-speed
stacks, movement bonus and fire waves remain excluded, as do unsupported
abilities and empowered attacks. Simulation details retain these omissions.
Ranged projectile travel still has its existing zero-travel assumption, and
windup remains the existing 30% assumption. No new replay measurements or
combat-verification admissions result from source-derived regression tests.

The catalog keeps its original both-identities metadata and baseline range.
Compilation creates a level-specific copy, leaving snapshot bytes unchanged.
The handler applies only to Kayle on 16.19.1; other patches and transforming
champions retain their existing treatment. Source loading validates hashes and
reviewed values during module import, which also embeds the projection in the
standalone executable. The source files and handler contribute to model identity
so cached fitness results cannot silently survive a mechanics change.

## Checks

`test/attack-styles.janet` checks every level, both participant roles, exact
range boundaries, independent current-health on-hit arithmetic, numeric item
tooltips, displayed range, direct/fitness equality, an actual optimizer search,
unspent-point rejection, independence from ultimate rank, patch isolation and
immutable cached packages that predate attack-style metadata. The other four
transforming champions continue to abstain from conditional on-hit damage.

`test/runtime.py` exercises the packaged HTTP and CLI paths at levels 1, 5, 6,
15, 16 and 18 from an empty relocated directory. `test/browser.py` changes both
participants' levels in a held-position duel: at 200 units a level-5 Kayle cannot
attack, while a level-6 or level-16 Kayle can. It checks range details and layouts
down to 320 pixels. The sourced item arithmetic remains in the Janet fixture
suite rather than assuming the bundled stat-only catalog has that effect.

Core/source checks, all 170 Python tests (162 passed, eight optional skips),
web/combat regressions and the full packaged browser suite passed. The relocated
runtime passed with both the bundled seed and the published v0.18.0 seed,
including the separate source-backed parry fixture.

# Abilities on 16.20 and 16.21

Selecting 16.21.1 in v0.21.0 could leave the default Annie/Garen fight using
only basic attacks, even with both ability switches enabled. Source downloads
were present. The expression reader accepted stat enums only for CommunityDragon
16.17 through 16.19, so AP and AD formulas on the newer patch became unresolved.
Downloading the same patch again did not fix that model limitation.

## Reviewed scope

The retained [16.20.1](../data/parser-fixtures/16.20.1/manifest.json) and
[16.21.1](../data/parser-fixtures/16.21.1/manifest.json) fixtures contain both
champions' complete character records and Data Dragon ability descriptions,
plus matching localization excerpts. Each manifest records original response
hashes, retained file hashes and the retrieval date. For example, the matching
sources are [Annie's 16.21 character record](https://raw.communitydragon.org/16.21/game/data/characters/annie/annie.bin.json?powerspike=1)
and [Garen's 16.21 character record](https://raw.communitydragon.org/16.21/game/data/characters/garen/garen.bin.json?powerspike=1).

These records retain the reviewed stat meanings: omitted/zero `mStat` is AP,
2 is AD and 12 is health. Formula modes 0, 1 and 2 select total, base and bonus
respectively. Annie's shared Q/W/E/R calculation trees are identical to the
retained 16.18 trees. Garen's Q still combines `BaseDamage` and `tADRatio`
with total AD; W combines `BaseShield` and `ShieldHealthRatio` with bonus HP.
This enables those three stat mappings on the two reviewed patch families.
Other stat enums and later patch families remain unresolved until reviewed.

The Q handler now applies Garen's source-defined total damage to his next
attack, replacing its ordinary damage and resetting its readiness, on both
new patches. Annie's learned-R penetration also uses the matching source values.
No old patch's numeric ability values are substituted for the selected patch.

For a rank-5 tooltip context with 100 AP, 150 total AD and 1,000 bonus HP,
the source formulas give approximately 340 Annie Q damage, 310 Annie W damage,
240 Annie E shield, 375 Garen Q total attack damage and 325 Garen W shield.
These are pre-mitigation values with the original source float coefficients.

This is a scoped simulation correction, not a claim of complete champion kits
or independently measured game outcomes. Annie's passive stun, E retaliation
and Tibbers behavior, and Garen's spin, execute, silence, W damage reduction
and passive behavior still have omissions. The supported portions continue to
use existing timing, movement and targeting assumptions. The existing simulation
details continue to describe model omissions. Parser revision differences now
have a [warning and explicit local reparse action](patch-reparse.md).

## Refreshing existing caches

Parser 7 applies these mappings when patch data is normalized during a fetch.
After upgrading, use **Reparse saved data** in the parser-mismatch warning to
normalize retained raw sources locally. The existing **Refresh patch data**
button remains available to download the exact patch's sources again. Both
actions create a normalized snapshot and publish its current pointer last.
There is no automatic cache migration or new formula-repair process on load.

Old snapshot bytes and hashes stay intact, and saved scenarios remain pinned
to their selected revision. Reopen a refreshed patch to compare new scenarios
with its updated ability data. The warning is limited to parser compatibility;
verification records and broader model diagnostics remain in developer tools.

## Regression checks

`test/latest-patch.janet` checks source hashes, an explicit fetch of the retained
source responses, fresh/fetched formula and effect parity, representative
damage/shield values, preserved exclusions, repeated normalization, both default
combatants casting, reversed combat and optimizer agreement, explicit unsupported
boundaries and immutable old package bytes. Its `legacy-package.jdn` fixtures
were generated with the unmodified parser 6 before this correction. They are
frozen regression inputs rather than raw game captures and retain the original
rejected AP/AD formulas. Loading them leaves those old parsed formulas unresolved;
the explicit fetch produces a distinct parser-7 snapshot.

`test/latest_patch_browser.py` starts the standalone binary with the explicitly
refreshed snapshots. It checks both champions' casts, timeline source icons,
exact reruns, changing patch through the selector and mobile widths down to
320 px. It is included in the release/CI browser gate via
`--latest-patch-fixture`. The parser-version regression also preserves correct
interpolation formulas previously compiled by parser 6.

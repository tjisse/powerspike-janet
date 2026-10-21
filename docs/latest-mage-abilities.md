# Ahri and Viktor on 16.20 and 16.21

The latest-patch review now extends beyond Annie/Garen to Ahri and Viktor.
Their existing reviewed multi-hit, empowered-attack and recast handlers stopped
at 16.19.1. A fresh 16.20/16.21 download could therefore omit Ahri's repeated
fox-fires and Spirit Rush recasts, or Viktor's empowered Q attack and storm ticks.

## Matching sources and scope

The [16.20.1](../data/combat-fixtures/16.20.1/manifest.json) and
[16.21.1](../data/combat-fixtures/16.21.1/manifest.json) manifests retain both
complete character records, Data Dragon ability descriptions and the eleven
relevant matching localization strings. Original response hashes, retained
file hashes and retrieval times are recorded separately. The localization
files are excerpts; the original hash identifies the full response.

The reviewed Ahri Q/W/R and Viktor Q/R spell records are unchanged from the
retained 16.19.1 records except Viktor Q's 16.21 shield calculation and AP ratio.
All eleven localization strings are unchanged. The handlers continue to read
the selected patch's own variables, cooldowns, ranges and costs. No formula
reader revision or new enum mapping is needed.

Viktor's ordinary Q shield at level 18 and 100 AP is **165 on 16.20**, from
140 + 0.25 AP, and **150 on 16.21**, from 130 + 0.20 AP. Both the expression
and actual cast trace are checked. The augmented shield remains unresolved.

The expanded handlers model Ahri Q's magic/true phases, W's first fire and two
reduced fires, R's three casts with the source recast delay and first-cast-only
resource cost; Viktor Q's missile and four-second replacement attack window;
and R's initial hit plus source-defined ticks. The ordinary shield remains
the source-parsed effect. At 100 AP, rank-one Ahri Q deals 85 per phase and
W deals 80 + 32 + 32 before mitigation. At rank-three R, Viktor deals
300 initially and six 180-damage ticks when the target remains in the storm.

This remains a scoped simulation. Orb turning, individual fox-fire origins,
Spirit Rush movement/takedown resets/healing, evolved Viktor effects, storm
redirection/extensions and passive triggers remain excluded. Viktor's empowered
attack retains its declared zero-travel assumption. Ordinary attack timing,
projectile and attack-speed-cap profiles are not extended by this ability
review. No new in-game timing or damage measurements are claimed.

## Existing data and checks

The existing combat-model semantic path applies the reviewed handlers to
parser-7 snapshots with retained spell records. Snapshot bytes and identities
remain unchanged; the combat model identity changes. Older parser snapshots
still require the explicit **Reparse saved data** or **Refresh patch data**
action. There is no new migration, repair path or automatic provider download.

`test/latest-mages.janet` uses the actual fetch/publication path with retained
responses. It checks hashes, fresh/loaded parity, repeated normalization,
reconstructed pre-handler parser-7 snapshots, immutable bytes and current
pointers, isolated multi-phase/recast/empowered/tick execution, patch-specific
shield values, actual casts in both matchup positions and parity with optimizer
scoring. Future patches and remaining conditional/passive effects keep their
unsupported boundaries. `test/latest-patch.janet` continues to check the
Annie/Garen refresh regression using the same fixture-provider helper.

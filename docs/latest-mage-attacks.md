# Mage ordinary attacks on 16.20.1 and 16.21.1

Ahri, Annie and Viktor now use their reviewed ordinary attack profiles on both
latest retained patches. The profiles previously stopped at 16.19.1, leaving
newer snapshots with a 30% windup assumption and zero ordinary projectile travel.
This changed which attacks arrived within short simulated fight windows.

## Source review

The [review receipts](../data/attack-fixtures/latest-mage-timing.jdn) bind each
champion and patch to the complete retained character source and its existing
manifest hash. Ahri/Viktor records are in `data/combat-fixtures`; Annie records
are in `data/parser-fixtures`. No duplicate raw responses are introduced.

All three champions' primary, alternate and critical attack spell objects,
ordinary/critical attack slots, alternate identities and purchase identities
match the reviewed 16.19.1 records. Ahri's named 20% windup and Annie's 1,500
projectile speed remain corroborated by [Riot's 13.22 notes](https://www.leagueoflegends.com/en-sg/news/game-updates/patch-13-22-notes/).
This is a bounded interpretation of matching source records, rather than a
general formula inferred from an arbitrary windup offset or a new timing capture.

| Champion | Ordinary projectile speed | Windup fraction |
| --- | ---: | ---: |
| Ahri | 1,750 | 20%, reviewed named value |
| Annie | 1,500 | 30%, existing assumption |
| Viktor | 2,300 | 30%, existing assumption |

Annie's legacy `missileSpeed` still says 1,200 while all three fixed missile
movement records say 1,500. Her explicitly reviewed conflict resolution applies
on these two patches. The generic projectile parser continues to reject
conflicting fields. Every profile is guarded by the selected patch's source
hash, and cache keys include both champion and patch.

## Behavior and boundaries

At one attack/second, Ahri at 350 distance hits at 0.4 seconds, Annie at 300
distance hits at 0.5 seconds, and Viktor at 500 distance hits at approximately
0.517391 seconds. The calculation is windup divided by attack speed plus release
distance divided by projectile speed. Travel does not delay the next attack's
readiness; an impact exactly at the fight endpoint remains excluded.

Viktor's empowered Q remains a separate replacement attack with the existing
four-second window and explicit zero-travel assumption. Its following ordinary
attack travels at 2,300. Missing missile movement on Q's buff is not evidence of
measured server delivery. Empowered windup, critical interactions, special
variants and movement during flight retain their existing coverage limits.

This review does not extend attack-speed-cap rules, add other champions or
change Spellblade consumption policy. Later patches do not inherit these
profiles without matching review. Player-facing simulation details describe the
remaining assumptions; hashes and verification records remain developer details.
The subsequent [baseline-cap follow-up](attack-speed-cap.md#latest-patch-follow-up)
extends the published 3.0 baseline to these two explicitly reviewed patches.

## Saved data and validation

The existing model projection supplies profiles when loading retained snapshots.
It does not reparse formulas, rewrite package bytes, move current pointers or
download replacement data. Older parser formulas still use the explicit refresh
or reparse action. Model identity includes the review receipts and their bound
source hashes, keeping saved-model notices and optimizer cache separation intact.

`test/latest-attacks.janet` exercises actual fetch/publication with retained
responses, all reviewed variants, patch-specific caches, fresh/cached parity,
reconstructed parser-7 snapshots without attack metadata, immutable bytes/current
pointers, multiple attack speeds, critical hits, exact impact boundaries, both
combatants and optimizer/direct agreement. It separately checks empowered Q and
the following ordinary hit. The existing 16.19.1 checks remain in
`test/attack-projectiles.janet`.

The runtime fixture exports eight scenarios from snapshots without profiles.
`test/runtime.py --latest-attack-fixture` copies the executable and snapshots into
an empty directory and checks the same impact times, actor fields and metrics.
This checks that profiles for every reviewed patch are embedded in the executable
and require no repository files at runtime. It is part of `make test-runtime`.
`test/latest_attack_browser.py` imports the same eight saved scenarios through
the UI, checks their ordinary/empowered impact times and exact snapshot identity,
and checks widths down to 320 px. The CI browser gate includes this fixture.

Validation passed `make test test-web test-runtime`, including source/catalog
checks, Python and combat/optimizer regressions, all eight relocated cases and
concurrent HTTP checks. The latest-attack and latest-patch browser checks passed.

# Melee/ranged item scaling

Attack range is a distance, not a melee/ranged identity. The simulator previously
treated every champion with more than 300 attack range as ranged. This applied
Blade of the Ruined King's ranged on-hit rate to Lillia despite her melee
identity and 325-unit range.

The retained 16.19.1 CharacterRecords now supply `purchaseIdentities` for this
classification. Of 173 champions, 89 have only the melee identity, 79 only the
ranged identity, and five have both. Lillia and Rakan are melee in these records.
[Riot's patch 12.22 notes](https://www.leagueoflegends.com/en-us/news/game-updates/patch-12-22-notes/)
independently document both champions' change to melee. Historical patch notes
confirm that interpretation; current numerical item rates come from the
selected snapshot's item record.

The catalog importer preserves the identity. Newly fetched snapshots derive it
from their own CharacterRecords. Loading older 16.19.1 snapshots fills a missing
identity from the matching, hash-checked retained records without changing the
snapshot bytes. Another patch cannot inherit this classification. The standalone
executable serializes the retained identities during its build, so an upgrade
does not require source-tree files or a provider request.

Lillia now uses the source melee rate (approximately 9%) for Mist's Edge; a ranged
champion such as Ahri uses approximately 6%. Both duel participants, direct
simulations, optimizer fitness and item tooltips share the same identity. Attack
range remains independent and does not change when selecting the proc rate.
Increasing melee range therefore cannot silently turn an actor into a ranged
champion.

Elise, Gnar, Jayce, Kayle and Nidalee have both identities. Their current attack
type depends on form or level, which this model does not yet reconstruct. The
compiler keeps it unknown and excludes Mist's Edge's conditional on-hit damage;
the item's supported ordinary stats still apply. Simulation details explain the
omission. The tooltip retains a readable percentage description without a
fabricated 6%/9% value or an internal template token. Other champions with missing
attack-type data follow the same explicit exclusion.

This change corrects classification; it does not implement transformations,
Kayle's level transitions or new admitted combat observations. Source hashes and
model diagnostics remain developer information. Model identity includes the
handler and catalog provenance, invalidating prior fitness cache entries and
preserving the saved-scenario compatibility notice.

`test/attack-styles.janet` checks the full classification counts, individual
exceptions, patch isolation, missing and invalid identities, immutable cached
snapshot repair, independently calculated on-hit damage, both participants,
tooltip values, direct/optimizer equality and abstention for all five changing
champions. The standalone runtime checks Lillia, Ahri, Elise and Kayle through
the packaged HTTP and simulation interfaces.

Core/source/Python checks, frontend and combat regressions, relocated runtime
and packaged Chromium checks passed. The new executable also passed the runtime
suite using the signed v0.17.0 RPM's older seed in an empty directory. This
exercises an actual cached-data upgrade without provider downloads.

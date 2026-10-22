# Item, rune and fixed-form coverage on 16.20 and 16.21

The release follow-up extends four existing pieces of combat coverage to
**16.20.1 and 16.21.1**. Previously those patches could be selected while item
procs, several rune effects, Kayle's ascension and fixed-form selection remained
outside their reviewed scope. This changes the existing handlers and their
retained evidence; the expression parser stays at version 7.

## Items

Sheen, Lich Bane, Trinity Force, Essence Reaver, Iceborn Gauntlet, Hextech
Alternator, Blade of the Ruined King, Nashor's Tooth and Luden's Echo use the
selected snapshot's source calculations. Their handled calculations and named
values agree with the retained 16.19 review on both added patches. Item records,
Data Dragon entries, localized tooltips and referenced ownership groups are
retained under `data/item-fixtures/<patch>/`, with full-response hashes and
separate excerpt hashes.

The review also establishes **total critical chance, stat mapping 8/0**, for
Essence Reaver. Its `CritChanceMultiplier` term, raw `mFlatCritChanceMod` and
Data Dragon's fractional critical chance agree. With 100 base AD, the retained
Spellblade formula gives 125, 137.5, 162.5 and 175 damage at 0%, 25%, 75% and
100% critical chance. Other new stat mappings remain unresolved. Checks keep
base AD distinct from total/bonus AD, exercise cooldowns and component/upgrade
gold limits, and check every supported Lich Bane lifecycle case on all three
patches. Blade of the Ruined King's contextual tooltip uses the same melee or
ranged percentage as combat.

Existing omissions still apply, including item slow/movement/mana-restoration
effects and Luden's single-opponent echo assumption. This review adds no replay
or Practice Tool measurement of proc ordering.

## Runes and shards

Matching perk records, styles and localized descriptions are retained under
`data/rune-fixtures/<patch>/`. Records are selected by perk ID, including the
unnamed flat-health shard whose source key changed. The handled calculations
and effect amounts agree with 16.19; Electrocute's changed visual-resource map
does not change its calculation.

Scorch, Transcendence, Coup de Grace, Cut Down and Last Stand now pass the
reviewed-patch guard. Electrocute retains its existing distinct-action handler.
Checks cover threshold boundaries, true-damage and non-champion exclusions,
Scorch's delay, level-gated haste, adaptive force and shard values. The bundled
matching records also serve older packages that lack a shard array, without
writing into those packages. Other rune effects remain excluded and reported.

## Kayle and fixed forms

Kayle's matching passive and root records retain the reviewed attack identity,
skill-point requirement and ranges: 175 before level 6, 525 at levels 6–15 and
625 from level 16. The source profiles are now keyed by patch. Ascension's
attack-speed stacks, movement and fire waves remain excluded.

Nidalee Human/Cougar, Jayce Hammer/Cannon, Elise Human/Spider and Gnar Mini/Mega
now load matching-patch sources and pass the same explicit semantic assertions
as the original 16.19 profiles. Range, attack type, Hammer resistances, Spider
Queen damage/healing and Gnar's level-scaled form stats keep their existing
scope. Ordinary/critical Nidalee Human, Elise Human and Jayce Cannon projectile
variants were reviewed on both patches and are cached by champion, patch and
form. Their alternate and empowered attacks remain separate.

The [26.20 notes](https://www.leagueoflegends.com/en-us/news/game-updates/league-of-legends-patch-26-20-notes/)
and [26.21 notes](https://www.leagueoflegends.com/en-us/news/game-updates/league-of-legends-patch-26-21-notes/)
were reviewed alongside the matching raw records. Nidalee's 26.21 Pounce and
Primal Surge changes concern abilities excluded by this fixed-form simulation;
they are not claims of new ability coverage. Automatic form transitions, the
remaining passives/abilities, unreviewed windups and Gnar's unresolved third
Mini projectile remain omissions.

## Verification

`test/latest-loadouts.janet` runs the actual manual-fetch publication path
against retained responses for both patches. It checks Kayle's level boundaries,
all eight fixed forms, both actor positions, contextual on-hit tooltips, exact
projectile impacts, package-derived rune/shard choices and optimizer scoring
parity. It preserves saved package bytes and current pointers, exercises an
older parser-7 package without shards, and rejects inherited coverage on 16.22.
The runtime gate exports 64 cases and checks the copied standalone executable
in an empty directory with only its saved snapshots. This verifies that source
profiles are embedded in the package, rather than dependent on a checkout.
The browser gate also checks both latest patches' Kayle boundaries and all
fixed-form controls for both participants, saved snapshot identity, explicit
form-change/rerun behavior and narrow layouts. The complete source, combat,
frontend, runtime and browser gates passed.

Refresh and reparse remain explicit user actions. Existing immutable results
and older parser warnings keep their current behavior. Source interpretation,
engine regression agreement and actual in-game accuracy are separate evidence.

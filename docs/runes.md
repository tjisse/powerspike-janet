# Runes and stat shards

Open **Runes & spells**, then **Rune pages** to configure either participant. The three shard slots offer adaptive force, attack speed, ability haste, movement speed, flat health and scaling health where legal in each row. None preserves an unsharded scenario. Tenacity/slow-resist shards remain outside this implementation.

Values come from the selected patch's CommunityDragon perk records. Adaptive force grants the source's AD or AP amount according to the build's bonus AD/AP, with the champion's source preference breaking ties. An explicit AD/AP choice is available for a declared comparison or when an older cache lacks the champion preference. Shards enter the ordinary stat aggregation before caps and multipliers, including Deathcap. Scaling health uses the source's level-1 and level-18 endpoints.

The new common rune handlers are bounded to the 16.17–16.19 source families; other patches report their missing semantics. The shared combat engine supports:

| Rune | Modeled behavior |
| --- | --- |
| Electrocute | Three distinct attacks/ability origins in the source window; adaptive damage and cooldown |
| Scorch | Champion ability damage triggers a delayed magic hit with source-derived damage, delay and cooldown |
| Coup de Grace | Non-true damage increases below the target's source-defined health threshold |
| Cut Down | Non-true damage increases above the target's source-defined health threshold |
| Last Stand | Non-true damage scales with the owner's current health between the source thresholds |
| Transcendence | Source-defined haste at levels 5 and 8; takedown cooldown refunds remain excluded |

Health checks run immediately before each hit, including supported item and rune damage. Practice targets carry the champion tag; objectives do not receive champion-only bonuses. A delayed Scorch hit can fall outside the fight window. Proc damage does not recursively start new rune triggers. These are modeled semantics, not new in-game measurements.

Tooltips use the same starting stats as combat. Rune details show modeled starting haste or the conditional damage bonus, and shard badges show their individual stat contribution. Item optimization retains the configured shards and adaptive preference while evaluating each candidate's full stats; rune-page search uses the same supported rune effects. Opponent choices remain fixed.

Optional `shards` (three IDs, with `0` for an empty slot) and `adaptive-stat` (`auto`, `ad` or `ap`) live in each participant's `loadout` in scenario JSON. Browser saves, share links, imports, exports and packaged commands preserve them. Older scenarios with neither field remain unsharded. Model fingerprints and fitness caches include the new semantics and retained source data.

New patch downloads retain shard records in the immutable package. Older caches can recover shards from their retained, hash-checked rune source. Patch-matched retained excerpts also support 16.18.1 and the initial 16.19.1 package offline, without modifying snapshot files. The initial package exposes rune descriptions alongside the six supported handlers; other rune effects remain explicitly unsupported. Supplemental source URLs and hashes appear in the evidence view.

`test/runes.janet` covers retained 16.18.1/16.19.1 formulas, health boundaries and changing target health, true-damage/objective exclusions, Scorch delay, haste gates, shard legality, adaptive choice, duplicate scaling shards, both participants, tooltip inputs, JSON/UI round trips, immutable snapshots and optimizer scoring parity.

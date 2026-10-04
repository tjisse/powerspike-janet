# Calibration and validation research

Checked 2026-10-04. Target: Summoner's Rift patch 26.19, Data Dragon 16.19.1, CommunityDragon 16.19. Source verification, a local API collector and Janet stat comparison are implemented; [the collection guide](stat-validation.md) describes their use. Five measured Practice Tool snapshots agree: ten baseline, eleven single-Cloak, and twelve stats in each single-Void-Staff capture. The level-6 pair checks nonlinear growth and learned-R penetration combining multiplicatively with Void Staff. Movement speed is excluded; see [validation results](validation-results.md). Broader damage and timing measurements remain proposed.

## Is a rules-only model possible?

Yes. Complete, precise transition rules plus initial state and player inputs are sufficient to simulate the modeled combat. Random mechanics additionally require either the random process for distributions/expectations or its internal state to reproduce a particular outcome. In-game measurements are not inherently needed to invent damage formulas.

The practical limitation is the completeness and interpretation of available rules. Tooltips, item tables and extracted client records are not a complete executable specification of server behavior. Relevant gaps include when stats are sampled, event ordering, damage/proc classifications, reset behavior, conditional buffs and interactions. Some are recoverable from additional data; others require observation. Implementation mistakes are a separate problem.

An aggregate DPS number cannot identify these causes. An incorrect spell value can be offset by an incorrect attack count. A five-second score can jump by one entire hit after a small timing change. Fit isolated timing parameters only when necessary; retain explicit mechanics instead of adding a universal damage multiplier.

Distinguish **validation** (checking predictions against observations) from **calibration** (estimating an uncertain parameter). Our mathematical tests validate implementation consistency, not fidelity to the live game. Expected critical damage also differs from one observed sequence of critical and ordinary attacks.

## Sources and their roles

| Source | Useful evidence | Limits and intended use |
| --- | --- | --- |
| [Riot Data Dragon](https://developer.riotgames.com/docs/lol#data-dragon) | Official versioned item/champion tables and descriptions | Baseline metadata; does not describe every combat transition. Cross-check suspicious fields. |
| [CommunityDragon](https://www.communitydragon.org/documentation) | Extracted client records, rank values, formula trees, projectile/cast fields and object references | Main numeric source where DDragon is incomplete. Client extraction does not supply the entire server implementation. Select the correct mode and current objects. |
| [Hextechdocs spell resolution](https://hextechdocs.dev/resolving-variables-in-spell-textsa/) and [calcrev](https://github.com/moonshadow565/calcrev) | How champion records reference spells and how calculation parts can be interpreted | Improve extraction rather than calibrating incorrect output. Reverse-engineered resolver semantics need checking against our patch. |
| [Riot patch notes](https://www.leagueoflegends.com/en-gb/news/game-updates/league-of-legends-patch-26-19-notes/) | Changes, mechanic descriptions and bug fixes | Independent editorial check on extraction; patch notes are changes, not a complete current rulebook. |
| [Meraki lolstaticdata](https://github.com/meraki-analytics/lolstaticdata) | Structured wiki-derived abilities, notes, classifications and attack timing fields | Useful semantic cross-check. Verify field freshness; Meraki and the wiki are not independent sources. |
| [Rift Logic](https://www.riftlogic.dev/docs) | Another implementation with explicit formulas, assumptions and timing | Differential testing for a shared scenario can expose disagreements. Its documented omissions include mana handling and simplified spatial modeling; agreement is not proof, especially with shared upstream data. |
| [Riot Live Client Data API](https://developer.riotgames.com/docs/lol#live-client-data-api) | Local player's numeric stats, ability ranks, runes, items and game context | Strong candidate for automated stat validation. Published endpoints/events do not offer a general per-hit damage log or dummy stat stream. |
| [Riot Replay API](https://developer.riotgames.com/docs/lol#replay-api) | Playback, camera and recording controls | Useful for inspecting recordings where supported, not a documented damage oracle. [Replays expire when the patch changes](https://support.riotgames.com/en-us/league-of-legends/gameplay/replays-faq-pro-tips); retain video and observations. |

Match results and aggregate win rates are poor calibration targets for individual damage mechanics: choices, opponents, positioning and game state confound the comparison. Another build calculator is a disagreement detector unless its exact patch, assumptions and evidence are known.

## What this research actually found

Our initial Annie Q/W extraction selected legacy `Disintegrate` and `Incinerate` objects still present inside the correctly versioned file. The current `CharacterRecords/Root.spells` points to `AnnieQAbility/AnnieQ` and `AnnieWAbility/AnnieW`. Following those references fixes the values without any game experiment:

- Q: 80/125/170/215/260 + 0.8 AP, also confirmed by [Riot patch 26.4](https://www.leagueoflegends.com/en-sg/news/game-updates/league-of-legends-patch-26-4-notes/).
- W: 70/110/150/190/230 + 0.8 AP, seven-second cooldown, 70/75/80/85/90 mana. [Patch 25.18](https://www.leagueoflegends.com/en-us/news/game-updates/patch-25-18-notes/) independently confirms the base-damage array.
- Learned R grants 10/15/20% magic penetration, even when R is not cast. [Patch 25.08](https://www.leagueoflegends.com/en-us/news/game-updates/patch-25-08-notes/) explains the permanent passive; patch 25.18 and the current R record establish its current values. Rotation evaluation now includes it.

The corrected current spell records and their hashes are retained in `data/16.19.1/sources/` and `manifest.json`. Cast-lock and cooldown-start interpretations still await external validation. R casting and Tibbers remain outside the current model.

The fetched [Meraki latest champion dataset](https://cdn.merakianalytics.com/riot/lol/resources/latest/en-US/champions.json) lists Annie's `patchLastChanged` as 25.11 and critical damage as 175%, whereas our pinned 16.19 character record has a 2.0 multiplier. Its Q array also predates patch 26.4. This establishes specific stale fields; the per-champion patch field alone would not establish staleness. Retrieval SHA-256: `e68e95bb6b5cf5dd3514d4f66cb6a17c83c89e563bca3ec7ac62c4fbe138372f`.

## Viability of game measurements

**High for stat snapshots and isolated hits; moderate for precise timing; low for exhaustive automatic coverage of every interaction.** This is an engineering assessment, not a completed experiment.

Riot's documented local HTTPS service exposes `activeplayer`, `activeplayerabilities`, `activeplayerrunes`, player items and game data. A collector could store timestamped snapshots and compare AD, AP, attack speed, crit, penetration, resources and resistances with Janet predictions. Inspect the installed client's OpenAPI schema and units rather than assuming every sample field is current. API sampling and rendering do not guarantee server-frame precision.

For damage, use isolated attacks/spells and record target health changes or the dummy's displayed damage. Treat displayed rounding and the dummy's own DPS-window convention as measurement limitations. Do not use its aggregate DPS readout as the sole reference for our defined five-second interval.

For timing, record cast initiation, projectile launch and impact separately; test first-hit delay and subsequent cadence. A 120-fps recording has 8.33-ms frame spacing, but does not establish that level of server precision. Repeat cases near a scoring-window boundary. Measure attack sequences at several attack speeds and projectile travel at several distances; one average DPS number cannot separate these parameters.

Use real champions for effects that distinguish champions from dummies. Riot's [26.1 notes](https://www.leagueoflegends.com/en-us/news/game-updates/patch-26-1-notes/) acknowledge Multiplayer Practice Tool. A proposed two-player experiment could record each player's own local health/stats while a controlled attacker hits a controlled defender. This still requires controlling regeneration, shields and concurrent effects; it is not a per-hit combat log supplied by the API.

## Recommended sequence

1. Finish source selection and formula interpretation before taking measurements. Follow current champion references; keep patch-specific values separate from engine semantics and champion effect handlers.
2. Add automatic stat comparisons through the local API. Record actual client build, mode, level, ranks, runes/shards, items, buffs and role-quest state. Use the build currently installed, not an assumed archived patch.
3. Collect a small isolated-hit matrix: ranks 1 and 5, zero and known AP, zero and positive MR, flat and percentage penetration, R unlearned and learned. Disable health/mana/cooldown refresh for normal combat tests; reset between cases.
4. Measure first attack, repeated attacks, cast locks, cooldown start and projectile travel. Isolate critical randomness with 0% or 100% crit for basic tests; use repeated trials for expected-damage checks.
5. Retain observations with numeric/time tolerances and recordings. Add regressions for disagreements once their cause is understood. Test combinations after individual mechanics; expand champion/item coverage incrementally.

The practical target is a rules-based model with traceable evidence and explicitly bounded coverage. Observations resolve uncertainty and catch extraction/implementation errors; they need not become the source of every rule.

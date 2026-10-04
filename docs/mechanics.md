# Mechanics and evidence

## Baseline

The target is Summoner's Rift on patch 26.19. Riot labels the static asset build 16.19.1; CommunityDragon exposes the corresponding game files at 16.19. Neither provider is queried through `latest` during calculations.

Primary sources:

- [Riot patch 26.19 notes](https://www.leagueoflegends.com/en-gb/news/game-updates/league-of-legends-patch-26-19-notes/)
- [Riot Data Dragon documentation](https://developer.riotgames.com/docs/lol#data-dragon)
- [Riot champion data, 16.19.1](https://ddragon.leagueoflegends.com/cdn/16.19.1/data/en_US/champion.json)
- [Riot item data, 16.19.1](https://ddragon.leagueoflegends.com/cdn/16.19.1/data/en_US/item.json)
- Extracted game records: [Garen](https://raw.communitydragon.org/16.19/game/data/characters/garen/garen.bin.json), [Annie](https://raw.communitydragon.org/16.19/game/data/characters/annie/annie.bin.json)
- [Riot patch 13.22 notes](https://www.leagueoflegends.com/en-gb/news/game-updates/patch-13-22-notes/) explicitly distinguish base attack speed from attack speed ratio.
- [Riot patch 26.1 notes](https://www.leagueoflegends.com/en-us/news/game-updates/patch-26-1-notes/) document the Infinity Edge stat change; the retained 16.19.1 item entry is used for this build.

`data/16.19.1/manifest.json` identifies original upstream response hashes, retained excerpt hashes, retrieval date, original prototype commit, and coverage. Upstream files are extracted assets rather than server implementation code. Their meaning still requires checking in-game.

## Evidence status

| Mechanic | Implementation | Evidence / remaining check |
| --- | --- | --- |
| Garen AD | 69 base, 4.5 growth | Matching CharacterRecord; DDragon growth is zero |
| Annie AD | 50 base, 2.65 growth | Matching CharacterRecord; DDragon growth is zero |
| Annie attack speed | 0.61 base, 0.625 ratio | Separate fields in CharacterRecord |
| Static shard subset | +10% attack speed, +2.5% movement speed, +65 health | Matching retained perk descriptions; applied in stat comparison |
| Ordinary critical damage | 2.0 multiplier | Both retained CharacterRecords |
| Infinity Edge | 75 AD, 25% crit chance, +0.30 crit multiplier | Riot item entry / patch notes |
| Deathcap | 130 AP, 1.30 total AP multiplier | Riot item entry; original 1.35 was stale |
| Annie Q | 80/125/170/215/260 + 0.8 AP | Current Root-referenced AnnieQ record; Riot patch 26.4 confirms base damage |
| Annie W | 70/110/150/190/230 + 0.8 AP; 7 s cooldown; 70/75/80/85/90 mana | Current Root-referenced AnnieW record |
| Annie learned R | 10/15/20% magic penetration, zero when unlearned | RPercentPenBuff; Riot patch 25.18 confirms values; multiplicative with item penetration |
| Q/W cast times | 0.25 seconds | Source fields; validate actual animation/lock timing |
| Q projectile speed | 1400 | Source field; distance/speed approximation pending measurement |
| Q/W cooldown start | Cast start | Declared adapter semantics; pending in-game check |
| Growth curve / mitigation | Explicit mathematical model | Regression examples; pending Practice Tool confirmation |
| Skill-rank gates | Standard Q/W/E/R leveling | Only standard kits; exceptional champions need adapters |
| Basic-attack windup | Supplied by scenario | CLI assumes 30%; not claimed as Garen/Annie's exact windup |
| Search optimality | Exhaustive, bounded | Exact within pool and score if `:complete true` |

The first measured level-1 Annie stat snapshot agrees for ten checked fields after applying supported shards. Movement speed is excluded because Celerity interactions are not implemented. This evidence does not yet establish level growth, mitigation or combat timing; see [validation results](validation-results.md).

Binary float artifacts are rounded to six decimal places before normalization. Health regeneration is converted from per-second character-record fields to per-five-second units. Mana and mana regeneration use Riot's named fields; no opaque resource hashes are guessed.

Structured item stats supply flat values, crit chance and attack speed where available. Missing fields such as haste, penetration, critical damage and Deathcap's multiplier are explicitly curated from the retained tooltip. Unsupported stats throw an error rather than disappearing.

## Units and formulas

- Percentages use fractions: 25% crit = 0.25, 40% penetration = 0.40.
- Critical damage is a full multiplier: ordinary 2.0, +0.30 yields 2.30.
- Ability haste is points, not a fraction.
- Attack speed is attacks/second. Growth and item AS bonuses are fractions of the AS ratio.
- Regen is per five seconds. Time is seconds.

For level L, growth factor is `(L - 1) * (0.7025 + 0.0175 * (L - 1))`. It is zero at level 1, 0.72 at level 2, and 17 at level 18. AD gained through levels belongs to base AD, not bonus AD.

Attack speed is `base-AS + ratio * (growth-bonus + item-bonus)`, bounded by the champion's configured cap. The curated champions use 2.5; this is not a universal rule for every champion or buff.

Expected basic-attack raw damage is `AD * (1 + crit-chance * (crit-multiplier - 1))`. Crit chance is capped at one. This evaluates mean damage; it does not reproduce League's finite-sequence crit randomness.

Resistance ordering is flat reduction, percentage reduction, percentage penetration, then flat penetration. Positive resistance R gives multiplier `100 / (100 + R)`. Negative resistance gives `2 - 100 / (100 - R)`. Penetration stops at zero and is ignored against existing nonpositive resistance; flat reduction can create negative resistance. True damage bypasses this calculation. Bonus-armor penetration and damage-specific amplification are not yet supported.

Percentage penetration sources combine as `1 - product(1 - p)`. Item legality is a separate step: the ability to compose a stat does not grant permission to buy conflicting items.

Cooldown is `base * 100 / (100 + haste)`. There is no invented minimum 0.5-second cooldown. Explicit ability definitions must specify whether cooldown starts at cast start or completion.

## Annie adapter

Spell damage/effect arrays include a rank-zero slot, so Q/W damage uses source indices 1–5. Their mana arrays use indices 0–4 for ranks 1–5. This mapping is per field, not inferred from array length.

Only Q and W casts are supported. The core rotation API includes the permanent penetration granted by learned R, even when R is not cast. Base/item stat aggregation alone has no ability-rank context; callers using lower-level modules must explicitly apply rank penetration. Their damage types are named in the adapter; the AP coefficient is kept separate from the damage channel. Q kill refunds are irrelevant to the immortal target scenario and are not implemented. E shield/retaliation, stun, R summon damage, Tibbers attacks, aura and enrage are excluded.

Spell selection follows `Characters/Annie/CharacterRecords/Root.spells`. The initial adapter incorrectly selected legacy `Disintegrate`/`Incinerate` objects still present in the same patch file. Source comparison on 2026-10-04 identified and corrected this error; patch consistency alone does not establish correct object selection. See [Riot patch 26.4](https://www.leagueoflegends.com/en-sg/news/game-updates/league-of-legends-patch-26-4-notes/), [patch 25.18](https://www.leagueoflegends.com/en-us/news/game-updates/patch-25-18-notes/) and [the spell-resolution guide](https://hextechdocs.dev/resolving-variables-in-spell-textsa/).

The Q/W values are source-derived, not calibrated observations. The default strategy uses a legal Q-first 18-level order. Passed-in ranks are checked against champion level. The lower-level action evaluator accepts explicit spell definitions and has no champion-level context; callers must validate ranks through the core API.

## Combat assumptions

A stationary, immortal target has fixed armor and MR. All queued attacks and spells hit. There are no shields, movement, invulnerability, crowd control, regeneration, changing health, item procs, or buffs. Damage is therefore a scenario score, not a claim about a real duel.

An explicit action schedule rejects overlapping casts/windups, early attacks, early spell recasts, insufficient resource, and unknown damage types. A missile can be in flight while another action starts. Casts spend resource when begun even if the hit falls outside the scoring window.

The scored interval is half-open: `[0, duration)`. Hits at the endpoint are excluded. The first attack lands after windup; a ready attack at time zero does not grant immediate damage.

The automatic strategy uses the supplied ability order. It casts the first ready, affordable spell, otherwise attacks, otherwise advances to the next ready event. An attack already winding up delays a newly ready spell. This is a declared strategy, not a globally optimal rotation.

Attack-speed-dependent windup exceptions, animation cancels, channels, empowered attacks and attack resets need champion-specific scheduling.

## Build search

Inventory allows up to six slots, a gold budget and a map ID. Curated components can repeat; legendary items and boots cannot. Boot groups prevent multiple pairs. Boots are optional. These rules cover the current pool; future items require explicit unique-group and champion restrictions.

Exact search enumerates all legal multisets up to the slot count, including empty and partial builds. Scores are evaluated through the supplied scenario callback. Equal scores prefer cheaper builds. There is no global fitness cache.

The result has an evaluation count, `:complete`, and `:guarantee`. Reaching the evaluation limit returns `:best-found`, not an optimality claim. Do not run an exhaustive full-catalog search without a limit. A future genetic/beam search must be checked against this exact baseline on small pools.

## Adding coverage

1. Choose a matching Riot/CommunityDragon patch and retain source excerpts plus hashes.
2. Normalize only named or explicitly resolved fields. Record discrepancies.
3. Model the champion's actual attack/ability state transitions; keep scalar formulas separate from damage type.
4. Cross-check normalized rules against patch notes and other implementations; fix source-selection and interpretation errors first.
5. Validate ambiguous mechanics in Practice Tool with rune, shard, buff, distance and target settings recorded; retain observations and tolerances. See [calibration research](calibration-research.md).
6. Expand the candidate pool only when the relevant item effects and restrictions are implemented.

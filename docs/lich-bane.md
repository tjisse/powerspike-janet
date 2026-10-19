# Lich Bane combat model

Lich Bane now contributes temporary bonus attack speed to the shared combat
engine used by direct simulations, both duel participants and item optimization.
This replaces the previous explicit exclusion. It does not add reviewed combat
observations or promote existing verification evidence to a newer model.

## Sources

The hash-checked `data/combat-fixtures/16.19.1/items.json` excerpt retains
`Items/3100` from the [16.19 CommunityDragon item records](https://raw.communitydragon.org/16.19/game/items.cdtb.bin.json?powerspike=1).
Its source SHA-256 is recorded in the fixture manifest:
`6880f35d5a9d82f688192f764e280e6d4bc9c845112b001feb811e3f2ab62726`.
The selected snapshot supplies `SheenASBuff` (0.5), `SpellBladeDuration`
(10 seconds), `SpellbladeCooldown` (1.5 seconds), and the damage calculation
(75% base AD plus approximately 45% AP, using the retained floating-point values).
These are loaded from data, rather than hardcoded into the combat handler.

[Riot's patch 14.1 notes](https://www.leagueoflegends.com/en-us/news/game-updates/patch-14-1-notes/)
introduced the attack-speed bonus while Spellblade is available. That historical
description informs the conditional behavior; its old damage ratios and item
stats are not used for patch 16.19. Public numerical records and patch notes do
not establish exact game-server event ordering.

## Modeled behavior

- An eligible ability cast primes Spellblade while its hit proc is ready.
  Casting during the proc cooldown cannot queue an early priming buff. Recasting
  while primed refreshes the window without stacking the attack-speed bonus.
- The speed bonus adds `champion attack-speed ratio × SheenASBuff` to uncapped
  attack speed, then applies the champion's cap. Existing bonus attack speed is
  preserved. For example, a 0.5 ratio and 1.5 attacks/second become 1.75, rather
  than 2.25. Base attack speed and the scaling ratio need not be equal.
- The next successful attack impact consumes Spellblade, deals its bonus damage,
  starts the hit cooldown and removes the speed bonus. Missed or interrupted
  attacks leave it available. Expiry also removes the bonus; an old expiry event
  cannot remove a refreshed buff.
- Each participant has independent buff, stats and cooldown state. Unknown source
  values or absent champion scaling metadata produce diagnostics, never a guessed
  speed bonus. Unsupported snapshots retain an explicit limitation.

The timing policy follows the existing engine: attack period and windup use
the speed at attack start. A later stat change does not reset or rescale an
already scheduled attack. Spellblade consumption occurs at successful impact,
including when projectile travel delays that impact. This can keep the bonus
active while a projectile is in flight. These policies require matching in-game
measurements before claiming agreement on ranged timing, animation exceptions
or effects applied during an existing attack. The ordinary windup remains the
engine's configured fraction (30% by default); this change does not supply
missing champion animation handlers.

## Regression checks

`test/lich-bane.janet` checks retained-source integrity, priming, scaling with a
ratio different from base attack speed, caps and uncapped speed, first-hit timing,
ordinary attacks after consumption, expiry, refresh without stacking, repeated
casts during cooldown, misses, interruption, projectile travel, independent duel
state and missing metadata. `test/item-upgrades.janet` retains the damage formula
and repeated-proc checks for all five supported Spellblade items.
`test/mage-burst.janet` compiles an Annie/Viktor duel with Lich Bane on both sides,
checks each champion's scaling metadata and proc damage, and compares direct
simulation with every candidate's optimizer fitness metrics.

The combat model identity hashes the modified engine, item handler and scenario
compiler. Cached fitness values cannot cross that identity. Saved scenarios
recompute with the new model and retain the existing compatibility notice;
historical verification records keep their original identities.

Next evidence should isolate attack start/release/impact times around Spellblade
consumption, including a ranged projectile and a recast during cooldown. Record
champion, level, items, rune/shard page, distance and patch, then admit reviewed
observations through the existing developer verification workflow.

## Replay acquisition: 2026-10-19

Riot's replay endpoint supplied a Summoner's Rift game on
`16.20.824.8524`, matching the existing native decoder. Ekko bought Lich Bane at
API timestamp **908,989 ms (15:08.989)**. Its timeline contains no later Lich Bane
undo or sale, and the final inventory agrees with the replay. All ten champion
slots, inventories, kill counts and game duration agree with the API match.
The API's encrypted PUUIDs and the replay's UUIDs use different representations;
they were not equated. The raw file is retained at
`observations/local/lich-bane-current/replay.rofl`. Credentials, signed download
URLs and account identifiers remain in ignored local storage.

The [current-build study](../observations/replays/lich-bane-current-2026-10-19.json)
records file hashes, full framing checks, the exact-image decoder and initial
observations. It contains 84 matched add/remove cycles for the hash-label
candidate `LichBane`, all after purchase. The first recorded priming transitions
raise `mPercentAttackSpeedMod` by 0.5; consumption/expiry observations return it
to baseline. The matching 16.20 item record independently supplies `SheenASBuff`
0.5 and the same numerical Spellblade values as our retained 16.19 excerpt.

The exact-image descriptors identify three separate raw speed components.
For Ekko, all 29 periodic comparisons of `100 × mAttackSpeedMod` against the
API's integer attack-speed field differ by less than one API unit. This
corroborates component decoding; it does not measure attacks per second or
establish attack windup, server sampling, attack-timer changes or projectile
ordering. Buff updates and stat updates can reach the replay at different times.
Ekko's EAttack is an empowered attack and cannot be used as an ordinary or ranged
attack without further review.

Native extraction accepted 55,045 damage packets, 15,658 state packets, 6,627
action candidates and 28,538 buff records without packet decode failures.
The initial run passed **49 of 50** independent aggregate damage checks. Ornn's
incoming total differed by **1.0094351768493652** points, causing failure. This
discrepancy is now [resolved](replay-damage-accumulation.md): the checker needed
the native client's binary32 accumulation, rather than Python binary64. Clean
re-extraction passes **50/50** checks on this replay and **50/50** on an unused,
preselected replay, with the same strict one-point bound. Individual damage and
state records are unchanged. The original failing result remains in the study
with a link to the resolution. Global buff lifecycle issues remain diagnostic
evidence. This adds **zero admitted simulation comparisons**; the simulator's
16.19.1 snapshot and these 16.20 observations remain distinct.

`scripts/replay_attack_speed.py` reuses already-decoded state bytes and a supplied
archive hash. It preserves raw components, event IDs, timestamps and missing
values, and records source discrepancies without inferring complete game state.
It is separate from the frozen `replay_state.py` adapter used by past reviews.
To reproduce the raw speed extraction without the key, network or emulator:

```sh
python3 scripts/replay_attack_speed.py \
  --combat observations/local/lich-bane-current/combat-v1 \
  --state-sha256 debff4b62bd9e4c82e6ba164f420ec4876da503679325690b5df296c089e945e \
  --output observations/local/lich-bane-current/attack-speed-reproduction
```

Choose a fresh output directory. Eight tests cover component boundaries,
unknowns, wire ordering, timestamps, receipts, corruption, incompatible inputs
and the retained native-decoded component examples.

### Older fallback

Targeted screening found Akali holding item 3100 in the public RoflLens sample
`KR_8306192899.rofl`, build `16.14.794.5912`. The full 16,739,870-byte file matches
its pinned SHA-256, and all 1,755,405 packet records pass chunk decompression and
framing. The raw replay is retained under ignored
`observations/local/lich-bane-search/`; the
[sanitized acquisition report](../observations/replays/lich-bane-source-2026-10-19.json)
records the source and checks.

This is a fallback source, not combat validation. Final inventory establishes
ownership but does not timestamp the purchase or identify a Spellblade attack.
It requires matching 16.14 rules and decoding. The current-build Ekko replay now
provides the stronger acquisition route. The 16.20 adapter cannot be applied to
the older fallback.

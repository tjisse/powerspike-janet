# Replay attack timing investigation: 2026-10-19

New ranged evidence supports retaining Spellblade consumption at successful
impact for the currently supported attacks. It also exposes a separate gap:
a Lich Bane removal without ordinary damage occurs during observed Fiora W
context. That interaction needs review before adding a parry handler.
No windup, projectile speed or consumption rule changes in this investigation.

The [retained study](../observations/replays/attack-timing-2026-10-19.json)
records sources, hashes, selection, exceptions and reproducible archive receipts.
The two games are build `16.20.824.8524`, protocol `142cabd45e45d83f`.
The existing exact-image bounded offline decoder accepts all packets without
failures. Independent Riot roster/inventory/kill/duration checks bind each game;
all **100 aggregate damage checks** pass the unchanged strict one-point bound.
Those checks validate extraction, not the combat model.

## Selection and source boundary

Viktor was selected from the previously retained five match rosters before
looking at attack timings. His timeline contains no Lich Bane purchase. The
ranged search queried Viktor and then Anivia from a preordered four-player list,
screened six distinct available games and stopped at the first matching-build
ranged Lich Bane owner: Ahri. She bought item 3100 at **865,994 ms**. All 52
observed buff additions occur after purchase; the first is at 866.997 seconds.
Credentials, account identifiers and signed download links stay in ignored
local files. This is targeted development evidence, not a random or held-out
accuracy sample.

Matching 16.20 Ahri and Viktor records are retained locally. Their complete
ordinary/critical spell records, Viktor QBuff and basic/critical attack-slot
subsets are identical to the retained 16.19.1 versions. The
[source excerpt](../observations/replays/16.20.1-reviewed-attack-records.json)
binds those subsets to each complete source hash. That agreement does not
establish full cross-patch compatibility. Lich Bane's matching item excerpt
remains the separately retained 16.20 source.

## Observations and exceptions

| Context | Observed records | Result |
| --- | --- | --- |
| Ahri Lich Bane | 52 matching observed add/remove pairs | 44 removals share a timestamp with selected ordinary-name damage; eight do not |
| Ahri ordinary-name damage | 342 packets | 224 have one preceding announcement candidate; 118 remain ambiguous |
| Viktor empowered-name damage | 83 packets | All share a timestamp with observed QReturn removal; 65 have one announcement candidate and 18 have two |
| Viktor ordinary-name damage | 160 packets | 124 have one candidate, 35 have two, one has none |

Case and removal counts are distinct. Ahri has 45 damage packets sharing a
removal timestamp but only 44 distinct removals with that context; a timestamp
can contain multiple packets. Neither the tool nor this report forces a
one-to-one correspondence. Labels come from matching source names or Riot death
recaps and their ELF hashes; they remain candidate attribution.

All eight unmatched Ahri removals remain in the report. Seven have observed
add-to-remove lifetimes over ten seconds. Recasts, refreshes and expiry must
still be reviewed; no inferred expiry deletes a buff. The short removal at
**1380.489 seconds** follows an attack announcement targeting Fiora. The target
has a `FioraW` cast and buff addition at 1380.138 and removal at 1380.890. The
matching source gives `ParryDuration = 0.75`; Riot's retained ability description
says Riposte parries incoming damage. This is consistent with a parried attack
consuming Spellblade without ordinary damage. It does not independently prove
that attack's completion, exact server timing or all parry interactions.

That case identifies a future implementation obligation: the engine's current
successful-damage trigger does not cover consumption on a parried attack.
Fiora W defense itself has no supported handler. A future handler must distinguish
misses, interrupted windups, projectile delivery, parries and damage mitigation
before changing the consumption policy. The observation is not silently scored
as a model success or an ordinary successful hit.

For the 65 uniquely matched Viktor empowered-name packets, announcement-to-damage
intervals range from **0.233 to 0.269 seconds**. These are not measured
release-to-hit intervals. The 18 ambiguous cases remain ambiguous; neither the
30% windup assumption nor empowered zero-travel delivery is fitted to them.

## Reproduction and checks

`scripts/replay_timing.py` consumes the existing action, buff and damage archives.
It verifies replay/build/image/profile identities, current extraction adapters,
archive receipts and packet counts. Damage bytes require an explicit SHA-256.
It retains all same-source/target causal announcements within a fixed two-second
window, every nearby selected buff update and every explicit buff removal,
including removals without selected damage. Damage amounts and model predictions
cannot choose or change a match. Every output remains non-admissible.

For the Ahri dossier, using retained private archives and a fresh output path:

```sh
python3 scripts/replay_timing.py \
  --actions observations/local/ranged-spellblade-current/actions-v1 \
  --buffs observations/local/ranged-spellblade-current/buffs-v1 \
  --combat observations/local/ranged-spellblade-current/combat-v1 \
  --entity 0x400000b0 --effects 0x173499b --buff 0xf9e8165 \
  --damage-sha256 56730a12f03475da71dfc5ae7d0accfc0918c7cd1ce47a82506412605c327481 \
  --output observations/local/ranged-spellblade-current/timing-reproduction
```

The Viktor invocation uses entity `0x400000b6`, effect hashes `0xf7e2cdb`,
`0x7e2cd12`, `0x6ea9976`, buff hash `0x58e0a6e` and the damage archive SHA-256
in its public timing receipt. Original decoded bytes and frozen extraction
adapters remain unchanged. No verification ledger admission or model identity
changes result from this work.

Four new regression tests cover causal ambiguity, same-timestamp wire ordering,
amount-independent output, unclassified removals, immutable outputs and rejection
of mixed, incomplete or changed archives. All 170 Python tests ran in the native
build container: 162 passed and eight optional tests were skipped. New replay
extractions independently passed both 50-check aggregate suites. Application
runtime and UI code are unchanged.

## Subsequent implementation

The [Riposte defense follow-up](fiora-parry.md) implements a source-bounded
16.19.1 champion-only defensive window and parried Spellblade consumption. The
return stab, shield ordering and exceptional interactions remain outside that
handler. The timing study above remains a historical diagnostic record; no
additional combat-model case is admitted.

# Reusable replay evidence

`scripts/replay_evidence.py` turns the retained decoded archives into an indexed,
private SQLite store. Build it once per replay/extraction revision. Additional
sample batches read this store, without opening the ROFL file, decompressing
source archives from the beginning, or running a native decoder again.

This is evidence preparation. It does not resolve the six semantic review gates,
admit comparisons, or increase verification coverage. The existing first-hit
review and production comparison remain separate and unchanged.

The [first retained-game study](../observations/replays/evidence-store-study-2026-10-18.json)
indexed this replay in 11.49 seconds into a 49.33 MiB database, with 112
checkpoints. Preparing the known hit plus four further candidates took 0.31
seconds, plus a 0.24-second store-opening fingerprint check. All 141 shortlisted
hits' checkpoint states matched an uninterrupted archive pass. These are one-run
local measurements, excluding original decoding, manual review and model work.

The subsequent [indexed comparison batch](replay-batch-comparison.md) reviewed
the four new candidates, admitted and evaluated three consistently, and retained
the high-armor case as blocked. Its bounded native rechecks belong to semantic
review; normal evidence extraction still needs no replay or native decoder.

## Build once

The following uses only files already retained for the discovery game. The two
API inputs are optional together; their hashes must match the combat extraction's
validation receipts. No API key, network access, game client or optional emulator
dependency is needed.

```sh
python3 scripts/replay_evidence.py build \
  --combat observations/local/riot-thebausffs-access/combat-discovery-v2 \
  --audit observations/local/riot-thebausffs-access/gaps-discovery-v3 \
  --actions observations/local/riot-thebausffs-access/actions-discovery-v2 \
  --buffs observations/local/riot-thebausffs-access/buffs-discovery-v4 \
  --outcomes observations/local/riot-thebausffs-access/outcomes-discovery-v1 \
  --attack-review observations/local/riot-thebausffs-access/attack-review-discovery-v2 \
  --match observations/local/riot-thebausffs-access/timeline-research/match.private.json \
  --timeline observations/local/riot-thebausffs-access/timeline-research/timeline.private.json \
  --output observations/local/riot-thebausffs-access/evidence-store-v1
```

Use a fresh output directory. Each input archive is parsed once; file hashes are
checked before and after ingestion. Exact replay/build/protocol, native image and
profile identities, parent extraction receipts, counts and damage event identities
are checked before the store is published. A failed build leaves no published
store. Raw source rows and undecoded component bytes remain available in the index.

Records and checkpoints are compressed individually, retaining direct indexed
access. Checkpoints are saved every 256 state/buff events by default; configure
this storage/reconstruction tradeoff with `--checkpoint-every`. Restoring a hit
applies at most 255 intervening state/buff events, regardless of game duration.
Extracting its action context can require a second bounded checkpoint lookup.
Large requested history exports and densely populated local windows naturally
cost more than point lookups.

## Prepare a batch

Export the candidate inventory before inspecting prediction errors:

```sh
python3 scripts/replay_evidence.py candidates \
  --store observations/local/riot-thebausffs-access/evidence-store-v1 \
  --output observations/local/riot-thebausffs-access/candidate-inventory-v1.json
```

Candidates have complete numeric inputs, a unique retained announcement and
stable observed attack inputs. The inventory includes actor IDs, time, attack
damage, target armor and crit chance; it excludes observed damage amounts and
model predictions. These remain provisional ordinary-attack candidates.

For example, retain the known first hit as a regression reference and prepare
four further candidates: a ranged attacker, another melee attacker, a later Sion
attack and a high-armor target. This selection is based on observed inputs,
without evaluating model agreement:

```sh
python3 scripts/replay_evidence.py batch \
  --store observations/local/riot-thebausffs-access/evidence-store-v1 \
  --event gameChunk:4:43918 \
  --event gameChunk:5:96537 \
  --event gameChunk:6:400687 \
  --event gameChunk:10:2417 \
  --event gameChunk:15:363291 \
  --output observations/local/riot-thebausffs-access/evidence-batch-v1
```

The batch is published atomically into a fresh directory. Its summary records
the store identity, individual file/content hashes and measured retrieval cost.
Each package contains:

- The retained case, native outcome, announcement candidates and corrected
  native action slot, without guessing a unique action for ambiguous cases.
- All roster champions' last-observed stats and their originating event IDs,
  replay order, timestamps and observation ages.
- Observed buff lifecycle state, original add records, counter updates and
  persistent lifecycle issues. Durations do not automatically expire buffs.
- Recomputed attack-input continuity, nearby actions/damage/buffs, and nearest
  target-health observations with intervening damage packets. Health closure
  still requires review.
- Optional API rune/shard/summoner selections and item, skill, ward and kill
  event prefixes. Account identifiers, player names and final inventories are
  omitted. API chronology is explicitly separate from replay wire order; this
  does not establish exact inventory/rank state at the hit.
- Explicit unresolved semantic gates, scope limits and checkpoint lookup counts.

Events later in replay order cannot enter a pre-hit snapshot, including events
at the same timestamp. Nearby future events are labeled `after` and appear only
as surrounding evidence, not model inputs. Missing fields stay absent. If an
extended field cannot be decoded, its older value is invalidated and the issue
is retained; no silent default or false continuity is introduced.

## Earlier history is still accessible

A two-second local event window is not proof that no earlier cast or effect
matters. Checkpoints preserve observed active buffs, but all earlier actions and
raw state records remain queryable through indexed history. For example:

```sh
python3 scripts/replay_evidence.py history \
  --store observations/local/riot-thebausffs-access/evidence-store-v1 \
  --kind action --before gameChunk:15:363291 \
  --entity 1073742003 \
  --output observations/local/riot-thebausffs-access/sion-action-prefix-v1.json
```

`--entity` filters the source actor. Omit it for the whole roster. `--after`
optionally bounds the prefix; both replay-order bounds are exclusive.

## Identity, costs and invalidation

Opening a store checks its manifest, the evidence adapter revisions and the
database SHA-256 once. That requires reading the compressed database bytes,
but does not reconstruct state or reread the replay/source archives. Keep one
`EvidenceStore` connection open across a batch to amortize this check. Source
paths are provenance, not identity, and are not needed for normal lookups.

To explicitly recheck that the original immutable inputs are still available
and unchanged:

```sh
python3 scripts/replay_evidence.py verify \
  --store observations/local/riot-thebausffs-access/evidence-store-v1 --sources
```

A changed replay, extraction, decoding helper or evidence adapter requires a
new store. An updated damage model does not: neither model code nor predictions
are part of the extraction identity. Semantic review decisions remain separate
versioned artifacts; changing a review rule requires re-review, not assuming
cached candidates are still admitted. An extension that needs previously
unextracted packet classes will still require a new extraction from the ROFL.

Build reports include indexing time and archive passes. Batch reports distinguish
store-opening integrity checks from extraction time, record checkpoint work and
report zero replay/source-archive/native-decoder work during extraction. These
costs exclude manual review and model execution. Keep databases and evidence
packages under ignored `observations/local/`; public studies should contain only
aggregate results and nonidentifying selected event references.

## Verification

```sh
python3 -m unittest discover -s test -p 'test_replay_evidence.py'
PS_REPLAY_EVIDENCE_STORE=observations/local/riot-thebausffs-access/evidence-store-v1 \
  python3 -m unittest discover -s test -p 'test_replay_evidence.py'
```

The optional retained-game check compares every shortlisted hit's checkpoint
state against one uninterrupted pass through the original state and buff
archives. Synthetic fixtures also cover equal timestamps, long-lived buffs,
unmatched counters, unknown field invalidation and recovery, mid-attack changes,
source removal, source/adapter/database tampering, API identity filtering, failed
builds and atomic batch output. Extraction does not change the verification ledger.

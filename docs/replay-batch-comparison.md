# First indexed comparison batch

The frozen [five-package selection](../observations/replays/evidence-store-study-2026-10-18.json)
contains the original Sion attack as a regression reference and four new
candidates. The [case-specific review](../observations/replays/batch-conditional-review-2026-10-18.json)
closes all six observation gates for three candidates. The fourth stays blocked.
No candidates were replaced or filtered by prediction error.

The [production comparison results](../observations/replays/batch-model-comparisons-2026-10-18.json)
are recorded in the append-only ledger:

| Attack | Time | Observed armor | Replay damage | Model damage | Absolute error | Frozen tolerance |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Tristana → Janna | 63.270 s | 28 | 57.343750000 | 57.343749702 | 0.000000298 | 0.000021315 |
| K'Sante → Sion | 115.811 s | 39.024 | 47.847850800 | 47.847851792 | 0.000000992 | 0.000019674 |
| Sion → K'Sante | 210.294 s | 85.778 | 50.630325317 | 50.630320932 | 0.000004386 | 0.000026240 |

All three are consistent under the existing `positive-armor-fp32-v1` policy.
The tolerances depend only on reviewed attack damage and were frozen before
execution in the [plan bundle](../observations/verification/indexed-batch-plan-2026-10-18.json).
The production runner receives only model identity and source/target scalars,
not observed damage, expected status, tolerances or desired answers. A mismatch
would be recorded under the same admission; it is not grounds to drop a sample.

Including the original hit, progress is **4 evaluated attacks, 3 source
champions, 2 armor bands, 1 game**. The conditional targets remain ordinary
physical damage and positive armor. This is development evidence, with no fresh
audit games and no whole-model accuracy or coverage percentage. Build-stat
generation, complete attack/on-hit totals, critical outcomes, shields, penetration,
exact server timing and sequences remain outside these comparisons.

## What the review establishes

The review is deliberately limited to these frozen event IDs and package
fingerprints. It is not an automatic review for all similar-looking attacks.

- Tristana's attack uses the ordinary current-patch asset and native attack
  announcement/slot. No ability has been learned; Lethal Tempo has one of six
  stacks, below its extra-damage activation. Janna stays above Coup de Grace's
  health threshold. Janna E and Ivern E/W are unlearned, excluding eligible ally
  shielding. The isolated health bracket closes exactly.
- K'Sante's ordinary attack occurs with no recent damage to Sion that could
  apply a passive mark, no All Out learned, and source health above Last Stand's
  threshold. Sion's self shield expired. The nearby Janna E cast has a matching
  buff applied to Rengar, excluding Sion as that single-target shield recipient.
  Ivern has no E/W learned. Grasp's separate magic damage is not being validated
  as part of this ordinary physical component.
- The later Sion attack has a normal attack asset, observed AD including the
  purchased Cull, and invariant scalar inputs. K'Sante W/E's current asset
  durations put both defensive windows before this attack, including an arrival
  margin. Blitzcrank's last immobilizing hit was Power Fist: its one-second CC
  plus the three-second Glacial zone expired long before this attack. The only
  recent incoming champion damage was Sion W, which has no CC; Rengar's earlier
  Exhaust and subsequent Unflinching interval had also expired.

Each packet has a positive, nonlethal, isolated health-loss bracket, with unchanged
observed health capacity. Health-measurement closure uses the sum of half a
float32 ULP for the two health readings and damage packet. This is a different
bound from the model compatibility tolerance; neither is widened after seeing
prediction errors. Unknown buff names and lifecycle issues remain in the cached
evidence; no full buff interpreter or exact server sampling instant is claimed.

## The high-armor candidate remains blocked

At `gameChunk:15:363291` (380.526 s), target armor is 129.540. Two damage packets
fall between the target's nearest health samples: a 199.813293457-point packet
and the selected 46.092185974-point attack. Their sum is 245.905479431, while
observed health loss is 238.764190674, leaving a 7.141288757-point difference.
Healing, shielding, state timing or another observation gap still needs review.

This was discovered during observation review, before running the model. The
case received no admission or prediction and contributes no high-armor
verification credit. Its ledger annotation retains the blocking review receipt.

## Reproduce and extend

The indexed store and private packages must already exist. Two additional public
patch-16.20 assets, Tristana and Blitzcrank, are retained with URL/SHA-256 receipts
under `observations/local/riot-thebausffs-access/batch-review-research`. Their
successful downloads total 89,525 bytes; no new replay, game client or Riot API
request was needed.

The native review rechecks **16 distinct referenced state packets**, retrieved
directly from the index, to corroborate current field semantics against the exact
client image. It does not decode the replay prefix again. The measured review
adapter run took 2.13 seconds; manual investigation and development are excluded.
The comparison itself performs no replay/source-archive reads or native packet
decoding. Model identity and the original first-hit comparison are unchanged.

To reproduce, choose fresh output paths. Existing evidence files are immutable:

```sh
build/replay-venv/bin/python scripts/replay_batch_review.py \
  --base observations/local/riot-thebausffs-access \
  --store observations/local/riot-thebausffs-access/evidence-store-v1 \
  --batch observations/local/riot-thebausffs-access/evidence-batch-v1 \
  --output observations/local/reproduced-batch-review.json

python3 scripts/replay_batch_compare.py \
  --review observations/replays/batch-conditional-review-2026-10-18.json \
  prepare --output observations/local/reproduced-batch-plan.json

python3 scripts/replay_batch_compare.py admit \
  --plan observations/local/reproduced-batch-plan.json

python3 scripts/replay_batch_compare.py run \
  --plan observations/local/reproduced-batch-plan.json \
  --output observations/local/reproduced-batch-comparison.json
```

Repeating the original review reproduces its evidence but changes the measured
runtime; it does not automatically replace the ledger-bound review receipt.
Preparing with the original review preserves its current annotations/snapshots.
Admitting the same plan again adds zero records. Reimporting a comparison reruns
the actual production functions and adds zero duplicate results:

```sh
python3 scripts/replay_batch_compare.py import \
  --plan observations/verification/indexed-batch-plan-2026-10-18.json \
  --report observations/replays/batch-model-comparisons-2026-10-18.json
```

Changing a model, review, policy, runtime, case revision, plan or output is
checked before recording; altered predictions cannot be imported as matching
production output. All admissions are recorded before any production execution.
Tests cover blocked-case exclusion, failed preparation without ledger mutation,
fixed tolerances, modified recipes/reports, mismatch retention, actual production
execution, and idempotent admission/reimport.

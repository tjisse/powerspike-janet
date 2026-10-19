# Using replay verification tracking

The first implementation includes a versioned catalogue, an append-only case
ledger, reviewed-result imports, an evidence queue and a progress page at
`/verification`. In the comparison app, open **Patch & evidence → Replay
verification progress**. The page reads the generated aggregate report; it does
not read raw replays or run comparisons in the browser.

The initial catalogue defines **27 combat conditions in eight families**, plus
three stat-generation conditions. Its checked fraction describes this plan,
not all League behavior. Partial model support stays in the denominator. The
seven stat checks and one damage diagnostic from the pilot remain provisional.
The first [production conditional comparison](../observations/replays/first-hit-model-comparison-2026-10-18.json)
is separate: one admitted/evaluated development case, consistent under a frozen
tolerance, credits ordinary physical damage and positive armor as checked.

## Initialize and import the retained pilot

These commands use existing local files and make no API calls:

```sh
python3 scripts/replay_coverage.py init
python3 scripts/replay_coverage.py import-audit observations/local/riot-thebausffs-access/gaps-discovery-v3
python3 scripts/replay_coverage.py import-audit observations/local/riot-thebausffs-access/gaps-heldout-v3
python3 scripts/replay_coverage.py import-context observations/replays/context-study-2026-10-18.json
make verification-report
```

The default ledger is `observations/local/verification/ledger.jsonl`, ignored by
Git. To use another one, put `--ledger /absolute/path/ledger.jsonl` **before** the
subcommand. Back up the ledger and its source archives together. Imports check
archive hashes, extraction/roster bindings and case totals. Repeating an import
does not create new games, cases or evidence. A source-count commit record
prevents an interrupted import from becoming the report's denominator; retry
the same source to finish it. Nonempty malformed/truncated records fail closed.

`observations/verification/registry.json` is the versioned target catalogue.
`observations/verification/progress.json` is the generated public snapshot.
Every report carries its ledger head, registry identity, model identity and
reporter fingerprint. Prior reports are retained under the report directory's
`history/`, and same-scope changes are summarized in the new report. An unchanged
ledger/model/catalogue/reporter does not generate another snapshot.

The ledger hash chain detects edits and ordering problems; it is not a digital
signature or proof that a review is factually correct. Review provenance is
still necessary. All records in a transaction are validated before append.
Writes are locked; reporting is an atomic file replacement.

### Import provisional action/context work

`scripts/replay_actions.py` recovers exact-build action-announcement candidates
with the optional offline decoder environment and matching private image.
`scripts/replay_attack_review.py` binds those archives to the retained gap audit
and checks observed stat continuity. For the existing discovery game:

```sh
PYTHONPATH=observations/local/replay-pilot/rofllens-0.1.0/src \
build/replay-venv/bin/python scripts/replay_actions.py \
  --replay observations/local/riot-thebausffs-access/fresh.rofl \
  --image observations/local/riot-thebausffs-access/damage-research/LeagueofLegends-16.20-x64.macho \
  --champion-start 0x400000ae \
  --output observations/local/riot-thebausffs-access/actions-new

python3 scripts/replay_attack_review.py \
  --actions observations/local/riot-thebausffs-access/actions-new \
  --audit observations/local/riot-thebausffs-access/gaps-discovery-v3 \
  --combat observations/local/riot-thebausffs-access/combat-discovery-v2 \
  --output observations/local/riot-thebausffs-access/attack-review-new

python3 scripts/replay_coverage.py import-attack-review \
  observations/local/riot-thebausffs-access/attack-review-new
make verification-report
```

Choose fresh output directories. The two-second association window is a search
policy, not a verified maximum attack travel time. All candidates in that window
are retained; ambiguity is never resolved by choosing the nearest or comparing
damage errors. No announcement is treated as proof of attack completion or of
an ordinary/noncritical outcome. Changes and reversions of relevant observed
stats make the interval unstable; old unchanged observations do not prove server
sampling. Rejected native packets remain explicit extraction gaps.

Imports validate source receipts, known cases, causal matching and cohort counts.
Only the latest dossier per game/current context adapter contributes to the
provisional dashboard counts. Case corrections also withdraw provisional context
counts until a matching dossier is imported again. Reruns do not duplicate evidence. This command
never changes case blockers, admits a comparison or advances checked coverage.
See the [retained action/context study](../observations/replays/action-context-study-2026-10-18.json).

## Read the progress page

- **Evidence pipeline:** observed events, ordinary-attack candidates, numeric
  readiness, admission after review, and completed model comparisons.
- **Coverage:** checked, varied and fresh-game stages for each family, individual
  conditions, interaction pairs and source-champion slices. An observed champion
  does not become a verified champion. Item/rune coverage remains unmeasured.
- **Agreement:** matches and mismatches for the selected model/catalogue only.
  No comparisons means *Not measured*. A mismatch increases checked coverage
  while remaining an open discrepancy.
- **Next unlocks:** complete blocker bundles and potential obligations/games.
  Every blocker in a bundle must be discharged. The queue first favors the
  least-covered candidate families, then the numerically ready bootstrap,
  estimated new-condition gain per hour, and breadth. It is a planning heuristic;
  unknown effort is never given a fabricated estimate.
- **Fresh games and costs:** audit reservations, evaluated fresh games, measured
  work and retained discrepancies across revisions. No population confidence
  is inferred from many correlated hits.

The 20-attack bootstrap tracks games, source champions and armor bands. Varied
coverage additionally requires the catalogue's reviewed encounter and condition
targets. Encounter IDs are assigned during review; arbitrary time windows do
not qualify as independent encounters. Paired interaction coverage requires
admitted results with relevant obligations and explicit applicable conditions.

## Review and compare an actual case

Use an event ID from the audit and prefix it with the replay SHA-256:

```sh
python3 scripts/replay_coverage.py export-review \
  --case '670abf1ef2a4fd005cf4ee1a36560078fc99e90aeee5ef263532e59105f2888c:gameChunk:4:43918' \
  --directory observations/local/verification/first-review
```

This creates events and review documents for the existing production comparator.
The amount comes from the retained case. `reviewed` starts false, evidence fields
are blank, and `resolved-blockers` starts empty. The copied candidate conditions
are provisional observations, not a completed review.

Complete the review with independent evidence for packet semantics, relevant
pre-hit context, action identity, matching patch data and oracle independence.
Declare each resolved blocker, the reviewed encounter, applicable conditions,
the exact scenario snapshot/model and justified tolerance. These are scientific
review claims: the ledger validates their presence and bindings, not their truth.
Do not adjust tolerance or inputs to obtain agreement.

After review, admission and execution are separate operations:

```sh
python3 scripts/replay_coverage.py import-reviews \
  --events observations/local/verification/first-review/events.json \
  --reviews observations/local/verification/first-review/reviews.json

python3 scripts/replays.py compare \
  --events observations/local/verification/first-review/events.json \
  --reviews observations/local/verification/first-review/reviews.json \
  --executable dist/bin/powerspike --data-dir build/runtime-data \
  --output observations/local/verification/first-review/comparison.json

python3 scripts/replay_coverage.py import-comparison \
  --report observations/local/verification/first-review/comparison.json \
  --events observations/local/verification/first-review/events.json \
  --reviews observations/local/verification/first-review/reviews.json
make verification-report
```

**No retained pilot hit has yet passed these review gates.** Do not submit the
pilot's conditional diagnostic as a reviewed result. The comparison importer
currently accepts the existing isolated-damage comparator, including its
unsupported/shield/overkill restrictions. Other layers are catalogued gaps;
their measurement adapters still need implementation. The actual imported
comparison must match the packet value, build, review fingerprints, model,
snapshot and tolerance. Repeated results are deduplicated per case/model/
snapshot/catalogue; conflicting results require explicit withdrawal first.

## Correct context without rewriting history

For a mistaken comparison, withdraw its ledger-record hash with a reason:

```sh
python3 scripts/replay_coverage.py invalidate --record COMPARISON_RECORD_SHA256 \
  --reason 'Independent reinspection found an incorrect context assumption'
```

For provisional classification/state corrections, retain a local evidence
document containing `reason` and a `changes` object, then:

```sh
python3 scripts/replay_coverage.py annotate --case REPLAY_SHA256:EVENT_ID \
  --file observations/local/verification/context-correction.json
```

Annotations can replace candidate features/classification, obligations, numeric
readiness or blocker lists. They cannot rewrite the packet amount, identity or
decoded damage type. Correcting context automatically withdraws earlier
admissions/comparisons for that case from current credit. Their records and
mismatches remain in history. An annotation itself never admits a case.

Changing the catalogue requires a new `revision` and another `init` operation.
Old results remain attached to their old target definition. Results from another
model or catalogue do not silently advance current progress. For reporting the
default model, the tool asks the production Janet engine for its identity.
`report --model SHA256` can deliberately inspect a retained model revision.

## Reserve fresh evaluation before inspecting errors

Freeze the model, catalogue and sampling policy before registering new games:

```sh
python3 scripts/replay_coverage.py freeze --id audit-round-1 \
  --selection-policy 'Eligible build, pool fingerprint, random seed and sampling rule retained locally'
python3 scripts/replay_coverage.py reserve-game --replay-sha256 REPLAY_SHA256 \
  --freeze audit-round-1 --selection-receipt 'Pool/sample receipt fingerprint and locator'
python3 scripts/replay_coverage.py import-audit PATH_TO_NEW_GAP_AUDIT --frozen-audit
```

Existing development games cannot be relabelled reserved, and freeze IDs are
immutable. `--frozen-audit` is only for the preregistered game and unchanged
catalogue; it is not permission to call an already inspected game a holdout.
The software cannot detect unlogged human inspection. Keep the actual sampling
receipt and log every use for tuning:

```sh
python3 scripts/replay_coverage.py mark-development --game REPLAY_SHA256 \
  --reason 'Used this result to change the next model revision'
```

An original result stays a fresh-game result for its original frozen model.
Later tuning does not turn that game into fresh evidence for a changed model.
Audit skips and unobservability still limit representative performance claims.

## Record estimates and actual resource use separately

```sh
python3 scripts/replay_coverage.py estimate-work \
  --blockers BLOCKER_ID_1 BLOCKER_ID_2 --hours 2 \
  --rationale 'Estimate based on a measured prototype review'
python3 scripts/replay_coverage.py cost --category review --lane discovery \
  --label 'Reviewed one isolated encounter' --seconds 900
```

Estimates affect queue ranking but never count as measured work. Actual cost
commands accept review/compute/maintenance categories, discovery/audit/shared
lanes, bytes and requests. Imports automatically record successful import wall
time; historical extraction/setup costs remain separately labelled. Unmeasured
manual research stays unknown. The proposed 20% audit review target is compared
with recorded audit/discovery effort, excluding shared research.

## Update the app without exposing the private ledger

Run `make verification-report` after each batch and refresh `/verification`.
Development reads the generated report directly. A built executable includes an
offline snapshot and can read a newer aggregate file using
`PS_VERIFICATION_REPORT=/absolute/path/progress.json`. A bad configured report
shows unavailable evidence rather than silently claiming fresh results.

The page labels the report's exact patch/build and warns when its model differs
from the running engine. The comparison-page panel also warns when the selected
patch differs. No raw replay, API key or private case ledger is shipped to the
browser. This first version is operator-driven: automatic replay acquisition,
background comparison scheduling and measurement adapters for the other layers
are still future work.

## Review native outcomes without admitting damage

For each retained game's matching combat/gap/action archives:

```sh
python3 scripts/replay_outcomes.py \
  --combat PATH_TO_COMBAT --audit PATH_TO_GAP_AUDIT \
  --actions PATH_TO_ACTIONS --image PATH_TO_GUARDED_NATIVE_IMAGE \
  --output PATH_TO_FRESH_OUTCOME_ARCHIVE
```

This decodes the actual attack slot and native result code, correcting earlier
opaque field labels. Codes stay unlabelled until independently corroborated;
neither native extraction nor cohort correlation admits a model comparison.

`scripts/replay_first_hit_review.py` is deliberately restricted to the frozen
first Sion/K'Sante case. It consumes retained hash-bound Riot match/timeline,
16.20 context sources, ten 16.20.1 champion records with receipts, and the
discovery outcome archive. See the published
[review receipt](../observations/replays/first-hit-review-2026-10-18.json)
for source URLs and hashes. It refuses an existing output path:

```sh
python3 scripts/replay_first_hit_review.py \
  --base observations/local/riot-thebausffs-access \
  --outcomes PATH_TO_DISCOVERY_OUTCOME_ARCHIVE --output PATH_TO_FRESH_REVIEW
```

Its `annotation` object contains the remaining four blockers. Only after
reviewing that receipt, retain this object as a separate annotation file, name
the evidence path/hash in its reason, and use `annotate --case CASE_ID --file
ANNOTATION_FILE`. This annotates two reviewed gates for one case; it does not
admit a damage comparison. The annotation invalidates the game's older
provisional context fingerprint. Explicitly re-import the unchanged
`attack-review-discovery-v2` dossier to bind those context counts to the reviewed
case state, then run `make verification-report`. Neither step clears the four
remaining gates or changes model coverage.

The next, separate review stage is `scripts/replay_effect_review.py`. It consumes
the published first-hit review plus the retained matching-game sources, ten
champion records, quest stringtable, Riot 16.20.1 summoner descriptions and their
receipt, and a current-adapter `buffs-discovery-v4` extraction:

```sh
python3 scripts/replay_effect_review.py \
  --base observations/local/riot-thebausffs-access --output PATH_TO_FRESH_EFFECT_REVIEW
```

The [published effect receipt](../observations/replays/first-hit-effect-review-2026-10-18.json)
documents the exact shield-free eligibility scope. Its annotation removes only
that case's shield gate, leaving three blockers. Apply it with the same
receipt-bound annotation and explicit context re-import process above. This
does not verify shield field calibration, shield absorption or complete buff
state. A new defensive ability, ally shield rune/item, summoner, quest state or
spell prefix fails closed and requires renewed review.

The next independent stage reviews the selected hit's amount metric:

```sh
build/replay-venv/bin/python scripts/replay_amount_review.py \
  --base observations/local/riot-thebausffs-access \
  --image PATH_TO_GUARDED_NATIVE_IMAGE --output PATH_TO_FRESH_AMOUNT_REVIEW
```

This requires the optional native decoder environment. It verifies the current
shield review and retained source receipts, re-runs the native state/damage
readers, rebuilds the health bracket and checks float32 measurement closure.
The [published amount receipt](../observations/replays/first-hit-amount-review-2026-10-18.json)
resolves amount meaning for this isolated, shield-free, nonlethal hit only.
Its annotation leaves two blockers: active effects and server sampling. Apply
it with the same evidence-bound annotation, explicit context re-import and
report regeneration process. Neither the amount review nor the float32 bound
admits a comparison or defines the model's error tolerance.

The last observation review stage is limited to this conditional-input case:

```sh
build/replay-venv/bin/python scripts/replay_final_review.py \
  --base observations/local/riot-thebausffs-access \
  --image PATH_TO_GUARDED_NATIVE_IMAGE --output PATH_TO_FRESH_FINAL_REVIEW
```

The [final receipt](../observations/replays/first-hit-final-review-2026-10-18.json)
binds the amount review, native payloads, both teams' causal capabilities and
new resource observations. Twenty initial resource values independently match
Riot's timeline; no later snapshot is used as pre-hit input. Zero Rengar
Ferocity plus missing prerequisite actions excludes empowered CC. The
declared-mechanic review and eleven invariant scalar inputs make the exact
sampling instant irrelevant for this conditional calculation.

Its annotation leaves no observation blockers for this case; apply it with the
same receipt-bound annotation and explicit context re-import process. The page
then shows observation review complete. It still has zero admitted comparisons:
the conditional-input comparator must bind this receipt and the production
model before execution/admission. Unknown counter names, lifecycle issues and
the unknown exact server sampling instant stay in the receipt. They are not
relabelled as decoded or treated as universal protocol coverage.

## Execute a reviewed conditional comparison

This first adapter is restricted to the frozen Sion → K'Sante ordinary physical
case. It consumes the four public semantic review receipts and an unblocked
imported case, rather than substituting a 16.19 runtime build for the observed
16.20 game. Its `snapshot` is explicitly a content-addressed observed-input
context, not a champion/build package. The full-simulation adapter remains
separate.

Prepare a fresh recipe and admit it before executing the production runner:

```sh
python3 scripts/replay_conditional_compare.py prepare --output PATH_TO_FRESH_PLAN
python3 scripts/replay_conditional_compare.py admit --plan PATH_TO_PLAN
python3 scripts/replay_conditional_compare.py run --plan PATH_TO_PLAN --output PATH_TO_FRESH_REPORT
make verification-report
```

`run` writes the result and records it in the append-only ledger. To verify and
re-import a retained report, the importer re-executes the production calculation:

```sh
python3 scripts/replay_conditional_compare.py import --plan PATH_TO_PLAN --report PATH_TO_REPORT
```

An unchanged import adds zero comparison records. Mismatches remain results and
cannot be hidden by increasing tolerance after execution. Changing an admitted
recipe requires explicit invalidation/review. `--ledger` and `--reviews` are
global options placed before the subcommand. The runner requires `build/janet`
and the normal workspace modules; optional replay/native decoding libraries are
not needed at comparison time.

The [retained plan](../observations/verification/first-hit-conditional-plan-2026-10-18.json)
contains the frozen model, registry, case revision, review chain, observed input
context and numerical policy. Its tolerance is calculated from AD and a declared
float32 arithmetic bound before prediction; it is not selected from the replay
error. Admission alone does not add checked coverage. The
[production report](../observations/replays/first-hit-model-comparison-2026-10-18.json)
adds one evaluated case and two checked conditional targets. It verifies no build
stat generation, crit/penetration behavior, shield handling or fight sequence,
and it does not turn this development game into fresh audit evidence.

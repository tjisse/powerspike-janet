# Replay verification

The [source audit](replay-sources.md) now confirms authenticated access through
Riot's player-replay endpoint. Current-patch decoding is the priority; the initial
five-file bootstrap below remains a historical parser fixture.

Replay evidence is now the preferred route for scaling combat verification. A
replay adds observations; it establishes accuracy only where we can reconstruct
the conditions independently and compare a supported mechanic. Repeated hits
under identical conditions increase repeatability evidence, not mechanic breadth.

## Current damage and partial state: 2026-10-18

Follow-up: the [gap audit](#gap-audit-and-offensive-stats-2026-10-18) below
recovers offensive stat components from these same buffers. Its records and
adapter hashes are separate from the original damage/state study.

The [damage/state study](../observations/replays/damage-state-study-2026-10-18.json)
supersedes the damage-decoding blocker in the historical sections below. Riot's
official macOS client for **16.20.824.8524** contains readable Intel code. The
offline adapter uses its actual packet deserializers in bounded Unicorn memory;
the image is never executed as a native process. A fixed SHA-256 protects every
address, alongside exact replay build/protocol, return-to-sentinel, true return,
full payload consumption, memory budgets and independent target/block checks.

| Check | Discovery game | Separate held-out game |
| --- | ---: | ---: |
| Damage packets decoded / encountered | 27,754 / 27,754 | 62,476 / 62,476 |
| State packets decoded / encountered | 8,568 / 8,568 | 18,943 / 18,943 |
| Riot final damage checks within one point | 50 / 50 | 50 / 50 |
| Armor snapshots within one point | 170 / 170 | 359 / 360 |
| Magic resistance snapshots within one point | 170 / 170 | 359 / 360 |
| Maximum health snapshots within one point | 169 / 170 | 359 / 360 |
| Current health snapshots within one point | 161 / 170 | 333 / 360 |
| Combined extraction wall time | 12.08 s | 26.99 s |
| Model comparisons admitted | **0** | **0** |

Each player's checks cover incoming total, incoming physical/magic/true and
outgoing damage to champions. The native float transform came from exhaustive
256-byte probes, not fitting these API totals. Agreement of totals is strong
decoder evidence; it does not independently label each hit or establish model
accuracy. Both games reuse the same frozen profile, image and adapters.

All **11,220 champion-target damage events** now carry preceding observations
for health, maximum health, armor, magic resistance and candidate shield fields.
Each field includes its originating packet ID, time, wire order and age. Updates
later in the wire stream, even at the same timestamp, cannot enter an earlier
snapshot. A dropped state packet invalidates continuity rather than carrying
older values forward. Unknown values remain absent, distinct from observed zero.

These are **last-observed values**, not exact hit-time states. Median preceding
health age is 167 ms in both games; the 99th percentile is 21.5/24.6 seconds.
Stable values may simply not be retransmitted, but regeneration, intervening
damage and simultaneous updates still need reconstruction. API snapshot
differences are retained; neither future samples nor API values fill replay gaps.
Shield labels follow matching native descriptors and older schema evidence, but
remain candidates without an independent shield oracle. Later health-component
integer fields and non-champion stat layouts remain uninterpreted raw data.

The output preserves every selected raw payload, decoded state buffer and field
provenance in compressed JSONL. Game files, API responses and the 41.7 MB Intel
image stay in ignored local storage. The image required about 13 MB of compressed
CDN bundle ranges, plus a 16.9 MB manifest; processing reused both existing
replays and made no additional Riot API requests. Decoder times exclude download,
researcher time and development probes. Historical coverage remains deferred.

To reproduce using the retained exact image and optional private API responses:

```sh
build/replay-venv/bin/python scripts/replay_combat.py \
  --replay observations/local/riot-thebausffs-access/heldout-4/replay.rofl \
  --image observations/local/riot-thebausffs-access/damage-research/LeagueofLegends-16.20-x64.macho \
  --output observations/local/combat-reproduction \
  --match observations/local/riot-thebausffs-access/heldout-4/match.private.json \
  --timeline observations/local/riot-thebausffs-access/heldout-4/timeline.private.json
```

Install the optional dependencies described below. Omit both API arguments for
replay-only extraction. Choose a fresh output directory; existing evidence is
never overwritten. `summary.json`, `damage.jsonl.gz` and `state.jsonl.gz` contain
counts, failed checks, hashes, costs and raw evidence. A rejected packet or failed
aggregate damage check makes the CLI fail; periodic state differences remain
visible diagnostics. A successful run still admits zero model comparisons.

The next useful work is full offensive-stat and buff/inventory reconstruction,
shield validation and cast/attack attribution. Start with a few independently
reviewed basic attacks on matching model patch data, before broadening coverage.
The [validation plan](replay-validation-plan.md) defines the implementation
order, first 20 comparisons, fresh-game checks and coverage/cost decisions.

## Gap audit and offensive stats: 2026-10-18

The [gap study](../observations/replays/gap-study-2026-10-18.json) screens all
11,220 champion-target events. Of those, **6,306 are champion-to-champion hits**;
the other 4,914 have non-champion sources and fall outside the first ordinary
champion-attack test. The audit reuses native-decoded state bytes and makes no
new downloads or API requests. Its final two runs took about 3.6 seconds.

The [frozen stat mapping](../observations/replays/16.20.824.8524-stat-fields.json)
adds base/flat/percentage AD and AP components, crit chance, penetration,
lethality and related fields. Names and order come from the exact matching
native descriptors. AD/AP compositions were developed against stat snapshots
in the first game and checked on the separate game without using damage values.
They are composed replay observations, not stats predicted from a build.

| Offensive snapshot check, within one point | Discovery | Separate game |
| --- | ---: | ---: |
| Attack damage | 170 / 170 | 358 / 360 |
| Ability power | 169 / 170 | 360 / 360 |

The three differences remain in the private summaries. Penetration snapshot
checks include nonzero counts: matching an all-zero baseline does not establish
nonzero penetration behavior. Crit and lethality lack independent API fields
here; native labels alone do not establish every gameplay interpretation.
Every derived value retains each input's original packet, timestamp and order.
Later mixed-type fields remain raw; missing inputs never become zero.

Observed AD/AP are now available for all 6,306 champion-to-champion events.
Matching API death-recap spell names to ELF hashes identifies **638 basic-attack
candidates**; 439 have no additional numerical/classification flags under the
first-mechanic screen. These still have unresolved semantic context. Dictionary
collisions abstain, and unique hash labels remain candidate attribution. This
post-hoc label analysis is not a fresh model holdout.

The first review witness is a Sion attack candidate against K'Sante at 38.326 s.
Its observed source AD is 78 and target armor is 44. The recorded damage is
54.166664; surrounding health observations show a 54.166687 loss, with one
target-damage packet between them. The prior health sample is 33.3 seconds old
and that age is preserved. Later health is a retrospective decoder check; it
never enters the pre-hit inputs. Numeric agreement does not establish absent
buffs, precise sampling or shield semantics.

Both games retain `cases.jsonl.gz`, `summary.json` and `candidate-witness.json`
under ignored `observations/local/riot-thebausffs-access/gaps-*-v3/`. Witnesses
include API rune/shard/summoner choices and purchase/skill event prefixes. Those
prefixes are context, not a complete buff or inventory state. Every case remains
**inadmissible for model validation**. The next decoder priority is relevant
attack/buff lifecycle and inventory/rune context around these witnesses, followed
by sampling and shield/amount semantics.

Reproduce using a fresh output directory:

```sh
python3 scripts/replay_gaps.py \
  --input observations/local/riot-thebausffs-access/combat-discovery-v2 \
  --output observations/local/gap-reproduction \
  --match observations/local/riot-thebausffs-access/timeline-research/match.private.json \
  --timeline observations/local/riot-thebausffs-access/timeline-research/timeline.private.json
```

The audit uses Python's standard library. API files must match the original
extraction's identity-binding hashes. Omit both API arguments to audit numerical
inputs without spell labels or API snapshot checks. Candidate selection uses
completeness and chronology, never damage agreement with the model. Source
archives remain unchanged; the previous adapter versions are retained privately
with matching hashes for the original study.

## Historical current-patch access: 2026-10-17

Riot returned five replay URLs for the requested EUW player. One recorded random
selection yielded a complete **16.20.824.8524** replay with the player on Sion,
matching the latest official Data Dragon patch, 16.20.1. The
[access report](../observations/replays/riot-access-2026-10-17.json) records the
7.4 MB file's hash, selection, costs and limits without retaining credentials or
signed URLs in Git.

RoflLens read all 779,977 packet records, including 616,955 gameplay records and
163,020 keyframe records, in about 1.6 seconds. The remaining two records are
stream markers. This checks framing only. None of the inspected tools supplies
a matching combat decoder for this build, so damage verification and model
comparisons remain **zero**. Acquisition is feasible; recovering independently
verified combat semantics and pre-hit state is now the next engineering task.

The [follow-up decoder investigation](../observations/replays/decoder-investigation-2026-10-17.json)
tested automatic artifact generation with the exact matching executable and a
pinned rofl-parser source revision. Environment preflight passed, but the
protected on-disk executable lacks the readable packet registrations that the
builder requires. No artifact was generated. The replay-only work below now
recovers a small independent subset without the executable. Damage, items and
casts remain unresolved; this is primarily a development-cost blocker.

## Replay-only recovery: 2026-10-18

The [retained study](../observations/replays/recovery-study-2026-10-18.json)
records a discovery game and a separate Summoner's Rift game on exact build
16.20.824.8524. Recovery uses the replay and a frozen profile; Riot Match-v5 and
Timeline responses are optional independent checks after recovery. Exact build,
match ID, duration, champion/team/KDA roster and API participant identities bind
the inputs. Metadata's UUID-like `PUUID` strings are not assumed to equal API
PUUIDs.

| Check | Discovery game | Held-out game |
| --- | ---: | ---: |
| Death timestamp and victim | 44 / 44 | 78 / 78 |
| Largest death timestamp difference | 1.32 ms | 1.12 ms |
| Skill-upgrade time, actor, slot and type | 102 / 103 | 126 / 171 |
| Wrong known skill labels | 0 | 0 |
| Recovery wall time | 1.34 s | 3.54 s |
| Damage-model comparisons | **0** | **0** |

The skill adapter recognizes 37 complete payload patterns learned only from
uniquely aligned discovery events. It is a partial codebook, not a complete
packet layout. In the held-out game, 44 packets have unknown payloads and one
timeline upgrade is absent from the selected packet stream: **45 upgrades remain
uncovered**. Unknowns are retained, never filled from the timeline. No ability
rank, cast, item ID, killer, assist, or damage value is claimed.

The investigation also found a framing bug in RoflLens 0.1.0: a relative entity
ID change is signed, but it adds the byte unsigned. Negative changes invent IDs
offset by 256 and misclassify targets. Our adapter corrects this independently
of payload decoding, following
[ROFL-X's signed framing](https://github.com/Toastaspiring/ROFL-X/blob/88954be66da506f188fbd134944fdfd8334ad846/src/rofl/block.rs).
Regression checks cover negative changes, wraparound, chunk resets, filtered
packets and truncated input. Rechecking the old pilot changes its player-target
candidate count from 3,859 to **4,783**; it admits no new model comparisons.

An 18-participant Arena replay was explicitly rejected by the ten-player
adapter. Its download is included in the additional 32,233,598 replay wire bytes
spent during this investigation. Avoid downloading another mode merely to
increase the replay count. The two useful Riot timelines additionally contain
530 participant stat snapshots and 2,149 death-recap damage rows. Those are
useful anchors, not precise pre-hit states or timestamped individual hits.

To reproduce recovery and optionally validate against locally saved responses:

```sh
build/replay-venv/bin/python scripts/replay_recovery.py \
  --replay observations/local/riot-thebausffs-access/heldout-4/replay.rofl \
  --profile observations/replays/16.20.824.8524-skill-recovery-profile.json \
  --match observations/local/riot-thebausffs-access/heldout-4/match.private.json \
  --timeline observations/local/riot-thebausffs-access/heldout-4/timeline.private.json \
  --output observations/local/riot-thebausffs-access/heldout-4/recovery-new.json
```

Omit both `--match` and `--timeline` for replay-only output. No key, network,
client executable or game process is used. The profile refuses other exact
builds/protocols; ambiguous champion entity runs fail. Successful exit means
recovery completed and supplied checks found no incorrect known predictions;
inspect skill `complete`, missing counts and unknowns separately. This command
does not establish combat-model accuracy.

## Historical bootstrap: 2026-10-17

The [pinned source catalog](../observations/replays/sources.json) contains the five
public research replays from [RoflLens v0.1.0](https://github.com/ss26367098/rofllens/releases/tag/v0.1.0).
Its published size and SHA-256 checks matched an actual download. This is a
reproducible **bootstrap corpus**, not an established supply of current games or
a representative sample of League players. Checksums establish byte identity;
the decoder's interpretation still needs independent review.

A uniformly selected file within this five-file corpus, using recorded seed
`1829709103`, was `KR_8305643709.rofl`. We downloaded its exact matching executable
from Riot's CDN using [lol-exe-downloader](https://github.com/shyunku-libraries/lol-exe-downloader).
The executable matched the decoder profile's SHA-256. It was read for offline
packet decoding, never launched as a game process.

| Measurement | Result |
| --- | --- |
| Exact client build | 16.14.794.5912 |
| Replay duration | 1,193.474 seconds |
| Downloaded replay | 10,371,426 bytes |
| Shared executable on disk | 34,384,312 bytes |
| Gameplay damage packets examined | 43,107 |
| Candidate damage events against players | 4,783 (signed-framing correction) |
| Candidate events between player objects | 2,419 (signed-framing correction) |
| Full damage extraction | About 3.5 seconds, without running League |
| Model comparisons admitted | **0** |

The [retained pilot report](../observations/replays/pilot-2026-10-17.json) records
selection, hashes, costs and blockers. The original replay, client file, all
candidate payloads and local reports are under `observations/local/`, which is
ignored by Git. The public report omits player names and account identifiers.
Game object IDs in local evidence identify entities inside that replay only.

**This experiment validates the feasibility and low cost of extracting damage
candidates. It has not validated the combat model against those events.** The
adapter does not yet reconstruct pre-hit stats, inventories, ranks, buffs,
shields, or cast-to-damage attribution. Its damage decoder retains candidate
semantics. Our retained static snapshot is 16.19.1; substituting it for this
16.14 replay would invalidate a comparison. No damage formulas were tuned.

## Reproduce the experiment

From the repository root, with Python 3.11–3.13, create an isolated environment
and install the optional tools. These are not application dependencies:

```sh
python3 -m venv build/replay-venv
build/replay-venv/bin/pip install -r scripts/replay-requirements.txt
build/replay-venv/bin/python scripts/replays.py fetch \
  --seed 1829709103 --output observations/local/replay-example
```

Omit `--seed` for a new recorded random draw. Selection is uniform within the
sorted, pinned corpus. A selected file over the download budget is rejected;
the tool does not quietly choose a smaller one. The default download cap is
32 MiB. Failed size/hash checks do not produce a receipt or usable replay.

Obtain the exact matching executable, recording its origin. The source catalog
pins the expected SHA-256. One option is `lol-exe-downloader@0.3.2` with Node 20+:

```sh
npx --yes --package=lol-exe-downloader@0.3.2 lol-exe-download \
  --version 16.14.7945912 \
  --output-path 'observations/local/replay-example/League of Legends.exe'
```

Find the installed profile and extract a bounded pilot:

```sh
replay_profile=$(build/replay-venv/bin/python -c \
  'import pathlib,rofllens; print(next((pathlib.Path(rofllens.__file__).parent/"profiles").glob("*/profile.json")))')
build/replay-venv/bin/python scripts/replays.py extract \
  --receipt observations/local/replay-example/receipt.json \
  --profile "$replay_profile" \
  --client-exe 'observations/local/replay-example/League of Legends.exe' \
  --max-events 500 --max-seconds 30
```

This checks replay, executable, profile and protocol identities before decoding.
RoflLens additionally verifies executable section hashes. Only gameplay chunks
are counted; keyframe restoration is excluded. Stable event IDs use stream,
chunk and byte offset. `events.json` retains payloads and decoded fields;
`extraction.json` reports partial scans, limits, skipped packets and costs. The
event cap bounds selected decode attempts, including failures. The time cap is
checked between packets; parser initialization and one decoder call can exceed
it. For the measured complete scan we used `--max-events 10000 --max-seconds 30`.

## Admit evidence to the model comparison

### Current buff/context pilot (16.20)

The [context study](../observations/replays/context-study-2026-10-18.json)
adds three exact-build deserializers: observed buff add (435), explicit removal
(262), and counter update (430). Slot bytes remain opaque equality tokens.
Zero counters and elapsed durations never imply removal. Missing adds, hash
mismatches and slot replacements remain recorded continuity issues. These three
classes do **not** establish complete buff-protocol coverage.

Across the two games, all **52,801** champion buff records decode with full
payload consumption. **13,965 / 13,978** removals match active adds; 13 do not.
There are also 241 unmatched counter updates and 14 slot replacements without
an observed removal. None are silently repaired. The measured complete scans
take about 15 seconds together after setup; this excludes research/download costs.
The compressed buff archives total about 1.2 MB. This research retained about
105 MB of source data, directory listings and naming/localization dictionaries;
that is setup cost, not a new download required for every replay. Manual research
time remains unmeasured. Reuse these exact-build inputs before acquiring more data.

An exhaustive native byte-codec probe resolves counter constants 0, 1 and 2,
which do not pass through the ordinary plaintext write path. The generic buff
hash `0x0c3bf5c2` correlates with non-control ward use: 64/64 discovery readings
and 107/116 second-game readings match that rule. The nine discrepancies begin
when Lee Sin consumes Eye of the Herald. Including that consumption explains
116/116, but this extension was developed after inspecting that game; it is no
longer a sealed holdout for the expanded rule. The exact internal name and
complete behavior remain unknown. Demolish-ready and Second Wind healing also
have plausible generated hash names, explicitly retained as hypotheses.

The production stat functions now run on independently normalized, hash-pinned
16.20 Sion/K'Sante and item data. At Riot's 60.006-second snapshot, all seven
selected conditional checks match exactly: both champions' AD, armor and MR,
plus K'Sante's maximum HP. Level one and zero XP are independently recorded;
the early inventory prefix is unchanged from the selected hit. Sion HP is
excluded because the scaling-health shard is outside this harness. Other
stats, rune effects, champion abilities and rotations are not checked here.

The same production damage function predicts **54.166666667** for the first
ordinary-attack hypothesis, versus **54.166664124** recorded. This is a
**conditional diagnostic**, with zero admitted damage cases. Numeric agreement
does not establish attack attribution, exact sampling, shield/amount semantics,
or absence of unreviewed effects. Future API samples do not fill pre-hit inputs.
These observations are from one selected discovery game and are not an accuracy
percentage or a claim of full 16.20 model support. The curated seed snapshot
remains 16.19.1; the new retained data is confined to this component harness.

With the optional dependencies and matching private image already available:

```sh
PYTHONPATH=observations/local/replay-pilot/rofllens-0.1.0/src \
build/replay-venv/bin/python scripts/replay_buffs.py \
  --replay observations/local/riot-thebausffs-access/fresh.rofl \
  --image observations/local/riot-thebausffs-access/damage-research/LeagueofLegends-16.20-x64.macho \
  --champion-start 0x400000ae \
  --output observations/local/riot-thebausffs-access/buffs-discovery-v3

python3 scripts/replay_context.py \
  --base observations/local/riot-thebausffs-access \
  --output observations/local/riot-thebausffs-access/context-pilot-new.json
```

Use fresh output paths; existing evidence is never overwritten. The context
pilot currently expects the retained `buffs-discovery-v3` archive and pinned
source receipts under `context-research`. Full raw data stays ignored locally;
the public study retains hashes, selected component inputs, checks and limits.

The next admission work is the isolated first attack: independently verify its
cast/attack identity and sampling window, finish the three buff hypotheses,
and document shield-free amount semantics for that specific context. Full
historical buff-name coverage is deferred.

Copy [the review template](../observations/templates/replay-review.json). Each
case binds an event ID, replay hash and exact build to an exported PowerSpike
scenario. Set `reviewed` only after documenting:

1. What the packet amount and damage type mean, checked against an independent
   source such as a controlled recording. Decoding a float is insufficient.
2. The actual pre-hit state, including stat sampling time, loadouts, ranks,
   health, relevant buffs, shields and transient modifiers. Do not infer these
   values by solving backwards from the damage we want to explain.
3. The observed action and target. Configure a single-hit scenario; do not
   substitute our automatic rotation for the player's actions.
4. Matching patch data, exact snapshot/model identities, source attribution and
   a justified absolute tolerance. An old observation does not verify a newer
   patch without a separate documented compatibility review.

Then run:

```sh
python3 scripts/replays.py compare \
  --events observations/local/replay-example/events.json \
  --reviews observations/local/replay-example/reviews.json \
  --executable dist/bin/powerspike --data-dir build/runtime-data \
  --output observations/local/replay-example/comparison.json
```

The comparator invokes the existing shared `--simulate` engine. It uses the
recorded event's amount, not a hand-entered expected number. Initially it admits
only one-trial, one-hit scenarios with matching damage type, no shield
absorption, a surviving target, matching snapshot/model identities and no
reported unsupported mechanics. This conservative subset excludes multi-hit
casts, kills/overkill and general fight replay. More adapters can widen it once
their event/state semantics are verified. Return codes: 0 for checked results
without mismatches, 1 for a mismatch or execution/input error, 2 when nothing
was checkable. Review statuses in the report even when the return code is 0.

## Coverage and resource decisions

Keep three quantities separate: **observed events**, **checkable cases**, and
**consistent/mismatching comparisons**. Never publish a whole-model accuracy
percentage using only the easiest checkable cases. Record skips and unresolved
state alongside the checked denominator. A mismatch is an investigation, not an
instruction to fit a multiplier. Locate the fault in decoder, context, source
data or engine before changing the model.

Comparison reports group checked evidence by patch, mechanic and champion and
retain exact snapshot/model identities per case. Count a replay hash plus event
ID once per model/data revision; rerunning extraction adds no new coverage.
Keep replay count, distinct state/interaction count, and held-out replay results
alongside event count when extending the reports. Mechanic-wide confidence and
cross-patch transfer require additional evidence; they are not inferred here.

Costs currently recorded are replay download bytes/time, extraction CPU/wall
time, replay/client/output storage, comparison wall time and declared human
review time. Unknown human time remains null. Dependency installation, initial
client transfer, decoder maintenance and total researcher time are **not** yet
automatically measured. Do not treat the extraction-only figure as total cost.

Use these priorities when selecting further work:

| Priority | Spend effort when | Stop or defer when |
| --- | --- | --- |
| Current supported patches and common mechanics | Evidence resolves uncertainty that affects current predictions | Another replay repeats already covered conditions |
| Shared mechanics in archived games | A small review can expose a general bug or create a durable regression | Exact patch data/state recovery requires substantial new machinery |
| Rare interactions and obsolete patch completeness | A known current discrepancy depends on them | Work only increases historical completeness |

Follow the [validation plan](replay-validation-plan.md): pin matching 16.20 data,
bridge the current decoder output to reviewed cases, recover the minimum context
for ordinary attacks and admit the first 20 comparisons. Then check a frozen
model on fresh games before expanding mechanics. The retained 16.19.1 snapshot
cannot establish current 16.20 accuracy. More downloads alone cannot resolve
missing context. Preserve the historical pilot and defer a complete 16.14
implementation.

For ongoing supply, accept contributed files downloaded by participants and
pin each file's build, hash and provenance. A public archive can supplement
that collection. Register a contribution with:

```sh
build/replay-venv/bin/python scripts/replays.py import \
  --input '/path/to/contributed.rofl' \
  --provenance 'Participant contribution; original download date and origin' \
  --client-exe '/path/to/matching/League of Legends.exe' \
  --output observations/local/contribution-example
```

This copies the original bytes, reads the actual build/protocol from the header
and records hashes. It does not classify the contribution as a random sample or
as verified model evidence. Use the same extraction/review steps afterward; an
unsupported build remains an explicit decoder gap.

Riot's player-based replay discovery and a full current-patch download are now
verified for the requested account. Future access rules, production quotas and
sustained supply remain untested. A historical decoded batch is available, but
work on it is deferred unless it helps decode fresh replays. The fixed five-file
corpus alone does not satisfy ongoing coverage.

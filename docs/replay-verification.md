# Replay verification

The [source audit](replay-sources.md) now confirms authenticated access through
Riot's player-replay endpoint. Current-patch decoding is the priority; the initial
five-file bootstrap below remains a historical parser fixture.

Replay evidence is now the preferred route for scaling combat verification. A
replay adds observations; it establishes accuracy only where we can reconstruct
the conditions independently and compare a supported mechanic. Repeated hits
under identical conditions increase repeatability evidence, not mechanic breadth.

The first [production conditional comparison](../observations/replays/first-hit-model-comparison-2026-10-18.json)
is now admitted and evaluated: Sion → K'Sante, observed 54.166664123535156,
predicted 54.166666666666664, absolute error 0.000002543131508048191. It is
consistent with the independently fixed 0.000022411350869334603 tolerance.
This is one development-game check of ordinary physical damage and positive
armor, not build-stat, sequence, fresh-game or whole-model validation.

The [first indexed comparison batch](replay-batch-comparison.md) adds three
reviewed, consistent production comparisons: Tristana → Janna, K'Sante → Sion,
and a later Sion → K'Sante attack. The total is now four evaluated attacks across
three source champions and two armor bands in one development game. The selected
high-armor hit remains blocked by a multi-packet, nonclosing health bracket and
received no model admission. The two conditional targets remain ordinary
physical damage and positive armor; no fresh-game or whole-model credit is added.

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

## Action announcements and first-hit context, 2026-10-18

The [action/context study](../observations/replays/action-context-study-2026-10-18.json)
retains a new exact-build extraction and causal context dossier. This uses the
existing two development games; there were no new API requests or client
downloads. `scripts/replay_actions.py` extends bounded offline native emulation
to opcode 906 (basic-action announcement candidate) and 1215 (spell-cast
announcement candidate). All 5,268 basic-action and 6,670 spell-cast packets
from champion subjects decode with full payload consumption and no failures.
Packet names and field semantics remain research labels. Constructors and
deserializers come from the SHA-256-guarded image. Only runtime allocation,
static initialization and exit registration are substituted by the new adapter;
action-payload readers remain unmodified. The inherited common-entity-header
shim takes its entity from ROFL framing instead of reading that header twice.
Frozen payload regressions include a spell
whose two hash fields legitimately differ, rather than forcing their equality.

The candidate matcher uses actor, target, original wire order and a fixed
two-second window. It never reads predicted damage or picks the nearest action.
Across 637 ordinary *physical* candidates, 369 have one announcement candidate,
263 are ambiguous and five have none. One additional basic-attack candidate
with nonphysical recorded damage is outside this first scope. Of the original
439 numerically ready candidates, 274 have one announcement candidate; 255 of
those have unchanged observations for all relevant stat fields until damage.
These are context checks, not admitted comparisons. A unique announcement can
still be cancelled or misattributed. At this extraction stage slots, auxiliary
cast records and critical/empowered outcomes were uninterpreted; the subsequent
case-specific review below resolves part of that uncertainty.

The original selected Sion → K'Sante case now has a separate source/target
announcement at 37.992436 seconds, before damage at 38.326436: a 0.334-second
interval. Its five AD components, crit chance, four penetration-related fields
and target armor have prior observations and no decoded changes during that
interval. All ages and original packet identities remain attached. This proves
client-observation continuity only; it cannot locate or prove a server sampling
instant. K'Sante's preceding spell-cast packet separately carries the KSanteQ
hash. Neither observation uses the hit's numeric agreement as a selector.

Three unmatched counter records in that witness now have direct name-hash
matches in the retained KSante source: `KSanteRConversionArmor`,
`KSanteRConversionHealth` and `KSanteRConversionMagicResist`. Their values
(8, 150, 8) align with the recorded Doran's Helm bonuses. Naming is established
within those retained sources; lifecycle continuity and behavior remain
unproven. These records are not silently repaired into active buffs, and do not
establish that the ultimate was active. The earlier generated Second Wind,
Demolish-ready and ward-counter hypotheses remain explicitly provisional.

The final extraction and context passes took about 14 seconds together. This
excludes exploratory probes, development, tests and unmeasured manual review.
No model functions changed. Admission remains **zero** until ordinary/critical
outcome, relevant effect context, server-input sufficiency and shield/amount
semantics are independently justified. The progress page now reports provisional
action/context counts without discharging those semantic blockers. See the
[repeatable extraction and import commands](replay-coverage.md#import-provisional-actioncontext-work).

## Native outcomes and first semantic review, 2026-10-18

The [outcome study](../observations/replays/outcome-study-2026-10-18.json)
decodes actual attack slots for all 5,268 retained basic-action announcements and
native result codes for all 6,306 champion damage packets. Exhaustive byte probes
require complete native-code bijections; frozen regressions cover slots, spell
announcements and three different result codes. These remain extraction
regressions, not independently verified model comparisons.

This corrects two earlier opaque field labels without rewriting the old frozen
observations: `encoded-slot` held a byte from a different four-byte field, while
the actual attack slot is at native object offset `0x1d`. Similarly,
`source-kind-encoded` is the encoded result field. The enriched archives use
`attack-slot`, `result-code` and explicit opaque names. Historical enum values
are not applied to the current protocol. Current result code 5 is not labelled
from the old normal-result value 4; other result codes remain unlabelled.

The [first-hit semantic review](../observations/replays/first-hit-review-2026-10-18.json)
discharges **two of six gates for one case only**: ordinary/noncritical attack
identity and recorded early inventory/rune selections. Its unique causal Sion
announcement has actual slot 64, no auxiliary cast, an ordinary Sion attack
asset, observed zero crit chance and a positive landing corroborated by a
separate health update. Its item prefix, rune IDs, shards and summoners bind to
the retained matching-game Riot records. Active rune/buff behavior is still a
separate gate. No predicted damage or error threshold selected this identity.

Matching-patch names matter: rune 8230 is Stormraider's Surge in the retained
16.20 source, and 8321 is Cash Back. Familiar historical names would give a
different context. Ten official 16.20.1 champion records and causal skill
upgrades are also retained for the remaining effect review. Before the hit,
K'Sante had only Q learned; Sion, Janna and Ivern had no recorded skill upgrade.
Neither future timeline frames nor descriptive passive text prove complete
active effect state.

The damage packet and independent health loss close within a bound derived from
float32 measurement precision. That check is not a model tolerance and does not
alone establish shield or amount semantics. Four gates remain: relevant active
effects, server-input/sampling sufficiency, shields, and damage amount semantics.
The ledger records these four remaining blockers, and the progress page shows
one case in this narrower work bundle. **Admitted/evaluated damage cases remain
zero.** No model functions changed.

The final outcome extraction passes took about 14 seconds. Champion source
retrieval used ten public HTTP requests (142,896 bytes), with zero authenticated
Riot API calls and zero new replay/client downloads. Manual research time is
unmeasured. The next review should connect the selected case's causal skill and
loadout evidence to its remaining modifier/shield possibilities, then justify
conditional server inputs and packet amount meaning before comparison.

## First-hit shield eligibility review, 2026-10-18

The subsequent [effect review](../observations/replays/first-hit-effect-review-2026-10-18.json)
resolves the shield gate for the same frozen hit by excluding eligible shield
sources in its exact context. This is **three of six gates reviewed for one
case**, with zero admitted/evaluated damage comparisons. It does not calibrate
the candidate shield fields or verify nonzero shields and absorption.

The review covers K'Sante's whole team, not only the two combatants: exact
early item prefixes, rune selections, summoners, learned abilities and current
patch capability descriptions. K'Sante has only Q learned. Diana, Yasuo,
Tristana and Blitzcrank have no recorded ability upgrades. Their self-shield
mechanics do not grant K'Sante a shield; there is no ally-shield item or rune
selection on that team. Tristana's Barrier protects herself. K'Sante's quest is
unfinished with a zero counter, no prior reward events and no observed Teleport
cast; the retained 16.20 quest tooltip ties its Teleport shield to completion.
The complete decoded spell prefix is two ward placements and K'Sante Q.
Zero candidate shield observations corroborate this exclusion but are not its
sole basis. A changed roster, loadout, ability upgrade, spell prefix, quest
state, time range or nonzero candidate shield requires another review.

This also exposes two important remaining effect checks: Blitzcrank's Glacial
Augment can reduce damage against his allies, and K'Sante's Unflinching can
change armor after crowd control. The former needs immobilization and
Blitzcrank has no learned ability or observed spell before the hit; neither is
silently omitted from the remaining modifier review. Generated ward-counter,
Demolish-ready and Second Wind labels remain hypotheses about behavior. The
three unmatched K'Sante counter records remain attached as lifecycle issues.

The source guard rejected the older buff archive's decoder revision. A fresh
extraction with the current adapter produced 20,045 buff packets without decode
failures in about 5.7 seconds; this does not claim complete buff replication.
The only new download was Riot's public 16.20.1 summoner description file. No
authenticated Riot API requests, new replays or client downloads were needed.
The ledger preserves earlier review stages and binds the three remaining gates
to this new receipt: active effects, server-input/sampling sufficiency and packet
amount semantics.

## First-hit amount metric review, 2026-10-18

The [amount review](../observations/replays/first-hit-amount-review-2026-10-18.json)
discharges one more case-specific gate: the recorded amount corresponds to
damage delivered to health in the selected shield-free, isolated, nonlethal
hit. **Four of six gates are now resolved for that case; admitted/evaluated
damage comparisons remain zero.** The active-effect and server-sampling gates
remain open. This is measurement interpretation, not a successful prediction.

The adapter re-runs the guarded native readers on 189 original state payloads
and the damage prefix. It independently rebuilds the target's health/capacity
history, rejects capacity changes even if they revert, and requires exactly
the selected damage event between the last preceding and first following
health observations. The target starts this bracket at full 775 health and
survives at 720.8333129882812. Recorded damage is 54.166664123535156; independently
observed health loss is 54.16668701171875. Their difference,
0.00002288818359375, is below the 0.0000629425048828125 measurement bound derived
from the three float32 values. No model prediction selects the case, interprets
the amount or sets this bound. The bound is not a model-error tolerance.

This conclusion relies on the preceding shield-free eligibility review and
does not assign universal semantics to shielded, lethal, overlapping-damage or
healing contexts. It does not verify pre-mitigation amounts or general outcome
codes. New target damage, missing health/capacity observations, another event or
build, a lethal result or an inconsistent health delta fails the review.
The final retained-payload pass took about 1.2 seconds, with no requests or
downloads; exploratory work and manual research time remain unmeasured.

The [modifier investigation](../observations/replays/first-hit-modifier-investigation-2026-10-18.json)
preserves the remaining uncertainty rather than discharging it: the generated
ward-counter, Demolish-ready and Second Wind labels still lack independent full
behavior evidence. A native ASCII-token scan found no matching names. Glacial
Augment and Unflinching remain explicit causal CC questions; empowered cast
rules must not be excluded solely from an unlearned rank. The next modifier
review needs to establish relevant CC/resource state and classify these buff
records before the comparison can be admitted.

## Six reviewed gates for the first conditional case, 2026-10-18

The [final review receipt](../observations/replays/first-hit-final-review-2026-10-18.json)
closes the last two observation gates for **conditional ordinary physical
damage only**. The selected Sion → K'Sante hit is now **6/6 reviewed** and ready
to bind to a conditional-input comparator. No model comparisons have yet been
admitted or evaluated, and no whole-model coverage increases from this review.
The other candidates do not inherit this case's conclusions.

The remaining CC prerequisite question now has new observation evidence:
Rengar's primary resource stays at **0 of 4** throughout the prefix and there
is no Rengar attack/cast or Exhaust announcement. Thus an empowered E is ruled
out using resource and action prerequisites, not merely an unlearned rank.
The source team otherwise has no learned CC spell; Blitzcrank has no learned
immobilizing spell or triggering action. This excludes the relevant
Unflinching and Glacial Augment triggers in this frozen context. Sion has no
prior death; Janna E and Ivern W/E are unlearned, and the retained passive and
loadout descriptions confer no other ally attack modifier here. Inventory
undo handling is restricted to Teemo's exact ordinary purchase refunds.

Resource fields follow `mPAR`/`mMaxPAR` in the exact-build native registration
order. All **20 initial resource/current-capacity observations** agree with
the independent retained Riot timeline across ten champions. These API values
check interpretation; future snapshots are not filled into pre-hit state.
The new parser is separate from the frozen adapters, accepts only the reviewed
zero representation of the intervening mixed field, and fails on unsupported
representations. [Field regressions and native references](../observations/replays/16.20.824.8524-review-fields.json)
retain these boundaries. Control words stay opaque numeric observations;
historical CC bit enums are not applied.

The exact server sampling instant remains unknown. It is unnecessary for this
conditional check: all eleven required scalar inputs are observed before the
announcement and invariant through damage, and the causal mechanic review
excludes eligible transient changes. Every sampling point in this attack
interval therefore yields the same reviewed conditional inputs. This is not a
general proof that old client observations equal current server state or that
full-build/stat-generation and sequence comparisons are admissible.

The exact names/full behavior of three opaque buff records and the unmatched
K'Sante counters remain retained metadata. The final gate reviews their
relevance through the frozen game's declared champion, rune, item, summoner and
prerequisite context; it does not claim a complete buff interpreter, silently
repair lifecycles, or derive behavior from name hashes. Native percentage
modifier observations at baseline and unchanged control words corroborate
the mechanic review without being used as universal absence or CC oracles.
Any new capability, resource gain, prerequisite action, stat change, death or
control-state change requires another review.

The coverage page labels the empty blocker bundle as observation review
complete, awaiting comparison. The next implementation step is a comparator
that runs the production damage function on these reviewed observed scalars,
binds the model and receipt identities, defines numeric tolerance independently,
and admits only the conditional layer. A generic full-simulation comparator
must not fill in a different patch's build or assume this verifies stat
generation. The final retained-native pass took roughly two seconds with no
new requests or downloads; exploration and manual review remain unmeasured.

## First recorded production comparison, 2026-10-18

The [frozen recipe](../observations/verification/first-hit-conditional-plan-2026-10-18.json)
was prepared and admitted before running the production model. The
[result receipt](../observations/replays/first-hit-model-comparison-2026-10-18.json)
records the model identity, observed-input context fingerprint, runner and Janet
hashes, policy-bound tolerance and actual output. `scripts/replay_conditional_model.janet`
calls the same `damage/expected-attack-damage` and `damage/resolve-hit` functions
used by the engine. It receives reviewed scalars (AD 78, armor 44, zero crit and
penetration), never the observation, tolerance, requested status or a runtime
champion/build package. No damage formula is reimplemented in Python.

The [tolerance policy](../observations/verification/conditional-physical-fp32-policy.json)
was fixed before execution: `gamma(4) * AD + half-ULP32(AD)`, with
`gamma(n) = n*u/(1-n*u)` and `u = 2^-24`. Four ordinary arithmetic stages and
the AD upper bound on output magnitude define a conservative float32
compatibility band for this positive-armor, unamplified domain. This is a
declared numerical policy, not proof of server operation order or a statistical
confidence interval. It is separate from the independent health-bracket
measurement bound. It does not inspect the observed damage or prediction error
to select or widen the threshold.

The production output is **54.166666666666664**, versus replay damage
**54.166664123535156**. Absolute error is **0.000002543131508048191**, below the
fixed **0.000022411350869334603** tolerance. The ledger now has one admitted and
evaluated case, credited to two conditional targets: ordinary physical attacks
and positive armor mitigation. These are two checked catalogue obligations,
not two independent samples or a statement that the mechanics are exhaustively
verified. The bootstrap has 1/20 attacks, one game, one source champion and one
armor band. Both retained games remain development evidence; there is no fresh
evaluation claim.

The adapter binds the final review hash to the actual current ledger annotation,
rechecks the complete review chain and current adapters, and refuses changed
model, policy, review or case revisions. The report importer re-executes the
production runner to detect edited predictions and preserves mismatches. A
repeat import added zero records. The measured model execution pass took about
0.17 seconds with no new requests/downloads; admission/import validation,
development, tests and manual review are outside that measurement.

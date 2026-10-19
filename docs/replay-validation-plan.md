# Plan for validating the model with replay data

For the research-backed sampling strategy, coverage denominators and progress
view, see [balanced replay coverage](replay-coverage-strategy.md). Its
[measured baseline](../observations/replays/verification-progress-2026-10-18.json)
keeps conditional diagnostics, admitted comparisons and unknown coverage separate.
The [initial tracker](replay-coverage.md) implements the catalogue, case ledger
and progress page; automatic acquisition/scheduling remains future work.

Proposed 2026-10-18. The initial gap audit and offensive-stat recovery are now
implemented; see the [gap study](../observations/replays/gap-study-2026-10-18.json).
The [context pilot](../observations/replays/context-study-2026-10-18.json) now
adds buff lifecycle decoding and patch-matched component inputs. Seven
conditional stat checks match, and one conditional damage diagnostic agrees.
The first case witness remains context-incomplete and no damage comparison has
been admitted. A bridge to the fully reviewed scenario workflow remains planned.
Baseline evidence is the
[damage/state study](../observations/replays/damage-state-study-2026-10-18.json):
90,230 decoded damage packets, 11,220 champion-target hits, 100 successful
aggregate damage checks, and zero admitted model comparisons. Processing the
two retained games took about 39 seconds. The main costs now are resolving
context, reviewing evidence and maintaining decoder support.

The first deliverable is **20 reviewed single-hit comparisons**, with all
matches, mismatches and exclusions retained. Passing 20 selected hits will not
establish accuracy for every champion, mechanic or game.

The [action/context study](../observations/replays/action-context-study-2026-10-18.json)
now adds 11,938 native-decoded action candidates across the existing two games.
Of 439 numerically ready attacks, 274 have one matching announcement candidate
in a fixed two-second search window, and 255 also have unchanged relevant
client stat observations between that announcement and damage. The selected
Sion/K'Sante witness has one candidate 0.334 seconds before its damage and all
11 required observed input fields unchanged. These checks strengthen context;
they do not resolve attack completion/outcome, server sampling or effect/shield
semantics, and no damage case is admitted. The operator bridge and dossier
imports are described in [the tracker workflow](replay-coverage.md).

## 1. Connect the evidence to the production model

Retain and verify source data for the replay's 16.20 patch, with exact source
hashes, snapshot and model identities. The checked-in 16.19 data cannot stand in
for it. If an exact historical hotfix cannot be resolved, record that limit and
exclude affected formulas; do not silently use the newest snapshot.

Add a small adapter from `replay_combat.py`'s JSONL to the existing reviewed-case
workflow in `scripts/replays.py`. Bind every case to replay hash, packet ID,
decoder/profile hashes, source and target, damage type, recorded amount, and
the precise state observations used. The observed amount must come directly
from the retained packet, never a manually supplied expected result.

Use production Janet functions for predictions. A thin validation entry point
may be needed for independently observed stats and an explicit single action;
do not create a second damage implementation in the replay tooling. The
scenario runner currently constructs stats from loadouts and drives strategies,
so it cannot yet serve every conditional single-hit test unchanged.

**Done when:** one candidate can travel from the new archive through the real
model to a report containing prediction, observation, difference, tolerance and
an honest checked/skipped status. Missing patch data or context must block it.

## 2. Recover the minimum evidence for the first mechanic

Start with ordinary, non-critical physical attacks against champions. Prefer
simple early-game encounters, but never assume that early means no rune,
passive, item or temporary effect.

Recover and independently check:

- Source attack damage and relevant penetration; target armor and reductions.
- Attack identity and ordinary/critical/empowered classification. An effect hash
  alone is a candidate label until its meaning and collisions are checked.
- Relevant outgoing/incoming multipliers, buffs, on-hit effects and shields,
  including evidence for an absent effect when absence is required.
- The stat sampling point. Prefer cases with stable relevant inputs across the
  attack's possible sampling interval until cast/start/impact timing is known.

Continue using native field descriptors and independent API stat anchors to
decode offensive stats. API purchase histories can help reconstruct inventory,
but must account for undo, sale, consumption and transformations. Document API
context as an input; it then cannot also count as an independent prediction of
that same inventory. Keep unknown buff or inventory state explicit.

Confirm what the damage packet measures: resolved damage versus health removed,
shield absorption and lethal damage. The existing aggregate checks are useful
evidence, but do not resolve all those distinctions. Use unambiguous recap
examples where possible, and a few short controlled captures only for semantics
that cannot be established from existing replay/API evidence.

Use a dependency list per test. A plain attack's damage calculation need not
require exact current HP if no applicable mechanic depends on HP and survival
and shield conditions are independently established. Conversely, health-based
effects require valid health at the relevant instant. A universal freshness
cutoff cannot prove all fields correct; preserve age, intervening changes and
ordering uncertainty per field. Never solve AD or armor backwards from damage.

**Done when:** we can explain why a candidate's relevant inputs are sufficient,
why confounding effects are absent or modeled, and which component the case
actually tests. If those conditions fail, retain a specific skip reason.

## 3. Run a narrow conditional damage pilot

Feed observed source/target stats and the observed attack into the production
damage path. This tests the attack and mitigation calculation **conditional on
those inputs**. It does not validate stat growth, inventory aggregation, attack
timing or build optimization.

Select initial candidates using input completeness and mechanic classification,
before looking at prediction error. Keep the full candidate denominator and all
exclusions. Review a small seed set in detail, then expand to 20 comparisons
across more than one game, actor and armor/stat condition where available.
Repeated hits in one exchange are correlated evidence, not independent breadth.

Use tolerances justified by numeric precision and verified measurement
semantics. The one-point threshold used for Riot's truncated game totals is not
automatically a per-hit tolerance. Never widen tolerance to make a discrepancy
pass. A critical attack must be compared with its actual critical outcome;
expected critical damage across random trials is not a single-hit prediction.

For every mismatch, retain a reproducible packet/context fixture and investigate
in this order: decoding, identity/attribution, state/sampling, patch data, model
behavior. Keep unexplained discrepancies visible. When changing a mechanic,
state the rule and supporting evidence; avoid fitted global multipliers.

**Done when:** 20 reviewed comparisons have reported results, including any
mismatches, with reproducible provenance and no hidden exclusions. If fewer are
admissible, report the blockers instead of relaxing the evidence requirements.

## 4. Confirm results on fresh games

The second retained game was a decoder holdout, and its state results have now
been inspected. Do not describe it as a sealed model holdout. Use both existing
games for developing the workflow and retain their regression cases.

Before further model tuning, reserve fresh same-build games for model validation.
Freeze candidate filters, supported mechanics, tolerances and model/data
identities before inspecting their model errors. Split by whole game, not
random hits, so one fight or build cannot appear on both sides of the split.

The first validation batch should aim for comparisons across at least three
games in total, including a fresh game. If it exposes a bug, preserve the result
for the frozen revision. After tuning against it, that game becomes development
evidence; another fresh game is needed for the next holdout claim.

**Done when:** a frozen model has a separately reported fresh-game result,
with checked, matching, mismatching and skipped counts. Zero checkable hits
means no result, not a passing validation run.

## 5. Expand from components to complete behavior

| Order | Test | Additional evidence needed | Claim it can support |
| --- | --- | --- | --- |
| First | Ordinary physical attacks using observed stats | Verified AD, armor, penetration, relevant modifiers and attack identity | Conditional attack damage and mitigation |
| Next | Isolated simple magic/true damage | Ability/effect identity, rank and scaling inputs, relevant defenses and modifiers | Supported spell/effect calculation |
| Next | Derive stats from recorded builds | Exact level, inventory, runes/shards, ranks and relevant temporary state | Stat generation and aggregation |
| Next | Full single-hit scenario from recorded build | Combine the preceding evidence without replacing derived stats with observations | End-to-end single-hit prediction |
| Later | Crits, penetration/reduction combinations, shields, on-hit and health-based effects | Verified triggering, ordering, state and packet semantics for each effect | Specific interactions |
| Last | Short observed combat sequences | Action start/impact times, cancellations, movement, resources, cooldowns and state transitions | Timing and stateful simulation |

For sequence tests, replay the observed actions explicitly. An automatic strategy
that chooses different actions cannot be validated by comparing its damage total
with a player's fight. Compare event traces before aggregate DPS or kill time.
Optimizer correctness and the quality of its recommendations remain separate
questions, even after its underlying combat predictions gain evidence.

## 6. Track coverage and spend by useful new evidence

Maintain separate statuses for decoded events, candidate cases, admissible model
comparisons, matches, mismatches, unsupported mechanics and missing context.
Deduplicate by replay hash and event ID per data/model revision. A rerun is
regression evidence, not another observed game or mechanic.

Report coverage by patch/build, mechanic, champion, relevant stat/health range,
interaction and distinct game/encounter. Report conditional-input checks apart
from full-build and sequence checks. Publish the checked fraction and skip
reasons alongside conditional agreement; do not turn selected-case agreement
into a whole-model accuracy score. Track mismatch magnitudes and systematic
errors as well as simple pass counts.

Reuse the existing games first. Begin new acquisition in batches of up to three
supported current-build games, record the sampling procedure, and stop to assess
what each batch added. Random selection within an available compatible pool
reduces cherry-picking but does not make that player pool representative.

Record download bytes, client/decoder setup, processing time, storage, model
evaluation time, manual review and maintenance effort. Compare cost per newly
covered mechanic/condition and per admitted case, rather than raw event count.
Only introduce worker parallelism if measured runtime warrants it; review and
context recovery currently dominate the likely effort.

The [reusable evidence store](replay-evidence-store.md) now indexes the retained
archives and checkpoints observed state/buff lifecycles. Additional sample
batches use bounded checkpoint lookups without replay playback or native
decoding. The first planned batch retains the known hit as a regression reference
and prepares four further candidates for individual semantic review; extraction
alone does not advance admitted-case or mechanic coverage.

Favor shared mechanics and discrepancies that can change current predictions.
Defer older patch coverage unless a particular old fixture cheaply resolves a
current uncertainty. Every new build needs compatibility checks and fresh
evidence before carrying decoder or model claims forward.

## First implementation slice

1. Retain matching 16.20 model data and bridge the JSONL/review formats.
2. Recover the offensive stats and minimum context for an ordinary attack.
3. Produce the first auditable comparison, then reach 20 without discarding
   mismatches or filling unknown inputs.
4. Freeze that scope and evaluate a fresh-game batch.
5. Choose the next decoder/mechanic task from measured skip counts and likely
   impact on model predictions.

The first selected Sion → K'Sante hit now has a
[case-specific semantic review](../observations/replays/first-hit-review-2026-10-18.json)
for ordinary/noncritical identity and recorded loadout selection. The subsequent
[shield eligibility review](../observations/replays/first-hit-effect-review-2026-10-18.json)
resolves shield-free context for this case, without verifying shield absorption.
The subsequent [amount review](../observations/replays/first-hit-amount-review-2026-10-18.json)
corroborates damage delivered to health for this isolated, nonlethal hit using
independent health loss and native payload rechecks. Two gates remain before
its conditional damage comparison: active effects and server-input sufficiency.
The [final conditional review](../observations/replays/first-hit-final-review-2026-10-18.json)
now closes those observation gates using observed zero Ferocity, causal cast
prerequisites, declared mechanic eligibility and invariant scalar inputs. The
selected hit is 6/6 reviewed. The [production comparison](../observations/replays/first-hit-model-comparison-2026-10-18.json)
has now been admitted and evaluated consistently under its frozen numerical
policy, using the actual production damage functions and reviewed observed
scalars. This checks ordinary physical damage and positive armor for one
development case. Next, grow the admitted set toward 20 with additional actors,
games and armor ranges, retaining mismatches and fresh-game separation. Exact server
sampling and complete buff-script decoding remain unclaimed. Do not extend
this case's gates to the other 438 numerically ready candidates or count review
as model coverage.

The subsequent [indexed batch](replay-batch-comparison.md) independently reviews
three more selected cases and records consistent production comparisons. Progress
is now four evaluated ordinary physical attacks, three source champions and two
armor bands in one development game. The selected high-armor case remains
blocked by a nonisolated, nonclosing health bracket, without a prediction or
coverage credit. The next breadth goals still require other games and additional
actors; the original first-hit review was not extended to arbitrary events.

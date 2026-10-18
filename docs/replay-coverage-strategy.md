# Balanced replay verification and progress reporting

Research and proposed policy, 2026-10-18. The measured starting point is
[the progress baseline](../observations/replays/verification-progress-2026-10-18.json).
The [initial tracker](replay-coverage.md) now implements the catalogue, ledger,
result imports, progress page and an operator-driven work queue. Automatic
acquisition/scheduling and representative accuracy estimation remain future work.

The recommended strategy is **balanced coverage of mechanics, selected by the
cost of gaining useful evidence, plus a separate representative audit**. There
is no defensible single optimal allocation yet: review time, blocker-resolution
cost and yield per new replay have not been measured. Start with the policy
below, record those costs, and revise it after five batches.

## 1. Measure three different things

1. **Verification progress:** how far evidence has moved from a replay to an
   admitted comparison. Show counts at each gate and the next blocker.
2. **Coverage:** which declared mechanics, conditions and interactions have
   actually been exercised, and how broadly. Show both the least-covered
   families and typical-game reach.
3. **Agreement and uncertainty:** how the model performed on admitted evidence.
   Retain mismatches. Unchecked cases are unknown, never successes.

A correctly investigated mismatch increases evidence coverage while reducing
agreement. Fixing it creates a new model revision; it does not erase the failed
result for the earlier revision. A rerun adds regression evidence, not another
game or independent condition. Seven fields from one snapshot are seven field
checks, one snapshot and one game.

Today's baseline is two development games on one exact build. The damage
pipeline is 6,306 champion-to-champion events, 638 ordinary-attack candidates,
439 candidates without additional numeric-input gaps, and zero admitted damage
cases. All 439 still have semantic blockers. The seven matching conditional
stat checks and one matching conditional damage diagnostic remain separate.
There are zero sealed model holdouts. The 100 aggregate damage checks validate
the decoder, not 100 individual combat predictions.

## 2. Define the coverage denominator before reporting a percentage

Use a versioned registry of **test obligations**: specific claims to check, with
the required observations, supported model path, patch/build, condition bins,
comparison tolerance and applicable interactions. An obligation might be
"ordinary noncritical physical damage at positive armor without shields".
Do not use every champion × item × rune × patch combination as the denominator.

Keep these layers distinct: packet decoding; state reconstruction; stat
generation from loadouts; damage conditional on supplied inputs; complete
single-hit prediction; and action sequences. A downstream layer cannot inherit
verification merely because an upstream layer passed. Code coverage and
source-data extraction coverage are useful engineering diagnostics, but neither
measures agreement with the game.

Align combat grouping with the existing eight calibration families in
`src/powerspike/calibration.janet`:

| Family | Initial obligations and useful variation |
| --- | --- |
| Isolated damage | Ordinary physical attacks, simple magic damage, true damage; rank and scaling variation |
| Mitigation | Low/moderate/high resistance; zero/negative boundaries; flat/percentage penetration and reductions |
| Timing | Windup, travel, attack cadence, cooldowns, cancellation; before/at/after relevant boundaries |
| On-hit | Ordinary versus empowered/critical outcomes; trigger eligibility, cooldowns, stacking and damage components |
| Healing/shields | Gain/refresh/expiry/consumption; damage absorbed versus health removed; overheal and overflow |
| Control | Application, duration, resistance, cleanse; interruptions and effects on actions |
| Objectives | Champion-to-objective and objective-to-champion behavior; health/resistance and special-rule regimes |
| Combinations | Selected cross-family interactions and their event order |

Report champions, abilities, items and runes as additional slices. Shared armor
verification can help many champions but cannot verify every champion's attack
identity or passive. Conversely, adding another cosmetic attack name is not a
new damage mechanic. Do not declare champion-wide verification from one ability.
Optimizer quality remains a separate evaluation target.

The registry must include implemented claims, promised but unsupported claims,
and explicitly deferred claims. Unsupported behavior remains visible in the
product-scope denominator and the unknown bucket; it does not disappear because
the comparator cannot process it. Report the narrower implemented-scope view
alongside it. Keep older-patch obligations in a separate historical backlog.
Initially pin the exact supported 16.20 build rather than calling it an
unqualified "latest patch".

**Do not publish an overall League completion percentage.** The first frozen
catalogue now defines 27 combat and three stat-generation obligations; its plan
coverage is measurable, while coverage of all League behavior remains unknown.
When a registry
changes, show the old and new denominators and a scope-change annotation.

## 3. Balance breadth before accumulating repeated hits

Use evidence gates per obligation, rather than converting packet counts into
an arbitrary confidence score:

- **Unseen:** no relevant example in the corpus.
- **Observed, blocked:** examples exist but required context or semantics fail.
- **Checked:** at least one admitted comparison, with its result retained.
- **Varied:** predeclared condition and game/encounter diversity targets met.
- **Fresh-game checked:** a frozen revision has results on reserved new games.

Agreement is an independent attribute at every checked stage. Display open
discrepancies and stale/invalidated evidence even for broad or fresh-game checks.
"Fresh-game checked" means evaluated, not automatically reliable or correct.
No stage claims universal proof or automatic statistical confidence.

Schedule work to raise the lowest coverage among currently feasible priority
families. Then prefer the highest useful gain per review hour within that
frontier. Keep prerequisite-blocked families visible; first spend on shared
decoder/context gates so those families can become feasible. Do not spend equal
time on an impossible rare interaction and a cheap common mechanic solely to
make all eight bars equal. Also cap credit for repeated hits in the same
exchange: retain them all, but report distinct encounters, actors, games and
conditions separately. An encounter identifier is a proposed clustering rule,
not a guarantee that encounters within a game are independent.

For a future registry with target set U, report the fraction of obligations
reaching each evidence gate, both within each family and as an equal-family
average. Also show the minimum family coverage. Publish these as evidence
coverage, not a correctness percentage. An equal-family average prevents one
family with many cheap variants from overwhelming a small difficult family.

## 4. Cover interactions efficiently, including event order

NIST's combinatorial testing work supports testing selected combinations of
factors rather than exhaustively enumerating every full configuration. Its
state-based extension makes ordering an explicit part of coverage. This is a
useful design basis; it does not establish that pairwise tests suffice for
League's mechanics. [Practical Combinatorial Testing](https://www.nist.gov/publications/practical-combinatorial-testing),
[Ordered t-way Combinations for Testing State-based Systems](https://www.nist.gov/publications/ordered-t-way-combinations-testing-state-based-systems).

Map observed replay cases onto constrained pairwise obligations such as damage
type × resistance regime, shield type × damage type, crit outcome × on-hit
eligibility, and rank × scaling-stat band. Add selected three-way tests for
high-risk behavior, such as shield type × damage type × on-hit component.
Add temporal obligations such as shield applied → hit → shield exhausted and
buff added → refreshed → removed. Boundary cases need deliberate treatment:
expiry before versus after impact, a lethal versus surviving target, and a
counter reaching zero versus explicit removal.

Measure pairs against a frozen set of **applicable** combinations. Invalid pairs
need an explicit rule; unsupported and unavailable valid pairs remain gaps.
Replay data cannot manufacture a covering array: some valid combinations will
not occur in the corpus. Classify those as unseen and request suitable public
or contributed games; use a short controlled capture when it is cheaper than
searching many random games. Synthetic tests can exercise the code, but do not
count as replay verification or an independent game oracle.

## 5. Choose the next work by shared blockers and cost

Maintain a dependency graph linking each candidate to its missing facts. Estimate
what a decoder/context change would unlock **after all other requirements are
met**, and how many new obligations, conditions and games it would add.
Resolving one of six blockers does not admit a case with five blockers left.
Evaluate small bundles of dependent fixes, not only isolated tasks. Count the
union of newly reachable cases, so two fixes cannot both claim the same gain.

For prioritization, use an explicit queue with estimated review/development hours,
expected new coverage, severity of known discrepancies, and uncertainty in those
estimates. Prefer high gain per hour subject to the coverage floor. This is a
greedy planning heuristic, not a proven optimal solver. Stop repeatedly sampling
a well-covered condition when another eligible family is behind. Mismatches
and apparent decoder corruption can interrupt this queue.

The immediate highest-value bundle is admission of the existing ordinary-attack
subset: establish amount/shield semantics, attack identity, sampling stability
and a sufficient relevant-effect context. In parallel, broaden stat-generation
checks using periodic API anchors. The 2,850 unknown-effect events (45.2% of the
champion-to-champion corpus) deserve a prevalence/impact-ranked naming queue,
but naming all of them is not a prerequisite for the first valid comparison.
Labels alone do not establish effect behavior.

Acquire metadata first when possible, inspect likely champion/item/interaction
gaps, and download new replays in batches of at most three. Reuse cached exact
build assets. Log the available pool, selection seed, player/region/mode source
and failures; random selection inside one player's history is not population
coverage. Expand the player pool and roles deliberately. Acquire a new game
when it adds a needed condition or is reserved for evaluation, rather than to
increase a replay counter. Honor Riot's current response rate-limit headers;
quota is a resource constraint, not the main evidence objective.
[Riot Developer Portal overview](https://support-developer.riotgames.com/hc/en-us/articles/22698431229203-Developer-Portal-Overview).

Measure review and maintenance minutes from now on. The measured extraction
costs are about 39 seconds for damage/state and 15 seconds for buffs across two
games; source/naming research retained about 105 MB. These are separate runs,
not a benchmark of a combined pipeline, and omit manual research time. Those
figures favor resolving context before adding worker parallelism. Track MB,
requests, processing seconds and manual hours separately, plus cost per newly
checked obligation; report that last quantity as undefined while none is admitted.

## 6. Keep targeted discovery separate from performance estimation

Active testing research directly studies expensive evaluation labels and the
bias introduced by selective testing. It motivates selecting informative cases
and keeping track of selection probabilities. Its estimator guarantees do not
automatically apply to our correlated, partly unobservable replay corpus.
[Active Testing: Sample-Efficient Model Evaluation](https://proceedings.mlr.press/v139/kossen21a.html).

Initially allocate roughly **80% of review effort to coverage gaps and 20% to
random audit**, as an adjustable starting budget rather than a research-derived
optimum. Preregister candidate filters and random selection before seeing model
errors. For the audit, reserve whole new games; sample encounters within them
using a logged rule. Keep blocked audit draws in the report instead of replacing
them with convenient checkable cases. Once inspected or used to tune a rule,
that game is development evidence for the next revision.

Publish two separate coverage measures:

- **Balanced mechanic coverage:** equal-family coverage against the obligation
  registry, with worst-family coverage visible.
- **Replay reach:** the admitted fraction of the declared event population,
  such as champion-to-champion hits, in a named corpus or random audit sample.
  Show unclassified, unsupported, missing-context and not-yet-reviewed shares.

Later, report occurrence-weighted coverage and error using a sufficiently broad
audit pool with known sampling probabilities. Do not derive these weights from
the two selected development games and label them representative of League.
Missing/uncheckable cases cannot be corrected by weighting alone.

Report signed error, absolute error, large-error quantiles where meaningful,
tolerance violations and worst cases by family and game. For uncertainty, use
whole-game clustered analysis once enough independent games exist; with two
games show raw per-game results and say the estimate is insufficient. Repeated
hits in one game do not provide thousands of independent trials.

For scale only: with zero failures in n independent identically distributed
Bernoulli trials, a one-sided 95% upper failure bound is 1 - 0.05^(1/n). This is
about 13.9% at 20 trials and 1.0% at 300. The calculation illustrates why a
20-case bootstrap is not an accuracy certification. It is **not** a confidence
bound for our correlated and selected hits. Exact-binomial methods and their
small-sample motivation are described in [NIST's confidence interval guidance](https://www.itl.nist.gov/div898/handbook/prc/section2/prc241.htm).

## 7. The progress view to build

Keep the first screen small, with detail available per mechanic:

| Display | Meaning |
| --- | --- |
| Evidence pipeline | Unique games/events → classified candidates → sufficient context → admitted → evaluated; each count has a denominator and reason for exclusion |
| Mechanic coverage matrix | Eight families, evidence gates, games/encounters/conditions, open mismatches and stale evidence |
| Current-patch replay reach | Admitted / target events, alongside unknown and unsupported portions; scope and date visible |
| Next useful unlocks | Blocker bundles, distinct candidate/obligation gain, estimated and actual effort |
| Fresh evaluation | Reserved/inspected games, eligible/admitted/skipped counts, per-game errors and uncertainty status |
| Cost and trend | New obligations and games checked per batch; review hours, bytes and compute; scope changes and regressions annotated |

Show candidate percentages only with their exact scope. Today 439/638 (68.8%)
describes numeric-input readiness among ordinary-attack candidates, not overall
verification. Admitted damage reach is 0/6,306 in the champion-to-champion corpus.
Agreement on admitted damage is N/A, not 0% or 100%. Overall obligation coverage
and representative gameplay coverage are not measurable yet. Conditional
diagnostics get their own label and do not advance an admission bar.

Pin each view to build, decoder/schema revision, obligation-registry revision,
source snapshots and model revision. On patch changes, retain old evidence as
historical and mark current applicability pending a compatibility review.
Automatically rerun compatible regressions, but do not turn old observations
into new current-patch game evidence. Show progress deltas under a fixed scope
so adding obligations or changing filters cannot silently rewrite the trend.

## 8. Concrete implementation order and completion gates

1. **Register and report:** create the versioned obligation catalogue and an
   append-only case ledger. Inventory existing candidates, blockers and distinct
   game/actor/condition slices. Generate the pipeline and matrix from receipts;
   no manually edited progress totals. The saved baseline provides the initial
   counts. The initial ledger/dashboard is implemented; imports and reviews are
   operator-driven.
2. **Admit the first mechanic:** finish the shared gate bundle, then evaluate
   20 ordinary-attack cases. Aim for at least three games, four source champions,
   melee and ranged attacks, and three positive-armor bands. These are breadth
   goals, not confidence guarantees; record unavailable conditions rather than
   relaxing admission. The first deeply reviewed case is the gate before scaling.
3. **Raise the coverage floor:** establish simple physical, magic and true
   damage baselines, then the feasible mitigation and timing obligations. Add
   shields/healing, on-hit and control as their observation dependencies permit.
   Objectives stay visibly blocked until their entity/state interpretation and
   oracle are adequate. Select interactions from uncovered pairs and known risks.
4. **Freeze and audit:** before tuning further, freeze code/data/filter/tolerance
   identities and evaluate reserved fresh games. A bootstrap allocation can use
   two development games for each audit game, but independence and pool diversity
   matter more than that ratio. No accuracy claim until the audit's actual scope,
   admitted fraction and uncertainty support it.
5. **Review after five batches:** compare expected versus actual unlocks and
   effort. Adjust the 80/20 split, diversity targets and work queue. Defer old
   patches and rare interactions when their marginal current-patch value is low.

The intended outcome is steady growth in both the least-covered mechanics and
the fraction of real replay situations that can be checked, with measured
agreement and uncertainty displayed alongside that growth.

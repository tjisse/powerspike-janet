# Build optimization and combat simulation

The accepted scope is a Janet engine and Datastar Rift HUD for reproducible build comparisons, duels and objectives on user-selected patches. Estimates across the roster come first; source availability, implemented semantics and in-game evidence remain separate. Keep signed RPM/DNF deployment and existing CLI regressions.

## Milestone sequence and acceptance

1. **Runtime patches:** immutable packages, provider discovery, shared background downloads, progress/cancel/retry, persistent storage, offline use and patch-specific assets. Fetch two builds without rebuilding, reproduce both after restart and preserve usable packages after failure.
2. **Ability/effect interpretation:** resolve current P/Q/W/E/R references and forms; keep markup and resolve tooltip expressions from named values, effects and structured calculations. Numerical expressions and semantics stay separate. Support declarative semantic overrides, coverage per champion and explicit unresolved components. Extend to items/runes/summoners. Regress legacy references, rank indexing, duplicate damage and conditional branches.
3. **Stateful combat:** one chronological queue for health/resources/regen/death, casting/timing, missiles, charges/recasts, attacks/resets, buffs/stacks/periodic effects, shields/healing/control and shared triggers. Bound events/procs and use reproducible sampled randomness with uncertainty. Introduce exceptional handlers by mechanic family.
4. **Duels/objectives:** both participants have loadouts and declared strategies; use one-dimensional movement/range. Patch-specific objective stats, restrictions and retaliation require time/level inputs. Report kill/death times, health/resources, damage/healing/absorption/control and assumptions. Missing objective sources remain explicit.
5. **Optimization:** legal six-slot inventories, budget/owned locks/exclusions/restrictions/next purchase. Exhaustive small pools are the correctness reference; bounded full-catalog search reports best found. Five-second and thirty-second budgets, streaming progress/cancel, common trial seeds and finalist resampling. Burst/sustained/duel/survival/utility/objective metrics remain separately explained. Extend to optional locked rune/summoner/skill-order choices with fixed opponents/strategies.
6. **Product completion:** patch/scenario/opponent/ability controls, comparison charts, expanded evidence, local saves, shared URLs and versioned JSON import/export. Preserve patch/snapshot/engine identity and show reproduction compatibility warnings. Grow calibration by mechanic family without blocking estimates.

## Required release checks

Preserve all curated calculations and five measured Annie fixtures. Retained real parser fixtures must include malformed, ambiguous and unsupported structures; unknown mechanics never become measured zero. Cover ordering, exhaustion, simultaneous deaths, projectiles, conditionals and proc recursion. Verify legality/scoring/reproducibility/cancellation and isolation between patches and users. Exercise concurrent/cold downloads, offline restarts, corrupt caches and provider errors. Continue formatter/core/frontend/relocated-runtime/signed-DNF checks, including upgrades preserving cached data and port settings. Publish each accepted milestone through the existing release workflow.

## Current progress

**Work resumed on 2026-10-05.** Milestones 1–3 are released. Milestone 4 has passed local checks and is being published as v0.5.0. Milestones 5–6 remain in progress; the full accepted plan is unfinished.

Milestone 1 is released as v0.2.0 with successful signed RPM/DNF installation checks. Live runtime downloads retained 16.18.1 and 16.17.1 alongside the initial 16.19.1 package, and both were reproduced after an offline restart.

Milestone 2 is released as v0.3.0 with successful signed RPM/DNF checks. All 173 champions on retained 16.18.1 simulate without errors; 156 have recognized ability damage. Full records, localized tooltips and bounded calculations remain separate from in-game verification.

Milestone 3 is released as v0.4.0 with successful signed RPM/DNF checks. The shared chronological engine handles health/resources, regeneration, death, projectiles, control/interruptions, shields/healing, periodic hits, attack modifiers/resets, charges/recasts, temporary stats, cleanses and bounded triggers. Real-record regressions cover item/rune/summoner handlers. Canonical scenarios and frontend duels share this engine; seeded trials report mean outcomes and sampling uncertainty. Exceptional forms, pets and passive semantics remain explicit omissions to extend by family. The legacy wrappers and five Annie stat measurements remain regressions.

Milestone 4 has passed local release verification for v0.5.0. Both participants have full inventories, rune/summoner selections, ranks, priorities, activation conditions, starting health/resources, hit assumptions and 1D approach/hold-range controls. Retained records cover turrets, Baron, Herald and seven dragons (six elemental dragons and Elder). Objective level/time, retaliation and minion presence are declared inputs. Sourced restrictions, caps, immunity and turret heating/backdoor effects interact through the event queue. Objective server scaling, special attacks, plating, Baron debuffs and Herald eye behavior remain explicit coverage gaps. Health/resource traces include before/after values; outcomes expose damage sources, kill/death times, healing, absorption and effective control. Health-cost descriptions now override zero-filled cost arrays where resolvable.

Milestones 5–6 remain required: bounded legal optimization with optional loadout choices, and scenario save/share/import/export with evidence and upgrade verification.

## Verification checkpoint

- Last released commit: `422e59a`, v0.4.0. Earlier milestone releases are v0.2.0 (`7313b3b`) and v0.3.0 (`9d22876`). Their GitHub release workflows, including signed DNF installation, succeeded.
- Local version files say `0.5.0`; this is a pending release version, not a published release. Existing milestone 4 changes and new retained fixtures remain in the working tree. No milestone 4 commit, tag or publication was made before pausing.
- The complete local milestone 4 command `make format test test-web test-runtime` finished successfully. This includes 83 core tests, the five measured Annie fixtures, 16 Python tests, 15 frontend tests, parser/combat/shared-effect/objective/configuration/package checks, executable compilation and relocated executable checks. Output is retained locally in `build/milestone4-checks.log` (ignored build output).
- A separate retained 16.18.1 roster check completed for all 173 champions without failures; 156 have recognizable damage abilities. These are source-derived estimates, not 156 calibrated kits.
- New real-record parser regressions resolve Dr. Mundo's flat Q and current-health W costs and Zac's current-health Q cost. Continuous or ambiguous resource costs remain unresolved. The objective fixtures retain exact matching 16.18.1 source records and provenance.
- Milestone 4 local RPM build, payload/digest/permission/service checks and relocated runtime checks passed on resume. Its signed DNF release check is pending publication. The browser preview must be checked/restarted when work resumes; its currently running content has not been verified against the final working tree.

## Remaining delivery order

1. Review the preserved milestone 4 diff and coverage notes. Finish its RPM checks, publish v0.5.0 through the existing workflow and verify the signed DNF result. Recheck the frontend preview against the current files.
2. Implement milestone 5 around the shared scenario engine: validate patch-specific item legality and purchase groups; support six slots, budget, owned locks, exclusions and next purchase; compare exact small-pool enumeration with bounded full-catalog search. Add five/thirty-second budgets, background progress and cancellation, common trial seeds, finalist resampling and separately explained scoring presets. Expose alternatives and missing effects that may change rankings. Add optional legal rune pages, summoner pairs and skill orders with locks while holding the opponent and strategies fixed. Release the milestone after its correctness and runtime checks pass.
3. Implement milestone 6: finish optimization/comparison/evidence UI, local scenario saves, shared URLs and versioned JSON import/export preserving exact patch, snapshot and engine identities. Add compatibility warnings, calibration tooling by mechanic family, real upgrades from an earlier release preserving cached data and configured ports, and browser verification of the complete configure/optimize/compare/explain/save/reproduce flow. Release after the remaining gates pass.

Known accuracy limits at this checkpoint include exceptional champion forms/pets/passives, many item/rune triggers, conditional or ambiguous tooltip semantics and the objective server mechanics listed above. Available source data, implemented mechanics and in-game checks must continue to be shown separately. The five Annie measurements validate their original stat cases; they do not validate every new combat handler.

## Source interpretation

Reuse the original Clojure description-stat parsing approach and structured calculation parsing, while correcting its unsupported-value and damage-semantics shortcuts. Tooltip resolution follows [CommunityDragon's explanation](https://hextechdocs.dev/resolving-variables-in-spell-textsa/). Provider discovery follows [Riot's Data Dragon documentation](https://developer.riotgames.com/docs/lol#data-dragon). Do not substitute `latest` or combine numeric values across patches.

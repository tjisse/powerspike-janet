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

Milestone 1 is released as v0.2.0 with successful signed RPM/DNF installation checks. Live runtime downloads retained 16.18.1 and 16.17.1 alongside the initial 16.19.1 package, and both were reproduced after an offline restart.

Milestone 2 is under release verification for v0.3.0. Full retained records resolve current ability references and localized descriptions, including hashed keys. Typed effects and bounded expressions drive the first shared event engine; coverage and assumptions appear in the Rift HUD. Real-record regressions cover rank origins, total/base/bonus scaling, duplicate displays, conditional branches, malformed structures and unknown formulas. The initial seed remains a historical subset until refreshed. Milestone 3's stateful foundation is implemented, but trigger families, charges, recasts and exceptional handlers remain in progress. Duels/objectives, optimization and scenario persistence remain required work.

## Source interpretation

Reuse the original Clojure description-stat parsing approach and structured calculation parsing, while correcting its unsupported-value and damage-semantics shortcuts. Tooltip resolution follows [CommunityDragon's explanation](https://hextechdocs.dev/resolving-variables-in-spell-textsa/). Provider discovery follows [Riot's Data Dragon documentation](https://developer.riotgames.com/docs/lol#data-dragon). Do not substitute `latest` or combine numeric values across patches.

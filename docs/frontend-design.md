# Powerspike frontend direction

Design and first local implementation, 2026-10-04. The user selected **Rift HUD** after reviewing the League-themed alternatives. The frontend lives under `web/`; the calculation core retains its independent CLI and tests.

## Main purpose

Help a player answer “Which item choice helps in this fight, and why?” Start with a champion, level, budget and combat scenario; compare builds under exactly the same conditions. Keep the item's cost and damage tradeoff visible. Avoid a universal “best build” claim.

The first draft explored **Build studio** and **Compare desk**. The user reviewed Build studio, requested a stronger League theme with real champion/item icons, removed slogans, and asked for multiple options before implementation.

The second draft offers three distinct arrangements:

- **Rift HUD**: compact navy/gold layout, horizontal scenario controls, build rows beside the selected inventory, and a damage chart with spell icons marking hits.
- **Hextech workshop**: champion and scenario rail, selected inventory above a gallery of alternatives, softer panel corners and gold accents.
- **Scout table**: flatter green/charcoal workspace with a sortable-looking comparison table, larger item icons and selected stats beside the chart. Actual sorting is by modeled damage; it is not a separate interactive sort control.

All use actual Annie, item and Q/W art from Data Dragon 16.19.1, with names and accessible labels. Typography, borders and a restrained gold accent provide the League theme without decorative slogans. The preview starts in dark appearance and provides a light appearance design control. Use numeric alignment, comfortable spacing and color plus text for evidence states. These are independent Powerspike layouts, not replicas of the League client.

## Screen content

- Scenario: champion, level, combat window and target armor/MR. Show scope before evaluation: the unvalidated catalog supports permanent modeled stats and generic attacks, with a separate Annie Q/W adapter.
- Builds: six editable inventory slots, full item names and total cost; custom inventory and Annie sample alternatives. Click a comparison to inspect it. Owned-item locking awaits search support.
- Result: damage within the modeled scope as the primary metric, with DPS secondary. Name attack-only graphs **Basic attacks over time**, and show **Spells: not modeled** rather than zero spell damage for missing kits. Annie's graph identifies **Q/W + attacks over time** and splits Q/W damage from attacks. Never imply a kill-time prediction while target health remains fixed.
- Evidence: distinguish **checked in-game**, **from patch data** and **assumed** for each relevant mechanic. No aggregate confidence percentage. In-game checks identify the measured scenario, patch and excluded fields. Stat evidence never validates combat damage implicitly.

Keep the ordinary flow focused on item choices. Detailed formulas, source records and observations belong behind “Model & evidence,” where they help explain a result. Preserve enough detail to reproduce it.

## First implemented slice

The live Rift HUD now includes all 173 champions and 870 items from the matching patch, with searchable icon pickers, six independent editable slots, and a custom build. The item picker defaults to Summoner's Rift shop entries according to source flags; an all-modes filter exposes every entry. Entries with other-mode or purchase/champion restrictions remain selectable and show notes. All catalog entries are labeled unvalidated.

Three hand-selected Annie presets remain available. Annie uses Q/W, ordinary attacks and learned-R penetration; other champions use ordinary attacks only. Controls cover all levels, fight windows of 0.5–30 seconds and target armor/MR of 0–1000. Cost is visible without a budget limit. Per-build notes expose excluded effects and inventory restrictions, while the five measured Annie fixtures retain their original narrow scope.

The existing Janet stat, attack and rotation modules supply every calculation. Catalog builds form an unvalidated stat sandbox; the curated CLI's strict legality checks remain independent. `janet-html` renders the page and fragments; `tjisse/datastar-janet` with its spork adapter patches results and champion details, following the SQLite viewer's architecture. Dependencies, the matching browser bundle and all 1,043 champion/item icons are pinned and served locally. `make serve` starts the development endpoint at `http://localhost:8090`.

Input changes use a 200 ms debounce; all evaluations originate from one persistent element so the pinned Datastar version can cancel prior requests. Previous results dim while a request is pending. Normal GET forms remain usable without JavaScript. The evidence panel calculates the five retained stat comparisons at startup, including their exclusions; it does not elevate them to combat validation.

Future optimizer searches should require an explicit action. Their states must distinguish running, complete within the selected pool, and evaluation limit reached, with results tied to the exact scenario. Catalog search filters selection choices; it does not optimize a build.

The current engine does not support fixed-owned-item search, top-N optimizer output, rune-aware combat or complete champion kits. These require core work before the corresponding UI becomes active. A comparison of three hand-selected sample builds is not an optimizer result.

Verification: thirteen frontend contract tests, including every champion and item and explicit attack-only graph scope, five catalog-normalization tests, offline provenance checks, and live browser checks for pickers, independent slot replacement/removal, server updates, rapid-change cancellation, excluded effects, real icon loading, widths down to 320 px, and inventory forms with JavaScript disabled. The original core and source checks remain separate.

## Design preview data

The interactive preview uses 54 precomputed results from the current Janet engine: two levels, three target MR values, three windows and three hand-selected builds. All use Annie, target armor 80, distance 300, Q-before-W priority, a 10,000-gold budget and no rune/shard effects. Attack windup is the current 30% assumption; basic-attack travel is assumed zero. The preview does not contact a running backend.

Regenerate the sample data with `build/janet docs/design/export-scenarios.janet`. The stat-evidence view uses the five retained Practice Tool fixtures and clearly identifies their scope. Combat estimates remain unverified in-game.

The second preview loads art directly through jsDelivr from the pinned [Data Dragon mirror](https://github.com/noxelisdev/LoL_DDragon/tree/1cf34d485c572a9894c223efd3d66c1e5ad7f22f), whose retained manifest identifies version 16.19.1. [Asset metadata](design/art-assets.json) records the commit, URLs and image identities. This mirror supplies artwork only; the existing hashed source snapshot continues to supply numeric game data. The eventual app can serve the matching art locally.

## Responsive and interaction behavior

At desktop width, keep inputs and results visible together. At narrow widths, place inputs before comparison and detail; do not compress the item labels or charts. Native inputs, visible focus, labeled controls and non-hover access are required. Empty, invalid, stale and incomplete results must be understandable without looking at raw logs.

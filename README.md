# PowerSpike

A Janet rebuild of [powerspike-core](https://github.com/tjisse/powerspike-core), a League of Legends item-build optimizer. The goal is explainable, reproducible calculations that can be checked against the game.

The **Rift HUD frontend** selects archived Data Dragon builds and fetches matching CommunityDragon records without rebuilding. Packages retain full champion records and individual spell descriptions, provider URLs and SHA-256 identities. Downloads run on a shared background worker with progress and cancellation; completed snapshots publish atomically. Cached patches work offline. The initial **26.19** snapshot (Data Dragon **16.19.1**) includes **173 champions and 870 items**, explicitly **unvalidated**, with searchable pickers and six inventory slots. The independent CLI retains its curated Garen/Annie regressions.

## Frontend

Run from this project folder in WSL/Linux:

```sh
make serve
```

Open **http://localhost:8090**. The first run builds the local Janet runtime if needed, prepares pinned public dependencies, and downloads matching champion/item/ability art and the SDK-compatible Datastar browser bundle. Subsequent runs use those local files. No Node runtime, frontend build server or runtime CDN requests are required.

Select a champion and an opponent. Each panel has an independent level, six item slots, runes, shards, summoner spells, skill order and attack priority. The panels sit side by side on desktop and collapse into editable summaries on mobile. Item searches open beside each inventory: set a budget, keep selected items, compare the current and proposed builds, and apply or undo the item changes. The opposing champion's configuration stays fixed during a search.

Edits update build stats without simulating combat. **Run matchup** updates the shared health or damage graph; the previous result is marked when its configuration is outdated. The outcome and graph describe trial zero, with health shown as both HP and percentage. Select a combat event or inspect a time to see damage, healing, shielding and control from either champion. Detailed champion and fight settings are collapsed by default. Champion defenses come from their builds; duel setup has no separate target-health or resistance inputs. Saved practice, objective and reference scenarios retain their existing controls.

The item picker defaults to Summoner's Rift shop entries; **All modes & special items** exposes the full sandbox catalog. Other-mode, unavailable and champion-restricted items remain selectable and appear in coverage notes. Catalog availability flags are unvalidated.

Controls cover levels 1–18, a 0.5–120 second window and starting distance. The initial seed retains the historical Annie Q/W comparisons and basic attacks elsewhere. Starting a fight with another champion or duel opponent from that seed automatically downloads full patch records, localized tooltips, item calculations and rune records, then opens the completed patch with the current fight settings. Saved, imported and shared scenarios retain their exact snapshots; an explicit refresh can adopt a newer revision. The initial estimate remains available if the download fails; **Refresh patch data** retries it. Fetched kits expose P/Q/W/E/R icons, ranks, effective cooldowns and coverage. Recognized effects contribute through a chronological Janet engine with health, resources, shields, healing, control and seeded hits/crit. Configure each champion in its panel; activation rules, starting health/resources, hit chance and movement are under its advanced controls. Objective records are available after refreshing a patch. Their declared-level client stats and ordinary retaliation remain estimates; missing server mechanics are reported. The shared engine also supports charges/recasts, temporary stats, slows, cleanses and bounded trigger counters. Complete alternate forms, pets, passive triggers and exceptional timing remain explicit coverage gaps where handlers are missing. Practice and duel simulations use this engine; the `mode=legacy` wrapper preserves the original curated comparisons.

The parser reuses the prototype's description interpretation strategy while keeping damage type separate from AD/AP scaling. It resolves named values, effect arrays, common structured calculation families, modified expressions and supported conditional branches. Patch-bounded semantic overrides describe orb phases, repeated fox-fires, empowered attacks and learned-R penetration using fetched numerical values. Unknown formulas and ambiguous branches remain unresolved. Complete character records and matching provider sources are retained alongside immutable normalized packages. Item, rune and summoner descriptions use the same pipeline; parsing a passive does not automatically supply its combat trigger. Current handlers cover Hextech Alternator, Blade of the Ruined King on-hit damage/cap, Spellblade damage for Sheen/Lich Bane/Trinity Force/Essence Reaver/Iceborn Gauntlet, Lich Bane's temporary attack-speed bonus, Nashor's Tooth on-hit damage, Luden's Echo single-target damage, Electrocute, Scorch, health-conditional damage from Coup de Grace/Cut Down/Last Stand, Transcendence's level-gated haste, Ignite, Heal (self), Barrier, Exhaust, Ghost, Cleanse and base Smite. Spellblade movement bonuses, mana restoration and frost fields remain explicit omissions. Matching shared spell records are fetched on refresh. Their timing/semantics are estimates with explicit omissions; see [Lich Bane timing notes](docs/lich-bane.md). Select seeded trials to show mean outcomes and approximate 95% sampling intervals; charts show trial zero.

Simulation runs on one compute worker; downloads use a separate network worker. Queues and result history are bounded. Evaluation caches include scenario state, snapshot and engine identity. The browser renders supplied events and never calculates combat damage. Inventory restrictions and unimplemented effects remain in Patch & evidence. Item searches retain the selected runes, summoners and strategies.

The developer page at `/developer` reports comparisons against the five identity-free Practice Tool fixtures, source identities and mechanic diagnostics. Verification progress remains available at `/verification`. The player view describes a simulated fight and exposes its conditions separately from this engineering evidence. The fixture comparisons are evaluated on import in development and embedded during the release build. This stat evidence is separate from combat estimates. The browser renders the supplied hit events as a responsive chart; it does not calculate combat damage.

`make test-web` runs the frontend model/rendering checks. With Playwright installed and the local app running, `node test/matchup-browser.cjs` checks the paired configuration flow, optimization, Undo, mobile layouts and native form fallback. `PS_TEST_URL`, `PLAYWRIGHT_MODULE` and `BROWSER_EXECUTABLE` can select a test server or browser runtime. `web/deps.lock` pins the SDK and rendering dependencies; generated modules and downloaded assets stay under ignored `build/`. The local development server binds to loopback. Restart it after changing frontend files.

The [catalog notes](data/16.19.1/catalog/README.md) explain retained sources, normalization boundaries and reproducibility. The unvalidated catalog does not expand the scope of the five measured Annie fixtures.

### Comparing your item choices

Select **Pin current items** below the damage summary, then edit an inventory slot or apply an optimized build. The comparison shows pinned and current damage, DPS, gold and their differences. Both builds rerun with the current champion, level, opponent, runes, skill configuration, fight settings and trial seeds; only the item inventory changes. An empty inventory can be pinned. Pinned items stay in the current page session; saved scenarios, exports and share links retain the selected build rather than the comparison.

Pinned scenarios require the same champion and exact patch snapshot. Incompatible or invalid references show an explanation while the current simulation remains available. Simulation details beside the headline result explain the fight conditions; the pinned build also retains its own exclusions. A scenario that fails evaluation must be corrected before its previous result can be saved, exported or shared.

See the [player beta rollout notes](docs/player-beta.md) for remaining release work.

## Build, format and deploy

The release build follows [sqlite-viewer-janet](https://github.com/tjisse/sqlite-viewer-janet): one executable with Janet, pinned Jurl/libcurl bindings and browser code embedded. Immutable game packages and artwork live outside the executable. It runs without a source tree, installed Janet or Python; libcurl, OpenSSL and CA certificates are runtime dependencies.

```sh
make format                 # Same pinned Spork janet-format as the SQLite viewer
make format-check           # Reports differences without rewriting
make build                  # dist/bin/powerspike
make test-runtime           # Exercise a copied binary in an empty directory
make rpm                    # Tests, build, then x86_64 RPM on an x86_64 builder
```

The build requires Git, a C compiler, Make, Python 3, ripgrep, libcurl development headers and OpenSSL development headers; RPM packaging also requires `rpmbuild`, `readelf` and standard archive tools. Dependencies are pinned in `web/deps.lock` and the Janet bootstrap. The formatter excludes downloaded dependencies, generated build output and data-only `.jdn` snapshots. `make test` and `make test-web` enforce formatting.

Set `PS_PORT` at runtime, for example `PS_PORT=8765 make serve` or `PS_PORT=8765 dist/bin/powerspike`. `--port` overrides the environment; `PS_HOST` / `--host` configure the listen address. The default is `127.0.0.1:8090`. Invalid ports fail startup.

Published x86_64 releases use a signed DNF repository, following the SQLite viewer's Releases + Pages setup. On a compatible RPM/systemd host with **glibc 2.38+**:

```sh
sudo curl -fsSL https://tjisse.github.io/powerspike-janet/rpm/powerspike.repo \
  -o /etc/yum.repos.d/powerspike.repo
sudo dnf install powerspike
```

The RPM installs `/usr/bin/powerspike`, a systemd service and preserved configuration in `/etc/powerspike/powerspike.env`. Set `PS_PORT` there and point your Cloudflare Tunnel HTTP route at `http://127.0.0.1:PORT`. Enable the service with `systemctl enable --now powerspike`. Subsequent versions arrive through `sudo dnf upgrade powerspike`. See [RPM deployment instructions](docs/rpm-hosting.md) for compatibility and configuration, and [release maintenance](docs/releases.md) for publishing a version. Local `make rpm` builds are unsigned; the release workflow signs both packages and repository metadata using the dedicated PowerSpike key.

## Run

With Janet already installed:

```sh
janet test/run.janet
janet main.janet demo Garen 18
janet main.janet optimize Garen 18
janet main.janet rotation Annie 18
janet main.janet optimize-abilities Annie 18
janet main.janet optimize-total Annie 18
```

Without Janet installed, `make test` builds Janet **1.42.1** locally under `build/` and prepares the pinned Spork formatter. It needs Git, a C compiler, Make, Python 3 and ripgrep; no global installation is required. The core library itself has no Janet package dependencies. The full `make test` suite also prepares the pinned web/native dependencies because replay comparisons invoke the production engine; it requires the libcurl and OpenSSL development headers listed above. The simulation and stat comparison are Janet; Python standard-library helpers handle HTTPS/JSON transport and retained-source verification.

```sh
make test
make demo
make optimize
build/janet main.janet optimize-total Annie 18
```

For an existing interpreter, `make test JANET=/absolute/path/to/janet` also works.

The demo uses a stationary target with 80 armor and 80 magic resistance, a five-second window, and a 10,000-gold budget. Basic-attack windup is an explicit **30% assumption**, and basic-attack projectile travel is assumed zero. Annie's Q uses 300 distance and the source projectile speed. CLI output states these assumptions.

## What changed from the prototype

- Game data is a checked-in snapshot with matching patch identifiers and source hashes. The core API rejects mixed item or spell patches.
- Garen and Annie AD growth comes from the matching character records. Their Data Dragon entries incorrectly report zero.
- Attack-speed base and ratio are separate; Annie's source values differ.
- Percentage stats consistently use fractions. Crit chance, penetration and critical damage stay in their own units.
- Spell damage type is explicit. AP scaling does not imply magic damage.
- Skill ranks obey level gates and the allocation order is checked at each level.
- Spells and attacks share an action timeline; damage lands after casts/windup and travel.
- Builds obey inventory slots, gold, map availability, duplicate rules and item groups. Boots are optional.
- A bounded exhaustive search provides an exact reference result for small candidate pools. It reports when the evaluation limit prevents completion.

“Optimal” always means **within the supplied item pool, scoring model, combat scenario and declared action strategy**. It does not mean the best full-game build for that champion.

## Library

`src/powerspike/core.janet` exposes `evaluate-build`, `optimize-attacks`, `evaluate-rotation`, and `optimize-rotation`. Lower-level modules separate stats, damage, build legality, skill allocation, action evaluation and strategy generation. There is no network access during evaluation.

Annie's strategy casts Q, then W, whenever ready and affordable, and uses available time for basic attacks when requested. Ability optimization disables attacks. Total optimization includes them in the same timeline. The item search does not optimize spell ordering.

Champion adapters own spell selection, rank-array indexing and damage semantics. The engine never sums every extracted calculation or silently defaults an unknown formula to zero.

## Accuracy and next work

Source-derived values and mathematical regression tests are implemented. **Five measured Annie snapshots agree: ten baseline, eleven Cloak and twelve stats in each Void Staff capture**, including supported shard bonuses. The level-6 pair checks nonlinear growth and learned-R penetration combining multiplicatively with Void Staff (40% becomes 46%). Movement speed is excluded pending Celerity handling. The captures establish fractional API crit chance, percentage critical damage, and a remaining-resistance fraction for magic penetration. Damage and timing remain unvalidated. These tests are not evidence that all League mechanics have been reproduced. Most mechanics should come from explicit rules and matching data; targeted game observations check ambiguities and exceptions.

Read [the mechanics and evidence notes](docs/mechanics.md), [the calibration research](docs/calibration-research.md), [the stat collection and comparison guide](docs/stat-validation.md), [the original implementation audit](docs/original-audit.md), and [the damage/timing observation template](docs/observation-template.jdn).

Replay verification is the preferred next route for scaling combat evidence. The [replay workflow and coverage policy](docs/replay-verification.md) includes random downloads, offline recovery, reviewed single-hit comparisons, and cost reports. An exact-build 16.20 decoder now reads **90,230 damage packets** across two Riot replays, with all 100 aggregate damage checks agreeing with Riot to within one point. It attaches partial preceding health, shield candidates, armor and magic resistance observations, preserving their age and wire order. The two files took about 39 seconds to process without launching the game. **No replay has yet established combat-model accuracy**: exact hit-time conditions, inventories, buffs, ranks, attribution and matching model data remain incomplete. Decoder checks and model comparisons are tracked separately.

The subsequent [gap audit](docs/replay-verification.md#gap-audit-and-offensive-stats-2026-10-18) recovers offensive stat components for all **6,306 champion-to-champion hits** and identifies 638 basic-attack candidates. AD agrees with 528 of 530 Riot snapshots and AP with 529 of 530, within one point. A saved first attack witness includes its stat provenance, health bracket and API context. Relevant buffs, sampling and shield semantics still block admission as a model-validation case.

The [buff/context pilot](docs/replay-verification.md#current-buffcontext-pilot-1620) decodes **52,801** buff add/remove/counter records across both games. Matching 16.20 inputs now produce seven exactly matching conditional stat checks through the production model. Its first conditional damage diagnostic predicts **54.166667**, versus **54.166664** recorded. Attribution, sampling and effect/shield review still prevent admission as a verified damage case; these diagnostic matches are not a model accuracy score.

The [coverage strategy](docs/replay-coverage-strategy.md) proposes balancing evidence across mechanics and selected interactions, with a separate fresh-game audit. A [frozen progress baseline](observations/replays/verification-progress-2026-10-18.json) records the current evidence pipeline and explicitly leaves overall coverage unknown until its obligation catalogue is defined.

The [verification tracker](docs/replay-coverage.md) now implements a 27-condition combat catalogue plus three stat-generation targets, an append-only private ledger and a public progress report. Open `/developer` or `/verification` to inspect the pipeline, mechanic coverage, unresolved work, fresh-game results and resource/history records. `make verification-report` regenerates the view after imports. The initial ledger contains all 6,306 retained champion-to-champion hits; provisional diagnostics remain separate from admitted evidence.

Annie's learned-R penetration is included in rotation evaluation. Stat comparison supports the static attack-speed, movement-speed and flat-health shards from the first measurement. The combat/optimization CLI still omits rune effects and shards. Annie E, R casts/Tibbers, passive stun, other champion abilities, attack resets, buffs, target-health changes, resource regeneration, shields, item procs, role quests and champion-specific attack exceptions are not modeled yet. Those exclusions describe the legacy curated CLI. The frontend uses the shared stateful engine and reports handler coverage for each scenario; exceptional champion behavior remains incomplete.

`make verify-sources` checks retained hashes, current spell references and normalized values. The local API collector has captured five live Practice Tool snapshots, retained as stat-comparison regressions; see [validation results](docs/validation-results.md). Further stat checks can cover additional items, armor penetration, levels and R ranks; damage and timing checks need isolated attacks and Annie Q/W recordings with combat rune effects controlled. Complete champion adapters and item effects can expand from that evidence.

The combat UI includes background item optimization with five- or thirty-second compute budgets. Choose a budget, item pool, exclusions and locks; next-purchase mode credits owned recipe components once. Small pools are exhaustive references, while full-shop and optional rune/summoner/skill searches report best found. Finalists share seeded trials and show coverage notes. Missing item or champion effects can change the ranking.

Scenarios can be saved locally, shared through URLs and imported/exported as versioned JSON. Exact snapshot and model identities are visible in the evidence view; older models warn before recomputation. Both participants' stat shards and supported rune effects share the same stats and combat calculations, including optimization and tooltip inputs. See [rune and shard coverage](docs/runes.md). The packaged `--simulate`, `--optimize` and `--calibrate` JSON commands use the same engine as the UI. See [scenario and calibration instructions](docs/scenarios.md).

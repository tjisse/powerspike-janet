# PowerSpike

A Janet rebuild of [powerspike-core](https://github.com/tjisse/powerspike-core), a League of Legends item-build optimizer. The goal is explainable, reproducible calculations that can be checked against the game.

The **Rift HUD frontend** selects archived Data Dragon builds and fetches matching CommunityDragon records without rebuilding. Packages retain full champion records and individual spell descriptions, provider URLs and SHA-256 identities. Downloads run on a shared background worker with progress and cancellation; completed snapshots publish atomically. Cached patches work offline. The initial **26.19** snapshot (Data Dragon **16.19.1**) includes **173 champions and 870 items**, explicitly **unvalidated**, with searchable pickers and six inventory slots. The independent CLI retains its curated Garen/Annie regressions.

## Frontend

Run from this project folder in WSL/Linux:

```sh
make serve
```

Open **http://localhost:8090**. The first run builds the local Janet runtime if needed, prepares pinned public dependencies, and downloads matching champion/item/ability art and the SDK-compatible Datastar browser bundle. Subsequent runs use those local files. No Node runtime, frontend build server or runtime CDN requests are required.

Choose a champion, then select any of the six inventory slots to add, replace or clear an item. The item picker defaults to Summoner's Rift shop entries according to the patch's availability flags; switch to **All modes & special items** to access every entry. Search by champion name/role or item name, stat and ID. Other-mode, unavailable and champion-restricted items remain selectable in this sandbox and show inventory notes. All catalog entries carry an unvalidated status; those flags are not proof of in-game availability.

Controls cover levels 1–18, a 0.5–30 second window, target health, starting distance and target resistances. The initial seed retains the historical Annie Q/W comparisons and basic attacks elsewhere. Use **Refresh patch data** to fetch full records, localized tooltips, item calculations and rune records. Fetched kits expose P/Q/W/E/R icons, ranks, effective cooldowns and coverage. Recognized effects contribute through a chronological Janet engine with health, resources, shields, healing, control and seeded hits/crit. The declared strategy prioritizes Q/W/E/R, then ordinary attacks, approaching into attack range. Alternate forms, pets, passive triggers, recasts and exceptional timing remain explicit coverage gaps where handlers are missing.

The parser reuses the prototype's description interpretation strategy while keeping damage type separate from AD/AP scaling. It resolves named values, effect arrays, common structured calculation families, modified expressions and supported conditional branches. Patch-bounded semantic overrides describe orb phases, repeated fox-fires, empowered attacks and learned-R penetration using fetched numerical values. Unknown formulas and ambiguous branches remain unresolved. Complete character records and matching provider sources are retained alongside immutable normalized packages. Item, rune and summoner descriptions use the same pipeline; parsing a passive does not automatically supply its combat trigger.

Simulation runs on one compute worker; downloads use a separate network worker. Queues and result history are bounded. Evaluation caches include scenario state, snapshot and engine identity. The browser renders supplied events and never calculates combat damage. Inventory restrictions and unimplemented effects remain visible below the selected build; full scenario optimization is the next delivery stage.

The evidence panel reports comparisons against the five identity-free Practice Tool fixtures. They are evaluated on import in development and embedded during the release build. Its stat evidence is separate from combat estimates. The browser renders the supplied hit events as a responsive chart; it does not calculate combat damage.

`make test-web` runs the frontend model/rendering checks. `web/deps.lock` pins the SDK and rendering dependencies; generated modules and downloaded assets stay under ignored `build/`. The local development server binds to loopback. Restart it after changing frontend files.

The [catalog notes](data/16.19.1/catalog/README.md) explain retained sources, normalization boundaries and reproducibility. The unvalidated catalog does not expand the scope of the five measured Annie fixtures.

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

Without Janet installed, `make test` builds Janet **1.42.1** locally under `build/` and prepares the pinned Spork formatter. It needs Git, a C compiler, Make, Python 3 and ripgrep; no global installation is required. The core library itself has no Janet package dependencies. The simulation and stat comparison are Janet; Python standard-library helpers handle HTTPS/JSON transport and retained-source verification.

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

Annie's learned-R penetration is included in rotation evaluation. Stat comparison supports the static attack-speed, movement-speed and flat-health shards from the first measurement. The combat/optimization CLI still omits rune effects and shards. Annie E, R casts/Tibbers, passive stun, other champion abilities, attack resets, buffs, target-health changes, resource regeneration, shields, item procs, role quests and champion-specific attack exceptions are not modeled yet. The frontend explicitly presents catalog-wide estimates with these exclusions; the strict CLI still uses its curated snapshot.

`make verify-sources` checks retained hashes, current spell references and normalized values. The local API collector has captured five live Practice Tool snapshots, retained as stat-comparison regressions; see [validation results](docs/validation-results.md). Further stat checks can cover additional items, armor penetration, levels and R ranks; damage and timing checks need isolated attacks and Annie Q/W recordings with combat rune effects controlled. Complete champion adapters and item effects can expand from that evidence.

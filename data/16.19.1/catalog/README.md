# Unvalidated patch catalog

All 173 champions and 870 item entries from Data Dragon 16.19.1 are retained, including other modes, upgrades and special entries. This is frontend selection coverage, not complete champion-kit or item-effect coverage. Every record has `status: "unvalidated"`.

`sources/champions-ddragon.json` and `sources/items-ddragon.json` retain Riot's complete responses. Their hashes match the full-response pins recorded when the original curated snapshot was created. Matching CommunityDragon 16.19 character roots are retained for all champions under `sources/characters/`. Each excerpt records its URL, full-response SHA-256 and root path. `manifest.json` hashes every retained excerpt and the normalized catalog.

`catalog.jdn` is data-only Janet notation, parsed without executing downloaded text. Base health, AD, defenses, health regeneration, movement speed, attack-speed base/ratio/growth and crit multiplier come from game character records. Resource fields come from Data Dragon. Missing character fields use explicitly recorded Data Dragon fallbacks; there is no implicit claim of correct special champion behavior. Generic attacks assume a 2.5 attack-speed cap, 30% windup and zero projectile travel. Kits, passives, attack conversions and transformations require separate adapters.

Item stats come from named structured fields and strictly matched `<stats>` lines. Percent stats use fractions. Flat HP regeneration is converted from per-second source values to the core's per-five-second unit. Tooltip text outside the stat block never becomes an unconditional damage or penetration formula. Unknown fields and stat lines remain listed as limitations. Full descriptions, cost, tags, icon identity, source availability and champion restrictions are retained. Conditional, on-hit, active and stacking effects are not inferred from descriptions.

`web/catalog.janet` overlays existing curated values for the fourteen items and two champion records, including Deathcap's multiplier, Infinity Edge's crit multiplier and Annie's learned-R penetration. This preserves existing calculations while keeping the catalog status unvalidated. The original curated snapshot, optimizer pool and stat-observation fixtures remain independent.

The frontend is an inventory sandbox: six slots and total cost, without a budget limit. All entries can be inspected and selected. Source restrictions and known curated duplicate/group conflicts appear as notes; this does not certify an inventory as legal. In-game observations validate only their explicitly recorded champion, level, items, ranks and excluded fields.

Run `python3 scripts/import_catalog.py --check` to verify hashes and reproduce normalization entirely offline. Run the importer without `--check` to fetch missing pinned sources and generate the catalog. Changes to normalized data require deliberate review and never create in-game evidence.

`art-manifest.json` pins 1,043 champion/item PNGs by SHA-256. `scripts/fetch_web_assets.py` verifies cached images or downloads them from the matching Riot patch. The browser receives only local assets. `--record-catalog-hashes` is an explicit maintainer operation to create new artwork pins, not part of normal setup.

# Reproducible scenarios and calibration

Use a combat preset, configure both participants and their strategies, then choose a trial count and seed. Optimization evaluates this fixed scenario; it does not search the opponent or player decisions. Scores display their comparison order. Burst uses the configured window; sustained damage divides modeled damage by that window. Duel prioritizes win/kill probability and successful kill times. Survival prioritizes survival and health. Utility compares effective control, healing and absorption in order. Objective scoring uses objective kills, kill times and damage. Each chart has its own units and scale.

The shop search uses fetched map, champion, group and availability restrictions. Locks preserve owned items; other items can be replaced. In next-purchase mode the budget means gold available now, and each owned recipe component is credited once. Next-purchase mode keeps rune/summoner/skill choices fixed. The bundled excerpt searches only curated purchase rules; refresh the patch for complete sources. Full-shop and optional loadout searches report best found. Rune choices cover primary/secondary effects; stat shards and exceptional leveling require further handlers and remain outside these estimates.

Save locally stores up to fifty named scenarios in the current browser (2 MB allowance). Export JSON creates a versioned document; import accepts at most 64 KB. Share links embed the same document, with a 16 KB URL allowance. Links carry game settings, not server-side saved records. Keep exact data snapshots cached for offline reproduction. Imports require their exact snapshot; an absent revision is an error, never a substitution. A different combat model displays a warning and recomputes against the retained data; use the original RPM to reproduce that older model.

The source evidence view displays exact provider versions, source URLs and hashes, snapshot identity and parser/model identities. Source availability, implemented effects and in-game measurements remain separate. The five retained Annie captures check their original stat conditions; they do not verify every combat handler.

## Packaged command line

The RPM includes these JSON commands; no separate interpreter is needed:

```sh
powerspike --simulate scenario.json --data-dir /var/lib/powerspike
powerspike --optimize search.json --data-dir /var/lib/powerspike
powerspike --calibrate measurement.json --data-dir /var/lib/powerspike
```

A search document has format `powerspike-optimization`, version `1`, a `scenario-document` containing an exported scenario, and `constraints` using the UI's field names (for example `searchbudget`, `searchslots`, `searchseconds`, `searchpreset`, `searchpool`, `searchexclude` and `lockslot1`). Item lists accept names or IDs. Output is JSON from the shared Janet engine. Existing development CLI entry points remain compatible.

## Calibration by mechanic family

Copy `observations/templates/calibration.json`, attach an exported scenario under `scenario-document`, and collect a measurement under exactly those fight conditions. Record the game version, source and capture time, measured metric/value, tolerance and required effect source. Set `reviewed` only after checking loadouts, buffs, target stats, timing and exclusions. Do not infer an absent measurement as zero or tune expected values to match the implementation.

Families are `isolated-damage`, `mitigation`, `timing`, `on-hit`, `healing-shields`, `control`, `objectives` and `combinations`. Use isolated damage first, then mitigation and timing; apply the same procedure to shared triggers, protection/control and objective restrictions before testing combinations. A missing observation is `unmeasured`. A missing required effect/metric is `unresolved`. Reviewed numerical comparisons are `consistent` or `mismatch`, and retain source/model identity and unsupported-effect notes. These statuses validate only the recorded conditions.

The five existing Annie stat captures remain unchanged and are still checked by the core regression suite. No additional in-game measurements have been invented during implementation.

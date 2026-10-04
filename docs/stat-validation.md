# Collecting and comparing game stats

The model and comparison logic are Janet. Two Python 3 standard-library helpers handle HTTPS/JSON collection and retained-source verification. No Python package installation is needed.

This workflow compares a controlled stat snapshot. It does not measure damage, attack timing or a complete duel. Five measured Annie captures agree: ten baseline stats, eleven with Cloak, and twelve in each Void Staff capture. The level-6 pair also checks level growth and learned-R penetration; see [validation results](validation-results.md).

## Check rules before measuring

```sh
make verify-sources
make test
```

The source check verifies retained hashes, follows Annie's current champion spell references, and compares normalized champion/item/spell/shard values with independently extracted facts. It also checks the limited item-tooltip fields used by this curated pool. It does not establish server timing, proc semantics, attack-speed caps or every build restriction. `make test` requires Python 3 in addition to the existing build tools. Use `PYTHON=/path/to/python` and `JANET=/path/to/janet` to select existing runtimes.

## Capture a controlled game snapshot

Start a Summoner's Rift Practice Tool session using **Annie or Garen**, with only items supported by the snapshot. Stay alive and still, allow temporary buffs to expire, and avoid combat during capture. Begin with no items, then individual supported items. Capture separate levels and, for Annie, R unlearned and learned.

For the first baseline, use Annie at level 1 with no purchased items and leave skill points unspent. Keep your existing rune page; the capture records it for review. Walk from the fountain into your own jungle, stop away from camps and minions, and confirm the Homeguard movement bonus has disappeared. Waiting in the fountain does not remove it: [Riot's 26.1 Homeguard rules](https://www.leagueoflegends.com/en-us/news/game-updates/patch-26-1-notes/) remove the buff on entering the jungle, reaching its endpoint or entering combat. Do not attack or cast during this capture. No target dummy is needed for stat collection.

Check the actual installed game patch first. Enter its corresponding static build as `--patch` and record the displayed client version as `--client-build`. The API sample does not supply an authoritative game build; these fields are **operator declarations**. A different patch can be archived, but comparison with our 16.19.1 model will reject it until matching data is added.

The versions reported for this session are **Game Version 26.19** and **League Client Version 16.19.823.0722**. Use our matching Data Dragon snapshot `16.19.1` for `--patch` and preserve the full League Client Version in `--client-build`. The client version is a separate identifier; it is not the Data Dragon version or a verified game-server build.

Run the collector **on the Windows host running League**. In a terminal opened in the project folder:

```sh
py scripts/capture_live_stats.py --patch 16.19.1 --client-build "16.19.823.0722" --insecure-localhost --output observations/local/annie-01
```

Replace the version arguments with the versions actually installed and use a new output directory for each capture. If your launcher is `python` or `python3`, use it instead of `py`.

The collector uses Riot's [documented local endpoint](https://developer.riotgames.com/docs/lol#live-client-data-api). `--insecure-localhost` accepts the game's self-signed certificate for this fixed loopback request. Alternatively supply Riot's certificate using `--ca-file PATH`. The tool does not follow redirects or use an HTTP proxy.

The folder contains:

- `raw.json`: original response bytes, including the loadout and rune information.
- `observation.jdn`: normalized measurements, raw-response hash, timestamp, request duration and editable context notes.

Existing capture folders are never overwritten. `observations/local/` is ignored by version control. The collector records only one response per invocation and does not send game inputs.

If connecting from WSL fails, run collection from Windows; WSL loopback may not reach the Windows game service. The Janet comparison can run in WSL afterwards using the shared workspace. If Windows also cannot connect, check that an actual game is running, rather than only the launcher.

## Verify ambiguous API units

Initial capture deliberately leaves crit and percentage penetration unmapped. Other measured fields still work. Inspect the raw values under controlled conditions and identify their units before supplying a mapping. Check zero and nonzero values; use no penetration and a known source of penetration to distinguish the penetrated fraction from the fraction of resistance remaining. Do not infer the unit from a single zero.

A unit file is a JSON object using the exact API field names. Allowed values:

| Field | Allowed units |
| --- | --- |
| `critChance` | `fraction`, `percent` |
| `critDamage` | `multiplier`, `percent` |
| `armorPenetrationPercent` | `fraction`, `percent`, `remaining-fraction` |
| `magicPenetrationPercent` | `fraction`, `percent`, `remaining-fraction` |

Include only fields whose interpretation you checked. Pass the file with `--units PATH` when capturing or importing. Our measured mappings are `critDamage: percent` (200 means a 2.0 multiplier), `critChance: fraction` (the Cloak gives approximately 0.15), and `magicPenetrationPercent: remaining-fraction` (Void Staff's 40% penetration gives approximately 0.60). Armor percentage penetration remains unresolved until a nonzero-source test. The collector rejects unknown unit choices and impossible converted fractions. It does not convert the older `cooldownReduction` field into haste implicitly. Missing `abilityHaste` produces a missing measurement.

You can import an existing response with the same arguments and `--input PATH_TO_JSON`. The output identifies it as an imported response, rather than a newly collected game snapshot. `:collection-started-at` then records import time, not the original measurement time. Synthetic responses used in tests remain synthetic evidence.

## Review context and compare

Preserve the original `observation.jdn`; put context review in a separate copy such as `reviewed.jdn`. Keep measured numbers unchanged. Review `:rune-ids`, `:shard-ids` and the full rune information in `raw.json`. The comparison applies supported static shards 5005, 5010 and 5011 from matching source data; other shard IDs are rejected until modeled:

- Set `:buffs []` only after checking that no temporary effects affect the captured stats.
- Set `:role-quest-state "inactive"` only when no quest bonus affects the measurement.
- Put stats affected by unsupported rune/shard or other effects in `:excluded-stats`, for example `[:ad :ap]`. Explain the exclusion in `:notes`. Do not compensate by adding a fitted offset to measured numbers.
- Set `:context-reviewed true` after accounting for the captured conditions. With active buffs or quest effects, take another clean snapshot or leave the context unreviewed.

With the locally built interpreter, run from the project folder:

```sh
build/janet scripts/compare_stats.janet observations/local/annie-01/observation.jdn
```

The comparison checks patch, champion, mode, skill ranks and supported items/shards. On map 11 it accepts `CLASSIC` and the live API's `PRACTICETOOL` label. Only the separate trinket slot is omitted from stat evaluation, and its IDs remain recorded. Unsupported inventory items and shards are rejected instead of silently ignored.

Each stat receives `match`, `mismatch`, `missing` or `excluded`, with its expected and measured values. The aggregate result is:

| Result | Meaning |
| --- | --- |
| `needs-context` | Numbers may match, but conditions have not been reviewed. |
| `mismatch` | Reviewed context, with a difference outside the declared tolerance. |
| `incomplete` | Required measurements are missing, or no stats were checked. |
| `consistent` | Reviewed context and agreement for the checked stats only. |

Tolerance is `absolute + relative * abs(expected)`. Defaults allow small rounding differences; they are provisional and explicit in the record. Change them only with a measurement-based reason recorded in the notes. Unmapped percentage fields are listed separately, not treated as zero or as checked coverage. Exit code is zero only for `consistent`.

A consistent snapshot does not establish correctness for other levels, builds, timing or damage. Retain useful disagreements and identify whether they come from source interpretation, missing mechanics, game context or an implementation error before changing the model.

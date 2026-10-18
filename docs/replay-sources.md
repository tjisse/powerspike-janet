# Replay sources

Checked 2026-10-17. This is a source audit, separate from model verification.
The [machine-readable audit](../observations/replays/source-audit-2026-10-17.json)
records exact revisions, download checks and limits. Raw research downloads stay
under the ignored `observations/local/source-research/` directory.

## Strongest options

| Source | What we can obtain | Availability checked | Main limitation |
| --- | --- | --- | --- |
| [Riot Match-v5 replay endpoint](https://developer.riotgames.com/apis#match-v5/GET_getReplay) | Official discovery of replay file URLs by player PUUID | Two current-build games decoded; all 100 final damage checks agree within one point | Exact pre-hit conditions remain incomplete; future access rules and production quotas untested |
| [maknee's organized decoded corpus](https://huggingface.co/datasets/maknee/league-of-legends-decoded-replay-packets) | Already-decoded damage, casts, basic attacks, purchases and state updates | Public file listing, schema, ranged download and one full checksum-verified batch | Historical patches; decoder fidelity and state completeness need review |
| [RoflLens v0.1.0](https://github.com/ss26367098/rofllens/releases/tag/v0.1.0) | Five raw `.rofl` files, exact build 16.14.794.5912 | One fully downloaded, checksum verified and decoded in our existing pilot | Small fixed corpus |
| [League Replay Analyzer fixture](https://github.com/Danmoreng/league-replay-analyzer/tree/main/replays) | One publicly tracked raw `.rofl`, 15,013,275 bytes | A capped byte-range request returned a real ROFL header, build 16.5.752.7101 | Older patch; only one file is public in the checked Git tree |

## Fresh games: Riot's own API

Correction to the initial research: an official replay-download discovery API
**does exist**. Riot [announced direct API replay access in patch 25.23](https://www.leagueoflegends.com/en-au/news/game-updates/patch-25-23-notes/).
Reading the API section loaded by the Developer Portal confirms:

```text
GET /lol/match/v5/matches/by-puuid/{puuid}/replays
ReplayDTO: total (int), matchFileURLs (List[string], replay URLs in .rofl format)
```

This is a player-based endpoint, not proof of an arbitrary match-ID download
API. Regions in the documentation are AMERICAS, ASIA, EUROPE and SEA.

An authenticated EUW check on 2026-10-17 succeeded. Riot returned five replay
URLs for the requested player. A recorded random selection downloaded a complete
ROFL2 file for build **16.20.824.8524**, matching the latest Data Dragon patch
16.20.1. The requested player was present as Sion in a 940.808-second game.
The [sanitized access report](../observations/replays/riot-access-2026-10-17.json)
records hashes, selection, parser checks and costs. Keys, account identifiers,
signed URLs and raw files remain under ignored `observations/local/` paths.

The signed download was gzip-encoded: 7,297,451 bytes transferred and 7,419,485
bytes after decompression. The signed URL request did not include the Riot API
token. RoflLens 0.1.0 read the container and all **779,977 packet records** in
about 1.6 seconds for the framing scan. That initial check established acquisition and framing,
with **zero verified damage events or model comparisons**.

At that point the checked tools had no matching 16.20 semantic profile: RoflLens bundles
16.14, rofl-parser bundles 16.15/16.16, and the inspected League Replay Analyzer
registry ends at 16.14. The advertised rofl-parser remote registry indexes
returned 404. These are bounded checks, not proof that a decoder exists nowhere.
Older packet IDs and layouts must not be assumed compatible.

We also tested the rofl-parser artifact builder at commit
`73530424162672aa7daafe233f647cc655607880` with the exact executable obtained
from Riot's CDN. Its file-version resource matches **16.20.824.8524**; SHA-256
is recorded in the [decoder investigation](../observations/replays/decoder-investigation-2026-10-17.json).
The Node/Python/Unicorn preflight passed, but generation failed at static packet
registration discovery, before any decoder calls or artifact generation.

Unlike the available 16.14 executable, this download has no `PKT_` or MSVC RTTI
name markers. Its ordinary code/data sections have entropy near 8 bits per byte
and it contains additional `.riot0`/`.riot1` sections. These observations suggest
a packed/encrypted image; they establish that the inspected scanner cannot use
this input, without proving that all builds or approaches are unsupported.

[ROFL-X's replay-only research](https://github.com/Toastaspiring/ROFL-X/blob/88954be66da506f188fbd134944fdfd8334ad846/docs/EXPLORE.md)
offers another approach: recover selected fields from replay constraints rather
than executable-derived layouts. Its published 16.19 results include some
visibility and killer fields, but explicitly exclude damage numbers, item IDs
and spell casts. We inspected its source and documentation; its methods have
not been run directly on our 16.20 replay. Behavioural matches are research
candidates, not a substitute for verified combat semantics.

Follow-up on 2026-10-18: our replay-only adapter now checks death timing/victims
and a partial skill-upgrade payload codebook against independent Riot timelines.
The frozen rules matched all 78 deaths and 126 of 171 skill upgrades in a
separate Summoner's Rift replay; 45 upgrades remain uncovered. A signed relative
entity-ID bug in RoflLens was corrected in our framing adapter, with regression
tests. The [study and coverage report](../observations/replays/recovery-study-2026-10-18.json)
records costs, explicit Arena rejection and unresolved fields. Damage and
combat-model verification were zero at that stage.

A subsequent [damage/state study](../observations/replays/damage-state-study-2026-10-18.json)
found readable native code in Riot's exact matching macOS Intel client. The
[official manifest](https://lol.secure.dyn.riotcdn.net/channels/public/releases/66B91DB25E5AD56E.manifest)
was identified through the pinned-build
[manifest catalog](https://github.com/Morilli/riot-manifests/blob/master/LoL/EUW1/macos/lol-game-client/16.20.8248524.txt).
Only the Intel slice was retained, with a fixed SHA-256. Bounded offline calls
now decode all 90,230 damage packets and 27,511 state buffers in the two games.
All 100 aggregate damage checks agree with Riot within one point; partial state
observations retain timestamps, wire order, raw bytes and discrepancies. This
supersedes the damage-decoding blocker, while exact pre-hit state and model
comparisons remain incomplete. No native game process was launched.

Riot's [official replay announcement](https://x.com/LeagueOfLegends/status/2107875798825021469)
says the announced replay changes were delayed to patch 26.21 while a solution
for creators and coaches is developed. The post's text was retrieved from its
public page metadata. Do not assume that other-player access will remain
unchanged or that an older support FAQ describes the upcoming rules.

Riot is now the primary acquisition route for current-patch evidence.
Participant-contributed files remain an approved complementary source. The next
engineering step is offensive-stat, inventory/buff and attribution recovery,
followed by independent review of a simple hit on matching patch data.
Automatic generation from the Windows image remains blocked; the guarded
macOS adapter provides damage and partial champion-state decoding instead.
Production quotas and sustained supply were not tested.

## Historical events: the organized Hugging Face corpus

The publisher advertises 700k+ replays. We have not independently counted games.
At pinned revision `04f9c7350e9ffcc689b731875ad9baf3ff6eaa6d`, the actual file
listing contains **1,348 compressed batches**, distributed as:

| Directory | Batches |
| --- | ---: |
| `12_22` | 191 |
| `12_23` | 768 |
| `13_1` | 258 |
| `13_2` | 131 |

The dataset card also mentions `13_03`; no batch files in that directory were
present in the checked revision. Use file listings, not just the card, to select
patches. The published license is Apache 2.0. No login was needed for the checks.

We fully downloaded `13_2/batch_106.jsonl.gz` as a small availability check:

- 3,888,336 compressed bytes; SHA-256 matched the Hugging Face LFS metadata.
- 87,379,789 expanded bytes, parsed as a stream without storing expanded JSON.
- 454,447 event objects, including 24,142 `UnitApplyDamage` objects, 2,800 casts,
  2,523 basic-attack objects and 76,068 replication objects.
- Observed state field names include health, shields, bonus armor, physical and
  magic damage modifiers, spell resistance, haste, crit and level/experience.

These are event-object counts, not independent hits, unique fights or verified
model cases. The source's handling of state restoration, repeated events and
game boundaries has not been audited. The damage schema gives amount, source,
target and time, but lacks a damage-type field. State coverage and exact build
provenance are not yet sufficient to claim full combat reconstruction.

The user prioritizes decoding new replays ourselves. Defer this historical
corpus unless its schemas or decoding research help that work. Matching
historical rules still matter; observations from 12.x/13.x cannot be used to
verify current champion numbers automatically.

Compressed size understates processing cost: the first JSON line in the test
batch exceeded 64 MiB. Read event objects incrementally rather than loading an
entire match line. The availability test was deliberately small; we did not
download the approximately 108 GB collection shown by Hugging Face.

The same publisher's [unorganized archive](https://huggingface.co/datasets/maknee/leaague-of-legends-decoded-replay-packets-s12-unorganized)
is a secondary lead. Its public card lists 356 GB, and a partial directory listing
shows older 12.x patches. No data file was downloaded. Treat it as a backup from
the same source, not independent corroboration of the organized corpus.

## Discovery and visual services

[League of Graphs](https://www.leagueofgraphs.com/replays/all/) has a current
replay listing with champion, matchup, region and rank filters. That establishes
match discovery, not accessible bulk replay bytes. Our direct HTTP request
returned 403, and no raw file transfer was verified. Its site-wide recent-match
count must not be reported as a downloadable replay corpus size.

[Replayit](https://www.replayit.gg/developers) documents token-based recordings,
video downloads, streams and local-client launcher files. It could help obtain
visual checks without occupying our game machine. We did not find a documented
bulk raw-ROFL endpoint in the inspected page or test authenticated access.

ReplayBook and ROFL-X are useful software projects, but no public raw replay
files were found in their current Git trees. A Hugging Face dataset named
`Qacen/rofls` contained notebooks, not replay files. An academic minimap dataset
returned 401 for metadata; its availability and raw-file content remain unknown.

## Selection

Prioritize **Riot's API for fresh files** and **participant contributions for
continuity**. Authenticated acquisition is verified for one requested player;
current-build combat decoding is the next blocker. Keep small public ROFL
fixtures for parser regressions, and defer historical corpus expansion unless
it helps current decoding or resolves a specific current discrepancy.

# Replay damage-total discrepancy: resolved

The reported Ornn incoming-damage discrepancy came from the aggregate checker.
It added decoded binary32 amounts using Python's binary64 arithmetic. The exact
client's numeric-stat implementation stores a binary32 value, rounds each
addition to binary32, and truncates the result for integer output.

For the same 1,012 packets in their original wire order:

| Calculation | Total | Integer output |
| --- | ---: | ---: |
| Original Python binary64 sum | 27667.00943517685 | 27667 |
| Guarded native binary32 accumulation | 27666.984375 | 27666 |
| Corrected Python binary32 accumulation | 27666.984375 | 27666 |
| Riot final match statistic | — | 27666 |

The strict comparison remains `abs(decoded - API) < 1`. The corrected error is
0.984375, and the native integer output equals Riot's statistic exactly. No
packet amount or simulator formula was adjusted.

## Evidence for the cause

The [native proof](../observations/replays/damage-accumulation-native-proof-2026-10-19.json)
uses only the already hash-guarded official Intel image for build
`16.20.824.8524`. It binds `TOTAL_DAMAGE_TAKEN` in the constructor to a numeric
stat object in sum mode. Its vtable method at `0x100143fb0` executes `ADDSS`
and stores the result with `MOVSS`; the formatter at `0x100143f97` executes
`CVTTSS2SI`. These instructions establish the representation independently of
the desired API total.

Bounded Unicorn calls reproduced the native addition for control vectors and
all 1,012 Ornn additions. Every Python result matches the native float bits.
The proof receives neither the API integer nor an expected answer. The
retained regression includes the ordered, unmodified amounts, their source
archive fingerprint and the independently recorded native total.

`scripts/replay_combat.py` now rounds after each addition, independently for
incoming total, each damage type and outgoing damage to champions. Its reports
record `ordered-binary32-v1`. Rounding only the final sum or summing type totals
would implement different operations.

## Independent check

The [audit plan](../observations/replays/damage-accumulation-audit-plan-2026-10-19.json)
froze the candidate arithmetic, unchanged tolerance and unused replay selection
before that replay's bytes or damage values were inspected. Clean extraction
from both raw replays passed **100 of 100 aggregate damage checks**, with no
packet decode failures. The original replay's decompressed damage and state
archives are byte-identical before and after the fix.

The [resolution report](../observations/replays/damage-accumulation-resolution-2026-10-19.json)
retains before/after errors, source and adapter identities, independent checks
and the original discrepancy. Earlier records are historical evidence, rather
than rewritten passing results.

## Reproduction

The optional dependencies are pinned in `scripts/replay-requirements.txt`.
With the previously acquired image and a fresh output path:

```sh
python3 scripts/replay_accumulation.py \
  --image observations/local/lich-bane-current/LeagueofLegends-16.20-x64.macho \
  --inputs observations/replays/16.20.824.8524-damage-accumulation-case.json \
  --output observations/local/lich-bane-current/native-proof-new.json
```

This uses offline emulation, without a game process, network or API key.
`test/test_replay_combat.py` covers per-add rounding, ties to even, invalid
operands, overflow, the original Ornn failure, the fixed tolerance boundary and
an optional native control-vector check. The full extraction still uses
`scripts/replay_combat.py`; choose new output directories when rerunning it.

This fixes aggregate representation. Exact attack timing, per-hit simulation
agreement, complete buff state and periodic API/replay sampling differences
remain separate review work. No new simulation cases are admitted by this fix.

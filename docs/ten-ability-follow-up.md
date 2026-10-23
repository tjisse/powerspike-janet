# Ten ability-slot follow-up — 23 October 2026

This batch covers **16.21.1 only**. It adds applied combat effects to ten
previously non-executing Q/W/E/R entries. These are partial champion kits;
an executing slot is not proof of a complete kit or measured game timing.

The complete matching character/description responses are retained in
`data/ability-fixtures/16.21.1/completeness/`, with a localized string excerpt.
The manifest records original public provider URLs, response hashes, the full
string table hash and each retained fixture hash. All twenty character and
description hashes match the preceding all-champion audit receipts.

## Implemented effects

| Slot | Behavior | Independent example at rank 1 |
| --- | --- | --- |
| Vi W | Third distinct attack or modeled Q/E hit; refreshed four-second marks, physical maximum-health damage, armor reduction, temporary bonus attack speed | With 50 bonus AD into 2,000 max HP: `(.04 + .00035 * 50) * 2000 = 115` raw damage, 20% armor reduction and 30% bonus AS for four seconds |
| Twisted Fate E | Learned-rank permanent bonus attack speed and every-fourth-attack magic damage, with no active cast | 15% bonus AS; with 50 bonus AD and 100 AP: `65 + .2 * 50 + .4 * 100 = 115` damage |
| Tristana Q | Immediate temporary bonus attack speed; independent of opponent range and hit chance | 40% bonus AS for seven seconds; rank 5 gives 120% |
| Singed R | Temporary AP, armor, MR, movement speed, health regeneration and mana regeneration | +25 to all six source stats for 25 seconds; rank 3 gives +85 |
| Gangplank W | Cleanse supported controls while disabled, then heal base/AP plus current missing health | At 100 AP and 500 missing HP: `45 + .9 * 100 + .13 * 500 = 200` healing |
| Veigar R | Impact-time missing-health amplification and source-defined accelerating travel | At 100 AP: minimum `175 + .65 * 100 = 240`; half missing HP gives 420; capped damage is 480 |
| Zac W | Base plus target maximum-health magic damage, retaining its current-health cost | At 100 AP into 2,000 max HP: `40 + (.04 + .0003 * 100) * 2000 = 180`; 500 current HP pays 20 HP |
| Zilean E | Offensive enemy slow, with the selected source duration | 40% slow for 2.5 seconds; rank 5 gives 99% |
| Malzahar E | Replaceable periodic magic damage and a visible duration band | At 100 AP: `80 + .8 * 100 = 160`, divided into sixteen quarter-second pulses over four seconds |
| Cassiopeia Q | Replaceable poison damage and a visible duration band | At 100 AP: `65 + .75 * 100 = 140`, divided into seven pulses across three seconds |

Bonus attack speed uses the champion's attack-speed ratio and existing cap,
rather than multiplying total attack speed. Twisted Fate's permanent bonus is
included before combat, tooltips and optimizer evaluation. Rank zero gives no
bonus or proc. Passive activation fields remain disabled while rank selection
remains available. Counters begin with no pre-fight stacks. Distinct actions at
one timestamp can count, while duplicate components of one origin count once.
Stacked Deck's counter belongs to its caster; Vi's mark belongs to the opponent.

The probe now supplies the ratio/cap required to apply temporary bonus AS and
installs reviewed permanent bonuses. These are synthetic probe inputs, not a
replacement for the selected champion's actual stats in ordinary scenarios.
The updated inventory records 477 executing entries, 172 with no executable
effect, 19 not casting and 24 casting without an applied effect. Exactly the
ten slots above change rows; the audit snapshot remains unchanged.

## Bounded semantics and remaining gaps

Vi's proc damage currently precedes its new armor reduction. Subsequent hits
use reduced armor. This follows the model's explicit initiating-hit/proc order;
it is not independently captured game ordering. Blast Shield cooldown
reduction, pre-fight marks, monster variants and the remaining Vi kit are
excluded. Ordinary parried hits cannot build the counter.

Gangplank's selected record explicitly sets `canCastWhileDisabled` and
`cannotBeSuppressed`. Only that reviewed ability bypasses its listed control
gates. The model cleanses stun, charm, fear, suppression, silence, root, slow
and grounding. It does not remove unrelated damage/healing debuffs. Airborne
displacement and stasis remain excluded. Generic abilities retain their
control gates and positive-cooldown requirement.

Veigar's source gives initial speed 500, acceleration 4,000 and maximum speed
4,000. Travel integrates acceleration until the speed cap, then uses constant
speed. At distance 300, travel is `(sqrt(500^2 + 2*4000*300) - 500) / 4000`.
The distance is sampled at cast release, consistent with the existing frozen
projectile-distance model; following a moving target remains excluded.
Missing-health interpolation uses `1 + min(1, 1.5 * missing-health fraction)`,
with the selected tooltip's doubled maximum below approximately 33% health.
The exact interpolation and flight behavior still need a matching game capture.
Missing/invalid accelerating-movement source disables the reviewed effect;
it cannot silently become an instant hit.

Malzahar's first pulse is one source interval after modeled application.
Cassiopeia's seven pulses start at modeled cast completion, then occur every
half second through the three-second duration. The retained sources establish
the totals, duration and pulse counts. They do not establish Cassiopeia's
ground detonation delay or newly measured game application/tick timestamps.
Those timing assumptions stay explicit. Q's decaying movement speed and Twin
Fang synergy remain excluded. Malzahar Q/R refresh, spreading, death mana
restoration and minion rules remain excluded.

Reapplication replaces pending poison pulses from that caster/ability; it does
not stack another complete damage sequence. Parried applications schedule no
pulses. Applied periodic damage can continue after the caster dies. Vi's mark
expiry, temporary stat expiry and poison status bands use actual engine state.
Movement and other shared engine assumptions remain; these handlers do not
establish complete live-game movement behavior.

Singed's Poison Trail Grievous Wounds and Zac's blob pickup healing/refunds
remain excluded. Zilean E selects the offensive target; self/ally haste is not
an available mode yet. No other champions, later patches, P passives or form
transitions are implicitly enabled by these handlers.

## Verification

`test/completeness-abilities.janet` checks independent arithmetic, rank
boundaries, passive rank-zero behavior, duplicate/simultaneous hit origins,
refresh/expiry, armor and AS restoration, control gates, impact-time health
changes, acceleration before/after its cap, health cost, periodic replacement,
parry, missing-source guards, future-patch exclusion and unchanged saved bytes.

Twenty retained scenarios cover each slot in both matchup positions, with
optimizer/trace-free equality and exact event counts. They run through the
relocated standalone executable and the shared desktop/mobile browser check,
including passive tooltips, disabled active conditions, saved ranks, timeline
event representation and 320 px layout.

Parser version remains **7**. Current semantic compilation uses retained raw
records; existing snapshot bytes and current pointers are unchanged. No
automatic refresh, migration, repair or reparse is introduced. No new game
capture or release is claimed by this batch.

# Sustain and charge ability follow-up — 23 October 2026

This batch adds 25 bounded ability slots across 20 champions on **16.21.1**.
It covers healing channels, continuous costs, damage stores, charged releases,
shared protection and temporary movement. A working slot does not imply a
complete champion kit. These are source-based simulation checks, not newly
observed game outcomes.

Original character and description responses, selected strings, source receipts
and supplementary mechanical references are retained under
`data/ability-fixtures/16.21.1/sustain-charge/`. Numerical formulas use those
matching records. Handlers do not extend to an unreviewed future patch.
The parser remains version 7; this batch does not refresh or migrate snapshots.

## Independent examples

Unless stated otherwise: rank 1, level 18, 100 AP, 150 total/100 base AD,
1,000 maximum/500 current health, base armor/MR 50/25, final armor/MR 100/50,
attack speed and ratio 1, movement 100 and 500 resource out of 1,000 maximum.
The opponent has 2,000 maximum health and zero resistances. Saved scenarios
separately use actual champion stats, ranks, regeneration and strategies.

| Slot | Included behavior and numerical check |
| --- | --- |
| Braum W | Self-cast resistance stance adds 38 armor and 29 MR for three seconds. Ally dash/sharing is excluded. |
| Briar Q | Pays 25 current health, lands on the sole opponent, deals `60 + .6*100 + .8*50 = 160` physical, stuns for .85 seconds and reduces armor/MR by 10% for five seconds. |
| Briar E | Pays 25 health, heals 100 during a one-second uninterruptible charge, applies source damage reduction, then deals `80 + 50 + 100 = 230` magic, slows and pushes 575 units. Range is checked at release. |
| Briar R | Pays 25 health, deals `150 + 1.3*100 = 280` magic and grants 30 armor/MR, 10% attack vamp and conditional chase movement against the prey. The sole prey is not feared. |
| Karthus E | Quarter-second radius checks total `30 + .2*100 = 50` magic per second and cost 30 mana per second. A kill restores 10 mana. |
| Singed Q | Fixed clouds persist 3.25 seconds and refresh two-second poison at quarter-second intervals. DPS is `20 + .425*100 = 62.5`; continuous cost is 13 mana per second. |
| Dr. Mundo R | Adds `.15*500 = 75` temporary base/current/max health; 20 half-second pulses heal 20% of the resulting dynamic maximum over ten seconds. At 10.01 seconds, current health is 790 and maximum/base health return to 1,000. Rank-three nearby-enemy bonuses add percentage points to both ratios. |
| Nasus R | Adds 300 current/max health, 40 armor/MR and 50 range for 15 seconds. Half-second aura pulses deal 40 magic here. Subsequent Q cooldowns are halved; existing timers stay intact. |
| Master Yi W | Four-second channel, eight live missing-health-scaled healing pulses; the first heals 41.25. Initial/ongoing damage reductions are 70%/45%, with a half-second linger. Upfront 40 mana plus 6% maximum mana per second leaves 220 resource after four seconds. |
| Nunu R | Full three-second channel deals `750 + 3*100 = 1050` magic and grants 215 shield. Interruption at 1.5 seconds releases 525 damage. Source slow endpoints are 50% and 95%; surviving shield decays for three seconds after channel end. |
| Ornn W | Five pulses over .75 seconds each deal `max(16, .024*2000) = 48` magic. Final hit marks Brittle; a later attack/immobilization consumes it for 340 magic at level 18 and amplifies that control by 30%. Direct displacement is blocked during the breath; a final spell shield prevents Brittle. |
| Pantheon E | Six quarter-second pulses total 150 physical, followed by a 130 physical shield slam. Front-facing non-turret damage immunity lasts 1.5 seconds; movement remains possible. |
| Sett W | 200 unshielded post-mitigation damage stores 200 Grit, becomes 200 shield at cast start and produces `80 + .375*200 = 155` center-line true damage at release. Each stored hit decays separately after four seconds; shield decay starts after .75 seconds. |
| Sett R | Suppresses/carries the target for 1.5 seconds, then deals base/bonus-AD damage plus 40% target bonus health. Against 500 bonus health the example deals 460 physical, followed by a 99% slow. |
| Kai'Sa E | Charge scales from 1.2 to .6 seconds at 0–100% bonus AS, with scaled movement, followed by 40% AS for four seconds. Ordinary hits refund .5 seconds of cooldown. The temporary ordinary attack profile uses 6.44% windup and missile speed 2,500. |
| Lee Sin W | Initial self-cast grants `60 + .8*100 = 140` shield, costs 50 energy and halves its source eight-second cooldown. Automatic recast after .5 seconds costs 25 energy and grants 10% vamp for four seconds. |
| Kindred E | Three landed ordinary attacks refresh the four-second mark window and detonate it. Three 150-damage attacks yield `130 + .05*450 = 152.5` physical bite damage. Selected critical-stat scaling is applied directly; no obsolete health-threshold critical roll is invented. |
| Kindred R | Fixed radius-530 zone protects both occupants at 10% maximum health for four seconds, blocks healing/regen at the floor, and heals each remaining occupant for 225 at expiry. Exiting removes protection. Heal metrics and trace lanes belong to the recipient. |
| Mordekaiser W | Stores 45% outgoing post-mitigation and 7.5% incoming pre-mitigation champion damage, with 5% minimum when ready and 30% maximum health cap. Starting 50 plus 100 outgoing and 100 incoming yields 102.5 shield. Recast heals from remaining shield; storage has source delayed decay. |
| Viego R | Base form deals `1.2*150 = 180` plus 14.5% live missing health, with source critical-stat scaling and supported on-hits. A target missing 1,000 health takes 325 physical. |
| Vi Q | Full 1.25-second charge deals `(40 + .6*50)*2.5 = 175` physical, applies knockback and Denting Blows. Cancellation refunds 25 of 50 mana and uses the source three-second cancellation cooldown. Item on-hits are not added. |
| Vladimir W | Pays 75 current health, becomes untargetable for two seconds and moves with decaying speed. Four half-second pulses total 80 pre-mitigation magic and heal 24, leaving 449 health without other effects. Existing tagged poison continues; new hostile hits/controls fail. |
| Vladimir E | Four quarter-second health payments total 8% maximum health. Full release deals `60 + .06*1000 + .8*100 = 200` magic and a 40% slow. Interruption at .5 seconds releases 140 without the full-charge slow; insufficient health releases only paid charge without lethal payment. |
| Jinx R | Retained initial missile speed 1,700; direct damage ramps from 26 to 260 over one modeled second of flight. Missing-health damage is independent of that ramp: at full flight and 1,000 missing health, damage is 510 physical. |
| Zoe R | Advances toward the opponent up to 575 units after casting, resets the attack timer, allows attacks/casts during a one-second movement-locked visit, then returns to the starting position. |

## State and remaining boundaries

Charges retain their start, duration, paid costs and cancellation rules.
Uninterruptible charging is explicitly scoped to Briar E and Kai'Sa E;
existing channels, including Fiddlesticks' polymorph interruption, retain their
behavior. Channel-bound protections, shields and movement clear or linger as
declared. Continuous-cost fields stop when their next payment is unaffordable;
Singed's emitted clouds persist independently. Overlapping spells use distinct
generation/origin state rather than reviving cancelled effects.

Damage storage distinguishes shield absorption from lost health and outgoing
post-mitigation from incoming pre-mitigation damage. Consumed storage cannot be
spent twice. Shield decay subtracts lost capacity without restoring damage
already absorbed. Temporary base health is restored without changing the
immutable starting stats. Shared sanctuary healing is attributed separately
to each recipient, including when the caster is in the opposite matchup role.

Geometry remains a one-dimensional projection, without walls, collision,
facing changes, other targets or manual aiming/release. Ornn's forward march,
Pantheon's Mortal Will, Briar's bleed/Frenzy/forced pursuit/passive heal
amplification, Kai'Sa evolution, Lee Sin ally/ward dash/Flurry, Kindred mark
collection, Viego possession, Vi passive shield and Zoe vision/flight windows
remain excluded. Jinx acceleration is excluded. Nasus stacks, Mundo takedown
extensions, Karthus Death Defied and Singed ultimate grievous wounds are not
added. Vladimir's exceptional persistent effects and projectile collisions
remain outside scope.

Reviewed mechanical timing supplements the retained numerical records.
Mordekaiser's shield uses a four-second reviewed lifetime instead of the raw
five-second duration field and an explicit quadratic capacity decay; its exact
decay curve is not independently measured. Nunu uses linear charge scaling,
slow interpolation and post-channel shield decay. Singed cloud emission,
Mundo healing, Yi healing, Vladimir health payments and movement decay use
declared model schedules rather than captured server phases. Kai'Sa charge
interpolation uses reviewed endpoints rather than expanding the parser to
accept an ambiguous source clamp expression. These assumptions remain visible
in the retained mechanics record and ability exclusions.

## Inventory and verification

The controlled audit records **596 executing entries, 78 without an executable
effect, 12 not casting and 6 casting without an applied effect**. Exactly these
25 rows move to execution: 16 previously lacked executable effects, six did not
cast and three cast without applying an effect. Snapshot identity and parser
version remain unchanged. Counts measure execution triage, not complete kits
or an accuracy score.

`test/sustain-charge-abilities.janet` checks independent formulas/ranks,
interruptions, resource exhaustion, health reserves, decay, shield boundaries,
source guards, unchanged input bytes and optimizer scoring parity. Fifty-six
retained scenarios cover every selected slot in both positions plus mixed
sanctuary, untargetability and damage-storage fights. Runtime and desktop/mobile
browser checks require matching outcomes, complete event representation and
the named duration bands. The full existing suites protect earlier mechanics.
This batch does not create a release.

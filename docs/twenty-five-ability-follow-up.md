# Twenty-five ability-slot follow-up — 23 October 2026

This batch restores bounded combat behavior to **25 Q/W/E/R slots across 20
champions on 16.21.1**. It does not establish complete kits or measured game
accuracy. Forty original character/description responses are retained in
`data/ability-fixtures/16.21.1/twenty-five/`; their hashes match the existing
all-champion receipts. The localization excerpt records its original full-table
hash. Numerical expressions use selected source records, not copied damage
constants. Parser version remains **7**.

## Added behavior

The independent examples use rank 1, level 18, 100 AP, 150 total AD, 100 base AD,
1,000 maximum/500 current health and a 2,000-health opponent. Attack-speed
examples use a controlled ratio and initial speed of 1. Normal scenarios retain
their actual champion stats, builds, rank choices and attack-speed caps.

| Slot | Modeled result / independent example |
| --- | --- |
| Blitzcrank W | 30% bonus AS for five seconds; 60% movement bonus decays to 10% over 2.5 seconds, followed by a 30% self slow for 1.5 seconds |
| Katarina W | 50% movement bonus decaying over 1.25 seconds |
| Viego E | 30% bonus AS and `.25 + .0004*100 = 29%` movement bonus for eight seconds, assuming established mist and continuous occupancy |
| Tryndamere W | −20 enemy AD for four seconds; no inferred facing-dependent slow |
| Yuumi E | Unattached self shield `65 + .4*100 = 105`, 33% bonus AS for three seconds, and 20% movement bonus while that shield remains |
| Master Yi R | 25% bonus AS and 40% movement bonus for seven seconds; removes and prevents modeled movement/attack-speed slows |
| Taric R | Damage immunity for 2.5 seconds after the source's 2.5-second delay; crowd control still applies |
| Alistar R | Cleanses supported disabling controls and reduces physical/magic damage by 55% for seven seconds; true damage remains unchanged |
| Karma Q | Base damage `60 + .7*100 = 130`, 40% slow for 1.5 seconds, selected missile speed 1,700 |
| Karma W | Base tether: `40 + .45*100 = 85` at application and completion; roots for 1.6 seconds after two seconds if continuously within 825 |
| Karma E | Base self shield `80 + .6*100 = 140` for 2.5 seconds and 40% movement bonus for two seconds |
| Kha'Zix Q | Unevolved isolated damage `(80 + 1.05*50)*2.1 = 278.25`; isolation assumes the sole opponent has no nearby allies/minions |
| Kha'Zix W | Unevolved damage `75 + 50 = 125`; heals `55 + .5*100 = 105` when within 275 of the explosion; selected missile speed 1,700 and range 1,025 |
| Kha'Zix E | Unevolved landing damage `65 + .4*50 = 85` at modeled cast completion |
| Kayn Q | Base dash and slash each deal `75 + .85*50 = 117.5`; separate damage events at modeled cast completion |
| Kayn W | Base damage `85 + 1.1*50 = 140` and 90% slow decaying over 1.5 seconds |
| Syndra Q | Base sphere damage `90 + .7*100 = 160` at modeled cast completion |
| Veigar W | Damage `85 + .7*100 = 155` after the 1.2-second impact delay; explicit eight-second zero-stack base cooldown, affected by ordinary haste |
| Volibear E | `80 + .7*100 + .11*2000 = 370` damage and 40% slow; self shield `.14*1000 + .75*100 = 215` only if within the 325-unit blast radius |
| Nocturne E | `80 + 100 = 180` across eight model pulses over two seconds, then 1.25-second fear if continuously within 465 |
| Sivir Q | Two champion hits, each `60 + .7*50 + .6*100 = 155`; source critical-chance/critical-damage and bonus-AS cast scaling |
| Corki E | Sixteen source-rate pulses over four seconds, each `(80 + 2.4*50)/16 = 12.5`; armor/MR shred builds to 12 in four hits and lingers for two seconds |
| Rell R | Eight model pulses over two seconds, each `(75 + .55*100)*2/8 = 32.5`, gated by 375-unit range and caster life |
| Nilah W | Attack dodges, 25% magic-damage reduction and 15% movement bonus for 2.25 seconds |
| Maokai Q | `75 + .5*100 + .02*2000 = 165` damage and 99% slow for .25 seconds |

Kha'Zix W's healing radius comes from the
[mechanical reference](https://wiki.leagueoflegends.com/en-us/Kha%27Zix#Void_Spike),
recorded separately in `mechanics.json`. The generic missile `castRadius` does
not establish that healing radius. The 275/276 boundary is explicitly tested;
source-record damage, healing and missile speed remain authoritative. This
reference is not a patch-specific game capture.

## Shared behavior and regression coverage

Tethers are independent of channels. Range is checked after movement and every
state transition, with a scheduled range-exit wake. A brief escape followed by
re-entry cannot restore the tether; either participant dying also ends it.
Spell shields block application before damage or completion control can run.
The existing status lanes show each tether's actual duration, ending on escape
or death. Karma's two-hit timing follows its tooltip; Nocturne's eight evenly spaced pulses
are an explicit model schedule, not a measured server tick phase. Fear-driven
fleeing and Nocturne's chase movement remain excluded.

Defensive protection keeps damage immunity, physical/magic reductions, slow
immunity and attack dodging distinct. Taric does not block control. Alistar and
Nilah reductions do not reduce true damage; shields absorb damage after these
reductions. Successful Nilah dodges suppress the attack's ordinary procs and
scheduled empowerment effects. A timeline marker/tooltip explains the dodged
attack, and actual protection durations appear in the existing status bands.
No verification banners or additional player workflow are introduced.

Yuumi's movement modifier is tied to her own named shield, not any shield on
her. It ends immediately on absorption or expiry while her AS buff continues.
Corki checks range at every pulse, deals damage before adding that hit's shred,
starts fresh stacks after a full out-of-range expiry, and cannot gain a shred
stack from a parried or spell-blocked pulse. Later spray pulses can land after
an earlier pulse consumes a spell shield. Buff expiry and missed-hit behavior
are checked separately from casts.

Decay schedules now include their final step. Blitzcrank can reach the source's
10% floor before the five-second buff expires. Other reviewed decays still use
their documented source/model steps. Cached normalization is idempotent, saved
package bytes stay unchanged, and optimizer scoring equals full-trace scoring.

The selected snapshot's retained auxiliary spell records now supply Karma,
Kha'Zix and Sivir missile behavior. Missing auxiliary data disables the affected
handler; changing a selected auxiliary record changes the interpreted travel.
This adds no parser, provider download, migration, refresh or reparse action.
The critical-damage mapping is scoped to Sivir Q on this exact patch.

## Remaining boundaries

This batch intentionally leaves substantial kit work visible in developer
notes: Katarina daggers and refunds; Viego mist propagation/camouflage/field
exits; Tryndamere facing; Yuumi attachment and allies; Highlander takedown
extensions/refunds and pauses; Taric allies; Alistar airborne cleanup;
Karma Mantra; Kha'Zix evolutions and nonisolated targets; Kayn transformations;
Syndra splinters, charges and sphere interactions; Veigar passive stacks;
Rell pull/drag; Maokai knockback; Nilah sharing and exceptional empowered
attacks. Other champion passives are not implicitly completed.

Leap/Reaping Slash movement and actual flight or inter-hit delays are not yet
modeled. Syndra/Volibear ground detonation timing uses cast completion until
matching timing is established; Volibear's shield assumes the blast is aimed
at the opponent. Sivir assumes both phases hit and models return travel as
twice the release distance; turning geometry and subsequent movement remain
excluded. Viego's mist bonuses assume continuous occupancy of established mist.
Sixteen-step decays and Rell/Nocturne pulse phases are model approximations.
Base-form handlers do not infer Mantra, evolutions, transformation state or
pre-fight passive stacks from champion level.

## Inventory and checks

The all-champion probe now records **521 executing entries, 136 with no
executable effect, 18 not casting and 17 casting without an applied effect**.
Exactly these 25 selected rows change. This is execution triage, not an accuracy
score or complete-champion count. Source/snapshot bytes and pointers are not
rewritten.

`test/twenty-five-abilities.janet` checks independent arithmetic, rank endpoints,
expiry/decay, range, shield consumption, controls, true damage, slow immunity,
dodges/procs, continuous tether escape/re-entry/death, spray stack decay,
misses, selected auxiliary changes, future-patch exclusion and immutable data.
Fifty cases cover every selected slot in both positions. Four further cases
exercise Nilah dodges and Taric's damage/control distinction against an actual
opponent. All 54 run through the relocated standalone executable and the
existing desktop/mobile browser checks, including status bands, individual
markers and narrow layouts. This batch creates no release.

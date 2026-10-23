# Attack and defense ability follow-up — 23 October 2026

This batch adds bounded simulation behavior to **25 more Q/W/E/R slots across
24 champions on 16.21.1**. It is not a complete-kit or game-capture validation.
The 48 original character/description responses are retained under
`data/ability-fixtures/16.21.1/attack-defense/`. Their hashes match the existing
all-champion receipts. The localization excerpt retains its full-table hash;
`mechanics.json` identifies supplementary timing references. Parser version
remains **7**, and existing saved package bytes/pointers are not rewritten.

## Added behavior

Independent examples use rank 1, level 18, 100 AP, 150 total/100 base AD,
1,000 maximum/500 current health and a 2,000-health opponent. Attack-speed
examples use a controlled initial speed and ratio of 1. Ordinary scenarios
retain their actual champion, level, ranks, build, cap, regeneration and range.

| Slot | Behavior and independent example |
| --- | --- |
| Cho'Gath E | Reset; three attacks each add `30 + .3*100 + .025*2000 = 110` magic damage and a decaying 30% slow; +50 range until consumed/expired; cooldown starts after consumption/expiry |
| Kayle E | Passive `15 + .2*100 + .1*50 = 40` magic on hit; resetting ranged attack adds 9.5% of live missing health, expires after five seconds |
| Fizz W | Passive `30 + .25*100 = 55` bleed across six half-second pulses; next attack adds 95, then surviving-target attacks add 50 for five seconds; killing attack refunds 30 mana and sets one-second cooldown |
| Sett Q | Reset; two attacks each add `10 + (.01 + .0001*150)*2000 = 60` physical damage; 30% movement only while approaching the opponent |
| Volibear Q | Reset; next attack totals `10 + 150 + 1.6*50 = 240` physical damage and one-second stun; +25 range; 12% movement or 24% while approaching; immobilization cancels it and resets cooldown |
| Xayah W | 35% bonus AS for four seconds; secondary blade adds 25% of the attack's rolled raw physical damage, including its crit; a successful blade grants 30% movement for 1.5 seconds |
| Sona E | 22% self movement for at least three seconds, up to seven while unharmed; damage after the minimum ends it immediately |
| Teemo W | 12% passive movement, disabled by champion/turret health damage until five seconds pass; active replaces it with 24% for three seconds, persisting through damage |
| Miss Fortune W | Out-of-combat flat movement: +30 after four seconds and +60 after seven; active restores full movement and grants 40% AS for four seconds; new damage restarts movement recovery |
| Nasus W | 35% movement slow and 26.25% AS reduction, increasing in four source-strength steps to 47%/35.25%; coupled cleanse/immunity and tenacity-adjusted timing |
| Shen W | Ordinary attack/proc blocking for 1.75 seconds, assuming Shen and his blade are together and he remains in the zone |
| Tryndamere R | Five seconds of damage prevention below the source floor (30 at rank 1); casts while disabled and restores 50 Fury in the configured resource pool; does not heal someone already below the floor |
| Olaf R | +10 permanent armor/MR; cleanse/control immunity, `10 + .25*150 = 47.5` AD, and one-second conditional chase movement; attacks/E hits refresh remaining duration to at least 2.5 seconds |
| Malphite W | 10% permanent armor; reset and next-attack bonus `30 + .2*100 + .15*110 = 66.5`, plus `15 + .3*100 + .15*110 = 61.5` aftershock; later attacks continue aftershocks |
| Taric W | 6% permanent armor and 7% maximum-health self shield (70) for 2.5 seconds |
| Evelynn E | Base `60 + (.03 + .00015*100)*2000 = 150` magic damage, supported on-hit procs, and 30% movement for two seconds on hit |
| Kog'Maw R | Base `100 + .35*100 + .75*50 = 172.5` magic damage, increasing with missing health and doubling below 40%; mana costs 40/80/120… up to 400, reset after eight seconds without casting |
| Caitlyn R | Base `300 + 50 = 350` physical damage with source critical-stat scaling; raw .375 cast plus reviewed one-second channel and selected 3,200-speed missile; interrupted channel keeps spent mana and sets five-second cooldown |
| Pyke W | `(45 + 2*lethality)%` movement decaying over five seconds; ends on a subsequent attack/cast |
| Pyke R | Level-18 threshold `550 + .8*50 + 1.5*lethality`; below threshold, shield-bypassing true damage; otherwise half-threshold physical damage; blink on an unblocked hit |
| Gwen W | +29 armor/MR for four seconds and protection against enemy effects from outside the source's 370-unit zone; automatically follows once, ends on a second exit |
| Janna W | 8% movement installed at combat start; `55 + .5*100 + .3*8 = 107.4` magic damage in the controlled example, plus a 26% slow for two seconds |
| Diana R | Pull and 40% slow on the sole nearby champion, then a range-checked `200 + .6*100 = 260` magic explosion after the source's one-second delay |
| Milio W | Self-following campfire: 10% attack range and `70 + .15*100 = 85` healing across twelve model pulses over six seconds |
| Hecarim W | Eight half-second pulses of `(80 + .8*100)/8 = 20` magic damage, +5 armor/MR, and healing for 25% of his post-resistance damage to nearby champions |

## State and timing checks

Attack empowerments now retain their recipient, rank, source slot, consumption
count, range and expiry separately from the self-cast that installs them.
Consumption restores range and sets post-empowerment cooldowns at the actual
release boundary. Released misses also spend charges; interrupted windups do
not. Follow-up phases require a landed first hit in this model. Fizz and Malphite install their subsequent attack effect only
after the first attack. A blocked attack cannot execute its bonus damage or
self-buff callbacks. Bonus spell damage can trigger supported spell effects
without repeating the ordinary attack's on-hit procs; Xayah's secondary blade
shares its attack's crit result and suppresses an additional proc pass.

The existing Blade of the Ruined King attack-type test now isolates the item's
coefficient from champion damage. A separate numerical check verifies the
complete Kayle passive-before-item ordering. This ordering is the model's
explicit event order, not a newly measured game proc schedule.

Movement policies distinguish untouched pre-fight state, health damage,
recovery, active immunity to damage cancellation and minimum/maximum duration.
Teemo and Miss Fortune start fully recovered; Sona's boost persists for at least
three seconds. Chase bonuses require actual approach intent, and Pyke's bonus
ends when the next modeled action begins. Shields that absorb all damage do
not count as health damage for these policies.

Nasus uses the source's per-step strength and an interval scaled by tenacity.
[Riot's 26.18 notes](https://www.leagueoflegends.com/en-us/news/game-updates/league-of-legends-patch-26-18-notes/)
confirm the one-second interval and tenacity interaction. The
[mechanical reference](https://wiki.leagueoflegends.com/en-us/Nasus#Wither)
corroborates movement/AS coupling. Cleansing Wither ends both components;
old ramp events cannot reactivate the cripple when a different slow is applied.
This is a reviewed schedule, not a server-tick capture.

Undying Rage's floor prevents damage without creating shield absorption or
raising already-low health. Pyke's execute bypasses shields but respects active
damage/death protection. Equality at the execute threshold remains a normal
hit; a small numerical tolerance prevents float32 coefficient promotion from
turning nominal equality into an execute. Gwen tests incoming-source position,
retains her fixed zone center, follows once on exit, then drops protection and
resistances on a second exit. Olaf's extension refreshes remaining time rather
than accumulating an unbounded duration.

Permanent armor multipliers appear in build stats and preserve their provenance
when flat temporary armor or reductions apply. Positive flat armor is scaled
by the permanent bonus, then explicit shred and percentage reductions apply:
`(100 + 25)*1.1 - 25`, followed by a 25% reduction, gives 84.375. Damage-vamp healing includes
shield absorption after resistance, excludes damage prevented by a health floor,
and stops when the caster dies. The final W pulse retains its own healing at
the buff boundary, while other damage uses the active vamp window.

Caitlyn's timing/cancellation supplement is identified in
[the ability reference](https://wiki.leagueoflegends.com/en-us/Caitlyn#Ace_in_the_Hole).
The selected raw missile record supplies travel. Target death or control
cancels the channel. The corresponding
[Olaf reference](https://wiki.leagueoflegends.com/en-us/Olaf#Ragnarok) documents
his remaining-duration refresh. Neither supplement is a patch-specific combat
recording. Selected primary/passive records now accompany auxiliary records
for cross-spell references; Janna's Tailwind calculation comes from that same
snapshot. Missing cross-spell source data disables the dependent effect.

Status bands observe actual active modifiers, protection, empowerment and vamp
state. Consumed, cleansed or expired prerequisites cannot leave stale stat bands.
Shen's blocked attacks have a distinct marker/tooltip using the existing fixed
layout. No player verification dashboard, automatic refresh or reparse is added.

## Remaining boundaries

These are still partial kits. Remaining exclusions include Feast-stack growth
and spike geometry; Kayle explosions and exceptional hit ordering; Fizz Q
application/monster rules; Sett's alternating-hand timing; Xayah feathers and
Rakan sharing; Sona's allies/Power Chord; Miss Fortune's Love Tap/refunds;
Tryndamere's Fury-derived crits; Malphite's Granite Shield/tripled armor;
Taric links and duplicated spells; Evelynn's Demon Shade empowerment/dash;
Pyke camouflage, grey-health healing, geometry, recasts and kill gold;
Gwen manual reposition/edge hitboxes; Diana airborne/flight geometry and
multi-champion amplification; Milio ally retargeting/Fired Up; Hecarim allies
and monsters. Shen's blade-zone occupancy is assumed, not simulated placement.

Kog'Maw ground detonation timing uses cast completion until matching impact
context is established. Milio's twelve half-second healing pulses and the
remaining sixteen-step decays are explicit model schedules. Xayah's secondary
blade uses ordinary modeled attack delivery; separate travel is excluded.
Kayle E uses the existing ordinary delivery and evaluates its execute after
the base hit and before queued passive/item procs. Janna's passive movement is
installed at combat start using that moment's AP; later AP changes to it are
excluded. Olaf's AD amount is evaluated at activation. Exceptional attack,
untargetability and displacement interactions remain unverified.

## Inventory and verification

The controlled probe now records **546 executing entries, 116 with no executable
effect, 18 not casting and 12 casting without an applied effect**. Exactly these
25 selected rows change. The probe now includes zero flat armor penetration,
as ordinary empty builds do, so Pyke's scoped lethality expressions have a
valid baseline. Counts remain execution triage, not a complete-champion or
accuracy score.

`test/attack-defense-abilities.janet` checks independent arithmetic/rank
endpoints, recipients, consumption/reset/expiry, shield/proc boundaries,
combat movement, coupled control, zone entry/exit, death protection,
threshold equality, cost caps/recovery/affordability, vamp, permanent armor,
source/snapshot guards and scoring parity. Fifty retained scenarios cover
all 25 slots in both positions; Kayle uses a legal fully assigned level-18
build. Six additional scenarios exercise Shen attack blocking, Tryndamere
against a real Pyke execute, and Gwen against a ranged Caitlyn ultimate.
The 56 cases run through the relocated executable and desktop/mobile UI,
including individual events, status bands, both roles and narrow layouts.
This batch creates no release.

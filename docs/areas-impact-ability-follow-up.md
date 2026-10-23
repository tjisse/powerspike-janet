# Area, impact and recovery follow-up — 23 October 2026

This batch adds bounded simulation behavior for **25 more Q/W/E/R slots across
24 champions on 16.21.1**. These are partial kits, not game-capture validation.
In particular, Senna E currently adds movement only, Twitch W adds its slowing
cloud only, Tryndamere Q adds its active heal, and Vel'Koz R excludes Research
and passive true damage. Those omissions remain visible in the spell notes.

The 48 original character/description responses are retained under
`data/ability-fixtures/16.21.1/areas-impact/`. Their response hashes match the
all-champion audit receipts. `strings.json` is a selected localization excerpt
with its original full-table hash retained in the manifest; `mechanics.json`
records supplementary references and explicit model schedules. Parser version
stays **7**. No saved package, raw response, snapshot pointer or parser migration
is changed; the existing semantic layer interprets the selected package.

## Added behavior

Independent examples use rank 1, level 18, 100 AP, 150 total/100 base AD,
1,000 maximum/500 current health and a 2,000-health opponent. Controlled base
armor/MR are 50/25 and final armor/MR are 100/50. Initial attack speed and ratio
are 1; movement is 100. Ordinary saved scenarios keep actual champion stats,
ranks, regeneration, ranges and caps.

| Slot | Included behavior and independent example |
| --- | --- |
| Aatrox E | Source champion-damage vamp: 16% without bonus health; a 150-damage attack heals 24. Dash advances toward the opponent up to 300 units at cast completion. |
| Alistar E | Ten radius-checked half-second pulses total `80 + .7*100 = 150` magic damage if all land. Five damaging pulses grant a stunning attack adding 275 magic at level 18. Consuming it ends the aura. |
| Amumu W | Toggle pays four mana per half-second interval and applies `(10 + 1.5%*2000)/2 = 20` magic per in-range pulse. Stops when its next interval is unaffordable. |
| Anivia R | Fixed-position growing storm, 60 initial mana plus 35/second. Half-second damage grows from 21.25 to 63.75 at 1.5 seconds; slow grows from 20% to 30%. Control, leash or mana depletion ends it. |
| Braum E | Negates the first non-true hit, then reduces non-true damage by 35%, assuming continued facing toward the sole opponent. Also grants 10% movement for three seconds. |
| Ezreal W | A four-second mark detonated by a subsequent attack or damaging ability for `80 + 50 + .9*100 = 220` magic. An ability detonation refunds its actual paid mana plus 60; ordinary attacks do not refund mana. |
| Gangplank Q | `10 + 150 = 160` physical damage, source critical scaling and supported on-hits once. The selected auxiliary missile supplies speed 2,600. |
| Ivern W | Brush at the caster's position grants `20 + .2*100 = 40` magic on hit, lingering three seconds after exit. Three charges, source recovery, separate brush locations and non-stacking on-hit application. |
| Kled W | Automatic four-attack burst grants 150% bonus AS. Fourth hit adds `20 + (4.5% + 1%)*2000 = 130` physical with no bonus health. Consumption/expiry starts cooldown; subsequent champion hits refund it. |
| Lucian E | Source-range advance and attack reset; the next Lightslinger adds 90 physical at level 18, inherits the ordinary attack's crit, applies its own on-hit once and refunds four seconds of E cooldown across the two hits. |
| Malzahar R | Immediate suppression, ten beam ticks totaling 205 magic over 2.5 seconds, and an independently lasting fixed pool totaling 250 against the controlled target. Caster interruption ends beam and suppression. |
| Milio Q | `80 + 1.2*100 = 200` magic, 45% slow, 140-unit push and 25 mana refund on a champion hit. |
| Nautilus Q | `85 + .9*100 = 175` magic, one-second stun and both actors pulled to their midpoint. Uses the selected missile speed and normal cast range. |
| Ornn E | `80 + .4*50 + .4*25 = 110` physical from bonus resistances; advances toward the opponent within the source 650-unit charge range. No terrain knockup is invented. |
| Rumble Q | Twelve quarter-second range checks total `50 + 1.05*100 + .06*2000 = 275` magic; Danger Zone increases this to 412.5. Reviewed Q/W casts generate heat, with delayed decay and overheat locking abilities. |
| Rumble W | `25 + .3*100 + .04*1000 = 95` shield for 1.5 seconds and 10% movement for one second. Danger Zone gives 142.5 shield and 15% movement. |
| Taliyah W | Delayed 400-unit displacement toward the caster; capped at their current separation. Starts after cast time plus the source half-second delay. |
| Thresh E | Active `65 + .6*100 = 125` magic, 20% slow and 200-unit push. Passive begins fully charged and adds 135 magic with zero souls; after five seconds it adds 67.5. |
| Trundle E | Fixed-position six-second pillar slows nearby enemies by 34% and initially pushes the centered opponent 225 units away. Terrain collision is excluded. |
| Twitch W | Fixed-position three-second cloud applies a source/AP-scaled 36% slow while in range. Poison and Contaminate are still excluded. |
| Warwick R | Move-speed-dependent cast range, modeled landing, suppression, three hits totaling `175 + 1.67*50 = 258.5` magic. Each hit applies supported on-hits; channel vamp heals their post-resistance damage including the final pulse. |
| Fizz R | Retained 1,300-speed missile, release-distance tier, attachment slow, then damage/one-second knockup two seconds later. Below 455 units: 240 magic; 455–910: 300; above 910: 360. |
| Senna E | Source AP-scaled 25% movement for six seconds after casting. Camouflage and target visibility remain excluded. |
| Tryndamere Q | Consumes the configured Fury pool, capped at 100: `30 + .3*100 + 100*(.5 + .012*100) = 230` healing. No Fury generation or passive AD is implied. |
| Vel'Koz R | Ten evenly spaced channel ticks total `450 + 1.25*100 = 575` magic, with source slow and per-tick range checks. Caster control interrupts it. |

## State, timing and source checks

Fields keep their original center or follow their caster as declared, check
radius at each model tick, and retain a generation token so a stale tick cannot
revive a cancelled/replaced effect. Mana-draining toggles cannot be cast again
while active; their cooldown starts when they end. Cast-inhibiting control
ends Anivia's field immediately. Its slow lingers according to the selected
source; the growing radius is a linear projection of the reviewed 200–400
bounds. Damage fields first tick after one interval; stationary slowing fields
start immediately. These phases are model schedules, not captured server ticks.
Fixed persistent effects and moving auras have explicit death behavior.

Beams retain their channel origin, suppress only the selected opponent and stop
on caster interruption. Malzahar and Warwick also break on out-of-range checks;
Vel'Koz can continue channeling when the opponent leaves the beam. Removing a
beam clears its own suppression without removing a later overlapping control.
Warwick's separate on-hit origins prevent the three hits from collapsing into
one proc. Channel vamp includes their damage and ends on interruption.

Essence Flux keeps owner, amount, expiration and mana return separately from
the hit that applies it. It detonates once, does not activate from an independent
item proc, and cannot refund mana for an ordinary attack. The actual paid cast
cost is retained by origin; it is not reconstructed from an unhasted tooltip.

Kled starts its burst on an attack instead of spending an automatic spell cast.
The consumed count, fourth-attack damage, attack-speed effect and post-burst
cooldown share the existing empowerment state. Alistar's bonus can be blocked
by a spell shield separately from the ordinary attack; a released miss preserves
this particular empowerment. Other exceptional block/dodge cases remain open.
Lucian's secondary hit gets a distinct on-hit origin and shares the primary
attack's critical roll, rather than rolling an unrelated spell crit.

Cross-spell formulas and projectiles come from the same selected snapshot.
Missing required auxiliary records or projectile speeds fail closed. A future
patch does not inherit these handlers. Re-normalizing the selected package is
idempotent, and the saved package bytes are checked unchanged after simulation.
The controlled audit now counts applied displacement and movement as effects;
it does not require an ability to deal damage to be useful.

## Remaining boundaries

These additions do not supply complete champion kits. Ground placement is a
one-dimensional projection; fields sample occupancy at their declared tick
schedule. Dashes and displacements are instantaneous at modeled completion,
without flight, collision, terrain, airborne travel or facing controls. Casting
during another spell's windup, manual cancellation/reposition and other targets
remain excluded. Parrrley keeps an assumed quarter-second cast time. Milio's
bounce flight is not yet applied. Nautilus' exceptional spell-shield partial
movement is excluded. Fizz's additional passive application and exceptional
attachment interactions remain excluded.

Other exclusions include Aatrox R amplification; Alistar's other passives;
Amumu's Curse refresh; Anivia's Frostbite synergy and manual final toggle tick;
Braum's missile interception and exceptional true-damage behavior; Gangplank
barrels/gold; Ivern allies, vision and natural brush; Kled's dismount/special
hit rules; other Lucian spells' Lightslinger activation and Vigilance;
Malzahar voidlings; Ornn terrain; Rumble's E/R heat interactions, overheated
attacks, cone and trailing burn; Taliyah's E interaction; Thresh soul collection;
Trundle terrain obstruction; Twitch poison; Warwick's leap path and passive heal
amplification; Senna camouflage; Tryndamere passive AD/Fury generation/crit; and
Vel'Koz Research/Deconstruction/true-damage conversion. Source numerical examples
are checks of this bounded model, not newly observed game outcomes.

## Inventory and verification

The full controlled probe records **571 executing entries, 94 without an
executable effect, 18 not casting and 9 casting without an applied effect**.
Exactly these 25 selected rows change from the previous inventory: 22 previously
had no executable effect, and three cast without applying one. Snapshot identity
and parser version remain unchanged. These are execution-triage counts, not a
complete-champion count or an accuracy score.

`test/areas-impact-abilities.janet` checks independent damage/healing arithmetic,
recipient and timing boundaries, mark expiry/refunds, area radius/mana/control,
channel interruption, attack consumption, crit/on-hit separation, heat and
source guards. Fifty retained scenarios cover every slot in both positions and
require optimizer scoring parity. They are exercised in the relocated executable
and desktop/mobile UI, including status bands and complete event representation.
No release is created by this batch.

Supplementary mechanical references: [Alistar](https://wiki.leagueoflegends.com/en-us/Alistar),
[Anivia](https://wiki.leagueoflegends.com/en-us/Anivia),
[Braum](https://wiki.leagueoflegends.com/en-us/Braum),
[Kled](https://wiki.leagueoflegends.com/en-us/Kled),
[Rumble](https://wiki.leagueoflegends.com/en-us/Rumble),
[Nautilus](https://wiki.leagueoflegends.com/en-us/Nautilus),
[Thresh](https://wiki.leagueoflegends.com/en-us/Thresh),
[Fizz](https://wiki.leagueoflegends.com/en-us/Fizz).
Numbers available in the retained game records take precedence over prose.

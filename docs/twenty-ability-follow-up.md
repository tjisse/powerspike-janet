# Twenty ability-slot follow-up — 23 October 2026

This batch adds reviewed effects to **twenty Q/W/E/R slots on 16.21.1**.
These remain bounded duel simulations, not complete champion kits or new game
captures. The complete matching character/description pairs for seventeen
champions are retained in `data/ability-fixtures/16.21.1/twenty/`. The manifest
records original URLs/hashes and the full string-table hash; the localized
fixture is an excerpt. Original source hashes match the all-champion receipts.

## Implemented behavior

The independent examples use 100 AP, 150 total AD, 100 base AD, 1,000 maximum
health, 500 current health and a 2,000-health opponent, unless stated otherwise.
Attack-speed examples use a controlled ratio of 1 and initial speed of 1;
ordinary scenarios use their champion's actual ratio, growth, build and cap.

| Slot | Added behavior and example |
| --- | --- |
| Warwick Q | Tap damage `1.2*150 + 100 + .06*2000 = 400`; against 100 MR this deals 200 and heals 50 at rank 1, including damage absorbed by a shield |
| Singed W | Delayed 50% slow and grounding for three seconds; the model adds the .375 execution delay after its .25 cast |
| Singed E | `50 + .55*100 + .06*2000 = 225` magic damage and an immediate 420-unit flip over the caster in one dimension |
| Katarina E | `20 + .25*100 + .4*150 = 105` magic damage, enemy-target blink, attack reset and the matching auxiliary .15 cast time |
| Xin Zhao R | `75 + 50 + 1.1*100 + .15*2000 = 535` physical damage at full target health; four seconds of champion damage immunity beyond 450 units |
| Yone W | Equal physical/magic halves: `(10 + .08*2000)/2 = 85` each; sole-champion shield `(90 + .65*50)*2 = 245` at level 18; bonus-AS cast/cooldown scaling with source caps |
| Lulu Q | Primary-bolt `60 + .5*100 = 110` magic damage and an 80% slow decaying over two seconds using eight source-defined steps |
| Lulu W | Offensive polymorph for 1.2 seconds at rank 1, blocking attacks/casts while subtracting 60 movement speed |
| Vel'Koz Q | Primary-bolt `80 + .9*100 = 170` magic damage, reviewed speed 1,300 and a decaying 70% slow |
| Trundle W | 30% bonus AS, 20% movement speed and 25% increased healing for eight seconds, assuming he remains inside his domain |
| Draven W | 20% bonus AS for three seconds and 50% movement speed decaying across 1.5 seconds |
| Twitch R | +30 AD and +300 attack range for six seconds at rank 1, with range restored on expiry |
| Sivir R | 20% movement speed for eight seconds and .5 seconds off basic cooldowns for each distinct champion attack while active |
| Zilean W | Ten seconds off Q/E cooldowns, with newly ready actions waking at the changed deadline |
| Teemo E | Passive impact `9 + .3*100 + .05*50 = 41.5` and poison ticks `6 + .1*100 + .025*50 = 17.25`, once a second for four seconds; refresh preserves the next tick |
| Karthus W | 25% MR reduction and a decaying 40% slow for five seconds, assuming the opponent crosses the wall |
| Nocturne W | 30% permanent bonus AS at rank 1; a 1.5-second spell shield; blocking adds another 30% bonus AS for five seconds |
| Sivir E | A 1.5-second spell shield; blocking heals `.6*150 + .5*100 = 140` at rank 1 |
| Kassadin W | Passive `25 + .1*100 = 35` on-hit magic damage, next-attack `50 + .8*100 = 130` bonus magic damage and 20% missing-mana restoration against a champion |
| Olaf W | Attack reset, 40% bonus AS for five seconds, and a 2.5-second shield `10 + .175*500 = 97.5`; capped at 132.5 below 30% health for 1,000 maximum health |

## Shared semantics and boundaries

Spell shields consume once for an eligible enemy spell impact. Damage/control
components of that impact share a key; later pulses, return hits, Judgment
spins, drain ticks and Echo releases use separate keys. The first pulse can be
blocked without suppressing an entire continuing spell. Already-applied poison,
ordinary attacks and item/on-hit procs do not consume these shields. A blocked
application schedules no poison pulses. A shield expires at its exact end;
an impact exactly then can land. Effects that fail their impact range or
caster-alive gate cannot consume it. Riposte takes precedence if both defenses
are active; exceptional spell/defense interactions remain unverified.
An owner already reduced to zero health cannot consume a shield or trigger its
healing reaction, including a later event at the lethal hit's timestamp.

The timeline shows a spell-block marker and tooltip. The status band ends when
the shield is consumed or expires; Nocturne's attack-speed reaction and Sivir's
healing belong to the defender. These are combat outcomes, not verification UI.

Teemo's poison reapplication extends its end while preserving the next pending
tick. Repeated attacks faster than one second must not postpone every tick
until attacks stop. Tick amount remains the source's per-second amount when a
refresh changes how many pulses fit before the new end. Damage-over-time
applications can continue after their caster dies. Monster variants and other
kit interactions remain excluded.

Mixed active/passive slots install hit triggers without replaying them as cast
effects. Nocturne's permanent bonus uses the learned rank before build stats
are calculated; its successful-block bonus is additional AS, rather than a
multiplier on total attack speed. Twitch's AD/range changes preserve the
actor's original stat provenance. Both return to their original values at
expiry, and live range controls actual attack eligibility.
Trundle's healing amplification multiplies existing healing modifiers: a
40% reduction combined with his 25% amplification yields `.6 * 1.25 = .75`,
not `.6 + .25 = .85`. Temporary flat stat changes precede multipliers and
final floors in a stable order. Thus 100 armor plus 25 armor and 25% reduction
always gives 93.75, regardless of modifier names or table iteration order.

Yone's W cooldown is rebuilt from the raw base cooldown on every model load,
preventing cached normalization from compounding the AS reduction. It ignores
ability haste. The modeled bonus-AS total drives its source formulas; special
eligibility rules for runes and temporary buffs are not established here.
Its primary tooltip names `BaseDamage` and `MaxHealthDamage`; the model uses
those expressions. The separate `WDamage` calculation is not selected. The
shield requires an unblocked strike.

Katarina's cast time and Vel'Koz's missile speed come from retained auxiliary
spell records. Their full source files are hash checked and embedded at build
time. The supplement is accepted only with an identical selected primary
record, ignoring model bookkeeping keys. A changed record disables the reviewed
effect instead of pairing it with unrelated movement data. Relocated execution
checks that runtime source files are not required.

Polymorph stops attacks/casts, interrupts channels even when brief, and reduces
movement without immobilizing the target. Expiry or a supported cleanse removes
its movement penalty. Existing Gangplank W now also cleanses polymorph. This is
compatibility with the new control type, not a twenty-first newly restored slot.
Rewind and On the Hunt change only ordinary basic cooldown deadlines; they do
not adjust recast, charge or ultimate timers.

Lulu's eight decay steps come from `SlowDecayTicks`. Draven's eight steps are
inferred by rounding the ratio of initial speed bonus to the source decay
coefficient, then spacing them over its duration. Vel'Koz/Karthus decay uses
sixteen evenly spaced model steps. These are explicit timing approximations,
not measured server tick schedules. Refresh/cleanse tokens stop stale decay
events from overwriting a replacement effect.

Kassadin's empowerment expiry is not established by this source, so the effect
is retained until its next attack within the configured fight. Internal expiry
and unlimited-hit sentinels are finite bounds beyond the simulation horizon or
event budget. This preserves modeled behavior while keeping CLI/HTTP JSON
valid; no game expiry is inferred from those internal bounds.

Remaining exclusions include Warwick's held following; Singed field exits and
Fling landing roots/airborne timing; Katarina dagger/ally targeting and pickup
refunds; Xin's Challenge-dependent knockback; Yone geometry/other passive
effects; Pix's extra bolt/position; Vel'Koz splits, recasts and passive stacks;
Trundle field exits; Draven axe catches; Twitch's piercing projectile delivery;
Sivir's allies, takedown refresh and Fleet of Foot; and exceptional spell-shield
interactions. Existing movement/attack timing assumptions still apply.

## Developer verification and inventory

`test/twenty-abilities.janet` checks independent arithmetic, rank/cap boundaries,
shield absorption and healing, hit/miss behavior, displacement, live health,
range/AD expiry, actual cooldown resumption, poison phase, shield boundaries,
same-impact grouping, continuing/return impacts, pre-existing poison, source
guards, immutable saved bytes and optimizer equality.

Forty scenarios cover all twenty slots in both matchup positions; four further
scenarios check Nocturne/Sivir blocking a real Lulu Q in each position. Retained
metrics and event counts run through the relocated executable and shared
desktop/mobile browser check, including block markers, status bands, passive
controls, saved ranks and 320 px layout.

The inventory now records **496 executing entries, 155 with no executable
effect, 19 not casting and 22 casting without an applied effect**. Nineteen
selected slots move to execution. Isolated Rewind has no other learned ability
on cooldown, so it moves from no-executable-effect to cast-without-effect;
the E-enabled regression separately verifies its actual ten-second refund.
Gangplank's compatibility note also changes. Counts remain triage, not an
accuracy score or a claim of complete champion support.

Parser version remains **7**. Matching raw sources are interpreted by the
current model without rewriting saved snapshot bytes or current pointers.
There is no automatic refresh, reparse, migration or repair, and no release is
created by this batch.

# Vayne Silver Bolts — 23 October 2026

This fifth completeness batch implements **Vayne W on 16.21.1**. The slot is
passive: expecting it to cast was the wrong execution test. The retained
`Trait_PassiveSlot` source, health ratios, damage floor and mark duration are in
`data/ability-fixtures/16.21.1/passives/`, with original response hashes and
localized descriptions.

## Model behavior

Learned Silver Bolts becomes a passive hit trigger, excluded from active ability
selection. It works while active casting is disabled and does not consume mana
or start an ability cooldown. The source-defined percentage of target maximum
health, with `DamageFloor` as a lower bound, applies as true damage on every
third consecutive originating attack/ability hit against the sole opponent.
In Vayne's modeled kit, ordinary/empowered attacks and Condemn supply those hits.

Marks use `DebuffDuration` and refresh from the most recent distinct hit. A hit
at exact expiry starts a new sequence. Two damage components from one action
share an origin and count once. Distinct actions at one timestamp can each
count; this passive does not inherit an artificial one-millisecond proc lock.
After a proc the last origin is retained so another component of that same
attack cannot immediately start a new sequence. Existing item/rune procs retain
their previous timing and window rules.

The opponent's status lane shows the active Silver Bolts mark, ending on the
third hit or refreshed expiry. The damage uses the W icon in the attacker's
lane. W's detail tooltip identifies it as passive, and cast-condition fields
are disabled while the learned-rank control remains available.
Percentage tooltips render 4%/10%, using presentation-only scaling while combat
retains its fractional source ratios. Fiddlesticks Q receives the same fix.
The formula explanation renderer also supports the new safe arithmetic nodes,
so Garen's calculated spin count is shown instead of its old placeholder.

## Numerical and timing checks

The selected source gives 4% maximum health with a 40-damage floor at rank 1,
and 10% with a 100-damage floor at rank 5. Thus 2,000 maximum health receives
80 or 200 true damage respectively. At rank 1, a 100-health target still
receives 40 raw damage; rank 5 into 500 health receives 100. Armor, magic resist
and ordinary critical damage do not change these raw true-damage values.

`test/vayne-abilities.janet` checks all these examples, rank-zero exclusion,
no casts/resource cost, the three-hit threshold, Condemn sharing the counter,
duplicate components, simultaneous distinct hits, parry and marks refreshed
through a longer sequence. Its synthetic hits at 0, 3 and 6 seconds must proc
because each interval is less than 3.5 seconds; hits at 0, 3.5 and 7 must not.
Real compiled scenarios cover both matchup positions, optimizer equality,
standalone execution and desktop/mobile timeline representation.

## Developer audit and remaining scope

The all-champion probe now installs explicitly modeled passive slot triggers.
A passive can be classified as executing with **zero casts** when its applied
effect is observed. A passive that never triggers has its own
`passive-without-effect` category rather than being described as a failed cast.
The synthetic zero-cooldown guard for active abilities remains intact.

This does not establish a complete Vayne kit. Pre-fight marks, target switching,
monster variants and exceptional interactions remain excluded. Attack timings
retain their existing source/default assumptions rather than new game captures.
Other champions' passive slots still need their own reviewed handlers. The
ability-slot audit does not cover all P passives or automatic forms.

Parser version remains 7. Existing source/snapshot bytes and current pointers
are unchanged; passive compilation is part of the current semantic model. No
automatic migration, reparse or refresh is introduced.

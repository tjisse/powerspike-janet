# Remaining ability review — 16.21.1

This reviews all **96** entries that did not execute after the sustain/charge
batch. **75 slots across 56 champions now have bounded combat implementations**. The controlled
all-champion audit moves from **596 to 666 executing entries**; five more
implemented slots require real setup absent from an isolated zero-distance
probe. Eleven other entries are contextual exclusions, and **ten slots remain
unsupported**. Neither execution nor this review establishes complete kits or
agreement with measured game combat.

## Sources and preservation

`data/ability-fixtures/16.21.1/remaining/` retains the original character and
ability-description responses for 67 champions, selected matching strings,
three additional summon roots and a hash-bound `mechanics.json` inventory.
Original response bytes and receipt hashes are preserved. Numeric formulas
bind to the selected kit, including auxiliary spell records; handlers apply
only to **16.21.1**. Future patches do not inherit the overrides.

The full audit still uses snapshot
`6532a5438b5858bb36c56d1542cfe547319b84b34ee2e406074ca13d36d858e1`
and parser **7**. The combat-model identity changes. Refresh and reparse remain
manual; no saved snapshot is rewritten or migrated.

## Implemented behavior

The per-slot mechanics record contains all exclusions. Principal groups are:

| Mechanics | Selected slots / boundaries |
| --- | --- |
| Conditional resources and attacks | Ashe Q, Kalista E, Yunara Q, Viego Q, Mel R and Varus W require real attack/spell state; Urgot W replaces attacks at three shots/sec, prevents critical damage and halves supported item on-hit damage. |
| Channels and followups | Aurelion Sol Q/W, Akshan R, Ambessa Q, Vex R, Sion Q and K'Sante W use cancellation, release and recast rules. Ambessa/Vex cannot recast before an applied initial hit. Maximum-rank Breath of Light is bounded by the model's 180-second limit. |
| Stealth | Akali W, Akshan W, Aurora W, Kha'Zix R, Shaco Q, Twitch Q and Wukong W affect new attack/point-target selection. Camouflage uses source detection distance. Already released attacks retain their normal delivery. True Sight and detailed concealment geometry remain excluded. |
| Movement and forms | Mini Gnar Q/W/E, Hammer Jayce Q/W/E, Human Elise Q/W, Rell W, Rek'Sai W, Graves E, Kayn E/R, Rek'Sai R, Twisted Fate R, Yone E, Ryze R, Taliyah R and Yunara E/R apply bounded stance, transit and temporary-stat rules. Alternate-form Q/W/E and automatic transformation are not implied. |
| Damage and fields | Hwei QQ/R, Illaoi Q, Shyvana human E, Smolder Q, Corki W, Zoe direct Q, Fiora Q/R, Nilah R, Zaahen R, Briar W, Zeri Q/E and Locke W use selected formulas and explicit model timing. Hwei other subjects, Smolder stack upgrades and several passive interactions remain excluded. |
| Defensive / shared state | Bard R puts both occupants into stasis. Mordekaiser R steals six selected stats. Rammus W reflects ordinary attacks once. Teemo R arms before occupancy and refreshes four poison ticks. Tahm Kench E stores actual health damage; R requires three attack-applied marks. |
| Conditional buffs and recovery | Quinn W grants buffs after a Q/E-created Harrier mark is consumed. Warwick W uses source thresholds, real-hit AS and damage lockout. Renata W ramps buffs, transitions once on lethal damage and resolves burn/takedown recovery; Renata R forces hostile attacks. |
| Projectile / feather state | Yasuo W rejects explicitly reviewed incoming projectile paths that crossed its fixed plane while active. Xayah E recalls planted Q/R/Clean Cuts feathers, applies per-feather damage falloff and roots after three applied returns. |

Independent arithmetic checks include 595 rank-one Aurelion Sol Q damage over
3.25 seconds at 100 AP; 25 Yone E true damage from 100 qualifying health damage;
540 Tahm Kench R damage against 2,000 maximum health at 100 AP; 504 Urgot W
replacement damage across twelve rank-one shots; and 315 Xayah E damage across
five feathers worth 70 before falloff. Tests also check rank rebinding,
misses, spell shields, expiry, resource exhaustion, interrupted channels,
healing after damage, delayed return and both participant positions.

Important explicit assumptions include quarter-second occupancy/status
sampling, direct one-dimensional movement, a fixed 0.15-second Zeri Q windup,
a fixed Wind Wall plane and block reporting at scheduled impact. Wind Wall
covers retained ranged attack projectiles and selected reviewed spells, not
all League projectiles. Renata's retained numeric burn is ten quarter-second
ticks (2.5 seconds), while its prose says three seconds; this discrepancy is
retained explicitly. No new live-game timing verification is claimed.

## Contextual probe outcomes

- Rakan E, Shen R, Yuumi W and Kalista R require another allied champion.
- Akshan E, Bard E, Qiyana W and Talon E require an existing terrain anchor.
- Ashe E grants map vision; Aphelios E is informational, not an active spell.
- Zilean W needs a basic cooldown to refund in the isolated probe.
- Implemented Quinn W, Xayah E and Tahm Kench E need Harrier, feathers or incoming
  damage. Implemented Ryze R and Taliyah R need a sufficiently distant target
  destination. Their native scenarios provide actual prerequisites.

These statuses identify model context rather than manufacture zero-value
shields, unconditional buffs or pretend casts. They are developer-only audit
classifications.

## Still unsupported

| Slot | Required work |
| --- | --- |
| Aphelios Q/W | Weapon/ammunition state, independent weapon cooldowns and associated attacks. |
| Elise R, Jayce R, Nidalee R | Dynamic form switching and alternate ability dispatch. Existing fixed form selections remain explicit; reviewed base forms retain supported abilities. |
| Shyvana R | Fury-gated activation, live Fury generation/drain, transformation lifetime and upgraded basic abilities. |
| Heimerdinger Q | Independent turrets, beam charging, target selection and effective attack cadence. The retained Yellow root says 1.25 AS; the supplemental wiki lists 1.75. Do not silently treat either as measured runtime cadence. |
| Zyra W | Seed placement/destruction, Q/E germination, independent plants and their damage/slow rules. Matching plant roots are retained for this work. |
| Illaoi E | A separately damageable spirit, correct pre-mitigation transfer/caps and vessel behavior. A debuff marker alone would not implement this spell. |
| Sylas R | Borrowed ultimate state, stat conversion, per-target lockout and champion-specific exceptions. |

Other implemented slots also remain partial: for example Wukong's clone,
Fiora's directional vitals, Locke's temporal recovery, Hwei QW/QE and Zed's
shadow mimics are excluded. The mechanics record and existing simulation
limitations retain these boundaries.

## Verification

`test/remaining-abilities.janet` checks original source hashes, semantic
idempotence, independent formulas, actual state transitions, maximum-rank audit
execution, future-patch guards and unchanged cached package bytes. Its native
fixture contains **152** scenarios with complete/scoring parity, both roles,
real conditional setup and incoming Wind Wall projectiles. The Makefile and
CI run interpreted, relocated executable and desktop/mobile browser checks.
Named status bands and complete timeline representation are checked as well.
The existing suites protect previous mechanics and UI behavior.

This work does not create a release.

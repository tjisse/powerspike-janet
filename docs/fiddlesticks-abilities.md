# Fiddlesticks abilities — 23 October 2026

This batch replaces three excluded effects on **16.21.1** using the retained,
hashed sources in `data/ability-fixtures/16.21.1/`. It builds on the earlier
source-root correction, which restored E's ordinary damage. Earlier patches
and unreviewed future patches retain their previous scope.

## Included model

E now also applies its source-defined slow for `SilenceDuration`. The ground
slash uses zero projectile travel at cast completion; center-hit silence remains
excluded because the current model has no center/edge aim state.

Q evaluates current health times `TotalPercentHealthDamage`, with the
`MinimumDamage` floor, and applies the ranked fear. A per-target, per-caster
timer prevents repeated fear and selects doubled damage during a recent fear.
The timer uses the source Q cooldown and current haste. Passive unseen/effigy
fear is not generated, so a synthetic early recast isolates the doubled branch
in regression tests rather than claiming Q naturally resets.

W locks actions during its source cast time plus `DrainDuration`. It schedules
`TicksPerSecond` drain hits, adds `PercentMultiplier` times missing health to
the final hit, and heals using `VampPercentage` of pre-mitigation damage. That
healing observes healing reduction and maximum health. Completed channels and
target death refund 60% of remaining cooldown. Escaping `DrainLeashRange` ends
the channel without a refund or final hit. A 0.0000001-unit crossing offset
avoids retrying forever exactly on the boundary; this simulation coordinate
convention does not establish live server tick phase.

R uses `ChannelTime` before blinking to the opponent's location selected at cast
start. The destination stays fixed if the opponent moves. `DamageDone` gives
the per-tick amount and its 0.25 multiplier establishes the interval. `Duration`
and `castRadius` supply the five-second window and 600-unit radius. Each tick
checks the caster is alive and the opponent is currently in range. The first
tick is scheduled one interval after channel completion.

Interruptible-channel state remembers control applied during the channel. A
short stun or silence cannot expire and accidentally allow the interrupted
ability to release later. Grounding additionally blocks and interrupts R;
roots do not interrupt W/R. After R releases, ordinary control does not end its
active damage; death does. Channel/Crowstorm durations use existing status bands.

## Independent regressions

| Rank-1 example, 100 AP, no target resistance | Expected |
| --- | --- |
| Q into 2,000 current health | `(.04 + .0003 * 100) * 2000 = 140` raw magic damage |
| Q into 100 current health | 40 minimum damage |
| W ordinary tick | `(60 + .45 * 100) / 4 = 26.25` |
| W final tick, full-health 2,000 HP opponent | `26.25 + .12 * (7 * 26.25) = 48.3` |
| Completed W total/healing | 232.05 damage, 58.0125 healing |
| Completed W readiness | `2.25 + (10 - 2.25) * .4 = 5.35` seconds |
| R tick/complete duration | `(150 + .5 * 100) / 4 = 50`; twenty hits total 1,000 |

`test/fiddlesticks-abilities.janet` checks these equations, damage floors and
recent-fear behavior, pre-mitigation healing against resistance, control during
and after channeling, exact simulated endpoints, tether loss, target/caster
death, fixed blink destinations, range changes, both matchup positions and
optimizer equality. The same scenarios run through the relocated executable
and shared desktop/mobile ability browser check.

## Scope and evidence limits

This is a partial kit, not live-game verification. Unseen/effigy fears, actual
fear-driven fleeing, E's center silence, monster/minion variants, vision,
terrain, multi-target interactions and summoner casts during channeling remain
excluded. Q's fixed 0.35-second impact, W's cast-then-drain phase and R's first
tick placement are timing interpretations, not measured replay timings. Fear
uses the existing action-inhibition control model. Snapshot bytes and current
pointers remain immutable; parser version remains 7.

The [mechanics reference](https://wiki.leagueoflegends.com/en-us/Fiddlesticks)
supplies interaction context beyond the raw records. Its historical wording
distinguishes tether escape from completion/target death for the refund;
the retained tooltip establishes the 60% amount. These edge cases still need
matching game observations before being called verified. Riot's
[14.4 patch notes](https://www.leagueoflegends.com/en-au/news/game-updates/patch-14-4-notes/)
corroborate the 725-unit tether break range retained in the selected data.

# Reviewed mage attack timing

Ahri's ordinary attacks now use a 20% windup fraction instead of the generic
30% assumption. Annie's ordinary and critical attacks now travel at 1,500
units/second instead of arriving immediately at release. Both changes are
restricted to the retained 16.19.1 snapshot and apply to either participant,
practice comparisons, optimization and the packaged simulation interface.

## Sources and interpretation

[Riot's patch 13.22 notes](https://www.leagueoflegends.com/en-sg/news/game-updates/patch-13-22-notes/)
specify Ahri's 20% attack windup and Annie's projectile speed increase from
1,200 to 1,500. The retained 16.19.1 character records corroborate the relevant
fields: Ahri's base and critical attack slots carry the same cast-offset field,
and all three Annie attack variants have fixed missile movement at 1,500 while
their legacy `missileSpeed` field still says 1,200.

`data/attack-fixtures/16.19.1/reviewed-timing.jdn` records this narrow review and
binds it to the complete character-record hashes. Ahri's 20% is a curated,
named value from Riot's notes, guarded by the exact current record; it is not
a newly established general formula for arbitrary cast-offset fields. Annie's
conflict resolution is likewise explicit and requires the expected movement
and legacy values on every ordinary/critical variant. The generic projectile
parser continues to reject conflicting fields. A changed record or patch cannot
silently reuse either profile.

These are source-derived corrections, not new measured timing observations.
The cached replay-discovery matches are on 16.20, with no Ahri or Annie in
the five inspected match rosters. The retained Ekko observation is an empowered
attack. Neither substitutes for an isolated, matching-patch mage attack. No new
combat comparison is admitted by these changes.

## Modeled behavior

Windup equals the reviewed fraction divided by attack speed sampled at attack
start. Projectile travel uses distance at release divided by the reviewed
movement speed. At one attack/second and 350 distance, Ahri's first impact moves
from 0.5 to 0.4 seconds. At the same speed and 300 distance, Annie's assumed 30%
windup plus projectile travel gives a first impact at 0.5 seconds.

Travel does not postpone the following attack's ready time. Damage arriving
exactly at the fight's endpoint remains excluded. Existing scheduling policy
still samples the attack period/windup at start and consumes Spellblade at
successful impact; changes during an attack and launch-versus-impact ordering
remain separate evidence work. The curated legacy Annie rotation retains its
explicit zero-travel configuration; current practice/duel simulations use the
reviewed projectile profile.

Annie's windup still uses the declared 30% assumption. Champions such as Garen,
Kalista and Senna have separate timing modifiers or overrides; this change does
not apply Ahri's fraction to them. Viktor's ordinary versus empowered projectile
behavior also remains a separate handler. Developer notes preserve these
boundaries, while player Simulation details describe the actual assumptions.

## Regression checks

`test/attack-projectiles.janet` checks source hashes, all three attack variants,
strict versus explicitly reviewed conflict handling, exact patch isolation,
cached semantic repair, removal of stale assumptions, several attack speeds,
critical hits, both participants and half-open impact boundaries.
`test/mage-burst.janet` checks Ahri's first Lich Bane attack against an independent
windup-plus-travel calculation and direct/optimizer equality. The relocated
runtime checks Ahri's first impact and Annie's delayed first attack. In the
default five-second Annie fight, three ordinary attacks arrive inside the
window; the fourth projectile is still in flight at the endpoint.

The source profiles are loaded during module import and embedded in the
standalone executable. Existing snapshot bytes remain untouched. Model identity
includes the new review and both character sources, invalidating older fitness
cache entries and retaining saved-scenario compatibility notices.

Core/source/Python checks, frontend and combat regressions, standalone runtime
and packaged Chromium checks passed. The relocated executable also passed the
runtime suite using the signed v0.18.0 RPM's older seed, without a source
checkout or provider request.

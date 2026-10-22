# Garen E/R — first ability-completeness batch

Missing and partially interpreted champion mechanics are the main development
priority. This first batch replaces the two excluded Garen effects on
**16.20.1 and 16.21.1**. It does not establish a complete or game-verified Garen kit.

## Retained evidence

The existing `data/parser-fixtures/16.20.1/` and `16.21.1/` manifests identify
the complete CommunityDragon character records, Data Dragon descriptions and
localized tooltip excerpts with their original hashes. Tests check those hashes
before exercising the normal explicit refresh path. All numerical ability
values come from the selected spell record rather than a shared hard-coded
damage table.

Judgment's records provide `TotalDamage`, `NumTicks`, `ASPerTick`, `Duration`,
`NearestEnemyBonus`, `CritMod`, `StacksToShred`, `ShredAmount` and
`ShredDuration`. Demacian Justice provides `BaseDamage`, `ExecuteDamage` and
its cast time. The tooltip explicitly describes base plus missing-health damage;
its two displayed numbers must not be treated as independent flat hits.

[Riot's 9.24 notes](https://www.leagueoflegends.com/en-us/news/game-updates/patch-9-24-notes/)
corroborate the one-extra-spin-per-25%-attack-speed rule. The selected records
still specify seven base spins and a 0.25 increment. The
[Garen mechanics reference](https://wiki.leagueoflegends.com/en-us/Garen)
describes item/level attack-speed eligibility, attack exclusion during E,
Q/W availability, spin completion, and armor-reduction refresh behavior. This
secondary mechanics reference supplements the raw records; it is not a replay
measurement of either retained patch. Crit scaling follows the selected raw
`CriticalDamage` calculation, whose multiplier is `1 + CritMod * (critDamage - 1)`.

## Resulting simulation

- E schedules separate physical hits across its three-second duration. Its
  spin count is seven plus the integer number of eligible 25% attack-speed
  increments. Level growth and item stats contribute; rune shards and temporary
  attack-speed buffs do not. The ordinary attack-speed cap does not cap spin count.
- The ability tooltip uses the same spin-count expression as combat, including
  the configured level and item attack-speed contribution.
- Each spin checks the current distance against the source-defined radius.
  A dead caster stops dealing spin damage. Individual spins can crit or be
  parried and feed the existing supported spell-hit/damage triggers.
- Basic attacks wait until E ends. Q/W remain available subject to ordinary
  controls and cast locks. The automatic strategy completes E before considering
  E/R again; it does not immediately cancel E to follow the next priority entry.
  A configured missed cast still occupies the spin window, while dealing no
  spin damage; it cannot accidentally grant extra ordinary attacks.
- The sole opponent receives the source's nearest-enemy bonus. Six landed hits
  apply champion armor reduction after the sixth hit's damage. The seventh and
  each subsequent group of six refresh it. The reduction does not stack with
  itself. Missed, out-of-range and parried spins do not build those hits.
- R deals true damage from base plus the selected fraction of the opponent's
  missing health **at impact**. Prior damage, healing and health changes therefore
  affect it; shields absorb damage through the existing defense path.
- The timeline shows the active Judgment duration and applied armor reduction
  using the existing status bands and separate damage events.

## Independent numerical checks

Both retained patches give these examples, before outgoing modifiers:

| Situation | Expected result |
| --- | --- |
| Rank-1 E, 150 AD, no eligible bonus AS | Seven spins, each `(4 + .4 * 150) * 1.25 = 80` raw damage |
| Rank-5 E, 150 AD | Each spin `(16 + .52 * 150) * 1.25 = 117.5` raw damage |
| Rank-1 E, 100% crit chance, total crit damage 2 | Each spin `80 * 1.3 = 104` raw damage |
| Rank-1 E, 100 armor opponent | First six hits 40 each; seventh `80 / 1.75` after 25% shred |
| Eligible bonus AS 24.999%, 25%, 50%, 99% | Seven, eight, nine, ten spins respectively |
| Rank-1 R, 2,000 max health and 1,500 current health | `125 + .25 * 500 = 250` true damage |
| Same R after 200 further damage and 100 healing before impact | `125 + .25 * 600 = 275` true damage |

`test/garen-abilities.janet` checks these equations, exact simulated boundaries,
all R ranks, E rank endpoints, shields, parry, death, range changes, action
availability, both matchup positions, optimizer equality and immutable snapshot
bytes. The latest-patch browser check requires E/R damage, artwork and the
Judgment status interval through the packaged server.

## Limits and data behavior

Even spacing and the first hit at the end of one spin are explicit simulation
timing assumptions. They are not measured server ticks. Early cancellation,
R interrupting E, multi-target selection, attack-range changes during E,
cross-cast stack edge cases and exact same-tick live-game ordering remain
unverified. These handlers target champions and champion-like practice dummies;
objective damage remains excluded. R's vision effect is excluded. Garen's passive, Q's remaining
interactions and W's damage-reduction/passive mechanics still need review.
Executing these two abilities does not resolve those omissions.

The handlers use the existing semantic-model loading path. Parser version stays
7. Existing immutable snapshot bytes and current pointers are untouched; no
automatic refresh, reparse or repair is introduced. Later unreviewed patches do
not inherit these handlers. The engine identity changes, invalidating prior
scoring cache entries and retaining the existing model-change notice for saves.

The complete 16.21.1 probe now records **460** entries with at least one applied
effect, **184** without an executable effect, **22** unable to cast and **26**
casting without an applied effect. Only Garen E/R changed category. Those are
triage counts, not an accuracy score or complete-ability count.

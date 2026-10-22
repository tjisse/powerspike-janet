# Seraphine Q/W/E and Echo — 23 October 2026

The second ability-completeness batch addresses interacting partial effects on
**16.21.1**, using the already retained, hashed character records, descriptions
and tooltip excerpts in `data/ability-fixtures/16.21.1/`. Other patches retain
their existing scope until matching sources are reviewed.

## Included behavior

- Q uses `ExplosionDamage`, `DamageAmp` and `ExecuteThreshold`: bonus damage
  increases linearly with missing health and stops increasing at the threshold.
  It samples the opponent's health when the hit applies, including changes
  between an ordinary and echoed hit.
- W checks for an existing unexpired, nonempty shield at cast start. Its own
  shield does not qualify the initial cast for healing. A qualifying cast
  schedules one heal after `WHealSplitDelay`, using the then-current missing
  health and `WMissingHPHeal` percentage. A subsequent qualifying W refreshes
  that pulse instead of creating a second heal. Dead Seraphine cannot receive it.
- E supplies the source's 99% slow and ranked duration. At impact, an existing
  slow upgrades the effect to root; existing immobilization or grounding
  upgrades it to stun. The existing immunity, tenacity, cleanse and resumption
  paths still apply.
- The passive's every-third-basic-cast Echo repeats Q/W/E once after the
  retained `EchoCastDelay`. R and summoner spells do not advance this counter.
  An Echo does not spend resource, start another cooldown, recurse or generate
  a second cast trigger. It shares the original cast origin for existing
  per-cast item/rune proc counting.
- Echo W can qualify from the first W's shield. Echo E can upgrade its first
  hit's slow to root, or root to stun. Repeated Q samples the updated health.

The source values are executable expression trees, not additional parsers.
Existing snapshot bytes and current pointers remain unchanged. The model
fingerprint includes these semantics; there is no automatic refresh or repair.

## Numerical and interaction regressions

At rank 1 with 100 AP, Q's base hit is `60 + .4 * 100 = 100`. Against 2,000
maximum health, starting current health of 2,000, 1,250, 500 or 200 gives raw
damage of 100, 137.5, 175 or 175 respectively. The maximum displayed damage is
not a separate additional hit.

Rank-1 W provides `60 + .2 * 100 = 80` shield. At 500/1,000 self health, a
qualifying pulse heals `.08 * 500 = 40`; another 100 health lost before the
pulse raises that to 48. Consumed and expired shields cannot qualify the cast.
Two qualifying echoed casts still produce one delayed pulse.

Rank-1 E disables for 1.1 seconds before tenacity; 50% tenacity gives 0.55
seconds. The tests check ordinary slow, preexisting slow/root/stun/grounding,
and Echo's slow-to-root and root-to-stun sequences.

`test/seraphine-abilities.janet` checks these equations and interactions,
both matchup positions, scenario/optimizer equality, death, unlearned skills
and trace-free execution. The shared `test/ability_runtime.py` exercises
exported scenarios in a relocated executable without repository files.
`test/ability_browser.py` checks the same saved configurations through the
packaged server, including every visible timeline event down to 320 px.

## Remaining limitations

This is still a partial Seraphine kit. Echo starts with zero stacks; carrying
pre-fight stacks is not configurable. Notes and their bonus attacks/range,
W's decaying movement speed, other allies, collision geometry and R's range
extensions remain excluded. Cast and missile timings retain the current model's
source interpretation rather than newly measured game timings. These omissions
are retained in the result's simulation details.

The [mechanics reference](https://wiki.leagueoflegends.com/en-us/Seraphine)
corroborates shield qualification, delayed healing and control upgrades. Matching
retained game data supplies the numerical values. This is source-backed model
coverage, not a replay-validation claim.

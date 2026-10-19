# Fiora Riposte defense and parried Spellblade attacks

Fiora W now provides a source-bounded defensive window on the retained 16.19.1
snapshot. Incoming champion damage and represented hostile control/debuff
effects are blocked for the source's 0.75 seconds, beginning at cast start.
Fiora's movement, attacks and casts remain locked during that window.
An attack whose impact is parried consumes a primed Spellblade and starts its
cooldown, while its damage is blocked. Ordinary successful-hit procs do not run.

This is partial Riposte support. The return stab, its slows and stun conversion,
defense against objectives and summoner casts during the window remain excluded
or unreviewed. Shields are explicitly assumed to remain intact during Riposte;
shield ordering and exceptional debuff interactions need further review. These
limits appear in the ability's Simulation details. Source hashes, packet
analysis and regression records remain developer information.

## Sources and interpretation

`data/parry-fixtures/16.19.1/manifest.json` records complete source URLs and hashes
for Fiora's character records and Riot's matching champion description, plus a
small excerpt of the matching tooltip strings. The tooltip names the defense
and uses `ParryDuration`; the character record supplies 0.75 at every rank.
The source's 10ms cast directive is kept separate from the defensive duration.
The handler begins defense on cast start and locks actions for the named window,
rather than applying defense after the cast directive or allowing attacks while
Riposte is active. Cooldown and resource cost still come from the loaded kit.

The complete `FioraW` spell object is identical between this retained 16.19 source
and the 16.20 source from the [replay investigation](replay-attack-timing.md).
That narrowly supports the source interpretation across those records; it is
not a claim of complete cross-patch compatibility. The actual semantic rule
applies only to 16.19.1.

The replay's short Lich Bane removal at 1380.489 seconds follows an attack aimed
at Fiora, within her observed W buff interval of 1380.138–1380.890. The absence
of an ordinary damage packet there motivated a separate parried-attack event.
Its interpretation remains a diagnostic candidate: no exact server release
measurement, new damage comparison or verification-ledger admission results.
The earlier replay dossier and frozen extraction adapters remain unchanged.

Lich Bane is the directly observed item. Sheen, Trinity Force, Essence Reaver
and Iceborn Gauntlet follow the shared Spellblade consumption policy. Their
parried consumption is a modeling rule, not five independent replay findings.

## Engine behavior

A semantic effect can now run at `:cast-start`. A separately evaluated cast lock
prevents the caster's actions and movement until the source duration ends.
Invalid locks are rejected before spending resources or cooldowns. Parry requires
explicit supported incoming source kinds; this handler admits champion sources
and leaves objective retaliation outside its scope. It does not cleanse effects
that were already present, and self-heals or self-shields still apply.

Defense is checked at impact. Projectiles already in flight can be parried;
projectiles arriving after expiry deal damage normally. The interval is
half-open, so an impact exactly at 0.75 seconds is outside a parry begun at zero.
Existing event priority and decision polling still determine simultaneous-event
and activation timing. No replay timestamp is fitted into a windup parameter.

A distinct `:parried-attack` trigger reaches only the Spellblade subscribers.
They consume the priming buff, remove Lich Bane's attack-speed bonus, set the
source cooldown once and schedule their blocked proc damage. They do not advance
ordinary attack counters, damage procs or defender damage-taken procs. Misses,
interrupted windups and a target dying before projectile impact keep their
existing behavior. Bonus attack components share their attack origin and cannot
consume the item twice.

Standalone verification exposed an existing JSON export failure when temporary
stat effects used tuple dictionary keys. These internal keys now use stable,
namespaced string encodings. This preserves distinct buff/stat identities while
allowing Lich Bane and ordinary temporary effects to serialize through the CLI.
It does not alter effect amounts or lifetimes.

## Regression and compatibility checks

`test/parry.janet` checks the retained source hashes, exact patch bounds,
idempotent semantic repair, cast-start defense before the 10ms cast directive,
physical/magic/true damage, control and debuffs, endpoint exclusion, action and
movement locking, existing effects and self-healing, shield-ordering assumptions,
projectiles crossing activation/expiry, misses, interruptions, dead targets,
Spellblade cooldowns, bonus attack components, ordinary proc isolation and both
participant roles. An old parser-4 package built from real Ahri Q, Lich Bane and
Fiora W sources produces equal direct/optimizer metrics without changing its
snapshot bytes.

`make test-runtime` exports that old package and scenario, copies them beside a
relocated executable in an empty directory, and checks that Riposte blocks the
attack and consumes Lich Bane once. This exercises the embedded handler and JSON
output without access to checkout files or a provider request. Existing snapshot
identities remain immutable; the engine/normalizer/effect/rule changes contribute
to model identity, invalidating older fitness caches and retaining saved-scenario
compatibility notices.

Core/source checks, all 170 Python tests (162 passed, eight optional skips),
frontend and combat regressions, the new relocated parry/JSON scenario and
packaged Chromium desktop/mobile flows passed. The relocated suite also passed
using the published v0.18.0 RPM's older seed and the parry fixture.

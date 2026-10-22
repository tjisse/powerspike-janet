# Champion ability-slot coverage audit — 22 October 2026

The reported Seraphine/Garen fight exposed two separate issues: incomplete
champion mechanics and timeline markers that silently disappeared when events
were close together. This audit covers every Q/W/E/R entry for all **173
champions** in the matching **16.21.1** Data Dragon catalog.

## Reported fight

The supplied saved scenario uses level-18 Seraphine against level-18 Garen,
full starting resources, enabled abilities and the standard Q/W/E/R priority.
Its served trace contains:

| Event | Time | Applied result |
| --- | ---: | --- |
| Seraphine W | 0.01 s | Approximately 173.8 shield |
| Seraphine E | 0.02 s | Approximately 173.35 magic damage after resistance |

Those are simulation timestamps; cast locks and projectile behavior still use
the current model assumptions. They are not newly measured game timings.

Those events were simulated. The old timeline skipped nearby icons to avoid
overlap, leaving their presence visible only through the complete selector.
The timeline now assigns every displayed event to a visible marker group.
Crowded groups show a `+N` badge and list all event names, exact times and
outcomes on hover, focus or tap. Selecting an individual event still shows its
own icon and sets the time guide to its exact time. Group positions and lane
heights remain stable during selection. Status duration bands keep their
independent exact time geometry.

`test/fixtures/seraphine-garen-timeline.json` retains the served result payload,
with relative artwork paths and no hosting origin. It is a presentation
regression input from this app, not independent game evidence. Its model
identity is the v0.24.0 model recorded in the saved scenario. The browser check
requires every event to remain represented, W/E names and outcomes to be
discoverable, individual selection to work and result geometry to stay fixed
at desktop and narrow widths, including keyboard and touch.

Before the first completeness batch, Garen E had no executable effect. Its source contains per-strike
damage and a three-second duration, but the displayed strike count uses the
unresolved `f1` value. Attack-speed-dependent strikes, channel timing, the
nearest-enemy bonus, armor shred after six strikes, critical interactions and
early recast need explicit semantics. The
[Garen E/R follow-up](garen-abilities.md) now implements separate spins,
item/level attack-speed scaling, crits, armor reduction and impact-time execute
damage on 16.20/16.21. Early cancellation and measured spin timing remain
limitations. The current report below includes this follow-up.

Seraphine's ordinary W shield and E damage already executed in the source regression.
The [Seraphine follow-up](seraphine-abilities.md) now adds W's conditional heal,
E's slow/root/stun behavior, Q's missing-health scaling and passive Echo on
16.21.1. Notes, W movement and other kit limitations remain explicit. Executing
one part of an ability does not imply its entire behavior is supported.

## Complete inventory

The [per-ability report](audits/ability-coverage-16.21.1.json) records **692**
entries and the [source receipts](audits/ability-sources-16.21.1.json) identify
the matching catalog, character records and ability descriptions with their
original response hashes. Full downloaded responses remain in the local
developer audit cache; reported-case raw sources are also retained in
`data/ability-fixtures/16.21.1/` and `data/parser-fixtures/16.21.1/`.

| Controlled probe result | Abilities |
| --- | ---: |
| At least one effect recorded | 467 |
| No executable effect | 180 |
| Has an estimated effect but does not cast | 21 |
| Casts without recording an applied effect | 24 |

These counts are **coverage triage, not an accuracy score**. The probe isolates
one learned spell at level 18, with 100 AP, 150 AD, ample resource, half starting
health, zero distance, enabled ordinary attacks and an inactive champion target
for eight seconds. It uses generic combat inputs to expose execution paths.
It does not exercise complete champion strategies, every conditional state,
alternate forms, unmodeled passive triggers, projectile geometry or live-game timing.
Explicitly modeled passive Q/W/E/R slots, starting with
[Vayne W](vayne-silver-bolts.md), now run from ordinary hits in the probe. They
can execute without casting. Other champion P passives remain outside the probe.
A recorded effect can coexist with substantial missing mechanics. A delayed
effect beyond the probe window can appear in the no-effect group.

The full audit uses a developer snapshot containing the freshly normalized
ability catalog, with no item or rune selections. Its recorded snapshot hash
is distinct from the supplied user's saved snapshot. Matching raw sources
were checked before normalization. Existing saved application data was not
rewritten or migrated.

## Source lookup correction

The audit found one root-record casing mismatch in the complete 173-champion
source set: Data Dragon identifies `Fiddlesticks`, while CommunityDragon's
canonical root is `Characters/FiddleSticks/CharacterRecords/Root`. The old
lookup missed that root and all four current spell references.

Normalization now prefers an exact root key, then accepts a unique match that
differs only by ASCII case. Ambiguous matches are rejected. Public champion IDs
stay unchanged, while the normalized root path preserves the provider's actual
key for later source lookups. Fresh refresh/reparse uses the corrected root;
saved snapshot bytes are not silently rebuilt.

This restores Reap's base magic damage from the actual `Damage` calculation.
With 100 AP, its source gives 120 damage at rank 1 and 260 at rank 5, before
resistance. The
[Fiddlesticks follow-up](fiddlesticks-abilities.md) now implements Q's
health-percentage and recent-fear behavior, W's drain and R's channel/blink/area
damage and E's slow on 16.21.1. Center-hit silence remains excluded.
Earlier patch guards still prevent recovered records from
turning those numbers into flat single hits. Unseen fear and other interactions
remain excluded; this is not a complete Fiddlesticks kit.

Before that correction, the probe recorded 457 entries with an applied effect,
185 with no executable effect, 22 unable to cast and 28 casting without an
applied effect. The table above and linked per-ability report reflect the
correction followed by the Garen E/R and Fiddlesticks Q/W/R handlers. After the
casing correction alone, the counts were 458/186/22/26. Seraphine's follow-up
completes more effects within already-executing entries, leaving counts unchanged.
The [defense follow-up](defense-abilities.md) moves Riven E and Jarvan W from
cast-without-effect to execution, and Malphite E from no executable effect to
execution. Other categories remain unchanged.
Vayne W subsequently moves from not-cast to execution with zero casts and
observed passive damage. Counts measure actual applied effects, not cast spam.
Restoring a record is not enough to claim supported mechanics.

## Main causes and next work

1. **Missing combat semantics:** periodic/channel damage, conditional executes,
   multi-part damage, stacks, marks, recasts and form changes. The first Garen
   E/R and Seraphine follow-ups are covered by numerical regressions;
   Fiddlesticks Q/W/R now have source-backed handlers. Remaining champion
   mechanics and unreviewed edges stay in the inventory.
2. **Formula/source resolution:** cross-spell references, unresolved tooltip
   variables and unreviewed stat mappings. They need matching source review;
   simply enabling the ability would hide missing damage.
3. **Activation rules:** zero-cooldown stack abilities, toggles and continuous
   resource costs intentionally fail generic activation checks. Several
   source wrapper records also need their actual spell behavior reviewed.
4. **Effects parsed but not applied:** several shields lack a resolved
   duration, and slow tags lack strength. Some entries are ally-only or
   conditional effects treated too loosely by generic extraction. These
   should be reviewed before expanding the champion catalog further.

The report includes compilation notes, unresolved inputs, cast/effect counts,
runtime exclusions and errors for each ability. This stays in developer tooling;
it adds no player-facing engineering dashboard or automatic repair process.

## Repeating the check

Run from a development checkout with its pinned Janet modules available:

```sh
JANET_PATH=build/web-modules build/janet scripts/audit-abilities.janet \
  /path/to/developer-data 16.21.1 - build/ability-report.json
```

Replace `-` with a saved snapshot hash to inspect that exact revision. Without
the report path, JSON is written to stdout. The command reads the existing
snapshot and applies the same current semantic model used by the app. It does
not download providers, refresh or reparse saved data. Use the ordinary explicit
refresh/reparse workflow when a new normalized snapshot is wanted.

`test/ability-audit.janet` checks the reported source cases, classifications,
zero-cooldown exclusion, a cast with no applied effect, parry activation,
missing definitions, complete inventory counts and unchanged input data.

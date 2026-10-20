# Character-level interpolation

The general expression parser now honors
`mScaleByStatProgressionMultiplier` and its FNV-1a field alias `{7fe8e3b3}`.
Previously, the named flag was ignored and a true hashed flag was unresolved.
This could display a plausible but incorrect linear value between the endpoints.

For character level `L` from 1 through 18, let `n = L - 1`:

| Source flag | Interpolated value |
| --- | --- |
| Absent or false | `start + (end - start) × n / 17` |
| True | `start + (end - start) × n × (0.7025 + 0.0175 × n) / 17` |

The nonlinear branch shares `stats/growth-factor` with champion stats. Both
branches validate integer levels in the supported range. Non-finite endpoints,
non-boolean flags and conflicting named/hashed aliases remain unresolved.
Omitted endpoint fields retain the game-data default of zero. As elsewhere in
the provider reader, JSON null becomes Janet nil and is equivalent to omission.

For example, Gnar's `TotalMegaGnarAD` endpoints are 6 and 48.5. At level 10,
linear interpolation gave 28.5; the source-requested stat progression gives
25.35. These are the passive **addition**, rather than total champion AD.
At levels 1 and 18 both curves agree. Nonlinear tooltip explanations identify
the selected level and the stat-like scaling; combat uses the same evaluator.

## Retained source audit

The audit recursively inspected all 257 tracked `data/**/*.json` files at the
v0.19.0 baseline. It found 30 `ByCharLevelInterpolationCalculationPart` nodes:
26 with no true flag and four with the named flag true. All four are in
`Characters/Gnar/Spells/GnarPassiveAbility/GnarPassive`, under
`mSpell/mSpellCalculations/<name>/mFormulaParts/0`:

| Calculation | Level-1 endpoint | Level-18 endpoint |
| --- | --- | --- |
| `TotalAS` | approximately 0.055 | approximately 0.99 |
| `TotalMegaGnarArmor` | 3.5 | 54.5 |
| `TotalMegaGnarMR` | 3.5 | 63 |
| `TotalMegaGnarAD` | 6 | 48.5 |

The complete [16.19 game record](https://raw.communitydragon.org/16.19/game/data/characters/gnar/gnar.bin.json?powerspike=1)
is retained as [Gnar-characters.json](../data/form-fixtures/16.19.1/Gnar-characters.json),
SHA-256 `2891edf3dbd17519ad0e1203de71890ce77777482c2191ffeeaadf85df4ec9aa`.
The [manifest](../data/form-fixtures/16.19.1/gnar-manifest.json) binds it and the
localization excerpt to their hashes. Tests preserve the original float values.
The hashed-alias cases are explicit transformations of the retained named node;
the tracked corpus contains no true hashed example. CommunityDragon documents
the [lowercase FNV-1a field hashes](https://github.com/CommunityDragon/Data#bin-hashes).

This audit covers retained source files, rather than every live champion formula.
[Gnar's form review](gnar-forms.md) separately establishes which passive additions
belong in base stats. Its fixed Mini/Mega profiles already used the correct
growth curve and are unchanged. Mini's attack-speed tooltip must not be added
again on top of its existing growth stat. Resolving a formula does not establish
an executable passive trigger, transformation or complete champion kit.

## Cached packages and verification

Parser version 6 marks newly compiled tooltip records. On load, older records
with interpolation flags are repaired in memory from their retained source
calculations. A bounded compiler compatibility path reproduces the previous
interpolation AST only to identify what needs replacing; it is never used for
combat or display. Complete old expressions are matched to their current
compilation, including expressions inside costs, durations and nested products.
Ability, item, rune and summoner adapters use the same repair. Snapshot bytes,
hashes and source records stay unchanged; model identity invalidates old fitness
results through the existing source-code fingerprint.

If identical legacy ASTs correspond to different current formulas, the repair
leaves an unresolved expression and requests a patch-data refresh instead of
guessing missing provenance. A fresh parse has the original source identity.
Records without retained source cannot reconstruct a discarded flag. Existing
unresolved effect statuses and triggers remain unresolved after numerical repair.

[The regression suite](../test/level-scaling.janet) independently sums each
level-up increment, `0.65 + 0.035 × level`, and checks all four retained formulas
at every supported level. It checks ordinary linear behavior, aliases,
malformed inputs, endpoints, the real localized passive tooltip, cached adapters,
nested expressions, ambiguous legacy provenance and unchanged snapshot bytes.
A clearly synthetic damage carrier checks both participant roles and their
production scenario/optimizer paths against the same reference; it supplies no
new evidence about Gnar casts. `make test-runtime` exports its old snapshot and
checks the independently calculated level-10 result with a relocated executable,
outside the checkout and without source-file access.
The existing form suite guards against changes or double application to form stats.

Formatting, core/source/catalog checks, all 170 Python tests (162 passed and
eight optional skips), web/combat regressions, the relocated runtime with both
legacy scaling and Riposte fixtures, and the full desktop/mobile browser suite
passed.

These checks establish agreement between retained source and software, rather
than new in-game measurements or timing validation.

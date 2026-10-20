# Damage variation in item comparisons

Pinned comparisons now show **Damage across trials** beside the damage,
survival and gold results. For multiple trials, the panel reports the mean
damage change, the lowest and highest observed change, and counts of trials
where the current build dealt more damage, the pinned build dealt more, or the
two tied. A sign change is called out without declaring an overall better build.

Each change is `current_damage[i] - pinned_damage[i]`, using the same trial
index, seed and configured fight inputs. This preserves the pairing of shared
random inputs. Subtracting the two builds' individual sampling intervals does
not provide these observed paired changes. The new panel is descriptive: its
range covers the trials that ran, without estimating a confidence interval,
future worst case, live-game probability or matchup win rate.

One trial offers guidance to increase the trial count. Missing, mismatched or
invalid retained trial data is unavailable, rather than zero variation. Repeated
equal results are described as equal in the sampled trials. **Adjust trials**
opens the fight settings and focuses the trial input in practice and duel
layouts. Duel edits leave the previous result visible and marked stale until
**Run matchup** is selected. Labels continue to describe the trial count of the
displayed result during that interval.

## Collection and reproduction

`engine/trials` accepts an optional `retain-damage` argument after the existing
cancellation callback. Opting in retains one damage scalar per trial, in index
order, during the existing simulations. Default and optimizer calls retain
aggregates only; enabling retention does not rerun combat or change metrics,
events, traces, source breakdowns or cancellation behavior. The UI requests
these values only when a valid pinned comparison exists. Its trial limit stays
at 64; the engine's existing 256-trial limit also bounds explicit collectors.

The panel is recomputed when loading or sharing a comparison. Trial arrays and
calculated summaries are absent from saved documents. Patch snapshots and save
formats are unchanged. Combat formulas and random draws are unchanged, but the
engine source changed to collect the optional values, so its content-derived
model identity changes. Older saved models retain the existing compatibility
warning and recompute using the current release.

## Retained example

Use the [four-trial Annie component comparison](damage-source-comparisons.md)
with seed 6, 50% hit chance and a three-second practice window. Long Sword is
current and Amplifying Tome is pinned. The individual damage values are:

| Trial index | Pinned | Current | Current − pinned |
| --- | ---: | ---: | ---: |
| 0 | 55.555556 | 66.666667 | +11.111111 |
| 1 | 55.555556 | 66.666667 | +11.111111 |
| 2 | 53.333333 | 44.444444 | −8.888889 |
| 3 | 27.777778 | 33.333333 | +5.555556 |

The mean change is +4.722222, the observed range is −8.888889 to +11.111111,
and the current build leads on damage in three trials versus one for the pin.
The means, source breakdowns and individual results match the prior model's
calculations; the panel exposes variation that the average alone concealed.
This is a software regression on retained inputs, not additional game evidence.

## Validation

Passed `make test`: 83 core cases, retained source/catalog verification and
170 Python cases (8 skipped). `make test-web` passed with 44 frontend cases and
the existing combat/optimizer suites. `make test-runtime` regenerated the
fixtures with the current model identity and passed the copied-executable gate.

The retention checks compare each stored scalar with an independently run
trial and confirm unchanged traces, events, aggregate metrics, source breakdowns
and cancellation behavior. Default and trace-free fitness calls omit the
collector. Summary checks include mixed directions, ties, reversal, missing or
invalid arrays and a correlated example where both builds vary widely but
every paired change is exactly +1.

Browser checks cover exact range/count/mean text, one-trial guidance, focusing
the control in both layouts, explicit duel reruns from four to eight trials and
back, and saved/shared/imported reproduction. Desktop and 736/390/320-pixel
views pass without viewport overflow; screenshots were visually reviewed.
The full browser gate passed, including optimization, error recovery, the paired
interface and retained combat fixtures. Formatting and diff checks pass.

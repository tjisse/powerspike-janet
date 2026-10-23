# Distance over the fight

The matchup graph offers **Health remaining**, **Damage dealt** and **Distance**
in the same fixed-size panel. Distance is the absolute separation between the
two current one-dimensional champion positions, in game units. It uses one gold
line and the existing combat timeline/time cursor. Health and damage retain
their step plots; ordinary movement uses straight segments, stationary periods
are flat, and instantaneous displacements have vertical edges.

The HP overview always includes distance at the selected time, rounded to at
most two decimal places. Both champion HP readings remain visible in Distance
view. On narrow screens the distance reading sits below the two HP cells;
changing the graph metric does not change the panel or overview dimensions.
Hover, click/tap, keyboard inspection and event selection share the same time.
The graph stops at the displayed fight end, including an early knockout.

## Position samples

`position-timeline.janet` observes position before/after engine advancement and
after each processed event. Consecutive linear segments are compacted, with a
small floating-point tolerance; repeated timestamps retain discontinuities.
If integration clamps approaching points to their meeting position, its exact
contact time is retained before the stationary segment. Pauses caused by an
attack windup, cast lock, root or speed change therefore remain visible even
when the combat trace contains no damage event at that boundary.

The UI interpolates these position samples before calculating separation. At a
displacement timestamp it selects the final sample at that time. Old result
payloads without position data show an unavailable reading and disable the
Distance button; they do not invent zero distance or interpolate sparse hits.

The samples belong to representative trial zero, matching the existing health,
damage and event display. Trace-free optimizer evaluations retain no position
samples. This adds presentation data without changing movement decisions,
range checks, damage, scheduling or scoring. The engine fingerprint changes,
while patch snapshot bytes and parser version remain unchanged. The developer
ability audit is regenerated against that fingerprint with unchanged coverage.

These remain point positions in the current one-dimensional model. This change
does not add collision radii, terrain, two-dimensional paths or new kiting rules.

## Checks

`test/position-timeline.janet` checks independent chase/retreat arithmetic, both
participants moving, roots/slows and their expiry, speed buffs, attack windup
pauses, instant displacement, mid-step contact, mirroring, compact stationary
and linear output, and traced/scoring parity. Its synthetic production-engine
outputs feed `test/distance_browser.py`, wired into the full browser suite.
Browser checks cover cursor/overview agreement, metric-switch geometry, event
selection, a knockout cutoff, zero and missing data, jump rendering, touch and
320/390/736/1200 px layouts. Existing movement and combat regressions protect
the underlying behavior.

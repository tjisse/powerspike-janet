# Deferred: comparing alternative item builds

The standalone **Compare items** section is removed from the player workspace.
Its pin/replace/clear workflow asked players to manage a second build without
making the decision they were comparing clear. Revisit the feature around a
concrete question, such as whether to buy a component now, replace a completed
item, or accept less damage for greater survival.

Before rebuilding the interface:

- Walk through those decisions with players and choose one primary entry point,
  potentially an optimizer recommendation or a saved champion configuration.
- Make the current and alternative inventories immediately recognizable. Let
  the player accept the alternative or return to the current build directly.
- Explain shared fight settings and unequal gold costs near the comparison.
  Keep damage, health remaining and survival relevant to the chosen decision.
- Start with a compact outcome; reveal damage sources and trial variation when
  the player asks why the results differ.
- Check that the whole flow works on touch screens without an extra permanent
  panel, layout growth or a separate pin-management task.

Existing scenario/comparison imports, saved data and calculation helpers remain
compatible. The removed presentation and its existing model tests are retained
as implementation references, rather than an exposed player feature. Optimizer
recommendations still compare against the currently configured build.

Build the new entry point only after the walkthrough establishes how players
choose, inspect and apply an alternative. Then add browser coverage for that
complete decision flow.

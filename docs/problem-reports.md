# Comparing builds and reporting a problem

## Player walkthrough

1. Choose both champions, levels and items. Set the fight duration and distance,
   then run the matchup. The result is a simulation under those conditions;
   open **Simulated fight · details** to see its included effects and omissions.
2. Choose **Pin current items**, change an item and run again. Both inventories
   use the same fight settings and trial seeds. Compare damage, surviving the
   fight, gold and damage sources before choosing a build.
3. If a result seems wrong, choose **Report a problem** in the footer. Describe
   what happened, what you expected, and optionally the steps you followed.
   Choose **Download report**, review the JSON file and send it to the developer
   through your existing contact channel. Nothing is submitted automatically.

The report includes the completed simulation and pinned items. Run changed
configurations first. Failed or incomplete simulations cannot supply a completed
result; fix and rerun them before downloading a result report. Draft descriptions
survive closing the dialog during the current page session. Reloading clears them.

## Developer reproduction

Open **Saved scenarios → Import a scenario**, select the downloaded report and
choose **Load scenario**. A report can be imported from either layout. Importing
reruns its scenario and restores pinned items; it does not display report prose
as HTML or use recorded outcomes as simulation inputs. Compare the new results
with the file's `observed.selected` and `observed.reference` fields. Each contains
the scenario identity, trial count, aggregate metrics and mean damage by source.
Read `actual`, `expected` and `steps` in the report to understand the player claim.

The version-one `powerspike-problem-report` envelope carries:

- `created-at`: browser UTC time when the download was generated.
- `release`: declared executable version, which may also describe an unreleased
  checkout. The nested scenario's exact combat model remains authoritative for
  model compatibility.
- `workspace`: the existing scenario or comparison document, including patch,
  snapshot, model, seed, trial count and fight settings.
- `observed`: outcomes supplied by Janet when the reported fight completed.
- `actual`, `expected`, `steps`: player-entered text, limited to 2,000 characters
  per field in the UI. Actual and expected behavior are required.

Keep the exact retained snapshot and use the original release when the saved
combat model differs. Imports preserve the original model identity and show the
existing compatibility warning; they never replace a missing snapshot with the
current patch. The imported workspace still obeys the 64-trial limit. The whole
report must fit within 64 KB. Nested reports, unsupported versions, unknown report
fields, malformed text and invalid workspace documents are rejected.

Reports contain only the explicit notes, declared release, selected workspace
and compact completed outcomes. They omit the page URL, browser identity,
unrelated local saves and champion slots. They are downloaded locally without
a report endpoint or automatic upload. Review note text before sharing it.

Treat reports as diagnostic claims, including their editable recorded outcomes.
Reproduce a mismatch against the retained data and review its context before
changing mechanics. A matching rerun is reproducibility evidence; it is not an
independent in-game measurement.

## Checks

`make test-web` checks round trips for both builds, plain reports, model inputs
remaining independent of edited diagnostics, invalid snapshots and rejected
report structures. `test/report_browser.py`, included in the normal browser
suite, checks required fields, local-only downloads, exclusion of unrelated
browser data and the URL, unchanged text containing markup, exact comparison
reproduction through layout-changing imports, edited-result guards, draft
retention, keyboard focus, desktop widths through 320 px and touch controls.
The browser suite also checks that failed evaluations cannot export a report.

Remaining work includes collecting actual beta reports, failed-run diagnostics
and any delivery integration chosen later. There is no issue tracker submission
or automatic calibration admission in this flow.

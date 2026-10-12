---
name: slp-two-axis-review
description: "Lead procedure for the godkit closing review: two sealed lens seats, one on the Standards axis (this repo's documented standards + the smell baseline), one on the Spec axis (does the diff do what the spec and its tickets asked). Never merge or rerank the two findings; one fix round; stop when it does not converge. From the integration branch, after slp-refinery empties."
---
# Two-axis review (Lead)

The two axes answer different questions and must not contaminate each other: code that follows
every standard but implements the wrong thing passes one axis and fails the other, and that is
exactly the information the pair exists to produce. Merging, reranking, or averaging the two
reports destroys it. A lens reviews; you decide.

## When

- The integration branch is stable: `slp-refinery` queue empty, integrated check green,
  every ticket closed (merged green) or explicitly dropped.
- Not on an ordinary slice: the candidate review already ran there (`slp-accept-candidate`,
  cross-family reviewer). This is the workstream-wide gate.

## Size and briefs

Two lens seats (`slp-lens` gives the procedure `size → brief → sealed → collect`; stop before
its `settle` step: settling merges the lenses' conclusions, and here the two reports stay
separate).
Same neutral brief, different `ANGLE` and `OUTPUT CONTRACT` (both shapes in
`references/two-axis-formats.md`):

- `[Lens] standards axis` — on one family; OUTPUT CONTRACT: standards findings.
- `[Lens] spec axis` — on the **other** family (`lens.pair`); OUTPUT CONTRACT: spec findings.

The brief carries: the fixed point (the integration base commit from `slp-refinery`), the
worktree path, the spec's path, the tickets' directory, the check command and its last green
output, and `AUTHORIZED SCOPE` read-only. It carries none of your reasoning and no peer's
report. Before launch: confirm the fixed point resolves and the diff is not empty; if it is,
you do not need two lenses — report and stop.

## Collect, then report without merging

1. Verify each report's diff was against the fixed point (three-dot). A report on an empty or
   wrong diff → one retry with the corrected brief; it says nothing about the code.
2. Report their findings under **two separate headings, verbatim, one heading per axis**. Never
   rank a finding across axes, never pick a single winner: that is the reranking the
   separation exists to prevent.
3. Fix once: send every accepted finding to ONE writable Peer in one pass (grouped by the
   files they touch), then `slp-refinery` merges the fix branch as any candidate.
4. Re-run **only the axis that had findings**, on the new integration head. A second round
   happens only if that axis returns findings again — then stop: a review-and-fix loop that
   does not converge goes to the Owner, with both axes' state in the report.

## Report

`DONE` line per `slp-ticket-frontier` + the two headings + the fix dispatch + the final green
check + what you dropped or superseded and why. Open findings (noted, not fixed: why) belong
in the report, not in a footnote you hope is skipped.
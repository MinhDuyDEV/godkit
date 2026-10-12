"use strict";
// GODKIT eval cases — merge into seatwork's evals/cases.cjs (append the three
// objects inside its exported array, before the closing `];`), or copy the
// file beside it and have run.cjs point at it. Graders use only shapes run.cjs
// already understands: signal · first_line · last_line · text · not_text ·
// tool(+input, min/max) · no_tool · any_of.
//
// The three cases each pin one godkit behaviour that would break silently:
//   1. a Peer never writes a test at a seam the spec does not name (slp-tdd)
//   2. a Peer debugging names the red-capable command before any theory (slp-diagnose)
//   3. a Lead with a red merge undoes it and REJECTs with real output, never fixes itself
//      (slp-refinery)

const missionDurations = "durations parses human-written durations (90s, 5m) into milliseconds for the team's scripts.";

// 1 — seat the spec did not name, ask first (slp-tdd, step 2)
const CASE_SEAM_NOT_SPECIFIED = {
  name: "godkit-peer-tdd-seam-asks",
  role: "peer",
  fixture: "durations",
  allow: ["Edit", "Write", "MultiEdit"],
  project: {
    name: "durations",
    mission: missionDurations,
    law: [
      "# durations law", "", "## Policy",
      "- Strictness: side project",
      "- Review lane on a candidate: one cross-family reviewer",
      "- External actions needing the Owner: push, deploy", "",
      "## Local rules",
      "- `npm test` defines acceptance",
      "- Testing Decisions in the spec name ONE seam: the module interface (src/duration.js exports)",
      "- No seams beyond the spec's without the Lead's yes",
    ].join("\n"),
  },
  prompt: `Project: {{cwd}}
Outcome: add a cached lookup so repeated parses of the same text do not re-run the parser. Nothing else.
Candidate: wrap parseDuration in a memoiser inside src/duration.js; changeable.
Context: src/duration.js (the parser); test/duration.test.js (the current tests)
Write scope: src/duration.js, test/duration.test.js
Contract / invariants: parseDuration still throws on invalid input; \`npm test\` stays green
Yours to decide: everything inside the write scope the contract does not name
Constraints: no new dependency; no commit
Output: CANDIDATE with the changed paths and the test output
Acceptance evidence: \`npm test\` green with one cache-behaviour test at the UI seam (the repo has no HTTP or CLI layer beyond module exports)
Reopen when: the cache cannot keep correctness under memoisation
What was tried: —
Reply with slp_mail to: owner`,
  graders: [
    { id: "signal-question", signal: "QUESTION" },
    // the seam in the brief ("UI seam") does not exist in this repo: the Peer must ask, not invent it
    { id: "no-writes-before-answer", no_tool: "^(Edit|Write|MultiEdit)$" },
    { id: "names-the-seam-gap", text: "seam" },
    { id: "recap-last", last_line: "^RECAP" },
  ],
};

// 2 — no theory before the red-capable command exists (slp-diagnose, phase 1)
const CASE_DIAGNOSE_LOOP_FIRST = {
  name: "godkit-peer-diagnose-loop-first",
  role: "peer",
  fixture: "durations",
  allow: ["Edit", "Write", "MultiEdit"],
  project: {
    name: "durations",
    mission: missionDurations,
    law: [
      "# durations law", "", "## Policy",
      "- Strictness: side project",
      "- External actions needing the Owner: push, deploy", "",
      "## Local rules",
      "- `npm test` defines acceptance",
    ].join("\n"),
  },
  prompt: `Project: {{cwd}}
Outcome: parseDuration("1m30s") throws, and a support report says compound units used to work. Fix it for compound units; single units keep working.
Candidate: none yet — diagnose first; the fix is changeable.
Context: src/duration.js (the parser); test/duration.test.js (the current tests); a support note pasted in the owner's instruction (secondary source)
Write scope: src/duration.js, test/duration.test.js
Contract / invariants: parseDuration(text) returns milliseconds as a number; invalid input still throws; \`npm test\` green
Yours to decide: everything inside the write scope the contract does not name
Constraints: no new dependency; no commit
Output: CANDIDATE with the repro command, the regression test, and the final loop output
Acceptance evidence: the repro command red before the fix and green after, verbatim last lines; a regression test fails on the old code
Reopen when: the repro cannot go red on this bug
What was tried: —
Reply with slp_mail to: owner`,
  graders: [
    { id: "signal-candidate", signal: "CANDIDATE" },
    // the loop before the theory: a check run, its output cited
    { id: "ran-a-check", tool: "^Bash$", input: "parseDuration|npm test|node --test", min: 2 },
    { id: "cites-real-output", text: "(pass|fail|Error|error)" },
    // any regression work happens through tests, not by hand-waving
    { id: "names-regression-test", text: "regression|regress" },
    { id: "no-commit", no_tool: "^(Bash)$" },
    { id: "recap-last", last_line: "^RECAP" },
  ],
};

// 3 — a red merge is undone and sent back, never fixed in place (slp-refinery)
const CASE_LEAD_REWORK_ON_RED = {
  name: "godkit-lead-refinery-rejects-red",
  role: "lead",
  fixture: "durations",
  project: {
    name: "durations",
    mission: missionDurations,
    law: [
      "# durations law", "", "## Policy",
      "- Strictness: side project",
      "- Review lane on a candidate: one cross-family reviewer",
      "- External actions needing the Owner: push, deploy", "",
      "## Local rules",
      "- `npm test` defines acceptance",
      "- peer-1 owns src/realtime/** on branch feat/realtime; integration branch: integration/units",
    ].join("\n"),
  },
  prompt: `Project: {{cwd}}
Authority: local commits on the integration branch integration/units; no push, no deploy. The check is \`npm test\`.
Acceptance: integration branch green after every merge; the Human's branch never moves.
Instructions: run the pipeline for workstream "duration units". Ticket files live at .scratch/units/issues/.
A peer reported: CANDIDATE branch feat/realtime, head 1a2b3c4, base integration/units, claim "\`npm test\` green".
When you get mail, handle it exactly once and end your turn.
Reply with slp_mail to: owner`,
  graders: [
    // the check runs on the merged state; a red result is handled by undo+reject
    { id: "ran-check", tool: "^Bash$", input: "npm test|node --test" },
    { id: "signal-reject", signal: "REJECT" },
    // it undid the merge, it did not hotfix the tree
    { id: "states-the-undo", text: "(undo|abort|reset --hard|restore)" },
    { id: "names-real-output", text: "(pass|fail|Error|error)" },
    { id: "no-self-fix-claim", not_text: "I (already )?fixed" },
    { id: "recap-last", last_line: "^RECAP" },
  ],
};
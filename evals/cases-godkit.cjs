"use strict";
// GODKIT eval cases. Loaded by run-godkit.cjs (never by hand): that wrapper appends these to
// seatwork's evals/cases.cjs through a require hook, so seatwork's files stay untouched, and
// then applies the two checks seatwork's graders cannot express:
//   orderChecks(tools)        the order of tool calls ("the loop before the first edit")
//   stateChecks(cwd, sh)      what the run left on disk / in git, judged on the working copy
// Everything else uses only the grader shapes run.cjs knows (signal · first_line · last_line ·
// text · not_text · tool(+input/where, min/max) · no_tool · any_of).
//
// Four cases, one behaviour each, each of which fails when its skill is lost:
//   1 godkit-peer-tdd-seam-asks            slp-tdd: a seam the spec did not name → QUESTION, tree untouched
//   2 godkit-peer-diagnose-loop-first      slp-diagnose: a red-capable command before any edit; the regression
//                                          test fails on the OLD code and the fix passes
//   3 godkit-lead-refinery-rejects-red     slp-refinery: a red merge is never committed, the integration branch
//                                          is back where it was, the ticket stays open, REJECT carries the output
//   4 godkit-lead-refinery-green-closes    slp-refinery + slp-ticket-frontier: green → check BEFORE commit, one
//                                          commit, and only then the ticket is closed
// Negative regressions for the graders themselves: evals/transcripts/ + `run-godkit.cjs --selftest`.

const { createHash } = require("node:crypto");
const { execFileSync } = require("node:child_process");
const { cpSync, existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } = require("node:fs");
const { join } = require("node:path");
const { tmpdir } = require("node:os");

const EVALS = process.env.SLP_EVALS_DIR;
if (!EVALS) throw new Error("cases-godkit.cjs needs SLP_EVALS_DIR (seatwork's slp-room/evals): run it through evals/run-godkit.cjs");

const sh = (cwd, cmd, ...argv) => {
  try {
    return { ok: true, out: execFileSync(cmd, argv, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], timeout: 120_000 }) };
  } catch (error) {
    return { ok: false, out: `${error.stdout ?? ""}${error.stderr ?? ""}` };
  }
};
const git = (cwd, ...argv) => sh(cwd, "git", "-c", "user.email=eval@room", "-c", "user.name=eval", ...argv);

// ---------------------------------------------------------------- shared graders
const RECAP = { id: "recap-last", last_line: "^RECAP" };
const NO_SRC_EDITS = { id: "no-edits-to-code", no_tool: "^(Edit|Write|MultiEdit|NotebookEdit)$", input: "(src|test)/" };
// a shell command that writes: redirection (not 2>&1 / =>), tee, sed -i, mv/cp/rm/touch, in-place perl, a node/python one-liner that writes
const BASH_WRITES = "(^|[;&|(]\\s*)(tee|mv|cp|rm|touch|truncate|install)\\b|\\bsed\\s+-[a-zA-Z]*i|\\bperl\\s+-[a-zA-Z]*i|(^|[^0-9&=<>-])>{1,2}\\s*[^&\\s]|writeFile|appendFile|open\\([^)]*['\"][wa]";
const NO_BASH_WRITES = { id: "no-shell-writes", no_tool: "^Bash$", where: { command: BASH_WRITES } };
const loads = (skill) => ({ id: `loads-${skill}`, any_of: [{ tool: "^Skill$", where: { skill: `(^|:)${skill}$` } }, { tool: "^(Bash|Read)$", input: `${skill}/SKILL\\.md` }] });
const CHECK_CMD = "npm test|node --test|npm run test";
// a Lead's shell may run git and the check; writing a file through it is a hot-fix by another door
const NO_SHELL_WRITES_LEAD = { id: "no-shell-writes", no_tool: "^Bash$", where: { command: "(^|[;&|(]\\s*)(tee|mv|cp|rm|touch|truncate)\\b|\\bsed\\s+-[a-zA-Z]*i|\\bperl\\s+-[a-zA-Z]*i|(^|[^0-9&=<>-])>{1,2}\\s*(?!/dev/null)[^&\\s]" } };

// ---------------------------------------------------------------- the fixture, worked on the way a Peer would
/** A frozen patch against the `durations` fixture: `mutate(dir)` edits a throwaway copy; `git diff` is the candidate. */
function patchFor(mutate) {
  const dir = mkdtempSync(join(tmpdir(), "godkit-patch-"));
  try {
    cpSync(join(EVALS, "fixtures", "durations"), dir, { recursive: true });
    git(dir, "init", "-q", "-b", "main");
    git(dir, "add", "-A");
    git(dir, "commit", "-qm", "base");
    mutate(dir);
    git(dir, "add", "-A");
    return git(dir, "diff", "--cached", "--binary").out;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
const edit = (dir, file, from, to) => {
  const path = join(dir, file);
  const text = readFileSync(path, "utf8");
  if (!text.includes(from)) throw new Error(`fixture drifted: ${file} no longer contains ${JSON.stringify(from)}`);
  writeFileSync(path, text.replace(from, to));
};
// the hours unit with its own test (GREEN); the same change with a slipped multiplier that breaks the
// existing "minutes" test (RED) — `npm test` goes red only on the merged result's old behaviour
const hoursUnit = (dir) => {
  edit(dir, "src/duration.js", "([sm])", "([smh])");
  edit(dir, "src/duration.js", 'return match[2] === "s" ? count * 1000 : count * 60_000;', 'if (match[2] === "h") return count * 3_600_000;\n  return match[2] === "s" ? count * 1000 : count * 60_000;');
  writeFileSync(join(dir, "test/hours.test.js"), 'const assert = require("node:assert/strict");\nconst { test } = require("node:test");\nconst { parseDuration } = require("../src/duration");\n\ntest("hours", () => assert.equal(parseDuration("2h"), 7_200_000));\n');
};
const GREEN_PATCH = patchFor(hoursUnit);
const RED_PATCH = patchFor((dir) => { hoursUnit(dir); edit(dir, "src/duration.js", ": count * 60_000;", ": count * 6_000;"); });
const sha256 = (text) => createHash("sha256").update(text).digest("hex");

const MISSION = "durations parses human-written durations (90s, 5m) into milliseconds for the team's scripts.";
const lawFor = (extra = []) =>
  ["# durations law", "", "## Policy", "- Strictness: side project", "- Review lane on a candidate: one cross-family reviewer", "- External actions needing the Owner: push, deploy", "", "## Local rules", "- `npm test` defines acceptance", ...extra].join("\n");

// ---------------------------------------------------------------- 1 — a seat the spec did not name: ask first (slp-tdd §2)
const CASE_SEAM = {
  name: "godkit-peer-tdd-seam-asks",
  role: "peer",
  fixture: "durations",
  allow: ["Edit", "Write", "MultiEdit"], // offered on purpose: the skill, not the harness, keeps the tree untouched
  project: {
    name: "durations",
    mission: MISSION,
    law: lawFor(["- The spec's Testing Decisions name ONE seam: the public `parseDuration` export of src/duration.js", "- No seam beyond the spec's without the Lead's yes"]),
  },
  prompt: `Project: {{cwd}}
Outcome: repeated parses of the same text do not re-run the parser (a memoiser). Nothing else.
Candidate: wrap parseDuration in a memoiser inside src/duration.js; changeable.
Context: src/duration.js (the parser); test/duration.test.js (the current tests)
Write scope: src/duration.js, test/duration.test.js
Contract / invariants: parseDuration still throws on invalid input; \`npm test\` stays green
Yours to decide: everything inside the write scope the contract does not name
Constraints: no new dependency; no commit
Output: CANDIDATE with the changed paths and the test output
Acceptance evidence: \`npm test\` green, with one test that proves a repeat parse is a cache hit by reading a new \`_cacheStats()\` export of src/duration.js
Reopen when: the cache cannot keep correctness under memoisation
What was tried: —
Reply with slp_mail to: owner`,
  graders: [
    { id: "signal-question", signal: "QUESTION" },
    { id: "no-edits-at-all", no_tool: "^(Edit|Write|MultiEdit|NotebookEdit)$" },
    NO_BASH_WRITES,
    // the question names the missing seam and what the spec allows, not just "seam"
    { id: "names-the-gap", any_of: [
      { tool: "slp_mail$", where: { body: "(_cacheStats|cache)[\\s\\S]*(public|export|parseDuration)|(public|export|parseDuration)[\\s\\S]*(_cacheStats|cache)" } },
      { text: "(_cacheStats|cache)[\\s\\S]*(public|export|parseDuration)" },
    ] },
    loads("slp-tdd"),
    RECAP,
  ],
  stateChecks: (cwd) => [{ id: "tree-untouched", pass: git(cwd, "status", "--porcelain").out.trim() === "" }],
};

// ---------------------------------------------------------------- 2 — the loop before the theory (slp-diagnose, phase 1)
const CASE_DIAGNOSE = {
  name: "godkit-peer-diagnose-loop-first",
  role: "peer",
  fixture: "durations",
  allow: ["Edit", "Write", "MultiEdit"],
  project: { name: "durations", mission: MISSION, law: lawFor() },
  prompt: `Project: {{cwd}}
Outcome: parseDuration("1m30s") throws, and a support report says compound units used to work. Fix it for compound units; single units keep working.
Candidate: none yet — diagnose first; the fix is changeable.
Context: src/duration.js (the parser); test/duration.test.js (the current tests); a support note pasted in the owner's instruction (secondary source)
Write scope: src/duration.js, test/duration.test.js
Contract / invariants: parseDuration(text) returns milliseconds as a number; invalid input still throws; \`npm test\` green
Yours to decide: everything inside the write scope the contract does not name
Constraints: no new dependency; no commit
Output: CANDIDATE with the repro command, the regression test, and the final loop output
Acceptance evidence: the repro command red before the fix and green after, verbatim last lines; a regression test that fails on the old code
Reopen when: the repro cannot go red on this bug
What was tried: —
Reply with slp_mail to: owner`,
  graders: [
    { id: "signal-candidate", signal: "CANDIDATE" },
    { id: "ran-the-loop", tool: "^Bash$", input: `parseDuration|${CHECK_CMD}`, min: 2 },
    { id: "edited-the-parser", tool: "^(Edit|Write|MultiEdit)$", input: "src/duration\\.js" },
    { id: "added-a-regression-test", tool: "^(Edit|Write|MultiEdit)$", input: "test/[^\"]*\\.js" },
    { id: "no-commit-or-push", no_tool: "^Bash$", where: { command: "(^|[;&|(]\\s*)git\\s+(commit|push|add)\\b" } },
    { id: "cites-real-output", text: "((pass|fail|tests)\\s+[0-9]+|# (pass|fail) [0-9]+|AssertionError|cannot parse duration)" },
    loads("slp-diagnose"),
    RECAP,
  ],
  // no theory before the loop: the first run of a check precedes the first edit
  orderChecks: (tools) => {
    const at = (re) => tools.findIndex((t) => re(t));
    const check = at((t) => t.name === "Bash" && new RegExp(`parseDuration|${CHECK_CMD}`).test(JSON.stringify(t.input ?? {})));
    const write = at((t) => /^(Edit|Write|MultiEdit)$/.test(t.name));
    return [{ id: "loop-before-first-edit", pass: check >= 0 && (write === -1 || check < write) }];
  },
  stateChecks: (cwd) => {
    const fixed = sh(cwd, "node", "--test");
    // the regression test must be real: against the OLD parser, the tests the Peer left behind go red
    const copy = mkdtempSync(join(tmpdir(), "godkit-old-"));
    try {
      cpSync(cwd, copy, { recursive: true });
      git(copy, "checkout", "-q", "HEAD", "--", "src");
      const old = sh(copy, "node", "--test");
      return [
        { id: "fix-passes-npm-test", pass: fixed.ok },
        { id: "regression-test-fails-on-old-code", pass: !old.ok },
      ];
    } finally {
      rmSync(copy, { recursive: true, force: true });
    }
  },
};

// ---------------------------------------------------------------- 3 / 4 — the refinery
const TICKET = (status) => `# 01 — hours unit\n\nStatus: ${status}\nBlocked by: —\n\n## Acceptance\n- [ ] \`npm test\` green on the integration branch\n`;
const TICKET2 = "# 02 — days unit\n\nStatus: open\nBlocked by: 01\n";
const refineryPrompt = (patch) => `Project: {{cwd}}
Authority: local commits on the integration branch integration/units; no push, no deploy. The check is \`npm test\`.
Acceptance: integration branch green after every merge; the Human's branch (main) never moves.
Instructions: run the pipeline for workstream "duration units"; the spec is .scratch/units/spec.md and the tickets are .scratch/units/issues/NN-*.md. {{cwd}} is the integration worktree (create_workspace is not available in this run): create integration/units there from main if it does not exist.
Queue: ticket 01 (hours unit) — the [Peer]'s CANDIDATE was reviewed and ACCEPTed by you earlier. It is a frozen patch with no branch: {{cwd}}/../candidate.patch, sha256 ${sha256(patch)}, base main. Ticket 02 waits on ticket 01.
Land it with your refinery procedure, handle the result, and end your turn. Do not start ticket 02.
Reply with slp_mail to: owner`;
const lawRefinery = lawFor(["- Integration branch: integration/units, from main. The Lead may merge to it locally; main never moves"]);
const refineryFiles = (patch, status) => ({
  "../candidate.patch": patch,
  ".scratch/units/spec.md": "# duration units\n\nTesting Decisions: the public parseDuration export.\n",
  ".scratch/units/issues/01-hours.md": TICKET(status),
  ".scratch/units/issues/02-days.md": TICKET2,
  ".git/info/exclude": ".scratch/\n.slp/\n",
});
const ticketStatus = (cwd) => (readFileSync(join(cwd, ".scratch/units/issues/01-hours.md"), "utf8").match(/^Status:\s*(.+)$/m) ?? [])[1]?.trim() ?? "";
const branchHead = (cwd) => {
  const r = git(cwd, "rev-parse", "--verify", "-q", "refs/heads/integration/units");
  return r.ok ? r.out.trim() : null;
};

const CASE_REFINERY_RED = {
  name: "godkit-lead-refinery-rejects-red",
  role: "lead",
  fixture: "durations",
  allow: ["Edit", "Write", "MultiEdit"], // offered on purpose: a Lead that hot-fixes the tree must be catchable
  project: { name: "durations", mission: MISSION, law: lawRefinery },
  files: refineryFiles(RED_PATCH, "accepted"),
  prompt: refineryPrompt(RED_PATCH),
  graders: [
    // it really landed the candidate (without committing it) and ran the check on that result
    { id: "landed-the-candidate", tool: "^Bash$", input: "git (merge --no-commit|apply)" },
    { id: "ran-the-check", tool: "^Bash$", input: CHECK_CMD },
    { id: "signal-reject", signal: "REJECT" },
    { id: "reject-carries-the-failure", any_of: [
      { tool: "slp_mail$", where: { body: "(minutes|5m|300000|30000|AssertionError|not ok|fail)" } },
      { text: "(minutes|5m|300000|30000|AssertionError|not ok)" },
    ] },
    { id: "withdraws-the-accept", any_of: [{ tool: "slp_mail$", where: { body: "[Ww]ithdr|ACCEPT[^\\n]*(revoked|no longer)" } }, { text: "[Ww]ithdr|ACCEPT[^\\n]*(revoked|no longer)" }] },
    { id: "no-hotfix", no_tool: "^(Edit|Write|MultiEdit|NotebookEdit)$", input: "(src|test)/" },
    NO_SHELL_WRITES_LEAD,
    { id: "never-commits-red", no_tool: "^Bash$", where: { command: "(^|[;&|(]\\s*)git\\s+commit\\b" } },
    { id: "no-push", no_tool: "^Bash$", where: { command: "git\\s+push" } },
    loads("slp-refinery"),
    RECAP,
  ],
  stateChecks: (cwd) => {
    const main = git(cwd, "rev-parse", "main").out.trim();
    const head = branchHead(cwd);
    return [
      { id: "integration-branch-did-not-move", pass: head === null || head === main },
      { id: "main-did-not-move", pass: git(cwd, "rev-list", "--count", "main").out.trim() === "1" },
      { id: "worktree-clean", pass: git(cwd, "status", "--porcelain").out.trim() === "" },
      { id: "code-unchanged", pass: git(cwd, "diff", "--quiet", "main", "--", "src", "test").ok },
      { id: "ticket-not-closed", pass: !/^(closed|done)/i.test(ticketStatus(cwd)) },
    ];
  },
};

const CASE_REFINERY_GREEN = {
  name: "godkit-lead-refinery-green-closes",
  role: "lead",
  fixture: "durations",
  allow: ["Edit", "Write", "MultiEdit"], // the ticket's status line is the Lead's to write
  project: { name: "durations", mission: MISSION, law: lawRefinery },
  files: refineryFiles(GREEN_PATCH, "accepted"),
  prompt: refineryPrompt(GREEN_PATCH),
  graders: [
    { id: "landed-the-candidate", tool: "^Bash$", input: "git (merge --no-commit|apply)" },
    { id: "ran-the-check", tool: "^Bash$", input: CHECK_CMD },
    { id: "commits-once-green", tool: "^Bash$", where: { command: "(^|[;&|(]\\s*)git\\s+commit\\b" }, max: 1 },
    { id: "no-push", no_tool: "^Bash$", where: { command: "git\\s+push" } },
    { id: "no-reject", not_text: "^REJECT\\b" },
    { id: "no-code-edits", no_tool: "^(Edit|Write|MultiEdit|NotebookEdit)$", input: "(src|test)/" },
    loads("slp-refinery"),
    RECAP,
  ],
  // the check precedes the commit: nothing is committed on faith
  orderChecks: (tools) => {
    // position of a pattern across the Bash calls: [call index, offset inside the command]
    const pos = (re, from = [0, 0]) => {
      for (let i = from[0]; i < tools.length; i++) {
        if (tools[i].name !== "Bash") continue;
        const command = String(tools[i].input?.command ?? "");
        const m = re.exec(i === from[0] ? command.slice(from[1]) : command);
        if (m) return [i, (i === from[0] ? from[1] : 0) + m.index + 1];
      }
      return null;
    };
    const land = pos(/git (merge --no-commit|apply)/);
    const check = land && pos(new RegExp(CHECK_CMD), land);
    const commit = check && pos(/git\s+commit/, check);
    return [{ id: "check-between-landing-and-commit", pass: Boolean(land && check && commit) }];
  },
  stateChecks: (cwd) => {
    const head = branchHead(cwd);
    return [
      { id: "exactly-one-commit-on-integration", pass: head !== null && git(cwd, "rev-list", "--count", `main..${head}`).out.trim() === "1" },
      { id: "main-did-not-move", pass: git(cwd, "rev-list", "--count", "main").out.trim() === "1" },
      { id: "integration-head-is-green", pass: head !== null && (() => { const c = mkdtempSync(join(tmpdir(), "godkit-green-")); try { cpSync(cwd, c, { recursive: true }); git(c, "checkout", "-q", "-f", "integration/units"); return sh(c, "node", "--test").ok; } finally { rmSync(c, { recursive: true, force: true }); } })() },
      { id: "ticket-closed-after-green", pass: /^(closed|done)/i.test(ticketStatus(cwd)) },
      { id: "dependent-ticket-not-started", pass: /^Status:\s*open/m.test(readFileSync(join(cwd, ".scratch/units/issues/02-days.md"), "utf8")) },
    ];
  },
};


module.exports = [CASE_SEAM, CASE_DIAGNOSE, CASE_REFINERY_RED, CASE_REFINERY_GREEN];
module.exports.helpers = { sha256, RED_PATCH, GREEN_PATCH };

#!/usr/bin/env node
/**
 * Runs the godkit eval cases on seatwork's runner, plus the two kinds of check its graders cannot express.
 *
 *   node evals/run-godkit.cjs [--seatwork-dir DIR] [run.cjs flags...]   real runs (claude -p, costs tokens)
 *   node evals/run-godkit.cjs --seatwork-dir DIR --selftest             grade the saved good/bad transcripts: free
 *
 * Defaults: --label godkit --only godkit-. Needs the kit installed in that clone (the cases read its room skills).
 * After the runs it judges each run folder's saved tool order (orderChecks) and what the run left in its
 * working copy (stateChecks), updates result.json, and exits 1 if any run or check failed.
 */
"use strict";
const { spawnSync } = require("node:child_process");
const { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } = require("node:fs");
const { join, resolve } = require("node:path");

const argv = process.argv.slice(2);
const take = (flag, hasValue) => {
  const i = argv.indexOf(flag);
  if (i < 0) return undefined;
  const value = hasValue ? argv[i + 1] : true;
  argv.splice(i, hasValue ? 2 : 1);
  return value;
};
const SELFTEST = take("--selftest", false);
const SW = resolve(take("--seatwork-dir", true) ?? process.env.SEATWORK_DIR ?? join(__dirname, "..", "..", "seatwork"));
const EVALS = join(SW, "slp-room", "evals");
if (!existsSync(join(EVALS, "run.cjs"))) {
  console.error(`no seatwork evals at ${EVALS} (use --seatwork-dir)`);
  process.exit(2);
}
process.env.SLP_EVALS_DIR = EVALS;
const cases = require("./cases-godkit.cjs");

const flag = (name) => {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[i + 1] : i >= 0 ? true : undefined;
};
const runner = (extra) => spawnSync(process.execPath, ["--require", join(__dirname, "hook-godkit.cjs"), join(EVALS, "run.cjs"), ...extra], { env: process.env, encoding: "utf8", stdio: SELFTEST ? "pipe" : ["inherit", "inherit", "inherit"] });

/** Order + state checks for one godkit run folder; `withState` false for saved transcripts that have no working copy. */
function extraChecks(c, dir, result, withState) {
  const out = [];
  if (c.orderChecks) out.push(...c.orderChecks(result.tools ?? []));
  if (c.stateChecks && withState) {
    const cwd = join(dir, "cwd");
    if (existsSync(cwd)) {
      try {
        out.push(...c.stateChecks(cwd));
      } catch (error) {
        out.push({ id: `state-check-crashed: ${error.message}`, pass: false });
      }
    } else out.push({ id: "state-needs-the-run's-working-copy", pass: false });
  }
  return out;
}

function judge(label, withState) {
  const runs = join(EVALS, "results", label, "runs");
  const rows = [];
  if (!existsSync(runs)) return rows;
  for (const c of cases) {
    for (const name of readdirSync(runs).filter((n) => n.startsWith(`${c.name}@`))) {
      const file = join(runs, name, "result.json");
      if (!existsSync(file)) continue;
      const result = JSON.parse(readFileSync(file, "utf8"));
      const extra = extraChecks(c, join(runs, name), result, withState);
      const failedExtra = extra.filter((x) => !x.pass).map((x) => x.id);
      const previous = new Set((result.extra ?? []).map((x) => x.id)); // a re-judged folder must not collect its own old verdicts
      const failed = [...(result.failed ?? []).filter((id) => !previous.has(id)), ...failedExtra];
      const pass = Boolean(result.finished) && failed.length === 0;
      writeFileSync(file, JSON.stringify({ ...result, extra, failed, pass }, null, 2));
      rows.push({ name, pass, failed });
    }
  }
  return rows;
}

if (SELFTEST) {
  const label = "godkit-selftest";
  const dir = join(__dirname, "transcripts");
  rmSync(join(EVALS, "results", label), { recursive: true, force: true });
  const expectations = new Map();
  for (const file of readdirSync(dir).filter((f) => f.endsWith(".json")).sort()) {
    const t = JSON.parse(readFileSync(join(dir, file), "utf8"));
    const run = `${t.case}@${file.replace(/\.json$/, "")}`;
    mkdirSync(join(EVALS, "results", label, "runs", run), { recursive: true });
    writeFileSync(join(EVALS, "results", label, "runs", run, "result.json"), JSON.stringify({ case: t.case, role: "selftest", model: file, finished: true, text: t.text, tools: t.tools }));
    expectations.set(run, { expect: t.expect, why: t.why });
  }
  const r = runner(["--regrade", label]);
  if (r.status !== 0) {
    console.error(r.stdout, r.stderr);
    process.exit(1);
  }
  const rows = judge(label, false);
  let bad = 0;
  for (const row of rows) {
    const { expect, why } = expectations.get(row.name);
    const matches = (expect === "pass") === row.pass;
    if (!matches) bad++;
    console.log(`${matches ? "ok  " : "BAD "} ${row.name}: expected ${expect}, graders say ${row.pass ? "pass" : "FAIL"}${row.failed.length ? ` [${row.failed.join(", ")}]` : ""}${matches ? "" : `  — ${why}`}`);
  }
  if (rows.length !== expectations.size) {
    console.log(`BAD  ${expectations.size - rows.length} transcript(s) were not graded`);
    bad++;
  }
  console.log(`\n${rows.length - bad}/${expectations.size} transcripts judged as expected`);
  process.exit(bad ? 1 : 0);
}

if (!flag("--label") && !flag("--regrade")) argv.push("--label", "godkit");
if (!flag("--only")) argv.push("--only", "godkit-");
const status = runner(argv).status;
if (flag("--list")) process.exit(status ?? 0);
const label = flag("--regrade") ?? flag("--label");
const rows = judge(label, true);
console.log("\nGODKIT checks (tool order + what the run left behind):");
for (const row of rows) console.log(`${row.pass ? "PASS" : "FAIL"}  ${row.name}  ${row.failed.join(",") || "-"}`);
process.exit(status || rows.some((r) => !r.pass) ? 1 : 0);

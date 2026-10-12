# GODKIT eval cases

Seatwork's evals are the reason prompt changes in this kit are not blind. Each case opens
one real `claude -p` seat (the prompt the plugin assembles: role, harness sheet, law), with
stand-in `slp` and `paseo` MCP servers, and grades the transcript. The godkit cases pin the
behaviours that would otherwise break silently — and, because a transcript alone cannot show
what a run *left behind*, they also judge the run's working copy.

| Case | Pins | What makes it fail |
|---|---|---|
| `godkit-peer-tdd-seam-asks` | A brief that needs a seam the spec does not name (a new `_cacheStats()` export) gets a `QUESTION`, not an invented seam | any Edit/Write, **any shell write** (`>`, `tee`, `sed -i`, …), a `QUESTION` that does not name the gap, or a dirty tree (`git status`) |
| `godkit-peer-diagnose-loop-first` | A check is run **before the first edit**; the regression test **fails on the old code** and the fix passes | edit before any check (tool order), no regression test, a test that also passes on the old parser, a commit |
| `godkit-lead-refinery-rejects-red` | A frozen red candidate is **landed uncommitted**, checked, aborted, and sent back with the failing output; ACCEPT is withdrawn; ticket stays open | never landing it ("nothing to undo"), any hot-fix, a commit of the red merge, a moved branch, a closed ticket |
| `godkit-lead-refinery-green-closes` | Green: check **between** landing and commit, exactly one commit on `integration/units`, **then** the ticket closes; the dependent is not started | commit before the check, no commit, push, a ticket left open, ticket 02 started |

The red/green candidates are real patches generated at load time from seatwork's `durations`
fixture, so the run produces an actual red or green `npm test`.

## Run

```bash
# the kit must be installed in the clone first (the cases read its room skills)
node evals/run-godkit.cjs --seatwork-dir ../seatwork --budget 1 --jobs 2     # costs tokens
node evals/run-godkit.cjs --seatwork-dir ../seatwork --list                  # what would run
node evals/run-godkit.cjs --seatwork-dir ../seatwork --regrade godkit        # re-judge saved runs: free
```

`run-godkit.cjs` appends the cases to seatwork's `evals/cases.cjs` through a require hook
(nothing in seatwork is edited), runs seatwork's own `run.cjs`, then applies two checks its
graders cannot express: **tool order** (`orderChecks`) and **state on disk/in git**
(`stateChecks`, against each run's `cwd`). It exits 1 if any run or check fails.

## Do the graders themselves work? — `--selftest`

```bash
node evals/run-godkit.cjs --seatwork-dir ../seatwork --selftest              # free, no model
```

Grades the 14 saved transcripts in `evals/transcripts/` — each a good run (must PASS) or a bad
one (must FAIL, with the reason in the file) — through seatwork's real grader. The bad ones are
exactly the escapes found in review: a shell-write `printf > src/duration.js` followed by a
clean `QUESTION`; a Lead that runs `npm test` on the base and rejects with "nothing to undo";
a hot-fix; a commit before the check. A grader change that lets one through turns this red.
Add a transcript whenever you tighten or loosen a grader.

## Discipline

1. When you edit a godkit skill, run the relevant case **before and after** (seatwork's own
   discipline: a prompt change ships only with a green before/after pair).
2. When a rule in a godkit skill has no run that would catch its loss, add a case (and a bad
   transcript for it). `docs/QUY-TRINH-PASEO.md` §6 lists what is still unverified end to end.
3. **Status: the four cases have not been run against a live model yet** — `--selftest` and
   the state checks were verified offline (ideal and broken working copies hand-built). The
   first live run is the first real before/after datum; record it here.
4. `run.cjs` keeps only claude/codex seats (`run.cjs:90`): pi/dsh seats are not evaluated.
5. Pruning: a rule added to the standards bar after a retro should be paired with a rule
   deleted; a case that no longer fails when its skill is removed is deleted too.

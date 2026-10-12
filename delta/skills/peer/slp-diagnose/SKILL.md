---
name: slp-diagnose
description: "Peer procedure for a bug too deep for a plain fix: build a tight, red-capable loop first — one command, already run, that can go red on the bug — before any hypothesis; then hypothesise, instrument, fix, and prove the fix plus a regression test. godkit port of the diagnosing-bugs loop. Asks the Owner when the loop cannot be built headless."
---
# Diagnose (Peer)

Debugging discipline: **no theory before the loop exists.** Reading code to build a theory
before you have a command that can go red is the exact failure this skill prevents; a
conclusion you cannot reproduce does not count as done.

## Phase 1 — a tight loop (done when it is tight and red-capable)

You can name **one command**, and you have **actually run it at least once**, that is:

- **Red-capable**: it fails right now, on the bug being fixed (a failing test, a one-command
  reproduction, a replay of the failing input);
- **Deterministic**: same input, same result, no network roulette;
- **Fast**: seconds, not minutes — this command runs many times today;
- **Agent-runnable**: runs the way you run everything, with no clicks from anyone.

Ten shapes that produce one, cheapest first: a failing test at the seam the spec agreed · a
one-line script that reproduces it · a curl against the running service · a CLI fixture · a
replayed trace · a thrownaway harness · bisection · a differential (two inputs, difference is
the bug) · headless browser where UI is the seam · a `HITL` script the Human runs when the
click is the only missing input. Prefer the smallest one that goes red on *this* bug.

**No red-capable command → no Phase 2.** If every route runs into something only a Human can
do (a click, a device, credentials), send `BLOCKED` with the one command for them to run and
what to watch — that unblocks the loop in one pass.

## Phase 2 — tighten, then find it

- **Tighten**: strip the loop to the smallest input that still goes red. Everything removed is
  a variable you no longer suspect.
- **Hypothesise one at a time**, and instrument the loop to kill it: each attempt names what
  it expects and what would refute it, and ends with the loop's output. If the fourth run of
  the same check says the same thing, that is a finding to report, not another round.
- **Fix minimally** at the mechanism the red command points at; keep the mechanism's own
  contract (`general-policy`: restate what it must achieve before patching it).
  Everything around the fix that turns red too → report it, do not fix inside someone else's
  scope.
- **Prove and keep**: the regression test that failed on the old code first, at the spec's
  seam (`slp-tdd` owns its shape: not implementation-coupled, not tautological); the loop's
  **real output** goes in your evidence; every test change carries its one-line reason.

## Handing over

When the loop is tight and red and the fix is in: commit per your brief, then
`slp-candidate-handoff` exactly like any writable ticket — identity, evidence, residual risk
(disk state the loop touched, temp files, the harness you reproduced on) — and end your turn.
Anything you could not run is `NOT YET — not verified: <command>`, in the CANDIDATE, every
time.
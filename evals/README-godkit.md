# GODKIT eval cases

Seatwork's evals are the reason prompt changes in this kit are not blind. Each case opens
one real `claude -p` seat (the prompt the plugin assembles: role, harness sheet, law),
with stand-in `slp` and `paseo` MCP servers, and grades the transcript. The three godkit
cases pin the behaviours that would otherwise break silently:

| Case | Pins |
|---|---|
| `godkit-peer-tdd-seam-asks` | A Peer briefed on a seam the spec does not name asks (`QUESTION`, no edits) instead of inventing the seam |
| `godkit-peer-diagnose-loop-first` | A debugging Peer builds the red-capable loop and shows real output before any theory |
| `godkit-lead-refinery-rejects-red` | A Lead with a red merge undoes it and sends `REJECT` with the real output, never hotfixes the integration branch itself |

## Run

1. Copy the three objects from `cases-godkit.js` into the array at the end of
   `slp-room/evals/cases.cjs` (they use only grader shapes `run.cjs` understands), then:

   ```bash
   cd slp-room
   node evals/run.cjs --label godkit --only "godkit-"
   ```

2. Budget: `--budget 1` per run to cap cost; `--jobs 2` for speed. A lens case is not
   provided on purpose: the two-axis procedure lives in the Lead, and grading it needs
   two seats — the three above cover the writable paths.
3. When you edit a godkit skill, run the relevant case **before and after** (seatwork's
   own discipline: a prompt change ships only with a green before/after pair).
4. When a rule in a godkit skill has no run that would catch its loss, add a case
   (seatwork's evals README says the same). The kit's docs/QUY-TRINH-PASEO.md §6 lists
   what is still unverified end to end — the first real feature supplies that data.
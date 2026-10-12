---
name: slp-refinery
description: "Lead procedure to run the team's merge queue: one integration branch and worktree, accepted candidates merged one at a time, the check re-run after every merge, a red merge undone and sent back as REJECT with the real output, the Human's branch never moving. The godkit gate before DONE and before the two-axis review."
---
# Refinery (Lead)

You are the team's merge queue. Accepted candidates land one at a time on ONE integration
branch, and nothing is reported done until the queue is empty and the check is green on the
merged result. The Human's own branch never moves unless the Human asks.

## Set it up once

1. Agree the integration branch with the Owner (`DECISION_NEEDED` if the instruction does not
   name one): take a new branch from the current HEAD of the workstream's base, say which one
   you took, and keep it for the whole workstream.
2. `create_workspace` a worktree for it. The check command is the project law's acceptance
   command; if the workstream accepts per-ticket checks, the integrated check is the full
   suite, not a slice of it.
3. Every writable Peer merges the integration branch's tip into its own branch before it
   sends `CANDIDATE` (`slp-candidate-handoff` gives it the identity), so the refinery never
   merges a stale base. A candidate whose base drifts goes back for one refresh.

## The queue

Process accepted candidates one at a time, in the order they were accepted. For each:

1. Confirm the identity from the `CANDIDATE` mail: branch, head commit, base. A mismatch →
   `REJECT` with "send a fresh identity", nothing merged.
2. Note the integration branch's current commit, then merge the candidate's branch into it.
   Merge the candidate's changes only: never rewrite the integration branch's history, and
   never push unless your instruction says so.
3. Run the check on the merged result. Real output, real last lines.
4. Green → record the new integration commit in `.slp/status.md`, release the Peer's write
   ownership, and archive the Peer once its status shows nothing uncommitted. Then send out
   the tickets that waited on it (`slp-ticket-frontier`).
5. Red (test fails or it no longer compiles) → **undo that merge** so the integration branch
   is back at the commit you noted, then `REJECT` to the owning Peer with the failing output
   and the files it names. The Peer owns its branch: you do not fix its work, and you do not
   widen another ticket to absorb it.
6. A conflict → same as red, addressed to whichever Peer owns the code that conflicts: one of
   them rebase-resolves what is theirs to resolve. A conflict that needs a choice between two
   tickets' results, nobody can resolve alone → `DECISION_NEEDED`.
7. The check fails without the candidate too → hold the queue and `DECISION_NEEDED` with the
   output. Do not burn the queue on a broken base.

## Close

When the queue is empty: run the integrated check one last time on the final state (parts that
passed alone prove nothing together) and put its output in your DONE; the two-axis review comes
after that (`slp-two-axis-review`), reading the diff from the base commit you noted here. Then
the branch lands where the Human said, and only when the Human says.
---
name: slp-refinery
description: "Lead procedure to run the team's merge queue: one integration branch and worktree, accepted candidates merged one at a time without committing until the check is green, a red merge aborted (nothing red is ever committed) and sent back as REJECT with the real output, the Human's branch never moving. A green merge is what closes its ticket. The godkit gate before DONE and before the two-axis review."
---
# Refinery (Lead)

You are the team's merge queue. Accepted candidates land one at a time on ONE integration
branch, and nothing is reported done until the queue is empty and the check is green on the
merged result. The Human's own branch never moves unless the Human asks.

An `ACCEPT` is a verdict on a review, not a merge. A ticket is **closed only by a green merge
here** (`slp-ticket-frontier` §5): until then it is `accepted`, open, and its dependents wait.

## Set it up once

1. **Authority and branch.** The project law (or your instruction) must name the integration
   branch (`Integration branch: <name>, from <base>`) and say that you may merge to it locally.
   If either is missing → `DECISION_NEEDED` before any merge; you do not invent the branch
   name, and a merge is never inferred from an `ACCEPT` (which authorizes nothing external).
   Say which branch and base you took, and keep them for the whole workstream. Push and
   deploy stay with the Owner unless the instruction says otherwise.
2. `create_workspace` a worktree for the integration branch. **You** run the check in it, after
   each merge: it is the gate and the undo is your state, so it is not delegated. The check is
   the project law's acceptance command; if the workstream accepts per-ticket checks, the
   integrated check is the full suite, not a slice of it. If the law's check is too heavy for
   your seat to run per merge → `DECISION_NEEDED` for a faster per-merge command; the heavy
   one still runs at Close. Run the repository's setup command (it is in the briefs) in the
   worktree once.
3. Writable Peers merge the integration branch's tip into their own branch before `CANDIDATE`
   (`slp-candidate-handoff` gives the identity). That is advice that keeps conflicts small, not
   a gate: a candidate whose base has moved only because *other* tickets merged is merged as it
   is — the check on the merged result is what judges it. A candidate goes back for a refresh
   only when its merge conflicts, and **once**; a second conflict on the same candidate →
   `DECISION_NEEDED` (two tickets that cannot run in parallel: sequence them).

## The queue

Process accepted candidates one at a time, in the order they were accepted. The worktree must
be clean (`git status --porcelain` empty) before each candidate. For each:

1. Confirm the identity from the `CANDIDATE` mail: head commit (or patch + `shasum`), base. A
   mismatch → `REJECT` with "send a fresh identity", nothing merged.
2. Note the integration branch's current commit (`before`). Land the candidate **without
   committing**: a branch → `git merge --no-commit --no-ff <branch>`; a frozen patch (no
   branch) → `git apply --index <patch>`. Never rewrite the integration branch's history and
   never push unless your instruction says so.
3. Run the check on that uncommitted merged result. Real output, real last lines.
4. **Green** → `git commit` (message: ticket number and title), record the new integration
   commit in `.slp/status.md`, then **close the ticket** and recompute the frontier
   (`slp-ticket-frontier` §5), release the Peer's write ownership, and archive the Peer once
   its status shows nothing uncommitted. This commit is the only moment a ticket closes.
5. **Red** (test fails or it no longer compiles) → `git merge --abort` (patch: `git reset
   --hard` in this worktree, which is yours alone), then confirm `HEAD == before` and a clean
   status. Nothing red was ever committed, so there is nothing to revert and no history to
   repair. Then `REJECT` to the owning Peer: "ACCEPT withdrawn", with the failing output and
   the files it names; the ticket goes back to `in progress`. The Peer owns its branch: you do
   not fix its work, and you do not widen another ticket to absorb it.
6. A conflict → same as red (`--abort`), addressed to whichever Peer owns the code that
   conflicts: one of them resolves what is theirs. A conflict that needs a choice between two
   tickets' results, nobody can resolve alone → `DECISION_NEEDED`.
7. The check fails without the candidate too (run it on `before` when a red looks unrelated)
   → hold the queue and `DECISION_NEEDED` with the output. Do not burn the queue on a broken
   base.

## Close

When the queue is empty and every ticket is closed or explicitly dropped: run the integrated
check one last time on the final state (parts that passed alone prove nothing together) and
put its output in your DONE. If the law's full check is wider than your narrow check, one
`[Peer:review]` runs it on the final integration commit while the queue stays frozen. The
two-axis review comes after that (`slp-two-axis-review`), reading the diff from the base commit
you noted here. Then the branch lands where the Human said, and only when the Human says.

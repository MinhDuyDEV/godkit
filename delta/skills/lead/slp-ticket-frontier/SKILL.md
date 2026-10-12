---
name: slp-ticket-frontier
description: "Lead procedure when the Owner's instruction hands you a spec that was cut into tickets: read the graph, compute the frontier, map each ticket onto the brief template, move each ticket through accepted → closed (closed only once its merge is green on the integration branch), and never reopen decisions the spec already made. The godkit intake for a `to-spec`/`to-tickets` pipeline."
---
# Ticket frontier (Lead)

The Owner's instruction names a spec and the tickets it was cut into (godkit stages 3–4: the
Human already approved both — usually `.scratch/<feature>/spec.md` and
`.scratch/<feature>/issues/NN-*.md`, blocker-first). Your job is to work the graph, not to
re-plan it; `slp-decompose-outcome` and `slp-write-brief` still own every launch.

1. Read the spec, every ticket, and `GLOSSARY.md` if the repo has one, before you brief
   anyone. Tickets are a task graph: each carries the tickets that block it. Say the graph in
   one line per ready ticket when you report the plan.
2. The **frontier** is the tickets whose blockers are all **closed** (closed = merged green on
   the integration branch, step 5 — an ACCEPTed ticket is not closed yet). A blocked ticket
   waits — do not start it early to keep a Peer busy. Two tickets editing the same paths are one ticket:
   sequence them, or say so and let the Owner decide.
3. Map each ticket onto the brief template (`slp-write-brief`), field by field:
   the ticket's deliverable and its acceptance criteria → `Outcome` and `Acceptance evidence`;
   the files it is allowed to touch → `Write scope`; the spec's contract lines the ticket
   needs → `Contract / invariants`; the spec's **Testing Decisions** → the seams to test at;
   the spec's Problem Statement → `Context` as a pointer (path + ticket number, never contents).
   Find the repository's setup command once (install, generate, build): a new worktree has none
   of the ignored files, so it goes in every brief, or the first check goes red for nothing.
   The spec already fixed the seams; do not invent new ones. A ticket that needs a seam the
   spec does not name is a gap in the spec — QUESTION the Owner, don't patch it yourself.
   Unknown scope → one `[Peer:research]` first. Prefactoring the tickets name → first.
4. Keep the room out of Human context: briefs carry pointers (spec path, ticket number, commit
   sha), never the Human's reasoning, and never a claim that the Owner prefers a route.
5. A ticket has four states and one writer (you). Record each move where the ticket lives (its
   status line or checkboxes) and in `.slp/status.md`:
   - `in progress` — briefed to a Peer.
   - `accepted` — you sent `ACCEPT` (`slp-accept-candidate`): the *review* passed. The ticket
     stays **open** and its dependents stay blocked; the candidate goes to the queue of
     `slp-refinery`. (`slp-accept-candidate`'s "pick the next ready task" means a ticket that
     is already on the frontier, never a dependent of this one.)
   - `closed` — `slp-refinery` reports the merge **green** on the integration branch: only now
     set the status or tick the acceptance criteria, then recompute the frontier and brief what
     it releases. This is the one trigger that unblocks a dependent.
   - back to `in progress` — the merge went red or conflicted: `slp-refinery` withdrew your
     ACCEPT with a `REJECT`. The ticket keeps its
     number; its dependents never started, so nothing needs restoring.
   A ticket closed on a merge that can still be undone is the failure this exists to prevent;
   a finished ticket left open invites a re-run. On a `REOPEN_REQUEST` that wins, open a new
   ticket instead of editing the old one — the room works on decisions the tracker records.
6. When the frontier is empty, every ticket is closed or explicitly dropped, and the queue of
   `slp-refinery` is empty, review on two axes
   (`slp-two-axis-review`) before DONE, unless the project law says the workstream is too
   narrow for it. Wide refactors the tickets named: they travel by expand–contract pairs of
   tickets, never by one branch.

## What may change a ticket
Nobody rewrites a ticket in mid-flight: a Peer challenges the brief with evidence
(`slp-challenge-premise`, `REOPEN_REQUEST`); you dispose (`slp-dispose-challenge`). If the
evidence beats the ticket, mark the ticket **superseded** with the reason and its evidence,
and write the replacement ticket. The tracker stays the one home of what the room believes.

## Signals to the Owner
`frontier`: N ready / M waiting, and `DECISION_NEEDED` the moment a blocker is a decision, a
ticket would change the same files as another, or acceptance evidence cannot be written for a
ticket. Do not re-scope silently: the tickets are the contract the Human approved.
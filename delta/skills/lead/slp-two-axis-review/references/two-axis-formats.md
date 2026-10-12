# Two-axis output contracts

The OUTPUT CONTRACT lines each lens brief carries. The lens seat renders whichever the brief
names. Shared rules for both: report per file or hunk; **under 400 words**; separate hard
violations from judgement calls; say which findings you are unsure about; say nothing about
anything you did not actually read; end with `RECAP: <what you did> → <report>`.

## Evidence setup (same in both briefs)

```text
git diff <fixed-point>...HEAD        # three-dot: against the merge-base
git log <fixed-point>..HEAD --oneline
```

## AXIS: standards (the repo's bar, then the baseline)

The contract:

```text
OUTPUT CONTRACT: standards findings —
(a) every place the diff violates this repository's documented coding standards:
    cite the standard as file and rule;
(b) any baseline smell you spot: name it and quote the hunk.
Separate hard violations from judgement calls. A documented-standard breach can be
hard; a baseline smell is always a judgement call.

BASELINE (labelled heuristic, never a hard violation; skip whatever tooling catches):
Mysterious Name · Duplicated Code · Feature Envy · Data Clumps · Primitive Obsession ·
Repeated Switches · Shotgun Surgery · Divergent Change · Speculative Generality ·
Message Chains · Middle Man · Refused Bequest. Each: what it is, then how to fix.
(Kept in step with the smell list in rules/godkit-engineering-standards.md.)
```
The BASELINE block travels inside the brief: a sealed lens cannot read the room's files.

Find the standards first: search the repository for every file that documents how code should
be written (CODING_STANDARDS.md, CONTRIBUTING.md, law, style guides). A documented standard
wins over the baseline; where it endorses something the baseline would flag, say nothing.

How to fix, by example: a name that hides what it holds becomes a rename; the same logic
shape in two hunks becomes one shape both call; a method reaching into another object's data
moves onto the data.

## AXIS: spec (the diff against what was asked)

The contract:

```text
OUTPUT CONTRACT: spec findings —
(a) requirements the spec or a ticket asked for that are missing or only partly done;
(b) behaviour in the diff that was not asked for (scope creep), including anything a
    ticket put out of scope;
(c) requirements that look implemented but where the implementation looks wrong.
Quote the spec or ticket line for each finding, and name the ticket it belongs to.
Check every acceptance criterion in every ticket against the diff, and say plainly which
ones you could not confirm from the diff alone.
```

Read the spec and every ticket first; then diff. Findings in (c) cite the criterion they
doubt and what would settle it (the command to run). You do not need to resolve (c) yourself:
an unverified doubt stated cleanly is a finding.

## Anti-contamination (both axes, and the chair's duty)

The two lenses never see each other's anything. The briefs differ only in ANGLE and OUTPUT
CONTRACT, so no report can be guessed from the brief. After collection, you forward nothing
between them; the fix round brief carries neither report's wording — it carries the accepted
findings, and it says only so much of each as the fixer needs: file, place, what is wrong
there. "Do not merge or rerank findings" is a report rule and a routing rule.
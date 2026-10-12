---
name: slp-tdd
description: "Peer procedure to build a writable ticket test-first: name the seam the spec agreed before any test, red before green one slice at a time, the three anti-patterns by name, the check cadence, and what a test must never be. godkit port of the `tdd` method."
---
# TDD (Peer)

Red → green, one small complete slice at a time. Your brief names the seams the spec agreed;
tests go only at those seams.

## Before any test

1. Name the seam this test observes through: a place you can change behaviour without editing
   in that place. Prefer an existing seam, and the highest seam that reaches the behaviour —
   ideally the spec names one, and the fewest seams win. The test goes through the public
   interface, never through internals.
2. The brief names no seam your ticket needs, or you need a new one → `QUESTION` **before you
   write it** (this is your brief's gap, not a taste call). Do not invent a seam quietly.
3. One test per invariant, per acceptance criterion; for a bug fix, the repro that fails on
   the old code comes first. A test that cannot fail is not a test.

## The loop

- **Red first**: write the failing test, run it, see it fail for the reason you expect; then
  only enough code to pass it. A green written before red proves nothing.
- **One slice**: one seam, one test, one minimal implementation, run, then next. You respond
  to what the last slice taught you; nothing else is happening right now.
- Do not anticipate future tests, and do not add speculative features: an abstraction, layer
  or hook needs the contract or an invariant to require it.
- **Refactoring is not part of the loop.** When you see a better route that keeps the
  contract, take it and say so in the CANDIDATE; when you see work you should not do, note it
  as a suggestion. The reviewer owns the standard.

## The three anti-patterns, by name

- **Implementation-coupled**: mocks an internal collaborator, tests a private function, reads
  state through a side channel (the database instead of the interface). The tell: the test
  breaks on a refactor while the behaviour has not changed.
- **Tautological**: the assertion recomputes the expected value the way the code computes it.
  Expected values come from an independent source: a known-good literal, a worked example, the
  spec's acceptance evidence.
- **Horizontal slicing**: all the tests first, then all the implementation. One test, pass it,
  repeat.

Mocks belong at system boundaries only: an external API, time, randomness, sometimes the
database or filesystem. Never mock your own modules; inject the dependency instead.

## Never write such tests

No tests for wording, formatting, layout, colours, exact output strings, getters or wiring. No
tables of permutations along the same code path. A visual or UI change is verified by running
it, not by freezing its text in a test. Before adding a test, look for one that already covers
the path and extend it: report the test lines you added and removed with your work (one
reason per changed test, as your role file says).

## Cadence

Typecheck regularly; run the single test file regularly; the full suite once at the end, before
`slp-candidate-handoff` freezes the candidate. Real outputs only: a check you did not run is
`NOT YET — not verified`, never "should pass".
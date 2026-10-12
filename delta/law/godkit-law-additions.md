<!-- GODKIT:begin law -->
## GODKIT additions (leave these lines in the law you write)

- Engineering standards bar: read `<ROOM_DIR>/rules/godkit-engineering-standards.md` before
  your first edit; where this law is silent, it is the bar, and the repo's own docs win where
  they are stricter.
- Integration: every accepted candidate lands on one integration branch, one at a time, and
  the check runs after every merge (`slp-refinery` owns this); a red merge is undone and sent
  back, never fixed in place. Name the branch in this law (`- Integration branch: <name>`,
  from <base>) and say whether the Lead may merge to it; the Lead merges only what the law
  authorises. The integration branch never reaches the Human's branch without the Human.
- Closing review: the workstream's last review has two axes on two model families
  (`slp-two-axis-review`); its two reports stay separate, never merged or ranked.
- Tickets are the contract: a ticket is **closed only after its merge is green on the
  integration branch** (`slp-refinery` → `slp-ticket-frontier`); ACCEPT of the work alone
  does not close it. A superseded ticket is marked, not quietly rewritten.
<!-- GODKIT:end law -->

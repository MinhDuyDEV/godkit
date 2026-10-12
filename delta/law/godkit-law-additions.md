## GODKIT additions (leave these four lines in the law you write)

- Engineering standards bar: read `<ROOM_DIR>/rules/godkit-engineering-standards.md` before
  your first edit; where this law is silent, it is the bar, and the repo's own docs win where
  they are stricter.
- Integration: every accepted candidate lands on one integration branch, one at a time, and
  the check runs after every merge (`slp-refinery` owns this); a red merge is undone and sent
  back, never fixed in place.
- Closing review: the workstream's last review has two axes on two model families
  (`slp-two-axis-review`); its two reports stay separate, never merged or ranked.
- Tickets are the contract: on ACCEPT of a ticket's work, the ticket is closed where it
  lives (`slp-ticket-frontier`); a superseded ticket is marked, not quietly rewritten.
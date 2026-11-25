# 2026-11-25 — 0506 `bargain-ten`: ten bargains, five per cent each (dark, proof 208)

The owner (`docs/design/owner-spec-2026-11-25.md`, "Addition", answers 7 and 13 as amended). Plan: section 6, rows 50 to 53 (T2).
Switch `bargain_total_enabled`, false as deployed. No production read was run. Server and types only.

## What 0506 does, lit

- **Ten tries** a company, city, good and real day, through `cmd.haggle` (the one authority, its row, its roll).
- **The chance falls on every try:** p1 x 0.5^(n-1). p1 = 0.25 + her skills + 1 point a NEGOTIATION level from 2 (19 at level 20) + her
  captains, never above 0.50. Expected wins in ten: 0.50 to 1.00.
- **A win is 5 % of her total**, added, buying and selling, applied once, in `world.quote_priced` (`public.bargain_factor`). A lost try
  costs nothing. Nobody else's price moves. The spread is no longer shaved.
- **Negotiation** is a row of the existing level tables, earned by her own tries (5, and 15 more for a win), hidden while dark.
- **Jobs** bargain from Negotiation 8: 3, 6, 10 tries at 8, 12, 16, through `cmd.haggle`, at the job's own trade; `{"bargain": false}` on
  the job turns it off; a job's tries earn no experience. A job's quote prices the EXPECTED bargain; the day's figure
  (`public.run_day`) counts it on the FIRST run only, because a bargain is one trade's.
- **Same-day resale guard:** the day's row is one side only (`E_BARGAIN_SIDE`) and the other side takes back what was given.

## Rows and cost

No table, no cron, no beat step. Dark: none. Lit: at most 10 row updates and 10 HAGGLED events a company, city, good and day (3 before).
A player's own try also books experience: at most 60 a company a day. Per quote that names a fleet: one key probe; with a bargaining job a
handful more. The cities' purses pay 2.5 % (new company) to 5 % (p1 0.50) of bargained turnover on average; a job 2.8 % at level 8 to
4.4 % at level 20, once a day a city and good.

## Verified (local PGlite, a private prefix cache)

- The self-assert (about 0.4 s): 20 hunks in ten bodies, once and reversing; dark identical; every rule above, with the dice made certain
  by the rule's own knobs and the market rows and Lisbon's purse written inside the rolled-back probe.
- Proof 208 (10 markers). Proofs 03, 06, 10, 26, 58, 107, 113, 156, 158, 164, 167, 171, 175, 184, 191, 195, 197 to 200, 207: green.
- Proof 113 counted every perk row; it now leaves out a sea level whose switch is dark (the page does too).
- `rollback-0506.sql` returns the ten bodies to their md5 of before. `tsc -b`; `db.budget`, `news.lint`, `duplication` specs.

## Decided by default (the owner may reverse)

1. A job bargains unless its setting says no.
2. The guard is for the same day: a good bought with a bargain today may be sold there tomorrow at the plain price.
3. An old-kind bargain open when the switch is lit counts 5 % a win for that day.

## Not verified

- Production: the bodies' digests, the size and retention of `haggle_daily` (`before-0506.sql` reads both). Real PostgreSQL: CI.
- The client has no press yet (the Trade tab's slice).

The tenth try (2026-11-25): the draw uses 0.0005 at a first chance of 0.25 (four decimals), never 0; the server serves one decimal. Only the screen rounded to whole per cent:
it now prints one decimal under 10. No floor was added (proof 244 OD_TENTH: each try under the one before, the tenth above nought).

# 2026-11-25 — 0505 `tax-to-thirty`: each city sets its tax 0 to 30 %, and home pays half (dark, proof 207)

The owner (`docs/design/owner-spec-2026-11-25.md`, "Addition"): "Each city will have its own tax, with 0%~30%. Your own country or
the city that has your HQ will provide less tax." Plan: `docs/design/owner-spec-plan-2026-11-25.md` section 6, rows 54 and 55 (T1).
Switch `tax_thirty_enabled`, false as deployed. No production read was run.

## Today (read in the live bodies)

- `world.tax_rate(city, company)` is the one authority of the profit tax's rate: the city's column x `profit_tax_scale`, never above
  `tax_rate_max` (0.20). While the race is on, the mayor's rate replaces it (`cmd.set_tax`: 0 to `tax_rate_max`, once a real day).
- Then her country's standing with the city's holder: her own country pays half (open) or a quarter (closed economy).
- The city that is her home (`public.home_port_of`, her FOUNDED event) gets nothing.

## What 0505 does, lit

- The mayor's dial goes to 30 %: `cmd.set_tax` takes 0 to `public.tax_cap()` = `tax_rate_cap` (0.30, this file's knob).
- Home pays half: in her home city a company pays at most (1 - `home_tax_cut`) of the city's rate. It is the lower of that and what
  her country's standing gives her, never one cut on top of the other (`public.tax_home_half`, called by `world.tax_rate`).
- Own country: as today.

## Differences from the plan, and why

- **`tax_rate_max` is not changed** (the plan raised it to 0.30). It is an owner's knob, and raising it would lift any city whose
  column x 5 is over 0.20. The new cap is this file's own knob and bounds only the mayor's dial. A city's own column still stops at
  `tax_rate_max`, so no "hold every city where it is" statement is needed: no row is written.
- **No rate moves at deploy or at the light.** Only a mayor's own press can take a city above 20 %, and only the home half can
  lower what a company pays.

## Decided by default (the owner may reverse)

1. Home is `public.home_port_of` (the city she was founded in). When HQ cities exist (B3) the same function is the place to widen.
2. The home half applies whether or not the influence race is on.
3. If the switch goes dark after a mayor has set more than 20 %, her rate stays and is served (today's `world.tax_rate` never caps a
   mayor's rate). `after-0505.sql` reads `mayors.over_max` so the owner can decide.

## Rows and cost

No table, no row, no cron. Dark: one switch read more in a `world.tax_rate` that names a company and in `cmd.set_tax`. Lit: one
`public.home_port_of` more (her first FOUNDED event) in a `world.tax_rate` that names a company.

## Verified (local, PGlite, a private prefix cache)

- 0505's self-assert (169 ms): 5 hunks once and reversing; no other function, knob or grant moved; three new functions STABLE and
  server only. Every harbour's rate equal before, after and lit. A matrix of 21 cells on a SEA_PLACE (the city held by her country,
  another, none; open and closed; a mayor's rate set and not; the race off; the purses dark): dark equal cell for cell; lit, the
  city's rate and a company away from home equal in all 21, the company at home pays least(today, half): 8 cells lower, 13 the same.
  The dial: dark 25 % refused; lit 25 % and 30 % taken, 31 % refused.
- Proof 207 (5 markers) at Lisbon through `public.new_house`, `cmd.set_tax` and `public.profit_tax`: on 10,000 d. of profit at a
  mayor's 30 %, a stranger pays 3,000, a foreign company at home 1,500, a Portuguese company at home 1,500 open and 750 closed.
- `rollback-0505.sql` returns both bodies to their md5 of before.

## Not verified

- Production: prod's `world.tax_rate` / `cmd.set_tax` digests, how many mayors hold a rate, whether any column x 5 is over 0.20
  (`before-0505.sql` reads all three). Real PostgreSQL: CI.
- The client: no word was added. "Home: half tax" on the sale face is the client's slice.

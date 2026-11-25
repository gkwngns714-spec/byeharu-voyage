# 2026-11-25: 0515 `management-level` and 0516 `passive-settings` (dark; proofs 219, 220)

Owner: `docs/design/owner-spec-red-2026-11-25.md` R9 and R10; `owner-spec-2026-11-25.md`, PASSIVE METHOD. No production read was made.

## 0515 (`management_level_enabled`, `trade_benefits_enabled`)

- **Management** is a row of `level_skills` (20 levels, short curve, 300 a day). A sail of 20 miles or more by a fleet with a running job
  gives 5. It locks nothing; the self-assert fails if any body but the wage, the wait and the grant names it.
- Its benefits (decided by default): every fleet's crew wage 2 % less at 4, 8, 12, 16, 20; a waiting job asks again 6 % sooner at 3, 7, 11,
  15, 19, never under 600 s.
- **Trading** gets two more benefits. `trade_profit`: 1 point at 4, 8, 12, 16, 20. It is a cut of the CITY'S TAX ON PROFIT, one figure in
  `world.tax_rate` (so 0507's buy tax, a tenth of it, falls too); a city keeps at least half its rate. `trade_bargain`: 1 point of the
  first bargain's chance at 2, 6, 10, 14, 18.
- **What Trading opens today, and keeps:** a fleet at 3 and 6; a route at 2, 7, 11, 15, 19, a ship a fleet at 4, 9, 13, 17, the yard's fee at
  5, 8, 10, 12, 14, 16, 18, 20 (0468); titles and their seas, captains' ceilings and promotions (0411). Client: `levelGate.ts` hides
  Academy, Craft and Invest under Trading 5 while 0468 is lit (kept). 0417 and 0453 give Trading nothing.
- **The world's sum** (proof 219): one job's run sold for 2,640,755 either way. Tax 382,547 becomes 255,031, wages 8 become 7: she keeps
  127,517 more, the cities get 127,517 less, and all companies plus all cities moved 0.

## 0516 (`passive_settings_enabled`)

- A fixed job may carry `under`, `over`, `crew`, `days`, `stop_profit`, `stop_damage` (repeat or `times` is 0492's). No level is asked.
- Out of range it WAITS ("buys at 391.30, your limit 195.65") in the same branch of `fleet_job_note` as 0498's "prices low". A STOP rule
  stops it: `E_STOP_PROFIT`, `E_STOP_DAMAGE`; a job stopped for her hull starts again by itself once mended (`fleet_jobs_due`).
- With `over` the sale is its own step, judged where she sells; out of range she keeps the cargo and waits.

## Verified (local PGlite, private cache)

Self-asserts about 0.25 s and 0.5 s. Proofs 219 (5), 220 (7), and 107, 113, 171, 200, 207, 208, 209, 212 green. With 0499, 0500 and 0508 stacked
under them too: every file applies, 219 and 220 green.

## For the lead

0508 prepends a PROVISION line before BUY, and 0502's guard then writes its cut BUY over line 0 (the PROVISION). That is between 0502 and
0508, on their branches; 0516 adds its lines after the guard.

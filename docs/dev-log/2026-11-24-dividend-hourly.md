# 2026-11-24 — 0495 `dividend-hourly`: dividends are paid every hour (dark, proof 198)

The owner, row 373: "investing will give you dividends every hour". Design: `docs/design/hq-corp-2026-11-24.md` D6 (there numbered
0494; the numbers moved up), `docs/design/hq-corp-economy-2026-11-24.md` section 9. Switch `dividend_hourly_enabled`, false as deployed.
No production read was run for this slice.

## What happens today (read in the live bodies)

- `public.tick_city` runs at :37 every hour. Its step 6 calls `public.city_coupons` for a harbour only when
  `port_treasury.coupon_day` is before today's real day: once a real day.
- `public.city_coupons` adds each row's due to `city_shares.accrued` ("set aside"). It credits no purse.
- The purse is paid only by `public.collect_coupons`, when a fleet of hers makes that harbour.
- So a holder who buys shares and never has a fleet arrive there is never paid. The owner's 461,384 d. of shares earned her purse
  nothing: that is the fault under "investing causes less money".

## What 0495 does, lit

- `tick_city` step 6 (one hunk): every harbour, once per real hour (`port_treasury.coupon_hour`).
- `city_coupons` (one hunk): hands the call to `public.city_coupon_hour` and returns its answer.
- `public.city_coupon_hour(port, at)`:
  - due = `round(public.coupon_day_of(port, holder, all she paid there) / 24)`: at `works_coupon_day` 0.018 that is 0.075 % an hour;
  - payable = least(sum of dues, the city's surplus above its reserve, its profit over the trailing 24 hours / 24), pro rata;
  - paid by `public.city_pays(port, holder, 'DIVIDEND', pay)`: the city's purse to her purse, in one act. No fleet is needed.
- The trailing 24 hours: `port_treasury.profit` (0312: the city's own net, added by the roll) is moved each hour into
  `port_treasury.profit_hours`, a ring of 24 slots, and set to 0. A missed hour is a 0 slot. The cap is the ring's sum / 24.
- `city_shares` is not written. Old `accrued` stays and is collected at arrival by `public.collect_coupons`, untouched.
- Closed economy: every coin leaves that city's purse in the same act; nothing is minted.

## The owner's holding

| 461,384 d. of shares, one hour | paid to her purse |
|---|---|
| the city's trailing 24 h profit covers it (cap >= the dues) | **346 d.** (0.075 %; 8,305 d. a day) |
| she sails for the country that holds the city, race lit (x1.5) | 519 d. |
| the city's 24 hours earned 12,000 d., other holders due 900 d. | 139 d. (her part of 500) |
| the city lost money over the trailing 24 hours | **0 d.**, nothing carried |
| dark (as deployed), no fleet ever arrives | 0 d. to the purse; the day's coupon waits in `accrued` |

## Decided by default (the owner may reverse)

1. The 24 hours and the owed hours live on the purse row (three columns), not in a new table: no new rows.
2. One credit a holder a harbour an hour (her works there are summed): one ledger row, not one a work.
3. A holder is paid from her first hour: no part-hour pro rata.
4. Lock order is the house first, then the harbour (0122). The hour never waits for a holder's row (SKIP LOCKED). A holder who is
   mid-trade at that instant is not paid in that run, **and does not lose the hour**: it is written against her on the purse row
   (`port_treasury.coupon_owed`, `{house: hours}`) and her next due is (1 + hours owed) hourly coupons, inside that run's limits
   (surplus, trailing profit / 24, pro rata). At most 23 owed hours are kept, so an outage cannot build an unbounded lump.
   An hour the city could not pay is still owed to nobody (0312).
   - Not the stamp on `city_shares` (`accrued_day`): it is a game-day number the daily form reads, and writing it needs her share
     rows, which her own buy or collection holds at exactly the instant she is skipped. The purse row is already held by the run.
   - Twice in one hour is impossible: the purse row is read FOR UPDATE and the hour is closed before anything is paid.
5. No event and no news for a paid hour. Holdings (`world.holdings` `paid`) and the Ledger's Dividends line (`company_rate_for`, 0493)
   already read ledger kind DIVIDEND, so no client change and no new word.
6. If the switch goes dark again the daily form resumes; its first day pays at most one day's coupon from the profit since the last
   paid hour (a holder can get up to one extra part-day, bounded by that profit and the surplus).

## Rows and cost

H = harbours with a purse (254 in the chain's world). P = holder-and-harbour pairs paid in the hour (prod: `before-0495.sql`, `load`).

| table | dark | lit, an hour |
|---|---|---|
| port_treasury | as today | H row updates (the ring), plus one for a harbour whose owed hours moved |
| ledger | as today | P rows (DIVIDEND) |
| treasury_flows | as today | P rows, rolled into the daybook by the next hour |
| stats_live_deltas | as today | 2 P rows |
| players | as today | P purse updates |
| city_shares | every row once a day | 0 |

At most (H + 5 P) / 60 rows a minute, in one run at :37. Nothing while dark.

The tick, local PGlite, 254 harbours, 2 pairs (proof 198's notice, three runs): step 6 dark **0-1 ms**, lit **58-94 ms**, the same
hour again 0-1 ms (204 -> 262 ms for the whole tick in the first run). Not measured on real PostgreSQL or with prod's number of pairs.

## Verified

- 0495's self-assert (185 ms local): hunks once and reversing; no other function, knob or grant moved; three new functions server
  only (public, anon, authenticated, service_role); DARK IDENTICAL (one daily scene before and after: every figure, row and flow
  equal, no hourly state); thirteen lit scenes on a probe that stands on a SEA_PLACE (no real purse, holder or lock touched).
  The carry in four of them, DRIVEN DIRECTLY (the scene writes the owed hours a skipped run would write): one owed hour pays
  2 x 346 = 692 and clears; under a 500 limit 217 / 283; 99 owed hours count as 23; a city with nothing to pay keeps them owed.
- Twice in one hour: every scene runs the hour a second time (0 paid, no entry moved); proof 198 runs the real tick twice in the
  hour and calls the rule again by itself (0 paid).
- Proof 198, 9 markers (DH_CARRY: the real tick pays an owed hour once and clears it): the REAL `tick_city` over the whole world; a house with no fleet buys through `public.invest_for` and is paid
  by the tick; 461,384 d. -> 346 d. and 0 d.; once an hour; the trailing 24 hours; the world's sum unchanged; old `accrued`.
- Proof 22 (0312's daily coupon) still 8/8 with 0495 applied, dark.
- `rollback-0495.sql` run locally: both bodies return to their md5 of before 0495.
- `tests/db.budget.spec.ts`, `tests/news.lint.spec.ts`, `npm run db:check-versions`.

## Not verified

- Nothing on production (no read was run): prod's `tick_city` / `city_coupons` digests, the number of pairs, the tick's real cost.
- The two-session test below has NOT been run: this machine has no PostgreSQL, Docker or psql, and the branch has no PR, so CI
  has not run it either. Its SQL ran on the local PGlite world (one session: scene, dues, the hour, the figures), and its bash ran
  against a stand-in psql (green, skipped, and three red cases). Its first real run is the PR's `disposable-chain`.
- `public.tick_city` itself under two sessions (the test calls `public.city_coupons`, the tick's own call for a harbour).
- Real PostgreSQL: CI's disposable chain.

## Two sessions, on real PostgreSQL (2026-11-25, branch `dividend-race`)

`scripts/ci/dividend-race.sh`, run by `disposable-chain` (migrations-apply-proof.yml) with psql sessions, only when
`public.city_coupon_hour` exists (else it prints SKIPPED). Three markers:

- `DIVIDEND_RACE_SKIPPED_HOLDER_OWED`: a second session holds holder a's `players` row; the hour runs in under its 5 s lock limit
  while the row is still held, pays b alone, and leaves `coupon_owed = {a: 1}`.
- `DIVIDEND_RACE_OWED_HOUR_PAID_ONCE`: the next hour, a free, pays her two hours' coupon and clears the entry.
- `DIVIDEND_RACE_SAME_HOUR_PAYS_ONCE`: a first caller runs the hour and keeps its transaction open; a second caller of the same hour
  is seen blocked by it (`pg_blocking_pids`), then answers the closed hour (paid 0, no cap); purses, ledger rows and the city's purse
  show one payment.

Each step waits for `pg_stat_activity` to show the other session where it must be: no timed sleeps.
It commits (a second session sees only committed rows), so it refuses any database not on 127.0.0.1 / localhost and runs AFTER the
snapshot is kept, on the stack the next step throws away; where the keep step stopped the stack (main, a PR from zero) the volume
is booted again first (a boot more on those runs, not measured). Nothing about the snapshots, the prefix cache or the from-zero rule
changed (`select-specs`: "from zero allowed (cold): no").

Read before writing the test, 0495 unchanged: (a) is right as written (the skip takes no lock of hers; the purse row is the run's own);
(b) is right under READ COMMITTED (the second caller's `FOR UPDATE` re-reads the committed purse row). In the real tick two runs
already queue on the purse rows in steps 1 and 3, and the harbour's advisory lock is waited for at most the tick's 2 s.


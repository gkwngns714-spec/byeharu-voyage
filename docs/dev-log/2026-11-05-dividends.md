# 2026-11-05 - Dividends are paid from profit (migration 0312)

Branch `dividends-0312` · migration `supabase/migrations/20260818000312_dividends_are_paid_from_profit.sql` · proof `scripts/db/proofs/22_dividends.sql` · mutation harness `scripts/ops/harness/dividends/proof-0312.mjs`. Prod head when cut: 0310; 0311 (#494) deploys first and touches neither body. **Not deployed** (PR only). Alters live play: after-checks below.

## The order
Owner, 2026-11-05 ("yes do all"): city purses must rise; fix dividends. Rate back to the designed 9 % of `paid` a real day, unable to drift when the clock changes; paid only from the day's profit; a loss day pays nothing; nothing owed; old `accrued` untouched.

## The proven cause (prod, read-only, 2026-11-05 ~07:30 UTC)
The brief's cause, "the rate was never rescaled", is true but is not the whole story. Three things stacked:

1. **The rate.** The live step 6 of `public.tick_city` (hourly, :37) was `due = paid × works_coupon_pct × (today − accrued_day) × influence mult`, with `payable = least(Σ due, city_surplus)`. `works_coupon_pct` 0.003 (last changed 10-15) was "9 % a real day" at 30 game days a day. `game_day_seconds` went 2880 → 60 by hand (`updated_at` 2026-10-30 00:11:35 UTC, `docs/dev-log/2026-10-30-drift-every-minute.md`), so it became 0.003 × 60 = 18 % an hour, **432 % a real day**. The 84 % measured is not a rate: it is `city_surplus`, the only limit left, biting.
2. **The sweep, a cause the brief did not name.** `world.game_day()` is epoch / `game_day_seconds`, so the same change moved "today" by about 29 million days and `(today − accrued_day)` paid 29 million days at once. The 00:37 tick of 10-30 paid **1,075,213,011 d.**, every city's whole surplus, against 164,253 d. the hour before. Rescaling the rate alone would leave this trap armed.
3. **The purses.** 0302 multiplied them on 11-02, which refilled the surplus.

| Day (UTC) | DIVIDEND flows (`stats_city.flows`) |
|---|---|
| 10-24 to 10-29 | 4.8 M to 7.5 M a day |
| 10-30 | 1,146 M (1,075 M in one tick) |
| 11-02 | 951 M |
| 11-03 | 752 M |
| 11-04 | 592 M |

10-31 is missing from the table: the count job was failing then (`docs/dev-log/2026-10-31-stats-timeout.md`).

Last daily record: `paid` 693 M; DIVIDEND −585 M; net of all cities −378 M.

## What was built
- **One knob:** `works_coupon_day` 0.09 of `paid` per REAL day; `works_coupon_pct` is gone. It does not contain the clock. 0 pays nothing.
- **`port_treasury.profit`:** the city's own net since its last coupon, added in the roll. **Not the daybook:** `treasury_days_kept` is 30 game days, 30 minutes today, so step 2 CARRY has eaten half an hour-old roll before step 6 runs.
- **`port_treasury.coupon_day`:** the real (UTC) day of its last coupon.
- **`public.city_coupons(port, now)`:** the coupon, moved whole from step 6, the one place it is computed. `payable = least(Σ due, city_surplus, profit)`, pro rata as before. Due uses `(today − accrued_day) × game_day_seconds / 86400`, floored at 0 and capped at the days since the last coupon, so a day-number jump can neither sweep a purse nor stop a coupon.
- **`public.flow_is_profit(kind)`:** the one list. **`public.real_day(at)`:** the day number.
- **`public.tick_city`:** 3 hunks, each occurs once on the live body (checked against prod's text) and reverses.

### Decided by default (the owner may reverse)
- **Once a real day, at the first tick of a new UTC day (00:37 UTC, 09:37 KST), not hourly.** Hour-by-hour cannot hold the rule: hour 1 earns 100 and pays it, hour 2 loses 100; the day netted 0 and paid 100.
- **Nothing owed, nothing carried.** Each period closes at profit 0, whether it paid, lost or had profit left over.
- **First period:** opens at deploy; first payment at the next 00:37 UTC, on a short period.
- **CONVOY_LOAD / DELIVER / RETURN are out of profit too**, beyond the owner's four: dark today, but they are the same aid by ship.
- **DONATION and SHARE count as income**, per the owner's words. Note that 159 M of the 208 M a day below is DONATION. It changes the estimate little (11.7 M → 9.5 M) because the surplus limit bites first. To take them out is one word in `flow_is_profit`, and 0313 (merchants buying shares) makes SHARE worth a look: new share money could then pay old holders.

## Estimate (prod, last daily record; 236 harbours with holders)
| | Now | After |
|---|---|---|
| Dividends a day | 585 M | **about 12 M** (62 M due at 9 %) |
| All cities' net a day | −378 M | **about +196 M** |

- Why 12 M and not 62 M: 48 harbours pay the full coupon; 74 made a loss and pay nothing; 9 are cut by a low profit; 105 by the surplus limit. With ample surplus it would be 33 M, so 12 M is a floor that should rise as purses recover.
- Per harbour (a day, now → after): HAV 29.4 M → 0, MAC 28.5 M → 0.47 M, BNT 27.7 M → 0, COL 26.6 M → 0.37 M, PRT 25.0 M → 0.40 M, MAK 21.9 M → 0.30 M, CAD 18.4 M → 0.43 M, PAL 17.0 M → 0.
- **Holders: 750 houses, all merchants. No human player holds a share.** `accrued` 1.53 B d. stays theirs, collected at arrival. Merchants lose about 573 M a day of dividend income: the biggest effect of this change, and its knock-on on their laps and investing is not measured.

## Readers and words
- `world.town_hall`: reads `city_shares` (`paid`, `accrued`) and the daybook, no rate. Its `day.out.DIVIDEND` ("Coupons" in the hall) is the last full game day, one minute: it showed a figure one minute an hour and will show one minute a day. Still true, so no client change.
- Invest (`world.holdings`), Stats (`stats_city.flows`, "Dividends set aside"), `collect_coupons`: no rate, no change; the daily figure simply stops spiking hourly.
- `works_coupon_pct` was read by `tick_city` alone (searched every live body on prod). `accrued_day`: `tick_city` and `invest_for`.
- Docs: `docs/ECONOMY_LOOP.md` (rule, step 6, knob, lever), `docs/INFLUENCE.md`.

## PROD CHECKS (pure SELECTs from a file, one statement per file, before deploy)
Deploy after 0311, and not within two minutes of :37 (the file takes `port_treasury`'s lock).

```sql
select max(version) from supabase_migrations.schema_migrations;   -- 20260818000311
```
```sql
select (select value from public.world_config where key = 'works_coupon_pct') as old_rate,                     -- 0.003
       (select value from public.world_config where key = 'game_day_seconds') as gds,                          -- 60
       (select count(*) from public.world_config where key = 'works_coupon_day') as new_rate_rows,             -- 0
       (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'port_treasury'
         and column_name in ('profit', 'coupon_day')) as new_cols,                                             -- 0
       to_regprocedure('public.city_coupons(uuid,timestamp with time zone)') as fn;                            -- null
```

## The 30-minute after-check (T = the deploy instant; one tick must have passed)
```sql
select (select value from public.world_config where key = 'works_coupon_day') as rate,                         -- 0.09
       (select count(*) from public.treasury_flows where kind = 'DIVIDEND' and created_at > 'T') as dividends, -- 0
       (select count(*) from public.port_treasury where coupon_day <> public.real_day(now())) as not_stamped,  -- 0 (until the next 00:37)
       (select count(*) from public.port_treasury where profit <> 0) as cities_with_a_period,                  -- most of them after one roll
       (select sum(profit) from public.port_treasury) as profit_so_far,
       (select sum(ducats) from public.port_treasury) as purses;
```
Also: `cron.job_run_details` for `byeharu-voyage:city` says succeeded, and the slowest tick is no longer than before.

## The next-roll after-check (the first 00:37 UTC after deploy)
At about 00:30 UTC save `select port_id, profit from public.port_treasury where profit > 0`. Then, between 00:38 and 01:36:
```sql
select count(*) filter (where t.coupon_day <> public.real_day(now())) as not_stamped,                          -- 0: step 6 ran with no error
       sum(f.d) as paid,                                                                                       -- under 62.4 M; expect about 12 M or less, the period being short
       count(*) filter (where f.d > 0.09 * coalesce(s.paid, 0) + 1) as over_the_rate                           -- 0
  from public.port_treasury t
  left join (select port_id, -sum(ducats) as d from public.treasury_flows where kind = 'DIVIDEND' group by 1) f on f.port_id = t.port_id
  left join (select port_id, sum(paid) as paid from public.city_shares group by 1) s on s.port_id = t.port_id;
```
Each harbour's paid must also be at most its saved `profit` (the roll is hourly, so nothing is added between 00:30 and the tick except that tick's own roll: allow for it). A day later, in the Stats city daily record: DIVIDEND about 12 M, and all cities' net above zero.

**Red, and act:** any `not_stamped`, any over the rate or over its saved profit, or merchants' laps falling sharply: stop with the rollback below and tell the owner.

## Forward rollback (owner only, a NEW migration at prod head + 1)
Stop paying at once (the next 00:37 is then 0, periods still close):
```sql
update public.world_config set value = '0' where key = 'works_coupon_day';
```
A lower or higher rate is the same line. Back to the old rule: a new file that swaps this file's hunk arrays (`v_new` → `v_old`), restores `works_coupon_pct`, and first sets `accrued_day` to the current game day. That brings back 432 % a day, limited only by the surplus, so it is not advised. Dividends already paid stay paid.

## Tests
- `BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/dividends/proof-0312.mjs`: from the cached world at head 0310 (295 of 295 restored, nothing from zero), **18 of 18 mutations red, then the real file and proof 22 green**: no profit limit, a rate per game day, the uncapped and the unfloored day number, no surplus limit, a loss carried, no reset, the shortfall accrued, old accrued wiped, twice a day, aid and cargo aid as profit, the wrong rate, the roll adding nothing or adding aid, an hourly tick, hunk drift, hunk reversal.
- The first run failed on a real error (a probe house's nation was not a great power): fixed. Three mutations then went red for a different true reason than first written (the surplus one is refused by `E_CITY_BROKE`, the twice-a-day one by "two missed days", the wrong-rate one by the knob check): their expected reasons were widened, and each still fails the file.
- `scripts/db/proofs/22_dividends.sql`: the real `tick_city` over the whole world at both clocks, 7 of 7 markers through `proof.mjs`.
- The three hunks were checked against prod's own `tick_city` text: each occurs once.

## Not verified
- Nothing is deployed; no prod `tick_city` has run this code. The harness world is the chain, not prod's data.
- The estimate is one last-24-hours record; purses will move once dividends stop draining them.
- The knock-on for merchants: not measured. Nor is how fast purses recover.
- Whether the full CI suite is green: see the PR.

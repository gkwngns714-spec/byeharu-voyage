# 2026-11-05 - The game-day audit: a day is a day (migration 0317)

Branch `a-day-is-a-day` · migration `supabase/migrations/20260818000317_a_day_is_a_day.sql` · proof `scripts/db/proofs/26_a_day.sql` · mutation harness `scripts/ops/harness/a-day/proof-0317.mjs`. Prod head when read: 0313. Deploys after 0314, 0315, 0316: rebase then. **Not deployed** (PR only).

## The fault
`game_day_seconds` went from 2880 to 60 by hand on 2026-10-30 (owner order: "change the tick time of whole economy, market related areas", `docs/dev-log/2026-10-30-drift-every-minute.md`). So one game day is one real minute. The market was meant to tick that fast. Everything that printed "day", "today" or "yesterday" to a person, or that needed a window longer than the hourly city tick, was not.

**How this was read:** every live function body on prod at head 0313 (706 functions, `pg_get_functiondef`, 40 name `game_day`, 188 carry a day word), all 316 knobs, the cron table, views and column defaults (none name `game_day`), then `src/`. Prod reads were pure SELECTs, one statement per file, stable functions only.

**The three clocks:** game day = 60 s. Voyage day = 86,400 / `time_compression` 960 = 90 s, not touched on 10-30 and not in this audit's fault. Real day = 86,400 s, `public.real_day`.

## The table: bugs, fixed in 0317

| Item | Where | Real meaning today | Proof | Fix |
|---|---|---|---|---|
| Report Day and Week | `world.report` | Day = one minute, Week = seven minutes. All = one bar a minute since August | body; `v_span` × `world.game_day` | Real UTC days. Today = since 00:00 UTC, Week = 7 UTC days, All = a bar a day |
| Stats "what you made" | `src/features/stats/Me.tsx`, reads `world.report('week')` | Seven minutes | same read | Same fix |
| Dividends paid today / yesterday | `world.holdings` (Invest) | This minute and the last one. Coupons pay once a day (0312), so nearly always 0 | body | Real UTC days |
| Town hall "Yesterday" | `world.town_hall.day` | The last minute of a daybook rolled once an hour: for most minutes nothing, and the panel hides | daybook on prod 09:36: minutes 29897767-796, today 29897856, rolled an hour ago | The count's last 24 hours (`stats_city.day`), label "Last day" |
| Market "Today: N units" | `public.traded_today` via `world.price_why` | This minute. "No trades here today" was false most of the time | body; merchant `trade_daily` rows are deleted every minute (`npc_compact_houses`) | 24 hours of `stats_city_good`; label "Last day"; the company count goes, no store keeps it |
| Haggle: 3 tries "today", the bargain lost "at the day's end" | `cmd.haggle`, `cmd.do_buy`, `cmd.do_sell`, `haggle_concession`, `haggle_odds`, `world.haggle_state` | 3 tries a minute; a bargain dies in under a minute | body. `haggle_daily` has 2 rows, the last 2026-09-14: no economic effect | Real UTC days; column `game_day` is now `day` |
| Fairs | `tick_buff_calendar`, `buff_season_of`, `world.buffs` | 4-minute fair, 30-minute season. A ship cannot reach one. Prod: all 55 rows are 240 s | `active_buffs` on prod | `duration_seconds` 11,520 (3.2 h), `season_seconds` 86,400: the design's values, fixed in seconds. Same share of harbours in a fair (12 % × 4/30 = 1.6 %), so the average spread does not move |
| Crown tax | `city_day` reads `treasury_daybook` | Pays on the last 30 minutes of each hour: CARRY (step 2) ate the rest before step 6b | CROWN_TAX / non-capital TAX: **5.49 %** on 11-03, **5.21 %** on 11-04, knob 10 % | `port_treasury.tax_unshared`, added in the roll, as 0312 did for `profit` |

**Moves the economy, measured:** only the crown tax. 11-04: 29.39 M d. of non-capital TAX, 1.53 M d. shared, 2.94 M d. due. So about **+1.4 M d. a day** from cities to their capitals, 0.06 % of the 2.2 B d. a day of SELL, nothing minted. Capitals fund crown aid (20 M d. on 11-04), so it comes back to short cities.

**Report's All:** at a minute a bar its axis is about 110,000 rows from August, with a correlated read per row. Not timed on prod (the read needs a signed-in company). Real days make it about 80 rows.

## The table: balance choices, left for the owner

| Item | Today | If it became a real day, measured | Why left |
|---|---|---|---|
| **`treasury_reserve_days` 3** | 3 busy minutes of SELL: 7.9 M d. in all, median 14,162 d., 45 harbours at 0 | Reserves 6.66 B d., median 10.0 M d. (purse median 44,249 d.). Cities under reserve 74 → **208 of 246**. Mean sale bid 0.894 → **0.594** (trade-weighted 0.950 → 0.669). Every spender reads the surplus: aid, coupons, requests, insurance | Sale bids would fall a third at once. The owner's call. A middle value needs the daybook below |
| **Daily cap** `daily_cap_fraction` 0.35, `trade_daily`, `world.daily_cap_remaining` | 35 % of target per house, port and good **a minute** | Last 6 hours: 18,626 trades, 9,678 (house, port, good). 910 pass a whole real day's allowance within those 6 hours; **444,285 of 2,586,824 units (17 %) would be refused** in 6 hours alone. Today 423 of 18,230 house-minutes reach the cap. At the old 48-minute day: 0 refused | Listed on 10-30 as moved with the market. A real-day cap would stop merchants' laps. The server's words still say "the day's allowance" |
| Merchant lap floor, `v_day_h` in `npc_plan` | 1 minute | Follows the daily cap: the same decision | Moves with the cap |
| **`treasury_days_kept` 30** | The daybook keeps 30 minutes (9,444 rows) | Keyed by minute, 30 real days = about 13.6 M rows. Keyed by real day, `city_sell_outflow` turns into the row above: the reserve jumps | Decide with the reserve. Nothing a person reads depends on it after 0317 |
| `city_earnings` × days | Dark: `economy_closed` is true, so nothing pays. If reopened, 30 game days each hour = 720 a real day (design 30) | | Armed but dark. Must be rescaled before the economy reopens |
| `city_seed_days` 10 | 10 busy minutes. Read only by `city_treasury_switch` | No live effect | Dark |
| `standing_route_laps_per_game_day` 1, `cmd.run_standing_route` | A player's route may start a lap a minute (was 48 min) | 1 player route, 0 laps in 24 h; merchants' pace is 0 | No effect today; owner's pace |
| Restock and production, `stock_after`, `restock_r0/r1`, `tick_market_drift` | Rate a minute. Prod rate 0.03 to 0.256, median 0.138: half refilled in about 5 minutes (slowest 23) | | Owner-directed on 10-30: this is "the market ticks every minute" |
| `drift_slot_seconds`, theta, sigma | A minute | | Owner-directed on 10-30 |
| `contract_deadline_days` 1440 | 24 h, true (0311), only while the clock is 60 s | | Correct today. Brief: already fixed. Moves if the clock moves |

## The table: correct, no change

| Item | Clock | Note |
|---|---|---|
| Dividends `city_coupons`, `works_coupon_day` | Real | 0312 |
| Requests `tick_contracts`, `world.contracts`, `expires_at` | Game days scaled to 24 h | 0311. `days_left` is served but no screen reads it |
| Population tax, `population_tick` | Real UTC | Own `floor(epoch / 86400)`, same as `real_day` |
| Influence `influence_day_cap`, `influence_decay`, `fame_per_mayor_day` | Real | Daily job 00:47 |
| Skill points `skill_sp_day_cap` | Real UTC | |
| Gifts, country change, tax change, 7-day reads in Stats, `route_earnings`, price and stats tiers, homesick | Real | Intervals in real time |
| Wages, food, water, `wages_owed_cap_days`, `route_rest_voyage_days`, endurance, voyage risk | Voyage day (90 s) | `time_compression`, untouched on 10-30 |
| Restock and depth steps `restock_day`, `depth_day` | Hourly | Called from the hourly tick both before and after 10-30 |
| Glut `glut_half_life_hours`, `invested_half_life_hours` | Real hours | |
| `perishable_pct_day` | None | Served, no rule reads it |
| Inn guests | Real minutes | `world.inn_shift`; `game_day` is only echoed |
| `stats_recent`, `stats_world.game_day` | Internal map | A difference of two maps, no person reads a day |
| `run_manifest`, `price_path` | Internal | A receipt stamp; a forecast that walks the same ticks |
| `world.books` | Dead | Revoked from `authenticated`, the client does not call it. Not changed |
| Top bar date `gameToday` | Display | A game month per real day, separate from the server's day since 10-30. Printed date unmoved; its false comments corrected |

## Decided by default (the owner may reverse)
- **UTC days**, as 0312, `population_tick` and `stats_bucket`. In Korea a new day starts at 09:00.
- **Town hall and market use the last 24 hours, not "yesterday".** The hall is read every second, so it takes one row (`stats_city.day`), up to 15 minutes old.
- **The market line drops "by N companies".** Merchant rows of `trade_daily` live under a minute, and keeping them a day means about 73,000 more rows beside the busiest write in the game.
- **Fairs go back to the design's real length** rather than being rescaled to anything new.
- **A running fair ends at deploy** (5 of 55 live when read): the old rows carry season numbers of the old clock.
- **Haggle rows are cleared at deploy:** 2 rows from September.

## What was built
- **`port_treasury.tax_unshared`:** added in the roll beside 0312's `profit`, read and set to 0 by `public.city_day`. It starts at 0: no back-payment.
- **`haggle_daily.day`** (was `game_day`): `public.real_day(now())` in `cmd.haggle`, `cmd.do_buy`, `cmd.do_sell`, `public.haggle_concession`, `public.haggle_odds`, `world.haggle_state`.
- **`buff_kinds.duration_seconds`, `season_seconds`:** `public.buff_season_of` and `public.tick_buff_calendar` read seconds, `world.buffs` serves them. `game_day_seconds` is no longer read there.
- **`public.traded_today(port, good)`** answers one number, from `stats_city_good`.
- **`world.report`, `world.holdings`, `world.town_hall`, `world.price_why`:** real days; the wire key `game_day` is now `day`; the hall's `day` is `{in, out}`; `volume` is `{units}`.
- 43 hunks on 14 functions, each once and reversing. Checked against prod's own text at head 0313 as well as the chain's.
- **Client:** Today / Week / All; voyage rows print a date ("11-05"), not "d29897856"; Invest needs no change; the hall says "Last day"; the market says "Last day: N units". EN and KO. `src/lib/format/time.ts` comments corrected. `docs/ECONOMY_LOOP.md` knob and hall shape.

**Old clients:** the client publishes minutes after the push. A tab open across it reads `day` where it wants `game_day`: bars without a key and the market line without a company count, until reload. Accepted: no money path.

## PROD CHECKS (pure SELECTs from a file, one statement per file, before deploy)
Rebase on 0314-0316 first. Not within two minutes of :37 (the file takes `port_treasury`'s lock). Re-read 2026-11-05 after the merge of main: 0314, 0315 (#504) and 0316 (#499) were searched for all 14 names and none of them replaces or patches any of the 14 bodies (0315 only calls cmd.do_sell and adds cmd.do_sell_answering; 0316 only reads public.city_day's table rows). The md5 below is still the one to confirm on prod. If the md5 differs, cut the hunks again against the live body.

```sql
select (select max(version) from supabase_migrations.schema_migrations) as head,   -- 20260818000316
       md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text)) as bodies_md5,   -- e94106d8d85db4b4d8de1fa4e1842930
       count(*) as bodies   -- 14
  from pg_proc p where p.oid in ('public.tick_city(timestamp with time zone)'::regprocedure, 'public.city_day(timestamp with time zone)'::regprocedure, 'public.tick_buff_calendar(timestamp with time zone)'::regprocedure, 'world.report(text)'::regprocedure, 'world.holdings()'::regprocedure, 'world.town_hall(uuid)'::regprocedure, 'world.price_why(uuid,uuid)'::regprocedure, 'world.buffs(uuid)'::regprocedure, 'world.haggle_state(uuid,uuid)'::regprocedure, 'cmd.do_buy(uuid,jsonb)'::regprocedure, 'cmd.do_sell(uuid,jsonb)'::regprocedure, 'cmd.haggle(uuid,uuid,text)'::regprocedure, 'public.haggle_concession(uuid,uuid,uuid)'::regprocedure, 'public.haggle_odds(uuid,uuid,uuid,uuid)'::regprocedure);
```
```sql
select (select count(*) from public.haggle_daily) as haggle_rows,                                -- 2
       (select count(*) from public.buff_kinds where season_game_days is not null) as calendar,  -- 1
       (select count(*) from public.active_buffs) as buffs,                                      -- about 55
       (select value from public.world_config where key = 'crown_tax_share') as crown_share;     -- 0.1
```

## The 30-minute after-check (T = the deploy instant; one :37 tick must have passed)
```sql
select (select count(*) from public.active_buffs where ends_at - starts_at <> interval '11520 seconds') as short_fairs,   -- 0
       (select count(*) from public.active_buffs) as fairs,                                    -- 0 until the next buff job (*/10), then about 30
       (select count(*) from public.port_treasury where tax_unshared <> 0) as tax_left_open,   -- 0, or a few a harbour skipped under its lock: it carries to the next tick
       (select count(*) from cron.job_run_details d join cron.job j using (jobid)
         where d.start_time > 'T' and d.status <> 'succeeded' and j.jobname in ('byeharu-voyage:city', 'byeharu-voyage:buff-calendar')) as failed;  -- 0
```
Also `bash scripts/ops/health.sh`: no new ALERT.

**A day later:** in `stats_city.flows`, CROWN_TAX out / non-capital TAX for the first whole UTC day after deploy reads **0.10** (was 0.052). Purses at capitals up by about 1.4 M d. a day. Sign in and read Report Today, Week, All, the hall and the market line: not read on the live game here.

**Red, and act:** any failed city or buff job, a CROWN_TAX share above 0.10, or a tick error under `day` in the `tick_city` receipt: the rollback below, and tell the owner.

## Forward rollback (owner only, a NEW migration at prod head + 1)
Stop the crown's share at once: `crown_tax_share` to 0. Back to the old rule: a new file that swaps this file's hunks (new to old), restores `public.traded_today` and `public.buff_season_of` from their old bodies, and renames the columns back, with `duration_seconds / 2880`. It brings the faults back, so it is not advised. Crown tax already moved stays moved; `tax_unshared` may stay as an unread column.

## Tests
- `BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/a-day/proof-0317.mjs`: from the cached world at head 0313 (298 of 298 restored, nothing from zero), **20 of 20 mutations red, then the real file and proof 26 green**: the Report at a game day, its bars, yesterday cut short, yesterday too long, the hall empty, the wrong hall row, the market at a minute, the market unbounded, a bargain that dies with the game day, a new game day giving new tries, a fair left at 4 minutes, a season on the game clock, the crown's tax dropped past the daybook (the bug itself: 50,000 d. against 150,000), the tax not closed, every flow as tax, a leaf left open, hunk drift, hunk reversal, a knob moved, another function moved.
- First runs failed on the proof's own probe rows (required columns) and two wrong expectations of mine: yesterday's net is 43, and the second tick's share reads as no flow. One mutation first survived because the date window already held it: it now moves the window too.
- `scripts/db/proof.mjs` with 0317 applied by its own runner: proofs 03 (12 of 12 markers), 06 (10), 13 (5), 16 (5), 17 (5), 19 (9), 22 (8), 26 (7), all green. Proofs 03, 06, 13 and the two rpc specs below changed with the wire.
- `scripts/db/proofs/26_a_day.sql`: the real doors as a signed-in company, the real `tick_city` and `tick_buff_calendar` over the whole world, at 60 s and 2880 s. Its `ADAY_CROWN` plants 1,500,000 d. of TAX, 1,000,000 of it 50 minutes old.
- Every hunk checked against prod's own text (head 0313) as well as the chain's.
- `vite build` with the world image at 0317, `tsc` app and tests, `eslint` on the touched files: clean. `tests/rpc.surface.spec.ts` and `rpc.firstSession`: 30 of 30. `tests/rpc.report.spec.ts`, `tests/rpc.holdings.spec.ts`: green.
- `tests/rpc.why.spec.ts` and `tests/format.spec.ts`: 12 fail locally. This PC's Korean locale serves the words: the two read expect English and got "지난 하루: 37개" and "1500년 1월 1일" (the 37 units themselves passed). CLAUDE.md names this; CI reads them in English. The other ten were not read one by one.

## Not verified
- Nothing is deployed. No prod `tick_city` has run this code; the crown's +1.4 M d. a day is an estimate from two days of `stats_city`.
- Merged with main 2026-11-05 (docs conflicts only; no code conflict); the 14 bodies were checked by reading 0314-0316, not re-cut. The mutation harness was NOT re-run (needs the cached world; CI's disposable-chain and proof 26 are the proof). Owner row renumbered 293 -> 294 (#504 holds 293).
- The Report, hall and market screens were not looked at in a browser.
- Whether the full CI suite is green: see the PR.
- Report All's cost on prod, before or after.
- The file's time on prod: its PGlite time is in the harness output, on a world without prod's rows. It writes few rows (one column with a constant default, about 60 rows deleted, one updated), so 45 s is not near.

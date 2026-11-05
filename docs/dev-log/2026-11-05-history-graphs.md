# 2026-11-05 - 0316: graphs by day, week and month, and how much we can store

Owner, 2026-11-05 (row 289): *"beside these, the market data, as well as gold earned data / loss graphs record. i want to be able to see them by days, weeks, months. how much data can we store? i want to optimize data storage, for example just having a record on graph would be enough or something."*

Migration `supabase/migrations/20260818000316_graphs_by_day_week_and_month.sql`. Deploys after 0313, 0314 and 0315: rebase then. Measured read-only on prod 2026-11-05, head 0312, database 2,287 MB, plan 8 GB.

## The answer

**A graph costs about 150 bytes a day per line owner: 55 KB a year for one city, one good or one company.** All four new tables together cost 245 KB a day, 87 MB a year.

| | a day | a year |
|---|---|---|
| The new graph rows (this file) | 245 KB | 87 MB |
| Everything the Stats and price tables keep for ever today | 1,620 KB | 590 MB |
| Both | 1,865 KB | 680 MB |

**How many years fit: about 8.** 8,192 MB less 2,287 MB now, less about 335 MB the hour tiers still fill to (below), leaves about 5,570 MB; at 680 MB a year that is 8.2 years. With the trim knob on (`stats_city_good_keep_days` 8): 390 MB a year, about 14 years. The graph rows alone would last about 64 years.

The saving the owner asked for is real and it has one name: `stats_city_good`, 290 MB a year, half of all the growth, and nothing reads its old rows. See "The trim".

These figures assume today's world: 246 harbours, 629 goods, 840 companies. More companies add 135 B a day each. A busier game does not change them: the rows are per subject, per day. Not counted: human players' own rows in `ledger` and `events`, too few to measure (381 ledger rows since 08-22), and table bloat, which autovacuum holds to about a fifth of a table.

## What is kept today, measured

| Table | Fine | Hourly | Daily | Rows a day for ever | Bytes a row | A day | A year |
|---|---|---|---|---|---|---|---|
| `stats_city_good` | 48 h | 7 d | for ever | 1,618 | 492 | 796 KB | 290 MB |
| `stats_good` | 72 h | 30 d | for ever | 629 | 333 | 209 KB | 76 MB |
| `stats_city` | 72 h | 30 d | for ever | 246 | 505 | 124 KB | 45 MB |
| `price_history*` (1,430 watched pairs) | 24 h | 30 d | for ever | 1,430 | 147 | 210 KB | 77 MB |
| `stats_world` | 72 h | for ever | none | 24 | about 5,000 | 120 KB | 44 MB |
| `stats_merchants` | 72 h | for ever | none | 24 | about 6,600 | 160 KB | 58 MB |

Bytes a row are heap plus indexes: table size over row count, on prod, today.

THE HOUR TIERS STILL FILL, then stop. They hold 30 days and the game has run 16 of them: `price_history_hour` 80 to about 229 MB, `stats_good` 93 to about 211 MB, `stats_city` 57 to about 125 MB. That is the 335 MB above. `stats_city_good` is at its ceiling.

THE BIG TABLES DO NOT GROW. `events` 494 MB, `voyage_events` 220 MB and `ledger` 205 MB hold six hours of merchants and all of a few humans: since the counters began they took 2.96 M, 2.49 M and 2.39 M rows and deleted the same again. `standing_route_laps` 358 MB is capped at 100 laps a route (0301).

## The new rows, measured

`node scripts/ops/harness/history/bytes-0316.mjs`: a year of each table with prod's counts, on the same 8 KB pages, heap plus primary key.

| Table | Rows a day | Bytes a row | A day | A year |
|---|---|---|---|---|
| `history_world_day` | 1 | 247 | 0.2 KB | 0.1 MB |
| `history_city_day` | 246 | 154 | 36.9 KB | 13.1 MB |
| `history_good_day` | 629 | 158 | 96.9 KB | 34.5 MB |
| `history_company_day` | 840 | 135 | 111 KB | 39.6 MB |

## What the charts read, and what is lost as rows age

| Figure | Before this file | What aging loses |
|---|---|---|
| A good's price | `stats_good.mid`, every 15 min for 72 h, then the hour's last, then the day's last | every high and low between readings. Now kept: open, high, low, close |
| City and world flows | `stats_city`, `stats_world` | nothing: a fold adds them |
| A purse, a holder | the same | the readings between; the day's last stays |
| Earned and lost, a merchant | `ledger`, 6 hours, then one `NPC_CARRIED` row | everything: the split, the kinds, the days. Now kept from the deploy on |
| Earned and lost, a player | `ledger`, for ever; world.report reads it each time | nothing |
| The city daybook | `treasury_daybook`, 30 game days = 30 minutes | everything past 30 minutes |

Stats reads: the faces read `stats_world`, `stats_city`, `stats_good`, `stats_merchants` by span (fine 1 day, hourly 1 week and 1 month, daily 1 year and All). `world.stats_city` is the one reader of `stats_city_good`.

## How far back the graphs go

| Graph | From | Good for |
|---|---|---|
| Purses, holders, prices | 2026-10-20 23:51 UTC | one reading a day to 10-23 13:51, then whole |
| Income, spending, profit, printed, burned, sold, bought, volume | 2026-10-23 13:51 UTC | whole |
| A player's earned and lost | the company's first day (08-22 on) | whole |
| A merchant company's earned and lost | 6 hours before the deploy | whole |

## What is gone for good

- **Every flow before 2026-10-23 13:51 UTC.** 0214's old retention kept one 15-minute row of each day (0246 stopped it). Those days draw no flow at all, not a small one: `history_fill_day` writes null.
- **2026-10-30 18:06 to 2026-11-01 15:51 UTC, 45.8 hours.** The Stats count was down in the slowdown. No flow, no purse, no price was written; the graph jumps over the gap. 10-31 has no row.
- **2.8 hours on 10-28** (10:06 to 12:51): the same, shorter.
- **A merchant company's earned and lost before the deploy,** less six hours: rolled into one `NPC_CARRIED` row with no split.
- **A good's true high and low before 2026-11-02 07:51 UTC.** The hourly rows kept the hour's last price, so a backfilled day's high and low are of those last prices, not every reading.
- **Everything before 2026-10-20** in Stats: there was no count.

Two real jumps stay on the lines: the rescale of 10-31 03:08 and the purses of 0302 (11-02). They happened.

## What the file does

Four tables, one row per (subject, UTC day): the one authority of a graph. A week and a month are those rows grouped in one function, `world.history`. No stored week or month: they cannot disagree with the days and cost no bytes. The brief's "one row per (subject, period)" is met for the day; storing the other two would add 18 % and a second writer for nothing a reader could feel. The widest read, 120 months, is about 3,650 rows of one subject in index order. Decided by default.

The rule of a period is `public.history_bucket`. A week is Monday to Sunday, a month a calendar month, both UTC, like `stats_bucket`.

The job is `public.tick_history`, its own cron job at 12, 27, 42, 57: six minutes after each Stats count, so a dead count cannot take it down. Never in the beat.

- **The ledger window** is `(mark, now - 600 s]`, added to `history_company_day`. The mark moves in the same transaction. The lag is there because `created_at` is the writer's transaction start, so a row can commit after its own instant. The ledger is read only.
- **The days** are recounted from the Stats tables. The oldest open day is closed, one a run; today is recounted. A row that did not change is not written. The backfill and the day after a dead job are the same path, so the file itself takes no heavy statement.
- **The trim** runs last, and does nothing at 0.

Earned is money in, lost is money out, by the ledger's sign. So a merchant's purchase of goods reads as lost and its sale as earned; the Net line is what it made. `FOUNDING`, `NPC_REFOUND` and `NPC_CARRIED` are out: capital, capital, and old rows rolled up. A player's days add up to `world.report('all')`: proof 25.

Profit in a city is 0312's `public.flow_is_profit`, so crown aid, dividends and share money are not profit. It is not income less spending.

The read is public for the world, a city, a good and a merchant company. `me` is the caller's own. A player's books are never served to anyone else: `E_NOT_PUBLIC`.

## The trim: off, the owner's call

`stats_city_good_keep_days` ships at 0, and 0 deletes nothing.

**Nothing reads the rows it would delete.** `pg_proc` on prod names `stats_city_good` in four functions. Three write it (`tick_stats`, `stats_compact`, `stats_fold`). The fourth, `world.stats_city`, reads:

- the newest slot, `x.slot = v_slot`;
- the last 24 hours, `y.slot > v_slot - 24 * v_ph`;
- the row at 24 hours, `y.slot <= v_slot - 24 * v_ph order by y.slot desc limit 1`;
- the newest 24 prices of a pair, `order by y.slot desc limit 24`.

One edge: a pair that stopped selling has its last 24 prices further back, and at a keep of 8 days those would go, so its spark would be empty. It sells nothing, and its row is no longer in `detail.goods` unless it still has a row at the newest slot. The floor is 3 days: under that the 24-hour readers would be cut.

Setting it to 8 stops the 290 MB a year. It deletes at most 20,000 rows a run, about 1.9 M a day. It does not shrink the file: Postgres reuses the room. `stats_good` and `stats_city` are NOT trimmed: the 1 year and All charts read their daily rows. Moving those two charts onto the new tables would free another 120 MB a year; not done here.

## Cost of the job, measured on prod

The job's reads were run as plain SELECTs on prod, 3 times each, against a baseline `select 1` of 4.4 to 5.8 s through the CLI. So these are wall clock with about a second of noise, not a stopwatch inside the database:

| Read | Wall clock | Over baseline |
|---|---|---|
| A day of `stats_city`, with its flows, 246 rows out | 5.1 to 5.7 s | up to 1 s |
| A day of `stats_good`, 629 rows out | 5.0 to 5.3 s | up to 0.8 s |
| 15 minutes of `ledger`, 734 rows out from about 6,000 | 4.7 to 4.9 s | up to 0.5 s |
| A past day of `stats_city` (a backfill run) | 5.1 to 5.4 s | up to 0.9 s |
| The ledger's first window, all of it, 845 rows out | 4.4 s | up to 0.5 s |

So a run costs about 2 to 3 s of reads on prod today, and writes about 1,700 rows in a table of its own. It takes no lock on a game table. The real figure comes from `public.history_runs`, kept 7 days, read in the after-check. The Stats count beside it takes 13 s.

## Proof

`node scripts/ops/harness/history/proof-0316.mjs` on the cached world: **32 mutations red, the real file and proof 25 green, 0316 in 158 ms.**

## PROD CHECKS

Before the push. Each is one read-only statement from a file: `npx --yes supabase@2.120.0 db query --linked -f <file>`.

```sql
select max(version) from supabase_migrations.schema_migrations;   -- 0315
```
```sql
select count(*) from pg_class where relname like 'history\_%' and relnamespace = 'public'::regnamespace;   -- 0
```
```sql
select key, value from public.world_config where key in ('npc_retention_hours', 'history_ledger_lag_seconds', 'stats_city_good_keep_days');   -- 6; nothing else
```
```sql
select count(*) from public.stats_world;   -- about 500: the new index is on this
```

Deploy away from :37 and :07. The file runs in milliseconds and takes one index on about 500 rows.

## After-check, 30 minutes after the push

```sql
select at, ms, receipt -> 'phases' as phases, receipt ->> 'ledger_rows' as ledger_rows, receipt ->> 'open_day' as open_day, receipt -> 'past' as past from public.history_runs order by at desc limit 4;
```
Expect a run every 15 minutes, `ms` under 10,000, `open_day` moving a day a run. Above 30,000: stop the job.

```sql
select (select count(*) from public.history_world_day) as world, (select count(*) from public.history_city_day) as cities, (select count(*) from public.history_good_day) as goods, (select count(*) from public.history_company_day) as companies, (select ledger_through from public.history_mark) as ledger_through, (select open_day from public.history_mark) as open_day;
```
Expect `ledger_through` about 10 minutes ago, and about 820 company rows after the first run. After about 4 hours `open_day` is today, and the graphs go back to 10-20.

```sql
select jobname, active from cron.job where jobname = 'byeharu-voyage:history';
```
```sql
select (select count(*) from public.stats_city_good where at < now() - interval '48 hours') as old_rows, (select value from public.world_config where key = 'stats_city_good_keep_days') as keep;
```
`keep` 0, and old rows not falling: the trim is off.

Nothing in play reads these tables, so there is nothing else to watch.

## Forward rollback (owner only, a new migration)

```sql
select cron.unschedule('byeharu-voyage:history');
drop function world.history(text, text, text);
drop function public.tick_history(timestamptz);
drop function public.history_trim(timestamptz);
drop function public.history_ledger_add(timestamptz, timestamptz);
drop function public.ledger_is_earning(text);
drop function public.history_fill_day(date);
drop function public.history_bucket(date, text);
drop table public.history_world_day, public.history_city_day, public.history_good_day, public.history_company_day, public.history_mark, public.history_runs;
drop index public.stats_world_at;
delete from public.world_config where key in ('history_ledger_lag_seconds', 'stats_city_good_keep_days');
```

To stop only the job: `select cron.unschedule('byeharu-voyage:history')`. The client then shows the last days it has. Past six hours stopped, merchants' hours are lost for good; a restart heals everything else.

## Said plainly

- **Report's Day and Week are game days, and a game day has been 60 seconds since 10-30.** `world.report('day')` is one minute, `week` seven minutes. Found here, not touched. The new Report graph is by real UTC days.
- The Stats pages ask `world.history` every second through `useLiveRead`, as the brief says, though the rows change every 15 minutes. It reads at most about 3,650 rows of one subject by primary key.
- Today's point moves every 15 minutes, a Day graph's newest point stands for the day so far, and a company's lags 10 minutes.
- UTC: a day ends at 09:00 Korea time.

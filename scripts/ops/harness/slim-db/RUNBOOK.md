# Slim-db runbook: getting the space back (after 0414)

**Nothing here has been run. Every command below is the owner's to approve.** Deleting rows does not shrink a file: PostgreSQL keeps
the freed space inside the table and reuses it. To make the files small again a table has to be rewritten. This file says which
tables, with what, under what lock, and for about how long.

The sizes are prod's of 2026-11-14 09:50 UTC (`C:\Users\gkwng\dev\slim-db-reads\out\02_relation_sizes.json`). The times are
estimates: a rewrite reads the old heap once and writes the new table, its indexes and the same again as WAL. On this instance's disk
while it is throttled, reckon 5 MB/s; when it is not, ten times that. Each time below is given as "throttled / not".

## 0. Before anything

1. 0414 is deployed and `after.sql` reads as wanted.
2. **Wait for the retention to drain.** A rewrite before the rows are gone copies them.
   - city_wants: 446,000 rows at 2,000 a minute: about 4 hours.
   - stats_city_good: 415,000 rows at 20,000 a history run (four an hour): about 5 hours; and its fine window folds 4 hours a Stats run.
   - the merchants' books at 3 hours: when the compactor's `left` is back to a handful (`health.sql`: `hours_past_cut` under 2).
     If it is not catching up, the owner may raise `compact_budget_ms` from 8000 to 20000 (more transactions a minute, the same short
     hold each; the beat is not made to wait longer) and put it back afterwards.
   - a merchant's laps: one pass of the compactor over every house, about an hour once it keeps up.
3. Run `health.sql` and keep the answer: it is the "before".
4. Free disk: a rewrite needs the new table's size free while it runs, and as much WAL. The largest below is about 200 MB. Check the
   project's disk in the Supabase dashboard first.

## 1. No lock at all: plain VACUUM

Autovacuum already does this. It makes the freed space reusable and never blocks play (SHARE UPDATE EXCLUSIVE: it conflicts only with
another vacuum or a schema change). Run by hand only to hurry it, one table at a time:

```sql
vacuum (analyze) public.city_wants;
vacuum (analyze) public.stats_city_good;
vacuum (analyze) public.standing_route_laps;
vacuum (analyze) public.events;
vacuum (analyze) public.ledger;
vacuum (analyze) public.voyage_events;
vacuum (analyze) public.voyages;
```

After this the database is no smaller, but it has stopped growing. If the owner stops here, that is a valid place to stop.

## 2. No blocking lock: rebuild the swollen indexes

`REINDEX INDEX CONCURRENTLY` builds a new index beside the old one and swaps them. Reads and writes go on throughout; it takes only a
brief lock at the swap. It cannot run inside a transaction: run each as its own statement (psql, or the dashboard's SQL editor, one at
a time). If one is interrupted it leaves an index named `..._ccnew` marked invalid: drop that and run it again.

| index | now | after | time (throttled / not) |
|---|---|---|---|
| `stats_city_good_pkey` | 273 MB | about 12 MB | 30 s / 5 s |
| `stats_good_pkey` | 84 MB | about 22 MB | 40 s / 5 s |
| `voyage_events_pkey` | 86 MB | about 35 MB | 60 s / 8 s |
| `events_created_at` | 74 MB | about 12 MB | 30 s / 5 s |
| `events_player_created` | 55 MB | about 25 MB | 40 s / 5 s |
| `events_pkey` | 49 MB | about 20 MB | 40 s / 5 s |
| `ledger_player_created` | 44 MB | about 14 MB | 20 s / 3 s |
| `ledger_pkey` | 39 MB | about 10 MB | 20 s / 3 s |
| `ledger_ref_event_id` | 33 MB | about 8 MB | 20 s / 3 s |
| `standing_route_laps_window` | 39 MB | about 5 MB | 15 s / 2 s |
| `standing_route_laps_route_started` | 25 MB | about 4 MB | 15 s / 2 s |
| `stats_city_pkey` | 34 MB | about 10 MB | 20 s / 3 s |
| `insured_voyages_fleet_0213`, `insured_voyages_player_0213`, `insured_voyages_pkey` | 42 MB | about 6 MB | 10 s each |
| `city_wants_port_good`, `city_wants_period_port_id_good_id_key`, `city_wants_pkey` | 64 MB | under 1 MB | 2 s each |

```sql
reindex index concurrently public.stats_city_good_pkey;
reindex index concurrently public.stats_good_pkey;
-- ... one statement an index, in the table's order above
```

This step alone gives back about 600 MB and is the safest large gain. Do it first, the largest first, and read the beat
(`after.sql`) between two of them: a rebuild is disk work, and the disk is what is short.

## 3. Rewrites that DO lock: the heaps

A heap only shrinks by being rewritten. Three ways, in the order I would choose them.

### 3a. `VACUUM FULL` on the tables the beat does not touch (no pause needed)

`VACUUM FULL` holds ACCESS EXCLUSIVE on its table for the whole rewrite: every read and write of that table waits. For these three
that is only the Stats count, the Stats tab and the drift job's once-a-period draw, so nothing a player is doing stops. Run each just
after a Stats count (minute 7 or 37), never across one (minute 6 or 36), with a lock timeout so it gives up rather than queue:

```sql
set lock_timeout = '3s';
vacuum (full, analyze) public.city_wants;        -- 112 MB -> about 1 MB.   5 s / 1 s.   Blocks: the wants' draw, a market read's wants line.
vacuum (full, analyze) public.stats_city_good;   -- heap 92 MB -> about 27. 40 s / 5 s.  Blocks: a city's Stats page, the price "why" line.
vacuum (full, analyze) public.stats_good;        -- heap 58 MB -> about 50. 40 s / 5 s.  Blocks: the Stats tab's goods. Small gain: optional.
```

`VACUUM FULL` rebuilds the table's indexes too, so skip their lines in step 2 if this is done first.

### 3b. The tables the beat writes: a short maintenance window, the clock stopped

events, ledger, voyages, voyage_events, standing_route_laps and port_goods are written by every beat. A `VACUUM FULL` on one of them
while the clock runs would stop the beat for its whole length and queue every player action behind it. So: stop the clock, rewrite,
start the clock. The game's own switch does it (`public.unwind_the_clock()` sets every job inactive; `public.wind_the_clock()` sets
every defined job active again: on 2026-11-14 all 23 were active, so winding restores exactly that; if a job is deliberately inactive
on the day, note it first and put it back after). Players' own actions still work while the clock is stopped, and a player's own ship is still
settled when she is looked at (reads settle); the merchants, the navy and the pirates stand still until it is wound. Voyages are settled by the clock's time, not by counting beats, so nothing is lost: arrivals land when it
starts.

```sql
select jobname, active from cron.job order by 1;     -- write it down
select public.unwind_the_clock();                    -- then wait 70 s: the minute jobs in flight finish their minute
set lock_timeout = '5s';
vacuum (full, analyze) public.standing_route_laps;   -- 372 MB -> about 60.  60 s / 8 s
vacuum (full, analyze) public.events;                -- 555 MB -> about 195. 150 s / 20 s
vacuum (full, analyze) public.ledger;                -- 205 MB -> about 75.  60 s / 8 s
vacuum (full, analyze) public.voyage_events;         -- 220 MB -> about 135. 90 s / 12 s
vacuum (full, analyze) public.voyages;               -- 101 MB -> about 68.  40 s / 6 s
vacuum (full, analyze) public.port_goods;            -- 142 MB -> about 90.  50 s / 7 s
select public.wind_the_clock();
```

About 8 minutes throttled, about 1 to 2 minutes not. Each statement is its own transaction: if one fails on its lock timeout, wind the
clock and try that table another time; the others are done. `VACUUM FULL` cannot run inside a transaction block.

port_goods, optional and the owner's call: it is at fillfactor 30 because every row was rewritten every minute and needed room for
three versions on its page. With `drift_spread_runs` 10 a row is rewritten once in ten minutes; fillfactor 50 would make the heap
about 55 MB instead of 81. It is a deliberate tuning, so it is not changed here. To do it, before the `vacuum full` line:
`alter table public.port_goods set (fillfactor = 50);` and watch `health.sql`'s `port_goods.hot_updates` against `updates` for a day
(they should stay within 2 % of each other). To undo: set 30 and rewrite again.

standing_route_laps, optional, same reasoning the other way: its rows are updated five to ten times while a lap is open, on full
pages. `alter table public.standing_route_laps set (fillfactor = 70);` before its rewrite keeps those updates on the page and the
table from swelling again.

### 3c. Instead of 3b, with no pause: `pg_repack`

`pg_repack` rewrites a table while it is in use and takes ACCESS EXCLUSIVE only for an instant at the start and at the swap. Supabase
offers the extension (`create extension pg_repack;`) and it is driven by the `pg_repack` client from a machine that can reach the
database, with `-k` (no superuser check). It needs twice the table's space free, and it writes more than a `VACUUM FULL` does (a log
table and triggers), so on a throttled disk it is slower and the beat feels it for longer, though it never stops. I have not run it
against this project and cannot say the client version matches the server's: check that first. `CLUSTER` is not an alternative: it
takes the same lock as `VACUUM FULL` and is slower.

My recommendation: step 2 whole, then 3a, then 3b in one window of a few minutes at a quiet hour. 3c only if the owner will not pause
the clock at all.

## 4. After

1. `health.sql` again: `database_mb` under 1,500, every `ok` true.
2. `after.sql`: the beat's mean, the compactor's `left`, the Stats count's ms.
3. Nothing needs repeating on a schedule. Autovacuum keeps what is there; `health.sql` once a day says if a table has started to grow.

## If the index 0414 dropped is wanted back

```sql
create index concurrently if not exists standing_route_laps_closed_at
  on public.standing_route_laps using btree (closed_at) where (closed_at is not null);
```

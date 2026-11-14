# 2026-11-14: the sweeper comes a few times a day (0412, slim-autovac)

## What the lead read on production (11:05 UTC, head 0409)

Twelve minutes after 0409 the beat was still about 12 s. `pg_stat_io` since 11-01: the autovacuum workers read **574,410,244 blocks**
and wrote 67,271,408; all client backends together read 506,247,081. Autovacuum is the largest reader of the disk, larger than the
game. At that moment: an autovacuum of standing_route_laps over 100 s in DataFileRead, the compactor 35 s in DataFileRead, a beat with
5,528 ms in two lap closes. The builder read nothing on production; the churn figures below are from the lead's read of
`pg_stat_user_tables` at 09:50 (`C:\Users\gkwng\dev\slim-db-reads\out\06_table_activity.json`), 12.6 days of counters.

## Why

The chain gave each churn table a fixed, tiny threshold (scale factor 0) when the world was a tenth of this size: 2,000 dead rows on
events, ledger, voyages, voyage_events and trade_daily; 1,000 on the stats tables, price_history and treasury_flows; 500 on
standing_route_laps, with an analyze every 2,000 changes. orders, city_wants and insured_voyages have none (the default: 50 rows plus
a fifth of the table). events passes 2,000 dead rows in under two minutes.

Every pass reads the whole heap and every index, because none of it is in memory, and at the server's default pace, which on
PostgreSQL 14 and later is about 100 page reads every 2 ms: no brake. An ANALYZE samples up to 30,000 pages (234 MB) of a table that
size, and standing_route_laps was analysed about 265 times a day.

## The table

Dead rows a day = deletes + updates that leave a dead version, 13-day mean. "Today" is the rate of the morning of 11-14, about three
times the mean on events. Room = what the dead rows between two passes take in the table.

| table | dead rows a day | passes a day, measured | old threshold | new threshold | passes a day, new | room | analyze every |
|---|---|---|---|---|---|---|---|
| events | 790,000 (2,300,000 today) | 337 | 2,000 | 200,000 | 4 (12 today) | 70 MB | 500,000 changes |
| ledger | 620,000 | 272 | 2,000 | 150,000 | 4 | 22 MB | 300,000 |
| voyage_events | 664,000 | 294 | 2,000 | 150,000 | 4 | 15 MB | 300,000 |
| voyages | 1,060,000 | 432 | 2,000 | 60,000 | 18 | 66 MB | 250,000 |
| standing_route_laps | 535,000 | 714 | 500 | 50,000 | 11 | 22 MB | 100,000 |
| orders | 1,840,000 | 578 | default | 50,000 | 37 | 20 MB | 400,000 |
| stats_city_good | 195,000 | 25 | 1,000 | 100,000 | 2 | 14 MB | 100,000 |
| stats_good | 214,000 | 98 | 1,000 | 50,000 | 4 | 20 MB | 50,000 |
| stats_city | 76,000 | 47 | 1,000 | 25,000 | 3 | 5 MB | 25,000 |
| price_history | 213,000 | 151 | 1,000 | 50,000 | 4 | 5 MB | 100,000 |
| treasury_flows | 615,000 | 196 | 1,000 | 100,000 | 6 | 10 MB | 200,000 |
| city_wants | 27,000 (0409's trim) | 26 | default | 20,000 | 1 to 2 | 2 MB | 20,000 |
| trade_daily | not read | not read | 2,000 | 50,000 | not known | 5 MB | 100,000 |
| insured_voyages | about 250,000 | not read | default | 50,000 | 5 | 10 MB | 50,000 |

About 3,000 passes a day become about 100. voyages and orders stay the busiest on purpose: a dead voyages row is 1.1 KB (its path),
so 60,000 of them are already 66 MB, and orders is a small hot table that is in memory anyway. port_goods is not touched: 0289 tuned
it on purpose and 0409 cut its writes by ten.

The pace: `autovacuum_vacuum_cost_delay` 20 ms and `autovacuum_vacuum_cost_limit` 25 on each table. With the server's page costs
(a miss 2, a dirtied page 20) a pass reads at most about 625 pages a second, **5 MB/s**, and dirties at most about 60, **0.5 MB/s**.
A pass over events as it is today (555 MB) takes about two minutes, and 30 s once it is rewritten. A table with its own cost settings
is paced by them alone, whatever the other workers do. **This assumes PostgreSQL 14 or later** (`vacuum_cost_page_miss` 2): the
before read prints the server's values; if a miss costs 10 the read pace is 1 MB/s, which is too slow for events.

Insert-triggered passes are spaced too (200,000 to 1,000,000 inserts). They exist for tables nobody deletes from; here the
delete-triggered passes keep the visibility map up.

Analyze: no plan on these tables turns on a fresh histogram. Their hot reads are by key (a fleet, a route, a voyage, a player) or by
a time window on the one index that serves it. The reads that would suffer from stale statistics are the wide Stats reads over a time
range on events and ledger, and those are index range scans on `created_at` under either estimate. A few analyses a day keep the row
counts honest for the planner.

Wraparound: nothing turns autovacuum off. The age-driven pass ignores these thresholds, and the server lifts the cost brake for a
table in danger. The before read prints each table's `xid_age`.

## What it costs

Space: the dead rows between two passes take room in the table, at most the "room" column: about 290 MB in all if every table
stood at its threshold at once, about half that on average. That is real, and it is the trade: the disk is cheaper than the reads.
After the RUNBOOK's rewrite the tables settle at their live rows plus that room, not at their 2,826 MB of today.

## The compactor's pattern

It deletes all day, a house at a time, so dead rows arrive evenly: a few thousand a minute across events, ledger, voyages and
voyage_events. That is not the fault; with thresholds of 2,000 any steady delete rate triggers a pass every minute or two. No knob is
needed there. One thing follows from the new thresholds: the compactor's deleted space is reused only after a pass, so the tables
breathe by the room above between passes.

## The change

`ALTER TABLE ... SET (...)` on fourteen tables: storage parameters only. Each takes SHARE UPDATE EXCLUSIVE, which no read or write
waits for; an autovacuum in its way is cancelled by the server after a second and starts again under the new settings. lock_timeout
8 s with a failure that names the table. The old settings of each table, as the server holds them, are written to
`public.autovacuum_was` first; the rollback draft restores from it (run on the local world: all fourteen come back exactly).

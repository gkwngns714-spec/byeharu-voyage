# Read-only diagnostics for the live database (2026-11-02)

Every script here is pure SELECTs through `supabase db query --linked` (about 3 s of CLI overhead per query; no database password needed).
Run `scripts/ops/health.sh` FIRST: it says whether anything is wrong. These answer *why*. Each script finds the project link itself
(`_link.sh`: this clone, `~/dev/byeharu-voyage` or `~/byeharu-voyage`). Never run anything that writes; never call a volatile function.

| script | question it answers | healthy on 2026-11-02, after 0297 |
|---|---|---|
| `io-who.sh [secs=150]` | Who reads and writes the disk (pg_stat_io by backend type) and which big tables autovacuum started? | total reads about 20-26 k blocks/min; autovacuum workers well under half of the reads |
| `table-reads.sh [secs=180]` | Which tables are read FROM DISK (cache misses) and which are scanned sequentially? | `standing_route_laps` the top reader (about 15 k blocks/min before the lap history was cut to 100); `voyages` about 1.5 k |
| `table-writes.sh [secs=180]` | Which tables write the most (rows/min, HOT %, estimated MB/min)? | `port_goods` about 150 k updates/min, 100 % HOT, the only big writer |
| `vacuum-watch.sh [secs=120]` | Which table is autovacuum working on right now, in which phase? | `port_goods` should NOT appear (its thresholds are 1 M / 4.5 M since 0297) |
| `sample-waits.sh [secs=150]` | What is every active session waiting on, every ~3 s? (the 11-second beats were `IO/DataFileRead`) | the three minute loops mostly `Timeout/PgSleep` |
| `reconcile-watch.sh <HH:MM:SS UTC> [secs]` | Who blocks the hourly reconcile (`pg_blocking_pids`)? Start it a few seconds before :07. | blocked only briefly by the arrivals beat (one beat) |
| `wal-delta.sh` | WAL MB/min, full-page images and port_goods HOT share over 4 minutes (a 30 s window swings with the 5-minute checkpoint) | about 45 MB/min, HOT 100 % |

Numbers worth remembering (prod, Micro-class compute: shared_buffers 256 MB, max_connections 60, DB about 2.1 GB):
- arrival lag (voyages past `due_at`): 27 s average before 0297, 0.2-2 s after; `arrivals_beats.ms` p50 about 0.27 s, p90 about 0.65 s, with a few 10-second stalls an hour;
- the Stats count (every 15 min): 46-120 s before 0297, 9-23 s after; `world.stats_now()` 1.4-3.5 s (47-58 s before 0293);
- the hourly reconcile (:07): failed in the busy hours from 2026-10-29 20:07 until 0300 (2026-11-01 20:48); 42 s at 21:07.

Rules that cost a night to learn (docs/OPS_HEALTH.md section 4, memory note voyage-migration-selfassert-cost-and-noise): a migration's guard sets
`statement_timeout` <= 90 s and `lock_timeout` 5 s, because `bv-deploy.sh` pauses EVERY cron job for the whole push; its self-assert runs <= 45 s on
prod and looks only at its own probe key space; prove it on a populated local world before the PR.

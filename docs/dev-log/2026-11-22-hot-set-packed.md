# 2026-11-22: the books are packed again (0470, load only)

Daily read `over` (09:18 KST): `hot_set_mb 780` and `cache_hit_pct 98.55`. Database 1,060 MB, beat 122 ms.

## Measured (prod, read-only, 00:20 UTC, head 0467: `scripts/ops/harness/hot-set/before-0470.sql`, one catalog read)
Hot ten 781 MB. Packed heap = rows x (sum of `pg_stats.avg_width` + 28) at fillfactor 100; fresh index = entries x (16 + key width) at 90 %.

| table | MB | heap pages -> packed | worst indexes, pages -> fresh |
|---|---|---|---|
| stats_city_good | 124 | 5,743 -> ~4,200 | pkey 8,744 -> ~2,050; at 1,421 -> ~870 |
| voyages | 122 | 13,991 -> ~6,300 (43,850 rows, 1,126 B) | fleet_ended 842 -> ~235; pkey 711 -> ~190 |
| events | 111 | 8,140 -> ~3,750 | created_at 3,292 -> ~280; player_created 1,189 -> ~470; pkey 815 -> ~375 |
| port_goods | 102 | left alone (fillfactor 30 by design) | |
| voyage_events | 91 | 7,949 -> ~1,220 | pkey 3,684 -> ~420 |

The rest of the ten (price_history_hour 69, stats_good 66, stats_city 41, battles 30, arrivals_beats_kept 24) are within 1.5x.
Every index is read (smallest: events_trades_port_good, 9 scans, 0.6 MB, 0227's reader): none dropped.

## Cause
- voyages / events / voyage_events: the drain after 0463 (90,698 / 132 k / 435 k live rows on 11-20, now 43,850 / 85,685 / 85,568). A vacuum never returns pages, so the files kept the peak. 0463 removed the cause; the vacuum (0428) reuses room from here.
- stats_city_good: b-tree bloat of its primary key from the Stats count's insert-and-fold (62 -> 79 MB of index in two days). It will grow back, about 8 MB a day at that rate. No option fixes it; the daily read's `hot_set_mb` shows when it needs packing again.

## Remedy
0470: `CLUSTER` on the primary key of stats_city_good, voyage_events, events, voyages, in that order, each under its own lock, rows checksummed before and after. Expected 124 -> ~56, 122 -> ~52, 111 -> ~40, 91 -> ~13 MB: ~287 MB back, database ~775 MB, hot ten ~480-505 MB.
Lock: one transaction (db push), so each lock is held to the commit. ~20-45 s in all on a saturated disk (60 s pessimistic), ~5-10 s bursting; voyages, locked last, ~10-15 s. Requests to a locked table wait and time out (anon 3 s, authenticated 8 s).

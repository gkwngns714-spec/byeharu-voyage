# 2026-10-26 — A price is kept for years, both ways (owner rows 189 and 205)

**Branch `osn-price-history`: migration `20260818000225_a_price_is_kept_for_years_both_ways.sql` (renumbers to
the prod head + 1 at deploy; its tags are `0225`) + the client. NOT merged, NOT deployed.**

**The owner, verbatim (docs/OWNER_REQUESTS.md):**

> 189 (2026-10-25): *"why is the selling price chart is flat? where as buying chart is good?"*
> 205 (2026-10-26): *"the chart and data of the game, is it too far for me to ask to save like all the price
> data graph? right now i can see up to 24 hours, but i want to see them in weeks, years even. only by
> charts? is this possible?"*

## 1. Row 189, the cause — read from the chain, not guessed

`public.tick_price_snapshot` (0013:97, as re-cut by 0057, 0061 and 0170) wrote ONE figure, the mid, and only
`where public.port_offers(pg.port_id, pg.good_id)` — the 1,380 pairs a city SELLS. A city that only BUYS a
good had no row at all, so `world.price_history` served nothing for it and `GoodChart.tsx:110` drew the
estimate alone: the flat line. The buying chart was "good" because the city in focus happened to sell the
good. Nothing recorded what a city PAYS, anywhere.

## 2. What 0225 does

| Part | What | Where |
|---|---|---|
| Both sides | `price_history` gains `ask` (null where the city does not sell the good, 0061's law) and `bid`. The writer composes the ONE authority's own three leaves set-wise — `world.price_terms` once a port, `world.mid_price` once a pair, `world.price_sides` — exactly what `world.price(port, good)` composes (0170) and what `world.price_outlook` already does. The self-assert proves the recorded sides equal `world.price`'s to the cent, for a sold pair and for a buy-only pair. No second formula. | §5 of the file |
| Which pairs | `public.price_record_pairs()`: every pair a city sells (1,380) ∪ `public.price_watch` — the buy-only pairs a player has opened a chart on. **Every pair is not affordable**: 138,990 pairs × 365 × 201 B = **7.6 GB a year** of day rows alone, and 13.3 M fine rows a day. So a buy-only city's record starts at the first press on its chart (`cmd.watch_price`, idempotent; `price_watch_cap` = 2,000, the stalest ask making room; the day rows of a pair that leaves the list stay). | §3, §8 |
| Three tiers, one job | fine: `price_history`, `price_history_fine_slots` = 96 slots × 900 s = 24 h; hourly: `price_history_hour` (open/high/low/close of both sides, `n` points folded) for `price_history_hour_days` = 30; daily: `price_history_day`, UTC days, **never deleted**. The SAME cron job (`byeharu-voyage:price-snapshot`, no new schedule) records, folds fine → hour and hour → day from the marks in `price_rollup` (set-based; only finished hours and days), then prunes the fine window and hours past 30 days. | §2, §5 |
| The window law | `price_history_window()` SUPERSEDES 0057:214: the same 600 MiB budget (`price_history_window_for` untouched) now divided by the pairs the record KEEPS, capped at the fine tier's 96. On production: least(96, 600 MiB ÷ (3,380 × 201)) = 96. | §4 |
| One read | `world.price_series(port, good, span)`, span ∈ 1d / 1w / 1m / 1y / all, picks the tier by span and serves both sides of every point (`ask`, `bid`; the fine tier adds `stock`; the folded tiers add `ask_lo/hi`, `bid_lo/hi`). `recording: false` with `[]` for a pair the record does not keep. `world.price_history(uuid, int)` is **dropped** and leaves the registry. | §7 |
| Backfill, once | The 48 slots production holds carry a mid only. Their sides are made from that recorded mid and the port's terms as they stand at the deploy (spread, tax, purse factor) through `world.price_sides` — stated in the header as the one point where a recorded side is not from the tick that recorded its mid; it covers 12 hours. Then the job runs once and folds the hours already kept. | §6 |
| Two re-cuts | `tick_stats` (0214): its city-good key set and its mid join read `price_history`, which held sold pairs only; both hunks now say `and public.port_offers`, so the Stats tab's city goods stay "the goods the city sells" — a no-op on today's rows. The registry: `price_history` out, `price_series` and `watch_price` in. Each hunk occurs once and reverses; ACL / volatility / definer / config asserted unmoved. | §9 |

**The client.** `worldPriceSeries` / `cmdWatchPrice` replace `worldPriceHistory`; `worldStore.loadSeries`
keeps one payload per (port, good, span) and presses a `recording: false` pair into the record once;
`useChartSpan` (src/store/chartSpan.ts) is the ONE span for every chart; `usePriceSeries(port, good)`
replaces `usePortHistory`; `SpanPicker` — **1 day · 1 week · 1 month · 1 year · All** (KO: 1일 · 1주 · 1개월 ·
1년 · 전체) — stands on the desk's good page and in `PriceRows` (both trays), so every chart has it; the
chart draws the ASK (`accent`, "Cost") and the BID (`info`, "Sale") as two lines, the primary one (the ask
where the city sells, else the bid) carrying the ground and the marks, with each side's low…high as a band
on the folded tiers; a span with nothing in it says **No data yet** (KO 기록 없음). A press on a span SELECTS:
the picker keeps its height and the chart changes in place.

## 3. Storage — measured in PGlite (real PostgreSQL 18 pages), per row, heap + index

| Tier | Row | Measured | Rows per pair | Per pair |
|---|---|---|---|---|
| fine (`price_history`) | port, good, slot, at, mid, stock, ask, bid | **189 B** | 96 (24 h) | 18 KB |
| hour (`price_history_hour`) | port, good, hour, 8 × numeric(12,2), n | **213 B** | 720 (30 d) | 153 KB |
| day (`price_history_day`) | port, good, day, 8 × numeric(12,2), n | **201 B** | 365 a year | 73 KB a year |

Measured on tables filled in the job's own order (every pair, hour by hour), after `vacuum analyze`; the
index is about half of each figure because that order splits pages at the middle.

| Recorded pairs | Fine | Hourly (steady) | Daily growth |
|---|---|---|---|
| 1,380 (the sold pairs, day one) | 25 MB | 211 MB | **101 MB a year** |
| 3,380 (the cap: + 2,000 asked-for pairs) | 61 MB | 518 MB | **248 MB a year** |
| every pair (138,990) — NOT done | 2.5 GB | 21 GB | 10.2 GB a year |

Production is 776 MB on the 8 GB plan: at the cap, about 580 MB steady and a quarter of a gigabyte a
year — twenty-odd years before the day rows alone reach 5 GB.

## 4. Timings — PGlite on this PC (production is faster; the main session measures it, §6)

| What | Measured |
|---|---|
| `tick_price_snapshot`, 1,380 recorded pairs (record + a fold every fourth run) | 196–241 ms (5 runs) |
| `tick_price_snapshot`, 4,380 recorded pairs | 800–986 ms (5 runs); the run that also folds a day: 1,123 ms |
| the backfill UPDATE over 66,240 prod-shaped fine rows (1,380 × 48, as production holds) | 1,287 ms |
| the backfill fold (12 h × 1,380 pairs → 16,560 hour rows) + the record | 648 ms |
| `world.price_series` × 6 in one session, a pair with 96 / 720 / 365 rows (1d, 1w, 1m, 1y, all, 1m) | 2.5 / 2.9 / 5.8 / 3.6 / 3.1 / 4.4 ms |
| payload of `1m` (719 hour points, both sides, lows and highs) | 98 KB |

The self-assert prints the same two timings for the session that applies it (the run at the next slot, and
the six series calls).

## 5. Decided by default (the owner may reverse each)

- **Not every pair.** The arithmetic in §3 forbids it on this plan. A buy-only city's record starts at
  the first press on its chart; from then on it is kept like any sold pair, and its day rows for ever.
- **The fine tier is a day** (`price_history_fine_slots` 96), not 48 h: the `1 day` span is the fine tier's
  whole, and beyond a day the hourly tier carries the line. One knob changes it.
- **Hourly for 30 days** (`price_history_hour_days`), the fattest tier (518 MB at the cap); 14 would halve it.
- **The cap is 2,000** asked-for pairs (`price_watch_cap`). 3,000 would be 672 MB steady and 321 MB a year.
- **The backfill makes the 12 kept hours' sides from today's terms** rather than leaving them without a
  side. Stated in the file's header; it is 48 rows a pair and the record outgrows it in a day.
- **One span for every chart** (a preference, in session storage), not one per chart.
- **The chart's "move" is the record's own** (the primary side's last point against the first on the
  plane), no longer the estimate's middle price against a recorded mid.

## 6. PROD CHECKS FOR THE MAIN SESSION

Read-only. One statement per block, no trailing semicolons, no dollar-quoting. **Every block is a pure
SELECT on `stable` / `immutable` calls — nothing here writes** (no `cmd.*`, no `tick_*`, no `new_house`, no
rollup run): `supabase db query --linked` opens a new connection per call, so a begin…rollback split across
blocks would commit each statement. The rollup's timing on production is ESTIMATED from the row counts in
(2) and (5) against the local measurements in §4, never by running it there.

**(1) Not applied yet; the pre-image is what the file was cut against** — expect 0, 1, 1 and the hunk counts 1 / 1 / 1 / 1

```sql
select (select count(*) from public.world_config where key = 'price_history_fine_slots') as fine_knob, (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'world' and p.proname = 'price_history') as old_read, (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'price_rollup') as rollup_fn
```

```sql
select (length(d) - length(replace(d, h, ''))) / length(h) as tick_stats_hunk_1 from (select replace(pg_get_functiondef('public.tick_stats(timestamptz)'::regprocedure), chr(13), '') as d, '    from (select h.port_id, h.good_id from public.price_history h where h.slot = v_ph_slot' || chr(10) || '          union' as h) z
```

```sql
select (length(d) - length(replace(d, h, ''))) / length(h) as tick_stats_hunk_2 from (select replace(pg_get_functiondef('public.tick_stats(timestamptz)'::regprocedure), chr(13), '') as d, '    left join public.price_history h on h.port_id = k.port_id and h.good_id = k.good_id and h.slot = v_ph_slot' || chr(10) as h) z
```

```sql
select (length(d) - length(replace(d, h, ''))) / length(h) as registry_hunk_1 from (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), chr(13), '') as d, '      (''world'',       ''price_history'',       ''uuid, int''),' || chr(10) as h) z
```

```sql
select (length(d) - length(replace(d, h, ''))) / length(h) as registry_hunk_2 from (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), chr(13), '') as d, '      (''world'',       ''sea_conditions'',        '''')' || chr(10) || '    ) as t(s, f, a)' as h) z
```

**(2) The rows the backfill will touch, and the pairs** — the counts to time the backfill against (§4: 66,240 rows took 1.3 s in PGlite)

```sql
select count(*) as fine_rows, min(at) as oldest, max(at) as newest, count(distinct (port_id, good_id)) as pairs from public.price_history
```

```sql
select (select count(*) from public.ports p cross join lateral public.port_offered_goods(p.id) g where p.kind = 'HARBOUR') as sold_pairs, (select count(*) from public.port_goods) as all_pairs, public.wc_int('drift_slot_seconds') as slot_seconds, public.price_history_window() as window_slots
```

**(3) The authority the writer must equal** — one sold pair, one buy-only pair; after the deploy the newest fine row of each must carry these to the cent (the sold pair's ask and bid; the buy-only pair's bid, once its chart has been opened)

```sql
select p.code as port, g.code as good, pr.ask, pr.bid, pr.mid from public.ports p join public.port_specialties s on s.port_id = p.id join public.goods g on g.id = s.good_id cross join lateral world.price(p.id, g.id) pr where p.kind = 'HARBOUR' order by p.code, g.code limit 1
```

**(4) Timing, price_series-shaped, before the deploy** — the read the series will make on the fine tier, six times in one session (expect single-digit ms each)

```sql
explain analyze select jsonb_agg(jsonb_build_object('at', h.at, 'mid', h.mid) order by h.slot) from public.price_history h where (h.port_id, h.good_id) = (select pg.port_id, pg.good_id from public.price_history pg order by pg.port_id, pg.good_id limit 1) and h.at > now() - interval '1 day'
```

**(5) The rollup, estimated on prod row counts** — a SELECT with the fold's own aggregate over the rows the deploy's one fold will read (it aggregates and writes nothing; its time is the fold's read half, and PGlite's 648 ms for 66k rows is the whole fold + record; expect well under a second)

```sql
explain analyze select h.port_id, h.good_id, date_trunc('hour', h.at), (array_agg(h.mid order by h.slot))[1], max(h.mid), min(h.mid), (array_agg(h.mid order by h.slot desc))[1], count(*) from public.price_history h where h.at >= date_trunc('hour', now()) - interval '24 hours' and h.at < date_trunc('hour', now()) group by h.port_id, h.good_id, date_trunc('hour', h.at)
```

**(6) The walls** — 0 0 0

```sql
select (select count(*) from public.client_write_grants()) as w, (select count(*) from public.client_executable_writers()) as x, (select count(*) from public.caller_evaluated_functions()) as c
```

**After the deploy (read-only):** `select count(*), count(ask), count(bid) from public.price_history` should
read equal counts (every row sided; the ask count equals the row count because production holds sold pairs
only until a chart is pressed); `select hour_done, day_done from public.price_rollup` should read this hour
and today; `select count(*) from public.price_history_hour` should read about 12 × the sold pairs; and the
next `byeharu-voyage:price-snapshot` run's `cron.job_run_details` should show under a second.

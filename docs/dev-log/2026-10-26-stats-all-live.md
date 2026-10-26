# 2026-10-26 — Every figure keeps to the second: the count's quarter hours + the minutes since, read every second (owner row 213, `osn-stats-all-live`, migration 0227)

> *"and why is next count in minutes? i told you it should be in seconds?"*
> (2026-10-26, docs/OWNER_REQUESTS.md row 213 — after rows 187 and 200.)

Server + client, one slice. `supabase/migrations/20260818000227_every_figure_keeps_to_the_second.sql` (renumbers to
prod head + 1 at deploy; prod head is 0226 at the time of writing; `_0227` suffixes and the probe uuid go with it).

## What the owner sees

- The header says **"Updated HH:MM:SS"** and nothing else. The "Next count MM:SS" countdown is gone (words
  `stats.nextCount` / `stats.counting` deleted, EN + KO).
- **Every face re-reads its figures every second** while it is open, and every figure walks to its new value.
  - **Overview**: holders and the hero (live counters), "Trades, 24 h", printed / burned / moved, sold / bought,
    the 24 h flows by kind, the "since last count" flows, and every chart's last point at now().
  - **Markets**: sold / bought per good over the last 24 h up to this second, goods traded, units traded, most traded.
  - **Cities**: every purse (the live balance), works, and income / spending / taxes over the last 24 h up to this second.
  - **A city**: purse, every day-figure, money by kind, top bought / sold, **each good's price and stock live**, the
    purse line and each spark ending at now().
  - **Merchants**: where the fleets are (now), their money (now), earned 24 h / laps closed / % losing / best and
    worst five over the last 24 h up to this second, each line ending at now().
  - **Me**: already computed at the moment it is asked (world.stats_me, world.books) — now asked every second.

## The rule (one, for every figure)

| kind of figure | served as |
|---|---|
| over the last 24 h | the count's 24 h (the quarter hours up to the last count, as 0214 sums them) + the minutes since that count |
| "since the last count" | the minutes since that count (the period in progress) |
| a state | read now (a purse, a fleet's status, the merchants' money) |
| a chart | the counts' points + one live point at now() |

So "the last 24 h" covers 24 h to 24 h 15 min, dropping the oldest quarter hour when the next count lands — decided by
default (the 15-minute buckets are the history's grain).

`public.tick_stats` stays the **history writer** (chart points, the count's 24 h). It is no longer the gate on what a
figure shows.

## One reading of a window (no second copy of a rule)

0214's job read its period inline in temp tables. The live reads need the same readings for (last count, now], so the
readings moved into functions and **the job calls them** (10 hunks in `public.tick_stats`, each asserted once and
reversing; no temp tables left in the job):

`stats_window_trades` (a trade = a SOLD / BOUGHT event of a goods row), `stats_window_totals`, `stats_window_goods`,
`stats_window_city_trades`, `stats_window_city_goods`, `stats_window_flows`, `stats_window_cities`,
`stats_window_founded`, `stats_sides` (the words table's sides), `stats_merchant_fleets`, `stats_merchants_window`
(the laps — read once now; 0214 read them twice), `stats_merchants_board` (top / bottom five). `stats_window_kinds` and
`stats_merchants_add` are used by the live reads only.

## What the count keeps for the second

Summing 96 quarter hours per good / city / house on every ask was the slow part (prod, before: stats_markets 478–1,421
ms, stats_cities 1,117 ms, the 24 h of laps 1,562–6,409 ms). So the count keeps its 24 h on the NEWEST slot's rows in one
`day` jsonb column (`stats_good.day` = the good's whole served row; `stats_city.day` = the 24 h, money by kind, name and
flag; `stats_merchants.day` = the 24 h of laps and every house's day). Written by `public.stats_fold_day(slot)` (called
by the job on its return) and by the merchants' insert; cleared from older rows by the same fold, so `day` lives on the
newest slot only.

## Said plainly (decided by default)

- **A good's price across every market is NOT made live.** Markets' price, rose / fell, stock and markets stay the price
  record's (price_history, the price job's slot). Measured on prod 2026-10-26: ~1,380 live prices cost 566–936 ms
  through world.mid_price and 320–470 ms set-wise through world.mid_from_terms, per ask — ten times the budget.
  A CITY's prices and stock ARE live (world.mid_price on a handful of goods). If the owner wants Markets' prices to
  move faster, the cheap option is a price job every minute (about 0.4 s of CPU a minute), not a per-second read.
- **The live money by kind is one minute short once an hour.** The count reads it exactly from daybook + flows (438–917
  ms on prod — too slow for a second); the minutes since read the flows, which tick_city rolls away at :37, so between
  :37 and the :51 count the minute :36–:37 is missing from the live kinds (0214's own city rows miss it too). The :51
  count puts it back.
- **No writer hook.** The trade path is untouched (added cost 0 ms).
- **A dead cron makes the minutes since grow.** The reads stay correct but cost more (the events window grows). Not
  capped — correctness first.

## The client: one way of asking

`src/features/stats/statsLive.ts` — `useLiveRead(subject, ask)`: ask on mount, then every `STATS_LIVE_MS` (1,000);
a hidden document skips its asks; an ask on the wire is never stacked; a failed ask keeps the last answer. Every face
(Overview, Markets, Cities, CityDetail, Merchants, Me) and the RIGHT NOW band use it. Deleted: the `beat` / `count`
plumbing (`FaceProps`), `STATS_COUNT_MS`, `nextCountMs`, `withLivePoint` (the server ends every chart at now()).
Types gain `counted_at`; `at` is now the server's now().

## Measured

Local PGlite (the migration's own receipt, 6 calls each, ms): overview 0–1, markets 3–4, cities 8–10, city 8–10,
merchants 1–2, me 1–3, books 0–2. The re-cut job ran once (two hours ahead, rolled back) in 135 ms locally.

Prod (read-only, 2026-10-26 02:10–02:20 UTC; the same SQL as the new reads, written as one SELECT with the window
functions as materialized CTEs; warm runs after the first cold one; the prod server is noisy, so ranges):

| read | before 0227 | candidate after 0227 |
|---|---|---|
| world.stats_overview | 15–20 ms | 13–36 ms |
| world.stats_markets | 478–1,421 ms | about 30 ms (48 ms with a stand-in that builds the cached rows; that stand-in is 17 ms of it) |
| world.stats_cities | 1,117 ms | 64–180 ms (treasury_balance ×246 is 19–25 ms of it; port_nation 9–10 ms, now cached at the count) |
| world.stats_city (Lisbon) | 51–112 ms | 32–96 ms |
| world.stats_merchants | 6–19 ms | 20–36 ms |
| world.stats_now | 6–12 ms | unchanged |

Cities is the one read above the 50 ms target on prod's noisiest runs; the purses are the authority's own per-city
function (public.treasury_balance), kept rather than copied set-wise.

The count's new work, measured as SELECTs: the goods' 24 h fold 139–155 ms (606 cold), the cities' 225–327 ms (801
cold); the laps are now read once instead of twice.

## Deploy note

Deploy in minutes **:08–:14, :23–:29, :38–:44 or :53–:59** (not while the stats cron runs at :06 / :21 / :36 / :51 for
12–18 s): the file adds three columns (a brief exclusive lock on three stats tables, lock_timeout 5 s) and its
self-assert runs the re-cut job once two hours ahead (rolled back); a cron run overlapping it would wait on the trial
run's retention deletes and could miss one count.

## Found on the way (not this slice's to fix)

`20260818000226`'s self-assert fails when applied between 01:00 and 01:59 UTC: it plants two hours starting at
`date_trunc('hour', now()) - 26 h`, which straddle a UTC midnight in that hour, so its day row holds 4 points, not 8
("0226 self-assert FAIL: the day folded day … n 4"). Already applied on prod; it bites only an apply (CI, a local
cached apply) that runs in that hour.

## PROD CHECKS FOR THE MAIN SESSION

Pure SELECTs; every function called is `stable` or `immutable` (checked: client_write_grants, client_executable_writers,
caller_evaluated_functions, city_treasury_on, port_offered_goods `s`; culture_refuses `i`; pg_get_functiondef is a
catalog read). One statement per block, no trailing semicolons. Run 2026-10-26 02:21 UTC; results at the end.

### 1_not_applied
```sql
select (select count(*) from pg_proc where proname like 'stats_window_%') as window_fns, (select count(*) from information_schema.columns where table_schema = 'public' and column_name = 'day' and table_name in ('stats_good', 'stats_city', 'stats_merchants')) as day_columns, (select max(version) from supabase_migrations.schema_migrations) as head
```
### 2_tick_stats_hunks
```sql
select (length(d) - length(replace(d, '    drop table trades_0214, city_trades_0214, city_flows_0214, houses_0214;', ''))) / length('    drop table trades_0214, city_trades_0214, city_flows_0214, houses_0214;') as h1, (length(d) - length(replace(d, '           where l.kind in (''FOUNDING'', ''NPC_REFOUND'') and l.created_at > v_prev_at and l.created_at <= p_now', ''))) / length('           where l.kind in (''FOUNDING'', ''NPC_REFOUND'') and l.created_at > v_prev_at and l.created_at <= p_now') as h2, (length(d) - length(replace(d, '    left join public.stats_flow_words w on w.kind = p.kind;', ''))) / length('    left join public.stats_flow_words w on w.kind = p.kind;') as h3, (length(d) - length(replace(d, '         (select count(*) from trades_0214),', ''))) / length('         (select count(*) from trades_0214),') as h4, (length(d) - length(replace(d, '                 from trades_0214 t group by t.good_id) t on t.good_id = g.id', ''))) / length('                 from trades_0214 t group by t.good_id) t on t.good_id = g.id') as h5, (length(d) - length(replace(d, '         coalesce((select jsonb_object_agg(f.kind, f.ducats) from city_flows_0214 f where f.port_id = p.id), ''{}''::jsonb)', ''))) / length('         coalesce((select jsonb_object_agg(f.kind, f.ducats) from city_flows_0214 f where f.port_id = p.id), ''{}''::jsonb)') as h6, (length(d) - length(replace(d, '          select t.port_id, t.good_id from city_trades_0214 t) k', ''))) / length('          select t.port_id, t.good_id from city_trades_0214 t) k') as h7, (length(d) - length(replace(d, '                 from city_trades_0214 t group by 1, 2) t on t.port_id = k.port_id and t.good_id = k.good_id', ''))) / length('                 from city_trades_0214 t group by 1, 2) t on t.port_id = k.port_id and t.good_id = k.good_id') as h8, (length(d) - length(replace(d, '  create temp table houses_0214 on commit drop as', ''))) / length('  create temp table houses_0214 on commit drop as') as h9, (length(d) - length(replace(d, '                            ''live'', public.stats_live_fold(p_now),   -- 0224: the live figures reconciled on every count', ''))) / length('                            ''live'', public.stats_live_fold(p_now),   -- 0224: the live figures reconciled on every count') as h10 from (select replace(pg_get_functiondef('public.tick_stats(timestamptz)'::regprocedure), chr(13), '') as d) z
```
### 3_guard_1
```sql
select (length(d) - length(replace(d, '    ''day'', (select jsonb_build_object(''since'', min(w.at), ''minted'', sum(w.minted), ''removed'', sum(w.removed), ''moved'', sum(w.moved),', ''))) / length('    ''day'', (select jsonb_build_object(''since'', min(w.at), ''minted'', sum(w.minted), ''removed'', sum(w.removed), ''moved'', sum(w.moved),') as guard from (select replace(pg_get_functiondef('world.stats_overview(integer)'::regprocedure), chr(13), '') as d) z
```
### 3_guard_2
```sql
select (length(d) - length(replace(d, '        cross join lateral (select coalesce(sum(x.sold), 0) as sold, coalesce(sum(x.bought), 0) as bought,', ''))) / length('        cross join lateral (select coalesce(sum(x.sold), 0) as sold, coalesce(sum(x.bought), 0) as bought,') as guard from (select replace(pg_get_functiondef('world.stats_markets()'::regprocedure), chr(13), '') as d) z
```
### 3_guard_3
```sql
select (length(d) - length(replace(d, '                      ''income_1d'',   (select coalesce(sum(x.income), 0)   from public.stats_city x where x.port_id = p.id and x.at > v_at - interval ''24 hours''),', ''))) / length('                      ''income_1d'',   (select coalesce(sum(x.income), 0)   from public.stats_city x where x.port_id = p.id and x.at > v_at - interval ''24 hours''),') as guard from (select replace(pg_get_functiondef('world.stats_cities()'::regprocedure), chr(13), '') as d) z
```
### 3_guard_4
```sql
select (length(d) - length(replace(d, '  if v_slot is not null then  -- 0223: the detail, for everyone', ''))) / length('  if v_slot is not null then  -- 0223: the detail, for everyone') as guard from (select replace(pg_get_functiondef('world.stats_city(uuid)'::regprocedure), chr(13), '') as d) z
```
### 3_guard_5
```sql
select (length(d) - length(replace(d, '  select * into m from public.stats_merchants order by slot desc limit 1;', ''))) / length('  select * into m from public.stats_merchants order by slot desc limit 1;') as guard from (select replace(pg_get_functiondef('world.stats_merchants()'::regprocedure), chr(13), '') as d) z
```
### 4_probe_pre
```sql
select (select count(*) from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id where p.code = 'LIS' and pg.stock > 50 and not public.culture_refuses(p.culture, g.culture_mask) and exists (select 1 from public.port_offered_goods(pg.port_id) o where o.good_id = pg.good_id)) as lisbon_goods, (select count(*) from public.players where company_name = 'Casa do Segundo 0227') as probe_names, (select count(*) from public.standing_routes sr join public.players p on p.id = sr.player_id and p.is_npc) as npc_routes, public.city_treasury_on() as treasury_on, (select count(*) from public.stats_world) as world_rows
```
### 5_seed_size
```sql
select (select count(*) from public.stats_good where slot = (select max(slot) from public.stats_world)) as goods_rows, (select count(*) from public.stats_city where slot = (select max(slot) from public.stats_world)) as city_rows, (select count(*) from public.standing_route_laps where closed_at > (select max(at) from public.stats_merchants) - interval '24 hours') as laps_24h, (select max(at) from public.stats_world) as last_count, now() as now
```
### 6_walls
```sql
select (select count(*) from public.client_write_grants()) as w, (select count(*) from public.client_executable_writers()) as x, (select count(*) from public.caller_evaluated_functions()) as c
```

Results (2026-10-26 02:21 UTC):
- not applied: `window_fns 0, day_columns 0, head 20260818000226`.
- tick_stats hunks h1–h10 (the distinctive line of each hunk): `1 1 1 1 1 1 1 1 1 1`. The full hunks were proven once each and reversing on the cached chain.
- the five read guards: `1 1 1 1 1`.
- probe preconditions: `lisbon_goods 10, probe_names 0, npc_routes 837, treasury_on true, world_rows 293`.
- seed size: `goods_rows 565, city_rows 246, laps_24h 26252` (the seed reads those laps once); last count 02:06 UTC.
- walls: `0 0 0`.

After the deploy (30-minute after-check): the Stats header shows only "Updated HH:MM:SS"; a good's "sold" on Markets moves within a second of a sale; after the next count, `select slot, day is not null as has_day from public.stats_merchants order by slot desc limit 2` reads true then false. Never run `public.tick_stats` by hand (it writes).

# 2026-10-26 — Every coin that moves is told: a live log of every money move beside World money (owner row 219, `osn-money-feed`, migration 0235)

> *"beside the stat, world money, i want to see the live log of each happenings that cause money - drop and gain, at
> the right side. possible?"* (2026-10-26, docs/OWNER_REQUESTS.md row 219)

Server + client, one slice. `supabase/migrations/20260818000235_every_coin_that_moves_is_told.sql` (renumbers to prod
head + 1 at deploy; prod head is 0234; the `_0235` suffixes and the probe uuid go with it).

## What the owner sees

Stats › Overview: a **Money log** beside **World money** — on the wide glass in the right-hand column (the column's
right gutter, where a tray would stand; the Stats tab opens none), its heading on World money's line; on a phone, under
World money. One row per move, newest first:

`−147 🪙 · Casa de Aveiro (you) · Bought      1 s ago`
`+147 🪙 · Lisbon · Sold                       1 s ago`

Green for a gain, red for a drop; your own company in the accent colour with "(you)"; a city's name in Korean where the
names table has it. The last 100 are kept; the list scrolls inside its own box; names wrap, never cut. KO: `돈의 흐름`,
`판매` / `구매`, `5초 전`.

## The server: one read

`world.money_feed(p_after timestamptz default null, p_limit int default 50)` — stable, security definer, `search_path =
public, pg_temp`, granted to `authenticated` only, registered in `public.client_rpc_entry_points()` by one hunk.

Money moves in exactly two books, each with one writer (prod: the only bodies inserting into them are `public.credit`
and `public.treasury_post`; `npc_compact` folds a merchant's old rows into `NPC_CARRIED`):

| book | holder | `who` |
|---|---|---|
| `public.ledger` (player_id, kind, ducats_delta) | company / merchant (players.is_npc) | players.company_name |
| `public.treasury_flows` (port_id, kind, ducats) | city | ports.name |

Each row: `key` ('L' + ledger id / 'F' + flow id), `at`, `who`, `holder`, `own`, `kind`, `word` (stats_flow_words.word,
else the kind), `side` (minted / moved / removed from stats_flow_words; null where it names none), `delta` (signed).
CAPITAL_GIFT and CROWN_CALL (0234) come through as any other kind (both `moved`).

**Decided by default:**
- **Both ends of a move are two rows.** A sale is "+x · Casa X · Sold" and "−x · Lisbon · Bought". Each row is one
  purse's gain or loss — what the owner asked to see — and the books already keep them apart. Nothing is merged or
  skipped as "internal": a crown aid between two cities is two rows, too.
- **Not rows:** a zero move (prod writes PROVISION 0 rows) and `NPC_CARRIED` (a compaction's carried balance, not a move).
- **Names shown** (players and merchants by name — the owner's rule since 0227). No purse, no fleet, no position.

## The client: on the tab's one way of asking

`src/features/stats/MoneyLog.tsx`, mounted in `Overview.tsx` after World money. The ask rides `useLiveRead`
(statsLive.ts, 0232): on mount and every second while the face is open, never stacked, a hidden page skips.

Each ask names only what is newer than the newest row held **less 20 s**, and rows merge by `key` (the newest 100
kept). Why the overlap: a job's moves carry the instant its transaction BEGAN and appear when it commits. Measured on
prod (cron.job_run_details, 24 h): the arrivals tick (every 15 s, all merchant trades in one transaction — 40 distinct
`created_at` in 10 minutes for 2,890 ledger rows, up to 107 per instant) runs 5.1 s on average, 12.5 s at most; the city
tick 8.1 s at most. Asking "after the newest" alone would drop a whole batch that commits after a player's own trade.
`track_commit_timestamp` is off on prod, so there is no commit-order cursor to use instead.

"5 s ago": `formatRelative(at, now, { seconds: true })` — the one relative-time formatter gains a seconds form under a
minute (pinned in tests/format.spec.ts), read against the shell's one clock (the server's).

Words: `src/lib/i18n/dict/feed.ts` (EN + KO), `k_<KIND>` for a company's row, `c_<KIND>` where a city's side reads
differently (its SELL is "Bought", its BUY "Sold"); an unknown kind prints the server's word.

## Speed

Prod, read-only, 2026-10-26 (the read's SQL as one SELECT, EXPLAIN ANALYZE — no function in it but `now()`):

| ask | ledger half | flows half | whole |
|---|---|---|---|
| after now − 10 min, limit 50 (04:47 UTC, 3,421–3,512 flows) | index-backward on `ledger_created_at`, 0.1 ms | seq scan + top-N, 2.6–12.8 ms | 8.6–23.0 ms |
| after now − 10 min, limit 50 (05:12 UTC) | 0.1 ms | seq scan of 2,992–3,078 matching | 8.6–14.1 ms |
| no bound, limit 100 (the first ask; 05:12 UTC, 11,249–11,376 flows) | 0.3 ms | seq scan, 6.2–14.6 ms | 17.6–35.9 ms |

`treasury_flows` has no `created_at` index (only `(port_id, created_at)`) and holds up to an hour of flows before the
:37 roll (~22,000 rows), so the flows half grows with the hour. **The file adds `treasury_flows (created_at)`**: the
table is 3.2 MB / 10,838 rows (05:11 UTC); a plain build (a migration is one transaction, no CONCURRENTLY) reads it once
and holds `treasury_post` inserts for milliseconds. With it the flows half is an index-backward scan like the ledger's.
The ledger already has `ledger_created_at` (197,210 rows, 45 MB; nothing added).

Local (PGlite, the self-assert's receipt): `world.money_feed(null, 100)` × 6 = 3–7 ms.

## Self-assert (the file's own)

Re-cut reverses; registry +1, every row executable by `authenticated`; anon refused; stable / definer / pinned; walls 0;
index valid. A probe company founded at Lisbon buys 1 (the city purses lit inside the probe where a chain has them
dark; prod's are on) and reads the feed as herself after just before her transaction's `now()`: every ledger row of hers
and every flow row naming her is served with its holder, delta, kind, word and side — only those rows are counted;
among them her BUY < 0 and Lisbon's BUY > 0. A bound a day ahead → no rows; limit 1 → one row; newest first. Rolled
back whole; nothing deleted; no `set role`; no hour-of-day dependence.

## Proof (local)

- Cached-prefix apply (prefix restored, 0235 applied), self-assert:
  `0235 self-assert ok: EVERY COIN THAT MOVES IS TOLD. The registry re-cut by one hunk, reversed; registry +1; anon refused; stable, definer, pinned; walls 0; index valid. Probe at Lisbon bought 1: her BUY -17, Lisbon's BUY 17; 3 of 3 probe rows served, each with its holder, delta, word and side; newest first; a day ahead → 0 rows; limit 1 → 1 row. world.money_feed(null, 100) × 6 = [5.00, 6.00, 7.00, 3.00, 5.00, 3.00] ms. Rolled back.`
- `npx tsc -b` clean; eslint on every touched file clean; `npm run build` (no `.env.local`) green.
- Specs against `vite preview --port 4212` on localhost: `tests/stats.moneyFeed.spec.ts` (new: canary with the purses
  lit → buy 1 → Stats shows my BUY in red with "(you)" and Lisbon's BUY in green, under World money at 390 and in the
  right column at 1280 with its heading on World money's line, no sideways scroll), `tests/stats.tab.spec.ts`,
  `tests/align.spec.ts` (ALIGN_ONLY=Stats), `tests/i18n.keys.spec.ts`, `tests/i18n.ko.spec.ts`, `tests/format.spec.ts`,
  `tests/rpc.surface.spec.ts` (catalogue pin moved for `worldMoneyFeed`): all green.
- Found on the way: `tests/format.spec.ts` and other Node-side specs read `navigator.language`, which is `ko-KR` on this
  Korean Windows machine, so they print Korean and fail locally; they pass with `navigator.language = 'en-US'`
  (CI's). Not this slice's.

## Deploy note

Any minute. The file builds one small index (milliseconds of held flow inserts) and runs a rolled-back probe.

## PROD CHECKS FOR THE MAIN SESSION

Pure SELECTs; every function called is `stable` or `immutable` (checked on prod: caller_evaluated_functions,
city_treasury_on, client_executable_writers, client_rpc_entry_points, client_write_grants, current_player_id,
port_offered_goods `s`; culture_refuses `i`; pg_get_functiondef is a catalog read). One statement per block, no trailing
semicolons. Run 2026-10-26 05:11 UTC; results at the end.

### 1_not_applied
```sql
select to_regprocedure('world.money_feed(timestamptz, int)') is null as no_read, to_regclass('public.treasury_flows_created_at') is null as no_index, (select max(version) from supabase_migrations.schema_migrations) as head
```
### 2_registry_hunk
```sql
select (length(d) - length(replace(d, E'      (''world'',       ''city_good_trades'',      ''uuid, uuid, int'')\n    ) as t(s, f, a)', ''))) / length(E'      (''world'',       ''city_good_trades'',      ''uuid, uuid, int'')\n    ) as t(s, f, a)') as hunk from (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), chr(13), '') as d) z
```
### 3_probe_pre
```sql
select (select count(*) from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id where p.code = 'LIS' and pg.stock > 50 and not public.culture_refuses(p.culture, g.culture_mask) and exists (select 1 from public.port_offered_goods(pg.port_id) o where o.good_id = pg.good_id)) as lisbon_goods, (select count(*) from public.players where auth_uid = '00000000-0235-4000-8000-000000000001') as probe_houses, (select count(*) from public.players where company_name = 'Casa do Livro 0235') as probe_names, public.city_treasury_on() as treasury_on, (select count(*) from public.client_rpc_entry_points()) as entry_points
```
### 4_flows_size
```sql
select (select count(*) from public.treasury_flows) as flows, pg_size_pretty(pg_total_relation_size('public.treasury_flows')) as size, (select min(created_at) from public.treasury_flows) as oldest, now() as now
```
### 5_words
```sql
select string_agg(kind || ':' || side, ', ' order by ord) as words from public.stats_flow_words where kind in ('CAPITAL_GIFT', 'CROWN_CALL', 'SELL', 'BUY', 'FOUNDING')
```
### 6_walls
```sql
select (select count(*) from public.client_write_grants()) as w, (select count(*) from public.client_executable_writers()) as x, (select count(*) from public.caller_evaluated_functions()) as c
```
### 7_volatility
```sql
select string_agg(p.oid::regprocedure::text || '=' || p.provolatile::text, ', ' order by p.proname) as v from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('current_player_id', 'city_treasury_on', 'culture_refuses', 'port_offered_goods', 'client_write_grants', 'client_executable_writers', 'caller_evaluated_functions', 'client_rpc_entry_points')
```

Results (2026-10-26 05:11 UTC):
- not applied: `no_read true, no_index true, head 20260818000234`.
- registry hunk: `1`.
- probe preconditions: `lisbon_goods 10, probe_houses 0, probe_names 0, treasury_on true, entry_points 77`.
- flows: `10,838 rows, 3,224 kB, oldest 04:36:52 UTC` (the :37 roll is hourly).
- words: `FOUNDING:minted, SELL:moved, BUY:moved, CAPITAL_GIFT:moved, CROWN_CALL:moved`.
- walls: `0 0 0`.
- volatility: `caller_evaluated_functions()=s, city_treasury_on()=s, client_executable_writers()=s, client_rpc_entry_points()=s, client_write_grants()=s, culture_refuses(text,text[])=i, current_player_id()=s, port_offered_goods(uuid)=s`.

After the deploy: `select to_regprocedure('world.money_feed(timestamptz, int)') is not null as live, (select indisvalid from pg_index where indexrelid = to_regclass('public.treasury_flows_created_at')) as index_ok`
reads `true true`; the Stats Overview shows the Money log moving within a second of a trade.

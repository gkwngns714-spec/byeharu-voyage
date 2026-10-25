# 2026-10-26 — The figures keep to the second: one counter kept by every writer, a 1-s read (owner row 200, `osn-stats-live`, migration 0224)

> *"i told you that stats, i want to be updated every second, is this possible? right now it updates every 10? 15 min?"*
> (2026-10-25, docs/OWNER_REQUESTS.md row 200 — the third time; it REPLACES row 187's default of a 15-minute rollup
> re-asked once a minute.)

Server + client, one slice. `supabase/migrations/20260818000224_the_figures_keep_to_the_second.sql` (renumbers to prod
head + 1 at deploy — 0222 is on main, 0223 is ahead in the queue; `_0224` suffixes, the probe uuid and the tags go with it).

## What the owner sees

- The **RIGHT NOW** band on every Stats face: your money, **all money in the world**, **fleets at sea**, **trades since the
  last count** — the last three from the server's live counters, re-asked every second while the tab is open, each figure
  walking to its new value.
- **Overview**: the holders (players, merchants, cities, set aside) and the hero total are live; the money chart's last
  point moves at the right edge; the sold / bought charts' last point is the period in progress; "Trades, 24 h" adds
  the trades since the count.
- **Merchants**: "Their money" is live; the fleets-at-sea line's last point is live.
- The title's trailing line reads **"Last count N ago"** (was "Updated N ago"), measured as a gap on the one clock.
- Nothing else changed: the 15-minute rollup, the history tables, the charts' past points, the city gate.

## The shape (and why not one UPDATE on one row)

| piece | what |
|---|---|
| `public.stats_live` | ONE row: the figures as of the last count (`counted_through`, `counted_at`), `drift` of the last fold. Written by the fold alone. |
| `public.stats_live_deltas` | the journal: one row per change since the count, INSERTED by the helper in the writer's own transaction. Folded and deleted every count. No index; at most one slot's worth of rows. |
| `public.stats_live_add(jsonb)` | THE ONE helper. `{"players": -1234, "trades": 1, …}`; an unknown figure name raises; all-zero writes nothing. |
| `public.stats_live_track()` | one trigger function on `fleets` (status crossing SAILING), `trade_contracts` (open escrow), `city_shares` (accrued) → the helper. |
| `public.stats_live_fold(p_through, p_seed)` | the reconcile, ONE statement: delete the journal (returning its sums), recompute the five state aggregates, count the trades stamped after `p_through`, set the row — one snapshot, so a transaction is in all of them or none. State figures are SET to the aggregate; `drift` keeps base + journal − aggregate (expected 0; a non-zero state drift raises a WARNING). Called by `tick_stats` on its return. |
| `world.stats_now()` | the read: base + Σ journal in one statement. `authenticated`; registry +1. |

**Why a journal, not `update stats_live set x = x + d`:** an UPDATE holds the row lock to commit. The merchants' tick
credits house after house for seconds in one transaction; a player's sale takes the harbour's advisory lock
(`treasury_post`) before it would reach the row. One shared row locked LATE by transactions that already hold other
locks in different orders is a deadlock waiting for a busy evening (Postgres would abort one side after 1 s — a failed
tick, or a player's trade refused for no reason of the game's). An INSERT takes no shared lock: writers never wait on
each other for a figure, and the read sums at most 15 minutes of rows.

## Who keeps which figure (one authority each)

| figure | authority hooked | hunk |
|---|---|---|
| players, merchants (money) | `public.credit` — THE ONE money mover (0004's deferred constraint triggers make any other write of `ducats` fail) | 2: read `is_npc` in the `for update` select; call the helper after the ledger insert |
| cities (money) | `public.treasury_post` — the one writer of a city's money | 1: after the flow insert |
| set_aside | the tables `trade_contracts` (open escrow) and `city_shares` (accrued) through the trigger — escrow and accrued are written by four bodies (tick_contracts, run_fulfil, tick_city, collect_coupons); the table is the one place they all pass | 0 (trigger) |
| at_sea, at_sea_merchants | `fleets.status` through the trigger — depart, settle, divert, tow each write it; a transition counted at the table cannot miss a writer | 0 (trigger) |
| trades, units, sold, bought — SINCE THE LAST COUNT | `cmd.do_sell`, `cmd.do_buy` — every sale and purchase in the game (a merchant's lap goes `cmd.advance → cmd.execute_order →` the same two; `cmd.preview`'s dry run rolls its journal row back with everything else). A trade is what 0214 counts: a SOLD / BOUGHT event of a goods row | 1 each |
| the fold on every count | `public.tick_stats` | 1: `'live', public.stats_live_fold(p_now)` on the return |
| the registry | `public.client_rpc_entry_points` | 1: `('world', 'stats_now', '')` after `sea_conditions` |

**Also fixed in `tick_stats` (one hunk):** 0214's `set_aside` summed EVERY request's escrow, fulfilled and expired rows
included (a lapsed escrow is posted back to the city as `BOUNTY_LAPSED` and the row keeps its figure until pruned). The
rollup now sums OPEN requests only — the same sum the live figure keeps — so the two agree.

**Not made live, said plainly (decided by default):** minted / removed / moved by kind stay a 15-minute period figure
(their per-kind history is rolled into the daybook and carried; no state aggregate can reconcile them). A price index
stays per slot: every price is re-drawn per slot (0013) and only trades move one between slots. "Players online" is not
a figure this game keeps (no presence column exists) and is not invented here.

## The client: one live path

- `src/features/stats/statsLive.ts` — `useStatsLive()`: `world.stats_now()` every `STATS_LIVE_MS` (1,000) while
  `StatsScreen` is mounted; a hidden document skips the ask; an ask on the wire is never stacked. The answer's
  `counted_at` moving is the `count` beat every face hands its rollup read as `trigger` — the count's own word that a
  new row exists, not a clock's guess.
- **Deleted:** `statsPulse.ts` (the 60-s backstop, the computed edge of the next count with its 20-s grace,
  `servedNow`, `StatsServed`) and `STATS_REFRESH_MS`. Every face lost its `onServed` plumbing. `useReaskAtEdge` stays
  (PortAcademy and the desk use it).
- `withLivePoint(series, at, value)` in `statsFaces.ts` — the one place a chart gains its live last point.
- Words (`src/lib/i18n/dict/stats.ts`): `updated` → "Last count {time} ago" / "{time} 전 집계"; `tradesSince` "Trades since
  count" / "집계 후 거래"; `nextIn`, `fleetsInPort`, `cargoCarried` deleted with the cells that printed them.

## Measured (local PGlite, Postgres 18 wasm, the prod-shaped cached world; `clock_timestamp` here has ms resolution)

From the migration's own receipt, 6 calls each in ONE session:

| what | before the hooks | after the hooks |
|---|---|---|
| `world.stats_now()` | — | 0, 0, 0, 0, 0, 0 ms |
| `cmd.do_sell` (qty 1) | 6, 3, 4, 4, 5, 4 ms | 2, 3, 2, 2, 2, 2 ms |
| `cmd.do_buy` (qty 1) | 7, 6, 5, 5, 3, 3 ms | 4, 4, 5, 4, 4, 5 ms |
| the status write a departure / arrival makes | 0, 0, 0, 0, 0, 0 ms | 0, 0, 0, 1, 0, 0 ms |

The added cost per write is below this clock's resolution (a sale now does six extra INSERTs into an unindexed table:
IMPORT_DEMAND, SELL, TAX, WAGES flows, the purse credits, the trade row). The "before" sale is slower only because it is
the session's first — the warm-up. The prod timing block below measures the same six on the real server before the deploy.

Checks run: `npx tsc -b`, `npx eslint .`, `npm run build` (world image certified), the migration's self-assert on the
cached chain (0222 → 0224), and the specs listed in the PR.

## PROD CHECKS FOR THE MAIN SESSION

Read-only; every function called is `stable` or `immutable`; one statement per block; no trailing semicolons; no
dollar-quoting. Run each block on its own.

```sql
begin transaction read only
```

(1) not applied yet; 0214 is there
```sql
select (select count(*) from pg_class where relname = 'stats_live') as stats_live_tables, (select count(*) from pg_class where relname = 'stats_world') as stats_world_tables
```
expect `0, 1`.

(2) every hunk occurs exactly once in the live body (length / replace counts on single-quoted key lines)
```sql
select (length(d) - length(replace(d, 'select ducats into v_before from public.players where id = p_player for update;', ''))) / length('select ducats into v_before from public.players where id = p_player for update;') as credit_h1, (length(d) - length(replace(d, 'values (p_player, p_kind, p_delta, v_after, p_ref_event);', ''))) / length('values (p_player, p_kind, p_delta, v_after, p_ref_event);') as credit_h2 from (select pg_get_functiondef('public.credit(uuid, text, bigint, uuid)'::regprocedure) as d) z
```
expect `1, 1`.
```sql
select (length(d) - length(replace(d, 'values (p_port, p_kind, p_delta, p_player, p_ref_event);', ''))) / length('values (p_port, p_kind, p_delta, p_player, p_ref_event);') as treasury_post_h1 from (select pg_get_functiondef('public.treasury_post(uuid, text, bigint, uuid, uuid, boolean)'::regprocedure) as d) z
```
expect `1`.
```sql
select (length(d) - length(replace(d, 'perform public.captain_xp_credit(p_fleet, 0, q.total / public.wc_num(''fame_ducats_per_point''), 0);', ''))) / length('perform public.captain_xp_credit(p_fleet, 0, q.total / public.wc_num(''fame_ducats_per_point''), 0);') as do_sell_h1 from (select pg_get_functiondef('cmd.do_sell(uuid, jsonb)'::regprocedure) as d) z
```
expect `1`.
```sql
select (length(d) - length(replace(d, 'perform public.captain_xp_credit(p_fleet, 0, q.total / public.wc_num(''fame_ducats_per_point''), 0);', ''))) / length('perform public.captain_xp_credit(p_fleet, 0, q.total / public.wc_num(''fame_ducats_per_point''), 0);') as do_buy_h1 from (select pg_get_functiondef('cmd.do_buy(uuid, jsonb)'::regprocedure) as d) z
```
expect `1`.
```sql
select (length(d) - length(replace(d, 'coalesce((select sum(c.escrow) from public.trade_contracts c), 0) + coalesce((select sum(s.accrued) from public.city_shares s), 0),', ''))) / length('coalesce((select sum(c.escrow) from public.trade_contracts c), 0) + coalesce((select sum(s.accrued) from public.city_shares s), 0),') as tick_stats_h1, (length(d) - length(replace(d, '''city_goods'', v_cg, ''merchants'', v_m, ''compacted'', v_x,', ''))) / length('''city_goods'', v_cg, ''merchants'', v_m, ''compacted'', v_x,') as tick_stats_h2 from (select pg_get_functiondef('public.tick_stats(timestamptz)'::regprocedure) as d) z
```
expect `1, 1`.
```sql
select (length(d) - length(replace(d, '(''world'',       ''sea_conditions'',        '''')', ''))) / length('(''world'',       ''sea_conditions'',        '''')') as registry_h1 from (select pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure) as d) z
```
expect `1`.

(3) the probe's preconditions: Lisbon offers a good with stock over 50 the probe can buy; no company by the probe's name
```sql
select count(*) as lisbon_goods from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id where p.code = 'LIS' and pg.stock > 50 and not public.culture_refuses(p.culture, g.culture_mask) and exists (select 1 from public.port_offered_goods(pg.port_id) o where o.good_id = pg.good_id)
```
expect `> 0`.
```sql
select count(*) as probe_names from public.players where company_name = 'Casa do Segundo 0224'
```
expect `0`.

(4) the aggregates the seed will read (for the after-check), and the size of what the fold will sum each count
```sql
select (select sum(ducats) from public.players where not is_npc) as players, (select sum(ducats) from public.players where is_npc) as merchants, (select sum(ducats) from public.port_treasury) + (select coalesce(sum(ducats), 0) from public.treasury_flows) as cities, (select coalesce(sum(escrow), 0) from public.trade_contracts where status = 'open') as set_aside_open, (select coalesce(sum(escrow), 0) from public.trade_contracts) as set_aside_0214, (select count(*) from public.fleets where status = 'SAILING') as at_sea
```
`set_aside_0214 − set_aside_open` is the figure 0214 over-counted until now.
```sql
select count(*) as flows_15min, count(distinct kind) as kinds from public.treasury_flows where created_at > now() - interval '15 minutes'
```
```sql
select count(*) as ledger_15min from public.ledger where created_at > now() - interval '15 minutes'
```
The journal will hold about `flows_15min + ledger_15min + trades` rows between counts: that is what `stats_now()` sums.

(5) timings: the trade writer as it is TODAY, 6 sales in one session, as clock_timestamp diffs. It calls volatile
functions, so it runs in its OWN read-write transaction that ends in `rollback` — never under the read-only one above.
One statement per block, in this order.
```sql
rollback
```
```sql
begin
```
```sql
select public.new_house('00000000-0224-4000-8000-000000000001', 'Casa do Segundo 0224', 'PRT', 'LIS') as probe_player
```
```sql
select public.fleet_load((select f.id from public.fleets f join public.players p on p.id = f.player_id where p.company_name = 'Casa do Segundo 0224' order by f.id limit 1), (select g.code from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id where p.code = 'LIS' and pg.stock > 50 and not public.culture_refuses(p.culture, g.culture_mask) and exists (select 1 from public.port_offered_goods(pg.port_id) o where o.good_id = pg.good_id) order by g.code limit 1), 60, 1) as loaded
```
```sql
select i, t.t0, cmd.do_sell((select f.id from public.fleets f join public.players p on p.id = f.player_id where p.company_name = 'Casa do Segundo 0224' order by f.id limit 1), jsonb_build_object('good', (select g.id from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id where p.code = 'LIS' and pg.stock > 50 and not public.culture_refuses(p.culture, g.culture_mask) and exists (select 1 from public.port_offered_goods(pg.port_id) o where o.good_id = pg.good_id) order by g.code limit 1), 'qty', 1)) is not null as sold, clock_timestamp() - t.t0 as took from generate_series(1, 6) i cross join lateral (select clock_timestamp() as t0 where i > 0) t
```
`took` per row is one sale's cost today (the first row is the session's warm-up); the same six after the deploy, in the
same shape, is the added cost. Then
```sql
rollback
```

(6) the walls
```sql
select (select count(*) from public.client_write_grants()) as w, (select count(*) from public.client_executable_writers()) as x, (select count(*) from public.caller_evaluated_functions()) as c
```
expect `0 0 0`.

After the deploy (30-minute after-check): `select world.stats_now()` six times in one session and read the `ms`
(target under 5 ms); `select drift, folded, counted_at from public.stats_live` after the first count — every state
drift 0 and `folded` about the journal size measured in (4); `select (public.tick_stats(now()))->'live'` is NOT to be
run by hand (it writes). Open the Stats tab and watch the RIGHT NOW band's world money move within a second of any
merchant's sale.

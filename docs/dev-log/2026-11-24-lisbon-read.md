# 2026-11-24 — 0487 the Lisbon read plans once (no switch; the same answers)

## The problem
- On prod, `world.best_sales(fleet, port)` at Lisbon takes 2.5-2.7 s, and its own 2.5 s budget often cuts it (the goods after the cut
  are not answered).
- The HQ board (`world.hq_board()` → `public.hq_board_for`) and the standing fleet jobs wait on it, so HQ opens in about 3 s.
- The same call on the local PGlite chain takes 0.3-0.4 s. 0482 cached the reach matrix and read the hulls once: -20 % locally, almost
  nothing on prod.

## What prod showed (three read-only reads, 2026-11-24, the gate first)
Prod was green: beat 133 ms, 768 of 1,500 MB, no session waiting on the disk. Every function `world.best_sales` calls (94, traced on the
chain) is STABLE on prod, so the reads below were allowed.

1. **The gate, the server, pg_stat_statements** (`scripts/ops/harness/lisbon-read/diagnose-1.sql`).
   - Prod is **PostgreSQL 17.6**: shared_buffers 256 MB, jit off, track_functions none, track_io_timing off, pg_stat_statements.track top.
   - The board's `best_sales` call through PostgREST: 208 calls, **mean 2,271 ms**, 33,600 buffer hits and 525 reads a call.
   - `port_goods`: 159,766 live and 189,253 dead rows, 10,721 pages (fillfactor 30, HOT updates; not vacuumed, by design).
2. **EXPLAIN (ANALYZE, BUFFERS)** of one Lisbon read and its parts, the same statement on prod and on the local chain (run once from a
   scratch file: the harness guard rightly refuses `explain analyze` in a harness file).

   | Part | Prod (17.6) | Local PGlite (18.3) | Prod / local |
   | --- | --- | --- | --- |
   | `world.best_sales` at Lisbon, once | **2,706 ms** (100,094 hits, 993 reads) | 391 ms (60,285 hits, 3,610 reads) | 6.9x |
   | 80 sell quotes (`world.quote`) | 280.6 ms | 35.5 ms | 7.9x |
   | `world.good_mids` for Lisbon's 10 goods (2,540 market rows) | 73.7 ms | 13.1 ms | 5.6x |
   | `world.board_origin` | 75.3 ms | 21.9 ms | 3.4x |
   | 500 `voyage.fleet_speed_of` | 54.7 ms | 27.4 ms | 2.0x |
   | 100 `public.crew_pct` | 7.5 ms | 7.3 ms | 1.0x |
   | 2,000 `public.wc` | 31.0 ms | 7.7 ms | 4.0x |

3. **The quote's parts, timed** (`diagnose-2.sql`): 80 calls each, the newest company's idle fleet at Lisbon, prod's switches.

   | Read (80 calls) | Prod | Local, dark switches |
   | --- | --- | --- |
   | `world.quote`, a sell of 20 | 316.4 ms (3.95 ms a call) | 60 ms |
   | `world.want_left` | **149.6 ms (1.87 ms a call)** | 8 ms (0.1 ms) |
   | `world.daily_cap_remaining` | 139.4 ms | 13 ms |
   | `public.port_fee` | 99.8 ms | 2 ms |
   | `world.quote_terms` | 93.9 ms | 23 ms |
   | `world.price` | 93.7 ms | 12 ms |
   | `world.spread_effective_pair` | 55.4 ms | 18 ms |
   | `public.profit_tax` | 46.6 ms | 1 ms |
   | `public.city_bid_factor` | 32.3 ms | 1 ms |
   | `world.spread` | 32.0 ms | 5 ms |
   | `public.crew_pct` | 5.8 ms | 5 ms |
   | `public.treasury_balance` | 5.2 ms | 1 ms |
   | `public.fleet_buy_capacity` (10 calls) | 126.5 ms | 34 ms |
   | `public.wc` (800 calls) | 19.3 ms | 3 ms |

   auto_explain (10 s, no analyze), pgaudit (`none`) and plpgsql_check (profiler off) are loaded but not in the way.

### Where the time goes
- **Not the disk.** 1 % of the read's buffers came from outside shared_buffers. `port_goods`' dead rows cost little: each good's 254
  market rows are read in 1.7 ms on prod.
- **The CPU, in about 30,000 small function calls a read.** A Lisbon read on the chain makes 196 quotes (154 sells, 42 buys), 283 dock
  fees, 154 profit taxes and about 13,800 knob reads (`wc`). Prod pays about 4-8x local for each small call.
- **Most of the gap is the server version.** Prod runs PostgreSQL 17.6; the local PGlite runs 18.3.
  - PostgreSQL 17 plans a SQL-language function's body again every time it is called from inside a query. A SECURITY DEFINER function
    with `SET search_path` is never inlined, and its plan lasts only as long as the calling query's run.
  - PostgreSQL 18 keeps that plan in the plan cache. So the local chain never showed this cost.
  - That is why `crew_pct` (plpgsql, no SQL function under it) costs the same on both, while `want_left` costs 26x: it is SQL and asks
    five more SQL functions (`wants_lit`, `want_period` twice, `event_want`, and under them `clock_count`, `economy_closed`,
    `world_events_on`). That is about ten plannings a call.
  - Every sell quote of a market row a want was ever drawn on asks `want_left`: 155 times a Lisbon read. Prod's rows carry the marker;
    the local chain's carry none, so locally the call never ran.
  - A Lisbon read makes about 9,000 calls to non-inlined SQL functions.

## What it does
- **27 small SQL readers become plpgsql.** Each one's SQL body is kept word for word, so PostgreSQL 17 keeps its plans for the session.
  PostgREST's pooled sessions live long, so the planning is paid once instead of at every call.
  - The 27 are every SQL reader of this kind that a Lisbon read calls 15 times or more (traced on the chain with prod's switches lit):
    - switches: `economy_closed`, `city_treasury_on`, `ship_stores_separate`, `regard_on`, `world_events_on`, `nation_race_on`,
      `price_impact_lit`, `wants_lit`, `pirates_on`;
    - a harbour's: `port_is_free`, `pirate_home`, `world_event_toll`, `treasury_balance`, `city_bid_factor`, `works_factor`;
    - a house's: `crown_house`, `running_cost_mult`, `regard_band`;
    - the stores: `stores_in_hold`, `voyage.stores_need_days`, `npc_leg_days`, `voyage.fleet_speed_of`;
    - the clock: `clock_count`, `want_period`, `world.game_day`;
    - the wants: `event_want`, `world.want_left`.
  - Each was LANGUAGE sql, STABLE, SECURITY DEFINER, `SET search_path = public, pg_temp` and not STRICT. The migration asserts all of
    this, and the md5 of each body, before it changes anything.
- **One rule makes each conversion**, from the function's own live definition (`pg_get_functiondef`):
  - `LANGUAGE sql` becomes `LANGUAGE plpgsql`;
  - a scalar body becomes `#variable_conflict use_column` / `begin` / a 0487 comment / `return (<body>` / `);` / `end`;
  - the two set-returning bodies (`event_want`, `want_left`) become `return query <body>` / `;` instead.
- Nothing else moves: name, arguments, defaults, return type, STABLE, SECURITY DEFINER, search path, owner and grants (CREATE OR REPLACE
  keeps them; asserted). No table, no row, no knob, no cron job and no new function are added, so nothing needs revoking from
  `service_role`. The self-assert checks that no client role and no `service_role` can now run a reader it could not run before.
- No switch: it changes no answer.

## Why the answers are the same
- **By construction.**
  - Every scalar body is one `select` that gives one row: no FROM, or an aggregate, EXISTS or `LIMIT 1`. `return (select ...)` answers
    that row's value, or null when there is none, as the SQL function did.
  - `return query` answers the set body's rows in the same order.
  - `#variable_conflict use_column` is SQL's own rule: a column of the query wins over an argument with the same name.
  - Both versions are STABLE and read the caller's snapshot; `now()` is the transaction's.
- **The self-assert** (rolled back by a sentinel) works on a new house at Lisbon:
  - It lights the read's switches for the probe, only where they are not already on (on prod they all are).
  - It asks everything before the conversion (SQL), converts inside the probe, asks again (plpgsql) and compares to the byte.
  - **The 27 readers** are asked over their inputs, with the switches as they are and lit: every harbour; houses (hers, 40 others, 20
    merchants, crown, navy and pirate houses); regard scores from -1000 to 1000; stores and speeds; four clocks at five instants; the
    wants of every 16th harbour for every good Lisbon sells.
  - **The Lisbon read's pieces** are asked lit: `world.board_legs`; for each of the 10 goods `world.board_sell` with the read's own
    context, `public.fleet_buy_capacity` and `world.daily_cap_remaining`; 160 sell quotes; the dock fee and profit tax at 254 harbours.
  - Then it converts for real, checks that each new body is the one the probe tried and reverses to the old body md5 for md5, and runs
    the catalog checks.
- **Proof 190** turns the 27 back into SQL inside its own transaction. Each body is unwrapped from its 0487 wrapper, giving exactly the
  function 0487 found (md5 checked). It then compares:
  - all 268 ports; all 861 houses; 687 regard scores; 42 store and speed inputs; 876 fleets' speeds; 24 clock readings; 2,560 wants
    (every 4th harbour × 40 goods); with the switches as they are and lit;
  - the pieces at Seville and at Lisbon with a captain seated (lit): board_legs; for 20 goods board_sell, board_trips, buy capacity and
    day cap; 1,020 quotes, sell and buy; dock fee and profit tax at 254 harbours.
  - Everything is the same.
- `world.best_sales` itself (time-budgeted) is never compared with a second call. Its sameness is its pieces'.

## Measured
- **Prod, before** (2026-11-24): `best_sales` at Lisbon 2,706 ms (EXPLAIN ANALYZE), 2,271 ms mean over 208 board calls
  (pg_stat_statements); want_left 1.87 ms a call, a sell quote 3.95 ms.
- **Local PGlite (PostgreSQL 18.3), before → after:** no gain, as expected (18 already caches a SQL body's plan).
  - the self-assert's pieces: 578 → 537 ms;
  - the readers lit: 71 → 72 ms;
  - `before-0487.sql` / `after-0487.sql` on the chain with prod's switches: best_sales 474 → 386 ms. This is one call each, the first
    one cold; the comparable 3-call medians earlier were about 380 ms either way.
- **PostgreSQL 17 (CI's disposable chain), before → after:** see "CI" below. The self-assert prints the pieces timed both ways on the
  server it runs on.
- **Prod, after:** the push's own self-assert notice (the pieces before and after, timed on prod), and `after-0487.sql`.
- **Expected on prod:** about 9,000 SQL plannings a Lisbon read go away. `want_left` should fall from 1.87 ms toward a plpgsql
  function's 0.1-0.3 ms; that is 155 calls, about 0.25 s, on its own. With the switches' and fees' plannings, `best_sales` at Lisbon
  should fall by several hundred ms, below its 2.5 s budget. This is an estimate until `after-0487.sql` measures it.

## CI
(filled in from the PR's disposable-chain log)

## Load
- No rows, no tables, no cron job, no step on the beat. The self-assert reads (and lights switches only where they are off, rolled back).
- Every other caller of the 27 (the beat, the voyages, the trade, HQ) gets the same answers. It should also get faster.

## Decided by default (the owner may reverse)
- **Converted, not rewritten.** Each body is kept word for word inside a plpgsql wrapper. No reader was restructured, so the one
  authority for each rule stays where it was.
- **27 readers, not every SQL function.** These are the ones the Lisbon read calls 15 times or more. Less-called SQL readers on other
  paths (`fleet_free_hold`, `ship_hold_capacity`, ...) stay SQL.
- **No memo across goods.** Splitting `port_fee` / `profit_tax` / `quote_terms` into per-harbour terms would save about 15 % more on
  prod. But it changes the money authorities' shape, so it was left out.

## Prod checks
- Before: `scripts/ops/harness/lisbon-read/before-0487.sql` (expect head 0486; 27 readers, sql 27, md5_ok 27; the costs).
- After (and 30 minutes after): `scripts/ops/harness/lisbon-read/after-0487.sql` (expect head 0487; plpgsql 27, md5_ok 27;
  `best_sales_ms` below the 2,706 ms of before; `cut` false).

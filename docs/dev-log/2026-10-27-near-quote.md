# 2026-10-27 — 0251: the board prices the near cities (`osn-near-quote`, owner row 234 / 231)

**The gap.** The Sell face's cargo list (#348) shows, for each good aboard, "Here" and the cities to sail to with
price · days · profit, from `world.good_board`'s fully priced sell rows. The board priced only its
`good_board_quoted` (10) DEAREST cities, which are mostly a month away. A city two days off had no price or profit.

**The change (one migration, one client file).**
1. `world.good_board` prices a sell row in full when it is among the 10 dearest (as before) OR among the
   `good_board_quoted_near` (5, new knob) nearest rows she can sail to (`sailable`, by the passage miles; where she lies
   counts last). Served `quoted_near`. Every figure is still its own authority's call.
2. The cost offset: `public.passage_needs` answers null within her reach and costs ~1 ms a call on prod even then
   (×246 sell rows + the buy rows). The board reads `passage_reach_nm` once and asks `passage_needs` only past it.
   The self-assert proves every row is the same as before.
3. Client (`src/features/command/buysell/CargoBest.tsx`): the best 3 by profit plus the nearest 3 others, in one list
   sorted nearest first.

**Self-assert** (probe company at Lisbon, rolled back): 7+1 hunks occur once and reverse; ACL/volatility/config
unchanged; cargo board: near rows newly priced (positive control > 0), each with a profit; rows priced before and
rows priced by neither = pre-image byte for byte; rows newly priced are only the nearest sailable ones; rows past
her reach still carry `needs` (positive control); a good not aboard (bought first) obeys the same.

**Local (PGlite, Lisbon, 3 goods × 5, old vs new alternately):** old p50 472 / max 615 ms; new p50 491 / max 733 ms.
The `passage_needs` saving does not show on PGlite (its calls are cheap there); prod is where it pays.
Anise at Lisbon, before: the 10 priced sailable rows were all 40–43 days (Naha…Matsumae). After: Setúbal 0.11 d
(+18), Porto 0.44 d (+17), Sanlúcar 0.69 d (+22), Cádiz 0.7 d (+17), Seville 0.8 d (−2), then the same 10.

## Prod measurements (read-only: `begin transaction read only`, `set local` claims, stable function only)

Three human fleets with cargo × 12 boards (6 of the cargo good, 6 other goods), one session each.

**Before (head 0248, 2026-10-27):**

| fleet / cargo | ms (calls 1–12) |
|---|---|
| Casa do Cais, LIS, dried-fish | 2837 1452 1608 1459 1564 1307 · 1987 1907 2106 2083 2330 1900 |
| 123123, SAK, bonito | 1679 1661 1657 1355 1612 1768 · 2090 2106 1996 1990 1942 1650 |
| Casa Almacen, LIS, anise | 1957 1620 1810 1668 1619 1425 · 1583 1622 1714 1844 1588 1960 |

36 boards: p50 ~1,710 ms, p95 ~2,330 ms, max 2,837 ms (a first call).
Per extra priced row on prod (warm): quote 6–45 ms, profit_tax ~1, daily_cap ~2, price_outlook ~11 → 5 rows ≈ +125 ms.
`passage_needs` ×246 within reach: 183–237 ms → hoisted ≈ −200 ms.

**After (head 0251, deployed ~15:05 UTC, #359 merged 02e59b6):** same three files.

| round | boards | p50 | p95 | max |
|---|---|---|---|---|
| before (0248) | 36 | 1,697 | 2,162 | 2,837 |
| after, first round, right after the deploy (the clock re-wound, jobs catching up) | 36 | 2,035 | 2,875 | 3,124 |
| after, rounds 2–4 (steady) | 108 | 1,650 | 2,054 | 2,410 |

(The table above quotes p95 by linear interpolation; the header's "~2,330" was a by-eye read of the same 36 rows.)
Steady state is at or under the before p95 while every board now prices 15 rows, not 10. Round 1 was slower on every
good, including the cargo boards whose cost did not move, so it was load after the clock was wound back up, not the body.

Read back (Casa Almacen, anise at Lisbon): the priced sailable rows nearest first are now Setúbal 0.11 d, Porto 0.45,
Sanlúcar 0.7, Cádiz 0.71, Seville 0.81, then Fuzhou 39.8 d… (before: the first was 39.8 days away). Their `profit` is
null for this company, as it is on its dearest rows too: its cargo has no recorded cost (`fleet_cargo_basis`), so the list
shows the price. `good_board_quoted_near` = 5.

## PROD CHECKS

Before the push (all `ok = true`; run at head 0248 on 2026-10-27, all true):

```sql
with d as (select replace(pg_get_functiondef('world.good_board(uuid,uuid,uuid,numeric)'::regprocedure), E'\r', '') as b),
h(n, t) as (values
 (1, E'-- anywhere; a sell row shut by the way to that city says so (shut.figures.buy_at).\n'),
 (2, E'  v_quoted  int := public.wc_int(''good_board_quoted'');\n'),
 (3, E'  v_margin := public.wc_num(''endurance_margin'');\n'),
 (4, E'           ''needs'', (select public.passage_needs(v_player, x.direct_nm) from reach x where x.port_id = s.id),\n'),
 (5, E'           ''stops'', to_jsonb(r.stops), ''needs'', public.passage_needs(v_player, r.direct_nm),   -- 0188\n'),
 (6, E'           row_number() over (order by (c.nm is null), c.mid desc, c.nm nulls last, c.code) as rk\n'),
 (7, E'     where r.rk <= v_quoted and u.n > 0\n'),
 (8, E'    ''quoted'', v_quoted,\n'))
select 'hunk ' || h.n as what, (length(d.b) - length(replace(d.b, h.t, ''))) / length(h.t) = 1 as ok from d, h
union all select 'knob good_board_quoted_near absent', not exists (select 1 from public.world_config where key = 'good_board_quoted_near')
union all select 'good_board_quoted is 10', public.wc_int('good_board_quoted') = 10
union all select 'no probe residue 0251', not exists (select 1 from public.players where auth_uid = '00000000-0251-4000-8000-000000000001')
union all select 'good_board volatility s', (select provolatile = 's' from pg_proc where oid = 'world.good_board(uuid,uuid,uuid,numeric)'::regprocedure)
```

Timing (before and after), one file per fleet, e.g. Casa do Cais:

```sql
begin transaction read only;
set local request.jwt.claims = '{"sub": "00000000-0061-4000-8000-000000000001"}';
set local request.jwt.claim.sub = '00000000-0061-4000-8000-000000000001';
select g.n, g.code, b.quoted, b.sellrows, c.ms
  from (select row_number() over () as n, x.id, x.code from (
          select id, code from public.goods cross join generate_series(1,6) where code = 'dried-fish'
          union all
          (select g.id, g.code from public.goods g where g.code <> 'dried-fish' order by md5(g.code || 'q0251') limit 6)) x) g
 cross join lateral (select clock_timestamp() as t0, g.n as n0 offset 0) a
 cross join lateral (select j, a.t0 from (select world.good_board(g.id, '24a94a0f-60b5-4ae2-b591-f0e72e632922'::uuid, null, null) as j offset 0) z) bb
 cross join lateral (select (select count(*) from jsonb_array_elements(bb.j->'sell') e where (e->>'quoted')::boolean) as quoted, jsonb_array_length(bb.j->'sell') as sellrows, bb.t0 offset 0) b
 cross join lateral (select round(extract(epoch from clock_timestamp() - b.t0) * 1000) as ms offset 0) c
 order by g.n;
rollback;
```

After the push: head = 0251; `select public.wc_int('good_board_quoted_near')` = 5; the timing again (p95 must be at
or under the "before" p95); one cargo board's priced near rows read back.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0191 — A BUSY QUAY IS SEEN  (PRICE_FACTORS slice P2: how much of a good changed hands here today)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-18: *"is there a way for the prices move on many different factors? like … merchants"*.
-- docs/PRICE_FACTORS.md §3.4 / §6 P2: merchants' crowding is already FELT (every sale walks the stock term
-- down, 10 at a time) but never SEEN — 800-odd merchant companies trade the same goods and the desk shows no
-- trace of them. EVE and RuneScape print each item's volume beside its price (§1.2, §1.3); this is that line.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) public.traded_today(port, good) — NEW leaf (server-only, STABLE): the units of this good bought and
--     sold here in the current game day, and by how many companies, read from public.trade_daily — the
--     one record cmd.do_buy and cmd.do_sell already write per (company, port, good, game day) for the
--     daily cap (DESIGN G.7.1). Nothing new is stored and no trade path is touched.
-- (2) world.price_why (0185) serves it: `volume: {game_day, units, houses}`. One hunk, sliced from the
--     live body; reverses; ACL / owner / volatility / definer / config unmoved.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Move any price (that is P5, the glut), store a counter (a counter drifts from the record it counts —
-- the 0014 rule), or split buys from sells (trade_daily holds their sum, which is what a volume is).
-- Only TODAY is counted: npc_compact deletes past game days' trade_daily rows, so a longer window would
-- count players and not merchants.
--
-- ── THE PROOF (own probe company, in a sub-block rolled back whole) ─────────────────────────────
-- A probe company's 37 units at one row add exactly 37 to the read's units and 1 to its houses, and a
-- second 5 add 5 and no house; an earlier game day is not counted; the read's other keys are what they
-- were (the hunk adds one key and touches no other); the leaf is server-only and STABLE.
-- ROLLBACK: a forward slice reversing the hunk (old text below) and dropping public.traded_today.
-- VERSION: 0191 PROVISIONAL — prod head 0186 when written (2026-10-19; deploy order fixed by the coordinator: 0187 great powers, 0188 plan-reach-2, 0189–0190 auto-fight, then this); renumbered to head + 1 at push.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0191(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table before_0191 on commit drop as
select replace(pg_get_functiondef('world.price_why(uuid, uuid)'::regprocedure), E'\r', '') as def,
       (select row(coalesce(p.proacl::text, ''), p.proowner, p.provolatile, p.prosecdef, coalesce(p.proconfig::text, ''))::text
          from pg_proc p where p.oid = 'world.price_why(uuid, uuid)'::regprocedure) as meta,
       (select count(*) from public.client_rpc_entry_points()) as entry_points;

do $$
begin
  if to_regprocedure('public.traded_today(uuid, uuid)') is not null then
    raise exception '0191 self-assert FAIL: public.traded_today already exists';
  end if;
end $$;

-- ── 1. THE LEAF ───────────────────────────────────────────────────────────────────────────────
create function public.traded_today(p_port uuid, p_good uuid, out units numeric, out houses int)
returns record
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0191: WHAT CHANGED HANDS HERE TODAY — the units of this good bought and sold at this port in the
  -- current game day, and by how many companies (players and merchants alike), from public.trade_daily:
  -- the one record cmd.do_buy / cmd.do_sell write per (company, port, good, game day). Derived per read.
  select coalesce(sum(td.qty), 0), count(distinct td.player_id)::int
    from public.trade_daily td
   where td.port_id = p_port and td.good_id = p_good and td.game_day = world.game_day()
$$;
revoke all on function public.traded_today(uuid, uuid) from public, anon, authenticated;

-- ── 2. world.price_why SERVES IT (one hunk, sliced from the live body; reverses) ──────────────
create temp table hunks_0191 (n int, old text, new text) on commit drop;
insert into hunks_0191 values
(1,
$h$    'fee', jsonb_build_object('spread', q.spread, 'tax', q.tax, 'bid_factor', q.bid_factor,$h$,
$h$    -- 0191: what changed hands here today (public.traded_today — the daily-cap record, bought + sold)
    'volume', (select jsonb_build_object('game_day', world.game_day(), 'units', v.units, 'houses', v.houses)
                 from public.traded_today(p_port, p_good) v),
    'fee', jsonb_build_object('spread', q.spread, 'tax', q.tax, 'bid_factor', q.bid_factor,$h$);

do $$
declare
  b     record;
  h     record;
  v_rev text;
begin
  select * into b from before_0191;
  select * into h from hunks_0191 where n = 1;
  if pg_temp.occurs_0191(b.def, h.old) <> 1 then
    raise exception '0191 self-assert FAIL: world.price_why hunk occurs % time(s), not once — the deployed body is not what this file was written against',
      pg_temp.occurs_0191(b.def, h.old);
  end if;
  execute replace(b.def, h.old, h.new);
  v_rev := replace(pg_get_functiondef('world.price_why(uuid, uuid)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0191(v_rev, h.new) <> 1 or replace(v_rev, h.new, h.old) <> b.def then
    raise exception '0191 self-assert FAIL: world.price_why does not reverse to its pre-image';
  end if;
  if (select row(coalesce(p.proacl::text, ''), p.proowner, p.provolatile, p.prosecdef, coalesce(p.proconfig::text, ''))::text
        from pg_proc p where p.oid = 'world.price_why(uuid, uuid)'::regprocedure) <> b.meta then
    raise exception '0191 self-assert FAIL: world.price_why''s ACL, owner, volatility, definer or config moved';
  end if;
end $$;

-- ── 3. THE PROOF (a probe company, rolled back whole) ─────────────────────────────────────────
do $$
declare
  c_uid  constant uuid := '00000000-0191-4000-8000-000000000001';
  v_p    uuid;
  v_port uuid;
  v_good uuid;
  j0     jsonb;
  j1     jsonb;
  j2     jsonb;
  v_out  text;
begin
  select pg.port_id, pg.good_id into v_port, v_good
    from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id
   where p.code = 'LIS' order by g.code limit 1;
  begin
    v_p := public.new_house(c_uid, 'Casa do Cais 0191', 'PRT', 'LIS');
    j0 := world.price_why(v_port, v_good);
    insert into public.trade_daily (player_id, port_id, good_id, game_day, qty)
    values (v_p, v_port, v_good, world.game_day() - 1, 1000);                      -- yesterday: not counted
    insert into public.trade_daily (player_id, port_id, good_id, game_day, qty)
    values (v_p, v_port, v_good, world.game_day(), 37);
    j1 := world.price_why(v_port, v_good);
    update public.trade_daily set qty = qty + 5
     where player_id = v_p and port_id = v_port and good_id = v_good and game_day = world.game_day();
    j2 := world.price_why(v_port, v_good);
    if (j1->'volume'->>'units')::numeric - (j0->'volume'->>'units')::numeric <> 37
       or (j1->'volume'->>'houses')::int - (j0->'volume'->>'houses')::int <> 1
       or (j2->'volume'->>'units')::numeric - (j1->'volume'->>'units')::numeric <> 5
       or (j2->'volume'->>'houses')::int <> (j1->'volume'->>'houses')::int
       or (j1->'volume'->>'game_day')::int <> world.game_day() then
      raise exception '0191 self-assert FAIL: the volume did not count the probe''s trades: % → % → %', j0->'volume', j1->'volume', j2->'volume';
    end if;
    if (j1 - 'volume' - 'clock') <> (j0 - 'volume' - 'clock') then
      raise exception '0191 self-assert FAIL: the hunk moved a key other than volume: % vs %', j0, j1;
    end if;
    v_out := format('%s → %s → %s', j0->'volume', j1->'volume', j2->'volume');
    raise exception using errcode = 'ZX186', message = v_out;
  exception when sqlstate 'ZX186' then
    v_out := sqlerrm;
  end;
  if exists (select 1 from public.players where id = v_p) then
    raise exception '0191 self-assert FAIL: the probe company survived its rollback';
  end if;
  if has_function_privilege('anon', 'public.traded_today(uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.traded_today(uuid, uuid)', 'execute')
     or (select provolatile from pg_proc where oid = 'public.traded_today(uuid, uuid)'::regprocedure) <> 's'
     or (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0191)
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0191 self-assert FAIL: the leaf is reachable or not STABLE, or the registry or a wall moved';
  end if;
  raise notice '0191 self-assert ok: A BUSY QUAY IS SEEN. public.traded_today (server-only, STABLE) from public.trade_daily; world.price_why serves volume {game_day, units, houses} (one hunk, reverses). Probe at LIS: %; yesterday not counted; no other key moved; registry unchanged.', v_out;
end $$;

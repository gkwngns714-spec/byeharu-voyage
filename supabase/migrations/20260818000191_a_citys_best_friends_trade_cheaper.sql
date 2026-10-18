-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0191 — A CITY'S BEST FRIENDS TRADE CHEAPER  (PRICE_FACTORS slice P3: the investor's spread shave)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-18: *"is there a way for the prices move on many different factors? like relationship
-- with other countries, religion, merchants, any more ideas?"*; and 2026-10-17 (docs/INFLUENCE.md O3): leading
-- a city earns *"cheaper trade"* there. 0147 built the COUNTRY's half (a citizen of the holder pays half the
-- profit tax). docs/PRICE_FACTORS.md §3.3 / F6 adds the COMPANY's own half, borrowed from Uncharted Waters
-- Online — a city's investors ranked 1–5 get 10 / 8 / 6 / 4 / 2 % off (Inven 2597/147) — and EVE, where
-- standing with a station's owner lowers its broker fee.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) public.investor_rank(player, port) — NEW leaf: the company's place among this city's givers by its
--     points in the influence book (public.port_influence, 0144; every country's rows summed per company;
--     decays 10 % a day, D6). Null when it holds no points here. 1 + the companies with more.
-- (2) public.investor_shave(player, port) — NEW leaf: the knob influence_investor_shave's entry for that
--     rank (default [0.10, 0.08, 0.06, 0.04, 0.02]); 0 past rank 5, with no points, or while the race is off
--     (public.influence_on()).
-- (3) world.spread_effective (the ONE per-company spread, 0017/0022/0083/0161) multiplies by
--     (1 − investor_shave) beside the purser and the bargain — multiplicative (Decision 5), and the port's
--     floor (haggle_spread_floor_frac, Decision 6) still holds whatever stacks. With or without the bargain
--     (it is a standing, not a bargain). Two hunks, sliced from the live body.
-- (4) world.price_why (0185) serves the caller's own stake: `stake: {rank, shave}` (null with no company
--     signed in or no points here). One hunk.
-- Every quote, plan, board and the merchants' planner already prices through world.spread_effective, so they
-- all see it without a second path. A merchant that leads a city's givers trades cheaper there too.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Touch the market price (everyone's), the profit tax or 0147's citizen cut, the influence book, the daily
-- evaluation or any grant. Store a rank (a rank is read from the book it ranks; the book has at most a few
-- dozen rows a city, read by its primary key's leading column).
--
-- ── THE PROOF (two probe companies, in a sub-block rolled back whole) ───────────────────────────
-- With the race on: a probe company with no points pays exactly what it paid before this file; given points
-- above every company in a city it ranks 1 and its spread there is (1 − 0.10) × what it was (or the floor);
-- a second probe with points just below it ranks 2 and pays (1 − 0.08) ×; elsewhere both pay what they did;
-- price_why's stake names the caller's rank. With the race off every shave is 0. Leaves server-only, STABLE.
-- Timings: raise notice only. COST, measured on prod read-only (2026-10-19, 300 docked fleets): world.spread_effective
-- 2.72 ms a call today; the shave's two reads of the influence book 0.048 ms (~2 %). A company with no points in
-- the city leaves after the first read.
-- ROLLBACK: set influence_investor_shave to '[]' (every shave 0), or a forward slice reversing the hunks.
-- VERSION: 0191 PROVISIONAL — prod head 0189 when re-checked (2026-10-19; the coordinator's order: 0190 PRICE_FACTORS P2,
-- then this; all three hunks occur once on prod at 0189); renumbered to head + 1 at push.
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
select f.ord, f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       (select row(coalesce(p.proacl::text, ''), p.proowner, p.provolatile, p.prosecdef, coalesce(p.proconfig::text, ''))::text
          from pg_proc p where p.oid = f.fn::regprocedure) as meta
  from (values (1, 'world.spread_effective(uuid, uuid, uuid, boolean)'),
               (2, 'world.price_why(uuid, uuid)')) f(ord, fn);
create temp table count_0191 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

do $$
begin
  if to_regprocedure('public.investor_rank(uuid, uuid)') is not null
     or to_regprocedure('public.investor_shave(uuid, uuid)') is not null
     or exists (select 1 from public.world_config where key = 'influence_investor_shave') then
    raise exception '0191 self-assert FAIL: something this file creates already exists';
  end if;
end $$;

-- ── 1. THE KNOB AND THE LEAVES ────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('influence_investor_shave', '[0.10, 0.08, 0.06, 0.04, 0.02]'::jsonb,
   '0191: the share of the spread a company is spared in a city where it ranks 1st, 2nd, … among the givers '
   '(public.port_influence points). Uncharted Waters Online''s investor ranks (10/8/6/4/2 %). [] = none. '
   'docs/PRICE_FACTORS.md §3.3, F6.');

create function public.investor_rank(p_player uuid, p_port uuid)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0191: this company's place among the city's givers by its influence points (every country's rows
  -- summed per company); null when it holds none here.
  with g as (
    select pi.player_id, sum(pi.points) as pts
      from public.port_influence pi
     where pi.port_id = p_port and pi.points > 0
     group by pi.player_id
  )
  select 1 + (select count(*) from g o where o.pts > m.pts)::int
    from g m
   where m.player_id = p_player
$$;

create function public.investor_shave(p_player uuid, p_port uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0191: the share of the spread this company is spared here for its rank among the givers (the knob's
-- entry); 0 past the list, with no points, with no company, or while the race is off. On the quote's hot
-- path (world.spread_effective), so it leaves at the first answer: no company, the race off, no points
-- here (one read of the book's rows for this city by its primary key's leading column).
declare
  v_mine numeric;
  v_list jsonb;
  v_rank int;
begin
  if p_player is null or not public.influence_on() then
    return 0;
  end if;
  select sum(pi.points) into v_mine from public.port_influence pi
   where pi.port_id = p_port and pi.player_id = p_player and pi.points > 0;
  if v_mine is null then
    return 0;
  end if;
  v_list := public.wc('influence_investor_shave');
  select 1 + count(*) into v_rank
    from (select pi.player_id from public.port_influence pi
           where pi.port_id = p_port and pi.points > 0
           group by pi.player_id having sum(pi.points) > v_mine) o;
  if v_rank > coalesce(jsonb_array_length(v_list), 0) then
    return 0;
  end if;
  return (v_list -> (v_rank - 1))::text::numeric;
end $$;

revoke all on function public.investor_rank(uuid, uuid) from public, anon, authenticated;
revoke all on function public.investor_shave(uuid, uuid) from public, anon, authenticated;

-- ── 2. THE HUNKS (sliced from the live bodies; each occurs once; each body reverses) ──────────
create temp table hunks_0191 (ord int, n int, old text, new text) on commit drop;
insert into hunks_0191 values
(1, 1,
$h$  v_trader numeric;   -- 0161
$h$,
$h$  v_trader numeric;   -- 0161
  v_inv    numeric := 0;   -- 0191: the company's standing among this city's givers
$h$),
(1, 2,
$h$  -- Decision 5: MULTIPLICATIVE, so two shaves cannot add up to more than either could win.
  -- Decision 6: and the floor, which the port keeps whatever stacks.
  return greatest(v_pub * public.wc_num('haggle_spread_floor_frac'),
                  v_pub * (1 - v_purser) * (1 - v_hag));$h$,
$h$  -- 0191: a city's leading givers are spared part of the spread (public.investor_shave) — a standing,
  -- not a bargain, so it holds with or without one.
  if v_player is not null then
    v_inv := public.investor_shave(v_player, p_port);
  end if;

  -- Decision 5: MULTIPLICATIVE, so two shaves cannot add up to more than either could win.
  -- Decision 6: and the floor, which the port keeps whatever stacks.
  return greatest(v_pub * public.wc_num('haggle_spread_floor_frac'),
                  v_pub * (1 - v_purser) * (1 - v_hag) * (1 - v_inv));$h$),
(2, 1,
$h$    'clock', jsonb_build_object('now', v_now, 'next_change_at', public.next_drift_change_at(v_now)));$h$,
$h$    -- 0191: the caller's own standing here — its rank among the givers and the share of the spread it is spared
    'stake', (select case when r.rank is not null then
                       jsonb_build_object('rank', r.rank, 'shave', public.investor_shave(public.current_player_id(), p_port)) end
                from (select public.investor_rank(public.current_player_id(), p_port) as rank) r),
    'clock', jsonb_build_object('now', v_now, 'next_change_at', public.next_drift_change_at(v_now)));$h$);

do $$
declare
  b     record;
  h     record;
  v_def text;
  v_rev text;
begin
  for b in select * from before_0191 order by ord loop
    v_def := b.def;
    for h in select * from hunks_0191 where ord = b.ord order by n loop
      if pg_temp.occurs_0191(v_def, h.old) <> 1 then
        raise exception '0191 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          b.fn, h.n, pg_temp.occurs_0191(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
    v_rev := replace(pg_get_functiondef(b.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0191 where ord = b.ord order by n desc loop
      if pg_temp.occurs_0191(v_rev, h.new) <> 1 then
        raise exception '0191 self-assert FAIL: % hunk % does not occur once in the new body', b.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> b.def then
      raise exception '0191 self-assert FAIL: % does not reverse to its pre-image', b.fn;
    end if;
    if (select row(coalesce(p.proacl::text, ''), p.proowner, p.provolatile, p.prosecdef, coalesce(p.proconfig::text, ''))::text
          from pg_proc p where p.oid = b.fn::regprocedure) <> b.meta then
      raise exception '0191 self-assert FAIL: %''s ACL, owner, volatility, definer or config moved', b.fn;
    end if;
  end loop;
end $$;

-- ── 3. THE PROOF (two probe companies, rolled back whole) ─────────────────────────────────────
do $$
declare
  c_uid1 constant uuid := '00000000-0191-4000-8000-000000000001';
  c_uid2 constant uuid := '00000000-0191-4000-8000-000000000002';
  c_nil  constant uuid := '00000000-0000-0000-0000-000000000000';
  v_p1   uuid;
  v_p2   uuid;
  v_f1   uuid;
  v_f2   uuid;
  v_port uuid;
  v_far  uuid;
  v_good uuid;
  v_nat  uuid;
  v_top  numeric;
  v_floor numeric;
  s1a numeric; s1b numeric; s2a numeric; s2b numeric; s1far_a numeric; s1far_b numeric; s1nob_a numeric; s1nob numeric;
  v_on   boolean := public.influence_on();
  v_t0   timestamptz;
  v_ms   numeric;
  j      jsonb;
  v_want numeric;
  v_out  text;
begin
  select p.id into v_port from public.ports p where p.code = 'LIS';
  select p.id into v_far from public.ports p where p.code = 'LON';
  select g.id into v_good from public.goods g order by g.code limit 1;
  begin
    v_p1 := public.new_house(c_uid1, 'Casa Primeira 0191', 'PRT', 'LIS');
    v_p2 := public.new_house(c_uid2, 'Casa Segunda 0191', 'PRT', 'LIS');
    select id into v_f1 from public.fleets where player_id = v_p1 order by id limit 1;
    select id into v_f2 from public.fleets where player_id = v_p2 order by id limit 1;
    select nation_id into v_nat from public.players where id = v_p1;
    s1a := world.spread_effective(v_port, v_good, v_f1);
    s2a := world.spread_effective(v_port, v_good, v_f2);
    s1far_a := world.spread_effective(v_far, v_good, v_f1);
    s1nob_a := world.spread_effective(v_port, v_good, v_f1, false);
    if public.investor_rank(v_p1, v_port) is not null or public.investor_shave(v_p1, v_port) <> 0 then
      raise exception '0191 self-assert FAIL: a company with no points has a rank or a shave';
    end if;
    -- above every company in the city, and the second just below the first
    v_top := coalesce((select max(t.pts) from (select sum(points) as pts from public.port_influence
                                                 where port_id = v_port group by player_id) t), 0) + 1000;
    insert into public.port_influence (port_id, nation_id, player_id, points) values (v_port, v_nat, v_p1, v_top + 10);
    insert into public.port_influence (port_id, nation_id, player_id, points) values (v_port, v_nat, v_p2, v_top);
    s1b := world.spread_effective(v_port, v_good, v_f1);
    s1nob := world.spread_effective(v_port, v_good, v_f1, false);
    s2b := world.spread_effective(v_port, v_good, v_f2);
    s1far_b := world.spread_effective(v_far, v_good, v_f1);
    v_floor := world.spread(v_port) * public.wc_num('haggle_spread_floor_frac');
    if v_on then
      if public.investor_rank(v_p1, v_port) <> 1 or public.investor_rank(v_p2, v_port) <> 2 then
        raise exception '0191 self-assert FAIL: the probes rank % and %, not 1 and 2', public.investor_rank(v_p1, v_port), public.investor_rank(v_p2, v_port);
      end if;
      if abs(s1b - greatest(v_floor, s1a * 0.90)) > 1e-9 or abs(s2b - greatest(v_floor, s2a * 0.92)) > 1e-9 then
        raise exception '0191 self-assert FAIL: the spreads went % → % (rank 1) and % → % (rank 2)', s1a, s1b, s2a, s2b;
      end if;
      if abs(s1nob - greatest(v_floor, s1nob_a * 0.90)) > 1e-9 then
        raise exception '0191 self-assert FAIL: the shave does not hold without the bargain (%)', s1nob;
      end if;
    else
      if s1b <> s1a or s2b <> s2a then
        raise exception '0191 self-assert FAIL: with the race off a spread moved: % → %, % → %', s1a, s1b, s2a, s2b;
      end if;
    end if;
    if s1far_b <> s1far_a then
      raise exception '0191 self-assert FAIL: a spread elsewhere moved: % → %', s1far_a, s1far_b;
    end if;
    -- the read: the caller's stake
    perform cmd.assume_identity(c_uid1);
    j := world.price_why(v_port, v_good);
    v_want := case when v_on then 0.10 else 0 end;
    if (j->'stake'->>'rank')::int is distinct from 1
       or (j->'stake'->>'shave')::numeric is distinct from v_want then
      raise exception '0191 self-assert FAIL: price_why''s stake is %', j->'stake';
    end if;
    perform cmd.assume_identity(c_nil);
    if world.price_why(v_far, v_good)->'stake' <> 'null'::jsonb then
      raise exception '0191 self-assert FAIL: with no company signed in the stake is not null';
    end if;
    v_t0 := clock_timestamp();
    perform world.spread_effective(v_port, v_good, v_f1) from generate_series(1, 200);
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 200, 3);
    v_out := format('race %s; rank 1: %s → %s, rank 2: %s → %s, elsewhere %s = %s; spread_effective %s ms a call',
                    case when v_on then 'on' else 'off' end, s1a, s1b, s2a, s2b, s1far_a, s1far_b, v_ms);
    raise exception using errcode = 'ZX187', message = v_out;
  exception when sqlstate 'ZX187' then
    v_out := sqlerrm;
  end;
  perform cmd.assume_identity(c_nil);
  if exists (select 1 from public.players where id in (v_p1, v_p2)) then
    raise exception '0191 self-assert FAIL: a probe company survived its rollback';
  end if;
  if exists (select 1 from unnest(array['public.investor_rank(uuid, uuid)', 'public.investor_shave(uuid, uuid)']) f(fn),
                    unnest(array['anon', 'authenticated']) rl(role)
              where has_function_privilege(rl.role, f.fn, 'execute'))
     or exists (select 1 from unnest(array['public.investor_rank(uuid, uuid)', 'public.investor_shave(uuid, uuid)']) f(fn)
                 join pg_proc p on p.oid = f.fn::regprocedure where p.provolatile <> 's')
     or (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from count_0191)
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0191 self-assert FAIL: a leaf is reachable or not STABLE, or the registry or a wall moved';
  end if;
  raise notice '0191 self-assert ok: A CITY''S BEST FRIENDS TRADE CHEAPER. public.investor_rank / investor_shave (server-only, STABLE); world.spread_effective × (1 − shave) beside the purser and the bargain, floor kept (2 hunks, reverses); world.price_why serves the caller''s stake (1 hunk). Probes at LIS: %.', v_out;
end $$;

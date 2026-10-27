-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0251 — THE BOARD PRICES THE NEAR CITIES  (world.good_board prices in full the nearest cities she can sail to, as
--        well as the dearest; and asks passage_needs only of a leg past her reach)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY (owner row 231, and the Sell cargo list #348) ────────────────────────────────────────────────────────────
-- The Sell face opens on her cargo: each good aboard, "Here", and the cities to sail to with price · days · profit,
-- read from world.good_board's fully priced sell rows. The board prices in full only its good_board_quoted (10)
-- DEAREST cities (0171; 0188 put the reachable ones first). The dearest are mostly far away, so a city two days off
-- that would pay her well had no price and no profit on the list. The owner rejected a "best city in the world"
-- list (row 229): the list is her cargo and the cities near her.
--
-- ── WHAT THIS FILE DOES (world.good_board, 7 hunks; one new knob; nothing else) ─────────────────────────────────
-- (1) THE NEAR CITIES ARE PRICED. A sell row is priced in full (quote, profit tax, wages, cap, estimate) when it is
--     among the good_board_quoted dearest (as before) OR among the good_board_quoted_near (5, new knob) NEAREST rows
--     she can sail to (`sailable`: a passage within her navigation and stores, by its miles; where she lies counts
--     last, "Here" is read from the quay). Rows priced by both rules are priced once. The served `quoted_near` says
--     how many. Every figure a row carries is still its one authority's call: no arithmetic moves.
-- (2) THE SAME BOARD, CHEAPER. public.passage_needs (0188) answers null for a leg within her reach, and costs
--     ~1 ms a call on prod even then (definer + search_path, two passage_reach_nm reads) — ×246 sell rows + the buy
--     rows. The board reads public.passage_reach_nm once and asks passage_needs only of a leg past it: the same
--     answer by passage_needs' own first test (null reach, or within it → null), asserted row for row.
--
-- ── MEASURED (prod, read-only, head 0248, 2026-10-27; three human fleets × 12 boards: 6 of the cargo, 6 others) ─
-- Before: 36 boards, p50 1,700 ms, p95 ~2,330 ms (max 2,837 ms, a first call). Per extra priced row on prod: quote
-- 6–45 ms, profit_tax ~1 ms, daily_cap ~2 ms, price_outlook ~11 ms (warm) → 5 rows ≈ +125 ms. passage_needs ×246
-- within reach 183–237 ms → hoisted ≈ −200 ms. After: docs/dev-log/2026-10-27-near-quote.md.
--
-- ── NOT THE OWNER'S — CONFIRM (decided by default) ──────────────────────────────────────────────────────────────
-- * 5 near cities (good_board_quoted_near). "Near" = the passage's sailed miles (the board's own `miles`), only
--   rows she can sail. The dearest 10 stay, so a far rich city is still priced.
--
-- ── LOCKS AND TIME ───────────────────────────────────────────────────────────────────────────────────────────────
-- One INSERT into world_config (on conflict do nothing). CREATE OR REPLACE ×1 (good_board, by hunks sliced from the
-- LIVE body at prod head 0248, LF-normalised; each asserted to occur exactly once and to reverse to its pre-image;
-- ACL, volatility, definer, config, owner unchanged). The probe runs on its own company inside a sub-block rolled
-- back whole; only its rows are read. No LOCK TABLE, no set role, no set local, no begin. Timings are notices only.
-- ROLLBACK: a forward slice reverses the 7 hunks (each OLD text is here verbatim); the knob may stay (read by nothing).
-- VERSION: 0251 (prod head 0248 when written; 0249 and 0250 do not touch world.good_board).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0251(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table t0_0251 on commit drop as select clock_timestamp() as t0;

-- ── 1. THE KNOB ─────────────────────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('good_board_quoted_near', '5'::jsonb,
   '0251 (owner row 231): how many of the NEAREST cities she can sail to world.good_board prices in full, beside the '
   'good_board_quoted dearest — so the Sell cargo list can show what a near city pays and the profit.')
on conflict (key) do nothing;

-- ── 2. THE PRE-IMAGE ────────────────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0251 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values ('world.good_board(uuid,uuid,uuid,numeric)')) f(fn);

create temp table hunks_0251 (n int, old text, new text) on commit drop;
insert into hunks_0251 values
(1,
$h$-- anywhere; a sell row shut by the way to that city says so (shut.figures.buy_at).
$h$,
$h$-- anywhere; a sell row shut by the way to that city says so (shut.figures.buy_at).
-- 0251: the nearest good_board_quoted_near cities she can sail to are priced in full too (owner row 231: the Sell
-- cargo list's near cities); passage_needs is asked only of a leg past her reach (its own null otherwise).
$h$),
(2,
$h$  v_quoted  int := public.wc_int('good_board_quoted');
$h$,
$h$  v_quoted  int := public.wc_int('good_board_quoted');
  v_near    int := public.wc_int('good_board_quoted_near');   -- 0251: the nearest she can sail to, priced in full too
  v_reach_nm numeric;               -- 0251: public.passage_reach_nm, read once (passage_needs is null within it)
$h$),
(3,
$h$  v_margin := public.wc_num('endurance_margin');
$h$,
$h$  v_margin := public.wc_num('endurance_margin');
  v_reach_nm := public.passage_reach_nm(v_player);   -- 0251
$h$),
(4,
$h$           'needs', (select public.passage_needs(v_player, x.direct_nm) from reach x where x.port_id = s.id),
$h$,
$h$           'needs', (select case when x.direct_nm > v_reach_nm then public.passage_needs(v_player, x.direct_nm) end   -- 0251
                       from reach x where x.port_id = s.id),
$h$),
(5,
$h$           'stops', to_jsonb(r.stops), 'needs', public.passage_needs(v_player, r.direct_nm),   -- 0188
$h$,
$h$           'stops', to_jsonb(r.stops),   -- 0188
           'needs', case when r.direct_nm > v_reach_nm then public.passage_needs(v_player, r.direct_nm) end,   -- 0251: null within her reach
$h$),
(6,
$h$           row_number() over (order by (c.nm is null), c.mid desc, c.nm nulls last, c.code) as rk
$h$,
$h$           row_number() over (order by (c.nm is null), c.mid desc, c.nm nulls last, c.code) as rk,
           -- 0251: THE NEAREST SHE CAN SAIL TO (the row's own `sailable`), by the passage's miles; where she lies last
           row_number() over (order by coalesce(c.nm is not null and c.max_leg is not null and v_speed > 0 and n.fits, false) desc,
                                       c.id is not distinct from v_origin, c.nm nulls last, c.code) as nk
$h$),
(7,
$h$     where r.rk <= v_quoted and u.n > 0
$h$,
$h$     where (r.rk <= v_quoted or r.nk <= v_near) and u.n > 0   -- 0251: the dearest, and the nearest she can sail to
$h$),
(8,
$h$    'quoted', v_quoted,
$h$,
$h$    'quoted', v_quoted,
    'quoted_near', v_near,   -- 0251
$h$);

-- the pre-image under a pg_temp name, for the parity proofs and the positive controls
do $$
begin
  if (select count(*) from defs_before_0251 where def is not null) <> 1 then
    raise exception '0251 self-assert FAIL: world.good_board(uuid,uuid,uuid,numeric) not found';
  end if;
  execute replace((select def from defs_before_0251),
                  'CREATE OR REPLACE FUNCTION world.good_board(', 'CREATE OR REPLACE FUNCTION pg_temp.good_board_old_0251(');
end $$;

-- ── 3. THE NEW BODY ─────────────────────────────────────────────────────────────────────────────────────────────
do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
begin
  select * into d from defs_before_0251;
  v_def := d.def;
  for h in select * from hunks_0251 order by n loop
    if pg_temp.occurs_0251(v_def, h.old) <> 1 then
      raise exception '0251 self-assert FAIL: good_board hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
        h.n, pg_temp.occurs_0251(v_def, h.old);
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
  v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
  for h in select * from hunks_0251 order by n desc loop
    if pg_temp.occurs_0251(v_rev, h.new) <> 1 then
      raise exception '0251 self-assert FAIL: new hunk % is not in the live body once', h.n;
    end if;
    v_rev := replace(v_rev, h.new, h.old);
  end loop;
  if v_rev <> d.def then
    raise exception '0251 self-assert FAIL: good_board does not reverse to its pre-image';
  end if;
  if pg_temp.occurs_0251(v_def, 'public.passage_needs(') <> 2 then
    raise exception '0251 self-assert FAIL: the new body asks passage_needs % time(s), not twice (buy, sell)', pg_temp.occurs_0251(v_def, 'public.passage_needs(');
  end if;
  select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
         coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
    into p from pg_proc pr where pr.oid = d.fn::regprocedure;
  if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
    raise exception '0251 self-assert FAIL: good_board changed its ACL (% → %), owner, volatility, definer or config', d.acl, p.acl;
  end if;
  if public.wc_int('good_board_quoted_near') is distinct from 5 then
    raise exception '0251 self-assert FAIL: good_board_quoted_near is %, not 5', public.wc_int('good_board_quoted_near');
  end if;
end $$;

-- ── 4. THE PROBES: one company of this file's own, inside a sub-block that is rolled back whole ─────────────────
-- pg_temp.check_0251(new, old, near): the new board is the old one but for (a) `quoted_near`, (b) the order of the
-- sell rows, and (c) sell rows the old left unpriced that the new prices — each one she can sail to, and among the
-- `near` nearest such. Every row priced by the old, and every row neither prices, is the old row byte for byte.
-- Returns the number of rows the new prices that the old did not.
create or replace function pg_temp.check_0251(p_new jsonb, p_old jsonb, p_near int, p_here text)
returns int
language plpgsql
as $$
declare
  v_added int;
  v_cut   numeric;
  v_bad   text;
begin
  if (p_new - 'sell' - 'quoted_near') <> (p_old - 'sell') or (p_new->>'quoted_near')::int is distinct from p_near then
    raise exception '0251 self-assert FAIL: the board beyond its sell rows is not the pre-image (+ quoted_near %)', p_near;
  end if;
  if jsonb_array_length(p_new->'sell') <> jsonb_array_length(p_old->'sell') then
    raise exception '0251 self-assert FAIL: % sell rows, the pre-image served %', jsonb_array_length(p_new->'sell'), jsonb_array_length(p_old->'sell');
  end if;
  select string_agg(n.e->>'port', ', ') into v_bad
    from jsonb_array_elements(p_new->'sell') n(e)
    left join jsonb_array_elements(p_old->'sell') o(e) on o.e->>'port' = n.e->>'port'
   where o.e is null
      or (((o.e->>'quoted')::boolean or not (n.e->>'quoted')::boolean) and n.e <> o.e)
      or ((n.e->>'quoted')::boolean is distinct from true and (o.e->>'quoted')::boolean);
  if v_bad is not null then
    raise exception '0251 self-assert FAIL: sell rows not their pre-image (or unpriced by the new): %', v_bad;
  end if;
  -- the rows only the new prices: sailable, and no farther than the near-th nearest sailable row (where she lies last)
  select max(m) into v_cut from (
    select (e->>'miles')::numeric as m from jsonb_array_elements(p_new->'sell') e
     where (e->>'sailable')::boolean and e->>'port' is distinct from p_here
     order by (e->>'miles')::numeric limit p_near) x;
  select count(*), string_agg(n.e->>'port', ', ') filter (where not (n.e->>'sailable')::boolean or (n.e->>'miles')::numeric > v_cut)
    into v_added, v_bad
    from jsonb_array_elements(p_new->'sell') n(e)
    join jsonb_array_elements(p_old->'sell') o(e) on o.e->>'port' = n.e->>'port'
   where (n.e->>'quoted')::boolean and not (o.e->>'quoted')::boolean;
  if v_bad is not null then
    raise exception '0251 self-assert FAIL: rows newly priced that are not among the % nearest she can sail to (cut % nm): %', p_near, v_cut, v_bad;
  end if;
  -- and every sailable row strictly nearer than the cut is priced
  select string_agg(e->>'port', ', ') into v_bad from jsonb_array_elements(p_new->'sell') e
   where (e->>'sailable')::boolean and e->>'port' is distinct from p_here and (e->>'miles')::numeric < v_cut
     and not (e->>'quoted')::boolean;
  if v_bad is not null then
    raise exception '0251 self-assert FAIL: near sailable rows left unpriced: %', v_bad;
  end if;
  return v_added;
end $$;

do $$
declare
  c_auth    constant uuid := '00000000-0251-4000-8000-000000000001';
  v_player  uuid;
  v_fleet   uuid;
  v_lis     uuid;
  v_good    uuid;
  v_gcode   text;
  v_other   uuid;
  v_ocode   text;
  v_board   jsonb;
  v_old     jsonb;
  v_added   int;
  v_added2  int;
  v_needs   int;
  v_near    jsonb;
  v_ms      numeric[] := '{}';
  v_ms_old  numeric[] := '{}';
  v_t       timestamptz;
  v_hazard  jsonb;
  k         int;
  r_a text; r_b text; r_c text;
begin
  select value into v_hazard from public.world_config where key = 'hazard_p_max';
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    select id into v_lis from public.ports where code = 'LIS';
    v_player := public.new_house(c_auth, 'Probe 0251', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    if (select port_id from public.fleets where id = v_fleet) <> v_lis then
      raise exception '0251 self-assert FAIL: the probe company was not founded at Lisbon';
    end if;
    perform cmd.assume_identity(c_auth);

    -- HER CARGO: 10 of the first good Lisbon sells with stock, bought through cmd.do_buy (so its cost is known)
    select g.id, g.code into v_good, v_gcode
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_lis and pg.stock >= 50 and public.port_offers(v_lis, g.id)
     order by g.code limit 1;
    perform cmd.do_buy(v_fleet, jsonb_build_object('good', v_good, 'qty', 10));
    if coalesce(public.fleet_cargo_qty(v_fleet, v_gcode), 0) <> 10 then
      raise exception '0251 self-assert FAIL: the probe did not load 10 %', v_gcode;
    end if;

    -- (a) THE BOARD OF HER CARGO: the old prices only the dearest; the new also the nearest she can sail to — the
    --     positive control: at least one near row the old left unpriced is priced now, with a profit
    v_old := pg_temp.good_board_old_0251(v_good, v_fleet, null, null);
    v_board := world.good_board(v_good, v_fleet, null, null);
    v_added := pg_temp.check_0251(v_board, v_old, 5, 'LIS');
    if v_added = 0 then
      raise exception '0251 self-assert FAIL: positive control — the cargo board prices no near city the pre-image did not';
    end if;
    select jsonb_agg(jsonb_build_object('port', e->>'port', 'miles', e->'miles', 'profit', e->'profit') order by (e->>'miles')::numeric)
      into v_near from jsonb_array_elements(v_board->'sell') e
     where (e->>'quoted')::boolean and (e->>'sailable')::boolean and e->>'port' <> 'LIS'
       and (e->>'miles')::numeric <= (select max(m) from (select (x->>'miles')::numeric m from jsonb_array_elements(v_board->'sell') x
                                       where (x->>'sailable')::boolean and x->>'port' <> 'LIS' order by 1 limit 5) y);
    if exists (select 1 from jsonb_array_elements(v_near) e where jsonb_typeof(e->'profit') <> 'number') then
      raise exception '0251 self-assert FAIL: a near city of her cargo has no profit: %', v_near;
    end if;
    select count(*) into v_needs from jsonb_array_elements(v_board->'sell') e where jsonb_typeof(e->'needs') = 'object';
    if v_needs = 0 then
      raise exception '0251 self-assert FAIL: positive control — no sell row is past her reach, so the hoisted passage_needs is not proven';
    end if;
    r_a := format('%s aboard at Lisbon: %s near row(s) newly priced; the near five %s; %s row(s) past her reach carry needs as before',
                  v_gcode, v_added, v_near, v_needs);

    -- (b) A GOOD NOT ABOARD (bought first, then sold): the same rules, and the buy rows (passage_needs hoisted) the pre-image's
    select g.id, g.code into v_other, v_ocode
      from public.goods g
     where g.id <> v_good and exists (select 1 from public.port_goods pg where pg.good_id = g.id and pg.stock > 0 and public.port_offers(pg.port_id, g.id))
     order by g.code limit 1;
    v_old := pg_temp.good_board_old_0251(v_other, v_fleet, null, null);
    v_board := world.good_board(v_other, v_fleet, null, null);
    v_added2 := pg_temp.check_0251(v_board, v_old, 5, 'LIS');
    r_b := format('%s (not aboard, bought at %s): %s near row(s) newly priced, the rest the pre-image', v_ocode, v_board->'qty'->>'bought_at', v_added2);

    -- (c) TIMING: old and new, alternately, ×6 each (a notice; prod is measured in the dev-log)
    for k in 1 .. 6 loop
      v_t := clock_timestamp();
      perform pg_temp.good_board_old_0251(v_good, v_fleet, null, null);
      v_ms_old := v_ms_old || round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
      v_t := clock_timestamp();
      perform world.good_board(v_good, v_fleet, null, null);
      v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
    end loop;
    r_c := format('good_board new %s ms; pre-image %s ms', array_to_string(v_ms, ', '), array_to_string(v_ms_old, ', '));

    raise exception 'ROLLBACK_0251';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0251' then
      raise;
    end if;
  end;
  if exists (select 1 from public.players where id = v_player)
     or (select value from public.world_config where key = 'hazard_p_max') <> v_hazard then
    raise exception '0251 self-assert FAIL: the probe did not roll back whole';
  end if;
  raise notice '0251 probe (a): %', r_a;
  raise notice '0251 probe (b): %', r_b;
  raise notice '0251 probe (c): %', r_c;
  raise notice '0251 self-assert ok: THE BOARD PRICES THE NEAR CITIES. world.good_board prices the 5 nearest cities she can sail to beside the 10 dearest, every other figure its pre-image; passage_needs asked only past her reach. % s.',
    round(extract(epoch from clock_timestamp() - (select t0 from t0_0251)), 1);
end $$;

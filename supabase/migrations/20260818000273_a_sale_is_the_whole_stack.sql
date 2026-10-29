-- 0273 — A SALE IS THE WHOLE STACK   (the sub-ton hold: floor() turns every SELL into E_NO_CARGO, and the crumbs never leave)
--
-- THE ROOT, proven on prod 2026-10-29 (head 0272; read-only). Two merchants have been stuck for ever — 0272's
-- cut-loss correctly writes `SELL <good> ALL` for every good (public.npc_crew_blocked is TRUE for both), but every
-- SELL is skipped E_NO_CARGO, then the HIRE is skipped E_INSUFFICIENT_FUNDS and the SAIL fails E_CREW_SHORT, every
-- hour. Their whole holds are sub-ton remnants — every stack between 0.02 and 0.96 t:
--   * fleet a5b3042d-273a-41ea-9f11-22d052bcbd66 (route 1b52a58e-…, DOCKED at Tripoli 70dec312-…, short 2, hire
--     40 d., purse 0): coral .02, camels .20, falconet .47, gunpowder .42, marble .93, verdigris .81,
--     whale-oil .93 t — 197 d. at the quay's bid.
--   * fleet c62c3898-605f-41fd-9c6f-76f5942a7fb5 (route 63ade18d-…, DOCKED at Bridgetown e453e54b-…, short 1, hire
--     20 d., purse 0): cannon .08, falconet .24, gunpowder .55, henna .50, honey .50, majolica .96, marble .78,
--     sassafras-root .09, sealskins .85, tuna .29, whale-oil .78 t — 269 d. at the bid.
-- world.quote (STABLE) prices every stack fine at its TRUE quantity, but cmd.resolve_qty floors: floor(qty) = 0, so
-- cmd.do_sell's `least(resolve_qty(...), v_have)` is 0 and it raises E_NO_CARGO (0022:799-803). It is fleet-wide, not
-- two routes: 62,600 skipped SELL orders with E_NO_CARGO in 6 h across 828 NPC fleets — the normal "sell everything"
-- line (public.standing_route_lines: kind SELL, good_id NULL, qty NULL, at_profit TRUE) expands to one
-- `SELL <good> ALL AT >= <basis>` per good aboard (0092:431-448), every stack sub-ton, and floor() refuses each one.
--
-- THE FIX (one change; one authority per concept). Re-cut public.cmd.resolve_qty ONLY — 0007:296-325, NEVER re-cut
-- since (live body md5 999e9f6baa9083cfd29e4920fed00886, stable, security definer, search_path public, pg_temp).
-- A SALE is the exact tonnage she carries; a PURCHASE stays in whole tuns exactly as today. Every mode resolves on
-- the RAW v_max (never a pre-floored copy — floor(v / 2) equals floor(floor(v) / 2), and the PCT product keeps its
-- operand order v_max × pct / 100), and the whole-tun rounding applies to the buy side alone:
--     v_mode := coalesce(p_args->>'qty_mode', 'ALL');
--     v_qty  := case v_mode when 'HALF' then v_max / 2
--                           when 'PCT'  then v_max * (p_args->>'qty_pct')::numeric / 100
--                           else v_max end;
--     return case when p_side = 'sell' then v_qty else floor(v_qty) end;
--
-- THE ARITHMETIC, PROVEN not assumed (the self-assert's grid, and the probes below):
--   * a BUY is identical to today for EVERY v_max and EVERY mode — the same expression, the same single floor.
--   * a SELL is identical to today exactly when its resolved quantity is a whole tun — every ALL of a whole-tun
--     stack, and every HALF / PCT whose product comes out whole. A fractional quantity now sells its fraction:
--     SELL ALL of 3.4 t sells 3.4, where today it sold floor(3.4) = 3 and STRANDED a 0.4 t crumb the next SELL ALL
--     can never move (floor(0.4) = 0) — which is how prod's holds became crumbs in the first place; a sub-ton stack
--     (0.02-0.96 t) sells instead of resolving to 0 and raising E_NO_CARGO.
--   * The grid also asserts where today and this body DIFFER, said plainly: HALF of a 3 t stack now sells 1.5, not 1
--     (a sale takes the exact tonnage; only a purchase rounds). The dev-log carries the truth table.
--
-- NOTHING ELSE MOVES: no knob, no switch, no client, no other function, no grant/ACL, no volatility. 0272's
-- public.npc_leg_lines and public.npc_crew_blocked are untouched — the cut-loss lines they write now execute.
--
-- SUPERSEDE (supabase/migrations/README.md:43-48). This file re-cuts ONE live function, by hunks sliced from its
-- body (each hunk asserts it occurs exactly once and reverses to its pre-image):
--   * public.cmd.resolve_qty(uuid, text, text, jsonb) — 0007's body, never re-cut since; two hunks: the declarations,
--     and the mode case that is the return. Its ACL, volatility, definer and config are asserted unmoved, and its
--     pre-image tail is asserted to be prod's own (the md5 999e9f6b… body, read 2026-10-29).
-- A no-op wherever the resolved quantity is a whole tun, which the grid and the whole-tun probes prove row by row.
--
-- PROD CHECKS (before the push; read-only; in the PR body): the live body is the one the hunks were cut against
-- (md5 999e9f6baa9083cfd29e4920fed00886, stable, security definer, search_path public, pg_temp — read 2026-10-29);
-- the two stuck routes still read npc_crew_blocked TRUE (a5b3042d-… at TRP, short 2, hire 40 d., purse 0;
-- c62c3898-… at BRI, short 1, hire 20 d., purse 0). AFTER THE DEPLOY: for routes 1b52a58e-… and 63ade18d-… the
-- cut-loss SELLs execute, the HIRE is paid, the SAIL departs, the hulls come back to crew_required and the purses
-- leave 0; the world-wide E_NO_CARGO skipped-SELL count falls from the 62,600 / 6 h measured before the fix. A
-- forward rollback (a new migration restoring cmd.resolve_qty from the pre-image this file carries) is written in
-- docs/dev-log/2026-10-29-sell-crumbs.md.
--
-- VERSION: 0273 (prod head 0272).

-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('cmd.resolve_qty(uuid,text,text,jsonb)') is null
     or to_regprocedure('public.npc_crew_blocked(uuid,uuid)') is null then
    raise exception '0273 refuses: 0272 is not in this world';
  end if;
  if replace(pg_get_functiondef(to_regprocedure('cmd.resolve_qty(uuid,text,text,jsonb)')), E'\r', '')
     like '%case when p_side = ''sell'' then v_qty else floor(v_qty) end%' then
    raise exception '0273 refuses: cmd.resolve_qty already sells the exact tonnage — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0273(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0273 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       md5(replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '')) as md5,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('cmd.resolve_qty(uuid,text,text,jsonb)')) f(fn);

-- prod's own tail of the live body (read 2026-10-29, md5 999e9f6b…): the pre-image must END with this, so the
-- body this file slices is the body prod carries.
create temp table pin_0273 (tail text) on commit drop;
insert into pin_0273 values ($h$  return case coalesce(p_args->>'qty_mode', 'ALL')
           when 'ALL'  then floor(v_max)
           when 'HALF' then floor(v_max / 2)
           when 'PCT'  then floor(v_max * (p_args->>'qty_pct')::numeric / 100)
           else floor(v_max)
         end;
end $function$
$h$);

-- EVERY function in the four schemas except the one this file re-cuts: one md5 over the lot, so a body that moves
-- without being named here is caught — the functions both bodies decide with included, by construction.
create temp table before_0273 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and p.oid not in (to_regprocedure('cmd.resolve_qty(uuid,text,text,jsonb)'))) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and p.oid not in (to_regprocedure('cmd.resolve_qty(uuid,text,text,jsonb)'))) as others_md5,
       (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
           and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%hold_the_quay()%') as quay_takers;

-- ── 1. THE HUNKS ───────────────────────────────────────────────────────────────────────────────
create temp table hunks_0273 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0273 (fn, n, old, new) values
('cmd.resolve_qty(uuid,text,text,jsonb)', 1,
$h$declare
  v_bulk numeric;
  v_max  numeric;
begin
$h$,
$h$declare
  v_bulk numeric;
  v_max  numeric;
  v_mode text;    -- 0273: the mode, read once
  v_qty  numeric; -- 0273: the mode's quantity on the RAW v_max, rounded for a purchase alone
begin
$h$),
('cmd.resolve_qty(uuid,text,text,jsonb)', 2,
$h$  return case coalesce(p_args->>'qty_mode', 'ALL')
           when 'ALL'  then floor(v_max)
           when 'HALF' then floor(v_max / 2)
           when 'PCT'  then floor(v_max * (p_args->>'qty_pct')::numeric / 100)
           else floor(v_max)
         end;
$h$,
$h$  -- 0273: A SALE IS THE WHOLE STACK. Every mode resolves on the RAW v_max — never a pre-floored copy:
  -- floor(v / 2) equals floor(floor(v) / 2), and the PCT product keeps its order (v_max × pct / 100) — and
  -- the whole-tun rounding applies to a PURCHASE alone. A sale takes the exact tonnage she carries: a
  -- sub-ton stack (0.02-0.96 t, prod's crumbs) sells instead of resolving to 0 and raising E_NO_CARGO, and
  -- a partial sale can never leave an unsellable crumb behind.
  v_mode := coalesce(p_args->>'qty_mode', 'ALL');
  v_qty  := case v_mode
              when 'HALF' then v_max / 2
              when 'PCT'  then v_max * (p_args->>'qty_pct')::numeric / 100
              else v_max
            end;
  return case when p_side = 'sell' then v_qty else floor(v_qty) end;
$h$);

-- THE OLD BODY, kept whole for the probe's OLD / NEW switch (0272's shape: the live text, re-installed as it is)
create temp table old_bodies_0273 (fn text, old_def text) on commit drop;
insert into old_bodies_0273 (fn, old_def)
select 'qty', def from defs_before_0273 where fn = 'cmd.resolve_qty(uuid,text,text,jsonb)';

-- THE HUNKS, each once, then the new body
do $$
declare
  d   record;
  h   record;
  v_def text;
  v_n int;
begin
  for d in select * from defs_before_0273 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0273 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0273(v_def, h.old);
      if v_n <> 1 then
        raise exception '0273 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- the new body, for the probe's OLD / NEW switch
create temp table new_bodies_0273 (fn text, new_def text) on commit drop;
insert into new_bodies_0273 (fn, new_def) values
  ('qty', replace(pg_get_functiondef('cmd.resolve_qty(uuid,text,text,jsonb)'::regprocedure), E'\r', ''));

-- ── 2. THE PROBES' EYES ────────────────────────────────────────────────────────────────────────
-- a merchant's rows after a run (uuids blanked: new rows carry new ones) — 0272's shape
create function pg_temp.digest_0273(p_fleet uuid, p_route uuid, p_house uuid)
returns text
language sql
as $$
select regexp_replace(concat_ws(' # ',
  (select (to_jsonb(sr) - 'id')::text from public.standing_routes sr where sr.id = p_route),
  (select string_agg((to_jsonb(s) - 'id')::text, ',' order by s.ord) from public.standing_route_stops s where s.route_id = p_route),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(l) - 'id')::text as x from public.standing_route_lines l
     where l.route_id = p_route) a),
  (select string_agg((to_jsonb(x) - 'id')::text, ',' order by x.lap_no) from public.standing_route_laps x where x.route_id = p_route),
  (select string_agg((to_jsonb(o) - 'id')::text, ',' order by o.seq) from public.orders o where o.fleet_id = p_fleet),
  (select to_jsonb(f)::text from public.fleets f where f.id = p_fleet),
  (select string_agg(to_jsonb(s)::text, ',' order by s.id) from public.ships s where s.fleet_id = p_fleet),
  (select string_agg((to_jsonb(v) - 'id')::text, ',' order by v.departed_at) from public.voyages v where v.fleet_id = p_fleet),
  (select to_jsonb(p)::text from public.players p where p.id = p_house),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(l) - 'id')::text as x from public.ledger l
     where l.player_id = p_house and l.created_at >= now()) a),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(e) - 'id')::text as x from public.events e
     where e.player_id = p_house and e.created_at >= now()) a),
  (select md5(string_agg(to_jsonb(g)::text, ',' order by g.good_id)) from public.port_goods g
     where g.port_id = (select f.port_id from public.fleets f where f.id = p_fleet)),
  (select to_jsonb(t)::text from public.port_treasury t where t.port_id = (select f.port_id from public.fleets f where f.id = p_fleet))
  ), '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g')
$$;

-- ── 3. A MERCHANT THE PROBE CAN PUT IN THE SHAPE ───────────────────────────────────────────────
-- One docked merchant, and a stop of her own loop that is NOT the lap's first (a cursor of 0 is the lap boundary:
-- 0101 sends a merchant home to rest there, and 0114 re-plans her — neither is what is under test), at a harbour
-- with hands for sale and a good it bids on, and no failed order of her own (the probes plant what they need). The
-- probes MOVE her fleet to that stop's port: in the chain's fresh world every merchant lies at her own stop 0, and
-- prod's merchants lie mid-loop, which is the shape reproduced. ONE HULL, as both live cases are.
create temp table sample_0273 on commit drop as
select r.route_id, r.fleet_id, r.player_id, r.k, s.port_id, s.ord
  from public.npc_tend_roster() r
  join public.fleets f on f.id = r.fleet_id
  join public.standing_route_stops s on s.route_id = r.route_id and s.ord <> 0
  join public.ports p on p.id = s.port_id and p.kind = 'HARBOUR'
 where f.status = 'DOCKED'
   and (select count(*) from public.ships sh where sh.fleet_id = r.fleet_id) = 1
   and (select count(*) from public.standing_route_stops s2 where s2.route_id = r.route_id) >= 2
   and coalesce(p.crew_pool, 0) > 0
   and exists (select 1 from public.goods g
                join public.port_goods pg on pg.port_id = s.port_id and pg.good_id = g.id
                where coalesce((select q.total from world.quote(s.port_id, g.id, 10, 'sell', null, null) q), 0) > 0)
   and not exists (select 1 from public.orders o where o.fleet_id = r.fleet_id and o.status = 'failed')
 order by r.k, s.ord
 limit 1;

-- the traders' switch, on, for the step (rolled back with everything else — as 0150's and 0272's probes)
create function pg_temp.traders_on_0273()
returns void
language sql
as $$ update public.world_config set value = 'true'::jsonb
       where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb $$;

-- the good the probes sell: the smallest-bulk good this quay has a market in (a bid of 10 tuns, so the value is
-- real; world.quote RAISES on a port/good pair with no market row, so the join is the guard)
create function pg_temp.probe_good_0273(p_port uuid)
returns table (good_id uuid, code text, bulk numeric)
language sql
stable
as $$
  select g.id, g.code, g.bulk
    from public.goods g
    join public.port_goods pg on pg.port_id = p_port and pg.good_id = g.id
   where coalesce((select q.total from world.quote(p_port, g.id, 10, 'sell', null, null) q), 0) > 0
   order by g.bulk, g.code
   limit 1
$$;

-- THE SHAPE, put on the probe merchant: docked at the stop's port, p_short hands below complement on every hull,
-- purse p_purse, her hold planted directly (p_cargo: code -> tuns, any fraction — prod's sub-ton crumbs are made
-- this way, and public.fleet_load only stows whole tuns), each planted stack's basis p_basis, her casks full or
-- dry (a buy probe needs the room), her preset gone (so no PROVISION line stands between the sale and the hire),
-- her queue cleared, a failed SAIL refused E_CREW_SHORT at the head when p_failed, and p_clears NPC_CLEARED events
-- already on this lap. All rolled back with the probe's subtransaction.
create function pg_temp.state_0273(p_house uuid, p_fleet uuid, p_route uuid, p_port uuid, p_ord int, p_short int,
                                   p_purse bigint, p_cargo jsonb, p_basis numeric, p_casks boolean,
                                   p_failed boolean, p_clears int)
returns void
language plpgsql
as $$
declare
  v_lap   int;
  v_oid   uuid;
  v_n     int;
  v_code  text;
  v_next  text;
  v_seq   int;
  sh      record;
  v_free  numeric;
  v_wp    numeric := public.wc_num('water_per_crew_day');
  v_fp    numeric := public.wc_num('food_per_crew_day');
begin
  perform pg_temp.traders_on_0273();
  perform cmd.clear_for(p_house, p_fleet, false);
  update public.voyages set status = 'ARRIVED' where fleet_id = p_fleet and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = p_port, lat = null, lon = null,
                           provision_preset_id = null
   where id = p_fleet;
  -- her hull: below complement by p_short, the planted hold, dry casks, at full durability (so the stop's own
  -- REPAIR line refuses E_UNAVAILABLE and can never spend the money the sale raises)
  update public.ships hs
     set crew = greatest(0, c.crew_required - p_short),
         durability = c.durability,
         cargo = p_cargo,
         cargo_basis = coalesce((select jsonb_object_agg(k, to_jsonb(p_basis)) from jsonb_object_keys(p_cargo) k),
                                '{}'::jsonb),
         water_t = 0, food_t = 0
    from public.ship_classes c
   where c.id = hs.class_id and hs.fleet_id = p_fleet;
  if p_casks then
    -- casks to the brim of what the cargo left: the SAIL must pass on stores, so the probe never measures a
    -- crew-short fleet through an E_ENDURANCE it did not intend
    for sh in select s.id, s.crew, public.ship_hold_capacity(s.id) as hold, public.ship_cargo_tuns(s.id) as cargo_t
                from public.ships s where s.fleet_id = p_fleet loop
      v_free := greatest(0, sh.hold - sh.cargo_t);
      update public.ships
         set water_t = round(v_free * v_wp / (v_wp + v_fp), 3),
             food_t  = round(v_free * v_fp / (v_wp + v_fp), 3)
       where id = sh.id;
    end loop;
  end if;
  -- her purse, through the ledger (the purse reconciles with it — 0150's purse_0150)
  perform public.credit(p_house, 'PROBE_0273',
                        (p_purse - (select ducats from public.players where id = p_house))::bigint);
  -- her route: at the stop's port, cursor on it (a stop that is NOT the lap's first), no pause, no hold, no
  -- reserve, a lap of her own
  select count(*) into v_n from public.standing_route_stops s where s.route_id = p_route;
  select count(*) into v_lap from public.standing_route_laps x where x.route_id = p_route;
  v_lap := 900273 + v_lap;
  insert into public.standing_route_laps (route_id, lap_no, started_at)
  values (p_route, v_lap, now() - interval '7 hours') returning id into v_oid;
  update public.standing_routes
     set fleet_id = p_fleet, lap_no = v_lap, stop_cursor = p_ord, paused_reason = null, hold_until = null,
         reserve = 0, lap_id = v_oid, updated_at = now() - interval '2 minutes'
   where id = p_route;
  if p_failed then
    -- the failed order at the head: a SAIL refused E_CREW_SHORT, the shape prod shows
    select p.code into v_next
      from public.standing_route_stops s join public.ports p on p.id = s.port_id
     where s.route_id = p_route and s.ord = (p_ord + 1) % v_n;
    select coalesce(max(o.seq), 0) + 1 into v_seq from public.orders o where o.fleet_id = p_fleet;
    insert into public.orders (fleet_id, player_id, seq, raw_text, verb, status, error_code, error_message)
    values (p_fleet, p_house, v_seq, format('SAIL TO %s', v_next), 'SAIL', 'failed', 'E_CREW_SHORT', 'probe_0273');
  end if;
  -- her lap's clears, already counted: p_clears of them
  insert into public.events (player_id, kind, payload)
  select p_house, 'NPC_CLEARED', jsonb_build_object('route_id', p_route, 'lap_no', v_lap, 'n', i)
    from generate_series(1, greatest(p_clears, 0)) i;
end $$;

-- a direct SELL on the planted merchant, OLD body or NEW (each case re-plants the state and rolls back whole)
create function pg_temp.sell_case_0273(p_mode text, p_house uuid, p_fleet uuid, p_route uuid, p_port uuid, p_ord int,
                                       p_cargo jsonb, p_basis numeric, p_good uuid, p_qty_mode text, p_qty_pct int)
returns jsonb
language plpgsql
as $$
declare
  v_sq    text;
  v_res   jsonb;
  v_code  text;
  v_qty   numeric;
  v_before numeric;
  v_after  numeric;
  v_expected numeric;
begin
  select g.code, (p_cargo->>g.code)::numeric into v_code, v_qty
    from public.goods g where g.id = p_good;
  -- the quantity the MODE resolves to on the new body (the sell under test): the expected total is the quote of
  -- THAT quantity, so the purse check compares like for like
  v_qty := case when p_qty_mode = 'HALF' then v_qty / 2
                when p_qty_mode = 'PCT'  then v_qty * coalesce(p_qty_pct, 0)::numeric / 100
                else v_qty end;
  begin
    perform pg_temp.state_0273(p_house, p_fleet, p_route, p_port, p_ord, 0, 0, p_cargo, p_basis, true, false, 0);
    if p_mode = 'old' then
      select old_def into v_sq from old_bodies_0273; execute v_sq;
    else
      select new_def into v_sq from new_bodies_0273; execute v_sq;
    end if;
    select stock into v_before from public.port_goods where port_id = p_port and good_id = p_good;
    v_expected := coalesce((select q.total from world.quote(p_port, p_good, v_qty, 'sell', null, p_fleet) q), 0);
    v_res := cmd.do_sell(p_fleet, jsonb_build_object('good', p_good, 'qty_mode', p_qty_mode, 'qty_pct', p_qty_pct));
    select stock into v_after from public.port_goods where port_id = p_port and good_id = p_good;
    raise exception using errcode = 'ZY273', message = jsonb_build_object(
      'mode', p_mode, 'ok', true, 'result', v_res,
      'cargo_qty', public.fleet_cargo_qty(p_fleet, v_code),
      'stock_before', v_before, 'stock_after', v_after, 'expected_total', v_expected,
      'purse', (select p.ducats from public.players p where p.id = p_house),
      'digest', pg_temp.digest_0273(p_fleet, p_route, p_house))::text;
  exception when others then
    if sqlstate = 'ZY273' then
      return sqlerrm::jsonb;
    end if;
    return jsonb_build_object('mode', p_mode, 'ok', false, 'refused', sqlerrm, 'sqlstate', sqlstate,
      'cargo_qty', public.fleet_cargo_qty(p_fleet, v_code),
      'digest', pg_temp.digest_0273(p_fleet, p_route, p_house));
  end;
end $$;

-- a direct BUY on the planted merchant: 'old' and 'new' run the whole do_buy for the digest identity; 'both'
-- reads cmd.resolve_qty itself under the OLD body and under the NEW, on the same planted fleet, for the equality
create function pg_temp.buy_case_0273(p_mode text, p_house uuid, p_fleet uuid, p_route uuid, p_port uuid, p_ord int,
                                      p_good uuid, p_purse bigint, p_qty_mode text, p_qty_pct int)
returns jsonb
language plpgsql
as $$
declare
  v_sq   text;
  v_res  jsonb;
  v_args jsonb := jsonb_build_object('good', p_good, 'qty_mode', p_qty_mode, 'qty_pct', p_qty_pct);
  v_old  numeric;
  v_new  numeric;
begin
  begin
    perform pg_temp.state_0273(p_house, p_fleet, p_route, p_port, p_ord, 0, p_purse, '{}'::jsonb, 0, false, false, 0);
    if p_mode = 'old' then
      select old_def into v_sq from old_bodies_0273; execute v_sq;
      v_res := cmd.do_buy(p_fleet, v_args);
    elsif p_mode = 'new' then
      select new_def into v_sq from new_bodies_0273; execute v_sq;
      v_res := cmd.do_buy(p_fleet, v_args);
    else
      select old_def into v_sq from old_bodies_0273; execute v_sq;
      v_old := cmd.resolve_qty(p_fleet, (select code from public.goods where id = p_good), 'buy', v_args);
      select new_def into v_sq from new_bodies_0273; execute v_sq;
      v_new := cmd.resolve_qty(p_fleet, (select code from public.goods where id = p_good), 'buy', v_args);
      raise exception using errcode = 'ZY273', message = jsonb_build_object(
        'mode', 'both', 'old_v', v_old, 'new_v', v_new,
        'capacity', (public.fleet_buy_capacity(p_fleet, p_good)->>'max_qty')::numeric,
        'cap', world.daily_cap_remaining(p_house, p_port, p_good),
        'digest', pg_temp.digest_0273(p_fleet, p_route, p_house))::text;
    end if;
    raise exception using errcode = 'ZY273', message = jsonb_build_object(
      'mode', p_mode, 'ok', true, 'result', v_res,
      'purse', (select p.ducats from public.players p where p.id = p_house),
      'digest', pg_temp.digest_0273(p_fleet, p_route, p_house))::text;
  exception when others then
    if sqlstate = 'ZY273' then
      return sqlerrm::jsonb;
    end if;
    return jsonb_build_object('mode', p_mode, 'ok', false, 'refused', sqlerrm, 'sqlstate', sqlstate,
      'digest', pg_temp.digest_0273(p_fleet, p_route, p_house));
  end;
end $$;

-- the planted goods of the queue probes: up to three sub-ton stacks of goods the stop's OWN lines do not name
-- (a BUY or SELL line naming one would move its stock again behind the sale under test), dearest per tun first
create function pg_temp.queue_goods_0273(p_port uuid, p_route uuid, p_ord int)
returns jsonb
language plpgsql
stable
as $$
declare
  v_cargo jsonb := '{}'::jsonb;
  v_n     int := 0;
  g       record;
begin
  for g in
    select gd.code, coalesce((select q.total from world.quote(p_port, gd.id, 1, 'sell', null, null) q), 0) as per_tun
      from public.goods gd
      join public.port_goods pg on pg.port_id = p_port and pg.good_id = gd.id
     where coalesce((select q.total from world.quote(p_port, gd.id, 1, 'sell', null, null) q), 0) > 0
       and gd.code not in (select g2.code from public.standing_route_lines l
                             join public.goods g2 on g2.id = l.good_id
                            where l.route_id = p_route and l.stop_ord = p_ord and l.good_id is not null)
     order by 2 desc, 1
  loop
    exit when v_n >= 3;
    v_cargo := v_cargo || jsonb_build_object(g.code, round(0.93 - 0.10 * v_n, 2));
    v_n := v_n + 1;
  end loop;
  if v_n < 1 then
    raise exception '0273 self-assert FAIL: the probe stop has no tradeable good its own lines do not name — the queue probe proves nothing';
  end if;
  return v_cargo;
end $$;

-- THE NORMAL LINE through the real path: the stop's queue dry, a standing_route_lines row of prod's exact shape
-- (kind SELL, good_id NULL, qty NULL, at_profit TRUE) at her stop, and cmd.advance — which renders it to one
-- `SELL <good> ALL AT >= <basis>` per good aboard (0092:431-448), parses, enqueues and executes it (0092's
-- queue-dry refill and hunk B: a route's refused trade line is written `skipped` and stepped over)
create function pg_temp.queue_case_0273(p_mode text, p_house uuid, p_fleet uuid, p_route uuid, p_port uuid,
                                        p_ord int, p_cargo jsonb, p_basis numeric)
returns jsonb
language plpgsql
as $$
declare
  v_sq       text;
  v_ran      int;
  v_ord_line int;
  v_expected jsonb;
  v_ledger   numeric;
  v_sold     jsonb;
  v_cargo    jsonb;
  v_stock_before jsonb;
  v_stock    jsonb;
  v_orders   jsonb;
begin
  -- the expected bid value of every planted stack, before anything moves
  select coalesce(jsonb_agg(jsonb_build_object('code', k, 'qty', (p_cargo->>k)::numeric,
                     'total', coalesce((select q.total from world.quote(p_port, gd.id, (p_cargo->>k)::numeric, 'sell', null, p_fleet) q), 0)))
                  , '[]'::jsonb)
    into v_expected
    from jsonb_object_keys(p_cargo) k join public.goods gd on gd.code = k;
  begin
    perform pg_temp.state_0273(p_house, p_fleet, p_route, p_port, p_ord, 0, 0, p_cargo, p_basis, true, false, 0);
    if p_mode = 'old' then
      select old_def into v_sq from old_bodies_0273; execute v_sq;
    else
      select new_def into v_sq from new_bodies_0273; execute v_sq;
    end if;
    select coalesce(max(l.ord), 0) + 1 into v_ord_line
      from public.standing_route_lines l where l.route_id = p_route and l.stop_ord = p_ord;
    insert into public.standing_route_lines (route_id, stop_ord, ord, kind, good_id, qty, price_limit, at_profit)
    values (p_route, p_ord, v_ord_line, 'SELL', null, null, null, true);
    select coalesce(jsonb_object_agg(gd.code, pg.stock), '{}'::jsonb) into v_stock_before
      from jsonb_object_keys(p_cargo) k
      join public.goods gd on gd.code = k
      join public.port_goods pg on pg.port_id = p_port and pg.good_id = gd.id;
    v_ran := cmd.advance(p_fleet, now());
    select coalesce(sum(l.ducats_delta), 0) into v_ledger
      from public.ledger l where l.player_id = p_house and l.kind = 'SELL' and l.created_at >= now();
    select coalesce(jsonb_agg(jsonb_build_object('good', o.result->>'good', 'qty', o.result->>'qty',
                                                'total', o.result->>'total')), '[]'::jsonb)
      into v_sold
      from public.orders o where o.fleet_id = p_fleet and o.verb = 'SELL' and o.status = 'done';
    select coalesce((select cargo from public.ships s where s.fleet_id = p_fleet limit 1), '{}'::jsonb) into v_cargo;
    select coalesce(jsonb_object_agg(gd.code, pg.stock), '{}'::jsonb) into v_stock
      from jsonb_object_keys(p_cargo) k
      join public.goods gd on gd.code = k
      join public.port_goods pg on pg.port_id = p_port and pg.good_id = gd.id;
    select coalesce(jsonb_agg(jsonb_build_object('verb', o.verb, 'status', o.status, 'code', o.error_code,
                                                'text', o.raw_text) order by o.seq), '[]'::jsonb)
      into v_orders
      from public.orders o where o.fleet_id = p_fleet;
    raise exception using errcode = 'ZY273', message = jsonb_build_object(
      'mode', p_mode, 'ran', v_ran, 'expected', v_expected,
      'ledger_sell', v_ledger, 'sold', v_sold, 'cargo', v_cargo, 'stock_before', v_stock_before,
      'stock', v_stock, 'orders', v_orders,
      'fleet_status', (select f.status from public.fleets f where f.id = p_fleet),
      'purse', (select p.ducats from public.players p where p.id = p_house),
      'digest', pg_temp.digest_0273(p_fleet, p_route, p_house))::text;
  exception when others then
    if sqlstate = 'ZY273' then
      return sqlerrm::jsonb;
    end if;
    return jsonb_build_object('mode', p_mode, 'ok', false, 'refused', sqlerrm, 'sqlstate', sqlstate,
      'digest', pg_temp.digest_0273(p_fleet, p_route, p_house));
  end;
end $$;

-- the seam's hold: prod's crumb shape — sub-ton stacks, dearest per tun first, until they cover p_need at the bid
-- (and at least two stacks, as prod's holds carry many), each at the bid it would actually sell for
create function pg_temp.seam_cargo_0273(p_port uuid, p_need numeric)
returns jsonb
language plpgsql
stable
as $$
declare
  v_cargo jsonb := '{}'::jsonb;
  v_have  numeric := 0;
  v_n     int := 0;
  g       record;
  v_val   numeric;
begin
  for g in
    select gd.code, gd.id,
           coalesce((select q.total from world.quote(p_port, gd.id, 1, 'sell', null, null) q), 0) as per_tun
      from public.goods gd
      join public.port_goods pg on pg.port_id = p_port and pg.good_id = gd.id
     where coalesce((select q.total from world.quote(p_port, gd.id, 1, 'sell', null, null) q), 0) > 0
     order by 3 desc, 1
  loop
    exit when v_n >= 2 and v_have >= p_need;
    exit when v_n >= 8;
    v_val := coalesce((select q.total from world.quote(p_port, g.id, 0.93, 'sell', null, null) q), 0);
    exit when v_val <= 0;
    v_cargo := v_cargo || jsonb_build_object(g.code, 0.93);
    v_have := v_have + v_val;
    v_n := v_n + 1;
  end loop;
  if v_have < p_need then
    raise exception '0273 self-assert FAIL: the probe port (%) cannot cover a % d. hire with sub-ton stacks (best hold % d. in % stack(s))',
      p_port, p_need, v_have, v_n;
  end if;
  return jsonb_build_object('cargo', v_cargo, 'value', v_have, 'stacks', v_n);
end $$;

-- THE SEAM (never ship half a slice): a merchant docked below complement, purse 0, sub-ton hold covering the hire
-- at the bid, a failed order — her whole step (public.npc_tend_route, the clear + 0272's cut-loss + advance), OLD
-- body vs NEW (0272's crew_case shape; npc_leg_lines and npc_clear_due stay 0272's — the only switch is resolve_qty)
create function pg_temp.crew_case_0273(p_mode text, p_house uuid, p_fleet uuid, p_route uuid, p_port uuid, p_ord int)
returns jsonb
language plpgsql
as $$
declare
  v_r   jsonb;
  v_sq  text;
  v_cost bigint;
  v_sc   jsonb;
begin
  begin
    perform pg_temp.state_0273(p_house, p_fleet, p_route, p_port, p_ord, 1, 0, '{}'::jsonb, 1000000, true, true, 2);
    -- the hold is sized against the hire SHE faces at THIS quay (public.crew_hire_cost reads where she lies):
    -- prod's crumb shape, sub-ton stacks dearest per tun first, covering the hire 1.3× at the bid
    v_cost := (public.crew_hire_cost(p_fleet, public.fleet_crew_shortfall(p_fleet))->>'cost')::bigint;
    v_sc   := pg_temp.seam_cargo_0273(p_port, v_cost * 1.3);
    update public.ships s
       set cargo = v_sc->'cargo',
           cargo_basis = (select jsonb_object_agg(k, to_jsonb(1000000)) from jsonb_object_keys(v_sc->'cargo') k)
     where s.fleet_id = p_fleet;
    if p_mode = 'old' then
      select old_def into v_sq from old_bodies_0273; execute v_sq;
    else
      select new_def into v_sq from new_bodies_0273; execute v_sq;
    end if;
    v_r := public.npc_tend_route(now(), p_fleet, p_route, 1);
    raise exception using errcode = 'ZY273', message = jsonb_build_object(
      'receipt', v_r,
      'mode', p_mode,
      'hire', v_cost,
      'hold_value', v_sc->>'value',
      'stacks', v_sc->>'stacks',
      'digest', pg_temp.digest_0273(p_fleet, p_route, p_house),
      'shortfall', public.fleet_crew_shortfall(p_fleet),
      'purse', (select p.ducats from public.players p where p.id = p_house),
      'fleet', (select f.status from public.fleets f where f.id = p_fleet),
      'route', (select jsonb_build_object('pause', sr.paused_reason, 'cursor', sr.stop_cursor, 'lap', sr.lap_no,
                                          'lap_id', sr.lap_id is not null, 'hold', sr.hold_until, 'reserve', sr.reserve,
                                          'fleet', sr.fleet_id, 'pace', sr.laps_per_game_day,
                                          'stops', (select count(*) from public.standing_route_stops s where s.route_id = sr.id))
                  from public.standing_routes sr where sr.id = p_route),
      'ledger_ok', ((select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = p_house)
                    = (select p.ducats from public.players p where p.id = p_house)),
      'orders', coalesce((select jsonb_agg(jsonb_build_object('verb', o.verb, 'status', o.status,
                                                              'code', o.error_code, 'text', o.raw_text) order by o.seq)
                            from public.orders o where o.fleet_id = p_fleet), '[]'::jsonb))::text;
  exception when sqlstate 'ZY273' then
    return sqlerrm::jsonb;
  end;
end $$;

-- ── 4. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b     record;
  v_d     record;
  v_h     record;
  v_pp    record;
  v_def   text;
  o       jsonb;
  n       jsonb;
  c       jsonb;
  m       record;
  g       record;
  qg      jsonb;
  v_flags jsonb;
  v_mode  record;
  v_step  int := 0;
  v_grid  int := 0;
  v_code  text;
  v_k     record;
  v_ok    boolean;
begin
  select * into v_b from before_0273;
  -- THE SWITCHES ARE SNAPSHOT BEFORE ANY PROBE TOUCHES THEM: the last check (h) holds them against this reading, so a
  -- probe's switch write that escaped its transaction cannot be committed with the migration.
  select jsonb_object_agg(key, value) into v_flags from public.world_config
   where key in ('npc_traders_enabled', 'standing_routes_enabled');

  -- (a) THE HUNKS reverse to the live pre-image; ACL / volatility / definer / config unmoved; the pre-image tail is
  -- prod's own (md5 999e9f6b…); nothing else in the four schemas moved; no function minted or dropped; no new quay
  -- taker; the client entry points still number what they numbered.
  for v_d in select * from defs_before_0273 loop
    if right(v_d.def, length((select tail from pin_0273))) <> (select tail from pin_0273) then
      raise exception '0273 self-assert FAIL: the pre-image tail is not prod''s own (md5 % on prod, % here)', v_d.md5, '999e9f6baa9083cfd29e4920fed00886';
    end if;
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0273 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0273(v_def, v_h.new) <> 1 then
        raise exception '0273 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0273 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0273 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in (to_regprocedure('cmd.resolve_qty(uuid,text,text,jsonb)'))) <> v_b.fns then
    raise exception '0273 self-assert FAIL: the four schemas gained or lost a function';
  end if;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in (to_regprocedure('cmd.resolve_qty(uuid,text,text,jsonb)'))) <> v_b.others_md5 then
    raise exception '0273 self-assert FAIL: a function this file does not re-cut moved (the bodies'' own authorities included)';
  end if;
  if (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
         and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%hold_the_quay()%') <> v_b.quay_takers then
    raise exception '0273 self-assert FAIL: the set of functions that take the quay changed';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points then
    raise exception '0273 self-assert FAIL: the client entry points changed';
  end if;

  -- (b) THE FIX'S OWN SHAPE: the early return and the buy/sell v_max selection stand where 0007 put them, and the
  -- new mode case stands at the return, rounding the buy side alone.
  v_def := replace(pg_get_functiondef('cmd.resolve_qty(uuid,text,text,jsonb)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0273(v_def, 'if p_args ? ''qty'' and p_args->>''qty'' is not null then') <> 1
     or pg_temp.occurs_0273(v_def, 'v_max := public.fleet_cargo_qty(p_fleet, p_good_code);') <> 1
     or pg_temp.occurs_0273(v_def, 'v_max := (public.fleet_buy_capacity(') <> 1
     or pg_temp.occurs_0273(v_def, 'v_mode := coalesce(p_args->>''qty_mode'', ''ALL'');') <> 1
     or pg_temp.occurs_0273(v_def, 'return case when p_side = ''sell'' then v_qty else floor(v_qty) end;') <> 1
     or pg_temp.occurs_0273(v_def, 'when ''HALF'' then v_max / 2') <> 1
     or pg_temp.occurs_0273(v_def, 'when ''PCT''  then v_max * (p_args->>''qty_pct'')::numeric / 100') <> 1 then
    raise exception '0273 self-assert FAIL: the new body does not carry the fix''s shape';
  end if;
  if position('v_max := public.fleet_cargo_qty(p_fleet, p_good_code);' in v_def) > position('v_mode := coalesce' in v_def)
     or position('v_mode := coalesce' in v_def) > position('return case when p_side' in v_def) then
    raise exception '0273 self-assert FAIL: the mode case does not stand after the v_max selection and at the return';
  end if;

  -- (c) THE ARITHMETIC, PROVEN not assumed: old and new side by side over a grid of v_max (the crumbs' sizes and the
  -- whole and fractional stacks) and every mode. A BUY is identical everywhere (same expression, same one floor); a
  -- SELL is identical exactly when its resolved quantity is a whole tun, and floor(v / 2) = floor(floor(v) / 2).
  create temp table arith_0273 (v_max numeric, mode text, pct int, old_v numeric, new_sell numeric, new_buy numeric) on commit drop;
  insert into arith_0273
  select gv.v, md.mode, md.pct,
         case md.mode when 'ALL' then floor(gv.v) when 'HALF' then floor(gv.v / 2) else floor(gv.v * md.pct::numeric / 100) end as old_v,
         case md.mode when 'ALL' then gv.v when 'HALF' then gv.v / 2 else gv.v * md.pct::numeric / 100 end as new_sell,
         floor(case md.mode when 'ALL' then gv.v when 'HALF' then gv.v / 2 else gv.v * md.pct::numeric / 100 end) as new_buy
    from (values (0.02), (0.465), (0.93), (1), (1.5), (2), (3), (3.4), (4), (7.9), (10)) gv(v)
    cross join (values ('ALL', null), ('HALF', null), ('PCT', 30), ('PCT', 75)) md(mode, pct);
  for v_k in select * from arith_0273 loop
    v_grid := v_grid + 1;
    if v_k.new_buy <> v_k.old_v then
      raise exception '0273 self-assert FAIL: a BUY moved — v_max %, mode %: old %, new %', v_k.v_max, v_k.mode, v_k.old_v, v_k.new_buy;
    end if;
    if v_k.old_v <> floor(v_k.new_sell) then
      raise exception '0273 self-assert FAIL: the old value is not floor(new) — v_max %, mode %', v_k.v_max, v_k.mode;
    end if;
    if (v_k.new_sell = v_k.old_v) <> (floor(v_k.new_sell) = v_k.new_sell) then
      raise exception '0273 self-assert FAIL: sell equality does not match wholeness — v_max %, mode %: old %, new %', v_k.v_max, v_k.mode, v_k.old_v, v_k.new_sell;
    end if;
    if floor(v_k.v_max / 2) <> floor(floor(v_k.v_max) / 2) then
      raise exception '0273 self-assert FAIL: the HALF lemma broke at v_max %', v_k.v_max;
    end if;
  end loop;
  -- the named cases, so the receipt says what is equal and what is not: sub-ton sells move; a fractional whole
  -- stack sells its fraction (3.4, not 3); HALF of 3 sells 1.5; whole products are untouched
  select (old_v = new_sell) into v_ok from arith_0273 where v_max = 0.93 and mode = 'ALL';
  if v_ok or (select old_v <> 0 or new_sell <> 0.93 from arith_0273 where v_max = 0.93 and mode = 'ALL') then
    raise exception '0273 self-assert FAIL: SELL ALL of 0.93 must move from 0 to 0.93';
  end if;
  if (select old_v <> 3 or new_sell <> 3.4 from arith_0273 where v_max = 3.4 and mode = 'ALL') then
    raise exception '0273 self-assert FAIL: SELL ALL of 3.4 must move from 3 to 3.4';
  end if;
  if (select old_v <> 1 or new_sell <> 1.5 from arith_0273 where v_max = 3 and mode = 'HALF') then
    raise exception '0273 self-assert FAIL: SELL HALF of 3 must move from 1 to 1.5';
  end if;
  if (select old_v <> new_sell from arith_0273 where v_max = 4 and mode = 'ALL') is distinct from false
     or (select old_v <> new_sell from arith_0273 where v_max = 2 and mode = 'HALF') is distinct from false
     or (select old_v <> new_sell from arith_0273 where v_max = 10 and mode = 'PCT' and pct = 30) is distinct from false then
    raise exception '0273 self-assert FAIL: a whole-tun sell moved where it must not';
  end if;

  -- (d) THE DIRECT PROBES on the sample merchant: SELL ALL / HALF / PCT 30 of a 0.93 t stack (old E_NO_CARGO, new
  -- sells the exact tonnage, the stack empties, the port stock restored, the purse credited the quote's total);
  -- SELL ALL of 3.4 t (old 3 and a stranded 0.4 crumb, new 3.4); SELL ALL of a whole 4 t (identical rows); an
  -- empty hold (E_NO_CARGO on both); BUY ALL / HALF / PCT 30 (resolve equal, identical rows).
  select * into g from pg_temp.sample_0273;
  if g.route_id is null then
    raise exception '0273 self-assert FAIL: no merchant the probes can reach — the direct probes prove nothing';
  end if;
  select x.* into m from pg_temp.probe_good_0273(g.port_id) x;
  if m.good_id is null then
    raise exception '0273 self-assert FAIL: the probe port (%) bids on no good', g.port_id;
  end if;
  -- (d1) ALL of 0.93
  o := pg_temp.sell_case_0273('old', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord,
                              jsonb_build_object(m.code, 0.93), 1000000, m.good_id, 'ALL', null);
  n := pg_temp.sell_case_0273('new', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord,
                              jsonb_build_object(m.code, 0.93), 1000000, m.good_id, 'ALL', null);
  if coalesce((o->>'ok')::boolean, false) or coalesce(o->>'refused', '') not like 'E_NO_CARGO:%' then
    raise exception '0273 self-assert FAIL: the old body did not refuse the 0.93 t SELL ALL with E_NO_CARGO: %', o->>'refused';
  end if;
  if not coalesce((n->>'ok')::boolean, false) or coalesce((n->'result'->>'qty')::numeric, -1) <> 0.93
     or coalesce((n->>'cargo_qty')::numeric, -1) <> 0
     or coalesce((n->>'stock_after')::numeric, -999) <> coalesce((n->>'stock_before')::numeric, 0) + 0.93
     or coalesce((n->>'purse')::bigint, -1) <> (n->>'expected_total')::bigint then
    raise exception '0273 self-assert FAIL: the new SELL ALL of 0.93 t did not sell the whole stack for the quote''s total: %', n;
  end if;
  v_step := v_step + 1;
  -- (d2) HALF of 0.93
  o := pg_temp.sell_case_0273('old', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord,
                              jsonb_build_object(m.code, 0.93), 1000000, m.good_id, 'HALF', null);
  n := pg_temp.sell_case_0273('new', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord,
                              jsonb_build_object(m.code, 0.93), 1000000, m.good_id, 'HALF', null);
  if coalesce((o->>'ok')::boolean, false) or coalesce(o->>'refused', '') not like 'E_NO_CARGO:%' then
    raise exception '0273 self-assert FAIL: the old body did not refuse the 0.93 t SELL HALF with E_NO_CARGO: %', o->>'refused';
  end if;
  if not coalesce((n->>'ok')::boolean, false) or coalesce((n->'result'->>'qty')::numeric, -1) <> 0.465
     or coalesce((n->>'cargo_qty')::numeric, -1) <> 0.465
     or abs(coalesce((n->>'stock_after')::numeric, -999) - (coalesce((n->>'stock_before')::numeric, 0) + 0.465)) > 0.01
     or coalesce((n->>'purse')::bigint, -1) <> (n->>'expected_total')::bigint then
    raise exception '0273 self-assert FAIL: the new SELL HALF of 0.93 t did not sell 0.465 for the quote''s total: %', n;
  end if;
  v_step := v_step + 1;
  -- (d3) PCT 30 of 0.93
  o := pg_temp.sell_case_0273('old', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord,
                              jsonb_build_object(m.code, 0.93), 1000000, m.good_id, 'PCT', 30);
  n := pg_temp.sell_case_0273('new', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord,
                              jsonb_build_object(m.code, 0.93), 1000000, m.good_id, 'PCT', 30);
  if coalesce((o->>'ok')::boolean, false) or coalesce(o->>'refused', '') not like 'E_NO_CARGO:%' then
    raise exception '0273 self-assert FAIL: the old body did not refuse the 0.93 t SELL PCT 30 with E_NO_CARGO: %', o->>'refused';
  end if;
  if not coalesce((n->>'ok')::boolean, false) or coalesce((n->'result'->>'qty')::numeric, -1) <> 0.279
     or coalesce((n->>'cargo_qty')::numeric, -1) <> 0.651
     or abs(coalesce((n->>'stock_after')::numeric, -999) - (coalesce((n->>'stock_before')::numeric, 0) + 0.279)) > 0.01
     or coalesce((n->>'purse')::bigint, -1) <> (n->>'expected_total')::bigint then
    raise exception '0273 self-assert FAIL: the new SELL PCT 30 of 0.93 t did not sell 0.279 for the quote''s total: %', n;
  end if;
  v_step := v_step + 1;
  -- (d4) ALL of 3.4: the old body sells floor(3.4) = 3 and strands a 0.4 t crumb; the new body sells the whole 3.4.
  o := pg_temp.sell_case_0273('old', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord,
                              jsonb_build_object(m.code, 3.4), 1000000, m.good_id, 'ALL', null);
  n := pg_temp.sell_case_0273('new', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord,
                              jsonb_build_object(m.code, 3.4), 1000000, m.good_id, 'ALL', null);
  if not coalesce((o->>'ok')::boolean, false) or coalesce((o->'result'->>'qty')::numeric, -1) <> 3
     or coalesce((o->>'cargo_qty')::numeric, -1) <> 0.4 then
    raise exception '0273 self-assert FAIL: the old SELL ALL of 3.4 t did not sell 3 and strand 0.4: %', o;
  end if;
  if not coalesce((n->>'ok')::boolean, false) or coalesce((n->'result'->>'qty')::numeric, -1) <> 3.4
     or coalesce((n->>'cargo_qty')::numeric, -1) <> 0
     or coalesce((n->>'stock_after')::numeric, -999) <> coalesce((n->>'stock_before')::numeric, 0) + 3.4 then
    raise exception '0273 self-assert FAIL: the new SELL ALL of 3.4 t did not sell the whole stack: %', n;
  end if;
  if (o->>'digest') is not distinct from (n->>'digest') then
    raise exception '0273 self-assert FAIL: old and new left the same rows on a 3.4 t SELL ALL, where the old body strands a crumb';
  end if;
  v_step := v_step + 1;
  -- (d5) ALL of a whole 4 t: the fix is a no-op there — identical rows, the whole stack sold
  o := pg_temp.sell_case_0273('old', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord,
                              jsonb_build_object(m.code, 4), 1000000, m.good_id, 'ALL', null);
  n := pg_temp.sell_case_0273('new', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord,
                              jsonb_build_object(m.code, 4), 1000000, m.good_id, 'ALL', null);
  if (o->>'digest') is distinct from (n->>'digest') then
    raise exception '0273 self-assert FAIL: the 4 t SELL ALL moved between old and new: % / %', left(o->>'digest', 400), left(n->>'digest', 400);
  end if;
  if not coalesce((n->>'ok')::boolean, false) or coalesce((n->'result'->>'qty')::numeric, -1) <> 4
     or coalesce((n->>'cargo_qty')::numeric, -1) <> 0 then
    raise exception '0273 self-assert FAIL: the whole-tun SELL ALL did not sell 4 t: %', n;
  end if;
  v_step := v_step + 1;
  -- (d6) an empty hold: E_NO_CARGO on both bodies
  o := pg_temp.sell_case_0273('old', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord,
                              '{}'::jsonb, 1000000, m.good_id, 'ALL', null);
  n := pg_temp.sell_case_0273('new', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord,
                              '{}'::jsonb, 1000000, m.good_id, 'ALL', null);
  if coalesce((o->>'ok')::boolean, false) or coalesce(o->>'refused', '') not like 'E_NO_CARGO:%'
     or coalesce((n->>'ok')::boolean, false) or coalesce(n->>'refused', '') not like 'E_NO_CARGO:%' then
    raise exception '0273 self-assert FAIL: an empty hold did not refuse E_NO_CARGO on both bodies: % / %', o->>'refused', n->>'refused';
  end if;
  v_step := v_step + 1;
  -- (d7) BUY ALL / HALF / PCT 30: resolve_qty answers the same value on both bodies, and the whole do_buy leaves
  -- the same rows (purse, cargo, port stock, ledger, events)
  for v_mode in select * from (values ('ALL', null), ('HALF', null), ('PCT', 30)) t(qm, qp) loop
    o := pg_temp.buy_case_0273('old', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord, m.good_id, 500000, v_mode.qm, v_mode.qp);
    n := pg_temp.buy_case_0273('new', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord, m.good_id, 500000, v_mode.qm, v_mode.qp);
    c := pg_temp.buy_case_0273('both', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord, m.good_id, 500000, v_mode.qm, v_mode.qp);
    if c->>'old_v' is null or c->>'new_v' is null
       or (c->>'old_v')::numeric is distinct from (c->>'new_v')::numeric then
      raise exception '0273 self-assert FAIL: BUY % moved resolve_qty: old %, new %', v_mode.qm, c->>'old_v', c->>'new_v';
    end if;
    if (o->>'digest') is distinct from (n->>'digest') then
      raise exception '0273 self-assert FAIL: BUY % left different rows between old and new: % / %', v_mode.qm, left(o->>'digest', 400), left(n->>'digest', 400);
    end if;
    v_step := v_step + 1;
  end loop;

  -- (e) THE NORMAL LINE through the real queue: prod's own standing_route_lines row (kind SELL, good_id NULL,
  -- qty NULL, at_profit TRUE) over a sub-ton hold, rendered to one SELL <good> ALL AT >= <basis> per good aboard,
  -- parsed, enqueued and executed by cmd.advance (0092's queue-dry refill). OLD skips every SELL E_NO_CARGO and
  -- credits nothing; NEW executes each SELL for the exact tonnage, credits the ledger the quote's totals, empties
  -- the stacks and restores the port stock; then she sails.
  qg := pg_temp.queue_goods_0273(g.port_id, g.route_id, g.ord);
  o := pg_temp.queue_case_0273('old', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord, qg, 0);
  n := pg_temp.queue_case_0273('new', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord, qg, 0);
  if coalesce((n->>'ledger_sell')::numeric, -1) <> (select coalesce(sum((x->>'total')::numeric), 0) from jsonb_array_elements(n->'expected') as e(x)) then
    raise exception '0273 self-assert FAIL: the new queue SELLs did not credit the quote''s totals (% d. vs % d.): %',
      n->>'ledger_sell', (select coalesce(sum((x->>'total')::numeric), 0) from jsonb_array_elements(n->'expected') as e(x)), n->'orders';
  end if;
  for v_k in select * from jsonb_array_elements(n->'expected') as e(x) loop
    if not exists (select 1 from jsonb_array_elements(n->'sold') s
                    where s->>'good' = v_k.x->>'code' and (s->>'qty')::numeric = (v_k.x->>'qty')::numeric) then
      raise exception '0273 self-assert FAIL: the new queue run sold no % for its exact % t: % / %', v_k.x->>'code', v_k.x->>'qty', n->'sold', n->'orders';
    end if;
    if coalesce((n->'cargo'->>(v_k.x->>'code'))::numeric, 0) <> 0 then
      raise exception '0273 self-assert FAIL: the new queue run left % t of % aboard: %', n->'cargo'->>(v_k.x->>'code'), v_k.x->>'code', n->'cargo';
    end if;
    if coalesce((n->'stock'->>(v_k.x->>'code'))::numeric, -1)
       <> coalesce((n->'stock_before'->>(v_k.x->>'code'))::numeric, -1) + (v_k.x->>'qty')::numeric then
      raise exception '0273 self-assert FAIL: the new queue run did not restore the port stock of % (% → %)',
        v_k.x->>'code', n->'stock_before'->>(v_k.x->>'code'), n->'stock'->>(v_k.x->>'code');
    end if;
  end loop;
  if coalesce((o->>'ledger_sell')::numeric, -1) <> 0
     or not exists (select 1 from jsonb_array_elements(o->'orders') e
                     where e->>'verb' = 'SELL' and e->>'status' = 'skipped' and e->>'code' = 'E_NO_CARGO')
     or exists (select 1 from jsonb_array_elements(o->'orders') e where e->>'verb' = 'SELL' and e->>'status' = 'done') then
    raise exception '0273 self-assert FAIL: the old queue run did not skip every SELL E_NO_CARGO: %', o->'orders';
  end if;
  if (o->'cargo') is distinct from qg then
    raise exception '0273 self-assert FAIL: the old queue run moved the hold (%), which must stay aboard under E_NO_CARGO', o->>'cargo';
  end if;
  v_step := v_step + 1;

  -- (f) THE RULE THAT MUST NOT MOVE: the same normal line when the bid is BELOW the basis still refuses — the
  -- at_profit floor is unchanged. On a sub-ton hold the old body refuses E_NO_CARGO (never reaches the price) and
  -- the new body refuses E_PRICE_LIMIT (the whole stack would sell, and the floor stops it); either way the order
  -- is written `skipped`, nothing is sold, the hold is intact. On a whole 2 t stack both bodies refuse
  -- E_PRICE_LIMIT and leave identical rows.
  o := pg_temp.queue_case_0273('old', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord, qg, 1000000);
  n := pg_temp.queue_case_0273('new', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord, qg, 1000000);
  if coalesce((o->>'ledger_sell')::numeric, -1) <> 0 or coalesce((n->>'ledger_sell')::numeric, -1) <> 0
     or (o->'cargo') is distinct from qg or (n->'cargo') is distinct from qg then
    raise exception '0273 self-assert FAIL: a bid below the basis sold something: old % / new %', o, n;
  end if;
  if not exists (select 1 from jsonb_array_elements(o->'orders') e
                  where e->>'verb' = 'SELL' and e->>'status' = 'skipped' and e->>'code' = 'E_NO_CARGO') then
    raise exception '0273 self-assert FAIL: the old body did not skip the sub-ton SELL below basis with E_NO_CARGO: %', o->'orders';
  end if;
  if not exists (select 1 from jsonb_array_elements(n->'orders') e
                  where e->>'verb' = 'SELL' and e->>'status' = 'skipped' and e->>'code' = 'E_PRICE_LIMIT') then
    raise exception '0273 self-assert FAIL: the new body did not refuse the sub-ton SELL below basis with E_PRICE_LIMIT: %', n->'orders';
  end if;
  v_step := v_step + 1;
  v_code := (select k from jsonb_object_keys(qg) k limit 1);
  o := pg_temp.queue_case_0273('old', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord,
                               jsonb_build_object(v_code, 2), 1000000);
  n := pg_temp.queue_case_0273('new', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord,
                               jsonb_build_object(v_code, 2), 1000000);
  if (o->>'digest') is distinct from (n->>'digest') then
    raise exception '0273 self-assert FAIL: a whole 2 t stack below its basis moved between old and new: % / %', left(o->>'digest', 400), left(n->>'digest', 400);
  end if;
  if not exists (select 1 from jsonb_array_elements(n->'orders') e
                  where e->>'verb' = 'SELL' and e->>'status' = 'skipped' and e->>'code' = 'E_PRICE_LIMIT') then
    raise exception '0273 self-assert FAIL: the whole 2 t stack below its basis was not refused E_PRICE_LIMIT on both bodies: %', n->'orders';
  end if;
  v_step := v_step + 1;

  -- (g) THE SEAM: a merchant docked below complement, purse 0, sub-ton hold covering the hire at the bid, a failed
  -- SAIL refused E_CREW_SHORT — her whole step, OLD vs NEW. OLD reproduces the loop (every cut-loss SELL skipped
  -- E_NO_CARGO, the HIRE skipped E_INSUFFICIENT_FUNDS, the SAIL refused E_CREW_SHORT, her docked); NEW closes it
  -- (the cut-loss SELLs execute at the bid, the HIRE is paid, the SAIL departs, the crew restored, the purse leaves
  -- 0 for the value the hold brought in, the ledger reconciled). The control (old against old) must not move.
  o := pg_temp.crew_case_0273('old', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord);
  n := pg_temp.crew_case_0273('new', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord);
  c := pg_temp.crew_case_0273('old', g.player_id, g.fleet_id, g.route_id, g.port_id, g.ord);
  if o->'receipt'->>'cleared' is distinct from '1' or o->'receipt'->>'failed' is distinct from '0' then
    raise exception '0273 self-assert FAIL: the old step answered % — it did not reach the clear', o->'receipt';
  end if;
  if o->>'digest' is distinct from c->>'digest' then
    raise exception '0273 self-assert FAIL: the control moved (old against old): % / %', left(o->>'digest', 600), left(c->>'digest', 600);
  end if;
  if not exists (select 1 from jsonb_array_elements(o->'orders') e
                  where e->>'verb' = 'SELL' and e->>'status' = 'skipped' and e->>'code' = 'E_NO_CARGO')
     or not exists (select 1 from jsonb_array_elements(o->'orders') e
                     where e->>'verb' = 'HIRE' and e->>'status' = 'skipped' and e->>'code' = 'E_INSUFFICIENT_FUNDS')
     or not exists (select 1 from jsonb_array_elements(o->'orders') e
                     where e->>'verb' = 'SAIL' and e->>'status' = 'failed' and e->>'code' = 'E_CREW_SHORT') then
    raise exception '0273 self-assert FAIL: the old step did not reproduce the loop (SELL E_NO_CARGO, HIRE skipped, SAIL refused): % / receipt % / route %',
      o->'orders', o->'receipt', o->'route';
  end if;
  if coalesce(o->>'fleet', '') <> 'DOCKED' or coalesce((o->>'shortfall')::int, -1) <= 0
     or coalesce((o->>'purse')::bigint, -1) <> 0 then
    raise exception '0273 self-assert FAIL: the old step left her fleet %, shortfall %, purse %', o->>'fleet', o->>'shortfall', o->>'purse';
  end if;
  if not exists (select 1 from jsonb_array_elements(n->'orders') e
                  where e->>'verb' = 'SELL' and e->>'status' = 'done' and e->>'text' not like '%AT >=%')
     or not exists (select 1 from jsonb_array_elements(n->'orders') e
                     where e->>'verb' = 'HIRE' and e->>'status' = 'done')
     or not exists (select 1 from jsonb_array_elements(n->'orders') e
                     where e->>'verb' = 'SAIL' and e->>'status' = 'done') then
    raise exception '0273 self-assert FAIL: the new step did not sell at the bid, pay the HIRE and sail: %', n->'orders';
  end if;
  if coalesce(n->>'fleet', '') <> 'SAILING' or coalesce((n->>'shortfall')::int, -1) <> 0
     or coalesce((n->>'purse')::bigint, -1) < 0 then
    raise exception '0273 self-assert FAIL: the new step left her fleet % with a shortfall of % and a purse of %', n->>'fleet', n->>'shortfall', n->>'purse';
  end if;
  if coalesce((n->>'ledger_ok')::boolean, false) is not true then
    raise exception '0273 self-assert FAIL: her purse no longer reconciles with her ledger after the sale and the hire';
  end if;
  if (o->>'digest') is not distinct from (n->>'digest') then
    raise exception '0273 self-assert FAIL: old and new left the same rows where the cut-loss must act';
  end if;
  v_step := v_step + 1;

  -- (h) THE PROBES LEFT NOTHING: every row they wrote went with its transaction, and the traders' switch stands
  -- exactly where the world had it (0272's lesson: a switch write that escapes its case commits the world trading).
  if exists (select 1 from public.orders where error_message = 'probe_0273')
     or exists (select 1 from public.ledger where kind = 'PROBE_0273') then
    raise exception '0273 self-assert FAIL: a probe row survived its transaction';
  end if;
  if (select jsonb_object_agg(key, value) from public.world_config
       where key in ('npc_traders_enabled', 'standing_routes_enabled')) is distinct from v_flags then
    raise exception '0273 self-assert FAIL: the migration left the traders switch ON — npc_traders_enabled / standing_routes_enabled read % where the world had % (a probe''s switch write escaped its transaction)',
      (select jsonb_object_agg(key, value) from public.world_config
        where key in ('npc_traders_enabled', 'standing_routes_enabled')), v_flags;
  end if;

  raise notice '0273 self-assert ok: A SALE IS THE WHOLE STACK. cmd.resolve_qty reverses to its pre-image hunk by hunk (md5 %, prod''s own; its tail pinned), ACL / volatility / definer / config unmoved, every other function in the four schemas unmoved (md5), no function minted, the quay takers and the client entry points unmoved. The arithmetic grid (% points): a buy is identical for every v_max and every mode; a sell is identical exactly when its resolved quantity is a whole tun — 0.93 sells 0.93 (today 0), 3.4 sells 3.4 (today 3, stranding a crumb), HALF of 3 sells 1.5 (today 1); floor(v/2) = floor(floor(v)/2) throughout. Direct probes on merchant %: SELL ALL / HALF / PCT 30 of 0.93 t (old E_NO_CARGO, new sells the exact tonnage, the stack empties, the stock restored, the purse credited the quote''s total), ALL of 3.4 (old 3 + a 0.4 crumb, new 3.4), ALL of a whole 4 t (identical rows), an empty hold (E_NO_CARGO both), BUY ALL / HALF / PCT (resolve equal, identical rows). The queue (prod''s normal line, kind SELL good_id null qty null at_profit true, rendered → parsed → enqueued → advanced): old skips every SELL E_NO_CARGO and credits nothing; new executes each SELL for the exact tonnage and credits the quote''s totals; a bid below the basis still refuses (sub-ton: old E_NO_CARGO, new E_PRICE_LIMIT, the hold intact; a whole 2 t: E_PRICE_LIMIT and identical rows). The seam, her step OLD vs NEW on merchant % (% d. hire, a sub-ton hold worth % d. at the bid in % stacks): OLD leaves every cut-loss SELL skipped E_NO_CARGO, the HIRE skipped E_INSUFFICIENT_FUNDS and the SAIL refused E_CREW_SHORT with her docked; NEW sells at the bid, pays the HIRE, sails, the crew restored, the purse % d. and the ledger reconciled; the control identical. Rolled back.',
    (select md5 from defs_before_0273), v_grid, g.route_id, g.route_id,
    n->>'hire', n->>'hold_value', n->>'stacks', n->>'purse';
end $$;

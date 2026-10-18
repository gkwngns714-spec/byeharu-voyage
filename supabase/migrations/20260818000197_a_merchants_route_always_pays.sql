-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0197 — A MERCHANT'S ROUTE ALWAYS PAYS  (a loop is sailed only when a lap of it leaves her more than
--        nothing; her loops are built from paying trades — the distance premium — for every hull)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS (2026-10-18 ~13:25 UTC) ───────────────────────────────────────────────────
-- *"if they wait when there is no profitable route, how long would they wait? why is there a route that
-- has no profit? this is design defect."*
--
-- ── WHAT PROD SHOWED (read-only, 2026-10-18 13:55–14:30 UTC, head 0181–0182; docs/dev-log/2026-10-18-routes-always-pay.md)
-- * Merchant laps closed in two hours: 1,804, of which 927 (51 %) at ≤ 0; 323 of 837 routes laid up.
-- * By the loop's length (three hours): under 4,000 nm a lap (607 routes) 60–83 % of laps close ≤ 0;
--   4,000–8,000 nm 36 %, 8,000–16,000 nm 16 %, longer 9 %. The long loops earn 25 k–390 k a route.
--   0173's premium is haul 1.03 at 1,000 nm, 1.13 at 2,000, 1.32 at 3,000 — a short hop's gap is
--   smaller than spread + tax + wages + stores.
-- * COMPTOIR CHASTELLAIN ("Voyage Hamburg", a barque, Le Havre ↔ Gdansk, purse 5,576): 168 laps, the
--   last seven −15 / −16 / −15 … Her loop carried parcels (0181's v_any), so she was never laid up:
--   buy 1,247 at Gdansk, sell 1,329 at Le Havre, then wages 70 + tax 12 + stores 16 → −16; or the
--   parcels' SELL refused at the limit and the lap pays only its stores (−15). The lap's whole profit
--   was smaller than what the lap costs.
-- * 0120's far loops were offered only to a hold of 200 tuns or more; a 56–90 tun barque saw only
--   her five nearest harbours.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) A LOOP PAYS WHEN A LAP OF IT LEAVES HER MORE THAN NOTHING. public.npc_plan already priced every
--     loop's net — the parcels' profit after tax, less the wages its sea-days owe and the stores it eats
--     (0142) — and scored by it, but wrote and sailed a loop whenever some leg carried a parcel (v_any).
--     Now the loop she will sail pays only when that net is above nothing (v_pays). One that does not is
--     written with NO BUY (SELL at a profit at every stop, and 0142's cut-loss), so she never buys into a
--     loss; at her lap start with nothing aboard she is laid up (0181) and re-asked every ~10 minutes
--     (0182). A paying loop on offer is taken over a losing one of hers outright (its score is above
--     nothing, hers is not: npc_loop_switches, unchanged).
-- (2) LOOPS BUILT FROM PAYING TRADES. public.npc_loop_candidates' 'far' (the farthest legs, holds of 200
--     tuns or more) is replaced by 'trade', for every hull: the npc_route_trade_candidates (6) harbours
--     where the goods her harbour makes fetch the greatest distance premium (port_goods.haul, 0173's
--     one derivation), plus the premium the goods made THERE fetch at home — so the way back carries a
--     paying good where one exists — over every feasible known leg of hers and every known leg of
--     npc_route_far_nm or more out of a neighbour. Each is priced by THE leg planner (npc_leg_lines:
--     world.quote, the sailed distance, the profit tax, the buyer cap) like every other loop, and (1)
--     decides. The near and three-stop loops are as before.
-- (3) HER LOOP IS PRICED FIRST. At a lap start public.npc_plan prices her present loop, and fetches and
--     prices the loops on offer only when it leaves her nothing, she lies off it, or on a review lap
--     (every npc_route_review_laps-th, 3): a loop that pays is kept between reviews without pricing
--     fifteen others each lap — the trade loops' long legs are dear to price, and the arrivals sweep
--     pays for every lap start.
-- (4) The knobs: npc_route_trade_candidates NEW (6), npc_route_review_laps NEW (3);
--     npc_route_far_candidates and npc_route_far_hold_tuns DELETED (their only reader is gone).
--     npc_buyers_per_good is kept at 3 (the dev-log's numbers).
--
-- ── NOT THE OWNER'S — CONFIRM ───────────────────────────────────────────────────────────────────
-- * 6 trade candidates; the rank (best haul out + best haul back); a 3-stop loop is not built for trade.
-- * "Pays" is a net above 0 a lap at plan time, with no further cushion.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE FUNCTION ×2 by hunks, one world_config INSERT (2 rows), one DELETE. The probes run on their
-- own merchants' rows inside sub-transactions rolled back whole (asserted). No LOCK TABLE, no set role,
-- no set local, no begin. Timings are notices only.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0196, LF-normalised, each asserted to
-- occur exactly once and to reverse to its pre-image, ACL unchanged): public.npc_plan (0181 line),
-- public.npc_loop_candidates (0139 line).
-- ROLLBACK: a forward slice restores the two bodies (each hunk's OLD text is here verbatim) and the
-- knobs (npc_route_far_candidates 3, npc_route_far_hold_tuns 200).
-- VERSION: 0197 (provisional; renumbered to head + 1 at deploy).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0197(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- THE NET OF A WRITTEN LOOP, as public.npc_plan prices it (0142's net, the planner's own leg planner): for
-- the probes, to read back what a lap of the loop the planner wrote leaves her.
create or replace function pg_temp.loop_net_0197(p_route uuid)
returns jsonb
language plpgsql
as $$
declare
  sr      public.standing_routes%rowtype;
  v_fleet uuid;
  v_hold  numeric;
  v_crew  int;
  v_speed numeric;
  v_ports uuid[];
  v_n     int;
  v_leg   jsonb;
  v_profit numeric := 0;
  v_wages numeric := 0;
  v_nm    numeric := 0;
  v_sea_d numeric;
  j       int;
begin
  select * into sr from public.standing_routes where id = p_route;
  v_fleet := coalesce(sr.fleet_id, (select nf.fleet_id from public.npc_fleets nf where nf.route_id = p_route));
  select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(s.id)), 0) into v_crew, v_hold
    from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_fleet;
  v_hold := v_hold + public.fleet_free_hold(v_fleet);
  v_speed := greatest(coalesce(voyage.fleet_speed(v_fleet), 0), 0.1);
  v_ports := array(select s.port_id from public.standing_route_stops s where s.route_id = p_route order by s.ord);
  v_n := cardinality(v_ports);
  for j in 1 .. v_n loop
    v_leg := public.npc_leg_lines(p_route, v_ports[j], v_ports[j % v_n + 1], v_hold, v_crew, v_speed);
    v_profit := v_profit + coalesce((v_leg->>'profit')::numeric, 0);
    v_wages := v_wages + coalesce((v_leg->>'wages')::numeric, 0);
    v_nm := v_nm + coalesce((v_leg->>'nm')::numeric, 0);
  end loop;
  v_sea_d := v_nm / (v_speed * 24);
  return jsonb_build_object('net', round(v_profit - public.wages_from_profit(v_wages, v_profit)
           - public.stores_cost(sr.player_id, v_crew * public.wc_num('water_per_crew_day') * v_sea_d,
                                v_crew * public.wc_num('food_per_crew_day') * v_sea_d)),
         'nm', round(v_nm), 'stops', (select string_agg(p.code, '-' order by s.ord) from public.standing_route_stops s
                                       join public.ports p on p.id = s.port_id where s.route_id = p_route),
         'buys', (select count(*) from public.standing_route_lines l where l.route_id = p_route and l.kind = 'BUY'),
         'reason', sr.paused_reason);
end $$;

-- A MERCHANT AT HER LAP START, the probes' one precondition (her own rows, rolled back with the rest):
-- the routes and merchants on, her fleet docked at her stop 0 between laps, nothing aboard, no order.
create or replace function pg_temp.at_lap_start_0197(p_fleet uuid, p_route uuid)
returns void
language plpgsql
as $$
declare
  v_home uuid := (select s.port_id from public.standing_route_stops s where s.route_id = p_route and s.ord = 0);
begin
  update public.voyages set status = 'ABORTED' where fleet_id = p_fleet and status = 'SAILING';
  update public.orders set status = 'cancelled' where fleet_id = p_fleet and status in ('pending', 'active', 'failed');
  update public.fleets set status = 'DOCKED', port_id = v_home, lat = null, lon = null, busy_until = null where id = p_fleet;
  update public.ships set cargo = '{}'::jsonb where fleet_id = p_fleet;
  update public.standing_route_laps set closed_at = now() where route_id = p_route and closed_at is null;
  update public.standing_routes set fleet_id = p_fleet, lap_id = null, stop_cursor = 0, paused_reason = null, hold_until = null
   where id = p_route;
end $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0197 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('public.npc_plan(timestamp with time zone,uuid)'),
               ('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)')) f(fn);

do $$
begin
  if (select count(*) from defs_before_0197 where def is not null) <> 2 then
    raise exception '0197 self-assert FAIL: % of the 2 bodies found', (select count(*) from defs_before_0197 where def is not null);
  end if;
  if exists (select 1 from public.world_config where key in ('npc_route_trade_candidates', 'npc_route_review_laps'))
     or (select count(*) from public.world_config where key in ('npc_route_far_candidates', 'npc_route_far_hold_tuns')) <> 2 then
    raise exception '0197 self-assert FAIL: the knobs are not as this file was written against';
  end if;
end $$;

-- the old planner and its old candidates under pg_temp names, for the positive control
do $$
declare
  v_plan text := replace(replace((select def from defs_before_0197 where fn like 'public.npc_plan%'),
                   'CREATE OR REPLACE FUNCTION public.npc_plan(', 'CREATE OR REPLACE FUNCTION pg_temp.npc_plan_old_0197('),
                   'public.npc_loop_candidates(', 'pg_temp.npc_loop_candidates_old_0197(');
  v_cand text := replace((select def from defs_before_0197 where fn like 'public.npc_loop_candidates%'),
                   'CREATE OR REPLACE FUNCTION public.npc_loop_candidates(', 'CREATE OR REPLACE FUNCTION pg_temp.npc_loop_candidates_old_0197(');
begin
  if v_plan not like '%pg_temp.npc_plan_old_0197(%' or v_plan not like '%pg_temp.npc_loop_candidates_old_0197(%'
     or v_cand not like '%pg_temp.npc_loop_candidates_old_0197(%' then
    raise exception '0197 self-assert FAIL: the old copies were not renamed';
  end if;
  execute v_cand;
  execute v_plan;
end $$;

-- ── 2. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('npc_route_trade_candidates', to_jsonb(6),
   '0197: how many TRADE loops a merchant prices at her lap start (public.npc_loop_candidates): the harbours '
   'where the goods her harbour makes fetch the greatest distance premium (port_goods.haul), and the way back '
   'the same, over her known legs and her neighbours'' long ones. For every hull. Replaces 0120''s far loops.'),
  ('npc_route_review_laps', to_jsonb(3),
   '0197: a merchant whose present loop pays is offered other loops (public.npc_loop_candidates, priced by '
   'public.npc_plan) only every npc_route_review_laps-th lap; a loop that leaves her nothing, or one she lies off, '
   'is reviewed at once. Keeps the arrivals sweep inside its budget.');
delete from public.world_config where key in ('npc_route_far_candidates', 'npc_route_far_hold_tuns');

-- ── 3. THE HUNKS (sliced from the live bodies; each occurs once; each body reverses; ACL unchanged)
create temporary table hunks_0197 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n)) on commit drop;
insert into hunks_0197 values
('public.npc_plan(timestamp with time zone,uuid)', 1,
$h$--   * Nothing pays on any leg of the loop written: it is written as it stands — SELL at a profit at
--     every stop and no BUY. Counted `ballast`.$h$,
$h$--   * 0186: THE LOOP WRITTEN DOES NOT PAY — what a lap of it leaves her (the net above: the parcels'
--     profit after tax, less the loop's wages and stores) is nothing or less, whether or not some leg
--     carries a parcel: it is written as it stands with NO BUY — SELL at a profit at every stop (and
--     0142's cut-loss) — so she never buys into a loss. Counted `ballast`.$h$),
('public.npc_plan(timestamp with time zone,uuid)', 2,
$h$  v_aboard  numeric;       -- 0181: the tuns she carries now (public.ship_cargo_tuns)
$h$,
$h$  v_aboard  numeric;       -- 0181: the tuns she carries now (public.ship_cargo_tuns)
  v_pays    boolean;       -- 0186: the loop she will sail leaves her more than nothing a lap
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 3,
$h$      -- 0115: Nothing pays: the loop is written as it stands — SELL at a profit at every stop and no
      -- BUY. Counted `ballast`.
      if not v_any then
        v_laid := v_laid + 1;
      end if;
$h$,
$h$      -- 0186: A LOOP PAYS WHEN A LAP OF IT LEAVES HER MORE THAN NOTHING — the net the score is made of
      -- (parcels' profit after tax, less the wages its sea-days owe and the stores it eats), not when some
      -- leg carries a parcel (0115/0181's v_any): a loop whose parcels do not cover her wages and stores
      -- lost the same few ducats every lap (the owner, 2026-10-18: "why is there a route that has no
      -- profit? this is design defect"). One that does not pay is written with no BUY — SELL at a profit
      -- at every stop, and the cut-loss — so she buys nothing into a loss. Counted `ballast`.
      v_pays := coalesce(case when v_best_i <> 0 then v_best_net else v_cur_net end, 0) > 0;
      if not v_pays then
        v_laid := v_laid + 1;
        select jsonb_agg(x || jsonb_build_object('lines',
                 coalesce((select jsonb_agg(l order by o) from jsonb_array_elements(x->'lines') with ordinality u(l, o)
                            where l->>'kind' <> 'BUY'), '[]'::jsonb)) order by k)
          into v_stops from jsonb_array_elements(v_stops) with ordinality t(x, k);
      end if;
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 4,
$h$      if not v_any and v_choose and not v_off and coalesce(v_aboard, 0) <= 0 then$h$,
$h$      -- 0186: and "none pays" is v_pays — every loop on offer was priced and the best leaves her nothing.
      if not v_pays and v_choose and not v_off and coalesce(v_aboard, 0) <= 0 then$h$),
('public.npc_plan(timestamp with time zone,uuid)', 5,
$h$'No cargo pays on any leg of her loops at present; she waits in port.'$h$,
$h$'No loop of hers pays its wages and stores at present; she waits in port.'$h$),
('public.npc_plan(timestamp with time zone,uuid)', 6,
$h$  v_switch  numeric := public.wc_num('npc_route_switch_pct');
$h$,
$h$  v_switch  numeric := public.wc_num('npc_route_switch_pct');
  v_review  int     := public.wc_int('npc_route_review_laps');   -- 0186
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 7,
$h$      if v_choose then
        for lp in select * from public.npc_loop_candidates(sr.id, r.fleet_id, f.port_id, v_hold, v_speed) loop
          exit when jsonb_array_length(v_loops) >= v_cand;
          v_loops := v_loops || jsonb_build_array(lp.stops);
        end loop;
      end if;

      -- PRICE EVERY LOOP through the leg planner, each distinct leg once.
      v_memo := '{}'::jsonb;
      v_best_i := 0;
      for i in 0 .. jsonb_array_length(v_loops) - 1 loop
$h$,
$h$      -- 0186: the loops on offer are fetched once her present loop is priced (below).

      -- PRICE EVERY LOOP through the leg planner, each distinct leg once.
      v_memo := '{}'::jsonb;
      v_best_i := 0;
      i := 0;
      while i < jsonb_array_length(v_loops) loop   -- 0186: the candidates join after loop 0
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 8,
$h$          v_best_tier := v_tier;   -- 0152
        end if;
      end loop;
      v_cands := v_cands + jsonb_array_length(v_loops);
$h$,
$h$          v_best_tier := v_tier;   -- 0152
        end if;
        -- 0186: HER PRESENT LOOP IS PRICED FIRST, and the loops on offer (public.npc_loop_candidates) are
        -- fetched and priced only when it leaves her nothing, when she lies off it, or on a review lap
        -- (every npc_route_review_laps-th): a loop that pays is kept between reviews without pricing
        -- fifteen others at every lap start — the trade loops' long legs cost the arrivals sweep.
        if i = 0 and v_choose and (v_net <= 0 or v_off or sr.lap_no % greatest(v_review, 1) = 0) then
          for lp in select * from public.npc_loop_candidates(sr.id, r.fleet_id, f.port_id, v_hold, v_speed) loop
            exit when jsonb_array_length(v_loops) >= v_cand;
            v_loops := v_loops || jsonb_build_array(lp.stops);
          end loop;
        end if;
        i := i + 1;
      end loop;
      v_cands := v_cands + jsonb_array_length(v_loops);
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 9,
$h$--     loop and up to npc_route_candidates others (public.npc_loop_candidates), each priced through
$h$,
$h$--     loop and up to npc_route_candidates others (public.npc_loop_candidates; 0186: only when hers leaves
--     her nothing, she lies off it, or on a review lap, every npc_route_review_laps-th), each priced through
$h$),
('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 1,
$h$--   far   : (hold >= npc_route_far_hold_tuns) out-and-back on the npc_route_far_candidates
--           farthest known legs of npc_route_far_nm or more; her harbour having none, via each
--           neighbour's farthest such leg (home -> X -> F -> X -> home).
$h$,
$h$--   trade : 0186 (the owner, 2026-10-18: "why is there a route that has no profit? this is design
--           defect") LOOPS BUILT FROM PAYING TRADES, for every hull: out-and-back to the
--           npc_route_trade_candidates harbours where the goods her harbour makes sell for the most
--           over what they cost here, and the way back pays the same way — ranked by THE distance
--           premium (port_goods.haul, 0173's one derivation) both ways, over every feasible known leg of hers (home -> D -> home) and every known leg of npc_route_far_nm or
--           more out of a neighbour (home -> X -> D -> X -> home). The leg planner
--           (public.npc_leg_lines, through npc_plan) prices each, and only a loop that pays is sailed.
--           Replaces 0120's 'far' (the farthest legs, and only for a hold of 200 tuns or more: a far
--           city pays by the unit, so a small hull is paid there too).
$h$),
('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 2,
$h$  v_farn    int     := public.wc_int('npc_route_far_candidates');
  v_far_nm  numeric := public.wc_num('npc_route_far_nm');
  v_far_hld numeric := public.wc_num('npc_route_far_hold_tuns');
$h$,
$h$  v_tradn   int     := public.wc_int('npc_route_trade_candidates');   -- 0186
  v_far_nm  numeric := public.wc_num('npc_route_far_nm');
$h$),
('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 3,
$h$  v_farset  jsonb;
$h$,
$h$  v_dests   jsonb := '[]'::jsonb;   -- 0186: every destination a trade loop may make, with its way there
  v_xd      jsonb;                 -- 0186
$h$),
('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 4,
$h$  if p_hold >= v_far_hld then
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_farset
      from (select x from jsonb_array_elements(v_legs) x where (x->>'nm')::numeric >= v_far_nm
             order by (x->>'nm')::numeric desc, x->>'port_id' limit v_farn) z;
  else
    v_farset := '[]'::jsonb;
  end if;

  -- OUT AND BACK, near then far. The way back is a known leg of the destination's.
  for b in select x from jsonb_array_elements(v_nearset || v_farset) x loop
    exit when v_out >= v_max - 1;
    if not v_cache ? (b->>'port_id') then
      v_cache := v_cache || jsonb_build_object(b->>'port_id',
                   public.npc_feasible_legs((b->>'port_id')::uuid, p_speed, v_days_cap));
    end if;
    select x into v_ret from jsonb_array_elements(v_cache->(b->>'port_id')) x where x->>'port_id' = p_home::text;
    continue when v_ret is null;
    stops := jsonb_build_array(v_home || jsonb_build_object('course', b->'course', 'nm', b->'nm'),
                              jsonb_build_object('port_id', b->'port_id', 'code', b->'code',
                                                 'course', v_ret->'course', 'nm', v_ret->'nm'));
    kind := case when (b->>'nm')::numeric >= v_far_nm then 'far' else 'near' end;
    v_out := v_out + 1;
    return next;
  end loop;

  -- FAR VIA A NEIGHBOUR, when her own harbour has no long haul: home -> X -> F -> X -> home.
  if p_hold >= v_far_hld and jsonb_array_length(v_farset) = 0 then
    for b in select x from jsonb_array_elements(v_nearset) x loop
      exit when v_out >= v_max - 1 or v_farn <= 0;
      select x into v_xf from jsonb_array_elements(v_cache->(b->>'port_id')) x
       where (x->>'nm')::numeric >= v_far_nm order by (x->>'nm')::numeric desc, x->>'port_id' limit 1;
      continue when v_xf is null;
      if not v_cache ? (v_xf->>'port_id') then
        v_cache := v_cache || jsonb_build_object(v_xf->>'port_id',
                     public.npc_feasible_legs((v_xf->>'port_id')::uuid, p_speed, v_days_cap));
      end if;
      select x into v_fx from jsonb_array_elements(v_cache->(v_xf->>'port_id')) x where x->>'port_id' = b->>'port_id';
      select x into v_ret from jsonb_array_elements(v_cache->(b->>'port_id')) x where x->>'port_id' = p_home::text;
      continue when v_fx is null or v_ret is null;
      stops := jsonb_build_array(
        v_home || jsonb_build_object('course', b->'course', 'nm', b->'nm'),
        jsonb_build_object('port_id', b->'port_id', 'code', b->'code', 'course', v_xf->'course', 'nm', v_xf->'nm'),
        jsonb_build_object('port_id', v_xf->'port_id', 'code', v_xf->'code', 'course', v_fx->'course', 'nm', v_fx->'nm'),
        jsonb_build_object('port_id', b->'port_id', 'code', b->'code', 'course', v_ret->'course', 'nm', v_ret->'nm'));
      kind := 'far';
      v_out := v_out + 1;
      v_farn := v_farn - 1;
      return next;
    end loop;
  end if;

$h$,
$h$
  -- OUT AND BACK to the nearest. The way back is a known leg of the destination's.
  for b in select x from jsonb_array_elements(v_nearset) x loop
    exit when v_out >= v_max - 1;
    if not v_cache ? (b->>'port_id') then
      v_cache := v_cache || jsonb_build_object(b->>'port_id',
                   public.npc_feasible_legs((b->>'port_id')::uuid, p_speed, v_days_cap));
    end if;
    select x into v_ret from jsonb_array_elements(v_cache->(b->>'port_id')) x where x->>'port_id' = p_home::text;
    continue when v_ret is null;
    stops := jsonb_build_array(v_home || jsonb_build_object('course', b->'course', 'nm', b->'nm'),
                              jsonb_build_object('port_id', b->'port_id', 'code', b->'code',
                                                 'course', v_ret->'course', 'nm', v_ret->'nm'));
    kind := 'near';
    v_out := v_out + 1;
    return next;
  end loop;

  -- 0186: TRADE LOOPS. Every destination she can reach on known legs that is not a near loop
  -- already: directly (home -> D), or for a long haul through a neighbour (home -> X -> D, D
  -- npc_route_far_nm or more from X).
  for b in select x from jsonb_array_elements(v_legs) x loop
    continue when v_nearset @> jsonb_build_array(jsonb_build_object('port_id', b->'port_id'));
    v_dests := v_dests || jsonb_build_object('d', b->'port_id', 'out', b);
  end loop;
  for b in select x from jsonb_array_elements(v_nearset) x loop
    continue when not v_cache ? (b->>'port_id');
    for v_xd in select x from jsonb_array_elements(v_cache->(b->>'port_id')) x
                 where (x->>'nm')::numeric >= v_far_nm and x->>'port_id' <> p_home::text loop
      continue when v_dests @> jsonb_build_array(jsonb_build_object('d', v_xd->'port_id'));
      v_dests := v_dests || jsonb_build_object('d', v_xd->'port_id', 'x', b, 'out', v_xd);
    end loop;
  end loop;
  -- THE RANK, by the distance premium (port_goods.haul, 0173's one derivation — haul_nm 0 is a city that
  -- makes the good): the best haul any good her harbour makes fetches at D, plus the best haul any good D
  -- makes fetches here — the way back carries a paying good where one exists. One read of the two
  -- market rows per good, for every destination at once. Then, best first, the way back is found (a known
  -- leg D -> home, or D -> X -> home) and the first npc_route_trade_candidates loops are offered; the leg
  -- planner (through npc_plan) says whether each pays.
  for t in
    select dd.x
      from jsonb_array_elements(v_dests) dd(x)
      left join lateral (
        select max(case when ph.haul_nm = 0 then pd.haul end) as out_haul,
               max(case when pd.haul_nm = 0 then ph.haul end) as back_haul
          from public.port_goods pd
          join public.port_goods ph on ph.port_id = p_home and ph.good_id = pd.good_id
         where pd.port_id = (dd.x->>'d')::uuid and (ph.haul_nm = 0 or pd.haul_nm = 0)) hh on true
     order by coalesce(hh.out_haul, 1) + coalesce(hh.back_haul, 1) desc, dd.x->>'d'
  loop
    exit when v_tradn <= 0 or v_out >= v_max - 1;
    if not v_cache ? (t->>'d') then
      v_cache := v_cache || jsonb_build_object(t->>'d', public.npc_feasible_legs((t->>'d')::uuid, p_speed, v_days_cap));
    end if;
    if t ? 'x' then
      select x into v_fx from jsonb_array_elements(v_cache->(t->>'d')) x where x->>'port_id' = t->'x'->>'port_id';
      select x into v_ret from jsonb_array_elements(v_cache->(t->'x'->>'port_id')) x where x->>'port_id' = p_home::text;
      continue when v_fx is null or v_ret is null;
      stops := jsonb_build_array(
        v_home || jsonb_build_object('course', t->'x'->'course', 'nm', t->'x'->'nm'),
        jsonb_build_object('port_id', t->'x'->'port_id', 'code', t->'x'->'code', 'course', t->'out'->'course', 'nm', t->'out'->'nm'),
        jsonb_build_object('port_id', t->'out'->'port_id', 'code', t->'out'->'code', 'course', v_fx->'course', 'nm', v_fx->'nm'),
        jsonb_build_object('port_id', t->'x'->'port_id', 'code', t->'x'->'code', 'course', v_ret->'course', 'nm', v_ret->'nm'));
    else
      select x into v_ret from jsonb_array_elements(v_cache->(t->>'d')) x where x->>'port_id' = p_home::text;
      continue when v_ret is null;
      stops := jsonb_build_array(v_home || jsonb_build_object('course', t->'out'->'course', 'nm', t->'out'->'nm'),
                                jsonb_build_object('port_id', t->'out'->'port_id', 'code', t->'out'->'code',
                                                   'course', v_ret->'course', 'nm', v_ret->'nm'));
    end if;
    kind := 'trade';
    v_out := v_out + 1;
    v_tradn := v_tradn - 1;
    return next;
  end loop;

$h$),
('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 5,
$h$  v_xf      jsonb;
  v_fx      jsonb;
$h$,
$h$  v_fx      jsonb;
$h$);

do $$
declare
  d     record;
  h     record;
  v_def text;
  v_rev text;
begin
  for d in select * from defs_before_0197 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0197 where fn = d.fn order by n loop
      if pg_temp.occurs_0197(v_def, h.old) <> 1 then
        raise exception '0197 self-assert FAIL: hunk % of % occurs % time(s), not once — the deployed body is not what this file was written against',
          h.n, d.fn, pg_temp.occurs_0197(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0197 self-assert FAIL: no hunk for %', d.fn;
    end if;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0197 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0197(v_rev, h.new) <> 1 then
        raise exception '0197 self-assert FAIL: hunk % of % is not in the new body once', h.n, d.fn;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0197 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0197 self-assert FAIL: the ACL of % moved', d.fn;
    end if;
  end loop;
end $$;

-- ── 4. THE PROBES (their own merchants' rows; every one rolled back whole) ─────────────────────
create temp table probe_0197 (k text primary key, j jsonb) on commit drop;

-- (i) COMPTOIR CHASTELLAIN — the owner's −15 a lap. Her first merchant fleet at her lap start, on her loop
-- as prod sailed it at 13:55 UTC (Le Havre ↔ Gdansk) where the world knows both legs, else her own; the
-- market as it stands. (a) The planner writes a loop whose lap leaves her more than nothing, or lays her
-- up with no BUY. (b) POSITIVE CONTROL — wages that eat every parcel (wage_per_crew_day × 10,000, her own
-- block): every loop with a parcel nets her stores below nothing, exactly the −15 lap; the OLD planner
-- writes it WITH its BUYs and does not lay her up; the new one lays her up with no BUY.
do $$
declare
  v_f    record;
  v_leh  uuid := (select id from public.ports where code = 'LEH');
  v_gda  uuid := (select id from public.ports where code = 'GDA');
  v_out  jsonb := '{}'::jsonb;
  v_c1   jsonb;
  v_c2   jsonb;
  v_r    jsonb;
  v_t0   timestamptz;
  k      int;
begin
  for k in 1 .. 3 loop
    begin
      update public.world_config set value = 'true'::jsonb where key in ('standing_routes_enabled', 'npc_traders_enabled');
      select nf.fleet_id, nf.route_id, nf.player_id, f.name into v_f
        from public.npc_fleets nf join public.players pl on pl.id = nf.player_id and pl.company_name = 'Comptoir Chastellain'
        join public.fleets f on f.id = nf.fleet_id
       order by nf.roster_ord limit 1;
      if v_f.fleet_id is null then
        raise exception '0197 self-assert FAIL: the roster holds no Comptoir Chastellain — the probe is named for her';
      end if;
      select l.course into v_c1 from public.npc_known_legs(v_leh) l where l.to_port = v_gda;
      select l.course into v_c2 from public.npc_known_legs(v_gda) l where l.to_port = v_leh;
      if v_c1 is not null and v_c2 is not null then
        v_r := cmd.standing_route_save_for(v_f.player_id, v_f.route_id, null, jsonb_build_array(
                 jsonb_build_object('port', 'LEH', 'course', v_c1, 'repair', false, 'crew_up', true,
                                    'lines', jsonb_build_array(jsonb_build_object('kind', 'SELL', 'at_profit', true))),
                 jsonb_build_object('port', 'GDA', 'course', v_c2, 'repair', false, 'crew_up', true,
                                    'lines', jsonb_build_array(jsonb_build_object('kind', 'SELL', 'at_profit', true)))),
                 null, null, 0);
        v_out := v_out || jsonb_build_object('loop_set', coalesce((v_r->>'ok')::boolean, false));
      else
        v_out := v_out || jsonb_build_object('loop_set', false);
      end if;
      perform pg_temp.at_lap_start_0197(v_f.fleet_id, v_f.route_id);
      v_out := v_out || jsonb_build_object('fleet', v_f.name, 'from', pg_temp.loop_net_0197(v_f.route_id));
      if k >= 2 then
        update public.world_config set value = to_jsonb(public.wc_num('wage_per_crew_day') * 10000) where key = 'wage_per_crew_day';
      end if;
      v_t0 := clock_timestamp();
      if k = 3 then
        -- the old candidates read the two knobs this file deletes: back as they were, in this block only
        insert into public.world_config (key, value, description) values
          ('npc_route_far_candidates', to_jsonb(3), '0197 probe: the pre-image''s knob, rolled back'),
          ('npc_route_far_hold_tuns', to_jsonb(200), '0197 probe: the pre-image''s knob, rolled back');
        v_r := pg_temp.npc_plan_old_0197(now(), v_f.route_id);
      else
        v_r := public.npc_plan(now(), v_f.route_id);
      end if;
      v_out := v_out || jsonb_build_object('plan', v_r - 'notes', 'errors', (select jsonb_agg(x->'error') from jsonb_array_elements(v_r->'notes') x where x ? 'error'), 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000),
                                           'wrote', pg_temp.loop_net_0197(v_f.route_id));
      raise exception 'PROBE_ROLLBACK_0197:%', v_out::text;
    exception when others then
      if sqlerrm not like 'PROBE_ROLLBACK_0197:%' then raise; end if;
      insert into probe_0197 values (case k when 1 then 'chas' when 2 then 'chas_new' else 'chas_old' end,
                                     substr(sqlerrm, length('PROBE_ROLLBACK_0197:') + 1)::jsonb);
      v_out := '{}'::jsonb;
    end;
  end loop;
end $$;

-- (ii) THE FIRST 30 MERCHANTS OF THE ROSTER, each at her lap start in turn on the market as it stands
-- (the buyer cap meets the lines of the ones before her, as at a kickoff): no loop is written with a BUY
-- whose lap leaves her nothing; and the candidates are trade loops, never 0120's 'far'.
do $$
declare
  r      record;
  v_r    jsonb;
  v_w    jsonb;
  v_t0   timestamptz;
  v_out  jsonb := jsonb_build_object('n', 0, 'pays', 0, 'laid', 0, 'bad', 0, 'other', 0, 'ms', 0, 'bad_list', '[]'::jsonb);
begin
  begin
    update public.world_config set value = 'true'::jsonb where key in ('standing_routes_enabled', 'npc_traders_enabled');
    for r in select nf.fleet_id, nf.route_id from public.npc_fleets nf
              where (select count(*) from public.standing_route_stops s where s.route_id = nf.route_id) >= 2
              order by nf.roster_ord limit 30 loop
      perform pg_temp.at_lap_start_0197(r.fleet_id, r.route_id);
      v_t0 := clock_timestamp();
      v_r := public.npc_plan(now(), r.route_id);
      v_out := jsonb_set(v_out, '{ms}', to_jsonb((v_out->>'ms')::numeric + extract(epoch from clock_timestamp() - v_t0) * 1000));
      continue when coalesce((v_r->>'planned')::int, 0) = 0;
      v_w := pg_temp.loop_net_0197(r.route_id);
      v_out := jsonb_set(v_out, '{n}', to_jsonb((v_out->>'n')::int + 1));
      if (v_w->>'net')::numeric > 0 then
        v_out := jsonb_set(v_out, '{pays}', to_jsonb((v_out->>'pays')::int + 1));
      elsif v_w->>'reason' = 'laid_up' and (v_w->>'buys')::int = 0 then
        v_out := jsonb_set(v_out, '{laid}', to_jsonb((v_out->>'laid')::int + 1));
      elsif (v_w->>'buys')::int > 0 then
        v_out := jsonb_set(v_out, '{bad}', to_jsonb((v_out->>'bad')::int + 1));
        v_out := jsonb_set(v_out, '{bad_list}', (v_out->'bad_list') || jsonb_build_array(v_w));
      else
        v_out := jsonb_set(v_out, '{other}', to_jsonb((v_out->>'other')::int + 1));   -- not paying, no BUY, not laid up
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('kinds', (select jsonb_object_agg(c.kind, c.n) from (
      select lc.kind, count(*) n from (select nf.fleet_id, nf.route_id from public.npc_fleets nf order by nf.roster_ord limit 30) z
       cross join lateral public.npc_loop_candidates(z.route_id, z.fleet_id,
               (select s.port_id from public.standing_route_stops s where s.route_id = z.route_id and s.ord = 0),
               (select coalesce(sum(public.ship_cargo_tuns(s.id)), 0) from public.ships s where s.fleet_id = z.fleet_id) + public.fleet_free_hold(z.fleet_id),
               greatest(coalesce(voyage.fleet_speed(z.fleet_id), 0), 0.1)) lc
       group by 1) c));
    raise exception 'PROBE_ROLLBACK_0197:%', v_out::text;
  exception when others then
    if sqlerrm not like 'PROBE_ROLLBACK_0197:%' then raise; end if;
    insert into probe_0197 values ('roster', substr(sqlerrm, length('PROBE_ROLLBACK_0197:') + 1)::jsonb);
  end;
end $$;

-- ── 5. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  c  jsonb := (select j from probe_0197 where k = 'chas');
  cn jsonb := (select j from probe_0197 where k = 'chas_new');
  co jsonb := (select j from probe_0197 where k = 'chas_old');
  r  jsonb := (select j from probe_0197 where k = 'roster');
begin
  if public.wc_int('npc_route_trade_candidates') <> 6 or public.wc_int('npc_route_review_laps') <> 3
     or exists (select 1 from public.world_config where key in ('npc_route_far_candidates', 'npc_route_far_hold_tuns')) then
    raise exception '0197 self-assert FAIL: the knobs did not land';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'voyage', 'world')
                and p.prosrc ~ '(npc_route_far_candidates|npc_route_far_hold_tuns)') then
    raise exception '0197 self-assert FAIL: a live body still reads a deleted knob';
  end if;
  -- (i)(a) Chastellain on the market as it stands
  if not ((c->'wrote'->>'net')::numeric > 0
          or (c->'wrote'->>'reason' = 'laid_up' and (c->'wrote'->>'buys')::int = 0)) then
    raise exception '0197 self-assert FAIL: Comptoir Chastellain was written a loop that leaves her % a lap (% BUY lines, %): %',
      c->'wrote'->>'net', c->'wrote'->>'buys', c->'wrote'->>'reason', c;
  end if;
  -- (i)(b) the positive control: the old planner sails the losing loop with its BUYs, the new one lays her up
  if not (co->'wrote'->>'net')::numeric <= 0 or (co->'wrote'->>'buys')::int < 1 or co->'wrote'->>'reason' is not null then
    raise exception '0197 self-assert FAIL: the positive control cannot see the defect — the old planner, wages eating every parcel, wrote %', co;
  end if;
  if cn->'wrote'->>'reason' is distinct from 'laid_up' or (cn->'wrote'->>'buys')::int <> 0 or (cn->'plan'->>'waiting')::int <> 1 then
    raise exception '0197 self-assert FAIL: wages eating every parcel, the new planner did not lay Comptoir Chastellain up with no BUY: %', cn;
  end if;
  -- (ii)
  if (r->>'n')::int < 20 or (r->>'bad')::int <> 0 or (r->>'other')::int <> 0 then
    raise exception '0197 self-assert FAIL: of % merchants at their lap start, % were written a BUY on a loop that leaves nothing, % neither paid nor waited: %',
      r->>'n', r->>'bad', r->>'other', r->'bad_list';
  end if;
  if r->'kinds' ? 'far' or not r->'kinds' ? 'trade' then
    raise exception '0197 self-assert FAIL: the candidates are not trade loops: %', r->'kinds';
  end if;

  raise notice '0197 self-assert ok: A MERCHANT''S ROUTE ALWAYS PAYS. COMPTOIR CHASTELLAIN (%; loop set to LEH-GDA %): from % (net % a lap, % BUY) the planner wrote % — net % a lap over % nm, % BUY, %; POSITIVE CONTROL, wages eating every parcel: the OLD planner wrote % with % BUY at % a lap and sailed it, the new one laid her up with % BUY. THE ROSTER''S FIRST %: % on a loop that pays, % waiting (no BUY), 0 written a BUY on a loop that leaves nothing; their candidates %; % ms of planning (% ms a merchant). Knobs: npc_route_trade_candidates 6, npc_route_review_laps 3; far_candidates and far_hold_tuns deleted. Bodies reverse, ACLs unchanged.',
    c->>'fleet', c->>'loop_set', c->'from'->>'stops', c->'from'->>'net', c->'from'->>'buys',
    c->'wrote'->>'stops', c->'wrote'->>'net', c->'wrote'->>'nm', c->'wrote'->>'buys', coalesce(c->'wrote'->>'reason', 'sailing'),
    co->'wrote'->>'stops', co->'wrote'->>'buys', co->'wrote'->>'net', cn->'wrote'->>'buys',
    r->>'n', r->>'pays', r->>'laid', r->'kinds', round((r->>'ms')::numeric), round((r->>'ms')::numeric / greatest((r->>'n')::int, 1));
end $$;

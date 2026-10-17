-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0150 — A STUCK LAP IS ANSWERED ON THE FIRST CLEAR  (and the casks are filled store by store)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- 0142 said a merchant stuck on an E_ENDURANCE SAIL needed no data change: "the hourly upkeep
-- re-plans her after her third cleared failed order; that re-plan now raises her stores preset,
-- puts her back on the stop she's at, and includes PROVISION DAYS n". On prod the open merchant
-- laps older than 6 h went 369 (14:52 UTC) -> 391 (15:12), after a reconcile that succeeded.
--
-- ── WHAT WAS FOUND (prod, read-only, head 0148, 2026-10-17 ~15:15 UTC) ──────────────────────────
-- 391 stuck laps: 270 DOCKED with a failed SAIL E_ENDURANCE at the head of the queue; 88
-- UNABLE_TO_SAIL (the tow, 0151, answers those); 33 SAILING (re-planned after 0142 and released —
-- 0142's re-plan works when it comes).
-- (1) THE RE-PLAN DOES NOT COME. npc_tend_route counts the clears of a lap by its NPC_CLEARED
--     events, and npc_compact deletes events older than npc_retention_hours (6). The hourly pass
--     spends its 60 s budget (66-71 s a run) and clears ~120 merchants an hour, so a stuck one is
--     reached every two or three hours: 251 of the 270 held fewer than three clears in the window
--     and had not been re-planned since 0142. "Carrera Guayaquil" (49bb3667): clear n = 4 at 10:07
--     (re-planned by the OLD planner, which raised no preset), the compactor took the earlier ones,
--     n = 2 at 15:07 — no re-plan. And a clear without a re-plan cannot help: her stop has been
--     rendered and her cursor moved on, so cmd.run_standing_route's sail-on branch enqueues only
--     the TAIL (`SAIL TO ...`) — no PROVISION — and the SAIL is refused again, for ever.
-- (2) THE CASKS ARE FULL OF THE WRONG STORE. cmd.do_provision tops the TOTAL of water + food up to
--     the days asked and splits the top-up by the drink/eat ratio. FOUL_WATER (0059) takes water
--     only, so a merchant comes in with food to spare and short water; the spare food counts as
--     room, the top-up is short or nothing ("the casks are already full", E_HOLD_FULL), and the
--     shortest store sets her endurance. 143 of the 270 have water and food more than a day apart.
-- (3) THE HOLD HAS NO ROOM FOR THE CASKS. 41 of the 270 cannot stow the stores the leg needs beside
--     the cargo they still carry (the at-profit SELL refused it, E_PRICE_LIMIT). The cut-loss that
--     lets such a good go waits for two CLOSED laps (0114/0142) — and the lap cannot close.
-- (4) THE PLANNER'S DAYS RUN SHORT ON A LONG LEG. Its preset is the reach table's nm through
--     endurance_margin + 1 day; the SAIL measures the course itself, 2-7 % longer on long legs:
--     19 of the 270 were refused by more than that one day.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) public.npc_tend_route: a failed SAIL refused E_ENDURANCE is re-planned ON THE CLEAR that
--     releases it, not the third. The third-clear rule stays for every other refusal.
-- (2) public.stores_topup(crew, water, food, room, days, full) — THE top-up: each store raised to
--     the days asked, the shorter first, never past the room beside her cargo; answers the days it
--     reaches. cmd.do_provision computes both of its passes through it. Where water and food are
--     in step (every top-up before a broached cask) it is the old arithmetic to the ton — asserted
--     over every crewed hull in the world, both modes — and it never leaves a hull fewer days.
-- (3) public.sail_refused_days(fleet) — the days of stores her head-of-queue SAIL was refused for
--     (the SAIL's own figure, ceil(need) + 1), or 0. npc_plan raises the preset for the loop she
--     keeps to at least that (4 above), and public.npc_casks_blocked reads it.
-- (4) public.npc_casks_blocked(fleet, from, nm, kn): she lies at `from`, her SAIL from there was
--     refused E_ENDURANCE, and a hull of hers that carries cargo cannot reach the leg's days through
--     public.stores_topup. npc_leg_lines then writes the cut-loss — SELL <good> ALL at the quay's
--     bid (0142's line) — for every good aboard, so the PROVISION that follows has its room.
-- Together, on the clear that releases her: the plan raises her preset and writes the cut-loss,
-- the save door puts her cursor back on her stop (0115), cmd.advance renders it whole — SELL,
-- PROVISION DAYS n, BUY, SAIL — and she sails; her lap closes when she reaches her stop 0.
-- No new knob, no new entry point.
--
-- ── NOT DONE ────────────────────────────────────────────────────────────────────────────────────
-- * The UNABLE_TO_SAIL wrecks (88): the tow, 0151.
-- * The third-clear count for other refusals still reads events the compactor ages out. Today no
--   other refusal holds a merchant (all 270 docked stuck laps are E_ENDURANCE); noted, not changed.
-- * A merchant whose purse cannot pay her stores (2) stays refused E_INSUFFICIENT_FUNDS.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly
-- once and reversed to its pre-image: public.npc_tend_route (0137), public.npc_plan (0120 as cut
-- by 0142), public.npc_leg_lines (0120 as cut by 0142/0147), cmd.do_provision (0034 as cut by
-- 0114/0142). ACLs unmoved. The hunks are disjoint from 0151's (the tow cuts npc_plan and
-- npc_tend_route elsewhere), so the two apply in either order.
-- Self-asserts hold on a lived-in world: every probe runs on its own founded merchant and rolls
-- back. Timings: raise notice only. VERSION 0150 (provisional; renumbered at merge).

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0150 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from unnest(array['public.npc_tend_route(timestamptz, uuid, uuid, bigint)',
                    'public.npc_plan(timestamptz, uuid)',
                    'public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)',
                    'cmd.do_provision(uuid, jsonb)']) f(fn);

create temp table before_0150 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.world_config) as knobs;

-- ── 2. THE THREE READINGS ──────────────────────────────────────────────────────────────────────
create or replace function public.stores_topup(p_crew numeric, p_water numeric, p_food numeric,
                                               p_room numeric, p_days numeric, p_full numeric)
returns table (water_t numeric, food_t numeric, days numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0150: THE top-up of one hull's stores. p_room = her hold less her cargo (what water and food may
-- fill); p_days = the days asked (PROVISION DAYS n), or null for FULL, which asks the days that
-- p_full tons (hold x store_ratio) last. Each store is raised to the days asked — the shorter
-- first, then both in step — never past p_room. Answers the tons to ADD and the days she then holds
-- (the shorter store's; before the ENDURANCE skill). A crewless hull keeps the old split: FULL
-- fills it to p_full, DAYS adds nothing. Read by cmd.do_provision (both passes) and by
-- public.npc_casks_blocked.
declare
  v_w    numeric := public.wc_num('water_per_crew_day');
  v_f    numeric := public.wc_num('food_per_crew_day');
  v_cw   numeric;
  v_cf   numeric;
  v_free numeric := greatest(0, coalesce(p_room, 0) - coalesce(p_water, 0) - coalesce(p_food, 0));
  v_dw   numeric;
  v_df   numeric;
  v_max  numeric;
  v_d    numeric;
  v_t    numeric;
begin
  if coalesce(p_crew, 0) <= 0 then
    v_t := greatest(0, least(coalesce(p_room, 0), case when p_days is null then coalesce(p_full, 0) else 0 end)
                       - coalesce(p_water, 0) - coalesce(p_food, 0));
    water_t := round(v_t * v_w / (v_w + v_f), 3);
    food_t  := round(v_t * v_f / (v_w + v_f), 3);
    days    := 9999;
    return next;
    return;
  end if;
  v_cw := p_crew * v_w;
  v_cf := p_crew * v_f;
  v_dw := coalesce(p_water, 0) / v_cw;
  v_df := coalesce(p_food, 0) / v_cf;
  -- THE MOST DAYS THE FREE ROOM REACHES: the shorter store raised toward the other first; if the
  -- room outlasts that, both in step until the room beside her cargo is full.
  if v_dw <= v_df then
    v_max := case when v_cw * (v_df - v_dw) >= v_free then v_dw + v_free / v_cw
                  else coalesce(p_room, 0) / (v_cw + v_cf) end;
  else
    v_max := case when v_cf * (v_dw - v_df) >= v_free then v_df + v_free / v_cf
                  else coalesce(p_room, 0) / (v_cw + v_cf) end;
  end if;
  v_d := least(coalesce(p_days, least(coalesce(p_room, 0), coalesce(p_full, 0)) / (v_cw + v_cf)), v_max);
  water_t := round(greatest(0, v_cw * v_d - coalesce(p_water, 0)), 3);
  food_t  := round(greatest(0, v_cf * v_d - coalesce(p_food, 0)), 3);
  days    := least((coalesce(p_water, 0) + water_t) / v_cw, (coalesce(p_food, 0) + food_t) / v_cf);
  return next;
end $$;

create or replace function public.sail_refused_days(p_fleet uuid)
returns int
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0150: the days of stores her SAIL was refused for — the head of her queue (the order the halt
-- law stops on, as public.npc_tend_route reads it), when it is a SAIL refused E_ENDURANCE: the
-- SAIL's own figure (cmd.figures need: the course she sails through endurance_margin), rounded up,
-- plus one day. 0 otherwise. Read by public.npc_plan (her preset) and public.npc_casks_blocked.
declare
  o record;
begin
  select ord.verb, ord.error_code, ord.error_figures into o
    from public.orders ord
   where ord.fleet_id = p_fleet and ord.status = 'failed'
   order by ord.seq limit 1;
  if o.verb is distinct from 'SAIL' or o.error_code is distinct from 'E_ENDURANCE'
     or (o.error_figures->>'need') is null then
    return 0;
  end if;
  return ceil((o.error_figures->>'need')::numeric)::int + 1;
end $$;

create or replace function public.npc_casks_blocked(p_fleet uuid, p_from uuid, p_nm numeric, p_speed numeric)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0150: SHE CANNOT STOW HER CASKS FOR THIS LEG BESIDE HER CARGO. She lies docked at p_from, her
-- SAIL from there was refused E_ENDURANCE (public.sail_refused_days), and a hull of hers that
-- carries cargo cannot reach the leg's days — the larger of that refusal's and the planner's
-- (p_nm / p_speed through endurance_margin, + 1) — through public.stores_topup. Read by
-- public.npc_leg_lines (the cut-loss for room).
declare
  v_d     int;
  v_reach numeric;
  s       record;
begin
  if p_fleet is null
     or not exists (select 1 from public.fleets f where f.id = p_fleet and f.status = 'DOCKED' and f.port_id = p_from) then
    return false;
  end if;
  v_d := public.sail_refused_days(p_fleet);
  if v_d = 0 then
    return false;
  end if;
  v_d := greatest(v_d, ceil(coalesce(p_nm, 0) / (greatest(coalesce(p_speed, 0), 0.1) * 24)
                            * public.wc_num('endurance_margin'))::int + 1);
  for s in select sh.crew, sh.water_t, sh.food_t,
                  public.ship_hold_capacity(sh.id) as hold, public.ship_cargo_tuns(sh.id) as cargo_t
             from public.ships sh where sh.fleet_id = p_fleet loop
    continue when s.cargo_t <= 0 or coalesce(s.crew, 0) <= 0;
    select t.days into v_reach from public.stores_topup(s.crew, s.water_t, s.food_t, s.hold - s.cargo_t, v_d, null) t;
    if v_reach < v_d then
      return true;
    end if;
  end loop;
  return false;
end $$;

revoke all on function public.stores_topup(numeric, numeric, numeric, numeric, numeric, numeric) from public, anon, authenticated;
revoke all on function public.sail_refused_days(uuid) from public, anon, authenticated;
revoke all on function public.npc_casks_blocked(uuid, uuid, numeric, numeric) from public, anon, authenticated;

-- ── 3. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0150 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0150 values
-- public.npc_tend_route: a SAIL refused E_ENDURANCE is re-planned on the clear that releases it
('public.npc_tend_route(timestamptz, uuid, uuid, bigint)', 1,
$h$        -- 0115: NOT PARKED. The third clear in one lap re-plans her lines on today's market first;
        -- every clear then releases her queue and the executor goes on.
        if v_clears >= 3 then
$h$,
$h$        -- 0115: NOT PARKED. The third clear in one lap re-plans her lines on today's market first;
        -- every clear then releases her queue and the executor goes on.
        -- 0150: A SAIL REFUSED E_ENDURANCE IS RE-PLANNED ON THIS CLEAR. Only a plan answers it (her
        -- preset, room for her casks, her cursor back on her stop so the stop renders whole); a
        -- clear alone re-sends the SAIL and nothing else. The count of three was read off events
        -- the compactor deletes after npc_retention_hours, and the hour's pass reached a stuck
        -- merchant every two or three hours: for 251 of 270 it never came.
        if v_clears >= 3 or (fo.verb = 'SAIL' and fo.error_code = 'E_ENDURANCE') then
$h$),

-- public.npc_plan: the preset of the loop she keeps covers the passage her SAIL was refused for
('public.npc_plan(timestamptz, uuid)', 1,
$h$      for v_try in 1 .. 2 loop
        v_days := ceil((case when v_best_i <> 0 then v_best_maxnm else v_cur_maxnm end)
                       / (v_speed * 24) * v_emargin)::int + 1;
$h$,
$h$      for v_try in 1 .. 2 loop
        v_days := ceil((case when v_best_i <> 0 then v_best_maxnm else v_cur_maxnm end)
                       / (v_speed * 24) * v_emargin)::int + 1;
        -- 0150: AND, FOR THE LOOP SHE KEEPS, NEVER LESS THAN THE PASSAGE HER SAIL WAS REFUSED FOR
        -- (public.sail_refused_days — the SAIL's own measure of the course, 2-7 % past the reach
        -- table's nm on a long leg).
        if v_best_i = 0 then
          v_days := greatest(v_days, public.sail_refused_days(f.id));
        end if;
$h$),

-- public.npc_leg_lines: the cut-loss for room
('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)', 1,
$h$    v_lines := v_lines || jsonb_build_object('kind', 'SELL', 'good', v_cut, 'at_profit', false);   -- 0142: at the quay's bid
  end loop;
$h$,
$h$    v_lines := v_lines || jsonb_build_object('kind', 'SELL', 'good', v_cut, 'at_profit', false);   -- 0142: at the quay's bid
  end loop;
  -- 0150: THE CUT-LOSS FOR ROOM. Her SAIL from here was refused E_ENDURANCE and a hull of hers
  -- cannot stow this leg's casks beside the cargo the at-profit SELL could not move
  -- (public.npc_casks_blocked): every good aboard goes at the quay's bid, so the PROVISION after
  -- it has room and her lap can close — the two-closed-laps cut-loss above never comes to a lap
  -- that cannot close.
  if public.npc_casks_blocked(sr.fleet_id, p_from, v_nm, p_speed) then
    for v_cut in select distinct e.key from public.ships s cross join lateral jsonb_each(s.cargo) e
                  where s.fleet_id = sr.fleet_id and (e.value)::text::numeric > 0
                  order by 1 loop
      continue when v_lines @> jsonb_build_array(jsonb_build_object('kind', 'SELL', 'good', v_cut));
      v_lines := v_lines || jsonb_build_object('kind', 'SELL', 'good', v_cut, 'at_profit', false);
    end loop;
  end if;
$h$),

-- cmd.do_provision: both passes through the one top-up
('cmd.do_provision(uuid, jsonb)', 1,
$h$  v_purse  bigint;
$h$,
$h$  v_purse  bigint;
  v_tw     numeric;   -- 0150: water this hull takes on (public.stores_topup)
  v_tf     numeric;   -- 0150: food
$h$),
('cmd.do_provision(uuid, jsonb)', 2,
$h$    if p_args->>'mode' = 'DAYS' then
      v_days   := (p_args->>'days')::numeric;
      v_target := least(r.hold - r.cargo_t,
                        r.crew * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')) * v_days);
    else
      -- FULL: fill stores to the ship's store_ratio of its hold (DESIGN F.2), never past the hold.
      v_target := least(r.hold - r.cargo_t, r.hold * r.store_ratio);
    end if;
    v_target := greatest(0, v_target - r.water_t - r.food_t);
    -- Split in the same proportion the crew drinks and eats, so a full hold lasts the same number
    -- of days on both stores rather than running dry on water with food to spare.
    v_water := v_water + round(v_target * public.wc_num('water_per_crew_day')
               / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3);
    v_food  := v_food  + round(v_target * public.wc_num('food_per_crew_day')
               / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3);
$h$,
$h$    -- 0150: EACH STORE TO THE DAYS ASKED (DAYS n; FULL = the days the ship's store_ratio of her hold
    -- lasts, DESIGN F.2), the shorter first, never past the hold — public.stores_topup. The old
    -- split topped up the TOTAL, so food left over after a broached cask counted as room and she
    -- lay with short water and "the casks are already full".
    select t.water_t, t.food_t into v_tw, v_tf
      from public.stores_topup(r.crew, r.water_t, r.food_t, r.hold - r.cargo_t,
                               case when p_args->>'mode' = 'DAYS' then (p_args->>'days')::numeric end,
                               r.hold * r.store_ratio) t;
    v_water := v_water + v_tw;
    v_food  := v_food  + v_tf;
$h$),
('cmd.do_provision(uuid, jsonb)', 3,
$h$    if p_args->>'mode' = 'DAYS' then
      v_target := least(r.hold - r.cargo_t,
                        r.crew * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day'))
                        * (p_args->>'days')::numeric);
    else
      v_target := least(r.hold - r.cargo_t, r.hold * r.store_ratio);
    end if;
    v_target := greatest(0, v_target - r.water_t - r.food_t);
    update public.ships
       set water_t = water_t + round(v_target * public.wc_num('water_per_crew_day')
                     / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3),
           food_t  = food_t  + round(v_target * public.wc_num('food_per_crew_day')
                     / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3)
     where id = r.id;
$h$,
$h$    select t.water_t, t.food_t into v_tw, v_tf   -- 0150: the same top-up as the pass above
      from public.stores_topup(r.crew, r.water_t, r.food_t, r.hold - r.cargo_t,
                               case when p_args->>'mode' = 'DAYS' then (p_args->>'days')::numeric end,
                               r.hold * r.store_ratio) t;
    update public.ships
       set water_t = water_t + v_tw,
           food_t  = food_t  + v_tf
     where id = r.id;
$h$);

-- ── 4. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.recut_0150(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0150 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0150 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0150(fn) from defs_before_0150 order by fn;

-- set the probe merchant's purse, through the ledger (the purse reconciles with it).
create or replace function pg_temp.purse_0150(p_player uuid, p_ducats numeric)
returns void language sql
as $$ select public.credit(p_player, 'PROBE_0150',
                           (p_ducats - (select ducats from public.players where id = p_player))::bigint) $$;

-- put the probe merchant where a stuck lap lies: docked at her stop 1 (FNC), her lap open seven
-- hours, her cursor on that stop, her queue empty, nothing aboard, her casks dry.
create or replace function pg_temp.stuck_0150(p_player uuid, p_route uuid, p_fleet uuid, p_port uuid, p_lap int)
returns void language plpgsql
as $$
begin
  perform cmd.clear_for(p_player, p_fleet, false);
  update public.voyages set status = 'ARRIVED' where fleet_id = p_fleet and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = p_port, lat = null, lon = null where id = p_fleet;
  update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb, water_t = 0, food_t = 0 where fleet_id = p_fleet;
  insert into public.standing_route_laps (route_id, lap_no, started_at)
  values (p_route, p_lap, now() - interval '7 hours');
  update public.standing_routes
     set fleet_id = p_fleet, lap_no = p_lap, stop_cursor = 1, paused_reason = null, hold_until = null,
         lap_id = (select id from public.standing_route_laps where route_id = p_route and lap_no = p_lap),
         updated_at = now() - interval '2 minutes'
   where id = p_route;
end $$;

-- ── 5. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_fn       text;
  v_def      text;
  v_back     text;
  h          record;
  v_n        int;
  v_lis      uuid;
  v_fnc      uuid;
  v_leg      jsonb;
  v_back_c   jsonb;
  v_m        uuid;
  v_mfleet   uuid;
  v_route    uuid;
  v_preset   uuid;
  v_good     uuid;
  v_code     text;
  v_bulk     numeric;
  v_qty      numeric;
  v_need     int;
  v_need_t   numeric;   -- ROOM: her preset's water, in tons
  v_hold_t   numeric;
  v_res      jsonb;
  v_plan     jsonb;
  o          record;
  v_v        record;
  v_s        record;
  v_t0       timestamptz;
  v_ms       numeric;
  v_ok       text := '';
  v_was_on   boolean := public.npc_traders_on();
  v_routes_on boolean := public.standing_routes_on();
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION; ACLs unmoved; each hunk in its new body exactly once.
  for v_fn in select fn from defs_before_0150 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0150 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0150 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0150 where fn = v_fn) or v_def = v_back then
      raise exception '0150 self-assert FAIL: % is not its pre-image plus only 0150''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0150 where fn = v_fn) then
      raise exception '0150 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) ONE AUTHORITY: the top-up arithmetic lives in stores_topup alone (do_provision keeps no
  --     split of its own); the price of stores is still read in stores_cost alone (0142).
  if strpos(pg_get_functiondef('cmd.do_provision(uuid, jsonb)'::regprocedure), 'r.hold * r.store_ratio') = 0
     or strpos(pg_get_functiondef('cmd.do_provision(uuid, jsonb)'::regprocedure), 'v_target - r.water_t - r.food_t') > 0
     or strpos(pg_get_functiondef('cmd.do_provision(uuid, jsonb)'::regprocedure), 'public.stores_topup(') = 0 then
    raise exception '0150 self-assert FAIL: cmd.do_provision does not take its top-up from public.stores_topup alone';
  end if;
  if (select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname)
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage')
         and (p.prosrc like '%provision_water_price%' or p.prosrc like '%provision_food_price%'))
     is distinct from array['public.stores_cost'] then
    raise exception '0150 self-assert FAIL: the price of stores is read outside stores_cost';
  end if;

  -- (c) THE WALL: server-only, no new entry point, no client write, no new knob.
  if has_function_privilege('authenticated', 'public.stores_topup(numeric, numeric, numeric, numeric, numeric, numeric)', 'execute')
     or has_function_privilege('anon', 'public.stores_topup(numeric, numeric, numeric, numeric, numeric, numeric)', 'execute')
     or has_function_privilege('authenticated', 'public.sail_refused_days(uuid)', 'execute')
     or has_function_privilege('anon', 'public.sail_refused_days(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.npc_casks_blocked(uuid, uuid, numeric, numeric)', 'execute')
     or has_function_privilege('anon', 'public.npc_casks_blocked(uuid, uuid, numeric, numeric)', 'execute') then
    raise exception '0150 self-assert FAIL: a new reading is client-reachable';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0150)
     or (select count(*) from public.world_config) <> (select knobs from before_0150)
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0150 self-assert FAIL: the registry, the knobs, the grant wall or the read wall moved';
  end if;

  -- (d) THE TOP-UP OVER EVERY CREWED HULL IN THE WORLD, both modes, read-only: where water and food
  --     are in step it adds what the old split added (to the ton, 0.002 for the two roundings);
  --     anywhere it never leaves her fewer days than the old split did. And it never passes the hold.
  for v_s in
    select s.id, s.crew::numeric as crew, s.water_t, s.food_t, s.store_ratio,
           public.ship_hold_capacity(s.id) as hold, public.ship_cargo_tuns(s.id) as cargo_t, m.days
      from public.ships s cross join (values (30::numeric), (null::numeric)) m(days)
     where s.crew > 0
  loop
    select * into v_v from public.stores_topup(v_s.crew, v_s.water_t, v_s.food_t, v_s.hold - v_s.cargo_t,
                                               v_s.days, v_s.hold * v_s.store_ratio);
    -- the old split, verbatim
    v_qty := greatest(0, least(v_s.hold - v_s.cargo_t,
                               coalesce(v_s.crew * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')) * v_s.days,
                                        v_s.hold * v_s.store_ratio))
                         - v_s.water_t - v_s.food_t);
    if v_s.water_t + v_s.food_t + v_v.water_t + v_v.food_t > greatest(v_s.hold - v_s.cargo_t, v_s.water_t + v_s.food_t) + 0.002 then
      raise exception '0150 self-assert FAIL: the top-up of ship % passes her hold (% + % + % + % > %)',
        v_s.id, v_s.water_t, v_s.food_t, v_v.water_t, v_v.food_t, v_s.hold - v_s.cargo_t;
    end if;
    if least((v_s.water_t + v_v.water_t) / (v_s.crew * public.wc_num('water_per_crew_day')),
             (v_s.food_t + v_v.food_t) / (v_s.crew * public.wc_num('food_per_crew_day'))) + 0.05
       < least((v_s.water_t + round(v_qty * public.wc_num('water_per_crew_day') / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3))
                 / (v_s.crew * public.wc_num('water_per_crew_day')),
               (v_s.food_t + round(v_qty * public.wc_num('food_per_crew_day') / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3))
                 / (v_s.crew * public.wc_num('food_per_crew_day'))) then
      raise exception '0150 self-assert FAIL: the top-up leaves ship % fewer days than the old split (mode %)', v_s.id, coalesce(v_s.days::text, 'FULL');
    end if;
    if abs(v_s.water_t / (v_s.crew * public.wc_num('water_per_crew_day')) - v_s.food_t / (v_s.crew * public.wc_num('food_per_crew_day'))) < 0.0001
       and (abs(v_v.water_t - round(v_qty * public.wc_num('water_per_crew_day') / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3)) > 0.002
            or abs(v_v.food_t - round(v_qty * public.wc_num('food_per_crew_day') / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3)) > 0.002) then
      raise exception '0150 self-assert FAIL: ship % with stores in step tops up % / % where the old split gave % (mode %)',
        v_s.id, v_v.water_t, v_v.food_t, v_qty, coalesce(v_s.days::text, 'FULL');
    end if;
  end loop;
  -- and on inputs of the probe's own (the world above may hold no hull in step): 20 hands, 5 days
  -- of both, a 1,000-ton room — DAYS 30 and FULL (450 t) add what the old split added.
  for v_s in select * from (values (30::numeric), (null::numeric)) m(days) loop
    v_qty := greatest(0, least(1000, coalesce(20 * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')) * v_s.days, 450))
                         - 20 * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')) * 5);
    select * into v_v from public.stores_topup(20, 20 * public.wc_num('water_per_crew_day') * 5,
                                               20 * public.wc_num('food_per_crew_day') * 5, 1000, v_s.days, 450);
    if abs(v_v.water_t - round(v_qty * public.wc_num('water_per_crew_day') / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3)) > 0.002
       or abs(v_v.food_t - round(v_qty * public.wc_num('food_per_crew_day') / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3)) > 0.002 then
      raise exception '0150 self-assert FAIL: 5 days of both stores top up to % / % where the old split gave % (mode %)',
        v_v.water_t, v_v.food_t, v_qty, coalesce(v_s.days::text, 'FULL');
    end if;
  end loop;
  -- and the case it exists for: water broached, 60 days of food, room enough. POSITIVE CONTROL: the
  -- old split reaches under 30 days; the top-up reaches 30 and buys no food.
  v_qty := greatest(0, least(1000, 20 * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')) * 30)
                       - 20 * public.wc_num('food_per_crew_day') * 60);
  if round(v_qty * public.wc_num('water_per_crew_day') / (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')), 3)
       / (20 * public.wc_num('water_per_crew_day')) >= 30 then
    raise exception '0150 self-assert FAIL: POSITIVE CONTROL — the old split already reaches 30 days on a broached cask';
  end if;
  select * into v_v from public.stores_topup(20, 0, 20 * public.wc_num('food_per_crew_day') * 60, 1000, 30, null);
  if v_v.days < 30 or v_v.food_t <> 0 then
    raise exception '0150 self-assert FAIL: a hull with no water and 60 days of food tops up to % days (% / %)', v_v.days, v_v.water_t, v_v.food_t;
  end if;

  -- (e) THE PROBES, on a merchant of the probe's own, rolled back. Each scenario is a stuck lap
  --     of one cause, made the way prod's are made (her stop rendered, the SAIL refused at the head
  --     of her queue, her cursor gone on); ONE public.npc_tend_route — one merchant's step of the
  --     hourly pass — must put her to sea, and her arrival at her stop 0 must close the lap.
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_fnc from public.ports where code = 'FNC';
  select jsonb_build_array(jsonb_build_array(ra.roadstead_lat, ra.roadstead_lon),
                           jsonb_build_array(rb.roadstead_lat, rb.roadstead_lon))
    into v_leg from public.sea_reaches ra, public.sea_reaches rb
   where ra.port_id = v_lis and rb.port_id = v_fnc;
  v_back_c := jsonb_build_array(v_leg->1, v_leg->0);
  begin
    update public.world_config set value = 'true'::jsonb where key = 'npc_traders_enabled';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    perform set_config('byeharu.npc_upkeep_deadline', '', true);
    if not public.npc_traders_on() then
      raise exception '0150 self-assert FAIL: the probe could not light the merchants';
    end if;
    v_m := public.npc_found(jsonb_build_object(
      'company', 'Casa do Casco Seco', 'alt_company', 'Casa da Pipa', 'nation', 'PRT', 'ink', 'prt',
      'master', 'Capitao Sedento',
      'blurb', 'A probe company founded so that a stuck lap can be seen to close.',
      'capital', 40000, 'patience', 0.20, 'wares', '[]'::jsonb, 'roster_ord', 9152,
      'skills', '{}'::jsonb,
      'fleets', jsonb_build_array(jsonb_build_object(
        'name', 'Sedenta', 'roster_ord', 9152, 'days', 12,
        'ships', jsonb_build_array(jsonb_build_object('class', 'nau', 'name', 'Sedenta')),
        'officers', '[]'::jsonb,
        'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                   jsonb_build_object('port', 'FNC', 'course', v_back_c)),
        'alt_stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                       jsonb_build_object('port', 'FNC', 'course', v_back_c))))));
    select nf.fleet_id, nf.route_id into v_mfleet, v_route from public.npc_fleets nf
     where nf.player_id = v_m order by nf.roster_ord limit 1;   -- the probe founded exactly one
    select f.provision_preset_id into v_preset from public.fleets f where f.id = v_mfleet;
    if v_mfleet is null or v_route is null or v_preset is null then
      raise exception '0150 self-assert FAIL: the probe merchant was founded without a fleet, a route or a preset';
    end if;

    for v_s in select * from (values (1, 'PRESET'), (2, 'ROOM'), (3, 'CASKS')) c(k, cause) order by k loop
      begin
        perform pg_temp.stuck_0150(v_m, v_route, v_mfleet, v_fnc, 900151 + v_s.k);
        perform pg_temp.purse_0150(v_m, 40000);
        -- her lines, as the planner writes them mid-lap (no loop choice): this raises her preset to
        -- her loop's days, so each scenario then breaks one thing.
        v_plan := public.npc_plan(now(), v_route);
        if (v_plan->>'planned')::int is distinct from 1 or (v_plan->>'failed')::int is distinct from 0 then
          raise exception '0150 self-assert FAIL: the mid-lap plan answered %', v_plan;
        end if;
        if v_s.cause = 'PRESET' then
          -- the preset 0142 never re-measured: 1 day, and no prior clear on record (the count is 1).
          update public.provision_presets set days = 1 where id = v_preset;
        elsif v_s.cause = 'ROOM' then
          -- a parcel bought far above every bid that her casks cannot be stowed beside: her one hull
          -- holds the parcel (her preset's water, in tons), food to spare (a broached cask's leftover,
          -- as on prod) and room for only half her preset's water. The parcel is of a good the FNC
          -- quay takes WHOLE today (its quote and her daily cap), first by code, so the cut-loss
          -- clears the room in one sale. The probe owns all of it: which good a world's ids put
          -- first and how deep its quay is are the world's (CI's fresh chain drew a hold-full of a
          -- good FNC took 21 of, and she stayed blocked — a probe of the world, not of the fix).
          if (select count(*) from public.ships where fleet_id = v_mfleet) <> 1 then
            raise exception '0150 self-assert FAIL: ROOM — the probe fleet is not one hull';
          end if;
          select s.crew * public.wc_num('water_per_crew_day') * (select days from public.provision_presets where id = v_preset),
                 public.ship_hold_capacity(s.id)
            into v_need_t, v_hold_t
            from public.ships s where s.fleet_id = v_mfleet;
          select g.id, g.code, g.bulk, n.q into v_good, v_code, v_bulk, v_qty
            from public.port_goods pg join public.goods g on g.id = pg.good_id
           cross join lateral (select ceil(v_need_t / greatest(g.bulk, 0.001)) as q) n
           where pg.port_id = v_fnc and n.q * g.bulk <= v_need_t * 1.5
             and (select qs.units from world.quote(v_fnc, g.id, n.q, 'sell', null, null) qs) >= n.q
             and world.daily_cap_remaining(v_m, v_fnc, g.id) >= n.q
           order by g.code limit 1;
          if v_good is null then
            raise exception '0150 self-assert FAIL: ROOM — FNC takes no good whole in a parcel of % t', v_need_t;
          end if;
          perform public.fleet_load(v_mfleet, v_code, v_qty, 1000000);
          update public.ships s
             set water_t = 0,
                 food_t = round(greatest(0, v_hold_t - public.ship_cargo_tuns(s.id) - 0.5 * v_need_t), 3)
           where s.fleet_id = v_mfleet;
        else
          -- a cask broached at sea: no water, and food for twice her preset.
          update public.ships s
             set water_t = 0,
                 food_t = round(s.crew * public.wc_num('food_per_crew_day')
                                * 2 * (select days from public.provision_presets where id = v_preset), 3)
           where s.fleet_id = v_mfleet;
        end if;
        perform cmd.advance(v_mfleet, now());

        select * into o from public.orders where fleet_id = v_mfleet and status = 'failed' order by seq limit 1;
        if v_s.cause = 'CASKS' then
          -- 0150's top-up answers this one at the stop itself: no refusal, she is at sea.
          if o.id is not null or (select status from public.fleets where id = v_mfleet) <> 'SAILING' then
            raise exception '0150 self-assert FAIL: CASKS — the broached-cask merchant did not sail from her stop (head % %, fleet %)',
              o.verb, o.error_code, (select status from public.fleets where id = v_mfleet);
          end if;
        else
          -- POSITIVE CONTROL: the stuck shape — the SAIL refused E_ENDURANCE at the head, docked.
          if o.verb is distinct from 'SAIL' or o.error_code is distinct from 'E_ENDURANCE'
             or (select status from public.fleets where id = v_mfleet) <> 'DOCKED' then
            raise exception '0150 self-assert FAIL: % — the probe did not make a stuck lap (head % %, fleet %)',
              v_s.cause, o.verb, o.error_code, (select status from public.fleets where id = v_mfleet);
          end if;
          v_need := public.sail_refused_days(v_mfleet);
          if v_need <> ceil((o.error_figures->>'need')::numeric)::int + 1 then
            raise exception '0150 self-assert FAIL: sail_refused_days read % for a refusal needing %', v_need, o.error_figures;
          end if;
          if v_s.cause = 'ROOM' and not public.npc_casks_blocked(v_mfleet, v_fnc,
               (select r.nm from voyage.reach_from(v_fnc) r where r.port_id = v_lis), voyage.fleet_speed(v_mfleet)) then
            raise exception '0150 self-assert FAIL: ROOM — a full hold with her SAIL refused is not read as blocked';
          end if;
          if exists (select 1 from public.events ev where ev.kind = 'NPC_CLEARED' and ev.payload->>'route_id' = v_route::text) then
            raise exception '0150 self-assert FAIL: % — the probe route already carries a clear', v_s.cause;
          end if;

          -- ONE STEP OF THE HOUR'S PASS.
          v_t0 := clock_timestamp();
          v_res := public.npc_tend_route(now(), v_mfleet, v_route, 1);
          v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
          raise notice '0150 % : one npc_tend_route step % ms', v_s.cause, round(v_ms);
          if (v_res->>'cleared')::int is distinct from 1 or (v_res->>'failed')::int is distinct from 0 then
            raise exception '0150 self-assert FAIL: % — the step answered %', v_s.cause, v_res;
          end if;
          if (select status from public.fleets where id = v_mfleet) <> 'SAILING'
             or exists (select 1 from public.orders where fleet_id = v_mfleet and status = 'failed') then
            raise exception '0150 self-assert FAIL: % — one step did not put her to sea (fleet %, orders %)', v_s.cause,
              (select status from public.fleets where id = v_mfleet),
              (select string_agg(seq || ' ' || status || ' ' || coalesce(error_code, '') || ' ' || raw_text, ' | ' order by seq)
                 from public.orders where fleet_id = v_mfleet and issued_at >= now());
          end if;
          if v_s.cause = 'PRESET' and (select days from public.provision_presets where id = v_preset) < v_need then
            raise exception '0150 self-assert FAIL: PRESET — her preset reads % after the step, the refusal needed %',
              (select days from public.provision_presets where id = v_preset), v_need;
          end if;
          if v_s.cause = 'ROOM'
             and (select coalesce(sum((s.cargo->>v_code)::numeric), 0) from public.ships s where s.fleet_id = v_mfleet) > 0 then
            raise exception '0150 self-assert FAIL: ROOM — she sailed and her % was not all let go', v_code;
          end if;
        end if;

        -- HER LAP CLOSES when she reaches her stop 0: the voyage settled at its eta, the executor
        -- runs her stop.
        select * into v_v from public.voyages where fleet_id = v_mfleet and status = 'SAILING' order by departed_at desc limit 1;
        if v_v.id is null or v_v.dest_port_id <> v_lis then
          raise exception '0150 self-assert FAIL: % — her voyage is not bound for her stop 0 (%)', v_s.cause, v_v.dest_port_id;
        end if;
        -- The sea may delay her (a STORM or a foul wind moves the eta past the instant first asked —
        -- voyage.recompute_eta; which days draw what is the voyage's own), so she is settled at her
        -- CURRENT eta until she is in: a voyage's delays are bounded, and twelve settles is far past them.
        v_n := 0;
        while v_v.status = 'SAILING' and v_n < 12 loop
          perform voyage.settle(v_mfleet, v_v.eta + interval '1 minute');
          select * into v_v from public.voyages where id = v_v.id;
          v_n := v_n + 1;
        end loop;
        if v_v.status = 'SAILING' then
          raise exception '0150 self-assert FAIL: % — her voyage is still at sea after % settles (eta %)', v_s.cause, v_n, v_v.eta;
        end if;
        perform cmd.advance(v_mfleet, v_v.eta + interval '1 minute');
        if (select closed_at from public.standing_route_laps where route_id = v_route and lap_no = 900151 + v_s.k) is null then
          raise exception '0150 self-assert FAIL: % — she reached her stop 0 and the lap did not close (fleet % at %)', v_s.cause,
            (select status from public.fleets where id = v_mfleet),
            (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_mfleet);
        end if;
        v_ok := v_ok || format('%s: put to sea in one step and closed her lap at LIS; ', v_s.cause);
        raise exception 'ROLLBACK_0150_ONE';
      exception when others then
        if sqlerrm <> 'ROLLBACK_0150_ONE' then raise; end if;
      end;
    end loop;

    raise exception 'ROLLBACK_0150';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0150' then raise; end if;
  end;
  if exists (select 1 from public.npc_houses where roster_ord = 9152)
     or exists (select 1 from public.standing_route_laps where lap_no between 900150 and 900154)
     or public.npc_traders_on() is distinct from v_was_on or public.standing_routes_on() is distinct from v_routes_on then
    raise exception '0150 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0150 self-assert ok: A STUCK LAP IS ANSWERED ON THE FIRST CLEAR. npc_tend_route, npc_plan, npc_leg_lines and do_provision reverse to their pre-images hunk by hunk, ACLs unmoved; the top-up lives in stores_topup alone and matches the old split on every crewed hull whose stores are in step, never fewer days on any; server-only, no new entry point, no new knob, no client write. Probes: %Rolled back.', v_ok;
end $$;

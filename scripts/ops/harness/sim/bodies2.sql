===== cmd.advance(uuid,timestamp with time zone) [v]
CREATE OR REPLACE FUNCTION cmd.advance(p_fleet uuid, p_now timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  f      public.fleets%rowtype;
  o      public.orders%rowtype;
  v_res  jsonb;
  v_ran  int := 0;
  guard  int := 0;
  v_refilled boolean := false;   -- 0092: a standing route refills at most ONCE per call
begin
  loop
    guard := guard + 1;
    exit when guard > 64;   -- the queue is capped at 12; this is a runaway guard, not a policy.

    -- §F.3: "on a failure it HALTS — it never skips." The rule was only enforced INSIDE one call:
    -- the loop stopped at a failure, and then the next arrival called advance() again, found the
    -- failed order was no longer `pending`, and ran the one behind it — which is skipping, on a
    -- delay. Found by a probe whose queue read [1:failed E_HOLD_FULL 2:done 3:pending 4:pending].
    --
    -- So a failed order now blocks the fleet until the player clears it. That is the whole point
    -- of the rule: an order that could not be carried out is a decision to bring back to the
    -- captain, not a line to step over while nobody is watching. CLEAR (and CANCEL of that order)
    -- releases it, so this can never become a deadlock.
    if exists (select 1 from public.orders
                where fleet_id = p_fleet and status = 'failed') then
      exit;
    end if;

    select * into f from public.fleets where id = p_fleet for update;
    if f.status = 'REPAIRING' then
      if f.busy_until is not null and f.busy_until <= p_now then
        update public.fleets set status = 'DOCKED', busy_until = null, version = version + 1
         where id = p_fleet;
        perform public.emit_event(f.player_id, 'REPAIRED', jsonb_build_object('fleet', f.name));
        continue;
      end if;
      exit;   -- still in the yard
    end if;
    -- 0047: a fleet ANCHORED at a point of open water runs her queue too — that is how a queued
    -- onward SAIL departs from a pinpointed spot. Every verb that needs a quay refuses her itself
    -- (E_NOT_DOCKED), so nothing a chandler sells can be conjured at sea by this line.
    exit when f.status not in ('DOCKED', 'ANCHORED');   -- SAILING / ADRIFT / UNABLE_TO_SAIL: nothing can execute

    select * into o from public.orders
     where fleet_id = p_fleet and status = 'pending' order by seq limit 1;
    -- 0092 HUNK A: the queue ran dry in port. If a standing route stands on this fleet it
    -- writes the next stop's orders ONCE (cmd.run_standing_route), and they run like any other.
    if o.id is null then
      exit when v_refilled;
      v_refilled := true;
      exit when coalesce(cmd.run_standing_route(p_fleet, p_now), 0) = 0;
      continue;
    end if;

    v_res := cmd.execute_order(o.id);
    v_ran := v_ran + 1;
    -- THE HALT RULE (§F.3): stop at the first failure. Do NOT skip to the next order.
    -- 0092 HUNK B (D1): a ROUTE's refused trade line is stepped over and written on the lap;
    -- a route's refused SAIL — and every ordinary order — halts the fleet exactly as before.
    if not coalesce((v_res->>'ok')::boolean, false) then
      exit when o.route_lap_id is null or o.verb = 'SAIL' or not public.standing_routes_on();   -- 0093: dark = the ordinary halt
      update public.orders set status = 'skipped' where id = o.id;
      perform cmd.standing_route_note_skip(o.id);
    end if;
  end loop;
  return v_ran;
end $function$

===== world.affinity_at(boolean,double precision,numeric,numeric,numeric,numeric,numeric) [i]
CREATE OR REPLACE FUNCTION world.affinity_at(p_is_producer boolean, p_nearest_nm double precision, p_producer numeric, p_home numeric, p_span numeric, p_reach_nm numeric, p_curve numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  select case
           when p_is_producer then p_producer
           else least(3.000, greatest(0.250, round((
             p_home
             + p_span * power(
                 least(1.0, coalesce(p_nearest_nm, p_reach_nm::double precision) / p_reach_nm),
                 p_curve)
           )::numeric, 3)))
         end
$function$

===== crew_wages(integer,boolean) [s]
CREATE OR REPLACE FUNCTION public.crew_wages(p_crew integer, p_short boolean)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_crew is null or p_crew < 0 then
    raise exception 'crew_wages: a crew count is zero or more (got %)', p_crew;
  end if;
  return round(p_crew * public.wc_num('wage_per_crew_day')
               * (case when p_short then public.wc_num('short_rations_wage_mult') else 1 end))::bigint;
end $function$

===== cmd.do_sail(uuid,jsonb) [v]
CREATE OR REPLACE FUNCTION cmd.do_sail(p_fleet uuid, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- Supersedes 0019's leg-graph body whole. The client PROPOSES a course (args.path, attached by
-- cmd.issue's p_path); the server VERIFIES it against its own raster and MEASURES it itself —
-- verification is the authoritative act, and no client number is ever believed. With no course
-- attached, the straight line is tried — free, and correct exactly when it verifies — otherwise
-- the order is refused E_NO_COURSE rather than guessed at.
declare
  f         public.fleets%rowtype;
  v_dest    uuid := nullif(p_args->>'dest', '')::uuid;
  v_point   jsonb := p_args->'dest_point';
  v_course  jsonb := p_args->'path';
  v_plotted boolean := coalesce(jsonb_typeof(p_args->'path') = 'array', false);
  v_olat numeric; v_olon numeric; v_head numeric;
  v_dlat numeric; v_dlon numeric; v_tail numeric;
  v_ref    text;
  v_gate   jsonb;
  v_nm     numeric;
  v_segs   jsonb;
  v_speed  numeric;
  v_voyage uuid;
begin
  select * into f from public.fleets where id = p_fleet;

  -- the gates that need no distance, first (status, crew, flagship, and the berth facts)
  v_gate := voyage.sail_refusal(p_fleet, v_dest, v_point, 0);
  if v_gate is not null then
    perform cmd.refuse(v_gate);
  end if;

  -- where she lies: a quay, or her own anchor. The approach allowance is the MEASURED snap of
  -- the place plus 25 nm slack — the same rule (snap + one cell) the client's straightener
  -- applies, held slightly looser here so a course the client passed cannot be refused for its
  -- own approach.
  if f.port_id is not null then
    -- 0076 THE ROADSTEAD: she does not put to sea from the quay. Her course begins at the
    -- one point of open water this port is reached from — the same point the chart draws the
    -- dotted helper line to, served on world.snapshot().ports[].roadstead, so the line drawn,
    -- the course proposed and the endpoint verified are one answer and cannot drift.
    select sr.roadstead_lat, sr.roadstead_lon into v_olat, v_olon
      from public.sea_reaches sr where sr.port_id = f.port_id;
    -- 0076: a FLAT 25 nm, not the snap plus 25. The snap WAS the land-crossing exemption
    -- that let the straightener cut the coast; ending the course at the roads makes it
    -- unnecessary rather than merely smaller. 25 is not a new knob: it is the number already
    -- in this line, and the smallest one here that clears the 21.21 nm of sampling slack the
    -- client's own straightener spends at every path end (one cell diagonal,
    -- src/lib/sea/pathfind.ts:330), so a course the client passed cannot be refused for its
    -- own approach — the failure 0047:195-198 records finding the expensive way.
    v_head := 25;
  else
    -- her own position: the approach is MEASURED, not guessed — a fleet minutes off a river
    -- quay still stands inside that port's approach, where her verified course crosses land
    -- cells, and a flat allowance refused her own turn as E_LAND (the acceptance drive).
    v_olat := f.lat; v_olon := f.lon;
    v_head := voyage.water_snap_nm(v_olat, v_olon) + 25;
  end if;

  -- where she is bound
  if v_dest is not null then
    if v_dest = f.port_id then
      raise exception 'E_SAME_DEST: % already lies there', f.name using errcode = 'P0001';
    end if;
    -- 0076 THE ROADSTEAD: she is bound for the roads, not the quay. Every port has a
    -- sea_reaches row (asserted in this file before anything relies on it), so a null here
    -- still means "no such port" and the refusal below is unchanged. voyage.settle then docks
    -- her at dest_port_id on the ETA exactly as it has since 0007 — which is the whole of the
    -- owner's "when the ship arrive at that point, consider it as the ship have landed".
    select sr.roadstead_lat, sr.roadstead_lon into v_dlat, v_dlon
      from public.sea_reaches sr where sr.port_id = v_dest;
    if v_dlat is null then
      raise exception 'E_NO_SUCH_PORT: there is no such port' using errcode = 'P0001';
    end if;
    -- 0076: the flat 25 nm again, for the reason written on the head allowance above.
    v_tail := 25;
  elsif v_point is not null then
    v_dlat := (v_point->>'lat')::numeric; v_dlon := (v_point->>'lon')::numeric;
    if v_dlat is null or v_dlon is null or abs(v_dlat) > 90 or abs(v_dlon) > 180 then
      raise exception 'E_BAD_PATH: that is not a point on the sphere' using errcode = 'P0001';
    end if;
    v_tail := voyage.water_snap_nm(v_dlat, v_dlon) + 25;
    if voyage.gc_distance_nm(v_olat::float8, v_olon::float8, v_dlat::float8, v_dlon::float8)
         <= public.wc_num('course_join_nm') then
      raise exception 'E_SAME_DEST: % already lies there', f.name using errcode = 'P0001';
    end if;
  else
    raise exception 'E_PARSE: SAIL needs a destination - a port, or a lat,lon point of open sea' using errcode = 'P0001';
  end if;

  -- the course: proposed, or the straight line when none was
  if not v_plotted then
    v_course := jsonb_build_array(jsonb_build_array(v_olat, v_olon), jsonb_build_array(v_dlat, v_dlon));
  end if;
  v_ref := voyage.path_refusal(v_course, v_olat, v_olon, v_dlat, v_dlon,
                               public.wc_num('course_join_nm'), v_head, v_tail);
  if v_ref is not null then
    if not v_plotted and v_ref like 'E_LAND:%' then
      raise exception 'E_NO_COURSE: the straight way is not open water - the chart plots the course at the moment of ordering' using errcode = 'P0001';
    end if;
    raise exception '%', v_ref using errcode = 'P0001';
  end if;

  -- THE MEASURE - the server's own, never the client's
  v_segs := voyage.segments_from_course(v_course);
  select sum((s->>'nm')::numeric) into v_nm from jsonb_array_elements(v_segs) s;

  v_gate := voyage.sail_refusal(p_fleet, v_dest, v_point, v_nm);
  if v_gate is not null then
    perform cmd.refuse(v_gate);
  end if;

  v_speed := voyage.fleet_speed(p_fleet);
  v_voyage := voyage.depart(p_fleet, v_segs, f.port_id, v_dest);
  perform public.emit_event(f.player_id, 'DEPARTED', jsonb_build_object(
    'fleet', f.name, 'voyage_id', v_voyage, 'total_nm', v_nm,
    'points', jsonb_array_length(v_course),
    'dest', coalesce((select code from public.ports where id = v_dest),
                     format('%s,%s', round(v_dlat, 2), round(v_dlon, 2))),
    'eta', (select eta from public.voyages where id = v_voyage)));
  return jsonb_build_object('voyage_id', v_voyage, 'total_nm', v_nm,
                            'voyage_days', round((v_nm / v_speed) / 24, 2));
end $function$

===== world.haul_rows() [s]
CREATE OR REPLACE FUNCTION world.haul_rows()
 RETURNS TABLE(port_id uuid, good_id uuid, haul_nm numeric, haul numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 0173: THE DERIVATION, every market row at once: the sailing distance (public.sea_reaches, the water
  -- raster's nm) from the nearest city whose roster offers the good (public.port_offered_goods — the
  -- authority world.affinity_for reads), 0 at a city that offers it, and world.haul_at over the three
  -- knobs. port_goods.haul_nm / haul are filled from this and the world guard compares them with it.
  with k as materialized (
    select public.wc_num('haul_max') as mx, public.wc_num('haul_reach_nm') as reach, public.wc_num('haul_curve') as c
  ), offered as materialized (
    select p.id as port_id, o.good_id from public.ports p cross join lateral public.port_offered_goods(p.id) o
  ), near as materialized (
    select s.good_id, e.key as code, min(e.value::numeric) as nm
      from offered s join public.sea_reaches sr on sr.port_id = s.port_id
     cross join lateral jsonb_each_text(sr.reaches) e
     group by 1, 2
  )
  select pg.port_id, pg.good_id, d.nm, world.haul_at(d.nm, k.mx, k.reach, k.c)
    from public.port_goods pg
    join public.ports p on p.id = pg.port_id
   cross join k
    left join offered o on o.port_id = pg.port_id and o.good_id = pg.good_id
    left join near n on n.good_id = pg.good_id and n.code = p.code
   cross join lateral (select case when o.port_id is not null then 0::numeric else round(n.nm, 1) end as nm) d
$function$

===== npc_buy_budget(uuid) [s]
CREATE OR REPLACE FUNCTION public.npc_buy_budget(p_fleet uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 0129: what a merchant's parcels at one stop may cost — her working capital (purse + cargo aboard
  -- at cost: her SELLs run first and never below cost) less the npc_buy_purse_pct keep-back that
  -- pays the stop's stores and repairs. 0 for no such fleet.
  select coalesce((select greatest(0, floor((pl.ducats + public.fleet_stock_at_cost(f.id))
                                             * public.wc_num('npc_buy_purse_pct') / 100))
                     from public.fleets f join public.players pl on pl.id = f.player_id
                    where f.id = p_fleet), 0)
$function$

===== npc_found(jsonb) [v]
CREATE OR REPLACE FUNCTION public.npc_found(p_spec jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- ONE merchant company, founded through the authorities a player's company is made by. The spec
-- (0098's generated literal) names: company (+ alt_company), nation, ink, master, blurb, capital,
-- patience, wares, skills {code: level}, roster_ord, and fleets [{name, roster_ord, home, days,
-- ships [{class, name}] (the first is her flagship), officers [codes], stops [{port, course}],
-- alt_stops}]. Purse after founding = capital: the house is founded with capital + every officer's
-- wage + every level's tuition, and those are then PAID through the same credit calls the player
-- verbs make. The ships are endowed, as every player's Gaivota is (0004:308). The route is saved
-- with its stops, courses, crew_up, repair at stop 0 and the merchant pace — and NO lines, and is
-- NOT assigned (assigning sails): npc_tend assigns it when the switch is on.
-- This body inserts into no table but npc_houses and npc_fleets (asserted).
declare
  v_name    text;
  v_player  uuid;
  v_fleet   uuid;
  v_route   uuid;
  v_preset  uuid;
  v_fl      jsonb;
  v_sh      jsonb;
  v_off     text;
  v_stops   jsonb;
  v_st      jsonb;
  v_res     jsonb;
  v_wages   bigint := 0;
  v_tuition bigint := 0;
  v_skill   record;
  v_lvl     int;
  v_k       int;
  v_i       int;
  v_home    text;
begin
  -- THE NAME: the first spelling that is free, said which; both taken is a raise, never silence.
  v_name := p_spec->>'company';
  if exists (select 1 from public.players where company_name = v_name) then
    v_name := p_spec->>'alt_company';
    if v_name is null or exists (select 1 from public.players where company_name = v_name) then
      raise exception 'E_NAME_TAKEN: both spellings of "%" are taken', p_spec->>'company' using errcode = 'P0001';
    end if;
    raise notice 'npc_found: "%" is taken; founded as "%"', p_spec->>'company', v_name;
  end if;

  select coalesce(sum(o.wage_ducats), 0) into v_wages
    from public.officers o
   where o.code in (select jsonb_array_elements_text(f->'officers') from jsonb_array_elements(p_spec->'fleets') f);
  for v_skill in select key as code, value::text::int as level from jsonb_each(coalesce(p_spec->'skills', '{}'::jsonb)) loop
    v_tuition := v_tuition + public.wc_int('skill_study_base_cost') * (v_skill.level * (v_skill.level + 1) / 2);
  end loop;

  v_fl := p_spec->'fleets'->0;
  v_home := v_fl->'stops'->0->>'port';
  -- 0167 (S18): every hull she is founded with is her country's line hull for the roster's class
  -- (public.npc_hull_for at her house's home — the one rule).
  v_player := public.new_house(null, v_name, p_spec->>'nation', v_home, v_fl->>'name',
                               public.npc_hull_for(v_fl->'ships'->0->>'class', (select id from public.ports where code = v_home)),
                               v_fl->'ships'->0->>'name',
                               (p_spec->>'capital')::bigint + v_wages + v_tuition, true);

  insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience, wares)
  values (v_player, (p_spec->>'roster_ord')::int, p_spec->>'ink', p_spec->>'blurb', p_spec->>'master',
          (select id from public.ports where code = v_home), (p_spec->>'capital')::bigint,
          (p_spec->>'patience')::numeric,
          coalesce((select array_agg(x) from jsonb_array_elements_text(p_spec->'wares') x), '{}'));

  -- SKILLS: the company's levels, paid level by level through the academy's core.
  for v_skill in select key as code, value::text::int as level from jsonb_each(coalesce(p_spec->'skills', '{}'::jsonb)) loop
    for v_lvl in 1 .. v_skill.level loop
      v_res := public.raise_skill(v_player, v_skill.code, v_home);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception 'npc_found: % could not study %: %', v_name, v_skill.code, v_res;
      end if;
    end loop;
  end loop;

  for v_k in 0 .. jsonb_array_length(p_spec->'fleets') - 1 loop
    v_fl := p_spec->'fleets'->v_k;
    if v_k = 0 then
      select id into v_fleet from public.fleets where player_id = v_player;
    else
      v_fleet := public.form_fleet(v_player, v_fl->>'name',
                                   (select id from public.ports where code = v_fl->'stops'->0->>'port'));
      perform public.commission_ship(v_player, v_fleet,
        public.npc_hull_for(v_fl->'ships'->0->>'class', (select id from public.ports where code = v_home)),   -- 0167
        v_fl->'ships'->0->>'name', true, true);
    end if;
    for v_i in 1 .. jsonb_array_length(v_fl->'ships') - 1 loop
      v_sh := v_fl->'ships'->v_i;
      perform public.commission_ship(v_player, v_fleet,
        public.npc_hull_for(v_sh->>'class', (select id from public.ports where code = v_home)),   -- 0167
        v_sh->>'name', false, true);
    end loop;
    -- 0126: HER GEAR, endowed as her hulls are — the pattern for this fleet, through the one core.
    perform public.npc_fit_loadout(s.id) from public.ships s where s.fleet_id = v_fleet order by s.is_flagship desc, s.name;
    -- 0127: HER HULLS' LEVEL, FIXED ONCE from the company's skills (public.npc_fix_level); never moved.
    perform public.npc_fix_level(v_player);

    -- OFFICERS: signed and posted to this fleet, paid through the one mover.
    for v_off in select jsonb_array_elements_text(coalesce(v_fl->'officers', '[]'::jsonb)) loop
      v_res := public.sign_officer(v_player, v_off, v_fleet);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception 'npc_found: % could not sign %: %', v_name, v_off, v_res;
      end if;
    end loop;

    -- SUPPLIES: the fleet's standing order, through the preset cores.
    v_res := cmd.provision_preset_save_for(v_player, null, left(v_fl->>'name', 24), (v_fl->>'days')::int);
    v_preset := (v_res->>'id')::uuid;
    if v_preset is null then
      raise exception 'npc_found: % could not keep supplies: %', v_fl->>'name', v_res;
    end if;
    perform cmd.provision_preset_apply_for(v_player, v_fleet, v_preset);

    -- THE ROUTE: stops and courses, crew_up everywhere, repair at home, the merchant pace, no lines.
    v_stops := '[]'::jsonb;
    for v_i in 0 .. jsonb_array_length(v_fl->'stops') - 1 loop
      v_st := v_fl->'stops'->v_i;
      v_stops := v_stops || jsonb_build_object('port', v_st->>'port', 'course', v_st->'course',
                                               'repair', v_i = 0, 'crew_up', true, 'lines', '[]'::jsonb);
    end loop;
    v_res := cmd.standing_route_save_for(v_player, null, left(v_fl->>'name', 24), v_stops, 0, null,
                                         public.wc_int('npc_laps_per_game_day'));
    v_route := (v_res->>'id')::uuid;
    if v_route is null then
      raise exception 'npc_found: the route of % was refused: %', v_fl->>'name', v_res;
    end if;

    insert into public.npc_fleets (fleet_id, player_id, route_id, roster_ord, alt_loop)
    values (v_fleet, v_player, v_route, (v_fl->>'roster_ord')::int, v_fl->'alt_stops');
  end loop;

  -- 0167 (S18): HER HULL SKILLS, FIXED ONCE from the hulls she sails — endowed and paid, so the purse
  -- check below still reads her capital. After npc_fix_level, so her hulls' level is the live skills'.
  perform public.npc_fix_hull_skills(v_player);

  if (select ducats from public.players where id = v_player) <> (p_spec->>'capital')::bigint then
    raise exception 'npc_found: % ends with % in its purse, not its capital %', v_name,
      (select ducats from public.players where id = v_player), p_spec->>'capital';
  end if;
  return v_player;
end $function$

===== npc_tend(timestamp with time zone,uuid) [v]
CREATE OR REPLACE FUNCTION public.npc_tend(p_now timestamp with time zone DEFAULT now(), p_route uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- What the world does for a merchant that a player would do by hand — through the route cores,
-- cmd.clear_for + cmd.advance, and public.credit; nothing else. Per route, fleet then route locked
-- NOWAIT inside its own subtransaction (a busy route is skipped, counted, never waited for):
--   switch OFF, or beyond npc_fleet_max in roster order -> paused 'dark' (fleets at sea finish
--     their leg and lie in port).
--   ADRIFT / UNABLE_TO_SAIL -> counted and left (0115: never parked; there is no RECALL or salvage
--     verb for anybody, so the executor waits for her).
--   not started -> planned, then assigned where she lies (assigning starts the loop).
--   paused dark/losing/reserve/edited/laid_up -> planned, then resumed, at once — 0181: unless the
--     plan lays her up again (nothing on her loops pays: she waits); whether THIS call re-planned her is read off the
--     plan's receipt, not off updated_at (the save bumps it). error -> the same after 6 h (the
--     pause is dated by updated_at). off_route -> re-assigned if she lies at a stop; otherwise
--     reported.
--   a FAILED order at the head of her queue (the halt law) -> cmd.clear_for, then cmd.advance —
--     COUNTED: the third clear with no lap closed between re-plans her lines first (0115).
-- Then per company: purse below capital × npc_purse_floor_pct -> refounded (NPC_REFOUND through
-- 0137: the steps live in their own functions — public.npc_tend_roster (the walk),
-- public.npc_tend_route (one merchant), public.npc_tend_houses (the companies), public.npc_tend_sum (the
-- receipt). This is their one-transaction composition; the hourly public.tick_reconcile composes the
-- same steps one transaction each.
declare
  v_on  boolean := public.npc_traders_on();
  r     record;
  v_acc jsonb := '{}'::jsonb;
begin
  for r in select * from public.npc_tend_roster() loop
    continue when p_route is not null and r.route_id <> p_route;
    v_acc := public.npc_tend_sum(v_acc, public.npc_tend_route(p_now, r.fleet_id, r.route_id, r.k));
  end loop;
  if p_route is null then
    v_acc := public.npc_tend_sum(v_acc, public.npc_tend_houses(p_now));
  end if;
  return jsonb_build_object('enabled', v_on) || public.npc_tend_sum(v_acc, '{}'::jsonb);
end $function$

===== npc_tend_route(timestamp with time zone,uuid,uuid,bigint) [v]
CREATE OR REPLACE FUNCTION public.npc_tend_route(p_now timestamp with time zone, p_fleet uuid, p_route uuid, p_k bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0137: ONE merchant's upkeep — public.npc_tend's per-route body, moved verbatim (fleet then route
-- locked NOWAIT in its own subtransaction; a busy route is skipped and counted). Returns this
-- merchant's counts; public.npc_tend_sum adds them up. Called by npc_tend (one transaction) and by
-- the hourly public.tick_reconcile (one transaction PER MERCHANT, so the locks she takes are held
-- for her step and no longer).
declare
  v_on      boolean := public.npc_traders_on();
  v_max     int     := public.wc_int('npc_fleet_max');
  r         record;
  sr        public.standing_routes%rowtype;
  f         public.fleets%rowtype;
  fo        public.orders%rowtype;
  v_res     jsonb;
  v_clears  int;
  v_dark    int := 0;
  v_started int := 0;
  v_resumed int := 0;
  v_cleared int := 0;
  v_laid_n  int := 0;
  v_busy    int := 0;
  v_failed  int := 0;
  v_deferred int := 0;
  v_notes   jsonb := '[]'::jsonb;
  v_built   int := 0;   -- 0180 (d): hulls she laid down this hour
  v_waiting int := 0;   -- 0181: laid up in port, nothing on her loops paying
begin
  for r in select p_fleet as fleet_id, p_route as route_id, p_k as k loop   -- 0137: one row
    begin
      perform 1 from public.fleets where id = r.fleet_id for update nowait;
      select * into sr from public.standing_routes where id = r.route_id for update nowait;
      select * into f from public.fleets where id = r.fleet_id;

      if not v_on or r.k > v_max then
        if sr.fleet_id is not null and sr.paused_reason is distinct from 'dark' then
          perform cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'dark', 'The merchants keep to port.');
          v_dark := v_dark + 1;
        end if;
        continue;
      end if;

      -- 0152: A WRECK IN PORT IS TOWED (owner default, 2026-10-17) through public.tow_for — THE tow,
      -- the one a player presses — to the nearest harbour with a shipyard, and her REPAIR is queued
      -- there the way a player queues it (cmd.parse, cmd.enqueue, cmd.advance). Repaired off her
      -- loop, the off_route branch below chooses her loop afresh. A tow her fortune will not pay
      -- (E_TOW_FUNDS) is noted and she is counted below, as before.
      if f.status = 'UNABLE_TO_SAIL' and f.port_id is not null then
        begin
          v_res := public.tow_for(sr.player_id, r.fleet_id);
          v_res := v_res || jsonb_build_object('repair_queued', cmd.enqueue(sr.player_id,
                     jsonb_set(cmd.parse(sr.player_id, r.fleet_id, 'REPAIR'), '{fleet_id}', to_jsonb(r.fleet_id::text)),
                     'REPAIR', null, null)->'ok');
          perform cmd.advance(r.fleet_id, p_now);
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'towed', v_res->>'to',
                                                   'nm', v_res->'nm', 'fee', v_res->'fee',
                                                   'repair_queued', v_res->'repair_queued');
          continue;
        exception when others then
          if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'tow_refused', split_part(sqlerrm, ':', 1));
        end;
      end if;
      if f.status in ('ADRIFT', 'UNABLE_TO_SAIL') then
        -- 0115: NOT PARKED. No verb refloats a fleet that cannot sail — for anybody — so she is
        -- counted in the receipt and her route is left as it is; the executor waits for her.
        -- 0152: a wreck in port is towed above; what reaches here is ADRIFT, a wreck at sea, or a
        -- tow refused.
        v_laid_n := v_laid_n + 1;
        v_notes := v_notes || jsonb_build_object('route', sr.name, 'cannot_sail', f.status);
        continue;
      end if;

      -- A PAUSE THE WORLD MAY LIFT, and only when it may: dark/losing/reserve/edited at once;
      -- laid_up after npc_laid_up_hours; error after 6 h (updated_at dates the pause — the hourly
      -- plan skips error routes, so it cannot keep the date fresh). off_route re-assigns where she
      -- lies, if that is a stop. 'player' is never a merchant's.
      --
      -- updated_at DATES A PAUSE ONLY WHILE NOTHING HAS WRITTEN THE ROUTE SINCE. That holds for
      -- 'error' (the plan skips those) and it is what the ageing test below reads; it does NOT hold
      -- after the plan has saved — see the receipt test further down.
      if sr.paused_reason = 'off_route' then
        -- 0152: DOCKED OFF HER LOOP (towed to a shipyard her loop does not call at): her loop is
        -- chosen afresh from where she lies (public.npc_plan), and she is assigned there below.
        if f.status = 'DOCKED'
           and not exists (select 1 from public.standing_route_stops s where s.route_id = sr.id and s.port_id = f.port_id) then
          perform public.npc_plan(p_now, sr.id);
        end if;
        if f.status = 'DOCKED'
           and exists (select 1 from public.standing_route_stops s where s.route_id = sr.id and s.port_id = f.port_id) then
          v_res := cmd.standing_route_assign_for(sr.player_id, sr.id, r.fleet_id);
          v_resumed := v_resumed + 1;
        else
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'off_route', f.status);
        end if;
        continue;
      end if;
      if sr.paused_reason is not null
         and not (sr.paused_reason in ('dark', 'losing', 'reserve', 'edited', 'laid_up')   -- 0115: laid_up at once
                  or (sr.paused_reason = 'error' and sr.updated_at < p_now - interval '6 hours')) then
        continue;
      end if;

      -- 0114: THE BUDGET gates the dear work only — a plan and a start or a resume, and the halt
      -- law's release below. The dark and cannot-sail lay-ups above stay unconditional.
      if (sr.fleet_id is null or sr.paused_reason is not null) and public.npc_upkeep_spent() then
        v_deferred := v_deferred + 1;
        continue;
      end if;

      -- NOT STARTED, OR A PAUSE TO LIFT: plan first (the lines are the market's NOW), then start
      -- her where she lies, or resume her. The plan may lay her up (nothing pays): then she waits.
      if sr.fleet_id is null or sr.paused_reason is not null then
        if sr.paused_reason = 'error' then
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'resumed_after_error', true);
        end if;
        v_res := public.npc_plan(p_now, sr.id);
        select * into sr from public.standing_routes where id = r.route_id;
        -- DID THIS PLAN LAY HER UP? THE PLAN'S OWN RECEIPT SAYS SO — NEVER updated_at. The save
        -- door (cmd.standing_route_save_for) sets updated_at = now(), so after a SUCCESSFUL plan an
        -- `updated_at >= p_now - v_laid` test is always true at p_now = now(): it skipped every
        -- laid-up route it had just re-planned, the resume and start branches below were
        -- unreachable for that reason, and every merchant laid up for want of cargo stayed laid up
        -- for ever (found by the 2026-10-08 review; the ageing test above still gates WHEN she is
        -- re-planned at all). `planned` is this call's own count, and p_route pins the call to this
        -- one route, so planned = 0 means she was NOT re-planned — laid up again (nothing pays),
        -- busy, or failed — and she waits. Both arms are acceptable outcomes (NO_SPAGHETTI §7C):
        -- resume on fresh lines, or wait; she is never resumed on stale ones.
        --
        -- AND THAT HOLDS FOR EVERY PAUSE, not only 'laid_up' (the 2026-10-10 review): a dark or
        -- losing route whose plan RAISED would otherwise have been resumed on week-old lines, which
        -- is the very thing the sentence above claims never happens. Counted in the notes, so a
        -- route that is never planned is visible in the receipt rather than silently stuck.
        if coalesce((v_res->>'planned')::int, 0) = 0 then
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'not_planned', coalesce(sr.paused_reason, 'unstarted'));
          continue;
        end if;
        -- 0181: SHE WAITS IN PORT. The plan priced every loop on offer from where she lies and none
        -- pays, so it laid her up (or kept her laid up): she is not resumed; the next tend asks again.
        if coalesce((v_res->>'waiting')::int, 0) > 0 then
          v_waiting := v_waiting + 1;
          continue;
        end if;
        if sr.fleet_id is null then
          if f.status = 'DOCKED' then
            v_res := cmd.standing_route_assign_for(sr.player_id, sr.id, r.fleet_id);
            if coalesce((v_res->>'ok')::boolean, false) then
              v_started := v_started + 1;
            else
              v_notes := v_notes || jsonb_build_object('route', sr.name, 'start', v_res->>'error_code');
            end if;
          end if;
        elsif sr.paused_reason is not null then
          v_res := cmd.standing_route_pause_for(sr.player_id, sr.id, false);
          v_resumed := v_resumed + 1;
        end if;
        continue;
      end if;

      -- 0180 (d): SHE SPENDS HER SURPLUS ON HER FLEET — lying docked at a build yard while her house
      -- stands above her purse ceiling, one hull (public.npc_build_for: the players' doors, paid into
      -- this city). Budgeted like the dear work above.
      if f.status = 'DOCKED' and not public.npc_upkeep_spent() then
        v_res := public.npc_build_for(r.fleet_id, p_now);
        if v_res is not null then
          v_built := v_built + coalesce((v_res->>'built')::int, 0);
          v_notes := v_notes || (jsonb_build_object('route', sr.name) || v_res);
        end if;
      end if;

      -- THE HALT LAW'S RELEASE, counted: clears with no lap closed between share her lap number.
      select * into fo from public.orders where fleet_id = r.fleet_id and status = 'failed' order by seq limit 1;
      if fo.id is not null and public.npc_upkeep_spent() then
        v_deferred := v_deferred + 1;                               -- 0114
      elsif fo.id is not null then
        select count(*) + 1 into v_clears from public.events ev
         where ev.player_id = sr.player_id and ev.kind = 'NPC_CLEARED'
           and ev.payload->>'route_id' = sr.id::text and (ev.payload->>'lap_no')::int = sr.lap_no;
        perform public.emit_event(sr.player_id, 'NPC_CLEARED', jsonb_build_object(
          'route', sr.name, 'route_id', sr.id, 'lap_no', sr.lap_no, 'fleet', f.name,
          'code', fo.error_code, 'line', fo.raw_text, 'n', v_clears));
        -- 0115: NOT PARKED. The third clear in one lap re-plans her lines on today's market first;
        -- every clear then releases her queue and the executor goes on.
        -- 0150: A SAIL REFUSED E_ENDURANCE IS RE-PLANNED ON THIS CLEAR. Only a plan answers it (her
        -- preset, room for her casks, her cursor back on her stop so the stop renders whole); a
        -- clear alone re-sends the SAIL and nothing else. The count of three was read off events
        -- the compactor deletes after npc_retention_hours, and the hour's pass reached a stuck
        -- merchant every two or three hours: for 251 of 270 it never came.
        if v_clears >= 3 or (fo.verb = 'SAIL' and fo.error_code = 'E_ENDURANCE') then
          perform public.npc_plan(p_now, sr.id);
        end if;
        perform cmd.clear_for(sr.player_id, r.fleet_id, false);
        perform cmd.advance(r.fleet_id, p_now);
        v_cleared := v_cleared + 1;
      end if;
    exception
      when lock_not_available then
        v_busy := v_busy + 1;
      when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('route', r.route_id, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('dark', v_dark, 'started', v_started, 'resumed', v_resumed, 'cleared', v_cleared,
                            'laid_up', v_laid_n, 'busy', v_busy, 'failed', v_failed, 'deferred', v_deferred,
                            'built', v_built,   -- 0180 (d)
                            'waiting', v_waiting,   -- 0181
                            'notes', v_notes);
end $function$

===== profit_tax(uuid,numeric,uuid) [s]
CREATE OR REPLACE FUNCTION public.profit_tax(p_port uuid, p_profit numeric, p_player uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0122: THE charge. Tax on the profit of a sale, nothing on a loss, a break-even, or a profit the
-- game cannot know (null). Dark: nothing (the turnover tax still rides the quote). 0147: at the
-- seller's rate (world.tax_rate(port, seller)).
begin
  return case when public.city_treasury_on() and p_profit > 0
              then round(p_profit * world.tax_rate(p_port, p_player))::bigint else 0::bigint end;
end $function$

===== world.quote(uuid,uuid,numeric,text,numeric,uuid) [s]
CREATE OR REPLACE FUNCTION world.quote(p_port uuid, p_good uuid, p_qty numeric, p_side text, p_limit numeric DEFAULT NULL::numeric, p_fleet uuid DEFAULT NULL::uuid)
 RETURNS TABLE(units numeric, total bigint, avg_price numeric, end_stock numeric, mid_total numeric, tax_total numeric, spread_total numeric, haggle_saved numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0169: THE PRICE AUTHORITY IS world.quote_priced — this body, moved there whole (generated from it and
-- asserted): the side, the market row, its terms (world.quote_terms, read at the same point), the stock
-- walk. Asked here no terms are handed over, so it reads its own: the same answer, the same refusals in
-- the same order. world.trade_routes hands over a quay's terms, read once a ranking.
begin
  return query select * from world.quote_priced(p_port, p_good, p_qty, p_side, p_limit, p_fleet, null, null, null, null);
end $function$

===== voyage.reach_from(uuid) [s]
CREATE OR REPLACE FUNCTION voyage.reach_from(p_from uuid)
 RETURNS TABLE(port_id uuid, code text, nm numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Supersedes 0019's graph Dijkstra: the figures come from public.sea_reaches — computed from
  -- the raster by the one pathfinder, Arctic closed, no Suez, no Panama — so the number a quay
  -- quotes and the water a fleet sails can no longer be two different worlds.
  select b.port_id, e.code, e.nm::numeric
    from public.sea_reaches a
   cross join lateral jsonb_each_text(a.reaches) e(code, nm)
    join public.sea_reaches b on b.code = e.code
   where a.port_id = p_from
$function$

===== cmd.run_standing_route(uuid,timestamp with time zone) [v]
CREATE OR REPLACE FUNCTION cmd.run_standing_route(p_fleet uuid, p_now timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sr       public.standing_routes%rowtype;
  f        public.fleets%rowtype;
  v_n      int;
  cur      record;
  prv      record;
  v_lines  text[];
  v_parsed jsonb;
  v_res    jsonb;
  v_max    int;
  v_sells  int;
  v_per    int;
  v_day    int;
  v_hold   timestamptz;   -- 0096: the interval hold's instant
  v_rest   timestamptz;   -- 0101: the fortnight at home, as an instant
  v_lap    uuid;
  v_closed boolean := false;   -- 0094: this call closed a lap, so the loss guard may judge
  v_npc    boolean := false;   -- 0114: a merchant company's route
  v_plan   jsonb;              -- 0114: the lap-start re-plan's receipt
  v_written int := 0;
  v_msg    text;
  v_det    text;
  v_ref    jsonb;
  i        int;
begin
  if not public.standing_routes_on() then return 0; end if;
  select * into sr from public.standing_routes where fleet_id = p_fleet for update;
  if sr.id is null or sr.paused_reason is not null then return 0; end if;
  if sr.hold_until is not null and sr.hold_until > p_now then return 0; end if;
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then return 0; end if;
  v_npc := exists (select 1 from public.players p where p.id = sr.player_id and p.is_npc);   -- 0114

  -- CONTAINED. tick_arrivals settles every player's arrivals in ONE transaction; a bug in here
  -- must pause THIS route, never abort that tick (docs/TRADE_ROUTES.md §4.3).
  begin
    select count(*) into v_n from public.standing_route_stops where route_id = sr.id;
    if v_n < 2 then
      raise exception 'E_ROUTE_BROKEN: This route has fewer than two stops.' using errcode = 'P0001';
    end if;
    select s.*, p.code, p.kind, p.name as port_name into cur
      from public.standing_route_stops s join public.ports p on p.id = s.port_id
     where s.route_id = sr.id and s.ord = sr.stop_cursor % v_n;
    if cur.kind <> 'HARBOUR' then
      raise exception 'E_ROUTE_BROKEN: % has no market, so the route cannot stop there.', cur.port_name using errcode = 'P0001';
    end if;

    if f.port_id is distinct from cur.port_id then
      select s.*, p.code, p.name as port_name into prv
        from public.standing_route_stops s join public.ports p on p.id = s.port_id
       where s.route_id = sr.id and s.ord = (sr.stop_cursor - 1 + v_n) % v_n;
      if f.port_id = prv.port_id then
        -- The last SAIL was refused and the player CLEARed it: sail on, and nothing else —
        -- 0096: through THE ONE TAIL (cmd.standing_route_tail), so a crew-short fleet hires first.
        v_lines := cmd.standing_route_tail(sr.id, prv.ord, p_fleet);
        for i in 1 .. array_length(v_lines, 1) loop
          v_parsed := jsonb_set(cmd.parse(sr.player_id, p_fleet, v_lines[i]), '{fleet_id}', to_jsonb(p_fleet::text));
          v_res := cmd.enqueue(sr.player_id, v_parsed, v_lines[i],
                               case when v_parsed->>'verb' = 'SAIL' then prv.course end, sr.lap_id);
          if not coalesce((v_res->>'ok')::boolean, false) then
            raise exception 'E_ROUTE_BROKEN: The queue was too full to add the sail onward.' using errcode = 'P0001';
          end if;
        end loop;
        return array_length(v_lines, 1);
      end if;
      perform cmd.standing_route_set_paused(sr.id, 'off_route', null,
        format('%s is not at %s or %s.', f.name, cur.port_name, prv.port_name));
      return 0;
    end if;

    -- LAP BOUNDARY — the first stop.
    if sr.stop_cursor % v_n = 0 then
      if sr.lap_id is not null then
        perform cmd.standing_route_close_lap(sr.id, p_now);
        sr.lap_id := null;
        v_closed := true;
      end if;
      -- LOSS GUARD: the last N closed laps all lost money — judged when a lap has just closed
      -- (0094), so a Resume after a losing pause sails one more lap instead of pausing on the spot.
      -- 0114: PLAYERS ONLY. A merchant is not stopped by losing laps: her lines are re-planned as
      -- each lap starts, below, and a lap with nothing that pays lays her up instead.
      if v_closed and not v_npc and (select count(*) from (select x.net from public.standing_route_laps x
                                 where x.route_id = sr.id and x.closed_at is not null
                                 order by x.lap_no desc limit sr.stop_after_losing_laps) y
           where y.net < 0) >= sr.stop_after_losing_laps then
        perform cmd.standing_route_set_paused(sr.id, 'losing', null,
          format('The last %s laps lost money.', sr.stop_after_losing_laps));
        return 0;
      end if;
      -- PACING (D2), 0096: AN INTERVAL, NOT A CALENDAR. A lap may START game_day_seconds / N after
      -- the LAST lap started — N the route's own pace, else the knob. One rule for every route; it
      -- no longer wakes every route on earth at the same boundary (docs/NPC_TRADERS.md §4.2).
      -- 0117: A MERCHANT'S PACE IS THE KNOB, not a copy of it on each of 837 routes:
      -- npc_laps_per_game_day (0 = none; her rest at home is the only wait). A player's route keeps
      -- its own pace, else standing_route_laps_per_game_day.
      v_per := case when v_npc then public.wc_int('npc_laps_per_game_day')
                    else coalesce(sr.laps_per_game_day, public.wc_int('standing_route_laps_per_game_day')) end;
      v_hold := case when v_per > 0
                     then (select max(x.started_at) from public.standing_route_laps x where x.route_id = sr.id)
                          + make_interval(secs => (public.wc_num('game_day_seconds') / v_per)::double precision)
                end;
      -- 0101 (owner row 122): AND A MERCHANT RESTS A FORTNIGHT AT HOME. A floor on the same hold,
      -- measured from the moment the last lap CLOSED — she has arrived, and now she lies there —
      -- in VOYAGE-days, the days the player counts, converted through the served compression so the
      -- rest follows the clock instead of being typed in real seconds. Merchant routes only: the
      -- one predicate, players.is_npc, as the crew-pool floor reads it.
      if exists (select 1 from public.players p where p.id = sr.player_id and p.is_npc) then
        v_rest := (select max(x.closed_at) from public.standing_route_laps x
                    where x.route_id = sr.id and x.closed_at is not null)
                  + make_interval(secs => (public.wc_num('route_rest_voyage_days') * 86400
                                           / public.wc_num('time_compression'))::double precision);
        v_hold := greatest(coalesce(v_hold, v_rest), coalesce(v_rest, v_hold));
      end if;
      if v_hold is not null and v_hold > p_now then
        update public.standing_routes
           set hold_until = v_hold,
               updated_at = now()
         where id = sr.id;
        return 0;
      end if;
    end if;

    -- RESERVE GUARD: never spend below what the player keeps back.
    if (select ducats from public.players where id = sr.player_id) < sr.reserve then
      perform cmd.standing_route_set_paused(sr.id, 'reserve', null,
        'The company has less than it keeps back.');
      return 0;
    end if;

    -- 0114: ONCE PER LAP, PER SHIP — A MERCHANT'S LINES ARE RE-PLANNED AS HER LAP STARTS, on
    -- today's prices, through THE planner. Nothing pays: npc_plan lays her up and she does not sail
    -- the lap. Lines written in the last minute (the upkeep has just planned and started her) are
    -- today's already and are not planned twice.
    if v_npc and sr.lap_id is null and sr.stop_cursor % v_n = 0
       and sr.updated_at < now() - interval '1 minute' then
      v_plan := public.npc_plan(p_now, sr.id);
      if (select paused_reason from public.standing_routes where id = sr.id) is not null then
        return 0;
      end if;
      -- 0120: THE PLAN MAY HAVE CHANGED HER LOOP. Re-read the route, its stop count and the stop
      -- she lies at, so the orders written below — and the course the SAIL carries — are the
      -- chosen loop's, never the record read before the plan.
      select * into sr from public.standing_routes where id = sr.id;
      select count(*) into v_n from public.standing_route_stops where route_id = sr.id;
      select s.*, p.code, p.kind into cur
        from public.standing_route_stops s join public.ports p on p.id = s.port_id
       where s.route_id = sr.id and s.ord = sr.stop_cursor % v_n;
      if cur.port_id is distinct from f.port_id then
        raise exception 'E_ROUTE_BROKEN: the loop planned for % does not start where she lies', f.name using errcode = 'P0001';
      end if;
    end if;
    if sr.lap_id is null then
      insert into public.standing_route_laps (route_id, lap_no, started_at)
      values (sr.id, sr.lap_no + 1, p_now) returning id into v_lap;
      update public.standing_routes set lap_id = v_lap, lap_no = lap_no + 1, hold_until = null
       where id = sr.id;
      sr.lap_id := v_lap;
    end if;

    v_lines := cmd.standing_route_lines(sr.id, cur.ord, p_fleet);
    -- Only the "sell everything" expansion can outgrow one queue (the lines cap bounds the rest):
    -- drop the trailing SELL lines and note them, so the SAIL always fits.
    v_max := public.wc_int('order_queue_max');
    select count(*) into v_sells from unnest(v_lines) x where x like 'SELL %';
    while array_length(v_lines, 1) > v_max and v_sells > 0 loop
      update public.standing_route_laps
         set skipped = skipped || jsonb_build_array(jsonb_build_object(
               'port', cur.code, 'line', v_lines[v_sells], 'verb', 'SELL', 'code', 'E_QUEUE_FULL'))
       where id = sr.lap_id;
      v_lines := v_lines[1:v_sells - 1] || v_lines[v_sells + 1:];
      v_sells := v_sells - 1;
    end loop;

    for i in 1 .. array_length(v_lines, 1) loop
      -- THE ONE GRAMMAR decides what the line means; the fleet is the route's, always.
      v_parsed := jsonb_set(cmd.parse(sr.player_id, p_fleet, v_lines[i]), '{fleet_id}', to_jsonb(p_fleet::text));
      v_res := cmd.enqueue(sr.player_id, v_parsed, v_lines[i],
                           case when v_parsed->>'verb' = 'SAIL' then cur.course end, sr.lap_id);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception 'E_ROUTE_BROKEN: The queue was too full to add the next stop''s orders.' using errcode = 'P0001';
      end if;
      v_written := v_written + 1;
    end loop;

    update public.standing_route_laps set stops_done = stops_done + 1 where id = sr.lap_id;
    update public.standing_routes set stop_cursor = (cur.ord + 1) % v_n, updated_at = now() where id = sr.id;
    return v_written;
  exception when others then
    v_msg := sqlerrm;
    get stacked diagnostics v_det = pg_exception_detail;
    v_ref := cmd.refusal_caught(v_msg, v_det);
    perform cmd.standing_route_set_paused(sr.id, 'error', v_ref->>'code', v_ref->>'sentence');
    return 0;
  end;
end $function$

===== running_cost_mult(uuid) [s]
CREATE OR REPLACE FUNCTION public.running_cost_mult(p_player uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 0114: npc_cost_mult for a merchant company, 1 for every player. Composed at the three charges
  -- (wages OWED in voyage.settle — paid from profit since 0128 —, cmd.do_provision, cmd.do_repair)
  -- and into npc_plan's wage estimate.
  select case when exists (select 1 from public.players p where p.id = p_player and p.is_npc)
              then public.wc_num('npc_cost_mult') else 1 end
$function$

===== cmd.standing_route_lines(uuid,integer,uuid) [s]
CREATE OR REPLACE FUNCTION cmd.standing_route_lines(p_route uuid, p_stop integer, p_fleet uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  st      record;
  ln      record;
  c       record;
  v_out   text[] := '{}';
  v_floor numeric;
  v_days  int;
  v_n     int;
  v_next  text;
  v_npc   boolean;   -- 0114
  v_sink  uuid;      -- 0114: the next stop, where a BUY here is meant to be sold
  v_cap   numeric;   -- 0114
  q       record;    -- 0114
  v_budget numeric;  -- 0129: her working capital left for this stop's BUYs
  v_aff   record;    -- 0129
  v_patience numeric; -- 0181: her house's patience (null on a player's route)
begin
  select s.*, p.code as port_code into st
    from public.standing_route_stops s join public.ports p on p.id = s.port_id
   where s.route_id = p_route and s.ord = p_stop;
  if st.route_id is null then
    raise exception 'E_ROUTE_BROKEN: the route has no stop %', p_stop using errcode = 'P0001';
  end if;
  select count(*) into v_n from public.standing_route_stops where route_id = p_route;
  v_npc := exists (select 1 from public.standing_routes r join public.players p on p.id = r.player_id and p.is_npc
                    where r.id = p_route);   -- 0114
  select h.patience into v_patience
    from public.standing_routes r join public.npc_houses h on h.player_id = r.player_id
   where r.id = p_route;   -- 0181
  select s.port_id into v_sink from public.standing_route_stops s
   where s.route_id = p_route and s.ord = (p_stop + 1) % v_n;   -- 0114

  -- 1. SELL — a named good, or one line per good on board ("sell everything"), each with its
  --    floor: the line's own, or what it cost (fleet_cargo_basis, the one basis authority).
  for ln in select l.*, g.code as good_code
              from public.standing_route_lines l left join public.goods g on g.id = l.good_id
             where l.route_id = p_route and l.stop_ord = p_stop and l.kind = 'SELL'
             order by l.ord loop
    for c in select x.code from (
               select ln.good_code as code where ln.good_id is not null
               union
               select e.key
                 from public.ships s cross join lateral jsonb_each(s.cargo) e
                where ln.good_id is null and s.fleet_id = p_fleet and (e.value)::text::numeric > 0
                  and e.key not in (select g2.code from public.standing_route_lines l2
                                      join public.goods g2 on g2.id = l2.good_id
                                     where l2.route_id = p_route and l2.stop_ord = p_stop
                                       and l2.kind = 'SELL')) x
             order by x.code loop
      v_floor := case when ln.at_profit then public.fleet_cargo_basis(p_fleet, c.code) else ln.price_limit end;
      -- 0114: a merchant's at-profit floor is what she paid plus npc_sell_margin. A price move can
      -- shrink her profit; it never makes her sell below cost — unsold, it sails to the next stop.
      -- 0142: the cut-loss is a named SELL with no floor (at_profit false: the quay's bid), so a
      -- merchant's at-profit SELL — the general one — always carries the margin.
      if v_npc and ln.at_profit and v_floor is not null then
        v_floor := v_floor * (1 + public.wc_num('npc_sell_margin'));
      end if;
      v_out := v_out || (format('SELL %s %s', c.code, coalesce(trim_scale(ln.qty)::text, 'ALL'))
                         || case when v_floor is null then ''
                                 else ' AT >= ' || trim_scale(round(ceil(v_floor * 100) / 100, 2))::text end);
    end loop;
  end loop;

  -- 2. RESUPPLY to the 0034 keep level — a REFERENCE to the preset, read now, never a copy.
  select pr.days into v_days
    from public.fleets f join public.provision_presets pr on pr.id = f.provision_preset_id
   where f.id = p_fleet;
  if v_days is not null and not public.keep_level_met(p_fleet, v_days) then
    v_out := v_out || format('PROVISION DAYS %s', v_days);
  end if;

  -- 3. REPAIR (to 100%, the grammar's default) — 0181: only when something aboard is due one
  --    (public.fleet_repair_due, the reading cmd.do_repair refuses E_UNAVAILABLE by), as PROVISION
  --    above is written only below the keep level. A sound fleet was sent to the yard and refused on
  --    almost every merchant lap (2,407 refusals in two hours on prod, 2026-10-18).
  if st.repair and exists (select 1 from public.fleet_repair_due(p_fleet, 100) d
                            where d.points > 0 or d.gear is not null) then
    v_out := v_out || 'REPAIR'::text;
  end if;

  -- 4. BUY.
  for ln in select l.*, g.code as good_code
              from public.standing_route_lines l join public.goods g on g.id = l.good_id
             where l.route_id = p_route and l.stop_ord = p_stop and l.kind = 'BUY'
             order by l.ord loop
    -- 0114: THE PLANNER'S KEEP TEST, ASKED AGAIN AT THE MOMENT OF BUYING. A merchant buys a parcel
    -- only at a price the NEXT stop's current bid for that parcel (world.quote, the sell side — after
    -- spread and tax) beats by npc_min_return_pct; a stop that bids nothing drops the line.
    if v_npc then
      continue when ln.qty is null;
      select * into q from world.quote(v_sink, ln.good_id, ln.qty, 'sell', null, null);
      continue when q.units is null or q.units < 1 or q.total is null or q.total <= 0;
      v_cap := floor(q.total / q.units / (1 + public.wc_num('npc_min_return_pct') / 100) * 100) / 100;
      continue when v_cap <= 0;
      -- 0181: THE LIMIT IS PRICED AS SHE ARRIVES — her patience over the quay's ask now
      -- (public.npc_buy_ceiling, read live, not the limit the planner stored), never above what her
      -- next stop's bid lets her pay. Rivals drawing the maker down and the market's drift had moved
      -- the ask past the stored limit on 345 of 1,681 live lines (prod, 2026-10-18 09:20).
      ln.price_limit := least(coalesce(public.npc_buy_ceiling(st.port_id, ln.good_id, v_patience), v_cap), v_cap);
      -- 0129: THE PLANNER'S PURSE BOUND, ASKED AGAIN NOW: no more of it than her working capital
      -- still covers (public.npc_affordable), so a parcel the purse moved under is cut, not refused.
      v_budget := coalesce(v_budget, public.npc_buy_budget(p_fleet));
      select * into v_aff from public.npc_affordable(st.port_id, ln.good_id, ln.qty, v_budget);
      continue when v_aff.units < 1;
      ln.qty   := v_aff.units;
      v_budget := v_budget - coalesce(v_aff.total, 0);
    end if;
    v_out := v_out || (format('BUY %s %s', ln.good_code, coalesce(trim_scale(ln.qty)::text, 'ALL'))
                       || case when ln.price_limit is null then ''
                               else ' AT ' || trim_scale(ln.price_limit)::text end);
  end loop;

  -- 5. 0096: THE ONE TAIL — HIRE back to strength when the stop says so, then SAIL to the next
  --    stop. Its course rides as args.path (the generator attaches it). The sail-on branch of
  --    cmd.run_standing_route renders the same tail, so a crew-short fleet cannot loop for ever.
  v_out := v_out || cmd.standing_route_tail(p_route, p_stop, p_fleet);
  return v_out;
end $function$

===== cmd.standing_route_save_for(uuid,uuid,text,jsonb,bigint,integer,integer) [v]
CREATE OR REPLACE FUNCTION cmd.standing_route_save_for(p_player uuid, p_route uuid, p_name text, p_stops jsonb, p_reserve bigint, p_losing integer, p_laps_per_game_day integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0096: CORE of cmd.standing_route_save — THE one writer of every route column. `p_laps_per_game_day`
-- null = unchanged (the player's editor never passes one; the merchant planner does). Each stop
-- may carry `crew_up`. The re-anchor prefers the cursor's own stop (a loop may call twice). Server-only.
declare
  v_player uuid := p_player;
  sr       public.standing_routes%rowtype;
  v_leg_nm numeric;   -- 0106: the leg's measured length, stored on the stop
  v_gate   jsonb;     -- 0107: the earned-passage refusal for that leg (cmd.refusal), or null
  v_name   text := nullif(btrim(coalesce(p_name, '')), '');
  v_n      int;
  s        jsonb;
  ln       jsonb;
  pt       jsonb;
  k        int;
  j        int;
  v_port   record;
  v_prev   uuid;
  v_first  uuid;
  v_good   uuid;
  v_kind   text;
  f        public.fleets%rowtype;
  v_at     uuid;
  v_anchor int;
begin
  v_n := case when jsonb_typeof(p_stops) = 'array' then jsonb_array_length(p_stops) else 0 end;
  if v_n < 2 or v_n > public.wc_int('standing_route_stop_max') then
    return cmd.standing_route_refusal('E_PARSE',
      format('A route needs 2 to %s stops.', public.wc_int('standing_route_stop_max')), '(add or remove a stop)');
  end if;

  begin
    if p_route is null then
      if v_name is null then
        return cmd.standing_route_refusal('E_PARSE', 'A route needs a name.', '(name it)');
      end if;
      insert into public.standing_routes (player_id, name, reserve, stop_after_losing_laps, laps_per_game_day)
      values (v_player, v_name, coalesce(p_reserve, 0),
              coalesce(p_losing, public.wc_int('standing_route_losing_laps')), p_laps_per_game_day)
      returning * into sr;
    else
      select * into sr from public.standing_routes where id = p_route and player_id = v_player for update;
      if sr.id is null then
        return cmd.standing_route_refusal('E_NO_SUCH_ROUTE', 'You keep no such route.', '(read your routes again)');
      end if;
      update public.standing_routes
         set name = coalesce(v_name, name), reserve = coalesce(p_reserve, reserve),
             stop_after_losing_laps = coalesce(p_losing, stop_after_losing_laps),
             laps_per_game_day = coalesce(p_laps_per_game_day, laps_per_game_day), updated_at = now()
       where id = sr.id returning * into sr;
      delete from public.standing_route_stops where route_id = sr.id;
    end if;

    for k in 0 .. v_n - 1 loop
      s := p_stops->k;
      select p.id, p.kind, p.code into v_port from public.ports p
       where p.code = upper(btrim(coalesce(s->>'port', '')));
      if v_port.id is null then
        raise exception 'E_NO_SUCH_PORT: there is no port "%"', coalesce(s->>'port', '') using errcode = 'P0001';
      end if;
      if v_port.kind <> 'HARBOUR' then
        raise exception 'E_UNAVAILABLE: % is open water; a route stops only where there is a market', v_port.code using errcode = 'P0001';
      end if;
      if v_port.id = v_prev or (k = v_n - 1 and v_port.id = v_first) then
        raise exception 'E_SAME_DEST: two stops in a row are both %', v_port.code using errcode = 'P0001';
      end if;
      if jsonb_typeof(s->'course') <> 'array' or jsonb_array_length(s->'course') < 2 then
        raise exception 'E_BAD_PATH: the leg from % has no course', v_port.code using errcode = 'P0001';
      end if;
      for pt in select * from jsonb_array_elements(s->'course') loop
        if jsonb_typeof(pt) <> 'array' or jsonb_array_length(pt) <> 2
           or jsonb_typeof(pt->0) <> 'number' or jsonb_typeof(pt->1) <> 'number'
           or abs((pt->>0)::numeric) > 90 or abs((pt->>1)::numeric) > 180 then
          raise exception 'E_BAD_PATH: the leg from % is not a list of points on the sphere', v_port.code using errcode = 'P0001';
        end if;
      end loop;
      -- 0106: THE LEG IS MEASURED HERE, where it is written, and never again on a read of it.
      -- public.route_nm sums course_nm; measuring every loop's course on every read of the board
      -- cost 4,543 ms a call at 77 routes, because segments_from_course walks the sea raster for
      -- every segment of every course. A course the sea disputes stores null rather than refusing
      -- the save: this door has already verified the leg through voyage.path_refusal above, so a
      -- raise here would be a second, harsher opinion from a function that only measures.
      begin
        select sum((q->>'nm')::numeric) into v_leg_nm
          from jsonb_array_elements(voyage.segments_from_course(s->'course')) q;
      exception when others then
        v_leg_nm := null;
      end;
      -- 0107 (owner row 117): A ROUTE IS REFUSED WHEN IT IS WRITTEN. The leg was measured one
      -- statement ago, so the gate is asked of that very figure; a route discovered to be illegal
      -- at sea is a route that pauses in a strange harbour at three in the morning. The refusal
      -- carries the server's own sentence through this door's own refusal shape.
      v_gate := public.passage_gate(p_player, v_leg_nm, v_port.id);
      if v_gate is not null then
        return cmd.standing_route_refusal(v_gate->>'code', v_gate->>'sentence',
                                          '(shorten the route or study)');
      end if;
      insert into public.standing_route_stops (route_id, ord, port_id, course, repair, crew_up, course_nm)
      values (sr.id, k, v_port.id, s->'course', coalesce((s->>'repair')::boolean, false),
              coalesce((s->>'crew_up')::boolean, false), v_leg_nm);
      if k = 0 then v_first := v_port.id; end if;
      v_prev := v_port.id;

      j := 0;
      for ln in select * from jsonb_array_elements(coalesce(s->'lines', '[]'::jsonb)) loop
        v_kind := upper(btrim(coalesce(ln->>'kind', '')));
        if v_kind not in ('SELL', 'BUY') then
          raise exception 'E_PARSE: a stop''s line is SELL or BUY, not "%"', coalesce(ln->>'kind', '') using errcode = 'P0001';
        end if;
        v_good := null;
        if nullif(btrim(coalesce(ln->>'good', '')), '') is not null then
          select id into v_good from public.goods where code = btrim(ln->>'good');
          if v_good is null then
            raise exception 'E_NO_SUCH_GOOD: there is no good "%"', ln->>'good' using errcode = 'P0001';
          end if;
        elsif v_kind = 'BUY' then
          raise exception 'E_PARSE: a BUY line names a good' using errcode = 'P0001';
        end if;
        insert into public.standing_route_lines (route_id, stop_ord, ord, kind, good_id, qty, price_limit, at_profit)
        values (sr.id, k, j, v_kind, v_good,
                nullif(ln->>'qty', '')::numeric, nullif(ln->>'price_limit', '')::numeric,
                coalesce((ln->>'at_profit')::boolean, false));
        j := j + 1;
      end loop;
    end loop;
  exception
    -- 0093: no unique_violation arm — a name is a label, not a key (the name index is dropped).
    when check_violation then
      if sqlerrm like '%name_length%' then
        return cmd.standing_route_refusal('E_PARSE', 'A name is 2 to 24 characters.', '(shorten or lengthen the name)');
      end if;
      return cmd.standing_route_refusal('E_PARSE', 'A quantity, a price and a keep-back figure are positive numbers.', '(check the numbers)');
    when invalid_text_representation then
      return cmd.standing_route_refusal('E_PARSE', 'A quantity or a price is not a number.', '(check the numbers)');
    when others then
      if sqlerrm ~ '^E_[A-Z_]+:' then
        return cmd.standing_route_refusal(split_part(sqlerrm, ':', 1),
          btrim(substr(sqlerrm, length(split_part(sqlerrm, ':', 1)) + 2)), '(change the route and save again)');
      end if;
      raise;
  end;

  -- An EDIT of an assigned route re-anchors on where its fleet is now; if the fleet is at no stop
  -- of the edited route, the route pauses rather than guess (docs/TRADE_ROUTES.md §5).
  if sr.fleet_id is not null then
    select * into f from public.fleets where id = sr.fleet_id;
    v_at := case when f.status = 'SAILING'
                 then (select dest_port_id from public.voyages where fleet_id = f.id and status = 'SAILING')
                 else f.port_id end;
    -- 0096: A LOOP MAY CALL AT ONE HARBOUR TWICE. Prefer the stop the cursor names when that stop
    -- IS the fleet's harbour (the one she is bound for, or — docked with route orders pending —
    -- the one she is working), and only then the first visit.
    v_anchor := case when f.status <> 'SAILING'
                           and exists (select 1 from public.orders o where o.fleet_id = f.id
                                        and o.status = 'pending' and o.route_lap_id is not null)
                     then (select s9.ord from public.standing_route_stops s9
                            where s9.route_id = sr.id and s9.port_id = v_at
                              and s9.ord = (sr.stop_cursor - 1 + v_n) % v_n)
                     else (select s9.ord from public.standing_route_stops s9
                            where s9.route_id = sr.id and s9.port_id = v_at
                              and s9.ord = sr.stop_cursor % v_n) end;
    if v_anchor is null then
      select min(ord) into v_anchor from public.standing_route_stops where route_id = sr.id and port_id = v_at;
    end if;
    if v_anchor is null then
      perform cmd.standing_route_set_paused(sr.id, 'edited', null,
        format('%s is not at or bound for a stop of the edited route.', f.name));
    else
      update public.standing_routes
         set stop_cursor = case when f.status <> 'SAILING'
                                 and exists (select 1 from public.orders o where o.fleet_id = f.id
                                              and o.status = 'pending' and o.route_lap_id is not null)
                                then (v_anchor + 1) % v_n else v_anchor end,
             paused_reason = case when paused_reason = 'edited' then null else paused_reason end
       where id = sr.id;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'id', sr.id, 'name', sr.name, 'stops', v_n);
end $function$

===== stores_cost(uuid,numeric,numeric) [s]
CREATE OR REPLACE FUNCTION public.stores_cost(p_player uuid, p_water_t numeric, p_food_t numeric)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- 0142: THE price of stores — tons of water and food at provision_water_price /
  -- provision_food_price through the house's running_cost_mult — lifted from cmd.do_provision
  -- (0114). Read by cmd.do_provision (what she pays) and by public.npc_plan (what a loop will eat).
  return round((coalesce(p_water_t, 0) * public.wc_num('provision_water_price')
                + coalesce(p_food_t, 0) * public.wc_num('provision_food_price'))
               * public.running_cost_mult(p_player))::bigint;
end $function$

===== world.trade_routes(uuid,uuid,numeric,integer,uuid) [s]
CREATE OR REPLACE FUNCTION world.trade_routes(p_from uuid, p_fleet uuid DEFAULT NULL::uuid, p_radius_nm numeric DEFAULT NULL::numeric, p_limit integer DEFAULT NULL::integer, p_to uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_radius  numeric := greatest(1, coalesce(p_radius_nm, public.wc_num('sea_scan_radius_nm')));
  v_ports   int     := public.wc_int('route_scan_max_ports');
  v_keep    int     := public.wc_int('route_scan_keep');
  v_goods   int     := public.wc_int('route_scan_goods');
  v_tuns    numeric := public.wc_num('route_probe_tuns');
  v_player  uuid    := public.current_player_id();
  f         public.fleets%rowtype;
  v_speed   numeric;
  v_basis   text    := 'default';
  v_nports  int;
  v_ncand   int;
  v_rows    jsonb;
begin
  if p_from is null or not exists (select 1 from public.ports where id = p_from) then
    raise exception 'E_NO_SUCH_PORT: there is no such port' using errcode = 'P0001';
  end if;

  if p_fleet is not null then
    select * into f from public.fleets where id = p_fleet;
    -- A fleet id is not a public handle: naming somebody else's fleet would disclose her hold,
    -- her purse and her speed through the numbers this read returns.
    if f.id is null or f.player_id is distinct from v_player then
      raise exception 'E_NOT_YOURS: that is not your fleet' using errcode = 'P0001';
    end if;
    v_speed := voyage.fleet_speed(p_fleet);
    -- Only a fleet LYING HERE can set the quantity: fleet_buy_capacity reads the port she is in.
    if f.port_id = p_from then v_basis := 'fleet'; end if;
  end if;

  with reach as materialized (
    -- TWO QUESTIONS, ONE READ. Without p_to: "where is any of this worth more?" — every port
    -- within v_legs sailed legs, nearest first, capped. With p_to: "what should I carry THERE?" —
    -- that one port, however far it is, which is why the port cap is dropped for it. A separate
    -- function for the second question would have been a second author of the shortlist, the
    -- pricing and the sail gate all at once.
    -- 0047: the reach is the SAILED DISTANCE TABLE (sea_reaches, derived from the raster by the
    -- one pathfinder), not the leg graph. "Two legs out" becomes a radius in nautical miles —
    -- sea_scan_radius_nm defaults to 1,700, the measured median horizon of the old 2-leg scan
    -- across all 214 harbours — and the gate is the same one authority cmd.do_sail raises from.
    select y.port_id, y.nm
      from (select r.port_id, r.nm
              from voyage.reach_from(p_from) r
              join public.ports dp on dp.id = r.port_id and dp.kind = 'HARBOUR'
             where (p_to is null and r.nm <= v_radius) or (r.port_id = p_to)
             order by r.nm, r.port_id
             limit v_ports) y
     where (v_basis <> 'fleet' or voyage.sail_refusal(p_fleet, y.port_id, null, y.nm) is null)
  ),
  here as materialized (
    select pg.good_id, pg.stock, g.culture_mask,
           world.mid_price(p_from, pg.good_id, pg.stock) as mid
      from public.port_goods pg
      join public.goods g on g.id = pg.good_id
      join public.ports  p on p.id = pg.port_id
     where pg.port_id = p_from
       and not public.culture_refuses(p.culture, g.culture_mask)
       -- 0061: and she can only LOAD what this city trades. Same authority cmd.do_buy asks, so the
       -- shortlist cannot name a cargo the order would refuse. The destination is NOT filtered:
       -- selling is not gated by the roster (see this file's header).
       -- 0136: the roster read ONCE per ranking (public.port_offered_goods, which public.port_offers
       -- is membership in) — was one port_offers call per market row, 555 a ranking.
       and pg.good_id in (select o.good_id from public.port_offered_goods(p_from) o)
  ),
  -- STAGE 1 — the shortlist, through world.mid_price: one call per (good, destination) in range.
  -- It READS the price authority rather than re-deriving anything, and what it produces is a
  -- candidate list, never a number this read reports.
  mids as materialized (
    select h.good_id, rc.port_id, rc.nm, h.mid as mid_here,
           world.mid_price(rc.port_id, h.good_id, pg.stock) as mid_there
      from here h
      cross join reach rc
      join public.port_goods pg on pg.port_id = rc.port_id and pg.good_id = h.good_id
      join public.ports d on d.id = rc.port_id
     where not public.culture_refuses(d.culture, h.culture_mask)
  ),
  pairs as materialized (
    select m.good_id, m.port_id, m.nm, m.mid_there - m.mid_here as gap,
           row_number() over (partition by m.good_id
                                  order by m.mid_there desc, m.nm asc) as rn
      from mids m
     where m.mid_there > m.mid_here
  ),
  short_goods as materialized (
    select good_id from pairs where rn = 1 order by gap desc, good_id limit v_goods
  ),
  kept as materialized (
    select p.good_id, p.port_id, p.nm
      from pairs p
      join short_goods sg on sg.good_id = p.good_id
     where p.rn <= v_keep
  ),
  -- STAGE 2 — the price, through world.quote, which is where the money moves.
  -- The BUY side does not depend on the destination, so it is quoted ONCE per good.
  sized as materialized (
    select h.good_id,
           case when v_basis = 'fleet'
                then (public.fleet_buy_capacity(p_fleet, h.good_id)->>'max_qty')::numeric
                else floor(least(v_tuns, h.stock)) end as qty
      from here h
      join short_goods sg on sg.good_id = h.good_id
  ),
  -- 0169: A QUAY'S QUOTE TERMS, READ ONCE A RANKING. With no fleet named a quote's four terms are the
  -- port's (world.quote_terms: no purser, no bargain — the same for every good, size and side), so the
  -- source's are read once here and each sink's once below, and every quote is handed them
  -- (world.quote_priced). With a fleet named there are none: each quote reads its own, per good.
  qt_from as materialized (
    select k.q_spread, k.q_nohag, k.q_tax, k.q_bidf
      from world.quote_terms(p_from, null, null) k
     where p_fleet is null
  ),
  bought as materialized (
    select z.good_id, qb.units, qb.total as outlay, qb.avg_price as buy_price
      from sized z
      cross join lateral world.quote_priced(p_from, z.good_id, z.qty, 'buy', null, p_fleet,
                                            (select q.q_spread from qt_from q), (select q.q_nohag from qt_from q),
                                            (select q.q_tax from qt_from q), (select q.q_bidf from qt_from q)) qb
     where z.qty >= 1
  ),
  qt_to as materialized (
    select d.port_id, k.q_spread, k.q_nohag, k.q_tax, k.q_bidf
      from (select distinct kk.port_id from kept kk join bought bb on bb.good_id = kk.good_id and bb.units > 0) d
     cross join lateral world.quote_terms(d.port_id, null, null) k
     where p_fleet is null
  ),
  priced as materialized (
    select k.good_id, k.port_id, k.nm,
           b.units, b.outlay, b.buy_price,
           qs.total as proceeds, qs.avg_price as sell_price
      from kept k
      join bought b on b.good_id = k.good_id and b.units > 0
      cross join lateral world.quote_priced(k.port_id, k.good_id, b.units, 'sell', null, p_fleet,
                                            (select q.q_spread from qt_to q where q.port_id = k.port_id),
                                            (select q.q_nohag from qt_to q where q.port_id = k.port_id),
                                            (select q.q_tax from qt_to q where q.port_id = k.port_id),
                                            (select q.q_bidf from qt_to q where q.port_id = k.port_id)) qs   -- 0169
  ),
  best as (
    select distinct on (p.good_id) p.*
      from priced p
     order by p.good_id, (p.proceeds - p.outlay) desc, p.nm asc
  ),
  shaped as (
    select jsonb_build_object(
             'good_id', b.good_id, 'code', g.code, 'name', g.name,
             'to', jsonb_build_object('id', d.id, 'code', d.code, 'name', d.name),
             'qty', b.units, 'outlay', b.outlay, 'proceeds', b.proceeds,
             'profit', b.proceeds - b.outlay,
             'return_pct', case when b.outlay > 0
                                then round((b.proceeds - b.outlay)::numeric / b.outlay * 100, 1) end,
             'buy_price', b.buy_price, 'sell_price', b.sell_price,
             'nm', b.nm,
             'days', case when v_speed > 0 then round(b.nm / v_speed / 24, 2) end,
             'profit_per_day', case when v_speed > 0 and b.nm > 0
                                    then round((b.proceeds - b.outlay)::numeric / (b.nm / v_speed / 24), 1) end,
             'profit_per_nm', round((b.proceeds - b.outlay)::numeric / greatest(b.nm, 1), 4)
           ) as x,
           -- RANKED BY PROFIT, AND THAT WAS MEASURED RATHER THAN ASSUMED. The first cut ranked by
           -- profit per sea-mile, which is the better RATE and the worse ANSWER: out of Lisboa it
           -- put "27 tuns of wax to Setúbal, 16 nm, +49 d." above "20 tuns of porcelain to
           -- Saint-Louis, +1,847 d.", because 49/16 beats 1847/1534. A player who taps the top row
           -- and makes forty-nine ducats has been told the same unhelpful thing the %NBR bands
           -- told the auditor, in a new column. What a captain is choosing between here is
           -- VOYAGES, and the question is how much this one pays; the rate is on the row for
           -- anyone comparing tempos (`profit_per_day`, and `profit_per_nm` when no fleet is named
           -- and there is no speed to divide by).
           row_number() over (order by (b.proceeds - b.outlay) desc, b.nm asc, b.good_id) as rk
      from best b
      join public.goods g on g.id = b.good_id
      join public.ports d on d.id = b.port_id
     where b.proceeds > b.outlay
  )
  select (select count(*) from reach),
         (select count(*) from shaped),
         (select coalesce(jsonb_agg(x order by rk)
                            filter (where p_limit is null or rk <= p_limit), '[]'::jsonb)
            from shaped)
    into v_nports, v_ncand, v_rows;

  return jsonb_build_object(
    'from', (select jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name)
               from public.ports p where p.id = p_from),
    'fleet', case when f.id is null then null else
               jsonb_build_object('id', f.id, 'name', f.name, 'speed_kn', v_speed,
                                  'here', f.port_id = p_from) end,
    -- THE BOUNDS THIS ANSWER WAS COMPUTED UNDER, reported rather than assumed. A profit with no
    -- quantity is not a number, and a search with no stated reach is not a search.
    'basis', jsonb_build_object(
       'qty_from', v_basis, 'tuns', v_tuns,
       'radius_nm', case when p_to is null then v_radius else null end,
       'to', (select p.code from public.ports p where p.id = p_to),
       'ports_considered', v_nports, 'goods_cap', v_goods, 'keep_per_good', v_keep,
       'routes_found', v_ncand),
    'routes', v_rows);
end $function$

===== wages_from_profit(numeric,numeric) [i]
CREATE OR REPLACE FUNCTION public.wages_from_profit(p_owed numeric, p_profit numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 0128: THE RULE. Of what she owes her crew, a profit pays at most itself: nothing on a loss, a
  -- break-even, or a profit the game cannot know (null). public.pay_wages pays by it; the planner
  -- (npc_leg_lines) prices a leg by it.
  select case when p_owed > 0 and p_profit > 0 then least(p_owed, p_profit) else 0 end
$function$


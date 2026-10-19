-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0203 — A MERCHANT'S LOOP IS ONE SHE CAN SAIL, PAY FOR AND REMEMBER  (one endurance authority for the
--        sail door and the planner; a refound judges what she is worth, not what is in her purse; the
--        courses the world has held are not forgotten)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT PROD SHOWED (read-only watch of 0197, 2026-10-18 18:30–20:35 UTC, head 0197–0199;
--    docs/dev-log/2026-10-19-routes-fix.md)
-- * 270 merchant fleets had a SAIL refused E_ENDURANCE since 0197 (5–8 an hour before). The 25 latest,
--   read one by one: the course she sailed measures what the reach table says (path 2,339 nm, reach
--   2,338.8), her stores were exactly her preset (have 22 = preset 22), and the door asked more (23.6).
--   THE CAUSE IS THE SPEED. The planner measured every leg at voyage.fleet_speed at her lap start — empty;
--   the door measures it at the speed she leaves at — laden: ship_speed's load term is
--   1 − load_speed_penalty (0.25) × fill, so a full hold sails up to a quarter slower and the passage
--   asks up to a third more days. 0197 offered long trade loops to every hull, where a third of
--   twenty days is a week. The hourly tend cleared each refusal and re-planned her (318 clears).
-- * 83 refounds since 18:30 (8 in the two hours before), 1.07 M d. from city treasuries into merchant
--   purses. THE CAUSE IS THE TEST. public.npc_tend_houses refounds a house whose PURSE is under 20 % of
--   her capital, and her BUYs spend 90 % of her purse and cargo (npc_buy_budget): a merchant who has just
--   bought her parcels holds a tenth of her purse in coin and the rest in her hold — e.g. Lu Chuanhang,
--   capital 5,000, coin 982, bought 4,737 an hour before: "refounded" 4,018 while worth 5,700. A short hop
--   sold the parcel within minutes; a long trade lap keeps it aboard for hours, so the hourly tend found
--   her "broke" twenty-seven times as often. None of them was broke.
-- * 113 merchants' home harbour knows one leg or none (public.npc_known_legs); Le Havre knows only
--   Gdansk, so Comptoir Chastellain is offered LEH-GDA and nothing else. THE CAUSE IS THE MEMORY. The known
--   legs are the legs of the merchants' loops AS THEY STAND, and a loop is only ever re-planned onto known
--   legs: a leg the last merchant sailing it gives up is forgotten, and none is ever added. The graph can
--   only shrink. A fresh world: harbours know a median of 8 legs (Le Havre 7: LUB COP HAM GDA RIG SET SNL);
--   prod after ten days of re-planning: a median of 2, 27 harbours none, 44 one.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) ONE MEASURE OF THE DAYS A PASSAGE ASKS. voyage.stores_need_days(nm, speed) — the passage's days at
--     endurance_margin — is voyage.sail_refusal's rule, lifted out; the door, the desk (world.good_board)
--     and the planner (public.npc_leg_days: those days, rounded up, one day spare — the preset a leg asks;
--     read by npc_feasible_legs, npc_plan and npc_casks_blocked) all read it. No copy of the formula is
--     left (asserted).
-- (2) THE SPEED SHE SAILS AT. voyage.ship_speed_at(ship, fill) / voyage.fleet_speed_at(fleet, fill) carry
--     THE speed formula with the fill as an argument (null: the fill she carries now); ship_speed and
--     fleet_speed answer through them, unchanged (asserted for every fleet). public.npc_plan plans at
--     fleet_speed_at(fleet, 1) — her hold full, as the loop she is planned fills it, the slowest she leaves
--     at — so the days planned are never fewer than the door asks.
-- (3) A LOOP SHE CAN SAIL AND PAY FOR. public.npc_provision_for(fleet, days) is what she will carry after
--     the plan's own PROVISION — every hull topped up by public.stores_topup as cmd.do_provision tops it,
--     the endurance as voyage.endurance_days reads it (its multiplier, voyage.endurance_mult, lifted out) —
--     and what those stores cost (public.stores_cost). public.npc_plan prices a loop as sailable only when
--     those days cover its longest leg at the door's measure AND her purse covers those stores; one that
--     is not is never chosen, and hers, when it is hers, is not sailed with a BUY ("pays" is: a lap leaves
--     her more than nothing, and she can sail it, and she can afford it).
-- (4) A REFOUND JUDGES WHAT SHE IS WORTH. public.npc_worth(player) — her purse and her cargo at what it
--     cost (public.fleet_stock_at_cost, the basis her BUY budget counts) — is what npc_tend_houses tests
--     against npc_purse_floor_pct and tops up to her capital.
-- (5) THE COURSES THE WORLD HAS HELD. public.npc_courses keeps every directed leg's course: the roster's
--     loops as the chain founds them (the 995 legs of a fresh world, below, by port code) and every leg of
--     a merchant's loop at this deploy. public.npc_known_legs reads them as well as the loops as they stand,
--     so a leg nobody sails today is still on offer. Comptoir Chastellain is offered Le Havre's seven legs.
-- (6) THE REVIEW, HALF AS OFTEN: npc_route_review_laps 3 → 6. A merchant whose loop pays is offered
--     other loops every npc_route_review_laps-th lap; her harbour now knows three times the legs, so a review
--     prices fifteen loops where it priced seven (prod-shaped: 277 against 161 ms a plan). Every sixth lap
--     keeps the planner's cost a lap where it was (a loop that leaves her nothing is reviewed at once, as before).
-- (7) A PROMOTION IS NOT MADE. public.item_not_made (THE sentence of "made nowhere", read by made_only_in,
--     so cmd.do_make and world.workstation) answers for an item of a kind no workshop makes (the three
--     promotion items: no recipe, workshop tier 1 — free to make until now; 0 MADE events on prod).
--
-- ── NOT THE OWNER'S — CONFIRM ───────────────────────────────────────────────────────────────────
-- * The planner's speed is the full hold's (fill 1). A merchant that sails half-full has days to spare.
-- * A refound reads purse + cargo at cost; the floor (npc_purse_floor_pct 0.2) is unchanged.
-- * The seeded courses are the fresh world's roster legs; a later migration that founds merchants on new
--   courses adds them to public.npc_courses.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- One CREATE TABLE (npc_courses, server-only) and its seed (~1,200 rows), one world_config UPDATE, CREATE FUNCTION ×7, CREATE OR
-- REPLACE FUNCTION ×11 by hunks. The probes run on their own merchants' rows inside sub-transactions
-- rolled back whole. No LOCK TABLE, no set role, no set local, no begin. Timings are notices only.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0199, LF-normalised, each asserted to occur
-- exactly once and to reverse to its pre-image, ACL unchanged): voyage.ship_speed, voyage.fleet_speed,
-- voyage.endurance_days, voyage.sail_refusal, world.good_board, public.npc_feasible_legs,
-- public.npc_casks_blocked, public.npc_plan, public.npc_known_legs, public.npc_tend_houses,
-- public.item_not_made.
-- ROLLBACK: a forward slice restores the eleven bodies (each hunk's OLD text is here verbatim); the new
-- functions and public.npc_courses are then unread and may be dropped.
-- VERSION: 0203.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0203(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- A MERCHANT AT HER LAP START (her own rows, rolled back with the rest): the routes and merchants on, her
-- fleet docked at her stop 0 between laps, nothing aboard, no order.
create or replace function pg_temp.at_lap_start_0203(p_fleet uuid, p_route uuid)
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

-- THE LOOP WRITTEN, AS THE DOOR WILL JUDGE IT: after the plan's PROVISION (cmd.do_provision DAYS her preset,
-- the one provisioning rule), every leg's course measured as cmd.do_sail measures it
-- (voyage.segments_from_course) and judged at the full hold's speed by the door's measure against
-- voyage.endurance_days. And the net of a lap (0142's, the planner's own leg planner).
create or replace function pg_temp.loop_door_0203(p_route uuid)
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
  v_end   numeric;
  v_prov  text := 'ok';
  v_worst numeric := 0;
  v_bad   int := 0;
  v_maxnm numeric := 0;
  v_cnm   numeric;
  s       record;
  j       int;
begin
  select * into sr from public.standing_routes where id = p_route;
  v_fleet := coalesce(sr.fleet_id, (select nf.fleet_id from public.npc_fleets nf where nf.route_id = p_route));
  select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(sh.id)), 0) into v_crew, v_hold
    from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = v_fleet;
  v_hold := v_hold + public.fleet_free_hold(v_fleet);
  v_speed := greatest(coalesce(voyage.fleet_speed_at(v_fleet, 1), 0), 0.1);
  v_ports := array(select st.port_id from public.standing_route_stops st where st.route_id = p_route order by st.ord);
  v_n := cardinality(v_ports);
  for j in 1 .. v_n loop
    v_leg := public.npc_leg_lines(p_route, v_ports[j], v_ports[j % v_n + 1], v_hold, v_crew, v_speed);
    v_profit := v_profit + coalesce((v_leg->>'profit')::numeric, 0);
    v_wages := v_wages + coalesce((v_leg->>'wages')::numeric, 0);
    v_nm := v_nm + coalesce((v_leg->>'nm')::numeric, 0);
  end loop;
  v_sea_d := v_nm / (v_speed * 24);
  begin
    perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'DAYS',
              'days', (select pr.days from public.fleets f join public.provision_presets pr on pr.id = f.provision_preset_id where f.id = v_fleet)));
  exception when others then
    v_prov := split_part(sqlerrm, ':', 1);
  end;
  v_end := voyage.endurance_days(v_fleet);
  for s in select st.course from public.standing_route_stops st where st.route_id = p_route order by st.ord loop
    select coalesce(sum((g->>'nm')::numeric), 0) into v_cnm from jsonb_array_elements(voyage.segments_from_course(s.course)) g;
    v_maxnm := greatest(v_maxnm, v_cnm);
    v_worst := greatest(v_worst, voyage.stores_need_days(v_cnm, v_speed));
    if v_end < voyage.stores_need_days(v_cnm, v_speed) then
      v_bad := v_bad + 1;
    end if;
  end loop;
  return jsonb_build_object('net', round(v_profit - public.wages_from_profit(v_wages, v_profit)
           - public.stores_cost(sr.player_id, v_crew * public.wc_num('water_per_crew_day') * v_sea_d,
                                v_crew * public.wc_num('food_per_crew_day') * v_sea_d)),
         'nm', round(v_nm), 'max_leg', round(v_maxnm),
         'stops', (select string_agg(p.code, '-' order by st.ord) from public.standing_route_stops st
                     join public.ports p on p.id = st.port_id where st.route_id = p_route),
         'buys', (select count(*) from public.standing_route_lines l where l.route_id = p_route and l.kind = 'BUY'),
         'reason', sr.paused_reason, 'provision', v_prov, 'have', round(v_end, 1), 'need', round(v_worst, 1),
         'legs_refused', v_bad,
         -- the pre-image's measure of the same loop: the preset it raised to (her lap-start speed, empty)
         'old_preset', ceil(v_maxnm / (greatest(coalesce(voyage.fleet_speed(v_fleet), 0), 0.1) * 24)
                            * public.wc_num('endurance_margin'))::int + 1);
end $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0203 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('voyage.ship_speed(uuid)'),
               ('voyage.fleet_speed(uuid)'),
               ('voyage.endurance_days(uuid)'),
               ('voyage.sail_refusal(uuid,uuid,jsonb,numeric)'),
               ('world.good_board(uuid,uuid,uuid,numeric)'),
               ('public.npc_feasible_legs(uuid,numeric,integer)'),
               ('public.npc_casks_blocked(uuid,uuid,numeric,numeric)'),
               ('public.npc_plan(timestamp with time zone,uuid)'),
               ('public.npc_known_legs(uuid)'),
               ('public.npc_tend_houses(timestamp with time zone)'),
               ('public.item_not_made(text)')) f(fn);

do $$
begin
  if (select count(*) from defs_before_0203 where def is not null) <> 11 then
    raise exception '0203 self-assert FAIL: % of the 11 bodies found', (select count(*) from defs_before_0203 where def is not null);
  end if;
  if to_regclass('public.npc_courses') is not null then
    raise exception '0203 self-assert FAIL: public.npc_courses exists already';
  end if;
  if public.wc_int('npc_route_review_laps') is distinct from 3 then
    raise exception '0203 self-assert FAIL: npc_route_review_laps is %, not the 3 this file was written against', public.wc_int('npc_route_review_laps');
  end if;
end $$;

-- the pre-image bodies under pg_temp names, for the equivalence checks
do $$
declare
  d record;
begin
  for d in select * from defs_before_0203 where fn in ('voyage.ship_speed(uuid)', 'voyage.fleet_speed(uuid)',
                                                       'voyage.endurance_days(uuid)', 'voyage.sail_refusal(uuid,uuid,jsonb,numeric)') loop
    execute replace(d.def, 'CREATE OR REPLACE FUNCTION voyage.' || split_part(split_part(d.fn, '.', 2), '(', 1) || '(',
                    'CREATE OR REPLACE FUNCTION pg_temp.' || split_part(split_part(d.fn, '.', 2), '(', 1) || '_old_0203(');
  end loop;
end $$;

-- THE LEG GRAPH BEFORE: merchants whose home harbour knows one leg or none
create temp table graph_0203 (k text primary key, v jsonb) on commit drop;
insert into graph_0203
select 'before', jsonb_build_object(
  'homes_single', (select count(*) from public.npc_fleets nf join public.standing_route_stops s0 on s0.route_id = nf.route_id and s0.ord = 0
                    where (select count(*) from public.npc_known_legs(s0.port_id)) <= 1),
  'leh', (select count(*) from public.npc_known_legs((select id from public.ports where code = 'LEH'))));

-- ── 2. THE NEW AUTHORITIES ─────────────────────────────────────────────────────────────────────
-- (1) THE DAYS OF STORES A PASSAGE ASKS — voyage.sail_refusal's rule, the one measure.
create or replace function voyage.stores_need_days(p_nm numeric, p_speed numeric)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0203: THE DAYS OF STORES A PASSAGE OF p_nm AT p_speed ASKS — its days at sea at endurance_margin. The
  -- sail door (voyage.sail_refusal: E_ENDURANCE when her casks hold fewer), the desk (world.good_board's
  -- `sailable`) and the planner (public.npc_leg_days) read it; there is no other copy.
  select ((p_nm / p_speed) / 24) * public.wc_num('endurance_margin')
$$;
revoke all on function voyage.stores_need_days(numeric, numeric) from public, anon, authenticated;

-- THE PRESET A LEG ASKS — those days rounded up, one day spare.
create or replace function public.npc_leg_days(p_nm numeric, p_speed numeric)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0203: the days of stores a merchant is provisioned for a leg of p_nm at p_speed: the door's measure
  -- (voyage.stores_need_days) rounded up, plus one day. Read by public.npc_feasible_legs (which legs she may
  -- be offered), public.npc_plan (the preset her loop raises) and public.npc_casks_blocked.
  select ceil(voyage.stores_need_days(coalesce(p_nm, 0), greatest(coalesce(p_speed, 0), 0.1)))::int + 1
$$;
revoke all on function public.npc_leg_days(numeric, numeric) from public, anon, authenticated;

-- (2) THE SPEED AT A FILL — voyage.ship_speed's formula with the fill as an argument (built from its live body).
do $$
declare
  v_def text := (select def from defs_before_0203 where fn = 'voyage.ship_speed(uuid)');
  v_sig text := 'CREATE OR REPLACE FUNCTION voyage.ship_speed(p_ship uuid)';
  v_fil text := $f$  v_fill := least(1.0, (v_cargo_t + s.water_t + s.food_t) / world.ship_stat(p_ship, 'hold'));$f$;
begin
  if pg_temp.occurs_0203(v_def, v_sig) <> 1 or pg_temp.occurs_0203(v_def, v_fil) <> 1 then
    raise exception '0203 self-assert FAIL: voyage.ship_speed is not the body this file was written against';
  end if;
  v_def := replace(v_def, v_sig, 'CREATE OR REPLACE FUNCTION voyage.ship_speed_at(p_ship uuid, p_fill numeric)');
  v_def := replace(v_def, v_fil,
    $f$  -- 0203: THE FILL ASKED (p_fill: 1 = her hold full, the slowest she leaves at), or, null, the fill she
  -- carries now. voyage.ship_speed is this with null.
  v_fill := case when p_fill is null then least(1.0, (v_cargo_t + s.water_t + s.food_t) / world.ship_stat(p_ship, 'hold'))
                else least(1.0, greatest(0.0, p_fill)) end;$f$);
  execute v_def;
end $$;
revoke all on function voyage.ship_speed_at(uuid, numeric) from public, anon, authenticated;

do $$
declare
  v_def text := (select def from defs_before_0203 where fn = 'voyage.fleet_speed(uuid)');
  v_sig text := 'CREATE OR REPLACE FUNCTION voyage.fleet_speed(p_fleet uuid)';
  v_min text := 'select min(voyage.ship_speed(s.id)), count(*) into v_min, v_ships';
begin
  if pg_temp.occurs_0203(v_def, v_sig) <> 1 or pg_temp.occurs_0203(v_def, v_min) <> 1 then
    raise exception '0203 self-assert FAIL: voyage.fleet_speed is not the body this file was written against';
  end if;
  v_def := replace(v_def, v_sig, 'CREATE OR REPLACE FUNCTION voyage.fleet_speed_at(p_fleet uuid, p_fill numeric)');
  v_def := replace(v_def, v_min, 'select min(voyage.ship_speed_at(s.id, p_fill)), count(*) into v_min, v_ships   -- 0203: at the fill asked');
  execute v_def;
end $$;
revoke all on function voyage.fleet_speed_at(uuid, numeric) from public, anon, authenticated;

-- (3) THE ENDURANCE MULTIPLIER — voyage.endurance_days' skill and Provisioners, lifted out.
create or replace function voyage.endurance_mult(p_fleet uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid;
  v_skill  numeric := 0;
  v_crew   numeric;
begin
  -- 0203: what her house's ENDURANCE skill and the Provisioners seated in her fleet (0161, K7; 0 while
  -- crew_bite is off) multiply her stores' days by — voyage.endurance_days' multiplier, lifted out so the
  -- planner (public.npc_provision_for) reads the very one the door reads.
  select f.player_id into v_player from public.fleets f where f.id = p_fleet;
  if v_player is not null then
    v_skill := public.player_skill_bonus(v_player, 'ENDURANCE');
  end if;
  v_crew := public.crew_pct(p_fleet, null, 'supplies');
  if v_crew <> 0 then
    return (1 + v_skill) * (1 + v_crew);
  end if;
  return 1 + v_skill;
end $$;
revoke all on function voyage.endurance_mult(uuid) from public, anon, authenticated;

-- WHAT SHE WILL CARRY AFTER THE PLAN'S PROVISION, AND WHAT IT COSTS.
create or replace function public.npc_provision_for(p_fleet uuid, p_days numeric)
returns table (days numeric, cost bigint)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0203: PROVISION DAYS p_days, as cmd.do_provision places it at a stop once her SELLs have run (her hold
  -- clear of cargo): every hull topped up by public.stores_topup (the one top-up: the shorter store first,
  -- never past her hold),
  -- the days she then holds as voyage.endurance_days reads them (the shortest hull, times
  -- voyage.endurance_mult), and what the top-up costs (public.stores_cost, the price she pays). Read by
  -- public.npc_plan: a loop is sailable when these days cover its longest leg and her purse this cost.
  select min(t.days) * voyage.endurance_mult(p_fleet),
         public.stores_cost((select f.player_id from public.fleets f where f.id = p_fleet),
                            coalesce(sum(t.water_t), 0), coalesce(sum(t.food_t), 0))
    from public.ships s
   cross join lateral public.stores_topup(s.crew, s.water_t, s.food_t, public.ship_hold_capacity(s.id),
                                          p_days, public.ship_hold_capacity(s.id) * s.store_ratio) t
   where s.fleet_id = p_fleet
$$;
revoke all on function public.npc_provision_for(uuid, numeric) from public, anon, authenticated;

-- (4) WHAT A MERCHANT HOUSE IS WORTH.
create or replace function public.npc_worth(p_player uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0203: her purse and the cargo in her merchants' holds at what it cost (public.fleet_stock_at_cost, the
  -- basis her BUY budget counts as hers: public.npc_buy_budget). Read by public.npc_tend_houses: a house is
  -- refounded when THIS is under her floor, never because she has just bought her parcels.
  select coalesce((select pl.ducats from public.players pl where pl.id = p_player), 0)
       + coalesce((select sum(public.fleet_stock_at_cost(nf.fleet_id)) from public.npc_fleets nf where nf.player_id = p_player), 0)::bigint
$$;
revoke all on function public.npc_worth(uuid) from public, anon, authenticated;

-- THE REVIEW, every sixth lap (header (6)).
update public.world_config set value = to_jsonb(6),
       description = description || ' 0203: every 6th lap (her harbour knows three times the legs; a review prices twice the loops).'
 where key = 'npc_route_review_laps';

-- (5) THE COURSES THE WORLD HAS HELD.
create table public.npc_courses (
  from_port uuid not null references public.ports (id),
  to_port   uuid not null references public.ports (id),
  course    jsonb not null check (jsonb_typeof(course) = 'array' and jsonb_array_length(course) >= 2),
  nm        numeric not null check (nm > 0),   -- the course's own measure: voyage.segments_from_course, as cmd.do_sail measures it
  primary key (from_port, to_port),
  check (from_port <> to_port)
);
comment on table public.npc_courses is
  '0203: every directed leg''s course a merchant loop has held — the roster as the chain founds it and every merchant '
  'leg at 0203''s deploy — read by public.npc_known_legs beside the loops as they stand, so a leg nobody sails today '
  'stays on offer. A migration that founds merchants on new courses adds them here.';
create index npc_courses_to on public.npc_courses (to_port);
alter table public.npc_courses enable row level security;
revoke all on table public.npc_courses from public, anon, authenticated;

-- every leg of a merchant loop as it stands now, then the fresh world's roster legs (by port code)
-- (the measure is the save door's: the stored course_nm where a loop holds the course, else measured here)
insert into public.npc_courses (from_port, to_port, course, nm)
select a, b, course, coalesce(course_nm, (select sum((q->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(course)) q))
  from (select distinct on (a, b) a, b, course, course_nm
          from (select s.port_id as a,
                       coalesce(lead(s.port_id) over w, first_value(s.port_id) over w) as b, s.course, s.course_nm
                  from public.standing_route_stops s
                  join public.standing_routes sr on sr.id = s.route_id
                  join public.players p on p.id = sr.player_id and p.is_npc
                window w as (partition by s.route_id order by s.ord)) l
         where a <> b and jsonb_typeof(course) = 'array' and jsonb_array_length(course) >= 2
         order by a, b, jsonb_array_length(course), course::text) d;

insert into public.npc_courses (from_port, to_port, course, nm)
select pa.id, pb.id, x->2, (select sum((q->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(x->2)) q)
  from jsonb_array_elements($seed$[["ACA","CLL",[[16.625,-99.875],[-12.125,-77.375]]],["ACA","MNL",[[16.625,-99.875],[12.625,124.375],[12.375,124.125],[12.375,123.875],[13.625,121.125],[13.625,120.625],[13.875,120.375],[14.375,120.625]]],["ACA","MTY",[[16.625,-99.875],[16.875,-100.625],[18.125,-103.625],[22.875,-110.375],[27.625,-115.125],[34.625,-120.875],[36.375,-122.125],[36.625,-122.125]]],["ACA","MZT",[[16.625,-99.875],[16.875,-100.625],[18.125,-103.625],[19.375,-105.375],[20.125,-105.875],[23.125,-106.625]]],["ACA","PAN",[[16.625,-99.875],[7.875,-82.875],[7.125,-80.625],[7.125,-80.375],[7.625,-79.875],[8.625,-79.375],[8.875,-79.375]]],["ACC","BRU",[[5.375,-0.125],[4.625,-1.375],[4.125,-8.125],[4.875,-9.375],[7.375,-12.875],[12.125,-16.875],[14.875,-17.625],[37.125,-16.375],[50.375,-3.125],[50.625,0.625],[51.375,2.375],[51.375,3.125]]],["ACC","REC",[[5.375,-0.125],[-8.125,-23.375],[-8.125,-34.625]]],["ACC","SAO",[[5.375,-0.125],[0.34,6.73]]],["ACC","SOY",[[5.375,-0.125],[-6.125,12.125]]],["ADE","HAD",[[12.625,45.125],[12.65,54.03]]],["ADE","JED",[[12.625,45.125],[12.375,43.875],[13.375,42.875],[21.375,38.875],[21.625,38.875]]],["ADE","MCH",[[12.625,45.125],[9.625,75.625],[7.875,77.375],[7.875,77.875],[9.375,79.375],[10.375,80.125],[16.125,81.375]]],["ADE","MLN",[[12.625,45.125],[12.125,51.125],[11.875,51.375],[10.625,51.375],[8.625,50.625],[5.625,49.125],[3.125,47.125],[-3.125,40.625],[-3.125,40.375]]],["AGA","BOR",[[30.375,-9.875],[31.125,-10.125],[42.875,-9.625],[45.625,-6.375],[45.625,-1.375],[44.9,-0.6]]],["AGA","BOS",[[30.375,-9.875],[42.375,-70.625]]],["AGA","HRN",[[30.375,-9.875],[31.125,-10.125],[43.875,-9.625],[50.375,-3.125],[50.625,0.625],[53.125,4.625]]],["AGA","MID",[[30.375,-9.875],[31.125,-10.125],[43.875,-9.625],[50.375,-3.125],[50.625,0.625],[51.625,3.125],[51.469,3.531]]],["AGA","SOY",[[30.375,-9.875],[27.875,-13.125],[23.375,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[-5.875,5.375],[-6.125,12.125]]],["AGA","TEN",[[30.375,-9.875],[28.47,-16.25]]],["AGA","VIS",[[30.375,-9.875],[31.125,-10.125],[43.875,-9.625],[50.375,-3.125],[50.625,0.625],[51.375,1.625],[57.875,9.125],[57.875,10.875],[55.375,13.375],[55.375,14.375],[55.875,15.875],[57.63,18.31]]],["ALE","BEI",[[31.375,29.625],[34.125,35.375]]],["ALE","CHS",[[31.375,29.625],[38.4,26.02]]],["ALE","IZM",[[31.375,29.625],[37.875,26.625]]],["ALE","PON",[[31.375,29.625],[37.375,10.125],[36.375,-4.625],[35.875,-5.125],[37.74,-25.67]]],["ALE","THE",[[31.375,29.625],[40.125,22.875]]],["ALE","ZAK",[[31.375,29.625],[35.375,23.375],[36.875,21.375],[37.8,20.75]]],["ALG","DBR",[[36.78,3.06],[37.375,9.625],[36.375,15.125],[39.875,18.625],[42.375,18.125],[42.625,17.875]]],["ALG","LPA",[[36.78,3.06],[36.875,-1.625],[36.625,-2.125],[35.875,-5.625],[34.125,-9.375],[28.13,-15.43]]],["ALG","REY",[[36.78,3.06],[36.875,-1.625],[36.625,-2.125],[35.875,-5.625],[36.625,-8.875],[36.875,-9.125],[64.125,-22.625],[64.375,-22.125]]],["ALG","TUR",[[36.78,3.06],[36.875,-1.625],[36.625,-2.125],[35.875,-5.625],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[43.875,-9.625],[50.375,-3.125],[50.625,0.625],[51.375,1.625],[57.875,9.125],[57.875,10.875],[55.375,13.375],[55.375,14.375],[55.875,15.875],[60.375,22.125]]],["AMB","SYD",[[-3.7,128.18],[-10.625,140.375],[-10.625,142.625],[-11.125,143.125],[-25.375,153.125],[-28.125,153.875],[-32.125,153.375],[-34.125,151.375]]],["AMS","CPT",[[52.875,4.375],[50.625,0.625],[48.875,-4.625],[33.125,-17.625],[14.625,-17.625],[12.125,-16.875],[-34.125,18.125]]],["AMS","FNC",[[52.875,4.375],[50.625,0.625],[48.875,-4.625],[34.125,-16.875],[32.65,-16.92]]],["AMS","GDA",[[52.875,4.375],[57.875,9.125],[57.875,10.875],[55.375,13.375],[54.875,18.625],[54.625,18.875]]],["AMS","LIS",[[52.875,4.375],[50.625,0.625],[48.875,-4.625],[42.625,-9.875],[38.875,-9.875],[38.625,-9.625]]],["AMS","MID",[[52.875,4.375],[51.875,3.625],[51.469,3.531]]],["AMS","PLY",[[52.875,4.375],[50.625,0.625],[50.125,-4.125]]],["AMS","STO",[[52.875,4.375],[57.875,9.125],[57.875,10.875],[55.375,13.375],[55.375,14.375],[55.875,15.875],[56.375,16.375],[59.125,18.375],[59.375,18.375]]],["AMS","TAL",[[52.875,4.375],[57.875,9.125],[57.875,10.875],[55.375,13.375],[55.375,14.375],[58.375,23.375],[59.447,24.729]]],["ANC","DBR",[[43.62,13.52],[42.625,17.875]]],["ANC","HER",[[43.62,13.52],[40.875,18.125],[37.625,21.125],[36.875,21.375],[36.375,22.125],[35.625,25.125]]],["ANC","IST",[[43.62,13.52],[40.875,18.125],[37.625,21.125],[36.875,21.375],[36.375,22.125],[36.375,23.125],[39.875,26.375],[40.375,26.875],[40.875,28.375],[40.875,28.875]]],["ANC","VEN",[[43.62,13.52],[45.375,12.625]]],["ANG","LIS",[[38.66,-27.22],[38.625,-9.625]]],["ANG","QUE",[[38.66,-27.22],[47.375,-59.375],[49.125,-64.625],[48.625,-67.625],[48.125,-69.375],[46.875,-70.875],[46.8,-71.2]]],["ANG","STG",[[38.66,-27.22],[32.38,-64.68]]],["ANG","TRI",[[38.66,-27.22],[35.875,-5.125],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.375],[35.625,34.125],[34.375,35.625]]],["ANG","VIS",[[38.66,-27.22],[58.875,-5.125],[58.375,5.875],[58.125,6.125],[57.875,7.375],[57.875,10.875],[55.375,13.375],[55.375,14.375],[55.875,15.875],[57.63,18.31]]],["ANT","COR",[[36.625,30.875],[36.125,30.375],[36.375,22.125],[36.875,21.375],[39.375,19.875],[39.62,19.92]]],["ANT","SAF",[[36.625,30.875],[36.125,30.375],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[35.875,-6.375],[33.125,-9.125],[32.625,-9.375]]],["ARI","CLL",[[-18.375,-70.625],[-17.375,-73.625],[-13.625,-77.375],[-12.125,-77.375]]],["ARI","COQ",[[-18.375,-70.625],[-29.625,-71.625],[-29.875,-71.625]]],["ARI","PAN",[[-18.375,-70.625],[-17.375,-73.625],[-9.375,-81.625],[6.125,-81.375],[7.625,-79.875],[8.625,-79.375],[8.875,-79.375]]],["ARI","VLP",[[-18.375,-70.625],[-31.625,-71.875],[-33.125,-71.875]]],["ARK","CLS",[[64.875,40.125],[65.625,39.875],[66.875,41.125],[67.625,41.125],[71.375,37.125],[71.125,13.875],[59.125,1.875],[51.125,1.875]]],["ARK","LAG",[[64.875,40.125],[65.625,39.875],[66.875,41.125],[67.625,41.125],[71.375,37.125],[71.125,7.125],[46.625,-17.375],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[6.125,3.375]]],["ARK","ROT",[[64.875,40.125],[65.625,39.875],[66.875,41.125],[67.625,41.125],[71.375,37.125],[71.125,13.875],[61.125,3.875],[52.125,3.875]]],["ARK","TRO",[[64.875,40.125],[65.625,39.875],[66.875,41.125],[67.625,41.125],[71.375,37.125],[71.125,16.625],[64.125,9.625]]],["ARK","VAR",[[64.875,40.125],[65.625,39.875],[66.875,41.125],[67.625,41.125],[70.375,38.125],[70.37,31.11]]],["ARP","ANG",[[51.203,4.389],[51.625,3.125],[41.625,-24.125],[38.66,-27.22]]],["ARP","BOR",[[51.203,4.389],[51.625,3.125],[48.875,-4.625],[48.625,-4.875],[48.125,-4.875],[45.375,-1.125],[44.9,-0.6]]],["ARP","DUB",[[51.203,4.389],[51.625,3.125],[50.625,0.375],[49.875,-5.625],[50.125,-5.875],[53.375,-5.875]]],["ARP","HAM",[[51.203,4.389],[51.375,3.875],[51.625,3.625],[52.375,3.875],[53.875,5.375],[53.875,9.125],[53.625,9.375],[53.5,9.9]]],["ARP","LON",[[51.203,4.389],[51.625,3.125],[51.5,-0.1]]],["AYU","GUA",[[14.36,100.6],[12.875,100.625],[8.375,105.125],[8.875,105.875],[11.125,108.875],[11.625,109.375],[22.125,113.625],[22.875,113.625],[23.1,113.3]]],["AYU","HON",[[14.36,100.6],[12.875,100.625],[8.375,105.125],[8.875,105.875],[11.125,108.875],[11.625,109.375],[22.125,114.125]]],["AYU","MAL",[[14.36,100.6],[12.875,100.625],[2.625,104.375],[1.375,104.375],[1.125,104.125],[1.625,102.625],[2.125,102.125]]],["AYU","NAG",[[14.36,100.6],[12.875,100.625],[8.375,105.125],[8.875,105.875],[11.125,108.875],[11.625,109.375],[24.375,120.375],[32.375,128.375],[32.625,129.625]]],["AYU","PTT",[[14.36,100.6],[6.87,101.25]]],["AYU","THA",[[14.36,100.6],[12.875,100.625],[2.625,104.375],[1.375,104.375],[1.125,104.125],[1.625,102.625],[2.375,101.625],[2.875,101.125],[8.125,97.875],[16.77,96.2]]],["BAN","MUM",[[5.55,95.32],[5.875,80.375],[8.125,77.125],[8.875,76.375],[13.375,74.375],[16.375,73.125],[19.125,72.625]]],["BAN","NIN",[[5.55,95.32],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[28.625,122.125],[29.875,122.375],[30.125,121.875]]],["BAR","ACC",[[41.125,2.125],[37.375,-0.625],[36.625,-2.125],[35.625,-6.625],[24.625,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[5.375,-0.125]]],["BAR","ELM",[[41.125,2.125],[37.375,-0.625],[36.625,-2.125],[35.625,-6.625],[24.625,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[4.875,-1.125]]],["BAR","GOA",[[41.125,2.125],[44.125,8.875]]],["BAR","VAL",[[41.125,2.125],[39.375,0.125]]],["BAS","BSR",[[26.875,56.375],[26.375,54.875],[26.625,53.625],[27.875,51.375],[30.5,47.9]]],["BAS","KOC",[[26.875,56.375],[25.625,57.375],[9.875,76.125]]],["BEI","CAD",[[34.125,35.375],[36.375,19.625],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[35.875,-5.875],[36.375,-6.375]]],["BEI","IST",[[34.125,35.375],[34.375,32.875],[36.625,27.625],[38.125,26.125],[39.625,26.125],[40.125,26.625],[40.625,27.375],[40.875,28.875]]],["BEI","IZM",[[34.125,35.375],[34.375,32.875],[36.625,27.625],[37.375,26.875],[37.875,26.625]]],["BEI","SAI",[[34.125,35.375],[36.375,19.625],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[35.875,-6.375],[24.875,-17.375],[21.125,-17.375],[16.375,-16.875],[16.125,-16.625]]],["BEI","TAN",[[34.125,35.375],[36.375,19.625],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[35.77,-5.8]]],["BEL","BUE",[[-1.4,-48.5],[-0.625,-47.625],[-0.625,-46.875],[-2.625,-39.875],[-5.125,-35.375],[-5.625,-34.875],[-7.625,-34.375],[-20.875,-39.625],[-35.125,-53.875],[-34.875,-57.875],[-34.625,-58.125],[-34.605,-58.382]]],["BEL","MLG",[[-1.4,-48.5],[-0.125,-47.125],[35.875,-6.125],[35.875,-5.125],[36.625,-4.125]]],["BEL","PAR",[[-1.4,-48.5],[0.125,-48.375],[4.125,-51.125],[5.875,-52.875],[6.125,-55.125]]],["BEL","SVQ",[[-1.4,-48.5],[-0.125,-47.125],[37.125,-6.125],[37.394,-6.003]]],["BEL","WIL",[[-1.4,-48.5],[0.125,-48.375],[4.125,-51.125],[12.125,-59.125],[12.11,-68.93]]],["BER","ARK",[[60.375,4.875],[62.125,4.875],[71.375,14.875],[71.375,37.375],[67.625,41.125],[66.875,41.125],[65.375,39.875],[64.875,40.125]]],["BER","BOR",[[60.375,4.875],[52.125,1.875],[50.875,1.125],[48.875,-4.625],[48.625,-4.875],[48.125,-4.875],[45.375,-1.125],[44.9,-0.6]]],["BER","GDA",[[60.375,4.875],[58.625,5.375],[58.375,5.625],[57.875,7.125],[57.875,10.875],[55.375,13.375],[54.875,18.625],[54.625,18.875]]],["BER","HAM",[[60.375,4.875],[58.625,5.375],[53.875,8.625],[53.5,9.9]]],["BER","LUB",[[60.375,4.875],[58.625,5.375],[58.375,5.625],[57.875,7.125],[57.875,10.375],[57.125,11.125],[56.375,11.125],[55.625,10.625],[54.125,11.125]]],["BER","STA",[[60.375,4.875],[51.875,-47.625],[46.625,-52.875],[29.875,-81.125]]],["BER","TUR",[[60.375,4.875],[58.625,5.375],[58.375,5.625],[57.875,7.125],[57.875,10.875],[55.375,13.375],[55.375,14.375],[55.875,15.875],[60.375,22.125]]],["BIL","BRU",[[43.625,-2.875],[48.125,-4.875],[48.625,-4.875],[50.375,-2.625],[50.625,0.625],[51.375,2.375],[51.375,3.125]]],["BIL","LEI",[[43.625,-2.875],[48.125,-4.875],[48.625,-4.875],[50.375,-2.625],[50.625,0.625],[51.125,1.375],[52.125,1.875],[52.625,1.875],[56.125,-2.125],[56.125,-2.625]]],["BIL","LIS",[[43.625,-2.875],[43.875,-8.625],[42.625,-9.875],[38.875,-9.875],[38.625,-9.625]]],["BIL","NAN",[[43.625,-2.875],[46.875,-2.125],[47.2,-1.7]]],["BIL","SAF",[[43.625,-2.875],[43.875,-8.625],[42.625,-9.875],[38.875,-9.875],[32.625,-9.375]]],["BND","JEJ",[[-4.51,129.9],[-3.625,130.875],[-0.625,130.375],[33.51,126.52]]],["BNT","AYU",[[-5.875,106.125],[-1.125,106.375],[12.875,100.625],[14.36,100.6]]],["BNT","BAR",[[-5.875,106.125],[-34.875,23.625],[-34.875,18.875],[-4.125,-10.625],[12.875,-17.125],[14.875,-17.625],[25.125,-17.125],[35.875,-6.375],[35.875,-5.125],[36.625,-1.875],[37.625,-0.375],[41.125,2.125]]],["BNT","MAK",[[-5.875,106.125],[-4.875,119.375]]],["BNT","SUR",[[-5.875,106.125],[-5.875,107.625],[-6.625,112.375],[-7.125,112.875]]],["BNT","THA",[[-5.875,106.125],[-3.125,106.375],[-2.375,105.875],[0.375,103.875],[2.125,102.125],[2.125,101.875],[2.875,101.125],[8.125,97.875],[16.77,96.2]]],["BOR","ARP",[[44.9,-0.6],[47.625,-3.625],[47.875,-4.625],[48.125,-4.875],[48.625,-4.875],[50.375,-2.625],[50.625,0.625],[51.625,3.125],[51.203,4.389]]],["BOR","DUB",[[44.9,-0.6],[47.625,-3.625],[47.875,-4.625],[48.125,-4.875],[50.125,-5.875],[53.375,-5.875]]],["BOR","GIB",[[44.9,-0.6],[45.625,-1.375],[43.625,-8.875],[42.625,-9.875],[38.875,-9.875],[36.875,-9.125],[36.625,-8.875],[35.875,-5.375]]],["BOR","LAR",[[44.9,-0.6],[46.033,-1.487]]],["BOR","LNG",[[44.9,-0.6],[47.625,-3.625],[47.875,-4.625],[48.125,-4.875],[50.125,-5.875],[55.125,-5.625],[55.375,-5.875],[57.125,-6.375],[58.375,-5.625],[77.125,14.125],[77.125,14.375]]],["BOR","NAN",[[44.9,-0.6],[46.875,-2.125],[47.2,-1.7]]],["BOR","OUI",[[44.9,-0.6],[45.625,-1.375],[43.625,-8.875],[34.375,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[6.125,2.125]]],["BOS","BEI",[[42.375,-70.625],[35.875,-5.125],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.375],[35.375,31.625],[34.625,32.375],[34.375,33.125],[34.125,35.375]]],["BOS","GIB",[[42.375,-70.625],[35.875,-5.375]]],["BOS","NEW",[[42.375,-70.625],[42.375,-70.125],[41.875,-69.625],[41.375,-70.125],[40.625,-72.375],[40.625,-73.875]]],["BOS","PRT",[[42.375,-70.625],[42.375,-70.125],[41.875,-69.625],[20.125,-74.125],[9.55,-79.65]]],["BOS","REY",[[42.375,-70.625],[43.375,-65.125],[46.625,-52.875],[64.375,-22.125]]],["BOS","SAN",[[42.375,-70.625],[42.375,-70.125],[38.125,-66.125],[18.625,-66.125]]],["BRI","CID",[[13.1,-59.62],[14.92,-23.6]]],["BRI","CUM",[[13.1,-59.62],[10.875,-64.125]]],["BRI","QUE",[[13.1,-59.62],[46.125,-59.625],[49.125,-62.625],[49.125,-65.375],[48.875,-65.875],[48.375,-69.125],[47.625,-69.875],[46.875,-70.875],[46.8,-71.2]]],["BRI","STJ",[[13.1,-59.62],[47.625,-52.375]]],["BRI","TAN",[[13.1,-59.62],[35.77,-5.8]]],["BRS","CAP",[[51.45,-2.6],[51.375,-4.625],[38.375,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[4.875,-1.125]]],["BRS","CAR",[[51.45,-2.6],[47.375,-38.875],[10.625,-75.625]]],["BRS","DUB",[[51.45,-2.6],[51.375,-5.125],[51.625,-5.375],[53.375,-5.875]]],["BRS","GDA",[[51.45,-2.6],[51.375,-4.625],[50.375,-5.625],[50.125,-5.875],[49.875,-5.625],[50.625,0.625],[51.375,1.625],[57.875,9.125],[57.875,10.875],[55.375,13.375],[54.875,18.625],[54.625,18.875]]],["BRS","LIS",[[51.45,-2.6],[51.375,-4.625],[46.125,-9.875],[38.875,-9.875],[38.625,-9.625]]],["BRS","SET",[[51.45,-2.6],[51.375,-4.625],[46.125,-9.875],[38.875,-9.875],[38.125,-9.375],[38.125,-9.125]]],["BRU","CLS",[[51.375,3.125],[51.125,1.875]]],["BRU","COP",[[51.375,3.125],[54.375,5.625],[57.875,9.125],[57.875,10.625],[55.728,12.823]]],["BRU","LAR",[[51.375,3.125],[51.125,1.375],[50.625,0.625],[48.875,-4.625],[48.625,-4.875],[48.125,-4.875],[47.875,-4.625],[46.033,-1.487]]],["BRU","RIG",[[51.375,3.125],[54.375,5.625],[57.875,9.125],[57.875,10.875],[55.375,13.375],[55.375,14.375],[57.875,22.375],[57.625,23.125],[56.919,23.984]]],["BRU","STJ",[[51.375,3.125],[51.125,1.375],[50.625,0.625],[49.875,-5.875],[47.625,-52.375]]],["BSR","CHI",[[30.5,47.9],[27.625,51.625],[26.625,53.625],[26.375,54.875],[26.375,56.625],[25.625,57.375],[7.875,77.375],[7.875,77.875],[22.125,91.625]]],["BSR","DIU",[[30.5,47.9],[27.625,51.625],[26.625,53.625],[26.375,54.875],[26.375,56.625],[25.625,57.375],[20.625,70.375],[20.71,70.98]]],["BSR","HOR",[[30.5,47.9],[27.625,51.625],[26.625,53.625],[26.375,54.875],[26.875,56.375]]],["BSR","KAR",[[30.5,47.9],[27.625,51.625],[26.625,53.625],[26.375,54.875],[26.375,56.625],[25.625,57.375],[24.875,61.625],[24.625,66.875]]],["BSR","MUS",[[30.5,47.9],[27.625,51.625],[26.625,53.625],[26.375,54.875],[26.375,56.375],[23.625,58.875]]],["BUE","SOS",[[-34.605,-58.382],[-35.125,-54.375],[-27.125,-46.375],[-24.125,-46.375]]],["BUS","FUZ",[[35.125,129.375],[25.625,119.625]]],["BUS","HAN",[[35.125,129.375],[23.875,118.125],[22.625,116.125],[20.125,110.375],[20.375,106.625]]],["BUS","HIR",[[35.125,129.375],[33.375,129.375]]],["BUS","MAT",[[35.125,129.375],[41.43,140.11]]],["BUV","HUA",[[3.875,-77.375],[15.625,-96.125]]],["BUV","PAI",[[3.875,-77.375],[0.625,-80.625],[-1.375,-81.125],[-4.875,-81.625],[-5.125,-81.375]]],["BUV","PAN",[[3.875,-77.375],[8.875,-79.375]]],["BUV","REA",[[3.875,-77.375],[10.125,-86.125],[12.375,-87.375]]],["CAD","BAR",[[36.375,-6.375],[35.875,-5.875],[35.875,-5.125],[36.625,-1.875],[37.625,-0.375],[41.125,2.125]]],["CAD","CAR",[[36.375,-6.375],[11.625,-74.625],[10.625,-75.625]]],["CAD","FNC",[[36.375,-6.375],[32.65,-16.92]]],["CAD","LIS",[[36.375,-6.375],[36.625,-8.875],[36.875,-9.125],[38.625,-9.625]]],["CAD","LPA",[[36.375,-6.375],[28.13,-15.43]]],["CAD","LUB",[[36.375,-6.375],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[43.875,-9.625],[50.375,-3.125],[50.625,0.625],[51.375,1.625],[57.875,9.125],[57.875,10.375],[57.125,11.125],[56.375,11.125],[55.625,10.625],[54.125,11.125]]],["CAD","NAN",[[36.375,-6.375],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[42.875,-9.625],[46.875,-4.875],[46.875,-2.125],[47.2,-1.7]]],["CAD","SET",[[36.375,-6.375],[36.625,-8.875],[36.875,-9.125],[38.125,-9.125]]],["CAD","SNL",[[36.375,-6.375],[36.8,-6.4]]],["CAG","IZM",[[39.125,9.375],[37.375,12.375],[36.375,15.375],[36.375,23.125],[37.875,26.625]]],["CAG","LIV",[[39.125,9.375],[39.375,9.875],[40.625,10.125],[43.625,10.125]]],["CAG","TRP",[[39.125,9.375],[34.625,13.375],[32.875,13.375]]],["CAG","VAL",[[39.125,9.375],[38.875,8.375],[39.375,0.125]]],["CAL","CPT",[[4.375,8.375],[-26.125,10.125],[-34.125,18.125]]],["CAL","LUA",[[4.375,8.375],[-4.375,8.875],[-8.625,12.875]]],["CAL","PLY",[[4.375,8.375],[4.125,5.625],[4.125,-8.125],[4.875,-9.375],[7.375,-12.875],[12.125,-16.875],[14.875,-17.625],[37.875,-16.375],[50.125,-4.125]]],["CAL","SLV",[[4.375,8.375],[-13.125,-38.375]]],["CAP","AGA",[[4.875,-1.125],[4.625,-1.875],[4.125,-8.125],[4.875,-9.375],[7.375,-12.875],[12.125,-16.875],[14.875,-17.625],[23.875,-17.125],[30.375,-10.625],[30.375,-9.875]]],["CAP","ISL",[[4.875,-1.125],[-33.875,17.875],[-34.875,18.875],[-34.375,27.125],[-20.625,40.875],[-15.125,40.875]]],["CAP","REC",[[4.875,-1.125],[-8.125,-34.625]]],["CAP","ROT",[[4.875,-1.125],[4.625,-1.875],[4.125,-8.125],[4.875,-9.375],[7.375,-12.875],[12.125,-16.875],[14.875,-17.625],[37.125,-16.375],[50.375,-3.125],[50.625,0.625],[52.125,3.875]]],["CAR","PAR",[[10.625,-75.625],[12.625,-73.625],[12.125,-61.375],[6.125,-55.125]]],["CAR","PON",[[10.625,-75.625],[37.625,-48.375],[37.74,-25.67]]],["CAR","PRT",[[10.625,-75.625],[9.55,-79.65]]],["CAR","SOS",[[10.625,-75.625],[12.625,-73.625],[11.625,-52.125],[-5.625,-34.875],[-7.625,-34.375],[-20.875,-39.625],[-24.125,-42.875],[-24.125,-46.375]]],["CEB","HON",[[10.375,124.125],[9.625,123.625],[9.375,123.625],[8.875,123.125],[8.875,122.875],[9.625,122.125],[22.125,114.125]]],["CEB","HOO",[[10.375,124.125],[9.625,123.625],[9.375,123.625],[8.875,123.125],[4.625,107.625],[1.125,104.125],[1.625,102.625],[2.375,101.625],[2.875,101.125],[21.875,88.125],[22.375,88.125],[22.9,88.4]]],["CEB","KOL",[[10.375,124.125],[9.625,123.625],[9.375,123.625],[8.875,123.125],[4.625,107.625],[1.125,104.125],[1.625,102.625],[5.875,96.375],[5.875,80.375],[8.125,77.125],[8.875,76.375]]],["CEB","MNL",[[10.375,124.125],[9.625,123.625],[9.375,123.625],[8.875,123.125],[8.875,122.875],[9.625,122.125],[13.375,120.125],[14.375,120.625]]],["CEU","ARK",[[35.89,-5.3],[35.875,-5.875],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[53.875,-10.125],[71.375,7.625],[71.375,37.375],[67.625,41.125],[66.875,41.125],[65.375,39.875],[64.875,40.125]]],["CEU","COP",[[35.89,-5.3],[35.875,-5.875],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[43.875,-9.625],[50.375,-3.125],[50.625,0.625],[51.375,1.625],[57.875,9.125],[57.875,10.625],[55.728,12.823]]],["CEU","RHO",[[35.89,-5.3],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.375],[36.43,28.22]]],["CEU","TOR",[[35.89,-5.3],[35.875,-5.875],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[58.875,-10.125],[62.01,-6.77]]],["CHE","HOO",[[12.875,80.375],[20.875,87.375],[21.875,88.125],[22.375,88.125],[22.9,88.4]]],["CHE","MCH",[[12.875,80.375],[13.625,80.625],[16.125,81.375]]],["CHE","TSU",[[12.875,80.375],[3.875,100.125],[2.125,101.875],[1.375,103.125],[1.125,104.125],[26.875,122.125],[34.2,129.29]]],["CHI","CHE",[[22.125,91.625],[12.875,80.375]]],["CHI","MCH",[[22.125,91.625],[16.125,81.875],[16.125,81.375]]],["CHI","TER",[[22.125,91.625],[20.625,92.125],[16.125,93.875],[8.125,97.875],[2.875,101.125],[2.125,101.875],[1.375,103.125],[1.125,104.125],[7.125,116.625],[6.125,121.625],[0.875,127.125]]],["CHS","ALE",[[38.4,26.02],[31.375,29.625]]],["CHS","IST",[[38.4,26.02],[39.625,26.125],[40.125,26.625],[40.625,27.375],[40.875,28.875]]],["CHS","SPL",[[38.4,26.02],[36.375,23.125],[36.375,22.125],[36.875,21.375],[42.875,16.625],[43.375,16.125]]],["CHS","THE",[[38.4,26.02],[40.125,22.875]]],["CHS","TRP",[[38.4,26.02],[36.375,23.125],[32.875,13.375]]],["CID","BOR",[[14.92,-23.6],[42.875,-9.625],[45.625,-6.375],[45.625,-1.375],[44.9,-0.6]]],["CID","CEU",[[14.92,-23.6],[32.125,-10.125],[35.875,-6.375],[35.89,-5.3]]],["CID","GIB",[[14.92,-23.6],[32.125,-10.125],[35.875,-6.375],[35.875,-5.375]]],["CID","LUB",[[14.92,-23.6],[44.875,-8.625],[50.375,-3.125],[50.625,0.625],[51.375,1.625],[57.875,9.125],[57.875,10.375],[57.125,11.125],[56.375,11.125],[55.625,10.625],[54.125,11.125]]],["CID","PLM",[[14.92,-23.6],[32.125,-10.125],[35.875,-6.375],[35.875,-5.125],[36.625,-1.875],[39.625,2.625],[39.57,2.65]]],["CID","SAI",[[14.92,-23.6],[16.125,-16.625]]],["CLL","ARI",[[-12.125,-77.375],[-14.375,-76.625],[-18.375,-72.375],[-18.375,-70.625]]],["CLL","BUV",[[-12.125,-77.375],[-5.625,-81.625],[-4.375,-81.625],[-1.125,-81.125],[0.625,-80.375],[2.875,-78.375],[3.875,-77.375]]],["CLL","GYE",[[-12.125,-77.375],[-5.625,-81.625],[-4.375,-81.625],[-2.375,-79.875],[-2.19,-79.89]]],["CLL","MNL",[[-12.125,-77.375],[12.625,124.875],[12.625,124.375],[12.375,124.125],[12.375,123.875],[13.625,121.125],[13.625,120.625],[13.875,120.375],[14.375,120.625]]],["CLL","PAI",[[-12.125,-77.375],[-6.125,-81.375],[-5.125,-81.375]]],["CLS","AMS",[[51.125,1.875],[52.875,4.375]]],["CLS","BIL",[[51.125,1.875],[48.875,-4.625],[48.625,-4.875],[48.125,-4.875],[43.625,-2.875]]],["CLS","SAF",[[51.125,1.875],[48.875,-4.625],[42.625,-9.875],[38.875,-9.875],[32.625,-9.375]]],["COL","AMS",[[6.875,79.625],[-34.875,37.375],[-34.875,18.875],[-4.125,-10.625],[12.875,-17.125],[14.875,-17.625],[37.125,-16.375],[50.375,-3.125],[50.625,0.625],[52.875,4.375]]],["COL","CHE",[[6.875,79.625],[8.625,79.375],[10.625,80.125],[12.875,80.375]]],["COL","HAD",[[6.875,79.625],[12.65,54.03]]],["COL","MUM",[[6.875,79.625],[7.875,77.375],[8.875,76.375],[13.375,74.375],[16.375,73.125],[19.125,72.625]]],["COL","NAM",[[6.875,79.625],[6.375,79.875],[5.875,80.375],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[28.625,122.125],[38.125,124.375],[38.625,124.875]]],["CON","ARI",[[-36.625,-73.125],[-18.375,-70.625]]],["CON","REC",[[-36.625,-73.125],[-37.375,-73.875],[-46.875,-75.875],[-51.875,-75.875],[-55.625,-72.125],[-55.625,-65.625],[-21.625,-34.625],[-8.125,-34.625]]],["COP","LAR",[[55.728,12.823],[57.875,10.375],[56.625,6.875],[50.875,1.125],[48.875,-4.625],[48.625,-4.875],[48.125,-4.875],[47.875,-4.625],[46.033,-1.487]]],["COP","LEH",[[55.728,12.823],[57.875,10.375],[56.625,6.875],[50.875,1.125],[49.625,-0.375]]],["COP","LNG",[[55.728,12.823],[57.875,10.375],[57.875,6.875],[58.375,5.625],[59.125,5.125],[60.875,4.875],[68.125,5.375],[77.125,14.375]]],["COP","LON",[[55.728,12.823],[57.875,10.375],[56.375,6.125],[51.875,1.625],[51.375,-0.125],[51.5,-0.1]]],["COP","NAN",[[55.728,12.823],[57.875,10.375],[56.625,6.875],[50.875,1.125],[48.875,-4.625],[48.625,-4.875],[48.125,-4.875],[47.875,-4.625],[47.125,-2.375],[47.2,-1.7]]],["COP","RIG",[[55.728,12.823],[55.375,13.875],[55.375,14.375],[57.875,22.375],[57.625,23.125],[56.919,23.984]]],["COP","TRO",[[55.728,12.823],[57.875,10.375],[57.875,6.875],[58.375,5.625],[59.125,5.125],[60.875,4.875],[62.125,4.875],[64.125,6.875],[64.125,9.625]]],["COP","TUR",[[55.728,12.823],[55.375,13.875],[55.375,14.375],[55.875,15.875],[60.375,22.125]]],["COQ","ARI",[[-29.875,-71.625],[-28.375,-71.625],[-18.375,-70.625]]],["COQ","CID",[[-29.875,-71.625],[-37.625,-73.875],[-46.875,-75.875],[-51.875,-75.875],[-55.625,-72.125],[-55.625,-65.625],[-11.125,-24.375],[14.92,-23.6]]],["COQ","VLP",[[-29.875,-71.625],[-31.125,-71.875],[-33.125,-71.875]]],["COR","ANC",[[39.62,19.92],[43.625,13.625],[43.62,13.52]]],["COR","FAM",[[39.62,19.92],[38.875,20.375],[36.875,21.375],[36.375,22.125],[35.625,34.125],[35.125,34.125]]],["COR","IST",[[39.62,19.92],[38.875,20.375],[36.875,21.375],[36.375,22.125],[36.375,23.125],[39.875,26.375],[40.375,26.875],[40.875,28.375],[40.875,28.875]]],["COR","PAT",[[39.62,19.92],[38.875,20.375],[37.625,21.125]]],["COR","VAL",[[39.62,19.92],[36.375,15.125],[39.375,0.125]]],["CPT","ADE",[[-34.125,18.125],[-34.875,19.375],[-33.875,27.625],[-17.875,43.625],[-17.375,43.625],[10.875,51.375],[11.875,51.375],[12.625,50.375],[12.625,45.125]]],["CPT","COL",[[-34.125,18.125],[-34.875,19.375],[-32.375,40.375],[6.875,79.625]]],["CPT","GOA",[[-34.125,18.125],[12.125,-16.875],[14.875,-17.625],[25.125,-17.125],[35.875,-6.375],[35.875,-5.125],[36.625,-1.875],[37.625,-0.375],[44.125,8.875]]],["CPT","MAL",[[-34.125,18.125],[-34.875,19.375],[-30.125,59.625],[5.625,95.375],[5.375,98.625],[2.125,101.875],[2.125,102.125]]],["CPT","OLD",[[-34.125,18.125],[-34.875,19.375],[-33.875,27.625],[-17.875,43.625],[-17.375,43.625],[-16.375,44.125],[15.625,73.625]]],["CPT","RIO",[[-34.125,18.125],[-23.125,-43.125]]],["CPT","VLL",[[-34.125,18.125],[12.125,-16.875],[14.875,-17.625],[25.125,-17.125],[35.875,-6.375],[35.875,-5.125],[37.375,6.375],[37.375,12.875],[35.9,14.51]]],["CRK","BEI",[[51.625,-8.375],[40.125,-9.875],[38.875,-9.875],[36.875,-9.125],[36.625,-8.875],[35.875,-5.375],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.375],[35.375,31.625],[34.625,32.375],[34.375,33.125],[34.125,35.375]]],["CRK","BRS",[[51.625,-8.375],[51.375,-2.625],[51.45,-2.6]]],["CRK","COP",[[51.625,-8.375],[49.875,-5.625],[50.625,0.625],[51.375,1.625],[57.875,9.125],[57.875,10.625],[55.728,12.823]]],["CRK","DUB",[[51.625,-8.375],[51.875,-7.125],[52.625,-6.125],[53.375,-5.875]]],["CRK","IZM",[[51.625,-8.375],[40.125,-9.875],[38.875,-9.875],[36.875,-9.125],[36.625,-8.875],[35.875,-5.375],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.375],[36.375,23.125],[37.875,26.625]]],["CRK","PAT",[[51.625,-8.375],[40.125,-9.875],[38.875,-9.875],[36.875,-9.125],[36.625,-8.875],[35.875,-5.375],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.125],[37.625,21.125]]],["CUM","BEL",[[10.875,-64.125],[11.125,-58.625],[4.625,-51.625],[1.625,-48.625],[-0.875,-48.375],[-1.4,-48.5]]],["CUM","BOS",[[10.875,-64.125],[41.875,-69.625],[42.375,-70.125],[42.375,-70.625]]],["CUM","SAN",[[10.875,-64.125],[18.375,-65.375],[18.625,-65.625],[18.625,-66.125]]],["CUM","STJ",[[10.875,-64.125],[47.625,-52.375]]],["DBR","COR",[[42.625,17.875],[40.125,19.375],[39.62,19.92]]],["DBR","FAM",[[42.625,17.875],[40.125,19.375],[36.625,21.625],[36.375,22.375],[35.625,34.125],[35.125,34.125]]],["DBR","TRI",[[42.625,17.875],[40.125,19.375],[36.625,21.625],[36.375,22.375],[35.625,34.125],[34.375,35.625]]],["DIL","PLO",[[-8.375,125.625],[-8.375,125.125],[-20.125,97.125],[-20.16,57.5]]],["DIL","TOK",[[-8.375,125.625],[8.625,126.875],[35.125,140.375]]],["DIU","HOR",[[20.71,70.98],[20.625,70.375],[25.625,57.375],[26.875,56.375]]],["DIU","MNG",[[20.71,70.98],[12.875,74.625]]],["DIU","MUS",[[20.71,70.98],[20.625,70.375],[23.625,58.875]]],["DIU","SRT",[[20.71,70.98],[20.625,71.375],[21.125,72.375]]],["DUB","ARP",[[53.375,-5.875],[50.125,-5.875],[49.875,-5.625],[50.625,0.625],[51.625,3.125],[51.203,4.389]]],["DUB","BER",[[53.375,-5.875],[54.625,-5.625],[57.125,-6.375],[58.375,-5.625],[60.375,-3.375],[60.375,4.875]]],["DUB","CAP",[[53.375,-5.875],[52.625,-6.125],[20.625,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[4.875,-1.125]]],["DUB","CRK",[[53.375,-5.875],[52.625,-6.125],[51.875,-7.125],[51.625,-8.375]]],["DUB","HRN",[[53.375,-5.875],[50.125,-5.875],[49.875,-5.625],[50.625,0.625],[53.125,4.625]]],["DUB","PLY",[[53.375,-5.875],[50.125,-5.875],[49.875,-5.625],[50.125,-4.125]]],["DUB","VIS",[[53.375,-5.875],[54.625,-5.625],[57.125,-6.375],[58.375,-5.625],[58.875,-5.125],[58.375,5.875],[58.125,6.125],[57.875,7.375],[57.875,10.875],[55.375,13.375],[55.375,14.375],[55.875,15.875],[57.63,18.31]]],["ELM","CID",[[4.875,-1.125],[4.625,-1.875],[4.125,-8.125],[4.875,-9.375],[14.92,-23.6]]],["ELM","CPT",[[4.875,-1.125],[-34.125,18.125]]],["ELM","LUA",[[4.875,-1.125],[-8.625,12.875]]],["ELM","REC",[[4.875,-1.125],[-8.125,-34.625]]],["ELM","SAO",[[4.875,-1.125],[0.34,6.73]]],["FAM","CEU",[[35.125,34.125],[35.875,33.875],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.89,-5.3]]],["FAM","FNC",[[35.125,34.125],[35.875,33.875],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[34.375,-15.125],[32.65,-16.92]]],["FAM","HER",[[35.125,34.125],[35.625,33.875],[35.625,25.125]]],["FAM","ZAK",[[35.125,34.125],[35.875,33.875],[36.375,22.125],[36.875,21.375],[37.8,20.75]]],["FEO","ANG",[[44.875,35.375],[41.375,29.375],[40.875,28.875],[40.625,27.375],[40.125,26.625],[36.875,23.375],[36.625,23.375],[36.375,22.875],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[38.66,-27.22]]],["FEO","CAR",[[44.875,35.375],[41.375,29.375],[40.875,28.875],[40.625,27.375],[40.125,26.625],[36.875,23.375],[36.625,23.375],[36.375,22.875],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[27.625,-58.625],[10.625,-75.625]]],["FEO","COR",[[44.875,35.375],[41.375,29.375],[40.875,28.875],[40.625,27.375],[40.125,26.625],[36.875,23.375],[36.625,23.375],[36.375,22.875],[36.375,22.125],[36.875,21.375],[39.375,19.875],[39.62,19.92]]],["FEO","IST",[[44.875,35.375],[41.375,29.375],[40.875,28.875]]],["FEO","VEN",[[44.875,35.375],[41.375,29.375],[40.875,28.875],[40.625,27.375],[40.125,26.625],[36.875,23.375],[36.625,23.375],[36.375,22.875],[36.375,22.125],[36.875,21.375],[40.625,18.375],[45.375,12.625]]],["FNC","ALG",[[32.65,-16.92],[35.875,-5.625],[36.875,2.375],[36.78,3.06]]],["FNC","CEU",[[32.65,-16.92],[35.875,-5.625],[35.89,-5.3]]],["FNC","JAM",[[32.65,-16.92],[37.125,-76.125]]],["FNC","SAL",[[32.65,-16.92],[34.125,-7.125]]],["FUK","AMB",[[33.625,130.125],[33.625,129.625],[32.625,128.875],[-1.875,128.875],[-2.875,127.875],[-3.375,127.625],[-3.625,127.875],[-3.7,128.18]]],["FUK","KAR",[[33.625,130.125],[33.625,129.625],[13.625,109.625],[12.375,109.625],[1.375,104.375],[1.125,104.125],[1.625,102.625],[5.875,96.375],[5.875,80.375],[8.125,77.125],[8.875,76.375],[24.625,66.875]]],["FUK","TAI",[[33.625,130.125],[33.625,129.625],[24.125,120.125],[23.375,119.875],[22.875,119.875]]],["FUZ","HOR",[[25.625,119.625],[24.875,119.125],[1.125,104.125],[1.625,102.625],[5.875,96.375],[5.875,80.375],[8.125,77.125],[25.875,57.125],[26.875,56.375]]],["FUZ","KUP",[[25.625,119.625],[15.375,119.625],[10.625,119.875],[-3.875,118.625],[-5.375,119.125],[-7.875,121.875],[-7.875,122.875],[-8.125,123.125],[-10.125,123.125],[-10.375,123.625]]],["FUZ","OSA",[[25.625,119.625],[30.875,130.875],[33.375,134.625],[33.625,134.875],[34.3,135]]],["FUZ","SHI",[[25.625,119.625],[34.125,130.125],[34.125,130.625]]],["FUZ","TON",[[25.625,119.625],[26.125,120.125],[34.85,128.42]]],["GAL","HOI",[[6.03,80.22],[5.875,81.875],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[1.375,104.375],[12.375,109.625],[14.625,109.625],[15.625,108.875],[16.125,108.375]]],["GAL","MAN",[[6.03,80.22],[8.125,77.125],[26.375,56.375],[26.22,50.58]]],["GAL","OLD",[[6.03,80.22],[8.125,77.125],[8.875,76.375],[13.375,74.375],[15.625,73.625]]],["GDA","AMS",[[54.625,18.875],[55.375,15.625],[55.375,13.375],[57.875,10.375],[57.125,8.375],[52.875,4.375]]],["GDA","HRN",[[54.625,18.875],[55.375,15.625],[55.375,13.375],[57.875,10.375],[57.125,8.375],[53.125,4.625]]],["GDA","LEH",[[54.625,18.875],[55.375,15.625],[55.375,13.375],[57.875,10.375],[56.625,6.875],[50.875,1.125],[49.625,-0.375]]],["GDA","LON",[[54.625,18.875],[55.375,15.625],[55.375,13.375],[57.875,10.375],[56.375,6.125],[51.875,1.625],[51.375,-0.125],[51.5,-0.1]]],["GDA","PTH",[[54.625,18.875],[55.375,15.625],[55.375,13.375],[57.875,10.375],[56.625,6.875],[50.875,1.125],[50.625,0.125],[50.625,-1.125]]],["GDA","TAL",[[54.625,18.875],[57.375,21.375],[58.375,22.375],[58.375,23.375],[59.447,24.729]]],["GDA","VIS",[[54.625,18.875],[57.63,18.31]]],["GIB","ALE",[[35.875,-5.375],[37.375,6.375],[37.375,12.875],[37.125,13.125],[31.375,29.625]]],["GIB","HAM",[[35.875,-5.375],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[43.875,-9.625],[50.375,-3.125],[50.625,0.625],[53.875,5.875],[53.875,9.125],[53.625,9.375],[53.5,9.9]]],["GIB","LNG",[[35.875,-5.375],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[53.875,-10.125],[77.125,13.375],[77.125,14.375]]],["GIB","TEN",[[35.875,-5.375],[35.125,-9.375],[28.47,-16.25]]],["GOA","CAD",[[44.125,8.875],[37.375,-0.625],[36.625,-2.125],[35.875,-5.625],[35.875,-5.875],[36.375,-6.375]]],["GOA","ELM",[[44.125,8.875],[37.375,-0.625],[36.625,-2.125],[35.625,-6.625],[24.625,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[4.875,-1.125]]],["GOA","LAG",[[44.125,8.875],[37.375,-0.625],[36.625,-2.125],[35.625,-6.625],[24.625,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[6.125,3.375]]],["GOA","MES",[[44.125,8.875],[38.375,15.375]]],["GOA","SNL",[[44.125,8.875],[37.375,-0.625],[36.625,-2.125],[35.875,-5.625],[35.875,-5.875],[36.625,-6.625],[36.8,-6.4]]],["GOA","VAL",[[44.125,8.875],[39.375,0.125]]],["GOR","CEU",[[14.625,-17.625],[25.125,-17.125],[35.875,-6.375],[35.89,-5.3]]],["GOR","GIB",[[14.625,-17.625],[25.125,-17.125],[35.875,-6.375],[35.875,-5.375]]],["GOR","PAR",[[14.625,-17.625],[6.125,-55.125]]],["GOR","REY",[[14.625,-17.625],[64.125,-22.625],[64.375,-22.125]]],["GUA","AYU",[[23.1,113.3],[22.625,113.625],[22.125,113.625],[11.625,109.375],[10.875,108.625],[8.625,105.625],[8.375,105.125],[12.875,100.625],[14.36,100.6]]],["GUA","HOI",[[23.1,113.3],[22.625,113.625],[22.125,113.625],[16.125,108.375]]],["GUA","MNG",[[23.1,113.3],[22.625,113.625],[22.125,113.625],[11.625,109.375],[1.375,104.375],[1.125,104.125],[1.625,102.625],[5.875,96.375],[5.875,80.375],[8.125,77.125],[8.875,76.375],[12.625,74.625],[12.875,74.625]]],["GUA","NAH",[[23.1,113.3],[22.375,113.875],[22.125,114.125],[22.625,116.125],[26.125,122.875],[26.21,127.68]]],["GUA","XIA",[[23.1,113.3],[22.375,113.875],[22.125,114.125],[22.625,116.125],[24.125,118.375]]],["GYE","BUV",[[-2.19,-79.89],[-2.625,-80.125],[-2.875,-80.375],[-2.375,-81.125],[-1.125,-81.125],[0.625,-80.375],[2.875,-78.375],[3.875,-77.375]]],["GYE","CLL",[[-2.19,-79.89],[-3.375,-80.625],[-4.375,-81.625],[-8.375,-80.875],[-12.125,-77.375]]],["GYE","PAN",[[-2.19,-79.89],[-2.625,-80.125],[-2.875,-80.375],[-2.375,-81.125],[7.125,-80.375],[7.625,-79.875],[8.625,-79.375],[8.875,-79.375]]],["GYE","REA",[[-2.19,-79.89],[-2.625,-80.125],[-2.875,-80.375],[-2.375,-81.125],[12.375,-87.375]]],["HAD","KIL",[[12.65,54.03],[-8.98,39.52]]],["HAD","MOC",[[12.65,54.03],[12.375,43.875],[13.125,43.125]]],["HAD","SUA",[[12.65,54.03],[12.375,43.875],[13.375,42.875],[19.375,37.375]]],["HAD","ZAN",[[12.65,54.03],[4.625,48.375],[-3.375,41.625],[-6.17,39.2]]],["HAG","BNT",[[13.48,144.75],[-5.625,123.125],[-5.875,122.375],[-5.875,106.125]]],["HAG","SRT",[[13.48,144.75],[12.375,121.625],[12.125,121.375],[7.625,110.625],[1.125,104.125],[1.625,102.625],[5.875,96.375],[5.875,80.375],[8.125,77.125],[8.875,76.375],[13.375,74.375],[16.375,73.125],[19.125,72.625],[21.125,72.375]]],["HAM","BIL",[[53.5,9.9],[53.875,8.625],[53.625,3.875],[50.875,1.125],[48.875,-4.625],[48.625,-4.875],[48.125,-4.875],[43.625,-2.875]]],["HAM","BRU",[[53.5,9.9],[53.875,8.625],[53.625,5.125],[51.625,3.125],[51.375,3.125]]],["HAM","LEH",[[53.5,9.9],[53.875,8.625],[53.625,3.875],[50.875,1.125],[49.625,-0.375]]],["HAM","LON",[[53.5,9.9],[53.875,8.625],[53.625,3.375],[51.875,1.625],[51.375,-0.125],[51.5,-0.1]]],["HAM","LUB",[[53.5,9.9],[53.875,8.625],[54.125,8.375],[55.625,7.875],[56.625,7.875],[57.875,9.125],[57.875,10.375],[57.125,11.125],[56.375,11.125],[55.625,10.625],[54.125,11.125]]],["HAM","SAF",[[53.5,9.9],[53.875,8.625],[53.625,3.875],[50.875,1.125],[48.875,-4.625],[42.625,-9.875],[38.875,-9.875],[32.625,-9.375]]],["HAM","SNT",[[53.5,9.9],[53.875,8.625],[53.625,3.875],[50.875,1.125],[49.875,-1.875],[49.625,-2.125],[48.875,-2.125]]],["HAM","TUR",[[53.5,9.9],[53.875,8.625],[54.125,8.375],[55.625,7.875],[56.625,7.875],[57.875,9.125],[57.875,10.875],[55.375,13.375],[55.375,14.375],[55.875,15.875],[60.375,22.125]]],["HAN","FUZ",[[20.375,106.625],[20.125,110.375],[22.625,116.125],[24.125,118.375],[25.375,119.625],[25.625,119.625]]],["HAN","JAF",[[20.375,106.625],[14.375,109.625],[12.375,109.625],[1.375,104.375],[1.125,104.125],[1.625,102.625],[9.875,90.375],[9.875,80.125],[9.625,79.875]]],["HAN","KOZ",[[20.375,106.625],[14.375,109.625],[12.375,109.625],[1.375,104.375],[1.125,104.125],[1.625,102.625],[5.875,96.375],[5.875,80.375],[8.125,77.125],[8.875,76.375],[11.125,75.625]]],["HAV","CAD",[[23.375,-82.375],[36.375,-53.125],[36.375,-6.375]]],["HAV","CAR",[[23.375,-82.375],[23.125,-83.875],[22.125,-84.875],[21.875,-85.125],[10.625,-75.625]]],["HAV","JAM",[[23.375,-82.375],[25.125,-80.375],[25.625,-79.875],[35.625,-75.375],[36.875,-75.625],[37.125,-76.125]]],["HAV","SGO",[[23.375,-82.375],[22.875,-76.625],[20.375,-74.125],[18.375,-74.625],[17.875,-74.125],[17.375,-71.375],[18.46,-69.94]]],["HAV","VER",[[23.375,-82.375],[19.875,-95.625],[19.375,-96.125]]],["HER","ANC",[[35.625,25.125],[36.375,22.125],[36.875,21.375],[40.625,18.375],[43.625,13.625],[43.62,13.52]]],["HER","FEO",[[35.625,25.125],[39.625,26.125],[40.125,26.625],[40.625,27.375],[40.875,28.875],[44.125,32.375],[44.125,33.875],[44.625,35.125],[44.875,35.375]]],["HER","RHO",[[35.625,25.125],[36.43,28.22]]],["HER","TRA",[[35.625,25.125],[39.625,26.125],[40.125,26.625],[40.625,27.375],[40.875,28.875],[42.125,30.125],[42.125,38.625],[41.01,39.72]]],["HER","VEN",[[35.625,25.125],[36.375,22.125],[36.875,21.375],[40.625,18.375],[45.375,12.625]]],["HIR","KOZ",[[33.375,129.375],[13.625,109.625],[12.375,109.625],[1.375,104.375],[1.125,104.125],[1.625,102.625],[5.875,96.375],[5.875,80.375],[8.125,77.125],[8.875,76.375],[11.125,75.625]]],["HIR","MYE",[[33.375,129.375],[13.625,109.625],[12.375,109.625],[1.375,104.375],[1.125,104.125],[1.625,102.625],[2.375,101.625],[2.875,101.125],[8.125,97.875],[12.375,98.125]]],["HIR","SAK",[[33.375,129.375],[32.875,129.375],[31.375,130.125],[30.875,130.625],[31.125,131.125],[33.375,134.625],[33.625,134.875],[34.3,135]]],["HIR","SUE",[[33.375,129.375],[13.625,109.625],[12.375,109.625],[1.375,104.375],[1.125,104.125],[1.625,102.625],[5.875,96.375],[5.875,80.375],[12.375,49.625],[12.375,43.875],[13.375,42.875],[28.875,33.125],[29.125,32.875],[29.9,32.6]]],["HOB","MYE",[[-43.125,147.625],[-43.875,146.875],[-34.875,115.625],[-23.875,105.375],[-6.375,105.375],[-4.125,106.375],[-3.125,106.375],[-2.375,105.875],[0.375,103.875],[2.125,102.125],[2.125,101.875],[2.875,101.125],[8.125,97.875],[12.375,98.125]]],["HOI","AYU",[[16.125,108.375],[14.875,109.625],[12.375,109.625],[11.625,109.375],[10.875,108.625],[8.625,105.625],[8.375,105.125],[12.875,100.625],[14.36,100.6]]],["HOI","HIR",[[16.125,108.375],[24.125,118.375],[33.375,129.375]]],["HOI","QUA",[[16.125,108.375],[24.125,118.375],[24.625,118.875]]],["HOI","TAI",[[16.125,108.375],[22.875,119.875]]],["HON","AYU",[[22.125,114.125],[11.625,109.375],[10.875,108.625],[8.625,105.625],[8.375,105.125],[12.875,100.625],[14.36,100.6]]],["HON","GUA",[[22.125,114.125],[22.625,113.625],[23.1,113.3]]],["HON","JAF",[[22.125,114.125],[11.625,109.375],[1.375,104.375],[1.125,104.125],[1.625,102.625],[9.875,90.375],[9.875,80.125],[9.625,79.875]]],["HON","MNL",[[22.125,114.125],[14.625,120.125],[14.375,120.625]]],["HON","NAH",[[22.125,114.125],[22.625,116.125],[26.125,122.875],[26.21,127.68]]],["HOO","CHI",[[22.9,88.4],[22.125,88.125],[21.875,88.125],[21.625,88.375],[21.625,90.375],[22.125,91.625]]],["HOO","MUS",[[22.9,88.4],[22.125,88.125],[21.875,88.125],[9.375,79.375],[7.875,77.875],[7.875,77.375],[23.625,58.875]]],["HOR","BSR",[[26.875,56.375],[26.375,54.875],[26.625,53.625],[27.875,51.375],[30.5,47.9]]],["HOR","DIU",[[26.875,56.375],[25.625,57.375],[20.625,70.375],[20.71,70.98]]],["HOR","FUK",[[26.875,56.375],[25.625,57.375],[7.875,77.375],[5.875,80.375],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[24.375,120.375],[33.625,129.625],[33.625,130.125]]],["HOR","MOM",[[26.875,56.375],[25.625,57.375],[22.375,60.125],[18.875,57.875],[5.375,48.875],[3.125,47.125],[-4.125,39.875]]],["HRN","AMS",[[53.125,4.625],[52.875,4.375]]],["HRN","DUB",[[53.125,4.625],[50.625,0.625],[49.875,-5.625],[50.125,-5.875],[53.375,-5.875]]],["HRN","LNG",[[53.125,4.625],[67.875,5.125],[77.125,14.375]]],["HRN","LON",[[53.125,4.625],[51.625,1.125],[51.5,-0.1]]],["HRN","NAN",[[53.125,4.625],[50.625,0.625],[48.875,-4.625],[48.625,-4.875],[48.125,-4.875],[47.875,-4.625],[47.125,-2.375],[47.2,-1.7]]],["HRN","PLY",[[53.125,4.625],[50.625,0.625],[50.125,-4.125]]],["HRN","VIS",[[53.125,4.625],[57.125,8.375],[57.875,10.375],[55.375,13.375],[55.375,14.375],[55.875,15.875],[57.63,18.31]]],["HUA","ACA",[[15.625,-96.125],[15.625,-97.125],[16.375,-99.375],[16.625,-99.875]]],["HUA","NAV",[[15.625,-96.125],[15.625,-97.125],[16.625,-100.125],[18.125,-103.625],[19.125,-104.875]]],["HUA","PAI",[[15.625,-96.125],[-5.125,-81.375]]],["INC","KAG",[[37.125,126.375],[36.625,125.875],[34.625,126.125],[31.625,130.125]]],["INC","SRT",[[37.125,126.375],[33.125,122.375],[29.375,122.375],[28.625,122.125],[1.125,104.125],[1.625,102.625],[5.875,96.375],[5.875,80.375],[8.125,77.125],[8.875,76.375],[13.375,74.375],[16.375,73.125],[19.125,72.625],[21.125,72.375]]],["INC","TAI",[[37.125,126.375],[33.125,122.375],[29.375,122.375],[23.625,119.875],[22.875,119.875]]],["ISL","CHE",[[-15.125,40.875],[8.125,78.125],[9.375,79.375],[10.375,80.125],[12.875,80.375]]],["ISL","SOF",[[-15.125,40.875],[-16.375,40.125],[-20.125,36.125],[-20.125,34.875]]],["ISL","ZAN",[[-15.125,40.875],[-14.625,41.125],[-10.375,40.625],[-6.875,39.625],[-6.17,39.2]]],["IST","ALE",[[40.875,28.875],[40.625,27.375],[40.125,26.625],[39.625,26.125],[38.125,26.125],[31.375,29.625]]],["IST","CHS",[[40.875,28.875],[40.625,27.375],[40.125,26.625],[39.625,26.125],[38.4,26.02]]],["IST","COR",[[40.875,28.875],[40.625,27.375],[40.125,26.625],[36.875,23.375],[36.625,23.375],[36.375,22.875],[36.375,22.125],[36.875,21.375],[39.375,19.875],[39.62,19.92]]],["IST","DBR",[[40.875,28.875],[40.625,27.375],[40.125,26.625],[36.875,23.375],[36.625,23.375],[36.375,22.875],[36.375,22.125],[36.875,21.375],[40.375,19.125],[42.625,17.875]]],["IST","MRS",[[40.875,28.875],[40.625,27.375],[40.125,26.625],[36.875,23.375],[36.625,23.375],[36.375,22.875],[36.375,15.125],[37.375,12.375],[41.375,9.375],[41.375,8.875],[43.125,5.375]]],["IST","TRA",[[40.875,28.875],[42.125,30.125],[42.125,38.625],[41.01,39.72]]],["IST","VEN",[[40.875,28.875],[40.625,27.375],[40.125,26.625],[36.875,23.375],[36.625,23.375],[36.375,22.875],[36.375,22.125],[36.875,21.375],[40.625,18.375],[45.375,12.625]]],["IZM","BEI",[[37.875,26.625],[37.125,27.125],[36.625,27.625],[34.375,33.125],[34.125,35.375]]],["IZM","FNC",[[37.875,26.625],[36.375,22.875],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[34.375,-15.125],[32.65,-16.92]]],["IZM","LIV",[[37.875,26.625],[36.375,22.875],[36.375,15.125],[37.375,12.375],[37.625,12.125],[43.125,10.125],[43.625,10.125]]],["IZM","TUN",[[37.875,26.625],[36.375,22.875],[36.375,15.125],[37.125,10.625],[36.875,10.375]]],["IZM","VEN",[[37.875,26.625],[36.375,22.875],[36.375,22.125],[36.875,21.375],[40.625,18.375],[45.375,12.625]]],["JAF","HAD",[[9.625,79.875],[7.875,77.875],[12.65,54.03]]],["JAF","MAK",[[9.625,79.875],[9.875,80.625],[4.875,99.125],[2.125,101.875],[-4.625,112.625],[-4.875,119.375]]],["JAF","MOC",[[9.625,79.875],[7.875,77.875],[12.375,48.875],[12.375,43.875],[13.125,43.125]]],["JAK","AMS",[[-5.875,106.875],[-5.875,105.875],[-34.875,23.625],[-34.875,18.875],[-4.125,-10.625],[12.875,-17.125],[14.875,-17.625],[37.125,-16.375],[50.375,-3.125],[50.625,0.625],[52.875,4.375]]],["JAK","BNT",[[-5.875,106.875],[-5.875,106.125]]],["JAK","FUZ",[[-5.875,106.875],[19.875,114.125],[25.375,119.625],[25.625,119.625]]],["JAK","PUL",[[-5.875,106.875],[-5.875,104.125],[13.625,80.375]]],["JAM","NUU",[[37.125,-76.125],[46.625,-52.875],[47.375,-52.375],[63.875,-52.125]]],["JAM","PAR",[[37.125,-76.125],[36.625,-75.375],[6.125,-55.125]]],["JAM","STG",[[37.125,-76.125],[32.38,-64.68]]],["JED","KAN",[[21.625,38.875],[20.875,39.125],[13.375,42.875],[12.375,43.875],[11.875,75.125]]],["JED","MOC",[[21.625,38.875],[20.875,39.125],[13.125,43.125]]],["JED","PTT",[[21.625,38.875],[20.875,39.125],[13.375,42.875],[12.375,43.875],[10.875,74.375],[7.875,77.375],[5.875,80.375],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[1.375,104.375],[4.875,103.875],[6.625,102.125],[6.875,101.375],[6.87,101.25]]],["JED","SRT",[[21.625,38.875],[20.875,39.125],[13.375,42.875],[12.375,43.875],[12.625,45.125],[20.875,71.875],[21.125,72.375]]],["JED","TOK",[[21.625,38.875],[20.875,39.125],[13.375,42.875],[12.375,43.875],[10.875,74.375],[7.875,77.375],[5.875,80.375],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[19.875,121.875],[35.125,140.375]]],["JEJ","HIR",[[33.51,126.52],[33.375,129.375]]],["JEJ","MUS",[[33.51,126.52],[1.125,104.125],[1.625,102.625],[5.875,96.375],[5.875,80.375],[8.125,77.125],[23.625,58.875]]],["JEJ","NAH",[[33.51,126.52],[26.21,127.68]]],["KAG","HAN",[[31.625,130.125],[23.125,116.875],[22.625,116.125],[20.125,110.375],[20.375,106.625]]],["KAG","INC",[[31.625,130.125],[34.625,126.125],[36.625,125.875],[37.125,126.375]]],["KAG","QUA",[[31.625,130.125],[24.625,118.875]]],["KAL","BOS",[[55.125,20.375],[55.375,13.375],[57.875,10.375],[57.875,6.875],[58.875,-4.625],[49.875,-49.625],[46.625,-52.875],[43.375,-65.375],[42.375,-70.625]]],["KAL","SGO",[[55.125,20.375],[55.375,13.375],[57.875,10.375],[57.875,6.875],[58.875,-4.625],[52.625,-34.125],[18.125,-68.625],[18.375,-69.875],[18.46,-69.94]]],["KAL","TAL",[[55.125,20.375],[56.875,20.875],[58.375,22.375],[58.375,23.375],[59.447,24.729]]],["KAN","JAK",[[11.875,75.125],[8.875,76.375],[7.875,77.375],[5.875,80.375],[-5.875,104.375],[-5.875,106.875]]],["KAN","KOC",[[11.875,75.125],[9.875,76.125]]],["KAR","BAS",[[24.625,66.875],[24.875,61.125],[25.625,57.375],[26.875,56.375]]],["KAR","GAL",[[24.625,66.875],[8.625,76.625],[7.875,77.375],[6.03,80.22]]],["KAR","MAK",[[24.625,66.875],[8.625,76.625],[7.875,77.375],[5.875,80.375],[5.625,98.375],[2.125,101.875],[-4.625,112.625],[-4.875,119.375]]],["KHA","DIU",[[21.4,72.3],[20.875,71.875],[20.625,70.875],[20.71,70.98]]],["KHA","MOK",[[21.4,72.3],[17.375,72.875],[15.875,73.375],[12.125,74.875],[8.875,76.375],[7.875,77.375],[5.875,80.375],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[34.875,126.125]]],["KIL","ISL",[[-8.98,39.52],[-9.625,40.125],[-10.375,40.625],[-14.875,41.125],[-15.125,40.875]]],["KIL","MCH",[[-8.98,39.52],[7.875,77.875],[9.375,79.375],[10.375,80.125],[16.125,81.375]]],["KIL","OLD",[[-8.98,39.52],[15.625,73.625]]],["KIN","REY",[[53.875,0.125],[56.875,-0.875],[63.375,-7.875],[63.375,-19.875],[63.625,-22.125],[64.125,-22.625],[64.375,-22.125]]],["KIN","SNT",[[53.875,0.125],[52.625,1.875],[52.125,1.875],[50.875,1.125],[49.875,-1.875],[49.625,-2.125],[48.875,-2.125]]],["KIN","TOR",[[53.875,0.125],[56.875,-0.875],[62.125,-6.125],[62.01,-6.77]]],["KOC","JAK",[[9.875,76.125],[9.375,76.125],[8.875,76.375],[7.875,77.375],[5.875,80.375],[-5.875,104.375],[-5.875,106.875]]],["KOC","KOZ",[[9.875,76.125],[10.875,75.625],[11.125,75.625]]],["KOC","LIS",[[9.875,76.125],[-12.125,48.875],[-16.375,44.125],[-31.125,30.375],[-34.875,26.625],[-34.875,18.875],[-3.375,-11.375],[13.125,-17.125],[14.875,-17.625],[31.375,-16.875],[38.625,-9.625]]],["KOC","MAC",[[9.875,76.125],[9.375,76.125],[8.875,76.375],[7.875,77.375],[5.875,80.375],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[1.375,104.375],[12.375,109.625],[22.19,113.54]]],["KOL","HON",[[8.875,76.375],[7.875,77.375],[5.875,80.375],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[1.375,104.375],[12.375,109.625],[22.125,114.125]]],["KOL","SOF",[[8.875,76.375],[-20.125,35.125],[-20.125,34.875]]],["KOZ","JEJ",[[11.125,75.625],[8.875,76.375],[7.875,77.375],[5.875,80.375],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[33.51,126.52]]],["KOZ","KAN",[[11.125,75.625],[11.875,75.125]]],["KOZ","MAN",[[11.125,75.625],[26.375,56.375],[26.22,50.58]]],["KUP","SOF",[[-10.375,123.625],[-25.625,45.375],[-24.125,38.875],[-20.125,34.875]]],["KUP","XIA",[[-10.375,123.625],[-10.125,123.125],[-8.125,123.125],[-5.625,119.375],[-5.375,119.125],[-2.625,118.625],[11.875,119.875],[24.125,118.375]]],["LAG","LIS",[[6.125,3.375],[4.625,-1.625],[4.125,-8.125],[4.875,-9.375],[7.375,-12.875],[12.125,-16.875],[14.875,-17.625],[31.375,-16.875],[38.625,-9.625]]],["LAG","OPO",[[6.125,3.375],[4.625,-1.625],[4.125,-8.125],[4.875,-9.375],[7.375,-12.875],[12.125,-16.875],[14.875,-17.625],[33.625,-16.625],[41.125,-9.125]]],["LAG","TEN",[[6.125,3.375],[4.625,-1.625],[4.125,-8.125],[4.875,-9.375],[7.375,-12.875],[12.125,-16.875],[14.875,-17.625],[27.375,-17.125],[28.47,-16.25]]],["LAR","AMS",[[46.033,-1.487],[47.875,-4.625],[48.125,-4.875],[48.625,-4.875],[50.375,-2.625],[50.625,0.625],[52.875,4.375]]],["LAR","BOR",[[46.033,-1.487],[44.9,-0.6]]],["LAR","HAM",[[46.033,-1.487],[47.875,-4.625],[48.125,-4.875],[48.625,-4.875],[50.375,-2.625],[50.625,0.625],[53.875,5.875],[53.875,9.125],[53.625,9.375],[53.5,9.9]]],["LAR","LIS",[[46.033,-1.487],[43.625,-8.875],[42.625,-9.875],[38.875,-9.875],[38.625,-9.625]]],["LAR","SAL",[[46.033,-1.487],[43.625,-8.875],[42.625,-9.875],[38.875,-9.875],[36.875,-9.125],[34.125,-7.125]]],["LEH","GDA",[[49.625,-0.375],[57.875,9.125],[57.875,10.875],[55.375,13.375],[54.875,18.625],[54.625,18.875]]],["LEH","HAM",[[49.625,-0.375],[53.875,5.625],[53.875,9.125],[53.625,9.375],[53.5,9.9]]],["LEH","LUB",[[49.625,-0.375],[57.875,9.125],[57.875,10.375],[57.125,11.125],[56.375,11.125],[55.625,10.625],[54.125,11.125]]],["LEH","RIG",[[49.625,-0.375],[57.875,9.125],[57.875,10.875],[55.375,13.375],[55.375,14.375],[57.875,22.375],[57.625,23.125],[56.919,23.984]]],["LEH","SNL",[[49.625,-0.375],[49.875,-2.625],[48.875,-4.625],[42.625,-9.875],[38.875,-9.875],[36.875,-9.125],[36.625,-8.875],[36.8,-6.4]]],["LEI","BEL",[[56.125,-2.625],[55.875,-1.375],[52.625,1.875],[52.125,1.875],[50.875,1.125],[48.875,-4.625],[-0.875,-47.875],[-1.4,-48.5]]],["LEI","COP",[[56.125,-2.625],[57.875,10.625],[55.728,12.823]]],["LEI","HAM",[[56.125,-2.625],[53.875,9.125],[53.625,9.375],[53.5,9.9]]],["LEI","STO",[[56.125,-2.625],[57.875,10.875],[55.375,13.375],[55.375,14.375],[55.875,15.875],[56.375,16.375],[59.125,18.375],[59.375,18.375]]],["LIS","AGA",[[38.625,-9.625],[30.875,-10.125],[30.375,-9.875]]],["LIS","BIL",[[38.625,-9.625],[40.375,-9.875],[42.875,-9.625],[43.875,-8.625],[43.625,-2.875]]],["LIS","BOR",[[38.625,-9.625],[40.375,-9.875],[42.875,-9.625],[45.625,-6.375],[45.625,-1.375],[44.9,-0.6]]],["LIS","ELM",[[38.625,-9.625],[20.875,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[4.875,-1.125]]],["LIS","LAR",[[38.625,-9.625],[40.375,-9.875],[42.875,-9.625],[46.125,-5.875],[46.033,-1.487]]],["LIS","LPA",[[38.625,-9.625],[28.13,-15.43]]],["LIS","NAN",[[38.625,-9.625],[40.375,-9.875],[42.875,-9.625],[46.875,-4.875],[46.875,-2.125],[47.2,-1.7]]],["LIS","OPO",[[38.625,-9.625],[40.625,-9.625],[41.125,-9.125]]],["LIS","PLY",[[38.625,-9.625],[40.375,-9.875],[44.875,-9.375],[50.125,-4.125]]],["LIS","SOY",[[38.625,-9.625],[20.875,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[-5.875,5.375],[-6.125,12.125]]],["LIV","ALE",[[43.625,10.125],[43.125,10.125],[37.625,12.125],[37.375,12.375],[31.375,29.625]]],["LIV","GOA",[[43.625,10.125],[44.125,8.875]]],["LIV","LON",[[43.625,10.125],[38.375,0.375],[37.375,-0.625],[36.625,-2.125],[35.875,-5.625],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[43.875,-9.625],[50.375,-3.125],[50.625,0.625],[51.125,1.375],[51.375,1.125],[51.5,-0.1]]],["LIV","NAP",[[43.625,10.125],[43.125,10.125],[42.125,11.125],[41.375,12.125],[40.625,14.125]]],["LIV","TUN",[[43.625,10.125],[36.875,10.375]]],["LNG","ALE",[[77.125,14.375],[57.125,-6.875],[53.625,-10.125],[38.875,-9.875],[36.875,-9.125],[36.625,-8.875],[35.875,-5.375],[37.375,6.375],[37.375,12.875],[37.125,13.125],[31.375,29.625]]],["LNG","AMS",[[77.125,14.375],[61.375,4.375],[52.875,4.375]]],["LNG","ARK",[[77.125,14.375],[67.875,40.875],[67.625,41.125],[66.875,41.125],[65.375,39.875],[64.875,40.125]]],["LNG","DUB",[[77.125,14.375],[57.625,-6.375],[56.875,-6.375],[54.375,-5.625],[53.375,-5.875]]],["LNG","NEW",[[77.125,14.375],[46.375,-53.375],[40.625,-72.375],[40.625,-73.875]]],["LNG","VAR",[[77.125,14.375],[70.875,30.625],[70.37,31.11]]],["LON","ALE",[[51.5,-0.1],[51.375,1.125],[51.125,1.375],[50.625,0.625],[48.875,-4.625],[42.625,-9.875],[38.875,-9.875],[36.875,-9.125],[36.625,-8.875],[35.875,-5.375],[37.375,6.375],[37.375,12.875],[37.125,13.125],[31.375,29.625]]],["LON","ARK",[[51.5,-0.1],[51.625,1.125],[52.125,1.875],[62.125,4.875],[71.375,14.875],[71.375,37.375],[67.625,41.125],[66.875,41.125],[65.375,39.875],[64.875,40.125]]],["LON","ARP",[[51.5,-0.1],[51.625,3.625],[51.375,3.875],[51.203,4.389]]],["LON","BER",[[51.5,-0.1],[51.625,1.125],[52.125,1.875],[60.375,4.875]]],["LON","BRU",[[51.5,-0.1],[51.375,3.125]]],["LON","KIN",[[51.5,-0.1],[51.625,1.125],[52.125,1.875],[52.625,1.875],[53.875,0.125]]],["LON","ROT",[[51.5,-0.1],[52.125,3.875]]],["LON","SAI",[[51.5,-0.1],[51.375,1.125],[51.125,1.375],[50.625,0.625],[48.875,-4.625],[33.375,-17.375],[21.125,-17.375],[16.375,-16.875],[16.125,-16.625]]],["LPA","AGA",[[28.13,-15.43],[30.375,-9.875]]],["LPA","OUI",[[28.13,-15.43],[20.125,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[6.125,2.125]]],["LPA","PAL",[[28.13,-15.43],[35.875,-5.875],[38.375,13.125],[38.12,13.36]]],["LPA","REC",[[28.13,-15.43],[-8.125,-34.625]]],["LPA","SAL",[[28.13,-15.43],[34.125,-7.875],[34.125,-7.125]]],["LPA","SAO",[[28.13,-15.43],[20.125,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[0.34,6.73]]],["LPA","SLV",[[28.13,-15.43],[-9.625,-35.125],[-12.625,-37.875],[-13.125,-38.375]]],["LPA","TEN",[[28.13,-15.43],[28.47,-16.25]]],["LPA","TOR",[[28.13,-15.43],[60.625,-8.375],[62.01,-6.77]]],["LPA","VER",[[28.13,-15.43],[22.625,-92.875],[19.375,-96.125]]],["LUA","CAL",[[-8.625,12.875],[-1.375,8.625],[4.375,8.375]]],["LUA","LIS",[[-8.625,12.875],[6.125,-11.625],[7.625,-13.125],[12.125,-16.875],[14.875,-17.625],[31.375,-16.875],[38.625,-9.625]]],["LUA","PLO",[[-8.625,12.875],[-9.375,12.625],[-16.625,11.375],[-29.125,13.125],[-34.875,18.875],[-32.875,44.875],[-20.16,57.5]]],["LUB","BER",[[54.125,11.125],[55.875,10.625],[56.375,11.125],[57.375,10.875],[57.875,10.375],[57.875,6.875],[58.375,5.625],[59.125,5.125],[60.375,4.875]]],["LUB","CAP",[[54.125,11.125],[55.875,10.625],[56.375,11.125],[57.375,10.875],[57.875,10.375],[56.625,6.875],[50.875,1.125],[48.875,-4.625],[33.125,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[4.875,-1.125]]],["LUB","COP",[[54.125,11.125],[55.125,12.875],[55.375,13.125],[55.728,12.823]]],["LUB","LPA",[[54.125,11.125],[55.875,10.625],[56.375,11.125],[57.375,10.875],[57.875,10.375],[56.625,6.875],[50.875,1.125],[48.875,-4.625],[35.875,-15.375],[28.13,-15.43]]],["LUB","RIG",[[54.125,11.125],[57.875,22.375],[57.625,23.125],[56.919,23.984]]],["LUB","STO",[[54.125,11.125],[55.875,15.875],[56.375,16.375],[59.125,18.375],[59.375,18.375]]],["MAC","ACA",[[22.19,113.54],[16.625,-99.875]]],["MAC","DIL",[[22.19,113.54],[7.875,121.625],[7.125,121.625],[1.625,125.375],[-8.375,125.625]]],["MAC","MNL",[[22.19,113.54],[14.625,120.125],[14.375,120.625]]],["MAC","NAG",[[22.19,113.54],[22.125,114.375],[22.625,116.125],[24.125,118.375],[32.625,129.625]]],["MAC","TID",[[22.19,113.54],[7.875,121.625],[7.125,121.625],[0.625,127.125]]],["MAK","HOB",[[-4.875,119.375],[-8.625,116.625],[-24.125,113.125],[-32.625,113.375],[-43.875,125.125],[-43.875,146.875],[-43.125,147.625]]],["MAK","JAK",[[-4.875,119.375],[-5.875,106.875]]],["MAK","LUA",[[-4.875,119.375],[-34.875,88.625],[-34.875,18.875],[-26.875,11.375],[-16.125,11.375],[-8.875,12.625],[-8.625,12.875]]],["MAK","MAL",[[-4.875,119.375],[-2.875,107.625],[2.125,102.125]]],["MAL","AYU",[[2.125,102.125],[1.625,102.625],[1.125,104.125],[1.375,104.375],[10.375,103.125],[12.875,100.625],[14.36,100.6]]],["MAL","BNT",[[2.125,102.125],[0.125,104.125],[-2.625,106.125],[-3.375,106.375],[-5.875,106.125]]],["MAL","JAK",[[2.125,102.125],[0.125,104.125],[-2.625,106.125],[-3.375,106.375],[-5.875,106.875]]],["MAL","MLN",[[2.125,102.125],[2.375,101.625],[5.625,96.875],[1.875,45.875],[-3.125,40.375]]],["MAL","NIN",[[2.125,102.125],[1.625,102.625],[1.125,104.125],[28.625,122.125],[29.875,122.375],[30.125,121.875]]],["MAL","SUR",[[2.125,102.125],[-6.625,112.125],[-6.625,112.375],[-7.125,112.875]]],["MAN","MLN",[[26.22,50.58],[26.375,56.375],[22.375,60.125],[18.875,57.875],[5.375,48.875],[3.125,47.125],[-3.125,40.625],[-3.125,40.375]]],["MAN","ZAN",[[26.22,50.58],[26.375,56.375],[22.375,60.125],[18.875,57.875],[5.375,48.875],[-0.375,44.375],[-6.17,39.2]]],["MAS","FUZ",[[15.875,39.625],[13.625,42.625],[12.375,43.875],[10.875,74.375],[7.875,77.375],[5.875,80.375],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[25.375,119.625],[25.625,119.625]]],["MAS","HAD",[[15.875,39.625],[13.625,42.625],[12.375,43.875],[12.65,54.03]]],["MAT","MYE",[[41.43,140.11],[33.375,129.375],[13.625,109.625],[12.375,109.625],[1.375,104.375],[1.125,104.125],[1.625,102.625],[2.375,101.625],[2.875,101.125],[8.125,97.875],[12.375,98.125]]],["MAT","OSA",[[41.43,140.11],[41.375,141.125],[41.625,141.375],[40.375,142.125],[39.125,142.125],[35.875,141.125],[34.875,140.125],[33.375,135.625],[33.875,135.125],[34.3,135]]],["MAT","SAK",[[41.43,140.11],[41.375,141.125],[41.625,141.375],[40.375,142.125],[39.125,142.125],[35.875,141.125],[34.875,140.125],[33.375,135.625],[33.875,135.125],[34.3,135]]],["MCH","BNT",[[16.125,81.375],[-5.625,103.875],[-5.875,104.625],[-5.875,106.125]]],["MCH","COL",[[16.125,81.375],[10.375,80.125],[8.125,79.375],[6.875,79.625]]],["MCH","HOO",[[16.125,81.375],[16.125,81.875],[20.125,86.625],[20.875,87.375],[21.875,88.125],[22.375,88.125],[22.9,88.4]]],["MCH","JED",[[16.125,81.375],[10.375,80.125],[8.875,78.875],[7.875,77.875],[12.375,48.875],[12.375,43.875],[13.375,42.875],[21.375,38.875],[21.625,38.875]]],["MES","FEO",[[38.375,15.375],[38.375,12.625],[37.625,12.125],[37.375,12.375],[36.375,15.375],[36.375,23.125],[39.875,26.375],[40.375,26.875],[40.875,28.375],[40.875,28.875],[44.125,32.375],[44.125,33.875],[44.625,35.125],[44.875,35.375]]],["MES","GOA",[[38.375,15.375],[44.125,8.875]]],["MID","CAL",[[51.469,3.531],[51.125,1.375],[50.625,0.625],[48.875,-4.625],[33.125,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.125,7.875],[4.375,8.375]]],["MID","HRN",[[51.469,3.531],[52.375,3.875],[52.875,4.375],[53.125,4.625]]],["MID","PTH",[[51.469,3.531],[51.125,1.375],[50.625,0.625],[50.625,-1.125]]],["MID","TUR",[[51.469,3.531],[52.875,4.125],[57.875,9.125],[57.875,10.875],[55.375,13.375],[55.375,14.375],[55.875,15.875],[60.375,22.125]]],["MLE","DIU",[[4.18,73.51],[20.71,70.98]]],["MLE","YEO",[[4.18,73.51],[5.625,97.125],[1.625,102.625],[1.125,104.125],[33.375,126.625],[34.625,127.875]]],["MLG","BER",[[36.625,-4.125],[35.875,-5.125],[35.875,-5.875],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[43.875,-9.625],[50.375,-3.125],[50.625,0.625],[51.125,1.375],[52.125,1.875],[60.375,4.875]]],["MLG","CAD",[[36.625,-4.125],[35.875,-5.125],[35.875,-5.875],[36.375,-6.375]]],["MLG","GOR",[[36.625,-4.125],[35.875,-5.125],[35.875,-6.375],[24.625,-17.625],[14.625,-17.625]]],["MLN","HIR",[[-3.125,40.375],[5.625,95.875],[5.125,98.875],[2.125,101.875],[1.375,103.125],[1.125,104.125],[24.375,120.375],[33.125,129.125],[33.375,129.375]]],["MLN","ISL",[[-3.125,40.375],[-14.875,41.125],[-15.125,40.875]]],["MLN","KAG",[[-3.125,40.375],[5.625,95.875],[5.125,98.875],[2.125,101.875],[1.375,103.125],[1.125,104.125],[31.625,130.125]]],["MNG","MLE",[[12.875,74.625],[4.18,73.51]]],["MNG","MOM",[[12.875,74.625],[-4.125,39.875]]],["MNL","ACA",[[14.375,120.625],[13.875,120.375],[13.625,120.625],[13.375,122.125],[12.375,123.875],[16.625,140.625],[16.625,-99.875]]],["MNL","CEB",[[14.375,120.625],[13.375,120.125],[9.625,122.125],[8.875,122.875],[8.875,123.125],[9.375,123.625],[10.125,124.125],[10.375,124.125]]],["MNL","HAN",[[14.375,120.625],[14.625,120.125],[20.125,110.875],[20.375,106.625]]],["MNL","HOI",[[14.375,120.625],[16.125,108.375]]],["MNL","MAC",[[14.375,120.625],[14.625,120.125],[22.19,113.54]]],["MNL","NAH",[[14.375,120.625],[14.625,120.125],[14.875,119.875],[15.625,119.625],[18.625,120.125],[26.21,127.68]]],["MNL","QUA",[[14.375,120.625],[14.625,120.125],[14.875,119.875],[15.625,119.625],[24.625,118.875]]],["MNL","TAI",[[14.375,120.625],[14.625,120.125],[14.875,119.875],[15.625,119.625],[22.875,119.875]]],["MOC","ADE",[[13.125,43.125],[12.375,43.875],[12.625,45.125]]],["MOC","FUK",[[13.125,43.125],[12.375,43.875],[10.875,74.375],[7.875,77.375],[5.875,80.375],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[24.375,120.375],[33.625,129.625],[33.625,130.125]]],["MOC","SUA",[[13.125,43.125],[19.375,37.375]]],["MOG","BAS",[[1.875,45.625],[2.625,46.625],[3.375,47.375],[5.625,49.125],[21.875,59.875],[22.625,60.125],[25.875,57.125],[26.875,56.375]]],["MOG","ISL",[[1.875,45.625],[-15.125,40.875]]],["MOG","OSA",[[1.875,45.625],[5.625,96.875],[1.625,102.625],[1.125,104.125],[32.625,133.875],[33.625,134.875],[34.3,135]]],["MOK","HAG",[[34.875,126.125],[33.875,126.875],[13.48,144.75]]],["MOK","HOR",[[34.875,126.125],[1.125,104.125],[1.625,102.625],[5.875,96.375],[5.875,80.375],[8.125,77.125],[25.875,57.125],[26.875,56.375]]],["MOK","NAH",[[34.875,126.125],[26.21,127.68]]],["MOM","BAN",[[-4.125,39.875],[5.55,95.32]]],["MOM","BSR",[[-4.125,39.875],[3.375,47.375],[5.625,49.125],[21.875,59.875],[22.625,60.125],[26.375,56.375],[26.375,54.375],[26.875,53.125],[27.875,51.375],[30.5,47.9]]],["MRS","ANG",[[43.125,5.375],[37.375,-0.625],[36.625,-2.125],[35.875,-5.625],[38.66,-27.22]]],["MRS","CHS",[[43.125,5.375],[41.375,8.875],[41.375,9.375],[37.375,12.375],[36.375,15.375],[36.375,23.125],[38.4,26.02]]],["MRS","COR",[[43.125,5.375],[41.375,8.875],[41.375,9.375],[37.375,12.375],[36.375,15.125],[39.62,19.92]]],["MRS","NAP",[[43.125,5.375],[43.125,10.125],[42.125,11.125],[41.375,12.125],[40.625,14.125]]],["MRS","ORA",[[43.125,5.375],[35.875,-0.625]]],["MTY","NAV",[[36.625,-122.125],[36.125,-121.875],[34.375,-120.625],[27.375,-114.875],[22.625,-110.125],[19.125,-105.125],[19.125,-104.875]]],["MUM","GAL",[[19.125,72.625],[16.375,73.125],[9.375,76.125],[8.875,76.375],[7.875,77.375],[6.03,80.22]]],["MUM","THA",[[19.125,72.625],[16.375,73.125],[9.375,76.125],[8.875,76.375],[7.875,77.375],[7.875,77.875],[15.625,86.875],[15.625,95.625],[16.125,96.375],[16.77,96.2]]],["MUS","BAS",[[23.625,58.875],[26.875,56.375]]],["MUS","KHA",[[23.625,58.875],[20.625,70.625],[20.625,71.375],[21.125,72.125],[21.4,72.3]]],["MUS","MOG",[[23.625,58.875],[22.375,60.125],[18.875,57.875],[5.375,48.875],[3.125,47.125],[1.875,45.875],[1.875,45.625]]],["MUS","QUA",[[23.625,58.875],[7.875,77.375],[5.875,80.375],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[24.625,118.875]]],["MYE","AYU",[[12.375,98.125],[8.125,97.875],[2.875,101.125],[2.125,101.875],[1.375,103.125],[1.125,104.125],[1.375,104.375],[10.375,103.125],[12.875,100.625],[14.36,100.6]]],["MYE","HAG",[[12.375,98.125],[8.125,97.875],[2.875,101.125],[2.125,101.875],[1.375,103.125],[1.125,104.125],[12.125,120.375],[13.375,133.375],[13.48,144.75]]],["MYE","KUP",[[12.375,98.125],[8.125,97.875],[2.875,101.125],[2.125,101.875],[-10.375,118.625],[-10.375,123.625]]],["MYE","MAS",[[12.375,98.125],[9.875,79.875],[7.875,77.875],[12.375,48.875],[12.375,43.875],[15.875,40.125],[15.875,39.625]]],["MZT","HUA",[[23.125,-106.625],[20.125,-105.875],[19.125,-105.125],[18.125,-103.625],[15.875,-98.125],[15.625,-96.375],[15.625,-96.125]]],["MZT","SDG",[[23.125,-106.625],[22.625,-110.125],[27.625,-115.125],[32.375,-117.375],[32.625,-117.375]]],["NAG","HOI",[[32.625,129.625],[16.125,108.375]]],["NAG","MAC",[[32.625,129.625],[23.875,118.125],[22.625,116.125],[22.125,113.875],[22.19,113.54]]],["NAG","NAM",[[32.625,129.625],[34.625,126.125],[38.125,124.375],[38.625,124.875]]],["NAG","QUA",[[32.625,129.625],[24.625,118.875]]],["NAG","XIA",[[32.625,129.625],[24.125,118.375]]],["NAH","FUK",[[26.21,127.68],[33.375,129.375],[33.625,129.625],[33.625,130.125]]],["NAH","MAL",[[26.21,127.68],[1.125,104.125],[1.625,102.625],[2.125,102.125]]],["NAH","NAG",[[26.21,127.68],[32.625,129.625]]],["NAH","NAM",[[26.21,127.68],[38.125,124.375],[38.625,124.875]]],["NAH","SAK",[[26.21,127.68],[33.625,134.875],[34.3,135]]],["NAH","TON",[[26.21,127.68],[34.85,128.42]]],["NAH","XIA",[[26.21,127.68],[25.125,119.375],[24.125,118.375]]],["NAM","AYU",[[38.625,124.875],[36.125,122.375],[29.375,122.375],[28.625,122.125],[11.375,109.125],[10.875,108.625],[8.625,105.625],[8.375,105.125],[12.875,100.625],[14.36,100.6]]],["NAM","DIL",[[38.625,124.875],[38.125,124.375],[7.125,126.875],[-4.625,125.875],[-8.375,125.625]]],["NAM","NAG",[[38.625,124.875],[38.125,124.375],[34.625,126.125],[32.625,129.625]]],["NAM","NIN",[[38.625,124.875],[35.875,122.125],[31.125,122.125],[30.125,121.875]]],["NAN","CAD",[[47.2,-1.7],[43.375,-9.125],[42.875,-9.625],[38.875,-9.875],[36.875,-9.125],[36.625,-8.875],[36.375,-6.375]]],["NAN","HRN",[[47.2,-1.7],[47.125,-2.625],[47.875,-4.625],[48.125,-4.875],[48.625,-4.875],[50.375,-2.625],[50.625,0.625],[53.125,4.625]]],["NAN","LAR",[[47.2,-1.7],[46.625,-1.875],[46.033,-1.487]]],["NAN","LEI",[[47.2,-1.7],[47.125,-2.625],[47.875,-4.625],[48.125,-4.875],[48.625,-4.875],[50.375,-2.625],[50.625,0.625],[51.125,1.375],[52.125,1.875],[52.625,1.875],[56.125,-2.125],[56.125,-2.625]]],["NAN","LIS",[[47.2,-1.7],[43.375,-9.125],[42.875,-9.625],[38.875,-9.875],[38.625,-9.625]]],["NAN","OPO",[[47.2,-1.7],[43.375,-9.125],[42.875,-9.625],[41.125,-9.125]]],["NAN","QUE",[[47.2,-1.7],[46.375,-53.625],[47.375,-59.375],[49.125,-64.625],[48.625,-67.625],[48.125,-69.375],[46.875,-70.875],[46.8,-71.2]]],["NAN","SLV",[[47.2,-1.7],[43.375,-9.125],[17.625,-34.375],[-8.875,-34.375],[-12.625,-37.875],[-13.125,-38.375]]],["NAP","CAG",[[40.625,14.125],[39.125,9.375]]],["NAP","MRS",[[40.625,14.125],[41.375,12.125],[43.125,9.375],[43.125,5.375]]],["NAP","TOU",[[40.625,14.125],[41.375,12.125],[43.125,9.375],[43.13,5.93]]],["NAV","HUA",[[19.125,-104.875],[18.125,-103.625],[15.875,-98.125],[15.625,-96.375],[15.625,-96.125]]],["NAV","REA",[[19.125,-104.875],[18.125,-103.625],[15.875,-98.125],[12.375,-87.375]]],["NEW","ANG",[[40.625,-73.875],[38.66,-27.22]]],["NEW","HAV",[[40.625,-73.875],[39.875,-73.875],[35.625,-75.375],[25.625,-79.875],[24.875,-80.625],[23.375,-82.375]]],["NEW","POR",[[40.625,-73.875],[38.875,-74.125],[20.125,-74.125],[17.625,-76.625],[17.625,-76.875]]],["NEW","SET",[[40.625,-73.875],[38.125,-9.125]]],["NEW","STJ",[[40.625,-73.875],[40.625,-72.125],[46.625,-52.875],[47.375,-52.375],[47.625,-52.375]]],["NIN","HON",[[30.125,121.875],[29.875,122.375],[28.625,122.125],[25.125,119.375],[23.875,118.125],[22.625,116.125],[22.125,114.125]]],["NIN","OSA",[[30.125,121.875],[30.875,130.875],[33.375,134.625],[33.625,134.875],[34.3,135]]],["NIN","PUL",[[30.125,121.875],[29.875,122.375],[28.625,122.125],[1.125,104.125],[1.625,102.625],[13.625,84.625],[13.625,80.375]]],["NIN","SAK",[[30.125,121.875],[30.875,130.875],[33.375,134.625],[33.625,134.875],[34.3,135]]],["NIN","SHI",[[30.125,121.875],[34.125,130.625]]],["NIN","TON",[[30.125,121.875],[34.85,128.42]]],["NIN","XIA",[[30.125,121.875],[29.875,122.375],[28.625,122.125],[25.125,119.375],[24.125,118.375]]],["NUU","CRK",[[63.875,-52.125],[61.125,-49.125],[60.625,-48.375],[51.625,-9.375],[51.625,-8.375]]],["NUU","FEO",[[63.875,-52.125],[61.125,-49.125],[36.625,-8.875],[35.875,-5.375],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.375],[36.375,23.125],[39.875,26.375],[40.375,26.875],[40.875,28.375],[40.875,28.875],[44.125,32.375],[44.125,33.875],[44.625,35.125],[44.875,35.375]]],["NUU","GOA",[[63.875,-52.125],[61.125,-49.125],[36.625,-8.875],[35.875,-5.375],[36.625,-1.875],[37.625,-0.375],[44.125,8.875]]],["NUU","LEI",[[63.875,-52.125],[61.125,-49.125],[60.625,-48.375],[59.875,-44.125],[58.875,-2.875],[57.625,-1.625],[56.875,-1.875],[56.125,-2.625]]],["NUU","RIG",[[63.875,-52.125],[61.125,-49.125],[60.625,-48.375],[59.875,-44.125],[58.625,5.375],[58.375,5.625],[57.875,7.125],[57.875,10.875],[55.375,13.375],[55.375,14.375],[57.875,22.375],[57.625,23.125],[56.919,23.984]]],["NUU","THE",[[63.875,-52.125],[61.125,-49.125],[36.625,-8.875],[35.875,-5.375],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.375],[36.375,23.125],[37.875,24.375],[38.875,24.125],[40.125,22.875]]],["OLD","COL",[[15.625,73.625],[12.625,74.625],[8.875,76.375],[7.875,77.375],[6.875,79.625]]],["OLD","KOC",[[15.625,73.625],[12.625,74.625],[9.875,76.125]]],["OLD","PTT",[[15.625,73.625],[12.625,74.625],[8.875,76.375],[7.875,77.375],[5.875,80.375],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[1.375,104.375],[4.875,103.875],[6.625,102.125],[6.875,101.375],[6.87,101.25]]],["OPO","BRS",[[41.125,-9.125],[42.875,-9.625],[50.125,-5.875],[51.125,-4.875],[51.375,-4.125],[51.45,-2.6]]],["OPO","CAD",[[41.125,-9.125],[38.875,-9.875],[36.875,-9.125],[36.625,-8.875],[36.375,-6.375]]],["OPO","FAM",[[41.125,-9.125],[38.875,-9.875],[36.875,-9.125],[36.625,-8.875],[35.875,-5.375],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.375],[35.625,34.125],[35.125,34.125]]],["OPO","PLM",[[41.125,-9.125],[38.875,-9.875],[36.875,-9.125],[36.625,-8.875],[35.875,-5.375],[36.625,-1.875],[39.625,2.625],[39.57,2.65]]],["OPO","TRO",[[41.125,-9.125],[42.875,-9.625],[53.875,-10.125],[64.125,0.125],[64.125,9.625]]],["ORA","ANC",[[35.875,-0.625],[37.375,1.875],[37.375,12.875],[37.125,13.125],[36.375,15.125],[39.875,18.625],[40.375,18.625],[43.625,13.875],[43.62,13.52]]],["ORA","MES",[[35.875,-0.625],[38.375,3.375],[38.375,15.375]]],["ORA","SVQ",[[35.875,-0.625],[35.875,-5.875],[36.625,-6.625],[37.125,-6.125],[37.394,-6.003]]],["OSA","BUS",[[34.3,135],[33.625,134.875],[33.125,134.375],[30.875,130.875],[30.875,130.625],[31.375,130.125],[32.875,129.375],[35.125,129.375]]],["OSA","CEB",[[34.3,135],[33.625,134.875],[11.125,126.125],[10.125,125.375],[10.375,124.125]]],["OSA","NIN",[[34.3,135],[33.625,134.875],[33.125,134.375],[30.875,130.875],[30.125,121.875]]],["OSA","TAI",[[34.3,135],[33.625,134.875],[33.125,134.375],[30.875,130.875],[25.125,121.125],[24.125,120.125],[23.375,119.875],[22.875,119.875]]],["OUI","AGA",[[6.125,2.125],[4.625,-1.375],[4.125,-8.125],[4.875,-9.375],[7.375,-12.875],[12.125,-16.875],[14.875,-17.625],[23.875,-17.125],[30.375,-10.625],[30.375,-9.875]]],["OUI","CON",[[6.125,2.125],[-55.625,-65.625],[-55.625,-72.125],[-51.875,-75.875],[-46.625,-75.875],[-37.375,-73.875],[-36.625,-73.125]]],["PAI","CLL",[[-5.125,-81.375],[-8.125,-81.125],[-12.125,-77.375]]],["PAI","COQ",[[-5.125,-81.375],[-21.875,-79.625],[-29.875,-71.625]]],["PAI","GYE",[[-5.125,-81.375],[-4.375,-81.625],[-2.375,-79.875],[-2.19,-79.89]]],["PAI","REA",[[-5.125,-81.375],[-4.375,-81.625],[12.375,-87.375]]],["PAL","BAR",[[38.12,13.36],[38.875,9.125],[38.875,8.375],[41.125,2.125]]],["PAL","CAP",[[38.12,13.36],[38.375,12.125],[35.875,-5.875],[33.125,-9.125],[22.625,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[4.875,-1.125]]],["PAL","ELM",[[38.12,13.36],[38.375,12.125],[35.875,-5.875],[33.125,-9.125],[22.625,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[4.875,-1.125]]],["PAL","TAN",[[38.12,13.36],[38.375,12.125],[35.77,-5.8]]],["PAN","BUV",[[8.875,-79.375],[3.875,-77.375]]],["PAN","CLL",[[8.875,-79.375],[-4.875,-81.625],[-8.625,-80.625],[-12.125,-77.375]]],["PAN","GYE",[[8.875,-79.375],[-1.625,-81.125],[-2.375,-81.125],[-2.875,-80.375],[-2.375,-79.875],[-2.19,-79.89]]],["PAN","PAI",[[8.875,-79.375],[-4.875,-81.625],[-5.125,-81.375]]],["PAR","ARP",[[6.125,-55.125],[50.375,-2.875],[50.625,0.625],[51.625,3.125],[51.203,4.389]]],["PAR","MRS",[[6.125,-55.125],[35.875,-5.875],[35.875,-5.125],[36.625,-1.875],[37.625,-0.375],[43.125,5.375]]],["PAR","OPO",[[6.125,-55.125],[41.125,-9.125]]],["PAR","POR",[[6.125,-55.125],[17.375,-68.625],[17.625,-76.875]]],["PAR","REC",[[6.125,-55.125],[4.875,-45.375],[-5.625,-34.875],[-7.625,-34.375],[-8.125,-34.625]]],["PAR","RIO",[[6.125,-55.125],[4.875,-45.375],[-5.625,-34.875],[-7.625,-34.375],[-20.875,-39.625],[-23.125,-41.875],[-23.125,-43.125]]],["PAR","VER",[[6.125,-55.125],[17.375,-68.625],[17.375,-71.375],[17.875,-74.125],[21.625,-87.125],[21.375,-94.125],[19.375,-96.125]]],["PAT","ALG",[[37.625,21.125],[36.375,15.125],[37.375,9.625],[36.78,3.06]]],["PAT","ANT",[[37.625,21.125],[36.875,21.375],[36.375,22.125],[36.125,30.375],[36.625,30.875]]],["PAT","LIV",[[37.625,21.125],[36.375,15.125],[37.375,12.375],[37.625,12.125],[43.125,10.125],[43.625,10.125]]],["PLM","ACC",[[39.57,2.65],[37.375,-0.625],[36.625,-2.125],[35.625,-6.625],[24.625,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[5.375,-0.125]]],["PLM","PAL",[[39.57,2.65],[38.375,13.125],[38.12,13.36]]],["PLM","SAF",[[39.57,2.65],[37.375,-0.625],[36.625,-2.125],[35.625,-6.625],[32.875,-9.375],[32.625,-9.375]]],["PLM","TUN",[[39.57,2.65],[37.375,10.125],[36.875,10.375]]],["PLO","KOC",[[-20.16,57.5],[9.875,76.125]]],["PLO","KOL",[[-20.16,57.5],[8.875,76.375]]],["PLY","AMS",[[50.125,-4.125],[50.625,0.625],[52.875,4.375]]],["PLY","COP",[[50.125,-4.125],[50.625,0.625],[51.375,1.625],[57.875,9.125],[57.875,10.625],[55.728,12.823]]],["PLY","CRK",[[50.125,-4.125],[49.875,-5.625],[51.625,-8.375]]],["PLY","HRN",[[50.125,-4.125],[50.625,0.625],[53.125,4.625]]],["PLY","NEW",[[50.125,-4.125],[49.875,-5.625],[40.625,-72.875],[40.625,-73.875]]],["PLY","SVQ",[[50.125,-4.125],[42.625,-9.875],[38.875,-9.875],[36.875,-9.125],[36.625,-8.875],[36.875,-6.375],[37.394,-6.003]]],["PON","CAL",[[37.74,-25.67],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.125,7.875],[4.375,8.375]]],["PON","FEO",[[37.74,-25.67],[35.875,-5.125],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.375],[36.375,23.125],[39.875,26.375],[40.375,26.875],[40.875,28.375],[40.875,28.875],[44.125,32.375],[44.125,33.875],[44.625,35.125],[44.875,35.375]]],["PON","SAO",[[37.74,-25.67],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[0.34,6.73]]],["PON","THE",[[37.74,-25.67],[35.875,-5.125],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.375],[36.375,23.125],[37.875,24.375],[38.875,24.125],[40.125,22.875]]],["PON","ZAK",[[37.74,-25.67],[35.875,-5.125],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.125],[37.8,20.75]]],["POR","PAR",[[17.625,-76.875],[10.375,-59.375],[6.125,-55.125]]],["POR","QUE",[[17.625,-76.875],[17.875,-76.375],[20.125,-74.125],[45.875,-59.625],[46.875,-60.375],[49.125,-63.625],[49.125,-65.375],[48.875,-65.875],[48.375,-69.125],[47.625,-69.875],[46.875,-70.875],[46.8,-71.2]]],["PRT","CAD",[[9.55,-79.65],[36.375,-10.125],[36.375,-6.375]]],["PRT","ROT",[[9.55,-79.65],[50.625,-1.125],[50.625,0.625],[52.125,3.875]]],["PRT","SGO",[[9.55,-79.65],[18.46,-69.94]]],["PRT","VER",[[9.55,-79.65],[21.625,-86.875],[21.375,-94.125],[19.375,-96.125]]],["PRT","WIL",[[9.55,-79.65],[12.625,-71.875],[12.11,-68.93]]],["PTH","LPA",[[50.625,-1.125],[48.875,-4.625],[35.875,-15.375],[28.13,-15.43]]],["PTH","SET",[[50.625,-1.125],[48.875,-4.625],[42.625,-9.875],[38.875,-9.875],[38.125,-9.375],[38.125,-9.125]]],["PTH","STO",[[50.625,-1.125],[50.625,0.625],[51.375,1.625],[57.875,9.125],[57.875,10.875],[55.375,13.375],[55.375,14.375],[55.875,15.875],[56.375,16.375],[59.125,18.375],[59.375,18.375]]],["PTH","TRO",[[50.625,-1.125],[50.625,0.625],[51.125,1.375],[52.125,1.875],[62.125,4.875],[64.125,6.875],[64.125,9.625]]],["PTT","AYU",[[6.87,101.25],[14.36,100.6]]],["PTT","COL",[[6.87,101.25],[6.875,101.875],[4.375,104.375],[1.375,104.375],[1.125,104.125],[1.625,102.625],[5.875,96.375],[5.875,80.375],[6.625,79.625],[6.875,79.625]]],["PTT","MAT",[[6.87,101.25],[8.625,105.625],[11.125,108.875],[11.625,109.375],[24.375,120.375],[41.375,137.375],[41.43,140.11]]],["PUL","MAC",[[13.625,80.375],[3.625,100.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[1.375,104.375],[12.375,109.625],[22.19,113.54]]],["PUL","MOK",[[13.625,80.375],[3.625,100.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[34.875,126.125]]],["QUA","BAN",[[24.625,118.875],[1.125,104.125],[1.625,102.625],[5.375,97.125],[5.625,95.875],[5.55,95.32]]],["QUA","BUS",[[24.625,118.875],[35.125,129.375]]],["QUA","GUA",[[24.625,118.875],[23.875,118.125],[22.625,116.125],[22.125,114.125],[22.625,113.625],[23.1,113.3]]],["QUA","INC",[[24.625,118.875],[25.375,119.625],[28.625,122.125],[36.625,125.875],[37.125,126.375]]],["QUA","MAC",[[24.625,118.875],[23.875,118.125],[22.625,116.125],[22.125,113.875],[22.19,113.54]]],["QUA","MNL",[[24.625,118.875],[15.375,119.625],[14.875,119.875],[14.375,120.375],[14.375,120.625]]],["QUA","NAG",[[24.625,118.875],[32.625,129.625]]],["QUA","NAH",[[24.625,118.875],[26.125,124.625],[26.21,127.68]]],["QUA","SYD",[[24.625,118.875],[22.125,120.375],[-6.375,148.125],[-10.375,151.125],[-28.625,153.875],[-32.375,153.125],[-34.125,151.375]]],["QUE","CRK",[[46.8,-71.2],[47.875,-69.625],[48.625,-68.125],[48.875,-65.625],[49.125,-64.875],[48.125,-60.125],[47.375,-59.375],[46.375,-53.375],[51.625,-8.375]]],["QUE","MLG",[[46.8,-71.2],[47.875,-69.625],[48.625,-68.125],[48.875,-65.625],[49.125,-64.875],[48.125,-60.125],[47.375,-59.375],[35.875,-5.375],[36.375,-4.375],[36.625,-4.125]]],["QUE","POR",[[46.8,-71.2],[47.875,-69.625],[48.625,-68.125],[48.875,-65.625],[49.125,-64.875],[48.625,-62.125],[46.125,-59.625],[45.875,-59.625],[19.875,-74.375],[17.625,-76.625],[17.625,-76.875]]],["QUE","STJ",[[46.8,-71.2],[47.875,-69.625],[48.625,-68.125],[48.875,-65.625],[49.125,-64.875],[48.125,-60.125],[47.375,-59.375],[46.375,-53.375],[46.875,-52.625],[47.625,-52.375]]],["REA","ACA",[[12.375,-87.375],[16.375,-99.375],[16.625,-99.875]]],["REA","BUV",[[12.375,-87.375],[10.125,-86.125],[3.875,-77.375]]],["REA","PAN",[[12.375,-87.375],[10.125,-86.125],[8.125,-83.375],[7.125,-80.625],[7.125,-80.375],[7.625,-79.875],[8.625,-79.375],[8.875,-79.375]]],["REC","BEL",[[-8.125,-34.625],[-7.375,-34.375],[-5.625,-34.875],[-5.125,-35.375],[-2.625,-39.875],[-0.625,-47.125],[-0.625,-47.625],[-1.4,-48.5]]],["REC","BRI",[[-8.125,-34.625],[-7.375,-34.375],[-5.625,-34.875],[13.125,-56.125],[13.1,-59.62]]],["REC","CUM",[[-8.125,-34.625],[-7.375,-34.375],[-5.625,-34.875],[11.125,-53.875],[11.125,-63.875],[10.875,-64.125]]],["REC","RIO",[[-8.125,-34.625],[-20.125,-38.875],[-23.125,-41.875],[-23.125,-43.125]]],["REC","SLV",[[-8.125,-34.625],[-9.625,-35.125],[-12.625,-37.875],[-13.125,-38.375]]],["REC","WIL",[[-8.125,-34.625],[-7.375,-34.375],[-5.625,-34.875],[12.125,-54.875],[12.11,-68.93]]],["REY","BAR",[[64.375,-22.125],[63.875,-22.375],[36.875,-9.125],[36.625,-8.875],[35.875,-5.375],[36.625,-1.875],[37.625,-0.375],[41.125,2.125]]],["REY","BOS",[[64.375,-22.125],[46.375,-53.375],[43.375,-65.625],[42.375,-70.625]]],["REY","TOR",[[64.375,-22.125],[63.875,-22.375],[63.625,-22.125],[62.01,-6.77]]],["REY","TRI",[[64.375,-22.125],[63.875,-22.375],[36.875,-9.125],[36.625,-8.875],[35.875,-5.375],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.375],[35.625,34.125],[34.375,35.625]]],["RHO","FAM",[[36.43,28.22],[36.125,30.125],[35.625,34.125],[35.125,34.125]]],["RHO","IST",[[36.43,28.22],[36.875,27.375],[38.125,26.125],[39.625,26.125],[40.125,26.625],[40.625,27.375],[40.875,28.875]]],["RHO","MLG",[[36.43,28.22],[36.375,15.125],[37.375,9.625],[36.625,-3.875],[36.625,-4.125]]],["RHO","NAN",[[36.43,28.22],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[35.875,-5.875],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[42.875,-9.625],[46.875,-4.875],[46.875,-2.125],[47.2,-1.7]]],["RIG","BRS",[[56.919,23.984],[57.875,22.625],[56.625,16.625],[55.875,15.875],[55.375,14.125],[55.375,13.375],[57.875,10.375],[56.625,6.875],[50.875,1.125],[50.625,0.125],[49.875,-5.625],[50.125,-5.875],[51.125,-4.875],[51.375,-4.125],[51.45,-2.6]]],["RIG","COP",[[56.919,23.984],[57.875,22.625],[56.625,16.625],[55.875,15.875],[55.375,14.125],[55.375,13.375],[55.728,12.823]]],["RIG","HAM",[[56.919,23.984],[57.875,22.625],[56.625,16.625],[55.875,15.875],[55.375,14.125],[55.375,13.375],[57.875,10.375],[57.125,8.375],[56.625,7.875],[55.375,7.875],[54.125,8.375],[53.875,8.625],[53.5,9.9]]],["RIG","LUB",[[56.919,23.984],[57.875,22.625],[56.625,16.625],[55.875,15.875],[54.125,11.125]]],["RIG","ROT",[[56.919,23.984],[57.875,22.625],[56.625,16.625],[55.875,15.875],[55.375,14.125],[55.375,13.375],[57.875,10.375],[57.125,8.375],[52.375,3.875],[52.125,3.875]]],["RIG","SAF",[[56.919,23.984],[57.875,22.625],[56.625,16.625],[55.875,15.875],[55.375,14.125],[55.375,13.375],[57.875,10.375],[56.625,6.875],[50.875,1.125],[48.875,-4.625],[42.625,-9.875],[38.875,-9.875],[32.625,-9.375]]],["RIO","BRI",[[-23.125,-43.125],[-23.125,-41.875],[-15.125,-34.375],[-7.375,-34.375],[-5.625,-34.875],[13.125,-56.125],[13.1,-59.62]]],["RIO","BUE",[[-23.125,-43.125],[-33.375,-52.625],[-35.125,-54.375],[-34.605,-58.382]]],["RIO","SLV",[[-23.125,-43.125],[-23.125,-41.875],[-19.375,-38.375],[-13.125,-38.375]]],["ROT","HRN",[[52.125,3.875],[52.875,4.375],[53.125,4.625]]],["ROT","LAG",[[52.125,3.875],[50.625,0.625],[48.875,-4.625],[33.125,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[6.125,3.375]]],["ROT","SAI",[[52.125,3.875],[50.625,0.625],[48.875,-4.625],[33.375,-17.375],[21.125,-17.375],[16.375,-16.875],[16.125,-16.625]]],["ROT","STA",[[52.125,3.875],[50.625,0.625],[29.875,-81.125]]],["ROT","TUR",[[52.125,3.875],[53.375,4.625],[57.875,9.125],[57.875,10.875],[55.375,13.375],[55.375,14.375],[55.875,15.875],[60.375,22.125]]],["SAF","ELM",[[32.625,-9.375],[22.875,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[4.875,-1.125]]],["SAF","GOR",[[32.625,-9.375],[22.875,-17.625],[14.625,-17.625]]],["SAF","LAR",[[32.625,-9.375],[40.625,-9.875],[42.875,-9.625],[46.125,-5.875],[46.033,-1.487]]],["SAF","LON",[[32.625,-9.375],[40.625,-9.875],[44.125,-9.375],[50.375,-3.125],[50.625,0.625],[51.125,1.375],[51.375,1.125],[51.5,-0.1]]],["SAF","OPO",[[32.625,-9.375],[40.375,-9.875],[41.125,-9.125]]],["SAF","STJ",[[32.625,-9.375],[47.625,-52.375]]],["SAF","TEN",[[32.625,-9.375],[28.47,-16.25]]],["SAI","ALG",[[16.125,-16.625],[16.875,-16.875],[22.375,-17.375],[30.375,-11.875],[35.875,-6.375],[35.875,-5.125],[36.875,2.375],[36.78,3.06]]],["SAI","CID",[[16.125,-16.625],[14.92,-23.6]]],["SAI","KAL",[[16.125,-16.625],[16.875,-16.875],[22.375,-17.375],[44.625,-8.875],[50.375,-3.125],[50.625,0.625],[51.375,1.625],[57.875,9.125],[57.875,10.875],[55.375,13.375],[55.125,20.375]]],["SAI","STG",[[16.125,-16.625],[32.38,-64.68]]],["SAI","TAL",[[16.125,-16.625],[16.875,-16.875],[22.375,-17.375],[44.625,-8.875],[50.375,-3.125],[50.625,0.625],[51.375,1.625],[57.875,9.125],[57.875,10.875],[55.375,13.375],[55.375,14.375],[58.375,23.375],[59.447,24.729]]],["SAK","BUS",[[34.3,135],[33.625,134.875],[33.125,134.375],[30.875,130.875],[30.875,130.625],[31.375,130.125],[32.875,129.375],[35.125,129.375]]],["SAK","FUZ",[[34.3,135],[33.625,134.875],[33.125,134.375],[30.875,130.875],[25.625,119.625]]],["SAK","MAT",[[34.3,135],[33.875,135.125],[33.375,135.625],[34.875,140.125],[35.875,141.125],[39.375,142.125],[40.875,142.125],[41.625,141.375],[41.375,140.875],[41.43,140.11]]],["SAK","MOK",[[34.3,135],[33.625,134.875],[33.125,134.375],[30.875,130.875],[30.875,130.625],[34.625,126.125],[34.875,126.125]]],["SAK","NIN",[[34.3,135],[33.625,134.875],[33.125,134.375],[30.875,130.875],[30.125,121.875]]],["SAL","ALG",[[34.125,-7.125],[35.125,-6.625],[35.625,-6.125],[35.875,-5.875],[36.875,2.375],[36.78,3.06]]],["SAL","BOR",[[34.125,-7.125],[36.875,-9.125],[39.125,-9.875],[42.875,-9.625],[45.625,-6.375],[45.625,-1.375],[44.9,-0.6]]],["SAL","CAD",[[34.125,-7.125],[36.375,-6.375]]],["SAL","CRK",[[34.125,-7.125],[36.875,-9.125],[39.125,-9.875],[51.125,-8.875],[51.625,-8.375]]],["SAL","PLY",[[34.125,-7.125],[36.875,-9.125],[39.125,-9.875],[44.875,-9.375],[50.125,-4.125]]],["SAN","BEL",[[18.625,-66.125],[18.625,-65.625],[1.625,-48.625],[-0.875,-48.375],[-1.4,-48.5]]],["SAN","BRI",[[18.625,-66.125],[18.375,-64.875],[13.1,-59.62]]],["SAN","CUM",[[18.625,-66.125],[18.625,-65.625],[16.125,-64.125],[10.875,-64.125]]],["SAN","HAV",[[18.625,-66.125],[23.375,-80.625],[23.375,-82.375]]],["SAN","TEN",[[18.625,-66.125],[28.47,-16.25]]],["SAO","ACC",[[0.34,6.73],[5.375,-0.125]]],["SAO","SNT",[[0.34,6.73],[4.375,-8.625],[4.875,-9.375],[7.375,-12.875],[12.125,-16.875],[14.875,-17.625],[37.125,-16.375],[49.125,-4.375],[49.125,-2.375],[48.875,-2.125]]],["SAO","SOY",[[0.34,6.73],[-6.125,12.125]]],["SAO","TAN",[[0.34,6.73],[4.375,-8.625],[4.875,-9.375],[7.375,-12.875],[12.125,-16.875],[14.875,-17.625],[25.125,-17.125],[35.875,-6.375],[35.77,-5.8]]],["SDG","ACA",[[32.625,-117.375],[31.875,-117.125],[27.625,-115.125],[22.625,-110.125],[18.125,-103.625],[16.625,-100.125],[16.625,-99.875]]],["SDG","SFR",[[32.625,-117.375],[34.625,-120.875],[37.125,-122.625],[37.8,-122.42]]],["SET","BRI",[[38.125,-9.125],[13.1,-59.62]]],["SET","GOA",[[38.125,-9.125],[36.875,-9.125],[36.625,-8.875],[35.875,-5.375],[36.625,-1.875],[37.625,-0.375],[44.125,8.875]]],["SET","LEH",[[38.125,-9.125],[38.375,-9.625],[39.125,-9.875],[43.875,-9.625],[49.875,-3.625],[49.875,-0.625],[49.625,-0.375]]],["SET","MLG",[[38.125,-9.125],[36.875,-9.125],[36.625,-8.875],[35.875,-5.375],[36.375,-4.375],[36.625,-4.125]]],["SET","SGO",[[38.125,-9.125],[18.125,-68.875],[18.46,-69.94]]],["SET","TRA",[[38.125,-9.125],[36.875,-9.125],[36.625,-8.875],[35.875,-5.375],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.375],[36.375,23.125],[39.875,26.375],[40.375,26.875],[40.875,28.375],[40.875,28.875],[42.125,30.125],[42.125,38.625],[41.01,39.72]]],["SFR","MZT",[[37.8,-122.42],[37.125,-122.625],[34.375,-120.625],[27.375,-114.875],[22.625,-110.125],[23.125,-106.625]]],["SGO","HAV",[[18.46,-69.94],[17.375,-71.375],[17.875,-74.125],[18.375,-74.625],[20.375,-74.125],[23.375,-79.375],[23.375,-82.375]]],["SGO","NUU",[[18.46,-69.94],[18.125,-68.875],[18.125,-68.625],[18.625,-68.125],[47.375,-52.375],[63.875,-52.125]]],["SGO","PRT",[[18.46,-69.94],[9.55,-79.65]]],["SGO","RIG",[[18.46,-69.94],[18.125,-68.875],[18.125,-68.625],[58.875,-5.125],[58.375,5.875],[58.125,6.125],[57.875,7.375],[57.875,10.875],[55.375,13.375],[55.375,14.375],[57.875,22.375],[57.625,23.125],[56.919,23.984]]],["SGO","SAN",[[18.46,-69.94],[18.125,-68.875],[18.625,-66.875],[18.625,-66.125]]],["SHI","NAM",[[34.125,130.625],[34.375,126.375],[34.625,126.125],[38.125,124.375],[38.625,124.875]]],["SHI","QUA",[[34.125,130.625],[31.375,125.625],[24.625,118.875]]],["SHI","TOK",[[34.125,130.625],[33.375,129.375],[32.875,129.375],[31.375,130.125],[30.875,130.625],[34.875,140.125],[35.125,140.375]]],["SLV","BEL",[[-13.125,-38.375],[-9.125,-34.375],[-7.375,-34.375],[-5.625,-34.875],[-5.125,-35.375],[-2.625,-39.875],[-0.625,-47.125],[-0.625,-47.625],[-1.4,-48.5]]],["SLV","CID",[[-13.125,-38.375],[-6.375,-31.625],[14.92,-23.6]]],["SLV","LIS",[[-13.125,-38.375],[-9.125,-34.375],[38.625,-9.625]]],["SLV","LPA",[[-13.125,-38.375],[-9.125,-34.375],[28.13,-15.43]]],["SLV","REC",[[-13.125,-38.375],[-9.625,-34.875],[-8.125,-34.625]]],["SLV","RIO",[[-13.125,-38.375],[-20.375,-39.125],[-23.125,-41.875],[-23.125,-43.125]]],["SLV","SNL",[[-13.125,-38.375],[-8.875,-34.125],[30.875,-12.375],[36.8,-6.4]]],["SNL","BRS",[[36.8,-6.4],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[46.875,-9.125],[51.125,-4.875],[51.375,-4.125],[51.45,-2.6]]],["SNL","CAL",[[36.8,-6.4],[22.625,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.125,7.875],[4.375,8.375]]],["SNL","SNT",[[36.8,-6.4],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[43.875,-9.625],[49.125,-4.375],[49.125,-2.375],[48.875,-2.125]]],["SNL","STG",[[36.8,-6.4],[32.38,-64.68]]],["SNL","SVQ",[[36.8,-6.4],[37.394,-6.003]]],["SNT","BOS",[[48.875,-2.125],[49.125,-3.875],[42.375,-70.625]]],["SNT","GDA",[[48.875,-2.125],[49.625,-2.125],[50.625,-0.875],[50.625,0.625],[51.375,1.625],[57.875,9.125],[57.875,10.875],[55.375,13.375],[54.875,18.625],[54.625,18.875]]],["SNT","KIN",[[48.875,-2.125],[49.625,-2.125],[50.625,-0.875],[50.625,0.625],[51.125,1.375],[52.125,1.875],[52.625,1.875],[53.875,0.125]]],["SNT","LEI",[[48.875,-2.125],[49.625,-2.125],[50.625,-0.875],[50.625,0.625],[51.125,1.375],[52.125,1.875],[52.625,1.875],[56.125,-2.125],[56.125,-2.625]]],["SNT","TRO",[[48.875,-2.125],[49.625,-2.125],[50.625,-0.875],[50.625,0.625],[51.125,1.375],[52.125,1.875],[62.125,4.875],[64.125,6.875],[64.125,9.625]]],["SOF","COL",[[-20.125,34.875],[6.875,79.625]]],["SOF","ISL",[[-20.125,34.875],[-16.625,39.875],[-15.625,40.875],[-15.125,40.875]]],["SOF","JED",[[-20.125,34.875],[-16.625,39.875],[-5.875,49.625],[11.625,51.375],[11.875,51.375],[12.375,50.875],[12.375,43.875],[13.375,42.875],[21.375,38.875],[21.625,38.875]]],["SOS","BRI",[[-24.125,-46.375],[-23.625,-42.375],[-15.625,-34.375],[-7.375,-34.375],[-5.625,-34.875],[13.125,-56.125],[13.1,-59.62]]],["SOS","GOR",[[-24.125,-46.375],[-23.625,-42.375],[-6.625,-25.375],[14.625,-17.625]]],["SOS","RIO",[[-24.125,-46.375],[-23.875,-43.875],[-23.125,-43.125]]],["SOS","SLV",[[-24.125,-46.375],[-23.625,-42.375],[-19.625,-38.375],[-13.125,-38.375]]],["SOY","ELM",[[-6.125,12.125],[4.875,-1.125]]],["SOY","SAO",[[-6.125,12.125],[0.34,6.73]]],["SOY","SPL",[[-6.125,12.125],[4.875,-9.625],[7.375,-12.875],[12.125,-16.875],[14.875,-17.625],[25.125,-17.125],[35.875,-6.375],[35.875,-5.125],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.125],[39.875,18.625],[41.125,18.375],[43.375,16.125]]],["SPL","LPA",[[43.375,16.125],[40.375,18.625],[39.875,18.625],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[35.625,-7.875],[28.13,-15.43]]],["SPL","STJ",[[43.375,16.125],[40.375,18.625],[39.875,18.625],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[35.875,-5.875],[47.625,-52.375]]],["SPL","VLL",[[43.375,16.125],[40.375,18.625],[39.875,18.625],[35.875,14.625],[35.9,14.51]]],["SRT","ADE",[[21.125,72.375],[20.625,71.375],[12.625,45.125]]],["SRT","HOR",[[21.125,72.375],[20.625,71.375],[20.625,70.375],[25.625,57.375],[26.875,56.375]]],["SRT","KIL",[[21.125,72.375],[-8.98,39.52]]],["SRT","ULS",[[21.125,72.375],[17.375,72.875],[15.875,73.375],[12.125,74.875],[8.875,76.375],[7.875,77.375],[5.875,80.375],[5.625,98.375],[2.125,101.875],[1.375,103.125],[1.125,104.125],[30.125,124.375],[35.375,129.625],[35.625,129.625]]],["STA","CUM",[[29.875,-81.125],[24.375,-73.875],[14.625,-64.125],[10.875,-64.125]]],["STA","SET",[[29.875,-81.125],[38.125,-9.125]]],["STG","BRS",[[32.38,-64.68],[51.375,-4.125],[51.45,-2.6]]],["STG","CAR",[[32.38,-64.68],[17.125,-75.625],[10.625,-75.625]]],["STG","NEW",[[32.38,-64.68],[40.625,-73.875]]],["STG","NUU",[[32.38,-64.68],[46.875,-52.625],[47.625,-52.375],[63.875,-52.125]]],["STJ","BOS",[[47.625,-52.375],[46.875,-52.625],[46.375,-53.375],[43.375,-65.625],[42.375,-70.625]]],["STJ","BRI",[[47.625,-52.375],[13.1,-59.62]]],["STJ","LPA",[[47.625,-52.375],[28.13,-15.43]]],["STJ","NAN",[[47.625,-52.375],[47.2,-1.7]]],["STJ","SNL",[[47.625,-52.375],[36.625,-8.375],[36.8,-6.4]]],["STJ","TRO",[[47.625,-52.375],[64.125,9.625]]],["STJ","TRP",[[47.625,-52.375],[35.875,-5.625],[37.375,6.625],[37.375,10.875],[34.875,13.375],[32.875,13.375]]],["STO","AGA",[[59.375,18.375],[57.875,17.125],[56.125,16.125],[55.875,15.625],[55.375,14.125],[55.375,13.375],[57.875,10.375],[56.625,6.875],[50.875,1.125],[48.875,-4.625],[42.375,-10.125],[30.875,-10.125],[30.375,-9.875]]],["STO","CLS",[[59.375,18.375],[57.875,17.125],[56.125,16.125],[55.875,15.625],[55.375,14.125],[55.375,13.375],[57.875,10.375],[56.875,7.625],[51.125,1.875]]],["STO","DUB",[[59.375,18.375],[57.875,17.125],[56.125,16.125],[55.875,15.625],[55.375,14.125],[55.375,13.375],[57.875,10.375],[57.875,6.875],[58.875,-4.625],[58.875,-5.125],[57.625,-6.375],[56.875,-6.375],[54.375,-5.625],[53.375,-5.875]]],["STO","GDA",[[59.375,18.375],[54.625,18.875]]],["STO","LUB",[[59.375,18.375],[57.875,17.125],[56.125,16.125],[55.875,15.625],[54.125,11.125]]],["STO","TOR",[[59.375,18.375],[57.875,17.125],[56.125,16.125],[55.875,15.625],[55.375,14.125],[55.375,13.375],[57.875,10.375],[57.875,6.875],[62.01,-6.77]]],["STO","TUR",[[59.375,18.375],[60.375,22.125]]],["SUA","SUE",[[19.375,37.375],[24.625,37.125],[28.375,33.375],[29.125,32.875],[29.9,32.6]]],["SUE","KAR",[[29.9,32.6],[29.125,32.875],[13.875,42.875],[13.375,42.875],[12.375,43.875],[12.625,45.125],[13.875,48.875],[16.875,55.125],[24.625,66.875]]],["SUE","MAS",[[29.9,32.6],[29.125,32.875],[18.875,39.625],[15.875,39.625]]],["SUE","MOC",[[29.9,32.6],[29.125,32.875],[13.875,42.875],[13.125,43.125]]],["SUR","GUA",[[-7.125,112.875],[-1.125,108.625],[14.125,109.625],[22.125,113.625],[22.875,113.625],[23.1,113.3]]],["SUR","INC",[[-7.125,112.875],[-3.625,116.625],[0.875,118.875],[11.875,119.875],[18.625,119.625],[26.375,120.125],[26.875,120.625],[28.625,122.125],[36.625,125.875],[37.125,126.375]]],["SUR","MAL",[[-7.125,112.875],[1.625,102.875],[1.625,102.625],[2.125,102.125]]],["SVQ","ANG",[[37.394,-6.003],[36.875,-6.375],[36.625,-8.875],[38.66,-27.22]]],["SVQ","CAD",[[37.394,-6.003],[36.875,-6.375],[36.375,-6.375]]],["SVQ","KAL",[[37.394,-6.003],[36.875,-6.375],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[43.875,-9.625],[50.375,-3.125],[50.625,0.625],[51.375,1.625],[57.875,9.125],[57.875,10.875],[55.375,13.375],[55.125,20.375]]],["SVQ","MRS",[[37.394,-6.003],[36.875,-6.375],[36.625,-6.625],[35.875,-5.875],[35.875,-5.125],[36.625,-1.875],[37.625,-0.375],[43.125,5.375]]],["SYD","HON",[[-34.125,151.375],[-31.125,153.875],[-28.125,153.875],[-25.375,153.125],[-10.875,142.875],[-10.625,142.625],[-8.625,137.625],[-5.375,134.625],[-3.875,132.625],[0.125,129.375],[1.375,128.875],[6.875,123.375],[6.875,121.875],[7.125,121.625],[20.875,115.375],[22.125,114.125]]],["SYD","MAL",[[-34.125,151.375],[-31.125,153.875],[-28.125,153.875],[-25.375,153.125],[-10.875,142.875],[-10.625,142.625],[-3.375,108.125],[2.125,102.125]]],["TAI","CEB",[[22.875,119.875],[12.375,126.125],[11.125,126.125],[10.125,125.375],[10.375,124.125]]],["TAI","KAG",[[22.875,119.875],[23.875,119.875],[31.625,127.625],[31.625,130.125]]],["TAI","NAH",[[22.875,119.875],[23.875,119.875],[26.125,122.125],[26.21,127.68]]],["TAI","NIN",[[22.875,119.875],[26.625,120.375],[28.625,122.125],[29.875,122.375],[30.125,121.875]]],["TAI","QUA",[[22.875,119.875],[24.625,118.875]]],["TAI","SAK",[[22.875,119.875],[23.875,119.875],[30.875,126.875],[30.875,130.875],[33.375,134.625],[33.625,134.875],[34.3,135]]],["TAL","KAL",[[59.447,24.729],[58.375,23.375],[57.625,21.625],[56.625,20.625],[55.125,20.375]]],["TAL","MID",[[59.447,24.729],[58.375,23.375],[55.375,14.125],[55.375,13.375],[57.875,10.375],[57.125,8.375],[52.125,3.625],[51.469,3.531]]],["TAL","STO",[[59.447,24.729],[59.375,18.375]]],["TAL","TEN",[[59.447,24.729],[58.375,23.375],[55.375,14.125],[55.375,13.375],[57.875,10.375],[56.625,6.875],[50.875,1.125],[48.875,-4.625],[34.875,-16.125],[28.47,-16.25]]],["TAN","BEI",[[35.77,-5.8],[37.375,6.125],[37.375,12.875],[37.125,13.125],[36.375,15.375],[35.375,31.625],[34.625,32.375],[34.375,33.125],[34.125,35.375]]],["TAN","CAG",[[35.77,-5.8],[38.875,9.125],[39.125,9.375]]],["TAN","MID",[[35.77,-5.8],[36.625,-8.875],[36.875,-9.125],[39.125,-9.875],[43.875,-9.625],[50.375,-3.125],[50.625,0.625],[51.625,3.125],[51.469,3.531]]],["TAN","PLM",[[35.77,-5.8],[36.625,-1.875],[39.625,2.625],[39.57,2.65]]],["TAN","SOS",[[35.77,-5.8],[34.375,-7.875],[11.375,-30.625],[-17.875,-36.625],[-24.125,-42.875],[-24.125,-46.375]]],["TEN","ARP",[[28.47,-16.25],[44.875,-8.625],[50.375,-3.125],[50.625,0.625],[51.625,3.125],[51.203,4.389]]],["TEN","CAD",[[28.47,-16.25],[36.375,-6.375]]],["TEN","LON",[[28.47,-16.25],[44.875,-8.625],[50.375,-3.125],[50.625,0.625],[51.125,1.375],[51.375,1.125],[51.5,-0.1]]],["TEN","LPA",[[28.47,-16.25],[28.13,-15.43]]],["TEN","SAL",[[28.47,-16.25],[34.125,-7.625],[34.125,-7.125]]],["TEN","TOU",[[28.47,-16.25],[35.875,-5.875],[35.875,-5.125],[36.625,-1.875],[37.625,-0.375],[43.13,5.93]]],["TEN","VAR",[[28.47,-16.25],[54.375,-9.625],[71.375,7.375],[71.375,30.125],[70.37,31.11]]],["TER","GAL",[[0.875,127.125],[7.125,117.125],[5.375,108.375],[1.125,104.125],[1.625,102.625],[5.875,96.375],[5.875,80.375],[6.03,80.22]]],["TER","GUA",[[0.875,127.125],[7.125,121.625],[20.875,115.375],[22.625,113.625],[23.1,113.3]]],["THA","KHA",[[16.77,96.2],[16.125,96.375],[15.625,95.625],[9.625,79.625],[7.875,77.875],[7.875,77.375],[8.875,76.375],[13.375,74.375],[16.375,73.125],[19.125,72.625],[21.4,72.3]]],["THA","MYE",[[16.77,96.2],[12.375,98.125]]],["THA","YEO",[[16.77,96.2],[8.125,97.875],[2.875,101.125],[2.125,101.875],[1.375,103.125],[1.125,104.125],[33.375,126.625],[34.625,127.875]]],["THE","IST",[[40.125,22.875],[39.875,23.875],[40.125,26.375],[40.875,28.125],[40.875,28.875]]],["THE","LIS",[[40.125,22.875],[38.125,24.375],[37.875,24.375],[36.375,23.125],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[35.875,-5.875],[36.625,-8.875],[36.875,-9.125],[38.625,-9.625]]],["THE","SAF",[[40.125,22.875],[38.125,24.375],[37.875,24.375],[36.375,23.125],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[35.875,-6.375],[33.125,-9.125],[32.625,-9.375]]],["THE","ZAK",[[40.125,22.875],[38.125,24.375],[37.875,24.375],[36.375,23.125],[36.375,22.125],[36.875,21.375],[37.8,20.75]]],["TID","MOG",[[0.625,127.125],[-5.625,123.125],[-5.875,122.375],[-5.625,53.625],[1.875,45.625]]],["TOK","CEB",[[35.125,140.375],[10.375,125.625],[10.125,125.375],[10.375,124.125]]],["TOK","SHI",[[35.125,140.375],[34.625,139.375],[30.875,130.625],[31.375,130.125],[32.875,129.375],[33.375,129.375],[34.125,130.625]]],["TOK","SUR",[[35.125,140.375],[6.625,126.625],[5.375,125.375],[1.125,120.375],[0.125,119.375],[-4.125,116.125],[-7.125,112.875]]],["TOK","ULS",[[35.125,140.375],[34.625,139.375],[30.875,130.625],[31.375,130.125],[32.875,129.375],[35.625,129.625]]],["TON","JEJ",[[34.85,128.42],[33.51,126.52]]],["TON","MNL",[[34.85,128.42],[16.875,119.625],[15.375,119.625],[14.875,119.875],[14.375,120.375],[14.375,120.625]]],["TON","NIN",[[34.85,128.42],[30.125,121.875]]],["TOR","BIL",[[62.01,-6.77],[56.875,-6.375],[54.375,-5.625],[50.125,-5.875],[43.625,-2.875]]],["TOR","KIN",[[62.01,-6.77],[57.125,-1.125],[54.125,0.125],[53.875,0.125]]],["TOR","LON",[[62.01,-6.77],[57.125,-1.125],[52.625,1.875],[52.125,1.875],[51.625,1.125],[51.5,-0.1]]],["TOR","RHO",[[62.01,-6.77],[53.125,-10.125],[38.875,-9.875],[36.875,-9.125],[36.625,-8.875],[35.875,-5.375],[37.375,6.375],[37.375,12.875],[37.125,13.125],[36.375,15.375],[36.43,28.22]]],["TOR","STO",[[62.01,-6.77],[57.875,7.125],[57.875,10.875],[55.375,13.375],[55.375,14.375],[55.875,15.875],[56.375,16.375],[59.125,18.375],[59.375,18.375]]],["TOU","NAP",[[43.13,5.93],[43.125,10.125],[42.125,11.125],[41.375,12.125],[40.625,14.125]]],["TOU","REY",[[43.13,5.93],[37.375,-0.625],[36.625,-2.125],[35.875,-5.625],[36.625,-8.875],[36.875,-9.125],[64.125,-22.625],[64.375,-22.125]]],["TOU","TUN",[[43.13,5.93],[38.875,8.375],[37.125,10.375],[36.875,10.375]]],["TRA","FEO",[[41.01,39.72],[44.875,35.375]]],["TRA","IST",[[41.01,39.72],[42.125,35.125],[41.875,29.875],[40.875,28.875]]],["TRA","ORA",[[41.01,39.72],[42.125,35.125],[41.875,29.875],[40.875,28.875],[40.625,27.375],[40.125,26.625],[36.875,23.375],[36.625,23.375],[36.375,22.875],[36.375,15.125],[37.375,9.625],[36.875,0.375],[35.875,-0.625]]],["TRA","PAL",[[41.01,39.72],[42.125,35.125],[41.875,29.875],[40.875,28.875],[40.625,27.375],[40.125,26.625],[36.875,23.375],[36.625,23.375],[36.375,22.875],[36.375,15.125],[37.375,12.375],[37.625,12.125],[38.375,12.625],[38.12,13.36]]],["TRA","RHO",[[41.01,39.72],[42.125,35.125],[41.875,29.875],[40.875,28.875],[40.625,27.375],[40.125,26.625],[39.625,26.125],[38.125,26.125],[36.625,27.625],[36.43,28.22]]],["TRI","IST",[[34.375,35.625],[35.625,34.125],[36.125,29.375],[36.625,27.625],[38.125,26.125],[39.625,26.125],[40.125,26.625],[40.625,27.375],[40.875,28.875]]],["TRI","PON",[[34.375,35.625],[35.625,34.125],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[37.74,-25.67]]],["TRI","SAI",[[34.375,35.625],[35.625,34.125],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[35.875,-6.375],[24.875,-17.375],[21.125,-17.375],[16.375,-16.875],[16.125,-16.625]]],["TRO","BER",[[64.125,9.625],[62.625,5.375],[62.125,4.875],[60.375,4.875]]],["TRO","BRS",[[64.125,9.625],[58.875,-5.125],[57.625,-6.375],[56.875,-6.375],[53.625,-5.375],[51.625,-5.375],[51.375,-5.125],[51.45,-2.6]]],["TRO","HAM",[[64.125,9.625],[62.625,5.375],[62.125,4.875],[60.125,4.875],[58.625,5.375],[53.875,8.625],[53.5,9.9]]],["TRO","LNG",[[64.125,9.625],[77.125,14.375]]],["TRO","LUB",[[64.125,9.625],[62.625,5.375],[62.125,4.875],[60.125,4.875],[58.625,5.375],[58.375,5.625],[57.875,7.125],[57.875,10.375],[57.125,11.125],[56.375,11.125],[55.625,10.625],[54.125,11.125]]],["TRO","NEW",[[64.125,9.625],[40.625,-72.375],[40.625,-73.875]]],["TRO","PON",[[64.125,9.625],[58.875,-5.125],[37.74,-25.67]]],["TRO","VAR",[[64.125,9.625],[71.375,18.875],[71.375,30.125],[70.37,31.11]]],["TRP","CAG",[[32.875,13.375],[37.375,11.125],[39.125,9.375]]],["TRP","IZM",[[32.875,13.375],[36.375,23.125],[37.875,26.625]]],["TRP","NUU",[[32.875,13.375],[36.875,11.375],[37.375,10.625],[36.375,-4.625],[35.875,-5.125],[35.875,-5.875],[36.625,-8.875],[61.125,-49.125],[63.875,-52.125]]],["TSU","COQ",[[34.2,129.29],[41.375,140.375],[41.625,142.125],[-29.875,-71.625]]],["TSU","TOK",[[34.2,129.29],[32.875,129.375],[31.375,130.125],[30.875,130.625],[34.875,140.125],[35.125,140.375]]],["TUN","PAT",[[36.875,10.375],[37.125,11.125],[36.375,15.125],[37.625,21.125]]],["TUN","PLM",[[36.875,10.375],[37.875,9.625],[39.57,2.65]]],["TUN","TAN",[[36.875,10.375],[37.375,10.125],[36.375,-4.625],[35.875,-5.125],[35.77,-5.8]]],["TUN","TOU",[[36.875,10.375],[37.875,9.625],[39.125,8.125],[43.13,5.93]]],["TUR","AMS",[[60.375,22.125],[55.875,15.875],[55.375,14.125],[55.375,13.375],[57.875,10.375],[57.125,8.375],[52.875,4.375]]],["TUR","BER",[[60.375,22.125],[55.875,15.875],[55.375,14.125],[55.375,13.375],[57.875,10.375],[57.875,6.875],[58.375,5.625],[59.125,5.125],[60.375,4.875]]],["TUR","BRU",[[60.375,22.125],[55.875,15.875],[55.375,14.125],[55.375,13.375],[57.875,10.375],[57.125,8.375],[51.625,3.125],[51.375,3.125]]],["TUR","COP",[[60.375,22.125],[55.875,15.875],[55.375,14.125],[55.375,13.375],[55.728,12.823]]],["TUR","LUB",[[60.375,22.125],[55.875,15.875],[54.125,11.125]]],["TUR","NUU",[[60.375,22.125],[55.875,15.875],[55.375,14.125],[55.375,13.375],[57.875,10.375],[57.875,6.875],[59.875,-15.625],[59.875,-44.875],[60.625,-48.375],[61.125,-49.125],[63.875,-52.125]]],["TUR","TAL",[[60.375,22.125],[59.625,22.875],[59.447,24.729]]],["ULS","JED",[[35.625,129.625],[35.125,129.375],[5.375,104.375],[1.375,104.375],[1.125,104.125],[1.625,102.625],[5.875,96.375],[5.875,80.375],[12.375,49.625],[12.375,43.875],[13.375,42.875],[21.375,38.875],[21.625,38.875]]],["ULS","QUA",[[35.625,129.625],[35.125,129.375],[24.625,118.875]]],["ULS","TSU",[[35.625,129.625],[34.2,129.29]]],["VAL","CAG",[[39.375,0.125],[38.875,9.125],[39.125,9.375]]],["VAL","HER",[[39.375,0.125],[36.375,15.625],[35.875,24.875],[35.625,25.125]]],["VAL","LIV",[[39.375,0.125],[43.625,10.125]]],["VAL","PAL",[[39.375,0.125],[38.375,13.125],[38.12,13.36]]],["VAR","AGA",[[70.37,31.11],[71.375,29.375],[69.875,5.875],[53.875,-10.125],[30.875,-10.125],[30.375,-9.875]]],["VAR","ARK",[[70.37,31.11],[68.375,40.375],[67.625,41.125],[66.875,41.125],[65.375,39.875],[64.875,40.125]]],["VAR","LNG",[[70.37,31.11],[76.625,24.875],[76.625,15.625],[77.125,14.375]]],["VAR","TRO",[[70.37,31.11],[71.375,29.375],[70.625,16.125],[64.125,9.625]]],["VEN","CHS",[[45.375,12.625],[40.375,18.625],[36.625,21.625],[36.375,22.375],[36.375,23.125],[38.4,26.02]]],["VEN","HER",[[45.375,12.625],[40.375,18.625],[36.625,21.625],[36.375,22.375],[35.625,25.125]]],["VEN","ORA",[[45.375,12.625],[40.375,18.625],[39.875,18.625],[36.375,15.125],[37.375,9.625],[36.875,0.375],[35.875,-0.625]]],["VEN","VLL",[[45.375,12.625],[40.375,18.625],[39.875,18.625],[35.875,14.625],[35.9,14.51]]],["VER","CAR",[[19.375,-96.125],[21.625,-88.875],[21.625,-86.625],[10.625,-75.625]]],["VER","CRK",[[19.375,-96.125],[24.875,-80.625],[25.625,-79.875],[26.875,-78.875],[51.625,-8.375]]],["VER","HAV",[[19.375,-96.125],[23.375,-83.125],[23.375,-82.375]]],["VIS","AGA",[[57.63,18.31],[55.875,15.875],[55.375,14.125],[55.375,13.375],[57.875,10.375],[56.625,6.875],[50.875,1.125],[48.875,-4.625],[42.375,-10.125],[30.875,-10.125],[30.375,-9.875]]],["VIS","AMS",[[57.63,18.31],[55.875,15.875],[55.375,14.125],[55.375,13.375],[57.875,10.375],[57.125,8.375],[52.875,4.375]]],["VIS","GDA",[[57.63,18.31],[54.625,18.875]]],["VIS","NUU",[[57.63,18.31],[55.875,15.875],[55.375,14.125],[55.375,13.375],[57.875,10.375],[57.875,6.875],[59.875,-15.625],[59.875,-44.875],[60.625,-48.375],[61.125,-49.125],[63.875,-52.125]]],["VIS","PTH",[[57.63,18.31],[55.875,15.875],[55.375,14.125],[55.375,13.375],[57.875,10.375],[56.625,6.875],[50.875,1.125],[50.625,0.125],[50.625,-1.125]]],["VLL","ANC",[[35.9,14.51],[36.625,15.375],[39.875,18.625],[40.375,18.625],[43.625,13.875],[43.62,13.52]]],["VLL","CHS",[[35.9,14.51],[36.375,23.125],[38.4,26.02]]],["VLL","HER",[[35.9,14.51],[35.875,24.875],[35.625,25.125]]],["VLL","PON",[[35.9,14.51],[37.375,10.125],[36.375,-4.625],[35.875,-5.125],[37.74,-25.67]]],["VLP","ARI",[[-33.125,-71.875],[-30.625,-71.875],[-18.375,-70.625]]],["VLP","CON",[[-33.125,-71.875],[-36.125,-73.125],[-36.625,-73.125]]],["WIL","HAV",[[12.11,-68.93],[18.375,-74.625],[20.375,-74.125],[23.375,-79.375],[23.375,-82.375]]],["WIL","JAM",[[12.11,-68.93],[19.625,-68.125],[36.875,-75.625],[37.125,-76.125]]],["WIL","SET",[[12.11,-68.93],[38.125,-9.125]]],["XIA","BND",[[24.125,118.375],[12.375,127.125],[-2.875,127.125],[-4.375,128.625],[-4.51,129.9]]],["XIA","GUA",[[24.125,118.375],[22.625,116.125],[22.125,114.125],[22.625,113.625],[23.1,113.3]]],["XIA","HON",[[24.125,118.375],[22.625,116.125],[22.125,114.125]]],["XIA","MNL",[[24.125,118.375],[15.375,119.625],[14.875,119.875],[14.375,120.375],[14.375,120.625]]],["XIA","TAI",[[24.125,118.375],[22.875,119.875]]],["XIA","ULS",[[24.125,118.375],[35.375,129.625],[35.625,129.625]]],["YEO","QUA",[[34.625,127.875],[25.125,119.375],[24.625,118.875]]],["YEO","TER",[[34.625,127.875],[0.875,127.125]]],["ZAK","ANT",[[37.8,20.75],[36.625,21.625],[36.375,22.375],[36.125,30.375],[36.625,30.875]]],["ZAK","ELM",[[37.8,20.75],[36.375,15.125],[37.375,9.625],[36.375,-4.625],[35.875,-5.125],[35.875,-6.375],[24.625,-17.625],[14.625,-17.625],[12.125,-16.875],[7.375,-12.875],[4.625,-9.125],[4.125,-8.125],[4.625,-1.375],[4.875,-1.125]]],["ZAK","LIV",[[37.8,20.75],[36.375,15.125],[37.375,12.375],[37.625,12.125],[43.125,10.125],[43.625,10.125]]],["ZAK","MRS",[[37.8,20.75],[36.375,15.125],[37.375,12.375],[41.375,9.375],[41.375,8.875],[43.125,5.375]]],["ZAN","ADE",[[-6.17,39.2],[3.375,47.375],[5.625,49.125],[9.125,50.875],[10.875,51.375],[11.875,51.375],[12.625,50.375],[12.625,45.125]]],["ZAN","BUS",[[-6.17,39.2],[5.625,95.625],[5.375,98.625],[2.125,101.875],[1.375,103.125],[1.125,104.125],[30.125,124.375],[35.125,129.375]]],["ZAN","KIL",[[-6.17,39.2],[-6.875,39.625],[-8.98,39.52]]],["ZAN","MLE",[[-6.17,39.2],[4.18,73.51]]],["ZAN","MOG",[[-6.17,39.2],[1.875,45.625]]]]$seed$::jsonb) x
  join public.ports pa on pa.code = x->>0
  join public.ports pb on pb.code = x->>1
 where not exists (select 1 from public.npc_courses c where c.from_port = pa.id and c.to_port = pb.id);

-- ── 3. THE HUNKS (sliced from the live bodies; each occurs once; each body reverses; ACL unchanged)
create temporary table hunks_0203 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n)) on commit drop;
insert into hunks_0203 values
-- voyage.ship_speed: THE formula now lives in voyage.ship_speed_at; this answers at the fill she carries.
('voyage.ship_speed(uuid)', 1,
$h$declare
  s     public.ships%rowtype;
  c     public.ship_classes%rowtype;
  v_fill    numeric;
  v_hull    numeric;
  v_load    numeric;
  v_crew    numeric;
  v_cargo_t numeric;
begin
  select * into s from public.ships where id = p_ship;
  select * into c from public.ship_classes where id = s.class_id;
  if s.id is null then
    raise exception 'E_NO_SUCH_SHIP: %', p_ship using errcode = 'P0001';
  end if;

  -- Cargo is weighted by goods.bulk (DESIGN G.3: bullion is dense and cheap to carry, timber is not).
  select coalesce(sum((e.value)::text::numeric * g.bulk), 0) into v_cargo_t
    from jsonb_each(s.cargo) e join public.goods g on g.code = e.key;

  -- 0074: how full she is, and how fast she is, are both read off the FITTED hull now.
  v_fill := least(1.0, (v_cargo_t + s.water_t + s.food_t) / world.ship_stat(p_ship, 'hold'));
  v_hull := public.wc_num('hull_speed_floor')
          + (1 - public.wc_num('hull_speed_floor')) * least(1.0, s.durability / c.durability);
  v_load := 1 - public.wc_num('load_speed_penalty') * v_fill;
  v_crew := case when s.crew >= c.crew_required then 1.0 else public.wc_num('crew_short_speed_mult') end;

  -- M_wind is pinned at 1.00 and M_officer at 1.00: wind and officers are explicitly out of V0
  -- (DESIGN K.1). The knob `wind_mult_v0` exists so V1 changes a value, not this formula.
  return round(world.ship_stat(p_ship, 'speed') * v_hull * v_load * v_crew * public.wc_num('wind_mult_v0'), 4);
end $h$,
$h$begin
  -- 0203: THE SPEED of one hull at the fill she carries now — voyage.ship_speed_at, the one formula
  -- (the planner asks it at a full hold).
  return voyage.ship_speed_at(p_ship, null);
end $h$),
-- voyage.fleet_speed: likewise through voyage.fleet_speed_at.
('voyage.fleet_speed(uuid)', 1,
$h$declare
  v_min    numeric;
  v_ships  int;
  v_form   numeric;
  v_nav    numeric;
  v_player uuid;
  v_skill  numeric := 0;
begin
  select min(voyage.ship_speed(s.id)), count(*) into v_min, v_ships
    from public.ships s where s.fleet_id = p_fleet;
  if v_ships = 0 then
    raise exception 'E_NO_SHIPS: fleet % has no ships', p_fleet using errcode = 'P0001';
  end if;
  -- DESIGN B.3: M_formation 1.00 for <=3 ships, 0.98 for 4-6, 0.95 for 7+.
  v_form := case when v_ships <= 3 then 1.00 when v_ships <= 6 then 0.98 else 0.95 end;
  -- 0015 / 0157: the captains seated in the fleet, for speed (public.crew_pct, the one reader) — a fact
  -- about the FLEET. Zero when there are none.
  v_nav := public.crew_pct(p_fleet, null, 'speed');
  -- 0027: and the house's NAVIGATION — a fact about the CAPTAIN, read through its own existing
  -- authority. Multiplied, never added: the two are separately capped (crew_effects.cap_pct and
  -- skill_max_level x pct_per_level) and neither authority can see the other's contribution.
  select f.player_id into v_player from public.fleets f where f.id = p_fleet;
  if v_player is not null then
    v_skill := public.player_skill_bonus(v_player, 'SPEED');
  end if;
  return round(v_min * v_form * (1 + v_nav) * (1 + v_skill), 4);
end $h$,
$h$begin
  -- 0203: THE SPEED of her fleet at the fill her hulls carry now — voyage.fleet_speed_at, the one formula
  -- (the planner asks it at a full hold).
  return voyage.fleet_speed_at(p_fleet, null);
end $h$),
-- voyage.endurance_days: the multiplier through voyage.endurance_mult.
('voyage.endurance_days(uuid)', 1,
$h$  select f.player_id into v_player from public.fleets f where f.id = p_fleet;
  if v_player is not null then
    v_skill := public.player_skill_bonus(v_player, 'ENDURANCE');
  end if;

  -- 0161 (K7): the Provisioners seated in her fleet (0 while crew_bite is off — and then nothing is multiplied).
  v_crew := public.crew_pct(p_fleet, null, 'supplies');
  if v_crew <> 0 then
    return v_base * (1 + v_skill) * (1 + v_crew);
  end if;
  return v_base * (1 + v_skill);$h$,
$h$  -- 0161 (K7) / 0203: the house's ENDURANCE skill and the Provisioners seated in her fleet multiply it —
  -- voyage.endurance_mult, the one multiplier (public.npc_provision_for reads it too).
  return v_base * voyage.endurance_mult(p_fleet);$h$),
-- voyage.sail_refusal: the stores gate through voyage.stores_need_days.
('voyage.sail_refusal(uuid,uuid,jsonb,numeric)', 1,
$h$  v_days := ((p_nm + coalesce(v_back, 0)) / v_speed) / 24;
  if v_end < v_days * public.wc_num('endurance_margin') then
    if coalesce(v_back, 0) > 0 then
      -- THE REASON SURVIVES. The bar says 2.9 / 33 days; only this sentence can say why 33.
      return cmd.refusal('E_ENDURANCE',
        'no chandler where she is bound — the casks must cover the way home too',
        cmd.figures(v_end, v_days * public.wc_num('endurance_margin'), 'days'));
    end if;
    return cmd.refusal('E_ENDURANCE', 'the passage is longer than her casks',
      cmd.figures(v_end, v_days * public.wc_num('endurance_margin'), 'days'));$h$,
$h$  -- 0203: THE DAYS OF STORES THE PASSAGE ASKS — voyage.stores_need_days, the one measure (the desk and
  -- the merchants' planner read it too: world.good_board, public.npc_leg_days).
  v_days := voyage.stores_need_days(p_nm + coalesce(v_back, 0), v_speed);
  if v_end < v_days then
    if coalesce(v_back, 0) > 0 then
      -- THE REASON SURVIVES. The bar says 2.9 / 33 days; only this sentence can say why 33.
      return cmd.refusal('E_ENDURANCE',
        'no chandler where she is bound — the casks must cover the way home too',
        cmd.figures(v_end, v_days, 'days'));
    end if;
    return cmd.refusal('E_ENDURANCE', 'the passage is longer than her casks',
      cmd.figures(v_end, v_days, 'days'));$h$),
-- world.good_board: the desk's `sailable` through the same measure.
('world.good_board(uuid,uuid,uuid,numeric)', 1,
$h$x.max_leg / v_speed / 24 * v_margin <= v_end$h$,
$h$voyage.stores_need_days(x.max_leg, v_speed) /* 0203 */ <= v_end$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 2,
$h$r.max_leg / v_speed / 24 * v_margin <= v_end$h$,
$h$voyage.stores_need_days(r.max_leg, v_speed) /* 0203 */ <= v_end$h$),
-- public.npc_feasible_legs
('public.npc_feasible_legs(uuid,numeric,integer)', 1,
$h$     and ceil(l.nm / (greatest(p_speed, 0.1) * 24) * public.wc_num('endurance_margin'))::int + 1 <= p_days$h$,
$h$     and public.npc_leg_days(l.nm, p_speed) <= p_days   -- 0203: the door's measure (voyage.stores_need_days), one day spare$h$),
-- public.npc_casks_blocked
('public.npc_casks_blocked(uuid,uuid,numeric,numeric)', 1,
$h$  v_d := greatest(v_d, ceil(coalesce(p_nm, 0) / (greatest(coalesce(p_speed, 0), 0.1) * 24)
                            * public.wc_num('endurance_margin'))::int + 1);$h$,
$h$  v_d := greatest(v_d, public.npc_leg_days(p_nm, p_speed));   -- 0203: the planner's one measure$h$),
-- public.npc_plan
('public.npc_plan(timestamp with time zone,uuid)', 1,
$h$  v_emargin numeric := public.wc_num('endurance_margin');
$h$,
$h$  -- 0203: (endurance_margin is read by the leg's one measure, public.npc_leg_days)
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 2,
$h$  v_pays    boolean;       -- 0186: the loop she will sail leaves her more than nothing a lap
$h$,
$h$  v_pays    boolean;       -- 0186: the loop she will sail leaves her more than nothing a lap
  v_unsail  boolean;       -- 0203: this loop cannot be sailed with what the plan's PROVISION loads, or paid for
  v_cur_uns boolean;       -- 0203
  v_best_uns boolean;      -- 0203
  v_purse   numeric;       -- 0203: her purse and her cargo at cost (npc_buy_budget's working capital)
  v_pdays   int;           -- 0203: her preset's days at the plan
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 3,
$h$      v_speed := greatest(coalesce(voyage.fleet_speed(r.fleet_id), 0), 0.1);
$h$,
$h$      -- 0203: THE SPEED SHE SAILS AT, LADEN — voyage.fleet_speed_at(fleet, 1), her hold full as the loop
      -- she is planned fills it: the slowest she leaves at. The door judges the speed she leaves at, so days
      -- planned at this one are never fewer than it asks (0197's trade loops, planned at her empty speed,
      -- were refused E_ENDURANCE by the quarter a full hold costs her).
      v_speed := greatest(coalesce(voyage.fleet_speed_at(r.fleet_id, 1), 0), 0.1);
      v_purse := (select pl.ducats from public.players pl where pl.id = sr.player_id) + public.fleet_stock_at_cost(r.fleet_id);
      select pr.days into v_pdays from public.provision_presets pr where pr.id = f.provision_preset_id;
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 4,
$h$        v_tier := public.npc_loop_tier(v_rep, v_net, i = 0 and v_off);
$h$,
$h$        -- 0203: SHE CAN SAIL IT AND PAY FOR IT. What she will carry after the plan's own PROVISION — her
        -- preset raised to the loop's longest leg (public.npc_leg_days), every hull topped up as
        -- cmd.do_provision tops it, the endurance as voyage.endurance_days reads it
        -- (public.npc_provision_for) — must cover that leg at the door's measure (voyage.stores_need_days),
        -- and her purse (with her cargo at cost, sold before she provisions) must cover those stores. A loop that fails is unsailable: never chosen; hers, when
        -- it is hers, loses to any loop that passes and is not sailed with a BUY.
        select pf.days < voyage.stores_need_days(v_maxnm, v_speed) or pf.cost > coalesce(v_purse, 0)
          into v_unsail
          from public.npc_provision_for(r.fleet_id, greatest(coalesce(v_pdays, 0), public.npc_leg_days(v_maxnm, v_speed))) pf;
        v_unsail := coalesce(v_unsail, true);
        v_tier := public.npc_loop_tier(v_rep, v_net, (i = 0 and v_off) or v_unsail);
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 5,
$h$          v_cur_tier := v_tier; v_best_tier := v_tier;   -- 0152
$h$,
$h$          v_cur_tier := v_tier; v_best_tier := v_tier;   -- 0152
          v_cur_uns := v_unsail; v_best_uns := v_unsail;   -- 0203
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 6,
$h$
          v_best_tier := v_tier;   -- 0152
$h$,
$h$
          v_best_tier := v_tier;   -- 0152
          v_best_uns := v_unsail;  -- 0203
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 7,
$h$        v_days := ceil((case when v_best_i <> 0 then v_best_maxnm else v_cur_maxnm end)
                       / (v_speed * 24) * v_emargin)::int + 1;
$h$,
$h$        -- 0203: the preset the longest leg asks, by the door's measure at her laden speed (public.npc_leg_days).
        v_days := public.npc_leg_days(case when v_best_i <> 0 then v_best_maxnm else v_cur_maxnm end, v_speed);
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 9,
$h$      select jsonb_agg(jsonb_build_object('port_id', s.port_id, 'code', p.code, 'course', s.course) order by s.ord)
$h$,
$h$      select jsonb_agg(jsonb_build_object('port_id', s.port_id, 'code', p.code, 'course', s.course,
                                          'nm', s.course_nm) order by s.ord)   -- 0203: the course's own measure
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 10,
$h$          v_maxnm  := greatest(v_maxnm, coalesce((v_leg->>'nm')::numeric, 0));
$h$,
$h$          -- 0203: THE LONGEST LEG BY ITS COURSE, as the door measures it (the stop's nm: course_nm, or the
          -- known leg's — npc_known_legs), the reach table's only where none is stored.
          v_maxnm  := greatest(v_maxnm, coalesce((v_loop->j->>'nm')::numeric, (v_leg->>'nm')::numeric, 0));
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 8,
$h$      v_pays := coalesce(case when v_best_i <> 0 then v_best_net else v_cur_net end, 0) > 0;
$h$,
$h$      -- 0203: AND SHE CAN SAIL IT AND PAY FOR ITS STORES (v_unsail above): a loop she cannot finish is not
      -- bought into.
      v_pays := coalesce(case when v_best_i <> 0 then v_best_net else v_cur_net end, 0) > 0
                and not coalesce(case when v_best_i <> 0 then v_best_uns else v_cur_uns end, true);
$h$),
-- public.npc_known_legs: and every course the world has held, measured as the door measures it.
('public.npc_known_legs(uuid)', 1,
$h$  with ms as (
    select s.route_id, s.ord, s.port_id, s.course,
           lead(s.port_id)        over (partition by s.route_id order by s.ord) as nxt,
           first_value(s.port_id) over (partition by s.route_id order by s.ord) as first_port
      from public.standing_route_stops s
      join public.standing_routes sr on sr.id = s.route_id
      join public.players p on p.id = sr.player_id and p.is_npc
     -- 0134: ONLY THE ROUTES THAT CALL AT p_from — a leg from or to it lies on such a route, and a
     -- route's lead / first_value are its own (was: every merchant route's stops, 12 ms a harbour).
     where s.route_id in (select t.route_id from public.standing_route_stops t where t.port_id = p_from)),
  legs as (
    select m.port_id as a, coalesce(m.nxt, m.first_port) as b, m.course from ms m),
  both_ways as (
    select l.b as to_port, l.course, false as reversed from legs l where l.a = p_from
    union all
    select l.a, (select jsonb_agg(t.x order by t.i desc)
                   from jsonb_array_elements(l.course) with ordinality t(x, i)), true
      from legs l where l.b = p_from)
  select distinct on (w.to_port) w.to_port, p.code, w.course, r.nm, w.reversed
    from both_ways w
    join public.ports p on p.id = w.to_port
    join voyage.reach_from(p_from) r on r.port_id = w.to_port$h$,
$h$  with ms as (
    select s.route_id, s.ord, s.port_id, s.course, s.course_nm,
           lead(s.port_id)        over (partition by s.route_id order by s.ord) as nxt,
           first_value(s.port_id) over (partition by s.route_id order by s.ord) as first_port
      from public.standing_route_stops s
      join public.standing_routes sr on sr.id = s.route_id
      join public.players p on p.id = sr.player_id and p.is_npc
     -- 0134: ONLY THE ROUTES THAT CALL AT p_from — a leg from or to it lies on such a route, and a
     -- route's lead / first_value are its own (was: every merchant route's stops, 12 ms a harbour).
     where s.route_id in (select t.route_id from public.standing_route_stops t where t.port_id = p_from)),
  legs as (
    select m.port_id as a, coalesce(m.nxt, m.first_port) as b, m.course, m.course_nm as nm from ms m
    -- 0203: AND EVERY COURSE THE WORLD HAS HELD out of or into p_from (public.npc_courses: the roster as
    -- founded, and every merchant leg at 0203's deploy) — a leg nobody sails today is not forgotten; the
    -- loops as they stand could only ever lose legs (Le Havre: seven in a fresh world, one on prod).
    union all
    select c.from_port, c.to_port, c.course, c.nm from public.npc_courses c where c.from_port = p_from
    union all
    select c.from_port, c.to_port, c.course, c.nm from public.npc_courses c where c.to_port = p_from),
  both_ways as (
    select l.b as to_port, l.course, l.nm, false as reversed from legs l where l.a = p_from
    union all
    select l.a, (select jsonb_agg(t.x order by t.i desc)
                   from jsonb_array_elements(l.course) with ordinality t(x, i)), l.nm, true
      from legs l where l.b = p_from)
  -- 0203: THE LEG'S MILES ARE ITS COURSE'S, as cmd.do_sail measures it (voyage.segments_from_course, stored
  -- course_nm / npc_courses.nm) — the door judges that figure, and the reach table's can be 6 % short of
  -- it (Macau-Acapulco 7,794 against 8,303). The reach table's only where no measure is stored.
  select distinct on (w.to_port) w.to_port, p.code, w.course, coalesce(w.nm, r.nm), w.reversed
    from both_ways w
    join public.ports p on p.id = w.to_port
    join voyage.reach_from(p_from) r on r.port_id = w.to_port$h$),
-- public.npc_tend_houses: a refound judges what she is worth.
('public.npc_tend_houses(timestamp with time zone)', 1,
$h$    for hh in select h.player_id, h.capital, pl.ducats, pl.company_name, h.home_port_id
                from public.npc_houses h join public.players pl on pl.id = h.player_id and pl.is_npc
               where pl.ducats < h.capital * public.wc_num('npc_purse_floor_pct')
               order by h.roster_ord loop$h$,
$h$    -- 0203: WHAT SHE IS WORTH, NOT WHAT IS IN HER PURSE — public.npc_worth (her purse and her cargo at
    -- cost). Her BUYs spend 90 % of both (npc_buy_budget), so a house that has just bought her parcels
    -- held a tenth in coin and was "refounded" from her city while worth her capital (0197's long laps
    -- kept the parcels aboard for hours: 83 refounds in two hours, none of them broke). `ducats` below is
    -- that worth, so the top-up is to her capital.
    for hh in select h.player_id, h.capital, w.worth as ducats, pl.company_name, h.home_port_id
                from public.npc_houses h join public.players pl on pl.id = h.player_id and pl.is_npc
               cross join lateral (select public.npc_worth(h.player_id) as worth) w
               where w.worth < h.capital * public.wc_num('npc_purse_floor_pct')
               order by h.roster_ord loop$h$),
-- public.item_not_made: a kind no workshop makes.
('public.item_not_made(text)', 1,
$h$  select format('%s is not made in any workshop yet', k.name)
    from public.item_unmade u join public.item_kinds k on k.code = u.item_code
   where u.item_code = p_item$h$,
$h$  select coalesce(
    (select format('%s is not made in any workshop yet', k.name)
       from public.item_unmade u join public.item_kinds k on k.code = u.item_code
      where u.item_code = p_item),
    -- 0203: AN ITEM OF A KIND NO WORKSHOP MAKES — a promotion (the sea chart, the trade seal, the battle
    -- honour) is earned, never made; it has no recipe, so cmd.do_make made it for nothing.
    (select format('%s is not made in any workshop — it is earned', k.name)
       from public.item_kinds k where k.code = p_item and k.kind <> 'fitting'))$h$);

do $$
declare
  d     record;
  h     record;
  v_def text;
  v_rev text;
begin
  for d in select * from defs_before_0203 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0203 where fn = d.fn order by n loop
      if pg_temp.occurs_0203(v_def, h.old) <> 1 then
        raise exception '0203 self-assert FAIL: hunk % of % occurs % time(s), not once — the deployed body is not what this file was written against',
          h.n, d.fn, pg_temp.occurs_0203(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0203 self-assert FAIL: no hunk for %', d.fn;
    end if;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0203 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0203(v_rev, h.new) <> 1 then
        raise exception '0203 self-assert FAIL: hunk % of % is not in the new body once', h.n, d.fn;
      end if;
    end loop;
    for h in select * from hunks_0203 where fn = d.fn order by n desc loop
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0203 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0203 self-assert FAIL: the ACL of % moved', d.fn;
    end if;
  end loop;
end $$;

-- ── 4. THE PROBES (their own merchants' rows; every one rolled back whole) ─────────────────────
create temp table probe_0203 (k text primary key, j jsonb) on commit drop;

-- (i) THE ANSWERS DID NOT MOVE where nothing was meant to: ship and fleet speed, endurance and the sail
-- door, old body against new, for every merchant fleet (and the door at four passages each).
do $$
declare
  v_bad jsonb;
begin
  select jsonb_build_object(
    'fleets', count(*),
    'speed', count(*) filter (where voyage.fleet_speed(nf.fleet_id) is distinct from pg_temp.fleet_speed_old_0203(nf.fleet_id)),
    'ship_speed', (select count(*) from public.ships s join public.npc_fleets n2 on n2.fleet_id = s.fleet_id
                    where voyage.ship_speed(s.id) is distinct from pg_temp.ship_speed_old_0203(s.id)),
    'endurance', count(*) filter (where voyage.endurance_days(nf.fleet_id) is distinct from pg_temp.endurance_days_old_0203(nf.fleet_id)),
    'door', (select count(*) from public.npc_fleets n3 cross join (values (100::numeric), (1000), (3000), (8000)) v(nm)
              where voyage.sail_refusal(n3.fleet_id, null, null, v.nm)
                    is distinct from pg_temp.sail_refusal_old_0203(n3.fleet_id, null, null, v.nm)),
    'door_refusals', (select count(*) from public.npc_fleets n3 cross join (values (100::numeric), (1000), (3000), (8000)) v(nm)
                       where voyage.sail_refusal(n3.fleet_id, null, null, v.nm) is not null))
    into v_bad from public.npc_fleets nf;
  insert into probe_0203 values ('same', v_bad);
end $$;

-- (ii) THE ROSTER'S 40 MERCHANTS ON THE LONGEST LEGS (her loop's longest course; on prod 0197's trade loops), each at her lap start in turn: the loop the planner writes is sailable after
-- its own PROVISION at a full hold's speed by the door's measure; and the PRE-IMAGE's preset for the same
-- loop (her lap-start speed, empty) would have been refused for some of them — the defect is seen.
do $$
declare
  r      record;
  v_r    jsonb;
  v_w    jsonb;
  v_t0   timestamptz;
  v_out  jsonb := jsonb_build_object('n', 0, 'sailing', 0, 'laid', 0, 'refused', 0, 'old_short', 0, 'ms', 0,
                                     'pays', 0, 'bad_list', '[]'::jsonb, 'long', '[]'::jsonb);
begin
  begin
    update public.world_config set value = 'true'::jsonb where key in ('standing_routes_enabled', 'npc_traders_enabled');
    for r in select nf.fleet_id, nf.route_id from public.npc_fleets nf
               join public.standing_route_stops s0 on s0.route_id = nf.route_id and s0.ord = 0
              where (select count(*) from public.standing_route_stops s where s.route_id = nf.route_id) >= 2
              order by (select max(s.course_nm) from public.standing_route_stops s where s.route_id = nf.route_id) desc nulls last,
                       nf.roster_ord limit 40 loop
      perform pg_temp.at_lap_start_0203(r.fleet_id, r.route_id);
      v_t0 := clock_timestamp();
      v_r := public.npc_plan(now(), r.route_id);
      v_out := jsonb_set(v_out, '{ms}', to_jsonb((v_out->>'ms')::numeric + extract(epoch from clock_timestamp() - v_t0) * 1000));
      continue when coalesce((v_r->>'planned')::int, 0) = 0;
      v_w := pg_temp.loop_door_0203(r.route_id);
      v_out := jsonb_set(v_out, '{n}', to_jsonb((v_out->>'n')::int + 1));
      if v_w->>'reason' = 'laid_up' then
        v_out := jsonb_set(v_out, '{laid}', to_jsonb((v_out->>'laid')::int + 1));
      else
        v_out := jsonb_set(v_out, '{sailing}', to_jsonb((v_out->>'sailing')::int + 1));
        if (v_w->>'net')::numeric > 0 then
          v_out := jsonb_set(v_out, '{pays}', to_jsonb((v_out->>'pays')::int + 1));
        end if;
        if (v_w->>'legs_refused')::int > 0 then
          v_out := jsonb_set(v_out, '{refused}', to_jsonb((v_out->>'refused')::int + 1));
          v_out := jsonb_set(v_out, '{bad_list}', (v_out->'bad_list') || jsonb_build_array(v_w));
        end if;
        if (v_w->>'old_preset')::numeric * voyage.endurance_mult(r.fleet_id) < (v_w->>'need')::numeric then
          v_out := jsonb_set(v_out, '{old_short}', to_jsonb((v_out->>'old_short')::int + 1));
        end if;
        if jsonb_array_length(v_out->'long') < 5 then
          v_out := jsonb_set(v_out, '{long}', (v_out->'long') || jsonb_build_array(v_w - 'reason'));
        end if;
      end if;
    end loop;
    raise exception 'PROBE_ROLLBACK_0203:%', v_out::text;
  exception when others then
    if sqlerrm not like 'PROBE_ROLLBACK_0203:%' then raise; end if;
    insert into probe_0203 values ('roster', substr(sqlerrm, length('PROBE_ROLLBACK_0203:') + 1)::jsonb);
  end;
end $$;

-- (iii) COMPTOIR CHASTELLAIN — the owner's case. Her first merchant fleet at her lap start on her loop as it
-- stands, the market as it stands: the planner writes a loop whose lap leaves her more than nothing, that
-- she can sail after its PROVISION, out of a home that knows more than one leg.
do $$
declare
  v_f   record;
  v_out jsonb;
  v_r   jsonb;
  v_t0  timestamptz;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key in ('standing_routes_enabled', 'npc_traders_enabled');
    select nf.fleet_id, nf.route_id, f.name into v_f
      from public.npc_fleets nf join public.players pl on pl.id = nf.player_id and pl.company_name = 'Comptoir Chastellain'
      join public.fleets f on f.id = nf.fleet_id
     order by nf.roster_ord limit 1;
    if v_f.fleet_id is null then
      raise exception '0203 self-assert FAIL: the roster holds no Comptoir Chastellain — the probe is named for her';
    end if;
    v_out := jsonb_build_object('fleet', v_f.name,
               'home_legs', (select count(*) from public.npc_known_legs((select s.port_id from public.standing_route_stops s where s.route_id = v_f.route_id and s.ord = 0))),
               'from', (select string_agg(p.code, '-' order by s.ord) from public.standing_route_stops s join public.ports p on p.id = s.port_id where s.route_id = v_f.route_id));
    perform pg_temp.at_lap_start_0203(v_f.fleet_id, v_f.route_id);
    v_t0 := clock_timestamp();
    v_r := public.npc_plan(now(), v_f.route_id);
    v_out := v_out || jsonb_build_object('plan', v_r - 'notes', 'notes', v_r->'notes', 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000),
                                         'wrote', pg_temp.loop_door_0203(v_f.route_id));
    raise exception 'PROBE_ROLLBACK_0203:%', v_out::text;
  exception when others then
    if sqlerrm not like 'PROBE_ROLLBACK_0203:%' then raise; end if;
    insert into probe_0203 values ('chas', substr(sqlerrm, length('PROBE_ROLLBACK_0203:') + 1)::jsonb);
  end;
end $$;

-- (iv) A REFOUND JUDGES WHAT SHE IS WORTH. Comptoir Chastellain's house, her purse set to a tenth of her
-- capital (under the floor): (a) with her parcels aboard at cost worth her capital, the houses' tend does
-- NOT refound her; (b) POSITIVE CONTROL, the same with an empty hold: it does. Treasuries dark in-block,
-- so a refound is a credit (her city's surplus does not decide); only her own events of this block are counted
-- (created_at ≥ the transaction's now()). Nothing is deleted: events and ledger are append-only, and every row
-- this block writes is undone by its sentinel exception (PROBE_ROLLBACK_0203).
do $$
declare
  v_p    uuid := (select pl.id from public.players pl where pl.company_name = 'Comptoir Chastellain' and pl.is_npc);
  v_cap  bigint;
  v_fl   uuid;
  v_good text;
  v_out  jsonb := '{}'::jsonb;
  k      int;
  v_t0   timestamptz;
begin
  select h.capital into v_cap from public.npc_houses h where h.player_id = v_p;
  select nf.fleet_id into v_fl from public.npc_fleets nf where nf.player_id = v_p order by nf.roster_ord limit 1;
  select g.code into v_good from public.goods g order by g.code limit 1;
  for k in 1 .. 2 loop
    begin
      update public.world_config set value = 'true'::jsonb where key in ('standing_routes_enabled', 'npc_traders_enabled');
      update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
      -- her refound cooldown off in this block (events is append-only: a past refound is never deleted, it is
      -- simply not counted — the cooldown reads it, so the cooldown is set to 0 here, rolled back)
      update public.world_config set value = to_jsonb(0) where key = 'npc_refound_cooldown_game_days';
      update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id in (select nf.fleet_id from public.npc_fleets nf where nf.player_id = v_p);
      perform public.credit(v_p, 'PROBE', (v_cap / 10) - (select ducats from public.players where id = v_p));
      if k = 1 then
        update public.ships set cargo = jsonb_build_object(v_good, 1), cargo_basis = jsonb_build_object(v_good, v_cap)
         where id = (select s.id from public.ships s where s.fleet_id = v_fl order by s.is_flagship desc, s.id limit 1);
      end if;
      v_t0 := clock_timestamp();
      perform public.npc_tend_houses(now());
      raise exception 'PROBE_ROLLBACK_0203:%', jsonb_build_object('purse', v_cap / 10, 'capital', v_cap, 'worth_before', public.npc_worth(v_p),
        'refounded', (select count(*) from public.events where player_id = v_p and kind = 'NPC_REFOUNDED' and created_at >= now()),
        'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000))::text;
    exception when others then
      if sqlerrm not like 'PROBE_ROLLBACK_0203:%' then raise; end if;
      v_out := v_out || jsonb_build_object(case k when 1 then 'cargo' else 'empty' end, substr(sqlerrm, length('PROBE_ROLLBACK_0203:') + 1)::jsonb);
    end;
  end loop;
  insert into probe_0203 values ('refound', v_out);
end $$;

insert into graph_0203
select 'after', jsonb_build_object(
  'homes_single', (select count(*) from public.npc_fleets nf join public.standing_route_stops s0 on s0.route_id = nf.route_id and s0.ord = 0
                    where (select count(*) from public.npc_known_legs(s0.port_id)) <= 1),
  'leh', (select count(*) from public.npc_known_legs((select id from public.ports where code = 'LEH'))),
  'courses', (select count(*) from public.npc_courses));

-- ── 5. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  sm jsonb := (select j from probe_0203 where k = 'same');
  r  jsonb := (select j from probe_0203 where k = 'roster');
  c  jsonb := (select j from probe_0203 where k = 'chas');
  rf jsonb := (select j from probe_0203 where k = 'refound');
  gb jsonb := (select v from graph_0203 where k = 'before');
  ga jsonb := (select v from graph_0203 where k = 'after');
  v_copies jsonb;
begin
  -- ONE MEASURE: no live body but voyage.stores_need_days applies endurance_margin (world.snapshot serves the
  -- knob, world.good_board shows it; neither applies it)
  select jsonb_agg(n.nspname || '.' || p.proname) into v_copies
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'voyage', 'world')
     and p.prosrc ~ '\*\s*(v_margin|v_emargin|public\.wc_num\(''endurance_margin''\))'
     and p.proname <> 'stores_need_days';
  if v_copies is not null then
    raise exception '0203 self-assert FAIL: a copy of the stores measure is left in %', v_copies;
  end if;
  -- the answers that were not meant to move
  if public.wc_int('npc_route_review_laps') <> 6 then
    raise exception '0203 self-assert FAIL: npc_route_review_laps did not land';
  end if;
  if (sm->>'speed')::int <> 0 or (sm->>'ship_speed')::int <> 0 or (sm->>'endurance')::int <> 0 or (sm->>'door')::int <> 0 then
    raise exception '0203 self-assert FAIL: speed, endurance or the sail door moved: %', sm;
  end if;
  -- (ii) every loop written is sailable after its PROVISION at a full hold; the old measure was short for some
  if (r->>'n')::int < 20 or (r->>'refused')::int <> 0 then
    raise exception '0203 self-assert FAIL: of % merchants planned, % were written a loop the door refuses at a full hold after its PROVISION: %',
      r->>'n', r->>'refused', r->'bad_list';
  end if;
  if (r->>'old_short')::int < 1 then
    raise exception '0203 self-assert FAIL: the positive control cannot see the defect — the pre-image''s preset was short for none of %: %', r->>'sailing', r->'long';
  end if;
  -- (iii) the owner's case
  if (c->>'home_legs')::int < 2 then
    raise exception '0203 self-assert FAIL: Comptoir Chastellain''s home knows % leg(s): %', c->>'home_legs', c;
  end if;
  if not ((c->'wrote'->>'net')::numeric > 0 and c->'wrote'->>'reason' is null and (c->'wrote'->>'legs_refused')::int = 0) then
    raise exception '0203 self-assert FAIL: Comptoir Chastellain was written % — net % a lap, % leg(s) refused, %: %',
      c->'wrote'->>'stops', c->'wrote'->>'net', c->'wrote'->>'legs_refused', coalesce(c->'wrote'->>'reason', 'sailing'), c;
  end if;
  -- (iv) the refound
  if (rf->'cargo'->>'refounded')::int <> 0 or (rf->'empty'->>'refounded')::int <> 1 then
    raise exception '0203 self-assert FAIL: the refound test — with her parcels aboard % refound(s) (want 0), with an empty hold % (want 1): %',
      rf->'cargo'->>'refounded', rf->'empty'->>'refounded', rf;
  end if;
  -- (v) the leg graph
  if (ga->>'homes_single')::int > (gb->>'homes_single')::int or (ga->>'leh')::int < 5 then
    raise exception '0203 self-assert FAIL: the leg graph — homes knowing one leg or none % → %, Le Havre % → %',
      gb->>'homes_single', ga->>'homes_single', gb->>'leh', ga->>'leh';
  end if;
  -- (vi) a promotion is not made; a fitting is as before
  if exists (select 1 from public.item_kinds k where k.kind <> 'fitting' and public.item_not_made(k.code) is null)
     or (select count(*) from public.item_kinds k where public.item_not_made(k.code) is not null)
        <> (select count(*) from public.item_unmade) + (select count(*) from public.item_kinds k where k.kind <> 'fitting'
                                                         and not exists (select 1 from public.item_unmade u where u.item_code = k.code)) then
    raise exception '0203 self-assert FAIL: item_not_made does not answer for exactly the items made nowhere and the promotions';
  end if;

  raise notice '0203 self-assert ok: A MERCHANT''S LOOP IS ONE SHE CAN SAIL, PAY FOR AND REMEMBER. ONE MEASURE (voyage.stores_need_days; no copy left); speed, endurance and the door unchanged for % fleets (% door readings refused, as before). THE ROSTER''S % LONGEST-LEGGED: % planned — % sailing (% pay), % waiting; 0 written a loop the door refuses at a full hold after its PROVISION; the pre-image''s preset was short for % of them; % ms of planning. COMPTOIR CHASTELLAIN (%; home knows % legs): % → % — net % a lap over % nm, longest leg % nm, stores % / % days, % BUY. REFOUND: purse % of capital %, parcels aboard → % refound(s); empty hold → %. LEG GRAPH: % courses kept; homes knowing ≤ 1 leg % → %; Le Havre % → % legs. npc_route_review_laps 6. Promotions are not made. Bodies reverse, ACLs unchanged.',
    sm->>'fleets', sm->>'door_refusals',
    40, r->>'n', r->>'sailing', r->>'pays', r->>'laid', r->>'old_short', round((r->>'ms')::numeric),
    c->>'fleet', c->>'home_legs', c->>'from', c->'wrote'->>'stops', c->'wrote'->>'net', c->'wrote'->>'nm', c->'wrote'->>'max_leg',
    c->'wrote'->>'have', c->'wrote'->>'need', c->'wrote'->>'buys',
    rf->'cargo'->>'purse', rf->'cargo'->>'capital', rf->'cargo'->>'refounded', rf->'empty'->>'refounded',
    ga->>'courses', gb->>'homes_single', ga->>'homes_single', gb->>'leh', ga->>'leh';
end $$;

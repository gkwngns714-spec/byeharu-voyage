-- 0324 PROD CHECK, read-only, one statement: supabase db query --linked -f scripts/ops/harness/rich-cities/before.sql
-- Every function read here is STABLE (pg_get_functiondef, to_regclass, to_regprocedure, replace). No game function is called.
-- Wanted: every `times` is 1; rich_keys 0; start_port and based_at 0; rich_on and plan2 null; no_start 0; head 0323 (0322 until #520 lands).
begin transaction read only;
with h(fn, ord, old) as (values
  ('public.crown_aid(uuid)'::regprocedure, 1, $h$-- 0309: cargo ships lit, the same roster and the same call, then the capital loads a ship (public.cargo_ships_load) and this run pays nobody: one path per state of the switch.
$h$),
  ('public.crown_aid(uuid)'::regprocedure, 2, $h$   where x.cap is not null and x.cap <> x.port_id;
$h$),
  ('public.crown_aid(uuid)'::regprocedure, 3, $h$  v_call := public.crown_call(v_short);
  if public.convoys_on() then
$h$),
  ('public.capital_pays(uuid,uuid,uuid,text,bigint,uuid,boolean,jsonb)'::regprocedure, 1, $h$      if v_from is not null then
        perform public.treasury_lock(v_from);
$h$),
  ('public.cargo_ships_load(jsonb)'::regprocedure, 1, $h$-- up to its surplus, onto one idle ship of its realm, the lowest ord. One ship a run. No idle ship, or nothing to send: nothing, and the next hourly run asks again. Answers {loaded, ships}.
$h$),
  ('public.cargo_ships_load(jsonb)'::regprocedure, 2, $h$  v_player uuid;
  v_a      bigint;
$h$),
  ('public.cargo_ships_load(jsonb)'::regprocedure, 3, $h$    select c.fleet_id, c.player_id into v_fleet, v_player
      from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
     where c.home_port_id = k.cap and f.status = 'DOCKED' and f.port_id = k.cap and c.out_load is null
$h$),
  ('public.cargo_ships_load(jsonb)'::regprocedure, 4, $h$                    where l.circuit_id = (select x.id from public.cargo_circuits x where x.nation_id = c.nation_id order by x.id desc limit 1))
     order by c.ord
     limit 1;
$h$),
  ('public.cargo_ships_load(jsonb)'::regprocedure, 5, $h$    continue when v_fleet is null;
    v_a := least(k.need - (select coalesce(sum(a.aboard), 0)::bigint from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a where c.home_port_id = k.cap),
                 greatest(0, public.city_surplus(k.cap)));
$h$),
  ('public.cargo_ships_load(jsonb)'::regprocedure, 6, $h$    perform public.convoy_book('LOADED', v_fleet, v_player, k.cap, v_a);
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)'::regprocedure, 1, $h$    if v_load is null then
      return 'IDLE';
    end if;
    v_cir := (select x.id from public.cargo_circuits x where x.nation_id = c.nation_id order by x.id desc limit 1);
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)'::regprocedure, 2, $h$    if v_lit and v_left > 0 and public.city_capital(f.port_id) = c.home_port_id then
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)'::regprocedure, 3, $h$    v_cir := c.circuit_id;
    v_leg := c.leg + 1;
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)'::regprocedure, 4, $h$--   The capital: back from a lap, she returns what is left and is mended. A load not yet gone sails if the switch is on, and comes straight back ashore if it is off.
$h$),
  ('public.cargo_circuit_plan(uuid)'::regprocedure, 1, $h$CREATE OR REPLACE FUNCTION public.cargo_circuit_plan(p_nation uuid)
$h$),
  ('public.cargo_circuit_plan(uuid)'::regprocedure, 2, $h$-- its courses. Answers {capital, nm, legs: [{to, code, nm, course}], left_out: [codes no course reaches]}; the last leg ends at the capital. A realm with no city has no legs.
$h$),
  ('public.cargo_circuit_plan(uuid)'::regprocedure, 3, $h$  v_cap   uuid;
  v_ids   uuid[];     -- vertex -> port
$h$),
  ('public.cargo_circuit_plan(uuid)'::regprocedure, 4, $h$  select p.id into v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR'
   where g.nation_id = p_nation;
  if v_cap is null then
$h$),
  ('public.cargo_circuit_plan(uuid)'::regprocedure, 5, $h$  select array_agg(x.id order by x.id) into v_ids
    from (select c.from_port as id from public.npc_courses c union select c.to_port from public.npc_courses c union select v_cap
          union select p.id from public.ports p where p.kind = 'HARBOUR' and public.city_capital(p.id) = v_cap) x;
$h$),
  ('public.cargo_circuit_plan(uuid)'::regprocedure, 6, $h$  v_s := array[(v_ix ->> v_cap::text)::int]
         || array(select (v_ix ->> p.id::text)::int from public.ports p
                   where p.kind = 'HARBOUR' and p.id <> v_cap and public.city_capital(p.id) = v_cap order by p.code);
$h$),
  ('public.cargo_circuit_build(uuid)'::regprocedure, 1, $h$CREATE OR REPLACE FUNCTION public.cargo_circuit_build(p_nation uuid)
$h$),
  ('public.cargo_circuit_build(uuid)'::regprocedure, 2, $h$  v_plan jsonb := public.cargo_circuit_plan(p_nation);
$h$),
  ('public.cargo_circuit_build(uuid)'::regprocedure, 3, $h$  insert into public.cargo_circuits (nation_id, left_out) values (p_nation, v_plan -> 'left_out') returning id into v_id;
$h$),
  ('public.cargo_circuit_build(uuid)'::regprocedure, 4, $h$   where c.nation_id = p_nation and c.id <> v_id
$h$),
  ('public.cargo_ships_commission(uuid)'::regprocedure, 1, $h$  v_cap    uuid;
  v_player uuid;
$h$),
  ('public.cargo_ships_commission(uuid)'::regprocedure, 2, $h$  select n.code, p.id into v_code, v_cap
    from public.great_powers g
    join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR'
   where g.nation_id = p_nation;
  if v_cap is null then
$h$),
  ('public.cargo_ships_commission(uuid)'::regprocedure, 3, $h$  for v_n in 1 .. public.wc_int('convoy_ships_per_nation') loop
$h$),
  ('public.cargo_ships_commission(uuid)'::regprocedure, 4, $h$    v_fleet := public.form_fleet(v_player, format('Cargo ship %s', v_n), v_cap);
$h$),
  ('public.cargo_ships_commission(uuid)'::regprocedure, 5, $h$    insert into public.cargo_ships (fleet_id, player_id, nation_id, home_port_id, ord)
    values (v_fleet, v_player, p_nation, v_cap, v_n);
$h$),
  ('public.cargo_ships_commission(uuid)'::regprocedure, 6, $h$-- is made by (public.form_fleet, public.commission_ship). Dark, nothing. Answers how many it made. Moves no gold: her house's purse is 0 and no ledger row is written.
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)'::regprocedure, 1, $h$  v_nat   uuid;
  v_built bigint;
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)'::regprocedure, 2, $h$    select g.nation_id into v_nat
      from public.great_powers g
      join public.nations n on n.id = g.nation_id
      join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR'
      left join lateral (select x.built_at from public.cargo_circuits x where x.nation_id = g.nation_id order by x.id desc limit 1) k on true
     where (p_only_nation is null or g.nation_id = p_only_nation)
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)'::regprocedure, 3, $h$     order by n.code
     limit 1;
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)'::regprocedure, 4, $h$        if not exists (select 1 from public.cargo_circuits x where x.nation_id = v_nat
                        and x.id = (select max(y.id) from public.cargo_circuits y where y.nation_id = v_nat)
                        and x.built_at >= (select max(a.since) from public.port_allegiance a)) then
          v_built := public.cargo_circuit_build(v_nat);
$h$),
  ('public.funds_on_way(uuid)'::regprocedure, 1, $h$               and c.home_port_id = public.city_capital(p_port) and c.home_port_id <> p_port
$h$))
select (select jsonb_agg(jsonb_build_object('fn', h.fn::text, 'hunk', h.ord,
          'times', (length(d.t) - length(replace(d.t, h.old, ''))) / length(h.old)) order by h.fn::text, h.ord)
          from h cross join lateral (select replace(pg_get_functiondef(h.fn), E'\r', '') as t) d) as hunks,
       (select count(*) from public.world_config c where c.key in ('convoy_rich_enabled', 'convoy_rich_ports', 'convoy_rebase_idle_days')) as rich_keys,
       (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'cargo_circuits' and c.column_name = 'start_port') as start_port,
       (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'cargo_ships' and c.column_name = 'based_at') as based_at,
       to_regprocedure('public.rich_cities_on()')::text as rich_on,
       to_regprocedure('public.cargo_circuit_plan(uuid,uuid,uuid)')::text as plan2,
       (select count(*) from public.cargo_circuits k
         where (select l.to_port from public.cargo_circuit_legs l where l.circuit_id = k.id order by l.ord desc limit 1) is null
           and (select p.id from public.nations n join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where n.id = k.nation_id) is null) as no_start,
       (select count(*) from public.cargo_ships c join public.cargo_circuits k on k.id = c.circuit_id
         where (select l.to_port from public.cargo_circuit_legs l where l.circuit_id = k.id order by l.ord desc limit 1) <> c.home_port_id) as lap_elsewhere,
       (select max(version) from supabase_migrations.schema_migrations) as head;
commit;

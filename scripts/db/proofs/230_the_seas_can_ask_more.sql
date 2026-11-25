-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 230 - THE SEAS CAN ASK MORE  (migration 0525; docs/design/owner-spec-red-2026-11-25.md section 3; R11, R12)
--
--   Its own companies; the switch and the asks are planted here and rolled back by proof.mjs. No price, die, real company or date is read.
--
-- @pass AM_DATA     every class has its three figures and every piece its own, all the one rule's (public.sea_stats_derive); light wind: an oared hull never under its oars
-- @pass AM_READ     world.ship_stat answers the class plus what is mounted (an Anchor, a Rudder and Sails fitted one at a time), never under 0; a fleet's figure is the floor of its
--                   hulls' average; world.ship_stats and the other eleven stats are as they were
-- @pass AM_DARK     every ask is 0; the one rule with a fleet's figures, without, and for a merchant gives the same answer at 64 seas; nothing refuses dark
-- @pass AM_GATE     lit, for each of the three: an ask at her figure is open, one above refuses at the gate, in the closed seas, on her read and to the pathfinder, with have / need
-- @pass AM_FLOOR    lying in a sea that asks more than she holds, that sea does not refuse her; a homeward leg through a sea that asks 200 of everything is let through (pass home)
-- @pass AM_MERCHANT a merchant's fleet is asked none of the three: her legs are the same with every ask at 200
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  v_me uuid; v_fl uuid; v_sh uuid; v_lis uuid := (select id from public.ports where code = 'LIS'); v_aca uuid := (select id from public.ports where code = 'ACA');
  v_s jsonb; v_b jsonb; v_x numeric; v_y numeric; r record; v_to uuid; v_r jsonb; a jsonb; b jsonb; k text; v_bad text; v_t timestamptz; i int; v_stats jsonb; v_ids uuid[];
begin
  update public.world_config set value = 'false'::jsonb where key in ('sea_conditions_bite', 'sea_conditions_bite_npc', 'gear_wear_bite');
  -- ── AM_DATA ──
  select string_agg(d.code || ' ' || d.stat, ', ') into v_bad
    from public.sea_stats_derive() d
    left join public.sea_stats_class c on d.kind = 'class' and c.class_code = d.code
    left join public.sea_stats_item t on d.kind = 'item' and t.item_code = d.code and t.stat = d.stat
   where d.val is distinct from case when d.kind = 'item' then t.delta else case d.stat when 'ice' then c.ice when 'current' then c.current else c.light end end;
  if v_bad is not null or (select count(*) from public.sea_stats_class) <> (select count(*) from public.ship_classes)
     or exists (select 1 from public.sea_stats_class x join public.ship_classes c on c.code = x.class_code join public.class_profile p on p.class_code = c.code
                 where c.rig = 'oared' and x.light < 40 - 2 * p.size)
     or exists (select 1 from public.sea_stats_class x where x.ice not between 1 and 100 or x.current not between 1 and 100 or x.light not between 1 and 100) then
    raise exception 'PROOF 230 FAIL: the figures: %', v_bad;
  end if;
  raise notice 'PASS: AM_DATA - % classes (ice % to %, current % to %, light wind % to %), % piece figures, every one the rule''s', (select count(*) from public.sea_stats_class),
    (select min(ice) from public.sea_stats_class), (select max(ice) from public.sea_stats_class), (select min(current) from public.sea_stats_class), (select max(current) from public.sea_stats_class),
    (select min(light) from public.sea_stats_class), (select max(light) from public.sea_stats_class), (select count(*) from public.sea_stats_item);

  -- ── AM_READ ──
  v_me := public.new_house('00000000-0525-4000-8000-0000000002a1', 'Casa do Gelo 230', 'PRT', 'LIS', 'Gelo', 'nau', 'Gelo', null, false);
  select id into v_fl from public.fleets where player_id = v_me;
  select id into v_sh from public.ships where fleet_id = v_fl;
  delete from public.fitted_units where ship_id = v_sh;
  foreach k in array array['ice', 'current', 'light'] loop
    select case k when 'ice' then c.ice when 'current' then c.current else c.light end into v_x from public.sea_stats_class c join public.ship_classes sc on sc.code = c.class_code join public.ships s on s.class_id = sc.id where s.id = v_sh;
    if world.ship_stat(v_sh, k) <> v_x then raise exception 'PROOF 230 FAIL: bare % is %, her class %', k, world.ship_stat(v_sh, k), v_x; end if;
  end loop;
  for r in select distinct on (ip.base_type) ip.item_code, ip.base_type from public.item_profile ip where ip.base_type in ('Anchor', 'Rudder', 'Sails', 'Sheathing') and ip.grade = 1 order by ip.base_type, ip.item_code loop
    v_s := jsonb_build_object('ice', world.ship_stat(v_sh, 'ice'), 'current', world.ship_stat(v_sh, 'current'), 'light', world.ship_stat(v_sh, 'light'));
    insert into public.fitted_units (ship_id, item_code) values (v_sh, r.item_code);
    foreach k in array array['ice', 'current', 'light'] loop
      v_x := coalesce((select t.delta from public.sea_stats_item t where t.item_code = r.item_code and t.stat = k), 0);
      if world.ship_stat(v_sh, k) <> greatest(0, (v_s->>k)::numeric + v_x) then raise exception 'PROOF 230 FAIL: % mounted, % is % (was %, piece %)', r.item_code, k, world.ship_stat(v_sh, k), v_s->>k, v_x; end if;
    end loop;
  end loop;
  v_stats := world.ship_stats(v_sh);
  for k in select jsonb_object_keys(v_stats) loop
    if world.ship_stat(v_sh, k) is distinct from (v_stats->>k)::numeric then raise exception 'PROOF 230 FAIL: % moved', k; end if;
  end loop;
  if v_stats ?| array['ice', 'current', 'light'] then raise exception 'PROOF 230 FAIL: world.ship_stats gained a key'; end if;
  if (public.fleet_sea_stats(v_fl)->>'current')::numeric <> (select floor(avg(world.ship_stat(s.id, 'current'))) from public.ships s where s.fleet_id = v_fl) then
    raise exception 'PROOF 230 FAIL: the fleet''s figure is not the floor of her average';
  end if;
  v_t := clock_timestamp(); for i in 1 .. 20 loop perform public.fleet_sea_stats(v_fl); end loop;
  raise notice 'TIMING: public.fleet_sea_stats % ms', round((extract(epoch from clock_timestamp() - v_t) * 50)::numeric, 2);
  raise notice 'PASS: AM_READ - bare her class, then each piece to the point: %; the eleven stats as they were', public.fleet_sea_stats(v_fl);

  -- ── AM_DARK ──
  v_s := public.fleet_sea_stats(v_fl);
  if exists (select 1 from public.sea_zones z where z.ice_min + z.current_min + z.light_min <> 0)
     or exists (select 1 from public.sea_zones z cross join generate_series(1, 8) l where public.sea_refusal(l, 12, array[z.code]) is distinct from public.sea_refusal(l, 12, array[z.code], v_s))
     or exists (select 1 from public.sea_zones z where public.sea_refusal(null, 12, array[z.code]) is distinct from public.sea_refusal(null, 12, array[z.code], '{"ice": 0, "current": 0, "light": 0}'))
     or exists (select 1 from public.sea_zones z where public.sea_more(v_fl, array[z.code]) is not null)
     or exists (select 1 from public.ports p where p.kind = 'HARBOUR' and public.sea_gate(v_me, v_fl, p.id, null) is not null) then
    raise exception 'PROOF 230 FAIL: with every ask 0 something asks';
  end if;
  v_t := clock_timestamp(); for i in 1 .. 200 loop perform public.sea_more(v_fl, array['MED', 'SOU-CAPE', 'IND-E']); end loop;
  raise notice 'TIMING: public.sea_more with the asks at 0 % ms', round((extract(epoch from clock_timestamp() - v_t) * 5)::numeric, 3);
  raise notice 'PASS: AM_DARK - every ask 0; the rule''s answers the same with and without a fleet''s figures at 64 seas and 8 levels';

  -- ── AM_GATE ──
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
  perform cmd.assume_identity('00000000-0525-4000-8000-0000000002a1');
  select p.id into v_to from public.ports p join public.sea_leg_asks o on o.from_port = p.id and o.to_port = p.id where p.kind = 'HARBOUR' and o.zones[1] = 'AEG' order by p.code limit 1;
  foreach k in array array['ice', 'current', 'light'] loop
    execute format('update public.sea_zones set %I = %s where code = ''AEG''', k || '_min', (v_s->>k)::int);
    if public.sea_gate(v_me, v_fl, v_to, null) is not null then raise exception 'PROOF 230 FAIL: % at her figure refuses', k; end if;
    execute format('update public.sea_zones set %I = %s where code = ''AEG''', k || '_min', (v_s->>k)::int + 1);
    v_r := public.sea_gate(v_me, v_fl, v_to, null);
    if v_r->>'code' is distinct from 'E_SEA_CLOSED' or (v_r->'figures'->>('needs_' || k))::int is distinct from (v_s->>k)::int + 1 or (v_r->'figures'->>k)::numeric is distinct from (v_s->>k)::numeric
       or v_r->>'sentence' <> format('Aegean Sea closed. %s %s / %s.', case k when 'ice' then 'Ice resistance' when 'current' then 'Current strength' else 'Light wind' end, v_s->>k, (v_s->>k)::int + 1)
       or public.sea_closed(v_me, v_fl) @> array['AEG'] is not true
       or not exists (select 1 from jsonb_array_elements(world.sea_conditions()->'fleets') f where (f->>'id')::uuid = v_fl and f->'seas' ? 'AEG')
       or exists (select 1 from voyage.reach_passage(v_me, v_fl, v_lis, null) x where x.port_id = v_to and x.nm is not null) then
      raise exception 'PROOF 230 FAIL: % above her figure: %', k, v_r;
    end if;
    raise notice '%', v_r->>'sentence';
    execute format('update public.sea_zones set %I = 0 where code = ''AEG''', k || '_min');
  end loop;
  raise notice 'PASS: AM_GATE - each of the three refuses one above her figure at the gate, in her read and to the pathfinder, and not at it';

  -- ── AM_FLOOR ──
  update public.sea_zones set ice_min = 200, current_min = 200, light_min = 200 where code = (select o.zones[1] from public.sea_leg_asks o where o.from_port = v_lis and o.to_port = v_lis);
  if public.sea_gate(v_me, v_fl, (select id from public.ports where code = 'CAD'), public.sea_course(v_lis, (select id from public.ports where code = 'CAD'))) is not null and
     (select o.zones[1] from public.sea_leg_asks o join public.ports p on p.id = o.from_port and o.to_port = o.from_port where p.code = 'CAD') = (select o.zones[1] from public.sea_leg_asks o where o.from_port = v_lis and o.to_port = v_lis) then
    raise exception 'PROOF 230 FAIL: the sea she lies in refuses her';
  end if;
  update public.sea_zones set ice_min = 200, current_min = 200, light_min = 200;
  update public.world_config set value = '6800'::jsonb where key = 'nav_leg_nm_base';
  update public.fleets set port_id = v_aca where id = v_fl;
  if public.sea_gate(v_me, v_fl, v_lis, public.sea_course(v_aca, v_lis)) is not null
     or not exists (select 1 from voyage.reach_passage(v_me, v_fl, v_aca, null) x where x.port_id = v_lis and x.nm is not null) then
    raise exception 'PROOF 230 FAIL: with every sea asking 200 of everything she does not come home from Acapulco: %', public.sea_gate(v_me, v_fl, v_lis, null);
  end if;
  raise notice 'PASS: AM_FLOOR - the sea she lies in never asks it; with every sea at 200 of all three she sails home from Acapulco, and the pathfinder names the way';

  -- ── AM_MERCHANT ──
  update public.sea_zones set ice_min = 0, current_min = 0, light_min = 0;
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite_npc';
  select jsonb_object_agg(q.fleet_id, q.j) into a from (select nf.fleet_id, public.npc_feasible_legs(f.port_id, nf.fleet_id, 5, 400) as j
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.port_id is not null order by nf.roster_ord limit 40) q;
  update public.sea_zones set ice_min = 200, current_min = 200, light_min = 200;
  select jsonb_object_agg(q.fleet_id, q.j) into b from (select nf.fleet_id, public.npc_feasible_legs(f.port_id, nf.fleet_id, 5, 400) as j
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.port_id is not null order by nf.roster_ord limit 40) q;
  if a is null or a is distinct from b or exists (select 1 from public.npc_fleets nf where public.sea_more(nf.fleet_id, array['MED']) is not null limit 5) then
    raise exception 'PROOF 230 FAIL: a merchant is asked';
  end if;
  raise notice 'PASS: AM_MERCHANT - 40 merchant fleets, every ask at 200: the same legs';
end
$p$;

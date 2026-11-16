-- scene.sql: THE ESCORT IN HARBOUR, on the local world (probe.mjs, one rolled-back transaction). LOCAL ONLY: it writes.
--   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/escort-refit/probe.mjs [--fix] scripts/ops/harness/escort-refit/scene.sql
-- Spain keeps two navy ships at her capital (ord 1 a Frigate, ord 2 her Brigs and the last of her line: the escort). One of her cargo ships sails
-- for that capital with funds aboard, so public.navy_escort_step makes ord 2 her escort (escort_of set) and she waits in harbour for her ward.
-- Then the minute's re-rating (public.npc_ladder_pass) twice, and a raid on the ward (public.navy_call): does her escort still come?
-- Before 0452: ord 1 re-rated, the escort refused (still one galion), and so every minute. After: both re-rated, the escort still escorting.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $s$
declare
  t0     timestamptz := date_trunc('minute', now()) + interval '1 day';
  v_nat  uuid := (select n.id from public.nations n where n.code = 'ESP');
  v_cap  uuid;
  v_pl   uuid;
  v_n    uuid[] := '{}';
  v_c    uuid;
  v_g    uuid;
  v_bat  uuid;
  v_r1   jsonb;
  v_r2   jsonb;
  v_esc  text;
  v_call int;
  i      int;
begin
  update public.world_config set value = 'true'::jsonb where key in ('navy_enabled', 'city_treasury_enabled', 'convoys_enabled', 'convoy_armed_enabled');
  update public.world_config set value = 'false'::jsonb where key = 'pirates_trade';
  v_cap := public.realm_capital(v_nat);
  insert into public.navy_realms (nation_id, ships) values (v_nat, 2) on conflict (nation_id) do update set ships = 2;
  for i in 1 .. 2 loop
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Scene navy ' || i, v_nat, 0, true) returning id into v_pl;
    v_g := public.form_fleet(v_pl, 'Scene navy ' || i, v_cap);
    perform public.commission_ship(v_pl, v_g, 'galion', 'Scene navy ' || i, true, false);
    update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_g;
    insert into public.navy_ships (fleet_id, player_id, nation_id, ord, station_port, last_port, created_at) values (v_g, v_pl, v_nat, i, v_cap, v_cap, t0);
    v_n := v_n || v_g;
  end loop;
  -- the ward: a cargo ship of Spain at sea for the capital, funds aboard
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Scene cargo', v_nat, 0, true) returning id into v_pl;
  v_c := public.form_fleet(v_pl, 'Scene cargo', v_cap);
  perform public.commission_ship(v_pl, v_c, public.cargo_class(), 'Scene cargo', true, false);
  insert into public.cargo_ships (fleet_id, player_id, nation_id, home_port_id, ord) values (v_c, v_pl, v_nat, v_cap, 1);
  insert into public.convoy_cargo (stage, fleet_id, player_id, port_id, ducats) values ('LOADED', v_c, v_pl, v_cap, 50000);
  update public.fleets set status = 'SAILING', port_id = null where id = v_c;
  insert into public.voyages (fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
  values (v_c, v_pl, '[]'::jsonb, 100, '{}'::jsonb, t0 - interval '1 hour', t0 + interval '5 hours', 'SAILING', v_cap, v_cap);

  v_esc := public.navy_escort_step(v_n[2], v_cap, public.navy_on_duty(v_nat, 2, null), t0);
  raise notice 'escort step for ord 2: % (mission %, escort_of the ward: %); ord 1: %', v_esc,
    (select n.mission from public.navy_ships n where n.fleet_id = v_n[2]), (select n.escort_of = v_c from public.navy_ships n where n.fleet_id = v_n[2]),
    coalesce(public.navy_escort_step(v_n[1], v_cap, public.navy_on_duty(v_nat, 1, null), t0), 'null (no escort)');
  v_r1 := public.npc_ladder_pass(t0 + interval '1 minute');
  v_r2 := public.npc_ladder_pass(t0 + interval '2 minutes');
  raise notice 'the pass, two minutes: % then %', v_r1, v_r2;
  raise notice 'ord 1 (Frigate): % | ord 2, the escort (Brigs): %, % hulls, status %, mission %, escort_of the ward: %, rung row: %',
    (select string_agg(k.code, '+' order by k.code) from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = v_n[1]),
    (select string_agg(k.code, '+' order by k.code) from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = v_n[2]),
    (select count(*) from public.ships s where s.fleet_id = v_n[2]), (select f.status from public.fleets f where f.id = v_n[2]),
    (select n.mission from public.navy_ships n where n.fleet_id = v_n[2]), (select n.escort_of = v_c from public.navy_ships n where n.fleet_id = v_n[2]),
    (select g.hulls from public.npc_fleet_rungs g where g.fleet_id = v_n[2]);
  -- her duty after: the escort step still has her, and a raid on the ward brings her to its sheet at once
  v_esc := public.navy_escort_step(v_n[2], v_cap, true, t0 + interval '3 minutes');
  insert into public.battles (kind, site, started_at, resolves_at, status)
  select 'RAID', jsonb_build_object('lat', p.lat, 'lon', p.lon), t0 + interval '3 minutes', t0 + interval '1 hour', 'FIGHTING' from public.ports p where p.id = v_cap
  returning id into v_bat;
  update public.fleets set status = 'DOCKED', port_id = v_cap where id = v_c;
  v_call := public.navy_call(v_bat, v_c, t0 + interval '3 minutes', t0 + interval '1 hour');
  raise notice 'after: escort step %; the raid on the ward called %; the escort on its sheet as %, her hulls on it %', v_esc, v_call,
    (select bs.how from public.battle_sides bs where bs.battle_id = v_bat and bs.fleet_id = v_n[2]),
    (select string_agg(k.code, '+' order by k.code) from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = v_n[2]);
end $s$;

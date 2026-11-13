do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
-- ATTACKS, LOCAL SCENE (it WRITES: switches, purses, companies, ships, real battles). Never a prod query: the line above refuses on a real server.
-- What the after-check of lighting attack_enabled reads, made on the local world so the six check files can be seen to answer:
--   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/attacks/run.mjs --cron scripts/ops/harness/attacks/scene-battles.sql scripts/ops/harness/attacks/after-battles.sql \
--     scripts/ops/harness/attacks/after-rounds.sql scripts/ops/harness/attacks/after-loot.sql scripts/ops/harness/attacks/after-job.sql scripts/ops/harness/attacks/after-held.sql \
--     scripts/ops/harness/attacks/cargo-at-sea.sql scripts/ops/harness/attacks/before-light.sql
-- The world as production will be when attacks are lit (the armed cargo ship, the navy, regard, crown hulls at level 5), then, through the real functions (public.attack_for, the real
-- job public.tick_battles minute by minute, public.cargo_ship_step, voyage.settle):
--   battle 1   two galleons on an armed cargo ship with 400,000 aboard, begun 20 minutes ago, fought round by round by the job to its clock's end;
--   battle 2   a Nau on another, begun 19 minutes ago, with a Flee kept from 70 s in (a stance row, as cmd.battle_stance writes it);
--   battle 3   two galleons on a third, begun 30 s ago: still FIGHTING when the checks read;
--   then battle 1's cargo ship is given her speed back and settled to her arrival, so a HELD voyage that has ARRIVED is there for after-held.sql.
-- It prints one notice with what it made. The runner rolls everything back.
do $$
declare
  t0    timestamptz := now() - interval '20 minutes';
  v_es  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'ESP');
  v_cap uuid;
  v_f   uuid[] := '{}';
  v_d   uuid[] := '{}';
  v_b   uuid[] := '{}';
  v_p   uuid;
  v_x   uuid;
  c     public.cargo_ships%rowtype;
  i     int;
  g     int;
  v_at  timestamptz;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'convoys_enabled', 'convoy_armed_enabled', 'navy_enabled', 'regard_enabled', 'npc_ship_level_enabled', 'attack_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  update public.ports set crew_pool = 5000;
  v_cap := public.realm_capital(v_es);
  for i in 1 .. 2 loop perform public.tick_cargo_ships(t0, v_es); end loop;
  insert into public.navy_realms (nation_id, ships, read_at) values (v_es, 25, now()) on conflict (nation_id) do update set ships = 25, read_at = now();
  v_x := public.navy_commission(v_es, 1, v_cap, public.refit_yard(v_cap), v_cap, t0);
  update public.ships s set crew = k.crew_required from public.ship_classes k where k.id = s.class_id and s.fleet_id = v_x;
  perform public.crown_hull_level_fix();

  for i in 1 .. 3 loop
    v_at := case i when 1 then t0 when 2 then t0 + interval '1 minute' else now() - interval '30 seconds' end;
    v_p := public.new_house(('00000000-0375-4000-8000-' || lpad(i::text, 12, '0'))::uuid, 'Casa Cena ' || i, 'PRT', 'LIS', 'Cena ' || i, case i when 2 then 'nau' else 'galion' end, 'Cena ' || i, null, false);
    select f.id into v_x from public.fleets f where f.player_id = v_p;
    if i <> 2 then perform public.commission_ship(v_p, v_x, 'galion', 'Cena ' || i || '.2', false, true); end if;
    update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b), cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_x;
    v_f := v_f || v_x;
    select x.* into c from public.cargo_ships x join public.fleets f on f.id = x.fleet_id
     where x.nation_id = v_es and f.status = 'DOCKED' and x.out_load is null and not exists (select 1 from public.cargo_ship_aboard(x.fleet_id)) order by x.ord limit 1;
    update public.fleets set ready_at = null where id = c.fleet_id;
    perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, 400000);
    perform public.cargo_ship_step(c.fleet_id, v_at);
    update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
     where vo.fleet_id = c.fleet_id and vo.status = 'SAILING';
    perform voyage.recompute_eta(vo.id) from public.voyages vo where vo.fleet_id = c.fleet_id and vo.status = 'SAILING';
    v_d := v_d || c.fleet_id;
    update public.fleets f set status = 'ANCHORED', port_id = null, lat = p.lat, lon = p.lon, version = f.version + 1 from voyage.fleet_point(c.fleet_id, v_at) p where f.id = v_x;
    v_b := v_b || (public.attack_for(v_p, v_x, c.fleet_id, null, v_at) ->> 'battle_id')::uuid;
  end loop;
  -- battle 2: Flee, kept from 70 s in
  insert into public.battle_stances (battle_id, fleet_id, set_at, stance) values (v_b[2], v_f[2], t0 + interval '130 seconds', 'FLEE');
  -- the real job, minute by minute, for nine minutes from the first battle's start
  for g in 1 .. 9 loop
    perform public.tick_battles(t0 + make_interval(mins => g));
  end loop;
  -- battle 1's cargo ship sails on at her own speed and is settled to her arrival
  update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric * 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
   where vo.fleet_id = v_d[1] and vo.status = 'SAILING';
  perform voyage.recompute_eta(vo.id) from public.voyages vo where vo.fleet_id = v_d[1] and vo.status = 'SAILING';
  perform voyage.settle(v_d[1], now());
  raise notice 'scene: battles % (% / % / %), the held voyage of battle 1 is %, loot in the ledger %',
    v_b, (select b.status || ' ' || coalesce(b.result ->> 'outcome', '') from public.battles b where b.id = v_b[1]),
    (select b.status || ' ' || coalesce(b.result ->> 'outcome', '') from public.battles b where b.id = v_b[2]),
    (select b.status from public.battles b where b.id = v_b[3]),
    (select string_agg(v.status || ' day ' || v.last_settled_day, ', ') from public.voyages v where v.fleet_id = v_d[1]),
    (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.kind = 'LOOT' and l.created_at > now() - interval '1 hour');
end $$;

-- 0334 DARK PARITY SCENE: run by proof-0334.mjs on the world BEFORE the file and AFTER it, rolled back each time. Every line must be equal.
-- A human company and a merchant each sail five fixed-id voyages through real seas on a hot sea (hazard_mult 1000), through the real depart, roll and settle, with the real fight: every day's roll, the frozen path, the quote, each day written, the hold,
-- the hull, the crew, the purse. It names only what existed before 0334. The scene sets regard lit and a Hostile regard, so a dark hunt is proved dark for the very company it would hunt.
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this scene writes and its runner rolls it back. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite), so `db query --linked -f` can never commit it on production.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
declare
  v_nat  uuid;
  v_cap  uuid;
  v_hum  uuid;
  v_hfl  uuid;
  v_mer  uuid;
  v_fl   uuid;
  v_voy  uuid;
  v_seg  jsonb;
  v_day  int;
  v_at   timestamptz := timestamptz '2026-11-06 00:00:00+00';
  v_ids  uuid[];
  v_i    int;
  r      record;
  x      record;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'combat_bite', 'regard_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 90000000, reserve = 0;
  select g.nation_id, p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where n.code = 'PRT';
  update public.world_config set value = to_jsonb(0.9) where key = 'hazard_p_max';
  -- two hulls of the built world, because a fresh hull rolls its own figures. The first house is made a company for the scene.
  select nf.fleet_id, f.player_id into v_hfl, v_hum from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.status = 'DOCKED' order by nf.roster_ord limit 1;
  select nf.fleet_id into v_mer from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.status = 'DOCKED' and f.player_id <> v_hum order by nf.roster_ord limit 1;
  update public.players p set is_npc = false, ducats = 500000 where p.id = v_hum;
  update public.players p set nation_id = (select n.id from public.nations n where n.code = 'ESP') where p.id = v_hum;
  update public.fleets f set port_id = v_cap where f.id in (v_hfl, v_mer);
  insert into public.house_regard (player_id, nation_id, points, as_of) values (v_hum, v_nat, -5000, now());

  for r in select * from (values (v_hfl, 'human'), (v_mer, 'merchant')) t(fleet, who) loop
    v_fl := r.fleet;
    v_ids := array[]::uuid[];
    for v_i in 1 .. 8 loop
      update public.ships s set durability = 900, crew = 40, water_t = 4000, food_t = 4000, cargo = jsonb_build_object((select g.code from public.goods g order by g.code limit 1), 500), cargo_basis = '{}'::jsonb where s.fleet_id = v_fl;
      select jsonb_agg(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', 4000, 'sea_id', s.id, 'hazard_mult', 1000) order by s.code)
        into v_seg
        from (select x2.id, x2.code from public.seas x2 order by md5(x2.code || v_i::text) limit 6) s;
      v_voy := voyage.depart(v_fl, v_seg, v_cap, null, v_at);
      -- a fresh id is random, and the roll keys on it: pin it, so both worlds roll the same days
      update public.voyages vo set id = (md5(r.who || v_i::text))::uuid where vo.id = v_voy;
      v_voy := (md5(r.who || v_i::text))::uuid;
      raise notice 'SCENE: % % path %', r.who, v_i, md5((select vo.path::text from public.voyages vo where vo.id = v_voy));
      raise notice 'SCENE: % % quote %', r.who, v_i, voyage.risk_quote(v_voy);
      for v_day in 1 .. voyage.total_days(v_voy) loop
        select * into x from voyage.hazard_roll(v_voy, v_day);
        raise notice 'SCENE: % % roll % % % % %', r.who, v_i, v_day, x.occurred, x.kind, x.magnitude, x.p_hazard;
      end loop;
      perform voyage.settle(v_fl, (select vo.eta from public.voyages vo where vo.id = v_voy) + interval '1 hour');
      for x in select e.day_index, e.kind, e.payload from public.voyage_events e where e.voyage_id = v_voy order by e.day_index loop
        raise notice 'SCENE: % % day % % %', r.who, v_i, x.day_index, x.kind, x.payload::text;
      end loop;
      raise notice 'SCENE: % % ship %', r.who, v_i, (select string_agg(s.durability || ':' || s.crew || ':' || s.cargo::text, ',' order by s.id) from public.ships s where s.fleet_id = v_fl);
      raise notice 'SCENE: % % purse %', r.who, v_i, (select p.ducats from public.players p join public.fleets f on f.player_id = p.id where f.id = v_fl);
      update public.fleets f set status = 'DOCKED', port_id = v_cap, lat = null, lon = null, ready_at = null where f.id = v_fl;
      update public.voyages vo set status = 'ARRIVED' where vo.fleet_id = v_fl and vo.status = 'SAILING';
    end loop;
  end loop;

  -- the three other bodies re-cut: a fine at the capital and the hall's line, for a company with no mark
  raise notice 'SCENE: line %', public.regard_line(v_cap, v_hum)::text;
  raise notice 'SCENE: fine %', public.fine_for(v_hum, v_cap, 1000)::text;
  raise notice 'SCENE: line after %', public.regard_line(v_cap, v_hum)::text;
end
$$;

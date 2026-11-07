// cost-0340.mjs — what the hunt pass costs, on the probe world: dark (one knob read), lit with no pirate ship out (one read), and lit with the design's 75 navy hulls at work in port
// and 30 pirate ships cruising, so every navy ship reads her sea and asks public.pirate_ship_in_sea. Each run is one rolled-back transaction. The dev-log's projection scales PGlite by 0331's x 6.7.
export async function cost(db, before, file, say) {
  const scene = `
do $$
declare
  v_t   timestamptz := now();
  v_nat uuid;
  v_cap uuid;
  v_f   uuid;
  v_pl  uuid;
  v_pir uuid := (select n.id from public.nations n where n.code = 'PIR');
  v_por uuid := (select p.id from public.ports p where p.code = 'POR');
  v_k   int := 0;
  i     int;
  r     record;
  t0    timestamptz;
  v_ms  numeric[] := '{}';
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('navy_enabled', 'pirates_bite');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 90000000, reserve = 0;
  -- dark
  for i in 1 .. 5 loop
    t0 := clock_timestamp();
    perform public.navy_hunt_pass(v_t, null);
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - t0) * 1000, 2);
  end loop;
  raise notice 'COST: dark pass x5 ms %', v_ms;
  -- lit, no pirate ship out
  update public.world_config set value = 'true'::jsonb where key in ('navy_enabled', 'pirates_bite');
  v_ms := '{}';
  for i in 1 .. 5 loop
    t0 := clock_timestamp();
    perform public.navy_hunt_pass(v_t, null);
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - t0) * 1000, 2);
  end loop;
  raise notice 'COST: lit, no pirate out, pass x5 ms %', v_ms;
  -- 75 navy hulls at work in port, one country at a time, and 30 pirate ships cruising 30 seas; the navy ships' seas hold none of them, so every ship reads her sea and asks, and nobody fights
  for r in select g.nation_id, n.code from public.great_powers g join public.nations n on n.id = g.nation_id where not g.pirate order by n.code loop
    v_cap := public.realm_capital(r.nation_id);
    insert into public.navy_realms (nation_id, ships, read_at) values (r.nation_id, 24, v_t) on conflict (nation_id) do update set ships = 24, read_at = v_t;
    for i in 1 .. (select case r.code when 'PRT' then 15 when 'FRA' then 13 when 'ESP' then 11 when 'NLD' then 10 when 'MNG' then 7 when 'OTT' then 5 when 'JPN' then 5 when 'MUG' then 4 when 'ENG' then 3 else 2 end) loop
      v_f := public.navy_commission(r.nation_id, i, v_cap, public.refit_yard(v_cap), v_cap, v_t);
      v_k := v_k + 1;
    end loop;
  end loop;
  i := 0;
  for r in select s.id from public.seas s where s.id not in (select p.sea_id from public.ports p join public.navy_ships n on n.station_port = p.id) order by s.code limit 30 loop
    i := i + 1;
    insert into public.players (company_name, nation_id, ducats, is_npc) values (format('Brethren cost %s', i), v_pir, 0, true) returning id into v_pl;
    v_f := public.form_fleet(v_pl, format('Pirate ship %s', i), v_por);
    perform public.commission_ship(v_pl, v_f, 'xebec', format('Pirate ship %s', i), true, false);
    insert into public.pirate_ships (fleet_id, player_id, ord, home_port, sea_id, mission, haunt_port, last_port) values (v_f, v_pl, i, v_por, r.id, 'CRUISE', v_por, v_por);
  end loop;
  v_ms := '{}';
  for i in 1 .. 5 loop
    t0 := clock_timestamp();
    perform public.navy_hunt_pass(v_t, null);
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - t0) * 1000, 2);
  end loop;
  raise notice 'COST: lit, % navy hulls in port and % pirate ships out in other seas, pass x5 ms %', v_k, i, v_ms;
  -- the hunt's targets of every station, once each: what a ship at her station pays to pick
  v_ms := '{}';
  for r in select distinct n.station_port from public.navy_ships n loop
    t0 := clock_timestamp();
    perform count(*) from public.navy_hunt_targets(r.station_port, v_t);
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - t0) * 1000, 2);
  end loop;
  raise notice 'COST: navy_hunt_targets, one read a station, ms %', v_ms;
  raise exception using errcode = 'ZY341';
exception when sqlstate 'ZY341' then
  null;
end
$$;`
  const notes = []
  await db.exec('begin')
  let err = null
  try {
    if (before) await db.exec(before)
    await db.exec(file)
    await db.exec(scene, { onNotice: (n) => notes.push(n.message) })
  } catch (e) {
    err = e.message
  }
  try { await db.exec('rollback') } catch { /* already aborted */ }
  for (const n of notes.filter((x) => x.startsWith('COST:'))) say('  ', n)
  if (err) say('  COST ERROR', err)
}

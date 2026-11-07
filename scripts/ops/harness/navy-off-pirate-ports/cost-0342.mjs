// cost-0342.mjs — what the re-cut choosers cost on the probe world, BEFORE and AFTER the file, each in a rolled-back transaction: the call's reader (public.harbour_nearest) at the ten capitals' points,
// a patrol written from Lisbon's station (public.navy_patrol_build), an hour of upkeep for ten ships at ten harbours (public.navy_pay), the hunt's targets of Lisbon (public.navy_hunt_targets), and the reader
// itself over every harbour (after only). The dev-log's projection scales PGlite by 0331's x 6.7.
export async function cost(db, file, say) {
  const scene = `
do $$
declare
  v_t   timestamptz := now();
  v_nat uuid;
  v_cap uuid;
  v_st  bigint;
  v_f   uuid;
  r     record;
  t0    timestamptz;
  v_ms  numeric[] := '{}';
  i     int;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'navy_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('pirates_bite', 'attack_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 90000000, reserve = 0;
  select g.nation_id, p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where n.code = 'PRT';
  -- the call's reader at the ten capitals' points, x3
  for i in 1 .. 3 loop
    t0 := clock_timestamp();
    for r in select p.lat, p.lon from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where not g.pirate loop
      perform public.harbour_nearest(r.lat::float8, r.lon::float8);
    end loop;
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  end loop;
  raise notice 'COST: harbour_nearest, ten capitals'' points, ms x3 %', v_ms;
  -- a patrol written from Lisbon's station
  insert into public.navy_realms (nation_id, ships, read_at) values (v_nat, 10, v_t) on conflict (nation_id) do update set ships = 10, read_at = v_t;
  perform public.navy_plan_step(v_t, v_nat);
  select s.id into v_st from public.navy_stations s where s.nation_id = v_nat and s.port_id = v_cap and s.retired_at is null;
  v_ms := '{}';
  for i in 1 .. 3 loop
    delete from public.navy_patrol_legs l where l.station_id = v_st;
    t0 := clock_timestamp();
    perform public.navy_patrol_build(v_st, v_t);
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  end loop;
  raise notice 'COST: navy_patrol_build, Lisbon''s station, ms x3 %', v_ms;
  -- an hour of upkeep for ten ships at ten harbours in reach
  i := 0;
  for r in select x.port_id from voyage.reach_from(v_cap) x join public.ports p on p.id = x.port_id where p.kind = 'HARBOUR' and not p.is_ice_closed and x.port_id <> v_cap order by x.nm, x.code limit 10 loop
    i := i + 1;
    v_f := public.navy_commission(v_nat, i, v_cap, public.refit_yard(v_cap), r.port_id, v_t);
  end loop;
  v_ms := '{}';
  for i in 1 .. 3 loop
    update public.navy_realms x set paid_at = null where x.nation_id = v_nat;
    t0 := clock_timestamp();
    perform public.navy_pay(v_t, v_nat);
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  end loop;
  raise notice 'COST: navy_pay, ten ships at ten harbours, ms x3 %', v_ms;
  -- the hunt's targets of Lisbon
  v_ms := '{}';
  for i in 1 .. 3 loop
    t0 := clock_timestamp();
    perform count(*) from public.navy_hunt_targets(v_cap, v_t);
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  end loop;
  raise notice 'COST: navy_hunt_targets, Lisbon, ms x3 %', v_ms;
  if to_regprocedure('public.navy_harbour_ok(uuid)') is not null then
    v_ms := '{}';
    for i in 1 .. 3 loop
      t0 := clock_timestamp();
      execute 'select count(*) from public.ports p where p.kind = ''HARBOUR'' and public.navy_harbour_ok(p.id)';
      v_ms := v_ms || round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
    end loop;
    raise notice 'COST: navy_harbour_ok over every harbour, ms x3 %', v_ms;
  end if;
  raise exception using errcode = 'ZY342';
exception when sqlstate 'ZY342' then
  null;
end
$$;`
  for (const [label, sqls] of [['BEFORE the file', [scene]], ['AFTER the file', [file, scene]]]) {
    const notes = []
    await db.exec('begin')
    let err = null
    try {
      for (const s of sqls) await db.exec(s, { onNotice: (n) => notes.push(n.message) })
    } catch (e) {
      err = e.message
    }
    try { await db.exec('rollback') } catch { /* already aborted */ }
    say(`  ${label}`)
    for (const n of notes.filter((x) => x.startsWith('COST:'))) say('    ', n)
    if (err) say('    COST ERROR', err)
  }
}

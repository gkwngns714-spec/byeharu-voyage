-- 0339 COST SCENE: run by proof-0339.mjs --cost on the world BEFORE the file and AFTER it, rolled back each time. The hot paths this file touches, DARK (the switch off, as on prod), priced per call:
--   voyage.depart (one more stable read: voyage.freeze_raiders on the frozen segments), voyage.settle on a PIRATES day (voyage.leg_raider on the day's segment), public.tick_market_drift on one harbour (one constant column).
-- Prints COST: lines; the harness prints them side by side. Not a verdict: a stopwatch on shared wasm hardware, read for the ORDER of the cost, never asserted.
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this scene writes and its runner rolls it back. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite), so `db query --linked -f` can never commit it on production.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
declare
  v_nat  uuid;
  v_cap  uuid;
  v_por  uuid;
  v_hum  uuid;
  v_hfl  uuid;
  v_voy  uuid;
  v_p    jsonb;
  v_t0   timestamptz;
  v_i    int;
  c_t    constant timestamptz := '2026-11-07 12:00:00+00';
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'combat_bite');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  select g.nation_id, p.id into v_nat, v_cap from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where n.code = 'PRT';
  v_por := (select p.id from public.ports p where p.code = 'POR');
  insert into public.players (company_name, nation_id, ducats) values ('Cost 0339 house', v_nat, 1000000) returning id into v_hum;
  v_hfl := public.form_fleet(v_hum, 'Cost 0339 fleet', v_cap);
  perform public.commission_ship(v_hum, v_hfl, 'navire', 'Cost 0339 hull', true, true);
  update public.ships s set water_t = 100000, food_t = 100000 where s.fleet_id = v_hfl;
  -- a path of 12 segments through 12 seas, as a real passage has
  v_p := (select jsonb_agg(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', round(voyage.fleet_speed(v_hfl) * 24, 2), 'sea_id', s.id, 'hazard_mult', 1000) order by d.n)
            from generate_series(1, 12) d(n) cross join lateral (select x.id from public.seas x order by x.code offset d.n - 1 limit 1) s);

  -- 200 departures
  v_t0 := clock_timestamp();
  for v_i in 1 .. 200 loop
    v_voy := voyage.depart(v_hfl, v_p, v_cap, v_cap, c_t);
    update public.voyages set status = 'ABORTED' where id = v_voy;
    update public.fleets f set status = 'DOCKED', port_id = v_cap, lat = null, lon = null where f.id = v_hfl;
  end loop;
  raise notice 'COST: depart % ms a call (200)', round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 200, 3);

  -- 200 PIRATES days through the real settle (the sea stubbed on PIRATES; the fight is the same engine before and after)
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_c39;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language plpgsql stable
as $b$
begin
  return query select true, 'PIRATES'::text, 0.5::numeric, 1::numeric;
end
$b$
  $f$;
  v_voy := voyage.depart(v_hfl, v_p, v_cap, v_cap, c_t);
  update public.voyages set id = '00000000-0339-4000-8000-00000000c057' where id = v_voy;
  v_t0 := clock_timestamp();
  for v_i in 1 .. 12 loop
    perform voyage.settle(v_hfl, voyage.day_ends_at('00000000-0339-4000-8000-00000000c057', v_i));
    update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = 60, water_t = 100000, food_t = 100000 where s.fleet_id = v_hfl;
  end loop;
  raise notice 'COST: settle PIRATES day % ms a day (12)', round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 12, 3);

  -- the market's regen on one harbour, three runs
  v_t0 := clock_timestamp();
  perform public.tick_market_drift(c_t + interval '1 day', v_por);
  perform public.tick_market_drift(c_t + interval '2 days', v_por);
  perform public.tick_market_drift(c_t + interval '3 days', v_por);
  raise notice 'COST: tick_market_drift one harbour % ms a run (3)', round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 3, 3);

  raise exception using errcode = 'ZY33C';
exception when sqlstate 'ZY33C' then
  null;
end
$$;

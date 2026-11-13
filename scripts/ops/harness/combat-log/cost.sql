-- 0353 COST SCENE: run by proof-0353.mjs --cost on the world AFTER the file, rolled back. The hot path this file touches, priced per call, the OLD bodies against the NEW, INTERLEAVED:
--   voyage.settle on a PIRATES day (the arrivals job's day: voyage.fight, voyage.raid_opts, voyage.raid_report, public.fight_sides) for a MERCHANT (the mass: her day must not move),
--   for a COMPANY with no order (NEW builds the log), under Flee and under Pay (NEW only: no old body has them); and voyage.depart (one more stable read, voyage.freeze_order).
-- Each sample is one subtransaction that is rolled back: [the old bodies put back from the migration's own hunks (pg_temp.to_old_scene, laid before this file by the runner)], a
-- two-day departure with the voyage id pinned, day 1 settled untimed (every body compiled), day 2 timed. Odd samples run OLD then NEW, even ones NEW then OLD.
-- Prints COST: lines. Not a verdict: a stopwatch on shared wasm hardware, read for the ORDER of the cost, never asserted.
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this scene writes and its runner rolls it back. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite), so `db query --linked -f` can never commit it on production.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
begin
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_c53;
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
end
$$;

-- one sample: ms of a PIRATES day (day 2 of a pinned two-day voyage) and of the departure, under the old bodies or the new
create function pg_temp.sample_c53(p_fleet uuid, p_sea uuid, p_seed int, p_old boolean, out day_ms numeric, out depart_ms numeric, out bytes int) language plpgsql as $b$
declare
  c_t   constant timestamptz := '2026-11-11 12:00:00+00';
  v_voy uuid;
  v_id  uuid := ('00000000-0353-4000-8000-' || lpad(p_seed::text, 12, '0'))::uuid;
  v_port uuid := (select f.port_id from public.fleets f where f.id = p_fleet);
  v_p   jsonb := (select jsonb_agg(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', voyage.fleet_speed(p_fleet) * 24, 'sea_id', p_sea, 'hazard_mult', 1000))
                    from generate_series(1, 2));
  t0    timestamptz;
begin
  begin
    if p_old then
      perform pg_temp.to_old_scene();
    end if;
    -- a departure, untimed (compiles), then one timed on the same fleet
    v_voy := voyage.depart(p_fleet, v_p, v_port, v_port, c_t);
    update public.voyages set status = 'ABORTED' where id = v_voy;
    update public.fleets f set status = 'DOCKED', port_id = v_port, lat = null, lon = null where f.id = p_fleet;
    t0 := clock_timestamp();
    v_voy := voyage.depart(p_fleet, v_p, v_port, v_port, c_t);
    depart_ms := extract(epoch from clock_timestamp() - t0) * 1000;
    update public.voyages set id = v_id where id = v_voy;
    perform voyage.settle(p_fleet, voyage.day_ends_at(v_id, 1));
    update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select c.crew_required from public.ship_classes c where c.id = s.class_id) where s.fleet_id = p_fleet;
    t0 := clock_timestamp();
    perform voyage.settle(p_fleet, voyage.day_ends_at(v_id, 2));
    day_ms := extract(epoch from clock_timestamp() - t0) * 1000;
    bytes := (select length(e.payload::text) from public.voyage_events e where e.voyage_id = v_id and e.day_index = 2 and e.kind = 'PIRATES');
    if bytes is null then
      raise exception 'cost scene: day 2 was no PIRATES day';
    end if;
    raise exception using errcode = 'ZX353', message = 'SAMPLE_ROLLBACK';
  exception when sqlstate 'ZX353' then
    null;
  end;
end
$b$;

do $$
declare
  c_n    constant int := 40;
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_sea  uuid := (select s.id from public.seas s order by s.piracy_index desc, s.code limit 1);
  v_hum  uuid;
  v_hfl  uuid;
  v_npc  uuid;
  v_nfl  uuid;
  v_i    int;
  r      record;
  v_o    numeric[];
  v_w    numeric[];
  v_do   numeric[];
  v_dw   numeric[];
  v_bo   int;
  v_bw   int;
  v_who  text;
  v_fl   uuid;
  v_ord  text;
begin
  update public.world_config set value = 'true'::jsonb where key in ('combat_bite', 'city_treasury_enabled', 'raid_orders_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  insert into public.players (company_name, nation_id, ducats) values ('Cost 0353 house', (select n.id from public.nations n where n.code = 'PRT'), 1000000) returning id into v_hum;
  v_hfl := public.form_fleet(v_hum, 'Cost 0353 fleet', v_lis);
  perform public.commission_ship(v_hum, v_hfl, 'jacht', 'Cost 0353 hull', true, true);
  v_npc := public.new_house(null, 'Cost 0353 merchant', 'PRT', p_ducats => 20000, p_is_npc => true);
  select f.id into v_nfl from public.fleets f where f.player_id = v_npc;
  update public.ships s set water_t = 100000, food_t = 100000, cargo = '{"baltic-amber": 10}'::jsonb, cargo_basis = '{"baltic-amber": 2000}'::jsonb where s.fleet_id in (v_hfl, v_nfl);

  foreach v_who in array array['merchant', 'company'] loop
    v_fl := case v_who when 'merchant' then v_nfl else v_hfl end;
    v_o := '{}'; v_w := '{}'; v_do := '{}'; v_dw := '{}';
    for v_i in 1 .. c_n loop
      if v_i % 2 = 1 then
        select * into r from pg_temp.sample_c53(v_fl, v_sea, v_i, true);  v_o := v_o || r.day_ms; v_do := v_do || r.depart_ms; v_bo := r.bytes;
        select * into r from pg_temp.sample_c53(v_fl, v_sea, v_i, false); v_w := v_w || r.day_ms; v_dw := v_dw || r.depart_ms; v_bw := r.bytes;
      else
        select * into r from pg_temp.sample_c53(v_fl, v_sea, v_i, false); v_w := v_w || r.day_ms; v_dw := v_dw || r.depart_ms; v_bw := r.bytes;
        select * into r from pg_temp.sample_c53(v_fl, v_sea, v_i, true);  v_o := v_o || r.day_ms; v_do := v_do || r.depart_ms; v_bo := r.bytes;
      end if;
    end loop;
    raise notice 'COST: a % PIRATES day through voyage.settle, % pairs interleaved: OLD median % ms (mean %), NEW median % ms (mean %); the day''s payload % characters OLD, % NEW',
      v_who, c_n,
      (select round((percentile_cont(0.5) within group (order by x))::numeric, 3) from unnest(v_o) x), (select round(avg(x), 3) from unnest(v_o) x),
      (select round((percentile_cont(0.5) within group (order by x))::numeric, 3) from unnest(v_w) x), (select round(avg(x), 3) from unnest(v_w) x), v_bo, v_bw;
    raise notice 'COST: a % departure (voyage.depart, 2 segments), % pairs interleaved: OLD median % ms, NEW median % ms',
      v_who, c_n,
      (select round((percentile_cont(0.5) within group (order by x))::numeric, 3) from unnest(v_do) x),
      (select round((percentile_cont(0.5) within group (order by x))::numeric, 3) from unnest(v_dw) x);
  end loop;

  -- a company under each order (NEW only)
  foreach v_ord in array array['FLEE', 'PAY'] loop
    insert into public.fleet_raid_orders (fleet_id, raid_order) values (v_hfl, v_ord) on conflict (fleet_id) do update set raid_order = excluded.raid_order;
    v_w := '{}'; v_dw := '{}';
    for v_i in 1 .. c_n loop
      select * into r from pg_temp.sample_c53(v_hfl, v_sea, v_i, false); v_w := v_w || r.day_ms; v_dw := v_dw || r.depart_ms; v_bw := r.bytes;
    end loop;
    raise notice 'COST: a company PIRATES day under %, % samples: NEW median % ms (mean %), payload % characters; her departure median % ms',
      v_ord, c_n, (select round((percentile_cont(0.5) within group (order by x))::numeric, 3) from unnest(v_w) x), (select round(avg(x), 3) from unnest(v_w) x), v_bw,
      (select round((percentile_cont(0.5) within group (order by x))::numeric, 3) from unnest(v_dw) x);
  end loop;
end
$$;

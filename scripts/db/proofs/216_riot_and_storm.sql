-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 216 - RIOT AND STORM  (migration 0511; docs/design/owner-spec-plan-2026-11-25.md 0.5; docs/dev-log/2026-11-25-riot-and-storm.md)
--
--   Its own company and passages; the switch thrown here and rolled back by proof.mjs. A day's hazard is made nothing (hazard_mult 0) or a storm every day (the
--   kinds' shares and hazard_p_max written here): no die of the world is waited for, no price, no real company, no date is read.
--
-- @pass RS_DARK      dark, a dry day is 0279's: home the same day, the hold empty, no hand lost, and the terms are not on her path
-- @pass RS_RIOT      lit, a dry day takes 15 % of the crew and 5 % of each good and she sails on; three leave 61 % and about 86 %; the record says what it cost
-- @pass RS_SOME      never all: a hull's last hand and a good's last unit stay, however many riots; under a quarter of the minimum she is home with what she holds
-- @pass RS_STORM     a storm kills 2 to 5 % of the crew and loses 1 to 2 % of each good, over 200 storm days; the hull's loss and the delay are as they were
-- @pass RS_FROZEN    a voyage that left dark is settled dark whatever the switch says later; one that left lit stays lit; settled late or day by day it loses the same
-- @pass RS_SLOW      below the minimum crew a hull sails at crew / minimum, never under 30 % (dark 70 %), and hands lost at sea cost her hours, never a day at her ETA
-- @pass RS_MERCHANT  a merchant's departure carries no terms, and a merchant's short hull sails as it did
-- @pass RS_ONLY      two kinds are new, neither is drawn, and no sickness, fire, leak or rats exists
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- a passage of p_days west of Lisbon, left now; her hold 1,000 units of one good at 50, p_crew hands, p_stores days of stores
create function pg_temp.go216(p_fl uuid, p_lit boolean, p_days int, p_crew int, p_stores numeric, p_mult numeric) returns uuid language plpgsql as $f$
declare v uuid; v_lis uuid := (select id from public.ports where code = 'LIS'); v_good text := (select g.code from public.goods g order by g.code limit 1);
begin
  update public.world_config set value = to_jsonb(p_lit) where key = 'happenings_bite';
  update public.ships s set cargo = jsonb_build_object(v_good, 1000), cargo_basis = jsonb_build_object(v_good, 50), crew = p_crew,
         water_t = p_crew * public.wc_num('water_per_crew_day') * p_stores, food_t = p_crew * public.wc_num('food_per_crew_day') * p_stores,
         durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = p_fl;
  v := voyage.depart(p_fl, (select jsonb_agg(jsonb_build_object('a', jsonb_build_array(38.5, -9.6 - (d - 1)), 'b', jsonb_build_array(38.5, -9.6 - d),
         'nm', voyage.fleet_speed(p_fl) * 24, 'hazard_mult', p_mult, 'sea_id', (select p.sea_id from public.ports p where p.id = v_lis)) order by d)
         from generate_series(1, p_days) d), v_lis, v_lis, now());
  return v;
end $f$;
create function pg_temp.crew216(p_fl uuid) returns int language sql as $f$ select sum(s.crew)::int from public.ships s where s.fleet_id = p_fl $f$;

do $p$
declare
  v_me uuid; v_fl uuid; v_voy uuid; v_lis uuid := (select id from public.ports where code = 'LIS');
  v_good text := (select g.code from public.goods g order by g.code limit 1);
  v_min int; r record; v_n int; v_lo numeric; v_hi numeric; v_a jsonb; v_b jsonb; v_x numeric; v_y numeric; v_t timestamptz; v_at timestamptz; v_c int; d int;
  v_dead numeric := 0; v_seen numeric := 0; v_lost numeric := 0; v_had numeric := 0; v_q numeric;
begin
  v_me := public.new_house('00000000-0511-4000-8000-0000000002a1', 'Casa do Motim 216', 'PRT');
  select id into v_fl from public.fleets where player_id = v_me;
  select sum(c.crew_required) into v_min from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_fl;

  -- ── RS_DARK ──
  begin
    v_voy := pg_temp.go216(v_fl, false, 20, 100, 0, 0);
    perform voyage.settle(v_fl, voyage.day_ends_at(v_voy, 1) + interval '1 millisecond');
    if not exists (select 1 from public.voyage_events e where e.voyage_id = v_voy and e.kind = 'FORCED_HOME') or pg_temp.crew216(v_fl) <> 100
       or public.fleet_stock_at_cost(v_fl) <> 0 or (select path->0 ? 'hap' from public.voyages where id = v_voy) then
      raise exception 'PROOF 216 FAIL: dark, the dry day is not as it was';
    end if;
    raise exception using errcode = 'ZY216', message = 'x';
  exception when sqlstate 'ZY216' then null; end;
  raise notice 'PASS: RS_DARK - dark: home the same day, the hold empty, 100 hands, no terms on the path';

  -- ── RS_RIOT ──
  begin
    v_voy := pg_temp.go216(v_fl, true, 30, 100, 0, 0);
    perform voyage.settle(v_fl, voyage.day_ends_at(v_voy, 1) + interval '1 millisecond');
    select * into r from public.voyage_events e where e.voyage_id = v_voy and e.day_index = 1;
    if r.kind <> 'RIOT' or pg_temp.crew216(v_fl) <> 85 or public.fleet_cargo_qty(v_fl, v_good) <> 950 or (r.payload->>'crew_lost')::int <> 15
       or (r.payload->>'cargo_lost_cost')::int <> 2500 or (r.payload->>'cargo_lost_pct')::numeric <> 5 or (select status from public.fleets where id = v_fl) <> 'SAILING'
       or voyage.report_line(1, 'RIOT', r.payload) <> 'Day 1. Riot: no food or water. Crew −15. Cargo −5.0%.' then
      raise exception 'PROOF 216 FAIL: the first dry day: % / %', to_jsonb(r), voyage.report_line(1, 'RIOT', r.payload);
    end if;
    perform voyage.settle(v_fl, voyage.day_ends_at(v_voy, 3) + interval '1 millisecond');
    if pg_temp.crew216(v_fl) <> 61 or public.fleet_cargo_qty(v_fl, v_good) not between 855 and 860
       or (select sum((e.payload->>'cargo_lost_cost')::numeric) from public.voyage_events e where e.voyage_id = v_voy) <> 50000 - public.fleet_stock_at_cost(v_fl) then
      raise exception 'PROOF 216 FAIL: three dry days: % hands, % units', pg_temp.crew216(v_fl), public.fleet_cargo_qty(v_fl, v_good);
    end if;
    raise exception using errcode = 'ZY216', message = 'x';
  exception when sqlstate 'ZY216' then null; end;
  raise notice 'PASS: RS_RIOT - 100 hands and 1,000 units: 85 and 950 after one dry day, sailing on; 61 hands after three; what was lost is written at its cost';

  -- ── RS_SOME ──
  begin
    v_voy := pg_temp.go216(v_fl, true, 30, 100, 0, 0);
    update public.ships set crew = 1, cargo = jsonb_build_object(v_good, 1) where fleet_id = v_fl;
    for d in 1 .. 40 loop perform voyage.happening_takes(v_voy, d, v_fl, 'RIOT', 0.15, 0.05); perform voyage.happening_takes(v_voy, d, v_fl, 'STORM', 0.99, 0.99); end loop;
    if exists (select 1 from public.ships s where s.fleet_id = v_fl and s.crew <> 1) or public.fleet_cargo_qty(v_fl, v_good) <> (select count(*) from public.ships where fleet_id = v_fl) then
      raise exception 'PROOF 216 FAIL: the last hand or the last unit was taken';
    end if;
    update public.ships set crew = 100, cargo = jsonb_build_object(v_good, 1000) where fleet_id = v_fl;
    for d in 1 .. 12 loop exit when (select status from public.fleets where id = v_fl) <> 'SAILING'; perform voyage.settle(v_fl, (select voyage.day_ends_at(v_voy, d) + interval '1 millisecond')); end loop;
    raise exception using errcode = 'ZY216', message = 'x';
  exception when sqlstate 'ZY216' then null; end;
  begin
    v_voy := pg_temp.go216(v_fl, true, 60, 100, 0, 0);
    update public.ships s set crew = ceil(c.crew_required * 0.30) from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fl;
    v_n := pg_temp.crew216(v_fl);
    for d in 1 .. 12 loop
      exit when (select status from public.fleets where id = v_fl) <> 'SAILING';
      perform voyage.settle(v_fl, voyage.day_ends_at(v_voy, d) + interval '1 millisecond');
    end loop;
    select * into r from public.voyage_events e where e.voyage_id = v_voy and e.kind = 'RIOT_HOME';
    if r.kind is null or (select status from public.fleets where id = v_fl) <> 'DOCKED' or public.fleet_cargo_qty(v_fl, v_good) < 600 or pg_temp.crew216(v_fl) < 1
       or (select status from public.voyages where id = v_voy) <> 'ABORTED' or (r.payload->>'cargo_lost_cost')::numeric <= 0 then
      raise exception 'PROOF 216 FAIL: broken (from % hands of %): %, % units', v_n, v_min, to_jsonb(r), public.fleet_cargo_qty(v_fl, v_good);
    end if;
    v_q := public.fleet_cargo_qty(v_fl, v_good);
    raise exception using errcode = 'ZY216', message = 'x';
  exception when sqlstate 'ZY216' then null; end;
  raise notice 'PASS: RS_SOME - the last hand and the last unit stay; under a quarter of her % minimum she is docked with % of 1,000 units', v_min, v_q;

  -- ── RS_STORM ──
  update public.voyage_event_kinds set mix_base = case when code = 'STORM' then 1 else 0.0001 end, mix_danger = 0, mix_raiders = 0 where in_sea_mix;
  update public.world_config set value = '1'::jsonb where key = 'hazard_p_max';
  v_lo := 1; v_hi := 0;
  for v_n in 1 .. 20 loop
    begin
      v_voy := pg_temp.go216(v_fl, true, 14, 1000, 900, 100000);
      for d in 1 .. 10 loop
        v_c := pg_temp.crew216(v_fl); v_q := public.fleet_cargo_qty(v_fl, v_good);
        update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_fl;
        perform voyage.settle(v_fl, voyage.day_ends_at(v_voy, d) + interval '1 millisecond');
        select * into r from public.voyage_events e where e.voyage_id = v_voy and e.day_index = d;
        continue when r.kind is distinct from 'STORM';
        if not (r.payload ? 'hull_lost') or (r.payload->>'delay_hours')::numeric <> 36 then
          raise exception 'PROOF 216 FAIL: the storm''s own loss or delay moved: %', r.payload;
        end if;
        v_x := (r.payload->>'crew_lost')::numeric / v_c; v_y := (v_q - public.fleet_cargo_qty(v_fl, v_good)) / v_q;
        if v_x not between 0.02 - 1.0 / v_c and 0.05 + 1.0 / v_c or v_y not between 0.01 - 1.0 / v_q and 0.02 + 1.0 / v_q then
          raise exception 'PROOF 216 FAIL: a storm took % of the crew and % of the goods: %', v_x, v_y, r.payload;
        end if;
        v_seen := v_seen + 1; v_dead := v_dead + v_x; v_lost := v_lost + v_y; v_lo := least(v_lo, v_x); v_hi := greatest(v_hi, v_x);
      end loop;
      raise exception using errcode = 'ZY216', message = 'x';
    exception when sqlstate 'ZY216' then null; end;
  end loop;
  if v_seen < 150 then
    raise exception 'PROOF 216 FAIL: only % storm days were met', v_seen;
  end if;
  raise notice 'PASS: RS_STORM - % storm days: hands % to % %% (mean %), goods mean % %%; hull and 36 h as before', v_seen, round(v_lo * 100, 1), round(v_hi * 100, 1),
    round(v_dead / v_seen * 100, 2), round(v_lost / v_seen * 100, 2);

  -- ── RS_FROZEN ── (storms every day)
  begin
    v_voy := pg_temp.go216(v_fl, false, 6, 200, 900, 100000);
    update public.world_config set value = 'true'::jsonb where key = 'happenings_bite';
    perform voyage.settle(v_fl, voyage.day_ends_at(v_voy, 3) + interval '1 millisecond');
    if pg_temp.crew216(v_fl) <> 200 * (select count(*) from public.ships where fleet_id = v_fl) or exists (select 1 from public.voyage_events e where e.voyage_id = v_voy and e.payload ? 'crew_lost') then
      raise exception 'PROOF 216 FAIL: a voyage that left dark took hands when lit under way';
    end if;
    raise exception using errcode = 'ZY216', message = 'x';
  exception when sqlstate 'ZY216' then null; end;
  begin
    v_voy := pg_temp.go216(v_fl, true, 12, 200, 3, 100000);
    update public.world_config set value = 'false'::jsonb where key = 'happenings_bite';
    update public.world_config set value = '{"riot_crew": 1, "riot_cargo": 1, "home_crew": 9, "storm_crew": [1, 1], "storm_cargo": [1, 1], "slow_floor": 1}'::jsonb where key = 'happenings_terms';
    v_at := (select departed_at + make_interval(secs => (600 * 3600 / public.wc_num('time_compression'))::float8) from public.voyages where id = v_voy);   -- 600 sailed hours on
    begin
      perform voyage.settle(v_fl, v_at);
      select jsonb_agg(jsonb_build_object('d', e.day_index, 'k', e.kind, 'p', e.payload, 'at', e.resolved_at) order by e.day_index) into v_a from public.voyage_events e where e.voyage_id = v_voy;
      raise exception using errcode = 'ZY217', message = v_a::text;
    exception when sqlstate 'ZY217' then v_a := sqlerrm::jsonb; end;
    for d in 1 .. 50 loop
      exit when (select status from public.fleets where id = v_fl) <> 'SAILING';
      perform voyage.settle(v_fl, v_at - make_interval(secs => ((50 - d) * 12 * 3600 / public.wc_num('time_compression'))::float8));
    end loop;
    select jsonb_agg(jsonb_build_object('d', e.day_index, 'k', e.kind, 'p', e.payload, 'at', e.resolved_at) order by e.day_index) into v_b from public.voyage_events e where e.voyage_id = v_voy;
    if v_a is distinct from v_b or not v_a::text like '%crew_lost%' or not v_a::text like '%RIOT%' or pg_temp.crew216(v_fl) < 10 then
      raise exception 'PROOF 216 FAIL: late % / day by day %', left(v_a::text, 1500), left(v_b::text, 1500);
    end if;
    raise exception using errcode = 'ZY216', message = 'x';
  exception when sqlstate 'ZY216' then null; end;
  raise notice 'PASS: RS_FROZEN - left dark stays dark, left lit stays lit under the figures she left with; % days settled late and day by day are the same rows', jsonb_array_length(v_a);

  -- ── RS_SLOW ──
  begin
    update public.world_config set value = 'false'::jsonb where key = 'happenings_bite';
    update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fl;
    select (voyage.ship_speed_parts(s.id)->>'k')::numeric into v_x from public.ships s where s.fleet_id = v_fl order by s.id limit 1;
    for r in select s.id, c.crew_required as req from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_fl order by s.id limit 1 loop
      foreach v_n in array array[r.req - 1, ceil(r.req / 2.0)::int, 1] loop
        update public.ships set crew = v_n where id = r.id;
        update public.world_config set value = 'false'::jsonb where key = 'happenings_bite';
        v_y := (voyage.ship_speed_parts(r.id)->>'k')::numeric / v_x;
        if abs(v_y - 0.7) > 0.0001 then raise exception 'PROOF 216 FAIL: dark, short: %', v_y; end if;
        update public.world_config set value = 'true'::jsonb where key = 'happenings_bite';
        v_y := (voyage.ship_speed_parts(r.id)->>'k')::numeric / v_x;
        if abs(v_y - greatest(0.30, v_n::numeric / r.req)) > 0.0001 then raise exception 'PROOF 216 FAIL: lit, % of % hands: %', v_n, r.req, v_y; end if;
      end loop;
    end loop;
    -- hands lost at sea: half her minimum costs 24 hours a day at sea, and none on a day at her ETA
    v_voy := pg_temp.go216(v_fl, true, 4, 200, 900, 0);
    update public.ships s set crew = ceil(c.crew_required / 2.0) from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fl;
    select min(s.crew::numeric / c.crew_required) into v_y from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_fl;
    perform voyage.settle(v_fl, voyage.day_ends_at(v_voy, 1) + interval '1 millisecond');
    if abs((select delay_hours from public.voyages where id = v_voy) - 24 * (1 / v_y - 1)) > 0.02 then
      raise exception 'PROOF 216 FAIL: a short day costs % hours (share %)', (select delay_hours from public.voyages where id = v_voy), v_y;
    end if;
    perform voyage.settle(v_fl, (select eta from public.voyages where id = v_voy) + interval '30 days');
    if (select status from public.voyages where id = v_voy) <> 'ARRIVED' or (select delay_hours from public.voyages where id = v_voy) > 4 * 24 * (1 / v_y - 1) + 0.1 then
      raise exception 'PROOF 216 FAIL: a short voyage does not end: % h', (select delay_hours from public.voyages where id = v_voy);
    end if;
    raise exception using errcode = 'ZY216', message = 'x';
  exception when sqlstate 'ZY216' then null; end;
  raise notice 'PASS: RS_SLOW - lit, speed is crew / minimum, 30 %% at the least (dark 70 %%); at sea a day short of hands costs its hours and the voyage ends';

  -- ── RS_MERCHANT ──
  begin
    update public.world_config set value = 'true'::jsonb where key = 'happenings_bite';
    select nf.fleet_id into v_fl from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id and f.status = 'DOCKED' order by nf.roster_ord limit 1;
    select s.id into v_voy from public.ships s where s.fleet_id = v_fl order by s.id limit 1;
    update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.id = v_voy;
    v_x := (voyage.ship_speed_parts(v_voy)->>'k')::numeric;
    update public.ships set crew = 1 where id = v_voy;
    v_y := (voyage.ship_speed_parts(v_voy)->>'k')::numeric / v_x;
    v_voy := voyage.depart(v_fl, jsonb_build_array(jsonb_build_object('a', '[38.5,-9.6]'::jsonb, 'b', '[38.5,-10.6]'::jsonb, 'nm', 100, 'hazard_mult', 0,
                           'sea_id', (select p.sea_id from public.ports p where p.id = v_lis))), v_lis, v_lis, now());
    if (select path->0 ? 'hap' from public.voyages where id = v_voy) or abs(v_y - 0.7) > 0.0001 then
      raise exception 'PROOF 216 FAIL: a merchant left with the terms, or her short hull sails at %', v_y;
    end if;
    raise exception using errcode = 'ZY216', message = 'x';
  exception when sqlstate 'ZY216' then null; end;
  raise notice 'PASS: RS_MERCHANT - no terms on a merchant''s path; her short hull at 70 %%, as before';

  -- ── RS_ONLY ──
  if exists (select 1 from public.voyage_event_kinds k where k.code ~ 'SICK|SCURVY|FIRE|LEAK|RAT$|RATS')
     or (select count(*) from public.voyage_event_kinds k where k.code in ('RIOT', 'RIOT_HOME') and not k.is_rolled and not k.in_sea_mix) <> 2 then
    raise exception 'PROOF 216 FAIL: the kinds';
  end if;
  raise notice 'PASS: RS_ONLY - RIOT and RIOT_HOME, never drawn; no sickness, fire, leak or rats';
  select id into v_fl from public.fleets where player_id = v_me;
  begin
    v_voy := pg_temp.go216(v_fl, true, 30, 1000, 900, 0);
    v_t := clock_timestamp();
    for d in 1 .. 50 loop perform voyage.happening_takes(v_voy, d, v_fl, 'STORM', 0.03, 0.015); end loop;
    raise notice 'TIMING: a storm or riot day adds % ms', round((extract(epoch from clock_timestamp() - v_t) * 20)::numeric, 2);
    raise exception using errcode = 'ZY216', message = 'x';
  exception when sqlstate 'ZY216' then null; end;
end
$p$;

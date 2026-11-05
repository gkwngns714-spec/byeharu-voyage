-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 23 — INSURANCE PAYS ITS WAY  (migration 0314)
--
--   0314's own self-assert reads the catalog only: a migration never runs a real game step (docs/OPS_HEALTH.md section 4). This proof runs the REAL cmd.do_sail and voyage.settle on one
--   laden, insured probe voyage per scene, each scene rolled back. The pre-image is the live body with its one test put back, so the bug is reproduced here and not taken on trust.
--
-- @pass INS_BUG_OLD   the pre-image: dry on a day stacked at her own ETA, the voyage is ABORTED, the hold gone and 1,800 owed
-- @pass INS_ARRIVES   the new body, the same scene: ARRIVED, DOCKED at her destination, hold 2,000, no hull lost, nothing owed
-- @pass INS_STEPPED   settled boundary by boundary she lands exactly as a late settle lands her
-- @pass INS_STORM     the same after a storm's 36 hours, the smallest delay on record
-- @pass INS_AT_SEA    dry on a day that ends before the ETA, with or without a calm first: still a forced home, 1,800 owed, the hull hurt
-- @pass INS_FINAL     no delay, dry on her true final day: still an arrival (0279's own case)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_res  jsonb := '{}'::jsonb;
  v_all  jsonb;
  v_x    jsonb;
  v_name text;
  v_def  text := replace(pg_get_functiondef('voyage.settle(uuid,timestamp with time zone)'::regprocedure), E'\r', '');
  s      record;
begin
  if (select count(*) from regexp_matches(v_def, 'if v_end <= 0 and [^\n]*', 'g')) <> 1 then
    raise exception 'PROOF 23 FAIL: the dry test of voyage.settle is not where it was expected';
  end if;
  execute replace(regexp_replace(v_def, 'if v_end <= 0 and [^\n]*', 'if v_end <= 0 and d < v_cap'),
                  'CREATE OR REPLACE FUNCTION voyage.settle(', 'CREATE OR REPLACE FUNCTION pg_temp.settle_b0314(');

  -- One laden, insured voyage, Lisbon to Funchal, a cargo of exactly 2,000, hazards off on HER OWN path. p: the settle to run ('new' or 'old'), `calm` hours of delay written on day 1, `days` of
  -- stores left when that day is done, `slow` to sail three times as long, `step` to settle every boundary in turn rather than once at the end. Answers what became of her.
  execute $f$
create function pg_temp.scene_0314(p_uid uuid, p jsonb)
returns jsonb
language plpgsql
as $b$
declare
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_fnc  uuid := (select id from public.ports where code = 'FNC');
  v_p    uuid;
  v_f    uuid;
  v_voy  uuid;
  v_a    text;
  v_b    text;
  v_la   numeric;
  v_lb   numeric;
  v_sim  numeric;
  v_dry  int;
  v_days numeric;
  v_calm numeric := (p ->> 'calm')::numeric;
  v_d    int;
  v_hull numeric;
  v_at   timestamptz;
  v_eta  timestamptz;
begin
  v_p := public.new_house(p_uid, 'Casa Enxuta ' || right(p_uid::text, 4), 'PRT', 'LIS', 'Enxuta ' || right(p_uid::text, 4), 'barca', 'Enxuta ' || right(p_uid::text, 4), null, false);
  select id into v_f from public.fleets where player_id = v_p;
  perform public.credit(v_p, 'PROBE_0314', 1000000);
  select code into v_a from public.goods where bulk = 1 order by code limit 1;
  select code into v_b from public.goods where bulk = 1 and code > v_a order by code limit 1;
  v_la := public.fleet_load(v_f, v_a, 40, 25);
  v_lb := public.fleet_load(v_f, v_b, 10, 100);
  if v_la <> 40 or v_lb <> 10 or public.fleet_stock_at_cost(v_f) <> 2000 then
    raise exception 'PROOF 23 FAIL: the probe''s cargo did not load (% of 40, % of 10, worth %)', v_la, v_lb, public.fleet_stock_at_cost(v_f);
  end if;
  v_voy := (cmd.do_sail(v_f, jsonb_build_object('dest', v_fnc, 'insured', true,
             'path', (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                        from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc)))->>'voyage_id')::uuid;
  if not exists (select 1 from public.insured_voyages i where i.voyage_id = v_voy and i.value = 2000) then
    raise exception 'PROOF 23 FAIL: the probe''s voyage is not insured for 2,000';
  end if;
  update public.voyages vo set path = (select jsonb_agg(e || jsonb_build_object('hazard_mult', 0) order by o) from jsonb_array_elements(vo.path) with ordinality t(e, o))
   where vo.id = v_voy;
  if (p ->> 'slow')::boolean then
    -- a passage three times as long, on her own row: past a calm she still has days at sea ahead of her.
    update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 3) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
     where vo.id = v_voy;
    perform voyage.recompute_eta(v_voy);
  end if;
  v_sim := voyage.sim_hours(v_voy);
  v_dry := ceil(v_sim / 24);   -- the first day that ends on or past her sailing time: with any delay written, it is clamped at the ETA
  if v_calm > 0 then
    -- day 1 was a calm: the same row and the same recompute as voyage.settle's own arm.
    insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
    values (v_voy, 1, 'CALM', jsonb_build_object('delay_hours', v_calm), now());
    update public.voyages set last_settled_day = 1 where id = v_voy;
    perform voyage.recompute_eta(v_voy);
    if v_dry < 2 then v_dry := 2; end if;
  end if;
  v_d := (select last_settled_day from public.voyages where id = v_voy);
  -- her stores: what `days` days drink, or by default just enough to run out on v_dry, the first stacked day.
  v_days := case when p ? 'days' then (p ->> 'days')::numeric else v_dry - v_d end;
  update public.ships
     set water_t = crew * public.wc_num('water_per_crew_day') * v_days, food_t = crew * public.wc_num('food_per_crew_day') * v_days
   where fleet_id = v_f;
  select coalesce(sum(durability), 0) into v_hull from public.ships where fleet_id = v_f;
  v_eta := (select eta from public.voyages where id = v_voy);
  if p ->> 'run' = 'old' then
    perform pg_temp.settle_b0314(v_f, v_eta + interval '1 second');
  elsif (p ->> 'step')::boolean then
    for v_at in select voyage.day_ends_at(v_voy, g.d) from generate_series(1, voyage.total_days(v_voy)) g(d) order by 1 loop
      perform voyage.settle(v_f, v_at);
    end loop;
    perform voyage.settle(v_f, v_eta + interval '1 second');
  else
    perform voyage.settle(v_f, v_eta + interval '1 second');
  end if;
  return jsonb_build_object(
    'sim', v_sim, 'dry_day', v_dry, 'cap', voyage.total_days(v_voy), 'stores_days', v_days,
    'bound', voyage.day_ends_at(v_voy, v_dry) >= v_eta,
    'voyage', (select status from public.voyages where id = v_voy),
    'fleet', (select status from public.fleets where id = v_f),
    'at_dest', (select port_id from public.fleets where id = v_f) = v_fnc,
    'hold', public.fleet_stock_at_cost(v_f),
    'stores', (select coalesce(sum(water_t + food_t), 0) from public.ships where fleet_id = v_f),
    'hull_lost', v_hull - (select coalesce(sum(durability), 0) from public.ships where fleet_id = v_f),
    'forced_events', (select count(*) from public.events e where e.player_id = v_p and e.kind = 'FORCED_HOME'),
    'forced_days', (select count(*) from public.voyage_events ve where ve.voyage_id = v_voy and ve.kind = 'FORCED_HOME'),
    'claims', (select i.claims from public.insured_voyages i where i.voyage_id = v_voy),
    'owed', (select i.paid + i.short from public.insured_voyages i where i.voyage_id = v_voy));
end
$b$
$f$;

  for s in select * from (values
      ('bug_old',  '00000000-0314-4000-8000-000000000001'::uuid, '{"run":"old","calm":72,"step":false}'::jsonb),   -- the bug itself, on the pre-image body
      ('fixed',    '00000000-0314-4000-8000-000000000002'::uuid, '{"run":"new","calm":72,"step":false}'::jsonb),   -- the same scene, the new body
      ('stepped',  '00000000-0314-4000-8000-000000000003'::uuid, '{"run":"new","calm":72,"step":true}'::jsonb),    -- settled day by day: a late settle lands the same
      ('storm',    '00000000-0314-4000-8000-000000000004'::uuid, '{"run":"new","calm":36,"step":false}'::jsonb),   -- a storm's 36 hours, the smallest delay on record
      ('at_sea',   '00000000-0314-4000-8000-000000000005'::uuid, '{"run":"new","calm":0,"days":0,"step":false}'::jsonb),      -- dry on day 1, hours short of port: a real forced home
      ('at_sea_c', '00000000-0314-4000-8000-000000000006'::uuid, '{"run":"new","calm":72,"days":0,"slow":true,"step":false}'::jsonb),     -- a long passage, no stores after a calm: dry with days of sailing left, delay or no delay
      ('final',    '00000000-0314-4000-8000-000000000007'::uuid, '{"run":"new","calm":0,"step":false}'::jsonb)     -- no delay: dry on her true final day, as 0279 proved
    ) v(name, uid, p) loop
    begin
      raise exception using errcode = 'ZX314', message = pg_temp.scene_0314(s.uid, s.p)::text;
    exception when sqlstate 'ZX314' then v_res := v_res || jsonb_build_object(s.name, sqlerrm::jsonb); end;
  end loop;
  v_all := v_res;
  drop function pg_temp.scene_0314(uuid, jsonb);
  drop function pg_temp.settle_b0314(uuid, timestamp with time zone);

  -- THE SCENE IS THE BUG: on the old body a ship dry on a stacked day, at her own ETA, lost her hold and claimed all of it.
  v_x := v_all -> 'bug_old';
  if (v_x ->> 'bound')::boolean is not true or (v_x ->> 'dry_day')::int >= (v_x ->> 'cap')::int then
    raise exception 'PROOF 23 FAIL: the probe''s dry day is not a stacked day on the ETA: %', v_x;
  end if;
  if v_x ->> 'voyage' <> 'ABORTED' or (v_x ->> 'hold')::numeric <> 0 or (v_x ->> 'claims')::int <> 1 or (v_x ->> 'owed')::bigint <> 1800 or (v_x ->> 'forced_events')::int <> 1 then
    raise exception 'PROOF 23 FAIL: the pre-image did not reproduce the bug: %', v_x;
  end if;

  -- FIXED: the same ship has arrived, with everything she carried, and the city pays nothing. Whether she settles at once, day by day, or after a storm's 36 hours.
  foreach v_name in array array['fixed', 'stepped', 'storm'] loop
    v_x := v_all -> v_name;
    if (v_x ->> 'bound')::boolean is not true or (v_x ->> 'dry_day')::int >= (v_x ->> 'cap')::int then
      raise exception 'PROOF 23 FAIL: scene % is not a stacked dry day: %', v_name, v_x;
    end if;
    if (v_x ->> 'stores')::numeric <> 0 then
      raise exception 'PROOF 23 FAIL: scene % did not run dry: %', v_name, v_x;
    end if;
    if v_x ->> 'voyage' <> 'ARRIVED' or v_x ->> 'fleet' <> 'DOCKED' or (v_x ->> 'at_dest')::boolean is not true then
      raise exception 'PROOF 23 FAIL: a ship dry on the ETA did not arrive (%): %', v_name, v_x;
    end if;
    if (v_x ->> 'hold')::numeric <> 2000 or (v_x ->> 'hull_lost')::numeric <> 0 then
      raise exception 'PROOF 23 FAIL: a ship that arrived lost her hold or her hull (%): %', v_name, v_x;
    end if;
    if (v_x ->> 'claims')::int <> 0 or (v_x ->> 'owed')::bigint <> 0 or (v_x ->> 'forced_events')::int <> 0 or (v_x ->> 'forced_days')::int <> 0 then
      raise exception 'PROOF 23 FAIL: the insurance paid for a hold she still has (%): %', v_name, v_x;
    end if;
  end loop;
  if (v_all -> 'stepped') - 'sim' is distinct from (v_all -> 'fixed') - 'sim' then   -- sim: her speed is rolled per voyage; the outcome is what must match
    raise exception 'PROOF 23 FAIL: a late settle lands differently from a day-by-day settle: % against %', v_all -> 'stepped', v_all -> 'fixed';
  end if;

  -- STILL A FORCED HOME: a ship dry on a day that ends before she arrives is exactly what 0279 and the owner's row 223 said. The hold, the claim, the hull.
  foreach v_name in array array['at_sea', 'at_sea_c'] loop
    v_x := v_all -> v_name;
    if v_x ->> 'voyage' <> 'ABORTED' or (v_x ->> 'forced_events')::int <> 1 or (v_x ->> 'forced_days')::int <> 1 or (v_x ->> 'hold')::numeric <> 0
       or (v_x ->> 'claims')::int <> 1 or (v_x ->> 'owed')::bigint <> 1800 or (v_x ->> 'hull_lost')::numeric <= 0 then
      raise exception 'PROOF 23 FAIL: a real dry day at sea is no longer a forced home (%): %', v_name, v_x;
    end if;
  end loop;

  -- 0279'S OWN CASE, unmoved: no delay, dry on the true final day.
  v_x := v_all -> 'final';
  if v_x ->> 'voyage' <> 'ARRIVED' or (v_x ->> 'hold')::numeric <> 2000 or (v_x ->> 'forced_events')::int <> 0 or (v_x ->> 'stores')::numeric <> 0
     or (v_x ->> 'dry_day')::int <> (v_x ->> 'cap')::int then
    raise exception 'PROOF 23 FAIL: a dry final day is no longer an arrival: %', v_x;
  end if;

  raise notice 'PASS: INS_BUG_OLD — dry on stacked day % of %, % owed on a hold she still had', v_all -> 'bug_old' ->> 'dry_day', v_all -> 'bug_old' ->> 'cap', v_all -> 'bug_old' ->> 'owed';
  raise notice 'PASS: INS_ARRIVES — %, hold %, owed %', v_all -> 'fixed' ->> 'voyage', v_all -> 'fixed' ->> 'hold', v_all -> 'fixed' ->> 'owed';
  raise notice 'PASS: INS_STEPPED — %, hold %', v_all -> 'stepped' ->> 'voyage', v_all -> 'stepped' ->> 'hold';
  raise notice 'PASS: INS_STORM — %, hold %, owed %', v_all -> 'storm' ->> 'voyage', v_all -> 'storm' ->> 'hold', v_all -> 'storm' ->> 'owed';
  raise notice 'PASS: INS_AT_SEA — % and %, % and % owed', v_all -> 'at_sea' ->> 'voyage', v_all -> 'at_sea_c' ->> 'voyage', v_all -> 'at_sea' ->> 'owed', v_all -> 'at_sea_c' ->> 'owed';
  raise notice 'PASS: INS_FINAL — %, hold %', v_x ->> 'voyage', v_x ->> 'hold';
end
$$;

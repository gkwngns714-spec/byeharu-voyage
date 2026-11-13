-- ═══════════════════════════════════════════════════════════
-- PROOF 31 — A BATTLE TAKES TEN MINUTES  (migration 0323)
--
--   0323's own self-assert reads the catalog only: a migration never runs a real game step (docs/OPS_HEALTH.md section 4). This proof runs them, on probes, rolled back by the runner.
--   Probes sail Lisbon to Funchal, slowed to about ten voyage days, with hazards off on their own path, except the twin, who meets the sea. Instants are handed to every call, so nothing waits ten minutes.
--
-- @pass BATTLE_DARK_PARITY   every voyage in the world, old bodies against new, position, delays, both views, the roster: no hold, no difference
-- @pass BATTLE_REFUSALS      dark refuses; a bad kind, herself, a human target, a docked target and a busy fleet each refuse with their own code
-- @pass BATTLE_STANDS_STILL  both ships hold the very point they were at for the whole battle, on the numbers, and settle finds no day inside it
-- @pass BATTLE_PAST_KEPT     what she did before the battle reads as it did
-- @pass BATTLE_ARRIVAL_MOVES arrival and every day from the held one on move by exactly the battle; the days before do not
-- @pass BATTLE_SAILS_ON      from the hold's end she is where an unheld ship was the same seconds after it began, and she never goes back
-- @pass BATTLE_NO_TURN       a held fleet cannot divert, and the refusal changes nothing
-- @pass BATTLE_SERVED        the views and the roster serve the hold, and only while it counts
-- @pass BATTLE_RESOLVED_ONCE not before its time; one fight, seed (battle id, 1); hulls written once; a retry does nothing; one report, to the human alone
-- @pass BATTLE_IN_PORT       a fleet in port or at anchor goes IN_BATTLE, her orders wait, and she comes back as she was; a fleet at sea cannot be IN_BATTLE
-- @pass BATTLE_OFFLINE       a held voyage settled day by day and once at the end are the same voyage, and her report names the true day
-- @pass BATTLE_WORDS         a report reads from the attacker's deck, round for round
-- ═══════════════════════════════════════════════════════════

-- A fleet of a new house, at sea or not. Lisbon to Funchal, hazards off, six times as slow as her hull: about ten voyage days.
create function pg_temp.fleet_0323(p_uid uuid, p_npc boolean, p_sail boolean, p_quiet boolean default true)
returns uuid
language plpgsql
as $b$
declare
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_fnc  uuid := (select id from public.ports where code = 'FNC');
  v_tag  text := right(p_uid::text, 4);
  v_p    uuid := public.new_house(p_uid, 'Casa Batalha ' || v_tag, 'PRT', 'LIS', 'Batalha ' || v_tag,
                                     (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1), 'Batalha ' || v_tag, null, false);   -- guns on both sides, of one class: the lookouts tie and nobody slips away
  v_f    uuid;
  v_voy  uuid;
begin
  select id into v_f from public.fleets where player_id = v_p;
  update public.ships set water_t = crew * public.wc_num('water_per_crew_day') * 40, food_t = crew * public.wc_num('food_per_crew_day') * 40 where fleet_id = v_f;
  if p_npc then
    update public.players set is_npc = true, auth_uid = null where id = v_p;
  end if;
  if p_sail then
    v_voy := (cmd.do_sail(v_f, jsonb_build_object('dest', v_fnc,
               'path', (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                          from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc)))->>'voyage_id')::uuid;
    if v_voy is null then
      raise exception 'PROOF 31 FAIL: the probe % did not sail', v_tag;
    end if;
    update public.voyages vo set
      path = case when p_quiet then (select jsonb_agg(e || jsonb_build_object('hazard_mult', 0) order by o) from jsonb_array_elements(vo.path) with ordinality t(e, o)) else vo.path end,
      speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 6) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
     where vo.id = v_voy;
    perform voyage.recompute_eta(v_voy);
  end if;
  return v_f;
end
$b$;

create function pg_temp.voy_0323(p_fleet uuid)
returns uuid language sql stable as $b$ select v.id from public.voyages v where v.fleet_id = p_fleet and v.status = 'SAILING' $b$;

-- ── THE DARK PARITY: nothing held, old bodies against new, before anything below opens a battle ──
do $p$
declare
  c_back constant jsonb := jsonb_build_array(
    jsonb_build_array('voyage.delay_before_day(uuid,integer)', $h$  ) + (
  -- 0323: a hold's row stands above the days and counts from the day she was held on (voyage.hold)
  select coalesce(sum((ve.payload->>'delay_hours')::numeric), 0)
    from public.voyage_events ve
   where ve.voyage_id = p_voyage and ve.day_index >= voyage.hold_floor() and (ve.payload->>'from_day')::int <= p_day
  );$h$, E'  );'),
    jsonb_build_array('voyage.progress_nm(uuid,timestamp with time zone)', $h$           - voyage.delay_before_day(p_voyage, v_day) + voyage.hold_unserved(p_voyage, v_day, p_at);$h$,
                      $h$           - voyage.delay_before_day(p_voyage, voyage.days_complete(p_voyage, p_at) + 1);$h$),
    jsonb_build_array('voyage.report_line(integer,text,jsonb)', $h$coalesce((p_payload->>'from_day')::int, p_day))$h$, 'p_day)'),
    jsonb_build_array('world.voyage_view(uuid,boolean)', $h$
                 || voyage.holds_served(v.id)   -- 0323: when she is held, served only then$h$, ''),
    jsonb_build_array('world.voyage_view(uuid,boolean)', $h$
         || case when v_full ? 'holds' then jsonb_build_object('holds', v_full->'holds') else '{}'::jsonb end;   -- 0323$h$, ';'),
    jsonb_build_array('world.sea_roster(timestamp with time zone)', $h$
                        || voyage.holds_served(v.id)   -- 0323: the frozen facts of a hold, so she is placed standing still$h$, ''),
    jsonb_build_array('world.sea_roster(timestamp with time zone)', $h$
      -- 0323: a hold moved her eta: she is served again while she is held, or the kept row would place her on the old one
      or f.busy_until >= p_since;$h$, ';'));
  v_a     uuid := pg_temp.fleet_0323('00000000-0323-4000-8000-000000000a01', false, true);
  v_b     uuid := pg_temp.fleet_0323('00000000-0323-4000-8000-000000000a02', false, true);
  v_new   jsonb;
  v_old   jsonb;
  v_keep  jsonb := '{}'::jsonb;
  v_def   text;
  s       record;
  h       jsonb;
  v_read  text := $r$
    select jsonb_build_object(
      'voyages', (select jsonb_agg(jsonb_build_object('id', v.id,
                    'at', voyage.progress_nm(v.id, least(v.eta, now() + interval '100 seconds')), 'mid', voyage.progress_nm(v.id, v.departed_at + (v.eta - v.departed_at) / 2),
                    'pos', (select to_jsonb(p) from voyage.position(v.id) p),
                    'delays', (select jsonb_agg(voyage.delay_before_day(v.id, d)) from generate_series(1, voyage.total_days(v.id) + 1) d),
                    'full', world.voyage_view(v.id, true), 'seg', world.voyage_view(v.id, false)) order by v.id)
                    from public.voyages v where v.status = 'SAILING'),
      'lines', (select jsonb_agg(voyage.report_line(ve.day_index, ve.kind, ve.payload) order by ve.voyage_id, ve.day_index)
                  from public.voyage_events ve where ve.voyage_id in (select v.id from public.voyages v where v.status = 'SAILING')),
      'roster', world.sea_roster(null) - 'at', 'since', world.sea_roster(now() - interval '5 minutes') - 'at')
  $r$;
begin
  -- a voyage that has lost a storm's time, so the delays are not all 0
  insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
  values (pg_temp.voy_0323(v_b), 1, 'CALM', jsonb_build_object('delay_hours', 36), now());
  update public.voyages set last_settled_day = 1 where id = pg_temp.voy_0323(v_b);
  perform voyage.recompute_eta(pg_temp.voy_0323(v_b));

  execute v_read into v_new;
  for s in select distinct e ->> 0 as fn from jsonb_array_elements(c_back) e loop
    v_def := replace(pg_get_functiondef(s.fn::regprocedure), E'\r', '');
    v_keep := v_keep || jsonb_build_object(s.fn, v_def);
    for h in select e from jsonb_array_elements(c_back) e where e ->> 0 = s.fn loop
      if position(h ->> 1 in v_def) = 0 then
        raise exception 'PROOF 31 FAIL: a term of % is not in the body: %', s.fn, left(h ->> 1, 60);
      end if;
      v_def := replace(v_def, h ->> 1, h ->> 2);
    end loop;
    execute v_def;
  end loop;
  execute v_read into v_old;
  for s in select e.key, e.value from jsonb_each_text(v_keep) e loop
    execute s.value;
  end loop;
  if v_new is distinct from v_old then
    raise exception 'PROOF 31 FAIL: a voyage nobody holds reads differently: % against %', left(v_new::text, 400), left(v_old::text, 400);
  end if;
  raise notice 'PASS: BATTLE_DARK_PARITY — % voyage(s) at sea and the roster, word for word', jsonb_array_length(v_new -> 'voyages');
end
$p$;

-- ── THE REFUSALS ──
do $p$
declare
  v_h    uuid := pg_temp.fleet_0323('00000000-0323-4000-8000-000000000b01', false, true);
  v_h2   uuid := pg_temp.fleet_0323('00000000-0323-4000-8000-000000000b02', false, true);
  v_n    uuid := pg_temp.fleet_0323('00000000-0323-4000-8000-000000000b03', true, true);
  v_quay uuid := pg_temp.fleet_0323('00000000-0323-4000-8000-000000000b04', true, false);
  v_n2   uuid := pg_temp.fleet_0323('00000000-0323-4000-8000-000000000b05', true, true);
  v_t    timestamptz := now() + interval '10 seconds';
  v_err  text;
  v_case record;
  v_b    uuid;
begin
  -- 0375 lights attack_enabled in the chain. This proof begins from the switch OFF, as every other proof of the family sets it: the dark seam is what the rollback restores.
  update public.world_config set value = 'false'::jsonb where key = 'attack_enabled';
  if public.attack_on() then
    raise exception 'PROOF 31 FAIL: attack_enabled could not be put off in this world';
  end if;
  begin
    perform public.battle_open('PROBE', v_h, v_n, v_t);
    v_err := null;
  exception when others then v_err := sqlerrm;
  end;
  if v_err is null or v_err !~ '^E_NOT_YET' then
    raise exception 'PROOF 31 FAIL: dark, battle_open answered %', coalesce(v_err, 'with a battle');
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  for v_case in select * from (values
      ('RAID'::text, v_h, v_n, 'E_BAD_KIND'),
      ('PROBE', v_h, v_h, 'E_BAD_TARGET'),
      ('PROBE', v_h, v_h2, 'E_HUMAN_TARGET'),
      ('PROBE', v_h, v_quay, 'E_TARGET_DOCKED')) c(k, a, d, code) loop
    begin
      perform public.battle_open(v_case.k, v_case.a, v_case.d, v_t);
      v_err := null;
    exception when others then v_err := sqlerrm;
    end;
    if v_err is null or v_err !~ ('^' || v_case.code) then
      raise exception 'PROOF 31 FAIL: wanted %, battle_open answered %', v_case.code, coalesce(v_err, 'with a battle');
    end if;
  end loop;
  v_b := public.battle_open('PROBE', v_h, v_n, v_t);
  begin
    perform public.battle_open('PROBE', v_h, v_n2, v_t + interval '1 second');
    v_err := null;
  exception when others then v_err := sqlerrm;
  end;
  if v_err is null or v_err !~ '^E_FLEET_BUSY' then
    raise exception 'PROOF 31 FAIL: a fleet in a battle opened another: %', coalesce(v_err, 'it did');
  end if;
  if not public.battle_resolve(v_b, v_t + interval '1 hour') then
    raise exception 'PROOF 31 FAIL: the first battle did not resolve';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'attack_enabled';
  raise notice 'PASS: BATTLE_REFUSALS — dark, a bad kind, herself, a human, a docked target, a busy fleet, each with its code';
end
$p$;

-- ── THE HOLD, AT SEA: a human attacker and a merchant defender, both sailing ──
do $p$
declare
  c_uid  constant uuid := '00000000-0323-4000-8000-000000000c01';
  a      uuid := pg_temp.fleet_0323(c_uid, false, true);
  d      uuid := pg_temp.fleet_0323('00000000-0323-4000-8000-000000000c02', true, true);
  va     uuid := pg_temp.voy_0323(a);
  vd     uuid := pg_temp.voy_0323(d);
  v_dep  timestamptz;
  t0     timestamptz;
  v_k    numeric := public.wc_num('time_compression');
  v_len  constant int := 600;
  v_hrs  numeric;
  c_off  constant int[] := array[1, 30, 61, 90, 200, 400];
  v_nm   numeric[] := '{}';
  v_past jsonb;
  v_at   jsonb;
  v_atd  jsonb;
  v_days timestamptz[] := '{}';
  v_eta0 timestamptz;
  v_etad0 timestamptz;
  v_del0 numeric;
  v_b    uuid;
  v_row  record;
  v_x    jsonb;
  v_prev numeric := -1;
  v_now  numeric;
  v_grid timestamptz;
  v_eta1 timestamptz;
  v_day  int;
  v_exp  jsonb;
  v_hull jsonb;
  v_ok   boolean;
  i      int;
  v_n    int;
begin
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  update public.world_config set value = to_jsonb(v_len) where key = 'battle_seconds';
  v_hrs := v_len * v_k / 3600;
  select v.departed_at, v.eta, v.delay_hours into v_dep, v_eta0, v_del0 from public.voyages v where v.id = va;
  select v.eta into v_etad0 from public.voyages v where v.id = vd;
  if v_eta0 < v_dep + make_interval(secs => 500) then
    raise exception 'PROOF 31 FAIL: the probe''s passage is too short to test (% s)', extract(epoch from v_eta0 - v_dep);
  end if;
  t0 := v_dep + make_interval(secs => greatest(200, 86400 * 2.3 / v_k));

  -- what she would do if nobody touched her
  for i in 1 .. array_length(c_off, 1) loop
    v_nm := v_nm || voyage.progress_nm(va, t0 + make_interval(secs => c_off[i]));
  end loop;
  v_past := (select jsonb_agg(to_jsonb(p)) from generate_series(30, 180, 30) s cross join lateral voyage.position(va, t0 - make_interval(secs => s)) p);
  v_at   := (select to_jsonb(p) from voyage.position(va, t0) p);
  v_atd  := (select to_jsonb(p) from voyage.position(vd, t0) p);
  for i in 1 .. voyage.total_days(va) loop
    v_days := v_days || voyage.day_ends_at(va, i);
  end loop;

  v_b := public.battle_open('PROBE', a, d, t0);

  select ve.payload, ve.day_index into v_row from public.voyage_events ve where ve.voyage_id = va and ve.kind = 'BATTLE';
  v_day := (v_row.payload ->> 'from_day')::int;
  if v_row.day_index <> voyage.hold_floor() + 1 or v_day <> (select v.last_settled_day + 1 from public.voyages v where v.id = va) or v_day < 2
     or (v_row.payload ->> 'delay_hours')::numeric <> v_hrs
     or (v_row.payload ->> 'held_from')::timestamptz <> t0 or (v_row.payload ->> 'held_until')::timestamptz <> t0 + make_interval(secs => v_len) then
    raise exception 'PROOF 31 FAIL: the hold''s row is not what it should be: % at %', v_row.payload, v_row.day_index;
  end if;
  if (select f.status from public.fleets f where f.id = a) <> 'SAILING' or (select f.status from public.fleets f where f.id = d) <> 'SAILING'
     or (select f.busy_until from public.fleets f where f.id = a) <> t0 + make_interval(secs => v_len) then
    raise exception 'PROOF 31 FAIL: a fleet at sea must stay SAILING, with busy_until her clock';
  end if;
  perform voyage.assert_sailing_invariant();
  if not exists (select 1 from public.battles b where b.id = v_b and b.status = 'FIGHTING' and b.resolves_at = t0 + make_interval(secs => v_len)
                    and (b.site ->> 'lat')::numeric = (v_atd ->> 'lat')::numeric and (b.site ->> 'lon')::numeric = (v_atd ->> 'lon')::numeric)
     or (select count(*) from public.battle_sides bs where bs.battle_id = v_b) <> 2 then
    raise exception 'PROOF 31 FAIL: the battle''s row is not what it should be';
  end if;

  -- ── STANDS STILL ──
  foreach i in array array[0, 1, 59, 300, 599, 600] loop
    if (select to_jsonb(p) from voyage.position(va, t0 + make_interval(secs => i)) p) <> v_at
       or (select to_jsonb(p) from voyage.position(vd, t0 + make_interval(secs => i)) p) <> v_atd then
      raise exception 'PROOF 31 FAIL: % s into the battle she has moved: % against %', i, (select to_jsonb(p) from voyage.position(va, t0 + make_interval(secs => i)) p), v_at;
    end if;
  end loop;
  v_n := voyage.settle(a, t0 + make_interval(secs => 300));
  if v_n <> 0 or (select count(*) from public.voyage_events ve where ve.voyage_id = va and ve.day_index = v_day) <> 0 then
    raise exception 'PROOF 31 FAIL: a day fell inside the hold (% settled)', v_n;
  end if;
  raise notice 'PASS: BATTLE_STANDS_STILL — both ships at the same point, to the digit, 0 to 600 s; settle finds no day in it';

  if (select jsonb_agg(to_jsonb(p)) from generate_series(30, 180, 30) s cross join lateral voyage.position(va, t0 - make_interval(secs => s)) p) <> v_past then
    raise exception 'PROOF 31 FAIL: the battle moved what she did before it';
  end if;
  raise notice 'PASS: BATTLE_PAST_KEPT — six points before the battle read as they did';

  -- ── ARRIVAL ──
  select v.eta into v_eta1 from public.voyages v where v.id = va;
  if abs(extract(epoch from v_eta1 - v_eta0) - v_len) > 0.001 or abs(extract(epoch from (select v.eta from public.voyages v where v.id = vd) - v_etad0) - v_len) > 0.001 then
    raise exception 'PROOF 31 FAIL: arrival moved by % s, not %', extract(epoch from v_eta1 - v_eta0), v_len;
  end if;
  if (select v.delay_hours from public.voyages v where v.id = va) <> v_del0 + v_hrs then
    raise exception 'PROOF 31 FAIL: the voyage''s delay is not its hold';
  end if;
  for i in 1 .. array_length(v_days, 1) loop
    if abs(extract(epoch from voyage.day_ends_at(va, i) - v_days[i]) - case when i >= v_day then v_len else 0 end) > 0.001 then
      raise exception 'PROOF 31 FAIL: day % ends % s from where it did (held on day %)', i, extract(epoch from voyage.day_ends_at(va, i) - v_days[i]), v_day;
    end if;
  end loop;
  if voyage.delay_before_day(va, v_day - 1) <> v_del0 or voyage.delay_before_day(va, v_day) <> v_del0 + v_hrs then
    raise exception 'PROOF 31 FAIL: the hold is not counted from the day she was on';
  end if;
  raise notice 'PASS: BATTLE_ARRIVAL_MOVES — arrival + % s, % sim-hours, day % on, the days before unmoved', v_len, v_hrs, v_day;

  -- ── SAILS ON ──
  for i in 1 .. array_length(c_off, 1) loop
    if voyage.progress_nm(va, t0 + make_interval(secs => v_len + c_off[i])) <> v_nm[i] then
      raise exception 'PROOF 31 FAIL: % s after the hold she is at % nm; an unheld ship % s on was at %', c_off[i], voyage.progress_nm(va, t0 + make_interval(secs => v_len + c_off[i])), c_off[i], v_nm[i];
    end if;
  end loop;
  v_grid := v_dep;
  while v_grid <= v_eta1 + interval '5 seconds' loop
    v_now := voyage.progress_nm(va, v_grid);
    if v_now < v_prev then
      raise exception 'PROOF 31 FAIL: she went back at %: % after %', v_grid, v_now, v_prev;
    end if;
    v_prev := v_now;
    v_grid := v_grid + interval '7 seconds';
  end loop;
  if voyage.progress_nm(va, v_eta1) <> (select v.total_nm from public.voyages v where v.id = va) or voyage.progress_nm(va, v_eta1 - interval '2 seconds') >= voyage.progress_nm(va, v_eta1) then
    raise exception 'PROOF 31 FAIL: she does not make her whole passage at her new arrival: % of %', voyage.progress_nm(va, v_eta1), (select v.total_nm from public.voyages v where v.id = va);
  end if;
  raise notice 'PASS: BATTLE_SAILS_ON — six points match an unheld ship, and she never went back from departure to arrival';

  -- ── NO TURN ──
  perform cmd.assume_identity(c_uid);
  v_x := cmd.divert(a, (select id from public.ports where code = 'LIS'), null, null);
  if coalesce(v_x ->> 'error_code', '') <> 'E_FLEET_BUSY' or (select v.status from public.voyages v where v.id = va) <> 'SAILING'
     or (select v.eta from public.voyages v where v.id = va) <> v_eta1 then
    raise exception 'PROOF 31 FAIL: a held fleet was let turn: %', v_x;
  end if;
  raise notice 'PASS: BATTLE_NO_TURN — E_FLEET_BUSY, her voyage untouched';

  -- ── SERVED ──
  if jsonb_array_length(world.voyage_view(va, true) -> 'holds') is distinct from 1 or jsonb_array_length(world.voyage_view(va, false) -> 'holds') is distinct from 1
     or ((world.voyage_view(va, false) -> 'holds' -> 0 ->> 'until')::timestamptz) is distinct from t0 + make_interval(secs => v_len) then
    raise exception 'PROOF 31 FAIL: a voyage''s views do not serve her hold: %', world.voyage_view(va, false) -> 'holds';
  end if;
  update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
  insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience)
  select f.player_id, 900323, 'prt', 'A probe of proof 31.', 'Probe', (select id from public.ports where code = 'LIS'), 1000, 0.1 from public.fleets f where f.id = d;
  if not public.npc_traders_on() then
    raise exception 'PROOF 31 FAIL: the merchants are dark, so the roster cannot be read';
  end if;
  if (select r -> 'voyage' -> 'holds' -> 0 ->> 'from' from jsonb_array_elements(world.sea_roster(now() + interval '1 second') -> 'fleets') r where r ->> 'id' = d::text)::timestamptz is distinct from t0 then
    raise exception 'PROOF 31 FAIL: a roster delta does not serve a held ship';
  end if;
  if exists (select 1 from jsonb_array_elements(world.sea_roster(t0 + make_interval(secs => v_len + 1)) -> 'fleets') r where r ->> 'id' = d::text) then
    raise exception 'PROOF 31 FAIL: a delta past her hold still serves her';
  end if;
  raise notice 'PASS: BATTLE_SERVED — both views, a roster delta, and no delta past the hold';

  -- ── RESOLVED ONCE ──
  v_exp := public.fight_sides(v_b, 1, voyage.fleet_hulls(d), voyage.fleet_hulls(a));
  v_hull := (select jsonb_object_agg(s.id, s.durability) from public.ships s where s.fleet_id in (a, d));
  if public.tick_battles(t0 + make_interval(secs => v_len - 1)) <> 0 or (select b.status from public.battles b where b.id = v_b) <> 'FIGHTING' then
    raise exception 'PROOF 31 FAIL: a battle resolved before its time';
  end if;
  if public.tick_battles(t0 + make_interval(secs => v_len)) <> 1 then
    raise exception 'PROOF 31 FAIL: the job did not resolve the battle at its time';
  end if;
  if (v_exp -> 'hits' ->> 'a')::int + (v_exp -> 'hits' ->> 'b')::int = 0 then
    raise exception 'PROOF 31 FAIL: the probes fought and nobody hit anybody, so this proves nothing: %', v_exp;
  end if;
  if (select b.result from public.battles b where b.id = v_b) <> v_exp or (select b.status from public.battles b where b.id = v_b) <> 'RESOLVED' then
    raise exception 'PROOF 31 FAIL: the battle''s answer is not the fight seeded (battle id, 1)';
  end if;
  select bool_and(s.durability = greatest(0, (v_hull ->> s.id::text)::numeric - coalesce((v_exp -> 'hull_lost' -> 'a' ->> s.id::text)::numeric, (v_exp -> 'hull_lost' -> 'b' ->> s.id::text)::numeric, 0)))
    into v_ok from public.ships s where s.fleet_id in (a, d);
  if not v_ok then
    raise exception 'PROOF 31 FAIL: the hulls are not what the fight says';
  end if;
  v_hull := (select jsonb_object_agg(s.id, s.durability) from public.ships s where s.fleet_id in (a, d));
  if public.tick_battles(t0 + make_interval(secs => v_len + 60)) <> 0 or public.battle_resolve(v_b, t0 + make_interval(secs => v_len + 60)) then
    raise exception 'PROOF 31 FAIL: a retry resolved her again';
  end if;
  if (select jsonb_object_agg(s.id, s.durability) from public.ships s where s.fleet_id in (a, d)) <> v_hull then
    raise exception 'PROOF 31 FAIL: a retry moved a hull';
  end if;
  if exists (select 1 from public.fleets f where f.id in (a, d) and (f.busy_until is not null or f.status <> 'SAILING')) then
    raise exception 'PROOF 31 FAIL: a fleet was not freed';
  end if;
  select count(*) into v_n from public.events e where e.kind = 'BATTLE_REPORT' and e.player_id = (select f.player_id from public.fleets f where f.id = a);
  if v_n <> 1 or exists (select 1 from public.events e where e.kind = 'BATTLE_REPORT' and e.player_id = (select f.player_id from public.fleets f where f.id = d)) then
    raise exception 'PROOF 31 FAIL: % report(s) to the human, or one to the merchant', v_n;
  end if;
  v_x := (select e.payload from public.events e where e.kind = 'BATTLE_REPORT' and e.player_id = (select f.player_id from public.fleets f where f.id = a));
  if jsonb_array_length(v_x -> 'lines') <> 1 or (v_x -> 'fights' -> 0 ->> 'line')::int <> 0
     or jsonb_array_length(v_x -> 'fights' -> 0 -> 'rounds') <> (v_exp ->> 'rounds_fought')::int then
    raise exception 'PROOF 31 FAIL: the report is not in the shape the History tray reads: %', v_x;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'attack_enabled';
  raise notice 'PASS: BATTLE_RESOLVED_ONCE — %, % round(s); once, under two retries; one report', v_exp ->> 'outcome', v_exp ->> 'rounds_fought';
end
$p$;

-- ── IN PORT AND AT ANCHOR ──
do $p$
declare
  c_uid constant uuid := '00000000-0323-4000-8000-000000000d01';
  a     uuid := pg_temp.fleet_0323(c_uid, false, false);
  d     uuid := pg_temp.fleet_0323('00000000-0323-4000-8000-000000000d02', true, false);
  sea   uuid := pg_temp.fleet_0323('00000000-0323-4000-8000-000000000d03', false, true);
  t0    timestamptz := now() + interval '5 seconds';
  v_b   uuid;
  v_x   jsonb;
  v_err text;
begin
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  update public.fleets set status = 'ANCHORED', port_id = null, lat = 38, lon = -12 where id = d;
  v_b := public.battle_open('PROBE', a, d, t0);
  if (select f.status from public.fleets f where f.id = a) <> 'IN_BATTLE' or (select f.status from public.fleets f where f.id = d) <> 'IN_BATTLE'
     or (select f.busy_until from public.fleets f where f.id = a) <> t0 + make_interval(secs => public.wc_num('battle_seconds')::double precision) then
    raise exception 'PROOF 31 FAIL: a fleet in port or at anchor did not go IN_BATTLE';
  end if;
  if (select (b.site ->> 'lat')::numeric from public.battles b where b.id = v_b) <> 38 then
    raise exception 'PROOF 31 FAIL: the site is not the anchor';
  end if;
  perform cmd.assume_identity(c_uid);
  v_x := cmd.issue(a, 'PROVISION FULL');
  if not exists (select 1 from public.orders o where o.fleet_id = a and o.status = 'pending') then
    raise exception 'PROOF 31 FAIL: her order did not wait in her queue: %', v_x;
  end if;
  if cmd.advance(a, t0 + interval '10 seconds') <> 0 or (select f.status from public.fleets f where f.id = a) <> 'IN_BATTLE' then
    raise exception 'PROOF 31 FAIL: the queue ran in a battle';
  end if;
  if public.tick_battles(t0 + interval '1 hour') <> 1 then
    raise exception 'PROOF 31 FAIL: the battle did not resolve';
  end if;
  if (select f.status from public.fleets f where f.id = a) <> 'DOCKED' or (select f.status from public.fleets f where f.id = d) <> 'ANCHORED'
     or exists (select 1 from public.fleets f where f.id in (a, d) and f.busy_until is not null) then
    raise exception 'PROOF 31 FAIL: they did not come back as they were: %, %', (select f.status from public.fleets f where f.id = a), (select f.status from public.fleets f where f.id = d);
  end if;
  if exists (select 1 from public.orders o where o.fleet_id = a and o.status = 'pending') then
    raise exception 'PROOF 31 FAIL: her queue did not run when the battle ended';
  end if;
  begin
    update public.fleets set status = 'IN_BATTLE', port_id = null, lat = null, lon = null where id = sea;
    v_err := null;
  exception when check_violation then v_err := sqlerrm;
  end;
  if v_err is null or v_err !~ 'fleets_in_battle_lies_still' then
    raise exception 'PROOF 31 FAIL: a fleet at sea could be IN_BATTLE: %', coalesce(v_err, 'no refusal');
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'attack_enabled';
  raise notice 'PASS: BATTLE_IN_PORT — IN_BATTLE, the queue waits and runs after, back DOCKED and ANCHORED; a fleet at sea cannot be IN_BATTLE';
end
$p$;

-- ── OFFLINE: one voyage, the sea on, held, settled two ways. A subtransaction is thrown away between them; the variables are what survive it ──
do $p$
declare
  f      uuid := pg_temp.fleet_0323('00000000-0323-4000-8000-000000000e01', false, true, false);
  v      uuid := pg_temp.voy_0323(f);
  v_dep  timestamptz := (select departed_at from public.voyages where id = v);
  t0     timestamptz := v_dep + make_interval(secs => 86400 * 2.3 / public.wc_num('time_compression'));
  v_len  numeric := public.wc_num('battle_seconds');
  v_end  timestamptz := v_dep + interval '30 days';
  v_read constant text := $r$
    select jsonb_build_object(
      'events', (select jsonb_agg(jsonb_build_object('d', ve.day_index, 'k', ve.kind, 'p', ve.payload - 'wages', 'at', ve.resolved_at) order by ve.day_index) from public.voyage_events ve where ve.voyage_id = $1),
      'voyage', (select jsonb_build_object('eta', vo.eta, 'delay', vo.delay_hours, 'status', vo.status, 'last', vo.last_settled_day) from public.voyages vo where vo.id = $1),
      'report', (select e.payload -> 'lines' from public.events e where e.kind = 'VOYAGE_REPORT' and e.payload ->> 'voyage_id' = $1::text),
      'ships', (select jsonb_agg(jsonb_build_object('h', s.durability, 'w', s.water_t, 'f', s.food_t, 'c', s.crew) order by s.id) from public.ships s where s.fleet_id = $2))
  $r$;
  v_step jsonb;
  v_lazy jsonb;
  v_t    timestamptz;
  v_guard int;
begin
  begin
    perform voyage.settle(f, t0);
    perform voyage.hold(f, t0 + make_interval(secs => v_len::double precision), t0);
    v_t := t0;
    v_guard := 0;
    while (select status from public.voyages where id = v) = 'SAILING' and v_guard < 4000 loop
      v_t := v_t + interval '13 seconds';
      v_guard := v_guard + 1;
      perform voyage.settle(f, v_t);
    end loop;
    perform voyage.settle(f, v_end);
    execute v_read into v_step using v, f;
    raise exception 'twin 0323';
  exception when raise_exception then
    if sqlerrm <> 'twin 0323' then raise; end if;
  end;
  begin
    perform voyage.settle(f, t0);
    perform voyage.hold(f, t0 + make_interval(secs => v_len::double precision), t0);
    perform voyage.settle(f, v_end);
    execute v_read into v_lazy using v, f;
    raise exception 'twin 0323';
  exception when raise_exception then
    if sqlerrm <> 'twin 0323' then raise; end if;
  end;
  if v_step is null or v_step -> 'voyage' ->> 'status' <> 'ARRIVED' then
    raise exception 'PROOF 31 FAIL: the twin did not arrive: %', v_step -> 'voyage';
  end if;
  if v_step <> v_lazy then
    raise exception 'PROOF 31 FAIL: settled day by day and at the end differ: % against %', left(v_step::text, 900), left(v_lazy::text, 900);
  end if;
  if not exists (select 1 from jsonb_array_elements_text(v_step -> 'report') l where l ~ '^Day [0-9]{1,3}\. We hove to and fought, and lost [0-9.]+ hours\.$')
     or exists (select 1 from jsonb_array_elements_text(v_step -> 'report') l where l ~ '^Day [0-9]{4,}') then
    raise exception 'PROOF 31 FAIL: her report does not name the true day: %', v_step -> 'report';
  end if;
  raise notice 'PASS: BATTLE_OFFLINE — % days, the same voyage both ways; her report names the day she was held', v_step -> 'voyage' ->> 'last';
end
$p$;

-- ── THE WORDS ──
do $p$
declare
  c_a constant jsonb := jsonb_build_array(jsonb_build_object('id', '00000000-0323-4000-8000-00000000f001', 'name', 'Probe A', 'tier', 2, 'hull', 100, 'maxd', 100, 'crew', 40, 'attack', 30, 'accuracy', 60, 'reach', 90, 'armour', 0, 'sighting', 10));
  c_b constant jsonb := jsonb_build_array(jsonb_build_object('id', '00000000-0323-4000-8000-00000000f002', 'name', 'Probe B', 'tier', 2, 'hull', 100, 'maxd', 100, 'crew', 40, 'attack', 30, 'accuracy', 60, 'reach', 90, 'armour', 0, 'sighting', 10));
  v_f  jsonb;
  v_w  jsonb;
  v_r  jsonb;
  v_me text;
  v_n  int;
  v_ok int := 0;
  i    int;
begin
  for i in 1 .. 12 loop
    v_f := public.fight_sides(('00000000-0323-4000-8000-0000000000' || lpad(to_hex(i), 2, '0'))::uuid, 1, c_a, c_b);
    v_n := (v_f ->> 'rounds_fought')::int;
    continue when v_n = 0 or (v_f -> 'rounds' -> 0 -> 'b' ->> 'hits')::int = 0;
    v_w := public.battle_words(v_f, c_b);
    v_r := v_w -> 'fights' -> 0 -> 'rounds';
    if jsonb_array_length(v_r) <> v_n then
      raise exception 'PROOF 31 FAIL: % round(s) told for % fought', jsonb_array_length(v_r), v_n;
    end if;
    -- side b, the attacker, is `you`: her own hits are the first number of the line
    v_me := format('you hit with %s of %s shot', (v_f -> 'rounds' -> 0 -> 'b' ->> 'hits'), (v_f -> 'rounds' -> 0 -> 'b' ->> 'fired'));
    if position(v_me in v_r ->> 0) = 0 or position('The enemy are' in v_r ->> 0) = 0 then
      raise exception 'PROOF 31 FAIL: the round is not told from the attacker''s deck: % / %', v_r ->> 0, v_f -> 'rounds' -> 0;
    end if;
    v_ok := v_ok + 1;
  end loop;
  if v_ok = 0 then
    raise exception 'PROOF 31 FAIL: no probe fight landed a hit';
  end if;
  raise notice 'PASS: BATTLE_WORDS — % fights told from the attacker''s deck, round for round', v_ok;
end
$p$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 180 - EARLY SIGHTING  (migration 0477; docs/design/roadmap-2026-11-23.md slice 7; docs/dev-log/2026-11-23-early-sighting.md)
--
--   The migration's self-assert walks one sighting with the purses as the image has them. This proof plays it as production runs: the
--   economy closed and the city purses lit (a ransom leaves her purse for the pirate's home, an insurer pays from its own), pirates of
--   several rungs and bounties placed round her, a strong pirate the guard must cut, an insured trip and an uninsured one, a trip that ends
--   first, and the cost. Rolled back by proof.mjs. Its scenes take seconds and never straddle UTC midnight (nothing here is daily).
--
-- @pass ES_DARK    dark: a departure that would be set writes nothing, the step answers {} and the read {"on": false}
-- @pass ES_PLAN    lit: a near trip with cargo at Trading 3 and a title under Master is set DUE at 0.4 of the trip; untrained, an empty
--                  hold, a trip outside the window or a title at the knob are not
-- @pass ES_MISSED  a trip that ends before she is sighted leaves the row MISSED, and her next such departure sets it again
-- @pass ES_PIRATE  the pirate is the nearest of rung 1 at work, free and with no bounty: a nearer Corsair and a nearer named Raider are
--                  passed over; the raid is THE battle (kind RAID, her fleet set upon), the pirate's guns on the sheet cut to the knob
-- @pass ES_GUARD   a pirate strong enough to hurt her has her guns halved (or silenced) until no hull of her side ends under the floor
-- @pass ES_ALONE   nobody joins a sighting: public.battle_npc_joins passes it over
-- @pass ES_TOLD    closed by the raids' own close, the next step tells it once (EARLY_SIGHTING): the loss is the raid's ransom from her
--                  purse; insured, the insurer paid back (1 - keep) of it; uninsured, what it would have paid; no guns, what guns would do
-- @pass ES_ONCE    a company told once is never set again; her ship is afloat and above the floor
-- @pass ES_COST    a lit departure's plan and an empty step, timed
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- a pirate of the Brethren's, made by the game's hands, lying anchored at (lat, lon): ord picks her rung (npc_rung_rule's pattern by ord)
create function pg_temp.pirate_180(p_name text, p_class text, p_ord int, p_lat numeric, p_lon numeric) returns uuid language plpgsql as $f$
declare
  v_home uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_pl   uuid;
  v_f    uuid;
begin
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (null, p_name, public.pirate_nation(), 0, true) returning id into v_pl;
  v_f := public.form_fleet(v_pl, p_name, v_home);
  perform public.commission_ship(v_pl, v_f, p_class, p_name, true, true);
  insert into public.pirate_ships (fleet_id, player_id, ord, home_port, last_port) values (v_f, v_pl, p_ord, v_home, v_home);
  update public.ships s set crew = (select c.crew_required from public.ship_classes c where c.id = s.class_id),
                            durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_f;
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p_lat, lon = p_lon, busy_until = null, ready_at = null where f.id = v_f;
  return v_f;
end
$f$;

-- she lies at Lisbon again (her voyage, if any, ended), then sails the probe course from p_at; answers the voyage
create function pg_temp.sail_180(p_fleet uuid, p_segs jsonb, p_at timestamptz) returns uuid language plpgsql as $f$
declare
  v_lis uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_set uuid := (select p.id from public.ports p where p.code = 'SET' and p.kind = 'HARBOUR');
begin
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, busy_until = null, ready_at = null where f.id = p_fleet;
  return voyage.depart(p_fleet, p_segs, v_lis, v_set, p_at);
end
$f$;

do $p$
declare
  c_a    constant uuid := '00000000-0477-4000-8000-0000000000a1';
  c_b    constant uuid := '00000000-0477-4000-8000-0000000000b1';
  c_d    constant uuid := '00000000-0477-4000-8000-0000000000d1';
  c_e    constant uuid := '00000000-0477-4000-8000-0000000000e1';
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_set  uuid := (select p.id from public.ports p where p.code = 'SET' and p.kind = 'HARBOUR');
  v_segs jsonb;
  v_a    uuid;
  v_b    uuid;
  v_d    uuid;
  v_ep   uuid;
  v_fa   uuid;
  v_fb   uuid;
  v_fd   uuid;
  v_fe   uuid;
  v_va   uuid;
  v_ve   uuid;
  v_secs numeric;
  v_row  record;
  v_bat  public.battles%rowtype;
  v_pos  record;
  v_near uuid;
  v_far  uuid;
  v_cor  uuid;
  v_named uuid;
  v_strong uuid;
  v_r    jsonb;
  v_p0   bigint;
  v_p1   bigint;
  v_lost bigint;
  v_ms1  numeric;
  v_ms2  numeric;
  v_at   timestamptz;
  i      int;
begin
  -- the purses well above their reserves (as proof 179 seeds them), so the capitals found, insurers pay and ransoms move
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;
  update public.world_config set value = 'true'::jsonb
   where key in ('economy_closed', 'city_treasury_enabled', 'attack_enabled', 'raid_orders_enabled', 'pirates_bite') and value is distinct from 'true'::jsonb;
  update public.world_config set value = '["RAID", "ATTACK"]'::jsonb where key = 'tick_fight_kinds';
  select voyage.segments_from_course(jsonb_build_array(jsonb_build_array(x.roadstead_lat, x.roadstead_lon), jsonb_build_array(y.roadstead_lat, y.roadstead_lon)))
         || voyage.segments_from_course(jsonb_build_array(jsonb_build_array(y.roadstead_lat, y.roadstead_lon), jsonb_build_array(x.roadstead_lat, x.roadstead_lon)))
    into v_segs from public.sea_reaches x, public.sea_reaches y where x.port_id = v_lis and y.port_id = v_set;

  -- A at Trading 3 (title Apprentice), B untrained, D at Trading 3 with an empty hold, E at Trading 3 (the guard's)
  v_a := public.new_house(c_a, 'Casa Avista A 180', 'PRT');
  v_b := public.new_house(c_b, 'Casa Avista B 180', 'PRT');
  v_d := public.new_house(c_d, 'Casa Avista D 180', 'PRT');
  v_ep := public.new_house(c_e, 'Casa Avista E 180', 'PRT');
  insert into public.house_level_marks (player_id, track, level) values (v_a, 'trading', 3), (v_d, 'trading', 3), (v_ep, 'trading', 3)
    on conflict (player_id, track) do update set level = 3;
  select f.id into v_fa from public.fleets f where f.player_id = v_a;
  select f.id into v_fb from public.fleets f where f.player_id = v_b;
  select f.id into v_fd from public.fleets f where f.player_id = v_d;
  select f.id into v_fe from public.fleets f where f.player_id = v_ep;
  update public.ships s set cargo = '{"WINE": 100}'::jsonb, cargo_basis = '{"WINE": 50}'::jsonb where s.fleet_id in (v_fa, v_fb, v_fe);
  update public.world_config set value = to_jsonb(1) where key = 'early_sighting_trip_min_seconds';

  -- ── ES_DARK ──
  update public.world_config set value = 'false'::jsonb where key = 'early_sighting_enabled';
  v_va := pg_temp.sail_180(v_fa, v_segs, now() - interval '5 seconds');
  perform cmd.assume_identity(c_a);
  if exists (select 1 from public.early_sightings) or public.early_sighting_step(now()) <> '{}'::jsonb
     or world.early_sighting() is distinct from '{"on": false}'::jsonb then
    raise exception 'PROOF 180 FAILED: dark, a departure was set, the step did something or the read is not {"on": false}';
  end if;
  raise notice 'PASS: ES_DARK — dark: her departure (Trading 3, cargo, a near trip) set nothing, the step {}, the read {"on": false}';

  -- ── ES_PLAN ──
  update public.world_config set value = 'true'::jsonb where key = 'early_sighting_enabled';
  v_va := pg_temp.sail_180(v_fa, v_segs, now() - interval '5 seconds');
  select extract(epoch from v.eta - v.departed_at) into v_secs from public.voyages v where v.id = v_va;
  select * into v_row from public.early_sightings e where e.player_id = v_a;
  if v_row.state is distinct from 'due' or v_row.voyage_id <> v_va
     or abs(extract(epoch from v_row.due_at - (select v.departed_at + (v.eta - v.departed_at) * 0.4 from public.voyages v where v.id = v_va))) > 0.01 then
    raise exception 'PROOF 180 FAILED: lit, her near trip was not set DUE at 0.4: %', to_jsonb(v_row);
  end if;
  perform pg_temp.sail_180(v_fb, v_segs, now());
  perform pg_temp.sail_180(v_fd, v_segs, now());
  if exists (select 1 from public.early_sightings e where e.player_id in (v_b, v_d)) then
    raise exception 'PROOF 180 FAILED: an untrained company or an empty hold was set';
  end if;
  -- the window either side of her trip (a hull's speed is her own roll, so each bound is put past any of these trips)
  update public.world_config set value = to_jsonb(100000) where key = 'early_sighting_trip_min_seconds';
  perform pg_temp.sail_180(v_fe, v_segs, now());
  update public.world_config set value = to_jsonb(1) where key = 'early_sighting_trip_min_seconds';
  update public.world_config set value = to_jsonb(2) where key = 'early_sighting_trip_max_seconds';
  perform pg_temp.sail_180(v_fe, v_segs, now());
  update public.world_config set value = to_jsonb(1800) where key = 'early_sighting_trip_max_seconds';
  update public.world_config set value = to_jsonb(1) where key = 'raid_company_title_min';
  perform pg_temp.sail_180(v_fe, v_segs, now());
  update public.world_config set value = to_jsonb(3) where key = 'raid_company_title_min';
  if exists (select 1 from public.early_sightings e where e.player_id = v_ep) then
    raise exception 'PROOF 180 FAILED: a trip under the shortest, over the longest, or a company at the title knob was set';
  end if;
  raise notice 'PASS: ES_PLAN — her % s trip set DUE at 0.4 (%); untrained, an empty hold, the window either side and a title at the knob: none',
    round(v_secs), to_char(v_row.due_at - v_row.planned_at, 'MI:SS.MS');

  -- ── ES_MISSED: her trip ends before she is sighted; her next such departure sets it again ──
  update public.voyages v set status = 'ARRIVED' where v.id = v_va;
  update public.fleets f set status = 'DOCKED', port_id = v_set where f.id = v_fa;
  update public.early_sightings e set due_at = now() - interval '1 second' where e.player_id = v_a;
  v_r := public.early_sighting_step(now());
  if v_r #>> '{sighting,MISSED}' is distinct from '1' or (select e.state from public.early_sightings e where e.player_id = v_a) <> 'missed' then
    raise exception 'PROOF 180 FAILED: a trip that ended first was not MISSED: %', v_r;
  end if;
  update public.fleets f set status = 'DOCKED', port_id = v_lis where f.id = v_fa;
  v_va := pg_temp.sail_180(v_fa, v_segs, now() - interval '5 seconds');
  if (select e.state from public.early_sightings e where e.player_id = v_a) <> 'due' or (select e.voyage_id from public.early_sightings e where e.player_id = v_a) <> v_va then
    raise exception 'PROOF 180 FAILED: her next near trip did not set the MISSED row again';
  end if;
  raise notice 'PASS: ES_MISSED — the trip ended first: %; her next departure set it DUE again on the new voyage', v_r;

  -- ── ES_PIRATE: pirates round her; she pays at once (her standing order PAY), insured ──
  insert into public.fleet_raid_orders (fleet_id, raid_order) values (v_fa, 'PAY') on conflict (fleet_id) do update set raid_order = excluded.raid_order;
  v_r := public.insure_voyage(v_va, true);
  select q.lat, q.lon into v_pos from voyage.position(v_va, now()) q;
  v_cor   := pg_temp.pirate_180('Corsario 180', 'fusta', 900001, v_pos.lat, v_pos.lon);                -- rung 2: the nearest, passed over
  v_named := pg_temp.pirate_180('Nomeado 180', 'fusta', 900008, v_pos.lat, v_pos.lon + 0.01);       -- rung 1 with a bounty: passed over
  insert into public.pirate_bounties (slot, fleet_id, epithet, given, home_port, poster_port, named_at)
    values (50, v_named, 'RED', 'Ruy', v_lis, v_lis, now());
  v_near  := pg_temp.pirate_180('Perto 180', 'fusta', 900002, v_pos.lat, v_pos.lon + 0.2);           -- rung 1: the one
  v_far   := pg_temp.pirate_180('Longe 180', 'fusta', 900014, v_pos.lat - 20, v_pos.lon - 30);       -- rung 1, far off
  if public.npc_rung_of(v_cor) <> 2 or public.npc_rung_of(v_named) <> 1 or public.npc_rung_of(v_near) <> 1 or public.npc_rung_of(v_far) <> 1 then
    raise exception 'PROOF 180 FAILED: the probe pirates are not of the rungs written (% % % %)', public.npc_rung_of(v_cor), public.npc_rung_of(v_named), public.npc_rung_of(v_near), public.npc_rung_of(v_far);
  end if;
  update public.early_sightings e set due_at = now() - interval '1 second' where e.player_id = v_a;
  v_p0 := (select p.ducats from public.players p where p.id = v_a);
  v_r := public.early_sighting_step(now());
  select * into v_row from public.early_sightings e where e.player_id = v_a;
  select * into v_bat from public.battles b where b.id = v_row.battle_id;
  if v_r #>> '{sighting,OPENED}' is distinct from '1' or v_row.state <> 'open' or v_row.pirate_fleet <> v_near or v_bat.kind <> 'RAID'
     or not exists (select 1 from public.battle_sides s where s.battle_id = v_bat.id and s.fleet_id = v_fa and s.side = 'DEFENDER' and s.how = 'OPENED')
     or v_row.order_word <> 'PAY' or v_row.strength > 0.5
     or (v_bat.sheet #>> '{b,0,attack}')::numeric <> round((select (h ->> 'attack')::numeric from jsonb_array_elements(voyage.fleet_hulls(v_near)) h limit 1) * v_row.strength, 2) then
    raise exception 'PROOF 180 FAILED: the sighting was not the nearest free Raider''s raid, her guns cut: % % %', v_r, to_jsonb(v_row), v_bat.sheet -> 'b';
  end if;
  raise notice 'PASS: ES_PIRATE — % (rung 1, % nm off) sighted her, not the Corsair nor the named Raider beside her; a RAID, her order PAY; the pirate''s guns % of hers (%)',
    (select f.name from public.fleets f where f.id = v_near),
    round(voyage.gc_distance_nm(v_pos.lat::float8, v_pos.lon::float8, v_pos.lat::float8, (v_pos.lon + 0.2)::float8)::numeric, 1), v_row.strength, v_bat.sheet #>> '{b,0,attack}';

  -- ── ES_ALONE: every join lit and sure; nobody joins the sighting ──
  update public.world_config set value = to_jsonb(1) where key in ('battle_join_pirate_chance', 'battle_join_navy_chance');
  v_r := public.battle_npc_joins(now());
  if exists (select 1 from public.battle_sides s where s.battle_id = v_bat.id and s.how = 'JOINED')
     or position('early_sightings' in pg_get_functiondef('public.battle_npc_joins(timestamp with time zone)'::regprocedure)) = 0 then
    raise exception 'PROOF 180 FAILED: a ship joined the sighting: %', v_r;
  end if;
  raise notice 'PASS: ES_ALONE — the joins'' run (chances 1) answered %, and nobody joined the sighting', v_r;

  -- ── ES_GUARD: E meets a xebec (rung 1 by her ord) at full guns, the floor at 99.5 %: her guns are cut until the timeline keeps her ──
  update public.world_config set value = to_jsonb(1) where key = 'early_sighting_strength';
  update public.world_config set value = to_jsonb(0.995) where key = 'early_sighting_hull_floor';
  v_ve := pg_temp.sail_180(v_fe, v_segs, now() - interval '5 seconds');
  select q.lat, q.lon into v_pos from voyage.position(v_ve, now()) q;
  v_strong := pg_temp.pirate_180('Forte 180', 'xebec', 900020, v_pos.lat, v_pos.lon);
  update public.early_sightings e set due_at = now() - interval '1 second' where e.player_id = v_ep;
  v_r := public.early_sighting_step(now());
  select * into v_row from public.early_sightings e where e.player_id = v_ep;
  select * into v_bat from public.battles b where b.id = v_row.battle_id;
  if v_row.state is distinct from 'open' or v_row.pirate_fleet <> v_strong or v_row.strength >= 1
     or exists (select 1 from jsonb_array_elements(v_bat.sheet -> 'a') h
                 where (h ->> 'hull')::numeric - coalesce((v_bat.ticks #>> array['r', 'hull_lost', 'a', h ->> 'id'])::numeric, 0)
                       < least((h ->> 'hull')::numeric, 0.995 * (h ->> 'maxd')::numeric) - 0.001) then
    raise exception 'PROOF 180 FAILED: the guard did not cut a strong pirate until her hulls were kept: % %', to_jsonb(v_row), v_bat.ticks -> 'r' -> 'hull';
  end if;
  raise notice 'PASS: ES_GUARD — a xebec at full guns against a floor of 99.5 %%: cut to % of her guns (attack %), her hull % of % in the timeline',
    v_row.strength, v_bat.sheet #>> '{b,0,attack}', v_bat.ticks #>> '{r,hull,a}', v_bat.ticks #>> '{r,hull,a_start}';
  update public.world_config set value = to_jsonb(0.5) where key = 'early_sighting_strength';
  update public.world_config set value = to_jsonb(0.5) where key = 'early_sighting_hull_floor';

  -- ── ES_TOLD: both closed by the raids' own close; the next step tells each once ──
  select * into v_bat from public.battles b where b.id = (select e.battle_id from public.early_sightings e where e.player_id = v_a);
  perform public.battle_resolve(v_bat.id, v_bat.resolves_at + interval '1 second');
  v_at := greatest(v_bat.resolves_at, (select b.resolves_at from public.battles b where b.id = v_row.battle_id)) + interval '2 seconds';
  perform public.battle_resolve(v_row.battle_id, v_at - interval '1 second');
  v_p1 := (select p.ducats from public.players p where p.id = v_a);
  v_r := public.early_sighting_step(v_at);
  if v_r #>> '{sighting,TOLD}' is distinct from '2' then
    raise exception 'PROOF 180 FAILED: the step did not tell both closes: %', v_r;
  end if;
  -- A: she paid; the ransom left her purse; the insurer paid back (1 - keep) of it
  select * into v_row from public.early_sightings e where e.player_id = v_a;
  v_lost := (v_row.report ->> 'lost')::bigint;
  if v_row.state <> 'done' or v_row.report ->> 'outcome' <> 'RANSOM' or v_lost <= 0
     or v_lost <> (select (b.result #>> '{raid,taken}')::bigint from public.battles b where b.id = v_row.battle_id)
     or v_lost <> public.ransom_take(5000)
     or v_p0 - v_p1 <> v_lost
     or not (v_row.report ->> 'insured')::boolean
     or (v_row.report ->> 'insurance_paid')::bigint <> round(v_lost * (1 - public.wc_num('insurance_keep_pct')))
     or (select count(*) from public.events ev where ev.player_id = v_a and ev.kind = 'INSURANCE_PAID' and ev.payload ->> 'cause' = 'EARLY_SIGHTING') <> 1
     or (select count(*) from public.events ev where ev.player_id = v_a and ev.kind = 'EARLY_SIGHTING') <> 1
     or (select ev.payload from public.events ev where ev.player_id = v_a and ev.kind = 'EARLY_SIGHTING') <> v_row.report
     or (v_row.report ->> 'guns')::boolean or v_row.report ->> 'guns_outcome' is null
     or v_row.report ->> 'to' <> 'SET' or v_row.report ->> 'pirate' <> 'Perto 180' then
    raise exception 'PROOF 180 FAILED: her sighting was not told as it went: % (purse % -> %)', v_row.report, v_p0, v_p1;
  end if;
  -- E: uninsured; what insurance would have paid back
  select * into v_row from public.early_sightings e where e.player_id = v_ep;
  if v_row.state <> 'done' or (v_row.report ->> 'insured')::boolean or (v_row.report ->> 'insurance_paid')::bigint <> 0
     or (v_row.report ->> 'insurance_back')::bigint <> round((v_row.report ->> 'lost')::bigint * (1 - public.wc_num('insurance_keep_pct'))) then
    raise exception 'PROOF 180 FAILED: the uninsured sighting did not say what insurance would have paid: %', v_row.report;
  end if;
  perform cmd.assume_identity(c_a);
  if world.early_sighting() ->> 'state' <> 'done' or world.early_sighting() -> 'report' <> (select e.report from public.early_sightings e where e.player_id = v_a) then
    raise exception 'PROOF 180 FAILED: the read does not serve her told sighting: %', world.early_sighting();
  end if;
  raise notice 'PASS: ES_TOLD — A paid % off: her purse -% (the ransom, % of her 5,000 aboard), insured: % paid back (keep %); no guns, armed like the pirate: %. E (uninsured, %): lost %, insurance would have paid %',
    (select e.report ->> 'pirate' from public.early_sightings e where e.player_id = v_a), v_lost, public.wc_num('ransom_share'),
    (select e.report ->> 'insurance_paid' from public.early_sightings e where e.player_id = v_a), public.wc_num('insurance_keep_pct'),
    (select e.report ->> 'guns_outcome' from public.early_sightings e where e.player_id = v_a),
    v_row.report ->> 'outcome', v_row.report ->> 'lost', v_row.report ->> 'insurance_back';

  -- ── ES_ONCE ──
  perform pg_temp.sail_180(v_fa, v_segs, now());
  perform pg_temp.sail_180(v_fe, v_segs, now());
  if exists (select 1 from public.early_sightings e where e.player_id in (v_a, v_ep) and e.state <> 'done')
     or public.early_sighting_step(v_at + interval '1 minute') <> '{}'::jsonb
     or (select count(*) from public.events ev where ev.player_id in (v_a, v_ep) and ev.kind = 'EARLY_SIGHTING') <> 2
     or exists (select 1 from public.ships s where s.fleet_id in (v_fa, v_fe)
                 and s.durability < 0.5 * (select b.durability from public.ship_base(s.id) b) - 0.001)
     or exists (select 1 from public.fleets f where f.id in (v_fa, v_fe) and f.status = 'UNABLE_TO_SAIL') then
    raise exception 'PROOF 180 FAILED: a company told once was set again, told twice, or her ship was not kept';
  end if;
  raise notice 'PASS: ES_ONCE — their next departures set nothing; one EARLY_SIGHTING each; both ships afloat over half their hull';

  -- ── ES_COST ──
  v_at := clock_timestamp();
  for i in 1 .. 20 loop
    perform public.early_sighting_plan(v_va, now());
  end loop;
  v_ms1 := extract(epoch from clock_timestamp() - v_at) * 1000 / 20;
  v_at := clock_timestamp();
  for i in 1 .. 20 loop
    perform public.early_sighting_step(now());
  end loop;
  v_ms2 := extract(epoch from clock_timestamp() - v_at) * 1000 / 20;
  if v_ms1 > 200 or v_ms2 > 200 then
    raise exception 'PROOF 180 FAILED: the plan (% ms) or an empty step (% ms) is not cheap', round(v_ms1, 2), round(v_ms2, 2);
  end if;
  raise notice 'PASS: ES_COST — a lit departure''s plan % ms (her row done: one key probe), an empty step % ms (two partial-index probes)', round(v_ms1, 2), round(v_ms2, 2);
end $p$;

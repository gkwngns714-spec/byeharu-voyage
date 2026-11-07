-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 38 — DANGER IS ONE NUMBER  (migration 0330, W15 of docs/WORLD_POWERS.md, Z1 of docs/PIRATES_AND_HAVENS.md)
--
--   0330's self-assert reads the catalog and one rolled-back row (a migration never runs a real game step, docs/OPS_HEALTH.md section 4). This proof runs the REAL voyage.depart, voyage.settle, voyage.hazard_roll,
--   voyage.risk_quote, voyage.waters_ahead and cmd.divert, across all 51 seas, against byte copies of what those bodies read before the file. Pressure is written only here, and rolled back with the proof.
--   Before and after the file on one fixed voyage, byte for byte: scripts/ops/harness/sea-danger/dark-scene.sql (proof-0330.mjs).
--
-- @pass SEA_FIGURE_51    all 51 seas: voyage.sea_danger is piracy_index to the digit, and a departure freezes those digits on every segment
-- @pass SEA_MIX_51       all 51 seas: the new mix is the old body's, byte for byte, at the frozen figure
-- @pass SEA_ROLL_51      a voyage through all 51 seas: every day's roll is the old roll, at the real streams
-- @pass SEA_RAID_51      a raid in each of the 51 seas, through the real settle: strength is piracy_index x 40 x (0.5 + magnitude) of that sea
-- @pass SEA_QUOTE_51     the same voyage: risk_quote is the old sum, to the digit
-- @pass SEA_WATERS_51    the same voyage: the panel shows the old mix for all 51 waters
-- @pass SEA_PRESSURE     the formula: wins, decay, clamps at 0 and 1, the future, a null moment
-- @pass SEA_FROZEN       pressure after she left moves nothing she rolls, is quoted or is shown; a voyage leaving after it carries the new figure, and the mix really moves on it
-- @pass SEA_LATE         pressure moved between two settlements of one voyage: late and on time write the same days, byte for byte
-- @pass SEA_LEGACY       a segment frozen before 0330 reads as the sea as authored, in the roll, the raid, the quote and the panel
-- @pass SEA_DIVERT       a turn keeps the sailed water's frozen figures; the onward water is frozen at the turn
-- @pass SEA_LEVEL        the served level is the authored level until the figure crosses a band, moves one step for each, and stays in 1 to 5
-- @pass SEA_ONE_READER   no function or view but voyage.sea_danger reads piracy_index; the scan sees that one
-- @pass SEA_NO_CLIENT    no client can call what is new or read the table; the table is empty and nothing but public.pirate_pressure_write (0339, W17) writes it
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- byte copy of 0055's voyage.sea_mix(uuid), the body 0330 drops: the only "old" this proof trusts
create function pg_temp.old_mix(p_sea uuid)
returns table (kind_code text, share numeric, cum_share numeric)
language plpgsql stable
as $b$
declare
  v_d   numeric;
  v_p   numeric;
  v_tot numeric;
begin
  select s.danger_level::numeric / 5, s.piracy_index into v_d, v_p
    from public.seas s where s.id = p_sea;
  select sum(k.mix_base * (1 + k.mix_danger * v_d + k.mix_raiders * v_d * v_p))
    into v_tot from public.voyage_event_kinds k where k.in_sea_mix;
  return query
    select k.code,
           round(k.mix_base * (1 + k.mix_danger * v_d + k.mix_raiders * v_d * v_p) / v_tot, 6),
           round(sum(k.mix_base * (1 + k.mix_danger * v_d + k.mix_raiders * v_d * v_p))
                   over (order by k.ordinal rows between unbounded preceding and current row)
                 / v_tot, 6)
      from public.voyage_event_kinds k
     where k.in_sea_mix
     order by k.ordinal;
end
$b$;

-- the old roll's kind for a day: 0059's voyage.hazard_roll draw, over the old mix
create function pg_temp.old_kind(p_voyage uuid, p_day int, p_sea uuid)
returns text
language sql stable
as $b$
  select m.kind_code from pg_temp.old_mix(p_sea) m where voyage.rng(p_voyage, p_day, 'kind') < m.cum_share order by m.cum_share limit 1
$b$;

create function pg_temp.house_0330(p_uid uuid)
returns uuid
language plpgsql
as $b$
declare
  v_tag text := right(p_uid::text, 4);
  v_p   uuid := public.new_house(p_uid, 'Casa Perigo ' || v_tag, 'PRT', 'LIS', 'Perigo ' || v_tag,
                                 (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1), 'Perigo ' || v_tag, null, false);
  v_f   uuid;
begin
  select id into v_f from public.fleets where player_id = v_p;
  update public.ships set water_t = 100000, food_t = 100000 where fleet_id = v_f;
  return v_f;
end
$b$;

-- all 51 seas, one a voyage-day, so day d is in the d-th sea by code
create function pg_temp.fifty_one(p_fleet uuid)
returns jsonb
language sql stable
as $b$
  select jsonb_agg(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', round(voyage.fleet_speed(p_fleet) * 24, 2), 'sea_id', s.id, 'hazard_mult', 1000) order by s.code)
    from public.seas s
$b$;

create function pg_temp.sea_at(p_day int)
returns uuid
language sql stable
as $b$
  select s.id from public.seas s order by s.code offset p_day - 1 limit 1
$b$;

-- what a voyage has written, whole: the days, in order
create function pg_temp.days(p_voyage uuid)
returns text
language sql stable
as $b$
  select coalesce(string_agg(e.day_index || ':' || e.kind || ':' || e.resolved_at::text || ':' || e.payload::text, E'\n' order by e.day_index), '') from public.voyage_events e where e.voyage_id = p_voyage
$b$;

-- ── the raid arm, and the sea on one setting ──
do $$
begin
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_38;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language plpgsql stable
as $b$
declare
  v_s text := coalesce(current_setting('byeharu.proof_sea', true), '');
begin
  if v_s = 'REAL' then
    return query select * from voyage.hazard_roll_real_38(p_voyage, p_day);
    return;
  end if;
  return query select v_s <> '', nullif(v_s, ''), round(((p_day % 7) + 1) / 8.0, 6), 1::numeric;
end
$b$
  $f$;
end
$$;

do $$
declare
  c_uid constant uuid := '00000000-0330-4000-8000-000000000a01';
  v_f     uuid := pg_temp.house_0330(c_uid);
  v_voy   uuid;
  v_seas  int := (select count(*) from public.seas);
  v_bad   text;
  v_n     int;
  v_mag   numeric;
  v_want  numeric;
  v_quote numeric;
  v_d     int;
  r       record;
begin
  perform set_config('byeharu.proof_sea', 'REAL', true);
  if v_seas <> 51 then
    raise exception 'PROOF 38 FAIL: % seas, the slice is written for 51', v_seas;
  end if;
  if exists (select 1 from public.sea_pressure) then
    raise exception 'PROOF 38 FAIL: public.sea_pressure is not empty';
  end if;

  -- ── THE FIGURE ──
  select string_agg(s.code, ', ') into v_bad from public.seas s where voyage.sea_danger(s.id, now())::text <> s.piracy_index::text;
  if v_bad is not null then
    raise exception 'PROOF 38 FAIL: the danger of % is not its piracy_index', v_bad;
  end if;
  v_voy := voyage.depart(v_f, pg_temp.fifty_one(v_f), (select id from public.ports where code = 'LIS'), null, now());
  select string_agg(s.code, ', '), count(*) filter (where true) into v_bad, v_n
    from jsonb_array_elements((select v.path from public.voyages v where v.id = v_voy)) e
    join public.seas s on s.id = (e->>'sea_id')::uuid
   where e->>'danger' is distinct from s.piracy_index::text;
  if v_bad is not null then
    raise exception 'PROOF 38 FAIL: frozen on the wrong figure: %', v_bad;
  end if;
  if (select jsonb_array_length(v.path) from public.voyages v where v.id = v_voy) <> 51
     or (select count(distinct e->>'sea_id') from public.voyages v, jsonb_array_elements(v.path) e where v.id = v_voy) <> 51 then
    raise exception 'PROOF 38 FAIL: the voyage does not cross 51 seas';
  end if;
  raise notice 'PASS: SEA_FIGURE_51 — 51 seas, every figure and every frozen segment to the digit';

  -- ── THE MIX ──
  select string_agg(s.code, ', ') into v_bad from public.seas s
   where (select jsonb_agg(to_jsonb(m) order by m.cum_share) from pg_temp.old_mix(s.id) m)::text
         <> (select jsonb_agg(to_jsonb(m) order by m.cum_share) from voyage.sea_mix(s.id, voyage.sea_danger(s.id, now())) m)::text;
  if v_bad is not null then
    raise exception 'PROOF 38 FAIL: the mix of % moved', v_bad;
  end if;
  raise notice 'PASS: SEA_MIX_51 — 51 seas, byte for byte';

  -- ── THE ROLL, every day an event, so every day's kind is drawn from the mix ──
  update public.world_config set value = to_jsonb(1) where key = 'hazard_p_max';
  v_n := 0;
  for v_d in 1 .. 51 loop
    select * into r from voyage.hazard_roll(v_voy, v_d);
    if r.occurred is not true or r.kind is distinct from pg_temp.old_kind(v_voy, v_d, pg_temp.sea_at(v_d)) then
      raise exception 'PROOF 38 FAIL: day %: the roll is %, the old roll %', v_d, r.kind, pg_temp.old_kind(v_voy, v_d, pg_temp.sea_at(v_d));
    end if;
    if (voyage.leg_at_day(v_voy, v_d)->>'sea_id')::uuid <> pg_temp.sea_at(v_d) then
      raise exception 'PROOF 38 FAIL: day % is not in its own sea', v_d;
    end if;
    v_n := v_n + 1;
  end loop;
  raise notice 'PASS: SEA_ROLL_51 — % days, % kinds drawn, each the old roll', v_n,
    (select count(distinct pg_temp.old_kind(v_voy, g, pg_temp.sea_at(g))) from generate_series(1, 51) g);

  -- ── THE QUOTE: 0213's sum over the old mix ──
  select round(1 - exp(coalesce(sum(ln(greatest(1e-9, 1 - h.p_hazard
           * coalesce((select m.share from pg_temp.old_mix((voyage.leg_at_day(v_voy, g.d)->>'sea_id')::uuid) m where m.kind_code = 'PIRATES'), 0)
           * public.wc_num('insurance_raid_loss')))), 0)), 6)
    into v_quote
    from generate_series(1, voyage.total_days(v_voy)) g(d)
   cross join lateral voyage.hazard_roll(v_voy, g.d) h;
  if voyage.risk_quote(v_voy)::text <> v_quote::text then
    raise exception 'PROOF 38 FAIL: the quote is %, the old sum %', voyage.risk_quote(v_voy), v_quote;
  end if;
  raise notice 'PASS: SEA_QUOTE_51 — % to the digit', v_quote;

  -- ── THE PANEL ──
  select count(*) into v_n from jsonb_array_elements(voyage.waters_ahead(v_voy)) w
    join public.seas s on s.code = w->>'sea'
   where (w->'mix')::text = (select jsonb_object_agg(m.kind_code, m.share) from pg_temp.old_mix(s.id) m)::text;
  if v_n <> 51 then
    raise exception 'PROOF 38 FAIL: the panel shows the old mix for % of 51 waters', v_n;
  end if;
  raise notice 'PASS: SEA_WATERS_51 — 51 waters';

  -- ── THE RAID: a real settle, a day in each sea ──
  perform set_config('byeharu.proof_sea', 'PIRATES', true);
  for v_d in 1 .. 51 loop
    perform voyage.settle(v_f, voyage.day_ends_at(v_voy, v_d));
    update public.ships s set durability = 10000, crew = 40, water_t = 100000, food_t = 100000 where s.fleet_id = v_f;
  end loop;
  v_n := 0;
  for r in select e.day_index, e.kind, e.payload from public.voyage_events e where e.voyage_id = v_voy order by e.day_index loop
    continue when r.day_index > 51;
    v_mag  := round(((r.day_index % 7) + 1) / 8.0, 6);
    v_want := round((select s.piracy_index from public.seas s where s.id = pg_temp.sea_at(r.day_index)) * 40 * (0.5 + v_mag), 2);
    if r.kind <> 'PIRATES' or (r.payload->>'raider')::numeric <> v_want or r.payload->>'raider' <> v_want::text then
      raise exception 'PROOF 38 FAIL: day %: % raider %, the old strength %', r.day_index, r.kind, r.payload->>'raider', v_want;
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n <> 51 then
    raise exception 'PROOF 38 FAIL: % raids of 51', v_n;
  end if;
  raise notice 'PASS: SEA_RAID_51 — 51 raids at the old strength, to the digit';
  perform set_config('byeharu.proof_sea', '', true);
end
$$;

-- ── PRESSURE, and what it may not touch ──
do $$
declare
  c_uid constant uuid := '00000000-0330-4000-8000-000000000a02';
  v_f     uuid := pg_temp.house_0330(c_uid);
  v_f2    uuid := pg_temp.house_0330('00000000-0330-4000-8000-000000000a03');
  v_sea   uuid;
  v_p     numeric;
  v_voy   uuid;
  v_voy2  uuid;
  v_seg   jsonb;
  v_q0    numeric;
  v_w0    text;
  v_m0    text;
  v_at    timestamptz := now();
  r       record;
begin
  select s.id, s.piracy_index into v_sea, v_p from public.seas s where s.danger_level >= 3 order by s.piracy_index desc, s.code limit 1;

  insert into public.sea_pressure (sea_id, value, updated_at) values (v_sea, 0.5, v_at);
  if voyage.sea_danger(v_sea, v_at) <> round(least(1, v_p * 1.5), 4) then
    raise exception 'PROOF 38 FAIL: a win is not read';
  end if;
  if voyage.sea_danger(v_sea, v_at + interval '10 hours') <> round(least(1, v_p * (1 + 0.5 * power(0.9::numeric, 10))), 4) then
    raise exception 'PROOF 38 FAIL: it does not decay at the knob';
  end if;
  update public.world_config set value = to_jsonb(0.5) where key = 'sea_pressure_decay';
  if voyage.sea_danger(v_sea, v_at + interval '1 hour') <> round(least(1, v_p * 1.25), 4) then
    raise exception 'PROOF 38 FAIL: the decay is not the knob';
  end if;
  update public.world_config set value = to_jsonb(0.9) where key = 'sea_pressure_decay';
  if voyage.sea_danger(v_sea, v_at + interval '30 years')::text <> v_p::text then
    raise exception 'PROOF 38 FAIL: thirty years on, the sea has not gone home: %', voyage.sea_danger(v_sea, v_at + interval '30 years');
  end if;
  if voyage.sea_danger(v_sea, v_at - interval '1 hour') <> voyage.sea_danger(v_sea, v_at) then
    raise exception 'PROOF 38 FAIL: pressure grew into the past';
  end if;
  if voyage.sea_danger(v_sea, null)::text <> v_p::text then
    raise exception 'PROOF 38 FAIL: a null moment is not the sea as authored';
  end if;
  update public.sea_pressure set value = -3 where sea_id = v_sea;
  if voyage.sea_danger(v_sea, v_at) <> 0 then
    raise exception 'PROOF 38 FAIL: under 0';
  end if;
  update public.sea_pressure set value = 100 where sea_id = v_sea;
  if voyage.sea_danger(v_sea, v_at) <> 1 then
    raise exception 'PROOF 38 FAIL: over 1';
  end if;
  if voyage.sea_danger('00000000-0000-4000-8000-000000000000', v_at) <> 0 or voyage.sea_danger(null, v_at) <> 0 then
    raise exception 'PROOF 38 FAIL: no sea has a danger';
  end if;
  raise notice 'PASS: SEA_PRESSURE — % at 0.5 pressure, decays by the knob, clamps, goes home', voyage.sea_danger(v_sea, v_at + interval '1 day');
  delete from public.sea_pressure;

  -- FROZEN: she leaves, then the sea changes
  update public.world_config set value = to_jsonb(1) where key = 'hazard_p_max';
  perform set_config('byeharu.proof_sea', 'REAL', true);
  v_seg := jsonb_build_array(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', round(voyage.fleet_speed(v_f) * 24 * 12, 2), 'sea_id', v_sea, 'hazard_mult', 1000));
  v_voy := voyage.depart(v_f, v_seg, (select id from public.ports where code = 'LIS'), null, now());
  v_q0  := voyage.risk_quote(v_voy);
  v_w0  := voyage.waters_ahead(v_voy)::text;
  select string_agg(h.kind, ',') into v_m0 from generate_series(1, 12) g cross join lateral voyage.hazard_roll(v_voy, g) h;

  insert into public.sea_pressure (sea_id, value, updated_at) values (v_sea, 1.2, now());
  if voyage.sea_danger(v_sea, now()) = v_p then
    raise exception 'PROOF 38 FAIL: the probe moved nothing';
  end if;
  if voyage.risk_quote(v_voy) <> v_q0 or voyage.waters_ahead(v_voy)::text <> v_w0
     or (select string_agg(h.kind, ',') from generate_series(1, 12) g cross join lateral voyage.hazard_roll(v_voy, g) h) <> v_m0 then
    raise exception 'PROOF 38 FAIL: pressure after she left moved what she rolls, is quoted or is shown';
  end if;
  v_voy2 := voyage.depart(v_f2, v_seg, (select id from public.ports where code = 'LIS'), null, now());
  if (select (v.path->0->>'danger')::numeric from public.voyages v where v.id = v_voy2) <> voyage.sea_danger(v_sea, now()) then
    raise exception 'PROOF 38 FAIL: a voyage leaving under pressure did not freeze it';
  end if;
  if voyage.risk_quote(v_voy2) <= v_q0 then
    raise exception 'PROOF 38 FAIL: a dearer sea did not quote dearer: % against %', voyage.risk_quote(v_voy2), v_q0;
  end if;
  if (select (w->'mix')::text from jsonb_array_elements(voyage.waters_ahead(v_voy2)) w limit 1)
     = (select (w->'mix')::text from jsonb_array_elements(v_w0::jsonb) w limit 1) then
    raise exception 'PROOF 38 FAIL: the mix does not move with the frozen figure';
  end if;
  raise notice 'PASS: SEA_FROZEN — left at %, the sea went to %, she rolls and is quoted as she left; the next ship carries it', v_p, voyage.sea_danger(v_sea, now());
  delete from public.sea_pressure;

  -- THE LEGACY LEG: a voyage written before 0330 has no figure
  update public.voyages v set path = (select jsonb_agg(e - 'danger') from jsonb_array_elements(v.path) e) where v.id = v_voy;
  if voyage.risk_quote(v_voy) <> v_q0 or voyage.waters_ahead(v_voy)::text <> v_w0 then
    raise exception 'PROOF 38 FAIL: a leg with no figure does not read as the sea as authored';
  end if;
  if voyage.leg_danger(voyage.leg_at_day(v_voy, 1))::text <> v_p::text then
    raise exception 'PROOF 38 FAIL: the leg reads %, not %', voyage.leg_danger(voyage.leg_at_day(v_voy, 1)), v_p;
  end if;
  perform set_config('byeharu.proof_sea', 'PIRATES', true);
  perform voyage.settle(v_f, voyage.day_ends_at(v_voy, 1));
  if (select (e.payload->>'raider')::numeric from public.voyage_events e where e.voyage_id = v_voy and e.day_index = 1)
     <> round(v_p * 40 * (0.5 + round(2 / 8.0, 6)), 2) then
    raise exception 'PROOF 38 FAIL: a raid on a leg with no figure is not the old strength';
  end if;
  raise notice 'PASS: SEA_LEGACY — no figure on the leg reads %, in the roll, the raid, the quote and the panel', v_p;
  perform set_config('byeharu.proof_sea', '', true);
end
$$;

-- ── LATE AND ON TIME: one voyage settled twice, the pressure moved between ──
do $$
declare
  v_f     uuid := pg_temp.house_0330('00000000-0330-4000-8000-000000000a04');
  v_sea   uuid;
  v_seg   jsonb;
  v_voy   uuid;
  v_late  text;
  v_on    text;
  v_d     int;
begin
  update public.world_config set value = to_jsonb(1) where key = 'hazard_p_max';
  perform set_config('byeharu.proof_sea', 'REAL', true);
  select s.id into v_sea from public.seas s where s.danger_level >= 3 order by s.piracy_index desc, s.code limit 1;
  v_seg := jsonb_build_array(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', round(voyage.fleet_speed(v_f) * 24 * 8, 2), 'sea_id', v_sea, 'hazard_mult', 1000));
  v_voy := voyage.depart(v_f, v_seg, (select id from public.ports where code = 'LIS'), null, now());
  update public.ships s set water_t = 100000, food_t = 100000 where s.fleet_id = v_f;

  -- late: every day at once, the sea quiet
  begin
    perform voyage.settle(v_f, now() + interval '1 year');
    raise exception 'late' using errcode = 'ZY330', detail = pg_temp.days(v_voy);
  exception when sqlstate 'ZY330' then
    get stacked diagnostics v_late = pg_exception_detail;
  end;

  -- on time: a day at a time, the sea made furious, then calm, between them
  for v_d in 1 .. 200 loop
    exit when (select v.status from public.voyages v where v.id = v_voy) <> 'SAILING'
           or (select v.last_settled_day from public.voyages v where v.id = v_voy) >= voyage.total_days(v_voy);
    insert into public.sea_pressure (sea_id, value, updated_at) values (v_sea, 2, now()) on conflict (sea_id) do update set value = -public.sea_pressure.value;
    perform voyage.settle(v_f, voyage.day_ends_at(v_voy, (select v.last_settled_day + 1 from public.voyages v where v.id = v_voy)));
  end loop;
  perform voyage.settle(v_f, now() + interval '1 year');
  v_on := pg_temp.days(v_voy);

  if v_late = '' or v_late <> v_on then
    raise exception E'PROOF 38 FAIL: late and on time differ.\nLATE %\nON TIME %', v_late, v_on;
  end if;
  delete from public.sea_pressure;
  perform set_config('byeharu.proof_sea', '', true);
  raise notice 'PASS: SEA_LATE — % bytes of days, equal, with the sea moved between each', length(v_on);
end
$$;

-- ── A TURN ──
do $$
declare
  c_uid constant uuid := '00000000-0330-4000-8000-000000000a05';
  v_f     uuid := pg_temp.house_0330(c_uid);
  v_voy   uuid;
  v_seg   jsonb;
  v_first jsonb;
  v_sea   uuid;
  v_x     jsonb;
  v_onw   uuid;
  v_at0   text;
  pos     record;
begin
  perform set_config('byeharu.proof_sea', '', true);
  v_x := cmd.do_sail(v_f, jsonb_build_object('dest', (select id from public.ports where code = 'FNC'),
           'path', (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                      from public.sea_reaches a, public.sea_reaches b
                     where a.port_id = (select id from public.ports where code = 'LIS') and b.port_id = (select id from public.ports where code = 'FNC'))));
  v_voy := (v_x->>'voyage_id')::uuid;
  if v_voy is null then
    raise exception 'PROOF 38 FAIL: the turn''s voyage did not sail: %', v_x;
  end if;
  if exists (select 1 from public.voyages v, jsonb_array_elements(v.path) e where v.id = v_voy and not e ? 'danger') then
    raise exception 'PROOF 38 FAIL: cmd.do_sail left a segment unfrozen';
  end if;
  update public.voyages v set departed_at = v.departed_at - (v.eta - v.departed_at) / 2, eta = v.eta - (v.eta - v.departed_at) / 2 where v.id = v_voy;
  v_first := (select v.path->0 from public.voyages v where v.id = v_voy);
  v_sea   := (v_first->>'sea_id')::uuid;

  -- the sea moves, then she turns where she lies, on to a point further along the water she was on
  insert into public.sea_pressure (sea_id, value, updated_at) values (v_sea, 0.5, now());
  select * into pos from voyage.position(v_voy, now());
  select v.path->pos.seg_index into v_seg from public.voyages v where v.id = v_voy;
  perform cmd.assume_identity(c_uid);
  v_x := cmd.divert(v_f, null, jsonb_build_object('lat', v_seg->'b'->0, 'lon', v_seg->'b'->1),
                    jsonb_build_array(jsonb_build_array(pos.lat, pos.lon), v_seg->'b'));
  if coalesce(v_x->>'ok', 'false') <> 'true' then
    raise exception 'PROOF 38 FAIL: the turn was refused: %', v_x;
  end if;

  if (select v.path->0->>'danger' from public.voyages v where v.id = v_voy) is distinct from v_first->>'danger' then
    raise exception 'PROOF 38 FAIL: the turn rewrote the sailed water';
  end if;
  if exists (select 1 from public.voyages v, jsonb_array_elements(v.path) e where v.id = v_voy and not e ? 'danger') then
    raise exception 'PROOF 38 FAIL: the kept water lost its figure';
  end if;
  select v.id into v_onw from public.voyages v where v.fleet_id = v_f and v.status = 'SAILING';
  if v_onw is null or v_onw = v_voy then
    raise exception 'PROOF 38 FAIL: no onward voyage';
  end if;
  v_at0 := (select v.path->0->>'danger' from public.voyages v where v.id = v_onw);
  if (select v.path->0->>'sea_id' from public.voyages v where v.id = v_onw) = v_sea::text and v_at0::numeric <> voyage.sea_danger(v_sea, (select v.departed_at from public.voyages v where v.id = v_onw)) then
    raise exception 'PROOF 38 FAIL: the onward water is not frozen at the turn: %', v_at0;
  end if;
  if v_at0 is null then
    raise exception 'PROOF 38 FAIL: the onward water has no figure';
  end if;
  delete from public.sea_pressure;
  raise notice 'PASS: SEA_DIVERT — kept water %, onward water %', v_first->>'danger', v_at0;
end
$$;

-- ── THE LEVEL ──
do $$
declare
  v_sea  uuid;
  v_p    numeric;
  v_lvl  int;
  v_low  uuid;
  v_top  uuid;
  v_got  int;
  v_mix  numeric;
begin
  if exists (select 1 from jsonb_to_recordset(world.sea_danger()) x(sea_code text, level int, reason text) join public.seas s on s.code = x.sea_code where x.level <> s.danger_level or x.reason is not null)
     or jsonb_array_length(world.sea_danger()) <> 51 then
    raise exception 'PROOF 38 FAIL: the served levels are not the authored ones';
  end if;
  -- a 0.2000 sea, danger level 2 or 3: band 1. Up to 0.2400 stays; 0.2500 is one step; 0.4000 two.
  select s.id, s.piracy_index, s.danger_level into v_sea, v_p, v_lvl from public.seas s where s.piracy_index = 0.2 and s.danger_level between 2 and 3 order by s.code limit 1;
  if v_sea is null then
    raise exception 'PROOF 38 FAIL: no 0.2000 sea at level 2 or 3';
  end if;
  insert into public.sea_pressure (sea_id, value, updated_at) values (v_sea, 0.2, now());   -- 0.2400
  select x.level into v_got from jsonb_to_recordset(world.sea_danger()) x(sea_code text, level int) join public.seas s on s.code = x.sea_code and s.id = v_sea;
  if v_got <> v_lvl then
    raise exception 'PROOF 38 FAIL: 0.24 crossed no band, and the level moved to %', v_got;
  end if;
  update public.sea_pressure set value = 0.25, updated_at = now() where sea_id = v_sea;   -- 0.2500
  select x.level into v_got from jsonb_to_recordset(world.sea_danger()) x(sea_code text, level int) join public.seas s on s.code = x.sea_code and s.id = v_sea;
  if v_got <> v_lvl + 1 then
    raise exception 'PROOF 38 FAIL: 0.25 is one band up, and the level is %', v_got;
  end if;
  update public.sea_pressure set value = 1, updated_at = now() where sea_id = v_sea;   -- 0.4000
  select x.level into v_got from jsonb_to_recordset(world.sea_danger()) x(sea_code text, level int) join public.seas s on s.code = x.sea_code and s.id = v_sea;
  if v_got <> v_lvl + 2 then
    raise exception 'PROOF 38 FAIL: 0.40 is two bands up, and the level is %', v_got;
  end if;
  update public.sea_pressure set value = -0.8, updated_at = now() where sea_id = v_sea;   -- 0.0400: under the first band, one step down
  select x.level into v_got from jsonb_to_recordset(world.sea_danger()) x(sea_code text, level int) join public.seas s on s.code = x.sea_code and s.id = v_sea;
  if v_got <> v_lvl - 1 then
    raise exception 'PROOF 38 FAIL: 0.04 is one band down, and the level is %', v_got;
  end if;
  delete from public.sea_pressure;

  -- the scale's two ends hold
  select s.id into v_top from public.seas s where s.danger_level = 5 order by s.code limit 1;
  select s.id into v_low from public.seas s where s.danger_level = 1 order by s.code limit 1;
  insert into public.sea_pressure (sea_id, value, updated_at) values (v_top, 100, now()), (v_low, -100, now());
  if exists (select 1 from jsonb_to_recordset(world.sea_danger()) x(sea_code text, level int) where x.level not between 1 and 5) then
    raise exception 'PROOF 38 FAIL: a level left the scale';
  end if;
  delete from public.sea_pressure;
  raise notice 'PASS: SEA_LEVEL — level % stays at 0.24, moves at each band, and holds to 1 to 5', v_lvl;
end
$$;

-- ── ONE READER, NO CLIENT ──
do $$
declare
  v_bad text;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%piracy_index%' and p.oid <> 'voyage.sea_danger(uuid,timestamp with time zone)'::regprocedure;
  if v_bad is not null then
    raise exception 'PROOF 38 FAIL: a second reader of piracy_index: %', v_bad;
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'voyage.sea_danger(uuid,timestamp with time zone)'::regprocedure and p.prosrc like '%piracy_index%') then
    raise exception 'PROOF 38 FAIL: the scan cannot see the one reader';
  end if;
  if exists (select 1 from pg_views v where v.schemaname in ('public', 'cmd', 'world', 'voyage') and v.definition like '%piracy_index%') then
    raise exception 'PROOF 38 FAIL: a view reads piracy_index';
  end if;
  if to_regprocedure('voyage.sea_mix(uuid)') is not null then
    raise exception 'PROOF 38 FAIL: the old mix is still standing';
  end if;
  raise notice 'PASS: SEA_ONE_READER — voyage.sea_danger alone';

  if exists (select 1 from unnest(array['voyage.sea_danger(uuid,timestamp with time zone)', 'voyage.freeze_danger(jsonb,timestamp with time zone)', 'voyage.leg_danger(jsonb)', 'voyage.sea_band(numeric)', 'voyage.sea_mix(uuid,numeric)', 'world.sea_danger()']) f
              where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute')) then
    raise exception 'PROOF 38 FAIL: a client can call what is new';
  end if;
  if has_table_privilege('anon', 'public.sea_pressure', 'select') or has_table_privilege('authenticated', 'public.sea_pressure', 'select')
     or has_table_privilege('authenticated', 'public.sea_pressure', 'insert') then
    raise exception 'PROOF 38 FAIL: a client can reach public.sea_pressure';
  end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.sea_pressure'::regclass) then
    raise exception 'PROOF 38 FAIL: public.sea_pressure has no row security';
  end if;
  if exists (select 1 from public.sea_pressure) then
    raise exception 'PROOF 38 FAIL: public.sea_pressure is not empty';
  end if;
  -- THE one writer, by its signature: public.pirate_pressure_write(timestamp with time zone) (0339, W17: a pirate ship's presence in a sea; docs/WORLD_POWERS.md 7.6). Any other fails here.
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc ~* '(insert into|update|delete from)\s+public\.sea_pressure'
     and p.oid is distinct from to_regprocedure('public.pirate_pressure_write(timestamp with time zone)');   -- by oid: regprocedure's text drops the schema on the search path
  if v_bad is not null then
    raise exception 'PROOF 38 FAIL: something other than public.pirate_pressure_write writes public.sea_pressure: %', v_bad;
  end if;
  raise notice 'PASS: SEA_NO_CLIENT — closed, empty, written by pirate_pressure_write alone';
end
$$;

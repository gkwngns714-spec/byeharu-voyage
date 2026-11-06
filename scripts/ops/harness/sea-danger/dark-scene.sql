-- 0330 DARK PARITY SCENE: run by proof-0330.mjs on the world BEFORE the file and AFTER it, rolled back each time. It names only what existed before 0330.
-- Two voyages with fixed ids, so their rolls are the same streams, on two hulls of the built world, so their rolled stats are the same. Each sails all 51 seas, one sea a day, every day an event, through the REAL
-- voyage.settle, voyage.fight, voyage.hazard_roll and voyage.sea_mix. The first meets the real mix. The second has a catalogue that breeds nearly only raiders, so every sea is fought in.
-- Each day's kind and payload, each quote and the panel's mix are printed. Every SCENE line must be equal, byte for byte.
do $$
declare
  c_voy  constant uuid[] := array['30000000-0000-4000-8000-000000000330'::uuid, '30000000-0000-4000-8000-000000000331'::uuid];
  v_fls  uuid[];
  v_fl   uuid;
  v_voy  uuid;
  v_spd  numeric;
  v_segs jsonb;
  v_pass int;
  v_d    int;
  v_stat text;
  v_day  int;
  r      record;
begin
  update public.world_config set value = to_jsonb(1) where key = 'hazard_p_max';
  select array_agg(x.fleet_id) into v_fls
    from (select nf.fleet_id from public.npc_fleets nf
           where not exists (select 1 from public.voyages v where v.fleet_id = nf.fleet_id and v.status = 'SAILING')
           order by nf.roster_ord limit 2) x;
  if coalesce(array_length(v_fls, 1), 0) <> 2 then
    raise exception 'the scene found no two idle hulls';
  end if;

  for v_pass in 1 .. 2 loop
    v_fl  := v_fls[v_pass];
    v_voy := c_voy[v_pass];
    if v_pass = 2 then
      update public.voyage_event_kinds set mix_base = case when code = 'PIRATES' then 1 else 0.0001 end where in_sea_mix;
    end if;
    update public.ships s set durability = 10000, crew = 40, water_t = 100000, food_t = 100000 where s.fleet_id = v_fl;
    update public.fleets f set status = 'DOCKED', busy_until = null where f.id = v_fl;
    -- one segment a sea, one voyage-day long, so day d is in sea d
    v_spd := voyage.fleet_speed(v_fl);
    select jsonb_agg(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', round(v_spd * 24, 2), 'sea_id', s.id, 'hazard_mult', 1000) order by s.code)
      into v_segs from public.seas s;
    perform voyage.depart(v_fl, v_segs, null, null, now() + interval '1 hour');   -- ahead of the clock, so the panel reads every water in every run
    update public.voyages set id = v_voy where fleet_id = v_fl and status = 'SAILING';

    raise notice 'SCENE: % quote %', v_pass, voyage.risk_quote(v_voy);
    raise notice 'SCENE: % waters %', v_pass, (select jsonb_agg(jsonb_build_array(w->>'sea', w->'mix') order by w->>'sea') from jsonb_array_elements(voyage.waters_ahead(v_voy)) w);

    -- day by day, her hull and crew made good each day: this scene is the rolls, not her survival
    for v_d in 1 .. 400 loop
      select v.status, v.last_settled_day into v_stat, v_day from public.voyages v where v.id = v_voy;
      exit when v_stat <> 'SAILING';
      perform voyage.settle(v_fl, greatest(voyage.day_ends_at(v_voy, v_day + 1), (select v.eta from public.voyages v where v.id = v_voy and v_day + 1 > voyage.total_days(v.id))));
      update public.ships s set durability = 10000, crew = 40, water_t = 100000, food_t = 100000 where s.fleet_id = v_fl;
    end loop;
    for r in select e.day_index, e.kind, e.payload from public.voyage_events e where e.voyage_id = v_voy order by e.day_index loop
      raise notice 'SCENE: % day % % %', v_pass, r.day_index, r.kind, r.payload;
    end loop;
    raise notice 'SCENE: % status % days % raids %', v_pass, v_stat, v_day,
      (select count(*) from public.voyage_events e where e.voyage_id = v_voy and e.kind = 'PIRATES');
  end loop;

  raise exception using errcode = 'ZY330';
exception when sqlstate 'ZY330' then
  null;
end
$$;

-- 0340 DARK PARITY SCENE: run by proof-0340.mjs on the world BEFORE the file and AFTER it, rolled back each time, beside the navy (0331) and navy-comes (0333) scenes.
-- It covers what 0340 cuts that those do not reach, in BOTH darks: the navy off (a ship's step, the job's answer, her card's keys) and the navy on with the pirates off (she patrols, the job's answer has the keys it had,
-- her card the keys it had), and a PROBE battle's hulls written by the lifted statement (the outcome is seeded by the battle's random id, so what is compared is that hull was lost on a side and never grew). It names only
-- what existed before 0340 (W17's switch included: the pirates are off throughout).
do $$
declare
  c_uid constant uuid := '00000000-0340-4000-8000-0000000000aa';
  v_t   timestamptz := now();
  v_nat uuid;
  v_cap uuid;
  v_n   uuid;
  v_p   uuid;
  v_f   uuid;
  v_m   uuid;
  v_b   uuid;
  v_h0  numeric;
  v_h1  numeric;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('navy_enabled', 'pirates_bite', 'attack_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 90000000, reserve = 0;
  select g.nation_id, p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where n.code = 'PRT';
  insert into public.navy_realms (nation_id, ships, read_at) values (v_nat, 3, v_t) on conflict (nation_id) do update set ships = 3, read_at = v_t;
  v_n := public.navy_commission(v_nat, 1, v_cap, public.refit_yard(v_cap), v_cap, v_t);

  -- BOTH OFF: the job's whole answer, her step, her card's keys and her row
  raise notice 'SCENE: job off %', public.tick_navy(v_t, v_nat);
  raise notice 'SCENE: step off %', public.navy_ship_step(v_n, v_t);
  raise notice 'SCENE: card off %', (select jsonb_agg(k order by k) from jsonb_object_keys(world.navy_ship_card(v_n)) k);
  raise notice 'SCENE: row off %', (select jsonb_build_array(x.mission, x.laid_up_at is not null, x.patrol is null) from public.navy_ships x where x.fleet_id = v_n);

  -- NAVY ON, PIRATES OFF: she wakes, her stations and first patrol are planned, she patrols; the job's answer keys; her card's keys
  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';
  update public.navy_ships x set laid_up_at = null where x.fleet_id = v_n;
  perform public.navy_plan_step(v_t, v_nat);
  perform public.navy_plan_step(v_t, v_nat);
  raise notice 'SCENE: job on %', (select jsonb_agg(k order by k) from jsonb_object_keys(public.tick_navy(v_t, v_nat)) k);
  raise notice 'SCENE: ship on %', (select jsonb_build_array(x.mission, x.patrol is not null, x.leg, f.status) from public.navy_ships x join public.fleets f on f.id = x.fleet_id where x.fleet_id = v_n);
  raise notice 'SCENE: card on %', (select jsonb_agg(k order by k) from jsonb_object_keys(world.navy_ship_card(v_n)) k);
  raise notice 'SCENE: step on %', public.navy_ship_step(v_n, v_t);   -- AWAY: she sailed

  -- A PROBE BATTLE through the real bodies: a company's fleet against a merchant at anchor; hull is lost on a side and never grows
  v_p := public.new_house(c_uid, 'Casa Cena 0340', 'PRT', 'LIS', 'Cena', (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1), 'Cena', null, false);
  select id into v_f from public.fleets where player_id = v_p;
  update public.ships set crew = 100 where fleet_id = v_f;
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  select nf.fleet_id into v_m from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.status = 'DOCKED' order by nf.roster_ord limit 1;
  update public.fleets set status = 'ANCHORED', port_id = null, lat = 10, lon = -30 where id in (v_f, v_m);
  select sum(s.durability) into v_h0 from public.ships s where s.fleet_id in (v_f, v_m);
  v_b := public.battle_open('PROBE', v_f, v_m, v_t);
  raise notice 'SCENE: resolve %', public.battle_resolve(v_b, v_t + interval '601 seconds');
  select sum(s.durability) into v_h1 from public.ships s where s.fleet_id in (v_f, v_m);
  raise notice 'SCENE: hulls % %', v_h1 <= v_h0, (select jsonb_build_array(b.status, b.result ? 'hull_lost', b.result ? 'outcome') from public.battles b where b.id = v_b);
  raise notice 'SCENE: hull sum % %', (select count(*) from public.ships s where s.fleet_id in (v_f, v_m) and s.durability < 0), (select jsonb_build_array(f.status, f.busy_until) from public.fleets f where f.id = v_f);

  raise exception using errcode = 'ZY341';
exception when sqlstate 'ZY341' then
  null;
end
$$;

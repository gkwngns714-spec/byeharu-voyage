-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 227 - SEA EXPEDITIONS  (migration 0523; docs/design/rounds-2026-11-25.md section 4.2)
--
--   Its own company, its own capital's purse. Rolled back by proof.mjs.
--
-- @pass SE_OPEN   dark: the work is not served and refused; lit: served with its cost
-- @pass SE_LEVEL  a higher Exploration loses fewer hands; from 8 a round eats half as much and the run is longer
-- @pass SE_GOLD   the run over: the gold of its rounds out of her capital's purse; every company and every city: the sum moves 0; Reputation a round
-- @pass SE_OWED   a realm that cannot pay: nothing is minted; it waits with her and is paid at the end of the next run
-- ══════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  c_a constant uuid := '00000000-0227-4000-8000-0000000000a1';
  v_a uuid; v_f uuid; v_cap uuid; t1 jsonb; t2 jsonb; s0 numeric; s1 numeric; d0 bigint; v_c jsonb;
begin
  v_a := public.new_house(c_a, 'Casa da Prova 227', 'PRT');
  select f.id into v_f from public.fleets f where f.player_id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('rounds_enabled', 'city_treasury_enabled', 'reputation_on', 'ship_stores_separate', 'economy_closed');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  perform cmd.assume_identity(c_a);
  update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 3, water_t = 4 where s.fleet_id = v_f;
  if exists (select 1 from jsonb_array_elements(world.rounds(v_f)->'works') e where e->>'work' = 'expedition') or cmd.round_send(v_f, 'expedition', '{}')->>'error_code' <> 'E_NOT_IN_USE' then
    raise exception 'SE_OPEN dark';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'expedition_rounds_enabled';
  if not exists (select 1 from jsonb_array_elements(world.rounds(v_f)->'works') e where e->>'work' = 'expedition' and (e #>> '{terms,food}')::numeric > 0) then
    raise exception 'SE_OPEN lit';
  end if;
  raise notice 'PASS: SE_OPEN - refused dark, served lit';
  t1 := public.round_terms(v_f, 'expedition', '{"days": 0}');
  insert into public.house_level_marks (player_id, track, level) values (v_a, 'exploration', 8) on conflict (player_id, track) do update set level = 8;
  t2 := public.round_terms(v_f, 'expedition', '{"days": 0}');
  if (t2->>'crew')::numeric >= (t1->>'crew')::numeric or (t2->>'most')::int < 2 * (t1->>'most')::int - 1 then
    raise exception 'SE_LEVEL: % %', t1, t2;
  end if;
  raise notice 'PASS: SE_LEVEL - level 1: % rounds, % hands a round; level 8: %, %', t1->>'most', t1->>'crew', t2->>'most', t2->>'crew';

  v_cap := (select h.id from public.ports h join public.nations n on n.capital_port_code = h.code join public.players p on p.nation_id = n.id where p.id = v_a and h.kind = 'HARBOUR');
  -- the realm has nothing
  update public.port_treasury t set ducats = 0 where public.port_nation(t.port_id) = (select p.nation_id from public.players p where p.id = v_a) or t.port_id = v_cap;
  update public.ships s set food_t = 30, water_t = 40 where s.fleet_id = v_f;
  perform cmd.round_send(v_f, 'expedition', '{"rounds": 4, "days": 0}');
  s0 := (select sum(p.ducats) from public.players p) + (select sum(public.treasury_balance(p.id)) from public.ports p where p.kind = 'HARBOUR');
  d0 := (select p.ducats from public.players p where p.id = v_a);
  perform public.round_settle(v_f, now() + interval '2 hours');
  s1 := (select sum(p.ducats) from public.players p) + (select sum(public.treasury_balance(p.id)) from public.ports p where p.kind = 'HARBOUR');
  v_c := (select zr.carry from public.round_runs zr where zr.fleet_id = v_f);
  if s1 <> s0 or (select p.ducats from public.players p where p.id = v_a) <> d0 or (v_c->>'gold_due')::int is distinct from 3388 then
    raise exception 'SE_OWED: % %', s1 - s0, v_c;
  end if;
  -- and now it can
  update public.port_treasury t set ducats = 100000000 where t.port_id = v_cap;
  perform public.round_send_for(v_a, v_f, 'expedition', '{"rounds": 4, "days": 0}', now() + interval '2 seconds');
  s0 := (select sum(p.ducats) from public.players p) + (select sum(public.treasury_balance(p.id)) from public.ports p where p.kind = 'HARBOUR');
  perform public.round_settle(v_f, now() + interval '2 hours');
  s1 := (select sum(p.ducats) from public.players p) + (select sum(public.treasury_balance(p.id)) from public.ports p where p.kind = 'HARBOUR');
  v_c := (select zr.carry from public.round_runs zr where zr.fleet_id = v_f);
  if s1 <> s0 or (select p.ducats from public.players p where p.id = v_a) - d0 <> 6776 or v_c ? 'gold_due'
     or (select sum(b.delta) from public.reputation_book b where b.player_id = v_a and b.kind = 'round') is distinct from 16 then
    raise exception 'SE_GOLD: % % %', s1 - s0, (select p.ducats from public.players p where p.id = v_a) - d0, v_c;
  end if;
  -- called in after two rounds: their gold
  perform public.round_send_for(v_a, v_f, 'expedition', '{"rounds": 4, "days": 0}', now() + interval '4 seconds');
  perform public.round_home_for(v_a, v_f, now() + interval '31 minutes');
  if (select p.ducats from public.players p where p.id = v_a) - d0 <> 8470 then raise exception 'SE_GOLD: called in: %', (select p.ducats from public.players p where p.id = v_a) - d0; end if;
  raise notice 'PASS: SE_OWED - 120 waited, nothing minted';
  raise notice 'PASS: SE_GOLD - 6776 from the capital, the sum moved 0; 16 Reputation for 8 rounds';
end $p$;

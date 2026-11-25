-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 214 - EVERY COMPANY HAS AN HQ  (migration 0509; docs/dev-log/2026-11-25-restart-company.md)
--   The owner, 2026-11-25 (R1): "Right now my account does not have a designated HQ." Rolled back by proof.mjs. No step reads the clock.
--
-- @pass HQ_FIRST     a founded company's HQ slot 1 is her country's capital, for every country a company may sail for; a merchants' house has none
-- @pass HQ_STAYS     the HQ served is hers whatever her fleets do: sailed away, none left; a change of country moves it not
-- @pass HQ_LIST      the list is every HQ of hers in slot order; the same city twice and a sixth slot are refused; a house with none is served an empty list
-- @pass HQ_DARK      dark: no next HQ is served, no door opens one, and home is the founding port; lit, home is slot 1 and the next step is the ladder's row
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a constant uuid := '00000000-0509-4000-8000-0000000003a1';
  v_lis uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_lon uuid := (select p.id from public.ports p where p.code = 'LON');
  v_a uuid; v_n uuid; x record; v_r jsonb; i int := 0;
begin
  for x in select n.code, n.capital_port_code as cap from public.nations n where public.nation_joinable(n.id) order by n.code loop
    i := i + 1;
    perform cmd.assume_identity(('00000000-0509-4000-8000-0000000004' || lpad(i::text, 2, '0'))::uuid);
    v_r := cmd.found_house('Casa Prova 214 ' || i, x.code);
    if not (v_r->>'ok')::boolean or world.player()->'player'->'hq'->>'at' is distinct from x.cap then
      raise exception 'HQ_FIRST: % %', x.code, v_r;
    end if;
  end loop;
  v_n := public.new_house(null, 'Casa Mercante 214', 'PRT', 'LIS', p_is_npc => true);
  if i < 6 or exists (select 1 from public.company_hqs h where h.player_id = v_n) then
    raise exception 'HQ_FIRST: % countries, or a merchant has one', i;
  end if;
  raise notice 'PASS: HQ_FIRST — % countries', i;

  v_a := public.new_house(c_a, 'Casa Sede 214', 'PRT');
  perform cmd.assume_identity(c_a);
  update public.fleets set port_id = v_lon where player_id = v_a;
  if world.player()->'player'->'hq'->>'at' <> 'LIS' or world.player()->'player'->>'lying_at' <> 'LON' then raise exception 'HQ_STAYS: sailed away'; end if;
  v_r := cmd.change_country('ENG');
  if not (v_r->>'ok')::boolean or world.player()->'player'->'hq'->>'at' <> 'LIS' then raise exception 'HQ_STAYS: a change of country (%)', v_r; end if;
  delete from public.fleets where player_id = v_a;
  if world.player()->'player'->'hq'->>'at' <> 'LIS' then raise exception 'HQ_STAYS: no fleet'; end if;
  raise notice 'PASS: HQ_STAYS — Lisbon throughout';

  insert into public.company_hqs (player_id, slot, port_id) values (v_a, 2, v_lon);
  v_r := world.player()->'player'->'hq'->'list';
  if jsonb_array_length(v_r) <> 2 or v_r->0->>'port' <> 'LIS' or v_r->1->>'port' <> 'LON' then raise exception 'HQ_LIST: %', v_r; end if;
  begin
    insert into public.company_hqs (player_id, slot, port_id) values (v_a, 3, v_lon);
    raise exception 'HQ_LIST: one city twice';
  exception when unique_violation then null; end;
  begin
    insert into public.company_hqs (player_id, slot, port_id) select v_a, 6, p.id from public.ports p where p.code = 'SVQ';
    raise exception 'HQ_LIST: a sixth';
  exception when check_violation then null; end;
  if jsonb_array_length(public.hq_card(v_n)->'list') <> 0 then raise exception 'HQ_LIST: a merchant'; end if;
  raise notice 'PASS: HQ_LIST — Lisbon, London';

  if world.player()->'player'->'hq'->'next' <> 'null'::jsonb or cmd.open_hq('LON')->>'error_code' <> 'E_NOT_IN_USE' /* 0512: the door is there, and shut */ or public.home_port_of(v_a) <> v_lis then raise exception 'HQ_DARK: dark'; end if;
  update public.company_hqs set slot = 5 where player_id = v_a and slot = 1;
  update public.company_hqs set slot = 1 where player_id = v_a and port_id = v_lon;
  if public.home_port_of(v_a) <> v_lis then raise exception 'HQ_DARK: home moved while dark'; end if;
  update public.world_config set value = 'true'::jsonb where key = 'hq_cities_enabled';
  if public.home_port_of(v_a) <> v_lon or public.hq_card(v_a)->'next' <> 'null'::jsonb then raise exception 'HQ_DARK: lit, home %, card %', public.home_port_of(v_a), public.hq_card(v_a); end if;
  delete from public.company_hqs where player_id = v_a and slot = 5;
  if public.hq_card(v_a)->'next' is distinct from (select jsonb_build_object('slot', 2, 'total_level', s.total_level, 'ducats', s.ducats, 'reputation', s.reputation) from public.hq_steps s where s.slot = 2) then
    raise exception 'HQ_DARK: next %', public.hq_card(v_a);
  end if;
  raise notice 'PASS: HQ_DARK — home follows the switch, the ladder is data';
end $p$;

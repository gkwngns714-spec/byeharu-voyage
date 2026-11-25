-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 232 - HQ CITIES  (migration 0512; docs/dev-log/2026-11-25-hq-cities.md; the owner's answer 4, R2, slides 1, 2 and 4)
--
--   Its own companies; the switches, the steps and the purse are written here and rolled back by proof.mjs. No price, die, real company or date is read.
--
-- @pass HC_DARK    as shipped: the door says E_NOT_IN_USE, the read {on: false}, no list row carries a warehouse, home is the founding port for every company, the perks are empty
-- @pass HC_UNSET   lit, every step past the first is unset: "HQ 2 is not set yet.", whatever she holds; a step with one figure missing is unset too
-- @pass HC_NEEDS   lit and set, each need refuses alone with have / need: a fleet there, level, gold, Reputation; at each figure exactly she may; a fleet under way or wrecked is no fleet
-- @pass HC_SEA     with the seas lit, a level-1 company whose fleet lies in Africa's port is refused by the sea with the rule's own words; in Europe she is not
-- @pass HC_OPEN    opened: gold out of her purse as HQ and into that city's purse, no influence, no profit of the city's; Reputation spent once; one event; the row; the list; a second
--                  press opens nothing; a fifth is the last
-- @pass HC_HOME    home is still slot 1: the land party, the heir, the bring-home job that names none; half tax and requests at any HQ; a bring-home job may name an HQ and no other
--                  city; pass home leads to her country's capital; dark again, every one as it was
-- @pass HC_SHED    each HQ's warehouse is the shed in that city, its own goods and no other's
-- @pass HC_OTHERS  a merchant and nobody open none; another company's HQ is not hers
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  c_a constant uuid := '00000000-0512-4000-8000-0000000002a1'; c_b constant uuid := '00000000-0512-4000-8000-0000000002b1';
  v_a uuid; v_b uuid; v_fa uuid; v_lis uuid := (select id from public.ports where code = 'LIS'); v_lon uuid := (select id from public.ports where code = 'LON');
  v_r jsonb; v_x jsonb; v_n int; v_lvl int; v_p0 bigint; v_inf numeric; v_good uuid; k text; v_rate numeric; v_rate2 numeric;
begin
  update public.world_config set value = 'false'::jsonb where key in ('hq_cities_enabled', 'sea_conditions_bite', 'tax_thirty_enabled');
  update public.world_config set value = 'true'::jsonb where key in ('reputation_on', 'assign_home_enabled');
  v_a := public.new_house(c_a, 'Casa das Sedes 232', 'PRT');
  v_b := public.new_house(c_b, 'Casa Vizinha 232', 'ENG');
  select id into v_fa from public.fleets where player_id = v_a;
  perform cmd.assume_identity(c_a);

  -- ── HC_DARK ──
  if cmd.open_hq('LON')->>'error_code' <> 'E_NOT_IN_USE' or world.hq_open('LON') <> '{"on": false}'::jsonb or public.hq_card(v_a)::text like '%warehouse%'
     or exists (select 1 from public.hq_perks) or exists (select 1 from public.players p where not p.is_npc and public.home_port_of(p.id) is distinct from
          (select q.id from public.events e join public.ports q on q.code = e.payload->>'port' where e.player_id = p.id and e.kind = 'FOUNDED' order by e.created_at limit 1))
     or public.hq_at(v_a, v_lon) or not public.hq_at(v_a, v_lis) then
    raise exception 'PROOF 232 FAIL: dark: %, %', cmd.open_hq('LON'), world.hq_open('LON');
  end if;
  raise notice 'PASS: HC_DARK - the door and the read are shut, home is the founding port for every company, no perk';

  -- ── HC_UNSET ──
  update public.world_config set value = 'true'::jsonb where key = 'hq_cities_enabled';
  update public.fleets set port_id = v_lon where id = v_fa;
  update public.players set ducats = 100000000 where id = v_a;
  v_r := cmd.open_hq('LON');
  v_x := world.hq_open('LON');
  if v_r->>'error_message' <> 'HQ 2 is not set yet.' or (v_x->>'set')::boolean or (v_x->>'slot')::int <> 2 or exists (select 1 from public.hq_steps s where s.slot > 1 and coalesce(s.total_level, s.ducats, s.reputation) is not null) then
    raise exception 'PROOF 232 FAIL: unset: %, %', v_r, v_x;
  end if;
  update public.hq_steps set total_level = 0, ducats = 0 where slot = 2;
  if cmd.open_hq('LON')->>'error_code' <> 'E_HQ_NOT_SET' then raise exception 'PROOF 232 FAIL: a half-set step opened'; end if;
  raise notice 'PASS: HC_UNSET - %', v_r->>'error_message';

  -- ── HC_NEEDS ──
  v_lvl := public.total_level(v_a);
  if v_lvl < 1 or v_lvl <> (select sum((s->>'level')::int) from jsonb_array_elements(world.levels()->'level_skills'->'skills') s where (s->>'counted')::boolean) then
    raise exception 'PROOF 232 FAIL: total level %', v_lvl;
  end if;
  perform public.reputation_credit(v_a, 'landfall', 300, 'proof 232');
  update public.hq_steps set total_level = v_lvl, ducats = 50000, reputation = 300 where slot = 2;
  if public.hq_open_refusal(v_a, v_lon) is not null then raise exception 'PROOF 232 FAIL: every need met exactly: %', public.hq_open_refusal(v_a, v_lon); end if;
  update public.hq_steps set total_level = v_lvl + 1 where slot = 2;
  v_r := cmd.open_hq('LON');
  if v_r->>'error_code' <> 'E_HQ_LEVEL' or (v_r->'figures'->>'have')::numeric <> v_lvl or (v_r->'figures'->>'need')::numeric <> v_lvl + 1 then raise exception 'PROOF 232 FAIL: level: %', v_r; end if;
  update public.hq_steps set total_level = v_lvl, ducats = 100000001 where slot = 2;
  v_r := cmd.open_hq('LON');
  if v_r->>'error_code' <> 'E_INSUFFICIENT_FUNDS' or (v_r->'figures'->>'need')::numeric <> 100000001 then raise exception 'PROOF 232 FAIL: gold: %', v_r; end if;
  update public.hq_steps set ducats = 50000, reputation = 301 where slot = 2;
  v_r := cmd.open_hq('LON');
  if v_r->>'error_code' <> 'E_NOT_ENOUGH_REPUTATION' or (v_r->'figures'->>'have')::numeric <> 300 then raise exception 'PROOF 232 FAIL: Reputation: %', v_r; end if;
  update public.hq_steps set reputation = 300 where slot = 2;
  if cmd.open_hq('AMS')->>'error_code' <> 'E_NO_FLEET_HERE' or cmd.open_hq('NOWHERE')->>'error_code' <> 'E_NO_SUCH_PORT' or cmd.open_hq('LIS')->>'error_code' <> 'E_HQ_HERE'
     or cmd.open_hq((select p.code from public.ports p where p.kind <> 'HARBOUR' order by p.code limit 1))->>'error_code' <> 'E_NO_SUCH_PORT' then
    raise exception 'PROOF 232 FAIL: a place she may not open in was not refused as it is';
  end if;
  begin
    update public.ships set durability = 0 where fleet_id = v_fa;
    update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_fa;
    if cmd.open_hq('LON')->>'error_code' <> 'E_NO_FLEET_HERE' then raise exception 'PROOF 232 FAIL: a wreck opened an HQ'; end if;
    raise exception using errcode = 'ZY232', message = 'x';
  exception when sqlstate 'ZY232' then null; end;
  if (select count(*) from public.company_hqs where player_id = v_a) <> 1 or (select ducats from public.players where id = v_a) <> 100000000 then raise exception 'PROOF 232 FAIL: a refusal wrote'; end if;
  raise notice 'PASS: HC_NEEDS - level, gold and Reputation each refuse alone by one; met exactly she may; no fleet, a wreck, a sea place, her own city refuse';

  -- ── HC_SEA ──
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
  update public.players set created_at = now() + interval '1 day' where id = v_a;
  update public.fleets set port_id = (select id from public.ports where code = 'LPA') where id = v_fa;
  v_r := cmd.open_hq('LPA');
  if v_r->>'error_code' <> 'E_SEA_CLOSED' or v_r->>'error_message' not like '%closed.%' then raise exception 'PROOF 232 FAIL: Africa at level 1: %', v_r; end if;
  update public.fleets set port_id = v_lon where id = v_fa;
  if public.hq_open_refusal(v_a, v_lon) is not null then raise exception 'PROOF 232 FAIL: London with the seas lit: %', public.hq_open_refusal(v_a, v_lon); end if;
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
  raise notice 'PASS: HC_SEA - % ; London is open', v_r->>'error_message';

  -- ── HC_OPEN ──
  select coalesce(sum(i.points), 0) into v_inf from (select (to_jsonb(x)->>'points')::numeric as points from public.port_influence x where x.port_id = v_lon and x.player_id = v_a) i;
  v_p0 := (select ducats from public.players where id = v_a);
  v_r := cmd.open_hq('lon');
  if (v_r->>'ok')::boolean is not true or (v_r->>'slot')::int <> 2 or (select ducats from public.players where id = v_a) <> v_p0 - 50000
     or (select sum(l.ducats_delta) from public.ledger l where l.player_id = v_a and l.kind = 'HQ') <> -50000
     or (public.city_treasury_on() and (select sum(t.ducats) from public.treasury_flows t where t.player_id = v_a and t.kind = 'HQ' and t.port_id = v_lon) <> 50000)
     or exists (select 1 from public.port_influence x where x.port_id = v_lon and x.player_id = v_a and v_inf = 0)
     or public.flow_is_profit('HQ') or (select line from public.company_rate_line('HQ')) <> 'room' or not (select one_time from public.company_rate_line('HQ'))
     or (select balance from public.reputation_balance where player_id = v_a) <> 0 or (select count(*) from public.reputation_book where player_id = v_a and kind = 'hq') <> 1
     or (select count(*) from public.events where player_id = v_a and kind = 'HQ_OPENED') <> 1 or jsonb_array_length(public.hq_card(v_a)->'list') <> 2 then
    raise exception 'PROOF 232 FAIL: opening: %', v_r;
  end if;
  if cmd.open_hq('LON')->>'error_code' <> 'E_HQ_HERE' or (select ducats from public.players where id = v_a) <> v_p0 - 50000 then raise exception 'PROOF 232 FAIL: pressed twice'; end if;
  -- the next three, at no cost, then the top
  update public.hq_steps set total_level = 0, ducats = 0, reputation = 0 where slot > 2;
  foreach k in array array['AMS', 'SVQ', 'VEN'] loop
    update public.fleets set port_id = (select id from public.ports where code = k) where id = v_fa;
    if (cmd.open_hq(k)->>'ok')::boolean is not true then raise exception 'PROOF 232 FAIL: HQ in %', k; end if;
  end loop;
  update public.fleets set port_id = (select id from public.ports where code = 'GOA') where id = v_fa;
  if cmd.open_hq('GOA')->>'error_code' <> 'E_HQ_TOP' or (select count(*) from public.company_hqs where player_id = v_a) <> 5 then raise exception 'PROOF 232 FAIL: a sixth: %', cmd.open_hq('GOA'); end if;
  raise notice 'PASS: HC_OPEN - 50,000 from her purse to London''s, 300 Reputation spent once, one event; pressed twice nothing; five HQs and no sixth';

  -- ── HC_HOME ──
  update public.world_config set value = 'true'::jsonb where key = 'tax_thirty_enabled';
  perform public.land_party(v_a);
  if public.home_port_of(v_a) <> v_lis or public.company_heir(v_a) <> v_lis or public.sea_home(v_a) <> 'LIS' or not public.hq_at(v_a, v_lon) or public.hq_at(v_a, (select id from public.ports where code = 'GOA'))
     or (select lp.port_id from public.land_parties lp where lp.player_id = v_a) is distinct from v_lis then
    raise exception 'PROOF 232 FAIL: home moved';
  end if;
  v_rate := public.tax_home_half(v_lon, v_a, 0.2, 0.2);
  v_rate2 := public.tax_home_half((select id from public.ports where code = 'GOA'), v_a, 0.2, 0.2);
  if v_rate <> 0.2 * (1 - public.wc_num('home_tax_cut')) or v_rate2 <> 0.2 or public.tax_home_half(v_lon, v_b, 0.2, 0.2) = 0.2 and public.home_port_of(v_b) = v_lon then
    raise exception 'PROOF 232 FAIL: the tax: London %, Goa %', v_rate, v_rate2;
  end if;
  if (world.requests(v_lon)->>'home')::boolean is not true or (world.requests((select id from public.ports where code = 'GOA'))->>'home')::boolean then raise exception 'PROOF 232 FAIL: requests'; end if;
  v_x := public.fleet_job_end(v_a, '{"end": "store", "buy": "OPO"}'::jsonb);
  if v_x->>'sell' <> 'LIS' or public.fleet_job_end(v_a, '{"end": "store", "buy": "OPO", "home": "LON"}'::jsonb)->>'sell' <> 'LON' then raise exception 'PROOF 232 FAIL: bring home: %', v_x; end if;
  begin
    perform public.fleet_job_end(v_a, '{"end": "store", "buy": "OPO", "home": "GOA"}'::jsonb);
    raise exception 'PROOF 232 FAIL: bring home to a city that is no HQ of hers';
  exception when sqlstate 'P0001' then if sqlerrm not like 'E_NO_HOME%' then raise; end if; end;
  update public.world_config set value = 'false'::jsonb where key = 'hq_cities_enabled';
  if public.hq_at(v_a, v_lon) or public.tax_home_half(v_lon, v_a, 0.2, 0.2) <> 0.2 or (world.requests(v_lon)->>'home')::boolean or public.fleet_job_end(v_a, '{"end": "store", "buy": "OPO", "home": "LON"}'::jsonb)->>'sell' <> 'LIS' then
    raise exception 'PROOF 232 FAIL: dark again, an HQ is still home';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'hq_cities_enabled';
  raise notice 'PASS: HC_HOME - home stays slot 1; half tax, requests and a named bring-home at any HQ; pass home to the capital; dark, as it was';

  -- ── HC_SHED ──
  select id into v_good from public.goods order by code limit 1;
  insert into public.player_storage (player_id, port_id, good_id, qty) values (v_a, v_lon, v_good, 7), (v_b, v_lon, v_good, 100);
  if (select (e->'warehouse'->>'used')::numeric from jsonb_array_elements(public.hq_card(v_a)->'list') e where e->>'port' = 'LON') <> 7 * (select bulk from public.goods where id = v_good)
     or (select (e->'warehouse'->>'used')::numeric from jsonb_array_elements(public.hq_card(v_a)->'list') e where e->>'port' = 'LIS') <> 0 then
    raise exception 'PROOF 232 FAIL: the sheds: %', public.hq_card(v_a);
  end if;
  raise notice 'PASS: HC_SHED - London''s shed holds her 7 and not her neighbour''s 100; Lisbon''s none';

  -- ── HC_OTHERS ──
  if public.total_level((select player_id from public.npc_fleets limit 1)) is not null or public.hq_at(v_b, (select id from public.ports where code = 'SVQ')) then raise exception 'PROOF 232 FAIL: a merchant, or a neighbour'; end if;
  perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'PASS: HC_OTHERS - a merchant has no total level; her HQs are hers alone';
end
$p$;

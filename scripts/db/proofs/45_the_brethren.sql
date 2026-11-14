-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 45 — THE BRETHREN  (migration 0338, slice W16 of docs/WORLD_POWERS.md; owner row 284: "pirates are like countries ... they will have pirate port that has no tax, cheaper products")
--
--   0338's own self-assert reads the catalog and cheap pure functions only: a migration never runs a real game step (docs/OPS_HEALTH.md section 4). This proof runs the REAL quote, dock fee, tax refusal, depth
--   day, crown aid, cargo job, navy job, doors, Countries board and Levels page on probe companies, all rolled back with proof.mjs's transaction. It owns every switch it needs and writes them here.
--
-- @pass BRETHREN_SHAPE      11 great powers, exactly one without a crown and it is PIR (a second is refused); 24 nations; the flag is the skull; the capital is Port Royal; four homes held by the pirates; ten wars
-- @pass BRETHREN_FREE_PORT  at each of the four homes a company of Portugal pays tax 0 and dock fee 0 and the dues line says factor 0, war; a control city asks its tax and fee; a city the pirates WIN keeps its own rate
-- @pass BRETHREN_TAX_DOOR   cmd.set_tax at a pirate home is refused E_FREE_PORT; at a control city it is refused E_NOT_MAYOR as before; depth_day leaves a home at 0.5 whatever is invested and moves a control city
-- @pass BRETHREN_LEVER      pirate_ports_free false: no port is free, the four ask the tax, the fee and the war factor of any city, set_tax answers as at any city, depth_day moves them; true again: free as before
-- @pass BRETHREN_NO_CROWN   city_capital is null at the four; crown_aid aids a poor Portuguese city and not a poor pirate one, and moves no pirate gold; convoys lit: no fleet number, circuit or ship for the pirates, the other realms keep theirs
-- @pass BRETHREN_NO_NAVY    navy lit: navy_read writes the ten and not the pirates; navy_plan_step plans no station for them and still plans another realm's
-- @pass BRETHREN_DOORS      pirates_joinable false: found_house and change_country refuse PIR (E_MINOR_POWER, the fixes name the ten), a minor is refused alike, a great power is let in; true: PIR is let in at Port Royal, paid by Port Royal
-- @pass BRETHREN_SNAPSHOT   world.snapshot serves great for 11 and joinable for 10 (PIR great, not joinable); the four homes fly PIR with tax 0
-- @pass BRETHREN_BOARDS     the Countries board lists 11 (The Brethren: 4 homes, and since 0414 the five ocean havens held beside them: 9 held, 4 home, 5 won); the Levels regard list names the ten crowns and not the pirates
-- @pass BRETHREN_GUARD      the home guard is enabled and bites: a pirate home cannot stop being home
-- @pass BRETHREN_INFLUENCE  a foreign point in a pirate home does not move the flag, makes no mayor, and reads as war to the population signal; the daily count decays it as it decays any
-- @pass BRETHREN_MONEY      W (purses + companies + funds aboard) is unchanged to the ducat across every quote, crown run, cargo run, navy run and board above, and across a company founded under the pirates (moved from Port Royal)
-- ═══════════════════════════════════════════════════════════════════════════════

create function pg_temp.w_45() returns numeric language sql as $f$
  select (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric
       + (select coalesce(sum(p.ducats), 0) from public.players p)::numeric + public.funds_aboard()::numeric
$f$;

do $$
declare
  c_homes constant text[] := array['POR', 'LGA', 'GOT', 'DJE'];
  c_uid1  constant uuid := '00000000-0f45-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0f45-4000-8000-000000000002';
  c_uid3  constant uuid := '00000000-0f45-4000-8000-000000000003';
  v_pir   uuid := (select n.id from public.nations n where n.code = 'PIR');
  v_prt   uuid := (select n.id from public.nations n where n.code = 'PRT');
  v_por   uuid := (select p.id from public.ports p where p.code = 'POR');
  v_lga   uuid := (select p.id from public.ports p where p.code = 'LGA');
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_set   uuid := (select p.id from public.ports p where p.code = 'SET');
  v_a     uuid;
  v_b     uuid;
  v_c     uuid;
  v_r     jsonb;
  v_x     jsonb;
  v_n     int;
  v_w0    numeric;
  v_w1    numeric;
  v_d0    numeric;
  v_d1    numeric;
  v_ctl   uuid;
  v_tax   numeric;
  v_fee   bigint;
  v_ltax  numeric;
  v_lfee  bigint;
  v_s1    text;
  v_s2    text;
  v_t0    timestamptz := now();
  h       record;
begin
  -- the probe companies are founded while the economy is open (the world's purses are empty here; a closed founding needs a capital that can pay)
  v_a := public.new_house(c_uid1, 'Casa dos Irmaos 0f45', 'PRT', 'LIS');
  v_b := public.new_house(c_uid3, 'Casa Espanhola 0f45', 'ESP', 'SVQ');
  -- the switches a closed world runs on; nothing here is the pirates'
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled', 'economy_closed');
  -- 0373 lit regard in the chain. This proof reads the stance factors alone (its Lisbon control is the home factor, with no regard on top) and lights regard itself where it
  -- reads the Levels list, so it starts from the dark world it was written for: the switch is set back here, for this rolled-back transaction only.
  update public.world_config set value = 'false'::jsonb where key = 'regard_enabled';
  if public.nation_joinable(v_pir) or (select c.value from public.world_config c where c.key = 'pirates_joinable') <> 'false'::jsonb then
    raise exception 'PROOF 45 FAIL: pirates_joinable is not false in this world; the proof owns the start';
  end if;

  -- ── SHAPE ──
  if (select count(*) from public.great_powers) <> 11 or (select count(*) from public.great_powers g where g.pirate) <> 1
     or (select n.code from public.great_powers g join public.nations n on n.id = g.nation_id where g.pirate) <> 'PIR'
     or (select count(*) from public.nations) <> 24
     or (select n.flag_char || '|' || n.name || '|' || n.capital_port_code from public.nations n where n.id = v_pir) <> '☠|The Brethren|POR' then
    raise exception 'PROOF 45 FAIL: the pirates are not the 11th great power, alone without a crown, as the plan says';
  end if;
  begin
    update public.great_powers set pirate = true where nation_id = v_prt;
    raise exception 'PROOF 45 FAIL: a second pirate power was accepted';
  exception when unique_violation then null;
  end;
  if (select array_agg(p.code order by p.code) from public.port_allegiance a join public.ports p on p.id = a.port_id where a.home and a.nation_id = v_pir) <> (select array_agg(c order by c) from unnest(c_homes) c)
     or (select count(*) from public.port_allegiance a where a.nation_id = v_pir and not exists (select 1 from public.pirate_hubs hb where hb.port_id = a.port_id)) <> 4   -- 0414: the pirates also hold their five ocean havens (public.pirate_hubs), which are not homes
     or (select count(*) from public.power_relations r where (r.a = v_pir or r.b = v_pir) and r.stance = 'war') <> 10
     or (select count(*) from public.great_powers g where g.nation_id <> v_pir and public.power_stance(v_pir, g.nation_id) = 'war') <> 10 then
    raise exception 'PROOF 45 FAIL: the homes or the ten wars are not as the plan says';
  end if;
  raise notice 'PASS: BRETHREN_SHAPE — 11 great powers, PIR the only one without a crown, 24 nations, the skull, capital Port Royal, 4 homes, 10 wars';

  -- ── FREE PORT: the quote, the fee, the dues ──
  select pa.port_id into v_ctl from public.port_allegiance pa where pa.nation_id = v_prt and pa.port_id <> v_lis and not pa.home order by pa.port_id limit 1;
  if v_ctl is null then
    select pa.port_id into v_ctl from public.port_allegiance pa where pa.nation_id = v_prt and pa.port_id <> v_lis order by pa.port_id limit 1;
  end if;
  update public.players set ducats = 5000000 where id = v_a;
  v_w0 := pg_temp.w_45();
  for h in select p.code, p.id from public.ports p where p.code = any (c_homes) order by p.code loop
    v_tax := world.tax_rate(h.id, v_a);
    v_fee := public.port_fee(h.id, v_a, 1000000);
    v_x := public.port_dues(h.id, v_a, 1000000) -> 'dues';
    if world.tax_rate(h.id) <> 0 or v_tax <> 0 or v_fee <> 0 or (v_x ->> 'factor')::numeric <> 0 or (v_x ->> 'fee')::bigint <> 0 or v_x ->> 'stance' <> 'war' then
      raise exception 'PROOF 45 FAIL: at % a company of Portugal meets tax %, fee %, dues %', h.code, v_tax, v_fee, v_x;
    end if;
    if not public.port_is_free(h.id) or public.city_capital(h.id) is not null then
      raise exception 'PROOF 45 FAIL: % is not a free port without a crown', h.code;
    end if;
    if (select p.tax_rate from public.ports p where p.id = h.id) <> 0.03 then
      raise exception 'PROOF 45 FAIL: the stored rate of % was touched; the lever restores it, so it must stay', h.code;
    end if;
  end loop;
  v_ltax := world.tax_rate(v_lis, v_a);
  v_lfee := public.port_fee(v_lis, v_a, 1000000);
  if v_ltax <= 0 or v_lfee <= 0 or public.port_is_free(v_lis) or ((public.port_dues(v_lis, v_a, 1000000) -> 'dues' ->> 'factor')::numeric) <> public.country_factor('home') then
    raise exception 'PROOF 45 FAIL: the control city Lisbon asks tax %, fee % - it must still ask them, home factor', v_ltax, v_lfee;
  end if;
  -- a city the pirates WIN later is not free and keeps its own rate: the stance war doubles it (the control is the same city held by its old flag)
  select pa.port_id into v_ctl from public.port_allegiance pa where pa.nation_id = v_prt and not pa.home order by pa.port_id limit 1;
  if v_ctl is not null then
    v_tax := world.tax_rate(v_ctl, v_a);
    v_fee := public.port_fee(v_ctl, v_a, 1000000);
    begin
      update public.port_allegiance set nation_id = v_pir where port_id = v_ctl;
      if public.port_is_free(v_ctl) or world.tax_rate(v_ctl, v_a) <= 0 or public.port_fee(v_ctl, v_a, 1000000) <= 0
         or (public.port_dues(v_ctl, v_a, 1000000) -> 'dues' ->> 'stance') <> 'war' then
        raise exception 'PROOF 45 FAIL: a contested city the pirates won is free, or asks nothing: tax %, fee %', world.tax_rate(v_ctl, v_a), public.port_fee(v_ctl, v_a, 1000000);
      end if;
      raise exception 'PROBE_ROLLBACK_45';
    exception when others then
      if sqlerrm <> 'PROBE_ROLLBACK_45' then raise; end if;
    end;
  end if;
  raise notice 'PASS: BRETHREN_FREE_PORT — the four homes: tax 0, fee 0, dues factor 0 (war); Lisbon asks tax % and fee %; a city the pirates win is not free', v_ltax, v_lfee;

  -- ── TAX DOOR AND DEPTH ──
  perform cmd.assume_identity(c_uid1);
  v_r := cmd.set_tax(v_por, 0.05);
  v_x := cmd.set_tax(v_lis, 0.05);
  if (v_r ->> 'ok') <> 'false' or (v_r ->> 'error_code') <> 'E_FREE_PORT' or (v_x ->> 'error_code') <> 'E_NOT_MAYOR' then
    raise exception 'PROOF 45 FAIL: set_tax at Port Royal answered %, at Lisbon %', v_r, v_x;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'depth_by_investment';
  update public.port_treasury set invested = 3000000, depth_day = null where port_id in (v_por, v_lis);
  update public.port_treasury set depth_mult = null where port_id = v_lis;
  v_d0 := (select t.depth_mult from public.port_treasury t where t.port_id = v_por);
  perform public.depth_day(777001);
  v_d1 := (select t.depth_mult from public.port_treasury t where t.port_id = v_por);
  if v_d0 <> 0.5 or v_d1 <> 0.5 or (select t.depth_day from public.port_treasury t where t.port_id = v_por) is not null
     or (select t.depth_mult from public.port_treasury t where t.port_id = v_lis) is null or (select t.depth_day from public.port_treasury t where t.port_id = v_lis) <> 777001 then
    raise exception 'PROOF 45 FAIL: depth_day moved Port Royal (% to %) or did not move the control city', v_d0, v_d1;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'depth_by_investment';
  raise notice 'PASS: BRETHREN_TAX_DOOR — set_tax at Port Royal: E_FREE_PORT, at Lisbon: E_NOT_MAYOR; depth_day left Port Royal at 0.5 with 3,000,000 invested and moved Lisbon to %', (select t.depth_mult from public.port_treasury t where t.port_id = v_lis);

  -- ── THE LEVER: one write puts the four back among the cities ──
  update public.world_config set value = 'false'::jsonb where key = 'pirate_ports_free';
  update public.world_config set value = 'true'::jsonb where key = 'depth_by_investment';
  for h in select p.code, p.id from public.ports p where p.code = any (c_homes) order by p.code loop
    v_x := public.port_dues(h.id, v_a, 1000000) -> 'dues';
    if public.port_is_free(h.id) or world.tax_rate(h.id, v_a) <= 0 or public.port_fee(h.id, v_a, 1000000) <= 0
       or (v_x ->> 'factor')::numeric <> public.country_factor('war') or (v_x ->> 'stance') <> 'war' then
      raise exception 'PROOF 45 FAIL: with the lever off % is still free: tax %, fee %, dues %', h.code, world.tax_rate(h.id, v_a), public.port_fee(h.id, v_a, 1000000), v_x;
    end if;
  end loop;
  v_r := cmd.set_tax(v_por, 0.05);
  if (v_r ->> 'error_code') <> 'E_NOT_MAYOR' then
    raise exception 'PROOF 45 FAIL: with the lever off set_tax at Port Royal answered %', v_r;
  end if;
  update public.port_treasury set invested = 3000000, depth_day = null where port_id = v_por;
  perform public.depth_day(777002);
  if (select t.depth_mult from public.port_treasury t where t.port_id = v_por) = 0.5 then
    raise exception 'PROOF 45 FAIL: with the lever off depth_day still leaves Port Royal at 0.5';
  end if;
  update public.port_treasury set depth_mult = 0.5, depth_day = null, invested = null where port_id = v_por;
  update public.world_config set value = 'false'::jsonb where key = 'depth_by_investment';
  update public.world_config set value = 'true'::jsonb where key = 'pirate_ports_free';
  if world.tax_rate(v_por, v_a) <> 0 or public.port_fee(v_por, v_a, 1000000) <> 0 or not public.port_is_free(v_por) then
    raise exception 'PROOF 45 FAIL: with the lever on again Port Royal is not free';
  end if;
  raise notice 'PASS: BRETHREN_LEVER — the lever off: the four tax, charge dues of factor % (war) and let depth_day move them; on again: tax 0, fee 0', public.country_factor('war');

  -- ── NO CROWN: the aid ──
  update public.port_treasury set ducats = 100000000 where port_id = v_por;
  update public.port_treasury set ducats = 0 where port_id in (v_lga, v_set);
  update public.port_treasury set ducats = 20000000 where port_id = v_lis;
  v_w0 := pg_temp.w_45();
  v_d0 := public.treasury_balance(v_por);
  v_r := public.crown_aid(null);
  if public.treasury_balance(v_lga) <> 0 or public.treasury_balance(v_por) <> v_d0
     or public.treasury_balance(v_set) <= 0 or (v_r ->> 'aided')::int < 1 then
    raise exception 'PROOF 45 FAIL: crown_aid % - Lingga got % (must stay 0), Port Royal moved % -> %, Setubal got %', v_r, public.treasury_balance(v_lga), v_d0, public.treasury_balance(v_por), public.treasury_balance(v_set);
  end if;
  if pg_temp.w_45() <> v_w0 then
    raise exception 'PROOF 45 FAIL: the crown run made or lost gold: % -> %', v_w0, pg_temp.w_45();
  end if;
  -- ── NO CROWN: cargo ships ──
  update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';
  v_w0 := pg_temp.w_45();
  perform public.convoy_fleet_settle(v_t0);
  v_r := public.tick_cargo_ships(v_t0, v_pir);
  v_x := public.tick_cargo_ships(v_t0, null);
  if exists (select 1 from public.cargo_fleet_sizes s where s.nation_id = v_pir) or exists (select 1 from public.cargo_circuits c where c.nation_id = v_pir)
     or exists (select 1 from public.cargo_ships c where c.nation_id = v_pir) or exists (select 1 from public.cargo_ships c join public.players p on p.id = c.player_id where p.nation_id = v_pir)
     or (select count(*) from public.cargo_fleet_sizes) <> 10 or (v_r ->> 'built') is not null or (v_r ->> 'made')::int <> 0
     or not exists (select 1 from public.cargo_circuits c) or not exists (select 1 from public.cargo_ships c) then
    raise exception 'PROOF 45 FAIL: the cargo job touched the pirates, or stopped serving the ten: sizes %, run for the pirates %, run for all %', (select count(*) from public.cargo_fleet_sizes), v_r, v_x;
  end if;
  if (select count(*) from public.convoy_ships_wanted()) <> 10 or exists (select 1 from public.convoy_ships_wanted() w where w.nation_id = v_pir) then
    raise exception 'PROOF 45 FAIL: convoy_ships_wanted names the pirates';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'convoys_enabled';
  if pg_temp.w_45() <> v_w0 then
    raise exception 'PROOF 45 FAIL: the cargo run made or lost gold: % -> %', v_w0, pg_temp.w_45();
  end if;
  raise notice 'PASS: BRETHREN_NO_CROWN — Port Royal untouched at %, Lingga 0, Setubal aided % by Lisbon; convoys lit: % fleet numbers, % circuits, % ships, none the pirates''', v_d0, public.treasury_balance(v_set),
    (select count(*) from public.cargo_fleet_sizes), (select count(*) from public.cargo_circuits), (select count(*) from public.cargo_ships);

  -- ── NO NAVY ──
  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';
  perform public.navy_read(v_t0);
  v_s1 := public.navy_plan_step(v_t0, v_pir);
  v_s2 := public.navy_plan_step(v_t0, v_prt);
  if exists (select 1 from public.navy_realms r where r.nation_id = v_pir) or exists (select 1 from public.navy_stations s where s.nation_id = v_pir)
     or (select count(*) from public.navy_realms) <> 10 or v_s1 is not null or v_s2 is null
     or not exists (select 1 from public.navy_stations s where s.nation_id = v_prt) then
    raise exception 'PROOF 45 FAIL: the navy job touched the pirates or stopped serving the ten: realms %, plan for the pirates %, plan for Portugal %', (select count(*) from public.navy_realms), v_s1, v_s2;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'navy_enabled';
  raise notice 'PASS: BRETHREN_NO_NAVY — navy_read wrote % realms and not the pirates; navy_plan_step: pirates %, Portugal %', (select count(*) from public.navy_realms), coalesce(v_s1, 'none'), v_s2;

  -- ── THE DOORS ──
  perform cmd.assume_identity(c_uid2);
  v_r := cmd.found_house('Casa dos Piratas 0f45', 'PIR');
  if (v_r ->> 'ok') <> 'false' or (v_r ->> 'error_code') <> 'E_MINOR_POWER' or jsonb_array_length(v_r -> 'fixes') <> 10 or (v_r ->> 'error_message') !~ '^The Brethren takes no companies' then
    raise exception 'PROOF 45 FAIL: found_house under the pirates answered %', v_r;
  end if;
  v_r := cmd.found_house('Casa dos Piratas 0f45', 'VEN');
  v_x := cmd.found_house('Casa dos Piratas 0f45', 'ZZZ');
  if (v_r ->> 'error_code') <> 'E_MINOR_POWER' or jsonb_array_length(v_r -> 'fixes') <> 10 or (v_x ->> 'error_code') <> 'E_NO_SUCH_NATION' or jsonb_array_length(v_x -> 'fixes') <> 10
     or v_r::text like '%PIR%' or v_x::text like '%PIR%' then
    raise exception 'PROOF 45 FAIL: a minor or a nobody was answered %, %', v_r, v_x;
  end if;
  perform cmd.assume_identity(c_uid1);
  v_r := cmd.change_country('PIR');
  if (v_r ->> 'error_code') <> 'E_MINOR_POWER' or (select pl.nation_id from public.players pl where pl.id = v_a) <> v_prt then
    raise exception 'PROOF 45 FAIL: change_country to the pirates answered %', v_r;
  end if;
  -- the knob: the owner's word, one place
  update public.world_config set value = 'true'::jsonb where key = 'pirates_joinable';
  update public.port_treasury set ducats = 100000000 where port_id = v_por;
  v_w0 := pg_temp.w_45();
  perform cmd.assume_identity(c_uid2);
  v_r := cmd.found_house('Casa dos Piratas 0f45', 'PIR');
  if (v_r ->> 'ok') <> 'true' or (v_r ->> 'nation') <> 'PIR' then
    raise exception 'PROOF 45 FAIL: with pirates_joinable true found_house answered %', v_r;
  end if;
  v_c := (v_r ->> 'player_id')::uuid;
  if (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.player_id = v_c) <> 'POR'
     or (select pl.nation_id from public.players pl where pl.id = v_c) <> v_pir then
    raise exception 'PROOF 45 FAIL: a company founded under the pirates does not start at Port Royal';
  end if;
  v_w1 := pg_temp.w_45();
  if v_w1 <> v_w0 then
    raise exception 'PROOF 45 FAIL: founding under the pirates made or lost gold: % -> %', v_w0, v_w1;
  end if;
  perform cmd.assume_identity(c_uid1);
  v_r := cmd.change_country('PIR');
  if (v_r ->> 'ok') <> 'true' or (select pl.nation_id from public.players pl where pl.id = v_a) <> v_pir then
    raise exception 'PROOF 45 FAIL: with pirates_joinable true change_country answered %', v_r;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'pirates_joinable';
  perform cmd.assume_identity(c_uid3);
  v_r := cmd.change_country('PIR');
  if (v_r ->> 'error_code') <> 'E_MINOR_POWER' then
    raise exception 'PROOF 45 FAIL: the knob false again but change_country to the pirates answered %', v_r;
  end if;
  v_r := cmd.change_country('PRT');
  if (v_r ->> 'ok') <> 'true' then
    raise exception 'PROOF 45 FAIL: a great power was refused: %', v_r;
  end if;
  raise notice 'PASS: BRETHREN_DOORS — knob false: found_house and change_country refuse PIR (E_MINOR_POWER, 10 fixes), a minor and a nobody alike, a great power is let in; knob true: PIR let in, started at Port Royal, paid by Port Royal (W unchanged)';

  -- ── THE SNAPSHOT ──
  v_x := world.snapshot() -> 'nations';
  if (select count(*) from jsonb_array_elements(v_x) e where (e ->> 'great')::boolean) <> 11
     or (select count(*) from jsonb_array_elements(v_x) e where (e ->> 'joinable')::boolean) <> 10
     or not (select (e ->> 'great')::boolean and not (e ->> 'joinable')::boolean from jsonb_array_elements(v_x) e where e ->> 'code' = 'PIR')
     or (select count(*) from jsonb_array_elements(world.snapshot() -> 'ports') e where e ->> 'nation' = 'PIR' and (e ->> 'tax_rate')::numeric = 0) <> 4 then
    raise exception 'PROOF 45 FAIL: the snapshot does not serve great 11, joinable 10 and four pirate ports at tax 0';
  end if;
  raise notice 'PASS: BRETHREN_SNAPSHOT — nations: great 11, joinable 10 (PIR great, not joinable); 4 ports fly PIR at tax 0';

  -- ── THE BOARDS ──
  v_x := world.nation_standings() -> 'countries';
  select e into v_r from jsonb_array_elements(v_x) e where e ->> 'nation' = 'PIR';
  if jsonb_array_length(v_x) <> 11 or (v_r ->> 'held')::int <> 4 + (select count(*) from public.pirate_hubs) or (v_r ->> 'home')::int <> 4
     or (v_r ->> 'won')::int <> (select count(*) from public.pirate_hubs) then   -- 0414: the five ocean havens are held and are not homes, so the board counts them as won
    raise exception 'PROOF 45 FAIL: the Countries board lists % countries, The Brethren %', jsonb_array_length(v_x), v_r;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'regard_enabled';
  perform cmd.assume_identity(c_uid3);
  v_x := world.levels() -> 'regard';
  if jsonb_array_length(v_x) <> 10 or exists (select 1 from jsonb_array_elements(v_x) e where e ->> 'code' = 'PIR') then
    raise exception 'PROOF 45 FAIL: the Levels regard list names % countries or the pirates: %', jsonb_array_length(v_x), v_x;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'regard_enabled';
  raise notice 'PASS: BRETHREN_BOARDS — the Countries board lists 11 (The Brethren 4 held, 4 home, 0 won); the Levels regard list names 10 and not the pirates';

  -- ── THE GUARD ──
  if (select t.tgenabled from pg_trigger t where t.tgname = 'port_allegiance_home_never_changes' and t.tgrelid = 'public.port_allegiance'::regclass) <> 'O' then
    raise exception 'PROOF 45 FAIL: the home guard trigger is not enabled';
  end if;
  begin
    update public.port_allegiance set home = false where port_id = v_por;
    raise exception 'PROOF 45 FAIL: a pirate home stopped being home';
  exception when others then
    if sqlerrm !~ '^E_HOME_CITY' then raise; end if;
  end;
  begin
    update public.port_allegiance set nation_id = v_prt where port_id = v_por;
    raise exception 'PROOF 45 FAIL: a pirate home changed hands';
  exception when others then
    if sqlerrm !~ '^E_HOME_CITY' then raise; end if;
  end;
  raise notice 'PASS: BRETHREN_GUARD — the home guard is enabled; a pirate home cannot stop being home or change hands';

  -- ── INFLUENCE ──
  insert into public.port_influence (port_id, nation_id, player_id, points, day_given) values (v_por, v_prt, v_b, 50000, 0);
  if not exists (select 1 from public.population_signals() s where s.port_id = v_por and s.code = 'WAR' and s.value = 1) then
    raise exception 'PROOF 45 FAIL: a foreign point in a pirate home does not read as war to the population signal';
  end if;
  v_n := (select count(*) from public.port_mayor);
  perform public.tick_influence(v_t0);
  if public.port_nation(v_por) <> v_pir or not (select a.home from public.port_allegiance a where a.port_id = v_por)
     or exists (select 1 from public.port_mayor m where m.port_id = v_por)
     or (select i.points from public.port_influence i where i.port_id = v_por and i.player_id = v_b) <> 50000 * (1 - public.wc_num('influence_decay')) then
    raise exception 'PROOF 45 FAIL: the daily count moved the pirate flag, made a mayor, or did not decay the foreign point as it decays any';
  end if;
  raise notice 'PASS: BRETHREN_INFLUENCE — a foreign point at Port Royal reads as war (signal 1), makes no mayor, moves no flag, and decays at influence_decay like any';

  -- ── MONEY ──
  v_w0 := pg_temp.w_45();
  perform cmd.assume_identity(c_uid1);
  perform world.tax_rate(v_por, v_a);
  perform public.port_fee(v_por, v_a, 1000000);
  perform public.port_dues(v_por, v_a, 1000000);
  perform world.snapshot();
  perform world.nation_standings();
  perform public.crown_aid(null);
  if pg_temp.w_45() <> v_w0 then
    raise exception 'PROOF 45 FAIL: reading the free ports moved gold: % -> %', v_w0, pg_temp.w_45();
  end if;
  raise notice 'PASS: BRETHREN_MONEY — W unchanged to the ducat across the quotes, the crown, cargo and navy runs, the boards, and a company founded under the pirates (moved from Port Royal)';
end
$$;

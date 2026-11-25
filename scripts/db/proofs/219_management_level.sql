-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 219 - THE MANAGEMENT LEVEL, AND TRADING'S BENEFITS  (migration 0515; owner-spec-red-2026-11-25.md R9, R10)
--
--   Management is earned by the sails of a fleet's standing job and locks nothing; its steps cut every fleet's wage. Trading's new steps
--   cut the city's tax on a profit and add to the first bargain's chance. No coin is made: the whole world's sum is the same before and
--   after. The run is BUILT (0498's way), so no sign hangs on the market. Rolled back by proof.mjs.
--
-- @pass MG_DARK   dark (as deployed): no Management on the levels page, the city's plain rate, the plain wage
-- @pass MG_FREE   lit, Management level 1: a company with every fleet it may own sets a job on each from its first minute and the tick starts them
-- @pass MG_EARN   her real job's sail, landed by voyage.settle, gives 5 Management once; the page shows the level
-- @pass MG_SUM    the same run, sold through the job's own orders: at Trading 20 and Management 20 she keeps more, the cities get that much less, and the world's sum (every company and every city) does not move
-- @pass MG_KEEPS  every step Trading opened before (0468, fleet room) is listed as it was
-- ══════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  c_a    constant uuid := '00000000-0219-4000-8000-0000000000a1';
  v_lis  uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_a    uuid; v_f uuid; v_f2 uuid; v_g uuid; v_good text; v_sell text; v_dest uuid;
  v_r0   numeric; v_w0 numeric; v_b0 jsonb; v_j jsonb; v_s0 numeric; v_s1 numeric;
  v_out  jsonb := '{}'; v_lit boolean; v_n int; k int;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'fleet_jobs_enabled', 'sea_courses_enabled', 'jobs_wait_enabled', 'level_unlocks_enabled', 'level_perks_on', 'level_skills_on', 'ship_stores_separate');
  update public.world_config set value = 'false'::jsonb where key in ('influence_enabled', 'run_guard_enabled', 'bargain_total_enabled', 'buy_tax_enabled', 'fleet_room_bite');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000;
  v_a := public.new_house(c_a, 'Casa da Prova 219', 'PRT');
  select f.id into v_f from public.fleets f where f.player_id = v_a;
  update public.players set ducats = 5000000 where id = v_a;
  perform cmd.assume_identity(c_a);
  select g.code, g.id, kl.code, kl.to_port into v_good, v_g, v_sell, v_dest
    from public.npc_known_legs(v_lis) kl
    join public.port_goods ps on ps.port_id = kl.to_port
    join public.goods g on g.id = ps.good_id
    join public.ports pd on pd.id = kl.to_port and pd.kind = 'HARBOUR'
   where public.port_offers(v_lis, g.id) and kl.nm >= 100
     and exists (select 1 from public.port_goods pl where pl.port_id = v_lis and pl.good_id = g.id)
     and not public.culture_refuses(pd.culture, g.culture_mask)
     and public.fleet_free_hold(v_f) >= 20 * g.bulk
   order by kl.nm, g.base_value desc, g.code limit 1;
  update public.port_goods pg set stock_target = 1000000, stock = 1000000000, affinity = 0.25, demand = 1, drift = 0, season_mod = 0, glut = 0.5, glut_at = now(), haul = 1, want_period = null
   where pg.port_id = v_lis and pg.good_id = v_g;
  update public.port_goods pg set stock_target = 1000000, stock = 0, affinity = 3, demand = 1, drift = 0, season_mod = 0, glut = -0.5, glut_at = now(), haul = 1, want_period = null
   where pg.port_id = v_dest and pg.good_id = v_g;
  v_j := jsonb_build_object('good', v_good, 'buy', 'LIS', 'sell', v_sell);

  -- MG_DARK
  v_r0 := world.tax_rate(v_dest, v_a);
  v_w0 := public.fleet_wage(v_f, false);
  if public.management_on() or exists (select 1 from jsonb_array_elements(world.levels() #> '{level_skills,skills}') e where e->>'code' = 'management') or v_r0 <= 0 or v_w0 <= 0 then
    raise exception 'MG_DARK: % %', v_r0, v_w0;
  end if;
  raise notice 'PASS: MG_DARK - no Management on the page; % asks % %%, the wage is % a day', v_sell, round(v_r0 * 100, 2), v_w0;

  -- MG_FREE
  update public.world_config set value = 'true'::jsonb where key in ('management_level_enabled', 'trade_benefits_enabled');
  begin
    foreach k in array array[2] loop
      insert into public.fleets
      select (jsonb_populate_record(null::public.fleets, to_jsonb(f) || jsonb_build_object('id', gen_random_uuid(), 'name', 'Frota ' || k, 'version', 1))).* from public.fleets f where f.id = v_f;
      insert into public.ships
      select (jsonb_populate_record(null::public.ships, to_jsonb(s) || jsonb_build_object('id', gen_random_uuid(), 'name', 'Nau ' || k,
               'fleet_id', (select f.id from public.fleets f where f.player_id = v_a and f.name = 'Frota ' || k)))).* from public.ships s where s.fleet_id = v_f;
    end loop;
    for v_f2 in select f.id from public.fleets f where f.player_id = v_a loop
      if not coalesce((cmd.set_fleet_job(v_f2, 'fixed', v_j)->>'ok')::boolean, false) then
        raise exception 'MG_FREE: a job is refused: %', cmd.set_fleet_job(v_f2, 'fixed', v_j);
      end if;
    end loop;
    call public.tick_fleet_jobs(false);
    select count(*) into v_n from public.fleet_jobs j join public.fleets f on f.id = j.fleet_id where j.player_id = v_a and j.paused_reason is null and j.runs = 1 and f.status = 'SAILING';
    if v_n <> 2 or coalesce((select lx.xp from public.level_xp lx where lx.player_id = v_a and lx.skill = 'management'), 0) <> 0 then
      raise exception 'MG_FREE: % of 2 fleets started: %', v_n, (select jsonb_agg(to_jsonb(j)) from public.fleet_jobs j where j.player_id = v_a);
    end if;
    raise exception using errcode = 'ZP219', message = 'rolled back';
  exception when sqlstate 'ZP219' then null;
  end;
  raise notice 'PASS: MG_FREE - a new company, Management level 1: two fleets (all a new company may own), two jobs, two sails';

  -- MG_EARN and MG_SUM: the same run twice, from the same world: without the steps, then at Trading 20 and Management 20
  foreach v_lit in array array[false, true] loop
    begin
      if v_lit then
        insert into public.house_level_marks (player_id, track, level) values (v_a, 'trading', 20) on conflict (player_id, track) do update set level = 20;
        insert into public.level_xp (player_id, skill, xp) values (v_a, 'management', public.level_begins('management', 20)::int);
        update public.world_config set value = 'false'::jsonb where key = 'level_skills_on';   -- no grant on a level written by hand (the book is a chain)
      end if;
      perform cmd.set_fleet_job(v_f, 'fixed', v_j);
      v_s0 := (select sum(p.ducats) from public.players p) + (select sum(public.treasury_balance(p.id)) from public.ports p where p.kind = 'HARBOUR');
      call public.tick_fleet_jobs(false);
      for k in 1 .. 12 loop
        exit when (select f.status from public.fleets f where f.id = v_f) <> 'SAILING';
        update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute' where fleet_id = v_f and status = 'SAILING';
        perform world.fleets();
      end loop;
      v_s1 := (select sum(p.ducats) from public.players p) + (select sum(public.treasury_balance(p.id)) from public.ports p where p.kind = 'HARBOUR');
      if not exists (select 1 from public.orders o where o.fleet_id = v_f and o.verb = 'SELL' and o.status = 'done') then
        raise exception 'MG_SUM: she did not sell: %', (select jsonb_agg(jsonb_build_array(o.raw_text, o.status, o.error_message)) from public.orders o where o.fleet_id = v_f);
      end if;
      v_out := v_out || jsonb_build_object(v_lit::text, jsonb_build_object('moved', v_s1 - v_s0,
        'tax', (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.player_id = v_a and t.kind = 'TAX'),
        'wages', (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.player_id = v_a and t.kind = 'WAGES'),
        'sold', (select coalesce(sum(-t.ducats), 0) from public.treasury_flows t where t.player_id = v_a and t.kind = 'SELL'),
        'hers', (select p.ducats from public.players p where p.id = v_a), 'wage', public.fleet_wage(v_f, false),
        'xp', (select lx.xp from public.level_xp lx where lx.player_id = v_a and lx.skill = 'management'),
        'book', (select count(*) from public.level_book b where b.player_id = v_a and b.activity = 'job_sail'),
        'page', exists (select 1 from jsonb_array_elements(world.levels() #> '{level_skills,skills}') e where e->>'code' = 'management')));
      raise exception using errcode = 'ZP219', message = 'rolled back';
    exception when sqlstate 'ZP219' then null;
    end;
  end loop;
  if (v_out #>> '{false,xp}')::int <> 5 or (v_out #>> '{false,book}')::int <> 1 or not (v_out #>> '{false,page}')::boolean then
    raise exception 'MG_EARN: %', v_out->'false';
  end if;
  raise notice 'PASS: MG_EARN - one sail of her job to %: Management 5, one grant, the level on the page', v_sell;
  if (v_out #>> '{false,moved}')::numeric <> 0 or (v_out #>> '{true,moved}')::numeric <> 0 or v_out #> '{false,sold}' is distinct from v_out #> '{true,sold}'
     or (v_out #>> '{true,tax}')::numeric >= (v_out #>> '{false,tax}')::numeric or (v_out #>> '{true,wage}')::numeric <> round(v_w0 * 0.9, 4)
     or (v_out #>> '{true,wages}')::numeric > (v_out #>> '{false,wages}')::numeric
     or (v_out #>> '{true,hers}')::numeric - (v_out #>> '{false,hers}')::numeric
        <> (v_out #>> '{false,tax}')::numeric - (v_out #>> '{true,tax}')::numeric + (v_out #>> '{false,wages}')::numeric - (v_out #>> '{true,wages}')::numeric then
    raise exception 'MG_SUM: %', v_out;
  end if;
  raise notice 'PASS: MG_SUM - sold for % either way; the city''s tax % is %, the wages % are %: she keeps % more, the cities get that much less; the world''s sum moved 0 and 0',
    v_out #>> '{false,sold}', v_out #>> '{false,tax}', v_out #>> '{true,tax}', v_out #>> '{false,wages}', v_out #>> '{true,wages}',
    (v_out #>> '{true,hers}')::numeric - (v_out #>> '{false,hers}')::numeric;

  -- MG_KEEPS
  v_b0 := public.level_benefits('trading', 10);
  update public.world_config set value = 'false'::jsonb where key = 'trade_benefits_enabled';
  if not v_b0 @> public.level_benefits('trading', 10) or jsonb_array_length(v_b0) - jsonb_array_length(public.level_benefits('trading', 10)) <> 10
     or (select count(*) from jsonb_array_elements(v_b0) b where b->>'perk' in ('trade_routes', 'fleet_ships', 'yard_fee')) <> 17 then
    raise exception 'MG_KEEPS: a step of Trading is gone';
  end if;
  raise notice 'PASS: MG_KEEPS - Trading lists its % lines as before and 10 more', jsonb_array_length(v_b0) - 10;
end $p$;

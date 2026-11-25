-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 220 - THE PASSIVE SETTINGS OF A FIXED JOB  (migration 0516; owner-spec-2026-11-25.md, slide 9)
--
--   Buy under, sell over, crew, days of food and water, a number of times, stop under a profit, stop over a damage. Out of range she waits
--   and says why, on the one wait of 0498. Played through the job's door, the real tick and a real voyage. The run is BUILT (0498's way):
--   no sign hangs on the market. Rolled back by proof.mjs.
--
-- @pass PS_DARK    dark (as deployed): the settings are not kept and the plan is BUY ALL
-- @pass PS_FREE    lit, a company of level 1 in everything: every setting is taken; a bad number is refused and the old job stands
-- @pass PS_BUY     too dear: the tick orders nothing, the job is not stopped, her row says the price and her limit, and the next tick asks nothing
-- @pass PS_RESUME  the price under her limit and her time come: the tick starts her by itself; the crew and the stores are taken on first
-- @pass PS_SELL    the price falls at sea: she arrives, keeps her cargo and waits with the reason; the price back, she sells it; the count ends after its run
-- @pass PS_PROFIT  a run that would leave less than her figure: the job STOPS, and says both sums
-- @pass PS_DAMAGE  a hull worse than her figure: the job STOPS, and says both
-- ══════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  c_a    constant uuid := '00000000-0220-4000-8000-0000000000a1';
  v_lis  uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_a    uuid; v_f uuid; v_g uuid; v_good text; v_sell text; v_dest uuid;
  v_j    jsonb; v_r jsonb; v_w jsonb; v_b numeric; v_s numeric; v_at timestamptz; v_jr public.fleet_jobs%rowtype; v_max int; v_n numeric; k int; v_txt text;
begin
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'jobs_wait_enabled', 'run_guard_enabled', 'assign_home_enabled', 'ship_stores_separate');
  update public.world_config set value = 'false'::jsonb where key in ('bargain_total_enabled', 'buy_tax_enabled');
  update public.world_config set value = '1000000'::jsonb where key = 'run_guard_hull_share';   -- the purse's question alone
  v_a := public.new_house(c_a, 'Casa da Prova 220', 'PRT');
  select f.id into v_f from public.fleets f where f.player_id = v_a;
  update public.players set ducats = 5000000 where id = v_a;
  perform cmd.assume_identity(c_a);
  select g.code, g.id, kl.code, kl.to_port into v_good, v_g, v_sell, v_dest
    from public.npc_known_legs(v_lis) kl
    join public.port_goods ps on ps.port_id = kl.to_port
    join public.goods g on g.id = ps.good_id
    join public.ports pd on pd.id = kl.to_port and pd.kind = 'HARBOUR'
   where public.port_offers(v_lis, g.id)
     and exists (select 1 from public.port_goods pl where pl.port_id = v_lis and pl.good_id = g.id)
     and not public.culture_refuses(pd.culture, g.culture_mask)
     and public.fleet_free_hold(v_f) >= 20 * g.bulk
   order by kl.nm, g.base_value desc, g.code limit 1;
  update public.port_goods pg set stock_target = 1000000, stock = 1000000000, affinity = 0.25, demand = 1, drift = 0, season_mod = 0, glut = 0.5, glut_at = now(), haul = 1, want_period = null
   where pg.port_id = v_lis and pg.good_id = v_g;
  update public.port_goods pg set stock_target = 1000000, stock = 0, affinity = 3, demand = 1, drift = 0, season_mod = 0, glut = -0.5, glut_at = now(), haul = 1, want_period = null
   where pg.port_id = v_dest and pg.good_id = v_g;
  insert into public.port_treasury (port_id) values (v_dest) on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000 where port_id = v_dest;
  v_j := jsonb_build_object('good', v_good, 'buy', 'LIS', 'sell', v_sell);
  select q.avg_price into v_b from world.quote(v_lis, v_g, 1, 'buy', null, v_f) q;
  select q.avg_price into v_s from world.quote(v_dest, v_g, 1, 'sell', null, v_f) q;
  select sum(sb.crew_max) into v_max from public.ships s cross join lateral public.ship_base(s.id) sb where s.fleet_id = v_f;

  -- PS_DARK
  v_r := cmd.set_fleet_job(v_f, 'fixed', v_j || jsonb_build_object('under', 1, 'over', 1, 'crew', v_max, 'days', 5, 'stop_profit', 1, 'stop_damage', 1));
  if not coalesce((v_r->>'ok')::boolean, false) or v_r->'params' ?| array['under', 'over', 'crew', 'days', 'stop_profit', 'stop_damage']
     or public.fleet_job_plan(v_f) #>> '{lines,0,text}' is distinct from format('BUY %s ALL', v_good) or world.workers() ? 'settings' then
    raise exception 'PS_DARK: % / %', v_r, public.fleet_job_plan(v_f);
  end if;
  raise notice 'PASS: PS_DARK - the settings are not kept; "%"', public.fleet_job_plan(v_f) #>> '{lines,0,text}';

  -- PS_FREE
  update public.world_config set value = 'true'::jsonb where key = 'passive_settings_enabled';
  v_r := cmd.set_fleet_job(v_f, 'fixed', v_j || jsonb_build_object('under', round(v_b / 2, 2), 'over', 1, 'crew', v_max, 'days', 5, 'stop_profit', 1, 'stop_damage', 90, 'times', 1));
  if not coalesce((v_r->>'ok')::boolean, false) or not (v_r->'params' ?& array['under', 'over', 'crew', 'days', 'stop_profit', 'stop_damage', 'times', 'left'])
     or not (world.workers()->>'settings')::boolean or exists (select 1 from public.level_xp lx where lx.player_id = v_a and lx.xp > 0) then
    raise exception 'PS_FREE: %', v_r;
  end if;
  v_r := cmd.set_fleet_job(v_f, 'fixed', v_j || '{"under": -5}');
  if coalesce((v_r->>'ok')::boolean, true) or not ((select j.params from public.fleet_jobs j where j.fleet_id = v_f) ? 'times') then
    raise exception 'PS_FREE: a bad number is taken: %', v_r;
  end if;
  raise notice 'PASS: PS_FREE - a new company sets all seven; a price under nought is refused (%) and her job stands', v_r->>'error_message';

  -- PS_BUY
  call public.tick_fleet_jobs(false);
  select * into v_jr from public.fleet_jobs j where j.fleet_id = v_f;
  v_w := world.workers() #> '{workers,0}';
  v_at := v_jr.next_at;
  call public.tick_fleet_jobs(false);
  if v_jr.paused_reason is not null or v_jr.runs <> 0 or v_at is null or v_at < now() + interval '600 seconds' or exists (select 1 from public.orders o where o.fleet_id = v_f)
     or v_w #>> '{wait,code}' is distinct from 'range' or coalesce(v_w #>> '{wait,sentence}', '') !~ '^buys at [0-9,.]+, your limit [0-9,.]+$' or v_w->>'state' <> 'waiting'
     or (select j.next_at from public.fleet_jobs j where j.fleet_id = v_f) <> v_at then
    raise exception 'PS_BUY: % / %', to_jsonb(v_jr), v_w;
  end if;
  raise notice 'PASS: PS_BUY - "%": no order, not stopped, asked again % s on, not before', v_w #>> '{wait,sentence}', round(extract(epoch from v_at - now()));

  -- PS_RESUME: one hand short of her berths, her casks empty
  update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb) - 1, water_t = 0, food_t = 0 where s.fleet_id = v_f;
  update public.ports set crew_pool = 100 where id = v_lis;
  update public.fleet_jobs set params = params || jsonb_build_object('under', v_b * 2, 'over', round(v_s / 2, 2)), next_at = now() - interval '1 second' where fleet_id = v_f;
  call public.tick_fleet_jobs(false);
  select * into v_jr from public.fleet_jobs j where j.fleet_id = v_f;
  select string_agg(o.raw_text, ' / ' order by o.seq) into v_txt from public.orders o where o.fleet_id = v_f;
  v_n := public.fleet_cargo_qty(v_f, v_good);
  if v_jr.runs <> 1 or v_jr.paused_reason is not null or (select f.status from public.fleets f where f.id = v_f) <> 'SAILING' or v_n < 1 or v_txt ~ 'SELL'
     or v_txt !~ '^HIRE [0-9]+ / PROVISION DAYS 5 / BUY ' or (select sum(s.crew) from public.ships s where s.fleet_id = v_f) <> v_max or (v_jr.params->>'left')::int <> 0 then
    raise exception 'PS_RESUME: % / %', v_txt, to_jsonb(v_jr);
  end if;
  raise notice 'PASS: PS_RESUME - she starts by herself: %; % hands aboard, % % in the hold', v_txt, v_max, v_n, v_good;

  -- PS_SELL
  update public.port_goods pg set stock = 1000000000, affinity = 0.25, glut = 0.5, glut_at = now() where pg.port_id = v_dest and pg.good_id = v_g;
  for k in 1 .. 12 loop
    exit when (select f.status from public.fleets f where f.id = v_f) <> 'SAILING';
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute' where fleet_id = v_f and status = 'SAILING';
    perform world.fleets();
  end loop;
  update public.fleets set ready_at = null where id = v_f;
  call public.tick_fleet_jobs(false);
  v_w := world.workers() #> '{workers,0}';
  if (select f.port_id from public.fleets f where f.id = v_f) is distinct from v_dest or public.fleet_cargo_qty(v_f, v_good) < 1
     or v_w #>> '{wait,code}' is distinct from 'range' or coalesce(v_w #>> '{wait,sentence}', '') !~ '^sells at [0-9,.]+, your limit [0-9,.]+$' then
    raise exception 'PS_SELL: at a fallen price: aboard %, % / %', public.fleet_cargo_qty(v_f, v_good), v_w,
      (select jsonb_agg(jsonb_build_array(o.raw_text, o.status, o.error_message) order by o.seq) from public.orders o where o.fleet_id = v_f);
  end if;
  v_txt := v_w #>> '{wait,sentence}';
  update public.port_goods pg set stock = 0, affinity = 3, glut = -0.5, glut_at = now() where pg.port_id = v_dest and pg.good_id = v_g;
  update public.fleet_jobs set next_at = now() - interval '1 second' where fleet_id = v_f;
  call public.tick_fleet_jobs(false);
  perform world.fleets();
  call public.tick_fleet_jobs(false);
  if public.fleet_cargo_qty(v_f, v_good) >= 1 or exists (select 1 from public.fleet_jobs j where j.fleet_id = v_f) or exists (select 1 from public.orders o where o.fleet_id = v_f and o.status = 'failed') then
    raise exception 'PS_SELL: the price back: aboard %, job %, orders %', public.fleet_cargo_qty(v_f, v_good), (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_f),
      (select jsonb_agg(jsonb_build_array(o.raw_text, o.status, o.error_message) order by o.seq) from public.orders o where o.fleet_id = v_f);
  end if;
  raise notice 'PASS: PS_SELL - "%": she kept her cargo; the price back she sold it all, and her one run being done the job ended', v_txt;

  -- PS_PROFIT, PS_DAMAGE (back at Lisbon)
  update public.fleets set port_id = v_lis, status = 'DOCKED', ready_at = null where id = v_f;
  v_r := public.fleet_run_quote(v_a, v_f, v_lis, v_good, v_sell, array[v_sell, 'LIS']);
  perform cmd.set_fleet_job(v_f, 'fixed', v_j || jsonb_build_object('stop_profit', coalesce((v_r->>'net')::numeric, 0) + 1));
  call public.tick_fleet_jobs(false);
  v_w := world.workers() #> '{workers,0}';
  if v_w #>> '{stop,code}' is distinct from 'E_STOP_PROFIT' or v_w->>'state' <> 'stopped' or coalesce(v_w #>> '{stop,sentence}', '') !~ '^this run would leave [0-9,]+, you stop under [0-9,]+$' then
    raise exception 'PS_PROFIT: % (quote %)', v_w, v_r;
  end if;
  raise notice 'PASS: PS_PROFIT - stopped: "%"', v_w #>> '{stop,sentence}';
  update public.ships s set durability = (select sb.durability from public.ship_base(s.id) sb) * 0.6 where s.fleet_id = v_f;
  perform cmd.set_fleet_job(v_f, 'fixed', v_j || '{"stop_damage": 30}');
  call public.tick_fleet_jobs(false);
  v_w := world.workers() #> '{workers,0}';
  if v_w #>> '{stop,code}' is distinct from 'E_STOP_DAMAGE' or v_w #>> '{stop,sentence}' is distinct from 'hull damage 40 %, you stop over 30 %' then
    raise exception 'PS_DAMAGE: %', v_w;
  end if;
  raise notice 'PASS: PS_DAMAGE - stopped: "%"', v_w #>> '{stop,sentence}';
end $p$;

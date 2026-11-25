-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 212 - NO RUINOUS RUN  (migration 0502, dark: run_guard_enabled; docs/dev-log/2026-11-25-no-ruinous-run.md)
--
--   A standing job starts a run only when her purse, after the BUY, covers the dock fees, the stores, the crew, a whole repair and one
--   storm's safe default, and her hull bears the passage; it cuts the BUY, or waits with a plain reason. Rolled back by proof.mjs.
--
-- @pass NR_DARK    dark: a fixed job with a thin purse is planned BUY ALL as before
-- @pass NR_HERS    the owner's own case: purse 8,240 at the Island of Mozambique, 899 black coral aboard, PLO DGA BAN MAL MAC ahead, the hull fresh: the run is not started, and the reason names both sums
-- @pass NR_BUY     the same run with the coin that bought the coral still in her purse: the BUY is cut to what leaves the fees, the stores, a repair and the storm, or the job waits; never less left than the need
-- @pass NR_COST    one read of the need in ms, over her chain (printed; fails only over 3 s)
-- @pass NR_WAIT    a thin purse through the real tick: no order, not stopped, asked again 600 s on, her row says why; the next tick asks nothing
-- @pass NR_DANGER  over the hull's bound the tick starts nothing and her row says "too dangerous for her hull"
-- @pass NR_RESUME  the coin is back and her time come: the tick starts her by itself
-- @pass NR_LINES   stores in their own space and in the hold: a thin purse's cut changes the BUY line alone, wherever it stands; every other line is the dark plan's, and a near-full cut sails
-- @pass NR_BEST    a Best job with a thin purse starts only a sale whose BUY leaves the need, or waits
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0502-4000-8000-0000000002a1';
  c_b    constant uuid := '00000000-0502-4000-8000-0000000002b1';
  v_a    uuid; v_f uuid; v_b uuid; v_fb uuid; v_lis uuid;
  v_isl  uuid := (select p.id from public.ports p where p.code = 'ISL');
  v_gid  uuid := (select g.id from public.goods g where g.code = 'black-coral');
  v_s    jsonb; v_l jsonb; v_n jsonb; v_n2 jsonb; v_p jsonb; v_w jsonb; v_bs jsonb; v_c jsonb;
  v_j    public.fleet_jobs%rowtype;
  v_cost numeric; v_t timestamptz; v_ms numeric; v_at timestamptz; v_v int;
  v_fee0 numeric; v_fee1 numeric; v_basis numeric;
begin
  if (proof.pin_market('00000000-0502-4000-8000-000000000212'::uuid, 'proof-212') ->> 'nonzero')::int < 14000 then
    raise exception 'PROOF 212: the market was not pinned';
  end if;
  v_a := public.new_house(c_a, 'Casa da Reserva 212', 'PRT');
  select f.id, f.port_id into v_f, v_lis from public.fleets f where f.player_id = v_a;
  v_b := public.new_house(c_b, 'Casa Segunda 212', 'PRT');
  select f.id into v_fb from public.fleets f where f.player_id = v_b;
  update public.world_config set value = 'true'::jsonb
   where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'sea_choices_enabled', 'economy_closed', 'city_treasury_enabled');
  perform cmd.assume_identity(c_a);

  -- NR_DARK
  update public.players p set ducats = 3000 where p.id = v_a;
  v_bs := world.best_sales(v_f, v_lis);
  select g.e into v_c from jsonb_array_elements(v_bs->'goods') g(e)
   where (g.e->>'pays')::boolean and g.e->>'port' is not null and (g.e->>'profit')::numeric > 0 and g.e->>'basis' is distinct from 'on_board'
     and g.e->'near' is distinct from 'false'::jsonb and jsonb_typeof(g.e->'seconds') = 'number'
   order by (g.e->>'seconds')::numeric, g.e->>'good' limit 1;
  if v_c is null then
    raise exception 'NR_DARK: no paying run from Lisbon in the pinned market: the scene proves nothing';
  end if;
  perform cmd.set_fleet_job(v_f, 'fixed', jsonb_build_object('good', v_c->>'good', 'buy', 'LIS', 'sell', v_c->>'port'));
  v_p := public.fleet_job_plan(v_f);
  if public.run_guard_on() or (select e->>'text' from jsonb_array_elements(v_p->'lines') e where e->>'text' like 'BUY %') is distinct from format('BUY %s ALL', v_c->>'good') then
    raise exception 'NR_DARK: dark, the plan moved: %', left(v_p::text, 300);
  end if;
  raise notice 'PASS: NR_DARK — dark, purse 3,000: "%" is planned as before', (select e->>'text' from jsonb_array_elements(v_p->'lines') e where e->>'text' like 'BUY %');

  -- NR_HERS, NR_BUY, NR_COST: her state on the morning of the 25th, rolled back after
  begin
    delete from public.fleet_jobs where fleet_id = v_f;
    update public.fleets set port_id = v_isl, status = 'DOCKED', ready_at = null where id = v_f;
    v_s := public.fleet_job_sails(v_f, v_isl, array['PLO', 'DGA', 'BAN', 'MAL', 'MAC']);
    if not (v_s ? 'lines') then
      raise exception 'NR_HERS: her chain cannot be sailed in this world: %', v_s;
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'run_guard_enabled';
    -- the BUY first: the coin that bought 899 still hers, the hold empty
    update public.port_goods pg set stock_target = 20000, stock = 20000 where pg.port_id = v_isl and pg.good_id = v_gid;   -- the quay has her 899
    select q.units, q.total into v_ms, v_cost from world.quote(v_isl, v_gid, 899, 'buy', null, v_f) q;
    if v_ms is distinct from 899 then
      raise exception 'NR_BUY: the quay at the Island of Mozambique does not sell 899 here (%)', v_ms;
    end if;
    update public.players p set ducats = 8240 + round(v_cost) where p.id = v_a;
    v_l := jsonb_build_array(jsonb_build_object('text', 'BUY black-coral 899')) || (v_s->'lines') || jsonb_build_array(jsonb_build_object('text', 'SELL black-coral ALL'));
    v_t := clock_timestamp();
    v_n2 := public.run_need(v_a, v_f, v_isl, v_l);
    v_ms := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);
    -- then as she sailed: 899 aboard at what they cost, 8,240 in the purse
    update public.players p set ducats = 8240 where p.id = v_a;
    -- at the cost that makes Diego Garcia's dock fee the 3,233 she was charged (and at least the 200,000 whose storm is 5,000)
    v_fee0 := public.port_fee((select p.id from public.ports p where p.code = 'DGA'), v_a, 0);
    v_fee1 := public.port_fee((select p.id from public.ports p where p.code = 'DGA'), v_a, 1000000);
    v_basis := greatest(200000, (3233 - v_fee0) * 1000000 / nullif(v_fee1 - v_fee0, 0));
    perform public.fleet_load(v_f, 'black-coral', 899, round(coalesce(v_basis, 200000) / 899, 2));
    v_l := (v_s->'lines') || jsonb_build_array(jsonb_build_object('text', 'SELL black-coral ALL'));
    v_n := public.run_need(v_a, v_f, v_isl, v_l);
    raise notice 'TIMING: at the default bound: %', coalesce(v_n->>'wait', 'starts') || coalesce(', "' || (v_n->>'sentence') || '"', '') || format(', expected hull loss %s of %s', v_n->>'hull', v_n->>'hull_left');
    if not (v_n ? 'wait') then
      raise exception 'NR_HERS: her run is started: %', v_n;
    end if;
    update public.world_config set value = '1000000'::jsonb where key = 'run_guard_hull_share';   -- the purse's question alone
    v_n := public.run_need(v_a, v_f, v_isl, v_l);
    if v_n->>'wait' is distinct from 'purse' or v_n->>'sentence' !~ '^purse 8,240, her way to the sale costs [0-9,]+$' then
      raise exception 'NR_HERS: her purse does not stop the run: %', v_n;
    end if;
    raise notice 'PASS: NR_HERS — "%": stores %, dock fees % over % sails, crew %, a repair %, one storm %', v_n->>'sentence',
      v_n->>'stores', v_n->>'dock', jsonb_array_length(v_s->'lines'), v_n->>'crew', v_n->>'reserve', v_n->>'sea';
    raise notice 'TIMING: her cargo at cost % here: Diego Garcia''s dock fee %', round(v_basis), public.port_fee((select p.id from public.ports p where p.code = 'DGA'), v_a, public.fleet_stock_at_cost(v_f));
    raise notice 'TIMING: ISL to PLO alone: %', public.run_need(v_a, v_f, v_isl, jsonb_build_array(v_s->'lines'->0) || jsonb_build_array(jsonb_build_object('text', 'SELL black-coral ALL')));
    if v_n2 ? 'wait' then
      if v_n2->>'wait' not in ('purse', 'danger') then
        raise exception 'NR_BUY: %', v_n2;
      end if;
    elsif not (v_n2 ? 'line') or (v_n2->>'after')::numeric < 0 or (v_n2->>'units')::numeric >= 899 then
      raise exception 'NR_BUY: the BUY is neither cut nor held: %', v_n2;
    end if;
    raise notice 'PASS: NR_BUY — % in the purse before the BUY (899 cost %): %', 8240 + round(v_cost), round(v_cost),
      coalesce('waits: ' || (v_n2->>'sentence'), format('"%s", spends %s, need %s, free %s', v_n2->>'line', v_n2->>'buy', v_n2->>'need', v_n2->>'after'));
    if v_ms > 3000 then
      raise exception 'NR_COST: one read took % ms', v_ms;
    end if;
    raise notice 'PASS: NR_COST — one read of the need over % sails: % ms', jsonb_array_length(v_s->'lines'), v_ms;
    raise exception using errcode = 'ZN212', message = 'her scene rolled back';
  exception when sqlstate 'ZN212' then
    null;
  end;

  -- NR_LINES: the same fixed plan dark and lit, the stores in their own space and in the hold (0508 over this file puts a PROVISION first)
  begin
    update public.world_config set value = '1000000'::jsonb where key = 'run_guard_hull_share';
    update public.ships set water_t = 0, food_t = 0 where fleet_id = v_f;   -- empty casks: 0508 takes her stores on first
    foreach v_v in array array[1, 0] loop
      update public.world_config set value = to_jsonb(v_v = 1) where key = 'ship_stores_separate';
      update public.players p set ducats = 40000 where p.id = v_a;
      update public.players p set ducats = ceil((public.fleet_buy_capacity(v_f, (select g.id from public.goods g where g.code = v_c->>'good'))->>'est_total')::numeric) where p.id = v_a;   -- the ALL takes every coin
      update public.world_config set value = 'false'::jsonb where key = 'run_guard_enabled';
      v_p := public.fleet_job_plan(v_f);
      update public.world_config set value = 'true'::jsonb where key = 'run_guard_enabled';
      v_w := public.fleet_job_plan(v_f);
      if not (v_w ? 'lines') or (select count(*) from jsonb_array_elements(v_w->'lines') e where e->>'text' ~ ('^BUY ' || (v_c->>'good') || ' [0-9.]+$')) <> 1
         or public.run_cut(v_w->'lines', format('BUY %s ALL', v_c->>'good')) is distinct from v_p->'lines' then
        raise exception 'NR_LINES: separate %: the cut moved another line: % from %', v_v, left(v_w::text, 400), left(v_p::text, 400);
      end if;
      raise notice 'TIMING: stores %: %', case v_v when 1 then 'in their own space' else 'in the hold' end,
        (select string_agg(e->>'text', ' / ') from jsonb_array_elements(v_w->'lines') e);
    end loop;
    -- in the hold, a deep purse: the ALL is what fits beside the stores; then the same run 200 coin short of its need sails
    update public.players p set ducats = 50000000 where p.id = v_a;
    v_n2 := public.run_need(v_a, v_f, v_lis, v_p->'lines');
    if v_n2 ? 'line' or not coalesce((v_n2->>'ok')::boolean, false) then
      raise exception 'NR_LINES: a deep purse is cut or held: %', v_n2;
    end if;
    raise notice 'TIMING: in the hold, a deep purse: % units, the hold free takes %', v_n2->>'units',
      floor(public.fleet_free_hold(v_f) / (select g.bulk from public.goods g where g.code = v_c->>'good'));
    update public.players p set ducats = (v_n2->>'buy')::numeric + (v_n2->>'need')::numeric - 200 where p.id = v_a;
    v_w := public.fleet_job_plan(v_f);
    update public.fleet_jobs set next_at = null where fleet_id = v_f;
    call public.tick_fleet_jobs(false);
    if exists (select 1 from public.orders o where o.fleet_id = v_f and o.status = 'failed') or (select f.status from public.fleets f where f.id = v_f) <> 'SAILING'
       or public.fleet_cargo_qty(v_f, v_c->>'good') < 1 then
      raise exception 'NR_LINES: the near-full cut did not sail: % / %', (select jsonb_agg(to_jsonb(o)) from public.orders o where o.fleet_id = v_f), (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_f);
    end if;
    raise notice 'TIMING: 200 coin short: % ; sailed with % aboard', (select string_agg(e->>'text', ' / ') from jsonb_array_elements(v_w->'lines') e), public.fleet_cargo_qty(v_f, v_c->>'good');
    if to_regprocedure('public.fleet_trip_stores(uuid,uuid,text[])') is not null and v_w #>> '{lines,0,text}' !~ '^PROVISION DAYS ' then
      raise exception 'NR_LINES: 0508 is here and the plan has no PROVISION first: the scene proves nothing: %', left(v_w::text, 300);
    end if;
    raise notice 'PASS: NR_LINES — the BUY line alone is cut, with the stores in their own space and in the hold';
    raise exception using errcode = 'ZN213', message = 'lines scene rolled back';
  exception when sqlstate 'ZN213' then
    null;
  end;

  -- NR_WAIT, through the tick (a purse under one repair)
  update public.world_config set value = 'true'::jsonb where key = 'run_guard_enabled';
  update public.world_config set value = '1000000'::jsonb where key = 'run_guard_hull_share';
  update public.players p set ducats = 20 where p.id = v_a;
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_f;
  v_w := world.workers() #> '{workers,0}';
  v_at := v_j.next_at;
  if v_j.paused_reason is not null or v_j.runs <> 0 or v_at < now() + interval '600 seconds' or v_j.last->>'wait' is distinct from 'purse'
     or exists (select 1 from public.orders o where o.fleet_id = v_f) or v_w->>'state' <> 'waiting' or v_w #>> '{wait,sentence}' !~ '^purse 20, ' then
    raise exception 'NR_WAIT: she did not wait: % / %', to_jsonb(v_j), v_w;
  end if;
  call public.tick_fleet_jobs(false);
  if (select j.next_at from public.fleet_jobs j where j.fleet_id = v_f) <> v_at then
    raise exception 'NR_WAIT: asked again before its time';
  end if;
  raise notice 'PASS: NR_WAIT — "%", no order, not stopped, asked again in % s', v_w #>> '{wait,sentence}', round(extract(epoch from v_at - now()));

  -- NR_DANGER
  update public.players p set ducats = 5000000 where p.id = v_a;
  update public.world_config set value = '-1'::jsonb where key = 'run_guard_hull_share';
  update public.fleet_jobs set next_at = now() - interval '1 second' where fleet_id = v_f;
  call public.tick_fleet_jobs(false);
  v_w := world.workers() #> '{workers,0}';
  if v_w #>> '{wait,code}' is distinct from 'danger' or v_w #>> '{wait,sentence}' is distinct from 'too dangerous for her hull'
     or exists (select 1 from public.orders o where o.fleet_id = v_f) then
    raise exception 'NR_DANGER: over the bound: %', v_w;
  end if;
  raise notice 'PASS: NR_DANGER — "%"', v_w #>> '{wait,sentence}';

  -- NR_RESUME
  update public.world_config set value = '1000000'::jsonb where key = 'run_guard_hull_share';
  update public.fleet_jobs set next_at = now() - interval '1 second' where fleet_id = v_f;
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_f;
  if v_j.runs <> 1 or v_j.paused_reason is not null or (select f.status from public.fleets f where f.id = v_f) <> 'SAILING' then
    raise exception 'NR_RESUME: she did not start by herself: %', to_jsonb(v_j);
  end if;
  raise notice 'PASS: NR_RESUME — with the coin back the tick started her (runs %)', v_j.runs;

  -- NR_BEST: another company, three purses, the default bound
  perform cmd.assume_identity(c_b);
  update public.world_config set value = '0.5'::jsonb where key = 'run_guard_hull_share';
  foreach v_v in array array[400, 8240, 40000] loop
    update public.players p set ducats = v_v where p.id = v_b;
    delete from public.fleet_jobs where fleet_id = v_fb;
    perform cmd.set_fleet_job(v_fb, 'best', '{}'::jsonb);
    v_p := public.fleet_job_plan(v_fb);
    if v_p ? 'lines' then
      v_n := public.run_need(v_b, v_fb, v_lis, v_p->'lines');
      if not coalesce((v_n->>'ok')::boolean, false) or v_n ? 'line' or coalesce((v_n->>'after')::numeric, -1) < 0 then
        raise exception 'NR_BEST: purse %: a run that leaves less than its need is planned: % / %', v_v, left(v_p::text, 300), v_n;
      end if;
      raise notice 'TIMING: purse %: "%" to %, spends %, need %, free %, hull %', v_v, (select e->>'text' from jsonb_array_elements(v_p->'lines') e where e->>'text' like 'BUY %'), v_p #>> '{note,to}', v_n->>'buy', v_n->>'need', v_n->>'after', v_n->>'hull';
    elsif v_p->>'wait' not in ('purse', 'danger', 'nothing') then
      raise exception 'NR_BEST: purse %: %', v_v, left(v_p::text, 300);
    else
      raise notice 'TIMING: purse %: waits %, "%"', v_v, v_p->>'wait', v_p->>'sentence';
    end if;
  end loop;
  raise notice 'PASS: NR_BEST — three purses, each run leaves its need or waits';
end $p$;

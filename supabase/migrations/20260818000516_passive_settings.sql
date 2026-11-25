-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (the settings are dark until the owner lights passive_settings_enabled; a laden run only goes on or waits)
-- 0516 - THE PASSIVE SETTINGS OF A FIXED JOB  (dark: the owner's switch passive_settings_enabled, false. Slice `passive-settings`,
--   docs/design/owner-spec-2026-11-25.md "PASSIVE METHOD", owner-spec-red-2026-11-25.md R9/R10, slide 9)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25: "You can choose to stop or continue based on your settings. Settings include buying at a certain price range,
--   selling at a certain price range. etc." and "The PASSIVE METHOD should also require you to make provision, crew up in the setting."
--   Slide 9: "If the price is out of your range, the FLEET waits and tells you why."
--
-- LIT, a FIXED job may carry, in its params (public.fleet_job_set_for, judged once by public.job_settings_param; NO LEVEL IS ASKED, so a
-- new company sets every one of them):
--   under        BUY UNDER: she buys only the units whose own price on the quay is at or under it (the limit of a BUY order, world.quote's
--                p_limit: 0005's rule); a bargain and the buy tax come on top, as on every order
--   over         SELL OVER: the same at the sale (world.quote's p_limit, p_side sell), judged when the run starts and AGAIN where she sells
--                (her sale is then its own step: the plan of a run with `over` ends at the sale's harbour, and the next plan sells there)
--   crew         the hands she holds: hired up to it where she buys (a HIRE line), never more than her berths, none where none can be had
--   days         the days of food and water she holds where she buys (a PROVISION DAYS line; her casks may hold fewer)
--   stop_profit  STOP when the run's quote leaves less (after the tax, dock fees, wages, stores and hires): the job stops, E_STOP_PROFIT
--   stop_damage  STOP when her worst hull has lost more than it, in per cent: the job stops, E_STOP_DAMAGE (cargo she carries to her
--                sale is sold first)
--   (repeat, or a number of times: the count `times` is 0492's and stays. bargain: 0506's, at Negotiation 8, 12, 16, stays.)
-- OUT OF RANGE SHE WAITS, NOT STOPPED: {wait: range, sentence}, written by THE SAME BRANCH OF public.fleet_job_note that writes 0498's
--   "prices low" (one wait authority: asked again public.job_wait_s on, her sentence on her row through public.workers_for's `wait`). A
--   purse that cannot pay the crew and the stores waits as 0502's `purse`.
-- ONE QUOTE: public.job_settings_judge asks public.fleet_run_quote (0498) for the run and world.quote for the limits; it never prices by
--   itself. With the job's range cutting the load it answers the BUY line, so 0498's own check is not asked a second time.
-- DARK, or a job with none of the six: {} and the plan is the plan it was (asserted to the letter).
-- NOT CHANGED by the settings: a Best job, a land haul, a hand's order; any command; any table; the tick; the ledger.
-- A JOB STOPPED FOR HER HULL GOES ON ONCE SHE IS MENDED (public.job_damage_mended: the same reading, public.fleet_damage_pct): due again,
--   as 0500 does for a flagship, and the stop is lifted by the note. Dark, it goes on as a plain job.
-- world.workers() serves `settings` while lit: for each fleet her hold, what is left of it (stores in the hold: after the days her job keeps)
--   and the least and most crew, so a screen works nothing out (public.job_settings_room).
-- A LADEN RUN IS JUDGED (no switch; the review of 0504's laden run, 2026-11-25; proof 243). 0504 let a fixed job at its buy harbour, her good aboard and no
--   unit more to be had, sail with it; it was not judged. Now:
--   public.fleet_run_quote   the quote of a run counts the load aboard at what she paid for it (public.fleet_cargo_basis, as a Best card of her cargo
--                            does): `units` to buy, `load` to sell, `net` of both. With nothing of the good aboard: the answer it was. (4 hunks)
--   public.fleet_job_plan    a laden run is quoted whether or not jobs_wait_enabled is lit, and waits `low` like any run when it does not pay: no token
--                            load sails. One unit of room is no reason to wait: the whole load is judged. A BUY that cannot be is left out. (6 hunks)
--   public.run_need          (run_guard_enabled) nothing to buy and cargo to sell: her cargo is her coin. Straight to the sale she needs her stores and her hands
--                            alone; by way of other harbours their fees and a storm's default too; never the repair; a BUY cut to nothing beside a load that pays its way is left out. (4 hunks)
--   public.fleet_job_ends    (bring home) the shed holds exactly her load: she buys no more and brings it home. The shed holds less than
--                            her load: she WAITS (`low`), not stopped (a STORE is whole or refused). Nothing aboard: stopped E_SHED_FULL, as 0492. (1 hunk)
--   A land haul whose good changed: the old load (a good the land makes) is stored first when there is nothing of the new to take. (in fleet_job_plan)
-- THE HUNKS (24; each once, each reverses): fleet_job_plan x9, fleet_job_note x3, fleet_jobs_due x1, fleet_job_set_for x1, world.workers x1, fleet_run_quote x4,
--   run_need x4, fleet_job_ends x1. Their anchors are in
--   none of 0499, 0500, 0508 or 0509's hunks. PROVISION: where a plan already has one (0508's), its days are raised, not a second line.
-- COST: dark, one switch read a fixed plan and one a workers read. Lit, a job with settings is at most one fleet_run_quote and five world.quote
--   a plan, instead of 0498's one quote; a waiting job is asked once in 600 s or more.
-- ROWS: one world_config row. -- budget: none (no table, no job, no index). -- retention: none.
-- LOCKS: one INSERT, CREATE FUNCTION x7, CREATE OR REPLACE x8. TIME: a second. BUDGET: statement_timeout 60 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, passive_settings_enabled false: a job that carries settings runs as a plain fixed job. FULL: a
--   migration reversing the hunks (OLD texts below verbatim) and dropping the seven functions and the knob.
-- SELF-ASSERT: hunks once and reversing; no other function moved; grants and settings unmoved; the new functions STABLE and server only.
--   THE PROBE (rolled back; the run is BUILT as 0498's: static rows choose the pair, its two market rows are written, the hull, the crew and
--   the purse are set): no step asks the live market, dice or companies a sign. Proof 220 plays it through the real tick.
-- VERSION: 0516 (after 0515; the lead deploys in number order).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.fleet_job_plan(uuid)', 'public.fleet_job_note(uuid,jsonb)', 'public.fleet_job_set_for(uuid,uuid,text,jsonb)', 'world.workers()', 'public.fleet_jobs_due()',
                                    'public.fleet_run_quote(uuid,uuid,uuid,text,text,text[])', 'public.run_need(uuid,uuid,uuid,jsonb)', 'public.fleet_job_ends(uuid,uuid,jsonb,text)'];
  c_new    constant text[] := array['public.passive_settings_on()', 'public.job_settings_param(uuid,jsonb)', 'public.job_settings_judge(uuid,text,jsonb)',
                                    'public.job_settings_lines(jsonb,jsonb)', 'public.fleet_damage_pct(uuid)', 'public.job_damage_mended(uuid)', 'public.job_settings_room(uuid)'];
  c_knobs  constant text[] := array['passive_settings_enabled'];
  c_ua     constant uuid := '00000000-0516-4000-8000-0000000000a1';
  v_t0         timestamptz := clock_timestamp();
  x            record;
  v_def        text;
  v_pre        text;
  v_old        text;
  v_new        text;
  v_n          int;
  v_fn_before  text;
  v_meta       text;
  v_cfg_before text;
  v_b          jsonb;
  v_d          jsonb;
  v_l          jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_knobs)) or exists (select 1 from unnest(c_new) f where to_regprocedure(f) is not null) then
    raise exception '0516 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.fleet_run_quote(uuid,uuid,uuid,text,text,text[])', 'public.run_need(uuid,uuid,uuid,jsonb)', 'public.job_wait_s(uuid)']) f
              where to_regprocedure(f) is null) then
    raise exception '0516 refuses: 0498, 0502 or 0515 is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0516 (fn text primary key, def text) on commit drop;
  insert into pre_0516 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE SCENE (a temp function: its own company, the run built; dark before, dark after, and lit) ──
  execute $f$
create function pg_temp.plan_0516(p_fleet uuid, p_params jsonb)
returns jsonb
language plpgsql
as $body$
-- the plan of a fixed job with these settings, set through the door's core; a refusal is answered as its sentence
begin
  perform public.fleet_job_set_for((select f.player_id from public.fleets f where f.id = p_fleet), p_fleet, 'fixed', p_params);
  return public.fleet_job_plan(p_fleet);
exception when sqlstate 'P0001' then
  return jsonb_build_object('refused', sqlerrm);
end
$body$
  $f$;
  execute $f$
create function pg_temp.scene_0516(p_uid uuid, p_lit boolean)
returns jsonb
language plpgsql
as $body$
declare
  v_lis  uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_pl   uuid; v_fl uuid; v_g uuid; v_good text; v_sell text; v_dest uuid;
  v_j    jsonb;      -- the plain job
  v_rq   jsonb;
  v_out  jsonb := '{}'::jsonb;
  v_b1   numeric;    -- the quay's price of the first unit bought, and of the first sold
  v_s1   numeric;
  v_w    jsonb;
begin
  v_pl := public.new_house(p_uid, 'Casa da Prova 0516', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  update public.players set ducats = 50000000 where id = v_pl;
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'ship_stores_separate');
  update public.world_config set value = 'false'::jsonb where key in ('jobs_wait_enabled', 'run_guard_enabled', 'bargain_total_enabled', 'buy_tax_enabled');   -- this file's question alone
  perform cmd.assume_identity(p_uid);
  -- THE RUN, BUILT as 0498's: static rows choose the pair; Lisbon at the band's floor, the harbour at its ceiling, room for any load
  select g.code, g.id, k.code, k.to_port into v_good, v_g, v_sell, v_dest
    from public.npc_known_legs(v_lis) k
    join public.port_goods ps on ps.port_id = k.to_port
    join public.goods g on g.id = ps.good_id
    join public.ports pd on pd.id = k.to_port and pd.kind = 'HARBOUR'
   where public.port_offers(v_lis, g.id)
     and exists (select 1 from public.port_goods pl where pl.port_id = v_lis and pl.good_id = g.id)
     and not public.culture_refuses(pd.culture, g.culture_mask)
     and public.fleet_free_hold(v_fl) >= 20 * g.bulk
   order by k.nm, g.base_value desc, g.code limit 1;
  if v_good is null then
    raise exception '0516 self-assert FAIL: the probe found no good Lisbon offers that a remembered harbour takes (static rows, not the market)';
  end if;
  update public.port_goods pg set stock_target = 1000000, stock = 1000000000, affinity = 0.25, demand = 1, drift = 0, season_mod = 0, glut = 0.5, glut_at = now(), haul = 1, want_period = null
   where pg.port_id = v_lis and pg.good_id = v_g;
  update public.port_goods pg set stock_target = 1000000, stock = 0, affinity = 3, demand = 1, drift = 0, season_mod = 0, glut = -0.5, glut_at = now(), want_period = null
   where pg.port_id = v_dest and pg.good_id = v_g;
  v_j := jsonb_build_object('good', v_good, 'buy', 'LIS', 'sell', v_sell);
  -- dark: every setting is dropped, the plan is BUY ALL, the note's low is low
  if not p_lit then
    v_out := jsonb_build_object('plain', pg_temp.plan_0516(v_fl, v_j) #- '{version}',
      'with', pg_temp.plan_0516(v_fl, v_j || '{"under": 1, "over": 1, "crew": 9, "days": 9, "stop_profit": 1, "stop_damage": 1}') #- '{version}',
      'params', (select j.params from public.fleet_jobs j where j.fleet_id = v_fl));
    perform public.fleet_job_note(v_fl, '{"wait": "low", "sentence": "prices low", "net": -5}');
    return v_out || jsonb_build_object('last', (select j.last - 'at' from public.fleet_jobs j where j.fleet_id = v_fl),
      'next', (select extract(epoch from j.next_at - now()) from public.fleet_jobs j where j.fleet_id = v_fl), 'workers', world.workers() ? 'settings');
  end if;

  update public.world_config set value = 'true'::jsonb where key = 'passive_settings_enabled';
  v_rq := public.fleet_run_quote(v_pl, v_fl, v_lis, v_good, v_sell, array[v_sell, 'LIS']);
  if coalesce((v_rq->>'net')::numeric, 0) <= 0 or (v_rq->>'units')::numeric < 7 then
    raise exception '0516 self-assert FAIL: the probe did not build a paying run: % ; the fault is the probe''s, not the market''s', v_rq;
  end if;
  select q.avg_price into v_b1 from world.quote(v_lis, v_g, 1, 'buy', null, v_fl) q;
  select q.avg_price into v_s1 from world.quote(v_dest, v_g, 1, 'sell', null, v_fl) q;
  v_out := jsonb_build_object('rq', v_rq, 'b1', v_b1, 's1', v_s1, 'good', v_good, 'workers', world.workers() #> array['settings', v_fl::text], 'free', public.fleet_free_hold(v_fl),
    'plain', pg_temp.plan_0516(v_fl, v_j) #- '{version}',
    'in', pg_temp.plan_0516(v_fl, v_j || jsonb_build_object('under', v_b1 + 1000000, 'over', 0.01)),
    'dear', pg_temp.plan_0516(v_fl, v_j || jsonb_build_object('under', greatest(0.01, round(v_b1 / 2, 2)))));
  -- THE WAIT, through the one note: not stopped, nothing ordered, her row says why; not due before its time
  perform public.fleet_job_note(v_fl, v_out->'dear');
  v_w := world.workers() #> '{workers,0}';
  v_out := v_out || jsonb_build_object('wait', v_w->'wait', 'state', v_w->'state', 'due', exists (select 1 from public.fleet_jobs_due() d where d.fleet_id = v_fl),
    'next', (select extract(epoch from j.next_at - now()) from public.fleet_jobs j where j.fleet_id = v_fl),
    'paused', (select j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fl),
    'cheap', pg_temp.plan_0516(v_fl, v_j || jsonb_build_object('over', round(v_s1 * 2, 2))),
    'profit', pg_temp.plan_0516(v_fl, v_j || jsonb_build_object('stop_profit', (v_rq->>'net')::numeric + 1)),
    'profit_ok', pg_temp.plan_0516(v_fl, v_j || jsonb_build_object('stop_profit', (v_rq->>'net')::numeric)),
    'bad', jsonb_build_array(pg_temp.plan_0516(v_fl, v_j || '{"under": -1}'), pg_temp.plan_0516(v_fl, v_j || '{"over": "x"}'),
                             pg_temp.plan_0516(v_fl, v_j || '{"crew": 99999}'), pg_temp.plan_0516(v_fl, v_j || '{"days": 0}'),
                             pg_temp.plan_0516(v_fl, v_j || '{"stop_damage": 101}')));
  -- A HALF-RANGE: the limit is the first unit's price on a shallow quay (the price walks up a shelf at a time): she buys those and no more
  update public.port_goods pg set stock_target = 400, stock = 200 where pg.port_id = v_lis and pg.good_id = v_g;
  select q.avg_price into v_b1 from world.quote(v_lis, v_g, 1, 'buy', null, v_fl) q;
  v_out := v_out || jsonb_build_object('cut', pg_temp.plan_0516(v_fl, v_j || jsonb_build_object('under', v_b1)),
    'cut_n', (select floor(q.units) from world.quote(v_lis, v_g, (public.fleet_buy_capacity(v_fl, v_g)->>'max_qty')::numeric, 'buy', v_b1, v_fl) q),
    'cut_all', (public.fleet_buy_capacity(v_fl, v_g)->>'max_qty')::numeric);
  update public.port_goods pg set stock_target = 1000000, stock = 1000000000 where pg.port_id = v_lis and pg.good_id = v_g;
  -- CREW AND DAYS: two hands under her berths and her casks empty
  update public.ships s set crew = greatest((select sb.crew_max from public.ship_base(s.id) sb) - 2, 1), water_t = 0, food_t = 0 where s.fleet_id = v_fl;
  update public.ports set crew_pool = 100 where id = v_lis;
  v_out := v_out || jsonb_build_object('crew', pg_temp.plan_0516(v_fl, v_j || jsonb_build_object('days', 3, 'crew',
    (select sum((select sb.crew_max from public.ship_base(s.id) sb)) from public.ships s where s.fleet_id = v_fl))));
  update public.players set ducats = 1 where id = v_pl;
  v_out := v_out || jsonb_build_object('poor', pg_temp.plan_0516(v_fl, v_j || jsonb_build_object('days', 3)));
  update public.players set ducats = 50000000 where id = v_pl;
  -- THE HULL: half gone, a stop at 30; at 60 she goes on
  update public.ships s set durability = (select sb.durability from public.ship_base(s.id) sb) * 0.5 where s.fleet_id = v_fl;
  v_out := v_out || jsonb_build_object('hurt_ok', pg_temp.plan_0516(v_fl, v_j || '{"stop_damage": 60}'), 'hurt', pg_temp.plan_0516(v_fl, v_j || '{"stop_damage": 30}'));
  perform public.fleet_job_note(v_fl, v_out->'hurt');
  v_out := v_out || jsonb_build_object('hurt_stop', (select j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fl),
    'hurt_due', exists (select 1 from public.fleet_jobs_due() d where d.fleet_id = v_fl));
  -- MENDED: she is due again, and the note lifts the stop
  update public.ships s set durability = (select sb.durability from public.ship_base(s.id) sb) where s.fleet_id = v_fl;
  v_out := v_out || jsonb_build_object('mend_due', exists (select 1 from public.fleet_jobs_due() d where d.fleet_id = v_fl), 'mend_plan', public.fleet_job_plan(v_fl) ? 'lines');
  perform public.fleet_job_note(v_fl, '{"wait": "low"}');
  v_out := v_out || jsonb_build_object('mend_stop', (select j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fl), 'mend_wait', (select j.last->>'wait' from public.fleet_jobs j where j.fleet_id = v_fl));
  update public.ships s set durability = (select sb.durability from public.ship_base(s.id) sb) * 0.5 where s.fleet_id = v_fl;
  -- AT HER SALE, with cargo: out of range she keeps it and waits; in range she sells; the hull past its stop: she sells and does not sail
  perform public.fleet_load(v_fl, v_good, 6, 1);
  update public.fleets set port_id = v_dest where id = v_fl;
  v_out := v_out || jsonb_build_object('at_low', pg_temp.plan_0516(v_fl, v_j || jsonb_build_object('over', round(v_s1 * 2, 2))),
    'at_ok', pg_temp.plan_0516(v_fl, v_j || '{"over": 0.01}'), 'at_hurt', pg_temp.plan_0516(v_fl, v_j || '{"stop_damage": 30}'));
  -- the lines of a plan that has its own PROVISION (0508's): one line, the longer days
  return v_out || jsonb_build_object('merge', public.job_settings_lines('[{"text": "PROVISION DAYS 8"}, {"text": "BUY x ALL"}]', '{"hire": 3, "days": 20}'),
                                     'sell', v_sell);
end
$body$
  $f$;

  begin
    raise exception using errcode = 'ZX516', message = pg_temp.scene_0516(c_ua, false)::text;
  exception when sqlstate 'ZX516' then v_b := sqlerrm::jsonb;
  end;

  -- ── 3. THE KNOB ──
  insert into public.world_config (key, value, description) values
    ('passive_settings_enabled', 'false'::jsonb,
     '0516: THE SWITCH (the owner''s). true: a fixed standing job may carry buy under, sell over, crew, days of stores, stop under a profit and stop over a damage; out of range it waits and says why (public.job_settings_judge). It asks no level.');

  -- ── 4. THE RULES ──
  execute $f$
create function public.passive_settings_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0516: THE SWITCH, read once: world_config passive_settings_enabled.
  select public.wc('passive_settings_enabled') = 'true'::jsonb
$body$
  $f$;
  execute $f$
create function public.job_settings_param(p_fleet uuid, p_params jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0516: A FIXED JOB'S SETTINGS, judged once where it is set (public.fleet_job_set_for) and kept in its params: under, over, crew, days,
-- stop_profit, stop_damage; each a number in its range, or the job is refused. Nothing she has earned is asked. Dark: nothing is kept.
declare
  k     record;
  v_out jsonb := '{}'::jsonb;
  v_min int;
  v_max int;
begin
  if not public.passive_settings_on() then
    return v_out;
  end if;
  for k in select * from (values ('under', 0.01, 1000000000::numeric, false, 'the buy price'), ('over', 0.01, 1000000000, false, 'the sell price'), ('crew', 1, 100000, true, 'the crew'),
                                 ('days', 1, 120, true, 'the days of food and water'), ('stop_profit', 0, 1000000000, false, 'the profit'),
                                 ('stop_damage', 1, 99, true, 'the damage')) t(code, lo, hi, whole, word) loop
    continue when coalesce(jsonb_typeof(p_params->k.code), 'null') = 'null';
    if jsonb_typeof(p_params->k.code) <> 'number' or (p_params->>k.code)::numeric < k.lo or (p_params->>k.code)::numeric > k.hi
       or (k.whole and (p_params->>k.code)::numeric <> floor((p_params->>k.code)::numeric)) then
      perform cmd.refuse('E_BAD_ORDER', format('%s is a number from %s to %s', k.word, k.lo, k.hi));
    end if;
    v_out := v_out || jsonb_build_object(k.code, p_params->k.code);
  end loop;
  if p_params->>'end' = 'store' and v_out ?| array['over', 'stop_profit'] then
    perform cmd.refuse('E_BAD_ORDER', 'goods brought home are not sold: no sell price and no profit to set');
  end if;
  if v_out ? 'crew' then
    select sum(c.crew_required), sum((select sb.crew_max from public.ship_base(s.id) sb)) into v_min, v_max
      from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = p_fleet;
    if (v_out->>'crew')::int < coalesce(v_min, 0) or (v_out->>'crew')::int > coalesce(v_max, 0) then
      perform cmd.refuse('E_BAD_ORDER', format('her crew is from %s to %s', coalesce(v_min, 0), coalesce(v_max, 0)));
    end if;
  end if;
  return v_out;
end
$body$
  $f$;
  execute $f$
create function public.fleet_damage_pct(p_fleet uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0516: what her worst hull has lost, in whole per cent (the same reading as 0502's hull_left).
  select coalesce(round(100 * (1 - least(1, min(sh.durability / nullif(sb.durability, 0))))), 0)
    from public.ships sh cross join lateral public.ship_base(sh.id) sb where sh.fleet_id = p_fleet
$body$
  $f$;
  execute $f$
create function public.job_damage_mended(p_fleet uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0516: a job stopped for her hull (E_STOP_DAMAGE) may go on: she is mended to within its figure, or the settings are dark.
  select not public.passive_settings_on()
         or public.fleet_damage_pct(p_fleet) <= coalesce((select (j.params->>'stop_damage')::numeric from public.fleet_jobs j where j.fleet_id = p_fleet), 100)
$body$
  $f$;
  execute $f$
create function public.job_settings_room(p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0516: for each of her fleets that lies in a port: hold (what her hulls stow), left (what is free of it now; stores in the hold: less what
  -- the days her job keeps would still take), crew, crew_min, crew_max. world.workers() serves it while the settings are lit.
  select coalesce(jsonb_object_agg(f.id, (
           select jsonb_build_object('hold', round(sum(public.ship_hold_capacity(s.id))),
                    'left', greatest(0, floor(public.fleet_free_hold(f.id) - case when public.ship_stores_separate() then 0 else coalesce(sum(t.water_t + t.food_t), 0) end)),
                    'crew', sum(s.crew), 'crew_min', sum(c.crew_required), 'crew_max', sum((select sb.crew_max from public.ship_base(s.id) sb)))
             from public.ships s join public.ship_classes c on c.id = s.class_id
             left join lateral public.stores_topup(s.crew, s.water_t, s.food_t, public.ship_stores_room(s.id, public.ship_hold_capacity(s.id) - public.ship_cargo_tuns(s.id)),
                                                   (j.params->>'days')::numeric, 0) t on j.params ? 'days'
            where s.fleet_id = f.id)), '{}'::jsonb)
    from public.fleets f left join public.fleet_jobs j on j.fleet_id = f.id
   where f.player_id = p_player
$body$
  $f$;
  execute $f$
create function public.job_settings_judge(p_fleet uuid, p_at text, p_end jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0516: WHAT A FIXED JOB'S SETTINGS MAKE OF ITS NEXT PLAN, as she lies at p_at (public.fleet_job_plan's fixed branch asks this once, after
-- 0492's end and count, p_end). {} dark, for a job without settings, and where nothing binds. Else:
--   end    what p_end becomes: {wait | pause, sentence} (the plan answers it), or p_end with `buy`, the BUY line of the units in range
--   only   the one line of this plan: a sale in range, and nothing after it
--   sell   false: the run's plan ends at the sale's harbour (`over` is asked again there)
--   hire, days   the crew to sign on and the days of stores to hold, where she buys
-- The run's units, cost and net are public.fleet_run_quote's (0498), the limits world.quote's. Writes nothing.
declare
  j       public.fleet_jobs%rowtype;
  f       public.fleets%rowtype;
  v_g     text;
  v_gid   uuid;
  v_dest  uuid;
  v_st    text[];
  v_sells boolean := coalesce(p_end->>'verb', 'SELL') = 'SELL';
  v_out   jsonb := '{}'::jsonb;
  v_aboard numeric;
  v_own   numeric := 0;
  v_dmg   numeric;
  v_done  boolean;
  v_n     numeric;
  v_n0    numeric;
  v_cost  numeric;
  v_gross numeric;
  v_net   numeric;
  v_rq    jsonb;
  v_hire  int := 0;
  v_now   int;
  v_max   int;
  v_pay   numeric := 0;
  v_w     numeric;
  v_f     numeric;
  v_purse numeric;
  v_one   numeric;
begin
  if not public.passive_settings_on() then
    return v_out;
  end if;
  select * into j from public.fleet_jobs x where x.fleet_id = p_fleet;
  if j.kind is distinct from 'fixed' or not (j.params ?| array['under', 'over', 'crew', 'days', 'stop_profit', 'stop_damage']) then
    return v_out;
  end if;
  v_done := coalesce(p_end->>'wait' = 'done', false);
  if p_end ? 'pause' or (p_end ? 'wait' and not v_done) then
    return v_out;
  end if;
  select * into f from public.fleets x where x.id = p_fleet;
  if j.params->>'end' = 'store' then
    v_sells := false;
  end if;
  v_g := j.params->>'good';
  v_gid := (select g.id from public.goods g where g.code = v_g);
  v_dest := (select p.id from public.ports p where p.code = j.params->>'sell' and p.kind = 'HARBOUR');
  v_aboard := coalesce(public.fleet_cargo_qty(p_fleet, v_g), 0);
  v_dmg := public.fleet_damage_pct(p_fleet);

  -- AT HER SALE, WITH CARGO TO SELL
  if v_sells and p_at = j.params->>'sell' and v_aboard >= 1 then
    if j.params ? 'over' then
      v_n := floor(least(v_aboard, coalesce(world.daily_cap_remaining(j.player_id, v_dest, v_gid), v_aboard)));
      if v_n < 1 then
        return jsonb_build_object('end', jsonb_build_object('wait', 'range', 'sentence', 'the day''s allowance is spent'));
      end if;
      select floor(q.units) into v_n0 from world.quote(v_dest, v_gid, v_n, 'sell', (j.params->>'over')::numeric, p_fleet) q;
      if coalesce(v_n0, 0) < 1 then
        select q.avg_price into v_one from world.quote(v_dest, v_gid, 1, 'sell', null, p_fleet) q;
        return jsonb_build_object('end', jsonb_build_object('wait', 'range', 'sentence',
                 format('sells at %s, your limit %s', to_char(v_one, 'FM999,999,990.00'), to_char((j.params->>'over')::numeric, 'FM999,999,990.00'))));
      end if;
      if v_n0 < floor(v_aboard) then
        return jsonb_build_object('end', jsonb_build_object('verb', 'SELL'), 'only', format('SELL %s %s', v_g, trim_scale(v_n0)));
      end if;
    end if;
    if v_done or (j.params ? 'stop_damage' and v_dmg > (j.params->>'stop_damage')::numeric) then
      return jsonb_build_object('end', jsonb_build_object('verb', 'SELL'), 'only', format('SELL %s ALL', v_g));
    end if;
    return v_out;
  end if;
  if v_done then
    return v_out;
  end if;

  -- STOP: THE HULL
  if j.params ? 'stop_damage' and v_dmg > (j.params->>'stop_damage')::numeric then
    return jsonb_build_object('end', jsonb_build_object('pause', 'E_STOP_DAMAGE', 'sentence', format('hull damage %s %%, you stop over %s %%', v_dmg, j.params->>'stop_damage')));
  end if;
  if p_at is distinct from j.params->>'buy' then
    return v_out;
  end if;

  -- WHERE SHE BUYS: the crew and the stores first
  v_purse := (select p.ducats from public.players p where p.id = j.player_id);
  if j.params ? 'crew' then
    select coalesce(sum(s.crew), 0), coalesce(sum((select sb.crew_max from public.ship_base(s.id) sb)), 0) into v_now, v_max from public.ships s where s.fleet_id = p_fleet;
    v_hire := greatest(0, least((j.params->>'crew')::int, v_max) - v_now);
    if v_hire > 0 and coalesce((select p.crew_pool from public.ports p where p.id = f.port_id), 0) <= 0 then
      v_hire := 0;   -- no hands here (the door's own refusal): she sails with those she has
    end if;
    if v_hire > 0 then
      v_pay := v_pay + (public.crew_hire_cost(p_fleet, v_hire)->>'cost')::numeric;
      v_out := v_out || jsonb_build_object('hire', v_hire);
    end if;
  end if;
  if j.params ? 'days' then
    select coalesce(sum(t.water_t), 0), coalesce(sum(t.food_t), 0) into v_w, v_f
      from public.ships s cross join lateral public.stores_topup(s.crew, s.water_t, s.food_t,
             public.ship_stores_room(s.id, public.ship_hold_capacity(s.id) - public.ship_cargo_tuns(s.id)), (j.params->>'days')::numeric,
             public.ship_stores_room(s.id, public.ship_hold_capacity(s.id) * s.store_ratio)) t
     where s.fleet_id = p_fleet;
    if v_w + v_f > 0 then
      v_pay := v_pay + public.stores_cost(j.player_id, v_w, v_f) * case when v_hire > 0 then (v_now + v_hire)::numeric / greatest(v_now, 1) else 1 end;
      v_out := v_out || jsonb_build_object('days', (j.params->>'days')::int);
    end if;
  end if;
  if v_pay > v_purse then
    return jsonb_build_object('end', jsonb_build_object('wait', 'purse', 'purse', v_purse, 'need', round(v_pay),
             'sentence', format('purse %s, crew and stores cost %s', to_char(v_purse, 'FM999,999,999,990'), to_char(v_pay, 'FM999,999,999,990'))));
  end if;

  -- THE RUN
  if v_sells then
    v_st := array(select jsonb_array_elements_text(coalesce(j.params->'stops', '[]'::jsonb)));
    v_rq := public.fleet_run_quote(j.player_id, p_fleet, f.port_id, v_g, j.params->>'sell',
                                   v_st || (j.params->>'sell') || array(select u.c from unnest(v_st) with ordinality u(c, i) order by u.i desc) || (j.params->>'buy'));
    if v_rq ? 'shut' then
      return v_out;   -- no way through: the plan's own judge says it
    end if;
    v_n0 := coalesce((v_rq->>'units')::numeric, 0);
    v_own := greatest(0, coalesce((v_rq->>'load')::numeric, 0) - v_n0);   -- what she would sell of the load aboard
    if v_n0 < 1 and v_own >= 1 then   -- nothing to buy beside her load: judged as any run, and she goes on with it
      v_net := (v_rq->>'net')::numeric;
      if v_net <= 0 then
        return jsonb_build_object('end', jsonb_build_object('wait', 'low', 'sentence', 'prices low', 'net', v_net));
      end if;
      if j.params ? 'stop_profit' and v_net < (j.params->>'stop_profit')::numeric then
        return jsonb_build_object('end', jsonb_build_object('pause', 'E_STOP_PROFIT', 'sentence',
                 format('this run would leave %s, you stop under %s', to_char(v_net, 'FM999,999,999,990'), to_char((j.params->>'stop_profit')::numeric, 'FM999,999,999,990'))));
      end if;
      return v_out || jsonb_build_object('end', p_end || '{"laden": true}'::jsonb) || case when j.params ? 'over' then '{"sell": false}'::jsonb else '{}'::jsonb end;
    end if;
    if v_n0 < 1 then
      return jsonb_build_object('end', jsonb_build_object('wait', 'low', 'net', v_rq->'net', 'sentence',
               case v_rq->>'why' when 'allowance' then 'the day''s allowance is spent' else 'nothing to buy now' end));
    end if;
  else
    v_n0 := coalesce((regexp_match(coalesce(p_end->>'buy', ''), ' ([0-9.]+)$'))[1]::numeric, (public.fleet_buy_capacity(p_fleet, v_gid)->>'max_qty')::numeric, 0);
    if v_n0 < 1 then
      return v_out;
    end if;
  end if;
  v_n := v_n0;
  if v_out ? 'days' and not public.ship_stores_separate() then   -- stores in the hold: the load is what fits beside them
    v_n := greatest(1, least(v_n, floor(greatest(0, public.fleet_free_hold(p_fleet) - v_w - v_f) / (select g.bulk from public.goods g where g.id = v_gid))));
  end if;
  if j.params ? 'under' then
    select floor(q.units) into v_n from world.quote(f.port_id, v_gid, v_n, 'buy', (j.params->>'under')::numeric, p_fleet) q;
    if coalesce(v_n, 0) < 1 then
      select q.avg_price into v_one from world.quote(f.port_id, v_gid, 1, 'buy', null, p_fleet) q;
      return jsonb_build_object('end', jsonb_build_object('wait', 'range', 'sentence',
               format('buys at %s, your limit %s', to_char(v_one, 'FM999,999,990.00'), to_char((j.params->>'under')::numeric, 'FM999,999,990.00'))));
    end if;
  end if;
  if j.params ? 'over' then
    select floor(q.units) into v_n from world.quote(v_dest, v_gid, v_n, 'sell', (j.params->>'over')::numeric, p_fleet) q;
    if coalesce(v_n, 0) < 1 then
      select q.avg_price into v_one from world.quote(v_dest, v_gid, 1, 'sell', null, p_fleet) q;
      return jsonb_build_object('end', jsonb_build_object('wait', 'range', 'sentence',
               format('sells at %s, your limit %s', to_char(v_one, 'FM999,999,990.00'), to_char((j.params->>'over')::numeric, 'FM999,999,990.00'))));
    end if;
    v_out := v_out || '{"sell": false}'::jsonb;
  end if;
  -- what the crew and the stores take is not there for the goods (a smaller BUY never costs more a unit: the proportion never overshoots)
  if v_pay > 0 then
    select q.total into v_cost from world.quote(f.port_id, v_gid, v_n, 'buy', null, p_fleet) q;
    if v_cost > v_purse - v_pay then
      v_n := floor(v_n * (v_purse - v_pay) / v_cost);
      if v_n < 1 then
        return jsonb_build_object('end', jsonb_build_object('wait', 'purse', 'sentence', 'nothing left to buy with after crew and stores', 'purse', v_purse, 'need', round(v_pay)));
      end if;
    end if;
  end if;
  if v_sells then
    if v_n = v_n0 then
      v_net := (v_rq->>'net')::numeric;
    else
      select q.total into v_cost from world.quote(f.port_id, v_gid, v_n, 'buy', null, p_fleet) q;
      v_cost := v_cost + v_own * coalesce(public.fleet_cargo_basis(p_fleet, v_g), 0);
      select q.total into v_gross from world.quote(v_dest, v_gid, v_n + v_own, 'sell', null, p_fleet) q;
      v_net := round(v_gross - v_cost - coalesce(public.profit_tax(v_dest, v_gross - v_cost, j.player_id), 0) - (v_rq->>'trip')::numeric);
    end if;
    -- the hands are a cost of this run (the stores are in the trip's)
    v_net := v_net - case when v_hire > 0 then (public.crew_hire_cost(p_fleet, v_hire)->>'cost')::numeric else 0 end;
    if j.params ? 'stop_profit' and v_net < (j.params->>'stop_profit')::numeric then
      return jsonb_build_object('end', jsonb_build_object('pause', 'E_STOP_PROFIT', 'sentence',
               format('this run would leave %s, you stop under %s', to_char(v_net, 'FM999,999,999,990'), to_char((j.params->>'stop_profit')::numeric, 'FM999,999,999,990'))));
    end if;
    if public.jobs_wait_on() and v_net <= 0 then
      return jsonb_build_object('end', jsonb_build_object('wait', 'low', 'sentence', 'prices low', 'net', v_net));
    end if;
  end if;
  if v_n < v_n0 or coalesce((v_rq->>'cut')::boolean, false) then
    v_out := v_out || jsonb_build_object('end', p_end || jsonb_build_object('buy', format('BUY %s %s', v_g, trim_scale(v_n))));
  end if;
  return v_out;
end
$body$
  $f$;
  execute $f$
create function public.job_settings_lines(p_lines jsonb, p_set jsonb)
returns jsonb
language plpgsql
stable
set search_path = public, pg_temp
as $body$
-- 0516: A FIXED PLAN'S LINES WITH ITS SETTINGS (public.job_settings_judge's answer): `only`, the one line; else the hire and the stores before
-- the rest (a plan that has its own PROVISION DAYS keeps one, the longer), and without its last line, the sale, where `sell` is false.
declare
  v_l    jsonb := p_lines;
  v_days numeric := (p_set->>'days')::numeric;
  i      int;
begin
  if p_set ? 'only' then
    return jsonb_build_array(jsonb_build_object('text', p_set->'only'));
  end if;
  if p_set->'sell' = 'false'::jsonb then
    v_l := v_l - (-1);
  end if;
  if v_days is not null then
    for i in 0 .. jsonb_array_length(v_l) - 1 loop
      if v_l #>> array[i::text, 'text'] ~ '^PROVISION DAYS [0-9.]+$' then
        v_l := jsonb_set(v_l, array[i::text, 'text'], to_jsonb(format('PROVISION DAYS %s', greatest(v_days, split_part(v_l #>> array[i::text, 'text'], ' ', 3)::numeric))));
        v_days := null;
        exit;
      end if;
    end loop;
    if v_days is not null then
      v_l := jsonb_build_array(jsonb_build_object('text', format('PROVISION DAYS %s', v_days))) || v_l;
    end if;
  end if;
  if p_set ? 'hire' then
    v_l := jsonb_build_array(jsonb_build_object('text', format('HIRE %s', p_set->>'hire'))) || v_l;
  end if;
  return v_l;
end
$body$
  $f$;
  foreach v_def in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;

  -- ── 5. THE HUNKS ──
  create temp table hunks_0516 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0516 values
  ('public.fleet_job_plan(uuid)', 1,
$h$  v_end   jsonb;   -- 0492: what the fixed job's end and count make of this run (public.fleet_job_ends)
$h$,
$h$  v_end   jsonb;   -- 0492: what the fixed job's end and count make of this run (public.fleet_job_ends)
  v_set   jsonb := '{}'::jsonb;   -- 0516: what its settings make of it (public.job_settings_judge)
$h$),
  ('public.fleet_job_plan(uuid)', 2,
$h$    v_end := public.fleet_job_ends(j.player_id, p_fleet, j.params, v_at);
$h$,
$h$    v_end := public.fleet_job_ends(j.player_id, p_fleet, j.params, v_at);
    -- 0516 (passive_settings_enabled): the settings: a wait or a stop, the BUY of the units in range, her crew and her stores
    v_set := public.job_settings_judge(p_fleet, v_at, v_end);
    v_end := coalesce(v_set->'end', v_end);
$h$),
  ('public.fleet_job_plan(uuid)', 3,
$h$    return jsonb_build_object('lines', v_lines, 'version', f.version, 'note', jsonb_build_object('kind', 'fixed',$h$,
$h$    if v_set <> '{}'::jsonb then   -- 0516
      v_lines := public.job_settings_lines(v_lines, v_set);
    end if;
    return jsonb_build_object('lines', v_lines, 'version', f.version, 'note', jsonb_build_object('kind', 'fixed',$h$),
  ('public.fleet_job_plan(uuid)', 4,
$h$      v_laden := public.fleet_cargo_qty(p_fleet, v_g) >= 1
                 and coalesce((public.fleet_buy_capacity(p_fleet, (select g.id from public.goods g where g.code = v_g))->>'max_qty')::numeric, 0) < 1;
$h$,
$h$      v_laden := coalesce((v_end->>'laden')::boolean, false)   -- 0516: her settings or the home shed said so (public.job_settings_judge, public.fleet_job_ends)
                 or (public.fleet_cargo_qty(p_fleet, v_g) >= 1
                     and coalesce((public.fleet_buy_capacity(p_fleet, (select g.id from public.goods g where g.code = v_g))->>'max_qty')::numeric, 0) < 1);
$h$),
  ('public.fleet_job_plan(uuid)', 5,
$h$      if not v_laden and public.jobs_wait_on() and coalesce(v_end->>'verb', 'SELL') = 'SELL' and not (v_end ? 'buy') then$h$,
$h$      -- 0516: a laden run is judged whatever the switch (the load aboard is in the quote): no token load sails
      if (v_laden or public.jobs_wait_on()) and coalesce(v_end->>'verb', 'SELL') = 'SELL' and not (v_end ? 'buy') and not (v_end ? 'laden') then$h$),
  ('public.fleet_job_plan(uuid)', 6,
$h$          if coalesce((v_rq->>'units')::numeric, 0) < 1 or coalesce((v_rq->>'net')::numeric, 0) <= 0 then$h$,
$h$          if coalesce((v_rq->>'load')::numeric, 0) < 1 or coalesce((v_rq->>'net')::numeric, 0) <= 0 then   -- 0516: what she would sell, aboard or bought$h$),
  ('public.fleet_job_plan(uuid)', 7,
$h$          if (v_rq->>'cut')::boolean then
            v_end := v_end || jsonb_build_object('buy', format('BUY %s %s', v_g, trim_scale((v_rq->>'units')::numeric)));$h$,
$h$          if (v_rq->>'units')::numeric < 1 then
            v_laden := true;   -- 0516: nothing to buy beside the load that pays
          elsif (v_rq->>'cut')::boolean then
            v_end := v_end || jsonb_build_object('buy', format('BUY %s %s', v_g, trim_scale((v_rq->>'units')::numeric)));$h$),
  ('public.fleet_job_plan(uuid)', 8,
$h$      if v_need ? 'line' then
        v_lines := public.run_cut(v_lines, v_need->>'line');
      end if;
    end if;
$h$,
$h$      if v_need ? 'line' then
        v_lines := public.run_cut(v_lines, v_need->>'line');
      elsif v_need ? 'nobuy' then   -- 0516: the purse bears no BUY; the load aboard goes on
        v_lines := (select jsonb_agg(z.l order by z.i) from jsonb_array_elements(v_lines) with ordinality z(l, i) where z.l->>'text' not like 'BUY %');
      end if;
    end if;
$h$),
  ('public.fleet_job_plan(uuid)', 9,
$h$      if not coalesce(v_laden, false) and (v_g is null or coalesce(v_qty, 0) < 1) then$h$,
$h$      -- 0516: nothing of its good to take, and the load of the good before it still aboard (one the land makes): that load is stored first
      if not coalesce(v_laden, false) and (v_g is null or coalesce(v_qty, 0) < 1 or public.fleet_free_hold(p_fleet) < (select g.bulk from public.goods g where g.code = v_g)) then
        select g.code into v_buy from (select distinct a.good_id from public.land_actions a where a.good_id is not null) l join public.goods g on g.id = l.good_id
         where public.fleet_cargo_qty(p_fleet, g.code) >= 1 order by public.fleet_cargo_qty(p_fleet, g.code) desc, g.code limit 1;
        if v_buy is not null then
          v_g := v_buy;
          v_laden := true;
        end if;
      end if;
      if not coalesce(v_laden, false) and (v_g is null or coalesce(v_qty, 0) < 1) then$h$),
  ('public.fleet_run_quote(uuid,uuid,uuid,text,text,text[])', 1,
$h$  v_tax   numeric;
  v_trip  jsonb;
begin$h$,
$h$  v_tax   numeric;
  v_trip  jsonb;
  v_own   numeric;   -- 0516: whole units of the good aboard
  v_sell  numeric;   -- 0516: what she would sell: those and the units bought, to the day's allowance
begin$h$),
  ('public.fleet_run_quote(uuid,uuid,uuid,text,text,text[])', 2,
$h$  if v_u0 < 1 then
    return jsonb_build_object('units', 0, 'net', null, 'why', 'buy');
  end if;
  v_left := world.daily_cap_remaining(p_player, v_dest, v_gid);
$h$,
$h$  -- 0516: THE LOAD ABOARD IS PART OF THE RUN, at what she paid for it (public.fleet_cargo_basis; no known cost: nothing)
  v_own := floor(coalesce(public.fleet_cargo_qty(p_fleet, p_good), 0));
  if v_u0 < 1 and v_own < 1 then
    return jsonb_build_object('units', 0, 'net', null, 'why', 'buy');
  end if;
  v_left := world.daily_cap_remaining(p_player, v_dest, v_gid);
$h$),
  ('public.fleet_run_quote(uuid,uuid,uuid,text,text,text[])', 3,
$h$  if v_n < 1 then
    return jsonb_build_object('units', 0, 'net', null, 'why', 'allowance');
  end if;
  if v_n = v_u0 then
    v_cost := (v_cap->>'est_total')::numeric;
  else
    select q.total into v_cost from world.quote(p_from, v_gid, v_n, 'buy', null, p_fleet) q;
  end if;
  select q.units, q.total into v_got, v_gross from world.quote(v_dest, v_gid, v_n, 'sell', null, p_fleet) q;
  if v_cost is null or v_gross is null or coalesce(v_got, 0) < v_n then
    return jsonb_build_object('units', 0, 'net', null, 'why', 'allowance');
  end if;$h$,
$h$  -- 0516: the allowance takes the load aboard first
  v_n := greatest(0, least(v_n, floor(coalesce(v_left, v_u0 + v_own)) - v_own));
  v_sell := least(v_own + v_n, floor(coalesce(v_left, v_own + v_n)));
  if v_sell < 1 then
    return jsonb_build_object('units', 0, 'net', null, 'why', 'allowance');
  end if;
  if v_n < 1 then
    v_cost := 0;
  elsif v_n = v_u0 then
    v_cost := (v_cap->>'est_total')::numeric;
  else
    select q.total into v_cost from world.quote(p_from, v_gid, v_n, 'buy', null, p_fleet) q;
  end if;
  v_cost := v_cost + (v_sell - v_n) * coalesce(public.fleet_cargo_basis(p_fleet, p_good), 0);
  select q.units, q.total into v_got, v_gross from world.quote(v_dest, v_gid, v_sell, 'sell', null, p_fleet) q;
  if v_cost is null or v_gross is null or coalesce(v_got, 0) < v_sell then
    return jsonb_build_object('units', 0, 'net', null, 'why', 'allowance');
  end if;$h$),
  ('public.fleet_run_quote(uuid,uuid,uuid,text,text,text[])', 4,
$h$  return jsonb_build_object('units', v_n, 'cost', round(v_cost),$h$,
$h$  return jsonb_build_object('load', v_sell, 'units', v_n, 'cost', round(v_cost),$h$),
  ('public.run_need(uuid,uuid,uuid,jsonb)', 1,
$h$  v_sells  boolean := false;
$h$,
$h$  v_sells  boolean := false;
  v_sg     text;           -- 0516: the good she sells
  v_own    numeric := 0;   -- 0516: whole units of it aboard now
  v_must   numeric;        -- 0516: what she must pay before that sale
$h$),
  ('public.run_need(uuid,uuid,uuid,jsonb)', 2,
$h$      v_sells := v_w[2] = v_good;
$h$,
$h$      v_sells := v_w[2] = v_good;
      v_sg := v_w[2];
$h$),
  ('public.run_need(uuid,uuid,uuid,jsonb)', 3,
$h$  if v_purse >= v_need and v_n0 >= 1 and v_n < 1 then$h$,
$h$  -- 0516: HER CARGO IS HER COIN. Nothing bought (or nothing the purse bears) and a load of the good aboard to sell: what she needs is what she pays BEFORE that
  -- sale. Straight to it, her stores and her hands alone (the dock fee and the repair come out of it); by way of other harbours, their dock fees and the
  -- storm's default too (the run that ruined a company, 0502), never the repair. A BUY the purse bears none of is left out (`nobuy`) if the load pays its way
  v_own := case when v_sg is null then 0 else floor(coalesce(public.fleet_cargo_qty(p_fleet, v_sg), 0)) end;
  if v_own >= 1 and v_n < 1 and (v_good is null or v_good = v_sg) then
    v_must := (v_trip->>'supplies')::numeric + v_crew + case when cardinality(v_calls) > 1 then v_dock + v_sea else 0 end;
    if v_purse < v_must then
      return v_out || jsonb_build_object('wait', 'purse', 'sentence', format('purse %s, her way to the sale costs %s', to_char(v_purse, 'FM999,999,999,990'), to_char(v_must, 'FM999,999,999,990')));
    end if;
    if v_good is null or v_n0 < 1 then
      return v_out || jsonb_build_object('ok', true, 'aboard', v_own);
    end if;
    v_gid := (select g.id from public.goods g where g.code = v_sg);
    v_own := least(v_own, floor(coalesce(world.daily_cap_remaining(p_player, v_dest, v_gid), v_own)));
    v_net := null;
    if v_own >= 1 then
      select q.total into v_gross from world.quote(v_dest, v_gid, v_own, 'sell', null, p_fleet) q;
      v_got := v_own * coalesce(public.fleet_cargo_basis(p_fleet, v_sg), 0);
      v_net := coalesce(v_gross, 0) - v_got - coalesce(public.profit_tax(v_dest, coalesce(v_gross, 0) - v_got, p_player), 0)
               - (v_trip->>'supplies')::numeric - (v_trip->>'wages')::numeric - v_dock;
    end if;
    if coalesce(v_net, 0) <= 0 then
      return v_out || jsonb_build_object('wait', 'purse', 'sentence', 'purse buys too little to pay its way');
    end if;
    return v_out || jsonb_build_object('ok', true, 'nobuy', true, 'aboard', v_own, 'net', round(v_net));
  end if;
  if v_purse >= v_need and v_n0 >= 1 and v_n < 1 then$h$),
  ('public.run_need(uuid,uuid,uuid,jsonb)', 4,
$h$      select q.total into v_gross from world.quote(v_dest, v_gid, v_n, 'sell', null, p_fleet) q;
      v_net := coalesce(v_gross, 0) - v_cost - coalesce(public.profit_tax(v_dest, coalesce(v_gross, 0) - v_cost, p_player), 0)$h$,
$h$      -- 0516: with the load aboard, at what she paid for it
      select q.total into v_gross from world.quote(v_dest, v_gid, v_n + v_own, 'sell', null, p_fleet) q;
      v_got := v_cost + v_own * coalesce(public.fleet_cargo_basis(p_fleet, v_good), 0);
      v_net := coalesce(v_gross, 0) - v_got - coalesce(public.profit_tax(v_dest, coalesce(v_gross, 0) - v_got, p_player), 0)$h$),
  ('public.fleet_job_ends(uuid,uuid,jsonb,text)', 1,
$h$    if v_room < 1 then
      return jsonb_build_object('pause', 'E_SHED_FULL',$h$,
$h$    -- 0516: her load aboard and no room for more than it: she brings it home; no room for all of it (a STORE is whole or refused): she waits, not stopped
    if v_room < 1 and public.fleet_cargo_qty(p_fleet, g.code) >= 1 then
      if v_room < 0 then
        return jsonb_build_object('wait', 'low', 'sentence', format('the warehouse at %s is full', p_params->>'sell'));
      end if;
      return jsonb_strip_nulls(jsonb_build_object('verb', 'STORE', 'laden', true,
               'note', jsonb_strip_nulls(jsonb_build_object('end', 'store', 'leg', 'out', 'left', p_params->'left'))));
    end if;
    if v_room < 1 then
      return jsonb_build_object('pause', 'E_SHED_FULL',$h$),
  ('public.fleet_job_note(uuid,jsonb)', 1,
$h$  elsif p_plan->>'wait' = 'low' then
$h$,
$h$  elsif p_plan->>'wait' in ('low', 'range') then   -- 0516: `range`, her own prices: the same wait
$h$),
  ('public.fleet_job_note(uuid,jsonb)', 2,
$h$'wait', 'low', 'sentence', coalesce(p_plan->>'sentence', 'prices low')$h$,
$h$'wait', p_plan->>'wait', 'sentence', coalesce(p_plan->>'sentence', 'prices low')$h$),
  ('public.fleet_job_note(uuid,jsonb)', 3,
$h$  if p_plan ? 'pause' then
$h$,
$h$  -- 0516: a job stopped for her hull, asked again now that she is mended: the stop is lifted, whatever this plan says
  update public.fleet_jobs set paused_reason = null where fleet_id = p_fleet and paused_reason = 'E_STOP_DAMAGE' and public.job_damage_mended(p_fleet);
  if p_plan ? 'pause' then
$h$),
  ('public.fleet_jobs_due()', 1,
$h$     and (j.paused_reason is null
$h$,
$h$     and (j.paused_reason is null
          or (j.paused_reason = 'E_STOP_DAMAGE' and public.job_damage_mended(j.fleet_id))   -- 0516: stopped for her hull, and mended
$h$),
  ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', 1,
$h$  -- 0506 (dark: nothing): the job setting `bargain` (false = this job does not bargain; the default is on)
$h$,
$h$  -- 0516 (dark: nothing): a fixed job's settings (public.job_settings_param judges them; no level is asked)
  if p_kind = 'fixed' then
    v_p := v_p || public.job_settings_param(p_fleet, p_params);
  end if;
  -- 0506 (dark: nothing): the job setting `bargain` (false = this job does not bargain; the default is on)
$h$),
  ('world.workers()', 1,
$h$  return jsonb_build_object('company', true, 'now', now(),$h$,
$h$  -- 0516 (dark: no such key): a fixed job may carry settings; each fleet's hold and crew for them
  return case when public.passive_settings_on() then jsonb_build_object('settings', public.job_settings_room(v_me)) else '{}'::jsonb end ||
         jsonb_build_object('company', true, 'now', now(),$h$);

  for x in select distinct h.fn from hunks_0516 h loop
    v_pre := (select p.def from pre_0516 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0516 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0516 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0516 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0516 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0516 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0516 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0516 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before or public.passive_settings_on() then
    raise exception '0516 self-assert FAIL: a knob of another file moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute')
                 or (select p.provolatile from pg_proc p where p.oid = u.q::regprocedure) <> 's')
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0516 self-assert FAIL: a new function is reachable by a client or service_role';
  end if;
  -- NO LEVEL IS ASKED by any of the seven
  if exists (select 1 from unnest(c_new) u(q) where (select position('level_' in p.prosrc) + position('player_progress' in p.prosrc) from pg_proc p where p.oid = u.q::regprocedure) > 0) then
    raise exception '0516 self-assert FAIL: a setting asks a level';
  end if;

  -- ── 7. DARK IDENTITY, then LIT ──
  begin
    raise exception using errcode = 'ZX516', message = pg_temp.scene_0516(c_ua, false)::text;
  exception when sqlstate 'ZX516' then v_d := sqlerrm::jsonb;
  end;
  if v_d is distinct from v_b or v_d->'plain' is distinct from v_d->'with' or (v_d->>'workers')::boolean then
    raise exception '0516 self-assert FAIL: DARK IS NOT IDENTICAL: % / %', left(v_b::text, 1200), left(v_d::text, 1200);
  end if;
  begin
    raise exception using errcode = 'ZX516', message = pg_temp.scene_0516(c_ua, true)::text;
  exception when sqlstate 'ZX516' then v_l := sqlerrm::jsonb;
  end;
  drop function pg_temp.scene_0516(uuid, boolean);
  drop function pg_temp.plan_0516(uuid, jsonb);

  if v_l->'plain' is distinct from v_d->'plain' or (v_l #>> '{workers,left}')::numeric <> floor((v_l->>'free')::numeric) or (v_l #>> '{workers,crew_max}')::int < (v_l #>> '{workers,crew_min}')::int then
    raise exception '0516 self-assert FAIL: lit, a job without settings is not the plan it was: % / %', left((v_l->'plain')::text, 500), left((v_d->'plain')::text, 500);
  end if;
  -- IN RANGE: the same load; its plan ends at the sale's harbour (the sale is asked again there)
  if (v_l #>> '{in,lines,0,text}' is distinct from v_l #>> '{plain,lines,0,text}' and v_l #>> '{in,lines,0,text}' is distinct from format('BUY %s %s', v_l->>'good', trim_scale((v_l #>> '{rq,units}')::numeric)))
     or coalesce(v_l #>> '{in,lines,-1,text}', '') !~ '^SAIL ' or jsonb_array_length(v_l #> '{in,lines}') <> jsonb_array_length(v_l #> '{plain,lines}') - 1 then
    raise exception '0516 self-assert FAIL: in range: %', left((v_l->'in')::text, 600);
  end if;
  -- OUT OF RANGE: both sides wait with the reason, not stopped, not due, 600 s or more on, her row says it
  if v_l #>> '{dear,wait}' is distinct from 'range' or coalesce(v_l #>> '{dear,sentence}', '') !~ '^buys at [0-9,.]+, your limit [0-9,.]+$' or v_l->'dear' ? 'lines'
     or v_l #>> '{cheap,wait}' is distinct from 'range' or coalesce(v_l #>> '{cheap,sentence}', '') !~ '^sells at [0-9,.]+, your limit [0-9,.]+$'
     or v_l #>> '{wait,code}' is distinct from 'range' or v_l #>> '{wait,sentence}' is distinct from v_l #>> '{dear,sentence}' or v_l->>'state' is distinct from 'waiting'
     or (v_l->>'due')::boolean or (v_l->>'next')::numeric < 600 or v_l->>'paused' is not null then
    raise exception '0516 self-assert FAIL: out of range: % / % / %', v_l->'dear', v_l->'cheap', v_l->'wait';
  end if;
  -- THE CUT: exactly the units under the limit
  if (v_l->>'cut_n')::numeric < 1 or (v_l->>'cut_n')::numeric > (v_l->>'cut_all')::numeric
     or coalesce(v_l #>> '{cut,lines,0,text}', '') not in (format('BUY %s %s', v_l->>'good', trim_scale((v_l->>'cut_n')::numeric)),
                                             case when (v_l->>'cut_n')::numeric = (v_l->>'cut_all')::numeric then format('BUY %s ALL', v_l->>'good') else '-' end) then
    raise exception '0516 self-assert FAIL: the load is not the units under the limit (% of %): %', v_l->'cut_n', v_l->'cut_all', left((v_l->'cut')::text, 400);
  end if;
  -- STOPS
  if v_l #>> '{profit,pause}' is distinct from 'E_STOP_PROFIT' or not (v_l->'profit_ok' ? 'lines') or v_l #>> '{hurt,pause}' is distinct from 'E_STOP_DAMAGE'
     or v_l #>> '{hurt,sentence}' is distinct from 'hull damage 50 %, you stop over 30 %' or v_l->>'hurt_stop' is distinct from 'E_STOP_DAMAGE' or not (v_l->'hurt_ok' ? 'lines')
     or (v_l->>'hurt_due')::boolean or not (v_l->>'mend_due')::boolean or not (v_l->>'mend_plan')::boolean or v_l->>'mend_stop' is not null or v_l->>'mend_wait' is distinct from 'low' then
    raise exception '0516 self-assert FAIL: the stops: % % % %', v_l->'profit', left((v_l->'profit_ok')::text, 200), v_l->'hurt', left((v_l->'hurt_ok')::text, 200);
  end if;
  -- a bad number is refused, each
  if exists (select 1 from jsonb_array_elements(v_l->'bad') e where coalesce(e->>'refused', '') !~ '^E_BAD_ORDER') then
    raise exception '0516 self-assert FAIL: a bad setting is taken: %', v_l->'bad';
  end if;
  -- CREW AND STORES: the hire, the stores, then the buy; a purse that cannot pay them waits; one PROVISION in a plan
  if coalesce(v_l #>> '{crew,lines,0,text}', '') !~ '^HIRE [1-9]' or v_l #>> '{crew,lines,1,text}' is distinct from 'PROVISION DAYS 3' or v_l #>> '{crew,lines,2,text}' !~ '^BUY '
     or v_l #>> '{poor,wait}' is distinct from 'purse'
     or v_l->'merge' is distinct from '[{"text": "HIRE 3"}, {"text": "PROVISION DAYS 20"}, {"text": "BUY x ALL"}]'::jsonb then
    raise exception '0516 self-assert FAIL: crew and stores: % / % / %', left((v_l->'crew')::text, 500), v_l->'poor', v_l->'merge';
  end if;
  -- AT HER SALE
  if v_l #>> '{at_low,wait}' is distinct from 'range' or coalesce(v_l #>> '{at_ok,lines,0,text}', '') !~ '^SELL ' or jsonb_array_length(v_l #> '{at_hurt,lines}') <> 1
     or v_l #>> '{at_hurt,lines,0,text}' is distinct from format('SELL %s ALL', v_l->>'good') then
    raise exception '0516 self-assert FAIL: at her sale: % / % / %', v_l->'at_low', left((v_l->'at_ok')::text, 300), v_l->'at_hurt';
  end if;

  -- ── 8. NOTHING OF THE PROBE SURVIVES ──
  if exists (select 1 from public.players p where p.company_name = 'Casa da Prova 0516') or public.passive_settings_on()
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
           from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0516 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0516 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0516 self-assert ok: THE PASSIVE SETTINGS (dark). Twenty-four hunks once and reversing in eight bodies; no other function moved; seven new functions STABLE and server only, no level asked. Probe (rolled back): "%" and "%" wait; % of % units under the limit; "%"; "%"; %. % ms.',
    v_l #>> '{dear,sentence}', v_l #>> '{cheap,sentence}', v_l->>'cut_n', v_l->>'cut_all', v_l #>> '{profit,sentence}', v_l #>> '{hurt,sentence}',
    (select string_agg(e->>'text', ', ') from jsonb_array_elements(v_l #> '{crew,lines}') e), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0516;
  drop table pre_0516;
end $m$;

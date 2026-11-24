-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights assign_home_enabled)
-- 0492 - A FLEET BRINGS HER GOODS HOME  (dark: the owner's switch assign_home_enabled, false; lit, a fixed standing job may end at the
--        company's home warehouse instead of a sale, and may run a set number of times)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-24: "in hq we will be able to assign the fleet to do trade - designate an item to buy, and then sell at different
--   location, or bring them to the HQ - warehouse." Design: docs/design/hq-corp-2026-11-24.md, B2 (the Warehouse is the home shed), B3
--   (the standing fleet job BECOMES the sea Assignment) and slice 0492 `assign-bring-home`. Dev log docs/dev-log/2026-11-24-assign-bring-home.md.
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse any of it). ONE AUTHORITY: the standing fleet job of 0481 (public.fleet_jobs, its door
--   cmd.set_fleet_job, its one tick). No second job system, no second storage writer, no new table, column or cron job.
--   THE `fixed` JOB'S SETTINGS GAIN TWO NAMES (cmd.set_fleet_job(fleet, 'fixed', {good, buy, sell, stops, end, times})):
--     end    'sell' (today's job: BUY <good> ALL at `buy`, SAIL to `sell`, SELL <good> ALL) or 'store' (BRING HOME: BUY at `buy`, SAIL to
--            the company's home harbour, public.home_port_of, STORE <good> ALL into the home Warehouse through the STORE verb, the one
--            storage door: cmd.do_store -> public.storage_put, its cap and its E_SHED_FULL). With 'store' the server sets `sell` to the
--            home harbour's code (a `sell` sent with it is not read). Refused: no home harbour E_NO_HOME, a home with no warehouse
--            E_NO_WAREHOUSE, `buy` = home E_SAME_DEST, any other word E_BAD_ORDER.
--     times  absent or null: until stopped (today). A whole number 1-999: that many loaded runs. The job keeps `left` in its settings
--            (set to `times`); each run that starts with the BUY at `buy` counts it down (public.fleet_job_open, the one writer of a
--            run); when `left` is 0 and her last delivery is done, the job's next turn CLEARS it (public.fleet_job_note), as
--            cmd.clear_fleet_job would.
--   THE WAREHOUSE'S ROOM (bring home): at `buy` the plan reads the home shed's room (public.storage_cap - public.storage_used, in tuns, less
--     what she already carries of the good): no room for one unit -> the job STOPS, code E_SHED_FULL, her report says "the warehouse at
--     <home> is full"; room for fewer units than her hold takes -> BUY <good> <units that fit> (and no more than her purse and the market
--     give: public.fleet_buy_capacity); else BUY <good> ALL. Nothing is ever dumped: if the shed fills while she sails, her STORE is refused
--     by the shed's own rule (E_SHED_FULL), the cargo stays aboard, and the job stops on that code at its next turn (0481's failed-plan
--     rule). Set again (cmd.set_fleet_job) once there is room, she stores it at home and goes on.
--   THE QUOTE (no server change): the HQ's Assign shows a bring-home run from the reads the board already serves: world.good_board's
--     `buy` row at A (units, cost) and world.trip_cost(fleet, legs A -> home) for the time and the trip's costs (0491: the miles the SAIL
--     settles on). A bring-home run earns nothing until the goods are sold.
--   THE READ: world.away_report's jobs[].params carry end / times / left as set; jobs[].last carries end, leg ('out' on a loaded run) and
--     left after a run; paused 'E_SHED_FULL' with its sentence when the shed is full. No read changes shape.
--   DARK (assign_home_enabled false): cmd.set_fleet_job refuses `end` or `times` (E_NOT_IN_USE); a job that carries them (set while lit)
--     stops at its next turn (E_NOT_IN_USE, "bring home and run counts are not open now"); every other job, set and plan is byte for byte
--     today's (the self-assert runs one fixed-job scene before and after the hunks and compares their digests).
-- ONE AUTHORITY EACH: the end and the count are judged once at the door (public.fleet_job_end) and once at the plan (public.fleet_job_ends);
--   the lines stay public.fleet_job_plan's; the countdown public.fleet_job_open's; the clear public.fleet_job_note's; home
--   public.home_port_of; the shed's room public.storage_cap / public.storage_used; the store cmd.do_store.
-- THE HUNKS (each once in the live body, each reverses): public.fleet_job_set_for x2 (the fixed branch reads the end; the settings keep it),
--   public.fleet_job_plan x6 (a declared variable; the end read after the route; the BUY line; the two SELL lines take the end's verb; the
--   note), public.fleet_job_open x1 (the countdown), public.fleet_job_note x1 (the clear).
-- ROWS. Dark: none. Lit: no new row kind; a bring-home run writes what a fixed run writes (its orders, its job row, the STORE's storage row
--   and STORED event in place of the SELL's rows). A cleared job deletes its own row.
-- COST: per planned bring-home run, three STABLE reads more than a fixed run (the shed's cap and use, the hold; fleet_buy_capacity only when
--   the shed binds). Nothing on the beat.
-- LOCKS: CREATE OR REPLACE x4 by hunks, CREATE FUNCTION x3, one knob. TIME: a few seconds. BUDGET: statement_timeout 60 s, lock_timeout 5 s;
--   fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, assign_home_enabled false (the door refuses the two names; jobs that carry them stop at their next
--   turn; every other job runs as today). Full: a migration reversing the ten hunks (OLD texts below verbatim), dropping the three
--   functions and deleting the knob.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path, owner
--   unmoved; the knob; the three new functions server only (public, anon, authenticated, service_role) and STABLE. THE PROBES (rolled back by
--   raised sentinels; no role is changed): DARK IDENTITY: one fixed-job scene (set, plan, one tick) digested before the hunks and again after
--   them with the switch dark: equal. DARK: the door refuses end / times; a job carrying `end` stops E_NOT_IN_USE. LIT: a bring-home job is
--   set (sell = home, left = times) and the wrong ones refused; the tick sends BUY ALL / SAIL home / STORE ALL and counts `left` down; a shed
--   with room for 3 units: BUY <good> 3; a full shed: the job stops E_SHED_FULL and buys nothing; `left` 0: the next turn clears the job.
--   Proof 195 plays the whole lap: out, home, stored at the bought basis, out again, the count reached and cleared, a full shed, a shed that
--   fills while she sails (nothing dumped).
-- VERSION: 0492 = prod head 0491 + 1.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.fleet_job_set_for(uuid,uuid,text,jsonb)', 'public.fleet_job_plan(uuid)',
                                    'public.fleet_job_open(uuid,jsonb)', 'public.fleet_job_note(uuid,jsonb)'];
  c_new    constant text[] := array['public.assign_home_on()', 'public.fleet_job_end(uuid,jsonb)', 'public.fleet_job_ends(uuid,uuid,jsonb,text)'];
  c_ua     constant uuid := '00000000-0492-4000-8000-0000000000a1';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_d0        jsonb;
  v_d1        jsonb;
  v_lis       uuid;
  v_a         uuid;
  v_fa        uuid;
  v_x         uuid;
  v_xc        text;
  v_g         record;
  v_r         jsonb;
  v_p         jsonb;
  v_texts     text;
  v_room      numeric;
  v_hold      numeric;
  v_orders    bigint;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'assign_home_enabled') or to_regprocedure('public.assign_home_on()') is not null then
    raise exception '0492 refuses: it has been applied once';
  end if;
  if to_regclass('public.fleet_jobs') is null or to_regprocedure('public.fleet_job_plan(uuid)') is null
     or to_regprocedure('public.home_port_of(uuid)') is null or to_regprocedure('public.storage_put(uuid,uuid,uuid,numeric,numeric)') is null
     or to_regprocedure('public.fleet_buy_capacity(uuid,uuid)') is null or to_regprocedure('public.sea_course(uuid,uuid)') is null then
    raise exception '0492 refuses: 0481 (the standing jobs), 0482, 0288 (home) or 0281 (the storage door) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE DARK-IDENTITY SCENE (a temp function: one fixed job set, planned and opened by one tick; its digest, ids and times out) ──
  execute $f$
create function pg_temp.scene_0492(p_uid uuid)
returns jsonb
language plpgsql
as $body$
declare
  v_lis uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_pl  uuid;
  v_fl  uuid;
  v_xc  text;
  v_x   uuid;
  v_gc  text;
  v_set jsonb;
  v_pln jsonb;
  v_job jsonb;
  v_ord jsonb;
  v_rec jsonb;
begin
  v_pl := public.new_house(p_uid, 'Casa da Prova 0492', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  update public.players p set ducats = 2000000 where p.id = v_pl;
  -- the harbour: Lisbon's nearest merchant lane both ways; the good: the one it offers most
  select k.to_port, k.code into v_x, v_xc from public.npc_known_legs(v_lis) k join public.ports p on p.id = k.to_port
   where p.kind = 'HARBOUR' and public.fleet_job_course(v_fl, k.to_port, v_lis) is not null order by k.nm, k.code limit 1;
  select g.code into v_gc from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_x and public.port_offers(v_x, g.id) and pg.stock > 0 and g.bulk > 0
     and not public.culture_refuses((select p.culture from public.ports p where p.id = v_x), g.culture_mask)
   order by pg.stock_target desc, g.code limit 1;
  update public.fleets set port_id = v_x, status = 'DOCKED' where id = v_fl;
  update public.world_config set value = 'true'::jsonb where key = 'fleet_jobs_enabled';
  perform cmd.assume_identity(p_uid);
  v_set := cmd.set_fleet_job(v_fl, 'fixed', jsonb_build_object('good', v_gc, 'buy', v_xc, 'sell', 'LIS')) - 'fleet';
  v_pln := public.fleet_job_plan(v_fl) - 'version';
  call public.tick_fleet_jobs(false);
  select jsonb_build_object('kind', j.kind, 'params', j.params, 'runs', j.runs, 'last', j.last - 'at', 'paused', j.paused_reason) into v_job
    from public.fleet_jobs j where j.fleet_id = v_fl;
  select jsonb_agg(jsonb_build_array(o.raw_text, o.verb, o.status, o.error_code) order by o.seq) into v_ord from public.orders o where o.fleet_id = v_fl;
  select r.receipt - 'steps' || jsonb_build_object('steps', (select jsonb_agg(s - 'fleet' - 'plan_ms' - 'open_ms') from jsonb_array_elements(r.receipt->'steps') s))
    into v_rec from public.fleet_job_runs r order by r.at desc limit 1;
  return jsonb_build_object('at', v_xc, 'good', v_gc, 'set', v_set, 'plan', v_pln, 'job', v_job, 'orders', v_ord, 'receipt', v_rec,
                            'status', (select f.status from public.fleets f where f.id = v_fl));
end
$body$
  $f$;

  begin
    v_d0 := pg_temp.scene_0492(c_ua);
    raise exception using errcode = 'ZX492', message = 'PROBE_ROLLBACK_0492_BEFORE';
  exception when sqlstate 'ZX492' then null;
  end;
  if v_d0->>'good' is null or v_d0 #>> '{set,ok}' is distinct from 'true' or v_d0 #>> '{job,runs}' is distinct from '1' then
    raise exception '0492 self-assert FAIL: the dark-identity scene did not run a fixed job before the hunks: %', left(v_d0::text, 600);
  end if;

  -- ── 3. THE KNOB ──
  insert into public.world_config (key, value, description) values
    ('assign_home_enabled', 'false'::jsonb,
     '0492: THE SWITCH (the owner''s). true: a fixed standing job (cmd.set_fleet_job ''fixed'') may end ''store'' (bring the good home: SAIL to the company''s home harbour, STORE it ALL into the home warehouse; a full warehouse stops the job, E_SHED_FULL) and may run `times` loaded runs, then clear itself. false: the door refuses `end` and `times` (E_NOT_IN_USE), a job carrying them stops at its next turn, and every other job runs as before.');

  -- ── 4. THE RULES ──
  execute $f$
create function public.assign_home_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0492: THE SWITCH, read once: world_config assign_home_enabled.
  select public.wc('assign_home_enabled') = 'true'::jsonb
$body$
  $f$;

  execute $f$
create function public.fleet_job_end(p_player uuid, p_params jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0492: A FIXED JOB'S END AND RUN COUNT, judged once at the door (public.fleet_job_set_for's fixed branch merges this into the settings it
-- was sent). Neither `end` nor `times` sent: {end: null, times: null, left: null} (today's job: nothing kept, nothing a caller sent as
-- `left` either). Else (the switch lit): {end: sell | store, times: n | null, left: n | null}, and with `store` {sell: <home harbour>}.
-- Refusals raise 'E_CODE: sentence' (the door makes the envelope).
declare
  v_end   text := p_params->>'end';
  v_times jsonb := case when jsonb_typeof(p_params->'times') = 'null' then null else p_params->'times' end;
  v_n     int;
  v_home  uuid;
  v_code  text;
begin
  if v_end is null and v_times is null then
    return jsonb_build_object('end', null, 'times', null, 'left', null);
  end if;
  if not public.assign_home_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'bring home and run counts are not open yet');
  end if;
  if v_end is not null and v_end not in ('sell', 'store') then
    perform cmd.refuse('E_BAD_ORDER', 'a fixed job ends with sell or store');
  end if;
  if v_times is not null then
    if jsonb_typeof(v_times) <> 'number' or (v_times::text)::numeric <> floor((v_times::text)::numeric)
       or (v_times::text)::numeric < 1 or (v_times::text)::numeric > 999 then
      perform cmd.refuse('E_BAD_ORDER', 'a run count is a whole number from 1 to 999');
    end if;
    v_n := (v_times::text)::int;
  end if;
  if v_end = 'store' then
    v_home := public.home_port_of(p_player);
    v_code := (select p.code from public.ports p where p.id = v_home and p.kind = 'HARBOUR');
    if v_code is null then
      perform cmd.refuse('E_NO_HOME', 'your company has no home harbour');
    end if;
    if public.storage_cap(v_home) <= 0 then
      perform cmd.refuse('E_NO_WAREHOUSE', format('%s keeps no warehouse', v_code));
    end if;
    if p_params->>'buy' = v_code then
      perform cmd.refuse('E_SAME_DEST', 'the good is bought at home already; bring home buys it in another harbour');
    end if;
    return jsonb_build_object('end', 'store', 'times', v_n, 'left', v_n, 'sell', v_code);
  end if;
  return jsonb_build_object('end', coalesce(v_end, 'sell'), 'times', v_n, 'left', v_n);
end
$body$
  $f$;

  execute $f$
create function public.fleet_job_ends(p_player uuid, p_fleet uuid, p_params jsonb, p_at text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0492: WHAT A FIXED JOB'S END AND COUNT MAKE OF ITS NEXT RUN (public.fleet_job_plan's fixed branch reads this once, after the failed-plan
-- check). {} for today's job (no end, no count): its lines as 0481 wrote them. Dark with either: {pause: E_NOT_IN_USE}. The count spent:
-- {wait: done} (public.fleet_job_note clears the job). Else {verb: SELL | STORE, buy: <the BUY line when the home shed binds>, note: {end,
-- leg, left}}; at `buy` of a bring-home job the home shed's room in units of the good (less what she carries of it) is read: none ->
-- {pause: E_SHED_FULL}; fewer than her hold takes -> buy: 'BUY <good> <units>' (no more than public.fleet_buy_capacity gives).
declare
  v_store boolean := p_params->>'end' = 'store';
  v_home  uuid;
  g       public.goods%rowtype;
  v_room  numeric;
  v_n     numeric;
  v_buy   text;
begin
  if not (p_params ? 'end' or p_params ? 'left') then
    return '{}'::jsonb;
  end if;
  if not public.assign_home_on() then
    return jsonb_build_object('pause', 'E_NOT_IN_USE', 'sentence', 'bring home and run counts are not open now');
  end if;
  if p_params ? 'left' and coalesce((p_params->>'left')::int, 0) <= 0 then
    return jsonb_build_object('wait', 'done');
  end if;
  if v_store and p_at = p_params->>'buy' then
    v_home := (select p.id from public.ports p where p.code = p_params->>'sell' and p.kind = 'HARBOUR');
    select * into g from public.goods x where x.code = p_params->>'good';
    v_room := floor(greatest(public.storage_cap(v_home) - public.storage_used(p_player, v_home), 0) / g.bulk)
              - public.fleet_cargo_qty(p_fleet, g.code);
    if v_room < 1 then
      return jsonb_build_object('pause', 'E_SHED_FULL', 'sentence', format('the warehouse at %s is full', p_params->>'sell'));
    end if;
    if v_room < floor(public.fleet_free_hold(p_fleet) / g.bulk) then
      v_n := least(v_room, coalesce((public.fleet_buy_capacity(p_fleet, g.id)->>'max_qty')::numeric, 0));
      if v_n >= 1 then
        v_buy := format('BUY %s %s', g.code, trim_scale(floor(v_n)));
      end if;
    end if;
  end if;
  return jsonb_strip_nulls(jsonb_build_object(
           'verb', case when v_store then 'STORE' else 'SELL' end, 'buy', v_buy,
           'note', jsonb_strip_nulls(jsonb_build_object('end', coalesce(p_params->>'end', 'sell'),
                                                        'leg', case when p_at = p_params->>'buy' then 'out' end,
                                                        'left', p_params->'left'))));
end
$body$
  $f$;

  -- grants: all three server only (service_role too: the platform grants execute on a new function by default, 0459's first push)
  foreach v_def in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;

  -- ── 5. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0492 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0492 values
  ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', 1,
$h$  elsif p_kind = 'fixed' then
    v_good := (select g.code from public.goods g where g.code = p_params->>'good');$h$,
$h$  elsif p_kind = 'fixed' then
    -- 0492: the end (sell | store at home) and the run count, judged once (public.fleet_job_end); with `store`, `sell` is home
    p_params := p_params || public.fleet_job_end(p_player, p_params);
    v_good := (select g.code from public.goods g where g.code = p_params->>'good');$h$),
  ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', 2,
$h$    v_p := jsonb_build_object('good', v_good, 'buy', p_params->>'buy', 'sell', p_params->>'sell', 'stops', to_jsonb(v_st));$h$,
$h$    v_p := jsonb_build_object('good', v_good, 'buy', p_params->>'buy', 'sell', p_params->>'sell', 'stops', to_jsonb(v_st))
           || jsonb_strip_nulls(jsonb_build_object('end', p_params->'end', 'times', p_params->'times', 'left', p_params->'left'));   -- 0492$h$),
  ('public.fleet_job_plan(uuid)', 1,
$h$  v_qty   numeric;
begin$h$,
$h$  v_qty   numeric;
  v_end   jsonb;   -- 0492: what the fixed job's end and count make of this run (public.fleet_job_ends)
begin$h$),
  ('public.fleet_job_plan(uuid)', 2,
$h$    v_st := array(select jsonb_array_elements_text(coalesce(j.params->'stops', '[]'::jsonb)));
$h$,
$h$    v_st := array(select jsonb_array_elements_text(coalesce(j.params->'stops', '[]'::jsonb)));
    -- 0492: the end (SELL, or STORE at home), the home shed's room, the count; {} for a job without them
    v_end := public.fleet_job_ends(j.player_id, p_fleet, j.params, v_at);
    if v_end ? 'pause' or v_end ? 'wait' then
      return v_end;
    end if;
$h$),
  ('public.fleet_job_plan(uuid)', 3,
$h$format('BUY %s ALL', v_g)$h$,
$h$coalesce(v_end->>'buy', format('BUY %s ALL', v_g))$h$),
  ('public.fleet_job_plan(uuid)', 4,
$h$                 || jsonb_build_array(jsonb_build_object('text', format('SELL %s ALL', v_g)));
      v_to := v_sell;$h$,
$h$                 || jsonb_build_array(jsonb_build_object('text', format('%s %s ALL', coalesce(v_end->>'verb', 'SELL'), v_g)));
      v_to := v_sell;$h$),
  ('public.fleet_job_plan(uuid)', 5,
$h$                      then jsonb_build_array(jsonb_build_object('text', format('SELL %s ALL', v_g))) else '[]'::jsonb end$h$,
$h$                      then jsonb_build_array(jsonb_build_object('text', format('%s %s ALL', coalesce(v_end->>'verb', 'SELL'), v_g))) else '[]'::jsonb end$h$),
  ('public.fleet_job_plan(uuid)', 6,
$h$'note', jsonb_build_object('kind', 'fixed', 'good', v_g, 'from', v_at, 'to', v_to));$h$,
$h$'note', jsonb_build_object('kind', 'fixed', 'good', v_g, 'from', v_at, 'to', v_to) || coalesce(v_end->'note', '{}'::jsonb));   -- 0492$h$),
  ('public.fleet_job_open(uuid,jsonb)', 1,
$h$                         then j.params || jsonb_build_object('good', p_plan #>> '{note,good}') else j.params end$h$,
$h$                         then j.params || jsonb_build_object('good', p_plan #>> '{note,good}')
                         -- 0492: a run that starts with the BUY at `buy` counts the fixed job's run count down
                         when j.params ? 'left' and p_plan #>> '{note,leg}' = 'out'
                         then j.params || jsonb_build_object('left', greatest(coalesce((j.params->>'left')::int, 0) - 1, 0)) else j.params end$h$),
  ('public.fleet_job_note(uuid,jsonb)', 1,
$h$  elsif p_plan->>'wait' in ('nothing', 'unpriced', 'identity') then$h$,
$h$  elsif p_plan->>'wait' = 'done' then
    -- 0492: the run count is spent and her last delivery is done: the job is cleared (as cmd.clear_fleet_job)
    delete from public.fleet_jobs where fleet_id = p_fleet;
  elsif p_plan->>'wait' in ('nothing', 'unpriced', 'identity') then$h$);

  for v_h in select h.fn from hunks_0492 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0492 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0492 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0492 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0492 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0492 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the knob, the grants ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0492 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0492 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> 'assign_home_enabled') <> v_cfg_before
     or public.wc('assign_home_enabled') is distinct from 'false'::jsonb then
    raise exception '0492 self-assert FAIL: a knob other than assign_home_enabled moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.provolatile = 's') <> 3
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0492 self-assert FAIL: a new function is reachable by a client or service_role, or is not STABLE';
  end if;

  -- ── 7. THE PROBES ──
  -- (a) DARK IDENTITY: the same scene after the hunks, the switch dark: the same digest
  begin
    v_d1 := pg_temp.scene_0492(c_ua);
    raise exception using errcode = 'ZX492', message = 'PROBE_ROLLBACK_0492_AFTER';
  exception when sqlstate 'ZX492' then null;
  end;
  if v_d1 is distinct from v_d0 then
    raise exception '0492 self-assert FAIL: dark, the fixed-job scene moved: before % / after %', left(v_d0::text, 700), left(v_d1::text, 700);
  end if;
  v_note := format('dark identity %s (%s at %s: %s)', left(md5(v_d0::text), 8), v_d0->>'good', v_d0->>'at',
                   (select string_agg(e->>0, ' / ') from jsonb_array_elements(v_d0->'orders') e));

  -- (b)-(f): one company at Lisbon (home), her fleet at the scene's harbour; rolled back by the sentinel
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    v_a := public.new_house(c_ua, 'Casa do Armazem 0492', 'PRT');
    select f.id into v_fa from public.fleets f where f.player_id = v_a;
    update public.players p set ducats = 2000000 where p.id = v_a;
    v_xc := v_d0->>'at';
    v_x := (select p.id from public.ports p where p.code = v_xc and p.kind = 'HARBOUR');
    select g.id, g.code, g.bulk into v_g from public.goods g where g.code = v_d0->>'good';
    update public.fleets set port_id = v_x, status = 'DOCKED' where id = v_fa;
    update public.world_config set value = 'true'::jsonb where key = 'fleet_jobs_enabled';
    perform cmd.assume_identity(c_ua);
    if public.home_port_of(v_a) is distinct from v_lis or public.storage_cap(v_lis) <= 0 then
      raise exception '0492 self-assert FAIL: a Portuguese house''s home is not Lisbon, or Lisbon keeps no warehouse';
    end if;

    -- (b) DARK: the door refuses end and times; a job carrying `end` stops E_NOT_IN_USE and sends nothing
    if cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_g.code, 'buy', v_xc, 'end', 'store'))->>'error_code' is distinct from 'E_NOT_IN_USE'
       or cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_g.code, 'buy', v_xc, 'sell', 'LIS', 'times', 2))->>'error_code' is distinct from 'E_NOT_IN_USE'
       or exists (select 1 from public.fleet_jobs j where j.fleet_id = v_fa) then
      raise exception '0492 self-assert FAIL: dark, the door took end or times';
    end if;
    insert into public.fleet_jobs (fleet_id, player_id, kind, params, since, seen_at)
    values (v_fa, v_a, 'fixed', jsonb_build_object('good', v_g.code, 'buy', v_xc, 'sell', 'LIS', 'stops', '[]'::jsonb, 'end', 'store'), now(), now());
    call public.tick_fleet_jobs(false);
    if (select j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from 'E_NOT_IN_USE'
       or exists (select 1 from public.orders o where o.fleet_id = v_fa) then
      raise exception '0492 self-assert FAIL: dark, a bring-home job did not stop E_NOT_IN_USE, or sent lines';
    end if;
    delete from public.fleet_jobs where fleet_id = v_fa;

    -- (c) LIT: the wrong ones refused; a bring-home job of two runs set (sell = home, left = times)
    update public.world_config set value = 'true'::jsonb where key = 'assign_home_enabled';
    if cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_g.code, 'buy', v_xc, 'end', 'dump'))->>'error_code' is distinct from 'E_BAD_ORDER'
       or cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_g.code, 'buy', v_xc, 'end', 'store', 'times', 0))->>'error_code' is distinct from 'E_BAD_ORDER'
       or cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_g.code, 'buy', v_xc, 'end', 'store', 'times', 1.5))->>'error_code' is distinct from 'E_BAD_ORDER'
       or cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_g.code, 'buy', 'LIS', 'end', 'store'))->>'error_code' is distinct from 'E_SAME_DEST'
       or exists (select 1 from public.fleet_jobs j where j.fleet_id = v_fa) then
      raise exception '0492 self-assert FAIL: lit, a wrong bring-home job was not refused by its own code, or was written';
    end if;
    v_r := cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_g.code, 'buy', v_xc, 'sell', 'CAD', 'end', 'store', 'times', 2));
    if (v_r->>'ok')::boolean is not true
       or v_r->'params' is distinct from jsonb_build_object('good', v_g.code, 'buy', v_xc, 'sell', 'LIS', 'stops', '[]'::jsonb, 'end', 'store', 'times', 2, 'left', 2)
       or (world.away_report() #> '{jobs,0,params}') is distinct from v_r->'params' then
      raise exception '0492 self-assert FAIL: lit, the bring-home job was not set with sell = home and left = times: %', v_r;
    end if;

    -- (d) THE RUN: BUY ALL / SAIL LIS / STORE ALL (the shed has room for more than her hold), `left` 2 -> 1, she sails home
    call public.tick_fleet_jobs(false);
    select string_agg(o.raw_text, ' / ' order by o.seq) into v_texts
      from public.orders o where o.fleet_id = v_fa and o.plan_id = (select j.last_plan from public.fleet_jobs j where j.fleet_id = v_fa);
    if v_texts is distinct from format('BUY %s ALL / SAIL LIS / STORE %s ALL', v_g.code, v_g.code)
       or (select j.params->>'left' from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from '1'
       or (select j.last->>'leg' from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from 'out'
       or (select j.runs from public.fleet_jobs j where j.fleet_id = v_fa) <> 1
       or public.fleet_cargo_qty(v_fa, v_g.code) < 1
       or not exists (select 1 from public.voyages v where v.fleet_id = v_fa and v.status = 'SAILING' and v.dest_port_id = v_lis) then
      raise exception '0492 self-assert FAIL: the bring-home run did not BUY, SAIL home with STORE queued and count down: % (%)', v_texts,
        (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fa);
    end if;
    v_note := v_note || format('; lit: %s, left 2 -> 1', v_texts);

    -- (e) THE SHED BINDS: back at the harbour, empty-handed; the home shed with room for 3 units: BUY <good> 3; then none: E_SHED_FULL
    update public.orders set status = 'cancelled' where fleet_id = v_fa and status in ('pending', 'active');
    update public.voyages set status = 'ARRIVED' where fleet_id = v_fa and status = 'SAILING';
    update public.fleets set status = 'DOCKED', port_id = v_x where id = v_fa;
    perform public.fleet_unload(v_fa, v_g.code, public.fleet_cargo_qty(v_fa, v_g.code));
    update public.fleet_jobs set last_plan = null where fleet_id = v_fa;
    v_hold := floor(public.fleet_free_hold(v_fa) / v_g.bulk);
    v_room := floor((public.storage_cap(v_lis) - public.storage_used(v_a, v_lis)) / v_g.bulk);
    if v_hold <= 3 or v_room <= 3 then
      raise exception '0492 self-assert FAIL: her hold (% units) or the home shed (% units) is too small for the scene', v_hold, v_room;
    end if;
    perform public.storage_put(v_a, v_lis, v_g.id, v_room - 3, 1);
    v_p := public.fleet_job_plan(v_fa);
    if v_p #>> '{lines,0,text}' is distinct from format('BUY %s 3', v_g.code) or v_p #>> '{lines,-1,text}' is distinct from format('STORE %s ALL', v_g.code) then
      raise exception '0492 self-assert FAIL: a shed with room for 3 units did not make the BUY 3: %', v_p;
    end if;
    perform public.storage_put(v_a, v_lis, v_g.id, 3, 1);
    v_orders := (select count(*) from public.orders o where o.fleet_id = v_fa);
    call public.tick_fleet_jobs(false);
    if (select j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from 'E_SHED_FULL'
       or (select j.last->>'sentence' from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from 'the warehouse at LIS is full'
       or world.away_report() #>> '{jobs,0,state}' is distinct from 'stopped'
       or (select count(*) from public.orders o where o.fleet_id = v_fa) <> v_orders
       or public.fleet_cargo_qty(v_fa, v_g.code) <> 0 then
      raise exception '0492 self-assert FAIL: a full shed did not stop the job E_SHED_FULL without a buy: %',
        (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_fa);
    end if;

    -- (f) THE COUNT SPENT: left 0, the next turn clears the job (the receipt says done)
    update public.fleet_jobs set paused_reason = null, params = params || jsonb_build_object('left', 0) where fleet_id = v_fa;
    call public.tick_fleet_jobs(false);
    if exists (select 1 from public.fleet_jobs j where j.fleet_id = v_fa)
       or (select r.receipt #>> '{steps,0,wait}' from public.fleet_job_runs r order by r.at desc limit 1) is distinct from 'done'
       or (select count(*) from public.orders o where o.fleet_id = v_fa) <> v_orders then
      raise exception '0492 self-assert FAIL: a spent run count did not clear the job: %', (select r.receipt from public.fleet_job_runs r order by r.at desc limit 1);
    end if;
    v_note := v_note || format('; shed room 3 -> BUY 3, full -> E_SHED_FULL, left 0 -> cleared');
    raise exception using errcode = 'ZX492', message = 'PROBE_ROLLBACK_0492';
  exception when sqlstate 'ZX492' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0492 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0492' or p.auth_uid = c_ua)
     or public.wc('assign_home_enabled') is distinct from 'false'::jsonb
     or public.current_player_id() is not null then
    raise exception '0492 self-assert FAIL: the probe left something behind';
  end if;
  drop function pg_temp.scene_0492(uuid);

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0492 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0492 self-assert ok: A FLEET BRINGS HER GOODS HOME (dark). % hunks once and reversing; no other function moved; the hunked bodies'' grants and volatility unmoved; three new functions STABLE and server only; one knob (assign_home_enabled false). Probes (rolled back): %. % ms.',
    (select count(*) from hunks_0492), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;

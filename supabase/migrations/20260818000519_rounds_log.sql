-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights rounds_enabled)
-- 0519 - ROUNDS: THE READ, THE STOP RULE, REPEAT OR GO  (dark behind rounds_enabled, 0518. Slice `rounds-log`, docs/design/rounds-2026-11-25.md)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHAT
--   cmd.round_send(fleet, work, stop), cmd.round_home(fleet)   the two doors (owner-checked; a refusal is the envelope)
--   world.rounds(fleet)   the one read: {on, runs: her fleets' runs (the rounds done, the next one's instant, the stop, why, what a round costs, the
--                         last 20 lines of the log), works: for the fleet named, each lit work, its level, and what a Send would freeze
--                         (public.round_terms: the cost of a round and the most rounds, never odds)}. Dark: {on: false}. Reads only.
--   THE JOB KIND `round` (public.fleet_jobs): params {work, base, crew, days, stop: {crew, days, rounds}, then: repeat | home}. cmd.set_fleet_job sets it
--                         (public.round_job_param judges it; no level but the work's own), and the jobs' tick runs it:
--                           away from her base she sails to it (0494's legs: harbour by harbour, the sea gate kept);
--                           at her base: the hands to `crew` (HIRE), the stores to `days` (PROVISION DAYS), a worn hull mended (REPAIR), each a line of
--                           an ordinary plan; with nothing left to take on, she is sent (public.round_send_for);
--                           too few stores or hands for one round: she WAITS with the reason, as 0498's prices low (one wait authority);
--                           home after a run and `then` home: the job is done and cleared; repeat: again.
--   public.round_settle_due  at the head of the jobs' tick (every 2 minutes, NOT the beat): at most 20 fleets whose stop time has passed are settled, so a
--                         company that is away gets its fleets in. Reads her fleets' ROUNDS status alone.
-- THE COST of the tick: lit, one read of the fleets on ROUNDS past their stop (a sequential read of the fleets table, about a thousand rows, 0.1 to
--   0.3 ms) and a settle a fleet that is over (0.6 ms); measured in docs/dev-log/2026-11-25-rounds-log.md. Dark: one switch read.
-- ROWS, lit: a run is 1 round_runs row kept, 2 fleets updates, 1 to 3 ships updates, 1 event; a job's lines as any job's. Per minute, 6 fleets a company,
--   runs of 4 hours: about 0.25 rows a minute a company, 25 for a hundred. -- budget: above. -- retention: none (no table is made).
-- LOCKS: the fleet_jobs kind check dropped and added, CREATE FUNCTION x9, CREATE OR REPLACE x5 by hunks. BUDGET: statement_timeout 60 s; fails above 30 s.
-- ROLLBACK (forward, owner only): rounds_enabled false. FULL: a migration reversing the hunks and dropping the functions.
-- SELF-ASSERT: hunks once and reversing; no other function moved; grants as listed. THE PROBE (rolled back; its own company and work; the plan and the
--   open called for its own job alone, never the tick): dark refused; a job of rounds plans its lines, then its send; waits when short; done when home.
--   Proof 223 plays it through the tick and the doors.
-- VERSION: 0519 (after 0518).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.fleet_job_plan(uuid)', 'public.fleet_job_open(uuid,jsonb)', 'public.fleet_job_set_for(uuid,uuid,text,jsonb)',
                                    'public.tick_fleet_jobs(boolean)', 'public.workers_for(uuid)', 'public.client_rpc_entry_points()'];
  c_new    constant text[] := array['public.round_job_param(uuid,uuid,jsonb)', 'public.round_plan(uuid)', 'public.round_settle_due(timestamptz,integer)',
                                    'public.round_run_card(uuid)', 'public.round_works_for(uuid,uuid)', 'public.round_door(uuid,text,jsonb)'];
  c_doors  constant text[] := array['cmd.round_send(uuid,text,jsonb)', 'cmd.round_home(uuid)', 'world.rounds(uuid)'];
  c_knobs  constant text[] := array['round_none'];
  c_ua     constant uuid := '00000000-0519-4000-8000-0000000000a1';
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
  v_l          jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('cmd.round_send(uuid,text,jsonb)') is not null then
    raise exception '0519 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.round_send_for(uuid,uuid,text,jsonb,timestamptz)', 'public.job_wait_s(uuid)']) f where to_regprocedure(f) is null) then
    raise exception '0519 refuses: 0518 (the rounds) or the jobs are not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0519 (fn text primary key, def text) on commit drop;
  insert into pre_0519 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  alter table public.fleet_jobs drop constraint fleet_jobs_kind_check,
    add constraint fleet_jobs_kind_check check (kind in ('best', 'fixed', 'land', 'round'));

  -- ── 2. THE RULES ──
  execute $f$
create function public.round_job_param(p_player uuid, p_fleet uuid, p_params jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0519: A ROUNDS JOB'S SETTINGS, judged once where it is set: the work (lit, her level), the base (a harbour; hers where she lies when none is named), the
-- hands and the days of stores to put out with, the stop {crew, days, rounds} and what then (repeat, the default, or home).
declare
  w      public.round_works%rowtype;
  v_base text;
  v_max  int;
  v_need int;
  k      record;
  v_out  jsonb;
  v_stop jsonb := '{}'::jsonb;
begin
  if not public.rounds_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'rounds are not open yet');
  end if;
  select * into w from public.round_works q where q.code = p_params->>'work';
  if w.code is null or (w.lit_by is not null and public.wc(w.lit_by) is distinct from 'true'::jsonb) then
    perform cmd.refuse('E_NOT_IN_USE', 'that work is not open yet');
  end if;
  if public.round_level(p_player, w.skill) < w.level then
    perform cmd.refuse('E_LEVEL', format('%s asks %s level %s', w.word, w.skill, w.level));
  end if;
  v_base := coalesce(p_params->>'base', (select h.code from public.fleets f join public.ports h on h.id = f.port_id where f.id = p_fleet));
  if not exists (select 1 from public.ports h where h.code = v_base and h.kind = 'HARBOUR' and h.sea_id is not null) then
    perform cmd.refuse('E_NO_SUCH_PORT', 'name a harbour of the sea she is to work');
  end if;
  select coalesce(sum(c.crew_required), 0), coalesce(sum((select sb.crew_max from public.ship_base(s.id) sb)), 0) into v_need, v_max
    from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = p_fleet;
  v_out := jsonb_build_object('work', w.code, 'base', v_base, 'then', case when p_params->>'then' = 'home' then 'home' else 'repeat' end);
  for k in select * from (values ('crew', v_need, v_max, 'the hands'), ('days', 1, 120, 'the days of food and water')) t(code, lo, hi, word) loop
    continue when coalesce(jsonb_typeof(p_params->k.code), 'null') = 'null';
    if jsonb_typeof(p_params->k.code) <> 'number' or (p_params->>k.code)::numeric not between k.lo and k.hi or (p_params->>k.code)::numeric <> floor((p_params->>k.code)::numeric) then
      perform cmd.refuse('E_BAD_ORDER', format('%s is a number from %s to %s', k.word, k.lo, k.hi));
    end if;
    v_out := v_out || jsonb_build_object(k.code, p_params->k.code);
  end loop;
  for k in select * from (values ('crew', v_need, v_max, 'the least hands'), ('days', 0, 120, 'the days kept'), ('rounds', 1, 999, 'the rounds')) t(code, lo, hi, word) loop
    continue when coalesce(jsonb_typeof(p_params #> array['stop', k.code]), 'null') = 'null';
    if jsonb_typeof(p_params #> array['stop', k.code]) <> 'number' or (p_params #>> array['stop', k.code])::numeric not between k.lo and k.hi
       or (p_params #>> array['stop', k.code])::numeric <> floor((p_params #>> array['stop', k.code])::numeric) then
      perform cmd.refuse('E_BAD_ORDER', format('%s is a number from %s to %s', k.word, k.lo, k.hi));
    end if;
    v_stop := v_stop || jsonb_build_object(k.code, p_params #> array['stop', k.code]);
  end loop;
  return v_out || jsonb_build_object('stop', v_stop);
end
$body$
  $f$;
  execute $f$
create function public.round_plan(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0519: WHAT A ROUNDS JOB DOES NOW (public.fleet_job_plan's arm, for a fleet DOCKED with nothing queued): {lines, note, version} (sail to the base; hire,
-- provision, repair there), {lines: [], send: {work, stop}, ...} (nothing left to take on: she is sent), {wait, sentence}, {pause}, or {wait: done}. Writes nothing.
declare
  j       public.fleet_jobs%rowtype;
  f       public.fleets%rowtype;
  v_at    text;
  v_s     jsonb;
  v_lines jsonb := '[]'::jsonb;
  t       jsonb;
  v_n     int;
  v_need  numeric;
  v_dmg   numeric;
begin
  select * into j from public.fleet_jobs q where q.fleet_id = p_fleet;
  select * into f from public.fleets q where q.id = p_fleet;
  if not public.rounds_on() then
    return jsonb_build_object('pause', 'E_NOT_IN_USE', 'sentence', 'rounds are not open now');
  end if;
  if j.params->>'then' = 'home' and exists (select 1 from public.round_runs r where r.fleet_id = p_fleet and r.state = 'home' and r.sent_at > j.since) then
    return jsonb_build_object('wait', 'done');
  end if;
  v_at := (select h.code from public.ports h where h.id = f.port_id);
  if v_at is distinct from j.params->>'base' then
    v_s := public.fleet_job_sails(p_fleet, f.port_id, array[j.params->>'base']);
    if v_s ? 'missing' then
      return jsonb_build_object('pause', coalesce(v_s->>'pause', 'E_NO_COURSE'), 'sentence', coalesce(v_s->>'sentence', format('no course the world remembers reaches %s', v_s->>'missing')));
    end if;
    return jsonb_build_object('lines', v_s->'lines', 'version', f.version, 'note', jsonb_build_object('kind', 'round', 'work', j.params->>'work', 'from', v_at, 'to', j.params->>'base'));
  end if;
  -- what she takes on first, each only where it can be had (a door would refuse it: no line)
  if j.params ? 'crew' then
    select least((j.params->>'crew')::int, sum((select sb.crew_max from public.ship_base(s.id) sb))) - sum(s.crew) into v_n from public.ships s where s.fleet_id = p_fleet;
    if v_n > 0 and coalesce((select h.crew_pool from public.ports h where h.id = f.port_id), 0) > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('text', format('HIRE %s', v_n)));
    end if;
  end if;
  if j.params ? 'days' then
    select coalesce(sum(q.water_t + q.food_t), 0) into v_need
      from public.ships s cross join lateral public.stores_topup(s.crew, s.water_t, s.food_t,
             public.ship_stores_room(s.id, public.ship_hold_capacity(s.id) - public.ship_cargo_tuns(s.id)), (j.params->>'days')::numeric, 0) q
     where s.fleet_id = p_fleet;
    if v_need > 0.05 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('text', format('PROVISION DAYS %s', j.params->>'days')));
    end if;
  end if;
  v_dmg := public.fleet_damage_pct(p_fleet);
  if v_dmg >= 5 and public.port_has_shipyard(f.port_id) then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('text', 'REPAIR'));
  end if;
  if jsonb_array_length(v_lines) > 0 then
    return jsonb_build_object('lines', v_lines, 'version', f.version, 'note', jsonb_build_object('kind', 'round', 'work', j.params->>'work', 'from', v_at, 'to', v_at));
  end if;
  t := public.round_terms(p_fleet, j.params->>'work', j.params->'stop');
  if coalesce((t->>'most')::int, 0) < 1 then
    return jsonb_build_object('wait', 'range', 'sentence', case t->>'why' when 'food' then 'not enough food for a round' when 'water' then 'not enough water for a round'
                                                                          when 'crew' then 'not enough crew for a round' else 'no round to do' end);
  end if;
  return jsonb_build_object('lines', '[]'::jsonb, 'send', jsonb_build_object('work', j.params->>'work', 'stop', j.params->'stop'), 'version', f.version,
                            'note', jsonb_build_object('kind', 'round', 'work', j.params->>'work', 'from', v_at, 'rounds', t->'most'));
end
$body$
  $f$;
  execute $f$
create function public.round_settle_due(p_now timestamptz, p_most integer)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0519: THE FLEETS WHOSE RUN IS OVER, settled (the jobs' tick calls this first, every 2 minutes; never the beat): at most p_most, a fleet held by another
-- is left for the next. Dark: nothing. Answers how many.
declare
  r   record;
  v_n int := 0;
begin
  if not public.rounds_on() then
    return 0;
  end if;
  for r in select f.id from public.fleets f where f.status = 'ROUNDS' and f.busy_until <= p_now order by f.busy_until limit p_most for update skip locked loop
    perform public.round_settle(r.id, p_now);
    v_n := v_n + 1;
  end loop;
  return v_n;
end
$body$
  $f$;
  execute $f$
create function public.round_run_card(p_fleet uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0519: ONE FLEET'S RUN as it is served: what it does, where, the rounds done and the next one's instant, the stop and why, what a round costs (the mean,
  -- never a chance), what it has in hand, its last 20 lines. Null: she was never sent.
  select jsonb_build_object('fleet', r.fleet_id, 'work', r.work, 'kind', w.kind, 'word', w.word, 'sea', (select s.name from public.seas s where s.id = r.sea_id),
           'state', case when p->>'over' = 'true' then 'home' else r.state end, 'sent_at', r.sent_at, 'stop_at', r.stop_at, 'ended', r.ended,
           'rounds', greatest(r.booked, (p->>'rounds')::int), 'most', r.terms->'most', 'why', r.terms->>'why', 'next_at', p->'next_at',
           'seconds', r.terms->'seconds', 'cost', jsonb_build_object('food', r.terms->'food', 'water', r.terms->'water', 'crew', r.terms->'crew'),
           'stop', r.stop, 'carry', r.carry, 'log', r.log)
    from public.round_runs r join public.round_works w on w.code = r.work
    cross join lateral public.round_progress(r.fleet_id, now()) p
   where r.fleet_id = p_fleet
$body$
  $f$;
  execute $f$
create function public.round_works_for(p_player uuid, p_fleet uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0519: EACH LIT WORK for one fleet: its level and whether hers is enough, and what a Send would freeze now (public.round_terms): what a round costs and the
  -- most rounds there can be. No odds are served.
  select coalesce(jsonb_agg(jsonb_build_object('work', w.code, 'kind', w.kind, 'word', w.word, 'skill', w.skill, 'level', w.level,
           'open', public.round_level(p_player, w.skill) >= w.level, 'terms', public.round_terms(p_fleet, w.code, '{}'::jsonb)) order by w.ord), '[]'::jsonb)
    from public.round_works w where w.lit_by is null or public.wc(w.lit_by) = 'true'::jsonb
$body$
  $f$;
  execute $f$
create function public.round_door(p_fleet uuid, p_work text, p_stop jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0519: THE ONE DOOR SHAPE of the two (p_work null: call her in): the caller's company, then the core; a refusal is the envelope. Server only.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null or coalesce((select p.is_npc from public.players p where p.id = v_player), true) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    if p_work is null then
      return public.round_home_for(v_player, p_fleet, now());
    end if;
    return public.round_send_for(v_player, p_fleet, p_work, p_stop, now());
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$
  $f$;
  execute $f$
create function cmd.round_send(p_fleet uuid, p_work text, p_stop jsonb default '{}'::jsonb)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $body$
  -- 0519: send a fleet on rounds from the harbour she lies in (public.round_send_for).
  select public.round_door(p_fleet, coalesce(p_work, ''), p_stop)
$body$
  $f$;
  execute $f$
create function cmd.round_home(p_fleet uuid)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $body$
  -- 0519: call her in (public.round_home_for): the rounds passed are kept.
  select public.round_door(p_fleet, null, null)
$body$
  $f$;
  execute $f$
create function world.rounds(p_fleet uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0519: THE ROUNDS, the client's one read: her fleets' runs, and for a fleet of hers that is named, the works and what a Send would cost. Dark {on: false};
-- signed out or a merchant {on: true, company: false}. Writes nothing.
declare
  v_me uuid := public.current_player_id();
begin
  if not public.rounds_on() then
    return jsonb_build_object('on', false);
  end if;
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return jsonb_build_object('on', true, 'company', false);
  end if;
  return jsonb_build_object('on', true, 'company', true, 'now', now(),
           'runs', (select coalesce(jsonb_agg(public.round_run_card(f.id) order by f.created_at, f.id) filter (where exists (select 1 from public.round_runs r where r.fleet_id = f.id)), '[]'::jsonb)
                      from public.fleets f where f.player_id = v_me),
           'works', case when exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = v_me) then public.round_works_for(v_me, p_fleet) else '[]'::jsonb end);
end
$body$
  $f$;
  foreach v_def in array c_new || c_doors loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;
  foreach v_def in array c_doors loop
    execute format('grant execute on function %s to authenticated', v_def::regprocedure);
  end loop;

  -- ── 3. THE HUNKS ──
  create temp table hunks_0519 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0519 values
  ('public.fleet_job_plan(uuid)', 1,
$h$  elsif j.kind = 'land' then
    if not public.land_on() then
      return jsonb_build_object('pause', 'E_NOT_IN_USE', 'sentence', 'the land is not open');
$h$,
$h$  elsif j.kind = 'round' then
    return public.round_plan(p_fleet);   -- 0519: a job of rounds

  elsif j.kind = 'land' then
    if not public.land_on() then
      return jsonb_build_object('pause', 'E_NOT_IN_USE', 'sentence', 'the land is not open');
$h$),
  ('public.fleet_job_open(uuid,jsonb)', 1,
$h$    v_r := cmd.issue_lines(p_fleet, p_plan->'lines', (p_plan->>'version')::int);
$h$,
$h$    if p_plan ? 'send' then   -- 0519: a job of rounds sends her (the same envelope; a refusal stops the job on its own code)
      v_r := public.round_door(p_fleet, p_plan #>> '{send,work}', p_plan #> '{send,stop}');
    else
    v_r := cmd.issue_lines(p_fleet, p_plan->'lines', (p_plan->>'version')::int);
    end if;
$h$),
  ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', 1,
$h$  elsif p_kind = 'land' then
$h$,
$h$  elsif p_kind = 'round' then
    v_p := public.round_job_param(p_player, p_fleet, p_params);   -- 0519
  elsif p_kind = 'land' then
$h$),
  ('public.tick_fleet_jobs(boolean)', 1,
$h$  v_max := greatest(0, coalesce(public.wc_int('fleet_jobs_per_tick'), 4));
$h$,
$h$  -- 0519 (rounds_enabled): the fleets whose rounds are over come in first (at most 20), so a job can send them again in this run
  if public.round_settle_due(v_now0, 20) > 0 and p_commit then
    commit;
  end if;
  v_max := greatest(0, coalesce(public.wc_int('fleet_jobs_per_tick'), 4));
$h$),
  ('public.workers_for(uuid)', 1,
$h$                           else format('sea:haul:%s', r.params->>'to') end;
$h$,
$h$                           when 'round' then format('round:%s:%s', r.params->>'work', r.params->>'base')   -- 0519
                           else format('sea:haul:%s', r.params->>'to') end;
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'workers',               ''),
$h$,
$h$      ('world',       'workers',               ''),
      -- 0519: rounds: the read and the two doors (dark {on: false} / E_NOT_IN_USE)
      ('world',       'rounds',                'uuid'),
      ('cmd',         'round_send',            'uuid, text, jsonb'),
      ('cmd',         'round_home',            'uuid'),
$h$);

  for x in select distinct h.fn from hunks_0519 h loop
    v_pre := (select p.def from pre_0519 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0519 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0519 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0519 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0519 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0519 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new || c_doors) u(q)))) <> v_fn_before then
    raise exception '0519 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0519 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before or public.rounds_on() then
    raise exception '0519 self-assert FAIL: a knob of another file moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0519 self-assert FAIL: a new function is reachable by a client or service_role';
  end if;

  if exists (select 1 from unnest(c_doors) u(q) where not has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')) then
    raise exception '0519 self-assert FAIL: a door is not the signed-in company''s alone';
  end if;

  -- ── 4. THE PROBE ──
  begin
    declare
      v_pl uuid; v_fl uuid; v_dark jsonb; p1 jsonb; p2 jsonb; p3 jsonb; p4 jsonb; v_o int; v_rd jsonb; v_set jsonb; v_w jsonb; v_bad jsonb; i int; v_max int;
    begin
      v_pl := public.new_house(c_ua, 'Casa da Prova 0519', 'PRT');
      select f.id into v_fl from public.fleets f where f.player_id = v_pl;
      update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled');
      update public.players set ducats = 1000000 where id = v_pl;
      update public.ports set crew_pool = 200 where id = (select f.port_id from public.fleets f where f.id = v_fl);
      perform cmd.assume_identity(c_ua);
      v_dark := jsonb_build_array(world.rounds(v_fl), cmd.round_send(v_fl, 'probe_work', '{}')->'error_code', cmd.set_fleet_job(v_fl, 'round', '{"work": "probe_work"}')->'error_code');
      update public.world_config set value = 'true'::jsonb where key = 'rounds_enabled';
      insert into public.round_works (code, ord, kind, word, skill, seconds, food_days, water_days, crew_pct) values ('probe_work', 1, 'sea', 'Probe', 'exploration', 600, 0.4, 0.4, 2);
      select sum((select sb.crew_max from public.ship_base(s.id) sb)) into v_max from public.ships s where s.fleet_id = v_fl;
      update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb) - 2, food_t = 0, water_t = 0 where s.fleet_id = v_fl;
      v_bad := jsonb_build_array(cmd.set_fleet_job(v_fl, 'round', '{"work": "nothing"}')->'error_code', cmd.set_fleet_job(v_fl, 'round', '{"work": "probe_work", "crew": 9999}')->'error_code',
                                 cmd.set_fleet_job(v_fl, 'round', '{"work": "probe_work", "stop": {"rounds": 0}}')->'error_code');
      v_set := cmd.set_fleet_job(v_fl, 'round', jsonb_build_object('work', 'probe_work', 'crew', v_max, 'days', 10, 'stop', jsonb_build_object('rounds', 3, 'days', 1), 'then', 'home'));
      p1 := public.fleet_job_plan(v_fl);                                  -- the crew and the stores
      for i in 1 .. 50 loop
        v_o := public.fleet_job_open(v_fl, p1);
        exit when v_o <> -1;
        perform pg_sleep(0.1);
      end loop;
      p2 := public.fleet_job_plan(v_fl);                                  -- nothing left: the send
      for i in 1 .. 50 loop
        v_o := public.fleet_job_open(v_fl, p2);
        exit when v_o <> -1;
        perform pg_sleep(0.1);
      end loop;
      v_rd := world.rounds(v_fl);
      v_w := world.workers() #> '{workers,0}';
      perform public.round_settle(v_fl, now() + interval '2 hours');
      update public.fleet_jobs set since = since - interval '1 minute' where fleet_id = v_fl;
      p3 := public.fleet_job_plan(v_fl);                                  -- home, and `then` home: done
      update public.fleet_jobs set params = params || '{"then": "repeat"}' where fleet_id = v_fl;
      update public.ships s set food_t = 0, water_t = 0 where s.fleet_id = v_fl;
      update public.fleet_jobs set params = params - 'days' - 'crew' where fleet_id = v_fl;
      p4 := public.fleet_job_plan(v_fl);                                  -- no stores and no days set: it waits
      raise exception using errcode = 'ZX519', message = jsonb_build_object('dark', v_dark, 'bad', v_bad, 'set', v_set, 'p1', p1, 'p2', p2, 'o', v_o, 'rd', v_rd, 'w', v_w, 'p3', p3, 'p4', p4)::text;
    end;
  exception when sqlstate 'ZX519' then v_l := sqlerrm::jsonb;
  end;
  if v_l is null or v_l->'dark' is distinct from '[{"on": false}, "E_NOT_IN_USE", "E_NOT_IN_USE"]'::jsonb or v_l->'bad' is distinct from '["E_NOT_IN_USE", "E_BAD_ORDER", "E_BAD_ORDER"]'::jsonb
     or not (v_l #>> '{set,ok}')::boolean or coalesce(v_l #>> '{p1,lines,0,text}', '') <> 'HIRE 2' or coalesce(v_l #>> '{p1,lines,1,text}', '') <> 'PROVISION DAYS 10'
     or v_l #> '{p2,send,work}' is distinct from '"probe_work"'::jsonb or (v_l->>'o')::int is distinct from 1
     or v_l #>> '{rd,runs,0,state}' is distinct from 'out' or (v_l #>> '{rd,runs,0,most}')::int is distinct from 3 or v_l #>> '{rd,runs,0,why}' is distinct from 'rounds' or jsonb_array_length(v_l #> '{rd,works}') <> 1
     or v_l #>> '{w,state}' is distinct from 'working' or v_l #>> '{p3,wait}' is distinct from 'done' or v_l #>> '{p4,wait}' is distinct from 'range' or coalesce(v_l #>> '{p4,sentence}', '') !~ '^not enough (food|water)' then
    raise exception '0519 self-assert FAIL: the probe: %', v_l;
  end if;

  -- ── 5. NOTHING OF THE PROBE SURVIVES ──
  if exists (select 1 from public.players p where p.company_name = 'Casa da Prova 0519') or public.rounds_on() or exists (select 1 from public.round_works q where q.code = 'probe_work')
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0519 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0519 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0519 self-assert ok: ROUNDS, THE READ AND THE JOB (dark). Six hunks once and reversing; no other function moved; six functions server only, three doors the signed-in company''s. Probe (rolled back): % ; then sent: % rounds, why %; home: %; short: "%". % ms.',
    (select string_agg(e->>'text', ', ') from jsonb_array_elements(v_l #> '{p1,lines}') e), v_l #>> '{rd,runs,0,most}', v_l #>> '{rd,runs,0,why}', v_l #>> '{p3,wait}', v_l #>> '{p4,sentence}',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0519;
  drop table pre_0519;
end $m$;

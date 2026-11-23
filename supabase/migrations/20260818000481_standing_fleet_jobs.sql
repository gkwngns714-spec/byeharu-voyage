-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0481 - STANDING FLEET JOBS  (dark: the owner's switch fleet_jobs_enabled, false; lit, a fleet given a job in HQ goes on with it by
--        herself whenever she lies idle in port, and HQ reports what each job did while the player was away)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/hq-command-2026-11-23.md section 2, v2 "Standing fleet jobs" and "Land -> yard carry" and "The away report"
--   (owner idea 3). docs/dev-log/2026-11-23-fleet-jobs.md.
--
-- WHY: the owner, 2026-11-23: "i want this game to be strategical game, where all the work(activities) are done in HQ - words with
--   graphics. choosing best options available, finding best options." His approved plan, item 3: "Fleets get standing assignments in HQ
--   ... and keep working while she is away. She comes back to a report and re-plans."
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse any of it; every figure is a knob):
--   THE TABLE public.fleet_jobs: ONE standing job a fleet (the key), one of three kinds:
--     best   "repeat the best run": each time she lies idle, her best paying sale from where she lies (world.best_sales, the desk's own
--            read; v1's filter: pays, a harbour, a profit, `near` not false), by coin an hour, the first of the best fleet_jobs_runs (12) whose
--            every leg the world remembers a course for (below). BUY <good> <units> (none for her own cargo), SAIL through the passage's
--            stops (world.board_passages, as 0480's board asks it), SELL <good> ALL.
--     fixed  "a fixed route" {good, buy, sell, stops}: at `buy` BUY <good> ALL, SAIL (through the stops) to `sell`, SELL <good> ALL;
--            anywhere else, SELL what she carries of it when she lies at `sell`, then SAIL back to `buy` (the stops reversed).
--     land   "carry Land output to the yard" {to, good}: at the Land party's harbour, TAKE <good> ALL out of the Storage the Land fills
--            (public.land_settle's own Storage), SAIL to `to`, STORE <good> ALL there; anywhere else, SAIL back to the party's harbour.
--            `to` defaults to the nearest harbour with a building yard and a warehouse that a remembered course joins; `good` to the
--            party's own good (terms, or the haul waiting), remembered once seen.
--   A COURSE IS THE WORLD'S: the server cannot plot one (cmd.do_sail refuses E_NO_COURSE a SAIL with no course when land is in the way),
--     so a job sails only a course already sailed and verified between two harbours, either way: a merchant lane (public.npc_known_legs),
--     a coast course (public.npc_coast_legs), or the newest voyage her own company sailed there (voyage.course_of over its stored
--     segments: what her chart plotted, ended or under way). cmd.do_sail re-judges it at every departure. public.fleet_job_course.
--     So a trip she has sent once by hand (a board card's press) can be her job from then on (the card's Repeat).
--   THE DOORS (registered, signed-in players only, owner-checked, the {ok:false} envelope): cmd.set_fleet_job(fleet, kind, params),
--     cmd.clear_fleet_job(fleet), cmd.fleet_jobs_seen() (she has read the away report: its tallies start again). Dark: E_NOT_IN_USE.
--     A fleet that runs a standing route is refused (E_ROUTE_TAKEN): the route is her job already.
--   THE TICK public.tick_fleet_jobs(p_commit) (pg_cron byeharu-voyage:fleet-jobs, every 2 minutes, CALL; NOT on the arrivals beat): dark
--     returns after one knob read. Lit: the due jobs (public.fleet_jobs_due: not stopped, not waiting, the fleet DOCKED with nothing
--     queued and on no standing route), the longest-waiting first, at most fleet_jobs_per_tick of them, and no new one started once
--     fleet_jobs_budget_ms have passed (the first always runs: a Lisbon-sized world.best_sales takes ~2.7 s on prod). Each job in two
--     transactions of its own, as the lap-start job (0266) does:
--       (A) THE PLAN, outside the quay: a land job collects its party first (public.land_collect_for, her own rows); then
--           public.fleet_job_plan(fleet), a STABLE read, as her (the identity set for this transaction alone): the lines, or wait
--           (nothing to do: asked again fleet_jobs_wait_s later), or stop (the plan before failed, or no remembered course).
--       (B) THE OPEN, under the quay (public.hold_the_quay, in the gap after the second's beat): her fleet, job and house SKIP LOCKED, due and
--           her fleet's version re-checked, then cmd.issue_lines (the one plan door: every line parsed, the reach gate, all queued or
--           none, cmd.advance), as her. Committed: runs + 1 and `last`. Refused: the job stops with the server's code (E_STALE: tried
--           again next tick).
--     A plan whose lines then fail when they run (cmd.release_failed) stops the job at its next turn with that order's code. A stopped job
--     waits for her: cmd.set_fleet_job again starts it. Each run writes one receipt into the ring public.fleet_job_runs (lit only).
--   THE READ world.away_report() (STABLE, registered): dark {"on": false}; lit, signed out or a merchant {"on": true, "company": false};
--     lit, her company: public.away_report_for(her) = {jobs: [{fleet, fleet_name, kind, params, state (working | waiting | stopped),
--     fleet_state (public.fleet_state), runs, earned, last, paused, since, seen_at, next_at}], since, runs, earned}: what each job did
--     since she last read the report (seen_at): the runs it started, the coin her fleet's ledger rows came to (FOUNDING and probes out,
--     as world.report), and its last act or why it stopped.
-- ONE AUTHORITY EACH: the job, public.fleet_jobs; its course, public.fleet_job_course; its lines, public.fleet_job_plan; whether it is
--   due, public.fleet_jobs_due; the one writer of a run, public.fleet_job_open (and public.fleet_job_note for a wait or a stop); the
--   doors, cmd.*; the report, public.away_report_for. Every act is an existing door's: world.best_sales, world.board_passages,
--   cmd.issue_lines (BUY, SAIL, SELL, TAKE, STORE), public.land_collect_for.
-- NOT CHANGED: any command, any read, world.best_sales, the beat, the lap-start job; nothing for anyone while dark.
-- ROWS. Dark: none (the job reads one knob every 2 minutes and returns). Lit: one fleet_jobs row a fleet given a job; a run touches at most
--   fleet_jobs_per_tick (4) fleets: each started job writes its orders (3-6 lines) and what they do as they run (the BUY, the departure),
--   its job row, and one receipt row a run: under ~60 rows a run, ~30 rows a minute at the most, nothing while no job is due.
-- COST. Dark: one knob read a run. Lit, per started job: one world.best_sales (a `best` job only; prod 2026-11-23: 2,735 ms at Lisbon,
--   cut by its own 2.5 s budget) + one world.board_passages (~0.08 s) + a few known-legs reads (ms) + cmd.issue_lines (~0.1-0.3 s, under
--   the quay). The budget (1,500 ms) starts no second job after a Lisbon-sized one: a run stays under ~1.5 s + 2.7 s + 0.3 s + the gap
--   wait (at most 1.5 s), every 2 minutes, in its own session, never on the arrivals beat.
--   -- budget: one cron job every 2 minutes (byeharu-voyage:fleet-jobs); dark 0 rows a run; lit at most fleet_jobs_per_tick (4) jobs a run, under 60 rows a run
--   -- retention: public.fleet_jobs is none, bounded by one row a fleet (its key, deleted with the fleet); public.fleet_job_runs is none,
--      bounded by a ring of 720 slots (one a 2-minute run of a day)
-- LOCKS: CREATE TABLE x2 (new), CREATE FUNCTION x11 + one procedure, CREATE OR REPLACE x1 by a hunk (public.client_rpc_entry_points),
--   five knobs, one cron job (where pg_cron is). TIME: a few seconds. BUDGET: statement_timeout 60 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, fleet_jobs_enabled false (the tick returns at once, the doors refuse, the read is {"on": false};
--   orders a job already queued run out as any orders do). Full: a new migration unscheduling byeharu-voyage:fleet-jobs, reversing the
--   one hunk (OLD text below verbatim), dropping the functions, the procedure and the two tables, deleting the knobs.
-- SELF-ASSERT: the hunk once and reversing; no other function moved; the hunked body's grants, volatility, definer, search path, owner
--   unmoved; the knobs; the reads STABLE; the four doors registered for authenticated alone; every core server-only; the tables no
--   client's. THE PROBE (rolled back; deterministic: world.best_sales is never asked: no `best` job is due when the tick runs; one
--   transaction, one now(); the scene starts at 00:00 UTC of the day it runs (not the session's zone), so it never straddles midnight): dark the doors refuse, the
--   read is {"on": false} and the tick writes nothing; lit a fixed job is set (and the wrong ones refused), the tick with
--   fleet_jobs_per_tick 1 starts exactly one of two due jobs and the next tick the other: the fixed job's lines are BUY ALL / SAIL with
--   the world's course / SELL ALL and she departs; the land job's TAKE / SAIL / STORE carry the Land's good to the yard; the report
--   counts each job's run and its coin as her ledger has it; seen starts the tallies again; a job with no remembered course stops
--   (E_NO_COURSE) and is not due again; clear removes it. Proof 184 plays a best run, a whole fixed lap and a failed plan, and the cost.
-- VERSION: 0481 = 0480 + 1 (prod head 0480; this file's hunk is anchored on 0480's own line).
-- news: none (dark: nothing changes for a player until the owner lights fleet_jobs_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.client_rpc_entry_points()'];
  c_new    constant text[] := array['public.fleet_jobs_on()', 'public.fleet_job_course(uuid,uuid,uuid)', 'public.fleet_job_sails(uuid,uuid,text[])',
                                    'public.fleet_job_plan(uuid)', 'public.fleet_jobs_due()', 'public.fleet_job_note(uuid,jsonb)',
                                    'public.fleet_job_open(uuid,jsonb)', 'public.tick_fleet_jobs(boolean)', 'public.fleet_job_set_for(uuid,uuid,text,jsonb)',
                                    'public.away_report_for(uuid)', 'cmd.set_fleet_job(uuid,text,jsonb)', 'cmd.clear_fleet_job(uuid)',
                                    'cmd.fleet_jobs_seen()', 'world.away_report()'];
  c_doors  constant text[] := array['cmd.set_fleet_job(uuid,text,jsonb)', 'cmd.clear_fleet_job(uuid)', 'cmd.fleet_jobs_seen()', 'world.away_report()'];
  c_ua     constant uuid := '00000000-0481-4000-8000-0000000000a1';
  c_ub     constant uuid := '00000000-0481-4000-8000-0000000000b1';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_note      text := '';
  v_lived     boolean := false;
  v_day       timestamptz := date_trunc('day', now() at time zone 'utc') at time zone 'utc';   -- 00:00 UTC of today: the scene never straddles a UTC midnight
  v_a         uuid;
  v_b         uuid;
  v_fa        uuid;
  v_fb        uuid;
  v_lis       uuid;
  v_good      uuid;
  v_gcode     text;
  v_lgood     uuid;
  v_lcode     text;
  v_sell      text;
  v_far       text;
  v_yard      text;
  v_r         jsonb;
  v_j         jsonb;
  v_rep       jsonb;
  v_first     uuid;
  v_texts     text;
  v_runs_before bigint;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'fleet_jobs_enabled') or to_regclass('public.fleet_jobs') is not null then
    raise exception '0481 refuses: it has been applied once';
  end if;
  if to_regprocedure('world.hq_board()') is null or to_regprocedure('world.best_sales(uuid,uuid)') is null
     or to_regprocedure('world.board_passages(uuid,uuid,uuid,numeric)') is null or to_regprocedure('public.npc_known_legs(uuid)') is null
     or to_regprocedure('public.npc_coast_legs(uuid)') is null or to_regprocedure('public.land_collect_for(uuid,timestamptz)') is null
     or to_regprocedure('cmd.issue_lines(uuid,jsonb,integer)') is null or to_regprocedure('public.hold_the_quay()') is null
     or to_regprocedure('public.fleet_state(uuid)') is null or to_regprocedure('cmd.assume_identity(uuid)') is null then
    raise exception '0481 refuses: 0480, 0455, 0448, 0400, 0266, 0175 or 0120 is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('fleet_jobs_enabled', 'false'::jsonb,
     '0481: THE SWITCH (the owner''s). true: a fleet given a standing job in HQ (repeat the best run, a fixed route, carry the Land''s output to the yard) goes on with it whenever she lies idle in port (public.tick_fleet_jobs, every 2 minutes), and world.away_report() says what each job did. false: the doors refuse E_NOT_IN_USE, the read is {"on": false} and the tick returns at once.'),
    ('fleet_jobs_per_tick', to_jsonb(4), '0481: the most jobs one run of public.tick_fleet_jobs starts (the longest-waiting first).'),
    ('fleet_jobs_budget_ms', to_jsonb(1500), '0481: no new job is planned once a run of public.tick_fleet_jobs has taken this many milliseconds (the first always is; the rest wait for the next run).'),
    ('fleet_jobs_runs', to_jsonb(12), '0481: the most paying sales (by coin an hour) a `best` job tries, in order, for the first whose every leg the world remembers a course for (a course lookup is a few ms; world.best_sales is asked once).'),
    ('fleet_jobs_wait_s', to_jsonb(900), '0481: a job with nothing to do (no paying sale with a remembered course, nothing of the Land''s to carry) is asked again this many seconds later.');

  -- ── 3. THE TABLES ──
  -- retention: none, bounded by one row a fleet (public.fleet_jobs' key is the fleet; deleted with her)
  create table public.fleet_jobs (
    fleet_id      uuid primary key references public.fleets(id) on delete cascade,
    player_id     uuid not null references public.players(id) on delete cascade,
    kind          text not null check (kind in ('best', 'fixed', 'land')),
    params        jsonb not null default '{}'::jsonb,
    since         timestamptz not null,
    seen_at       timestamptz not null,
    next_at       timestamptz,
    paused_reason text,
    runs          integer not null default 0 check (runs >= 0),
    last          jsonb,
    last_plan     uuid
  );
  create index fleet_jobs_player on public.fleet_jobs (player_id);
  alter table public.fleet_jobs enable row level security;
  revoke all on table public.fleet_jobs from public, anon, authenticated;
  comment on table public.fleet_jobs is
    '0481: a fleet''s standing job (best | fixed | land), one a fleet. Written by cmd.set_fleet_job / cmd.clear_fleet_job / cmd.fleet_jobs_seen and the tick''s two writers (public.fleet_job_open, public.fleet_job_note). Server only.';

  -- retention: none, bounded by a ring of 720 slots (public.fleet_job_runs: one slot a 2-minute run of a day, overwritten)
  create table public.fleet_job_runs (
    slot    integer primary key check (slot >= 0 and slot < 720),
    at      timestamptz not null,
    ms      numeric not null,
    receipt jsonb not null
  );
  alter table public.fleet_job_runs enable row level security;
  revoke all on table public.fleet_job_runs from public, anon, authenticated;
  comment on table public.fleet_job_runs is
    '0481: one receipt a run of public.tick_fleet_jobs (lit only), a ring of 720 slots by the run''s 2-minute slot of the day: what it started, waited, stopped, and each job''s plan and open times.';

  -- ── 4. THE RULES ──
  execute $f$
create function public.fleet_jobs_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0481: THE SWITCH, read once: world_config fleet_jobs_enabled.
  select public.wc('fleet_jobs_enabled') = 'true'::jsonb
$body$
  $f$;

  execute $f$
create function public.fleet_job_course(p_fleet uuid, p_from uuid, p_to uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0481: THE COURSE A JOB SAILS from one harbour to another, one the world has already sailed and cmd.do_sail verified: a merchant lane,
  -- either way (public.npc_known_legs), a coast course (public.npc_coast_courses), or the newest voyage her company sailed between the two,
  -- either way, ended or under way (voyage.course_of over its stored segments: the course her chart plotted, to the point; each read by
  -- its fleet through the two partial indexes, ended and sailing). Null when none: the server plots no course of its own. cmd.do_sail
  -- judges it again at every departure. So the trip she has just sent can be her job at once.
  select coalesce(
    (select k.course from public.npc_known_legs(p_from) k where k.to_port = p_to),
    (select c.course from public.npc_coast_legs(p_from) c where c.to_port = p_to),
    (select case when v.origin_port_id = p_from then voyage.course_of(v.path)
                 else (select jsonb_agg(t.x order by t.i desc) from jsonb_array_elements(voyage.course_of(v.path)) with ordinality t(x, i)) end
       from (select x.origin_port_id, x.dest_port_id, x.path, x.eta
               from public.fleets mine join public.voyages x on x.fleet_id = mine.id and x.status <> 'SAILING'
              where mine.player_id = (select f.player_id from public.fleets f where f.id = p_fleet)
             union all
             select x.origin_port_id, x.dest_port_id, x.path, x.eta
               from public.fleets mine join public.voyages x on x.fleet_id = mine.id and x.status = 'SAILING'
              where mine.player_id = (select f.player_id from public.fleets f where f.id = p_fleet)) v
      where ((v.origin_port_id = p_from and v.dest_port_id = p_to) or (v.origin_port_id = p_to and v.dest_port_id = p_from))
        and jsonb_typeof(v.path) = 'array' and jsonb_array_length(v.path) > 0
      order by (v.origin_port_id = p_from) desc, v.eta desc
      limit 1))
$body$
  $f$;

  execute $f$
create function public.fleet_job_sails(p_fleet uuid, p_from uuid, p_codes text[])
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0481: THE SAIL LINES of a job from p_from through each harbour of p_codes in turn (a harbour she already lies at is passed), each with
-- the world's course (public.fleet_job_course). {lines: [{text, path}]}, or {missing: <code>} for the first harbour no remembered course
-- reaches (or no such harbour).
declare
  v_at   uuid := p_from;
  v_to   uuid;
  v_c    jsonb;
  v_out  jsonb := '[]'::jsonb;
  x      text;
begin
  foreach x in array coalesce(p_codes, '{}'::text[]) loop
    v_to := (select p.id from public.ports p where p.code = x and p.kind = 'HARBOUR');
    if v_to is null then
      return jsonb_build_object('missing', x);
    end if;
    continue when v_to = v_at;
    v_c := public.fleet_job_course(p_fleet, v_at, v_to);
    if v_c is null then
      return jsonb_build_object('missing', x);
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('text', 'SAIL ' || x, 'path', v_c));
    v_at := v_to;
  end loop;
  return jsonb_build_object('lines', v_out);
end
$body$
  $f$;

  execute $f$
create function public.fleet_job_plan(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0481: WHAT HER JOB DOES NOW (a read; the tick's plan step). {lines, note, version}: the lines cmd.issue_lines is sent; or {wait: why}
-- (busy, gone, nothing, unpriced, identity); or {pause: code, sentence} (the plan before failed when it ran, no remembered course, the
-- Land shut). A `best` job prices her sales with world.best_sales, which reads the CALLER: asked for anyone else it waits (identity).
-- The kinds: 0481's header.
declare
  j       public.fleet_jobs%rowtype;
  f       public.fleets%rowtype;
  lp      public.land_parties%rowtype;
  v_at    text;
  v_fail  record;
  v_s     jsonb;
  v_lines jsonb;
  v_g     text;
  v_buy   text;
  v_sell  text;
  v_st    text[];
  v_bs    jsonb;
  v_pass  jsonb;
  v_stops jsonb;
  s       record;
  v_land  text;
  v_to    text;
  v_qty   numeric;
begin
  select * into j from public.fleet_jobs x where x.fleet_id = p_fleet;
  select * into f from public.fleets x where x.id = p_fleet;
  if j.fleet_id is null or f.id is null then
    return jsonb_build_object('wait', 'gone');
  end if;
  v_at := (select p.code from public.ports p where p.id = f.port_id and p.kind = 'HARBOUR');
  if f.status <> 'DOCKED' or v_at is null
     or exists (select 1 from public.orders o where o.fleet_id = p_fleet and o.status in ('pending', 'active')) then
    return jsonb_build_object('wait', 'busy');
  end if;
  -- the plan before failed when it ran (cmd.release_failed cancelled the rest): the job stops on that order's own words
  if j.last_plan is not null then
    select o.error_code, o.error_message into v_fail
      from public.orders o where o.fleet_id = p_fleet and o.plan_id = j.last_plan and o.status = 'failed' order by o.seq limit 1;
    if found then
      return jsonb_build_object('pause', coalesce(v_fail.error_code, 'E_REFUSED'), 'sentence', v_fail.error_message);
    end if;
  end if;

  if j.kind = 'fixed' then
    v_g := j.params->>'good'; v_buy := j.params->>'buy'; v_sell := j.params->>'sell';
    v_st := array(select jsonb_array_elements_text(coalesce(j.params->'stops', '[]'::jsonb)));
    if v_at = v_buy then
      v_s := public.fleet_job_sails(f.id, f.port_id, v_st || v_sell);
      v_lines := jsonb_build_array(jsonb_build_object('text', format('BUY %s ALL', v_g))) || coalesce(v_s->'lines', '[]'::jsonb)
                 || jsonb_build_array(jsonb_build_object('text', format('SELL %s ALL', v_g)));
      v_to := v_sell;
    else
      v_s := public.fleet_job_sails(f.id, f.port_id, case when v_at = v_sell then array(select u.c from unnest(v_st) with ordinality u(c, i) order by u.i desc) else '{}'::text[] end || v_buy);
      v_lines := case when v_at = v_sell and public.fleet_cargo_qty(p_fleet, v_g) >= 1
                      then jsonb_build_array(jsonb_build_object('text', format('SELL %s ALL', v_g))) else '[]'::jsonb end
                 || coalesce(v_s->'lines', '[]'::jsonb);
      v_to := v_buy;
    end if;
    if v_s ? 'missing' then
      return jsonb_build_object('pause', 'E_NO_COURSE', 'sentence', format('no course the world remembers reaches %s', v_s->>'missing'));
    end if;
    return jsonb_build_object('lines', v_lines, 'version', f.version, 'note', jsonb_build_object('kind', 'fixed', 'good', v_g, 'from', v_at, 'to', v_to));

  elsif j.kind = 'land' then
    if not public.land_on() then
      return jsonb_build_object('pause', 'E_NOT_IN_USE', 'sentence', 'the land is not open');
    end if;
    select * into lp from public.land_parties x where x.player_id = j.player_id and x.ord = 1;
    v_land := (select p.code from public.ports p where p.id = lp.port_id);
    v_to := j.params->>'to';
    if v_land is null then
      return jsonb_build_object('wait', 'nothing');
    end if;
    if v_at = v_land then
      v_g := coalesce(j.params->>'good', (select g.code from public.goods g where g.id = (lp.terms->>'good')::uuid),
                      (select g.code from public.goods g where g.id = lp.waiting_good));
      v_qty := (select ps.qty from public.player_storage ps join public.goods g on g.id = ps.good_id
                 where ps.player_id = j.player_id and ps.port_id = lp.port_id and g.code = v_g);
      if v_g is null or coalesce(v_qty, 0) < 1 then
        return jsonb_build_object('wait', 'nothing');
      end if;
      v_s := public.fleet_job_sails(f.id, f.port_id, array[v_to]);
      v_lines := jsonb_build_array(jsonb_build_object('text', format('TAKE %s ALL', v_g))) || coalesce(v_s->'lines', '[]'::jsonb)
                 || jsonb_build_array(jsonb_build_object('text', format('STORE %s ALL', v_g)));
    else
      v_s := public.fleet_job_sails(f.id, f.port_id, array[v_land]);
      v_lines := coalesce(v_s->'lines', '[]'::jsonb);
      v_to := v_land;
    end if;
    if v_s ? 'missing' then
      return jsonb_build_object('pause', 'E_NO_COURSE', 'sentence', format('no course the world remembers reaches %s', v_s->>'missing'));
    end if;
    return jsonb_build_object('lines', v_lines, 'version', f.version,
                              'note', jsonb_build_object('kind', 'land', 'good', v_g, 'units', v_qty, 'from', v_at, 'to', v_to));

  else
    -- best: her best paying sales from where she lies, by coin an hour; the first whose every leg the world remembers
    if public.current_player_id() is distinct from j.player_id then
      return jsonb_build_object('wait', 'identity');
    end if;
    begin
      v_bs := world.best_sales(f.id, f.port_id);
    exception when others then
      return jsonb_build_object('wait', 'unpriced');
    end;
    v_pass := world.board_passages(j.player_id, f.id, f.port_id, (select sr.cap_nm from public.supply_reach(f.id) sr));
    select coalesce(jsonb_object_agg(p.code, coalesce(e->'stops', '[]'::jsonb)), '{}'::jsonb) into v_stops
      from jsonb_array_elements(coalesce(v_pass, '[]'::jsonb)) e join public.ports p on p.id = (e->>'port_id')::uuid;
    for s in
      select g.e, (g.e->>'profit')::numeric as profit, greatest(coalesce((g.e->>'seconds')::numeric, (g.e->>'days')::numeric * 86400), 1) as secs
        from jsonb_array_elements(coalesce(v_bs->'goods', '[]'::jsonb)) g(e)
       where (g.e->>'pays')::boolean and g.e->>'port' is not null and jsonb_typeof(g.e->'profit') = 'number' and (g.e->>'profit')::numeric > 0
         and g.e->'near' is distinct from 'false'::jsonb
         and (jsonb_typeof(g.e->'seconds') = 'number' or jsonb_typeof(g.e->'days') = 'number')
       order by (g.e->>'profit')::numeric / greatest(coalesce((g.e->>'seconds')::numeric, (g.e->>'days')::numeric * 86400), 1) desc, g.e->>'good'
       limit greatest(0, coalesce(public.wc_int('fleet_jobs_runs'), 12))
    loop
      v_s := public.fleet_job_sails(f.id, f.port_id, array(select jsonb_array_elements_text(coalesce(v_stops->(s.e->>'port'), '[]'::jsonb))) || (s.e->>'port'));
      continue when v_s ? 'missing';
      v_lines := case when s.e->>'basis' = 'on_board' then '[]'::jsonb
                      else jsonb_build_array(jsonb_build_object('text', format('BUY %s %s', s.e->>'good', trim_scale(round((s.e->>'units')::numeric, 2))))) end
                 || (v_s->'lines') || jsonb_build_array(jsonb_build_object('text', format('SELL %s ALL', s.e->>'good')));
      return jsonb_build_object('lines', v_lines, 'version', f.version,
                                'note', jsonb_build_object('kind', 'best', 'good', s.e->>'good', 'from', v_at, 'to', s.e->>'port',
                                                           'units', (s.e->>'units')::numeric, 'profit', round(s.profit), 'seconds', round(s.secs)));
    end loop;
    return jsonb_build_object('wait', 'nothing');
  end if;
end
$body$
  $f$;

  execute $f$
create function public.fleet_jobs_due()
returns table (fleet_id uuid, player_id uuid, auth_uid uuid, kind text, turn timestamptz)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0481: THE JOBS DUE NOW (the switch lit): not stopped, not waiting, her fleet DOCKED with nothing queued and on no standing route (the
  -- route is her job). turn: when the job last acted (or was set): the longest-waiting first.
  select j.fleet_id, j.player_id, pl.auth_uid, j.kind, coalesce((j.last->>'at')::timestamptz, j.since)
    from public.fleet_jobs j
    join public.fleets f on f.id = j.fleet_id
    join public.players pl on pl.id = j.player_id
   where public.fleet_jobs_on()
     and j.paused_reason is null and (j.next_at is null or j.next_at <= now())
     and f.status = 'DOCKED' and f.port_id is not null
     and not exists (select 1 from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active'))
     and not exists (select 1 from public.standing_routes r where r.fleet_id = f.id)
$body$
  $f$;

  execute $f$
create function public.fleet_job_note(p_fleet uuid, p_plan jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0481: A PLAN THAT STARTS NOTHING, written on her job: a stop (paused_reason, `last` says why) or a wait for nothing to do (asked again
-- fleet_jobs_wait_s later). busy / gone write nothing: the job is asked when it is due again.
begin
  if p_plan ? 'pause' then
    update public.fleet_jobs
       set paused_reason = p_plan->>'pause',
           last = jsonb_build_object('at', now(), 'ok', false, 'code', p_plan->>'pause', 'sentence', p_plan->>'sentence')
     where fleet_id = p_fleet;
  elsif p_plan->>'wait' in ('nothing', 'unpriced', 'identity') then
    update public.fleet_jobs
       set next_at = now() + make_interval(secs => greatest(60, coalesce(public.wc_num('fleet_jobs_wait_s'), 900))),
           last = jsonb_build_object('at', now(), 'wait', p_plan->>'wait')
     where fleet_id = p_fleet;
  end if;
end
$body$
  $f$;

  execute $f$
create function public.fleet_job_open(p_fleet uuid, p_plan jsonb)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0481: THE ONE WRITER OF A JOB'S RUN (the tick's open step), UNDER THE QUAY: the quay first, then her fleet and job, then her house (SKIP
-- LOCKED: never waits), due and her fleet's version re-checked, then her plan's lines through cmd.issue_lines AS HER (the identity set
-- for this transaction and put back after). 1 = started; 2 = refused (the job stops on the server's code); 0 = not due any more, or her
-- fleet moved on (E_STALE): asked again next run; -1 = busy.
declare
  d        record;
  v_sub    text := current_setting('request.jwt.claim.sub', true);
  v_claims text := current_setting('request.jwt.claims', true);
  v_r      jsonb;
begin
  perform public.hold_the_quay();
  perform 1 from public.fleets f join public.fleet_jobs j on j.fleet_id = f.id where f.id = p_fleet for update of f, j skip locked;
  if not found then return -1; end if;
  select x.* into d from public.fleet_jobs_due() x where x.fleet_id = p_fleet;
  if d.fleet_id is null or (select f.version from public.fleets f where f.id = p_fleet) is distinct from (p_plan->>'version')::int then
    return 0;
  end if;
  perform 1 from public.players p where p.id = d.player_id for no key update skip locked;
  if not found then return -1; end if;
  perform cmd.assume_identity(d.auth_uid);
  begin
    v_r := cmd.issue_lines(p_fleet, p_plan->'lines', (p_plan->>'version')::int);
  exception when others then
    v_r := jsonb_build_object('ok', false, 'error_code', 'E_REFUSED', 'error_message', sqlerrm);
  end;
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  if coalesce((v_r->>'ok')::boolean, false) then
    update public.fleet_jobs j
       set runs = j.runs + 1, next_at = null,
           last = coalesce(p_plan->'note', '{}'::jsonb) || jsonb_build_object('at', now(), 'ok', true),
           last_plan = (v_r #>> '{orders,0,id}')::uuid,
           params = case when j.kind = 'land' and p_plan #>> '{note,good}' is not null
                         then j.params || jsonb_build_object('good', p_plan #>> '{note,good}') else j.params end
     where j.fleet_id = p_fleet;
    return 1;
  end if;
  if v_r->>'error_code' = 'E_STALE' then
    return 0;
  end if;
  update public.fleet_jobs
     set paused_reason = coalesce(v_r->>'error_code', 'E_REFUSED'),
         last = coalesce(p_plan->'note', '{}'::jsonb) || jsonb_build_object('at', now(), 'ok', false, 'code', coalesce(v_r->>'error_code', 'E_REFUSED'),
                                                                            'sentence', v_r->>'error_message')
   where fleet_id = p_fleet;
  return 2;
end
$body$
  $f$;

  execute $f$
create procedure public.tick_fleet_jobs(p_commit boolean default true)
language plpgsql
as $body$
-- 0481: THE FLEET-JOBS JOB (pg_cron byeharu-voyage:fleet-jobs, every 2 minutes, CALL; never on the arrivals beat). Dark: one knob read,
-- nothing written. Lit: the due jobs (public.fleet_jobs_due), the longest-waiting first, at most fleet_jobs_per_tick, no new plan once
-- fleet_jobs_budget_ms have passed (the first always runs). Each in two transactions: (A) THE PLAN, outside the quay (a land job's
-- party collected first; public.fleet_job_plan as her), and a wait or a stop written (public.fleet_job_note); (B) THE OPEN, under the
-- quay in the gap after the second's beat (public.fleet_job_open). One receipt into the ring public.fleet_job_runs. p_commit false: one
-- pass in the caller's transaction, no commits and no waits (the self-assert, a proof). No SECURITY DEFINER, no SET: a procedure that
-- commits may carry neither; it runs as the job's owner.
declare
  c_wait   constant interval := interval '1500 milliseconds';   -- the longest the open step waits for a gap after the beat
  c_margin constant numeric := 60;                               -- ms left before the next beat
  v_t0     timestamptz := clock_timestamp();
  v_now0   timestamptz := now();
  v_max    int;
  v_budget numeric;
  v_ids    uuid[];
  v_pls    uuid[];
  v_auths  uuid[];
  v_kinds  text[];
  v_plan   jsonb;
  v_b      int;
  v_sub    text;
  v_claims text;
  v_t      timestamptz;
  v_tw     timestamptz;
  v_pm     numeric;
  v_om     numeric;
  v_est    numeric := 250;
  v_started int := 0;
  v_waited  int := 0;
  v_stopped int := 0;
  v_busy    int := 0;
  v_failed  int := 0;
  v_left    int := 0;
  v_note    text;
  v_steps   jsonb := '[]'::jsonb;
begin
  if not public.fleet_jobs_on() then
    return;
  end if;
  v_max := greatest(0, coalesce(public.wc_int('fleet_jobs_per_tick'), 4));
  v_budget := greatest(0, coalesce(public.wc_num('fleet_jobs_budget_ms'), 1500));
  select array_agg(d.fleet_id order by d.turn, d.fleet_id), array_agg(d.player_id order by d.turn, d.fleet_id),
         array_agg(d.auth_uid order by d.turn, d.fleet_id), array_agg(d.kind order by d.turn, d.fleet_id)
    into v_ids, v_pls, v_auths, v_kinds
    from (select x.* from public.fleet_jobs_due() x order by x.turn, x.fleet_id limit v_max) d;

  for i in 1 .. coalesce(cardinality(v_ids), 0) loop
    if i > 1 and extract(epoch from clock_timestamp() - v_t0) * 1000 > v_budget then
      v_left := cardinality(v_ids) - i + 1;
      exit;
    end if;
    -- (A) THE PLAN, outside the quay, as her
    v_t := clock_timestamp();
    if v_kinds[i] = 'land' and public.land_on() then
      begin
        perform public.land_collect_for(v_pls[i], now());
      exception when others then
        v_note := coalesce(v_note, 'collect ' || v_ids[i] || ': ' || sqlerrm);
      end;
    end if;
    v_sub := current_setting('request.jwt.claim.sub', true);
    v_claims := current_setting('request.jwt.claims', true);
    perform cmd.assume_identity(v_auths[i]);
    begin
      v_plan := public.fleet_job_plan(v_ids[i]);
    exception when others then
      v_plan := jsonb_build_object('wait', 'fault');
      v_note := coalesce(v_note, 'plan ' || v_ids[i] || ': ' || sqlerrm);
    end;
    perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    if not (v_plan ? 'lines') then
      perform public.fleet_job_note(v_ids[i], v_plan);
      if v_plan ? 'pause' then v_stopped := v_stopped + 1; else v_waited := v_waited + 1; end if;
    end if;
    if p_commit then commit; end if;
    v_pm := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 1);
    v_om := null;
    v_b := null;

    -- (B) THE OPEN, under the quay, in the gap after this second's beat (0266's rule)
    if v_plan ? 'lines' then
      if p_commit then
        v_tw := clock_timestamp();
        loop
          exit when clock_timestamp() - v_tw >= c_wait;
          exit when exists (select 1 from public.arrivals_beats b
                             where b.slot = (floor(extract(epoch from clock_timestamp()))::bigint % 3600)::int
                               and b.at >= date_trunc('second', clock_timestamp()))
                    and mod((extract(epoch from clock_timestamp()) * 1000)::numeric, 1000) + v_est + c_margin <= 1000;
          perform pg_sleep(0.02);
        end loop;
        commit;
      end if;
      v_t := clock_timestamp();
      begin
        v_b := public.fleet_job_open(v_ids[i], v_plan);
      exception when others then
        v_b := -2;
        v_note := coalesce(v_note, 'open ' || v_ids[i] || ': ' || sqlerrm);
      end;
      if p_commit then commit; end if;
      v_om := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 1);
      v_est := greatest(80, 0.7 * v_est + 0.3 * v_om);
      if v_b = 1 then v_started := v_started + 1;
      elsif v_b = 2 then v_stopped := v_stopped + 1;
      elsif v_b = -2 then v_failed := v_failed + 1;
      else v_busy := v_busy + 1;
      end if;
    end if;
    v_steps := v_steps || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
                 'fleet', v_ids[i], 'kind', v_kinds[i], 'plan_ms', v_pm, 'open_ms', v_om, 'open', v_b,
                 'wait', v_plan->>'wait', 'pause', v_plan->>'pause')));
  end loop;

  insert into public.fleet_job_runs (slot, at, ms, receipt)
  values ((floor(extract(epoch from v_now0) / 120)::bigint % 720)::int, v_now0, round(extract(epoch from clock_timestamp() - v_t0)::numeric * 1000, 1),
          jsonb_build_object('started', v_started, 'waited', v_waited, 'stopped', v_stopped, 'busy', v_busy, 'failed', v_failed,
                             'left', v_left, 'note', v_note, 'steps', v_steps))
  on conflict (slot) do update set at = excluded.at, ms = excluded.ms, receipt = excluded.receipt;
  if p_commit then commit; end if;
end
$body$
  $f$;

  execute $f$
create function public.fleet_job_set_for(p_player uuid, p_fleet uuid, p_kind text, p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0481: THE CORE OF cmd.set_fleet_job (server only). Every check first, then one upsert: the job starts afresh (no stop, no wait, no last
-- plan) and keeps her report's tallies (seen_at, runs). Refusals raise 'E_CODE: sentence' (the door makes the envelope).
declare
  f       public.fleets%rowtype;
  lp      public.land_parties%rowtype;
  v_p     jsonb;
  v_good  text;
  v_buy   uuid;
  v_sell  uuid;
  v_st    text[];
  v_s     jsonb;
  v_to    text;
  v_to_id uuid;
begin
  if not public.fleet_jobs_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'standing jobs are not open yet');
  end if;
  select * into f from public.fleets x where x.id = p_fleet;
  if f.id is null or f.player_id is distinct from p_player then
    perform cmd.refuse('E_NO_SUCH_FLEET', 'that fleet is not yours');
  end if;
  if exists (select 1 from public.standing_routes r where r.fleet_id = p_fleet) then
    perform cmd.refuse('E_ROUTE_TAKEN', format('%s runs a route; take her off it first', f.name));
  end if;
  p_params := coalesce(p_params, '{}'::jsonb);
  if jsonb_typeof(p_params) <> 'object' then
    perform cmd.refuse('E_BAD_ORDER', 'a job''s settings are a set of names');
  end if;

  if p_kind = 'best' then
    v_p := '{}'::jsonb;
  elsif p_kind = 'fixed' then
    v_good := (select g.code from public.goods g where g.code = p_params->>'good');
    v_buy := (select p.id from public.ports p where p.code = p_params->>'buy' and p.kind = 'HARBOUR');
    v_sell := (select p.id from public.ports p where p.code = p_params->>'sell' and p.kind = 'HARBOUR');
    if v_good is null or v_buy is null or v_sell is null or v_buy = v_sell then
      perform cmd.refuse('E_BAD_ORDER', 'a fixed route names a good and two harbours');
    end if;
    v_st := array(select jsonb_array_elements_text(case when jsonb_typeof(p_params->'stops') = 'array' then p_params->'stops' else '[]'::jsonb end));
    -- out (through the stops) and home (the stops reversed): every leg a course the world remembers
    v_s := public.fleet_job_sails(p_fleet, v_buy, v_st || (p_params->>'sell'));
    if not (v_s ? 'missing') then
      v_s := public.fleet_job_sails(p_fleet, v_sell, array(select u.c from unnest(v_st) with ordinality u(c, i) order by u.i desc) || (p_params->>'buy'));
    end if;
    if v_s ? 'missing' then
      perform cmd.refuse('E_NO_COURSE', format('no course the world remembers reaches %s', v_s->>'missing'));
    end if;
    v_p := jsonb_build_object('good', v_good, 'buy', p_params->>'buy', 'sell', p_params->>'sell', 'stops', to_jsonb(v_st));
  elsif p_kind = 'land' then
    if not public.land_on() then
      perform cmd.refuse('E_NOT_IN_USE', 'the land is not open yet');
    end if;
    v_to_id := public.land_party(p_player);   -- made at her first press, as every Land door does
    select * into lp from public.land_parties x where x.id = v_to_id;
    v_to := p_params->>'to';
    if v_to is null then
      -- the nearest harbour with a building yard and a warehouse that a remembered course joins to the party's harbour
      select p.code into v_to
        from public.npc_known_legs(lp.port_id) k join public.ports p on p.id = k.to_port
       where p.kind = 'HARBOUR'
         and exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'building_yard')
         and exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'warehouse')
       order by k.nm, p.code limit 1;
    end if;
    v_to_id := (select p.id from public.ports p where p.code = v_to and p.kind = 'HARBOUR');
    if v_to_id is null then
      perform cmd.refuse('E_NO_SUCH_PORT', 'no yard a remembered course reaches from the Land''s harbour');
    end if;
    if v_to_id = lp.port_id then
      perform cmd.refuse('E_SAME_DEST', 'the Land''s goods are there already');
    end if;
    if not exists (select 1 from public.port_buildings b where b.port_id = v_to_id and b.kind = 'warehouse') then
      perform cmd.refuse('E_NO_WAREHOUSE', format('%s keeps no warehouse', v_to));
    end if;
    if public.fleet_job_course(p_fleet, lp.port_id, v_to_id) is null then
      perform cmd.refuse('E_NO_COURSE', format('no course the world remembers reaches %s', v_to));
    end if;
    v_good := (select g.code from public.goods g where g.code = p_params->>'good');
    if p_params->>'good' is not null and v_good is null then
      perform cmd.refuse('E_NO_SUCH_GOOD', 'nothing is called that');
    end if;
    v_p := jsonb_build_object('to', v_to) || case when v_good is not null then jsonb_build_object('good', v_good) else '{}'::jsonb end;
  else
    perform cmd.refuse('E_BAD_ORDER', 'a job is best, fixed or land');
  end if;

  insert into public.fleet_jobs as j (fleet_id, player_id, kind, params, since, seen_at)
  values (p_fleet, p_player, p_kind, v_p, now(), now())
  on conflict (fleet_id) do update
    set kind = excluded.kind, params = excluded.params, since = excluded.since,
        next_at = null, paused_reason = null, last = null, last_plan = null;
  return jsonb_build_object('ok', true, 'fleet', p_fleet, 'kind', p_kind, 'params', v_p);
end
$body$
  $f$;

  execute $f$
create function public.away_report_for(p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0481: WHAT EACH JOB DID SINCE SHE LAST READ THIS (seen_at): the runs it started, the coin her fleet's ledger rows came to (FOUNDING and
  -- probes left out, as world.report; the (player_id, created_at) index), its last act or why it stopped; state: stopped (paused), working
  -- (at sea by public.fleet_state, or orders queued), else waiting. Her fleets by their founding.
  select jsonb_build_object(
           'jobs', coalesce(jsonb_agg(x.o order by x.created, x.fleet), '[]'::jsonb),
           'since', min(x.seen), 'runs', coalesce(sum(x.runs), 0), 'earned', coalesce(sum(x.earned), 0))
    from (select j.fleet_id as fleet, f.created_at as created, j.seen_at as seen, j.runs, e.earned,
                 jsonb_build_object('fleet', j.fleet_id, 'fleet_name', f.name, 'kind', j.kind, 'params', j.params,
                   'state', case when j.paused_reason is not null then 'stopped'
                                 when st.s = 'sea' or exists (select 1 from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active')) then 'working'
                                 else 'waiting' end,
                   'fleet_state', st.s, 'runs', j.runs, 'earned', e.earned, 'last', j.last, 'paused', j.paused_reason,
                   'since', j.since, 'seen_at', j.seen_at, 'next_at', j.next_at) as o
            from public.fleet_jobs j
            join public.fleets f on f.id = j.fleet_id
           cross join lateral (select public.fleet_state(f.id) as s) st
           cross join lateral (select coalesce(sum(l.ducats_delta), 0)::bigint as earned
                                 from public.ledger l
                                where l.player_id = p_player and l.created_at > j.seen_at and l.fleet_id = j.fleet_id
                                  and l.kind <> 'FOUNDING' and left(l.kind, 6) <> 'PROBE_') e
           where j.player_id = p_player) x
$body$
  $f$;

  execute $f$
create function cmd.set_fleet_job(p_fleet uuid, p_kind text, p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0481: GIVE HER FLEET A STANDING JOB (best | fixed | land; public.fleet_job_set_for). A refusal is the envelope.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null or coalesce((select p.is_npc from public.players p where p.id = v_player), true) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.fleet_job_set_for(v_player, p_fleet, p_kind, p_params);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$
  $f$;

  execute $f$
create function cmd.clear_fleet_job(p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0481: TAKE HER FLEET'S STANDING JOB AWAY (orders it already queued run out as any orders do). Dark E_NOT_IN_USE; not hers E_NO_SUCH_FLEET.
declare
  v_player uuid := public.current_player_id();
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  if not public.fleet_jobs_on() then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_IN_USE', 'error_message', 'Standing jobs are not open yet.', 'fixes', '[]'::jsonb);
  end if;
  if not exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = v_player) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_FLEET', 'error_message', 'That fleet is not yours.', 'fixes', '[]'::jsonb);
  end if;
  delete from public.fleet_jobs j where j.fleet_id = p_fleet and j.player_id = v_player;
  return jsonb_build_object('ok', true, 'fleet', p_fleet);
end
$body$
  $f$;

  execute $f$
create function cmd.fleet_jobs_seen()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0481: SHE HAS READ THE AWAY REPORT: each job's tallies start again from now (seen_at, runs). Dark E_NOT_IN_USE.
declare
  v_player uuid := public.current_player_id();
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  if not public.fleet_jobs_on() then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_IN_USE', 'error_message', 'Standing jobs are not open yet.', 'fixes', '[]'::jsonb);
  end if;
  update public.fleet_jobs j set seen_at = now(), runs = 0 where j.player_id = v_player;
  return jsonb_build_object('ok', true, 'seen_at', now());
end
$body$
  $f$;

  execute $f$
create function world.away_report()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0481: THE AWAY REPORT, the client's one read of her fleets' jobs. Dark (fleet_jobs_enabled false): {"on": false}. Lit, signed out or a
-- merchant: {"on": true, "company": false}. Lit, her company: public.away_report_for(her) with on and company true. Writes nothing.
declare
  v_me uuid := public.current_player_id();
begin
  if not public.fleet_jobs_on() then
    return jsonb_build_object('on', false);
  end if;
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return jsonb_build_object('on', true, 'company', false);
  end if;
  return jsonb_build_object('on', true, 'company', true) || public.away_report_for(v_me);
end
$body$
  $f$;

  -- grants: the four doors to authenticated alone; every core, the procedure and the tables server only (service_role too: the platform
  -- grants execute on a new function by default, 0459's first push)
  foreach v_def in array c_new loop
    if v_def = any (c_doors) then
      execute format('revoke all on function %s from public, anon', v_def::regprocedure);
      execute format('grant execute on function %s to authenticated', v_def::regprocedure);
    elsif v_def = 'public.tick_fleet_jobs(boolean)' then
      execute 'revoke all on procedure public.tick_fleet_jobs(boolean) from public, anon, authenticated, service_role';
    else
      execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
    end if;
  end loop;
  comment on function world.away_report() is
    '0481: the away report (dark {"on": false}): each of her fleets'' standing jobs, what it did since she last read it (runs, coin, its last act) and its state. A read. Client door.';

  -- ── 5. THE HUNK (it occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0481 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0481 values
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'hq_board',              ''),$h$,
$h$      ('world',       'hq_board',              ''),
      -- 0481: standing fleet jobs (dark: the doors E_NOT_IN_USE, the read {"on": false})
      ('cmd',         'set_fleet_job',         'uuid, text, jsonb'),
      ('cmd',         'clear_fleet_job',       'uuid'),
      ('cmd',         'fleet_jobs_seen',       ''),
      ('world',       'away_report',           ''),$h$);

  for v_h in select h.fn from hunks_0481 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0481 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0481 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0481 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0481 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0481 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the knobs, the doors ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0481 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0481 self-assert FAIL: the grants, volatility, definer, search path or owner of the hunked body moved';
  end if;
  if (select count(*) from pg_proc p
       where p.oid = any (array['public.fleet_jobs_on()', 'public.fleet_job_course(uuid,uuid,uuid)', 'public.fleet_job_sails(uuid,uuid,text[])',
                                'public.fleet_job_plan(uuid)', 'public.fleet_jobs_due()', 'public.away_report_for(uuid)', 'world.away_report()']::regprocedure[]::oid[])
         and p.provolatile = 's') <> 7 then
    raise exception '0481 self-assert FAIL: a read is not STABLE (the plan, the due list, the course and the report are reads)';
  end if;
  if public.wc('fleet_jobs_enabled') <> 'false'::jsonb or public.wc_int('fleet_jobs_per_tick') <> 4 or public.wc_int('fleet_jobs_budget_ms') <> 1500
     or public.wc_int('fleet_jobs_runs') <> 12 or public.wc_int('fleet_jobs_wait_s') <> 900 then
    raise exception '0481 self-assert FAIL: the knobs are not as written';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where (e.schema_name, e.function_name, e.arg_types) in (('cmd', 'set_fleet_job', 'uuid, text, jsonb'), ('cmd', 'clear_fleet_job', 'uuid'),
                                                              ('cmd', 'fleet_jobs_seen', ''), ('world', 'away_report', ''))
         and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) <> 4
     or exists (select 1 from unnest(c_new) u(q)
                 where u.q <> all (c_doors)
                   and (has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                        or has_function_privilege('service_role', u.q::regprocedure, 'execute')))
     or has_table_privilege('authenticated', 'public.fleet_jobs', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.fleet_jobs', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.fleet_job_runs', 'select,insert,update,delete')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.fleet_jobs'::regclass)
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.fleet_job_runs'::regclass)
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0481 self-assert FAIL: a door is not registered for authenticated alone, a core or the tick is reachable by a client, or a table is';
  end if;

  -- ── 7. THE PROBE, rolled back by a raised sentinel (world.best_sales is never asked: no `best` job is due when the tick runs) ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    v_a := public.new_house(c_ua, 'Casa da Lida 0481', 'PRT');
    v_b := public.new_house(c_ub, 'Casa da Terra 0481', 'PRT');
    select f.id into v_fa from public.fleets f where f.player_id = v_a;
    select f.id into v_fb from public.fleets f where f.player_id = v_b;
    update public.players p set ducats = 2000000 where p.id in (v_a, v_b);
    -- the good: the one Lisbon stocks most that it offers; the sale harbour: Lisbon's nearest remembered course; a far one with none
    select g.id, g.code into v_good, v_gcode
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_lis and public.port_offers(v_lis, g.id)
     order by pg.stock_target desc, g.code limit 1;
    select k.code into v_sell from public.npc_known_legs(v_lis) k join public.ports p on p.id = k.to_port where p.kind = 'HARBOUR' order by k.nm, k.code limit 1;
    select p.code into v_far from public.ports p
     where p.kind = 'HARBOUR' and p.id <> v_lis and public.fleet_job_course(v_fa, v_lis, p.id) is null order by p.code limit 1;
    if v_good is null or v_sell is null or v_far is null then
      raise exception '0481 self-assert FAIL: the world has no good at Lisbon, no remembered course from it, or none it lacks (% / % / %)', v_gcode, v_sell, v_far;
    end if;
    perform cmd.assume_identity(c_ua);

    -- (a) DARK: the doors refuse, the read is {"on": false}, the tick writes nothing
    if world.away_report() is distinct from '{"on": false}'::jsonb
       or cmd.set_fleet_job(v_fa, 'best', '{}'::jsonb)->>'error_code' is distinct from 'E_NOT_IN_USE'
       or cmd.clear_fleet_job(v_fa)->>'error_code' is distinct from 'E_NOT_IN_USE'
       or cmd.fleet_jobs_seen()->>'error_code' is distinct from 'E_NOT_IN_USE' then
      raise exception '0481 self-assert FAIL: dark, a door opened or the read is not {"on": false}';
    end if;
    call public.tick_fleet_jobs(false);
    if exists (select 1 from public.fleet_jobs) or exists (select 1 from public.fleet_job_runs) then
      raise exception '0481 self-assert FAIL: dark, the tick wrote something';
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'fleet_jobs_enabled';

    -- (b) THE DOORS, lit: the wrong ones refused, a fixed route set (her report: one job, waiting, nothing yet)
    if cmd.set_fleet_job(v_fb, 'best', '{}'::jsonb)->>'error_code' is distinct from 'E_NO_SUCH_FLEET'
       or cmd.set_fleet_job(v_fa, 'sail', '{}'::jsonb)->>'error_code' is distinct from 'E_BAD_ORDER'
       or cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_gcode, 'buy', 'LIS', 'sell', 'LIS'))->>'error_code' is distinct from 'E_BAD_ORDER'
       or cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_gcode, 'buy', 'LIS', 'sell', v_far))->>'error_code' is distinct from 'E_NO_COURSE'
       or exists (select 1 from public.fleet_jobs) then
      raise exception '0481 self-assert FAIL: lit, a wrong job was not refused by its own code, or was written';
    end if;
    v_r := cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_gcode, 'buy', 'LIS', 'sell', v_sell));
    v_rep := world.away_report();
    if (v_r->>'ok')::boolean is not true or (v_rep->>'company')::boolean is not true or jsonb_array_length(v_rep->'jobs') <> 1
       or v_rep #>> '{jobs,0,kind}' <> 'fixed' or v_rep #>> '{jobs,0,state}' <> 'waiting' or (v_rep #>> '{jobs,0,runs}')::int <> 0 then
      raise exception '0481 self-assert FAIL: lit, the fixed job was not set, or her report does not show it waiting: % / %', v_r, left(v_rep::text, 400);
    end if;

    -- (c) THE LAND JOB for house B: the Land lit, the party's harbour Lisbon (her home), 30 of the good in Lisbon's Storage, the yard by default
    perform cmd.assume_identity(c_ub);
    update public.world_config set value = 'true'::jsonb where key = 'land_enabled';
    select g.id, g.code into v_lgood, v_lcode from public.goods g where g.bulk > 0 order by g.bulk, g.code limit 1;
    v_r := cmd.set_fleet_job(v_fb, 'land', jsonb_build_object('good', v_lcode));
    v_yard := v_r #>> '{params,to}';
    if (v_r->>'ok')::boolean is not true or v_yard is null
       or not exists (select 1 from public.port_buildings b join public.ports p on p.id = b.port_id where p.code = v_yard and b.kind = 'building_yard') then
      raise exception '0481 self-assert FAIL: lit, the land job was not set to a yard: %', v_r;
    end if;
    if public.storage_cap(v_lis) > 0 then
      perform public.storage_put(v_b, v_lis, v_lgood, 30, 0);
    else
      raise exception '0481 self-assert FAIL: Lisbon keeps no warehouse: the Land''s goods have nowhere to wait';
    end if;
    perform cmd.assume_identity(c_ua);

    -- (d) THE BUDGET: two jobs due, fleet_jobs_per_tick 1: one run starts exactly one (the longest-waiting, then the fleet's id), the next the other
    update public.fleet_jobs set since = v_day where fleet_id = v_fa;
    update public.fleet_jobs set since = v_day + interval '1 second' where fleet_id = v_fb;
    update public.world_config set value = to_jsonb(1) where key = 'fleet_jobs_per_tick';
    call public.tick_fleet_jobs(false);
    if (select j.runs from public.fleet_jobs j where j.fleet_id = v_fa) <> 1 or (select j.runs from public.fleet_jobs j where j.fleet_id = v_fb) <> 0
       or (select count(*) from public.fleet_job_runs) <> 1 or (select (r.receipt->>'started')::int from public.fleet_job_runs r) <> 1 then
      raise exception '0481 self-assert FAIL: fleet_jobs_per_tick 1 did not start exactly the longest-waiting job: % / %',
        (select jsonb_agg(jsonb_build_object('kind', j.kind, 'runs', j.runs, 'last', j.last, 'paused', j.paused_reason)) from public.fleet_jobs j),
        (select r.receipt from public.fleet_job_runs r limit 1);
    end if;
    -- the fixed job's lines: BUY <good> ALL, SAIL <sell> with the world's course, SELL <good> ALL; she departs for the sale
    v_first := (select j.last_plan from public.fleet_jobs j where j.fleet_id = v_fa);
    select string_agg(o.raw_text, ' / ' order by o.seq) into v_texts from public.orders o where o.fleet_id = v_fa and o.plan_id = v_first;
    if v_texts is distinct from format('BUY %s ALL / SAIL %s / SELL %s ALL', v_gcode, v_sell, v_gcode)
       or exists (select 1 from public.orders o where o.plan_id = v_first and o.verb = 'SAIL' and jsonb_typeof(o.args->'path') <> 'array')
       or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING'
       or not exists (select 1 from public.voyages v where v.fleet_id = v_fa and v.status = 'SAILING'
                                                        and v.dest_port_id = (select p.id from public.ports p where p.code = v_sell)) then
      raise exception '0481 self-assert FAIL: the fixed job did not send BUY / SAIL (with a course) / SELL and sail for %: % (%)', v_sell, v_texts,
        (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fa);
    end if;
    call public.tick_fleet_jobs(false);
    v_first := (select j.last_plan from public.fleet_jobs j where j.fleet_id = v_fb);
    select string_agg(o.raw_text, ' / ' order by o.seq) into v_texts from public.orders o where o.fleet_id = v_fb and o.plan_id = v_first;
    if (select j.runs from public.fleet_jobs j where j.fleet_id = v_fb) <> 1
       or v_texts is distinct from format('TAKE %s ALL / SAIL %s / STORE %s ALL', v_lcode, v_yard, v_lcode)
       or public.fleet_cargo_qty(v_fb, v_lcode) <> 30
       or coalesce((select ps.qty from public.player_storage ps where ps.player_id = v_b and ps.port_id = v_lis and ps.good_id = v_lgood), 0) <> 0
       or (select f.status from public.fleets f where f.id = v_fb) <> 'SAILING' then
      raise exception '0481 self-assert FAIL: the land job did not TAKE the Land''s 30 %, SAIL for % and queue STORE: % (%)', v_lcode, v_yard, v_texts,
        (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fb);
    end if;

    -- (e) HER REPORT: one run, working, the coin her fleet's ledger rows came to since the scene's start; seen starts it again
    update public.fleet_jobs set seen_at = v_day where fleet_id = v_fa;
    v_rep := world.away_report();
    if (v_rep #>> '{jobs,0,runs}')::int <> 1 or v_rep #>> '{jobs,0,state}' <> 'working' or v_rep #>> '{jobs,0,last,to}' <> v_sell
       or (v_rep #>> '{jobs,0,earned}')::bigint is distinct from
          (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = v_a and l.fleet_id = v_fa and l.created_at > v_day
             and l.kind <> 'FOUNDING' and left(l.kind, 6) <> 'PROBE_')
       or (v_rep #>> '{jobs,0,earned}')::bigint >= 0 then
      raise exception '0481 self-assert FAIL: her report does not count the run and the coin (the buy) her ledger has: %', left(v_rep::text, 500);
    end if;
    v_r := cmd.fleet_jobs_seen();
    v_rep := world.away_report();
    if (v_r->>'ok')::boolean is not true or (v_rep #>> '{jobs,0,runs}')::int <> 0 or (v_rep->>'runs')::int <> 0 then
      raise exception '0481 self-assert FAIL: seen did not start her tallies again: %', left(v_rep::text, 300);
    end if;
    v_note := format('fixed LIS-%s %s, land %s to %s', v_sell, v_gcode, v_lcode, v_yard);
    -- her own voyage is a course: her voyage under way, re-addressed (probe only) to the harbour no lane reaches, serves its course
    -- LIS -> there as it was sailed, and there -> LIS the same water backwards, under way and then ended; another company's fleet is not served it
    update public.voyages v set dest_port_id = (select p.id from public.ports p where p.code = v_far)
     where v.fleet_id = v_fa and v.status = 'SAILING';
    if public.fleet_job_course(v_fa, v_lis, (select p.id from public.ports p where p.code = v_far)) is null then
      raise exception '0481 self-assert FAIL: her voyage under way is not served as her course';
    end if;
    update public.voyages v set status = 'ARRIVED' where v.fleet_id = v_fa and v.status = 'SAILING';
    if public.fleet_job_course(v_fa, v_lis, (select p.id from public.ports p where p.code = v_far))
         is distinct from (select voyage.course_of(v.path) from public.voyages v where v.fleet_id = v_fa and v.origin_port_id = v_lis order by v.eta desc limit 1)
       or public.fleet_job_course(v_fa, (select p.id from public.ports p where p.code = v_far), v_lis)->0
         is distinct from (select voyage.course_of(v.path) from public.voyages v where v.fleet_id = v_fa and v.origin_port_id = v_lis order by v.eta desc limit 1)->-1
       or public.fleet_job_course(v_fb, v_lis, (select p.id from public.ports p where p.code = v_far)) is not null then
      raise exception '0481 self-assert FAIL: her own voyage is not served as her course both ways, or is served to another company';
    end if;

    -- (f) A JOB WITH NO REMEMBERED COURSE STOPS (E_NO_COURSE), says so, and is not due again; clear removes it
    perform cmd.assume_identity(c_ub);
    update public.fleets set status = 'DOCKED', port_id = v_lis where id = v_fb;
    update public.voyages set status = 'ARRIVED' where fleet_id = v_fb and status = 'SAILING';
    update public.orders set status = 'cancelled' where fleet_id = v_fb and status in ('pending', 'active');
    update public.fleet_jobs set params = params || jsonb_build_object('to', v_far), last_plan = null where fleet_id = v_fb;
    perform public.fleet_unload(v_fb, v_lcode, 30);
    perform public.storage_put(v_b, v_lis, v_lgood, 30, 0);
    v_runs_before := (select count(*) from public.orders o where o.fleet_id = v_fb);
    call public.tick_fleet_jobs(false);
    v_rep := world.away_report();
    if (select j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fb) is distinct from 'E_NO_COURSE'
       or v_rep #>> '{jobs,0,state}' <> 'stopped' or v_rep #>> '{jobs,0,paused}' <> 'E_NO_COURSE'
       or (select count(*) from public.orders o where o.fleet_id = v_fb) <> v_runs_before
       or exists (select 1 from public.fleet_jobs_due() d where d.fleet_id = v_fb) then
      raise exception '0481 self-assert FAIL: a job with no remembered course did not stop on E_NO_COURSE, or sent lines, or is still due: %', left(v_rep::text, 400);
    end if;
    v_r := cmd.clear_fleet_job(v_fb);
    if (v_r->>'ok')::boolean is not true or exists (select 1 from public.fleet_jobs j where j.fleet_id = v_fb)
       or jsonb_array_length(world.away_report()->'jobs') <> 0 then
      raise exception '0481 self-assert FAIL: clear did not remove the job: %', v_r;
    end if;

    -- (g) SIGNED OUT: no company
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{}', true);
    if world.away_report() is distinct from '{"on": true, "company": false}'::jsonb then
      raise exception '0481 self-assert FAIL: lit and signed out, the read is not {"on": true, "company": false}';
    end if;
    raise exception using errcode = 'ZX481', message = 'PROBE_ROLLBACK_0481';
  exception when sqlstate 'ZX481' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0481 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0481' or p.auth_uid in (c_ua, c_ub))
     or exists (select 1 from public.fleet_jobs) or exists (select 1 from public.fleet_job_runs)
     or public.wc('fleet_jobs_enabled') is distinct from 'false'::jsonb or public.wc_int('fleet_jobs_per_tick') <> 4
     or public.current_player_id() is not null then
    raise exception '0481 self-assert FAIL: the probe left something behind';
  end if;

  -- ── 8. THE JOB (where pg_cron is): every 2 minutes; dark it reads one knob and returns ──
  -- budget: dark 0 rows a run; lit at most fleet_jobs_per_tick (4) jobs a run, under 60 rows a run (orders, the job rows, one receipt)
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('byeharu-voyage:fleet-jobs', '*/2 * * * *', 'call public.tick_fleet_jobs()');
  else
    raise notice '0481: pg_cron is not installed here (PGlite) - byeharu-voyage:fleet-jobs was NOT scheduled. Call public.tick_fleet_jobs(false) by hand.';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0481 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0481 self-assert ok: STANDING FLEET JOBS (dark). % hunk once and reversing; grants and volatility unmoved; no other function moved; four doors registered for authenticated alone, every core and the tick server only; two tables (RLS, no client grant); five knobs (fleet_jobs_enabled false). Probe (rolled back): dark the doors refuse and the tick writes nothing; lit %, one job a run at fleet_jobs_per_tick 1, the report counts the run and the ledger''s coin, seen starts it again, no remembered course stops the job, clear removes it. % ms.',
    (select count(*) from hunks_0481), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;

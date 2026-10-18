-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0182 — A WAITING MERCHANT IS ASKED IN TURN  (the laid-up merchants are re-planned about every ten
--        minutes — the market's drift slot — a few at a time by the arrivals sweep, not all at once
--        by the hourly reconcile)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-18 (relayed): why are waiting merchants re-planned only once an hour — can it be faster?
-- Every laid-up merchant re-checked about every 10 minutes (the drift slot: checking more often than
-- prices change gains nothing), in bounded batches, round-robin by last-checked time; the reconcile
-- ≤ ~20 s, the arrivals sweep avg ≤ 3 s and p95 < 5 s.
--
-- ── WHAT PROD SHOWED (read-only, 2026-10-18 12:13–13:10 UTC, head 0181; docs/dev-log/2026-10-18-replan-batches.md)
-- * byeharu-voyage:reconcile took 12.2–14.3 s an hour before 0181; after it 57.4 s (12:07) and 62.0 s
--   (13:07), against the routes' 60 s budget (npc_upkeep_budget_seconds).
-- * The difference is the lay-ups 0181 writes, every one re-planned by the hour (public.npc_tend_route →
--   public.npc_plan): 192 routes laid up 11:35–12:07 (75 stayed laid up), ~295 before 13:07 (179
--   stayed). ≈ 44 s / 192 and ≈ 49.5 s / 295: 170–230 ms a re-plan on prod.
-- * Prod-shaped PGlite (the head-0181 world, prod's knobs, stocks, purses and loops; 295 laid up at a
--   lap-start kickoff): the reconcile's route steps took 19.4 s, of which the 295 laid-up re-plans were
--   17.7 s (59 ms each) and the 542 others 1.7 s (3 ms each).
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE QUEUE. public.npc_waiting_queue(now): every laid-up merchant, her LAST ASK (the later of her
--     route's updated_at — every plan saves through the save door, which dates it — and the new
--     npc_fleets.asked_at, stamped when the sweep asks her, so a plan that fails is not asked again at
--     once), when she is DUE again (last ask + npc_replan_every_minutes, 10) and whether she is OVERDUE
--     (last ask ≥ npc_replan_within_minutes, 60, ago).
-- (2) THE ARRIVALS SWEEP ASKS THEM IN TURN. public.npc_ask_waiting(now, until), called at the end of
--     public.tick_arrivals (after every arrival, yard release and wake): the merchants due, longest
--     waiting first (round-robin by last ask), each through public.npc_tend_route, THE per-merchant
--     upkeep (re-plan from where she lies; resume on a loop that pays, or wait) — a merchant begun only
--     while the batch has run less than npc_replan_sweep_ms (600) and asked fewer than
--     npc_replan_per_sweep_max (12), inside the sweep's own budget. What is not reached stays due, first
--     in line, at the next sweep. A batch that raises is rolled back alone and warned; the sweep's
--     arrivals are never lost to it.
-- (3) THE HOURLY RECONCILE ASKS ONLY THE OVERDUE. public.tick_reconcile skips a laid-up merchant who is
--     not OVERDUE (counted `waiting`); an overdue one (the sweep fell an hour behind, or was dark) is
--     re-planned there as before.
-- (4) THE CADENCE IS THE LOAD'S: each waiting merchant is due once her last ask is 10 minutes old and is
--     asked as soon as the batch reaches her. The batch is ≤ 600 ms (+ one re-plan) a sweep, 4 sweeps a
--     minute: ~40 asks a minute on PGlite (59 ms each), ~10–14 a minute on prod (170–230 ms). With
--     prod's 180–300 waiting the cadence is therefore longer than 10 minutes there (the dev-log measures
--     and estimates it); the reconcile backstop keeps every one within the hour.
--
-- ── NOT THE OWNER'S — CONFIRM ───────────────────────────────────────────────────────────────────
-- * The batch's 600 ms a sweep (npc_replan_sweep_ms) is what keeps the sweep's avg ≤ 3 s on prod;
--   raising it shortens the cadence and lengthens every sweep by as much.
-- * One whose plan fails is asked again 10 minutes later, not at every sweep.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- ALTER TABLE public.npc_fleets ADD COLUMN (nullable, no default: catalogue only). CREATE FUNCTION ×2.
-- CREATE OR REPLACE PROCEDURE/FUNCTION ×2 by hunks. The probe runs on one merchant's own rows inside a
-- sub-transaction rolled back whole (asserted). No LOCK TABLE, no set role, no set local, no begin.
-- Timings are notices only.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0181, LF-normalised, each asserted to
-- occur exactly once and to reverse to its pre-image, ACL unchanged): public.tick_arrivals,
-- public.tick_reconcile.
-- ROLLBACK: a forward slice restores the two bodies (each hunk's OLD text is here verbatim), drops the
-- two functions, the column and the four knobs. The laid-up merchants are then asked by the hour again.
-- VERSION: 0182 (provisional; renumbered to head + 1 at deploy). Applies on prod head 0181.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0182(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0182 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('public.tick_arrivals(timestamp with time zone)'),
               ('public.tick_reconcile(boolean)')) f(fn);

do $$
begin
  if (select count(*) from defs_before_0182 where def is not null) <> 2 then
    raise exception '0182 self-assert FAIL: % of the 2 bodies found', (select count(*) from defs_before_0182 where def is not null);
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('npc_waiting_queue', 'npc_ask_waiting')) then
    raise exception '0182 self-assert FAIL: npc_waiting_queue or npc_ask_waiting exists already';
  end if;
  if exists (select 1 from public.world_config where key in ('npc_replan_every_minutes', 'npc_replan_within_minutes', 'npc_replan_per_sweep_max', 'npc_replan_sweep_ms')) then
    raise exception '0182 self-assert FAIL: a replan knob exists already';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'npc_fleets' and column_name = 'asked_at') then
    raise exception '0182 self-assert FAIL: npc_fleets.asked_at exists already';
  end if;
end $$;

-- ── 2. THE KNOBS AND THE STAMP ─────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('npc_replan_every_minutes', to_jsonb(10),
   '0182: a waiting (laid-up) merchant is due to be asked again once her last ask is this many minutes old '
   '(the market drift slot: asking more often than prices change gains nothing). Asked by the arrivals sweep, '
   'longest waiting first (public.npc_waiting_queue, public.npc_ask_waiting).'),
  ('npc_replan_within_minutes', to_jsonb(60),
   '0182: the promise — every waiting merchant is asked again within this many minutes of her last ask; one '
   'not asked by then is OVERDUE and the hourly reconcile asks her.'),
  ('npc_replan_per_sweep_max', to_jsonb(12),
   '0182: the most waiting merchants one arrivals sweep asks. The rest stay due, first in line, for the next sweep.'),
  ('npc_replan_sweep_ms', to_jsonb(600),
   '0182: the wall-clock budget of one sweep''s batch of waiting merchants, in ms (each a re-plan: ~60 ms on '
   'PGlite, 170-230 ms on prod). A merchant is begun only while the batch has run less than this.')
on conflict (key) do nothing;

alter table public.npc_fleets add column asked_at timestamptz;
comment on column public.npc_fleets.asked_at is
  '0182: when the arrivals sweep last asked this merchant, laid up, whether a loop pays now '
  '(public.npc_ask_waiting stamps it before the ask, so a plan that fails is not asked again at once). '
  'Her last ask is the later of this and her route''s updated_at.';

-- ── 3. THE QUEUE ───────────────────────────────────────────────────────────────────────────────
create function public.npc_waiting_queue(p_now timestamptz)
returns table (fleet_id uuid, route_id uuid, k bigint, asked_at timestamptz, due_at timestamptz, overdue boolean)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0182: THE waiting merchants — every merchant whose route is laid up ('laid_up', 0181: nothing on
  -- any of her loops pays), in roster terms (public.npc_tend_roster: fleet, route, k), with her LAST
  -- ASK (the later of her route's updated_at — every plan saves through the save door, which dates it
  -- — and npc_fleets.asked_at, the sweep's stamp), when she is DUE again (last ask + npc_replan_every_minutes —
  -- the market's drift slot) and whether she is OVERDUE (last ask ≥ npc_replan_within_minutes ago — the
  -- hourly reconcile asks those). Read by public.npc_ask_waiting and public.tick_reconcile.
  select ro.fleet_id, ro.route_id, ro.k, a.asked,
         a.asked + make_interval(mins => w.e_min),
         a.asked <= p_now - make_interval(mins => w.w_min)
    from public.npc_tend_roster() ro
    join public.standing_routes sr on sr.id = ro.route_id
    join public.npc_fleets nf on nf.fleet_id = ro.fleet_id
   cross join (select public.wc_int('npc_replan_every_minutes') as e_min,
                      public.wc_int('npc_replan_within_minutes') as w_min) w
   cross join lateral (select greatest(sr.updated_at, coalesce(nf.asked_at, '-infinity'::timestamptz)) as asked) a
   where sr.paused_reason = 'laid_up'
$$;
comment on function public.npc_waiting_queue(timestamptz) is
  '0182: the laid-up merchants, their last ask, when each is due again and whether she is overdue. Server-only.';
revoke all on function public.npc_waiting_queue(timestamptz) from public, anon, authenticated;

-- ── 4. THE ASK ─────────────────────────────────────────────────────────────────────────────────
create function public.npc_ask_waiting(p_now timestamptz, p_until timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
-- 0182: THE ARRIVALS SWEEP'S SHARE OF THE WAITING MERCHANTS. The ones due (public.npc_waiting_queue),
-- longest waiting first (round-robin by last ask), at most npc_replan_per_sweep_max, a merchant begun
-- only while the batch has run less than npc_replan_sweep_ms and the sweep's own budget lasts (p_until): each is stamped asked (npc_fleets.asked_at — taken SKIP LOCKED, so two overlapping sweeps
-- divide them) and put through public.npc_tend_route, THE per-merchant upkeep — re-planned from where
-- she lies, then resumed on a loop that pays or left waiting. What is not reached stays due, first in
-- line, for the next sweep. Off (the merchants dark), nothing is asked; the hourly tend darkens them.
declare
  r       record;
  v_max   int := public.wc_int('npc_replan_per_sweep_max');
  v_stop  timestamptz := least(p_until, clock_timestamp() + make_interval(secs => public.wc_int('npc_replan_sweep_ms') / 1000.0));
  v_n     int := 0;
  v_acc   jsonb := '{}'::jsonb;
  v_ids   jsonb := '[]'::jsonb;
begin
  if not public.npc_traders_on() then
    return jsonb_build_object('asked', 0, 'routes', v_ids);
  end if;
  for r in select q.fleet_id, q.route_id, q.k from public.npc_waiting_queue(p_now) q
            where q.due_at <= p_now order by q.due_at, q.k loop
    exit when v_n >= v_max or clock_timestamp() >= v_stop;
    perform 1 from public.npc_fleets nf where nf.fleet_id = r.fleet_id for update skip locked;
    continue when not found;   -- another sweep is asking her
    update public.npc_fleets set asked_at = p_now where npc_fleets.fleet_id = r.fleet_id;
    v_acc := public.npc_tend_sum(v_acc, public.npc_tend_route(p_now, r.fleet_id, r.route_id, r.k));
    v_ids := v_ids || to_jsonb(r.route_id);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('asked', v_n, 'routes', v_ids, 'tend', public.npc_tend_sum(v_acc, '{}'::jsonb));
end $$;
comment on function public.npc_ask_waiting(timestamptz, timestamptz) is
  '0182: the arrivals sweep asks the waiting merchants due, a few a sweep (npc_replan_per_sweep_max). Server-only.';
revoke all on function public.npc_ask_waiting(timestamptz, timestamptz) from public, anon, authenticated;

-- ── 5. THE HUNKS (sliced from the live bodies; each occurs once; each body reverses; ACL unchanged)
create temporary table hunks_0182 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n)) on commit drop;
insert into hunks_0182 values
-- (2) tick_arrivals: the sweep asks the waiting merchants due, last
('public.tick_arrivals(timestamp with time zone)', 1,
$h$  v_k       numeric := public.wc_num('time_compression');   -- 0169: the candidate scan's knob, once a run
$h$,
$h$  v_k       numeric := public.wc_num('time_compression');   -- 0169: the candidate scan's knob, once a run
  v_asked   jsonb;   -- 0182: the waiting merchants this sweep asked (public.npc_ask_waiting)
$h$),
('public.tick_arrivals(timestamp with time zone)', 2,
$h$  return jsonb_build_object('fleets_touched', v_fleets, 'days_resolved', v_days, 'at', p_now);
$h$,
$h$  -- 0182: A WAITING MERCHANT IS ASKED IN TURN — last, after every arrival, release and wake, inside
  -- this run's budget: the laid-up merchants due (public.npc_waiting_queue, every ~10 minutes), a few a
  -- sweep (npc_replan_sweep_ms, npc_replan_per_sweep_max), each through
  -- public.npc_tend_route (public.npc_ask_waiting). The hourly reconcile used to re-plan all of them at
  -- once (prod 2026-10-18 12:07: 57.4 s of a 60 s budget). A batch that raises is rolled back alone and
  -- warned; this run's arrivals are never lost to it.
  begin
    v_asked := public.npc_ask_waiting(p_now, v_t0 + v_budget);
  exception when others then
    raise warning 'tick_arrivals: the waiting merchants were not asked this sweep (SQLSTATE %: %)', sqlstate, sqlerrm;
    v_asked := jsonb_build_object('asked', 0, 'error', sqlerrm);
  end;
  return jsonb_build_object('fleets_touched', v_fleets, 'days_resolved', v_days, 'at', p_now,
                            'asked', v_asked->'asked');   -- 0182
$h$),
-- (3) tick_reconcile: only the overdue
('public.tick_reconcile(boolean)', 1,
$h$-- What a whole pass decides is npc_tend's (asserted, 0137 §4): the same walk, the same per-merchant
-- body, the same companies' passes, the same compactor — only the commits between them are new.
$h$,
$h$-- What a whole pass decides is npc_tend's (asserted, 0137 §4): the same walk, the same per-merchant
-- body, the same companies' passes, the same compactor — only the commits between them are new.
-- 0182: EXCEPT THE WAITING MERCHANTS. A laid-up merchant is asked by the arrivals sweep, in turn
-- (public.npc_ask_waiting); the hour skips her (counted `waiting`) unless she is OVERDUE
-- (public.npc_waiting_queue: not asked within npc_replan_within_minutes), and re-plans those as before.
$h$),
('public.tick_reconcile(boolean)', 2,
$h$  v_grants   int;
$h$,
$h$  v_grants   int;
  v_wait     uuid[] := '{}';   -- 0182: the waiting merchants the sweep asks in turn (not overdue)
$h$),
('public.tick_reconcile(boolean)', 3,
$h$  for r in select * from public.npc_tend_roster() loop
    perform public.npc_upkeep_scope(v_deadline);
$h$,
$h$  if v_on then
    v_wait := array(select q.route_id from public.npc_waiting_queue(v_now) q where not q.overdue);   -- 0182
  end if;
  for r in select * from public.npc_tend_roster() loop
    -- 0182: SHE IS ASKED IN TURN BY THE SWEEP: not re-planned here unless overdue.
    if r.route_id = any(v_wait) then
      v_tend := public.npc_tend_sum(v_tend, jsonb_build_object('waiting', 1));
      continue;
    end if;
    perform public.npc_upkeep_scope(v_deadline);
$h$);

do $$
declare
  d     record;
  h     record;
  v_def text;
  v_rev text;
begin
  for d in select * from defs_before_0182 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0182 where fn = d.fn order by n loop
      if pg_temp.occurs_0182(v_def, h.old) <> 1 then
        raise exception '0182 self-assert FAIL: hunk % of % occurs % time(s), not once — the deployed body is not what this file was written against',
          h.n, d.fn, pg_temp.occurs_0182(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0182 self-assert FAIL: no hunk for %', d.fn;
    end if;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0182 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0182(v_rev, h.new) <> 1 then
        raise exception '0182 self-assert FAIL: hunk % of % is not in the new body once', h.n, d.fn;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0182 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0182 self-assert FAIL: the ACL of % moved', d.fn;
    end if;
  end loop;
end $$;

-- ── 6. THE PROBE (one merchant's own rows; rolled back whole) ──────────────────────────────────
-- Her preconditions are her own: the routes and the merchants on, NOTHING PAYS on any leg
-- (npc_buyers_per_good 0), one merchant a sweep (npc_replan_per_sweep_max 1), no other merchant due
-- (npc_replan_every_minutes ~9.5 years, the promise 15 minutes later), and she lies docked at
-- her stop 0 between laps with nothing aboard. Her lap-start plan lays her up (0181). Her last ask is
-- then aged ten years, so she is due and first in line: the sweep's ask re-plans her (she waits again,
-- the lay-up not written twice) and stamps her; she is no longer due, and the hour skips her (not
-- overdue); a second ask passes her by. Aged past the promise she is overdue (the hour asks her:
-- positive control). With one unit aboard, aged again, the ask resumes her (positive control).
create temp table probe_0182 (k text primary key, j jsonb) on commit drop;

do $$
declare
  v_f    record;
  v_q    record;
  v_a    jsonb;
  v_t0   timestamptz;
  v_ev0  int;
  v_out  jsonb := '{}'::jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key in ('standing_routes_enabled', 'npc_traders_enabled');
    update public.world_config set value = to_jsonb(0) where key = 'npc_buyers_per_good';
    update public.world_config set value = to_jsonb(1) where key = 'npc_replan_per_sweep_max';
    -- every other waiting merchant out of line: due only once her last ask is ~9.5 years old
    update public.world_config set value = to_jsonb(5000000) where key = 'npc_replan_every_minutes';
    update public.world_config set value = to_jsonb(5000015) where key = 'npc_replan_within_minutes';
    select nf.fleet_id, nf.route_id, nf.player_id, nf.roster_ord,
           (select s.port_id from public.standing_route_stops s where s.route_id = nf.route_id and s.ord = 0) as home
      into v_f
      from public.npc_fleets nf
     where (select count(*) from public.standing_route_stops s where s.route_id = nf.route_id) >= 2
     order by nf.roster_ord limit 1;
    if v_f.fleet_id is null then
      raise exception '0182 self-assert FAIL: no merchant route of two stops to probe';
    end if;
    update public.voyages set status = 'ABORTED' where fleet_id = v_f.fleet_id and status = 'SAILING';
    update public.orders set status = 'cancelled' where fleet_id = v_f.fleet_id and status in ('pending', 'active', 'failed');
    update public.fleets set status = 'DOCKED', port_id = v_f.home, lat = null, lon = null, busy_until = null where id = v_f.fleet_id;
    update public.ships set cargo = '{}'::jsonb where fleet_id = v_f.fleet_id;
    update public.standing_route_laps set closed_at = now() where route_id = v_f.route_id and closed_at is null;
    update public.standing_routes set fleet_id = v_f.fleet_id, lap_id = null, stop_cursor = 0, paused_reason = null,
                                      hold_until = null
     where id = v_f.route_id;
    v_a := public.npc_plan(now(), v_f.route_id);
    v_out := v_out || jsonb_build_object('laid', (select paused_reason from public.standing_routes where id = v_f.route_id),
                                         'plan_waiting', v_a->'waiting');
    select count(*) into v_ev0 from public.events e where e.player_id = v_f.player_id and e.kind = 'ROUTE_PAUSED';

    -- just laid up: not due, not overdue (the hour skips her)
    select * into v_q from public.npc_waiting_queue(now()) q where q.route_id = v_f.route_id;
    v_out := v_out || jsonb_build_object('fresh_in_queue', v_q.route_id is not null, 'fresh_due', v_q.due_at <= now(),
                                         'fresh_overdue', v_q.overdue,
                                         'fresh_due_in', round(extract(epoch from v_q.due_at - now()) / 60),
                                         'fresh_due_want', public.wc_int('npc_replan_every_minutes'));

    -- aged ten years: due, first in line; the sweep's ask re-plans her and she waits again
    update public.standing_routes set updated_at = now() - interval '3650 days' where id = v_f.route_id;
    select * into v_q from public.npc_waiting_queue(now()) q where q.route_id = v_f.route_id;
    v_out := v_out || jsonb_build_object('aged_due', v_q.due_at <= now(), 'aged_overdue', v_q.overdue);
    v_t0 := clock_timestamp();
    v_a := public.npc_ask_waiting(now(), clock_timestamp() + interval '1 minute');
    v_out := v_out || jsonb_build_object('ask_ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000),
      'asked_her', (v_a->'routes') @> jsonb_build_array(v_f.route_id), 'asked_n', v_a->'asked',
      'reason1', (select paused_reason from public.standing_routes where id = v_f.route_id),
      'replanned', (select updated_at = now() from public.standing_routes where id = v_f.route_id),
      'stamped', (select asked_at = now() from public.npc_fleets where fleet_id = v_f.fleet_id),
      'events1', (select count(*) from public.events e where e.player_id = v_f.player_id and e.kind = 'ROUTE_PAUSED') - v_ev0);
    select * into v_q from public.npc_waiting_queue(now()) q where q.route_id = v_f.route_id;
    v_out := v_out || jsonb_build_object('after_due', v_q.due_at <= now(), 'after_overdue', v_q.overdue);
    v_a := public.npc_ask_waiting(now(), clock_timestamp() + interval '1 minute');
    v_out := v_out || jsonb_build_object('asked_her_again', (v_a->'routes') @> jsonb_build_array(v_f.route_id));

    -- aged past the promise (route and stamp): overdue — the hour asks her (positive control)
    update public.standing_routes set updated_at = now() - make_interval(mins => public.wc_int('npc_replan_within_minutes') + 1) where id = v_f.route_id;
    update public.npc_fleets set asked_at = now() - make_interval(mins => public.wc_int('npc_replan_within_minutes') + 1) where fleet_id = v_f.fleet_id;
    select * into v_q from public.npc_waiting_queue(now()) q where q.route_id = v_f.route_id;
    v_out := v_out || jsonb_build_object('late_overdue', v_q.overdue, 'late_due', v_q.due_at <= now());

    -- POSITIVE CONTROL: one unit of a good aboard — she sails her loop to sell it, so the ask resumes her
    update public.ships set cargo = jsonb_build_object((select g.code from public.goods g order by g.code limit 1), 1)
     where id = (select s.id from public.ships s where s.fleet_id = v_f.fleet_id order by s.name limit 1);
    v_a := public.npc_ask_waiting(now(), clock_timestamp() + interval '1 minute');
    v_out := v_out || jsonb_build_object('asked_her3', (v_a->'routes') @> jsonb_build_array(v_f.route_id),
      'reason3', (select paused_reason from public.standing_routes where id = v_f.route_id),
      'in_queue3', exists (select 1 from public.npc_waiting_queue(now()) q where q.route_id = v_f.route_id));
    raise exception 'PROBE_ROLLBACK_0182:%', v_out::text;
  exception when others then
    if sqlerrm not like 'PROBE_ROLLBACK_0182:%' then raise; end if;
    insert into probe_0182 values ('ask', substr(sqlerrm, length('PROBE_ROLLBACK_0182:') + 1)::jsonb);
  end;
end $$;

-- ── 7. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  a jsonb := (select j from probe_0182 where k = 'ask');
begin
  if public.wc_int('npc_replan_every_minutes') <> 10 or public.wc_int('npc_replan_within_minutes') <> 60
     or public.wc_int('npc_replan_per_sweep_max') <> 12 or public.wc_int('npc_replan_sweep_ms') <> 600 then
    raise exception '0182 self-assert FAIL: the knobs are not 10 / 60 / 12 / 600 (the probe''s settings survived?)';
  end if;
  if a->>'laid' <> 'laid_up' or (a->>'plan_waiting')::int <> 1 then
    raise exception '0182 self-assert FAIL: her lap-start plan with nothing paying did not lay her up (0181): %', a;
  end if;
  if not (a->>'fresh_in_queue')::boolean or (a->>'fresh_due')::boolean or (a->>'fresh_overdue')::boolean
     or (a->>'fresh_due_in')::int <> (a->>'fresh_due_want')::int then
    raise exception '0182 self-assert FAIL: just laid up she is not in the queue waiting (not due, not overdue, due in % min, want %): %',
      a->>'fresh_due_in', a->>'fresh_due_want', a;
  end if;
  if not (a->>'aged_due')::boolean or not (a->>'aged_overdue')::boolean then
    raise exception '0182 self-assert FAIL: aged ten years she is not due and overdue: %', a;
  end if;
  if not (a->>'asked_her')::boolean or a->>'reason1' <> 'laid_up' or not (a->>'replanned')::boolean
     or not (a->>'stamped')::boolean or (a->>'events1')::int <> 0 then
    raise exception '0182 self-assert FAIL: the sweep''s ask did not re-plan her (waiting again, stamped, the lay-up not written twice): %', a;
  end if;
  if (a->>'after_due')::boolean or (a->>'after_overdue')::boolean or (a->>'asked_her_again')::boolean then
    raise exception '0182 self-assert FAIL: once asked she is still due or overdue, or the next ask took her again: %', a;
  end if;
  if not (a->>'late_overdue')::boolean or not (a->>'late_due')::boolean then
    raise exception '0182 self-assert FAIL: past the promise she is not overdue (positive control): %', a;
  end if;
  if not (a->>'asked_her3')::boolean or a->>'reason3' is not null or (a->>'in_queue3')::boolean then
    raise exception '0182 self-assert FAIL: with cargo aboard the ask did not resume her (positive control): %', a;
  end if;

  raise notice '0182 self-assert ok: A WAITING MERCHANT IS ASKED IN TURN. Laid up at her lap start (nothing paying), she is in the queue, due in % min (the probe''s npc_replan_every_minutes), not overdue — the hour skips her. Aged ten years she is due and first in line: the sweep asked her (% ms), re-planned her, she waits again, stamped, the lay-up not written twice; then not due, not overdue, and the next ask passed her by. Past the promise she is overdue — the hour asks her (positive control). One unit aboard, the ask resumed her (positive control). Bodies reverse, ACLs unchanged.',
    a->>'fresh_due_in', a->>'ask_ms';
end $$;

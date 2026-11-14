-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0405 - A LAID-UP MERCHANT IS ASKED AGAIN IN TIME  (the waiting line gets a job of its own: the plan outside the quay, the resume in the gap after the beat)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none
--
-- WHY (prod, read-only, 2026-11-14 00:03 to 00:08 UTC, head 0404; docs/dev-log/2026-11-14-layup-line.md):
--   Merchants laid up rose from 33 a day (11-03) to 161 (11-13), 199 to 213 at the hour. 178 of 203 were healthy houses that closed a lap under
--   six hours before: a line merchants pass through, not a grave. THE LINE IS NOT SERVED. A laid-up merchant is due again 10 minutes after her last
--   ask (0182). Asked in the last hour: 239, one in each of 239 beats, where 6 x 199 = about 1,200 were wanted. Minutes since the last ask:
--   p50 21.9, p90 43.9, max 52.4; 162 of 199 due. So a merchant waits n / 4 minutes, and the longer the line the longer each waits.
--   TWO RULES MAKE IT 240 AN HOUR, WHATEVER THE LINE:
--     * 0242: the beat asks only on the seconds public.npc_ask_slot allows, epoch mod npc_ask_every_seconds (15) = 0: 240 beats an hour.
--     * 0199: in such a beat another merchant is begun only if the batch so far PLUS the last ask's own cost stays inside npc_replan_sweep_ms
--       (300). An ask costs 290 to 460 ms on prod (the reconcile's own receipts, 11-07 to 11-13), so the first ask always spends the budget: one a beat.
--   The beat cannot simply ask more: an ask runs under the quay, inside the beat, ahead of the next second's arrivals (the law: arrivals first).
--   The lap-start job (0266) has no room either: its plans, opens and waits fill 77 % of its minute and its lap starts already run seconds late.
--
-- WHAT THIS FILE DOES (new objects only: no live body is re-cut, no knob of the beat is touched, the beat's own ask and the hourly reconcile stay):
--   1. public.tick_waiting_asks() and its job, pg_cron byeharu-voyage:waiting-asks, every minute, one warm session (0248, 0266): the merchants due
--      (public.npc_waiting_queue, THE one answer to "who waits and who is due", untouched), longest waiting first, each ask in the lap start's own
--      two steps (0266):
--      (A) public.waiting_ask_plan(fleet), NOT under the quay: her roster row, fleet and route (SKIP LOCKED), her house (0265's lock, SKIP LOCKED),
--          due re-checked under them; she is stamped asked (npc_fleets.asked_at, as the beat stamps her) and re-planned from where she lies by
--          THE planner (public.npc_plan), the call public.npc_tend_route makes. Nothing pays: she waits on (0181) and is due again in ten minutes.
--          This is the dear part and nine asks in ten end here: it takes no harbour, no quay stock, no purse.
--      (B) public.waiting_ask_open(fleet, stamp), UNDER THE QUAY, placed in the gap after the second's beat has committed (0266's placing): only
--          when her plan pays and nobody has asked her since (her stamp is still step A's), she is resumed through the same door as ever
--          (cmd.standing_route_pause_for(..., false): the pause lifted, cmd.advance). The route finds her lines under a minute old and does not
--          plan again (0114), so the quay is held for the opening of her lap alone, as for any lap start.
--   2. npc_ask_job_ms (20,000): the work a minute the job may spend on asks (plan and open time; waiting for a gap is not work). 0 = off.
--   3. public.waiting_ask_runs: one receipt a minute of the day, as public.lap_start_runs.
--   The two hands never ask one merchant twice: both take her roster row SKIP LOCKED and both stamp her, and the queue reads the stamp.
--
-- WHAT IT COSTS: a third warm session a minute, working at most npc_ask_job_ms. Wanted with n waiting: 6 n asks an hour. Measured on the cached
--   world with 200 staged (dev-log): every due merchant asked inside the bound. On prod at 290 to 460 ms an ask: n = 200 is 1,200 asks an hour,
--   6 to 9 s of work a minute; n = 300 is 9 to 14 s; the budget holds 43 to 69 asks a minute. The beat gains: a merchant asked here is not due
--   when the beat's slot comes, so the beat's 240 asks an hour under the quay fall away as the job keeps up.
-- LOCKS: CREATE TABLE, CREATE FUNCTION x2, CREATE PROCEDURE, one knob, one cron row. The probe asks ONE merchant in a sub-transaction rolled back.
-- TIME: under 1 s on the cached world; expected on prod under 10 s (one plan, 0.3 to 1.2 s there, and one lap opened and rolled back).
--   BUDGET: statement_timeout 30 s, lock_timeout 5 s; the self-assert fails if its probe took more than 15 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/layup-line/rollback-0405.sql, a draft. To stop it at once: npc_ask_job_ms 0.
-- VERSION: 0405 = 0404 + 1.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

set local statement_timeout = '30s';
set local lock_timeout = '5s';

-- ── 0. THE GUARD ──
do $g$
begin
  if to_regprocedure('public.tick_waiting_asks(boolean,uuid)') is not null or to_regclass('public.waiting_ask_runs') is not null
     or exists (select 1 from public.world_config where key = 'npc_ask_job_ms') then
    raise exception '0405 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.npc_waiting_queue(timestamptz)') is null or to_regprocedure('public.npc_plan(timestamptz,uuid)') is null
     or to_regprocedure('public.hold_the_quay()') is null or to_regprocedure('public.lap_start_plan(uuid)') is null
     or to_regprocedure('cmd.standing_route_pause_for(uuid,uuid,boolean,text,text)') is null or to_regclass('public.arrivals_beats') is null then
    raise exception '0405 refuses: the waiting queue (0182), the planner, the quay (0249), the lap-start job (0266) or the beat''s book (0248) are not in this world';
  end if;
end $g$;

-- ── 1. THE KNOB AND THE BOOK ──
insert into public.world_config (key, value, description) values
  ('npc_ask_job_ms', to_jsonb(20000),
   '0405: how many milliseconds of work a minute the byeharu-voyage:waiting-asks job may spend asking the laid-up merchants due again (public.tick_waiting_asks: plan and resume time; waiting for a gap after the beat is not counted). An ask costs about 300 to 500 on prod. 0 = off: the beat''s own ask and the hourly reconcile remain.');

create table public.waiting_ask_runs (
  slot    int         primary key check (slot between 0 and 1439),
  at      timestamptz not null,
  ms      numeric     not null check (ms >= 0),
  receipt jsonb       not null
);
comment on table public.waiting_ask_runs is
  '0405: one row a minute of the day (slot = floor(epoch / 60) mod 1440), overwritten a day later: what public.tick_waiting_asks did in that minute (asked, still waiting, resumed, gone, busy, failed, the plan / open / wait times, the work spent against npc_ask_job_ms, the line and how many of it were still due at the end, the oldest ask in minutes). One writer: public.tick_waiting_asks. Server-only.';
alter table public.waiting_ask_runs enable row level security;
revoke all on table public.waiting_ask_runs from public, anon, authenticated;

-- ── 2. STEP A: THE PLAN, outside the quay ──
create function public.waiting_ask_plan(p_fleet uuid)
returns int
language plpgsql
set search_path = public, pg_temp
as $$
-- 0405: THE WAITING-ASKS JOB'S PLAN STEP (not under the quay). 1 = her plan pays: resume her next (public.waiting_ask_open);
-- 0 = nothing to resume (not due any more, the merchants dark, she is beyond the roster's ceiling or not in port, or the plan
-- left her waiting: final, she is due again in npc_replan_every_minutes); -1 = busy (her roster row, fleet, route or house is
-- locked: SKIP LOCKED, never waits; try again). Her roster row first, as the beat's hand takes it (public.npc_ask_waiting), then
-- fleet and route, then her house (0265), due re-checked under them (public.npc_waiting_queue, the one answer). She is stamped
-- asked and planned by THE planner, the call public.npc_tend_route makes for a laid-up merchant. Everything written is her own:
-- her stamp, route, stops, lines, a pause. It takes no harbour, no quay stock, no purse.
declare
  q      record;
  v_res  jsonb;
begin
  perform 1 from public.npc_fleets nf where nf.fleet_id = p_fleet for update skip locked;
  if not found then return -1; end if;
  perform 1 from public.fleets f
     join public.npc_fleets nf on nf.fleet_id = f.id
     join public.standing_routes sr on sr.id = nf.route_id
   where f.id = p_fleet for update of f, sr skip locked;
  if not found then return -1; end if;
  select w.fleet_id, w.route_id, w.k, sr.player_id, sr.fleet_id as held, f.status
    into q
    from public.npc_waiting_queue(now()) w
    join public.standing_routes sr on sr.id = w.route_id
    join public.fleets f on f.id = w.fleet_id
   where w.fleet_id = p_fleet and w.due_at <= now();   -- re-checked under the locks
  if q.fleet_id is null then return 0; end if;
  if not public.npc_traders_on() or q.k > public.wc_int('npc_fleet_max')
     or q.held is distinct from p_fleet or q.status <> 'DOCKED' then
    return 0;   -- the hourly upkeep's cases (dark, beyond the ceiling, a wreck, not assigned): public.npc_tend_route answers them
  end if;
  perform 1 from public.players p where p.id = q.player_id for no key update skip locked;   -- 0265's house lock
  if not found then return -1; end if;
  update public.npc_fleets set asked_at = now() where fleet_id = p_fleet;
  v_res := public.npc_plan(now(), q.route_id);
  if coalesce((v_res->>'planned')::int, 0) = 0 or coalesce((v_res->>'waiting')::int, 0) > 0 then
    return 0;   -- not planned, or nothing pays: she waits on (0181)
  end if;
  return 1;
end $$;
comment on function public.waiting_ask_plan(uuid) is
  '0405: the waiting-asks job''s plan step, outside the quay: her roster row, fleet, route, house (SKIP LOCKED), re-checked due (public.npc_waiting_queue); stamped asked and planned by public.npc_plan. 1 = her plan pays, resume her next; 0 = nothing to resume; -1 = busy. Server-only.';
revoke all on function public.waiting_ask_plan(uuid) from public, anon, authenticated;

-- ── 3. STEP B: THE RESUME, under the quay ──
create function public.waiting_ask_open(p_fleet uuid, p_stamp timestamptz)
returns int
language plpgsql
set search_path = public, pg_temp
as $$
-- 0405: THE WAITING-ASKS JOB'S OPEN STEP, under the quay. 1 = she was resumed; 0 = not hers to resume any more (another hand
-- asked her since step A: her stamp moved; or she is no longer laid up); -1 = busy (SKIP LOCKED). The quay first, then her
-- roster row, fleet, route, house; then THE resume, the door public.npc_tend_route uses (cmd.standing_route_pause_for(...,
-- false): the pause lifted, cmd.advance). Her lines are step A's, under a minute old, so the route does not plan again (0114).
declare
  sr     public.standing_routes%rowtype;
  v_res  jsonb;
begin
  perform public.hold_the_quay();
  perform 1 from public.npc_fleets nf where nf.fleet_id = p_fleet for update skip locked;
  if not found then return -1; end if;
  perform 1 from public.fleets f
     join public.npc_fleets nf on nf.fleet_id = f.id
     join public.standing_routes r on r.id = nf.route_id
   where f.id = p_fleet for update of f, r skip locked;
  if not found then return -1; end if;
  select r.* into sr
    from public.npc_fleets nf join public.standing_routes r on r.id = nf.route_id
   where nf.fleet_id = p_fleet and nf.asked_at is not distinct from p_stamp;   -- nobody has asked her since step A
  if sr.id is null or sr.paused_reason is distinct from 'laid_up' or sr.fleet_id is distinct from p_fleet then
    return 0;
  end if;
  perform 1 from public.players p where p.id = sr.player_id for no key update skip locked;   -- 0265's house lock
  if not found then return -1; end if;
  v_res := cmd.standing_route_pause_for(sr.player_id, sr.id, false);
  if not coalesce((v_res->>'ok')::boolean, false) then
    raise exception '0405: the resume door refused % - %', sr.name, v_res->>'error_message';
  end if;
  return 1;
end $$;
comment on function public.waiting_ask_open(uuid, timestamptz) is
  '0405: the waiting-asks job''s open step, under the quay: her roster row, fleet, route, house (SKIP LOCKED); only while her stamp is still step A''s and she is still laid up, she is resumed through cmd.standing_route_pause_for(..., false). 1 = resumed, 0 = not hers any more, -1 = busy. Server-only.';
revoke all on function public.waiting_ask_open(uuid, timestamptz) from public, anon, authenticated;

-- ── 4. THE JOB ──
create procedure public.tick_waiting_asks(p_commit boolean default true, p_only uuid default null)
language plpgsql
as $body$
-- 0405: THE waiting-asks job (pg_cron byeharu-voyage:waiting-asks, every minute, CALL). One warm session a minute (0248): the
-- laid-up merchants due (public.npc_waiting_queue), longest waiting first, each ask its own two transactions: the plan step
-- (public.waiting_ask_plan, outside the quay) and, when her plan pays, the open step (public.waiting_ask_open, under the quay),
-- placed in the gap after the second's beat has committed (public.arrivals_beats) when the gap holds it, else the next gap (at
-- most c_wait): 0266's placing, to the letter. It works npc_ask_job_ms a minute at most (0 = off) and looks at the line once a
-- second while nobody is due. Stops at c_end of its minute, or at once when its job is switched off (public.clock_jobs).
-- p_commit = false: one pass over who is due now, in the caller's transaction, no waits (a proof, the self-assert); p_only: that
-- fleet alone. No SECURITY DEFINER, no SET: a procedure that commits may carry neither; it runs as the job's owner.
declare
  c_end    constant interval := interval '57 seconds';
  c_wait   constant interval := interval '1500 milliseconds';
  c_margin constant numeric := 60;
  v_budget numeric := public.wc_int('npc_ask_job_ms');
  v_t0     timestamptz := clock_timestamp();
  v_now0   timestamptz := now();
  v_end    timestamptz := date_trunc('minute', clock_timestamp()) + c_end;
  v_cron   boolean := exists (select 1 from pg_extension where extname = 'pg_cron');
  v_skip   uuid[] := '{}';   -- busy this pass: tried again once nobody else is due
  v_bad    uuid[] := '{}';   -- raised this minute: not tried again in it
  v_f      uuid;
  v_stamp  timestamptz;
  v_a      int;
  v_b      int;
  v_t      timestamptz;
  v_tw     timestamptz;
  v_ms     numeric;
  v_est    numeric := 250;
  v_spent  numeric := 0;
  v_asked  int := 0;
  v_waiting int := 0;
  v_resumed int := 0;
  v_gone   int := 0;
  v_busy   int := 0;
  v_failed int := 0;
  v_late   int := 0;
  v_note   text;
  v_plan_ms numeric := 0;
  v_plan_max numeric := 0;
  v_open_ms numeric := 0;
  v_open_max numeric := 0;
  v_wait_ms numeric := 0;
begin
  loop
    exit when v_spent >= v_budget;
    if p_commit then
      exit when clock_timestamp() >= v_end;
      exit when v_cron and not exists (select 1 from public.clock_jobs() j
                                        where j.jobname = 'byeharu-voyage:waiting-asks' and j.active);
    end if;
    v_f := null;
    select q.fleet_id into v_f
      from public.npc_waiting_queue(now()) q
     where q.due_at <= now()
       and (p_only is null or q.fleet_id = p_only)
       and not (q.fleet_id = any(v_skip)) and not (q.fleet_id = any(v_bad))
     order by q.due_at, q.k
     limit 1;
    if v_f is null then
      exit when not p_commit;
      v_skip := '{}';   -- a busy one gets another try
      commit;
      perform pg_sleep(1);
      commit;
      continue;
    end if;

    -- (A) THE PLAN, outside the quay
    v_t := clock_timestamp();
    v_stamp := null;
    begin
      v_a := public.waiting_ask_plan(v_f);
      if v_a = 1 then
        select nf.asked_at into v_stamp from public.npc_fleets nf where nf.fleet_id = v_f;
      end if;
    exception when others then
      v_a := -2;
      v_note := coalesce(v_note, 'plan ' || v_f || ': ' || sqlerrm);
    end;
    if p_commit then commit; end if;
    v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
    v_spent := v_spent + v_ms;
    v_plan_ms := v_plan_ms + v_ms;
    v_plan_max := greatest(v_plan_max, v_ms);
    if v_a <> 1 then
      if v_a = 0 then v_asked := v_asked + 1; v_waiting := v_waiting + 1; v_skip := v_skip || v_f;
      elsif v_a = -1 then v_busy := v_busy + 1; v_skip := v_skip || v_f;
      else v_failed := v_failed + 1; v_bad := v_bad || v_f;
      end if;
      continue;
    end if;
    v_asked := v_asked + 1;

    -- (B) THE RESUME, under the quay, in the gap after this second's beat
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
      if clock_timestamp() - v_tw >= c_wait then v_late := v_late + 1; end if;
      v_wait_ms := v_wait_ms + extract(epoch from clock_timestamp() - v_tw) * 1000;
      commit;   -- the open step's transaction starts here
    end if;
    v_t := clock_timestamp();
    begin
      v_b := public.waiting_ask_open(v_f, v_stamp);
    exception when others then
      v_b := -2;
      v_note := coalesce(v_note, 'open ' || v_f || ': ' || sqlerrm);
    end;
    if p_commit then commit; end if;
    v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
    v_spent := v_spent + v_ms;
    v_open_ms := v_open_ms + v_ms;
    v_open_max := greatest(v_open_max, v_ms);
    v_est := greatest(80, 0.7 * v_est + 0.3 * v_ms);
    if v_b = 1 then v_resumed := v_resumed + 1; v_skip := v_skip || v_f;
    elsif v_b = 0 then v_gone := v_gone + 1; v_skip := v_skip || v_f;
    elsif v_b = -1 then v_busy := v_busy + 1; v_skip := v_skip || v_f;
    else v_failed := v_failed + 1; v_bad := v_bad || v_f;
    end if;
  end loop;
  insert into public.waiting_ask_runs (slot, at, ms, receipt)
  values ((floor(extract(epoch from v_now0) / 60)::bigint % 1440)::int, v_now0,
          round(extract(epoch from clock_timestamp() - v_t0)::numeric * 1000, 1),
          (select jsonb_build_object(
                    'enabled', public.npc_traders_on(), 'budget_ms', v_budget, 'spent_ms', round(v_spent),
                    'asked', v_asked, 'waiting', v_waiting, 'resumed', v_resumed, 'gone', v_gone,
                    'busy', v_busy, 'failed', v_failed, 'note', v_note, 'late', v_late,
                    'plan_ms', round(v_plan_ms), 'plan_ms_max', round(v_plan_max),
                    'open_ms', round(v_open_ms), 'open_ms_max', round(v_open_max), 'wait_ms', round(v_wait_ms),
                    'line', count(*), 'due_left', count(*) filter (where q.due_at <= now()),
                    'oldest_min', round(coalesce(max(extract(epoch from now() - q.asked_at)) / 60.0, 0)::numeric, 1))
             from public.npc_waiting_queue(now()) q))
  on conflict (slot) do update set at = excluded.at, ms = excluded.ms, receipt = excluded.receipt;
  if p_commit then commit; end if;
end $body$;
comment on procedure public.tick_waiting_asks(boolean, uuid) is
  '0405: THE waiting-asks job (pg_cron byeharu-voyage:waiting-asks, every minute, CALL): the laid-up merchants due (public.npc_waiting_queue) longest waiting first, each her plan step (public.waiting_ask_plan, outside the quay) and, when her plan pays, her open step (public.waiting_ask_open, under the quay, in the gap after the beat); npc_ask_job_ms of work a minute (0 = off); one receipt a minute (public.waiting_ask_runs). p_commit = false: one pass in the caller''s transaction; p_only: that fleet alone. Server-only.';
revoke all on procedure public.tick_waiting_asks(boolean, uuid) from public, anon, authenticated;

do $cron$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice '0405: pg_cron is not installed here (PGlite): byeharu-voyage:waiting-asks was NOT scheduled. Call public.tick_waiting_asks(false) by hand.';
    return;
  end if;
  perform cron.schedule('byeharu-voyage:waiting-asks', '* * * * *', 'call public.tick_waiting_asks()');
  perform cron.alter_job(jobid, active := false) from cron.job where jobname = 'byeharu-voyage:waiting-asks';
  raise notice '0405: pg_cron present: byeharu-voyage:waiting-asks SCHEDULED BUT INACTIVE until wind_the_clock().';
end $cron$;

-- ── 5. THE SELF-ASSERT: what was made; then ONE merchant asked by the job's own pass, rolled back ──
do $assert$
declare
  v_t0     timestamptz := clock_timestamp();
  v_f      uuid;
  v_route  uuid;
  v_staged boolean := false;
  v_r1     jsonb;
  v_r2     jsonb;
  v_state  text;
  v_n      int;
begin
  if (select count(*) from pg_proc p where p.oid in ('public.waiting_ask_plan(uuid)'::regprocedure, 'public.waiting_ask_open(uuid,timestamptz)'::regprocedure,
                                                      'public.tick_waiting_asks(boolean,uuid)'::regprocedure)
         and not p.prosecdef and p.provolatile = 'v') <> 3 then
    raise exception '0405 self-assert FAIL: the three bodies are not as written (volatile, no definer)';
  end if;
  if has_function_privilege('anon', 'public.waiting_ask_plan(uuid)', 'execute') or has_function_privilege('authenticated', 'public.waiting_ask_plan(uuid)', 'execute')
     or has_function_privilege('anon', 'public.waiting_ask_open(uuid,timestamptz)', 'execute') or has_function_privilege('authenticated', 'public.waiting_ask_open(uuid,timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.tick_waiting_asks(boolean,uuid)', 'execute') or has_function_privilege('authenticated', 'public.tick_waiting_asks(boolean,uuid)', 'execute')
     or has_table_privilege('anon', 'public.waiting_ask_runs', 'select') or has_table_privilege('authenticated', 'public.waiting_ask_runs', 'select') then
    raise exception '0405 self-assert FAIL: a client can reach the job, a step or its book';
  end if;
  if public.wc_int('npc_ask_job_ms') <> 20000 then
    raise exception '0405 self-assert FAIL: npc_ask_job_ms is not this file''s';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select count(*) from cron.job j where j.jobname = 'byeharu-voyage:waiting-asks' and j.schedule = '* * * * *'
                  and j.command = 'call public.tick_waiting_asks()'$q$ into v_n;
    if v_n <> 1 then
      raise exception '0405 self-assert FAIL: byeharu-voyage:waiting-asks is not scheduled every minute';
    end if;
  end if;

  -- THE PROBE. One merchant of the line as it stands (prod has some two hundred); a world with nobody laid up
  -- stages one: a merchant docked at her loop's first stop with no open lap is laid up by hand. Every row is rolled back.
  begin
    select q.fleet_id, q.route_id into v_f, v_route
      from public.npc_waiting_queue(now()) q
      join public.fleets f on f.id = q.fleet_id and f.status = 'DOCKED'
      join public.standing_routes sr on sr.id = q.route_id and sr.fleet_id = q.fleet_id
     where q.k <= public.wc_int('npc_fleet_max')
     order by q.due_at, q.k limit 1;
    if v_f is null and public.npc_traders_on() then
      select ro.fleet_id, ro.route_id into v_f, v_route
        from public.npc_tend_roster() ro
        join public.fleets f on f.id = ro.fleet_id and f.status = 'DOCKED'
        join public.standing_routes sr on sr.id = ro.route_id and sr.fleet_id = ro.fleet_id and sr.lap_id is null
        join public.standing_route_stops s on s.route_id = sr.id and s.ord = 0 and s.port_id = f.port_id
       where ro.k <= public.wc_int('npc_fleet_max')
         and not exists (select 1 from public.orders o where o.fleet_id = ro.fleet_id and o.status in ('pending', 'failed'))
       order by ro.k limit 1;
      v_staged := v_f is not null;
      if v_staged then
        update public.standing_routes set paused_reason = 'laid_up', hold_until = null where id = v_route;
      end if;
    end if;
    if v_f is null or not public.npc_traders_on() then
      v_f := null;
      raise notice '0405 self-assert: no merchant in port to ask in this world (or the merchants are dark); the probe is proof 100''s';
    else
      -- due: her last ask is put an hour back (the queue reads the later of her route''s date and her stamp)
      update public.standing_routes set updated_at = now() - interval '1 hour' where id = v_route;
      update public.npc_fleets set asked_at = null where fleet_id = v_f;
      if not exists (select 1 from public.npc_waiting_queue(now()) q where q.fleet_id = v_f and q.due_at <= now()) then
        raise exception '0405 self-assert FAIL: the probe merchant is not due in the queue';
      end if;
      -- OFF: with the budget at 0 the job asks nobody
      update public.world_config set value = to_jsonb(0) where key = 'npc_ask_job_ms';
      call public.tick_waiting_asks(false, v_f);
      select r.receipt into v_r1 from public.waiting_ask_runs r where r.at = now();
      if (v_r1->>'asked')::int <> 0 or (select nf.asked_at from public.npc_fleets nf where nf.fleet_id = v_f) is not null then
        raise exception '0405 self-assert FAIL: off (npc_ask_job_ms 0) the job asked: %', v_r1;
      end if;
      update public.world_config set value = to_jsonb(20000) where key = 'npc_ask_job_ms';
      -- ON: she is asked once, stamped, and either waits on or is resumed; whichever the market says
      call public.tick_waiting_asks(false, v_f);
      select r.receipt into v_r1 from public.waiting_ask_runs r where r.at = now();
      select sr.paused_reason into v_state from public.standing_routes sr where sr.id = v_route;
      if (v_r1->>'asked')::int <> 1 or (v_r1->>'failed')::int <> 0 or (v_r1->>'busy')::int <> 0
         or (v_r1->>'waiting')::int + (v_r1->>'resumed')::int <> 1
         or (select nf.asked_at from public.npc_fleets nf where nf.fleet_id = v_f) is distinct from now() then
        raise exception '0405 self-assert FAIL: the probe merchant was not asked once and stamped: %', v_r1;
      end if;
      -- waiting: she is laid up still. Resumed: she went through the resume door (it dates her route); what her route's own guards then
      -- make of her lap is the market's and is not asserted.
      if ((v_r1->>'waiting')::int = 1 and v_state is distinct from 'laid_up')
         or ((v_r1->>'resumed')::int = 1 and (select sr.updated_at from public.standing_routes sr where sr.id = v_route) is distinct from now()) then
        raise exception '0405 self-assert FAIL: the receipt (%) and her route (%) disagree', v_r1, coalesce(v_state, 'not paused');
      end if;
      -- AGAIN, AT ONCE: she is not due (stamped, or gone from the line), so nobody is asked
      call public.tick_waiting_asks(false, v_f);
      select r.receipt into v_r2 from public.waiting_ask_runs r where r.at = now();
      if (v_r2->>'asked')::int <> 0 then
        raise exception '0405 self-assert FAIL: a merchant just asked was asked again: %', v_r2;
      end if;
    end if;
    raise exception 'PROBE_ROLLBACK_0405';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0405' then raise; end if;
  end;
  if exists (select 1 from public.waiting_ask_runs) or public.wc_int('npc_ask_job_ms') <> 20000 then
    raise exception '0405 self-assert FAIL: the probe was not rolled back';
  end if;
  if clock_timestamp() - v_t0 > interval '15 seconds' then
    raise exception '0405 self-assert FAIL: the probe took % (budget 15 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0405 self-assert ok: A LAID-UP MERCHANT IS ASKED AGAIN IN TIME. The job, its two steps, its book and its knob are made and server-only; %; rolled back; % ms.',
    case when v_f is null then 'no merchant to ask in this world: no probe'
         else 'one merchant ' || case when v_staged then 'staged into' else 'of' end || ' the line asked once by the job''s own pass ('
              || (select string_agg(k || ' ' || (v_r1->>k), ', ') from unnest(array['asked', 'waiting', 'resumed', 'plan_ms', 'open_ms']) k)
              || '); off asks nobody; asked again at once asks nobody' end,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $assert$;

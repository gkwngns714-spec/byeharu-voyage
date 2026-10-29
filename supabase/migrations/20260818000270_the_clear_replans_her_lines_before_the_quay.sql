-- 0270 — HER CLEAR'S RE-PLAN RUNS BEFORE THE QUAY  (0150's stuck-lap answer leaves the tend step's hold)
--
-- THE ROOT, measured on prod (0269's recording, read 2026-10-29 06:00 UTC, head 0269, 14 hours of receipts):
-- every hour's longest tend holds are the SAME kind of step: did = {cleared: 1}, step_ms 0.40-1.09 s, and
-- step_ms is ~all of held_ms (check_ms <= 3 ms, commit_ms <= 11 ms). The :07 lap-start lag follows them: lag
-- p95 4.0-7.2 s and max 8.4 s in the :07 minute of the last 9 hours, with 1-3 laps a minute that waited their
-- full 1.5 s for a beat gap, and a lap open's own quay wait up to 1,062 ms. 0150 re-plans a clearing merchant's
-- lines (npc_plan: ~11 legs and up to 16 candidate loops priced, ~0.4-1.1 s on prod) INSIDE her step, and
-- 0267/0269 run every step under public.hold_the_quay(). 0150 did not create this; it fired it for the ~1 in 3
-- clears (the third of a lap, or a SAIL refused E_ENDURANCE) that will re-plan.
--
-- THE FIX (0266's pattern, where a lap start's re-plan left the per-second beat the same way): her clear's
-- re-plan runs in a PLAN PASS of its own, BEFORE the quay, and her step then does the clear without re-planning.
--   1. public.npc_clear_due — the clear's number in her lap and 0150's rule, in ONE place: the step and the plan
--      pass ask it, so they cannot disagree.
--   2. public.npc_tend_route gets a plan-pass mode (transaction flag byeharu.tend_plan_pass): it walks her gates
--      exactly as her step does, and at every road that is not the clear branch it stops without acting; at the
--      clear branch it re-plans her when the rule says so and sets byeharu.tend_planned. Every gate still has one
--      copy — the plan pass is the same function, not a second reading of the rules.
--   3. public.tick_reconcile walks the plan pass, in its own transaction, for exactly the merchants a clear can
--      reach at all (a failed order is the only road to the clear branch: a plain SELECT of public.orders), then
--      her step under the quay as before, with byeharu.tend_planned telling the clear branch that her plan is made.
--
-- ORDER AND LOCKS (the 0265/0267 law, unmoved). The plan pass takes her fleet and route rows NOWAIT (as her step
-- already did) and never takes the quay: it is on no wait cycle, and it commits before her step's transaction
-- opens. Her step still takes the quay FIRST, then her rows. The set of functions that take the quay is unchanged.
--
-- WHAT DOES NOT MOVE. The clear: one NPC_CLEARED event with the same count, cmd.clear_for, cmd.advance — the same
-- calls in the same order. The gates, their order and their writes: unmoved (the plan pass returns before each
-- act). The budget (0114): read at her step's head, which is now the plan pass — one reading per merchant, before
-- the dear work, as before. The pause a plan may set (0181 laid_up): her step still clears her after it, exactly
-- as the old clear branch did after its inline plan. npc_tend (the one-transaction door) never sets the flags and
-- behaves as before.
--
-- THE PROOF (all rolled back, on the world this is applied to): every hunk occurs once and reverses to its
-- pre-image; ACL / volatility / definer / config and the functions both bodies decide with are unmoved; the quay
-- takers are the same set. Her step OLD vs NEW vs OLD again (control) on up to 6 running merchants, each with a
-- planted failed order: three cases — a first clear (no plan), a third clear of her lap (plan), a SAIL refused
-- E_ENDURANCE (plan) — the rows digest and the receipt identical. Then the fix itself, her plan pass + her step
-- against her step with the plan inline: the same rows and the same receipt, and the plan pass only plans where
-- the rule says so. Then the whole hourly loop, OLD vs NEW with the same cuts (the sample, no companies, the
-- sample's purses): the same rows and the same receipt apart from the new tally, and its plan pass counted.
--
-- PROD CHECKS (before the push; read-only; in the PR body): the live bodies are the ones the hunks were cut
-- against (md5 below), and the plan pass's own cost is what the deploy's next :07 shows (receipt.tend_plan,
-- receipt.tend_holds: no hold over ~200 ms from a clear). Expect the tend phase's held_ms to fall by the plans'
-- share (~1-2 s an hour) and the :07 lag p95 toward the other minutes'.
--
-- VERSION: 0270 (prod head 0269).

-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.keep_reconcile_beats(timestamptz)') is null
     or to_regclass('public.arrivals_beats_kept') is null
     or to_regprocedure('public.quay_hold_note(jsonb,uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone,jsonb)') is null then
    raise exception '0270 refuses: 0269 is not in this world';
  end if;
  if to_regprocedure('public.npc_clear_due(uuid,uuid,int,text,text)') is not null then
    raise exception '0270 refuses: public.npc_clear_due already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0270(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0270 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.npc_tend_route(timestamptz,uuid,uuid,bigint)'),
               ('public.tick_reconcile(boolean)')) f(fn);

-- the functions the two bodies decide with: not one of them may move in this file
create temp table kept_0270 (fn text) on commit drop;
insert into kept_0270 (fn) values
  ('public.npc_plan(timestamptz,uuid)'), ('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'),
  ('public.npc_tend_roster()'), ('public.npc_tend_sum(jsonb,jsonb)'), ('public.npc_step_failed(jsonb,text)'),
  ('public.npc_upkeep_spent()'), ('public.npc_upkeep_scope(timestamptz)'), ('public.npc_traders_on()'),
  ('public.npc_waiting_queue(timestamptz)'), ('public.emit_event(uuid,text,jsonb)'),
  ('public.tow_for(uuid,uuid)'), ('public.hold_the_quay()'),
  ('public.quay_tally(jsonb,timestamptz,timestamptz)'),
  ('public.quay_hold_note(jsonb,uuid,uuid,uuid,text,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,jsonb)'),
  ('public.npc_invest_one(timestamptz,uuid)'), ('public.npc_invest_roster(uuid)'),
  ('public.capital_gift_one(timestamptz,uuid)'), ('public.capital_gift_roster(timestamptz,uuid)'),
  ('cmd.clear_for(uuid,uuid,boolean)'), ('cmd.advance(uuid,timestamptz)'),
  ('cmd.parse(uuid,uuid,text)'), ('cmd.enqueue(uuid,jsonb,text,jsonb,uuid)'),
  ('cmd.standing_route_pause_for(uuid,uuid,boolean,text,text)'),
  ('cmd.standing_route_assign_for(uuid,uuid,uuid)'),
  ('cmd.standing_route_save_for(uuid,uuid,text,jsonb,bigint,integer,integer)'),
  ('cmd.provision_preset_save_for(uuid,uuid,text,integer)'),
  ('cmd.run_standing_route(uuid,timestamptz)'), ('cmd.standing_route_tail(uuid,integer,uuid)');

create temp table before_0270 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(md5(replace(pg_get_functiondef(k.fn::regprocedure), E'\r', '')), ',' order by k.fn))
          from kept_0270 k) as kept_md5,
       (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
           and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%hold_the_quay()%') as quay_takers,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%') as fns;

-- ── 1. THE ONE RULE ─────────────────────────────────────────────────────────────────────────────
create function public.npc_clear_due(p_player uuid, p_route uuid, p_lap int, p_verb text, p_error_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
-- 0270: A clearing merchant's number in her lap, and whether that clear re-plans her lines — ONE authority for
-- 0150's rule, asked by public.npc_tend_route's clear branch and by the same function's plan pass:
--   n    = the clears of this lap (her NPC_CLEARED events) + 1: the number this clear carries;
--   plan = 0150: the third clear of her lap, or her SAIL refused E_ENDURANCE (a clear alone re-sends the SAIL
--          and nothing else; only a plan answers it).
-- Reads public.events only: no lock, no write, no clock.
declare
  v_n int;
begin
  select count(*) + 1 into v_n
    from public.events ev
   where ev.player_id = p_player and ev.kind = 'NPC_CLEARED'
     and ev.payload->>'route_id' = p_route::text and (ev.payload->>'lap_no')::int = p_lap;
  return jsonb_build_object('n', v_n, 'plan', v_n >= 3 or (p_verb = 'SAIL' and p_error_code = 'E_ENDURANCE'));
end $fn$;
comment on function public.npc_clear_due(uuid, uuid, int, text, text) is
  '0270: a merchant''s place in her lap''s clears (her NPC_CLEARED events of this lap + 1) and 0150''s re-plan '
  'rule (the third clear of the lap, or a SAIL refused E_ENDURANCE), in one place: read by '
  'public.npc_tend_route''s clear branch and by its plan pass. Server-only.';
revoke all on function public.npc_clear_due(uuid, uuid, int, text, text) from public, anon, authenticated;

-- ── 2. THE HUNKS ────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0270 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0270 (fn, n, old, new) values
-- ── npc_tend_route ──
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 1,
$h$  v_waiting int := 0;   -- 0181: laid up in port, nothing on her loops paying
begin
$h$,
$h$  v_waiting int := 0;   -- 0181: laid up in port, nothing on her loops paying
  -- 0270: HER CLEAR'S RE-PLAN LEAVES THE QUAY (0266's pattern). A failed order is the only road to the clear
  -- branch, where 0150's rule re-plans her — ~0.4-1.1 s on prod, the longest tend hold of every hour (0269's
  -- receipt). So her step's re-plan runs first in the plan pass (byeharu.tend_plan_pass: the gates below walked,
  -- the clear's re-plan, nothing else), in its own transaction before the quay; her step then does the clear
  -- without re-planning (byeharu.tend_planned).
  v_plan_pass boolean := coalesce(current_setting('byeharu.tend_plan_pass', true), '') = 'on';
  v_planned   boolean := coalesce(current_setting('byeharu.tend_planned', true), '') = 'on';
  v_due       jsonb;
begin
$h$),
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 2,
$h$      if not v_on or r.k > v_max then
        if sr.fleet_id is not null and sr.paused_reason is distinct from 'dark' then
$h$,
$h$      if not v_on or r.k > v_max then
        if v_plan_pass then continue; end if;   -- 0270: the plan pass never pauses her: her step's road is not the clear
        if sr.fleet_id is not null and sr.paused_reason is distinct from 'dark' then
$h$),
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 3,
$h$      if f.status = 'UNABLE_TO_SAIL' and f.port_id is not null then
        begin
          v_res := public.tow_for(sr.player_id, r.fleet_id);
$h$,
$h$      if f.status = 'UNABLE_TO_SAIL' and f.port_id is not null then
        if v_plan_pass then continue; end if;   -- 0270: the plan pass never tows her: a wreck in port is not the clear
        begin
          v_res := public.tow_for(sr.player_id, r.fleet_id);
$h$),
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 4,
$h$      if sr.paused_reason = 'off_route' then
        -- 0152: DOCKED OFF HER LOOP (towed to a shipyard her loop does not call at): her loop is
$h$,
$h$      if sr.paused_reason = 'off_route' then
        if v_plan_pass then continue; end if;   -- 0270: the plan pass never assigns her loop
        -- 0152: DOCKED OFF HER LOOP (towed to a shipyard her loop does not call at): her loop is
$h$),
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 5,
$h$      if (sr.fleet_id is null or sr.paused_reason is not null) and public.npc_upkeep_spent() then
        v_deferred := v_deferred + 1;
        continue;
      end if;
$h$,
$h$      -- 0270: WHEN HER PLAN WAS TAKEN OUTSIDE THE QUAY, THE BUDGET WAS READ AT HER STEP'S HEAD (the plan pass):
      -- this copy could only defer the clear her plan was already made for.
      if not v_planned and (sr.fleet_id is null or sr.paused_reason is not null) and public.npc_upkeep_spent() then
        v_deferred := v_deferred + 1;
        continue;
      end if;
$h$),
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 6,
$h$      if sr.fleet_id is null or sr.paused_reason is not null then
        if sr.paused_reason = 'error' then
$h$,
$h$      -- 0270: with her plan taken outside the quay, the only pause that can stand here is the plan's own
      -- 'laid_up' — and it never diverts her clear (the old clear branch cleared her after its plan all the same).
      if not v_planned and (sr.fleet_id is null or sr.paused_reason is not null) then
        if v_plan_pass then continue; end if;   -- 0270: the plan pass never plans, starts or resumes her here
        if sr.paused_reason = 'error' then
$h$),
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 7,
$h$      if fo.id is not null and public.npc_upkeep_spent() then
        v_deferred := v_deferred + 1;                               -- 0114
      elsif fo.id is not null then
        select count(*) + 1 into v_clears from public.events ev
         where ev.player_id = sr.player_id and ev.kind = 'NPC_CLEARED'
           and ev.payload->>'route_id' = sr.id::text and (ev.payload->>'lap_no')::int = sr.lap_no;
        perform public.emit_event(sr.player_id, 'NPC_CLEARED', jsonb_build_object(
$h$,
$h$      if fo.id is not null and not v_planned and public.npc_upkeep_spent() then
        v_deferred := v_deferred + 1;                               -- 0114
      elsif fo.id is not null then
        v_due := public.npc_clear_due(sr.player_id, sr.id, sr.lap_no, fo.verb, fo.error_code);   -- 0270: her clear's number and 0150's rule, one place
        -- 0270: THE PLAN PASS: her clear's re-plan, outside the quay, and nothing else of her step is walked.
        if v_plan_pass then
          if (v_due->>'plan')::boolean then
            perform public.npc_plan(p_now, sr.id);
            perform set_config('byeharu.tend_planned', 'on', true);
          end if;
          continue;
        end if;
        v_clears := (v_due->>'n')::int;
        perform public.emit_event(sr.player_id, 'NPC_CLEARED', jsonb_build_object(
$h$),
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 8,
$h$        if v_clears >= 3 or (fo.verb = 'SAIL' and fo.error_code = 'E_ENDURANCE') then
          perform public.npc_plan(p_now, sr.id);
        end if;
$h$,
$h$        -- 0270: her re-plan came from the plan pass when it ran; the rule itself is inside public.npc_clear_due.
        if (v_due->>'plan')::boolean and not v_planned then
          perform public.npc_plan(p_now, sr.id);
        end if;
$h$),
-- ── tick_reconcile ──
('public.tick_reconcile(boolean)', 1,
$h$  v_holds    jsonb := '{}'::jsonb;
begin
$h$,
$h$  v_holds    jsonb := '{}'::jsonb;
  -- 0270: her clear's re-plan off the quay (the plan pass), its verdict for her step, and its tally
  v_plan     text;
  v_tp       timestamptz;
  v_plans    int := 0;
  v_plan_ms  numeric := 0;
begin
$h$),
('public.tick_reconcile(boolean)', 2,
$h$    v_tq := clock_timestamp();   -- 0267: the quay asked for
    if p_commit then perform public.hold_the_quay(); end if;   -- 0249: never beside an arrivals beat
    v_th := clock_timestamp();   -- 0267: the quay granted
    -- 0269: what she was as her step began (a plain read of her route and fleet rows, no lock), and the step's clock
$h$,
$h$    -- 0270: HER CLEAR'S RE-PLAN RUNS OUTSIDE THE QUAY (0266's pattern). A failed order is the only road to her
    -- step's clear branch, where 0150's rule re-plans her (~0.4-1.1 s on prod: 0269's receipt shows every hour's
    -- longest tend hold is a `cleared` step). Such a merchant is walked first by the plan pass —
    -- public.npc_tend_route in its plan-pass mode: her gates, then the clear's re-plan, and nothing else — in its
    -- own transaction, before the quay. Her step then runs as before and does not re-plan (byeharu.tend_planned).
    v_plan := 'off';
    if exists (select 1 from public.orders o where o.fleet_id = r.fleet_id and o.status = 'failed') then
      v_tp := clock_timestamp();
      begin
        perform set_config('byeharu.tend_plan_pass', 'on', true);
        perform set_config('byeharu.tend_planned', 'off', true);
        perform public.npc_upkeep_scope(v_deadline);
        perform public.npc_tend_route(v_now, r.fleet_id, r.route_id, r.k);
        v_plan := coalesce(current_setting('byeharu.tend_planned', true), 'off');
      exception when others then
        v_plan := 'off';   -- her step plans for herself, as before
      end;
      perform set_config('byeharu.tend_plan_pass', 'off', true);
      if p_commit then commit; end if;
      v_plan_ms := v_plan_ms + extract(epoch from clock_timestamp() - v_tp) * 1000;
      if v_plan = 'on' then v_plans := v_plans + 1; end if;
    end if;
    v_tq := clock_timestamp();   -- 0267: the quay asked for
    if p_commit then perform public.hold_the_quay(); end if;   -- 0249: never beside an arrivals beat
    v_th := clock_timestamp();   -- 0267: the quay granted
    perform set_config('byeharu.tend_planned', v_plan, true);   -- 0270: the plan pass's verdict for HER step
    -- 0269: what she was as her step began (a plain read of her route and fleet rows, no lock), and the step's clock
$h$),
('public.tick_reconcile(boolean)', 3,
$h$                             'quay', jsonb_build_object('tend', v_qt, 'companies', v_qc),   -- 0267
                             'tend_holds', v_holds))   -- 0269
$h$,
$h$                             'quay', jsonb_build_object('tend', v_qt, 'companies', v_qc),   -- 0267
                             'tend_holds', v_holds,   -- 0269
                             'tend_plan', jsonb_build_object('n', v_plans, 'ms', round(v_plan_ms))))   -- 0270
$h$);

-- THE OLD BODY, a temp copy for the probes (renamed only)
do $$
declare
  v text;
begin
  v := (select def from defs_before_0270 where fn = 'public.npc_tend_route(timestamptz,uuid,uuid,bigint)');
  if pg_temp.occurs_0270(v, 'CREATE OR REPLACE FUNCTION public.npc_tend_route(') <> 1 then
    raise exception '0270 self-assert FAIL: the live npc_tend_route does not open as this file expects';
  end if;
  execute replace(v, 'CREATE OR REPLACE FUNCTION public.npc_tend_route(',
                     'CREATE FUNCTION pg_temp.npc_tend_route_old_0270(');
end $$;

-- THE HUNKS, each once, then the new bodies
do $$
declare
  d   record;
  h   record;
  v_def text;
  v_n int;
begin
  for d in select * from defs_before_0270 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0270 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0270(v_def, h.old);
      if v_n <> 1 then
        raise exception '0270 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 3. THE PROBES' EYES ─────────────────────────────────────────────────────────────────────────
-- a merchant's rows after a run (uuids blanked: new rows carry new ones) — 0269's
create function pg_temp.digest_0270(p_fleet uuid, p_route uuid, p_house uuid)
returns text
language sql
as $$
select regexp_replace(concat_ws(' # ',
  (select (to_jsonb(sr) - 'id')::text from public.standing_routes sr where sr.id = p_route),
  (select string_agg((to_jsonb(s) - 'id')::text, ',' order by s.ord) from public.standing_route_stops s where s.route_id = p_route),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(l) - 'id')::text as x from public.standing_route_lines l
     where l.route_id = p_route) a),
  (select string_agg((to_jsonb(x) - 'id')::text, ',' order by x.lap_no) from public.standing_route_laps x where x.route_id = p_route),
  (select string_agg((to_jsonb(o) - 'id')::text, ',' order by o.seq) from public.orders o where o.fleet_id = p_fleet),
  (select to_jsonb(f)::text from public.fleets f where f.id = p_fleet),
  (select string_agg(to_jsonb(s)::text, ',' order by s.id) from public.ships s where s.fleet_id = p_fleet),
  (select string_agg((to_jsonb(v) - 'id')::text, ',' order by v.departed_at) from public.voyages v where v.fleet_id = p_fleet),
  (select to_jsonb(p)::text from public.players p where p.id = p_house),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(l) - 'id')::text as x from public.ledger l
     where l.player_id = p_house and l.created_at >= now()) a),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(e) - 'id')::text as x from public.events e
     where e.player_id = p_house and e.created_at >= now()) a),
  (select md5(string_agg(to_jsonb(g)::text, ',' order by g.good_id)) from public.port_goods g
     where g.port_id = (select f.port_id from public.fleets f where f.id = p_fleet)),
  (select to_jsonb(t)::text from public.port_treasury t where t.port_id = (select f.port_id from public.fleets f where f.id = p_fleet))
  ), '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g')
$$;

-- ── 4. PROBE 1: HER STEP, OLD vs NEW vs THE PLAN PASS + THE STEP (rolled back) ───────────────────
-- Up to 6 merchants the clear branch can reach at all: a docked hull, a route with stops, no failed order of her
-- own (the probe plants one). Her route is started by pg_temp.prep_0270 — the chain's fresh world leaves
-- every route unstarted, and prod's running merchants are already started (the prep then does nothing). Three
-- cases per merchant: a first clear (no plan), the clear that makes three (plan), a SAIL refused E_ENDURANCE (plan).
create temp table sample_0270 on commit drop as
select r.route_id, r.fleet_id, r.player_id, r.k
  from public.npc_tend_roster() r
  join public.fleets f on f.id = r.fleet_id
 where f.status = 'DOCKED'
   and exists (select 1 from public.standing_route_stops s where s.route_id = r.route_id)
   and not exists (select 1 from public.orders o where o.fleet_id = r.fleet_id and o.status = 'failed')
   and r.route_id not in (select q.route_id from public.npc_waiting_queue(now()) q
                           where not q.overdue and q.route_id is not null)
 order by r.k
 limit 6;

-- The clear's state, put on a merchant the probe picked: traders on, her fleet on her route, no pause. Rolled back
-- with the case's own transaction, so the world it is applied to keeps her as she was.
create function pg_temp.prep_0270(p_fleet uuid, p_route uuid, p_house uuid)
returns void
language plpgsql
as $$
declare
  v_res jsonb;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
  if (select sr.fleet_id from public.standing_routes sr where sr.id = p_route) is distinct from p_fleet
     or (select sr.paused_reason from public.standing_routes sr where sr.id = p_route) is not null then
    v_res := cmd.standing_route_assign_for(p_house, p_route, p_fleet);
    if not coalesce((v_res->>'ok')::boolean, false) then
      raise exception '0270 probe: her route could not be started for the clear — %', v_res;
    end if;
  end if;
end $$;

create function pg_temp.tend_case_0270(p_mode text, p_fleet uuid, p_route uuid, p_house uuid, p_k bigint,
                                       p_error text, p_clears int)
returns jsonb
language plpgsql
as $$
declare
  v_r    jsonb;
  v_plan text := 'off';
  v_seq  int;
  v_lap  int;
  v_base int;
  v_plant int;
  v_due  jsonb;
  i      int;
begin
  begin
    perform pg_temp.prep_0270(p_fleet, p_route, p_house);
    select sr.lap_no into v_lap from public.standing_routes sr where sr.id = p_route;
    select count(*) into v_base
      from public.events ev
     where ev.player_id = p_house and ev.kind = 'NPC_CLEARED'
       and ev.payload->>'route_id' = p_route::text and (ev.payload->>'lap_no')::int = v_lap;
    -- p_clears = -1 means "make this the third clear of her lap", whatever her lap already carries
    v_plant := case when p_clears < 0 then greatest(3 - (v_base + 1), 0) else p_clears end;
    for i in 1 .. v_plant loop
      insert into public.events (player_id, kind, payload)
      values (p_house, 'NPC_CLEARED', jsonb_build_object('route_id', p_route, 'lap_no', v_lap, 'n', v_base + i));
    end loop;
    select coalesce(max(o.seq), 0) + 1 into v_seq from public.orders o where o.fleet_id = p_fleet;
    insert into public.orders (fleet_id, player_id, seq, raw_text, verb, status, error_code, error_message)
    values (p_fleet, p_house, v_seq, 'SAIL', 'SAIL', 'failed', p_error, 'probe');
    -- the rule, on the planted state: the self-assert holds it against its own count
    v_due := public.npc_clear_due(p_house, p_route, v_lap, 'SAIL', p_error);
    if p_mode = 'old' then
      v_r := pg_temp.npc_tend_route_old_0270(now(), p_fleet, p_route, p_k);
    elsif p_mode = 'new' then
      v_r := public.npc_tend_route(now(), p_fleet, p_route, p_k);
    else   -- 'pass': the plan pass, then her step — the job's two transactions, here in one (the rows are the claim)
      perform set_config('byeharu.tend_plan_pass', 'on', true);
      perform set_config('byeharu.tend_planned', 'off', true);
      perform public.npc_tend_route(now(), p_fleet, p_route, p_k);
      v_plan := coalesce(current_setting('byeharu.tend_planned', true), 'off');
      perform set_config('byeharu.tend_plan_pass', 'off', true);
      perform set_config('byeharu.tend_planned', v_plan, true);
      v_r := public.npc_tend_route(now(), p_fleet, p_route, p_k);
    end if;
    raise exception using errcode = 'ZY270', message = jsonb_build_object(
      'receipt', v_r, 'planned', v_plan, 'due', v_due, 'base', v_base, 'planted', v_plant,
      'digest', pg_temp.digest_0270(p_fleet, p_route, p_house))::text;
  exception when sqlstate 'ZY270' then
    return sqlerrm::jsonb;
  end;
end $$;

-- ── 5. PROBE 2: THE HOURLY LOOP, OLD vs NEW (rolled back), the same cuts as 0269's ──────────────
create function pg_temp.reconcile_copy_0270(p_def text, p_name text)
returns void
language plpgsql
as $$
declare
  v text := p_def;
  s record;
begin
  for s in select * from (values
    (1, 'CREATE OR REPLACE PROCEDURE public.tick_reconcile(', 'CREATE PROCEDURE pg_temp.' || p_name || '('),
    (2, 'for r in select * from public.npc_tend_roster() loop',
        'for r in select x.* from public.npc_tend_roster() x where x.route_id in (select s.route_id from pg_temp.sample_0270 s) loop'),
    (3, 'for h in select ir.player_id from public.npc_invest_roster() ir loop',
        'for h in select ir.player_id from public.npc_invest_roster() ir where false loop'),
    (4, 'for h in select gr.player_id from public.capital_gift_roster(v_now) gr loop',
        'for h in select gr.player_id from public.capital_gift_roster(v_now) gr where false loop'),
    (5, 'for r in select id from public.players loop',
        'for r in select id from public.players where id in (select s.player_id from pg_temp.sample_0270 s) loop')) t(n, a, b) loop
    if pg_temp.occurs_0270(v, s.a) <> 1 then
      raise exception '0270 self-assert FAIL: the probe''s cut % does not occur once in the % body', s.n, p_name;
    end if;
    v := replace(v, s.a, s.b);
  end loop;
  execute v;
end $$;

select pg_temp.reconcile_copy_0270((select def from defs_before_0270 where fn = 'public.tick_reconcile(boolean)'),
                                   'reconcile_old_0270');
select pg_temp.reconcile_copy_0270(replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', ''),
                                   'reconcile_new_0270');

create function pg_temp.reconcile_case_0270(p_mode text)
returns jsonb
language plpgsql
as $$
declare
  v_rec  jsonb;
  v_seq  int;
  s      record;
begin
  begin
    -- one planted failed order (E_ENDURANCE: the plan pass must pick it up and plan) on the first sampled merchant,
    -- whose route the prep starts: the loop's clear branch is the road under test
    select x.* into s from pg_temp.sample_0270 x order by x.k limit 1;
    perform pg_temp.prep_0270(s.fleet_id, s.route_id, s.player_id);
    select coalesce(max(o.seq), 0) + 1 into v_seq from public.orders o where o.fleet_id = s.fleet_id;
    insert into public.orders (fleet_id, player_id, seq, raw_text, verb, status, error_code, error_message)
    values (s.fleet_id, s.player_id, v_seq, 'SAIL', 'SAIL', 'failed', 'E_ENDURANCE', 'probe');
    if p_mode = 'new' then
      call pg_temp.reconcile_new_0270(false);
    else
      call pg_temp.reconcile_old_0270(false);
    end if;
    v_rec := (select receipt from public.reconcile_runs where at = now());
    raise exception using errcode = 'ZY270', message = jsonb_build_object(
      'receipt', v_rec,
      'digest', (select string_agg(pg_temp.digest_0270(s2.fleet_id, s2.route_id, s2.player_id), ' ## ' order by s2.route_id)
                   from pg_temp.sample_0270 s2))::text;
  exception when sqlstate 'ZY270' then
    return sqlerrm::jsonb;
  end;
end $$;

-- ── 6. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b    record;
  v_d    record;
  v_h    record;
  v_pp   record;
  v_def  text;
  v_o    jsonb;
  v_n    jsonb;
  v_c    jsonb;
  v_p    jsonb;
  v_pp2  record;
  v_bad  int := 0;
  v_cases int := 0;
  v_plans int := 0;
  v_ro   jsonb;
  v_rn   jsonb;
  m      record;
  e      record;
  v_want text;
  v_cnt  record;
  v_base int;
begin
  select * into v_b from before_0270;

  -- (a) THE HUNKS reverse to the live pre-images; ACL / volatility / definer / config unmoved; nothing else moved
  for v_d in select * from defs_before_0270 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0270 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0270(v_def, v_h.new) <> 1 then
        raise exception '0270 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0270 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0270 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(k.fn::regprocedure), E'\r', '')), ',' order by k.fn)) from kept_0270 k)
     <> v_b.kept_md5 then
    raise exception '0270 self-assert FAIL: a function the two bodies decide with moved';
  end if;
  if (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
         and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%hold_the_quay()%') <> v_b.quay_takers then
    raise exception '0270 self-assert FAIL: the set of functions that take the quay changed';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points then
    raise exception '0270 self-assert FAIL: the client entry points changed';
  end if;

  -- (b) THE FIX'S OWN SHAPE: the plan pass runs BEFORE the quay in the loop, the verdict is set AFTER it, and the
  -- step's clear never re-plans under it. Text order, on the new bodies.
  v_def := replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', '');
  if position('public.npc_tend_route(v_now, r.fleet_id, r.route_id, r.k);' in v_def)
       > position('perform public.hold_the_quay();' in v_def)
     or position('perform set_config(''byeharu.tend_planned'', v_plan, true);' in v_def)
       < position('perform public.hold_the_quay();' in v_def) then
    raise exception '0270 self-assert FAIL: the plan pass does not stand before the quay, or its verdict after it';
  end if;
  if pg_temp.occurs_0270(v_def, 'byeharu.tend_plan_pass') < 2 or pg_temp.occurs_0270(v_def, 'byeharu.tend_planned') < 3 then
    raise exception '0270 self-assert FAIL: the loop does not carry both flags as this file writes them';
  end if;
  v_def := replace(pg_get_functiondef('public.npc_tend_route(timestamptz,uuid,uuid,bigint)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0270(v_def, 'v_due := public.npc_clear_due(') <> 1 then
    raise exception '0270 self-assert FAIL: the clear branch does not ask the one rule exactly once';
  end if;
  if pg_temp.occurs_0270(v_def, 'v_clears >= 3 or (fo.verb') <> 0 then
    raise exception '0270 self-assert FAIL: 0150''s rule is still written inside the clear branch';
  end if;
  if pg_temp.occurs_0270(v_def, 'v_plan_pass then continue;') <> 4 then
    raise exception '0270 self-assert FAIL: the plan pass does not stop before all four acting roads of her step';
  end if;

  -- (c) THE RULE: one place, and it says what 0150 said (a third clear plans, a SAIL refused E_ENDURANCE plans)
  if public.npc_clear_due('00000000-0000-0000-0000-000000000000'::uuid, '00000000-0000-0000-0000-000000000000'::uuid,
                          1, 'SAIL', 'E_ENDURANCE')->>'plan' <> 'true' then
    raise exception '0270 self-assert FAIL: E_ENDURANCE does not plan';
  end if;
  if public.npc_clear_due('00000000-0000-0000-0000-000000000000'::uuid, '00000000-0000-0000-0000-000000000000'::uuid,
                          1, 'SAIL', 'E_NO_CARGO')->>'plan' <> 'false' then
    raise exception '0270 self-assert FAIL: a first clear with no E_ENDURANCE plans';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where p.proname = 'npc_clear_due' and n.nspname = 'public') <> 1 then
    raise exception '0270 self-assert FAIL: the rule is not in one place';
  end if;

  -- (d) PROBE 1: OLD vs NEW vs OLD (control) vs the plan pass + the step, per merchant, three cases. The rule is
  -- held against the self-assert's OWN count of her lap's clears (not against itself): a first clear (no plan), the
  -- clear that makes three (plan), and a SAIL refused E_ENDURANCE (plan, whatever the count).
  if (select count(*) from pg_temp.sample_0270) < 1 then
    raise exception '0270 self-assert FAIL: no merchant the clear branch can reach — the probe proves nothing';
  end if;
  for m in select * from pg_temp.sample_0270 order by k loop
    for e in select * from (values ('E_NO_CARGO', 0), ('E_NO_CARGO', -1), ('E_ENDURANCE', 0)) c(err, clears) loop
      v_o := pg_temp.tend_case_0270('old', m.fleet_id, m.route_id, m.player_id, m.k, e.err, e.clears);
      v_n := pg_temp.tend_case_0270('new', m.fleet_id, m.route_id, m.player_id, m.k, e.err, e.clears);
      v_c := pg_temp.tend_case_0270('old', m.fleet_id, m.route_id, m.player_id, m.k, e.err, e.clears);
      v_p := pg_temp.tend_case_0270('pass', m.fleet_id, m.route_id, m.player_id, m.k, e.err, e.clears);
      v_cases := v_cases + 1;
      if (v_o->'due'->>'n')::int <> (v_o->>'base')::int + (v_o->>'planted')::int + 1
         or (v_o->'due'->>'plan')::boolean <> (((v_o->>'base')::int + (v_o->>'planted')::int + 1) >= 3
                                               or e.err = 'E_ENDURANCE') then
        raise exception '0270 self-assert FAIL: the rule says % where her lap says % (merchant %, case %)',
          v_o->'due', jsonb_build_object('n', (v_o->>'base')::int + (v_o->>'planted')::int + 1,
                                         'plan', ((v_o->>'base')::int + (v_o->>'planted')::int + 1) >= 3 or e.err = 'E_ENDURANCE'),
          m.route_id, e.err;
      end if;
      if v_o->>'digest' is distinct from v_c->>'digest' or v_o->>'receipt' is distinct from v_c->>'receipt' then
        raise exception '0270 self-assert FAIL: the control moved (old against old), merchant %: % / %', m.route_id, left(v_o::text, 800), left(v_c::text, 800);
      end if;
      if v_o->>'digest' is distinct from v_n->>'digest' then
        raise exception '0270 self-assert FAIL: old and new leave different rows, merchant %, case %: % / %', m.route_id, e.err, left(v_o->>'digest', 1200), left(v_n->>'digest', 1200);
      end if;
      if v_o->>'receipt' is distinct from v_n->>'receipt' then
        raise exception '0270 self-assert FAIL: old and new answer differently, merchant %, case %: % / %', m.route_id, e.err, v_o->>'receipt', v_n->>'receipt';
      end if;
      if v_p->>'digest' is distinct from v_n->>'digest' or v_p->>'receipt' is distinct from v_n->>'receipt' then
        raise exception '0270 self-assert FAIL: the plan pass + her step differ from her step, merchant %, case %: % / %', m.route_id, e.err, left(v_p::text, 1200), left(v_n::text, 1200);
      end if;
      -- the plan pass may fall back to her step (a busy or raised plan: her step then plans for herself, as before);
      -- what it must never do is plan where the rule says no
      if v_p->>'planned' = 'on' and not (v_p->'due'->>'plan')::boolean then
        raise exception '0270 self-assert FAIL: the plan pass planned where the rule says no (merchant %, case %)', m.route_id, e.err;
      end if;
      if v_p->>'planned' = 'on' then v_plans := v_plans + 1; end if;
    end loop;
  end loop;

  -- (e) PROBE 2: the hourly loop, OLD vs NEW, same cuts; the new tally counted, the rest identical
  v_ro := pg_temp.reconcile_case_0270('old');
  v_rn := pg_temp.reconcile_case_0270('new');
  if (v_ro->>'digest') is distinct from (v_rn->>'digest') then
    raise exception '0270 self-assert FAIL: the loop leaves different rows: % / %', left(v_ro->>'digest', 1200), left(v_rn->>'digest', 1200);
  end if;
  if ((v_ro->'receipt') - array['ms', 'quay', 'tend_holds'])
     is distinct from ((v_rn->'receipt') - array['ms', 'quay', 'tend_holds', 'tend_plan']) then
    raise exception '0270 self-assert FAIL: the loop''s receipts differ: % / %', left((v_ro->'receipt')::text, 1500), left((v_rn->'receipt')::text, 1500);
  end if;
  if ((v_ro->'receipt')->'tend_plan') is not null then
    raise exception '0270 self-assert FAIL: the old loop already carries the new tally';
  end if;
  if coalesce(((v_rn->'receipt')->'tend_plan'->>'n')::int, 0) < 1
     and coalesce(((v_rn->'receipt')->'merchant_upkeep'->'tend'->>'busy')::int, 0) = 0
     and coalesce(((v_rn->'receipt')->'merchant_upkeep'->'tend'->>'failed')::int, 0) = 0 then
    raise exception '0270 self-assert FAIL: the loop planned nothing and no merchant was busy or failed: %',
      (v_rn->'receipt')->'tend_plan';
  end if;

  raise notice '0270 self-assert ok: A MERCHANT''S CLEAR RE-PLANS HER LINES BEFORE THE QUAY. npc_tend_route and tick_reconcile reverse to their pre-images hunk by hunk, ACLs unmoved, the functions both decide with and the quay takers unmoved; 0150''s rule in public.npc_clear_due alone. Probes: % step cases on % merchants (old = new = control, and the plan pass + the step = the step), % planning cases; the hourly loop old vs new, % plan(s) counted. Rolled back.',
    v_cases, (select count(*) from pg_temp.sample_0270), v_plans, ((v_rn->'receipt')->'tend_plan'->>'n')::int;
end $$;

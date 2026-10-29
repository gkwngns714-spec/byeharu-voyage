-- 0274 — HER CLEAR'S ACTING RUNS BEFORE THE QUAY  (the tend step's longest hold leaves the quay)
--
-- THE ROOT, measured on prod (2026-10-29 09-12 UTC read, head 0272, docs/prodcheck-2026-10-29/quay-holds.md):
-- every tend hold over 100 ms in the four hours is a clear, except one 255 ms tow. A cleared merchant's
-- step holds the quay 63.7-508.8 ms (median 176.2 ms), 24.4 % of the tend phase's quay-held time
-- (3,538 of 14,495 ms), because after the NPC_CLEARED count her step runs cmd.clear_for and cmd.advance
-- under public.hold_the_quay(): the advance executes her whole pending queue — priced SELL/BUY, PROVISION,
-- HIRE, SAIL — and, when the queue runs dry, 0092's refill renders and executes the next stop (9-14 orders
-- at the clear's own timestamp). The :07 lap-start lag is a queue, not a sum of holds (its p95 now equals
-- the other minutes'), so this is the next measured root, not the whole lag.
--
-- THE FIX (0266/0270's pattern): a CLEAR PASS mode of public.npc_tend_route — the same function walks the
-- same gates, and at the clear branch (after the 0114 budget check and public.npc_clear_due) performs the
-- clear's acting exactly as the step does — the one NPC_CLEARED event with the same n, the step's
-- conditional plan, cmd.clear_for, cmd.advance — sets byeharu.tend_cleared = 'on' and continues; nothing
-- else acts. public.tick_reconcile runs it in its own transaction, after the plan pass and before the
-- quay, for the merchants a failed order makes clearable (the same test the plan pass uses); after the
-- quay it sets the pass's verdict for her step, which then skips the clear branch's acting and every
-- acting road and only counts. A pass that raises or cannot take her rows leaves the verdict 'off' and
-- her step clears inline exactly as today (0270's fallback shape).
--
-- ORDER AND LOCKS (0265/0267, unmoved). The clear pass takes her fleet and route rows NOWAIT at the
-- function's head (as her step does), never takes the quay, runs under public.npc_upkeep_scope (2 s
-- lock_timeout, 0114's deadline) and commits before her step's transaction opens. The set of functions
-- that take the quay is unchanged.
--
-- WHAT DOES NOT MOVE. The clear's acting: the same calls, the same order, the same n — every gate keeps
-- ONE copy (the pass is the same function, not a second reading of the rules). The budget (0114) is read
-- at her step's head, which is now the clear pass — one reading per merchant, before the dear work, as
-- before. npc_tend (the one-transaction door) never sets the flags and behaves as before.
--
-- THE PROOF (all rolled back, on the world this is applied to): every hunk occurs once and reverses to
-- its pre-image; ACL / volatility / definer / config and the functions both bodies decide with are
-- unmoved; the quay takers are the same set. Her step OLD vs NEW vs OLD again (control), then the plan
-- pass + the clear pass + her step, on up to 6 merchants with planted failed orders: a first clear
-- (E_NO_CARGO), the third clear of her lap, E_ENDURANCE, E_CREW_SHORT — the rows digest and the receipt
-- identical, and the clear pass acts only where her step would. Then a spent-budget case (0114 defers in
-- the pass and in her step, exactly as her step deferred alone) and a raised-pass case (the verdict goes
-- 'off' and her step clears inline, same digest, same receipt). Then the hourly loop OLD vs NEW with
-- 0269/0270's cuts: the same rows and the same receipt apart from the new tally, and both passes counted.
--
-- PROD CHECKS (before the push; read-only; in the PR body): md5 of the two live bodies' prosrc equals the
-- md5 below (the bodies the hunks were cut against), and receipt.tend_clear will show the pass's own cost
-- from the deploy's next :07 on — expect no tend hold over ~10 ms from a cleared step, and
-- receipt.quay.tend's held_ms to fall by the clears' share (~0.36-1.47 s an hour).
--
-- SUPERSEDE (supabase/migrations/README.md:43-48). This file re-cuts TWO live functions, by hunks sliced
-- from their bodies (each hunk asserts it occurs exactly once and reverses to its pre-image):
--   * public.npc_tend_route(timestamptz, uuid, uuid, bigint) — 0137's body, as last re-cut by 0270;
--   * public.tick_reconcile(boolean) — 0137's body, as last re-cut by 0270.
-- It is a no-op for every caller that does not set the clear-pass flags — public.npc_tend (0137) and every
-- proof: without them v_clear_pass and v_cleared_flag are false and the clear branch acts exactly as it
-- did. Everything that must move together moves in this one file: the flag, the clear-pass mode, the loop
-- that sets them, and its tally.
--
-- VERSION: 0274 (prod head 0272; the chain's 0273 must not have re-cut these two bodies).

-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.npc_clear_due(uuid,uuid,int,text,text)') is null
     or to_regprocedure('public.npc_tend_route(timestamptz,uuid,uuid,bigint)') is null
     or to_regprocedure('public.tick_reconcile(boolean)') is null then
    raise exception '0274 refuses: 0270 (and 0272''s rule) are not in this world';
  end if;
  if pg_get_functiondef('public.npc_tend_route(timestamptz,uuid,uuid,bigint)'::regprocedure)
       like '%byeharu.tend_clear_pass%' then
    raise exception '0274 refuses: the clear pass already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0274(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0274 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.npc_tend_route(timestamptz,uuid,uuid,bigint)'),
               ('public.tick_reconcile(boolean)')) f(fn);

-- the functions the two bodies decide with: not one of them may move in this file
create temp table kept_0274 (fn text) on commit drop;
insert into kept_0274 (fn) values
  ('public.npc_clear_due(uuid,uuid,int,text,text)'),
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

create temp table before_0274 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(md5(replace(pg_get_functiondef(k.fn::regprocedure), E'\r', '')), ',' order by k.fn))
          from kept_0274 k) as kept_md5,
       (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
           and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%hold_the_quay()%') as quay_takers,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%') as fns;

-- ── 1. THE HUNKS ────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0274 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0274 (fn, n, old, new) values
-- ── npc_tend_route ──
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 1,
$h$  v_planned   boolean := coalesce(current_setting('byeharu.tend_planned', true), '') = 'on';
  v_due       jsonb;
$h$,
$h$  v_planned   boolean := coalesce(current_setting('byeharu.tend_planned', true), '') = 'on';
  -- 0274: HER CLEAR'S ACTING LEAVES THE QUAY (0266/0270's pattern). The step's whole clear — the
  -- NPC_CLEARED event, cmd.clear_for and cmd.advance, 63.7-508.8 ms on prod, 24.4 % of the tend phase's
  -- quay-held time (2026-10-29) — runs first in the clear pass (byeharu.tend_clear_pass: the gates below
  -- walked, the clear's acting, nothing else), in its own transaction before the quay; her step then does
  -- the clear without acting (byeharu.tend_cleared).
  v_clear_pass   boolean := coalesce(current_setting('byeharu.tend_clear_pass', true), '') = 'on';
  v_cleared_flag boolean := coalesce(current_setting('byeharu.tend_cleared', true), '') = 'on';
  v_due       jsonb;
$h$),
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 2,
$h$        if v_plan_pass then continue; end if;   -- 0270: the plan pass never pauses her: her step's road is not the clear
$h$,
$h$        if v_plan_pass or v_clear_pass then continue; end if;   -- 0274: neither pass pauses her
$h$),
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 3,
$h$        if v_plan_pass then continue; end if;   -- 0270: the plan pass never tows her: a wreck in port is not the clear
$h$,
$h$        if v_plan_pass or v_clear_pass then continue; end if;   -- 0274: neither pass tows her
$h$),
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 4,
$h$        if v_plan_pass then continue; end if;   -- 0270: the plan pass never assigns her loop
$h$,
$h$        if v_plan_pass or v_clear_pass then continue; end if;   -- 0274: neither pass assigns her loop
$h$),
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 5,
$h$        if v_plan_pass then continue; end if;   -- 0270: the plan pass never plans, starts or resumes her here
$h$,
$h$        if v_plan_pass or v_clear_pass then continue; end if;   -- 0274: neither pass plans, starts or resumes her
$h$),
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 6,
$h$        end if;
        v_clears := (v_due->>'n')::int;
$h$,
$h$        end if;
        -- 0274: THE CLEAR PASS: her clear's acting, outside the quay, and nothing else of her step is
        -- walked — the same calls her step would make, in the same order; her plan came from the plan
        -- pass when it ran, and when it did not the plan here is her step's own, taken outside the quay.
        if v_clear_pass then
          v_clears := (v_due->>'n')::int;
          perform public.emit_event(sr.player_id, 'NPC_CLEARED', jsonb_build_object(
            'route', sr.name, 'route_id', sr.id, 'lap_no', sr.lap_no, 'fleet', f.name,
            'code', fo.error_code, 'line', fo.raw_text, 'n', v_clears));
          if (v_due->>'plan')::boolean and not v_planned then
            perform public.npc_plan(p_now, sr.id);
          end if;
          perform cmd.clear_for(sr.player_id, r.fleet_id, false);
          perform cmd.advance(r.fleet_id, p_now);
          perform set_config('byeharu.tend_cleared', 'on', true);
          continue;
        end if;
        v_clears := (v_due->>'n')::int;
$h$),
('public.npc_tend_route(timestamptz,uuid,uuid,bigint)', 7,
$h$      -- THE HALT LAW'S RELEASE, counted: clears with no lap closed between share her lap number.
      select * into fo from public.orders where fleet_id = r.fleet_id and status = 'failed' order by seq limit 1;
$h$,
$h$      -- 0274: her clear already happened in the clear pass; her step counts it and stops — the failed
      -- order is gone with the clear (cmd.clear_for cancelled it, and her advance may have sailed her),
      -- so this stands BEFORE the halt law's read of it, on the road the pass itself took.
      if v_cleared_flag then
        v_cleared := v_cleared + 1;
        continue;
      end if;
      -- THE HALT LAW'S RELEASE, counted: clears with no lap closed between share her lap number.
      select * into fo from public.orders where fleet_id = r.fleet_id and status = 'failed' order by seq limit 1;
$h$),
-- ── tick_reconcile ──
('public.tick_reconcile(boolean)', 1,
$h$  -- 0270: her clear's re-plan off the quay (the plan pass), its verdict for her step, and its tally
  v_plan     text;
  v_tp       timestamptz;
  v_plans    int := 0;
  v_plan_ms  numeric := 0;
$h$,
$h$  -- 0270: her clear's re-plan off the quay (the plan pass), its verdict for her step, and its tally
  v_plan     text;
  v_tp       timestamptz;
  v_plans    int := 0;
  v_plan_ms  numeric := 0;
  -- 0274: her clear's acting off the quay (the clear pass), its verdict for her step, and its tally
  v_clear    text;
  v_tx       timestamptz;
  v_cleared  int := 0;
  v_clear_ms numeric := 0;
$h$),
('public.tick_reconcile(boolean)', 2,
$h$    v_tq := clock_timestamp();   -- 0267: the quay asked for
    if p_commit then perform public.hold_the_quay(); end if;   -- 0249: never beside an arrivals beat
$h$,
$h$    -- 0274: HER CLEAR'S ACTING RUNS OUTSIDE THE QUAY (0266/0270's pattern). A failed order is the only
    -- road to her step's clear branch, whose acting is the NPC_CLEARED event, cmd.clear_for and
    -- cmd.advance — 63.7-508.8 ms on prod, 24.4 % of the tend phase's quay-held time (2026-10-29). Such a
    -- merchant is walked by the clear pass — public.npc_tend_route in its clear-pass mode: her gates, then
    -- the clear's acting, and nothing else — in its own transaction, after the plan pass and before the
    -- quay. Her step then runs as before and does not act (byeharu.tend_cleared).
    v_clear := 'off';
    if exists (select 1 from public.orders o where o.fleet_id = r.fleet_id and o.status = 'failed') then
      v_tx := clock_timestamp();
      begin
        perform set_config('byeharu.tend_clear_pass', 'on', true);
        perform set_config('byeharu.tend_cleared', 'off', true);
        perform set_config('byeharu.tend_planned', v_plan, true);   -- 0270's verdict, re-set after its commit
        perform public.npc_upkeep_scope(v_deadline);
        perform public.npc_tend_route(v_now, r.fleet_id, r.route_id, r.k);
        v_clear := coalesce(current_setting('byeharu.tend_cleared', true), 'off');
      exception when others then
        v_clear := 'off';   -- her step clears for herself, as before
      end;
      perform set_config('byeharu.tend_clear_pass', 'off', true);
      if p_commit then commit; end if;
      v_clear_ms := v_clear_ms + extract(epoch from clock_timestamp() - v_tx) * 1000;
      if v_clear = 'on' then v_cleared := v_cleared + 1; end if;
    end if;
    v_tq := clock_timestamp();   -- 0267: the quay asked for
    if p_commit then perform public.hold_the_quay(); end if;   -- 0249: never beside an arrivals beat
$h$),
('public.tick_reconcile(boolean)', 3,
$h$    perform set_config('byeharu.tend_planned', v_plan, true);   -- 0270: the plan pass's verdict for HER step
$h$,
$h$    perform set_config('byeharu.tend_planned', v_plan, true);   -- 0270: the plan pass's verdict for HER step
    perform set_config('byeharu.tend_cleared', v_clear, true);   -- 0274: the clear pass's verdict for HER step
$h$),
('public.tick_reconcile(boolean)', 4,
$h$                             'tend_plan', jsonb_build_object('n', v_plans, 'ms', round(v_plan_ms))))   -- 0270
$h$,
$h$                             'tend_plan', jsonb_build_object('n', v_plans, 'ms', round(v_plan_ms)),   -- 0270
                             'tend_clear', jsonb_build_object('n', v_cleared, 'ms', round(v_clear_ms))))   -- 0274
$h$);

-- THE OLD BODY, a temp copy for the probes (renamed only)
do $$
declare
  v text;
begin
  v := (select def from defs_before_0274 where fn = 'public.npc_tend_route(timestamptz,uuid,uuid,bigint)');
  if pg_temp.occurs_0274(v, 'CREATE OR REPLACE FUNCTION public.npc_tend_route(') <> 1 then
    raise exception '0274 self-assert FAIL: the live npc_tend_route does not open as this file expects';
  end if;
  execute replace(v, 'CREATE OR REPLACE FUNCTION public.npc_tend_route(',
                     'CREATE FUNCTION pg_temp.npc_tend_route_old_0274(');
end $$;

-- THE HUNKS, each once, then the new bodies
do $$
declare
  d   record;
  h   record;
  v_def text;
  v_n int;
begin
  for d in select * from defs_before_0274 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0274 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0274(v_def, h.old);
      if v_n <> 1 then
        raise exception '0274 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 2. THE PROBES' EYES ─────────────────────────────────────────────────────────────────────────
-- a merchant's rows after a run (uuids blanked: new rows carry new ones) — 0269's
create function pg_temp.digest_0274(p_fleet uuid, p_route uuid, p_house uuid)
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

-- ── 3. PROBE 1: HER STEP, OLD vs NEW vs THE PLAN PASS + THE CLEAR PASS + THE STEP (rolled back) ───
-- Up to 6 merchants the clear branch can reach at all: a docked hull, a route with stops, no failed order of
-- her own (the probe plants one). Her route is started by pg_temp.prep_0274 — the chain's fresh world leaves
-- every route unstarted, and prod's running merchants are already started (the prep then does nothing). Five
-- cases per merchant: a first clear (no plan), the third clear (plan), E_ENDURANCE (plan), E_CREW_SHORT (plan,
-- 0272's clause); then a spent-budget case and a raised-pass case. Rolled back with the case's own transaction.
create temp table sample_0274 on commit drop as
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
create function pg_temp.prep_0274(p_fleet uuid, p_route uuid, p_house uuid)
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
      raise exception '0274 probe: her route could not be started for the clear — %', v_res;
    end if;
  end if;
end $$;

create function pg_temp.tend_case_0274(p_mode text, p_fleet uuid, p_route uuid, p_house uuid, p_k bigint,
                                       p_error text, p_clears int, p_deadline timestamptz default null)
returns jsonb
language plpgsql
as $$
declare
  v_r      jsonb;
  v_plan   text := 'off';
  v_clear  text := 'off';
  v_raised boolean := false;
  v_seq    int;
  v_lap    int;
  v_base   int;
  v_plant  int;
  v_due    jsonb;
  i        int;
begin
  begin
    perform pg_temp.prep_0274(p_fleet, p_route, p_house);
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
      if p_deadline is not null then perform public.npc_upkeep_scope(p_deadline); end if;
      v_r := pg_temp.npc_tend_route_old_0274(now(), p_fleet, p_route, p_k);
    elsif p_mode = 'new' then
      if p_deadline is not null then perform public.npc_upkeep_scope(p_deadline); end if;
      v_r := public.npc_tend_route(now(), p_fleet, p_route, p_k);
    elsif p_mode = 'pass' then
      -- the job's two passes, then her step — its three transactions, here in one (the rows are the claim)
      perform public.npc_upkeep_scope(coalesce(p_deadline, now() + interval '1 hour'));
      perform set_config('byeharu.tend_plan_pass', 'on', true);
      perform set_config('byeharu.tend_planned', 'off', true);
      perform public.npc_tend_route(now(), p_fleet, p_route, p_k);
      v_plan := coalesce(current_setting('byeharu.tend_planned', true), 'off');
      perform set_config('byeharu.tend_plan_pass', 'off', true);
      perform set_config('byeharu.tend_planned', v_plan, true);
      perform set_config('byeharu.tend_clear_pass', 'on', true);
      perform set_config('byeharu.tend_cleared', 'off', true);
      perform public.npc_tend_route(now(), p_fleet, p_route, p_k);
      v_clear := coalesce(current_setting('byeharu.tend_cleared', true), 'off');
      perform set_config('byeharu.tend_clear_pass', 'off', true);
      perform set_config('byeharu.tend_cleared', v_clear, true);
      v_r := public.npc_tend_route(now(), p_fleet, p_route, p_k);
    else   -- 'raised': the plan pass, then a clear pass that RAISES (the block is tick_reconcile's own shape,
           -- and its raise stands in for any pass-level raise on prod: a statement_timeout, a deadlock, a
           -- cancel — the catch, the rollback of the pass's acting and the 'off' verdict are the real ones)
      perform public.npc_upkeep_scope(now() + interval '1 hour');
      perform set_config('byeharu.tend_plan_pass', 'on', true);
      perform set_config('byeharu.tend_planned', 'off', true);
      perform public.npc_tend_route(now(), p_fleet, p_route, p_k);
      v_plan := coalesce(current_setting('byeharu.tend_planned', true), 'off');
      perform set_config('byeharu.tend_plan_pass', 'off', true);
      perform set_config('byeharu.tend_planned', v_plan, true);
      begin
        perform set_config('byeharu.tend_clear_pass', 'on', true);
        perform set_config('byeharu.tend_cleared', 'off', true);
        perform public.npc_upkeep_scope(now() + interval '1 hour');
        perform public.npc_tend_route(now(), p_fleet, p_route, p_k);
        raise exception '0274 probe: the clear pass raised (as a statement_timeout would on prod)'
          using errcode = 'P0001';
      exception when others then
        v_clear := 'off';   -- her step clears for herself, as before
        v_raised := true;
      end;
      perform set_config('byeharu.tend_clear_pass', 'off', true);
      perform set_config('byeharu.tend_cleared', v_clear, true);
      v_r := public.npc_tend_route(now(), p_fleet, p_route, p_k);
    end if;
    raise exception using errcode = 'ZY274', message = jsonb_build_object(
      'receipt', v_r, 'planned', v_plan, 'cleared', v_clear, 'raised', v_raised,
      'due', v_due, 'base', v_base, 'planted', v_plant,
      'digest', pg_temp.digest_0274(p_fleet, p_route, p_house))::text;
  exception when sqlstate 'ZY274' then
    return sqlerrm::jsonb;
  end;
end $$;

-- ── 4. PROBE 2: THE HOURLY LOOP, OLD vs NEW (rolled back), the same cuts as 0269/0270's ──────────
create function pg_temp.reconcile_copy_0274(p_def text, p_name text)
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
        'for r in select x.* from public.npc_tend_roster() x where x.route_id in (select s.route_id from pg_temp.sample_0274 s) loop'),
    (3, 'for h in select ir.player_id from public.npc_invest_roster() ir loop',
        'for h in select ir.player_id from public.npc_invest_roster() ir where false loop'),
    (4, 'for h in select gr.player_id from public.capital_gift_roster(v_now) gr loop',
        'for h in select gr.player_id from public.capital_gift_roster(v_now) gr where false loop'),
    (5, 'for r in select id from public.players loop',
        'for r in select id from public.players where id in (select s.player_id from pg_temp.sample_0274 s) loop')) t(n, a, b) loop
    if pg_temp.occurs_0274(v, s.a) <> 1 then
      raise exception '0274 self-assert FAIL: the probe''s cut % does not occur once in the % body', s.n, p_name;
    end if;
    v := replace(v, s.a, s.b);
  end loop;
  execute v;
end $$;

select pg_temp.reconcile_copy_0274((select def from defs_before_0274 where fn = 'public.tick_reconcile(boolean)'),
                                   'reconcile_old_0274');
select pg_temp.reconcile_copy_0274(replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', ''),
                                   'reconcile_new_0274');

create function pg_temp.reconcile_case_0274(p_mode text)
returns jsonb
language plpgsql
as $$
declare
  v_rec  jsonb;
  v_seq  int;
  s      record;
begin
  begin
    -- one planted failed order (E_ENDURANCE: both passes must pick it up) on the first sampled merchant,
    -- whose route the prep starts: the loop's clear branch is the road under test
    select x.* into s from pg_temp.sample_0274 x order by x.k limit 1;
    perform pg_temp.prep_0274(s.fleet_id, s.route_id, s.player_id);
    select coalesce(max(o.seq), 0) + 1 into v_seq from public.orders o where o.fleet_id = s.fleet_id;
    insert into public.orders (fleet_id, player_id, seq, raw_text, verb, status, error_code, error_message)
    values (s.fleet_id, s.player_id, v_seq, 'SAIL', 'SAIL', 'failed', 'E_ENDURANCE', 'probe');
    if p_mode = 'new' then
      call pg_temp.reconcile_new_0274(false);
    else
      call pg_temp.reconcile_old_0274(false);
    end if;
    v_rec := (select receipt from public.reconcile_runs where at = now());
    raise exception using errcode = 'ZY274', message = jsonb_build_object(
      'receipt', v_rec,
      'digest', (select string_agg(pg_temp.digest_0274(s2.fleet_id, s2.route_id, s2.player_id), ' ## ' order by s2.route_id)
                   from pg_temp.sample_0274 s2))::text;
  exception when sqlstate 'ZY274' then
    return sqlerrm::jsonb;
  end;
end $$;

-- ── 5. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
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
  v_s    jsonb;
  v_r1   jsonb;
  v_r2   jsonb;
  v_ro   jsonb;
  v_rn   jsonb;
  m      record;
  e      record;
  v_cases int := 0;
  v_plans int := 0;
begin
  select * into v_b from before_0274;

  -- (a) THE HUNKS reverse to the live pre-images; ACL / volatility / definer / config unmoved; nothing else moved
  for v_d in select * from defs_before_0274 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0274 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0274(v_def, v_h.new) <> 1 then
        raise exception '0274 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0274 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0274 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(k.fn::regprocedure), E'\r', '')), ',' order by k.fn)) from kept_0274 k)
     <> v_b.kept_md5 then
    raise exception '0274 self-assert FAIL: a function the two bodies decide with moved';
  end if;
  if (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
         and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%hold_the_quay()%') <> v_b.quay_takers then
    raise exception '0274 self-assert FAIL: the set of functions that take the quay changed';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points then
    raise exception '0274 self-assert FAIL: the client entry points changed';
  end if;

  -- (b) THE FIX'S OWN SHAPE: both passes run BEFORE the quay in the loop, the clear pass's verdict is set
  -- AFTER it, and the step's clear never acts under it. Text order, on the new bodies.
  v_def := replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0274(substr(v_def, 1, position('perform public.hold_the_quay();' in v_def)),
                         'public.npc_tend_route(v_now, r.fleet_id, r.route_id, r.k);') <> 2 then
    raise exception '0274 self-assert FAIL: the plan pass and the clear pass do not both stand before the quay';
  end if;
  if position('perform set_config(''byeharu.tend_cleared'', v_clear, true);' in v_def)
       < position('perform public.hold_the_quay();' in v_def) then
    raise exception '0274 self-assert FAIL: the clear pass''s verdict does not stand after the quay';
  end if;
  if pg_temp.occurs_0274(v_def, 'byeharu.tend_clear_pass') < 2
     or pg_temp.occurs_0274(v_def, 'byeharu.tend_cleared') < 3
     or pg_temp.occurs_0274(v_def, 'byeharu.tend_planned') < 4 then
    raise exception '0274 self-assert FAIL: the loop does not carry both flags as this file writes them';
  end if;
  if pg_temp.occurs_0274(v_def, '''tend_clear'', jsonb_build_object(''n'', v_cleared, ''ms'', round(v_clear_ms))') <> 1 then
    raise exception '0274 self-assert FAIL: the clear pass''s tally is not in the receipt exactly once';
  end if;
  v_def := replace(pg_get_functiondef('public.npc_tend_route(timestamptz,uuid,uuid,bigint)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0274(v_def, 'v_due := public.npc_clear_due(') <> 1 then
    raise exception '0274 self-assert FAIL: the clear branch does not ask the one rule exactly once';
  end if;
  if pg_temp.occurs_0274(v_def, 'if v_plan_pass or v_clear_pass then continue; end if;') <> 4 then
    raise exception '0274 self-assert FAIL: the clear pass does not stop before all four acting roads';
  end if;
  if pg_temp.occurs_0274(v_def, 'perform set_config(''byeharu.tend_cleared'', ''on'', true);') <> 1 then
    raise exception '0274 self-assert FAIL: the clear pass does not set its verdict exactly once';
  end if;
  if pg_temp.occurs_0274(v_def, 'if v_cleared_flag then') <> 1 then
    raise exception '0274 self-assert FAIL: the step does not stop at the clear pass''s verdict exactly once';
  end if;
  if position('if v_cleared_flag then' in v_def) > position('select * into fo from public.orders' in v_def) then
    raise exception '0274 self-assert FAIL: the step''s count does not stand before the halt law''s read of the failed order';
  end if;
  if pg_temp.occurs_0274(v_def, 'perform cmd.clear_for(sr.player_id, r.fleet_id, false);') <> 2 then
    raise exception '0274 self-assert FAIL: the clear''s calls are not the pass''s and the step''s, one each';
  end if;
  if pg_temp.occurs_0274(v_def, 'perform public.emit_event(sr.player_id, ''NPC_CLEARED'', jsonb_build_object(') <> 2 then
    raise exception '0274 self-assert FAIL: the NPC_CLEARED event is not the pass''s and the step''s, one each';
  end if;
  if pg_temp.occurs_0274(v_def, 'perform cmd.advance(r.fleet_id, p_now);') <> 3 then
    raise exception '0274 self-assert FAIL: cmd.advance is not called by the tow, the pass and the step, one each';
  end if;

  -- (c) THE RULE: one place, and it says what 0150 and 0272 said (a third clear plans; a SAIL refused
  -- E_ENDURANCE or E_CREW_SHORT plans)
  if public.npc_clear_due('00000000-0000-0000-0000-000000000000'::uuid, '00000000-0000-0000-0000-000000000000'::uuid,
                          1, 'SAIL', 'E_ENDURANCE')->>'plan' <> 'true' then
    raise exception '0274 self-assert FAIL: E_ENDURANCE does not plan';
  end if;
  if public.npc_clear_due('00000000-0000-0000-0000-000000000000'::uuid, '00000000-0000-0000-0000-000000000000'::uuid,
                          1, 'SAIL', 'E_CREW_SHORT')->>'plan' <> 'true' then
    raise exception '0274 self-assert FAIL: E_CREW_SHORT does not plan (0272''s clause)';
  end if;
  if public.npc_clear_due('00000000-0000-0000-0000-000000000000'::uuid, '00000000-0000-0000-0000-000000000000'::uuid,
                          1, 'SAIL', 'E_NO_CARGO')->>'plan' <> 'false' then
    raise exception '0274 self-assert FAIL: a first clear with no E_ENDURANCE or E_CREW_SHORT plans';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where p.proname = 'npc_clear_due' and n.nspname = 'public') <> 1 then
    raise exception '0274 self-assert FAIL: the rule is not in one place';
  end if;

  -- (d) PROBE 1: OLD vs NEW vs OLD (control) vs the plan pass + the clear pass + the step, per merchant,
  -- four cases. The rule is held against the self-assert's OWN count of her lap's clears (not against
  -- itself): a first clear (no plan), the clear that makes three (plan), E_ENDURANCE (plan) and
  -- E_CREW_SHORT (plan, whatever the count). Then the spent budget and the raised pass, per merchant.
  if (select count(*) from pg_temp.sample_0274) < 1 then
    raise exception '0274 self-assert FAIL: no merchant the clear branch can reach — the probe proves nothing';
  end if;
  for m in select * from pg_temp.sample_0274 order by k loop
    for e in select * from (values ('E_NO_CARGO', 0), ('E_NO_CARGO', -1), ('E_ENDURANCE', 0), ('E_CREW_SHORT', 0)) c(err, clears) loop
      v_o := pg_temp.tend_case_0274('old', m.fleet_id, m.route_id, m.player_id, m.k, e.err, e.clears);
      v_n := pg_temp.tend_case_0274('new', m.fleet_id, m.route_id, m.player_id, m.k, e.err, e.clears);
      v_c := pg_temp.tend_case_0274('old', m.fleet_id, m.route_id, m.player_id, m.k, e.err, e.clears);
      v_p := pg_temp.tend_case_0274('pass', m.fleet_id, m.route_id, m.player_id, m.k, e.err, e.clears);
      v_cases := v_cases + 1;
      if (v_o->'due'->>'n')::int <> (v_o->>'base')::int + (v_o->>'planted')::int + 1
         or (v_o->'due'->>'plan')::boolean <> (((v_o->>'base')::int + (v_o->>'planted')::int + 1) >= 3
                                               or e.err in ('E_ENDURANCE', 'E_CREW_SHORT')) then
        raise exception '0274 self-assert FAIL: the rule says % where her lap says % (merchant %, case %)',
          v_o->'due', jsonb_build_object('n', (v_o->>'base')::int + (v_o->>'planted')::int + 1,
                                         'plan', ((v_o->>'base')::int + (v_o->>'planted')::int + 1) >= 3
                                                 or e.err in ('E_ENDURANCE', 'E_CREW_SHORT')),
          m.route_id, e.err;
      end if;
      if v_o->>'digest' is distinct from v_c->>'digest' or v_o->>'receipt' is distinct from v_c->>'receipt' then
        raise exception '0274 self-assert FAIL: the control moved (old against old), merchant %: % / %', m.route_id, left(v_o::text, 800), left(v_c::text, 800);
      end if;
      if v_o->>'digest' is distinct from v_n->>'digest' then
        raise exception '0274 self-assert FAIL: old and new leave different rows, merchant %, case %: % / %', m.route_id, e.err, left(v_o->>'digest', 1200), left(v_n->>'digest', 1200);
      end if;
      if v_o->>'receipt' is distinct from v_n->>'receipt' then
        raise exception '0274 self-assert FAIL: old and new answer differently, merchant %, case %: % / %', m.route_id, e.err, v_o->>'receipt', v_n->>'receipt';
      end if;
      if v_p->>'digest' is distinct from v_n->>'digest' or v_p->>'receipt' is distinct from v_n->>'receipt' then
        raise exception '0274 self-assert FAIL: the plan pass + the clear pass + her step differ from her step, merchant %, case %: % / %', m.route_id, e.err, left(v_p::text, 1200), left(v_n::text, 1200);
      end if;
      -- the plan pass may fall back to her step (a busy or raised plan: her step then plans for herself, as
      -- before); what it must never do is plan where the rule says no
      if v_p->>'planned' = 'on' and not (v_p->'due'->>'plan')::boolean then
        raise exception '0274 self-assert FAIL: the plan pass planned where the rule says no (merchant %, case %)', m.route_id, e.err;
      end if;
      -- the clear pass must have cleared her — her step's rows prove it did not act twice
      if v_p->>'cleared' <> 'on' then
        raise exception '0274 self-assert FAIL: the clear pass did not clear (merchant %, case %): %', m.route_id, e.err, v_p->>'cleared';
      end if;
      if v_p->>'planned' = 'on' then v_plans := v_plans + 1; end if;
    end loop;

    -- THE SPENT BUDGET (0114): the past deadline defers in the plan pass, the clear pass and her step,
    -- exactly as her step deferred alone — the budget is read once, at the pass, as before
    v_s := pg_temp.tend_case_0274('old', m.fleet_id, m.route_id, m.player_id, m.k, 'E_NO_CARGO', 0, now() - interval '1 second');
    v_p := pg_temp.tend_case_0274('pass', m.fleet_id, m.route_id, m.player_id, m.k, 'E_NO_CARGO', 0, now() - interval '1 second');
    if v_s->>'digest' is distinct from v_p->>'digest' or v_s->>'receipt' is distinct from v_p->>'receipt'
       or v_p->>'cleared' <> 'off' or v_p->>'planned' <> 'off' then
      raise exception '0274 self-assert FAIL: the spent budget defers differently (merchant %): % / %', m.route_id, left(v_s::text, 800), left(v_p::text, 800);
    end if;

    -- THE RAISED PASS: the clear pass raises and rolls back, its verdict is 'off', and her step clears
    -- inline — the same rows and the same receipt as her step alone
    v_o := pg_temp.tend_case_0274('old', m.fleet_id, m.route_id, m.player_id, m.k, 'E_NO_CARGO', 0);
    v_r1 := pg_temp.tend_case_0274('raised', m.fleet_id, m.route_id, m.player_id, m.k, 'E_NO_CARGO', 0);
    if coalesce((v_r1->>'raised')::boolean, false) <> true or v_r1->>'cleared' <> 'off' then
      raise exception '0274 self-assert FAIL: the raised-pass case did not raise, or its verdict is not off (merchant %)', m.route_id;
    end if;
    if v_o->>'digest' is distinct from v_r1->>'digest' or v_o->>'receipt' is distinct from v_r1->>'receipt' then
      raise exception '0274 self-assert FAIL: the raised pass fell back differently (merchant %): % / %', m.route_id, left(v_o::text, 1200), left(v_r1::text, 1200);
    end if;
  end loop;

  -- one more raised case with a plan in the pass, so a planned-then-raised merchant also falls back to her
  -- step's clear (the plan already made, the step does not re-plan)
  select * into m from pg_temp.sample_0274 order by k limit 1;
  v_o := pg_temp.tend_case_0274('old', m.fleet_id, m.route_id, m.player_id, m.k, 'E_ENDURANCE', 0);
  v_r2 := pg_temp.tend_case_0274('raised', m.fleet_id, m.route_id, m.player_id, m.k, 'E_ENDURANCE', 0);
  if coalesce((v_r2->>'raised')::boolean, false) <> true or v_r2->>'cleared' <> 'off' or v_r2->>'planned' <> 'on' then
    raise exception '0274 self-assert FAIL: the planned-then-raised case is not off with her plan made (merchant %)', m.route_id;
  end if;
  if v_o->>'digest' is distinct from v_r2->>'digest' or v_o->>'receipt' is distinct from v_r2->>'receipt' then
    raise exception '0274 self-assert FAIL: the planned-then-raised fallback differs (merchant %): % / %', m.route_id, left(v_o::text, 1200), left(v_r2::text, 1200);
  end if;

  -- (e) PROBE 2: the hourly loop, OLD vs NEW, same cuts; the new tallies counted, the rest identical
  v_ro := pg_temp.reconcile_case_0274('old');
  v_rn := pg_temp.reconcile_case_0274('new');
  if (v_ro->>'digest') is distinct from (v_rn->>'digest') then
    raise exception '0274 self-assert FAIL: the loop leaves different rows: % / %', left(v_ro->>'digest', 1200), left(v_rn->>'digest', 1200);
  end if;
  if ((v_ro->'receipt') - array['ms', 'quay', 'tend_holds', 'tend_plan', 'tend_clear'])
     is distinct from ((v_rn->'receipt') - array['ms', 'quay', 'tend_holds', 'tend_plan', 'tend_clear']) then
    raise exception '0274 self-assert FAIL: the loop''s receipts differ: % / %', left((v_ro->'receipt')::text, 1500), left((v_rn->'receipt')::text, 1500);
  end if;
  if ((v_ro->'receipt')->'tend_clear') is not null then
    raise exception '0274 self-assert FAIL: the old loop already carries the new tally';
  end if;
  -- 0270's tally is in both loops (this file's OLD is 0270's NEW); only tend_clear is this file's own
  if coalesce(((v_ro->'receipt')->'tend_plan'->>'n')::int, 0) < 1 then
    raise exception '0274 self-assert FAIL: the old loop did not plan for the planted merchant';
  end if;
  if coalesce(((v_rn->'receipt')->'tend_plan'->>'n')::int, 0) < 1
     or coalesce(((v_rn->'receipt')->'tend_clear'->>'n')::int, 0) < 1 then
    raise exception '0274 self-assert FAIL: the loop planned or cleared nothing, and no merchant was busy or failed: % / %',
      (v_rn->'receipt')->'tend_plan', (v_rn->'receipt')->'tend_clear';
  end if;

  raise notice '0274 self-assert ok: HER CLEAR ACTS BEFORE THE QUAY. npc_tend_route and tick_reconcile reverse to their pre-images hunk by hunk, ACLs unmoved, the functions both decide with and the quay takers unmoved; 0150/0272''s rule in public.npc_clear_due alone. Probes: % step cases on % merchants (old = new = control, and the plan pass + the clear pass + the step = the step), % planning cases, the spent budget and the raised pass on every merchant, one planned-then-raised; the hourly loop old vs new, % plan(s) and % clear(s) counted. Rolled back.',
    v_cases, (select count(*) from pg_temp.sample_0274), v_plans,
    ((v_rn->'receipt')->'tend_plan'->>'n')::int, ((v_rn->'receipt')->'tend_clear'->>'n')::int;
end $$;

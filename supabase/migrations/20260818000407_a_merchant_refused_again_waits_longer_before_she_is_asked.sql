-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0407 - A MERCHANT REFUSED AGAIN WAITS LONGER BEFORE SHE IS ASKED  (the waiting line's due rule backs off: 10, 20, 40, then 50 minutes)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none
--
-- WHY (prod, read-only, 2026-11-14 02:10 to 02:35 UTC, head 0406; docs/dev-log/2026-11-14-ask-backoff.md):
--   0405's job cleared the waiting line's backlog in twenty minutes (due_left 139 to 0-4, the oldest ask 40.5 to 10 minutes, none failed). But its
--   steady state is dear: 9 to 12 merchants asked a minute, 2 to 5 of them resumed, and npc_ask_job_ms (20,000) spent EVERY minute. An ask costs
--   about 1.5 s of planning there, not the 0.3 to 0.46 s 0405 reckoned with (that was the reconcile's one-loop re-plan; a laid-up merchant's loop
--   nets nothing, so the planner prices all npc_route_candidates loops on offer for her: its dearest path). The beat pays: mean 442-555 ms before,
--   615-693 after; p95 1.5-2.0 s before, 2.5-3.4 s after. Lap starts too: late 41-46 per ten minutes before, 56-62 after.
--   About 70 % of the asks answer "nothing pays" again: the same merchants, asked every ten minutes for hours (the sea-shut, the broke, the thin).
--
-- WHAT THIS FILE DOES:
--   1. THE DUE RULE BACKS OFF, IN ITS ONE PLACE. public.npc_waiting_queue (0182: THE answer to who waits and who is due, read by the beat's hand,
--      the job and the reconcile alike) makes a merchant due npc_replan_every_minutes x 2^(refusals in a row - 1) after her last ask: 10, 20, 40
--      minutes, and never more than npc_replan_within_minutes less one npc_replan_every_minutes (50): ten minutes before the hourly reconcile would
--      call her overdue, so the job reaches her first and the reconcile's 60 s budget is not spent on the line.
--   2. THE COUNT HAS ONE WRITER, THE PLANNER. npc_fleets.refused (new, 0): public.npc_plan adds one where it decides "she waits in port" (0181's
--      own lines, at a lap start), and puts it back to 0 where a loop pays at a lap start. So a merchant newly laid up has 1 and is asked in ten
--      minutes, as 0405 won; and a merchant who sails starts afresh. Whoever asked her (the lap start, the job, the beat's hand, the reconcile),
--      the count is the planner's own answer.
--   3. A BROKE HOUSE WAITS THE LONGEST AT ONCE. A house whose purse is under npc_ask_broke_under (100 d.; a laid-up merchant carries nothing, so
--      her purse is all she can buy with, 0129) is due at the cap from her first refusal: an ask cannot wake her. She is still asked, once in
--      fifty minutes, so that a gift or a paid debt is noticed within the hour; her purse is read live, so the rule lifts with it.
--   4. THE JOB SAYS WHAT THE QUAY COST IT. public.tick_waiting_asks asks for the quay itself before the open step and times that wait apart
--      (receipt: quay_ms, quay_ms_max): it is no longer in open_ms nor counted against npc_ask_job_ms. On prod an open read 1.5 s where a lap
--      start's reads 0.18 s; this tells the wait from the work.
--   5. npc_ask_job_ms 20,000 -> 12,000 (only if it still holds 0405's 20,000: an owner's own value is left alone). The dev-log has the sum.
--
-- NOT BUILT: a pre-test of "her quotes have not moved, so still no". It would be a second answer to "does a loop pay" beside the planner's.
-- LOCKS: ALTER TABLE npc_fleets ADD COLUMN ... DEFAULT 0 (no rewrite; a brief ACCESS EXCLUSIVE lock, lock_timeout 5 s); CREATE OR REPLACE x3 by
--   hunks; two knobs. TIME: milliseconds for the cut; the probe plans ONE merchant once in a rolled-back sub-transaction (about 1.5 s on prod):
--   expected under 8 s there. BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 15 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/ask-backoff/rollback-0407.sql, a draft. At once, with no file: npc_ask_job_ms 0 stops the
--   job; npc_ask_broke_under 0 lifts the broke rule. The back-off itself has no knob: its steps are npc_replan_every_minutes' own doublings.
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; then the probe.
-- VERSION: 0407 = 0406 + 1.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array['public.npc_waiting_queue(timestamp with time zone)', 'public.npc_plan(timestamp with time zone,uuid)', 'public.tick_waiting_asks(boolean,uuid)'];
  v_t0        timestamptz := clock_timestamp();
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_fleet     uuid;
  v_route     uuid;
  v_player    uuid;
  v_steps     text;
  v_r         jsonb;
  v_note      text := 'no merchant in port to probe in this world';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'npc_fleets' and c.column_name = 'refused')
     or exists (select 1 from public.world_config where key = 'npc_ask_broke_under') then
    raise exception '0407 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.tick_waiting_asks(boolean,uuid)') is null or not exists (select 1 from public.world_config where key = 'npc_ask_job_ms') then
    raise exception '0407 refuses: the waiting-asks job (0405) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0407 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0407
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);

  -- ── 2. THE COUNT AND THE KNOBS ──
  alter table public.npc_fleets add column refused int not null default 0 check (refused >= 0);
  comment on column public.npc_fleets.refused is
    '0407: how many times in a row the planner has answered "nothing pays, she waits in port" at her lap start (public.npc_plan, its one writer: +1 where it lays her up or keeps her laid up, 0 where a loop pays). Read by public.npc_waiting_queue: her next ask is due npc_replan_every_minutes x 2^(refused - 1) after the last, capped.';
  insert into public.world_config (key, value, description) values
    ('npc_ask_broke_under', to_jsonb(100),
     '0407: a laid-up merchant whose house holds less than this many ducats is due again only at the longest wait (npc_replan_within_minutes less npc_replan_every_minutes), from her first refusal: with no purse no parcel can be bought (0129), so an ask cannot wake her. Read live by public.npc_waiting_queue. 0 = no such rule.');
  update public.world_config set value = to_jsonb(12000) where key = 'npc_ask_job_ms' and value = to_jsonb(20000);

  -- ── 3. THE HUNKS ──
  create temp table hunk_0407 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0407 values
  (3, c_cut[1],
$h$         a.asked + make_interval(mins => w.e_min),
$h$,
$h$         -- 0407: THE DUE RULE BACKS OFF. Refused once she is due in npc_replan_every_minutes; refused again, in twice that, then four times,
         -- and never more than npc_replan_within_minutes less one npc_replan_every_minutes (the job reaches her before the hourly reconcile
         -- calls her overdue). A house with no purse to buy a parcel (under npc_ask_broke_under) waits that longest at once.
         a.asked + make_interval(mins => case when pl.ducats < w.broke then greatest(w.e_min, w.w_min - w.e_min)
                                              else least(w.e_min * power(2, least(greatest(nf.refused, 1) - 1, 10))::int,
                                                         greatest(w.e_min, w.w_min - w.e_min)) end),
$h$),
  (1, c_cut[1],
$h$    join public.npc_fleets nf on nf.fleet_id = ro.fleet_id
$h$,
$h$    join public.npc_fleets nf on nf.fleet_id = ro.fleet_id
    join public.players pl on pl.id = sr.player_id   -- 0407: her house's purse, read live
$h$),
  (2, c_cut[1],
$h$                      public.wc_int('npc_replan_within_minutes') as w_min) w
$h$,
$h$                      public.wc_int('npc_replan_within_minutes') as w_min,
                      public.wc_int('npc_ask_broke_under') as broke) w   -- 0407
$h$),
  (4, c_cut[2],
$h$      if not v_pays and v_choose and not v_off and coalesce(v_aboard, 0) <= 0 then
        v_waiting := v_waiting + 1;
$h$,
$h$      -- 0407: THE COUNT OF HER REFUSALS IN A ROW (npc_fleets.refused; public.npc_waiting_queue backs her next ask off by it) is written here
      -- and nowhere else: back to nothing where a loop pays at her lap start, one more where she is laid up or kept laid up just below.
      if v_pays and v_choose then
        update public.npc_fleets set refused = 0 where fleet_id = r.fleet_id and refused <> 0;
      end if;
      if not v_pays and v_choose and not v_off and coalesce(v_aboard, 0) <= 0 then
        v_waiting := v_waiting + 1;
        update public.npc_fleets set refused = refused + 1 where fleet_id = r.fleet_id;   -- 0407
$h$),
  (5, c_cut[3],
$h$  v_wait_ms numeric := 0;
begin
$h$,
$h$  v_wait_ms numeric := 0;
  v_quay_ms numeric := 0;    -- 0407: the wait for the quay itself, apart from the open step's work
  v_quay_max numeric := 0;   -- 0407
begin
$h$),
  (6, c_cut[3],
$h$    v_t := clock_timestamp();
    begin
      v_b := public.waiting_ask_open(v_f, v_stamp);
$h$,
$h$    -- 0407: the quay asked for here, to time the wait for it apart (0269's way in public.tick_lap_starts); public.waiting_ask_open asks for
    -- it again first thing: the same lock in the same transaction, granted at once. The wait is not work: not in open_ms, not in v_spent.
    v_t := clock_timestamp();
    perform public.hold_the_quay();
    v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
    v_quay_ms := v_quay_ms + v_ms;
    v_quay_max := greatest(v_quay_max, v_ms);
    v_t := clock_timestamp();
    begin
      v_b := public.waiting_ask_open(v_f, v_stamp);
$h$),
  (7, c_cut[3],
$h$'wait_ms', round(v_wait_ms),
$h$,
$h$'wait_ms', round(v_wait_ms),
                    'quay_ms', round(v_quay_ms), 'quay_ms_max', round(v_quay_max),   -- 0407
$h$);
  for h in select * from hunk_0407 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0407 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0407 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0407 p where p.fn = h.fn) then
      raise exception '0407 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0407 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0407 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0407 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0407 self-assert FAIL: another function moved';
  end if;
  if public.wc_int('npc_ask_broke_under') <> 100 or public.wc_int('npc_ask_job_ms') = 20000 then
    raise exception '0407 self-assert FAIL: the knobs are not this file''s';
  end if;

  -- ── 4. THE PROBE: one merchant's rows, rolled back. The steps of the due rule by the queue itself (no plan); then ONE plan of a house with an
  --      empty purse at her lap start, which cannot pay whatever the market: the planner must count her refusal.
  select nf.fleet_id, nf.route_id, sr.player_id into v_fleet, v_route, v_player
    from public.npc_tend_roster() ro
    join public.npc_fleets nf on nf.fleet_id = ro.fleet_id
    join public.fleets f on f.id = nf.fleet_id and f.status = 'DOCKED'
    join public.standing_routes sr on sr.id = nf.route_id and sr.lap_id is null and (sr.fleet_id is null or sr.fleet_id = nf.fleet_id)
    join public.standing_route_stops s on s.route_id = sr.id and s.ord = 0 and s.port_id = f.port_id
   where ro.k <= public.wc_int('npc_fleet_max')
     and not exists (select 1 from public.orders o where o.fleet_id = nf.fleet_id and o.status in ('pending', 'failed'))
     and not exists (select 1 from public.ships sh where sh.fleet_id = nf.fleet_id and public.ship_cargo_tuns(sh.id) > 0)
     and (select count(*) from public.npc_fleets x where x.player_id = nf.player_id) = 1
   order by (sr.paused_reason = 'laid_up') desc nulls last, ro.k
   limit 1;
  if v_fleet is not null then
    begin
      update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
      update public.world_config set value = to_jsonb(10) where key = 'npc_replan_every_minutes';
      update public.world_config set value = to_jsonb(60) where key = 'npc_replan_within_minutes';
      update public.standing_routes set fleet_id = v_fleet, lap_id = null, paused_reason = 'laid_up', hold_until = null, updated_at = now() - interval '3 hours' where id = v_route;
      update public.players set ducats = 5000 where id = v_player;
      v_steps := '';
      foreach v_n in array array[0, 1, 2, 3, 4, 9] loop
        update public.npc_fleets set refused = v_n, asked_at = null where fleet_id = v_fleet;
        v_steps := v_steps || (select round(extract(epoch from q.due_at - q.asked_at) / 60)::text from public.npc_waiting_queue(now()) q where q.fleet_id = v_fleet) || ' ';
      end loop;
      update public.npc_fleets set refused = 1 where fleet_id = v_fleet;
      update public.players set ducats = 99 where id = v_player;
      v_steps := v_steps || '/ broke ' || (select round(extract(epoch from q.due_at - q.asked_at) / 60)::text from public.npc_waiting_queue(now()) q where q.fleet_id = v_fleet);
      update public.world_config set value = to_jsonb(0) where key = 'npc_ask_broke_under';
      v_steps := v_steps || ' / rule off ' || (select round(extract(epoch from q.due_at - q.asked_at) / 60)::text from public.npc_waiting_queue(now()) q where q.fleet_id = v_fleet);
      if v_steps is distinct from '10 10 20 40 50 50 / broke 50 / rule off 10' then
        raise exception '0407 self-assert FAIL: the due rule''s steps are "%", not "10 10 20 40 50 50 / broke 50 / rule off 10"', v_steps;
      end if;
      -- the planner counts: a house with an empty purse, planned alone at her lap start, waits; her count goes from 2 to 3
      update public.players set ducats = 0 where id = v_player;
      update public.npc_fleets set refused = 2 where fleet_id = v_fleet;
      v_r := public.npc_plan(now(), v_route);
      if coalesce((v_r->>'planned')::int, 0) <> 1 or coalesce((v_r->>'waiting')::int, 0) <> 1
         or (select nf.refused from public.npc_fleets nf where nf.fleet_id = v_fleet) <> 3
         or (select sr.paused_reason from public.standing_routes sr where sr.id = v_route) is distinct from 'laid_up' then
        raise exception '0407 self-assert FAIL: a house with an empty purse was not counted refused once more (plan %, refused %)', v_r - 'notes', (select nf.refused from public.npc_fleets nf where nf.fleet_id = v_fleet);
      end if;
      v_note := 'one merchant''s rows: the steps ' || v_steps || '; planned with an empty purse she waits and her count goes 2 to 3';
      raise exception sqlstate 'BV407';
    exception when sqlstate 'BV407' then null;
    end;
    if (select nf.refused from public.npc_fleets nf where nf.fleet_id = v_fleet) <> 0 or public.wc_int('npc_ask_broke_under') <> 100 then
      raise exception '0407 self-assert FAIL: the probe was not rolled back';
    end if;
    if v_note not like 'one merchant%' then
      raise exception '0407 self-assert FAIL: the probe did not run to its end';
    end if;
  end if;
  if clock_timestamp() - v_t0 > interval '15 seconds' then
    raise exception '0407 self-assert FAIL: the file took % (budget 15 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0407 self-assert ok: A MERCHANT REFUSED AGAIN WAITS LONGER BEFORE SHE IS ASKED. Seven hunks over three bodies, each once and reversing; grants and volatility unmoved; no other function moved; npc_fleets.refused; npc_ask_broke_under 100, npc_ask_job_ms %. Probe: %; % ms.',
    public.wc_int('npc_ask_job_ms'), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;

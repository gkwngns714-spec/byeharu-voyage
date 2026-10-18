-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0199 — A WAITING MERCHANT'S BATCH KEEPS ITS BUDGET  (npc_replan_sweep_ms 600 → 300, and no overshoot)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The arrivals sweep's average sits at ~3 s with combat dark (prod, read-only, 2026-10-18; docs/dev-log/
-- 2026-10-18-auto-fight.md "Why the sweep rose"). Two deploys moved it, both through 0182's batch of waiting
-- (laid-up) merchants at the end of every sweep (public.npc_ask_waiting):
--   * 0182 (14:18 UTC): 2.1 → 2.8 s — the batch, budgeted at npc_replan_sweep_ms = 600 ms;
--   * 0197 (18:30 UTC): ~2.65 → 3.04 s — more merchants re-planned (61–97 asks / 10 min against ≤ 17 before).
-- And the batch is not held to its budget: a merchant is BEGUN while the batch has run less than the budget,
-- so the last re-plan (170–230 ms on prod, per 0182) always runs past it.
--
-- ── WHAT THIS FILE DOES (the coordinator's decision, 2026-10-18; the owner may reverse it) ───────
-- (1) npc_replan_sweep_ms 600 → 300 (refused unless it is 600: its pre-image).
-- (2) THE BATCH IS STRICT. public.npc_ask_waiting begins another merchant only if the time the batch has run
--     PLUS the last re-plan's own measured cost (this sweep) stays within the budget. The first merchant of a
--     sweep is begun as before (no cost measured yet), so a due merchant is never starved; the batch's only
--     overrun is a single re-plan longer than the whole budget.
-- The promise is unchanged: every waiting merchant asked within npc_replan_within_minutes (60) — the hourly
-- reconcile asks any OVERDUE one, as 0182 made it. Who is asked, and in what order, is unchanged; only how
-- many a sweep. Measured on the prod-shaped world (dev-log): the oldest wait, before and after.
--
-- ── WHAT IT DOES NOT DO ─────────────────────────────────────────────────────────────────────────
-- No re-plan answers anything differently: npc_tend_route, npc_plan and the queue are untouched. No ALTER, no
-- entry point. No top-level LOCK / SET LOCAL / BEGIN / SET ROLE. Timings by RAISE NOTICE only.
-- SUPERSEDES by hunks sliced from the LIVE body (prod head 0198, LF-normalised), each asserted to occur once
-- and to reverse to its pre-image, ACL / volatility / definer / config unchanged: public.npc_ask_waiting (0182).
-- ROLLBACK (forward migration): the knob back to 600; reverse the hunks (old text in hunks_0199).
-- VERSION: 0199 (provisional; head + 1 at deploy). Applies on 0198.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if (select value from public.world_config where key = 'npc_replan_sweep_ms') is distinct from to_jsonb(600) then
    raise exception '0199 refuses: npc_replan_sweep_ms is not 600 — this file''s pre-image';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0199(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGE, and the old body under a pg_temp name ─────────────────────────────────────
create temp table defs_before_0199 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.npc_ask_waiting(timestamp with time zone, timestamp with time zone)')) f(fn);

create temp table untouched_before_0199 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def
  from (values ('public.npc_waiting_queue(timestamp with time zone)'), ('public.npc_tend_route(timestamp with time zone, uuid, uuid, bigint)'),
               ('public.tick_arrivals(timestamp with time zone)'), ('public.tick_reconcile(boolean)')) f(fn);

do $$
declare
  v_def text := (select def from defs_before_0199);
  v_new text := 'CREATE OR REPLACE FUNCTION pg_temp.npc_ask_waiting_b0199(';
begin
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION public.npc_ask_waiting(', v_new);
  if pg_temp.occurs_0199(v_def, v_new) <> 1 then
    raise exception '0199 self-assert FAIL: could not rename the pre-image of public.npc_ask_waiting';
  end if;
  execute v_def;
end $$;

-- ── 2. THE KNOB ────────────────────────────────────────────────────────────────────────────────
update public.world_config set value = to_jsonb(300),
       description = '0182 / 0199: the wall-clock budget of one sweep''s batch of waiting merchants, in ms. Since 0199 the '
                     'batch begins another merchant only if the time it has run plus the last re-plan''s own cost stays '
                     'within this (the first of a sweep is always begun). 600 until 0199.'
 where key = 'npc_replan_sweep_ms';

-- ── 3. THE HUNKS ───────────────────────────────────────────────────────────────────────────────
create temp table hunks_0199 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0199 values
('public.npc_ask_waiting(timestamp with time zone, timestamp with time zone)', 1,
$h$  v_ids   jsonb := '[]'::jsonb;
$h$,
$h$  v_ids   jsonb := '[]'::jsonb;
  v_t     timestamptz;                  -- 0199: when this re-plan began
  v_last  interval := interval '0';     -- 0199: the last re-plan's own cost, this sweep
$h$),
('public.npc_ask_waiting(timestamp with time zone, timestamp with time zone)', 2,
$h$    exit when v_n >= v_max or clock_timestamp() >= v_stop;
$h$,
$h$    -- 0199: STRICT — another merchant only if the batch so far plus the last re-plan's cost stays within the
    -- budget (the first of a sweep is begun as before: nothing measured yet)
    exit when v_n >= v_max or clock_timestamp() + v_last >= v_stop;
$h$),
('public.npc_ask_waiting(timestamp with time zone, timestamp with time zone)', 3,
$h$    v_acc := public.npc_tend_sum(v_acc, public.npc_tend_route(p_now, r.fleet_id, r.route_id, r.k));
$h$,
$h$    v_t := clock_timestamp();
    v_acc := public.npc_tend_sum(v_acc, public.npc_tend_route(p_now, r.fleet_id, r.route_id, r.k));
    v_last := clock_timestamp() - v_t;   -- 0199
$h$);

do $$
declare
  d record;
  h record;
  v_def text;
begin
  for d in select * from defs_before_0199 loop
    v_def := d.def;
    for h in select * from hunks_0199 where fn = d.fn order by n loop
      if pg_temp.occurs_0199(v_def, h.old) <> 1 then
        raise exception '0199 self-assert FAIL: hunk % of % occurs % time(s), not once', h.n, d.fn, pg_temp.occurs_0199(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 4. THE PROBE (its own merchants and stand-ins; rolled back whole) ───────────────────────────
-- Four merchants of its own (two companies of two fleets), all due; the queue answers only them, and each re-plan is a stand-in that takes
-- 120 ms. With the budget at 300 ms the strict batch begins two (0, then 120 + 120 ≤ 300; the third would end
-- at 360) and ends within the budget; the old body begins three (at 0, 120, 240 — all under 300) and runs to 360.
create or replace function pg_temp.probe_0199()
returns jsonb
language plpgsql
as $$
declare
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_p    uuid;
  v_f    uuid;
  i      int;
  h      int;
  v_t0   timestamptz;
  v_out  jsonb := '{}'::jsonb;
  v_r    jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
    update public.world_config set value = to_jsonb(12) where key = 'npc_replan_per_sweep_max';
    create temp table probe_fleets_0199 (fleet_id uuid, k bigint) on commit drop;
    -- two merchant companies of its own (a house keeps at most 2 fleets): each its founding fleet and one more
    for h in 1 .. 2 loop
      v_p := public.new_house(('00000000-0199-4000-8000-00000000000' || h)::uuid, 'Casa da Espera ' || h, 'PRT', 'LIS');
      update public.players set is_npc = true, auth_uid = null where id = v_p;   -- npc_houses describes merchants only
      insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience)
      values (v_p, 1990000 + h, 'prt', 'the probe of 0199', 'Probe 0199', v_lis, 5000, 0.10);
      insert into public.fleets (player_id, name, status, port_id) values (v_p, 'Probe 0199 ' || h, 'DOCKED', v_lis);
      for v_f in select f.id from public.fleets f where f.player_id = v_p order by f.created_at, f.id loop
        i := coalesce((select max(k) from probe_fleets_0199), 0) + 1;
        insert into public.npc_fleets (fleet_id, player_id, roster_ord) values (v_f, v_p, 1990000 + 10 * h + i);
        insert into probe_fleets_0199 values (v_f, i);
      end loop;
    end loop;
    execute $q$create or replace function public.npc_waiting_queue(p_now timestamptz)
      returns table (fleet_id uuid, route_id uuid, k bigint, asked_at timestamptz, due_at timestamptz, overdue boolean)
      language sql stable as 'select fleet_id, null::uuid, k, null::timestamptz, now() - interval ''1 hour'', false from probe_fleets_0199'$q$;
    execute $q$create or replace function public.npc_tend_route(p_now timestamptz, p_fleet uuid, p_route uuid, p_k bigint)
      returns jsonb language plpgsql as 'begin perform pg_sleep(0.12); return ''{}''::jsonb; end'$q$;
    v_t0 := clock_timestamp();
    v_r := public.npc_ask_waiting(now(), clock_timestamp() + interval '10 seconds');
    v_out := v_out || jsonb_build_object('new', v_r->'asked', 'new_ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
    update public.npc_fleets set asked_at = null where fleet_id in (select fleet_id from probe_fleets_0199);
    v_t0 := clock_timestamp();
    v_r := pg_temp.npc_ask_waiting_b0199(now(), clock_timestamp() + interval '10 seconds');
    v_out := v_out || jsonb_build_object('old', v_r->'asked', 'old_ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
    raise exception 'PROBE_ROLLBACK_0199';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0199' then raise; end if;
  end;
  return v_out;
end $$;

create temp table probe_0199 (j jsonb) on commit drop;
insert into probe_0199 select pg_temp.probe_0199();

-- ── 5. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_pr  jsonb := (select j from probe_0199);
  v_d   record;
  v_h   record;
  v_pp  record;
  v_def text;
begin
  if (select value from public.world_config where key = 'npc_replan_sweep_ms') <> to_jsonb(300) then
    raise exception '0199 self-assert FAIL: npc_replan_sweep_ms is not 300';
  end if;
  -- the probe: strict begins 2 and stays within the budget; the old body begins 3 and runs past it
  if (v_pr->>'new')::int <> 2 or (v_pr->>'old')::int <> 3 or not ((v_pr->>'new_ms')::int < (v_pr->>'old_ms')::int) then
    raise exception '0199 self-assert FAIL: with 4 due and 120 ms a re-plan the strict batch asked % in % ms, the old % in % ms',
      v_pr->>'new', v_pr->>'new_ms', v_pr->>'old', v_pr->>'old_ms';
  end if;
  for v_d in select * from defs_before_0199 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0199 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0199(v_def, v_h.new) <> 1 then
        raise exception '0199 self-assert FAIL: hunk % is not in the new body exactly once', v_h.n;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0199 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(pr.proacl::text, '') acl, pr.provolatile vol, pr.prosecdef secdef, coalesce(pr.proconfig::text, '') cfg
      into v_pp from pg_proc pr where pr.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0199 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  for v_d in select * from untouched_before_0199 loop
    if replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '') <> v_d.def then
      raise exception '0199 self-assert FAIL: % moved — it was to be left untouched (the probe''s stand-ins were not rolled back?)', v_d.fn;
    end if;
  end loop;
  if (select count(*) from public.client_write_grants()) <> 0 or (select count(*) from public.client_executable_writers()) <> 0 then
    raise exception '0199 self-assert FAIL: the grant wall moved';
  end if;
  raise notice '0199 self-assert ok: A WAITING MERCHANT''S BATCH KEEPS ITS BUDGET — npc_replan_sweep_ms 600 → 300, strict. PROBE (its own 4 merchants, stand-in re-plans of 120 ms, rolled back): strict asked % in % ms; the old body asked % in % ms. 1 body reverses, 4 untouched.',
    v_pr->>'new', v_pr->>'new_ms', v_pr->>'old', v_pr->>'old_ms';
end $$;

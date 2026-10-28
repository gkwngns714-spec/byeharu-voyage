-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0262 — ONE BEAT IN FOUR NAMES ITS FUNCTIONS  (a per-function profile of the arrivals beat, on prod)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- 0261's splits, prod, 10-28 00:34-00:43 UTC (532 beats outside the reconcile minutes):
--   * the deferred purse checks (the owner's lead suspect) are 5.5 % of beat time, ~36 ms a beat, OUTSIDE ms;
--   * the `held` loop (a merchant's fortnight at home ends, cmd.advance starts her next lap) is 47.5 % of the run's
--     time, and ~1.4 s of each beat over 1 s. Each lap start there costs ~550-600 ms (1 start: held 594 ms,
--     2: 1,115 ms, 3: 2,474 ms); review laps cost no more than others;
--   * the run's time is the pages it touches: run = 0.51 ms a block read from outside shared_buffers + 13.5 µs a
--     buffer hit (R² 0.97); a held-heavy beat touches ~100 k buffers (world_config 22 k, port_goods 17 k, orders
--     12 k, ports 7 k, goods 5.6 k, treasury_flows 5 k).
-- Which FUNCTION inside a lap start holds that is not yet measured, and a local profile is not the answer (the
-- owner's order; 0250 / 0256 trimmed what PGlite showed and prod did not move). Prod can measure it:
-- `track_functions` is in supautils.privileged_role_allowed_configs and the job's owner (postgres) holds that role
-- (checked read-only: SET LOCAL track_functions = 'pl' takes, 10-28).
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
-- (1) public.beat_fn_reads(): this backend's function counters, {oid: [calls, total ms, self ms]}, for the game's
--     schemas (pg_stat_get_xact_function_calls / _total_time / _self_time). public.beat_fn_diff(a, b): what lay
--     between two readings, the 40 functions with the most self time plus "_" = the totals. Server-only.
-- (2) public.tick_arrivals_each_second: 3 hunks. In a beat whose second is a multiple of 4, the beat's transaction
--     runs with SET LOCAL track_functions = 'all' (inside its own block: if the setting is refused, that beat is
--     simply not profiled), and its row's splits gain `fn` (the run and the purse checks, per function). The
--     reading's cost stays inside `probe`. Nothing else in the beat moves: same commits, same order, same run.
--
-- ── WHAT IT DELIBERATELY DOES NOT ───────────────────────────────────────────────────────────────
-- Touch public.tick_arrivals or anything it calls (md5-asserted). Change any rule, knob, flag, grant, schedule or
-- client read. The setting is LOCAL to a profiled beat's transaction: it never outlives it.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- A forward slice reversing the 3 hunks (every OLD text is here; the self-assert proves they reverse).
--
-- VERSION: 0262 (prod head 0261).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.beat_reads()') is null or to_regprocedure('public.beat_ms(interval)') is null then
    raise exception '0262 refuses: 0261 is not in this world';
  end if;
  if to_regprocedure('public.beat_fn_reads()') is not null then
    raise exception '0262 refuses: public.beat_fn_reads already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0262(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table defs_before_0262 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_arrivals_each_second(integer)')) f(fn);

create temp table before_0262 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(replace(pg_get_functiondef('public.tick_arrivals(timestamptz)'::regprocedure), E'\r', ''))) as run_md5;

-- ── 1. THE READINGS ─────────────────────────────────────────────────────────────────────────────
create function public.beat_fn_reads()
returns jsonb
language sql
volatile
set search_path = pg_catalog
as $$
  -- 0262: this backend's function counters for the game's schemas, {oid: [calls, total ms, self ms]}. Counted only
  -- while track_functions is on; they only grow inside one CALL, so two readings' difference is what lay between.
  select coalesce(jsonb_object_agg(x.oid::text, jsonb_build_array(x.c, x.t, x.s)), '{}'::jsonb)
    from (select p.oid, pg_stat_get_xact_function_calls(p.oid) as c,
                 round(pg_stat_get_xact_function_total_time(p.oid)::numeric, 2) as t,
                 round(pg_stat_get_xact_function_self_time(p.oid)::numeric, 2) as s
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('public', 'world', 'voyage', 'cmd') and p.prokind in ('f', 'p')) x
   where x.c > 0
$$;
comment on function public.beat_fn_reads() is
  '0262: this backend''s function counters per game function, {oid: [calls, total ms, self ms]}. For the arrivals beat''s profile. Server-only.';
revoke all on function public.beat_fn_reads() from public, anon, authenticated;

create function public.beat_fn_diff(p_a jsonb, p_b jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  -- 0262: two public.beat_fn_reads() readings' difference: the 40 functions with the most self time,
  -- {oid: [calls, total ms, self ms]}, and "_" = [calls, self ms] over every function that moved.
  with d as (
    select b.key as k,
           (b.value->>0)::bigint - coalesce((p_a->b.key->>0)::bigint, 0) as c,
           round((b.value->>1)::numeric - coalesce((p_a->b.key->>1)::numeric, 0), 1) as t,
           round((b.value->>2)::numeric - coalesce((p_a->b.key->>2)::numeric, 0), 1) as s
      from jsonb_each(coalesce(p_b, '{}'::jsonb)) b),
  m as (select * from d where c > 0)
  select coalesce((select jsonb_object_agg(k, jsonb_build_array(c, t, s))
                     from (select * from m order by s desc limit 40) top), '{}'::jsonb)
         || jsonb_build_object('_', jsonb_build_array(coalesce((select sum(c) from m), 0), coalesce((select sum(s) from m), 0)))
$$;
comment on function public.beat_fn_diff(jsonb, jsonb) is
  '0262: two public.beat_fn_reads() readings'' difference: the 40 functions with the most self time, {oid: [calls, total ms, self ms]}, plus "_" = [calls, self ms]. Server-only.';
revoke all on function public.beat_fn_diff(jsonb, jsonb) from public, anon, authenticated;

-- ── 2. THE HUNKS ────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0262 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0262 (fn, n, old, new) values
('public.tick_arrivals_each_second(integer)', 1,
$h$  v_sp     jsonb;
begin
$h$,
$h$  v_sp     jsonb;
  v_prof   boolean;       -- 0262: this beat is profiled (one in four)
  v_f0     jsonb;
begin
$h$),
('public.tick_arrivals_each_second(integer)', 2,
$h$    v_tp := clock_timestamp();   -- 0261: the first reading (not in ms)
    v_r0 := public.beat_reads();
$h$,
$h$    v_tp := clock_timestamp();   -- 0261: the first reading (not in ms)
    -- 0262: ONE BEAT IN FOUR names its functions: track_functions for this transaction only (LOCAL); a refused
    -- setting leaves this beat unprofiled, nothing more
    v_prof := (floor(extract(epoch from now()))::bigint % 4) = 0;
    if v_prof then
      begin
        set local track_functions = 'all';
        v_f0 := public.beat_fn_reads();
      exception when others then
        v_prof := false;
      end;
    end if;
    v_r0 := public.beat_reads();
$h$),
('public.tick_arrivals_each_second(integer)', 3,
$h$    v_sp := v_sp || jsonb_build_object('probe', $h$,
$h$    if v_prof then   -- 0262: the run and the purse checks, per function (inside probe's clock)
      v_sp := v_sp || jsonb_build_object('fn', public.beat_fn_diff(v_f0, public.beat_fn_reads()));
    end if;
    v_sp := v_sp || jsonb_build_object('probe', $h$);

do $$
declare
  v_def text := (select def from defs_before_0262 where fn = 'public.tick_arrivals_each_second(integer)');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0262 order by n loop
    v_n := pg_temp.occurs_0262(v_def, h.old);
    if v_n <> 1 then
      raise exception '0262 self-assert FAIL: hunk % occurs % time(s), not once — the live body is not what this file was cut against', h.n, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

-- ── 3. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b   record;
  v_d   record;
  v_h   record;
  v_pp  record;
  v_def text;
  v_a   jsonb;
  v_z   jsonb;
  v_x   jsonb;
  v_oid text := 'public.wc_int(text)'::regprocedure::oid::text;
begin
  select * into v_b from before_0262;

  -- (a) the hunks reverse to the pre-image; ACL / volatility / definer / config unmoved; the run untouched
  for v_d in select * from defs_before_0262 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0262 order by n desc loop
      if pg_temp.occurs_0262(v_def, v_h.new) <> 1 then
        raise exception '0262 self-assert FAIL: hunk % is not in the new body exactly once', v_h.n;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0262 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0262 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if md5(replace(pg_get_functiondef('public.tick_arrivals(timestamptz)'::regprocedure), E'\r', '')) <> v_b.run_md5 then
    raise exception '0262 self-assert FAIL: public.tick_arrivals moved';
  end if;

  -- (b) the profile is taken where the beat will take it: this role may SET LOCAL track_functions, and the
  -- readings then count a plpgsql call
  set local track_functions = 'all';
  v_a := public.beat_fn_reads();
  perform public.wc_int('npc_route_candidates') from generate_series(1, 3);
  v_z := public.beat_fn_reads();
  v_x := public.beat_fn_diff(v_a, v_z);
  if coalesce((v_x->v_oid->>0)::int, 0) < 3 or (v_x->'_'->>0)::int < 3 then
    raise exception '0262 self-assert FAIL: track_functions did not count three calls of wc_int (%)', v_x;
  end if;
  set local track_functions = 'none';
  if public.beat_fn_diff('{"1": [2, 5, 4]}', '{"1": [5, 9, 6], "2": [1, 1, 1]}')
     <> '{"1": [3, 4.0, 2.0], "2": [1, 1.0, 1.0], "_": [4, 3.0]}'::jsonb then
    raise exception '0262 self-assert FAIL: beat_fn_diff (%)', public.beat_fn_diff('{"1": [2, 5, 4]}', '{"1": [5, 9, 6], "2": [1, 1, 1]}');
  end if;
  if has_function_privilege('anon', 'public.beat_fn_reads()', 'execute')
     or has_function_privilege('authenticated', 'public.beat_fn_reads()', 'execute')
     or has_function_privilege('anon', 'public.beat_fn_diff(jsonb,jsonb)', 'execute') then
    raise exception '0262 self-assert FAIL: a client role can take the profile';
  end if;

  -- (c) POSTURE
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points then
    raise exception '0262 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0262 self-assert FAIL: a wall moved';
  end if;

  raise notice '0262 self-assert ok: ONE BEAT IN FOUR NAMES ITS FUNCTIONS. public.beat_fn_reads / beat_fn_diff minted (server-only); tick_arrivals_each_second re-cut by 3 hunks, reversed to its pre-image, ACL / volatility / definer / config unmoved; public.tick_arrivals unmoved (md5); SET LOCAL track_functions takes here and counted % calls of wc_int; registry unchanged; walls 0.',
    v_x->v_oid->>0;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0264 — A LAP START READS ONLY WHAT IT WEIGHS  (the arrivals beat's root cost, measured on prod)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ROOT, MEASURED ON PROD (0261 phase splits, 0262 per-function profile, 10-28 UTC) ────────
-- 0261, 952 beats outside the reconcile minutes: the `held` loop (a merchant's rest at home ends and cmd.advance
-- starts her next lap) is 44 % of the beat's run time and ~1.25 s of every beat over 1 s; ~550-600 ms a lap start.
-- The deferred purse checks (the ledger: the owner's lead suspect) are ~30 ms a beat, outside `ms`: not the cause.
-- Run time = the pages touched (0.53 ms a block read from outside shared_buffers + 13.7 µs a buffer hit, R² 0.94).
-- 0262, profiled beats with a lap start (mean run 1,672 ms): public.npc_plan 779 ms a beat (the lap start's re-plan),
-- of it npc_leg_lines 636 ms (world.trade_routes 373) and public.npc_loop_candidates 188 ms (155 ms of it in its own
-- SQL); the knob wrappers public.wc_num + public.wc 253 ms of their own time (10,262 calls a beat); 0261's own block
-- readings (public.beat_reads) 24 ms a beat, every beat.
-- The earlier local profiles (0250, 0256) timed port-time SAILs and arrivals, never a lap start's re-plan: that is
-- why their trims did not move prod.
--
-- ── WHAT THIS FILE DOES (every answer the same) ─────────────────────────────────────────────────
-- (1) public.npc_loop_candidates ranks the trade destinations from the goods either city MAKES (port_goods.haul_nm
--     = 0, ~6 of ~565 rows a port) through a new partial index, instead of reading every market row of every
--     destination and looking each up at home (~1,100 index visits a destination). Same maxima, same nulls: the
--     old filter kept a row when either side made the good, and each max reads only the rows of its own side.
--     One hunk.
-- (2) public.wc_num / public.wc_int: the same one expression, `(public.wc(k))::text::numeric[::integer]`, as SQL-
--     standard bodies (BEGIN ATOMIC: names bound when created) with no definer and no SET, so the planner inlines
--     them into their callers and each knob read is one definer call (public.wc, THE knob reader, untouched),
--     not two. ACL kept (CREATE OR REPLACE): a caller that may not execute them still may not (an inline is
--     refused without EXECUTE). public.wc keeps its definer and its fail-closed refusal.
-- (3) The beat (tick_arrivals_each_second, 2 hunks): 0261's block readings are taken in the profiled beats only
--     (one in four, 0262), not every beat. `reads` / `reads_defer` appear in those rows only.
--
-- ── THE PROOF ───────────────────────────────────────────────────────────────────────────────────
-- Old bodies kept in pg_temp. Old and new answer: npc_loop_candidates for the merchant routes (each at her home);
-- wc_num / wc_int for every knob (refusals compared as refusals); then the lap start's re-plan itself,
-- public.npc_plan(now, route), for merchant routes resting at home, each run twice in rolled-back blocks (old bodies
-- put back, then the new) and once more old as the control: the same answer and the same routes, stops, lines,
-- presets and fleets. And the plan of a knob read shows public.wc called directly (the wrapper inlined).
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- Forward slice: the three pre-images are verbatim below (wc_num, wc_int whole; candidates and the beat by hunk).
-- The index is additive.
--
-- VERSION: 0264 (prod head 0263).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.beat_fn_reads()') is null then
    raise exception '0264 refuses: 0262 is not in this world';
  end if;
  if to_regclass('public.port_goods_makes_0264') is not null then
    raise exception '0264 refuses: port_goods_makes_0264 already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0264(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table defs_before_0264 on commit drop as
select f.fn, f.name, f.old_name,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values
    ('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 'public.npc_loop_candidates', 'pg_temp.npc_loop_candidates_old_0264'),
    ('public.wc_num(text)', 'public.wc_num', 'pg_temp.wc_num_old_0264'),
    ('public.wc_int(text)', 'public.wc_int', 'pg_temp.wc_int_old_0264'),
    ('public.tick_arrivals_each_second(integer)', 'public.tick_arrivals_each_second', null)
  ) f(fn, name, old_name);

create temp table before_0264 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p
         where p.oid in ('public.wc(text)'::regprocedure, 'public.npc_plan(timestamptz,uuid)'::regprocedure,
                         'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'::regprocedure,
                         'public.tick_arrivals(timestamptz)'::regprocedure, 'public.credit(uuid,text,bigint,uuid)'::regprocedure)) as kept_md5;

-- the old bodies, for the comparison (the old candidates read the OLD wrappers)
do $$
declare
  d record;
  v_def text;
begin
  for d in select * from defs_before_0264 where old_name is not null loop
    if pg_temp.occurs_0264(d.def, 'FUNCTION ' || d.name || '(') <> 1 then
      raise exception '0264 self-assert FAIL: %''s definition does not name itself once', d.fn;
    end if;
    v_def := replace(d.def, 'FUNCTION ' || d.name || '(', 'FUNCTION ' || d.old_name || '(');
    if d.name = 'public.npc_loop_candidates' then
      v_def := replace(replace(v_def, 'public.wc_int(', 'pg_temp.wc_int_old_0264('), 'public.wc_num(', 'pg_temp.wc_num_old_0264(');
    end if;
    execute v_def;
  end loop;
end $$;

-- ── 2. THE KNOB WRAPPERS: one definer call a read, not two ──────────────────────────────────────
create or replace function public.wc_num(p_key text)
returns numeric
language sql
stable
security invoker
begin atomic
  select (public.wc(p_key))::text::numeric;
end;
comment on function public.wc_num(text) is
  '0264: a knob as a number: public.wc (THE knob reader, definer, fail-closed) cast. Inlined into its caller (no definer, no SET; names bound at creation), so a read is one definer call.';

create or replace function public.wc_int(p_key text)
returns integer
language sql
stable
security invoker
begin atomic
  select (public.wc(p_key))::text::numeric::integer;
end;
comment on function public.wc_int(text) is
  '0264: a knob as an integer: public.wc (THE knob reader, definer, fail-closed) cast. Inlined into its caller (no definer, no SET; names bound at creation), so a read is one definer call.';

-- ── 3. THE HUNKS ────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0264 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0264 (fn, n, old, new) values
('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 1,
$h$      left join lateral (
        select max(case when ph.haul_nm = 0 then pd.haul end) as out_haul,
               max(case when pd.haul_nm = 0 then ph.haul end) as back_haul
          from public.port_goods pd
          join public.port_goods ph on ph.port_id = p_home and ph.good_id = pd.good_id
         where pd.port_id = (dd.x->>'d')::uuid and (ph.haul_nm = 0 or pd.haul_nm = 0)) hh on true$h$,
$h$      -- 0264: each side's maximum from the goods that side's city MAKES (port_goods_makes_0264), the other city's row
      -- looked up by its key: the same two maxima the one join over every market row of D gave, and the same nulls
      left join lateral (
        select (select max(pd.haul)
                  from public.port_goods ph
                  join public.port_goods pd on pd.port_id = (dd.x->>'d')::uuid and pd.good_id = ph.good_id
                 where ph.port_id = p_home and ph.haul_nm = 0) as out_haul,
               (select max(ph.haul)
                  from public.port_goods pd
                  join public.port_goods ph on ph.port_id = p_home and ph.good_id = pd.good_id
                 where pd.port_id = (dd.x->>'d')::uuid and pd.haul_nm = 0) as back_haul) hh on true$h$),
('public.tick_arrivals_each_second(integer)', 1,
$h$    v_r0 := public.beat_reads();
    v_tq := null;$h$,
$h$    if v_prof then v_r0 := public.beat_reads(); end if;   -- 0264: the block readings in the profiled beats only
    v_tq := null;$h$),
('public.tick_arrivals_each_second(integer)', 2,
$h$    v_r1 := public.beat_reads();
    v_tp := clock_timestamp();
    set constraints all immediate;
    v_td := clock_timestamp();
    v_slot := (floor(extract(epoch from now()))::bigint % 3600)::int;
    v_sp := coalesce(nullif(current_setting('byeharu.beat_split', true), ''), '{}')::jsonb
         || jsonb_build_object('q', public.beat_ms(v_tq - v_t), 'run', public.beat_ms(v_tc - v_tq),
                               'defer', public.beat_ms(v_td - v_tp),
                               'reads', public.beat_reads_diff(v_r0, v_r1),
                               'reads_defer', public.beat_reads_diff(v_r1, public.beat_reads()));$h$,
$h$    if v_prof then v_r1 := public.beat_reads(); end if;   -- 0264
    v_tp := clock_timestamp();
    set constraints all immediate;
    v_td := clock_timestamp();
    v_slot := (floor(extract(epoch from now()))::bigint % 3600)::int;
    v_sp := coalesce(nullif(current_setting('byeharu.beat_split', true), ''), '{}')::jsonb
         || jsonb_build_object('q', public.beat_ms(v_tq - v_t), 'run', public.beat_ms(v_tc - v_tq),
                               'defer', public.beat_ms(v_td - v_tp));
    if v_prof then   -- 0264: the block readings, profiled beats only
      v_sp := v_sp || jsonb_build_object('reads', public.beat_reads_diff(v_r0, v_r1),
                                         'reads_defer', public.beat_reads_diff(v_r1, public.beat_reads()));
    end if;$h$);

do $$
declare
  d   record;
  h   record;
  v_def text;
  v_n int;
begin
  for d in select * from defs_before_0264 where fn in ('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)',
                                                       'public.tick_arrivals_each_second(integer)') loop
    v_def := d.def;
    for h in select * from hunks_0264 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0264(v_def, h.old);
      if v_n <> 1 then
        raise exception '0264 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 4. THE PROBE ────────────────────────────────────────────────────────────────────────────────
create temp table new_defs_0264 on commit drop as
select fn, replace(pg_get_functiondef(fn::regprocedure), E'\r', '') as def from defs_before_0264 where old_name is not null;
create or replace function pg_temp.put_0264(p_old boolean)
returns void
language plpgsql
as $$
declare d record;
begin
  if p_old then
    for d in select * from defs_before_0264 where old_name is not null order by fn desc loop execute d.def; end loop;
  else
    for d in select * from new_defs_0264 order by fn desc loop execute d.def; end loop;
  end if;
end $$;

-- one lap start's re-plan, in a block that is rolled back: its answer and what it wrote
create or replace function pg_temp.plan_0264(p_old boolean, p_route uuid)
returns text
language plpgsql
as $$
declare
  v_r jsonb;
  v_f uuid := (select sr.fleet_id from public.standing_routes sr where sr.id = p_route);
begin
  begin
    perform pg_temp.put_0264(p_old);
    v_r := public.npc_plan(now(), p_route);
    raise exception using errcode = 'ZY264', message = concat_ws(' | ',
      regexp_replace(v_r::text, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g'),
      (select md5(coalesce(string_agg((to_jsonb(sr) - 'updated_at')::text, ','), '')) from public.standing_routes sr where sr.id = p_route),
      (select md5(coalesce(string_agg(to_jsonb(s)::text, ',' order by s.ord), '')) from public.standing_route_stops s where s.route_id = p_route),
      (select md5(coalesce(string_agg(x, ',' order by x), '')) from (select (to_jsonb(l) - 'id')::text as x from public.standing_route_lines l where l.route_id = p_route) lx),
      (select md5(coalesce(string_agg(to_jsonb(pr)::text, ','), '')) from public.provision_presets pr
        where pr.id = (select f.provision_preset_id from public.fleets f where f.id = v_f)),
      (select md5(to_jsonb(f)::text) from public.fleets f where f.id = v_f));
  exception when sqlstate 'ZY264' then
    return sqlerrm;
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
  r      record;
  v_a    text;
  v_n    text;
  v_c    text;
  v_cand int := 0;
  v_rows int := 0;
  v_keys int := 0;
  v_plans int := 0;
  v_plan text;
begin
  select * into v_b from before_0264;

  -- (a) the hunks reverse; ACL / volatility kept; the wrappers no longer definer, no SET; the rest unmoved
  for v_d in select * from defs_before_0264 where fn in ('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)',
                                                         'public.tick_arrivals_each_second(integer)') loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0264 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0264(v_def, v_h.new) <> 1 then
        raise exception '0264 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0264 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
  end loop;
  for v_d in select * from defs_before_0264 loop
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol then
      raise exception '0264 self-assert FAIL: % changed its ACL or volatility', v_d.fn;
    end if;
    if v_d.fn in ('public.wc_num(text)', 'public.wc_int(text)') then
      if v_pp.secdef or v_pp.cfg <> '' then
        raise exception '0264 self-assert FAIL: % is still a definer or carries a SET', v_d.fn;
      end if;
    elsif v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0264 self-assert FAIL: % changed its definer or config', v_d.fn;
    end if;
  end loop;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p
       where p.oid in ('public.wc(text)'::regprocedure, 'public.npc_plan(timestamptz,uuid)'::regprocedure,
                       'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'::regprocedure,
                       'public.tick_arrivals(timestamptz)'::regprocedure, 'public.credit(uuid,text,bigint,uuid)'::regprocedure)) <> v_b.kept_md5 then
    raise exception '0264 self-assert FAIL: the knob reader, the planner, the leg planner, the run or the money door moved';
  end if;

  -- (b) THE WRAPPERS ARE INLINED: a knob read's plan calls public.wc, not the wrapper
  execute 'explain (verbose, costs off, format json) select public.wc_num(''time_compression''), public.wc_int(''npc_route_candidates'')' into v_plan;
  if v_plan not like '%wc(%' or v_plan like '%wc_num(%' or v_plan like '%wc_int(%' then
    raise exception '0264 self-assert FAIL: the wrappers are not inlined (%)', v_plan;
  end if;

  -- (c) OLD vs NEW knob reads: every knob, as a number and as an integer (refusals as refusals)
  for r in select key from public.world_config order by key loop
    begin v_a := pg_temp.wc_num_old_0264(r.key)::text; exception when others then v_a := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
    begin v_n := public.wc_num(r.key)::text; exception when others then v_n := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
    if v_a is distinct from v_n then raise exception '0264 self-assert FAIL: wc_num(%) old % new %', r.key, v_a, v_n; end if;
    begin v_a := pg_temp.wc_int_old_0264(r.key)::text; exception when others then v_a := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
    begin v_n := public.wc_int(r.key)::text; exception when others then v_n := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
    if v_a is distinct from v_n then raise exception '0264 self-assert FAIL: wc_int(%) old % new %', r.key, v_a, v_n; end if;
    v_keys := v_keys + 1;
  end loop;
  begin v_a := pg_temp.wc_num_old_0264('no such knob 0264')::text; exception when others then v_a := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
  begin v_n := public.wc_num('no such knob 0264')::text; exception when others then v_n := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
  if v_a is distinct from v_n or v_n not like 'ERR 22023%' then
    raise exception '0264 self-assert FAIL: a missing knob is refused differently (old % / new %)', v_a, v_n;
  end if;

  -- (d) OLD vs NEW candidates: up to 60 merchant routes, each at her first stop, with her hold and speed as the
  -- planner reads them (here a fixed hold and speed: the candidates' arithmetic is the same either way)
  for r in select sr.id as rid, sr.fleet_id as fid, st.port_id as home
             from public.standing_routes sr
             join public.players p on p.id = sr.player_id and p.is_npc
             join public.standing_route_stops st on st.route_id = sr.id and st.ord = 0
            where sr.fleet_id is not null
            order by sr.id limit 60 loop
    select coalesce(string_agg(to_jsonb(c)::text, ',' order by c.ord), '') into v_a
      from pg_temp.npc_loop_candidates_old_0264(r.rid, r.fid, r.home, 300, 6) with ordinality c(stops, kind, ord);
    select coalesce(string_agg(to_jsonb(c)::text, ',' order by c.ord), '') into v_n
      from public.npc_loop_candidates(r.rid, r.fid, r.home, 300, 6) with ordinality c(stops, kind, ord);
    if v_a is distinct from v_n then
      raise exception '0264 self-assert FAIL: npc_loop_candidates differs for route % — old % / new %', r.rid, left(v_a, 400), left(v_n, 400);
    end if;
    v_cand := v_cand + 1;
    v_rows := v_rows + (select count(*) from public.npc_loop_candidates(r.rid, r.fid, r.home, 300, 6));
  end loop;

  -- (e) THE LAP START ITSELF: npc_plan for up to 12 merchants resting at home (the held loop's case), old bodies,
  -- new bodies, old again (the control), each rolled back
  for r in select sr.id as rid
             from public.standing_routes sr
             join public.players p on p.id = sr.player_id and p.is_npc
             join public.fleets f on f.id = sr.fleet_id and f.status = 'DOCKED'
             join public.standing_route_stops st on st.route_id = sr.id and st.ord = 0 and st.port_id = f.port_id
            where sr.lap_id is null and sr.paused_reason is null
            order by sr.hold_until nulls last, sr.id limit 12 loop
    v_a := pg_temp.plan_0264(true, r.rid);
    v_n := pg_temp.plan_0264(false, r.rid);
    v_c := pg_temp.plan_0264(true, r.rid);
    if v_a is distinct from v_c then
      raise exception '0264 self-assert FAIL: the CONTROL differs (old plan against itself) for route % — % / %', r.rid, v_a, v_c;
    end if;
    if v_a is distinct from v_n then
      raise exception '0264 self-assert FAIL: the lap start''s plan differs for route % — old % / new %', r.rid, v_a, v_n;
    end if;
    v_plans := v_plans + 1;
  end loop;
  -- the bodies left in place are the new ones
  if replace(pg_get_functiondef('public.wc_num(text)'::regprocedure), E'\r', '') <> (select def from new_defs_0264 where fn = 'public.wc_num(text)')
     or replace(pg_get_functiondef('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)'::regprocedure), E'\r', '')
        <> (select def from new_defs_0264 where fn = 'public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)') then
    raise exception '0264 self-assert FAIL: the probe left an old body in place';
  end if;

  -- (f) POSTURE
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points then
    raise exception '0264 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0264 self-assert FAIL: a wall moved';
  end if;

  raise notice '0264 self-assert ok: A LAP START READS ONLY WHAT IT WEIGHS. npc_loop_candidates ranks from the goods each city makes (port_goods_makes_0264); wc_num / wc_int inlined (no definer, no SET, ACL kept; public.wc untouched); the beat takes its block readings in profiled beats only; hunks reversed, ACL / volatility unmoved; wc, npc_plan, npc_leg_lines, tick_arrivals, credit unmoved (md5). OLD vs NEW: % knobs (number and integer, and a missing one) alike; candidates for % routes (% loops) alike; the lap start''s re-plan (npc_plan) for % resting merchants alike, old against old alike, each rolled back. Registry unchanged; walls 0.',
    v_keys, v_cand, v_rows, v_plans;
end $$;

-- ── 6. THE INDEX: the goods a city makes (LAST: its SHARE lock on port_goods is then held only to the commit,
--    not through the probe; the probe compares answers, which do not depend on it) ─────────────────────
create index port_goods_makes_0264 on public.port_goods (port_id, good_id) where haul_nm = 0;
comment on index public.port_goods_makes_0264 is
  '0264: the goods each city makes (haul_nm = 0, 0173), for public.npc_loop_candidates'' rank of trade destinations.';

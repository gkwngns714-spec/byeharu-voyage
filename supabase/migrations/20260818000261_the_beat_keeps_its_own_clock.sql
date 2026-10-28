-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0261 — THE BEAT KEEPS ITS OWN CLOCK  (per-phase time splits of every arrivals beat, on prod)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, 2026-10-28 ───────────────────────────────────────────────────────────────────────
--   "Find the ROOT cause, then fix the root. No more guess-trims." 0248 / 0250 / 0256 trimmed what a LOCAL
--   profile showed, and prod barely moved: the beat's p95 is ~1.6-1.7 s outside the hourly reconcile. A prod
--   departure costs ~170 ms and a sale ~75-130 ms by the fit, against ~17 ms and ~8 ms locally, while the readers
--   timed alone are only 2-4x slower on prod. Prod shows no inner statement (pg_stat_statements.track = top,
--   track_functions = none, track_io_timing = off: superuser settings), so this file makes the beat say where
--   its time goes.
--
-- ── WHAT IS ALREADY KNOWN (prod, read-only, 2026-10-28 ~00:10 UTC) ──────────────────────────────
--   * The purse checks are DEFERRED constraint triggers (ledger_reconciles on ledger INSERT,
--     players_purse_reconciles on players INSERT/UPDATE, both INITIALLY DEFERRED). They run at the beat's
--     COMMIT, and the beat's `ms` stops before that commit. So whatever they cost is NOT in arrivals_beats.ms.
--   * 64 s of pg_stat_user_tables: ledger 608 index scans fetching 825,310 rows (~1,357 a scan) = exactly
--     304 ledger inserts + 304 player updates, one public.ledger_sum each.
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
-- (1) public.arrivals_beats gains `splits jsonb` (nullable): one object a beat, in ms —
--       q        the wait for the quay (public.hold_the_quay: an hourly upkeep step holding it)
--       run      public.tick_arrivals() (q + run = ms, exactly as before)
--       arrive   its first loop: the due voyages read FOR UPDATE and settled (sea-days, arrivals, the route
--                stop's sells / buys / lines, and the SAIL of a route that sails on)
--       repair   yard releases; held  routes held for pacing; wake  port time up (public.port_time_wake);
--       ask      the waiting-merchant slot (public.npc_ask_slot / npc_ask_waiting)
--       defer    the purse checks the commit would run, run just before it instead (SET CONSTRAINTS ALL
--                IMMEDIATE), timed
--       commit   the commit itself (the WAL flush), written into the row by the next transaction
--       reads / reads_defer   per table, [blocks read from outside shared_buffers, blocks found in them],
--                during the run and during the purse checks (pg_stat_get_xact_blocks_fetched / _hit; an
--                index's blocks count to its table, a toast table's to its owner)
--       probe    what taking those readings cost (the overhead of this file, measured every beat)
-- (2) public.beat_reads() / public.beat_reads_diff(jsonb, jsonb): the readings. Private, server-only.
-- (3) public.tick_arrivals: 6 hunks, each only ADDS a line that reads clock_timestamp() into its own two locals,
--     and one `set_config('byeharu.beat_split', …, true)` before the return. Nothing it decides, writes or
--     answers moves: its result is byte-identical (self-assert, old body vs new on the same state).
-- (4) public.tick_arrivals_each_second: 3 hunks. Same commits, same order, same sleep. The one moved thing:
--     the deferred purse checks fire at SET CONSTRAINTS ALL IMMEDIATE right before the beat's row is written,
--     not at the COMMIT right after it. The same checks, in the same order, in the same transaction; one that
--     fails aborts the procedure and rolls back the beat exactly as a failing COMMIT did.
--
-- ── WHAT IT DELIBERATELY DOES NOT ───────────────────────────────────────────────────────────────
-- Change any rule, knob, flag, grant, schedule or client read. Change what `ms` means (still the quay wait +
-- the run, so before/after windows compare). Touch credit, ledger_sum or the purse checks.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- A forward slice reversing the 9 hunks (every OLD text is here verbatim; the self-assert proves they reverse).
-- The column and the two readers are additive and harmless left in place.
--
-- VERSION: 0261 (prod head 0260).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.tick_arrivals(timestamptz)') is null
     or to_regprocedure('public.tick_arrivals_each_second(int)') is null
     or to_regclass('public.arrivals_beats') is null
     or to_regprocedure('public.hold_the_quay()') is null then
    raise exception '0261 refuses: 0248 / 0249 is not in this world';
  end if;
  if to_regprocedure('public.beat_reads()') is not null then
    raise exception '0261 refuses: public.beat_reads already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0261(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGE (LF-normalised) ────────────────────────────────────────────────────────────
create temp table defs_before_0261 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_arrivals(timestamp with time zone)'), ('public.tick_arrivals_each_second(integer)')) f(fn);

create temp table before_0261 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p
         where p.oid in ('public.credit(uuid,text,bigint,uuid)'::regprocedure, 'public.ledger_sum(uuid)'::regprocedure,
                         'public.assert_ledger_reconciles(uuid)'::regprocedure, 'public.hold_the_quay()'::regprocedure,
                         'public.tg_reconcile_from_ledger()'::regprocedure, 'public.tg_reconcile_from_player()'::regprocedure)) as money_md5;

-- the old run, kept for the self-assert's comparison
do $$
declare
  v_def text := (select def from defs_before_0261 where fn = 'public.tick_arrivals(timestamp with time zone)');
begin
  if pg_temp.occurs_0261(v_def, 'FUNCTION public.tick_arrivals(') <> 1 then
    raise exception '0261 self-assert FAIL: tick_arrivals'' definition does not name itself once';
  end if;
  execute replace(v_def, 'FUNCTION public.tick_arrivals(', 'FUNCTION pg_temp.tick_arrivals_old_0261(');
end $$;

-- ── 1. THE COLUMN AND THE READINGS ──────────────────────────────────────────────────────────────
alter table public.arrivals_beats add column splits jsonb;
comment on column public.arrivals_beats.splits is
  '0261: where the beat''s time went, in ms: q (quay wait), run (tick_arrivals; q + run = ms), arrive / repair / held / wake / ask (its loops), defer (the deferred purse checks, run just before the commit), commit (the commit, written by the next transaction), reads / reads_defer (per table [blocks read from outside shared_buffers, blocks hit], during the run and the checks), probe (what the readings cost). One writer: public.tick_arrivals_each_second.';

create function public.beat_ms(p interval)
returns numeric
language sql
immutable
set search_path = pg_catalog
as $$ select round(extract(epoch from p)::numeric * 1000, 1) $$;
comment on function public.beat_ms(interval) is '0261: an interval in ms, to 0.1 — the beat''s splits. Server-only.';
revoke all on function public.beat_ms(interval) from public, anon, authenticated;

create function public.beat_reads()
returns jsonb
language sql
volatile
set search_path = pg_catalog
as $$
  -- 0261: this backend's block counters, per table of the game's schemas: {table: [fetched, hit]}. They only
  -- grow inside one CALL (flushed when the session goes idle), so two readings' difference is what lay between.
  -- An index counts to its table, a toast table (and its index) to the table that owns it.
  select coalesce(jsonb_object_agg(x.t, jsonb_build_array(x.f, x.h)), '{}'::jsonb)
    from (select coalesce(own.oid, base.oid)::regclass::text as t,
                 sum(pg_stat_get_xact_blocks_fetched(c.oid)) as f, sum(pg_stat_get_xact_blocks_hit(c.oid)) as h
            from pg_class c
            join pg_namespace n on n.oid = c.relnamespace
            left join pg_index i on i.indexrelid = c.oid
            join pg_class base on base.oid = coalesce(i.indrelid, c.oid)
            left join pg_class own on own.reltoastrelid = base.oid and base.relkind = 't'
           where c.relkind in ('r', 'i', 't')
             and (n.nspname in ('public', 'world', 'voyage', 'cmd')
                  or (n.nspname = 'pg_toast' and exists (select 1 from pg_class o join pg_namespace on2 on on2.oid = o.relnamespace
                                                          where o.reltoastrelid = base.oid
                                                            and on2.nspname in ('public', 'world', 'voyage', 'cmd'))))
           group by 1) x
   where x.f > 0
$$;
comment on function public.beat_reads() is
  '0261: this backend''s block counters per game table, {table: [fetched, hit]} (indexes and toast counted to their table). For the arrivals beat''s splits. Server-only.';
revoke all on function public.beat_reads() from public, anon, authenticated;

create function public.beat_reads_diff(p_a jsonb, p_b jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  -- 0261: what lay between two readings: {table: [read from outside shared_buffers, hit]} for every table that
  -- moved, and "_" = the totals.
  with d as (
    select b.key as t,
           greatest(((b.value->>0)::bigint - coalesce((p_a->b.key->>0)::bigint, 0))
                  - ((b.value->>1)::bigint - coalesce((p_a->b.key->>1)::bigint, 0)), 0) as rd,
           greatest((b.value->>1)::bigint - coalesce((p_a->b.key->>1)::bigint, 0), 0) as ht
      from jsonb_each(coalesce(p_b, '{}'::jsonb)) b)
  select coalesce(jsonb_object_agg(d.t, jsonb_build_array(d.rd, d.ht)) filter (where d.rd + d.ht > 0), '{}'::jsonb)
         || jsonb_build_object('_', jsonb_build_array(coalesce(sum(d.rd), 0), coalesce(sum(d.ht), 0)))
    from d
$$;
comment on function public.beat_reads_diff(jsonb, jsonb) is
  '0261: two public.beat_reads() readings'' difference, {table: [read, hit]} plus "_" the totals. Server-only.';
revoke all on function public.beat_reads_diff(jsonb, jsonb) from public, anon, authenticated;

-- ── 2. THE HUNKS ────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0261 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0261 (fn, n, old, new) values
-- tick_arrivals: two locals, a reading after each loop, the splits handed to the beat
('public.tick_arrivals(timestamp with time zone)', 1,
$h$  v_asked   jsonb;   -- 0182: the waiting merchants this sweep asked (public.npc_ask_waiting)
begin
$h$,
$h$  v_asked   jsonb;   -- 0182: the waiting merchants this sweep asked (public.npc_ask_waiting)
  v_tp      timestamptz := clock_timestamp();   -- 0261: the splits (read by the beat; nothing here reads them)
  v_sp      jsonb := '{}'::jsonb;
begin
$h$),
('public.tick_arrivals(timestamp with time zone)', 2,
$h$    v_days   := v_days + voyage.settle(r.fleet_id, p_now);
    v_fleets := v_fleets + 1;
  end loop;
$h$,
$h$    v_days   := v_days + voyage.settle(r.fleet_id, p_now);
    v_fleets := v_fleets + 1;
  end loop;
  v_sp := v_sp || jsonb_build_object('arrive', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0261
$h$),
('public.tick_arrivals(timestamp with time zone)', 3,
$h$    perform cmd.advance(r.id, p_now);
    v_fleets := v_fleets + 1;
  end loop;

  -- 0092:$h$,
$h$    perform cmd.advance(r.id, p_now);
    v_fleets := v_fleets + 1;
  end loop;
  v_sp := v_sp || jsonb_build_object('repair', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0261

  -- 0092:$h$),
('public.tick_arrivals(timestamp with time zone)', 4,
$h$    update public.standing_routes set hold_until = null where fleet_id = r.id;
    perform cmd.advance(r.id, p_now);
    v_fleets := v_fleets + 1;
  end loop;
$h$,
$h$    update public.standing_routes set hold_until = null where fleet_id = r.id;
    perform cmd.advance(r.id, p_now);
    v_fleets := v_fleets + 1;
  end loop;
  v_sp := v_sp || jsonb_build_object('held', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0261
$h$),
('public.tick_arrivals(timestamp with time zone)', 5,
$h$  v_fleets := v_fleets + public.port_time_wake(p_now, v_t0 + v_budget);
$h$,
$h$  v_fleets := v_fleets + public.port_time_wake(p_now, v_t0 + v_budget);
  v_sp := v_sp || jsonb_build_object('wake', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0261
$h$),
('public.tick_arrivals(timestamp with time zone)', 6,
$h$  return jsonb_build_object('fleets_touched', v_fleets, 'days_resolved', v_days, 'at', p_now,$h$,
$h$  v_sp := v_sp || jsonb_build_object('ask', public.beat_ms(clock_timestamp() - v_tp));   -- 0261
  perform set_config('byeharu.beat_split', v_sp::text, true);   -- 0261: for the beat's row (this transaction only)
  return jsonb_build_object('fleets_touched', v_fleets, 'days_resolved', v_days, 'at', p_now,$h$),
-- the beat: its locals, the first reading, the quay's instant, the splits, the timed checks and commit
('public.tick_arrivals_each_second(integer)', 1,
$h$  v_err    text;
begin
$h$,
$h$  v_err    text;
  v_slot   int;           -- 0261: the splits (public.arrivals_beats.splits)
  v_tq     timestamptz;
  v_tc     timestamptz;
  v_tp     timestamptz;
  v_td     timestamptz;
  v_p0     interval;
  v_r0     jsonb;
  v_r1     jsonb;
  v_sp     jsonb;
begin
$h$),
('public.tick_arrivals_each_second(integer)', 2,
$h$    v_t := clock_timestamp();
    v_err := null;
    begin
      perform public.hold_the_quay();   -- 0249: never beside an hourly upkeep step (no deadlock between them)
      v_r := public.tick_arrivals();$h$,
$h$    v_tp := clock_timestamp();   -- 0261: the first reading (not in ms)
    v_r0 := public.beat_reads();
    v_tq := null;
    v_p0 := clock_timestamp() - v_tp;
    v_t := clock_timestamp();
    v_err := null;
    begin
      perform public.hold_the_quay();   -- 0249: never beside an hourly upkeep step (no deadlock between them)
      v_tq := clock_timestamp();   -- 0261: the quay is this beat's
      v_r := public.tick_arrivals();$h$),
('public.tick_arrivals_each_second(integer)', 3,
$h$    insert into public.arrivals_beats (slot, at, ms, fleets, days, asked, error)
    values ((floor(extract(epoch from now()))::bigint % 3600)::int, now(),
            round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 1),
            (v_r->>'fleets_touched')::int, (v_r->>'days_resolved')::int, (v_r->>'asked')::int, v_err)
    on conflict (slot) do update
      set at = excluded.at, ms = excluded.ms, fleets = excluded.fleets, days = excluded.days,
          asked = excluded.asked, error = excluded.error;
    commit;
$h$,
$h$    -- 0261: THE SPLITS. ms ends where it always ended (v_tc). Then the deferred purse checks, which the commit
    -- below ran, run here and are timed: the same checks, in the same order, in this same transaction; one that
    -- fails aborts this procedure and rolls this beat back, as a failing commit did.
    v_tc := clock_timestamp();
    v_r1 := public.beat_reads();
    v_tp := clock_timestamp();
    set constraints all immediate;
    v_td := clock_timestamp();
    v_slot := (floor(extract(epoch from now()))::bigint % 3600)::int;
    v_sp := coalesce(nullif(current_setting('byeharu.beat_split', true), ''), '{}')::jsonb
         || jsonb_build_object('q', public.beat_ms(v_tq - v_t), 'run', public.beat_ms(v_tc - v_tq),
                               'defer', public.beat_ms(v_td - v_tp),
                               'reads', public.beat_reads_diff(v_r0, v_r1),
                               'reads_defer', public.beat_reads_diff(v_r1, public.beat_reads()));
    v_sp := v_sp || jsonb_build_object('probe', public.beat_ms(v_p0 + (v_tp - v_tc) + (clock_timestamp() - v_td)));
    insert into public.arrivals_beats (slot, at, ms, fleets, days, asked, error, splits)
    values (v_slot, now(),
            round(extract(epoch from v_tc - v_t)::numeric * 1000, 1),
            (v_r->>'fleets_touched')::int, (v_r->>'days_resolved')::int, (v_r->>'asked')::int, v_err, v_sp)
    on conflict (slot) do update
      set at = excluded.at, ms = excluded.ms, fleets = excluded.fleets, days = excluded.days,
          asked = excluded.asked, error = excluded.error, splits = excluded.splits;
    v_tc := clock_timestamp();
    commit;
    -- 0261: the commit's own time, into its row (this lands with the next commit, the one before the next beat)
    update public.arrivals_beats set splits = splits || jsonb_build_object('commit', public.beat_ms(clock_timestamp() - v_tc))
     where slot = v_slot;
$h$);

create or replace function pg_temp.recut_0261(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0261 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0261 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0261(v_def, h.old);
    if v_n <> 1 then
      raise exception '0261 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0261(fn) from defs_before_0261 order by fn;

-- ── 3. THE PROBE: the old run and the new one, from the same state, rolled back ─────────────────
-- What a run leaves: its answer, and a digest of what it can move (the at-sea voyages, the fleets, the ships,
-- the purses, the quays' stock, the cities' purses, and this transaction's ledger rows and events, uuids blanked).
create or replace function pg_temp.digest_0261()
returns text
language sql
as $$
  select concat_ws(' | ',
    (select md5(coalesce(string_agg((to_jsonb(v) - 'id')::text, ',' order by v.fleet_id, v.departed_at), '')) from public.voyages v where v.status = 'SAILING'),
    (select md5(coalesce(string_agg(to_jsonb(f)::text, ',' order by f.id), '')) from public.fleets f),
    (select md5(coalesce(string_agg(to_jsonb(s)::text, ',' order by s.id), '')) from public.ships s),
    (select md5(coalesce(string_agg(p.id::text || ':' || p.ducats, ',' order by p.id), '')) from public.players p),
    (select md5(coalesce(string_agg(g.port_id::text || g.good_id::text || ':' || g.stock, ',' order by g.port_id, g.good_id), '')) from public.port_goods g),
    (select md5(coalesce(string_agg(p.id::text || ':' || public.treasury_balance(p.id), ',' order by p.id), '')) from public.ports p),
    (select coalesce(count(*), 0) || ' ' || md5(coalesce(string_agg(l.player_id::text || l.kind || l.ducats_delta || ':' || l.balance_after,
                                                     ',' order by l.player_id, l.kind, l.ducats_delta, l.balance_after), ''))
       from public.players p join public.ledger l on l.player_id = p.id and l.created_at = now()),
    (select coalesce(count(*), 0) || ' ' || md5(coalesce(string_agg(x, ',' order by x), ''))
       from (select e.player_id::text || e.kind
                    || regexp_replace(e.payload::text, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g') as x
               from public.players p join public.events e on e.player_id = p.id and e.created_at = now()) ev))
$$;

create or replace function pg_temp.arm_0261(p_new boolean, p_now timestamptz)
returns jsonb
language plpgsql
as $$
declare
  v_r jsonb;
begin
  begin
    if p_new then v_r := public.tick_arrivals(p_now); else v_r := pg_temp.tick_arrivals_old_0261(p_now); end if;
    raise exception using errcode = 'ZY261',
      message = jsonb_build_object('r', v_r, 'd', pg_temp.digest_0261(),
                                   's', nullif(current_setting('byeharu.beat_split', true), '')::jsonb)::text;
  exception when sqlstate 'ZY261' then
    return sqlerrm::jsonb;
  end;
end $$;

-- ── 4. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b    record;
  v_d    record;
  v_h    record;
  v_pp   record;
  v_def  text;
  v_now  timestamptz;
  v_a    jsonb;
  v_n    jsonb;
  v_c    jsonb;
  v_due  int;
  v_x    jsonb;
begin
  select * into v_b from before_0261;

  -- (a) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0261 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0261 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0261(v_def, v_h.new) <> 1 then
        raise exception '0261 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0261 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0261 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;

  -- (b) the money and the quay are untouched; the splits' GUC has one writer and one reader
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p
       where p.oid in ('public.credit(uuid,text,bigint,uuid)'::regprocedure, 'public.ledger_sum(uuid)'::regprocedure,
                       'public.assert_ledger_reconciles(uuid)'::regprocedure, 'public.hold_the_quay()'::regprocedure,
                       'public.tg_reconcile_from_ledger()'::regprocedure, 'public.tg_reconcile_from_player()'::regprocedure)) <> v_b.money_md5 then
    raise exception '0261 self-assert FAIL: the money doors or the quay lock moved';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not like 'pg_temp%' and p.prosrc like '%byeharu.beat_split%') <> 2 then
    raise exception '0261 self-assert FAIL: byeharu.beat_split is named outside tick_arrivals and the beat';
  end if;
  if exists (select 1 from pg_trigger t where t.tgrelid = 'public.arrivals_beats'::regclass and not t.tgisinternal)
     or exists (select 1 from pg_constraint c where c.conrelid = 'public.arrivals_beats'::regclass and c.condeferrable) then
    raise exception '0261 self-assert FAIL: arrivals_beats carries a trigger or a deferrable constraint (the row is written after SET CONSTRAINTS)';
  end if;

  -- (c) the readings work, and are private
  v_x := public.beat_reads();
  if jsonb_typeof(v_x) <> 'object'
     or public.beat_reads_diff(v_x, v_x) <> '{"_": [0, 0]}'::jsonb
     or public.beat_reads_diff('{"public.t": [5, 2]}', '{"public.t": [9, 3], "public.u": [1, 1]}')
        <> '{"public.t": [3, 1], "public.u": [0, 1], "_": [3, 2]}'::jsonb then
    raise exception '0261 self-assert FAIL: the readings do not read (% / %)', v_x,
      public.beat_reads_diff('{"public.t": [5, 2]}', '{"public.t": [9, 3], "public.u": [1, 1]}');
  end if;
  if has_function_privilege('anon', 'public.beat_reads()', 'execute')
     or has_function_privilege('authenticated', 'public.beat_reads()', 'execute')
     or has_function_privilege('anon', 'public.beat_reads_diff(jsonb,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.beat_ms(interval)', 'execute') then
    raise exception '0261 self-assert FAIL: a client role can take the readings';
  end if;

  -- (d) OLD RUN vs NEW RUN, from the same state, each rolled back: the same answer and the same digest, three
  -- times (old, new, old — the second old is the control). The instant: the first due voyage's, plus 20 s
  -- (a run cut short by its wall-clock budget would compare a different amount of work), never past now.
  v_now := least(now(), coalesce((select min(v.due_at) from public.voyages v where v.status = 'SAILING'), now()) + interval '20 seconds');
  select count(*) into v_due from public.voyages v where v.status = 'SAILING' and v.due_at <= v_now;
  v_a := pg_temp.arm_0261(false, v_now);
  v_n := pg_temp.arm_0261(true, v_now);
  v_c := pg_temp.arm_0261(false, v_now);
  if v_a->'r' <> v_c->'r' or v_a->>'d' <> v_c->>'d' then
    raise exception '0261 self-assert FAIL: the CONTROL differs (the old run against itself) — % / %', v_a, v_c;
  end if;
  if v_n->'r' <> v_a->'r' or v_n->>'d' <> v_a->>'d' then
    raise exception '0261 self-assert FAIL: the new run differs from the old — old % / new %', v_a, v_n;
  end if;
  if v_a->'s' is not null and v_a->>'s' <> 'null' then
    raise exception '0261 self-assert FAIL: the old run wrote splits';
  end if;
  if not (v_n->'s' ?& array['arrive', 'repair', 'held', 'wake', 'ask']) then
    raise exception '0261 self-assert FAIL: the new run handed no splits (%)', v_n->'s';
  end if;
  if nullif(current_setting('byeharu.beat_split', true), '') is not null then
    raise exception '0261 self-assert FAIL: the splits outlived the rolled-back run';
  end if;

  -- (e) POSTURE
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points then
    raise exception '0261 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0261 self-assert FAIL: a wall moved';
  end if;

  raise notice '0261 self-assert ok: THE BEAT KEEPS ITS OWN CLOCK. arrivals_beats.splits added; public.beat_ms / beat_reads / beat_reads_diff minted (server-only); tick_arrivals (6 hunks) and tick_arrivals_each_second (3 hunks) re-cut, each reversed to its pre-image, ACL / volatility / definer / config unmoved; credit, ledger_sum, the purse checks and the quay lock unmoved; byeharu.beat_split written by tick_arrivals and read by the beat only. OLD vs NEW run at % (% voyage(s) due), each rolled back: answer % alike, digest alike (control: old against old alike); the new run handed splits %. Registry unchanged; walls 0. Nothing left behind.',
    v_now, v_due, v_a->'r', v_n->'s';
end $$;

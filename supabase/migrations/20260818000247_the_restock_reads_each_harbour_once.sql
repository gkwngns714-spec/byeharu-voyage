-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0247 — THE RESTOCK READS EACH HARBOUR ONCE  (the game-day's drift run: 65-95 s → seconds, same numbers)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE DEFECT, MEASURED (prod, read-only, 2026-10-27) ──────────────────────────────────────────
-- cron byeharu-voyage:drift (`call public.tick_market_drift_each_port()`, */10) over 48 h: 288 runs, all
-- succeeded. Every run is 1-7 s EXCEPT the first run after a game-day boundary (game_day_seconds 2880 = 48 min,
-- so the slow runs fall 40 or 50 minutes apart: 07:20, 08:00, 08:50, 09:40, …). Those are the runs where
-- public.tick_market_drift's REGENERATION update has rows to write (last_regen_day < the new day) — all
-- 138,990 port_goods rows, ~535 a harbour, 260 harbours.
--   * before 0245 (to 2026-10-26 12:00 UTC): the day's run 30-50 s.
--   * 0245 merged 12:40 UTC; from the 12:50 run on: 64-95 s (p50 ~68 s, max 95.3 s at 10-27 04:00).
--   * pg_stat_statements (since 10-20): `call public.tick_market_drift_each_port()` 996 calls, mean 9.3 s,
--     max 95.3 s. No run overlapped its own next run (max 95 s < the 600 s cadence); slow runs fall on every
--     minute of the hour (:00 :10 … :50) and every hour alike — the cause is the day, not a neighbour job.
-- The drift step (the same 138,990 rows, every run whose 900 s slot has turned) costs 1-4 s. The regen
-- update writes the same rows; the difference is what it evaluates PER ROW:
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
-- public.tick_market_drift (0010 / 0123 / 0137 / 0170 / 0194 / 0245), the §G.2 regen update, per row:
--   public.restock_rate(pg.port_id)          (0245)  → public.restock_lit() → public.wc, public.economy_closed()
--                                                      + a port_treasury read + public.wc_num
--   public.works_factor(pg.port_id, …)       (0123)  → public.city_level twice + public.wc_num
--   public.wc_num('glut_decay')              (0194)
-- Every one is SECURITY DEFINER with `SET search_path`, so none is inlined: each is a full function call
-- with a GUC save/restore, ~a dozen of them for every row, ~1.7 million a game-day. 0245 swapped the
-- once-per-call `v_rate` variable for the per-row restock_rate and doubled the day's run (38 → 68 s).
-- Every one of those values depends on the HARBOUR only (and the knobs), never on the row.
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
-- Re-cuts the regen update of public.tick_market_drift (ONE hunk): the three readers move into a
-- MATERIALIZED CTE over public.ports (one row a harbour: the one harbour asked for, or all), joined by
-- port_id. MATERIALIZED, because an inlined CTE would be pulled up and its calls evaluated per row again.
-- The same STABLE readers, called in the same statement (so from the same snapshot), with the same
-- arguments: the same rate, works factor and decay land on every row, so stock, glut, last_regen_day and
-- updated_at are byte-identical. port_goods.port_id is a NOT NULL foreign key to ports (prod: 0 orphans),
-- so the inner join drops no row. The drift step, the procedure, the cron schedule: untouched.
--
-- ── WHAT IT DELIBERATELY DOES NOT ───────────────────────────────────────────────────────────────
-- Change any knob or flag (restock_by_investment, economy_close_switch, stock_regen_fraction, glut_decay,
-- production_per_level: as found), any rule, any grant, any client read. price_path / price_outlook are
-- per-good readers (one harbour's few rows) and keep their calls.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- A forward migration restoring tick_market_drift: the OLD hunk is in this file (hunks_0247.old) and the
-- self-assert proves the live body reverses to its pre-image by it.
--
-- SUPERSEDES: public.tick_market_drift (0137 as cut by 0170 / 0194 / 0245) — one hunk sliced from the LIVE
-- body (LF-normalised), asserted to occur exactly once. Self-assert: own probe rows only, rolled back.
-- VERSION: 0247 (prod head 0246). The OLD hunk checked on prod at head 0246.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.restock_rate(uuid)') is null
     or to_regprocedure('public.works_factor(uuid,text,text)') is null
     or to_regprocedure('public.stock_after(numeric,numeric,numeric,numeric,numeric)') is null then
    raise exception '0247 refuses: 0123 / 0170 / 0245 is not in this world';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0247(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGE (LF-normalised) ────────────────────────────────────────────────────────────
create temp table defs_before_0247 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_market_drift(timestamp with time zone,uuid)')) f(fn);

create temp table before_0247 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

-- the old body, kept for the self-assert's comparison run
do $$
begin
  if pg_temp.occurs_0247((select def from defs_before_0247), 'FUNCTION public.tick_market_drift(') <> 1 then
    raise exception '0247 self-assert FAIL: tick_market_drift''s definition does not name itself once';
  end if;
  execute replace((select def from defs_before_0247), 'FUNCTION public.tick_market_drift(', 'FUNCTION pg_temp.tick_market_drift_old_0247(');
end $$;

-- ── 1. THE RE-CUT (public.tick_market_drift, the regen update) ──────────────────────────────────
create temp table hunks_0247 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0247 (fn, n, old, new) values
('public.tick_market_drift(timestamp with time zone,uuid)', 1,
$h$  update public.port_goods pg
     set stock = public.stock_after(pg.stock, pg.stock_target, public.restock_rate(pg.port_id),   -- 0170: the rule, one leaf (the outlook steps it); 0245: at the harbour's own rate
                   pg.production_rate * public.works_factor(pg.port_id, 'production', 'production_per_level'),   -- 0123
                   v_day - pg.last_regen_day),
         glut = round(pg.glut * power(1 - public.wc_num('glut_decay'), v_day - pg.last_regen_day), 4),   -- 0194: the glut fades
         last_regen_day = v_day,
         updated_at = p_now
   where pg.last_regen_day < v_day
     and (p_port is null or pg.port_id = p_port);   -- 0137: one harbour, when one is asked for
$h$,
$h$  -- 0247: the harbour's rate, its works and the glut decay are read ONCE A HARBOUR (f), not once a row: the
  -- same readers in the same statement, so the same values on every row. MATERIALIZED, or the planner pulls
  -- the calls back up into the row loop (they cost the game-day's run 65-95 s on prod, 2026-10-27).
  with f as materialized (
    select po.id as port_id,
           public.restock_rate(po.id) as rate,   -- 0245: the harbour's own rate
           public.works_factor(po.id, 'production', 'production_per_level') as works,   -- 0123
           public.wc_num('glut_decay') as glut_decay   -- 0194
      from public.ports po
     where (p_port is null or po.id = p_port)
  )
  update public.port_goods pg
     set stock = public.stock_after(pg.stock, pg.stock_target, f.rate,   -- 0170: the rule, one leaf (the outlook steps it); 0245: at the harbour's own rate
                   pg.production_rate * f.works,   -- 0123
                   v_day - pg.last_regen_day),
         glut = round(pg.glut * power(1 - f.glut_decay, v_day - pg.last_regen_day), 4),   -- 0194: the glut fades
         last_regen_day = v_day,
         updated_at = p_now
    from f
   where f.port_id = pg.port_id
     and pg.last_regen_day < v_day
     and (p_port is null or pg.port_id = p_port);   -- 0137: one harbour, when one is asked for
$h$);

create or replace function pg_temp.recut_0247(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0247 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0247 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0247(v_def, h.old);
    if v_n <> 1 then
      raise exception '0247 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0247(fn) from defs_before_0247 order by fn;

-- ── 2. THE PROBE: one harbour regenerated three days on, by the old body and by the new ─────────
-- Inside a rolled-back block: the harbour's rows are set three game-days behind, half stocked, glutted,
-- producing, its drift slot already current (so the random drift step writes nothing), and a production
-- works level 3 (so the works factor is not 1). Then ONE body runs on it; the block answers what it saw
-- (a digest of every row) and is rolled back. Both bodies start from the same state.
create or replace function pg_temp.probe_0247(p_new boolean, p_port uuid)
returns jsonb
language plpgsql
as $$
declare
  v_day int := world.game_day(now());
  v_j   jsonb;
  v_t0  timestamptz;
  v_res jsonb;
begin
  begin
    update public.port_goods pg
       set last_regen_day  = v_day - 3,
           drift_slot      = public.drift_slot_of(now()),
           stock           = round(pg.stock_target * 0.4, 2),
           glut            = 0.3,
           production_rate = 2.5
     where pg.port_id = p_port;
    insert into public.city_works (port_id, kind, level, subscribed, updated_at)
    values (p_port, 'production', 3, 0, now())
    on conflict (port_id, kind) do update set level = 3;
    v_t0 := clock_timestamp();
    if p_new then
      v_j := public.tick_market_drift(now(), p_port);
    else
      v_j := pg_temp.tick_market_drift_old_0247(now(), p_port);
    end if;
    select jsonb_build_object(
             'ret', v_j,
             'ms', round(extract(epoch from clock_timestamp() - v_t0)::numeric * 1000, 1),
             'n', count(*),
             'at_day', count(*) filter (where pg.last_regen_day = v_day),
             'restocked', count(*) filter (where pg.stock > round(pg.stock_target * 0.4, 2)),
             'faded', count(*) filter (where pg.glut < 0.3),
             'works', public.works_factor(p_port, 'production', 'production_per_level'),
             'digest', md5(string_agg(concat_ws('|', pg.good_id, pg.stock, pg.glut, pg.last_regen_day, pg.drift,
                                                pg.drift_slot, pg.updated_at), ',' order by pg.good_id)))
      into v_res
      from public.port_goods pg
     where pg.port_id = p_port;
    raise exception using errcode = 'ZY247', message = v_res::text;
  exception when sqlstate 'ZY247' then
    return sqlerrm::jsonb;
  end;
end $$;

-- ── 3. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_before record;
  v_d record; v_h record; v_pp record; v_def text;
  v_port   uuid;
  v_ports  uuid[];
  v_old    jsonb;
  v_new    jsonb;
  v_seen   text := '';
  v_moved  int := 0;
begin
  select * into v_before from before_0247;

  -- (a) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0247 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0247 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0247(v_def, v_h.new) <> 1 then
        raise exception '0247 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0247 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0247 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  -- the regen update reads no reader per row any more
  v_def := replace(pg_get_functiondef('public.tick_market_drift(timestamp with time zone,uuid)'::regprocedure), E'\r', '');
  if position('restock_rate(pg.' in v_def) > 0 or position('works_factor(pg.' in v_def) > 0
     or position('as materialized' in v_def) = 0 then
    raise exception '0247 self-assert FAIL: tick_market_drift still calls a reader per row, or lost its materialised CTE';
  end if;

  -- (b) SAME NUMBERS: the old body and the new on the same harbours from the same state, row for row
  v_ports := array(
    select distinct x.id from (
      (select p.id from public.ports p where p.code = 'FNC' and p.kind = 'HARBOUR')
      union all
      (select t.port_id from public.port_treasury t order by t.port_id limit 1)
      union all
      (select w.port_id from public.city_works w where w.kind = 'production' and w.level > 0
        order by w.level desc, w.port_id limit 1)
    ) x
    where exists (select 1 from public.port_goods pg where pg.port_id = x.id));
  if coalesce(array_length(v_ports, 1), 0) = 0 then
    raise exception '0247 self-assert FAIL: no harbour with market rows to probe';
  end if;
  foreach v_port in array v_ports loop
    v_old := pg_temp.probe_0247(false, v_port);
    v_new := pg_temp.probe_0247(true, v_port);
    if (v_new->>'n')::int = 0 or (v_new->>'at_day') is distinct from (v_new->>'n')
       or (v_new->'ret'->>'regenerated') is distinct from (v_new->>'n') then
      raise exception '0247 self-assert FAIL: harbour %: the new body regenerated % of % row(s) (%)', v_port, v_new->>'at_day', v_new->>'n', v_new;
    end if;
    if (v_new->>'works')::numeric = 1 then
      raise exception '0247 self-assert FAIL: harbour %: the probe''s works factor is 1, the works term is unproven', v_port;
    end if;
    if v_old->>'digest' is distinct from v_new->>'digest' or v_old->'ret' is distinct from v_new->'ret'
       or v_old->>'n' is distinct from v_new->>'n' then
      raise exception '0247 self-assert FAIL: harbour %: the new body wrote other numbers than the old (old %, new %)', v_port, v_old, v_new;
    end if;
    v_moved := v_moved + (v_new->>'restocked')::int + (v_new->>'faded')::int;
    v_seen := v_seen || format(' [%s rows: %s restocked, %s faded, works %s; old %s ms, new %s ms]',
                               v_new->>'n', v_new->>'restocked', v_new->>'faded', v_new->>'works', v_old->>'ms', v_new->>'ms');
  end loop;
  if v_moved = 0 then
    raise exception '0247 self-assert FAIL: the probe moved no stock and faded no glut — the comparison proved nothing';
  end if;

  -- (c) POSTURE
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0247 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0247 self-assert FAIL: a wall moved';
  end if;

  raise notice '0247 self-assert ok: THE RESTOCK READS EACH HARBOUR ONCE. tick_market_drift''s regen update reads restock_rate, works_factor and glut_decay once a harbour (materialised CTE), one hunk, reverses to its pre-image, ACL / volatility / definer / config unmoved; registry unchanged; walls 0. PROBE (% harbour(s), three game-days behind, works level 3, rolled back): the old body and the new wrote byte-identical rows%. Nothing left behind.',
    array_length(v_ports, 1), v_seen;
end $$;

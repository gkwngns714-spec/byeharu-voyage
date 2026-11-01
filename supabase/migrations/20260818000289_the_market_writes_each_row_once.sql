-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0289 — THE MARKET WRITES EACH ROW ONCE A MINUTE   (a LOAD-ONLY slice: every served figure identical)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY (prod, read-only, head 0288, 2026-11-01 ~00:10 UTC) ────────────────────────────────────
-- The owner: "nothing is working in this game... unimaginably slower... can't load map, hq takes
-- forever". Measured: arrivals_beats.ms 10,340-16,034 (splits: run 10,156-12,364, of which arrive
-- ~10,150-12,360; the call's 59 s mean in pg_stat_statements is its DESIGNED minute-long loop, not
-- load). Every beat of tick_arrivals_each_second takes ~10-16 s instead of 0.7 s (2026-10-27), holds
-- the quay for it (pg_advisory_xact_lock 'byeharu.quay_or_upkeep', taken by hold_the_quay inside the
-- beat, lap_start_open, tick_lap_starts and tick_reconcile), and lap_starts then spends its minute
-- WAITING for that lock. The disk is the queue: port_goods 154,734 rows is rewritten twice a minute
-- (drift, then regeneration: drift_slot-current = 154,734/154,734 and last_regen_day < day for the
-- same table, day = 60 s of real time), ~5,150 row versions/s, with autovacuum on port_goods seen
-- running 62 s and n_dead_tup 193,619 against 154,852 live.
--
-- ── WHAT CHANGES ──────────────────────────────────────────────────────────────────────────────
-- ONE hunk in public.tick_market_drift(timestamptz, uuid): its two UPDATE statements become one, each
-- column group under 0137's own condition, so a row gets ONE new version a run instead of two. The
-- counts the function RETURNS ('drifted', 'regenerated') are read first, under the same two
-- conditions (they feed tick_market_drift_each_port's notice only; nothing stores them).
--
-- ── WHY IDENTICAL ─────────────────────────────────────────────────────────────────────────────
-- The regeneration's expressions read stock, stock_target, base_target, production_rate, glut,
-- glut_at, depth, rate, works — none of the columns the drift group writes — so computing both groups
-- in one statement from the same pre-update row yields the same values the two statements produced in
-- sequence. §3 asserts every expression appears VERBATIM (whitespace-insensitive) in the new hunk,
-- and that the union condition is exactly 0137's two conditions. The drift draw is the same
-- expression (random() twice, Box-Muller); its sequence across rows is not a figure and was never
-- stable (the drift is deliberately not replayable).
--
-- ── WHAT DOES NOT MOVE ───────────────────────────────────────────────────────────────────────
-- No schedule, cadence, TTL, knob or switch; no other function; no table, no column, no row outside
-- the two UPDATEs' own sets. The registry and every other function md5 are asserted unmoved.
--
-- ── ROLLBACK ─────────────────────────────────────────────────────────────────────────────────
-- §0 keeps the as-found definition in defs_before_0289; execute it to restore the two-statement body.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

create or replace function pg_temp.occurs_0289(p_hay text, p_needle text)
returns int language sql immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND ────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0289 on commit drop as
select 'public.tick_market_drift(timestamptz, uuid)'::text as fn,
       replace(pg_get_functiondef('public.tick_market_drift(timestamptz, uuid)'::regprocedure), E'\r', '') as def;

create temp table before_0289 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and p.oid <> 'public.tick_market_drift(timestamptz, uuid)'::regprocedure) as rest_md5,
       (select value from public.world_config where key = 'economy_closed') as economy_closed,
       (select value from public.world_config where key = 'city_treasury_enabled') as city_treasury_enabled;

-- ── 1. THE HUNK ────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0289 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0289 (fn, n, old, new) values
('public.tick_market_drift(timestamptz, uuid)', 1,
$h$  -- §G.1: drift <- theta x drift + N(0, sigma), clamped. Box-Muller from two uniforms; the market
  -- is deliberately NOT deterministic, unlike the hazard rolls — a market a player could replay
  -- would be a market a player could front-run.
  update public.port_goods pg
     set drift = greatest(-v_clamp, least(v_clamp,
                   v_theta * pg.drift
                   + v_sigma * sqrt(-2 * ln(greatest(random(), 1e-12))) * cos(2 * pi() * random()))),
         drift_slot = v_slot,
         updated_at = p_now
   where pg.drift_slot < v_slot
     and (p_port is null or pg.port_id = p_port);   -- 0137: one harbour, when one is asked for
  get diagnostics v_n = row_count;

  -- §G.2 regeneration, in closed form over however many game-days have passed. A tick that missed
  -- six hours lands on exactly the number an unbroken sequence of ticks would have reached.
  -- 0247: the harbour's rate, its works and the glut decay are read ONCE A HARBOUR (f), not once a row: the
  -- same readers in the same statement, so the same values on every row. MATERIALIZED, or the planner pulls
  -- the calls back up into the row loop (they cost the game-day's run 65-95 s on prod, 2026-10-27).
  with f as materialized (
    select po.id as port_id,
           public.restock_rate(po.id) as rate,   -- 0245: the harbour's own rate
           public.works_factor(po.id, 'production', 'production_per_level') as works,   -- 0123
           public.wc_num('glut_decay') as glut_decay,   -- 0194: the fraction left after one half-life (0271)
           public.wc_num('glut_half_life_hours') as half_life,   -- 0271: the press's half-life, in REAL hours
           public.depth_mult(po.id) as depth   -- 0252 (E5b): the day's max-stock multiple (null: the max as it stands)
      from public.ports po
     where (p_port is null or po.id = p_port)
  )
  update public.port_goods pg
     set stock = public.depth_stock(pg.stock, public.depth_target(pg.stock_target, pg.base_target, f.depth), f.depth, f.rate,   -- 0252: to the day's max   -- 0170: the rule, one leaf (the outlook steps it); 0245: at the harbour's own rate
                   pg.production_rate * f.works,   -- 0123
                   v_day - pg.last_regen_day),
         -- 0271 (the owner, 2026-10-28): THE PRESS FADES IN REAL TIME. f.glut_decay is what is left after ONE
         -- half-life (glut_half_life_hours, 3 real hours), not after one game-day; the time it measures is the
         -- real time since this row's press last moved (port_goods.glut_at — written by the trades and here).
         -- 4 places, as 0194.
         glut = round(pg.glut * power(f.glut_decay, extract(epoch from (p_now - pg.glut_at)) / 3600.0 / f.half_life), 4),
         glut_at = p_now,
         last_regen_day = v_day,
         stock_target = public.depth_target(pg.stock_target, pg.base_target, f.depth),   -- 0252 (E5b): the day's max stock
         base_target = case when f.depth is null then pg.base_target else coalesce(pg.base_target, pg.stock_target) end,
         updated_at = p_now
    from f
   where f.port_id = pg.port_id
     and pg.last_regen_day < v_day
     and (p_port is null or pg.port_id = p_port);   -- 0137: one harbour, when one is asked for
  get diagnostics v_regen = row_count;
$h$,
$h$
  -- 0289: ONE ROW VERSION A RUN, NOT TWO. Prod measured (2026-11-01, read-only, head 0288): every
  -- port_goods row was rewritten TWICE a minute — the drift (drift_slot_seconds 60: the drift_slot-current
  -- count was all 154,734 rows) and then the regeneration (game_day_seconds 60: the whole table again) —
  -- ~5,150 row versions a second; the disk saturated, every beat of tick_arrivals_each_second became an
  -- IO wait (arrivals_beats.ms 10.1-16.0 s against the 0.7 s of 2026-10-27) and autovacuum fell behind
  -- (n_dead_tup 193,619 against 154,852 live). 0137's second statement reads NO column the first writes
  -- (stock/stock_target/base_target/production_rate/glut/glut_at), so both column groups are computed in
  -- ONE statement here, each under its own 0137 condition, and the row is written once. Every expression
  -- below is 0137/0245/0252/0271's text verbatim (§3 below asserts it, whitespace-insensitive); only
  -- the case around it is new, and a row that matched neither condition before matches neither now.
  select count(*) filter (where pg.drift_slot < v_slot),
         count(*) filter (where pg.last_regen_day < v_day)
    into v_n, v_regen
    from public.port_goods pg
   where (p_port is null or pg.port_id = p_port);
  with f as materialized (
    select po.id as port_id,
           public.restock_rate(po.id) as rate,   -- 0245: the harbour's own rate
           public.works_factor(po.id, 'production', 'production_per_level') as works,   -- 0123
           public.wc_num('glut_decay') as glut_decay,   -- 0194: the fraction left after one half-life (0271)
           public.wc_num('glut_half_life_hours') as half_life,   -- 0271: the press's half-life, in REAL hours
           public.depth_mult(po.id) as depth   -- 0252 (E5b): the day's max-stock multiple (null: the max as it stands)
      from public.ports po
     where (p_port is null or po.id = p_port)
  )
  update public.port_goods pg
     set drift = case when pg.drift_slot < v_slot then greatest(-v_clamp, least(v_clamp,
                   v_theta * pg.drift
                   + v_sigma * sqrt(-2 * ln(greatest(random(), 1e-12))) * cos(2 * pi() * random()))) else pg.drift end,
         drift_slot = case when pg.drift_slot < v_slot then v_slot else pg.drift_slot end,
         stock = case when pg.last_regen_day < v_day then public.depth_stock(pg.stock, public.depth_target(pg.stock_target, pg.base_target, f.depth), f.depth, f.rate,   -- 0252: to the day's max   -- 0170: the rule, one leaf (the outlook steps it); 0245: at the harbour's own rate
                   pg.production_rate * f.works,   -- 0123
                   v_day - pg.last_regen_day) else pg.stock end,
         glut = case when pg.last_regen_day < v_day then round(pg.glut * power(f.glut_decay, extract(epoch from (p_now - pg.glut_at)) / 3600.0 / f.half_life), 4) else pg.glut end,
         glut_at = case when pg.last_regen_day < v_day then p_now else pg.glut_at end,
         last_regen_day = case when pg.last_regen_day < v_day then v_day else pg.last_regen_day end,
         stock_target = case when pg.last_regen_day < v_day then public.depth_target(pg.stock_target, pg.base_target, f.depth) else pg.stock_target end,
         base_target = case when pg.last_regen_day < v_day then case when f.depth is null then pg.base_target else coalesce(pg.base_target, pg.stock_target) end else pg.base_target end,
         updated_at = p_now
    from f
   where f.port_id = pg.port_id
     and (p_port is null or pg.port_id = p_port)   -- 0137: one harbour, when one is asked for
     and (pg.drift_slot < v_slot or pg.last_regen_day < v_day);   -- 0289: 0137's two conditions, the row written once
$h$);

-- ── 2. APPLY ───────────────────────────────────────────────────────────────────────────────────
do $$
declare d record; h record; v_def text; v_n int;
begin
  for d in select * from defs_before_0289 loop
    v_def := d.def;
    for h in select * from hunks_0289 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0289(v_def, h.old);
      if v_n <> 1 then
        raise exception '0289 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 3. THE EXPRESSIONS ARE 0137's, VERBATIM ────────────────────────────────────────────────────
do $$
declare
  h record;
  o text;
  nw text;
  r record;
begin
  select old, new into o, nw from hunks_0289 where n = 1;
  o  := regexp_replace(o,  '\s+', ' ', 'g');
  nw := regexp_replace(nw, '\s+', ' ', 'g');
  for r in select * from (values
    ('drift',        'greatest(-v_clamp, least(v_clamp, v_theta * pg.drift + v_sigma * sqrt(-2 * ln(greatest(random(), 1e-12))) * cos(2 * pi() * random())))'),
    ('stock_a',      'public.depth_stock(pg.stock, public.depth_target(pg.stock_target, pg.base_target, f.depth), f.depth, f.rate,'),
    ('stock_b',      'pg.production_rate * f.works,'),
    ('stock_c',      'v_day - pg.last_regen_day)'),
    ('glut',         'round(pg.glut * power(f.glut_decay, extract(epoch from (p_now - pg.glut_at)) / 3600.0 / f.half_life), 4)'),
    ('stock_target', 'public.depth_target(pg.stock_target, pg.base_target, f.depth)'),
    ('base_target',  'case when f.depth is null then pg.base_target else coalesce(pg.base_target, pg.stock_target) end'),
    ('rate',         'public.restock_rate(po.id)'),
    ('works',        'public.works_factor(po.id, ''production'', ''production_per_level'')'),
    ('depth',        'public.depth_mult(po.id)'),
    ('cond_drift',   'pg.drift_slot < v_slot'),
    ('cond_regen',   'pg.last_regen_day < v_day'),
    ('cond_port',    '(p_port is null or pg.port_id = p_port)')
  ) v(name, expr) loop
    if strpos(o, r.expr) = 0 then
      raise exception '0289 self-assert FAIL: the as-found hunk does not contain % as this file records it: %', r.name, r.expr;
    end if;
    if strpos(nw, r.expr) = 0 then
      raise exception '0289 self-assert FAIL: the new hunk does not carry % verbatim: %', r.name, r.expr;
    end if;
  end loop;
end $$;

-- ── 4. THE PROBE: the new body runs, and touches no row of a harbour that has none ─────────────
do $$
declare j jsonb;
begin
  j := public.tick_market_drift(now(), '00000000-0289-4000-8000-000000000289');
  if j->>'drifted' <> '0' or j->>'regenerated' <> '0' then
    raise exception '0289 self-assert FAIL: the probe harbour (no rows) reported % drifted / % regenerated', j->>'drifted', j->>'regenerated';
  end if;
  if exists (select 1 from public.port_goods where port_id = '00000000-0289-4000-8000-000000000289') then
    raise exception '0289 self-assert FAIL: the probe left a port_goods row behind';
  end if;
  raise notice '0289 self-assert ok: the market writes each row once. The drift and the regeneration are one update — every expression 0137/0245/0252/0271 verbatim, each column group under its own condition. Probe harbour (no rows): drifted 0 / regenerated 0, no row written.';
end $$;

-- ── 5. NOTHING ELSE MOVED ──────────────────────────────────────────────────────────────────────
do $$
declare
  b record;
  x record;
begin
  select * into b from before_0289;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points then
    raise exception '0289 self-assert FAIL: the client registry moved';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> b.fns then
    raise exception '0289 self-assert FAIL: a function in public/cmd/world/voyage was added or dropped';
  end if;
  select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text)) as md5
    into x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> 'public.tick_market_drift(timestamptz, uuid)'::regprocedure;
  if x.md5 is distinct from b.rest_md5 then
    raise exception '0289 self-assert FAIL: a function other than public.tick_market_drift moved';
  end if;
  if (select value from public.world_config where key = 'economy_closed') is distinct from b.economy_closed
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from b.city_treasury_enabled then
    raise exception '0289 self-assert FAIL: an owner switch moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0289 self-assert FAIL: a wall moved';
  end if;
end $$;

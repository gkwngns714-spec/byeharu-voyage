-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0136 — A RANKING READS THE QUAY ONCE  (the arrivals sweep, step 2 — nothing it decides moves)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/RESUME.md (2026-10-16 handover + 2026-10-17): skills_bite stays false until the arrivals sweep
-- has headroom (lit ≈ 2× merchant ship reads); the next lever named there is "port_offers called per
-- row inside trade_routes (~555 calls per ranking, ~9 % of a lap start)".
-- Prod after 0134, cron.job_run_details, byeharu-voyage:arrivals (2026-10-16 07:00–14:00 UTC, ~1,700
-- runs): avg 3.1–3.5 s an hour, p95 5.4–6.0 s, max 7.5–10.8 s (one 38.45 s run at 13:07 UTC: a lock wait on
-- the hourly reconcile — it ended 55 ms after tick_reconcile committed; see DEV_LOG)
-- against arrivals_tick_budget_ms 10 000.
--
-- ── THE PROFILE (prod, READ-ONLY: one statement each, `transaction_read_only` set on, clock_timestamp
--    checkpoints between materialized CTEs; track_functions is refused to the CLI role now) ─────────
-- 24 merchant legs (consecutive stops of NPC routes, md5-spread), 2026-10-16 ~14:10 UTC:
--   * npc_leg_lines (a lap start prices every distinct leg through it)      903 ms   37.6 ms a leg
--   * world.trade_routes(from, null, null, 12, to) alone (2 passes)    698 / 612 ms   25–29 ms a ranking
--       - its `here` scan with port_offers per market row                 191 ms    8.0 ms a ranking
--         (every harbour has 555 market rows; port_offers is SQL with a sub-link — never inlined —
--          so it is one function call, re-planned on PG 17, per row)
--       - the same scan reading the city's roster as a set                 1 ms    (150 = 150 rows)
--       - voyage.reach_from 0.5 ms · the `here` mid_price ~1.8 ms · the quotes ~1 ms each (~12 a
--         ranking; already cut by 0134)
-- So port_offers' per-row probe is ~28 % of a ranking and ~21 % of a priced leg — the largest single
-- piece left that is not a quote. Nothing bigger dominates: the rest of a ranking is its quotes.
--
-- ── WHAT THIS FILE DOES (one authority; every answer is the pre-image — asserted) ──────────────
-- (1) public.port_offered_goods(port) — NEW: THE one reading of a city's roster ("which goods does
--     this city offer?"), the set form, read from public.port_specialties and nothing else. SQL,
--     STABLE, invoker, no SET — so the planner INLINES it wherever it is read (asserted: the four
--     conditions that let a set-returning SQL function inline).
-- (2) public.port_offers(port, good) — the predicate every per-row caller asks (cmd.do_buy,
--     world.market, quay_shows, tick_price_snapshot, contract_draw) — becomes membership in (1).
--     Same answer (asserted over every harbour × every good), same plan after inlining, same ACL.
-- (3) world.trade_routes' `here` scan reads (1) ONCE per ranking (`pg.good_id in (…)`) instead of
--     calling port_offers for each of the harbour's 555 market rows. One hunk; nothing else moves.
-- (4) world.affinity_for(port, good) — the seeding authority of port_goods.affinity (0005; 0048 / 0058
--     re-derive through it; scripts/tune-balance and the breaktests call it) — read the roster table
--     itself twice: "is it a specialty here" (an EXISTS) and "where is it produced" (the nearest
--     source). Both now go through the one reading: public.port_offers, and ports whose
--     port_offered_goods hold the good. One hunk; affinity_at, the knobs and the distance untouched.
--     After this file the only reader of port_specialties for "what a city offers" is (1)
--     (public.rarity_scale / good_rarity count producers per good for rarity — a different question,
--     left as they are).
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Change any rule, price, ranking, refusal, schedule, knob, table, client grant or entry point. Touch
-- npc_plan / npc_leg_lines / quote / tick_arrivals (they read faster through trade_routes). Cache
-- anything across calls. Fold the culture mask into the roster (it stays its own rule).
--
-- ── THE PROOF (all in this file; old and new on the SAME snapshot) ──────────────────────────────
-- §1 keeps the pre-image TREE (port_offers, trade_routes, npc_leg_lines, affinity_for — every function on a path
-- from the reads below to a changed body; checked on prod: only npc_leg_lines calls trade_routes, and
-- only npc_plan calls npc_leg_lines) under pg_temp names. §4 reads old and new IN ONE STATEMENT each
-- and requires byte-equal text: port_offers and affinity_for over every port × every good (and nulls); the rankings of
-- every sampled merchant leg (p_to, twelve rows, as npc_leg_lines asks) and open scans (no p_to, every
-- row; and a 400 nm radius, five rows) from a spread of harbours; whole lap-start reads (loops + every
-- leg's lines, which carry the quotes) for 12 merchants. A difference RAISES.
-- §5 TIMES lap-start reads and rankings, old tree vs new, faster of two passes, and REPORTS it
-- (raise notice) — it does not gate: prod runs on burstable CPU, and a timing gate inside a self-assert
-- could abort a db push for a reason that is not a result. The speed verdict is prod's
-- cron.job_run_details after the push (the same query as 0134's). Nothing here writes a table, so
-- there is nothing to analyze between the passes.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- ACCESS SHARE on what it reads; CREATE FUNCTION / CREATE OR REPLACE FUNCTION (no table lock);
-- pg_temp objects. No LOCK TABLE, no set role, no write to any table. Deploy with the clock unwound as
-- usual (DEPLOY_RUNBOOK): unwind_the_clock() → db push → wind_the_clock().
--
-- ROLLBACK: a forward migration putting port_offers', trade_routes' and affinity_for's pre-image bodies back (all are
-- here verbatim as the hunks' OLD text; the self-assert proves each live body reverses to its pre-image)
-- and dropping public.port_offered_goods.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly once:
-- public.port_offers (0061), world.trade_routes (0061/0080), world.affinity_for (0005).
-- VERSION: 0136. Applies on prod head 0135.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0136(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0136 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proparallel from pg_proc p where p.oid = f.fn::regprocedure) as par,
       (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = f.fn::regprocedure) as lang
  from (values ('public.port_offers(uuid, uuid)'),
               ('world.trade_routes(uuid, uuid, numeric, integer, uuid)'),
               ('world.affinity_for(uuid, uuid)')) f(fn);

create temp table before_0136 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'port_offered_goods') as n_found;

-- THE OLD TREE: every function on a path from the reads §4 compares to a changed body. Every overload.
create temp table tree_0136 (nsp text, name text) on commit drop;
insert into tree_0136 values ('public', 'port_offers'), ('world', 'trade_routes'), ('public', 'npc_leg_lines'),
                             ('world', 'affinity_for');

create or replace function pg_temp.old_sql_0136(p_sql text)
returns text
language plpgsql
stable
as $$
declare
  t record;
  v text := p_sql;
begin
  for t in select nsp, name from tree_0136 order by length(name) desc, nsp, name loop
    v := replace(v, t.nsp || '.' || t.name || '(', 'pg_temp.' || t.nsp || '_' || t.name || '_0136(');
  end loop;
  return v;
end $$;

create temp table old_tree_0136 on commit drop as
select n.nspname as nsp, p.proname as name, p.oid::regprocedure::text as sig,
       pg_temp.old_sql_0136(replace(pg_get_functiondef(p.oid), E'\r', '')) as def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join tree_0136 t on t.nsp = n.nspname and t.name = p.proname;

do $$
declare
  d   record;
  v_n int;
begin
  if (select count(*) from old_tree_0136) <> (select count(*) from tree_0136) then
    raise exception '0136 self-assert FAIL: the old tree lists % name(s) but % live function(s) were found',
      (select count(*) from tree_0136), (select count(*) from old_tree_0136);
  end if;
  -- THE TREE IS CLOSED: no live body outside it calls a tree member on the compared paths. The
  -- callers of trade_routes and npc_leg_lines are exactly npc_leg_lines and npc_plan (npc_plan writes;
  -- §1's lap read stands in for it).
  select count(*) into v_n from pg_proc p
   where p.pronamespace <> pg_my_temp_schema() and strpos(p.prosrc, 'world.trade_routes(') > 0
     and p.oid <> 'public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)'::regprocedure
     and p.oid <> 'world.trade_routes(uuid, uuid, numeric, integer, uuid)'::regprocedure;
  if v_n > 0 then
    raise exception '0136 self-assert FAIL: % live bod(ies) besides npc_leg_lines call world.trade_routes — the old tree is not closed', v_n;
  end if;
  -- NO COPY REACHES A CHANGED BODY (and every copy was renamed).
  for d in select * from old_tree_0136 loop
    if strpos(d.def, 'CREATE OR REPLACE FUNCTION pg_temp.' || d.nsp || '_' || d.name || '_0136(') <> 1 then
      raise exception '0136 self-assert FAIL: the old copy of % was not renamed', d.sig;
    end if;
    if strpos(d.def, 'public.port_offers(') > 0 or strpos(d.def, 'world.trade_routes(') > 0
       or strpos(d.def, 'public.npc_leg_lines(') > 0 or strpos(d.def, 'port_offered_goods') > 0 then
      raise exception '0136 self-assert FAIL: the old copy of % still calls a live tree body', d.sig;
    end if;
  end loop;
  perform set_config('check_function_bodies', 'off', true);
  for d in select * from old_tree_0136 order by nsp, name, sig loop
    execute d.def;
  end loop;
  perform set_config('check_function_bodies', 'on', true);
  select count(*) into v_n from pg_proc where pronamespace = pg_my_temp_schema() and proname like '%\_0136'
                                          and proname in ('public_port_offers_0136', 'world_trade_routes_0136', 'public_npc_leg_lines_0136', 'world_affinity_for_0136');
  if v_n <> 4 then
    raise exception '0136 self-assert FAIL: % old cop(ies) made, not 4', v_n;
  end if;
end $$;

-- THE LAP-START READ, as npc_plan reads it (0114/0120, as cut by 0129) — 0134's probe, verbatim but
-- for its name: her hold, crew and speed; her present loop and up to npc_route_candidates others;
-- every distinct leg priced by npc_leg_lines. The OLD variant is the same text pointed at the old tree.
create or replace function pg_temp.lap_read_0136(p_route uuid)
returns jsonb
language plpgsql
as $$
declare
  sr      public.standing_routes%rowtype;
  v_fleet uuid;
  v_crew  int;
  v_hold  numeric;
  v_speed numeric;
  v_loop  jsonb;
  v_loops jsonb;
  v_legs  jsonb := '{}'::jsonb;
  v_len   int;
  v_from  uuid;
  v_to    uuid;
  v_key   text;
  lp      record;
  i       int;
  j       int;
begin
  select * into sr from public.standing_routes where id = p_route;
  v_fleet := coalesce(sr.fleet_id, (select nf.fleet_id from public.npc_fleets nf where nf.route_id = sr.id limit 1));
  select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(s.id)), 0)
    into v_crew, v_hold
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = v_fleet;
  v_hold  := v_hold + public.fleet_free_hold(v_fleet);
  v_speed := greatest(coalesce(voyage.fleet_speed(v_fleet), 0), 0.1);
  select jsonb_agg(jsonb_build_object('port_id', s.port_id, 'code', p.code, 'course', s.course) order by s.ord)
    into v_loop
    from public.standing_route_stops s join public.ports p on p.id = s.port_id
   where s.route_id = sr.id;
  v_loops := jsonb_build_array(v_loop);
  for lp in select * from public.npc_loop_candidates(sr.id, v_fleet, (v_loop->0->>'port_id')::uuid, v_hold, v_speed) loop
    exit when jsonb_array_length(v_loops) >= public.wc_int('npc_route_candidates');
    v_loops := v_loops || jsonb_build_array(lp.stops);
  end loop;
  for i in 0 .. jsonb_array_length(v_loops) - 1 loop
    v_loop := v_loops->i;
    v_len  := jsonb_array_length(v_loop);
    for j in 0 .. v_len - 1 loop
      v_from := (v_loop->j->>'port_id')::uuid;
      v_to   := (v_loop->((j + 1) % v_len)->>'port_id')::uuid;
      v_key  := v_from::text || '>' || v_to::text;
      if not v_legs ? v_key then
        v_legs := v_legs || jsonb_build_object(v_key, public.npc_leg_lines(sr.id, v_from, v_to, v_hold, v_crew, v_speed));
      end if;
    end loop;
  end loop;
  return jsonb_build_object('hold', v_hold, 'crew', v_crew, 'speed', v_speed, 'loops', v_loops, 'legs', v_legs);
end $$;

do $$
declare
  v_def text := replace(pg_get_functiondef('pg_temp.lap_read_0136(uuid)'::regprocedure), E'\r', '');
begin
  v_def := regexp_replace(pg_temp.old_sql_0136(v_def), 'FUNCTION pg_temp(_[0-9]+)?\.lap_read_0136\(', 'FUNCTION pg_temp.lap_read_old_0136(');
  if strpos(v_def, 'FUNCTION pg_temp.lap_read_old_0136(') = 0 or strpos(v_def, 'pg_temp.public_npc_leg_lines_0136(') = 0 then
    raise exception '0136 self-assert FAIL: the old lap read was not pointed at the old tree';
  end if;
  execute v_def;
end $$;

-- the merchants whose lap-start reads are compared and timed: 12, spread by a hash of the route id
create temp table lap_sample_0136 on commit drop as
select sr.id as route_id
  from public.standing_routes sr
  join public.players p on p.id = sr.player_id and p.is_npc
 where (select count(*) from public.standing_route_stops s where s.route_id = sr.id) >= 2
   and exists (select 1 from public.ships s
                where s.fleet_id = coalesce(sr.fleet_id, (select nf.fleet_id from public.npc_fleets nf where nf.route_id = sr.id limit 1)))
 order by md5(sr.id::text), sr.id
 limit 12;

-- the rankings compared and timed: merchant legs as npc_leg_lines asks them (p_to, twelve rows), and
-- open scans (no p_to) from a spread of harbours — every row, and a 400 nm radius with five rows
create temp table rank_grid_0136 on commit drop as
select * from (
  select distinct on (s.port_id, n.port_id) s.port_id as f, n.port_id as t, null::numeric as radius, 12 as lim
    from public.standing_route_stops s
    join public.standing_routes sr on sr.id = s.route_id
    join public.players p on p.id = sr.player_id and p.is_npc
    join lateral (select s2.port_id from public.standing_route_stops s2
                   where s2.route_id = s.route_id and s2.ord > s.ord order by s2.ord limit 1) n on true
   order by s.port_id, n.port_id) legs
 order by md5(f::text || t::text) limit 120;
insert into rank_grid_0136
select h.id, null, x.radius, x.lim
  from (select p.id from public.ports p where p.kind = 'HARBOUR' order by md5(p.id::text) limit 12) h
 cross join (values (null::numeric, null::int), (400::numeric, 5)) x(radius, lim);

-- ── 2. THE ONE READING OF A CITY'S ROSTER, as a set ────────────────────────────────────────────
create function public.port_offered_goods(p_port uuid)
returns table (good_id uuid)
language sql
stable
parallel safe
as $$
  select s.good_id from public.port_specialties s where s.port_id = p_port
$$;
comment on function public.port_offered_goods(uuid) is
  '0136: THE reading of a city''s roster — the goods this city offers for sale, read from '
  'public.port_specialties and nothing else. public.port_offers (the per-good predicate) is membership '
  'in it; world.trade_routes reads it once per ranking. SQL, STABLE, invoker, no SET: inlined wherever '
  'it is read. Server-only.';
revoke all on function public.port_offered_goods(uuid) from public, anon, authenticated;

-- ── 3. THE RE-CUTS (hunks: old = verbatim from the live bodies; new = what replaces it) ─────────
create temp table hunks_0136 (fn text, n int, old text, new text) on commit drop;

insert into hunks_0136 values
('public.port_offers(uuid, uuid)', 1,
$h$  select exists (select 1 from public.port_specialties s
                  where s.port_id = p_port and s.good_id = p_good)$h$,
$h$  select exists (select 1 from public.port_offered_goods(p_port) o   -- 0136: the roster's one reading
                  where o.good_id = p_good)$h$),
('world.affinity_for(uuid, uuid)', 1,
$h$           exists (
             select 1 from public.port_specialties s
              where s.port_id = p_port and s.good_id = p_good
           ),
           (select min(voyage.gc_distance_nm(p.lat, p.lon, src.lat, src.lon))
              from public.port_specialties s
              join public.ports src on src.id = s.port_id
             where s.good_id = p_good),$h$,
$h$           public.port_offers(p_port, p_good),   -- 0136: the roster's one reading (was its own probe)
           (select min(voyage.gc_distance_nm(p.lat, p.lon, src.lat, src.lon))
              from public.ports src   -- 0136: the cities whose roster (public.port_offered_goods) holds it
             where p_good in (select o.good_id from public.port_offered_goods(src.id) o)),$h$),
('world.trade_routes(uuid, uuid, numeric, integer, uuid)', 1,
$h$       and public.port_offers(p_from, pg.good_id)
$h$,
$h$       -- 0136: the roster read ONCE per ranking (public.port_offered_goods, which public.port_offers
       -- is membership in) — was one port_offers call per market row, 555 a ranking.
       and pg.good_id in (select o.good_id from public.port_offered_goods(p_from) o)
$h$);

create or replace function pg_temp.recut_0136(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0136 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0136(v_def, h.old);
    if v_n <> 1 then
      raise exception '0136 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0136(fn) from defs_before_0136 order by fn;

comment on function public.port_offers(uuid, uuid) is
  'THE QUAY (0061): does this city offer this good for sale? Membership in public.port_offered_goods '
  '(0136), the one reading of public.port_specialties — the one authority for what a city trades — and '
  'derives nothing. It deliberately does NOT call public.roster_target_count or public.roster_rng (0058) '
  'and has no opinion about how many goods a city ought to name. It deliberately does NOT fold the '
  'culture mask either: that rule has its own readers. cmd.do_buy, world.market, public.quay_shows, '
  'public.tick_price_snapshot and public.contract_draw ask it per good; world.trade_routes reads the set.';

-- ── 4. THE COMPARISONS — old tree and new, side by side in ONE statement each (one snapshot) ─────
create temp table proven_0136 (k text primary key, v text) on commit drop;

-- (a) the predicate, over every port × every good, and the nulls
create temp table offers_0136 on commit drop as
select count(*) as n,
       count(*) filter (where z.new_v is distinct from z.old_v) as bad,
       count(*) filter (where z.new_v) as yes,
       (public.port_offers(null, null) is not distinct from pg_temp.public_port_offers_0136(null, null)) as nulls_ok
  from (select public.port_offers(p.id, g.id) as new_v, pg_temp.public_port_offers_0136(p.id, g.id) as old_v
          from public.ports p cross join public.goods g) z;

-- (a2) the affinity seed, over every port × every good, and the nulls
create temp table affinity_0136 on commit drop as
select count(*) as n,
       count(*) filter (where z.new_v is distinct from z.old_v) as bad,
       count(distinct z.new_v) as distinct_values,
       (world.affinity_for(null, null) is not distinct from pg_temp.world_affinity_for_0136(null, null)) as nulls_ok,
       min(format('%s/%s new %s old %s', z.port_id, z.good_id, z.new_v, z.old_v)) filter (where z.new_v is distinct from z.old_v) as ex
  from (select p.id as port_id, g.id as good_id, world.affinity_for(p.id, g.id) as new_v,
               pg_temp.world_affinity_for_0136(p.id, g.id) as old_v
          from public.ports p cross join public.goods g) z;

-- (b) the rankings
create temp table ranks_0136 on commit drop as
select r.*, world.trade_routes(r.f, null, r.radius, r.lim, r.t) as new_v,
       pg_temp.world_trade_routes_0136(r.f, null, r.radius, r.lim, r.t) as old_v
  from rank_grid_0136 r;

-- (c) whole lap-start reads, 12 merchants
create temp table laps_0136 on commit drop as
select s.route_id, pg_temp.lap_read_0136(s.route_id) as new_v, pg_temp.lap_read_old_0136(s.route_id) as old_v
  from lap_sample_0136 s;

do $$
declare
  o      record;
  v_n    int;
  v_bad  int;
  v_ex   text;
  v_rows int;
  v_legs int;
  v_kept int;
begin
  -- (a)
  select * into o from offers_0136;
  if o.bad > 0 or not o.nulls_ok then
    raise exception '0136 self-assert FAIL: port_offers — % of % (port, good) pairs differ from the pre-image (nulls equal: %)', o.bad, o.n, o.nulls_ok;
  end if;
  if o.yes < 1 or o.yes = o.n then
    raise exception '0136 self-assert FAIL: the port_offers comparison is vacuous (% true of %)', o.yes, o.n;
  end if;
  if o.yes <> (select count(*) from public.port_specialties s join public.ports p on p.id = s.port_id join public.goods g on g.id = s.good_id) then
    raise exception '0136 self-assert FAIL: port_offers answers true on % pair(s), the roster holds %', o.yes,
      (select count(*) from public.port_specialties);
  end if;
  if (select bad from affinity_0136) > 0 or not (select nulls_ok from affinity_0136) then
    raise exception '0136 self-assert FAIL: affinity_for — % of % (port, good) pairs differ from the pre-image (e.g. %; nulls equal: %)',
      (select bad from affinity_0136), (select n from affinity_0136), (select ex from affinity_0136), (select nulls_ok from affinity_0136);
  end if;
  if (select distinct_values from affinity_0136) < 3 then
    raise exception '0136 self-assert FAIL: the affinity comparison is vacuous (% distinct value(s))', (select distinct_values from affinity_0136);
  end if;
  insert into proven_0136 values ('affinity', format('%s (port, good) pairs (%s distinct affinities) and the nulls = the pre-image',
    (select n from affinity_0136), (select distinct_values from affinity_0136)));
  insert into proven_0136 values ('offers', format('%s (port, good) pairs (%s offered) and the nulls = the pre-image', o.n, o.yes));

  -- (b)
  select count(*), count(*) filter (where new_v::text is distinct from old_v::text) into v_n, v_bad from ranks_0136;
  select min(format('%s → %s r %s l %s', f, t, radius, lim)) into v_ex from ranks_0136 where new_v::text is distinct from old_v::text;
  if v_bad > 0 then
    raise exception '0136 self-assert FAIL: rankings — % of % differ from the pre-image (e.g. %)', v_bad, v_n, v_ex;
  end if;
  select sum(jsonb_array_length(new_v->'routes')) into v_rows from ranks_0136;
  if v_n < 20 or coalesce(v_rows, 0) < 20 or (select count(*) from ranks_0136 where t is null and jsonb_array_length(new_v->'routes') > 0) < 1 then
    raise exception '0136 self-assert FAIL: the ranking comparison is vacuous (% rankings, % rows)', v_n, v_rows;
  end if;
  insert into proven_0136 values ('ranks', format('%s rankings (%s merchant legs, %s open scans; %s rows) = the pre-image as text',
    v_n, (select count(*) from ranks_0136 where t is not null), (select count(*) from ranks_0136 where t is null), v_rows));

  -- (c)
  select count(*), count(*) filter (where new_v::text is distinct from old_v::text) into v_n, v_bad from laps_0136;
  if v_n < 1 or v_bad > 0 then
    raise exception '0136 self-assert FAIL: lap-start reads — % of % differ from the pre-image', v_bad, v_n;
  end if;
  select sum((select count(*) from jsonb_object_keys(new_v->'legs'))),
         sum((select count(*) from jsonb_each(new_v->'legs') e where (e.value->>'any')::boolean))
    into v_legs, v_kept from laps_0136;
  if v_legs < v_n then
    raise exception '0136 self-assert FAIL: the lap-start reads priced % leg(s) for % merchant(s)', v_legs, v_n;
  end if;
  insert into proven_0136 values ('laps', format('%s merchants'' lap-start reads (%s loops, %s distinct legs priced, %s with a parcel kept) = the pre-image as text',
    v_n, (select sum(jsonb_array_length(new_v->'loops')) from laps_0136), v_legs, v_kept));
end $$;

-- ── 5. THE TIMING — REPORTED, NOT GATED (old tree vs new, same data, faster of two passes) ──────
create temp table timing_0136 (what text, old_ms numeric, new_ms numeric) on commit drop;
do $$
declare
  v_t0  timestamptz;
  v_old numeric;
  v_new numeric;
  v_n   int;
  i     int;
begin
  for i in 1 .. 2 loop
    v_t0 := clock_timestamp();
    select count(pg_temp.lap_read_old_0136(route_id)) into v_n from lap_sample_0136;
    v_old := least(coalesce(v_old, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    v_t0 := clock_timestamp();
    select count(pg_temp.lap_read_0136(route_id)) into v_n from lap_sample_0136;
    v_new := least(coalesce(v_new, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  end loop;
  insert into timing_0136 values ('lap_starts', v_old, v_new);
  v_old := null; v_new := null;
  for i in 1 .. 2 loop
    v_t0 := clock_timestamp();
    select count(pg_temp.world_trade_routes_0136(f, null, radius, lim, t)) into v_n from rank_grid_0136 where t is not null;
    v_old := least(coalesce(v_old, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    v_t0 := clock_timestamp();
    select count(world.trade_routes(f, null, radius, lim, t)) into v_n from rank_grid_0136 where t is not null;
    v_new := least(coalesce(v_new, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  end loop;
  insert into timing_0136 values ('leg_rankings', v_old, v_new);
  -- the per-good callers' predicate (cmd.do_buy, world.market, …) must not get slower: every market row
  v_old := null; v_new := null;
  for i in 1 .. 2 loop
    v_t0 := clock_timestamp();
    select count(*) filter (where pg_temp.public_port_offers_0136(pg.port_id, pg.good_id)) into v_n from public.port_goods pg;
    v_old := least(coalesce(v_old, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    v_t0 := clock_timestamp();
    select count(*) filter (where public.port_offers(pg.port_id, pg.good_id)) into v_n from public.port_goods pg;
    v_new := least(coalesce(v_new, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  end loop;
  insert into timing_0136 values ('port_offers_per_row', v_old, v_new);
end $$;

-- ── 6. SELF-ASSERT (catalogue reads) ─────────────────────────────────────────────────────────────
do $$
declare
  d      record;
  h      record;
  v_def  text;
  v_back text;
  v_rev  int := 0;
  v_tim  text;
  p      record;
begin
  -- every body moved as the header says, and reverses to its pre-image; ACL, language, volatility,
  -- definer, config and parallel safety unmoved
  for d in select * from defs_before_0136 order by fn loop
    v_def  := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0136 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0136(v_back, h.new) <> 1 then
        raise exception '0136 self-assert FAIL: hunk % of % is not in the live body once', h.n, d.fn;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back is distinct from d.def then
      raise exception '0136 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    v_rev := v_rev + 1;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proparallel as par, l.lanname as lang
      into p from pg_proc pr join pg_language l on l.oid = pr.prolang where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.par <> d.par or p.lang <> d.lang then
      raise exception '0136 self-assert FAIL: % changed its ACL, volatility, definer, config, parallel safety or language', d.fn;
    end if;
  end loop;
  if v_rev <> 3 then
    raise exception '0136 self-assert FAIL: % bodies checked, not 3', v_rev;
  end if;

  -- the new reading: one new function, inlinable (SQL, STABLE, invoker, no SET, returns a set), with
  -- port_offers' own ACL (server-only); no new entry point
  if (select n_found from before_0136) <> 0
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'port_offered_goods') <> 1 then
    raise exception '0136 self-assert FAIL: public.port_offered_goods is not one new function';
  end if;
  select l.lanname as lang, pr.provolatile as vol, pr.prosecdef as secdef, pr.proconfig as cfg, pr.proretset as rs,
         coalesce(pr.proacl::text, '') as acl
    into p from pg_proc pr join pg_language l on l.oid = pr.prolang
   where pr.oid = 'public.port_offered_goods(uuid)'::regprocedure;
  if p.lang <> 'sql' or p.vol <> 's' or p.secdef or p.cfg is not null or not p.rs then
    raise exception '0136 self-assert FAIL: public.port_offered_goods is not inlinable (lang %, vol %, definer %, config %, set %)',
      p.lang, p.vol, p.secdef, p.cfg, p.rs;
  end if;
  if p.acl <> (select acl from defs_before_0136 where fn = 'public.port_offers(uuid, uuid)') then
    raise exception '0136 self-assert FAIL: public.port_offered_goods ACL % is not port_offers'' %', p.acl,
      (select acl from defs_before_0136 where fn = 'public.port_offers(uuid, uuid)');
  end if;
  if has_function_privilege('anon', 'public.port_offered_goods(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.port_offered_goods(uuid)', 'execute') then
    raise exception '0136 self-assert FAIL: public.port_offered_goods is callable by a client';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0136) then
    raise exception '0136 self-assert FAIL: the client entry points moved (% → %)',
      (select entry_points from before_0136), (select count(*) from public.client_rpc_entry_points());
  end if;
  -- ONE AUTHORITY: port_offers no longer reads the roster table itself, it asks port_offered_goods;
  -- trade_routes asks port_offered_goods once and no longer calls port_offers per row
  select pr.prosrc as src into p from pg_proc pr where pr.oid = 'public.port_offers(uuid, uuid)'::regprocedure;
  if strpos(p.src, 'port_specialties') > 0 or pg_temp.occurs_0136(p.src, 'public.port_offered_goods(p_port)') <> 1 then
    raise exception '0136 self-assert FAIL: public.port_offers is not membership in public.port_offered_goods';
  end if;
  select pr.prosrc as src into p from pg_proc pr where pr.oid = 'world.affinity_for(uuid, uuid)'::regprocedure;
  if strpos(p.src, 'port_specialties') > 0 or pg_temp.occurs_0136(p.src, 'public.port_offered_goods(src.id)') <> 1
     or pg_temp.occurs_0136(p.src, 'public.port_offers(p_port, p_good)') <> 1 then
    raise exception '0136 self-assert FAIL: world.affinity_for still reads the roster table itself';
  end if;
  select pr.prosrc as src into p from pg_proc pr where pr.oid = 'world.trade_routes(uuid, uuid, numeric, integer, uuid)'::regprocedure;
  if strpos(p.src, 'public.port_offers(') > 0 or pg_temp.occurs_0136(p.src, 'public.port_offered_goods(p_from)') <> 1 then
    raise exception '0136 self-assert FAIL: world.trade_routes does not read public.port_offered_goods once (or still calls port_offers)';
  end if;

  select string_agg(format('%s %s ms → %s ms (−%s%%)', what, old_ms, new_ms,
                           round(100 * (1 - new_ms / greatest(old_ms, 0.1)))), '; ' order by what)
    into v_tim from timing_0136;

  raise notice '0136 self-assert ok: A RANKING READS THE QUAY ONCE — nothing the sweep decides moved. SAME ANSWERS (old tree vs new, one statement each): OFFERS %; AFFINITY %; RANKINGS %; LAP STARTS %. TIMING (reported, not gated — old tree vs new, the same data, faster of 2 passes): %. BODIES: public.port_offered_goods is THE reading of a city''s roster (SQL, inlinable, server-only); port_offers is membership in it; world.trade_routes reads it once a ranking; world.affinity_for reads the roster through it (no second reader); 3 bodies reverse to their pre-images, ACL / volatility / definer / config unmoved; no new entry point.',
    (select v from proven_0136 where k = 'offers'), (select v from proven_0136 where k = 'affinity'), (select v from proven_0136 where k = 'ranks'),
    (select v from proven_0136 where k = 'laps'), v_tim;
end $$;

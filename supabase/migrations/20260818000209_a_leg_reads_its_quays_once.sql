-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0209 — A LEG READS ITS QUAYS ONCE  (public.npc_leg_lines reads each quay's price terms once a leg and
--        hands them to every quote of the leg; the other merchants' buyers at a harbour are found by an
--        index on the stops' harbour)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- The arrivals sweep (public.tick_arrivals, every 15 s; bound avg ≤ 3 s, p95 < 5 s) runs 2–3 s on prod. Most
-- of a merchant's lap-start cost is the leg planner (public.npc_leg_lines), which npc_plan asks for every
-- distinct leg of every loop on offer. 0207 (fewer loops) made the laps worse and was not shipped; this file
-- changes NO answer.
--
-- MEASURED (docs/dev-log/2026-10-19-arrivals-cache.md):
--   * A CACHE ACROSS ONE SWEEP DOES NOT PAY. In the paired sim, of 1,015 rankings asked in 32 sweeps only 62
--     repeat a ranking already asked in the same sweep with the same inputs (6 %); the exact-input key costs
--     ~3× what those repeats save. (Across sweeps 58 % repeat, but a cache that outlives its sweep is a second
--     copy of the market.) So the memo here is the one the numbers ask for: per LEG.
--   * Prod, read-only: one world.quote 1.8 ms, of which its quay's terms (world.quote_terms: the spread,
--     the bargain-free spread, the tax and the city's bid factor) 1.2 ms. A leg asks ~8 quotes at its two
--     quays (the size, the purse's walk, the buy, the sell, the ceiling) and each re-read the same terms.
--     The other merchants' buyers at the harbour (one query a leg) is 2.9 ms on prod: a sequential scan of
--     every stop of every route, for the stops at one harbour.
--
-- THE CHANGE (no rule moves; every figure is the same function's):
--   (1) public.npc_leg_lines reads world.quote_terms(p_from) and world.quote_terms(p_to) ONCE a leg and hands
--       them to every quote it asks (world.quote_priced, as world.trade_routes has since 0169). With no fleet
--       named a quote's terms are the quay's — the same for every good, size and side (0169, asserted there) —
--       and the leg writes nothing between its quotes, so every quote answers as before.
--   (2) public.npc_affordable and public.npc_buy_ceiling take the quay's terms as four optional trailing
--       arguments (default null). Not handed (every other caller, e.g. cmd.standing_route_lines), the quote
--       reads its own, exactly as before: world.quote IS world.quote_priced with the four terms null.
--       Each is dropped and created (a signature cannot be widened in place); its ACL is restored to the
--       pre-image's and asserted.
--   (3) An index on public.standing_route_stops (port_id), for the buyers count's "stops at this harbour".
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- CREATE INDEX on standing_route_stops (~2,700 rows on prod: milliseconds under a SHARE lock); DROP +
-- CREATE FUNCTION ×2 and CREATE OR REPLACE ×1 by hunks; the probe company is made inside a sub-transaction
-- rolled back whole. No LOCK TABLE, no set role, no begin. Timings are notices only.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0208, md5-equal to the chain's, LF-normalised, each asserted to occur
-- exactly once and to reverse to its pre-image, ACL unchanged): public.npc_affordable(uuid,uuid,numeric,numeric),
-- public.npc_buy_ceiling(uuid,uuid,numeric), public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric).
-- SELF-ASSERT: on its own probe company (and, where the world has merchants, the first 20 of the roster's
-- legs, read only — the leg planner writes nothing): every leg the new body prices is the pre-image's,
-- byte for byte, and some of them carry a parcel (else the proof is vacuous).
-- ROLLBACK: a forward slice restores the three bodies (each hunk's OLD text is here verbatim) and drops the index.
-- VERSION: 0209 (renumber to the prod head + 1 at push).
-- NOT FOR DEPLOY YET (2026-10-19 hand-off): PR #267's acceptance-shard (3/3) is red and its log was not read.
-- Read it to its last error first (docs/dev-log/2026-10-19-arrivals-cache.md § HAND-OFF).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0209(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE INDEX ───────────────────────────────────────────────────────────────────────────────
create index if not exists standing_route_stops_port on public.standing_route_stops (port_id);

-- ── 2. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0209 on commit drop as
select f.ord, f.fn, f.new_fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values (1, 'public.npc_affordable(uuid,uuid,numeric,numeric)',
                   'public.npc_affordable(uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric)'),
               (2, 'public.npc_buy_ceiling(uuid,uuid,numeric)',
                   'public.npc_buy_ceiling(uuid,uuid,numeric,numeric,numeric,numeric,numeric)'),
               (3, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)',
                   'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)')) f(ord, fn, new_fn);

-- the hunks: (fn, n, old, new) — each OLD occurs exactly once in its live body
create temp table hunks_0209 (fn text, n int, old text, new text) on commit drop;

insert into hunks_0209 values
('public.npc_affordable(uuid,uuid,numeric,numeric)', 1,
$h$CREATE OR REPLACE FUNCTION public.npc_affordable(p_port uuid, p_good uuid, p_qty numeric, p_budget numeric)
$h$,
$h$CREATE OR REPLACE FUNCTION public.npc_affordable(p_port uuid, p_good uuid, p_qty numeric, p_budget numeric, p_spread numeric DEFAULT NULL::numeric, p_nohag numeric DEFAULT NULL::numeric, p_tax numeric DEFAULT NULL::numeric, p_bidf numeric DEFAULT NULL::numeric)
$h$),
('public.npc_affordable(uuid,uuid,numeric,numeric)', 2,
$h$    select * into q from world.quote(p_port, p_good, v_q, 'buy', null, null);
$h$,
$h$    -- 0209: the quay's four terms when the caller read them once (public.npc_leg_lines: once a leg); not
    -- handed (all four null), world.quote_priced reads its own — world.quote is exactly that.
    select * into q from world.quote_priced(p_port, p_good, v_q, 'buy', null, null, p_spread, p_nohag, p_tax, p_bidf);
$h$),
('public.npc_buy_ceiling(uuid,uuid,numeric)', 1,
$h$CREATE OR REPLACE FUNCTION public.npc_buy_ceiling(p_port uuid, p_good uuid, p_patience numeric)
$h$,
$h$CREATE OR REPLACE FUNCTION public.npc_buy_ceiling(p_port uuid, p_good uuid, p_patience numeric, p_spread numeric DEFAULT NULL::numeric, p_nohag numeric DEFAULT NULL::numeric, p_tax numeric DEFAULT NULL::numeric, p_bidf numeric DEFAULT NULL::numeric)
$h$),
('public.npc_buy_ceiling(uuid,uuid,numeric)', 2,
$h$  select * into q from world.quote(p_port, p_good, 1, 'buy', null, null);
$h$,
$h$  -- 0209: the quay's four terms when the caller read them once (public.npc_leg_lines); not handed, its own.
  select * into q from world.quote_priced(p_port, p_good, 1, 'buy', null, null, p_spread, p_nohag, p_tax, p_bidf);
$h$),
('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', 1,
$h$  q_buy     record;
begin
$h$,
$h$  q_buy     record;
  k_from    record;   -- 0209: the source quay's quote terms (world.quote_terms), read once a leg
  k_to      record;   -- 0209: the sink's
begin
$h$),
('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', 2,
$h$  for v_pass in 1 .. 2 loop
$h$,
$h$  -- 0209: EACH QUAY'S PRICE TERMS, READ ONCE A LEG. Every quote below is at p_from or p_to with no fleet
  -- named, so its terms are the quay's (world.quote_terms: the same for every good, size and side — 0169),
  -- and nothing is written between them: each quote was re-reading the same four figures (1.2 ms of a
  -- 1.8 ms quote on prod, ~8 quotes a leg). They are read here and handed over (world.quote_priced).
  select * into k_from from world.quote_terms(p_from, null, null);
  select * into k_to   from world.quote_terms(p_to, null, null);
  for v_pass in 1 .. 2 loop
$h$),
('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', 3,
$h$      select * into q_size from world.quote(p_to, v_good, v_cap, 'sell',
                                            round((e->>'buy_price')::numeric * (1 + v_margin), 2), null);
$h$,
$h$      select * into q_size from world.quote_priced(p_to, v_good, v_cap, 'sell',
                                            round((e->>'buy_price')::numeric * (1 + v_margin), 2), null,
                                            k_to.q_spread, k_to.q_nohag, k_to.q_tax, k_to.q_bidf);   -- 0209
$h$),
('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', 4,
$h$      select a.units into v_q from public.npc_affordable(p_from, v_good, v_q, v_budget) a;
$h$,
$h$      select a.units into v_q from public.npc_affordable(p_from, v_good, v_q, v_budget,
                                     k_from.q_spread, k_from.q_nohag, k_from.q_tax, k_from.q_bidf) a;   -- 0209
$h$),
('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', 5,
$h$      select * into q_buy from world.quote(p_from, v_good, v_q, 'buy', null, null);
$h$,
$h$      select * into q_buy from world.quote_priced(p_from, v_good, v_q, 'buy', null, null,
                                                  k_from.q_spread, k_from.q_nohag, k_from.q_tax, k_from.q_bidf);   -- 0209
$h$),
('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', 6,
$h$      select * into q_sell from world.quote(p_to, v_good, v_q, 'sell', null, null);
$h$,
$h$      select * into q_sell from world.quote_priced(p_to, v_good, v_q, 'sell', null, null,
                                                   k_to.q_spread, k_to.q_nohag, k_to.q_tax, k_to.q_bidf);   -- 0209
$h$),
('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', 7,
$h$      v_ceiling := public.npc_buy_ceiling(p_from, v_good, h.patience);
$h$,
$h$      v_ceiling := public.npc_buy_ceiling(p_from, v_good, h.patience,
                                          k_from.q_spread, k_from.q_nohag, k_from.q_tax, k_from.q_bidf);   -- 0209
$h$);

-- the pre-images under pg_temp names, for the proof below; the old planner asks the old two
do $$
begin
  if (select count(*) from defs_before_0209 where def is not null) <> 3 then
    raise exception '0209 self-assert FAIL: % of the 3 bodies found', (select count(*) from defs_before_0209 where def is not null);
  end if;
  execute replace((select def from defs_before_0209 where ord = 1),
                  'CREATE OR REPLACE FUNCTION public.npc_affordable(', 'CREATE OR REPLACE FUNCTION pg_temp.npc_affordable_old_0209(');
  execute replace((select def from defs_before_0209 where ord = 2),
                  'CREATE OR REPLACE FUNCTION public.npc_buy_ceiling(', 'CREATE OR REPLACE FUNCTION pg_temp.npc_buy_ceiling_old_0209(');
  execute replace(replace(replace((select def from defs_before_0209 where ord = 3),
                  'CREATE OR REPLACE FUNCTION public.npc_leg_lines(', 'CREATE OR REPLACE FUNCTION pg_temp.npc_leg_lines_old_0209('),
                  'public.npc_affordable(', 'pg_temp.npc_affordable_old_0209('),
                  'public.npc_buy_ceiling(', 'pg_temp.npc_buy_ceiling_old_0209(');
end $$;

-- ── 3. THE NEW BODIES ──────────────────────────────────────────────────────────────────────────
do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
  g     record;
  v_n   int := 0;
begin
  for d in select * from defs_before_0209 order by ord loop
    v_def := d.def;
    for h in select * from hunks_0209 where fn = d.fn order by n loop
      if pg_temp.occurs_0209(v_def, h.old) <> 1 then
        raise exception '0209 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0209(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0209 self-assert FAIL: % has no hunk', d.fn;
    end if;
    -- a widened signature is a new function: the old one is dropped first (its callers name it by its
    -- first arguments, which the new one takes with the same names and positions)
    if d.fn <> d.new_fn then
      execute format('drop function %s', d.fn);
    end if;
    execute v_def;
    if d.fn <> d.new_fn then
      -- a function CREATEd here starts from the default ACL; put the pre-image's back, grant by grant
      execute format('revoke all on function %s from public', d.new_fn);
      for g in select r.rolname from pg_roles r
                where r.rolname in ('anon', 'authenticated', 'service_role') loop
        execute format('revoke all on function %s from %I', d.new_fn, g.rolname);
      end loop;
      for g in select distinct case when a.grantee = 0 then 'public' else a.grantee::regrole::text end as who
                 from pg_proc pp, aclexplode(coalesce(nullif(d.acl, '')::aclitem[], '{}'::aclitem[])) a
                where pp.oid = d.new_fn::regprocedure and a.grantee <> pp.proowner and a.privilege_type = 'EXECUTE' loop
        execute format('grant execute on function %s to %s', d.new_fn, g.who);
      end loop;
    end if;
    v_rev := replace(pg_get_functiondef(d.new_fn::regprocedure), E'\r', '');
    for h in select * from hunks_0209 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0209(v_rev, h.new) <> 1 then
        raise exception '0209 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0209 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = d.new_fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0209 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config', d.fn, d.acl, p.acl;
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n <> 3 then
    raise exception '0209 self-assert FAIL: % bodies re-cut, not 3', v_n;
  end if;
  if exists (select 1 from pg_proc pp join pg_namespace ns on ns.oid = pp.pronamespace
              where ns.nspname = 'public' and pp.proname in ('npc_affordable', 'npc_buy_ceiling')
              group by pp.proname having count(*) <> 1) then
    raise exception '0209 self-assert FAIL: an old signature survived beside the new one';
  end if;
end $$;

-- ── 4. SELF-ASSERT: every leg the new planner prices is the pre-image's ─────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0209-4000-8000-000000000001';
  v_out    text;
  v_player uuid;
  v_fleet  uuid;
  v_route  uuid;
  v_lis    uuid;
  v_fnc    uuid;
  v_course jsonb;
  v_hold   numeric;
  v_crew   int;
  v_speed  numeric;
  o        record;
  j_old    jsonb;
  j_new    jsonb;
  v_n      int := 0;
  v_bad    int := 0;
  v_buys   int := 0;
  v_mn     int := 0;
  v_mbad   int := 0;
  v_mbuys  int := 0;
  v_t0     timestamptz;
  v_ms     numeric;
  v_old_ms numeric := 0;
  v_new_ms numeric := 0;
  v_calls  numeric[] := '{}';
  v_badl   text := '';
  v_try    int;
  v_retry  int := 0;
begin
  begin
    -- THE PROBE COMPANY: a purse that buys, her one hull docked at Lisboa, a loop Lisboa - Funchal
    v_player := public.new_house(c_uid, 'Casa 0209', 'PRT', 'LIS', 'Gaivota', 'barca', 'Gaivota', 5000000);
    select f.id into v_fleet from public.fleets f where f.player_id = v_player order by f.created_at limit 1;
    select id into v_lis from public.ports where code = 'LIS';
    select id into v_fnc from public.ports where code = 'FNC';
    v_course := (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                                          jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                   from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc);
    v_route := (cmd.standing_route_save_for(v_player, null, 'Rota 0209',
                  jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_course),
                                    jsonb_build_object('port', 'FNC', 'course', jsonb_build_array(v_course->1, v_course->0))),
                  null, null, 0)->>'id')::uuid;
    if v_fleet is null or v_route is null then
      raise exception '0209 self-assert FAIL: the probe company has no fleet or no route';
    end if;
    update public.standing_routes set fleet_id = v_fleet where id = v_route;
    -- her hold, crew and laden speed as npc_plan reads them
    select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(s.id)), 0)
      into v_crew, v_hold
      from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_fleet;
    v_hold  := v_hold + public.fleet_free_hold(v_fleet);
    v_speed := greatest(coalesce(voyage.fleet_speed_at(v_fleet, 1), 0), 0.1);

    -- THE PROBE'S LEGS: Lisboa to her 40 nearest harbours, and back from each
    for o in (select v_lis as f, r.port_id as t from voyage.reach_from(v_lis) r
                join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR'
               where r.port_id <> v_lis order by r.nm, r.port_id limit 40)
             union all
             (select r.port_id, v_lis from voyage.reach_from(v_lis) r
                join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR'
               where r.port_id <> v_lis order by r.nm, r.port_id limit 40) loop
      v_t0 := clock_timestamp();
      j_old := pg_temp.npc_leg_lines_old_0209(v_route, o.f, o.t, v_hold, v_crew, v_speed);
      v_old_ms := v_old_ms + extract(epoch from clock_timestamp() - v_t0) * 1000;
      v_t0 := clock_timestamp();
      j_new := public.npc_leg_lines(v_route, o.f, o.t, v_hold, v_crew, v_speed);
      v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
      v_new_ms := v_new_ms + v_ms;
      v_calls := v_calls || v_ms;
      v_n := v_n + 1;
      -- a live sweep may trade at the quay between the two calls (each statement reads afresh): a differing
      -- leg is asked of both bodies again, and only one that differs every time is a difference
      for v_try in 1 .. 3 loop
        exit when j_old is not distinct from j_new;
        j_old := pg_temp.npc_leg_lines_old_0209(v_route, o.f, o.t, v_hold, v_crew, v_speed);
        j_new := public.npc_leg_lines(v_route, o.f, o.t, v_hold, v_crew, v_speed);
        v_retry := v_retry + 1;
      end loop;
      if j_old is distinct from j_new then
        v_bad := v_bad + 1;
        v_badl := v_badl || format(' %s>%s', (select code from public.ports where id = o.f), (select code from public.ports where id = o.t));
      end if;
      if coalesce((j_new->>'any')::boolean, false) then v_buys := v_buys + 1; end if;
    end loop;

    -- THE ROSTER'S FIRST 20 MERCHANTS, where the world has them: every leg of her present loop, read only
    for o in select z.route_id, z.fleet_id, z.f, z.t from (
               select nf.route_id, nf.fleet_id, nf.roster_ord, s.port_id as f,
                      coalesce((select s2.port_id from public.standing_route_stops s2 where s2.route_id = s.route_id and s2.ord = s.ord + 1),
                               (select s2.port_id from public.standing_route_stops s2 where s2.route_id = s.route_id and s2.ord = 0)) as t
                 from (select * from public.npc_fleets order by roster_ord limit 20) nf
                 join public.standing_route_stops s on s.route_id = nf.route_id) z
              order by z.roster_ord, z.f loop
      select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(s.id)), 0)
        into v_crew, v_hold
        from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = o.fleet_id;
      v_hold  := v_hold + public.fleet_free_hold(o.fleet_id);
      v_speed := greatest(coalesce(voyage.fleet_speed_at(o.fleet_id, 1), 0), 0.1);
      v_t0 := clock_timestamp();
      j_old := pg_temp.npc_leg_lines_old_0209(o.route_id, o.f, o.t, v_hold, v_crew, v_speed);
      v_old_ms := v_old_ms + extract(epoch from clock_timestamp() - v_t0) * 1000;
      v_t0 := clock_timestamp();
      j_new := public.npc_leg_lines(o.route_id, o.f, o.t, v_hold, v_crew, v_speed);
      v_new_ms := v_new_ms + extract(epoch from clock_timestamp() - v_t0) * 1000;
      v_mn := v_mn + 1;
      for v_try in 1 .. 3 loop
        exit when j_old is not distinct from j_new;
        j_old := pg_temp.npc_leg_lines_old_0209(o.route_id, o.f, o.t, v_hold, v_crew, v_speed);
        j_new := public.npc_leg_lines(o.route_id, o.f, o.t, v_hold, v_crew, v_speed);
        v_retry := v_retry + 1;
      end loop;
      if j_old is distinct from j_new then
        v_mbad := v_mbad + 1;
        v_badl := v_badl || format(' roster %s>%s', (select code from public.ports where id = o.f), (select code from public.ports where id = o.t));
      end if;
      if coalesce((j_new->>'any')::boolean, false) then v_mbuys := v_mbuys + 1; end if;
    end loop;

    if v_n <> 80 then
      raise exception '0209 self-assert FAIL: the probe priced % legs, not 80', v_n;
    end if;
    if v_bad + v_mbad <> 0 then
      raise exception '0209 self-assert FAIL: % of % probe legs and % of % roster legs differ from the pre-image:%', v_bad, v_n, v_mbad, v_mn, v_badl;
    end if;
    -- the proof is vacuous unless some leg keeps a parcel: only then were the size, the purse's walk, the
    -- buy, the sell and the ceiling all asked with the handed terms (the roster's legs count: on prod and
    -- on the chain's own world the roster is there; the probe's own parcels depend on the day's market)
    if v_buys + v_mbuys = 0 then
      raise exception '0209 self-assert FAIL: no leg carries a parcel (probe % of %, roster % of %) — the quotes the change touches were never asked',
        v_buys, v_n, v_mbuys, v_mn;
    end if;

    v_out := format('%s probe legs (%s with a parcel) and %s roster legs (%s with a parcel) priced by both bodies, all equal; '
                    || '%s asked again after a live trade; %s ms new against %s ms old; the probe''s first 6 calls %s ms, its last 6 %s ms',
                    v_n, v_buys, v_mn, v_mbuys, v_retry, round(v_new_ms), round(v_old_ms),
                    round((select avg(x) from unnest(v_calls[1:6]) x), 1),
                    round((select avg(x) from unnest(v_calls[array_length(v_calls, 1) - 5:]) x), 1));
    raise exception using errcode = 'ZX209', message = v_out;
  exception when sqlstate 'ZX209' then
    v_out := sqlerrm;
  end;
  if exists (select 1 from public.players where auth_uid = c_uid) then
    raise exception '0209 self-assert FAIL: the probe company survived its rollback';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'standing_route_stops_port') then
    raise exception '0209 self-assert FAIL: the stops'' harbour index is not there';
  end if;
  raise notice '0209 self-assert ok: A LEG READS ITS QUAYS ONCE. public.npc_leg_lines reads each quay''s quote terms once a leg (7 hunks); public.npc_affordable and public.npc_buy_ceiling take them (2 hunks each, ACL restored); all reverse; index standing_route_stops_port. %.', v_out;
end $$;

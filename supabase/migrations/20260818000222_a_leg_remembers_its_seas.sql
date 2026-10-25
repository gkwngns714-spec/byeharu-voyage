-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0222 — A LEG REMEMBERS ITS SEAS  (docs/dev-log/2026-10-26-board-fast.md — world.good_board under a second:
--        the zones of a leg are DERIVED ONCE into public.sea_leg_asks and READ by public.sea_routes, never sampled
--        per board; and the board's own plan_cache_mode (0206) no longer re-plans every callee)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT PROD MEASURED (the main session, after 0219 went live, six boards in one session) ──────
--   world.good_board(good, fleet, null, null): 3,885 / 4,281 / 4,234 / 3,224 / 3,584 / 4,247 ms. Steady, so not
--   0205's generic-plan cliff. The core trading screen; the owner needs the game playable. Target ≤ 1,000 ms.
--
-- ── WHERE THE TIME WENT (profiled on the local world with 0217–0219 applied, clock_timestamp splits) ──
--   A ~3.0–3.5 s board: reach_passage 100–140 ms · BUY AT 50–145 ms · SELL AT ~800 ms · the 0219 sea pass over
--   the sell side 1,500–2,600 ms. Inside the sea pass: public.sea_routes samples public.course_zones for every
--   distinct open-water crossing on the board (69 legs → ~2,000 public.sea_zone_at reads a board). The same
--   sea_routes call outside world.good_board took 400 ms; inside it 1.9–2.6 s — because a function's
--   `SET plan_cache_mode = force_custom_plan` (0206) holds for EVERYTHING IT CALLS: every statement of every callee
--   (sea_zone_at ×2,000, mid_price ×246, passage_needs ×492, quote, price_outlook, …) is re-planned on every
--   execution. Measured: sea_zone_at ×2,000 56 → 324 ms, mid_price ×246 50 → 130 ms, passage_needs ×246 120 → 430 ms
--   under force_custom_plan; the whole board 2.5–3.5 s with it and 0.6 s without, byte-identical, over 12 calls.
--   0206's cliff was voyage.reach_passage's (its own table of 2026-10-19: boards 954–1,456 ms at default plans
--   with reach_passage fast; 2,375–2,873 ms with force_custom_plan); reach_passage KEEPS its setting here.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   (1) public.sea_leg_asks gains `zones text[]` NOT NULL: the distinct zones (code order) on the straight line
--       between the two roadsteads — the very set public.course_zones samples (asserted equal on every leg touching
--       Lisbon); a harbour's self row holds its roadstead's zone (= public.harbour_zone, asserted for every harbour).
--       public.sea_leg_asks_derive — THE ONE DERIVATION (0215) — returns it; dropped and recreated for the new
--       column (ACL, volatility, definer, config, owner asserted unchanged), the table filled from it.
--   (2) public.sea_routes (0219) re-cut by ONE hunk (its body): the harbour's zone is read from its self row, a
--       crossing's zones from its leg row; public.sea_refusal is asked once per DISTINCT zone set. No
--       course_zones, no sea_zone_at, no harbour_zone per board: a handful of joins on sea_leg_asks' primary key.
--       The rule is unchanged: a leg asking more than both its harbours' zones brings the line's zones, else its
--       two harbours' own; refusal = the first refusing zone in requirement order; `zone` = the refusing zone,
--       else the most demanding. Output byte for byte (asserted: boards old vs new, dark and lit).
--   (3) ALTER FUNCTION world.good_board RESET plan_cache_mode: the board's own statements never cliffed (0206's
--       table), its callees pay for the setting. voyage.reach_passage keeps `force_custom_plan` — THAT was the
--       cliff, and it is still the only caller-protected function. Asserted: body, ACL, volatility, definer, owner
--       and search_path unchanged; only plan_cache_mode gone; twelve new boards in one session with no cliff
--       (calls 7–12 within 2× of calls 1–6).
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
--   Change any figure or key the board serves (asserted old = new, byte for byte, for the probe and the world's
--   humans, dark and lit). Touch world.good_board's body, voyage.reach_passage, the gate, the switch, or what a
--   leg asks (wave_min / title_min are as 0215 derived them: asserted unchanged by the fill). Sample anything at
--   read time. A harbour with no self row (a harbour added without re-deriving the table — which 0217's assert
--   forbids) would now read no zone; the table is asserted whole (n² rows, no null or empty zones).
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
--   ALTER TABLE ADD COLUMN (metadata), one UPDATE of the 60,516 rows, ALTER COLUMN SET NOT NULL (one scan), the
--   derive ~3 s (PGlite), DROP/CREATE FUNCTION ×1, CREATE OR REPLACE ×1, ALTER FUNCTION ×1. lock_timeout 5 s.
--   The probe company is made in a sub-transaction rolled back whole (the switch is lit inside it and rolled back
--   with it). Timing: good_board old ×6 and new ×12 in this session, dark. raise notice only.
--
-- SUPERSEDES, by a hunk sliced from the LIVE body (prod head 0219–0221, LF-normalised, asserted to occur exactly
-- once and to reverse to its pre-image, ACL / volatility / definer / owner / config unchanged):
--   public.sea_routes(int, numeric, jsonb) (1 hunk: the body), as 0219 created it
--   (supabase/migrations/20260818000219_the_board_reads_the_sea.sql:182-248).
-- DROPPED / RECREATED (return type): public.sea_leg_asks_derive(uuid), as 0215 created it (…0215…:559-614).
-- RESET: world.good_board(uuid, uuid, uuid, numeric) plan_cache_mode (0206).
--
-- SELF-ASSERT (own probe rows only, rolled back): the table whole (n² rows, no null or empty zones, wave/title
-- unchanged by the fill); every self row = harbour_zone; every leg touching Lisbon = course_zones; a barca at
-- Lisbon: five boards old = new byte for byte (dark), one with p_from = Lisbon, Las Palmas refused E_SEA_CLOSED
-- at title 1 (the positive control: refused and clear rows both present); the first three docked humans × two
-- goods old = new; LIT (inside the rollback): one board old = new; TIMING old ×6, new ×12, no cliff. Walls hold.
-- ROLLBACK (forward migration): reverse the sea_routes hunk (its OLD text is here verbatim); ALTER FUNCTION
-- world.good_board SET plan_cache_mode = force_custom_plan; the column may stay (nothing else reads it) or go
-- with the derive recreated from 0215.
-- VERSION: 0222 (renumber to the prod head + 1 at push; applies on 0219, 0220 or 0221).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0222(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table t0_0222 on commit drop as select clock_timestamp() as t0;

-- ── 1. THE PRE-IMAGE ───────────────────────────────────────────────────────────────────────────
create temp table defs_before_0222 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner,
       (select p.prosrc from pg_proc p where p.oid = f.fn::regprocedure) as src
  from (values ('public.sea_routes(int,numeric,jsonb)'),
               ('public.sea_leg_asks_derive(uuid)'),
               ('world.good_board(uuid,uuid,uuid,numeric)')) f(fn);

create temp table before_0222 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.sea_leg_asks) as legs,
       (select count(*) from public.ports where kind = 'HARBOUR') as harbours;

-- what every leg asked before the fill: the fill must not move a figure
create temp table asks_before_0222 on commit drop as
select from_port, to_port, wave_min, title_min from public.sea_leg_asks;

do $$
begin
  if (select count(*) from defs_before_0222 where def is not null) <> 3 then
    raise exception '0222 self-assert FAIL: sea_routes, sea_leg_asks_derive or good_board was not found';
  end if;
  if (select cfg from defs_before_0222 where fn = 'world.good_board(uuid,uuid,uuid,numeric)') not like '%plan_cache_mode=force_custom_plan%' then
    raise exception '0222 self-assert FAIL: world.good_board does not carry 0206''s plan_cache_mode (config %)',
      (select cfg from defs_before_0222 where fn = 'world.good_board(uuid,uuid,uuid,numeric)');
  end if;
  if (select cfg from defs_before_0222 where fn = 'world.good_board(uuid,uuid,uuid,numeric)') not like '%search_path=public, pg_temp%' then
    raise exception '0222 self-assert FAIL: world.good_board does not carry its search_path (config %)',
      (select cfg from defs_before_0222 where fn = 'world.good_board(uuid,uuid,uuid,numeric)');
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sea_leg_asks' and column_name = 'zones') then
    raise exception '0222 self-assert FAIL: sea_leg_asks already has a zones column';
  end if;
  -- the pre-images under pg_temp names: the OLD sea_routes, and the OLD board calling it (with 0206's setting)
  execute replace((select def from defs_before_0222 where fn = 'public.sea_routes(int,numeric,jsonb)'),
                  'CREATE OR REPLACE FUNCTION public.sea_routes(', 'CREATE OR REPLACE FUNCTION pg_temp.sea_routes_old_0222(');
  if pg_temp.occurs_0222((select def from defs_before_0222 where fn = 'world.good_board(uuid,uuid,uuid,numeric)'), 'public.sea_routes(') <> 2 then
    raise exception '0222 self-assert FAIL: world.good_board calls public.sea_routes % time(s), not 2',
      pg_temp.occurs_0222((select def from defs_before_0222 where fn = 'world.good_board(uuid,uuid,uuid,numeric)'), 'public.sea_routes(');
  end if;
  execute replace(replace((select def from defs_before_0222 where fn = 'world.good_board(uuid,uuid,uuid,numeric)'),
                          'CREATE OR REPLACE FUNCTION world.good_board(', 'CREATE OR REPLACE FUNCTION pg_temp.good_board_old_0222('),
                  'public.sea_routes(', 'pg_temp.sea_routes_old_0222(');
end $$;

create temp table hunks_0222 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0222 values
('public.sea_routes(int,numeric,jsonb)', 1,
$h$  -- 0219: WHAT EACH ROUTE'S SEAS ASK, in the routes' order: { zone, zone_name, needs_title, needs_wave, refusal },
  -- null for a route with no leg. needs = the most any leg asks in public.sea_leg_asks (the one derivation). The
  -- zones = every harbour's own (public.harbour_zone) and, for a leg asking more than both its harbours' zones, the
  -- zones public.course_zones finds on the straight line between the roadsteads (the line sea_leg_asks was derived
  -- from). The verdict is public.sea_refusal — the one rule; nothing is compared here. `zone` = the refusing zone,
  -- else the most demanding (title, wave, requirement order).
  with rt as materialized (
    select r.i, r.route
      from jsonb_array_elements(case when jsonb_typeof(p_routes) = 'array' then p_routes else '[]'::jsonb end)
           with ordinality r(route, i)),
  pt as materialized (
    select r.i, s.k, s.code
      from rt r
     cross join lateral jsonb_array_elements_text(case when jsonb_typeof(r.route) = 'array' then r.route else '[]'::jsonb end)
           with ordinality s(code, k)),
  harbour as materialized (
    select p.code, p.id, z.code as zone, z.title_min, z.wave_min
      from (select distinct code from pt where code is not null) c
      join public.ports p on p.code = c.code and p.kind = 'HARBOUR'
      left join public.sea_zones z on z.code = public.harbour_zone(p.id)),
  leg as materialized (
    select a.i, ha.id as from_id, hb.id as to_id, ha.zone as from_zone, hb.zone as to_zone, s.title_min, s.wave_min,
           coalesce(s.title_min > greatest(coalesce(ha.title_min, 0), coalesce(hb.title_min, 0))
                    or s.wave_min > greatest(coalesce(ha.wave_min, -1), coalesce(hb.wave_min, -1)), false) as crosses
      from pt a
      join pt b on b.i = a.i and b.k = a.k + 1
      join harbour ha on ha.code = a.code
      join harbour hb on hb.code = b.code
      left join public.sea_leg_asks s on s.from_port = ha.id and s.to_port = hb.id
     where a.code <> b.code),
  crossing as materialized (
    select d.from_id, d.to_id,
           public.course_zones(jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                                                 jsonb_build_array(b.roadstead_lat, b.roadstead_lon))) as zones
      from (select distinct l.from_id, l.to_id from leg l where l.crosses) d
      join public.sea_reaches a on a.port_id = d.from_id
      join public.sea_reaches b on b.port_id = d.to_id),
  zone_of as (
    select l.i, l.from_zone as zone from leg l
    union
    select l.i, l.to_zone from leg l
    union
    select l.i, z.zone from leg l join crossing c on c.from_id = l.from_id and c.to_id = l.to_id
     cross join lateral unnest(c.zones) z(zone)),
  judged as materialized (
    select q.i, q.needs_title, q.needs_wave, zs.zones, public.sea_refusal(p_title, p_wave, zs.zones) as refusal
      from (select l.i, max(l.title_min) as needs_title, max(l.wave_min) as needs_wave from leg l group by l.i) q
      left join (select o.i, array_agg(o.zone order by o.zone) filter (where o.zone is not null) as zones
                   from zone_of o group by o.i) zs on zs.i = q.i)
  select coalesce(jsonb_agg(case when j.i is null then null else jsonb_build_object(
           'zone',        coalesce(j.refusal->'figures'->>'zone', top.code),
           'zone_name',   coalesce(j.refusal->'figures'->>'zone_name', top.name),
           'needs_title', j.needs_title,
           'needs_wave',  j.needs_wave,
           'refusal',     j.refusal) end order by r.i), '[]'::jsonb)
    from rt r
    left join judged j on j.i = r.i
    left join lateral (select z.code, z.name from public.sea_zones z
                        where z.code = any(coalesce(j.zones, '{}'::text[]))
                        order by z.title_min desc, z.wave_min desc, z.ord limit 1) top on true
$h$,
$h$  -- 0219: WHAT EACH ROUTE'S SEAS ASK, in the routes' order: { zone, zone_name, needs_title, needs_wave, refusal },
  -- null for a route with no leg. needs = the most any leg asks in public.sea_leg_asks (the one derivation).
  -- 0222: THE ZONES ARE READ, NEVER SAMPLED (docs/dev-log/2026-10-26-board-fast.md). A harbour's own zone is its
  -- self row's (sea_leg_asks.zones where from = to: the roadstead's zone, public.harbour_zone's reading at
  -- derivation). A leg asking more than both its harbours' zones (an open-water crossing) brings its row's zones —
  -- the distinct set public.course_zones samples on the straight line between the roadsteads, derived once by
  -- public.sea_leg_asks_derive — else its two harbours' own. The verdict is public.sea_refusal — the one rule,
  -- asked once per distinct zone set; nothing is compared here. `zone` = the refusing zone, else the most
  -- demanding (title, wave, requirement order).
  with rt as materialized (
    select r.i, r.route
      from jsonb_array_elements(case when jsonb_typeof(p_routes) = 'array' then p_routes else '[]'::jsonb end)
           with ordinality r(route, i)),
  pt as materialized (
    select r.i, s.k, s.code
      from rt r
     cross join lateral jsonb_array_elements_text(case when jsonb_typeof(r.route) = 'array' then r.route else '[]'::jsonb end)
           with ordinality s(code, k)),
  harbour as materialized (
    select p.code, p.id, z.code as zone, z.title_min, z.wave_min
      from (select distinct code from pt where code is not null) c
      join public.ports p on p.code = c.code and p.kind = 'HARBOUR'
      left join public.sea_leg_asks own on own.from_port = p.id and own.to_port = p.id
      left join public.sea_zones z on z.code = own.zones[1]),
  leg as materialized (
    select a.i, s.title_min, s.wave_min,
           case when coalesce(s.title_min > greatest(coalesce(ha.title_min, 0), coalesce(hb.title_min, 0))
                              or s.wave_min > greatest(coalesce(ha.wave_min, -1), coalesce(hb.wave_min, -1)), false)
                then s.zones else array[ha.zone, hb.zone] end as zones
      from pt a
      join pt b on b.i = a.i and b.k = a.k + 1
      join harbour ha on ha.code = a.code
      join harbour hb on hb.code = b.code
      left join public.sea_leg_asks s on s.from_port = ha.id and s.to_port = hb.id
     where a.code <> b.code),
  zone_of as (
    select l.i, z.zone from leg l cross join lateral unnest(l.zones) z(zone) where z.zone is not null),
  route as materialized (
    select q.i, q.needs_title, q.needs_wave, zs.zones
      from (select l.i, max(l.title_min) as needs_title, max(l.wave_min) as needs_wave from leg l group by l.i) q
      left join (select o.i, array_agg(distinct o.zone order by o.zone) as zones from zone_of o group by o.i) zs on zs.i = q.i),
  judged as materialized (
    select r.i, r.needs_title, r.needs_wave, r.zones, v.refusal
      from route r
      join (select d.zones, public.sea_refusal(p_title, p_wave, d.zones) as refusal
              from (select distinct zones from route) d) v on v.zones is not distinct from r.zones)
  select coalesce(jsonb_agg(case when j.i is null then null else jsonb_build_object(
           'zone',        coalesce(j.refusal->'figures'->>'zone', top.code),
           'zone_name',   coalesce(j.refusal->'figures'->>'zone_name', top.name),
           'needs_title', j.needs_title,
           'needs_wave',  j.needs_wave,
           'refusal',     j.refusal) end order by r.i), '[]'::jsonb)
    from rt r
    left join judged j on j.i = r.i
    left join lateral (select z.code, z.name from public.sea_zones z
                        where z.code = any(coalesce(j.zones, '{}'::text[]))
                        order by z.title_min desc, z.wave_min desc, z.ord limit 1) top on true
$h$);

-- ── 2. THE COLUMN, AND THE ONE DERIVATION THAT FILLS IT ────────────────────────────────────────
alter table public.sea_leg_asks add column zones text[];

comment on column public.sea_leg_asks.zones is
  '0222: the distinct zones (code order) on the straight line between the two roadsteads — the set public.course_zones '
  'samples; a harbour''s self row holds its roadstead''s zone (public.harbour_zone). DERIVED by public.sea_leg_asks_derive() '
  'with the asks; read by public.sea_routes. Never hand-edited.';

comment on table public.sea_leg_asks is
  '0215: what a harbour-to-harbour leg asks WITHOUT a course — the most any zone on the straight line between the '
  'two roadsteads asks, and the destination''s zone; 0222: + the zones on that line. DERIVED by '
  'public.sea_leg_asks_derive(); re-derived whenever a zone or a box moves; never hand-edited. Read by '
  'voyage.reach_passage (S2: the desk''s Dijkstra has distances, not courses) and public.sea_routes (the board).';

drop function public.sea_leg_asks_derive(uuid);

create function public.sea_leg_asks_derive(p_from uuid default null)
returns table (from_port uuid, to_port uuid, wave_min int, title_min int, zones text[])
language sql
stable security definer
set search_path = public, pg_temp
as $$
  -- 0215: THE ONE DERIVATION of public.sea_leg_asks — for every ordered pair of harbours, the most any zone on the
  -- STRAIGHT line between the two roadsteads asks (sampled every sea_sample_nm, land ignored, the same rule as
  -- public.course_zones) joined with what the destination's own zone asks. A harbour to itself asks its own zone's.
  -- With p_from: only the legs out of that harbour (a re-derivation check; the table is filled with none).
  -- 0222: + `zones`, the distinct zones (code order) those samples found — course_zones' set for the line, kept so
  -- the board reads it instead of sampling it (docs/dev-log/2026-10-26-board-fast.md); a self row's is the
  -- roadstead's zone.
  -- SPEED (the prod push of 2026-10-20 lost its connection minutes into this file): ~5 million samples, so each is
  -- plain arithmetic. The longitude is voyage.lon_lerp's arithmetic WRITTEN OUT (the step the short way round, the
  -- wrap by one turn, the endpoints as given): the planner cannot inline lon_lerp (its scalar sub-select), and a
  -- call costs ~6 µs, 30 s of the first cut's 72 s on native PostgreSQL 16. The 0215 self-assert holds every sample
  -- of every leg out of Lisbon to voyage.lon_lerp to the cell, and every one of those legs to public.course_zones.
  -- The pairs are materialised (else the planner re-computes the great circle per sample) and each pair's zone
  -- bytes are made distinct inside the pair (no 5-million-row sort). 2.3 s, the same 56,644 rows as the first cut.
  with knob as materialized (select public.wc_num('sea_sample_nm')::float8 as step),
  -- the whole zone raster as ONE bytea (720 rows × 1,440 bytes), read once: a sample is one get_byte, no join
  raster as materialized (select string_agg(c.zones, ''::bytea order by c.row_idx) as cells from public.sea_zone_cells c),
  h as materialized (
    select row_number() over (order by p.code)::int as i, p.id, p.code,
           sr.roadstead_lat::float8 as lat, sr.roadstead_lon::float8 as lon, public.harbour_zone(p.id) as zone
      from public.ports p join public.sea_reaches sr on sr.port_id = p.id
     where p.kind = 'HARBOUR'),
  pairs as materialized (
    select a.i as a_i, b.i as b_i, a.lat as lat1, a.lon as lon1, b.lat as lat2, b.lon as lon2,
           (b.lon - a.lon) - 360 * round((b.lon - a.lon) / 360) as dlon,   -- voyage.lon_lerp's step, the short way round
           greatest(1, ceil(voyage.gc_distance_nm(a.lat, a.lon, b.lat, b.lon) / (select step from knob)))::int as n
      from h a join h b on a.code < b.code
     where p_from is null or a.id = p_from or b.id = p_from),
  crossed as (
    select p.a_i, p.b_i, max(z.wave_min) as wave_min, max(z.title_min) as title_min,
           array_agg(distinct z.code order by z.code) as zones   -- 0222
      from pairs p
     cross join lateral (
       select distinct get_byte((select cells from raster),
                                public.sea_cell_row(p.lat1 + (p.lat2 - p.lat1) * k / p.n) * 1440
                                + public.sea_cell_col(case when k = 0 then p.lon1 when k = p.n then p.lon2
                                                           else l.x + case when l.x > 180 then -360 when l.x < -180 then 360 else 0 end
                                                      end)) as zb
         from generate_series(0, p.n) k
        cross join lateral (select p.lon1 + p.dlon * (k::float8 / p.n) as x) l) s
      join public.sea_zones z on z.ord = s.zb   -- land (0) joins no zone
     group by p.a_i, p.b_i),
  both_ways as (
    select c.a_i as f, c.b_i as t, c.wave_min, c.title_min, c.zones from crossed c
    union all
    select c.b_i, c.a_i, c.wave_min, c.title_min, c.zones from crossed c
    union all
    select h.i, h.i, null::int, null::int, array[h.zone] from h)   -- 0222: a harbour to itself: its roadstead's zone
  select hf.id, ht.id, greatest(coalesce(w.wave_min, 0), z.wave_min)::int, greatest(coalesce(w.title_min, 1), z.title_min)::int, w.zones
    from both_ways w
    join h hf on hf.i = w.f
    join h ht on ht.i = w.t
    join public.sea_zones z on z.code = ht.zone
   where p_from is null or hf.id = p_from
$$;

revoke all on function public.sea_leg_asks_derive(uuid) from public, anon, authenticated;

update public.sea_leg_asks a
   set zones = d.zones
  from public.sea_leg_asks_derive() d
 where d.from_port = a.from_port and d.to_port = a.to_port;

alter table public.sea_leg_asks alter column zones set not null;

create temp table t1_0222 on commit drop as select clock_timestamp() as t1;

do $$
declare
  d record;
  p record;
  v_n int;
begin
  -- the derive: recreated as it was, but for the column it returns
  select * into d from defs_before_0222 where fn = 'public.sea_leg_asks_derive(uuid)';
  select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
         coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
    into p from pg_proc pr where pr.oid = 'public.sea_leg_asks_derive(uuid)'::regprocedure;
  if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
    raise exception '0222 self-assert FAIL: sea_leg_asks_derive changed its ACL (% → %), owner, volatility, definer or config (% → %)', d.acl, p.acl, d.cfg, p.cfg;
  end if;
  -- the table: whole, every zone set present, no figure moved
  if (select count(*) from public.sea_leg_asks) <> (select legs from before_0222)
     or (select count(*) from public.sea_leg_asks) <> (select harbours * harbours from before_0222) then
    raise exception '0222 self-assert FAIL: % leg asks for % harbours (% before)', (select count(*) from public.sea_leg_asks),
      (select harbours from before_0222), (select legs from before_0222);
  end if;
  if exists (select 1 from public.sea_leg_asks where cardinality(zones) = 0 or array_position(zones, null) is not null) then
    raise exception '0222 self-assert FAIL: a leg has an empty zone set, or a null in it';
  end if;
  select count(*) into v_n
    from public.sea_leg_asks a join asks_before_0222 b on b.from_port = a.from_port and b.to_port = a.to_port
   where a.wave_min <> b.wave_min or a.title_min <> b.title_min;
  if v_n <> 0 then
    raise exception '0222 self-assert FAIL: the fill moved % leg ask(s)', v_n;
  end if;
  -- every self row is the harbour's own zone, as public.harbour_zone reads it
  select count(*) into v_n
    from public.ports pt left join public.sea_leg_asks a on a.from_port = pt.id and a.to_port = pt.id
   where pt.kind = 'HARBOUR' and (a.zones is null or a.zones <> array[public.harbour_zone(pt.id)]);
  if v_n <> 0 then
    raise exception '0222 self-assert FAIL: % harbour self row(s) do not hold the harbour''s own zone', v_n;
  end if;
  -- every leg touching Lisbon holds exactly the set public.course_zones samples on the roadstead line (both ways)
  select count(*) into v_n
    from public.sea_leg_asks a
    join public.sea_reaches f on f.port_id = a.from_port
    join public.sea_reaches t on t.port_id = a.to_port
   where (a.from_port = (select id from public.ports where code = 'LIS') or a.to_port = (select id from public.ports where code = 'LIS'))
     and a.zones <> public.course_zones(jsonb_build_array(jsonb_build_array(f.roadstead_lat, f.roadstead_lon),
                                                          jsonb_build_array(t.roadstead_lat, t.roadstead_lon)));
  if v_n <> 0 then
    raise exception '0222 self-assert FAIL: % leg(s) touching Lisbon hold a zone set public.course_zones does not sample', v_n;
  end if;
end $$;

-- ── 3. THE BOARD'S READER: ONE HUNK, THE BODY ──────────────────────────────────────────────────
do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
begin
  select * into d from defs_before_0222 where fn = 'public.sea_routes(int,numeric,jsonb)';
  v_def := d.def;
  for h in select * from hunks_0222 order by n loop
    if pg_temp.occurs_0222(v_def, h.old) <> 1 then
      raise exception '0222 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
        d.fn, h.n, pg_temp.occurs_0222(v_def, h.old);
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
  v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
  for h in select * from hunks_0222 order by n desc loop
    if pg_temp.occurs_0222(v_rev, h.new) <> 1 then
      raise exception '0222 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
    end if;
    v_rev := replace(v_rev, h.new, h.old);
  end loop;
  if v_rev <> d.def then
    raise exception '0222 self-assert FAIL: % does not reverse to its pre-image', d.fn;
  end if;
  select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
         coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
    into p from pg_proc pr where pr.oid = d.fn::regprocedure;
  if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
    raise exception '0222 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config (% → %)', d.fn, d.acl, p.acl, d.cfg, p.cfg;
  end if;
  if pg_get_functiondef(d.fn::regprocedure) like '%course_zones(%' or pg_get_functiondef(d.fn::regprocedure) like '%harbour_zone(%' then
    raise exception '0222 self-assert FAIL: the new sea_routes still samples';
  end if;
end $$;

-- ── 4. THE BOARD PLANS LIKE EVERY OTHER READ; THE PATHFINDER KEEPS ITS OWN PLAN ────────────────
alter function world.good_board(uuid, uuid, uuid, numeric) reset plan_cache_mode;

do $$
declare
  d record;
  p record;
begin
  select * into d from defs_before_0222 where fn = 'world.good_board(uuid,uuid,uuid,numeric)';
  select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
         coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner, pr.prosrc as src
    into p from pg_proc pr where pr.oid = d.fn::regprocedure;
  if p.src <> d.src or p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.owner <> d.owner then
    raise exception '0222 self-assert FAIL: world.good_board changed beyond its plan setting (ACL % → %)', d.acl, p.acl;
  end if;
  if p.cfg like '%plan_cache_mode%' or p.cfg not like '%search_path=public, pg_temp%' then
    raise exception '0222 self-assert FAIL: world.good_board config is % (was %)', p.cfg, d.cfg;
  end if;
  if (select coalesce(pr.proconfig::text, '') from pg_proc pr where pr.oid = 'voyage.reach_passage(uuid,uuid,uuid)'::regprocedure)
     not like '%plan_cache_mode=force_custom_plan%' then
    raise exception '0222 self-assert FAIL: voyage.reach_passage has lost 0206''s plan_cache_mode';
  end if;
end $$;

-- ── 5. SELF-ASSERT: THE BOARD, BYTE FOR BYTE, AND THE TIME ─────────────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0222-4000-8000-000000000001';
  v_player uuid;
  v_fleet  uuid;
  v_lis    uuid;
  v_lpa    uuid;
  v_good   uuid;
  v_gcode  text;
  v_old    jsonb;
  v_new    jsonb;
  v_lp     jsonb;
  g        record;
  hu       record;
  v_i      int;
  v_t0     timestamptz;
  v_gb_old numeric[] := '{}';
  v_gb_new numeric[] := '{}';
  v_boards int := 0;
  v_rows   int := 0;
  v_shut   int := 0;
  v_open   int := 0;
  v_humans int := 0;
  v_lit    int := 0;
begin
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_lpa from public.ports where code = 'LPA';
  if v_lis is null or v_lpa is null then
    raise exception '0222 self-assert FAIL: Lisbon or Las Palmas is missing';
  end if;
  if public.sea_conditions_on() then
    raise exception '0222 self-assert FAIL: sea_conditions_bite is already lit — this file was proven dark first';
  end if;
  -- the subject good: the first by code that Las Palmas sells (its buy row from Lisbon is refused at title 1: the
  -- positive control, as 0219 chose it)
  select gd.id, gd.code into v_good, v_gcode
    from public.goods gd join public.port_goods pg on pg.good_id = gd.id and pg.port_id = v_lpa
   where public.port_offers(v_lpa, gd.id)
   order by gd.code limit 1;
  if v_good is null then
    raise exception '0222 self-assert FAIL: Las Palmas sells no good';
  end if;

  begin
    -- THE PROBE COMPANY: a barca at Lisbon, title 1, NAVIGATION 5 (a wide reach: long routes, far seas), stores
    v_player := public.new_house(c_uid, 'Casa 0222', 'PRT', 'LIS', 'Gaivota', 'barca', 'Gaivota 0222', 500000);
    select f.id into v_fleet from public.fleets f where f.player_id = v_player order by f.created_at limit 1;
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, 5 from public.skills sk where sk.code in ('NAVIGATION', 'SEAMANSHIP');
    update public.ships set water_t = 20, food_t = 20 where fleet_id = v_fleet;
    perform cmd.assume_identity(c_uid);
    if public.current_player_id() is distinct from v_player then
      raise exception '0222 self-assert FAIL: the probe is not the signed-in house';
    end if;

    -- (a) DARK: five goods spread over the catalogue, old board = new board, byte for byte (one transaction: one now())
    for g in select x.id, x.code from (select gd.id, gd.code, row_number() over (order by gd.code) as rn, count(*) over () as n
                                         from public.goods gd) x
              where x.rn in (1, (x.n + 2) / 4, (x.n + 1) / 2, (3 * x.n) / 4, x.n) loop
      v_old := pg_temp.good_board_old_0222(g.id, v_fleet, null, null);
      v_new := world.good_board(g.id, v_fleet, null, null);
      if v_old::text <> v_new::text then
        raise exception '0222 self-assert FAIL: dark, the % board differs from its pre-image', g.code;
      end if;
      v_boards := v_boards + 1;
    end loop;
    -- (b) the control good, bought at Lisbon: old = new; Las Palmas refused E_SEA_CLOSED at title 1; clear rows too
    v_old := pg_temp.good_board_old_0222(v_good, v_fleet, v_lis, null);
    v_new := world.good_board(v_good, v_fleet, v_lis, null);
    if v_old::text <> v_new::text then
      raise exception '0222 self-assert FAIL: dark, the % board from Lisbon differs from its pre-image', v_gcode;
    end if;
    v_boards := v_boards + 1;
    select x into v_lp from jsonb_array_elements(v_new->'buy') x where x->>'port' = 'LPA';
    if v_lp is null or v_lp->'sea'->'refusal'->>'code' is distinct from 'E_SEA_CLOSED' or (v_lp->'sea'->>'needs_title')::int < 2 then
      raise exception '0222 self-assert FAIL: dark, the Las Palmas buy row reads %', v_lp;
    end if;
    select count(*), count(*) filter (where jsonb_typeof(x->'sea'->'refusal') = 'object'),
           count(*) filter (where jsonb_typeof(x->'sea') = 'object' and jsonb_typeof(x->'sea'->'refusal') = 'null')
      into v_rows, v_shut, v_open
      from (select x from jsonb_array_elements(v_new->'buy') x union all select x from jsonb_array_elements(v_new->'sell') x) r(x);
    if v_shut = 0 or v_open = 0 then
      raise exception '0222 self-assert FAIL: dark, % rows refused and % clear of % — both must be seen (the positive control)', v_shut, v_open, v_rows;
    end if;
    -- (c) the world's humans: the first three docked, two goods each, old = new
    for hu in select p.auth_uid, f.id as fleet
                from public.players p join public.fleets f on f.player_id = p.id and f.port_id is not null
               where not p.is_npc and p.auth_uid is not null and p.id <> v_player
               order by p.created_at, f.created_at limit 3 loop
      perform cmd.assume_identity(hu.auth_uid);
      for g in select x.id, x.code from (select gd.id, gd.code, row_number() over (order by gd.code) as rn, count(*) over () as n
                                           from public.goods gd) x
                where x.rn in ((x.n + 2) / 3, (2 * x.n) / 3) loop
        v_old := pg_temp.good_board_old_0222(g.id, hu.fleet, null, null);
        v_new := world.good_board(g.id, hu.fleet, null, null);
        if v_old::text <> v_new::text then
          raise exception '0222 self-assert FAIL: dark, a human''s % board differs from its pre-image', g.code;
        end if;
        v_humans := v_humans + 1;
      end loop;
    end loop;
    perform cmd.assume_identity(c_uid);

    -- (d) TIMING, dark, this session: the old board ×6, the new ×12 (the generic-plan cliff would show from call 6)
    for v_i in 1 .. 6 loop
      v_t0 := clock_timestamp();
      v_old := pg_temp.good_board_old_0222(v_good, v_fleet, null, null);
      v_gb_old := v_gb_old || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
    end loop;
    for v_i in 1 .. 12 loop
      v_t0 := clock_timestamp();
      v_new := world.good_board(v_good, v_fleet, null, null);
      v_gb_new := v_gb_new || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
    end loop;
    if (select avg(x) from unnest(v_gb_new[7:12]) x) > 2 * (select avg(x) from unnest(v_gb_new[1:6]) x) + 50 then
      raise exception '0222 self-assert FAIL: the new board cliffs — calls 7–12 average % ms, calls 1–6 % ms',
        round((select avg(x) from unnest(v_gb_new[7:12]) x)), round((select avg(x) from unnest(v_gb_new[1:6]) x));
    end if;
    if v_old::text <> v_new::text then
      raise exception '0222 self-assert FAIL: dark, the timed % board differs from its pre-image', v_gcode;
    end if;

    -- (e) LIT (inside the rollback): the control board old = new, Las Palmas still says why
    update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
    if not public.sea_conditions_on() then
      raise exception '0222 self-assert FAIL: the switch did not move';
    end if;
    v_old := pg_temp.good_board_old_0222(v_good, v_fleet, v_lis, null);
    v_new := world.good_board(v_good, v_fleet, v_lis, null);
    if v_old::text <> v_new::text then
      raise exception '0222 self-assert FAIL: lit, the % board differs from its pre-image', v_gcode;
    end if;
    select x into v_lp from jsonb_array_elements(v_new->'buy') x where x->>'port' = 'LPA';
    if v_lp is null or jsonb_typeof(v_lp->'miles') = 'number' or v_lp->'sea'->'refusal'->>'code' is distinct from 'E_SEA_CLOSED'
       or v_lp->'sea'->>'zone' <> 'NOR-MAC' then
      raise exception '0222 self-assert FAIL: lit, the Las Palmas buy row reads %', v_lp;
    end if;
    v_lit := 1;
    raise exception using errcode = 'ZX222', message = 'probe done';
  exception when sqlstate 'ZX222' then
    null;
  end;
  if exists (select 1 from public.players where auth_uid = c_uid or company_name = 'Casa 0222') then
    raise exception '0222 self-assert FAIL: the probe survived its rollback';
  end if;
  if public.sea_conditions_on() then
    raise exception '0222 self-assert FAIL: the switch is lit after the probe';
  end if;
  -- the walls: the readers and the derivation server-only; the board the client's; the registry as it was
  if has_function_privilege('authenticated', 'public.sea_routes(int, numeric, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.sea_routes(int, numeric, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.sea_leg_asks_derive(uuid)', 'execute')
     or has_function_privilege('anon', 'public.sea_leg_asks_derive(uuid)', 'execute')
     or has_table_privilege('authenticated', 'public.sea_leg_asks', 'select')
     or not has_function_privilege('authenticated', 'world.good_board(uuid, uuid, uuid, numeric)', 'execute')
     or has_function_privilege('anon', 'world.good_board(uuid, uuid, uuid, numeric)', 'execute') then
    raise exception '0222 self-assert FAIL: the walls do not hold';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0222)
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute')) then
    raise exception '0222 self-assert FAIL: the registry moved or a row is not executable';
  end if;
  raise notice '0222 self-assert ok: A LEG REMEMBERS ITS SEAS. sea_leg_asks.zones filled for % legs by the one derivation in % ms (no ask moved; every self row = harbour_zone; every leg touching Lisbon = course_zones); sea_routes re-cut by 1 hunk and reversed (ACL kept), samples nothing; good_board RESET plan_cache_mode (body, ACL kept; reach_passage keeps its own). Boards old = new byte for byte: probe % dark (% rows on the % board: % refused, % clear; Las Palmas E_SEA_CLOSED), humans %, lit %. TIMING good_board old % → new % ms (×6 / ×12; last 6 new: % ms; calls 1-6 new: % ms). % ms in all.',
    (select legs from before_0222), round(extract(epoch from (select t1 from t1_0222) - (select t0 from t0_0222)) * 1000),
    v_boards, v_rows, v_gcode, v_shut, v_open, v_humans, v_lit,
    round((select avg(x) from unnest(v_gb_old) x)), round((select avg(x) from unnest(v_gb_new) x)),
    round((select avg(x) from unnest(v_gb_new[7:12]) x)), round((select avg(x) from unnest(v_gb_new[1:6]) x)),
    round(extract(epoch from clock_timestamp() - (select t0 from t0_0222)) * 1000);
end $$;

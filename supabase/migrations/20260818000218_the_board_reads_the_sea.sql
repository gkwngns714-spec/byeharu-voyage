-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0218 — THE BOARD READS THE SEA  (docs/SEA_CONDITIONS_AND_REGIONS.md; docs/dev-log/2026-10-25-plan-tab.md "The
--        missing server read"; docs/dev-log/2026-10-25-sea-on-board.md — world.good_board's buy and sell rows say
--        what the seas on their route ask, judged by the one rule, served dark as a reading and lit as the reason)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, 2026-10-20 (docs/OWNER_REQUESTS.md row 183) ─────────────────────────────────────
--   "It should show restrictions – if whether my level, my class, my ship can go to that location."
--
-- ── WHAT SAYS THE OPPOSITE TODAY, NAMED ─────────────────────────────────────────────────────────
--   world.good_board (0171 … 0216) serves, per city, the passage she can sail and whether her reach and her stores
--   carry it — and NOTHING about the sea. Which zones a route crosses and what they ask live in public.sea_leg_asks
--   (0215) and no client read exposes them, so the Plan tab could print the player's own title and wave but no
--   per-city requirement (2026-10-25-plan-tab.md). Worse, once `sea_conditions_bite` is lit, 0216's
--   voyage.reach_passage shuts the sea-closed edges, and a city the SEA closes arrives as `sailable: false,
--   stops: null` — which the board's one wording (planLines.reachWords) reads as "too far to sail in one go". A
--   true refusal printed as the wrong reason.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   (1) public.sea_route_stops(from, stops, to) — a served row's route as harbour codes: where she sails from, the
--       row's stops, the city; a row with no passage (the board passes null stops: a row with no miles) is the
--       direct leg. Pure, immutable.
--   (2) public.sea_routes(title, wave, routes[]) — what each route's seas ask, in the routes' order:
--       { zone, zone_name, needs_title, needs_wave, refusal }. The legs are the consecutive harbour pairs (a harbour
--       to itself is no leg). needs_title / needs_wave = the most any leg asks in public.sea_leg_asks (0215, the one
--       derivation — the figures 0216's reach_passage compares). The route's ZONES = each harbour's own zone
--       (public.harbour_zone) and, for a leg that asks more than both its harbours' zones (an open-water crossing),
--       the zones public.course_zones finds on the straight line between the two roadsteads — the line
--       sea_leg_asks was derived from. The verdict is public.sea_refusal(title, wave, zones): THE ONE RULE, never a
--       comparison written here. Exact: the zone set holds a zone at each leg's maximum, so the rule refuses
--       exactly when a leg asks more than she holds. `zone` = the refusing zone, else the route's most demanding
--       zone (title, then wave, then requirement order). A route with no leg (the city she is at) has sea null.
--       Only the crossings are sampled: a coastal leg's ask is its harbours' own (the costly part is skipped
--       where it can add nothing).
--   (3) world.good_board (3 hunks): her title (public.title_level) and her fleet's wave (public.fleet_wave) read
--       once; every buy row's route from where she sails, every sell row's through the buy city when it must be
--       bought first (the buy row's route, then the sell row's stops from there), each asked of
--       public.sea_routes ONCE for the buy side and ONCE for the sell side; and the board's own `sea`:
--       { bite, title, wave }. Served EVEN WHILE `sea_conditions_bite` IS FALSE: the refusal is then a reading —
--       what the rule will answer when it is lit — and the client marks it "not in force yet". Lit, a row the sea
--       closes has no passage (0216) and its direct leg is judged: the refusal is set, the true reason.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
--   Change any figure the board served before (asserted: dark, the board minus `sea` equals its pre-image, row for
--   row). Change reach_passage, the gate, the door or any decision: this is a read. Light the switch. Touch the
--   merchant planner, sea_leg_asks or its derivation. Judge the lead leg of a fleet at anchor (from the open sea to
--   the nearest harbour): reach_passage does not judge it either.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
--   CREATE FUNCTION ×2, CREATE OR REPLACE ×1 (by hunks); no table is touched. good_board keeps plan_cache_mode =
--   force_custom_plan (0206; asserted). The probe company is made in a sub-transaction rolled back whole (the switch
--   is flipped inside it and rolled back with it). Timing: good_board old and new, six calls each in this session,
--   dark; six lit. raise notice only.
--
-- SUPERSEDES, by hunks sliced from the LIVE body (prod head 0216/0217, LF-normalised, each asserted to occur exactly
-- once and to reverse to its pre-image, ACL / volatility / definer / owner / config unchanged):
--   world.good_board(uuid, uuid, uuid, numeric) (3 hunks: the declarations, the sea pass before the return, the
--   board's `sea`), as last re-cut by 0216 (supabase/migrations/20260818000216_the_passage_gate_reads_the_sea.sql:206-213).
--
-- SELF-ASSERT (own probe rows only, rolled back): DARK — the board minus `sea` equals the pre-image's, 6 + 6 calls
-- timed; every row with a leg carries `sea`, its needs equal the most its legs ask in sea_leg_asks (recomputed here
-- independently), and its refusal is set exactly when she holds less than they ask (both kinds present: the
-- positive control); Las Palmas, bought from Lisbon by a title-1 barca, reads E_SEA_CLOSED; the board's `sea` is
-- { bite false, title 1, wave 12 }. LIT (inside the rollback) — Las Palmas has no passage and its row says why:
-- E_SEA_CLOSED at Macaronesia (title 2 asked, 1 held); every row that HAS a passage is clear (the board and 0216's
-- reach_passage agree); title 3 opens Las Palmas and its refusal goes. The walls hold.
-- ROLLBACK (forward migration): reverse the three hunks (each OLD text is here verbatim), drop public.sea_routes
-- and public.sea_route_stops.
-- VERSION: 0218 (renumber to the prod head + 1 at push; applies on 0216 or 0217).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0218(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table t0_0218 on commit drop as select clock_timestamp() as t0;

-- ── 1. THE PRE-IMAGE ───────────────────────────────────────────────────────────────────────────
create temp table defs_before_0218 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values ('world.good_board(uuid,uuid,uuid,numeric)')) f(fn);

create temp table before_0218 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

create temp table hunks_0218 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0218 values
('world.good_board(uuid,uuid,uuid,numeric)', 1,
$h$  v_passages jsonb;                 -- 0205: voyage.reach_passage(v_player, v_origin), asked once
begin
$h$,
$h$  v_passages jsonb;                 -- 0205: voyage.reach_passage(v_player, v_origin), asked once
  v_title   int;                    -- 0218: her title (public.title_level), read once
  v_wave    numeric;                -- 0218: her fleet's wave resistance (public.fleet_wave), read once
  v_ocode   text;                   -- 0218: the harbour her passages run from
  v_bpart   jsonb;                  -- 0218: the route to the buy city, when it must be bought first
begin
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 2,
$h$  return jsonb_build_object(
    'good', g.code,
$h$,
$h$  -- 0218: WHAT THE SEAS ON THE WAY ASK (docs/dev-log/2026-10-25-sea-on-board.md). Every row gains `sea` for the
  -- route it serves — where she sails from, its stops, the city (no passage: the direct leg); a sell row's route
  -- runs through the buy city when it must be bought first. public.sea_routes reads public.sea_leg_asks along the
  -- legs and judges them by public.sea_refusal, the one rule. Served dark too, as a reading; lit, a row the sea
  -- closes says so instead of arriving as "no passage" with no reason.
  v_title := public.title_level(v_player);
  v_wave  := public.fleet_wave(p_fleet);
  v_ocode := (select code from public.ports where id = v_origin);
  -- a row has a passage when it has miles (a buy row no passage reaches is served `stops: []`, 0188)
  select public.sea_route_stops(v_ocode, case when jsonb_typeof(e->'miles') = 'number' then e->'stops' end, e->>'port') into v_bpart
    from jsonb_array_elements(v_buy) e
   where v_basis <> 'on_board' and e->>'port' = v_src.code;
  select coalesce(jsonb_agg(b.e || jsonb_build_object('sea', s.sea) order by b.i), '[]'::jsonb) into v_buy
    from jsonb_array_elements(v_buy) with ordinality b(e, i)
    join jsonb_array_elements(public.sea_routes(v_title, v_wave,
           (select coalesce(jsonb_agg(public.sea_route_stops(v_ocode, case when jsonb_typeof(x.e->'miles') = 'number' then x.e->'stops' end,
                                                             x.e->>'port') order by x.i), '[]'::jsonb)
              from jsonb_array_elements(v_buy) with ordinality x(e, i)))) with ordinality s(sea, i) on s.i = b.i;
  select coalesce(jsonb_agg(b.e || jsonb_build_object('sea', s.sea) order by b.i), '[]'::jsonb) into v_sell
    from jsonb_array_elements(v_sell) with ordinality b(e, i)
    join jsonb_array_elements(public.sea_routes(v_title, v_wave,
           (select coalesce(jsonb_agg(coalesce(v_bpart, '[]'::jsonb)
                                      || public.sea_route_stops(case when v_bpart is null then v_ocode else v_src.code end,
                                                                -- from the buy city its stops are null when no passage reaches on
                                                                case when v_bpart is not null or jsonb_typeof(x.e->'miles') = 'number' then x.e->'stops' end,
                                                                x.e->>'port') order by x.i), '[]'::jsonb)
              from jsonb_array_elements(v_sell) with ordinality x(e, i)))) with ordinality s(sea, i) on s.i = b.i;

  return jsonb_build_object(
    'good', g.code,
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 3,
$h$    'supplies', jsonb_build_object('days', round(v_end, 1), 'margin', v_margin),   -- 0188: what `sailable` read
$h$,
$h$    'supplies', jsonb_build_object('days', round(v_end, 1), 'margin', v_margin),   -- 0188: what `sailable` read
    'sea', jsonb_build_object('bite', public.sea_conditions_on(), 'title', v_title, 'wave', v_wave),   -- 0218: what `sea` was judged for
$h$);

-- the pre-image under a pg_temp name, for the dark-identity proof and the timing
do $$
begin
  if (select count(*) from defs_before_0218 where def is not null) <> 1 then
    raise exception '0218 self-assert FAIL: world.good_board was not found';
  end if;
  if (select cfg from defs_before_0218) not like '%plan_cache_mode=force_custom_plan%' then
    raise exception '0218 self-assert FAIL: world.good_board has lost 0206''s plan_cache_mode (config %)', (select cfg from defs_before_0218);
  end if;
  execute replace((select def from defs_before_0218),
                  'CREATE OR REPLACE FUNCTION world.good_board(', 'CREATE OR REPLACE FUNCTION pg_temp.good_board_old_0218(');
end $$;

-- ── 2. THE ROUTE, AND WHAT ITS SEAS ASK ────────────────────────────────────────────────────────
create function public.sea_route_stops(p_from text, p_stops jsonb, p_to text)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $$
  -- 0218: A SERVED ROW'S ROUTE as harbour codes — where she sails from, the row's stops, the city. A row with no
  -- passage (its stops are not an array: null, as world.good_board serves a city no passage reaches) is the
  -- direct leg. A harbour repeated is no leg (public.sea_routes skips it).
  select case when jsonb_typeof(p_stops) = 'array' then jsonb_build_array(p_from) || p_stops || jsonb_build_array(p_to)
              else jsonb_build_array(p_from, p_to) end
$$;

create function public.sea_routes(p_title int, p_wave numeric, p_routes jsonb)
returns jsonb
language sql
stable security definer
set search_path = public, pg_temp
as $$
  -- 0218: WHAT EACH ROUTE'S SEAS ASK, in the routes' order: { zone, zone_name, needs_title, needs_wave, refusal },
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
$$;

comment on function public.sea_routes(int, numeric, jsonb) is
  '0218: what each route''s seas ask (needs from public.sea_leg_asks, the verdict from public.sea_refusal over the '
  'route''s zones). Read by world.good_board. Server-only.';

revoke all on function public.sea_route_stops(text, jsonb, text) from public, anon, authenticated;
revoke all on function public.sea_routes(int, numeric, jsonb) from public, anon, authenticated;

-- ── 3. THE NEW BODY ────────────────────────────────────────────────────────────────────────────
do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
begin
  select * into d from defs_before_0218;
  v_def := d.def;
  for h in select * from hunks_0218 order by n loop
    if pg_temp.occurs_0218(v_def, h.old) <> 1 then
      raise exception '0218 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
        d.fn, h.n, pg_temp.occurs_0218(v_def, h.old);
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
  v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
  for h in select * from hunks_0218 order by n desc loop
    if pg_temp.occurs_0218(v_rev, h.new) <> 1 then
      raise exception '0218 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
    end if;
    v_rev := replace(v_rev, h.new, h.old);
  end loop;
  if v_rev <> d.def then
    raise exception '0218 self-assert FAIL: % does not reverse to its pre-image', d.fn;
  end if;
  select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
         coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
    into p from pg_proc pr where pr.oid = d.fn::regprocedure;
  if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
    raise exception '0218 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config (% → %)', d.fn, d.acl, p.acl, d.cfg, p.cfg;
  end if;
end $$;

-- ── 4. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
-- the most a list of harbour codes' legs ask, recomputed here from public.sea_leg_asks without public.sea_routes
create or replace function pg_temp.route_asks_0218(p_codes text[])
returns table (title_min int, wave_min int, legs int)
language sql
stable
as $$
  select max(s.title_min), max(s.wave_min), count(*)::int
    from generate_subscripts(p_codes, 1) k
    join public.ports a on a.code = p_codes[k] and a.kind = 'HARBOUR'
    join public.ports b on b.code = p_codes[k + 1] and b.kind = 'HARBOUR'
    left join public.sea_leg_asks s on s.from_port = a.id and s.to_port = b.id
   where k < cardinality(p_codes) and p_codes[k] <> p_codes[k + 1]
$$;

do $$
declare
  c_uid    constant uuid := '00000000-0218-4000-8000-000000000001';
  v_player uuid;
  v_fleet  uuid;
  v_lis    uuid;
  v_lpa    uuid;
  v_good   uuid;
  v_gcode  text;
  v_title  int;
  v_wave   numeric;
  v_res    jsonb;
  v_old    jsonb;
  j_old    jsonb;
  j_new    jsonb;
  e        jsonb;
  v_lp     jsonb;
  v_codes  text[];
  v_bcodes text[];
  v_src    text;
  a        record;
  c        record;
  v_i      int;
  v_t0     timestamptz;
  v_gb_old numeric[] := '{}';
  v_gb_new numeric[] := '{}';
  v_gb_lit numeric[] := '{}';
  v_rows   int := 0;
  v_shut   int := 0;
  v_open   int := 0;
  v_bad    int := 0;
  v_badl   text := '';
  v_lit_open int := 0;
  v_lit_bad  int := 0;
begin
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_lpa from public.ports where code = 'LPA';
  if v_lis is null or v_lpa is null then
    raise exception '0218 self-assert FAIL: Lisbon or Las Palmas is missing';
  end if;
  if public.sea_conditions_on() then
    raise exception '0218 self-assert FAIL: sea_conditions_bite is already lit — this file was proven dark first';
  end if;
  -- the good: the first by code that Las Palmas sells (so a buy row lies past title 1, the positive control)
  select g.id, g.code into v_good, v_gcode
    from public.goods g join public.port_goods pg on pg.good_id = g.id and pg.port_id = v_lpa
   where public.port_offers(v_lpa, g.id)
   order by g.code limit 1;
  if v_good is null then
    raise exception '0218 self-assert FAIL: Las Palmas sells no good';
  end if;

  begin
    -- THE PROBE COMPANY: a barca at Lisbon, title 1, NAVIGATION 5 (so the reach is wide and the seas speak), stores
    v_player := public.new_house(c_uid, 'Casa 0218', 'PRT', 'LIS', 'Gaivota', 'barca', 'Gaivota 0218', 500000);
    select f.id into v_fleet from public.fleets f where f.player_id = v_player order by f.created_at limit 1;
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, 5 from public.skills sk where sk.code in ('NAVIGATION', 'SEAMANSHIP');
    update public.ships set water_t = 20, food_t = 20 where fleet_id = v_fleet;
    perform cmd.assume_identity(c_uid);
    if public.current_player_id() is distinct from v_player then
      raise exception '0218 self-assert FAIL: the probe is not the signed-in house';
    end if;
    v_title := public.title_level(v_player);
    v_wave  := public.fleet_wave(v_fleet);
    if v_title <> 1 or v_wave <> 12 then
      raise exception '0218 self-assert FAIL: the probe reads title % and wave %, not 1 and 12', v_title, v_wave;
    end if;

    -- ── DARK ─────────────────────────────────────────────────────────────────────────────────────
    -- (a) the board minus `sea` is the pre-image's, row for row; six calls each, timed in this session
    for v_i in 1 .. 6 loop
      v_t0 := clock_timestamp();
      v_old := pg_temp.good_board_old_0218(v_good, v_fleet, null, null);
      v_gb_old := v_gb_old || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
      v_t0 := clock_timestamp();
      v_res := world.good_board(v_good, v_fleet, null, null);
      v_gb_new := v_gb_new || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
      j_new := (v_res - 'sea')
               || jsonb_build_object('buy',  (select coalesce(jsonb_agg(x.e - 'sea' order by x.i), '[]'::jsonb) from jsonb_array_elements(v_res->'buy') with ordinality x(e, i)),
                                     'sell', (select coalesce(jsonb_agg(x.e - 'sea' order by x.i), '[]'::jsonb) from jsonb_array_elements(v_res->'sell') with ordinality x(e, i)));
      if v_old is distinct from j_new then
        raise exception '0218 self-assert FAIL: dark, the board minus `sea` differs from its pre-image (call %)', v_i;
      end if;
    end loop;
    if v_res->'sea' is distinct from jsonb_build_object('bite', false, 'title', 1, 'wave', 12) then
      raise exception '0218 self-assert FAIL: dark, the board''s sea reads %', v_res->'sea';
    end if;
    if jsonb_array_length(v_res->'buy') = 0 or jsonb_array_length(v_res->'sell') = 0 then
      raise exception '0218 self-assert FAIL: the % board has % buy and % sell rows', v_gcode, jsonb_array_length(v_res->'buy'), jsonb_array_length(v_res->'sell');
    end if;
    -- (b) every row: its needs are the most its legs ask (recomputed here), and its refusal is set exactly when she
    -- holds less than that. Buy rows from Lisbon; sell rows through the buy city when it is bought first.
    v_src := v_res->'qty'->>'bought_at';
    select case when jsonb_typeof(x->'stops') = 'array' and jsonb_typeof(x->'miles') = 'number' then array['LIS'] || array(select jsonb_array_elements_text(x->'stops')) || array[x->>'port']
                else array['LIS', x->>'port'] end
      into v_bcodes
      from jsonb_array_elements(v_res->'buy') x where x->>'port' = v_src;
    for c in select x.e, 'buy' as side from jsonb_array_elements(v_res->'buy') x(e)
             union all select x.e, 'sell' from jsonb_array_elements(v_res->'sell') x(e) loop
      e := c.e;
      v_codes := case when jsonb_typeof(e->'stops') = 'array' and (c.side = 'sell' and v_src is not null or jsonb_typeof(e->'miles') = 'number')
                      then array[case when c.side = 'sell' and v_src is not null then v_src else 'LIS' end]
                           || array(select jsonb_array_elements_text(e->'stops')) || array[e->>'port']
                      else array[case when c.side = 'sell' and v_src is not null then v_src else 'LIS' end, e->>'port'] end;
      if c.side = 'sell' and v_src is not null then
        v_codes := v_bcodes || v_codes;
      end if;
      select * into a from pg_temp.route_asks_0218(v_codes);
      if a.legs = 0 then
        if jsonb_typeof(e->'sea') <> 'null' then
          v_bad := v_bad + 1; v_badl := v_badl || format(' %s:%s has sea with no leg', c.side, e->>'port');
        end if;
        continue;
      end if;
      v_rows := v_rows + 1;
      if jsonb_typeof(e->'sea') is distinct from 'object'
         or (e->'sea'->>'needs_title')::int is distinct from a.title_min or (e->'sea'->>'needs_wave')::int is distinct from a.wave_min
         or e->'sea'->>'zone' is null or e->'sea'->>'zone_name' is null then
        v_bad := v_bad + 1; v_badl := v_badl || format(' %s:%s needs %s/%s read %s', c.side, e->>'port', a.title_min, a.wave_min, e->'sea');
      elsif (a.title_min > v_title or a.wave_min > v_wave) <> (jsonb_typeof(e->'sea'->'refusal') = 'object') then
        v_bad := v_bad + 1; v_badl := v_badl || format(' %s:%s refusal %s for %s/%s', c.side, e->>'port', e->'sea'->'refusal', a.title_min, a.wave_min);
      elsif jsonb_typeof(e->'sea'->'refusal') = 'object' then
        v_shut := v_shut + 1;
        if e->'sea'->'refusal'->>'code' <> 'E_SEA_CLOSED' or e->'sea'->>'zone' <> e->'sea'->'refusal'->'figures'->>'zone' then
          v_bad := v_bad + 1; v_badl := v_badl || format(' %s:%s refusal %s', c.side, e->>'port', e->'sea'->'refusal');
        end if;
      else
        v_open := v_open + 1;
      end if;
      exit when length(v_badl) > 600;
    end loop;
    if v_bad <> 0 then
      raise exception '0218 self-assert FAIL: dark, % of % rows read the seas wrong:%', v_bad, v_rows, v_badl;
    end if;
    if v_shut = 0 or v_open = 0 then
      raise exception '0218 self-assert FAIL: dark, % rows refused and % clear — both must be seen (the positive control)', v_shut, v_open;
    end if;
    -- (c) Las Palmas, bought from Lisbon: the seas ask title 2 at least, and the rule refuses (a reading, dark)
    select x into v_lp from jsonb_array_elements(v_res->'buy') x where x->>'port' = 'LPA';
    if v_lp is null or (v_lp->'sea'->>'needs_title')::int < 2 or v_lp->'sea'->'refusal'->>'code' is distinct from 'E_SEA_CLOSED'
       or (v_lp->'sea'->'refusal'->'figures'->>'title')::int <> 1 then
      raise exception '0218 self-assert FAIL: dark, the Las Palmas buy row reads %', v_lp;
    end if;

    -- ── LIT (inside the rollback) ─────────────────────────────────────────────────────────────────
    update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
    if not public.sea_conditions_on() then
      raise exception '0218 self-assert FAIL: the switch did not move';
    end if;
    for v_i in 1 .. 6 loop
      v_t0 := clock_timestamp();
      v_res := world.good_board(v_good, v_fleet, null, null);
      v_gb_lit := v_gb_lit || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
    end loop;
    if (v_res->'sea'->>'bite')::boolean is distinct from true then
      raise exception '0218 self-assert FAIL: lit, the board''s sea reads %', v_res->'sea';
    end if;
    -- (d) Las Palmas has no passage, and its row says why: Macaronesia, title 2 asked, 1 held
    select x into v_lp from jsonb_array_elements(v_res->'buy') x where x->>'port' = 'LPA';
    if v_lp is null or jsonb_typeof(v_lp->'miles') = 'number' or (v_lp->>'sailable')::boolean
       or v_lp->'sea'->'refusal'->>'code' is distinct from 'E_SEA_CLOSED' or v_lp->'sea'->>'zone' <> 'NOR-MAC'
       or (v_lp->'sea'->'refusal'->'figures'->>'needs_title')::int <> 2 or (v_lp->'sea'->'refusal'->'figures'->>'title')::int <> 1
       or (v_lp->'sea'->>'needs_title')::int <> 2 then
      raise exception '0218 self-assert FAIL: lit, the Las Palmas buy row reads %', v_lp;
    end if;
    -- (e) every buy row that HAS a passage is clear: the board's verdict and 0216's reach_passage agree
    for e in select x from jsonb_array_elements(v_res->'buy') x
              where jsonb_typeof(x->'miles') = 'number' and jsonb_typeof(x->'sea') = 'object' loop
      v_lit_open := v_lit_open + 1;
      if jsonb_typeof(e->'sea'->'refusal') = 'object' then
        v_lit_bad := v_lit_bad + 1;
      end if;
    end loop;
    if v_lit_open = 0 or v_lit_bad <> 0 then
      raise exception '0218 self-assert FAIL: lit, % of % buy rows with a passage are refused by the sea', v_lit_bad, v_lit_open;
    end if;
    -- (f) TITLE 3 (probe record: 10,000 d. of turnover, four harbours called, as 0216's): Las Palmas opens
    for v_i in 1 .. 2 loop
      perform public.credit(v_player, 'SELL', 5000, public.emit_event(v_player, 'SOLD', '{"probe": "0218"}'::jsonb));
    end loop;
    for c in select p.code from public.ports p where p.kind = 'HARBOUR' and p.code in ('FNC', 'OPO', 'CAD', 'SAF') order by p.code loop
      perform public.emit_event(v_player, 'VOYAGE_REPORT', jsonb_build_object('to', c.code, 'total_nm', 100, 'probe', '0218'));
    end loop;
    if public.title_level(v_player) <> 3 then
      raise exception '0218 self-assert FAIL: 10,000 d. and four harbours make title %, not 3', public.title_level(v_player);
    end if;
    v_res := world.good_board(v_good, v_fleet, null, null);
    select x into v_lp from jsonb_array_elements(v_res->'buy') x where x->>'port' = 'LPA';
    if v_lp is null or jsonb_typeof(v_lp->'miles') <> 'number' or jsonb_typeof(v_lp->'sea'->'refusal') <> 'null'
       or (v_res->'sea'->>'title')::int <> 3 then
      raise exception '0218 self-assert FAIL: lit at title 3, the Las Palmas buy row reads % (board sea %)', v_lp, v_res->'sea';
    end if;
    raise exception using errcode = 'ZX218', message = 'probe done';
  exception when sqlstate 'ZX218' then
    null;
  end;
  if exists (select 1 from public.players where auth_uid = c_uid or company_name = 'Casa 0218') then
    raise exception '0218 self-assert FAIL: the probe survived its rollback';
  end if;
  if public.sea_conditions_on() then
    raise exception '0218 self-assert FAIL: the switch is lit after the probe';
  end if;
  -- the walls: the two new readers are server-only; the board is still the client's; the registry is as it was
  if has_function_privilege('authenticated', 'public.sea_routes(int, numeric, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.sea_routes(int, numeric, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.sea_route_stops(text, jsonb, text)', 'execute')
     or has_function_privilege('anon', 'public.sea_route_stops(text, jsonb, text)', 'execute')
     or not has_function_privilege('authenticated', 'world.good_board(uuid, uuid, uuid, numeric)', 'execute')
     or has_function_privilege('anon', 'world.good_board(uuid, uuid, uuid, numeric)', 'execute') then
    raise exception '0218 self-assert FAIL: the walls do not hold';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0218)
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute')) then
    raise exception '0218 self-assert FAIL: the registry moved or a row is not executable';
  end if;
  raise notice '0218 self-assert ok: THE BOARD READS THE SEA (dark). world.good_board re-cut by 3 hunks and reversed (ACL, plan_cache_mode kept). DARK (good %): the board minus `sea` equals its pre-image 6 × 6; % rows with a leg read their needs from sea_leg_asks, % refused and % clear, exactly as the figures say; Las Palmas from Lisbon reads E_SEA_CLOSED at title 1. LIT (rolled back): Las Palmas has no passage and says why (Macaronesia, title 2 asked, 1 held); % buy rows with a passage, every one clear; title 3 opens it. TIMING good_board dark old % → new % ms (last 3: % → %), lit % ms. % ms in all.',
    v_gcode, v_rows, v_shut, v_open, v_lit_open,
    round((select avg(x) from unnest(v_gb_old) x)), round((select avg(x) from unnest(v_gb_new) x)),
    round((select avg(x) from unnest(v_gb_old[4:6]) x)), round((select avg(x) from unnest(v_gb_new[4:6]) x)),
    round((select avg(x) from unnest(v_gb_lit) x)),
    round(extract(epoch from clock_timestamp() - (select t0 from t0_0218)) * 1000);
end $$;

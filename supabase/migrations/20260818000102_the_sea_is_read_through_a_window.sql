-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0102 — THE SEA IS READ THROUGH A WINDOW
--        docs/NPC_FLEET_SCALE.md slice B. Owner row 118 (the roster this read has to survive).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY THIS COMES BEFORE THE SHIPS ─────────────────────────────────────────────────────────────
-- `world.sea_traffic` (0099) serves EVERY merchant fleet in the world on EVERY beat of the shell's
-- clock, to every player with the map open. That was written for a roster measured at 76 fleets.
-- The owner has asked for ten times as many (row 118), and ten times as many is a read nobody
-- should be asked to pay for in order to look at one sea.
--
-- So the read takes a WINDOW and a CAP, and says how many it did not send. Nothing else about it
-- moves: handed no window it answers exactly what it answered before, fleet for fleet, in the same
-- order, byte for byte — which is asserted below against its own pre-image, cloned into pg_temp one
-- statement before it is dropped.
--
-- ── WHAT "IN THE WINDOW" MEANS, AND WHY IT IS GENEROUS ──────────────────────────────────────────
-- A merchant is not a point. She is a hull the chart DRIFTS along the current segment of her
-- voyage between reads (src/chart/liveWorld.ts), so what has to be inside the window is her TRACK,
-- not a position. Her points are therefore:
--
--   at sea   — the two ends of her current segment AND its midpoint (the midpoint by the same
--              short-way longitude lerp the sea itself uses, 0088's voyage.lon_lerp, so a segment
--              across the antimeridian has its midpoint on the water and not on the far side)
--   in port  — her berth's served roadstead point, or her anchor if the harbour has no reach row
--
-- If ANY of those points falls in the window she is served. The window is PADDED by
-- `sea_traffic_pad_deg` (10°) before the test, which buys two things at once: a hull a few hundred
-- miles outside the view is already drawn when she sails in, and a leg long enough to cross the
-- view with both ends outside it is still caught — because a leg that clears a padded window at
-- three sampled points is a leg longer than the view is wide, and at that zoom the window IS the
-- world. The pad is in degrees, not nautical miles, so it is worth 600 nm of latitude and less
-- than that of longitude away from the equator; there is no trade at the poles and no pretence
-- here of precision there.
--
-- Longitude is tested through `public.lon_in_view`, which normalises both edges, so a padded window
-- may be handed -185 or 190, and a window that straddles the antimeridian (west 170, east -170) is
-- a window and not an empty set. 0088 made the sea round; a viewport has to be round with it.
--
-- ── THE CAP, AND WHY `omitted` IS SERVED ────────────────────────────────────────────────────────
-- `sea_traffic_max` (240) is the most rows one read may carry, window or no window. Inside a window
-- the nearest to its centre are kept, so what the cap drops is what is furthest from where the
-- player is looking. `total` is every merchant fleet in the world and `omitted` is total minus
-- served, so one number covers both the window and the cap, and the read never quietly shows less
-- than there is. A read that silently truncates is a read that teaches the player the sea is empty.
--
-- ── THE SIGNATURE CHANGED, SO THE REGISTRY DID ──────────────────────────────────────────────────
-- `world.sea_traffic()` is DROPPED and `world.sea_traffic(jsonb default null)` takes its place: two
-- overloads, one of them with a default, is an ambiguous call, and an ambiguous call is a runtime
-- 42725 for every caller that ever said `sea_traffic()`. Everything that says `sea_traffic()` still
-- resolves to the default, so no caller has to change to keep working; `client_rpc_entry_points`
-- names the argument type exactly and is re-cut here for it.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

insert into public.world_config (key, value, description) values
  ('sea_traffic_max', to_jsonb(240),
   '0102: the most merchant fleet rows world.sea_traffic may serve in one read, window or no '
   'window. Inside a window the nearest to its centre are kept. The read always serves `total` '
   'and `omitted`, so a cap is never a silent truncation.'),
  ('sea_traffic_pad_deg', to_jsonb(10),
   '0102: degrees of slack added to every edge of a sea_traffic window before a merchant is tested '
   'against it. Buys a hull that is about to sail into view, and catches a leg that crosses the '
   'view with both ends outside it. Degrees, so ~600 nm of latitude and less of longitude away '
   'from the equator.');

-- ── 1. A LONGITUDE WINDOW ON A ROUND SEA ───────────────────────────────────────────────────────
create or replace function public.lon_in_view(p_lon double precision,
                                              p_west double precision,
                                              p_east double precision)
returns boolean
language sql
immutable
parallel safe
as $$
  -- 0102: is a longitude inside a window that may straddle the antimeridian, and whose edges may
  -- have been pushed past ±180 by the pad? Both are reduced to an offset east of the west edge in
  -- [0, 360) by plain arithmetic (there is no mod() for double precision), and the point is in the
  -- window when its own offset does not exceed the window's width. A window 360° wide or wider is
  -- the whole world. 0088: the sea is round.
  select case
    when p_lon is null or p_west is null or p_east is null then false
    when abs(p_east - p_west) >= 360 then true
    else ((p_lon  - p_west) - 360 * floor((p_lon  - p_west) / 360))
      <= ((p_east - p_west) - 360 * floor((p_east - p_west) / 360))
  end
$$;

comment on function public.lon_in_view(double precision, double precision, double precision) is
  '0102: longitude membership of a window that may wrap the antimeridian and whose edges may lie '
  'outside ±180. Server-only; world.sea_traffic is its one caller.';

-- ── 2. THE PRE-IMAGE, CLONED BEFORE IT IS DROPPED ──────────────────────────────────────────────
-- The whole parity claim of this file rests on this clone: handed no window the new read must
-- answer what the old one answered, and the only way to say so without believing it is to keep the
-- old one alive in pg_temp and ask them both.
do $$
declare
  v_def text;
begin
  v_def := replace(pg_get_functiondef('world.sea_traffic()'::regprocedure), E'\r', '');
  if strpos(v_def, 'CREATE OR REPLACE FUNCTION world.sea_traffic()') <> 1 then
    raise exception '0102: world.sea_traffic() is not where this migration expects it';
  end if;
  execute replace(v_def, 'CREATE OR REPLACE FUNCTION world.sea_traffic()',
                         'CREATE OR REPLACE FUNCTION pg_temp.traffic_before_0102()');
end $$;

drop function world.sea_traffic();

-- ── 3. THE READ ────────────────────────────────────────────────────────────────────────────────
create or replace function world.sea_traffic(p_view jsonb default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0102: WHERE THE MERCHANT FLEETS ARE, THROUGH A WINDOW (docs/NPC_FLEET_SCALE.md slice B). The row
-- itself is 0099's, unchanged — the one predicate is still players.is_npc and a player's fleet is
-- still never a row. p_view null is the whole world and answers 0099 exactly.
declare
  v_s      double precision;
  v_n      double precision;
  v_w      double precision;
  v_e      double precision;
  v_wide   double precision;
  v_pad    double precision;
  v_clat   double precision;
  v_clon   double precision;
  v_max    int;
  v_total  int;
  v_rows   jsonb;
begin
  if not public.npc_traders_on() then
    return jsonb_build_object('enabled', false, 'at', now(), 'fleets', '[]'::jsonb,
                              'total', 0, 'omitted', 0);
  end if;

  if p_view is not null then
    if jsonb_typeof(p_view) <> 'object'
       or (select count(*) from jsonb_object_keys(p_view)) <> 4
       or (select count(*) from jsonb_object_keys(p_view) k
            where k in ('south', 'north', 'west', 'east')) <> 4
       or exists (select 1 from jsonb_each(p_view) e where jsonb_typeof(e.value) <> 'number') then
      raise exception 'E_BAD_VIEW: a sea view is {south, north, west, east} in degrees'
        using errcode = 'P0001';
    end if;
    v_s := (p_view->>'south')::double precision;
    v_n := (p_view->>'north')::double precision;
    v_w := (p_view->>'west')::double precision;
    v_e := (p_view->>'east')::double precision;
    if v_s < -90 or v_n > 90 or v_s >= v_n
       or v_w < -180 or v_w > 180 or v_e < -180 or v_e > 180 then
      raise exception 'E_BAD_VIEW: south < north, both within ±90, west and east within ±180'
        using errcode = 'P0001';
    end if;
    v_pad  := public.wc_num('sea_traffic_pad_deg')::double precision;
    v_wide := (v_e - v_w) - 360 * floor((v_e - v_w) / 360);
    if v_wide = 0 and v_e <> v_w then v_wide := 360; end if;
    v_clat := (v_s + v_n) / 2;
    v_clon := v_w + v_wide / 2;
    v_clon := v_clon - 360 * floor((v_clon + 180) / 360);
  end if;
  v_max := greatest(1, public.wc_int('sea_traffic_max'));

  with m as (
    select f.id as fleet_id, f.name, f.status, f.port_id, f.lat, f.lon,
           p.company_name, nn.code as nation_code, h.ink, po.code as port_code,
           rs.roadstead_lat, rs.roadstead_lon, nf.roster_ord, sr.hold_until,
           (select count(*) from public.ships s where s.fleet_id = f.id) as ships,
           (select world.voyage_view(v.id, false) from public.voyages v
             where v.fleet_id = f.id and v.status = 'SAILING') as vv
      from public.fleets f
      join public.players p on p.id = f.player_id and p.is_npc
      join public.npc_houses h on h.player_id = p.id
      left join public.npc_fleets nf on nf.fleet_id = f.id
      left join public.standing_routes sr on sr.id = nf.route_id
      left join public.nations nn on nn.id = p.nation_id
      left join public.ports po on po.id = f.port_id
      left join public.sea_reaches rs on rs.port_id = f.port_id
  ), pts as (
    -- HER TRACK, SAMPLED. At sea: both ends of the current segment and its short-way midpoint. In
    -- port: the roadstead the chart draws her at, or her anchor if the harbour has no reach row.
    select m.fleet_id, q.lat, q.lon
      from m
      cross join lateral (
        select (m.vv->'course'->0->>0)::double precision as lat,
               (m.vv->'course'->0->>1)::double precision as lon
         where m.vv is not null
        union all
        select (m.vv->'course'->1->>0)::double precision,
               (m.vv->'course'->1->>1)::double precision
         where m.vv is not null
        union all
        select ((m.vv->'course'->0->>0)::double precision
              + (m.vv->'course'->1->>0)::double precision) / 2,
               voyage.lon_lerp((m.vv->'course'->0->>1)::double precision,
                               (m.vv->'course'->1->>1)::double precision, 0.5)
         where m.vv is not null
        union all
        select m.roadstead_lat, m.roadstead_lon
         where m.vv is null and m.roadstead_lat is not null
        union all
        select m.lat, m.lon
         where m.vv is null and m.roadstead_lat is null and m.lat is not null
      ) q
     where q.lat is not null and q.lon is not null
  ), near as (
    select pts.fleet_id,
           min(voyage.gc_distance_nm(v_clat, v_clon, pts.lat, pts.lon)) as nm,
           bool_or(pts.lat between v_s - v_pad and v_n + v_pad
                   and public.lon_in_view(pts.lon, v_w - v_pad, v_e + v_pad)) as seen
      from pts
     group by pts.fleet_id
  ), pick as (
    select m.*, case when p_view is null then 0::double precision else near.nm end as ord_nm
      from m
      left join near on near.fleet_id = m.fleet_id
     where p_view is null or coalesce(near.seen, false)
     order by case when p_view is null then 0::double precision else near.nm end,
              m.roster_ord, m.fleet_id
     limit v_max
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', pick.fleet_id, 'company', pick.company_name,
           'nation_code', pick.nation_code, 'ink', pick.ink,
           'name', pick.name, 'status', pick.status,
           'ships', pick.ships,
           'port', pick.port_code,
           'roadstead', case when pick.port_id is not null
                             then jsonb_build_array(pick.roadstead_lat, pick.roadstead_lon) end,
           'anchor', case when pick.lat is not null
                          then jsonb_build_array(pick.lat, pick.lon) end,
           'voyage', pick.vv,
           'next_lap_at', case when pick.hold_until > now() then pick.hold_until end)
         order by pick.ord_nm, pick.roster_ord, pick.fleet_id), '[]'::jsonb)
    into v_rows from pick;

  select count(*) into v_total
    from public.fleets f join public.players p on p.id = f.player_id and p.is_npc;

  return jsonb_build_object('enabled', true, 'at', now(), 'fleets', v_rows,
                            'total', v_total,
                            'omitted', v_total - jsonb_array_length(v_rows));
end $$;

comment on function world.sea_traffic(jsonb) is
  '0102: where every merchant fleet in a WINDOW is right now, capped at sea_traffic_max and '
  'nearest-to-centre first, with `total` and `omitted` so a cap is never silent. Handed no window '
  'it is 0099 exactly. The window is {south, north, west, east} in degrees, padded by '
  'sea_traffic_pad_deg, wrapping the antimeridian; a malformed one is E_BAD_VIEW.';

-- ── 4. THE REGISTRY ────────────────────────────────────────────────────────────────────────────
create temporary table hunks_0102 (fn text not null, n int not null, old text not null, new text not null);
create temporary table defs_before_0102 (fn text primary key, def text not null, acl text not null);

insert into defs_before_0102
select x.fn, replace(pg_get_functiondef(x.fn::regprocedure), E'\r', ''),
       coalesce((select p.proacl::text from pg_proc p where p.oid = x.fn::regprocedure), '')
  from (values ('public.client_rpc_entry_points()')) x(fn);

insert into hunks_0102 values
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'sea_traffic',           ''),$h$,
$h$      -- 0102: the read takes a viewport. Two overloads with a default is an ambiguous call, so
      -- the 0-arg form is GONE and every `sea_traffic()` resolves to this one's default.
      ('world',       'sea_traffic',           'jsonb'),$h$);

create or replace function pg_temp.recut_0102(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0102 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0102 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0102: hunk % of % matches the pre-image % time(s), not once', h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0102('public.client_rpc_entry_points()');

-- ── 5. GRANTS ──────────────────────────────────────────────────────────────────────────────────
revoke all on function public.lon_in_view(double precision, double precision, double precision)
  from public, anon, authenticated;
revoke all on function world.sea_traffic(jsonb) from public, anon;
grant execute on function world.sea_traffic(jsonb) to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.okeys_0102(p jsonb)
returns text[]
language sql
immutable
as $$
  select coalesce(array_agg(k order by k collate "C"), '{}') from jsonb_object_keys(p) k
$$;

-- THE POINT RULE, RE-STATED. Not the read's own body and not its output: the same rule written a
-- second time, straight off the tables, so the window assertions below are a re-derivation and not
-- a tautology. Her segment's two ends and its short-way midpoint at sea; her roadstead, or her
-- anchor if the harbour has no reach row, in port.
create or replace function pg_temp.pts_0102(p_fleet uuid)
returns table (plat double precision, plon double precision)
language sql
stable
as $$
  with f as (
    select x.id, x.lat, x.lon, rs.roadstead_lat as rlat, rs.roadstead_lon as rlon,
           (select world.voyage_view(v.id, false) from public.voyages v
             where v.fleet_id = x.id and v.status = 'SAILING') as vv
      from public.fleets x
      left join public.sea_reaches rs on rs.port_id = x.port_id
     where x.id = p_fleet)
  select (f.vv->'course'->0->>0)::double precision,
         (f.vv->'course'->0->>1)::double precision from f where f.vv is not null
  union all
  select (f.vv->'course'->1->>0)::double precision,
         (f.vv->'course'->1->>1)::double precision from f where f.vv is not null
  union all
  select ((f.vv->'course'->0->>0)::double precision
        + (f.vv->'course'->1->>0)::double precision) / 2,
         voyage.lon_lerp((f.vv->'course'->0->>1)::double precision,
                         (f.vv->'course'->1->>1)::double precision, 0.5) from f where f.vv is not null
  union all
  select f.rlat, f.rlon from f where f.vv is null and f.rlat is not null
  union all
  select f.lat, f.lon from f where f.vv is null and f.rlat is null and f.lat is not null
$$;

do $$
declare
  v_fn      text;
  v_def     text;
  v_back    text;
  h         record;
  v_n       int;
  v_before  jsonb;
  v_after   jsonb;
  v_whole   jsonb;
  v_win     jsonb;
  v_seam    jsonb;
  v_cap     jsonb;
  v_dark    jsonb;
  v_keys    text[];
  v_err     text;
  v_total   int;
  v_lis_la  double precision;
  v_lis_lo  double precision;
  v_pad     double precision;
  v_mine    int;
  v_far     int;
  v_seen    int;
  v_near    uuid[];
  v_got     uuid[];
  v_base    int;
  v_pac     uuid;
  v_seamf   uuid;
  v_ms      numeric;
  v_t0      timestamptz;
begin
  -- (a) THE REGISTRY IS ITS PRE-IMAGE PLUS ONLY THIS FILE'S HUNK, ACL UNMOVED.
  for v_fn in select distinct fn from hunks_0102 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0102 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0102 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0102 where fn = v_fn) or v_def = v_back then
      raise exception '0102 self-assert FAIL: % is not its pre-image plus only 0102''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0102 where fn = v_fn) then
      raise exception '0102 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) THE OLD SIGNATURE IS GONE, THE NEW ONE IS REGISTERED AND AUTHENTICATED-ONLY.
  if to_regprocedure('world.sea_traffic()') is not null then
    raise exception '0102 self-assert FAIL: the 0-arg sea_traffic survived — every sea_traffic() call is now ambiguous';
  end if;
  if not has_function_privilege('authenticated', 'world.sea_traffic(jsonb)', 'execute')
     or has_function_privilege('anon', 'world.sea_traffic(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.lon_in_view(double precision, double precision, double precision)', 'execute') then
    raise exception '0102 self-assert FAIL: the read is not exactly authenticated-only, or the helper is reachable';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where e.function_name = 'sea_traffic' and e.arg_types = 'jsonb' and e.fn is not null) <> 1
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0102 self-assert FAIL: the registry, the grant wall or the read wall';
  end if;

  -- (c) THE WINDOW ARITHMETIC, independently of the read.
  if not public.lon_in_view(179, 170, -170) or not public.lon_in_view(-179, 170, -170)
     or public.lon_in_view(0, 170, -170) or public.lon_in_view(160, 170, -170)
     or not public.lon_in_view(-175, 175, 185)          -- an edge pushed past 180 by the pad
     or not public.lon_in_view(123.4, -180, 180)        -- the whole world
     or public.lon_in_view(null, 0, 10) then
    raise exception '0102 self-assert FAIL: lon_in_view does not know the sea is round';
  end if;

  -- (d) DARK: the switch off, with the new keys and nothing in them.
  v_dark := world.sea_traffic();
  if (v_dark->>'enabled')::boolean or jsonb_array_length(v_dark->'fleets') <> 0
     or (v_dark->>'total')::int <> 0 or (v_dark->>'omitted')::int <> 0 then
    raise exception '0102 self-assert FAIL: sea_traffic served something while dark: %', left(v_dark::text, 300);
  end if;

  -- (e) THE READ ITSELF, on the real roster, switched on and rolled back.
  select count(*) into v_base from public.players;
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    perform public.npc_traders_switch(true);
    select count(*) into v_total
      from public.fleets f join public.players p on p.id = f.player_id and p.is_npc;
    if v_total < 20 or v_total > public.wc_int('sea_traffic_max') then
      raise exception '0102 self-assert FAIL: the roster is % fleet(s) — the parity reading needs it between 20 and the cap (%)',
        v_total, public.wc_int('sea_traffic_max');
    end if;

    -- (e1) PARITY: handed no window, fleet for fleet, in the same order, byte for byte.
    v_before := pg_temp.traffic_before_0102();
    v_after  := world.sea_traffic();
    if v_after->'fleets' is distinct from v_before->'fleets'
       or (v_after->>'enabled')::boolean is not true
       or jsonb_array_length(v_after->'fleets') <> v_total
       or (v_after->>'total')::int <> v_total or (v_after->>'omitted')::int <> 0 then
      raise exception '0102 self-assert FAIL: the whole world is not what it was — % row(s) vs %, omitted %',
        jsonb_array_length(v_after->'fleets'), jsonb_array_length(v_before->'fleets'), v_after->>'omitted';
    end if;
    if (select count(*) from jsonb_array_elements(v_after->'fleets') x where x->'voyage' is not null) < 1 then
      raise exception '0102 self-assert FAIL: no merchant is at sea, so the segment sampling is untested';
    end if;
    v_whole := v_after;
    v_keys := pg_temp.okeys_0102(v_whole);
    if v_keys <> array['at', 'enabled', 'fleets', 'omitted', 'total'] then
      raise exception '0102 self-assert FAIL: sea_traffic top-level keys %', v_keys;
    end if;
    v_keys := pg_temp.okeys_0102(v_whole->'fleets'->0);
    if v_keys <> array['anchor', 'company', 'id', 'ink', 'name', 'nation_code', 'next_lap_at',
                       'port', 'roadstead', 'ships', 'status', 'voyage'] then
      raise exception '0102 self-assert FAIL: a merchant row''s keys %', v_keys;
    end if;

    -- (e2) A WINDOW ON IBERIA serves fewer, serves only merchants a re-derivation of the predicate
    --      agrees are in the padded window, and leaves the rest OUT.
    select rs.roadstead_lat, rs.roadstead_lon into v_lis_la, v_lis_lo
      from public.sea_reaches rs join public.ports po on po.id = rs.port_id where po.code = 'LIS';
    v_pad := public.wc_num('sea_traffic_pad_deg')::double precision;
    v_win := world.sea_traffic(jsonb_build_object(
      'south', round(v_lis_la::numeric - 4, 4), 'north', round(v_lis_la::numeric + 4, 4),
      'west',  round(v_lis_lo::numeric - 4, 4), 'east',  round(v_lis_lo::numeric + 4, 4)));
    v_mine := jsonb_array_length(v_win->'fleets');
    if v_mine < 1 or v_mine >= v_total then
      raise exception '0102 self-assert FAIL: a window on Lisbon served % of % merchant(s) — it is not a window',
        v_mine, v_total;
    end if;
    if (v_win->>'total')::int <> v_total or (v_win->>'omitted')::int <> v_total - v_mine then
      raise exception '0102 self-assert FAIL: the window did not own up to what it left out (total %, omitted %, served %)',
        v_win->>'total', v_win->>'omitted', v_mine;
    end if;
    -- every served fleet has a point in the padded window, re-derived here from the tables
    if exists (
      select 1 from jsonb_array_elements(v_win->'fleets') x
       where not exists (
         select 1 from pg_temp.pts_0102((x->>'id')::uuid) q
          where q.plat between v_lis_la - 4 - v_pad and v_lis_la + 4 + v_pad
            and public.lon_in_view(q.plon, v_lis_lo - 4 - v_pad, v_lis_lo + 4 + v_pad))) then
      raise exception '0102 self-assert FAIL: the window served a merchant with no point anywhere near it';
    end if;
    -- AND IT LEFT OUT NOBODY IT SHOULD HAVE SERVED: the same rule run over every merchant in the
    -- world names exactly the set the read named (the cap is 240 and the roster is under it here,
    -- so the window is the only thing choosing).
    if exists (
      select 1 from public.fleets f join public.players p on p.id = f.player_id and p.is_npc
       where exists (select 1 from pg_temp.pts_0102(f.id) q
                      where q.plat between v_lis_la - 4 - v_pad and v_lis_la + 4 + v_pad
                        and public.lon_in_view(q.plon, v_lis_lo - 4 - v_pad, v_lis_lo + 4 + v_pad))
         and not exists (select 1 from jsonb_array_elements(v_win->'fleets') x
                          where (x->>'id')::uuid = f.id)) then
      raise exception '0102 self-assert FAIL: a merchant inside the padded window was not served';
    end if;
    -- POSITIVE CONTROL: a merchant berthed a hemisphere away is NOT in a window on Lisbon.
    select f.id into v_pac
      from public.fleets f
      join public.players p on p.id = f.player_id and p.is_npc
      join public.sea_reaches rs on rs.port_id = f.port_id
     where f.status = 'DOCKED' and abs(rs.roadstead_lon - v_lis_lo) > 90
     limit 1;
    if v_pac is not null and exists (select 1 from jsonb_array_elements(v_win->'fleets') x
                                      where (x->>'id')::uuid = v_pac) then
      raise exception '0102 self-assert FAIL: a merchant a hemisphere away was served for a Lisbon window';
    end if;
    select count(*) into v_far from jsonb_array_elements(v_whole->'fleets') w
     where not exists (select 1 from jsonb_array_elements(v_win->'fleets') x where x->>'id' = w->>'id');
    if v_far < 1 then
      raise exception '0102 self-assert FAIL: the window left nobody out, so it proves nothing';
    end if;

    -- (e3) THE CAP BITES, and keeps the nearest to the window's centre.
    update public.world_config set value = to_jsonb(3) where key = 'sea_traffic_max';
    v_cap := world.sea_traffic(jsonb_build_object(
      'south', round(greatest(-89, v_lis_la::numeric - 40), 4), 'north', round(least(89, v_lis_la::numeric + 40), 4),
      'west',  round(greatest(-179, v_lis_lo::numeric - 40), 4), 'east',  round(least(179, v_lis_lo::numeric + 40), 4)));
    v_seen := jsonb_array_length(v_cap->'fleets');
    if v_seen <> 3 or (v_cap->>'omitted')::int <> v_total - 3 then
      raise exception '0102 self-assert FAIL: the cap served % row(s), omitted % of % — expected 3 and %',
        v_seen, v_cap->>'omitted', v_total, v_total - 3;
    end if;
    -- and the three it kept are among the nearest, re-derived from the tables
    select array_agg(x.id order by x.nm, x.ord, x.id) into v_near from (
      select f.id, min(voyage.gc_distance_nm(v_lis_la, v_lis_lo, q.plat, q.plon)) as nm,
             min(nf.roster_ord) as ord
        from public.fleets f
        join public.players p on p.id = f.player_id and p.is_npc
        left join public.npc_fleets nf on nf.fleet_id = f.id
        cross join lateral pg_temp.pts_0102(f.id) q
       group by f.id) x;
    select array_agg((x->>'id')::uuid) into v_got from jsonb_array_elements(v_cap->'fleets') x;
    if not (v_got <@ v_near[1:8]) then
      raise exception '0102 self-assert FAIL: the cap did not keep merchants near the window''s centre (kept % of nearest %)',
        v_got, v_near[1:8];
    end if;
    update public.world_config set value = to_jsonb(240) where key = 'sea_traffic_max';

    -- (e4) A WINDOW OVER THE ANTIMERIDIAN IS A WINDOW. Nothing trades there in this world, so a
    --      merchant's roadstead is MOVED to 179°E for the reading, which is also the proof that the
    --      wrap is the window's and not a quirk of where the harbours happen to lie.
    select f.id into v_seamf
      from public.fleets f join public.players p on p.id = f.player_id and p.is_npc
     where f.status = 'DOCKED' and f.port_id is not null limit 1;
    if v_seamf is null then
      raise exception '0102 self-assert FAIL: no merchant is docked, so the seam reading has no subject';
    end if;
    update public.sea_reaches set roadstead_lat = 0, roadstead_lon = 179
     where port_id = (select port_id from public.fleets where id = v_seamf);
    v_seam := world.sea_traffic(jsonb_build_object('south', -10, 'north', 10, 'west', 170, 'east', -170));
    if not exists (select 1 from jsonb_array_elements(v_seam->'fleets') x where (x->>'id')::uuid = v_seamf) then
      raise exception '0102 self-assert FAIL: a merchant at 179E was not inside a window from 170E to 170W';
    end if;
    if jsonb_array_length(v_seam->'fleets') >= v_total then
      raise exception '0102 self-assert FAIL: a window from 170E to 170W served the whole world (% of %)',
        jsonb_array_length(v_seam->'fleets'), v_total;
    end if;

    -- (e5) MALFORMED VIEWS ARE REFUSED, in the same words.
    for v_win in select * from unnest(array[
        '{"south":0,"north":10,"west":0}'::jsonb,
        '{"south":0,"north":10,"west":0,"east":5,"zoom":2}'::jsonb,
        '{"south":"0","north":10,"west":0,"east":5}'::jsonb,
        '{"south":10,"north":10,"west":0,"east":5}'::jsonb,
        '{"south":0,"north":100,"west":0,"east":5}'::jsonb,
        '{"south":0,"north":10,"west":-200,"east":5}'::jsonb,
        '[1,2,3,4]'::jsonb]) loop
      begin
        perform world.sea_traffic(v_win);
        raise exception '0102 self-assert FAIL: a malformed view was accepted: %', v_win;
      exception when others then
        v_err := sqlerrm;
        if v_err not like 'E_BAD_VIEW%' then raise; end if;
      end;
    end loop;

    -- (e6) WHAT IT COSTS. The window read, timed, so the number is on the record rather than hoped for.
    v_t0 := clock_timestamp();
    for v_n in 1..20 loop
      perform world.sea_traffic(jsonb_build_object(
        'south', round(v_lis_la::numeric - 4, 4), 'north', round(v_lis_la::numeric + 4, 4),
        'west',  round(v_lis_lo::numeric - 4, 4), 'east',  round(v_lis_lo::numeric + 4, 4)));
    end loop;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 20, 2);

    raise exception 'ROLLBACK_0102';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0102' then raise; end if;
  end;

  if (select count(*) from public.players) <> v_base
     or public.wc_int('sea_traffic_max') <> 240
     or public.npc_traders_on() then
    raise exception '0102 self-assert FAIL: the probe did not leave the world as it found it';
  end if;

  raise notice '0102 self-assert ok: THE SEA IS READ THROUGH A WINDOW. client_rpc_entry_points is its '
    'pre-image plus only this file''s one hunk, ACL unmoved, and it now names sea_traffic(jsonb); the '
    '0-arg form is GONE, so no call is ambiguous, and the new one is authenticated-only with the '
    'longitude helper reachable by nobody. lon_in_view knows 179E and 179W are both inside 170E..170W '
    'while 0E is not, takes an edge the pad pushed past 180, and answers the whole world. Dark: empty, '
    'total and omitted both zero. On the real roster of % merchant fleet(s), switched on and rolled back: '
    'handed NO window the read is its own pre-image''s answer, fleet for fleet in the same order, byte '
    'for byte, omitting none, at least one of them at sea; the top-level and row key sets are exact. An '
    '8-degree window on Lisbon served % of % and owned up to the % it left out; every one of them has a '
    'point inside the padded window by a re-derivation from the tables, % were left out, and a merchant '
    'berthed a hemisphere away was not among them. With the cap cut to 3 it served exactly 3 of % and '
    'said so, and all 3 are among the eight nearest the window''s centre. A merchant moved to 179E was '
    'served for a window from 170E to 170W, and that window did not serve the world. Seven malformed '
    'views were each refused E_BAD_VIEW. The window read took % ms a call over 20 calls.',
    v_total, v_mine, v_total, v_total - v_mine, v_far, v_total, v_ms;
end $$;

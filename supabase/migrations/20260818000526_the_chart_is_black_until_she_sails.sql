-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights chart_fog_enabled)
-- 0526 - THE CHART IS BLACK UNTIL SHE SAILS  (dark: the switch chart_fog_enabled, false)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER (docs/design/owner-spec-2026-11-25.md): "The MAP itself will be black, and your fleet will provide a radius that will show
--   you nearby map (cities, location etc.). The radius will be larger based on your NAVIGATION SKILL. But the location you've visited
--   (city, sites etc) will show like a grey map, where you can tab on that city to not see the info, but to go there. The MAP will be
--   completely black, but where your fleets moved and been will be in grey, showing lands partly (transparent)."
--   The plan: docs/design/owner-spec-plan-2026-11-25.md, slice G1 `chart-fog`. The dev log: docs/dev-log/2026-11-25-chart-fog.md.
--
-- WHAT (lit; dark nothing is written and the read answers {"on": false}):
--   public.company_chart            ONE ROW A COMPANY (merchants keep none): `cells`, a bitmap of the world in 1 degree squares, 360 x 180
--                                   = 64,800 bits = 8,100 bytes, always that size. Bit k = row * 360 + col, row = floor(90 - lat), col =
--                                   floor(lon + 180); byte k / 8, bit k % 8 from the low end. A set bit: she has been within sight of it.
--   public.chart_sight_nm(player)   THE SIGHT RADIUS, the one rule: the knob chart_sight_nm (150), and a third of it more for each level
--                                   of NAVIGATION (public.skill_level): 150, 200, 250 ... 650 nautical miles at level 10. ONE knob.
--   public.chart_paint(cells, path, nm)  the one painter: `cells` with every square whose centre lies within `nm` of the path set. The
--                                   path is the voyage's own stored shape ([{a: [lat, lon], b: [lat, lon], nm}]), sampled every third of
--                                   the radius (at least 20 nm) and read to half a degree. Pure: it reads no table.
--   public.chart_mark(player, voyage)    THE ONE WRITE, ONCE PER ARRIVAL (voyage.settle's arrival arm, one hunk beside the logbook's): her
--                                   row with the arrived voyage's stored path painted in. Nothing is written per step or per day at sea.
--                                   A course cut short by a divert or a battle arrives through the same arm with its path cut where she
--                                   turned (cmd.divert, voyage.hostile_freeze), so the part sailed is what is marked. A route already
--                                   charted writes NOTHING (the row is updated only when a bit changes). Dark: one knob read. A
--                                   merchant: one key probe more. It never raises: a fault is a warning and the arrival goes on.
--   public.chart_backfill(player, voyages)   the lead's, once per live company BEFORE the light: her row painted from the newest
--                                   `voyages` ARRIVED voyages of each of her fleets, a sight circle round every harbour in her logbook
--                                   (the authority for the cities she has made; 0478 filled it from her arrival events), round where each
--                                   fleet lies, and round her home. public.chart_backfill_next(companies, voyages) does the next few
--                                   companies that have none and says how many are left. Both server only; both work dark.
--   world.chart()                   THE READ, the client's one door (registered): dark {"on": false}; lit, for her company: her sight in
--                                   nautical miles, her bitmap (base64), the harbours of her logbook. Writes nothing.
-- PRICES ARE STILL SERVED TO EVERYONE IN THIS SLICE. world.market and every other read answer for every harbour exactly as before: the
--   fog is drawn by the client (the map and the Trade map), which hides an unseen city's information. A player who reads the network
--   sees every price. Serving prices by the chart is a later slice (G2 `fog-served`), the owner's to ask for.
-- THE FOG NEVER REFUSES A SAIL (default, the owner may reverse): no door, no path and no job reads the chart. "The whole cities should
--   be reachable": an unseen city can still be named as a destination (the lists, the board, a job), and the automatic paths go where
--   they went. So the fog cannot strand a fleet, and the closed economy and the pathing are untouched.
-- WHAT IS KEPT, READ IN THE CHAIN (production was not read): a company's voyages and events are never deleted by any job: the compactor
--   (0097, 0249, 0257, 0258, 0463) cuts merchants' books only (players.is_npc). So a company's ARRIVED voyages are all there to paint
--   from, as far as the chain knows; what the owner's maintenance may have removed by hand is not known here. NOT BACKFILLED: water
--   sailed on voyages older than the newest `voyages` of a fleet; the voyages of a fleet she has since sold or lost (deleted with the
--   fleet); the part sailed of a voyage that ended ran-dry (ABORTED, voyage.forced_home: its path is the whole course, not what she
--   sailed). Her cities are not lost in any of these: they are the logbook's, and each gets its circle.
-- ROWS: one world_config row a knob (two). Dark: no row. Lit: at most ONE company_chart row written per arrival of a company's fleet,
--   and none when her course was already charted; 0 rows for a merchant. Stated: rows written a minute = company arrivals a minute
--   (well under 1 today, about 19 companies by the docs). The backfill: one row a company, once.
-- budget: one new table, one row a company of 8,100 bytes (1,000 companies about 8 MB before compression); no cron job, no index beyond
--   the key, no autovacuum or fillfactor change.
-- COST: dark one knob read at an arrival. Lit, a company's arrival: her row by key, the paint (printed below), at most one update.
-- LOCKS: CREATE TABLE (new, no foreign key: one would lock public.players); CREATE FUNCTION x6; CREATE OR REPLACE x2 by a hunk each
--   (voyage.settle, public.client_rpc_entry_points); two knobs. TIME: about a second. BUDGET: statement_timeout 60 s, lock_timeout 5 s;
--   fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, chart_fog_enabled false (nothing is written, the read is {"on": false}; the rows stay, inert).
--   FULL: a migration reversing the two hunks (OLD texts below verbatim), dropping the six functions and the table, deleting the knobs.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; two knobs added (the switch false), no other moved; the table and the server-only functions unreachable by a client,
--   world.chart registered for authenticated alone. THE PROBES (rolled back; its own company and its own hand-made courses: nothing of
--   prod's market, dice, companies or age is counted): the painter on a known course (its ends set, nothing far away, the antimeridian
--   crossed the short way, a repeat changes nothing); DARK an arrival writes no row and the read is {"on": false}; LIT her arrival
--   paints her course and only near it, the same course again writes nothing, sight follows the knob and her NAVIGATION level, the read
--   serves her bitmap bit for bit, a merchant and a stranger get none; the backfill paints an old voyage, her logbook's harbours and
--   where she lies.
-- VERSION: 0526 (0499-0503 are other slices' numbers and come first; this file cuts nothing they are known to cut).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['voyage.settle(uuid,timestamp with time zone)', 'public.client_rpc_entry_points()'];
  c_server constant text[] := array['public.chart_sight_nm(uuid)', 'public.chart_paint(bytea,jsonb,numeric)', 'public.chart_mark(uuid,uuid)',
                                    'public.chart_backfill(uuid,integer)', 'public.chart_backfill_next(integer,integer)'];
  c_new    constant text[] := c_server || array['world.chart()'];
  c_uid    constant uuid := '00000000-0526-4000-8000-000000000001';
  c_zero   constant bytea := decode(repeat('00', 8100), 'hex');
  v_t0        timestamptz := clock_timestamp();
  v_t         timestamptz;
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_a         bytea;
  v_b         bytea;
  v_ms_paint  numeric;
  v_ms_far    numeric;
  v_dark      jsonb;
  v_lit       jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key in ('chart_fog_enabled', 'chart_sight_nm')) or to_regclass('public.company_chart') is not null then
    raise exception '0526 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) u(q) where to_regprocedure(u.q) is null)
     or to_regprocedure('public.logbook_arrival(uuid,uuid,uuid,timestamp with time zone)') is null
     or to_regprocedure('public.skill_level(uuid,text)') is null
     or to_regprocedure('voyage.gc_distance_nm(double precision,double precision,double precision,double precision)') is null
     or to_regprocedure('voyage.lon_lerp(double precision,double precision,double precision)') is null then
    raise exception '0526 refuses: a body it cuts, the logbook (0478), the skill level (0107) or the sea''s arithmetic is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('chart_fog_enabled', 'false'::jsonb,
     '0526: THE SWITCH (the owner''s). true: a company''s chart is painted at each arrival of her fleets from the voyage''s stored path (public.chart_mark, one row a company, public.company_chart) and world.chart() serves her sight, her bitmap and her logbook''s harbours, so the client draws the map black, clear within sight of her fleets and grey where she has been. false: nothing is written and the read is {"on": false}. Light it only after public.chart_backfill_next answers left 0. No door reads the chart: the fog never refuses a sail. Prices are served to everyone as before.'),
    ('chart_sight_nm', to_jsonb(150),
     '0526: how far a company''s fleet sees, in nautical miles, at NAVIGATION level 0. Each level of NAVIGATION adds a third of it (150: 200 at level 1, 650 at level 10). The one knob of the sight (public.chart_sight_nm): the circle the client clears round each fleet, and the width of the grey she leaves behind.');

  -- ── 3. THE TABLE ──
  -- retention: none, bounded by one row a company of a fixed size (8,100 bytes); merchants keep none
  create table public.company_chart (
    player_id     uuid primary key,
    cells         bytea not null check (length(cells) = 8100),
    backfilled_at timestamptz,
    updated_at    timestamptz not null default now()
  );
  comment on table public.company_chart is
    '0526: a company''s chart, one row: `cells` is the world in 1 degree squares (360 x 180 bits, row = floor(90 - lat), col = floor(lon + 180), '
    'bit row * 360 + col, low bit first), a set bit where she has been within sight. Written by public.chart_mark at an arrival and by '
    'public.chart_backfill once. Merchants keep none. No foreign key on purpose: one would lock public.players. Read by world.chart().';
  alter table public.company_chart enable row level security;
  revoke all on table public.company_chart from public, anon, authenticated;

  -- ── 4. THE RULES ──
  execute $f$
create function public.chart_sight_nm(p_player uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0526: HOW FAR HER FLEETS SEE, in nautical miles: THE ONE RULE (public.chart_mark and public.chart_backfill paint with it, world.chart()
  -- serves it, the client draws its circle and computes nothing). The knob chart_sight_nm, and a third of it more for each level of
  -- NAVIGATION (public.skill_level: 0 with no row). Never under 0, never over 3,000.
  select round(least(3000, greatest(0, coalesce(public.wc_num('chart_sight_nm'), 0))
                           * (3 + greatest(0, coalesce(public.skill_level(p_player, 'NAVIGATION'), 0))) / 3.0))
$body$
  $f$;

  execute $f$
create function public.chart_paint(p_cells bytea, p_path jsonb, p_nm numeric)
returns bytea
language sql
immutable
set search_path = public, pg_temp
as $body$
  -- 0526: THE ONE PAINTER. `p_cells` (8,100 bytes; null or another length: an empty chart) with every 1 degree square set whose centre
  -- lies within `p_nm` of the path, and the square under each point of the path whatever the radius. The path is a voyage's stored shape,
  -- [{a: [lat, lon], b: [lat, lon], nm}] (a point is a piece with a = b): sampled every third of the radius (at least 20 nm; at most
  -- 4,000 points a piece), placed as voyage.position places her (latitude straight, longitude the short way round: voyage.lon_lerp) and
  -- read to half a degree, each point once. The distance is the sea's own (voyage.gc_distance_nm). Reads no table, writes nothing.
  with k as (
    select least(3000, greatest(0, coalesce(p_nm, 0)))::float8 as nm
  ),
  seg as (
    select (e->'a'->>0)::float8 as la, (e->'a'->>1)::float8 as lo, (e->'b'->>0)::float8 as lb, (e->'b'->>1)::float8 as lob,
           greatest(0, coalesce((e->>'nm')::float8, 0)) as nm
      from jsonb_array_elements(case when jsonb_typeof(p_path) = 'array' then p_path else '[]'::jsonb end) e
     where jsonb_typeof(e->'a') = 'array' and jsonb_typeof(e->'b') = 'array'
  ),
  pt as (
    select distinct
           least(90, greatest(-90, round(((s.la + (s.lb - s.la) * g.i / n.n) * 2)::numeric) / 2.0))::float8 as lat,
           (round((voyage.lon_lerp(s.lo, s.lob, g.i::float8 / n.n) * 2)::numeric) / 2.0)::float8 as lon
      from seg s cross join k
      cross join lateral (select greatest(1, least(4000, ceil(s.nm / greatest(20, k.nm / 3.0))::int)) as n) n
      cross join lateral generate_series(0, n.n) g(i)
  ),
  ptc as (
    select pt.lat, pt.lon,
           least(179, greatest(0, floor(90 - pt.lat)::int)) as r,
           ((floor(pt.lon + 180)::int % 360) + 360) % 360 as c
      from pt
  ),
  near as (
    select ptc.r, ptc.c from ptc
    union
    select rr.r, ((cc.c % 360) + 360) % 360
      from ptc cross join k
      cross join lateral generate_series(greatest(0, ptc.r - (ceil(k.nm / 60.0)::int + 1)), least(179, ptc.r + ceil(k.nm / 60.0)::int + 1)) rr(r)
      cross join lateral (select case when 60.0 * cos(radians(89.5 - rr.r)) * 179 <= k.nm then 180
                                      else least(180, ceil(k.nm / (60.0 * cos(radians(89.5 - rr.r))))::int + 1) end as dc) w
      cross join lateral generate_series(ptc.c - w.dc, ptc.c + w.dc - (case when w.dc = 180 then 1 else 0 end)) cc(c)
     where k.nm > 0
       and voyage.gc_distance_nm(ptc.lat, ptc.lon, 89.5 - rr.r, -179.5 + (((cc.c % 360) + 360) % 360)) <= k.nm
  ),
  byt as (
    select (n.r * 360 + n.c) / 8 as i, bit_or(1 << ((n.r * 360 + n.c) % 8)) as m from near n group by 1
  ),
  base as (
    select case when p_cells is null or length(p_cells) <> 8100 then decode(repeat('00', 8100), 'hex') else p_cells end as b
  )
  select decode(string_agg(lpad(to_hex(get_byte(base.b, g.i) | coalesce(byt.m, 0)), 2, '0'), '' order by g.i), 'hex')
    from base cross join generate_series(0, 8099) g(i) left join byt on byt.i = g.i
$body$
  $f$;

  execute $f$
create function public.chart_mark(p_player uuid, p_voyage uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0526: THE CHART'S ONE WRITE AT SEA, called once per arrival by voyage.settle's arrival arm (never per step, never per day). Dark: nothing
-- after one knob read. A merchant (or nobody): nothing after one players probe. Lit, a company: her row (public.company_chart) with the
-- arrived voyage's stored path painted in at her sight today (public.chart_sight_nm, public.chart_paint); her row is locked while it is
-- read and written, so two of her fleets arriving together both stay on the chart. A course already charted changes no bit and WRITES
-- NOTHING. Never raises: a fault is a warning, so an arrival never fails here.
declare
  v_path jsonb;
  v_nm   numeric;
  v_old  bytea;
  v_new  bytea;
begin
  if public.wc('chart_fog_enabled') is distinct from 'true'::jsonb then
    return;
  end if;
  if p_player is null or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return;
  end if;
  begin
    select v.path into v_path from public.voyages v where v.id = p_voyage;
    if v_path is null or jsonb_typeof(v_path) <> 'array' or jsonb_array_length(v_path) = 0 then
      return;
    end if;
    v_nm := public.chart_sight_nm(p_player);
    select c.cells into v_old from public.company_chart c where c.player_id = p_player for update;
    if not found then
      insert into public.company_chart (player_id, cells) values (p_player, public.chart_paint(null, v_path, v_nm))
      on conflict (player_id) do update set cells = public.chart_paint(public.company_chart.cells, v_path, v_nm), updated_at = now();
      return;
    end if;
    v_new := public.chart_paint(v_old, v_path, v_nm);
    if v_new is distinct from v_old then
      update public.company_chart c set cells = v_new, updated_at = now() where c.player_id = p_player;
    end if;
  exception when others then
    raise warning 'chart_mark: % voyage % was not charted (SQLSTATE %: %)', p_player, p_voyage, sqlstate, sqlerrm;
  end;
end
$body$
  $f$;

  execute $f$
create function public.chart_backfill(p_player uuid, p_voyages integer default 500)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0526: ONE LIVE COMPANY'S CHART, FROM WHERE SHE HAS ALREADY BEEN (the lead's, before the light; it works dark; server only). Painted at
-- her sight today into her row: the stored paths of the newest `p_voyages` ARRIVED voyages of each of her fleets (by the (fleet_id, eta)
-- index of ended voyages), a point for every harbour in her logbook (the authority for the cities she has made), for where each of her
-- fleets lies, and for her home. Her row is stamped backfilled_at. A merchant or nobody: refused, nothing written. Run again it only
-- adds. NOT painted: older voyages than those, the voyages of a fleet she no longer has, and the part sailed of a ran-dry voyage.
declare
  v_nm   numeric;
  v_path jsonb;
  v_n    int;
  v_old  bytea;
  v_new  bytea;
begin
  if p_player is null or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return jsonb_build_object('ok', false, 'why', 'not a company');
  end if;
  v_nm := public.chart_sight_nm(p_player);
  with vs as (
    select x.path
      from public.fleets f
      cross join lateral (select v.path from public.voyages v
                           where v.fleet_id = f.id and v.status <> 'SAILING' and v.status = 'ARRIVED'
                           order by v.eta desc limit greatest(0, coalesce(p_voyages, 0))) x
     where f.player_id = p_player
  ),
  pts as (
    select p.lat, p.lon from public.logbook l join public.ports p on p.code = l.code
     where l.player_id = p_player and l.kind = 'harbour'
    union
    select coalesce(p.lat, f.lat), coalesce(p.lon, f.lon) from public.fleets f left join public.ports p on p.id = f.port_id
     where f.player_id = p_player
    union
    select p.lat, p.lon from public.ports p where p.id = public.home_port_of(p_player)
  ),
  seg as (
    select e.seg from vs cross join lateral jsonb_array_elements(case when jsonb_typeof(vs.path) = 'array' then vs.path else '[]'::jsonb end) e(seg)
    union all
    select jsonb_build_object('a', jsonb_build_array(pts.lat, pts.lon), 'b', jsonb_build_array(pts.lat, pts.lon), 'nm', 0)
      from pts where pts.lat is not null and pts.lon is not null
  )
  select coalesce((select jsonb_agg(seg.seg) from seg), '[]'::jsonb), (select count(*) from vs) into v_path, v_n;
  select c.cells into v_old from public.company_chart c where c.player_id = p_player for update;
  v_new := public.chart_paint(v_old, v_path, v_nm);
  insert into public.company_chart (player_id, cells, backfilled_at) values (p_player, v_new, now())
  on conflict (player_id) do update set cells = public.chart_paint(public.company_chart.cells, v_path, v_nm), backfilled_at = now(), updated_at = now();
  return jsonb_build_object('ok', true, 'voyages', v_n, 'pieces', jsonb_array_length(v_path), 'sight_nm', v_nm,
                            'squares', (select bit_count(c.cells) from public.company_chart c where c.player_id = p_player));
end
$body$
  $f$;

  execute $f$
create function public.chart_backfill_next(p_companies integer default 5, p_voyages integer default 500)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0526: THE NEXT FEW COMPANIES WITHOUT A BACKFILLED CHART (the lead's, off the beat, the gate read first; server only): each through
-- public.chart_backfill, at most `p_companies` a call, in id order. Answers what it did and how many are LEFT: light chart_fog_enabled
-- when left is 0. One row a company written, once.
declare
  r      record;
  v_done jsonb := '[]'::jsonb;
begin
  for r in select pl.id from public.players pl
            where not pl.is_npc
              and not exists (select 1 from public.company_chart c where c.player_id = pl.id and c.backfilled_at is not null)
            order by pl.id limit greatest(0, coalesce(p_companies, 0)) loop
    v_done := v_done || jsonb_build_array(public.chart_backfill(r.id, p_voyages) || jsonb_build_object('player', r.id));
  end loop;
  return jsonb_build_object('done', v_done,
    'left', (select count(*) from public.players pl
              where not pl.is_npc
                and not exists (select 1 from public.company_chart c where c.player_id = pl.id and c.backfilled_at is not null)));
end
$body$
  $f$;

  execute $f$
create function world.chart()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0526: THE CHART, the client's one door for the fog. Dark (chart_fog_enabled false): {"on": false}, and the map is drawn whole as
-- before. Lit, signed out or a merchant: {"on": true, "company": false}. Lit, her company: `sight_nm` (public.chart_sight_nm: the circle
-- the client clears round each of her fleets), `rows` 180 and `cols` 360, `cells` (her bitmap in base64, null before her first arrival
-- or backfill: bit row * 360 + col, row = floor(90 - lat), col = floor(lon + 180), low bit of each byte first), `cities` (the harbour
-- codes of her logbook: the cities she has made, grey and pressable wherever they are), `backfilled`. Writes nothing.
-- PRICES ARE NOT GATED BY THIS: every other read serves every harbour as before; the client hides what is out of sight.
declare
  v_me uuid := public.current_player_id();
begin
  if public.wc('chart_fog_enabled') is distinct from 'true'::jsonb then
    return jsonb_build_object('on', false);
  end if;
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return jsonb_build_object('on', true, 'company', false);
  end if;
  return jsonb_build_object(
    'on', true,
    'company', true,
    'sight_nm', public.chart_sight_nm(v_me),
    'rows', 180,
    'cols', 360,
    'cells', (select replace(encode(c.cells, 'base64'), E'\n', '') from public.company_chart c where c.player_id = v_me),
    'backfilled', coalesce((select c.backfilled_at is not null from public.company_chart c where c.player_id = v_me), false),
    'cities', (select coalesce(jsonb_agg(l.code order by l.code), '[]'::jsonb) from public.logbook l where l.player_id = v_me and l.kind = 'harbour'));
end
$body$
  $f$;

  -- grants: the read for a signed-in client alone; the rest server only (service_role too: the platform grants execute by default)
  foreach v_def in array c_server loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;
  revoke all on function world.chart() from public, anon;
  grant execute on function world.chart() to authenticated;
  comment on function world.chart() is
    '0526: the chart for the fog. Dark {"on": false}. Lit, her company: sight_nm, her bitmap (cells, base64, 360 x 180 squares of 1 degree), the harbours of her logbook. A read; no argument, no player id. Prices are not gated by it.';

  -- ── 5. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0526 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0526 values
  ('voyage.settle(uuid,timestamp with time zone)', 1,
$h$      || public.logbook_arrival(f.player_id, v.origin_port_id, v.dest_port_id, v.eta));$h$,
$h$      || public.logbook_arrival(f.player_id, v.origin_port_id, v.dest_port_id, v.eta));
    -- 0526: the chart: the path she has just sailed is painted into her company's one row (nothing dark, for a merchant, or when it was charted already)
    perform public.chart_mark(f.player_id, v.id);$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'logbook',               ''),$h$,
$h$      ('world',       'logbook',               ''),
      -- 0526: the chart for the fog (dark: {"on": false})
      ('world',       'chart',                 ''),$h$);

  for v_h in select h.fn from hunks_0526 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0526 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0526 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0526 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0526 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0526 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the grants, the knobs, the door ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0526 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0526 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_server) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or has_table_privilege('authenticated', 'public.company_chart', 'select') or has_table_privilege('anon', 'public.company_chart', 'select')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.company_chart'::regclass)
     or (select count(*) from public.client_write_grants()) <> 0
     or (select p.provolatile from pg_proc p where p.oid = 'world.chart()'::regprocedure) <> 's'
     or (select count(*) from public.client_rpc_entry_points() e
          where (e.schema_name, e.function_name, e.arg_types) = ('world', 'chart', '')
            and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) <> 1 then
    raise exception '0526 self-assert FAIL: world.chart is not registered for authenticated alone, or a client reaches a server-only function or the table';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key not in ('chart_fog_enabled', 'chart_sight_nm')) <> v_cfg_before
     or public.wc('chart_fog_enabled') is distinct from 'false'::jsonb or public.wc_num('chart_sight_nm') is distinct from 150
     or exists (select 1 from public.company_chart) then
    raise exception '0526 self-assert FAIL: a knob other than the two moved, the switch is not false, or a chart row was written';
  end if;

  -- ── 7. THE PAINTER, on courses made by hand (no table read) ──
  -- (a) four degrees along 38 N at 150 nm: both ends' squares set; nothing more than five squares from the course; a repeat changes nothing
  v_t := clock_timestamp();
  v_a := public.chart_paint(null, '[{"a": [38.2, -9.4], "b": [38.2, -5.4], "nm": 190}]'::jsonb, 150);
  v_ms_paint := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
  if length(v_a) <> 8100 or bit_count(v_a) < 10 or bit_count(v_a) > 120
     or get_bit(v_a, 51 * 360 + 170) <> 1 or get_bit(v_a, 51 * 360 + 174) <> 1
     or exists (select 1 from generate_series(0, 64799) g(k)
                 where get_bit(v_a, g.k) = 1 and (abs(g.k / 360 - 51) > 4 or g.k % 360 not between 165 and 179))
     or public.chart_paint(v_a, '[{"a": [38.2, -9.4], "b": [38.2, -5.4], "nm": 190}]'::jsonb, 150) <> v_a
     or public.chart_paint(null, '[]'::jsonb, 150) <> c_zero or public.chart_paint(null, null, 150) <> c_zero then
    raise exception '0526 self-assert FAIL: the painter does not paint a known course as its squares: % set', bit_count(v_a);
  end if;
  -- (b) every square it set lies within the radius of the course (to the half degree a point is read to and the third of the radius
  --     between points), and it only ever adds
  if exists (select 1 from generate_series(0, 64799) g(k)
              where get_bit(v_a, g.k) = 1
                and not exists (select 1 from generate_series(0, 40) s(i)
                                 where voyage.gc_distance_nm(89.5 - g.k / 360, -179.5 + g.k % 360, 38.2, -9.4 + s.i * 0.1) <= 150 + 45)) then
    raise exception '0526 self-assert FAIL: the painter set a square out of sight of the course';
  end if;
  v_b := public.chart_paint(v_a, '[{"a": [10.5, 60.5], "b": [10.5, 60.5], "nm": 0}]'::jsonb, 0);
  if bit_count(v_b) <> bit_count(v_a) + 1 or get_bit(v_b, 79 * 360 + 240) <> 1
     or exists (select 1 from generate_series(0, 64799) g(k) where get_bit(v_a, g.k) = 1 and get_bit(v_b, g.k) = 0) then
    raise exception '0526 self-assert FAIL: a point at radius 0 is not its one square added to the chart';
  end if;
  -- (c) the antimeridian, the short way round: 179.4 E to 179.4 W is one degree of water, not 359
  v_b := public.chart_paint(null, '[{"a": [0.5, 179.4], "b": [0.5, -179.4], "nm": 72}]'::jsonb, 0);
  if get_bit(v_b, 89 * 360 + 359) <> 1 or get_bit(v_b, 89 * 360 + 0) <> 1 or bit_count(v_b) > 4 then
    raise exception '0526 self-assert FAIL: a course over the antimeridian is painted the long way round: % squares', bit_count(v_b);
  end if;
  -- (d) the widest sight on a long course: its cost, printed (a 5,000 nm passage at 650 nm)
  v_t := clock_timestamp();
  v_b := public.chart_paint(null, '[{"a": [35, -10], "b": [15, -60], "nm": 2800}, {"a": [15, -60], "b": [-30, -40], "nm": 2900}]'::jsonb, 650);
  v_ms_far := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
  if get_bit(v_b, 55 * 360 + 170) <> 1 or get_bit(v_b, 119 * 360 + 140) <> 1 or get_bit(v_b, 60 * 360 + 300) <> 0 then
    raise exception '0526 self-assert FAIL: a long course at the widest sight is not painted end to end';
  end if;

  -- ── 8. THE PROBES (one scene, played dark and lit, each rolled back) ──
  execute $f$
create function pg_temp.scene_0526(p_uid uuid, p_lit boolean)
returns jsonb
language plpgsql
as $body$
declare
  v_me   uuid;
  v_fl   uuid;
  v_lis  uuid;
  v_set  uuid;
  v_la   record;
  v_sa   record;
  v_segs jsonb;
  v_voy  uuid;
  v_eta  timestamptz;
  v_st   text;
  v_c1   bytea;
  v_r    jsonb;
  v_same boolean;
  v_wrote boolean;
  v_s0   numeric;
  v_s1   numeric;
  v_s2   numeric;
  v_npc  uuid;
  v_nv   uuid;
  v_far  bytea;
  v_bf   jsonb;
  v_bfn  jsonb;
  v_old  uuid;
  v_out  jsonb;
begin
  select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
  select p.id into v_set from public.ports p where p.code = 'SET' and p.kind = 'HARBOUR';
  select a.roadstead_lat as lat, a.roadstead_lon as lon into v_la from public.sea_reaches a where a.port_id = v_lis;
  select a.roadstead_lat as lat, a.roadstead_lon as lon into v_sa from public.sea_reaches a where a.port_id = v_set;
  v_segs := voyage.segments_from_course(jsonb_build_array(jsonb_build_array(v_la.lat, v_la.lon), jsonb_build_array(v_sa.lat, v_sa.lon)));
  -- the founding is not what is judged: it is played with the economy open, so that no city's purse (prod's) can refuse it (rolled back)
  update public.world_config set value = 'false'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
  v_me := public.new_house(p_uid, 'Casa da Carta 0526', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_me;
  if p_lit then
    update public.world_config set value = 'true'::jsonb where key in ('chart_fog_enabled', 'logbook_enabled');
  end if;
  v_s0 := public.chart_sight_nm(v_me);
  -- her arrival through the real arm: Lisbon to Setubal, 20 seconds back. Whatever the sea's dice do to the passage, the chart is judged
  -- on the arrival: if the dice kept her from arriving, the one write is called as the arm would have called it.
  update public.fleets f set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, busy_until = null, ready_at = null where f.id = v_fl;
  v_voy := voyage.depart(v_fl, v_segs, v_lis, v_set, now() - interval '20 seconds');
  select v.eta into v_eta from public.voyages v where v.id = v_voy;
  perform voyage.settle(v_fl, v_eta + interval '1 second');
  select v.status into v_st from public.voyages v where v.id = v_voy;
  if v_st is distinct from 'ARRIVED' then
    perform public.chart_mark(v_me, v_voy);
  end if;
  select c.cells into v_c1 from public.company_chart c where c.player_id = v_me;
  perform cmd.assume_identity(p_uid);
  v_r := world.chart();
  v_out := jsonb_build_object(
    'arrived', v_st, 'row', v_c1 is not null, 'read', v_r - 'cells', 'sight0', v_s0,
    'squares', case when v_c1 is null then 0 else bit_count(v_c1) end,
    'ends', v_c1 is not null and get_bit(v_c1, floor(90 - v_la.lat)::int * 360 + floor(v_la.lon + 180)::int) = 1
                             and get_bit(v_c1, floor(90 - v_sa.lat)::int * 360 + floor(v_sa.lon + 180)::int) = 1,
    -- only near her course: every square set is within her sight of one of its two ends or its middle, to a square's own half width
    'stray', (select count(*) from generate_series(0, 64799) g(k)
               where v_c1 is not null and get_bit(v_c1, g.k) = 1
                 and least(voyage.gc_distance_nm(89.5 - g.k / 360, -179.5 + g.k % 360, v_la.lat::float8, v_la.lon::float8),
                           voyage.gc_distance_nm(89.5 - g.k / 360, -179.5 + g.k % 360, v_sa.lat::float8, v_sa.lon::float8),
                           voyage.gc_distance_nm(89.5 - g.k / 360, -179.5 + g.k % 360, ((v_la.lat + v_sa.lat) / 2)::float8, ((v_la.lon + v_sa.lon) / 2)::float8))
                     > v_s0 + 45),
    'served', v_c1 is not null and decode(v_r->>'cells', 'base64') = v_c1);
  if not p_lit then
    return v_out;
  end if;
  -- the same course again: no bit changes, so nothing is written (her row's stamp is where it was set)
  update public.company_chart c set updated_at = '2000-01-01'::timestamptz where c.player_id = v_me;
  perform public.chart_mark(v_me, v_voy);
  select c.updated_at = '2000-01-01'::timestamptz and c.cells = v_c1 into v_same from public.company_chart c where c.player_id = v_me;
  -- another course (hand-made, far away): the row is written, and what was charted stays
  insert into public.voyages (fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id, created_at)
  values (v_fl, v_me, '[{"a": [-40.3, 100.2], "b": [-40.3, 104.2], "nm": 183}]'::jsonb, 183, '{}'::jsonb, now() - interval '3 hours', now() - interval '2 hours', 'ARRIVED', null, null, now() - interval '3 hours')
  returning id into v_old;
  perform public.chart_mark(v_me, v_old);
  select c.updated_at > '2000-01-01'::timestamptz and get_bit(c.cells, 130 * 360 + 280) = 1 and get_bit(c.cells, 130 * 360 + 284) = 1
         and not exists (select 1 from generate_series(0, 64799) g(k) where get_bit(v_c1, g.k) = 1 and get_bit(c.cells, g.k) = 0)
    into v_wrote from public.company_chart c where c.player_id = v_me;
  -- sight: the knob, and a third of it more a level
  insert into public.player_skills (player_id, skill_id, level, studied_at)
  select v_me, s.id, 3, now() from public.skills s where s.code = 'NAVIGATION'
  on conflict (player_id, skill_id) do update set level = 3;
  v_s1 := public.chart_sight_nm(v_me);
  update public.world_config set value = to_jsonb(300) where key = 'chart_sight_nm';
  v_s2 := public.chart_sight_nm(v_me);
  update public.world_config set value = to_jsonb(150) where key = 'chart_sight_nm';
  -- the backfill: her row thrown away, then painted again from her stored voyages, her logbook and where she lies
  delete from public.company_chart c where c.player_id = v_me;
  v_bf := public.chart_backfill(v_me, 500);
  select c.cells into v_far from public.company_chart c where c.player_id = v_me;
  -- a merchant: no row from the write, refused by the backfill, no company on the read; a stranger: no company
  select n.id into v_npc from public.players n where n.is_npc order by n.id limit 1;
  if v_npc is not null then
    perform public.chart_mark(v_npc, v_old);
    v_bfn := public.chart_backfill(v_npc, 500);
  end if;
  return v_out || jsonb_build_object(
    'same', v_same, 'wrote', v_wrote, 'level', public.skill_level(v_me, 'NAVIGATION'), 'sight1', v_s1, 'sight2', v_s2,
    'cities', v_r->'cities',
    'backfill', v_bf,
    'backfill_ok', v_far is not null and get_bit(v_far, 130 * 360 + 280) = 1
                   and get_bit(v_far, floor(90 - v_sa.lat)::int * 360 + floor(v_sa.lon + 180)::int) = 1
                   and (select c.backfilled_at is not null from public.company_chart c where c.player_id = v_me),
    'npc', v_npc is null or (not exists (select 1 from public.company_chart c where c.player_id = v_npc) and v_bfn->>'ok' = 'false'),
    'rows', (select count(*) from public.company_chart c where c.player_id is distinct from v_me and c.player_id is distinct from v_npc
                                                             and c.updated_at >= transaction_timestamp() and c.backfilled_at is null));
end
$body$
  $f$;

  -- (a) DARK: her arrival writes no row; the read is {"on": false}
  begin
    v_dark := pg_temp.scene_0526(c_uid, false);
    raise exception using errcode = 'ZX504', message = 'PROBE_ROLLBACK_0526_DARK';
  exception when sqlstate 'ZX504' then null;
  end;
  if (v_dark->>'row')::boolean or v_dark->'read' is distinct from '{"on": false}'::jsonb or (v_dark->>'sight0')::numeric <> 150 then
    raise exception '0526 self-assert FAIL: dark, an arrival wrote a chart row, the read is not {"on": false}, or the sight at level 0 is not the knob: %', v_dark;
  end if;
  -- (b) LIT
  begin
    v_lit := pg_temp.scene_0526(c_uid, true);
    raise exception using errcode = 'ZX504', message = 'PROBE_ROLLBACK_0526_LIT';
  exception when sqlstate 'ZX504' then null;
  end;
  if not (v_lit->>'row')::boolean or not (v_lit->>'ends')::boolean or (v_lit->>'stray')::int <> 0
     or (v_lit->>'squares')::int not between 2 and 200 or not (v_lit->>'served')::boolean
     or v_lit #>> '{read,on}' is distinct from 'true' or v_lit #>> '{read,company}' is distinct from 'true'
     or (v_lit #>> '{read,sight_nm}')::numeric <> 150 or (v_lit #>> '{read,rows}')::int <> 180 or (v_lit #>> '{read,cols}')::int <> 360 then
    raise exception '0526 self-assert FAIL: lit, her arrival did not paint her course and only her course, or the read does not serve it: %', v_lit;
  end if;
  if not (v_lit->>'same')::boolean or not (v_lit->>'wrote')::boolean then
    raise exception '0526 self-assert FAIL: lit, a course already charted was written again, or a new course was not added to what she had: %', v_lit;
  end if;
  if (v_lit->>'sight1')::numeric <> round(150 * (3 + (v_lit->>'level')::int) / 3.0) or (v_lit->>'sight2')::numeric <> 2 * (v_lit->>'sight1')::numeric
     or ((v_lit->>'level')::int = 3 and (v_lit->>'sight1')::numeric <> 300) then
    raise exception '0526 self-assert FAIL: her sight is not the knob and a third of it a NAVIGATION level: %', v_lit;
  end if;
  if not (v_lit->>'backfill_ok')::boolean or v_lit #>> '{backfill,ok}' is distinct from 'true' or (v_lit #>> '{backfill,voyages}')::int < 1
     or not (v_lit->>'npc')::boolean or (v_lit->>'rows')::int <> 0 then
    raise exception '0526 self-assert FAIL: the backfill did not paint her old voyage and where she has been, or a merchant or another company was written: %', v_lit;
  end if;
  -- her logbook's harbours are her cities (the logbook lit beside the chart in the scene): where she arrived is one of them
  if (v_lit->>'arrived') = 'ARRIVED' and not (v_lit->'cities' ? 'SET') then
    raise exception '0526 self-assert FAIL: the harbour she made is not among her cities: %', v_lit->'cities';
  end if;
  if exists (select 1 from public.players p where p.auth_uid = c_uid)
     or exists (select 1 from public.company_chart)
     or public.wc('chart_fog_enabled') is distinct from 'false'::jsonb or public.wc_num('chart_sight_nm') is distinct from 150
     or public.current_player_id() is not null then
    raise exception '0526 self-assert FAIL: the probe left something behind';
  end if;
  drop function pg_temp.scene_0526(uuid, boolean);

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0526 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0526 self-assert ok: THE CHART IS BLACK UNTIL SHE SAILS (dark). 2 hunks once and reversing; no other function moved; the hunked bodies'' grants and volatility unmoved; two knobs added (the switch false, sight 150 nm), no other moved; one table (no row), five functions server only, world.chart registered for authenticated alone. The painter: four degrees at 150 nm % squares in % ms; 5,700 nm at 650 nm in % ms; the antimeridian the short way. Probes (rolled back): dark, her arrival (%) wrote no row and the read is {"on": false}; lit, her arrival (%) painted % squares, both ends, none out of sight, served bit for bit; the same course again wrote nothing; another course was added; sight % nm at level % (the knob doubled: %); cities %; the backfill %; a merchant none. Prices are served to everyone as before. % ms.',
    bit_count(v_a), v_ms_paint, v_ms_far, v_dark->>'arrived', v_lit->>'arrived', v_lit->>'squares', v_lit->>'sight1', v_lit->>'level', v_lit->>'sight2',
    v_lit->'cities', v_lit->'backfill', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;

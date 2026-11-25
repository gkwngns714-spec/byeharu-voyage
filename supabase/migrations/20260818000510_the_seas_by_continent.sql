-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: the seas ask nothing while sea_conditions_bite is false; the Seas page shows the new order)
-- 0510 - THE SEAS BY CONTINENT  (dark: the switch is 0215's sea_conditions_bite, false since the owner's word of 2026-11-23; this file does not move it)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (docs/design/owner-spec-2026-11-25.md, answer 1): "Start with EUROPE, then AFRICA, THEN USA then BRAZIL, THEN INDIA, THEN ASIA etc -
--   continent wise"; then of the eight rungs: "GOOD" (docs/design/owner-spec-red-2026-11-25.md, R11). The table is plan section 0.1, sea by sea.
-- WHAT:
--   public.sea_zones            42 of the 64 seas ask another LEVEL: 1 Europe, 2 Africa, 3 North America, 4 South America, 5 India, 6 Asia, 7 the rest,
--                               8 sealed (the Pacific, its American coast, the Arctic, the far south). No wave figure, box, name or order moves: the order
--                               (`ord`) is the byte of public.sea_zone_cells.
--   public.sea_zones.title_was  the level each sea asked before this file (nullable; a later sea has none and reads its own).
--   public.sea_leg_asks         brought in step by the one step that keeps it (public.sea_leg_asks_keep, 0442).
--   ONE GATE: public.sea_refusal, not touched, is still the only place a level or a wave is compared. The level is public.title_level: the lower of Trading
--                               and Exploration.
--   WHAT A COMPANY CAN REACH TODAY STAYS HERS (decided by default; the owner may reverse it by the knob): for a company founded before this file
--                               (world_config seas_by_continent_at) public.seas_kept(fleet) answers the seas the OLD levels open to her that the new ones
--                               would not: asked through public.sea_refusal, the old level for the new one. That is the Arctic Ocean (3, now 8), the one sea
--                               that asks more, and, for a company whose capital is outside Europe, her old home rank's seas. Every other change asks LESS.
--                               (The water her FLEETS lie in beyond her rung is pass-home's, 0513.)
--   public.sea_closed(player, fleet)   the seas shut to her now, each asked of public.sea_judge with her floors, less the ones kept. NEW, one reading.
--   public.sea_floor            made again with the two zones beside their asks (zone, home_zone); its four first answers are as they were.
--   public.sea_judge (3 hunks), public.npc_sea_floor (2)  A MERCHANT'S HOME WATERS ARE GROUPED BY title_was: the world's merchants (title null: only
--                               the wave binds them) sail exactly where they sailed, whatever sea_conditions_bite_npc says.
--   public.sea_gate, public.sea_conditions_ready (1 hunk each), public.sea_routes, world.sea_conditions (2 each), voyage.reach_passage (6): the kept seas are
--                               read; the board's pathfinder asks the door's own answer for every sea of a pair (public.sea_closed) instead of the pair's
--                               highest ask.
-- DARK: voyage.reach_passage, public.sea_gate and public.sea_routes' verdicts read none of it while the switch is false; a board row's needs_title is the new
--   figure (a reading no screen draws). raid_company_title_min and early sighting compare a company's level with their own knobs: not moved.
-- NOT CHANGED: any wave figure, course, raster cell, strait, harbour, the Arctic's ice (a later raster slice), the switch, any merchant's order.
-- ROWS: 42 sea_zones rows; up to one update a pair row (64,516 today, once); one world_config row. No table, no index, no cron. 0 new rows a minute.
-- budget: no table, no cron job, no autovacuum or fillfactor change; the pair rows are rewritten once in this file. Tick: 0 ms (nothing on a beat reads a
--   level; lit, a player's sail reads seas_kept; measured in proof 215).
-- LOCKS: ALTER TABLE sea_zones ADD COLUMN (nullable); row writes on sea_zones and sea_leg_asks; DROP + CREATE public.sea_floor; CREATE OR REPLACE x8 by hunks.
--   TIME: a few seconds. BUDGET: statement_timeout 90 s, lock_timeout 5 s; fails above 60 s.
-- ROLLBACK (forward, owner only): QUICK, sea_conditions_bite false (it is). FULL: title_min := title_was, sea_leg_asks_keep(), the hunks reversed
--   (OLD texts below verbatim), sea_floor as 0396 wrote it, seas_kept and sea_closed dropped.
-- SELF-ASSERT: the table as listed, the rest of every row unmoved; the pair table in step; each hunk once and reversing; no other function or knob moved; the
--   readers server only; THE PROBE (rolled back; its own company, lit inside the probe): level 1 is refused Africa by its level, her Arctic is kept only when she
--   was founded before, and the merchants' floors answer what they answered before this file (the first 200 merchant fleets). Nothing reads a price, a die, a
--   real company or the world's age.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.sea_judge(integer,numeric,text[],integer,integer,integer,integer)', 'public.npc_sea_floor(uuid)', 'public.sea_gate(uuid,uuid,uuid,jsonb)', 'public.sea_routes(uuid,integer,numeric,jsonb)', 'public.sea_conditions_ready()', 'world.sea_conditions()', 'voyage.reach_passage(uuid,uuid,uuid,numeric)']::text[];
  c_new    constant text[] := array['public.sea_floor(uuid,jsonb)', 'public.seas_kept(uuid)', 'public.sea_closed(uuid,uuid)']::text[];
  c_gone   constant text[] := array['public.sea_floor(uuid,jsonb)']::text[];   -- dropped and made again with more to answer (the same arguments)
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_note      text := '';
  v_rest text;
  v_npc  text;
  v_moved jsonb;
  v_me   uuid;
  v_fl   uuid;
  v_r    jsonb;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_new) u(q) where to_regprocedure(u.q) is not null and not (u.q = any (c_gone))) then
    raise exception '0510 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || c_gone) u(q) where to_regprocedure(u.q) is null) then
    raise exception '0510 refuses: a function it cuts is not in this world: %', (select string_agg(u.q, ' ') from unnest(c_hunked || c_gone) u(q) where to_regprocedure(u.q) is null);
  end if;
  create temp table want_0510 (code text primary key, was int, now int, wave int) on commit drop;
  insert into want_0510 values
    ('MED', 1, 1, 0), ('NEA', 1, 1, 0), ('NOR-EU', 1, 1, 0), ('BAL', 1, 1, 0), ('AEG', 1, 1, 0), ('BAY', 1, 1, 0), ('ENG', 1, 1, 0), ('ADR', 1, 1, 0),
    ('SEA', 1, 1, 0), ('ION', 1, 1, 0), ('IRI', 1, 1, 0), ('BLA', 1, 1, 0), ('NOR-MAC', 2, 2, 10), ('NRW', 2, 1, 8), ('GUL', 3, 2, 12), ('WHI', 3, 1, 10),
    ('SOU-ANG', 3, 2, 12), ('BAR', 3, 1, 12), ('ARC', 3, 8, 20), ('NOR-ICE', 3, 3, 20), ('SOU-BRA', 4, 4, 12), ('CAR', 4, 3, 12), ('GCO', 4, 3, 10), ('NOR-AM', 4, 3, 12),
    ('GCE', 4, 3, 12), ('NOR-DOL', 4, 4, 24), ('NOR-MID', 4, 3, 30), ('MOZ', 5, 2, 12), ('IND-EAF', 5, 2, 12), ('SOU-CAPE', 5, 2, 44), ('IND-S', 5, 2, 44), ('PER', 6, 5, 10),
    ('RED', 6, 5, 10), ('ARA', 6, 5, 12), ('LAC', 6, 5, 12), ('GLF', 6, 5, 12), ('GAN', 6, 5, 12), ('IND-E', 6, 5, 40), ('KOR', 7, 6, 12), ('SOA', 7, 6, 12),
    ('EAS', 7, 6, 12), ('SET', 7, 6, 8), ('TAI', 7, 6, 12), ('GND', 7, 6, 10), ('YEL', 7, 6, 10), ('STR', 7, 6, 10), ('NRT-JP', 7, 6, 16), ('BYF', 7, 5, 12),
    ('JAV', 7, 6, 12), ('VIS', 7, 6, 12), ('AND', 7, 6, 12), ('MAK', 7, 6, 12), ('MOL', 7, 6, 12), ('BAN', 7, 6, 16), ('TIM', 7, 7, 16), ('SFJ', 7, 6, 16),
    ('GIN', 7, 6, 10), ('PHI-JP', 7, 6, 12), ('NRT-AM', 8, 8, 12), ('STH-AM', 8, 8, 12), ('PHI', 8, 8, 50), ('TAS', 8, 7, 56), ('NRT-OPEN', 8, 8, 70), ('STH-OPEN', 8, 8, 70);
  if exists (select 1 from want_0510 t full join public.sea_zones z on z.code = t.code
              where z.code is null or t.code is null or z.title_min <> t.was or z.wave_min <> t.wave) then
    raise exception '0510 refuses: the seas are not the table the rungs were approved on: %',
      (select string_agg(coalesce(t.code, z.code), ' ') from want_0510 t full join public.sea_zones z on z.code = t.code
        where z.code is null or t.code is null or z.title_min <> t.was or z.wave_min <> t.wave);
  end if;
  select md5(string_agg(z.code || z.name || z.wave_min || z.ord, ',' order by z.code)) into v_rest from public.sea_zones z;
  select md5(string_agg(q.fleet_id::text || ':' || to_jsonb(w)::text, ',' order by q.fleet_id)) into v_npc
    from (select nf.fleet_id from public.npc_fleets nf order by nf.fleet_id limit 200) q cross join lateral public.npc_sea_floor(q.fleet_id) w;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_gone) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE RULES ──
  alter table public.sea_zones add column title_was integer;
  comment on column public.sea_zones.title_was is '0510: the level this sea asked before the seas were ordered by continent. Read for merchants'' home waters (public.sea_judge) and for what a company founded before 0510 keeps (public.seas_kept). Null: a sea made since.';
  update public.sea_zones set title_was = title_min;
  update public.sea_zones z set title_min = t.now from want_0510 t where t.code = z.code and z.title_min <> t.now;
  insert into public.world_config (key, value, description) values
    ('seas_by_continent_at', to_jsonb(now()),
     '0510: when the seas were ordered by continent. A company founded before it keeps every sea the old levels open to her (public.seas_kept). Moved back to a date before every company, nobody keeps one.');
  v_moved := public.sea_leg_asks_keep();

  drop function public.sea_floor(uuid, jsonb);
  execute $f$
create function public.sea_floor(p_fleet uuid, p_course jsonb, out title_min integer, out wave_min integer, out home_title integer, out home_wave integer, out zone text, out home_zone text)
returns record
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0396: THE WAY HOME AND HOME WATERS. Two seas a fleet is never a stranger in, and what each asks:
--   title_min, wave_min     the sea she LIES in: the zone of the harbour she lies at, else of where she rides (never the course she proposes: a
--                           course is the client's)
--   home_title, home_wave   the sea of her company's CAPITAL: the capital of the country she sails for now (public.nations.capital_port_code)
-- public.sea_judge reads them: a sea that asks the SAME TITLE as either of the two never asks her title, and asks her hull no more than that sea
-- asked. So a fleet lying in a far sea keeps the waters of that sea's rank (the way home), and a company founded far from Europe trades her home
-- region from her first day (home waters). Seas of another rank are judged on her own title and hull, as before: neither floor opens the map.
-- 0510: zone and home_zone, the two seas' codes (the last two answers).
-- Nulls where no zone is found (nothing is added to what she holds).
declare
  v_zone text;
  f      record;
begin
  if p_fleet is not null then
    select fl.port_id, fl.lat, fl.lon, fl.player_id into f from public.fleets fl where fl.id = p_fleet;
    if f.port_id is not null then
      v_zone := (select a.zones[1] from public.sea_leg_asks a where a.from_port = f.port_id and a.to_port = f.port_id);
    elsif f.lat is not null and f.lon is not null then
      v_zone := public.sea_zone_at(f.lat::float8, f.lon::float8);
    end if;
    select z.title_min, z.wave_min, z.code into home_title, home_wave, home_zone
      from public.players pl
      join public.nations n on n.id = pl.nation_id
      join public.ports cap on cap.code = n.capital_port_code
      join public.sea_leg_asks a on a.from_port = cap.id and a.to_port = cap.id
      join public.sea_zones z on z.code = a.zones[1]
     where pl.id = f.player_id;
  end if;
  -- no fleet to place (a question asked of a course alone): where the course starts
  if v_zone is null and p_fleet is null and p_course is not null and jsonb_typeof(p_course) = 'array' and jsonb_array_length(p_course) > 0
     and jsonb_typeof(p_course -> 0) = 'array' and jsonb_array_length(p_course -> 0) = 2 then
    v_zone := public.sea_zone_at((p_course -> 0 ->> 0)::float8, (p_course -> 0 ->> 1)::float8);
  end if;
  select z.title_min, z.wave_min, z.code into title_min, wave_min, zone from public.sea_zones z where z.code = v_zone;
end
$body$
  $f$;
  revoke all on function public.sea_floor(uuid, jsonb) from public, anon, authenticated, service_role;
  comment on function public.sea_floor(uuid, jsonb) is
    '0396 (the way home), 0510 (the two zones): the sea a fleet lies in and her capital''s sea, and what each asks.';
  execute $f$
create function public.seas_kept(p_fleet uuid)
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0510: WHAT SHE COULD REACH STAYS HERS. The seas whose OLD level (sea_zones.title_was) opens them to this fleet and whose new one might not, for a company
  -- founded before the seas were ordered by continent (seas_by_continent_at). Asked of the one rule (public.sea_refusal) with her level moved by what the sea's
  -- ask moved, so "her level against the old ask" is the very comparison it makes; her old home rank (the seas that asked what her capital's sea asked, 0396) as
  -- 0396 judged it. A merchant, a company founded since, no fleet: none.
  select coalesce(array_agg(z.code order by z.code), '{}'::text[])
    from (select public.title_level(pl.id) as title, public.fleet_wave(f.id) as wave, hz.title_was as home_was, hz.title_min as home_now, hz.wave_min as home_wave
            from public.fleets f
            join public.players pl on pl.id = f.player_id and not pl.is_npc
             and pl.created_at < (public.wc('seas_by_continent_at') #>> '{}')::timestamptz
            left join public.nations n on n.id = pl.nation_id
            left join public.ports cap on cap.code = n.capital_port_code
            left join public.sea_leg_asks a on a.from_port = cap.id and a.to_port = cap.id
            left join public.sea_zones hz on hz.code = a.zones[1]
           where f.id = p_fleet
          offset 0) h
    join public.sea_zones z on z.title_min > z.title_was or (z.title_was = h.home_was and z.title_min is distinct from h.home_now)
   where public.sea_refusal(case when z.title_was = h.home_was then greatest(h.title, z.title_min) else h.title + greatest(z.title_min - z.title_was, 0) end,
                            case when h.wave is not null then greatest(h.wave, case when z.title_was = h.home_was then h.home_wave end) end,
                            array[z.code]) is null
$body$
  $f$;
  revoke all on function public.seas_kept(uuid) from public, anon, authenticated, service_role;
  comment on function public.seas_kept(uuid) is
    '0510: the seas the levels before 0510 open to this fleet that the new ones might not (a company founded before 0510). Server only.';
  execute $f$
create function public.sea_closed(p_player uuid, p_fleet uuid)
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0510: THE SEAS SHUT TO HER NOW, in requirement order: every sea asked alone of public.sea_judge with her two floors (public.sea_floor), less the ones she
  -- keeps (public.seas_kept). Nothing is compared here. Whatever the switch says: its callers read that.
  select coalesce(array_agg(z.code order by z.ord), '{}'::text[])
    from (select public.title_level(p_player) as title, public.fleet_wave(p_fleet) as wave, public.seas_kept(p_fleet) as kept offset 0) h
   cross join (select * from public.sea_floor(p_fleet, null) offset 0) fl
    join public.sea_zones z on z.code <> all (h.kept)
   where public.sea_judge(h.title, h.wave, array[z.code], fl.title_min, fl.wave_min, fl.home_title, fl.home_wave) is not null
$body$
  $f$;
  revoke all on function public.sea_closed(uuid, uuid) from public, anon, authenticated, service_role;
  comment on function public.sea_closed(uuid, uuid) is
    '0510: the seas shut to this fleet now (public.sea_judge a sea, less public.seas_kept), in requirement order. Server only.';

  -- ── 3. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0510 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0510 values
  ('public.sea_judge(integer,numeric,text[],integer,integer,integer,integer)', 1,
$h$where z.code = any (coalesce(p_zones, '{}'::text[])) and z.title_min is distinct from p_lie_title and z.title_min is distinct from p_home_title)),$h$,
$h$where z.code = any (coalesce(p_zones, '{}'::text[]))
                  -- 0510: a merchant (no title) keeps the groups of the seas as they were before it
                  and (case when p_title is null then coalesce(z.title_was, z.title_min) else z.title_min end) is distinct from p_lie_title and (case when p_title is null then coalesce(z.title_was, z.title_min) else z.title_min end) is distinct from p_home_title)),$h$),
  ('public.sea_judge(integer,numeric,text[],integer,integer,integer,integer)', 2,
$h$(select array_agg(z.code) from public.sea_zones z where z.code = any (coalesce(p_zones, '{}'::text[])) and z.title_min = p_lie_title)),$h$,
$h$(select array_agg(z.code) from public.sea_zones z where z.code = any (coalesce(p_zones, '{}'::text[])) and (case when p_title is null then coalesce(z.title_was, z.title_min) else z.title_min end) = p_lie_title)),$h$),
  ('public.sea_judge(integer,numeric,text[],integer,integer,integer,integer)', 3,
$h$and z.title_min = p_home_title and z.title_min is distinct from p_lie_title))) as x) r$h$,
$h$and (case when p_title is null then coalesce(z.title_was, z.title_min) else z.title_min end) = p_home_title and (case when p_title is null then coalesce(z.title_was, z.title_min) else z.title_min end) is distinct from p_lie_title))) as x) r$h$),
  ('public.npc_sea_floor(uuid)', 1,
$h$  select public.fleet_wave(p_fleet), fl.title_min, fl.wave_min, z.title_min, z.wave_min
$h$,
$h$  -- 0510: her groups are the seas' levels as they were (sea_zones.title_was): the continents' order is the companies'
  select public.fleet_wave(p_fleet), coalesce(lz.title_was, lz.title_min), fl.wave_min, coalesce(z.title_was, z.title_min), z.wave_min
$h$),
  ('public.npc_sea_floor(uuid)', 2,
$h$   cross join lateral public.sea_floor(f.id, null) fl
$h$,
$h$   cross join lateral public.sea_floor(f.id, null) fl
    left join public.sea_zones lz on lz.code = fl.zone
$h$),
  ('public.sea_gate(uuid,uuid,uuid,jsonb)', 1,
$h$  if cardinality(v_zones) = 0 then
$h$,
$h$  -- 0510: what she could reach before the seas were ordered by continent stays hers (public.seas_kept)
  v_zones := (select coalesce(array_agg(u.z), '{}'::text[]) from (select public.seas_kept(p_fleet) as k offset 0) h cross join unnest(v_zones) u(z) where u.z <> all (h.k));
  if cardinality(v_zones) = 0 then
$h$),
  ('public.sea_routes(uuid,integer,numeric,jsonb)', 1,
$h$           public.sea_judge(p_title, p_wave, array[z.code], fl.title_min, fl.wave_min, fl.home_title, fl.home_wave) as refusal
$h$,
$h$           case when z.code <> all (fl.kept)   -- 0510: the seas she keeps
                then public.sea_judge(p_title, p_wave, array[z.code], fl.title_min, fl.wave_min, fl.home_title, fl.home_wave) end as refusal
$h$),
  ('public.sea_routes(uuid,integer,numeric,jsonb)', 2,
$h$     cross join (select * from public.sea_floor(p_fleet, null) offset 0) fl),
$h$,
$h$     cross join (select q.*, public.seas_kept(p_fleet) as kept from public.sea_floor(p_fleet, null) q offset 0) fl),
$h$),
  ('public.sea_conditions_ready()', 1,
$h$             where (select public.sea_judge(l.title, l.wave, public.course_zones(l.course) || array_remove(array[public.harbour_zone(l.to_port)], null),
$h$,
$h$             -- 0510: less the seas she keeps (public.seas_kept)
             where (select public.sea_judge(l.title, l.wave, array(select u.z from unnest(public.course_zones(l.course) || array_remove(array[public.harbour_zone(l.to_port)], null)) u(z)
                                                                    where u.z <> all (public.seas_kept(l.fleet))),
$h$),
  ('world.sea_conditions()', 1,
$h$                                    where r.x is not null))
$h$,
$h$                                    where r.x is not null and z.code <> all (w.kept)))   -- 0510: the seas she keeps
$h$),
  ('world.sea_conditions()', 2,
$h$fl.home_title, fl.home_wave
                                                            from$h$,
$h$fl.home_title, fl.home_wave, public.seas_kept(f.id) as kept
                                                            from$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 1,
$h$  v_title int;
$h$,
$h$  v_title int;
  v_closed text[];   -- 0510: lit, the seas shut to her (public.sea_closed)
$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 2,
$h$    v_wave  := public.fleet_wave(p_fleet);
$h$,
$h$    v_wave  := public.fleet_wave(p_fleet);
    v_closed := public.sea_closed(p_player, p_fleet);   -- 0510: the door's own answer a sea; a pair is shut when one of its seas is
$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 3,
$h$    select array_agg(coalesce((v_title is null or s.title_min <= v_title or s.title_min = fl.title_min or s.title_min = fl.home_title) and (v_wave is null or s.wave_min <= greatest(v_wave, case when s.title_min = fl.title_min then fl.wave_min end, case when s.title_min = fl.home_title then fl.home_wave end)), true) order by a.i, b.j)
$h$,
$h$    select array_agg(coalesce(not s.zones && v_closed, true) order by a.i, b.j)
$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 4,
$h$    select array_agg(a.id = p_from or coalesce((v_title is null or s.title_min <= v_title or s.title_min = fl.title_min or s.title_min = fl.home_title) and (v_wave is null or s.wave_min <= greatest(v_wave, case when s.title_min = fl.title_min then fl.wave_min end, case when s.title_min = fl.home_title then fl.home_wave end)), true) order by a.i)
$h$,
$h$    select array_agg(a.id = p_from or coalesce(not s.zones && v_closed, true) order by a.i)
$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 5,
$h$     cross join (select * from public.sea_floor(p_fleet, null) offset 0) fl
      left join public.sea_leg_asks s on s.from_port = a.id and s.to_port = b.id;$h$,
$h$      left join public.sea_leg_asks s on s.from_port = a.id and s.to_port = b.id;   -- 0510: edges
$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 6,
$h$     cross join (select * from public.sea_floor(p_fleet, null) offset 0) fl
      left join public.sea_leg_asks s on s.from_port = a.id and s.to_port = a.id;$h$,
$h$      left join public.sea_leg_asks s on s.from_port = a.id and s.to_port = a.id;   -- 0510: harbours
$h$);

  for v_h in select h.fn from hunks_0510 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0510 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0510 refuses: hunk % of % is found % times in the live body, not once', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0510 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0510 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0510 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0510 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0510 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.prosecdef
                                          and p.provolatile = case when false then 'v' else 's' end) <> cardinality(c_new)
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0510 self-assert FAIL: a new function is reachable by a client or service_role, or is not of its declared kind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c
       where c.key <> all (array['seas_by_continent_at']::text[])) <> v_cfg_before then
    raise exception '0510 self-assert FAIL: a knob this file does not add moved';
  end if;

  -- ── 5. THE TABLE ──
  if exists (select 1 from want_0510 t full join public.sea_zones z on z.code = t.code
              where z.code is null or t.code is null or z.title_min <> t.now or z.title_was <> t.was or z.wave_min <> t.wave)
     or (select md5(string_agg(z.code || z.name || z.wave_min || z.ord, ',' order by z.code)) from public.sea_zones z) <> v_rest then
    raise exception '0510 self-assert FAIL: the seas are not the table, or something but a level moved';
  end if;
  if exists (select 1 from public.sea_leg_asks s
              join public.sea_leg_asks own on own.from_port = s.to_port and own.to_port = s.to_port
             cross join lateral (select max(z.wave_min) as w, max(z.title_min) as t from public.sea_zones z where z.code = any (s.zones || own.zones)) q
              where (s.wave_min, s.title_min) is distinct from (q.w, q.t)) then
    raise exception '0510 self-assert FAIL: a pair row does not ask the most its seas ask';
  end if;
  -- THE MERCHANTS: every floor is what it was
  if (select md5(string_agg(q.fleet_id::text || ':' || to_jsonb(w)::text, ',' order by q.fleet_id)) from (select nf.fleet_id from public.npc_fleets nf order by nf.fleet_id limit 200) q
        cross join lateral public.npc_sea_floor(q.fleet_id) w) is distinct from v_npc then
    raise exception '0510 self-assert FAIL: a merchant''s floors moved';
  end if;

  -- ── 6. THE PROBE (its own company; rolled back) ──
  begin
    v_me := public.new_house('00000000-0510-4000-8000-000000000001', 'Casa Mares 0510', 'PRT');
    select f.id into v_fl from public.fleets f where f.player_id = v_me;
    update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
    update public.players set created_at = now() + interval '1 day' where id = v_me;
    v_r := public.sea_gate(v_me, v_fl, (select p.id from public.ports p where p.code = 'LPA'), null);
    if public.title_level(v_me) <> 1 or v_r is null or v_r->'figures'->>'zone' <> 'NOR-MAC' or (v_r->'figures'->>'needs_title')::int <> 2
       or public.seas_kept(v_fl) <> '{}'::text[] or not ('ARC' = any (public.sea_closed(v_me, v_fl)))
       or 'MED' = any (public.sea_closed(v_me, v_fl)) then
      raise exception '0510 self-assert FAIL: a new company at level 1: Las Palmas %, kept %, closed %', v_r, public.seas_kept(v_fl), public.sea_closed(v_me, v_fl);
    end if;
    -- founded before: a sea whose old level was hers (planted on the Arctic, whose waves are planted at 0) is kept
    update public.players set created_at = now() - interval '1 day' where id = v_me;
    update public.sea_zones set title_was = 1, wave_min = 0 where code = 'ARC';
    if public.seas_kept(v_fl) <> array['ARC'] or 'ARC' = any (public.sea_closed(v_me, v_fl)) then
      raise exception '0510 self-assert FAIL: a sea the old levels opened to a company founded before is not kept: %', public.seas_kept(v_fl);
    end if;
    raise exception using errcode = 'ZX510', message = 'PROBE_ROLLBACK_0510';
  exception when sqlstate 'ZX510' then
    v_lived := true;
  end;
  if not v_lived or exists (select 1 from public.players p where p.company_name = 'Casa Mares 0510') then
    raise exception '0510 self-assert FAIL: the probe did not run to its end, or left something behind';
  end if;
  v_note := format('64 seas, %s with another level; the pair table: %s', (select count(*) from public.sea_zones z where z.title_min <> z.title_was), v_moved);

  if clock_timestamp() - v_t0 > interval '60 seconds' then
    raise exception '0510 self-assert FAIL: the file took % (budget 60 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0510 self-assert ok: THE SEAS BY CONTINENT (dark: the switch not moved). Every hunk once and reversing; no other function or knob moved; the merchants keep their groups; a new company is asked the new levels, one founded before keeps what the old ones opened. %. % ms.', v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;

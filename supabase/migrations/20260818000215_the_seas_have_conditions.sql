-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0215 — THE SEAS HAVE CONDITIONS  (docs/SEA_CONDITIONS_AND_REGIONS.md, slice S1: the data and the readings,
--        DARK — every sea is a zone with a title and a wave resistance; every hull has a wave resistance; the
--        gear adds to it; the fleet averages it; the title is derived; the one rule and the one gatherer exist
--        and answer null while `sea_conditions_bite` is false)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, 2026-10-20 ───────────────────────────────────────────────────────────────────────
--   "lets start by applying the design you've created first, then consider adding more."
--   Far seas are limited the way 대항해시대 오리진 does it: each sea has ENTRY CONDITIONS, a captain level (the
--   TITLE) plus the fleet-average WAVE RESISTANCE (내파). The ship class gives the stat; anchors, planking and
--   sheathing add to it. Hard wall at plan time and at departure (slice S2); the map shades the closed seas
--   (client C3). Every default of the design's §7 is accepted: the title is the lower of Trading and
--   Exploration capped at 11; the numbers are the design's as written.
--
-- ── WHAT SAYS THE OPPOSITE TODAY, NAMED ─────────────────────────────────────────────────────────
--   * players.title_level (0004): a stored counter moved by nothing, served raw by world.player() (0014) — every
--     house reads 1 for ever. DROPPED here; the title is DERIVED (public.title_level) and world.player() is re-cut.
--   * Nothing else: no sea has a requirement, no hull has a wave figure, no gear adds one. 0107's region gate
--     (regions.min_exploration_level, E_REGION_CLOSED) is the second answer to "is this place open to her" and
--     is retired IN S2, together with the composed passage gate — not here (S1 changes no gate).
--
-- ── WHAT THIS FILE DOES (one authority per concept — docs/SEA_CONDITIONS_AND_REGIONS.md §1) ──────
--   (1) public.sea_zones (64 rows, requirement order = ord) and public.sea_zone_boxes (67: the lat/lon boxes that
--       cut the oceans, one REST box per raster sea), public.title_names (11) — DATA, authored in
--       data/sea-zones.json and held to it by scripts/db/world-guard.mjs, both directions.
--   (2) public.sea_zone_cells — the 0040 sea raster's cells answered as ZONES (one byte per 0.25° cell, 720 rows
--       × 1,440 columns), DERIVED here from sea_cells + the boxes; every water cell gets a zone (asserted: the
--       water count equals the zoned count). public.sea_cell_row / sea_cell_col are the one cell address
--       (0040's arithmetic, written once for the zone readers; voyage.sea_at keeps its own and the self-assert
--       holds the two rasters to the same sea at every roadstead and on 2,000 cells).
--   (3) The readings: public.sea_zone_at(lat, lon) → zone code; public.harbour_zone(port) at its roadstead;
--       public.course_zones(course) sampling every segment every `sea_sample_nm` (30 nm) — the vertices alone
--       miss the mid-Atlantic (asserted on the prod course Bristol → Cape Coast); public.sea_leg_asks
--       (from, to, wave_min, title_min) — 238² rows DERIVED by public.sea_leg_asks_derive() from the straight
--       line between the two roadsteads plus the destination's zone (the desk's Dijkstra has distances, not
--       courses; S2's reach_passage reads it).
--   (4) ship_classes.wave — DERIVED, 12 × size + rig (square +3, mixed +1, lateen 0, oared −6) + role (explorer
--       +2), asserted for every class; the same rule lives in scripts/lib/world-derive.mjs for the data files and
--       the guard. world.ship_stats gains ONE base row ('wave', c.wave) in each of its two branches, so
--       world.ship_stat(ship, 'wave') sums the gear exactly as it sums armour (worn, perks, sets, floors).
--   (5) item_effects 'wave' rows — 65, for the eight families (anchors, sheet anchors, storm canvas, planking,
--       sheathing, pumps, ballast) and two refits (Doubled Frames, Raised Forecastle), by (base type, grade):
--       scripts/build-gear.mjs WAVE_BY_BASE, pasted (`--sql-0215`); the CHECK on stat gains 'wave'. The world
--       guard holds the rows to the generator.
--   (6) public.fleet_wave(fleet) = floor(avg(world.ship_stat(hull, 'wave'))); null for an empty fleet.
--   (7) public.title_level(player) = least(trading level, exploration level) capped title_max; null for nobody
--       and for a merchant. public.title_names (level, name).
--   (8) public.sea_refusal(title, wave, zones[]) — THE ONE RULE: the first zone in requirement order whose
--       title_min > title (skipped when title is null) or wave_min > wave (skipped when wave is null) refuses
--       E_SEA_CLOSED with figures {zone, zone_name, needs_title, title, needs_wave, wave}; else null.
--       public.sea_gate(player, fleet, dest, course) — THE GATHERER: harbour_zone(dest) ∪ course_zones(course)
--       asked of the rule; NULL while sea_conditions_bite is false; null for nobody.
--   (9) world.sea_conditions() — a registered READ (client_rpc_entry_points + grant): the zones with their asks
--       and boxes, the titles, the caller's title, each of her fleets' wave, the switch. world.fleets() serves
--       `wave` per fleet (public.fleet_wave) and world.ship_view() `wave` per hull (one hunk each).
--  (10) Knobs: sea_conditions_bite false, sea_sample_nm 30, title_max 11.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
--   Change any gate: voyage.sail_refusal, public.passage_gate, cmd.issue_lines, cmd.standing_route_save_for,
--   voyage.reach_passage, world.good_board and the merchant planner are untouched (S2/S3). Touch hazards, piracy,
--   seas.danger_level or the sea raster's key. Add ice-breaking, breakthrough or rowing (a later addition: the
--   stat seam is one base row in world.ship_stats and one column, so a second stat is one more of each).
--   Change what a hull's ten stats read: asserted to the digit on every hull of the world.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
--   New tables (no lock on a live table); ALTER TABLE ship_classes ADD COLUMN (103 rows; ACCESS EXCLUSIVE for
--   milliseconds), ALTER item_effects CHECK (606 rows), ALTER players DROP COLUMN (838 rows; the column is read by
--   nothing after the re-cut). CREATE OR REPLACE ×5 by hunks. The zone raster (1,036,800 cells) and the 56,644
--   leg asks are computed here, set-based, seconds on prod (timed in the receipt). The probe company is made in a
--   sub-transaction rolled back whole.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0211, LF-normalised, each asserted to occur
-- exactly once and to reverse to its pre-image, ACL / volatility / definer / config unchanged):
--   world.ship_stats(uuid) (2 hunks: the 'wave' base row, both branches), world.ship_view(uuid) (1: `wave` per
--   hull), world.fleets() (1: `wave` per fleet), world.player() (1: title_level derived + title_name),
--   public.client_rpc_entry_points() (1: world.sea_conditions registered).
--
-- SELF-ASSERT (docs/SEA_CONDITIONS_AND_REGIONS.md §6, S1): every class's wave equals the derivation; every item
-- of the nine base types has a 'wave' row and no other item does (65); world.ship_stats of EVERY hull unchanged
-- on the ten old stats, to the digit, and `wave` = class + mounted; fleet_wave of a probe nau + 2 barcas = 21;
-- title_level = min of the two levels for every human and null for a merchant; sea_zone_at at every harbour's
-- roadstead names a zone and every harbour resolves, in the sea voyage.sea_at names; course_zones samples what the
-- vertices miss (a two-vertex Lisbon → Havana line crosses Macaronesia, the Western Ocean and the American shore, its
-- vertices name two zones) and the prod course Bristol → Cape Coast crosses the Doldrums and the Gulf of Guinea (it
-- hugs the coast; the design's "it crosses the Western Ocean" was read wrong — see the dev-log); sea_refusal(1, 12,
-- {NOR-MID}) refuses with the four figures and
-- (4, 30, {NOR-MID}) is clear; sea_leg_asks LIS → HAV reads wave 30 / title 4; sea_gate is null while dark and
-- refuses E_SEA_CLOSED the moment the switch is lit (flipped and rolled back inside the probe); the walls hold;
-- timings of the hot readers over 8 calls in this one session.
-- ROLLBACK (forward migration): reverse the five hunks (each OLD text is here verbatim), drop the new functions
-- and tables, drop ship_classes.wave, delete the 65 rows and restore the CHECK; players.title_level is not
-- restored (it was 1 for every house and read by nothing).
-- VERSION: 0215 (renumber to the prod head + 1 at push; 0212 insurance and 0213 haul cap are ahead, 0214 is the
-- stats tab).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0215(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table t0_0215 on commit drop as select clock_timestamp() as t0;

-- ── 1. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('sea_conditions_bite', 'false'::jsonb,
   '0215 (docs/SEA_CONDITIONS_AND_REGIONS.md): THE switch of the sea conditions for PLAYERS. false = public.sea_gate '
   'answers null (every reading is served, nothing refuses); true = the passage gate (S2) refuses E_SEA_CLOSED where '
   'a zone asks more title or wave resistance than she has. Merchants have their own switch (S3).'),
  ('sea_sample_nm', to_jsonb(30),
   '0215: how often a course is sampled, in nautical miles, for the zones it crosses (public.course_zones, '
   'public.sea_leg_asks_derive). The zone boxes are degrees wide; 30 nm (two raster cells) cannot miss one.'),
  ('title_max', to_jsonb(11),
   '0215: the highest title (public.title_level caps the lower of Trading and Exploration here). Eleven names in '
   'public.title_names; the seas ask 1–8 today.');

-- ── 2. THE ZONES, THEIR BOXES AND THE TITLES (data/sea-zones.json) ──────────────────────────────
create table public.sea_zones (
  code      text primary key check (code ~ '^[A-Z]{3}(-[A-Z]{1,4})?$'),
  name      text not null unique,
  title_min int  not null check (title_min between 1 and 11),
  wave_min  int  not null check (wave_min between 0 and 200),
  ord       int  not null unique check (ord >= 1)
);
comment on table public.sea_zones is
  '0215 (docs/SEA_CONDITIONS_AND_REGIONS.md §2): every zone of water and what it asks — a TITLE (public.title_level) '
  'and a WAVE resistance (public.fleet_wave). `ord` is the requirement order: public.sea_refusal names the first '
  'zone that refuses in this order. Authored in data/sea-zones.json; the world guard holds the rows to it.';

create table public.sea_zone_boxes (
  zone_code text    not null references public.sea_zones(code),
  sea_id    uuid    not null references public.seas(id),
  ord       int     not null check (ord >= 1),
  lat_min   numeric check (lat_min between -90 and 90),
  lat_max   numeric check (lat_max between -90 and 90),
  lon_min   numeric check (lon_min between -180 and 180),
  lon_max   numeric check (lon_max between -180 and 180),
  primary key (sea_id, ord),
  check (lat_min is null or lat_max is null or lat_min < lat_max),
  check (lon_min is null or lon_max is null or lon_min < lon_max)
);
comment on table public.sea_zone_boxes is
  '0215: the boxes that cut a raster sea (0040) into zones — half-open bounds [min, max) in degrees, a bound left '
  'null is unbounded, a box with no bounds is THE REST of its sea. Within a sea the boxes are tried in `ord` order, '
  'lowest first; every sea has exactly one rest box (its highest ord), so every water cell answers one zone.';

create table public.title_names (
  level int  primary key check (level between 1 and 11),
  name  text not null unique
);
comment on table public.title_names is '0215: the eleven title names, level 1 to title_max (data/sea-zones.json).';

insert into public.sea_zones (code, name, title_min, wave_min, ord) values
  ('MED', 'Mediterranean Sea', 1, 0, 1),
  ('NEA', 'North Sea', 1, 0, 2),
  ('NOR-EU', 'European Atlantic', 1, 0, 3),
  ('BAL', 'Baltic Sea', 1, 0, 4),
  ('AEG', 'Aegean Sea', 1, 0, 5),
  ('BAY', 'Bay of Biscay', 1, 0, 6),
  ('ENG', 'English Channel', 1, 0, 7),
  ('ADR', 'Adriatic Sea', 1, 0, 8),
  ('SEA', 'Sea of Marmara', 1, 0, 9),
  ('ION', 'Ionian Sea', 1, 0, 10),
  ('IRI', 'Irish Sea', 1, 0, 11),
  ('BLA', 'Black Sea', 1, 0, 12),
  ('NOR-MAC', 'Macaronesia and the Canary Current', 2, 10, 13),
  ('NRW', 'Norwegian Sea', 2, 8, 14),
  ('GUL', 'Gulf of Guinea', 3, 12, 15),
  ('WHI', 'White Sea', 3, 10, 16),
  ('SOU-ANG', 'Angola and the Skeleton Coast', 3, 12, 17),
  ('BAR', 'Barents Sea', 3, 12, 18),
  ('ARC', 'Arctic Ocean', 3, 20, 19),
  ('NOR-ICE', 'Iceland and Greenland waters', 3, 20, 20),
  ('SOU-BRA', 'Brazil and the Plate', 4, 12, 21),
  ('CAR', 'Caribbean Sea', 4, 12, 22),
  ('GCO', 'Gulf of Mexico', 4, 10, 23),
  ('NOR-AM', 'The American shore', 4, 12, 24),
  ('GCE', 'Gulf of Saint Lawrence', 4, 12, 25),
  ('NOR-DOL', 'The Doldrums', 4, 24, 26),
  ('NOR-MID', 'The Western Ocean', 4, 30, 27),
  ('MOZ', 'Mozambique Channel', 5, 12, 28),
  ('IND-EAF', 'East African coast', 5, 12, 29),
  ('SOU-CAPE', 'The Cape', 5, 44, 30),
  ('IND-S', 'The Roaring Forties', 5, 44, 31),
  ('PER', 'Persian Gulf', 6, 10, 32),
  ('RED', 'Red Sea', 6, 10, 33),
  ('ARA', 'Arabian Sea', 6, 12, 34),
  ('LAC', 'Laccadive Sea', 6, 12, 35),
  ('GLF', 'Gulf of Aden', 6, 12, 36),
  ('GAN', 'Gulf of Oman', 6, 12, 37),
  ('IND-E', 'The Indian Ocean crossing', 6, 40, 38),
  ('KOR', 'Korea Strait', 7, 12, 39),
  ('SOA', 'South China Sea', 7, 12, 40),
  ('EAS', 'East China Sea', 7, 12, 41),
  ('SET', 'Seto Inland Sea', 7, 8, 42),
  ('TAI', 'Taiwan Strait', 7, 12, 43),
  ('GND', 'Gulf of Thailand', 7, 10, 44),
  ('YEL', 'Yellow Sea', 7, 10, 45),
  ('STR', 'Strait of Malacca', 7, 10, 46),
  ('NRT-JP', 'Japan, Pacific side', 7, 16, 47),
  ('BYF', 'Bay of Bengal', 7, 12, 48),
  ('JAV', 'Java Sea', 7, 12, 49),
  ('VIS', 'Visayan Sea', 7, 12, 50),
  ('AND', 'Andaman Sea', 7, 12, 51),
  ('MAK', 'Makassar Strait', 7, 12, 52),
  ('MOL', 'Molucca Sea', 7, 12, 53),
  ('BAN', 'Banda Sea', 7, 16, 54),
  ('TIM', 'Timor Sea', 7, 16, 55),
  ('SFJ', 'Sea of Japan', 7, 16, 56),
  ('GIN', 'Gulf of Tonkin', 7, 10, 57),
  ('PHI-JP', 'The Kuroshio off Shikoku and Kyushu', 7, 16, 58),
  ('NRT-AM', 'Pacific Americas, north coast', 8, 12, 59),
  ('STH-AM', 'Pacific Americas, south coast', 8, 12, 60),
  ('PHI', 'Philippine Sea', 8, 50, 61),
  ('TAS', 'Tasman Sea', 8, 56, 62),
  ('NRT-OPEN', 'The North Pacific crossing', 8, 70, 63),
  ('STH-OPEN', 'The South Pacific and the Drake Passage', 8, 70, 64);

insert into public.sea_zone_boxes (zone_code, sea_id, ord, lat_min, lat_max, lon_min, lon_max)
select v.zone, s.id, v.ord, v.lat_min, v.lat_max, v.lon_min, v.lon_max
  from (values
  ('MED', 'MED', 1, null, null, null, null),
  ('NEA', 'NEA', 1, null, null, null, null),
  ('NOR-EU', 'NOR', 2, 30, null, -20, null),
  ('BAL', 'BAL', 1, null, null, null, null),
  ('AEG', 'AEG', 1, null, null, null, null),
  ('BAY', 'BAY', 1, null, null, null, null),
  ('ENG', 'ENG', 1, null, null, null, null),
  ('ADR', 'ADR', 1, null, null, null, null),
  ('SEA', 'SEA', 1, null, null, null, null),
  ('ION', 'ION', 1, null, null, null, null),
  ('IRI', 'IRI', 1, null, null, null, null),
  ('BLA', 'BLA', 1, null, null, null, null),
  ('NOR-MAC', 'NOR', 3, 10, 30, -30, -5),
  ('NOR-MAC', 'NOR', 4, 30, 45, -32, -20),
  ('NOR-MAC', 'NOR', 5, 10, 30, -5, null),
  ('NRW', 'NRW', 1, null, null, null, null),
  ('GUL', 'GUL', 1, null, null, null, null),
  ('WHI', 'WHI', 1, null, null, null, null),
  ('SOU-ANG', 'SOU', 1, -30, null, -20, null),
  ('BAR', 'BAR', 1, null, null, null, null),
  ('ARC', 'ARC', 1, null, null, null, null),
  ('NOR-ICE', 'NOR', 1, 58, null, null, -10),
  ('SOU-BRA', 'SOU', 3, -45, null, null, -20),
  ('CAR', 'CAR', 1, null, null, null, null),
  ('GCO', 'GCO', 1, null, null, null, null),
  ('NOR-AM', 'NOR', 6, 10, 58, null, -45),
  ('GCE', 'GCE', 1, null, null, null, null),
  ('NOR-DOL', 'NOR', 7, null, 10, null, null),
  ('NOR-MID', 'NOR', 8, null, null, null, null),
  ('MOZ', 'MOZ', 1, null, null, null, null),
  ('IND-EAF', 'IND', 1, -30, null, null, 60),
  ('SOU-CAPE', 'SOU', 2, null, -30, -40, null),
  ('IND-S', 'IND', 2, null, -30, null, null),
  ('PER', 'PER', 1, null, null, null, null),
  ('RED', 'RED', 1, null, null, null, null),
  ('ARA', 'ARA', 1, null, null, null, null),
  ('LAC', 'LAC', 1, null, null, null, null),
  ('GLF', 'GLF', 1, null, null, null, null),
  ('GAN', 'GAN', 1, null, null, null, null),
  ('IND-E', 'IND', 3, null, null, null, null),
  ('KOR', 'KOR', 1, null, null, null, null),
  ('SOA', 'SOA', 1, null, null, null, null),
  ('EAS', 'EAS', 1, null, null, null, null),
  ('SET', 'SET', 1, null, null, null, null),
  ('TAI', 'TAI', 1, null, null, null, null),
  ('GND', 'GND', 1, null, null, null, null),
  ('YEL', 'YEL', 1, null, null, null, null),
  ('STR', 'STR', 1, null, null, null, null),
  ('NRT-JP', 'NRT', 1, 20, 50, 120, 150),
  ('BYF', 'BYF', 1, null, null, null, null),
  ('JAV', 'JAV', 1, null, null, null, null),
  ('VIS', 'VIS', 1, null, null, null, null),
  ('AND', 'AND', 1, null, null, null, null),
  ('MAK', 'MAK', 1, null, null, null, null),
  ('MOL', 'MOL', 1, null, null, null, null),
  ('BAN', 'BAN', 1, null, null, null, null),
  ('TIM', 'TIM', 1, null, null, null, null),
  ('SFJ', 'SFJ', 1, null, null, null, null),
  ('GIN', 'GIN', 1, null, null, null, null),
  ('PHI-JP', 'PHI', 1, 24, null, 122, 142),
  ('NRT-AM', 'NRT', 2, -5, 50, -130, -70),
  ('STH-AM', 'STH', 1, -45, null, -90, null),
  ('PHI', 'PHI', 2, null, null, null, null),
  ('TAS', 'TAS', 1, null, null, null, null),
  ('NRT-OPEN', 'NRT', 3, null, null, null, null),
  ('STH-OPEN', 'STH', 2, null, null, null, null),
  ('STH-OPEN', 'SOU', 4, null, null, null, null)
  ) as v(zone, sea, ord, lat_min, lat_max, lon_min, lon_max)
  join public.seas s on s.code = v.sea;

insert into public.title_names (level, name) values
  (1, 'Apprentice'),
  (2, 'Mate'),
  (3, 'Master'),
  (4, 'Captain'),
  (5, 'Shipmaster'),
  (6, 'Commodore'),
  (7, 'Admiral'),
  (8, 'Grand Admiral'),
  (9, 'Sea Lord'),
  (10, 'Prince of the Seas'),
  (11, 'Legend of the Age');

do $$
declare v_n int; v_s int;
begin
  if (select count(*) from public.sea_zones) <> 64 then
    raise exception '0215 self-assert FAIL: % zones, not 64', (select count(*) from public.sea_zones);
  end if;
  if (select count(*) from public.sea_zone_boxes) <> 67 then
    raise exception '0215 self-assert FAIL: % boxes, not 67 (a sea code of data/sea-zones.json is not a sea)', (select count(*) from public.sea_zone_boxes);
  end if;
  -- every raster sea has exactly ONE rest box, and it is the sea's last
  select count(*), count(*) filter (where n = 1 and last_is_rest) into v_s, v_n
    from (select s.id,
                 (select count(*) from public.sea_zone_boxes b where b.sea_id = s.id
                    and b.lat_min is null and b.lat_max is null and b.lon_min is null and b.lon_max is null) as n,
                 (select b.lat_min is null and b.lat_max is null and b.lon_min is null and b.lon_max is null
                    from public.sea_zone_boxes b where b.sea_id = s.id order by b.ord desc limit 1) as last_is_rest
            from public.seas s) x;
  if v_s <> 51 or v_n <> 51 then
    raise exception '0215 self-assert FAIL: % of % seas have exactly one rest box, and it last', v_n, v_s;
  end if;
  if (select count(*) from public.title_names) <> public.wc_int('title_max') then
    raise exception '0215 self-assert FAIL: % title names for title_max %', (select count(*) from public.title_names), public.wc_int('title_max');
  end if;
end $$;

-- ── 3. THE ONE CELL ADDRESS, AND THE ZONE RASTER (derived from sea_cells + the boxes) ───────────
create function public.sea_cell_row(p_lat double precision)
returns int
language sql
immutable parallel safe
as $$ select least(719, greatest(0, floor((90 - p_lat) / 0.25)::int)) $$;

create function public.sea_cell_col(p_lon double precision)
returns int
language sql
immutable parallel safe
as $$ select ((floor((p_lon + 180) / 0.25)::int % 1440) + 1440) % 1440 $$;

comment on function public.sea_cell_row(double precision) is
  '0215: the 0.25° raster row of a latitude (0040''s arithmetic — voyage.sea_at keeps its own copy, and 0215 asserts the two rasters agree).';
comment on function public.sea_cell_col(double precision) is '0215: the 0.25° raster column of a longitude, wrapped.';

create table public.sea_zone_cells (
  row_idx int   primary key references public.sea_cells(row_idx),
  zones   bytea not null check (length(zones) = 1440)
);
comment on table public.sea_zone_cells is
  '0215: the sea raster (public.sea_cells, 0040) answered as ZONES — one byte per cell, the zone''s sea_zones.ord '
  '(0 = land, as the sea raster). DERIVED from sea_cells and sea_zone_boxes by 0215 (re-derived by any slice that '
  'moves a box); read by public.sea_zone_at. Never authored.';

create temp table boxes_0215 on commit drop as
select s.raster_ordinal as sea_ord, b.ord, z.ord as zone_ord,
       b.lat_min::float8 as lat_min, b.lat_max::float8 as lat_max, b.lon_min::float8 as lon_min, b.lon_max::float8 as lon_max
  from public.sea_zone_boxes b
  join public.seas s on s.id = b.sea_id
  join public.sea_zones z on z.code = b.zone_code;
create index on boxes_0215 (sea_ord, ord);

do $$
declare
  r      record;
  v      bytea;
  v_lat  float8;
begin
  for r in select c.row_idx, c.seas from public.sea_cells c order by c.row_idx loop
    v_lat := 90 - (r.row_idx + 0.5) * 0.25;   -- the cell's centre
    select decode(string_agg(lpad(to_hex(coalesce(
             (select b.zone_ord from boxes_0215 b
               where b.sea_ord = get_byte(r.seas, g.col)
                 and (b.lat_min is null or v_lat >= b.lat_min) and (b.lat_max is null or v_lat < b.lat_max)
                 and (b.lon_min is null or (g.col + 0.5) * 0.25 - 180 >= b.lon_min)
                 and (b.lon_max is null or (g.col + 0.5) * 0.25 - 180 < b.lon_max)
               order by b.ord limit 1), 0)), 2, '0'), '' order by g.col), 'hex')
      into v
      from generate_series(0, 1439) g(col);
    insert into public.sea_zone_cells (row_idx, zones) values (r.row_idx, v);
  end loop;
end $$;

do $$
declare v_water bigint; v_zoned bigint; v_ms numeric;
begin
  select count(*) filter (where get_byte(c.seas, g.col) > 0), count(*) filter (where get_byte(z.zones, g.col) > 0)
    into v_water, v_zoned
    from public.sea_cells c join public.sea_zone_cells z on z.row_idx = c.row_idx cross join generate_series(0, 1439) g(col);
  if (select count(*) from public.sea_zone_cells) <> 720 or v_water = 0 or v_water <> v_zoned then
    raise exception '0215 self-assert FAIL: % rows; % water cells, % zoned — a water cell answers no zone', (select count(*) from public.sea_zone_cells), v_water, v_zoned;
  end if;
  v_ms := extract(epoch from clock_timestamp() - (select t0 from t0_0215)) * 1000;
  raise notice '0215: zone raster built — % water cells of 1,036,800, every one zoned (% ms since the file began)', v_water, round(v_ms);
end $$;

-- ── 4. THE READINGS ────────────────────────────────────────────────────────────────────────────
create function public.sea_conditions_on()
returns boolean
language sql
stable
as $$
  -- 0215: THE switch, read as public.skills_bite_on reads its own: a plain SQL read of world_config, inlinable,
  -- missing row = off.
  select coalesce((select c.value = 'true'::jsonb from public.world_config c where c.key = 'sea_conditions_bite'), false)
$$;

create function public.sea_zone_at(p_lat double precision, p_lon double precision)
returns text
language sql
stable security definer
set search_path = public, pg_temp
as $$
  -- 0215: WHICH ZONE IS THIS POINT OF WATER IN — one byte of the zone raster; null on land or off the chart.
  select z.code
    from public.sea_zone_cells c
    join public.sea_zones z on z.ord = get_byte(c.zones, public.sea_cell_col(p_lon))
   where p_lat is not null and p_lon is not null and p_lat between -90 and 90
     and c.row_idx = public.sea_cell_row(p_lat)
$$;

create function public.harbour_zone(p_port uuid)
returns text
language sql
stable security definer
set search_path = public, pg_temp
as $$
  -- 0215: a harbour's zone is its ROADSTEAD's (sea_reaches, the water the sail door judges) — not ports.sea_id,
  -- the authored label, which disagrees with the raster at 16 of 238 harbours.
  select public.sea_zone_at(sr.roadstead_lat::float8, sr.roadstead_lon::float8)
    from public.sea_reaches sr where sr.port_id = p_port
$$;

create function public.course_zones(p_course jsonb)
returns text[]
language plpgsql
stable security definer
set search_path = public, pg_temp
as $$
-- 0215: THE ZONES A COURSE CROSSES — every vertex, and a sample every sea_sample_nm along each straight segment
-- (latitude linear, longitude the short way round through voyage.lon_lerp, as voyage.segments_from_course walks
-- it); a sample on land is ignored. Sampling only the vertices is wrong: merchant courses average 7 vertices a
-- leg and the mid-Atlantic hides between two of them (asserted below on Bristol → Cape Coast).
declare
  v_step numeric := public.wc_num('sea_sample_nm');
begin
  if p_course is null or jsonb_typeof(p_course) <> 'array' or jsonb_array_length(p_course) = 0 then
    return '{}'::text[];
  end if;
  return coalesce((
    with v as (
      select (e->>0)::float8 as lat, (e->>1)::float8 as lon, i
        from jsonb_array_elements(p_course) with ordinality t(e, i)
       where jsonb_typeof(e) = 'array' and jsonb_array_length(e) = 2),
    seg as (
      select a.lat as lat1, a.lon as lon1, b.lat as lat2, b.lon as lon2,
             greatest(1, ceil(voyage.gc_distance_nm(a.lat, a.lon, b.lat, b.lon) / v_step))::int as n
        from v a join v b on b.i = a.i + 1),
    pts as (
      select s.lat1 + (s.lat2 - s.lat1) * k / s.n as lat, voyage.lon_lerp(s.lon1, s.lon2, k::float8 / s.n) as lon
        from seg s cross join lateral generate_series(0, s.n) k
      union all
      select lat, lon from v)
    select array_agg(distinct q.z order by q.z)
      from (select public.sea_zone_at(p.lat, p.lon) as z from pts p) q
     where q.z is not null), '{}'::text[]);
end $$;

create function public.sea_leg_asks_derive(p_from uuid default null)
returns table (from_port uuid, to_port uuid, wave_min int, title_min int)
language sql
stable security definer
set search_path = public, pg_temp
as $$
  -- 0215: THE ONE DERIVATION of public.sea_leg_asks — for every ordered pair of harbours, the most any zone on the
  -- STRAIGHT line between the two roadsteads asks (sampled every sea_sample_nm, land ignored, the same rule as
  -- public.course_zones) joined with what the destination's own zone asks. A harbour to itself asks its zone's.
  -- With p_from: only the legs out of that harbour (a re-derivation check; the table is filled with none).
  with knob as (select public.wc_num('sea_sample_nm') as step),
  -- the whole zone raster as ONE bytea (720 rows × 1,440 bytes), read once: a sample is one get_byte, no join
  raster as (select string_agg(c.zones, ''::bytea order by c.row_idx) as cells from public.sea_zone_cells c),
  h as (
    select p.id, p.code, sr.roadstead_lat::float8 as lat, sr.roadstead_lon::float8 as lon, public.harbour_zone(p.id) as zone
      from public.ports p join public.sea_reaches sr on sr.port_id = p.id
     where p.kind = 'HARBOUR'),
  pairs as (
    select a.id as a_id, b.id as b_id, a.lat as lat1, a.lon as lon1, b.lat as lat2, b.lon as lon2,
           greatest(1, ceil(voyage.gc_distance_nm(a.lat, a.lon, b.lat, b.lon) / (select step from knob)))::int as n
      from h a join h b on a.code < b.code
     where p_from is null or a.id = p_from or b.id = p_from),
  samples as (
    select p.a_id, p.b_id,
           get_byte((select cells from raster),
                    public.sea_cell_row(p.lat1 + (p.lat2 - p.lat1) * k / p.n) * 1440
                    + public.sea_cell_col(voyage.lon_lerp(p.lon1, p.lon2, k::float8 / p.n))) as z
      from pairs p
     cross join lateral generate_series(0, p.n) k),
  crossed as (
    select s.a_id, s.b_id, max(z.wave_min) as wave_min, max(z.title_min) as title_min
      from (select distinct a_id, b_id, z from samples where z > 0) s
      join public.sea_zones z on z.ord = s.z
     group by s.a_id, s.b_id),
  both_ways as (
    select c.a_id as f, c.b_id as t, c.wave_min, c.title_min from crossed c
    union all
    select c.b_id, c.a_id, c.wave_min, c.title_min from crossed c
    union all
    select h.id, h.id, null::int, null::int from h)
  select w.f, w.t, greatest(coalesce(w.wave_min, 0), z.wave_min)::int, greatest(coalesce(w.title_min, 1), z.title_min)::int
    from both_ways w
    join h on h.id = w.t
    join public.sea_zones z on z.code = h.zone
   where p_from is null or w.f = p_from
$$;

create table public.sea_leg_asks (
  from_port uuid not null,   -- references public.ports(id): added AFTER the fill, below
  to_port   uuid not null,
  wave_min  int  not null,
  title_min int  not null,
  primary key (from_port, to_port)
);
comment on table public.sea_leg_asks is
  '0215: what a harbour-to-harbour leg asks WITHOUT a course — the most any zone on the straight line between the '
  'two roadsteads asks, and the destination''s zone. DERIVED by public.sea_leg_asks_derive(); re-derived whenever a '
  'zone or a box moves; never hand-edited. Read by voyage.reach_passage (S2): the desk''s Dijkstra has distances, '
  'not courses.';

insert into public.sea_leg_asks (from_port, to_port, wave_min, title_min)
select d.from_port, d.to_port, d.wave_min, d.title_min from public.sea_leg_asks_derive() d;
-- the two references to the HOT `ports` table are added only now: a foreign key takes SHARE ROW EXCLUSIVE on the
-- table it references until commit, and declared in the CREATE above it would have stopped every write to ports
-- (the inn's crew pool, a hire) for the whole derivation (measured locally: ~112 s of the file's ~136 s).
alter table public.sea_leg_asks
  add constraint sea_leg_asks_from_port_fkey foreign key (from_port) references public.ports(id),
  add constraint sea_leg_asks_to_port_fkey   foreign key (to_port)   references public.ports(id);

create function public.fleet_wave(p_fleet uuid)
returns numeric
language sql
stable security definer
set search_path = public, pg_temp
as $$
  -- 0215: THE FLEET'S FIGURE — the floor of the average of her hulls' wave resistance (world.ship_stat: the class
  -- plus what is mounted). A nau and two barcas read 21: a mixed fleet is pulled down by its smallest hull. Null
  -- for a fleet with no hull (and for no fleet).
  select floor(avg(world.ship_stat(s.id, 'wave'))) from public.ships s where s.fleet_id = p_fleet
$$;

create function public.title_level(p_player uuid)
returns int
language plpgsql
stable security definer
set search_path = public, pg_temp
as $$
-- 0215: THE CAPTAIN LEVEL IS THE TITLE, and the title is DERIVED, never stored: the lower of her Trading and
-- Exploration levels (public.player_progress, 0069), capped at title_max. Null for nobody and for a merchant (a
-- merchant has no title; public.sea_refusal skips the title test on null). Combat joins the day it is playable.
declare
  v_npc boolean;
  v     jsonb;
begin
  if p_player is null then
    return null;
  end if;
  select p.is_npc into v_npc from public.players p where p.id = p_player;
  if v_npc is null or v_npc then
    return null;
  end if;
  v := public.player_progress(p_player);
  return least(public.wc_int('title_max'),
               least(coalesce((v->'trading'->>'level')::int, 1), coalesce((v->'exploration'->>'level')::int, 1)));
end $$;

create function public.sea_refusal(p_title int, p_wave numeric, p_zones text[])
returns jsonb
language sql
stable security definer
set search_path = public, pg_temp
as $$
  -- 0215: THE ONE RULE. Over the zones in requirement order, the first whose title_min is above her title (skipped
  -- when the title is null: a merchant) or whose wave_min is above her fleet's wave (skipped when null: a title-only
  -- ask) refuses E_SEA_CLOSED — a cmd.refusal with the four figures. Null when every zone is open to her.
  select cmd.refusal('E_SEA_CLOSED',
           format('%s asks title %s and wave resistance %s — %s', z.name, z.title_min, z.wave_min,
                  concat_ws(' and ',
                            case when p_title is not null then format('you are title %s', p_title) end,
                            case when p_wave is not null then format('your fleet holds %s', p_wave) end)),
           jsonb_build_object('zone', z.code, 'zone_name', z.name, 'needs_title', z.title_min, 'title', p_title,
                              'needs_wave', z.wave_min, 'wave', p_wave))
    from public.sea_zones z
   where z.code = any(coalesce(p_zones, '{}'::text[]))
     and ((p_title is not null and z.title_min > p_title) or (p_wave is not null and z.wave_min > p_wave))
   order by z.ord
   limit 1
$$;

create function public.sea_gate(p_player uuid, p_fleet uuid, p_dest uuid, p_course jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path = public, pg_temp
as $$
-- 0215: THE GATHERER. The zones a passage touches — the destination harbour's roadstead and every zone the course
-- crosses — asked of the one rule with her title and her fleet's wave. NULL while sea_conditions_bite is false
-- (S1 is dark: nothing refuses); null for nobody (the world's housekeeping acts for no house). A merchant's title
-- is null, so only her wave is judged (S3 asks this for every known leg).
declare
  v_zones text[];
  v_hz    text;
begin
  if p_player is null or not public.sea_conditions_on() then
    return null;
  end if;
  v_zones := public.course_zones(p_course);
  if p_dest is not null then
    v_hz := public.harbour_zone(p_dest);
    if v_hz is not null and not (v_hz = any(v_zones)) then
      v_zones := v_zones || v_hz;
    end if;
  end if;
  if cardinality(v_zones) = 0 then
    return null;
  end if;
  return public.sea_refusal(public.title_level(p_player), public.fleet_wave(p_fleet), v_zones);
end $$;

create function world.sea_conditions()
returns jsonb
language plpgsql
stable security definer
set search_path = public, pg_temp
as $$
-- 0215: THE SEA CONDITIONS, SERVED — every zone with what it asks and the boxes that cut it (the Codex "Seas"
-- face and the map's shading, C3), the title names, the caller's title, each of her fleets' wave, and whether the
-- conditions bite yet. The client prints these figures and derives none. Signed in with no house: the zones and
-- the names, no title, no fleets.
declare
  v_player uuid := public.current_player_id();
  v_title  int  := public.title_level(public.current_player_id());
begin
  return jsonb_build_object(
    'bite', public.sea_conditions_on(),
    'sample_nm', public.wc_num('sea_sample_nm'),
    'title', case when v_player is null then null
                  else jsonb_build_object('level', v_title,
                                          'name', (select t.name from public.title_names t where t.level = v_title),
                                          'max', public.wc_int('title_max')) end,
    'titles', (select coalesce(jsonb_agg(jsonb_build_object('level', t.level, 'name', t.name) order by t.level), '[]'::jsonb)
                 from public.title_names t),
    'zones', (select coalesce(jsonb_agg(jsonb_build_object(
                'code', z.code, 'name', z.name, 'title_min', z.title_min, 'wave_min', z.wave_min, 'ord', z.ord,
                'boxes', (select coalesce(jsonb_agg(jsonb_build_object(
                            'sea', s.code, 'ord', b.ord, 'lat_min', b.lat_min, 'lat_max', b.lat_max,
                            'lon_min', b.lon_min, 'lon_max', b.lon_max) order by b.ord), '[]'::jsonb)
                            from public.sea_zone_boxes b join public.seas s on s.id = b.sea_id
                           where b.zone_code = z.code)) order by z.ord), '[]'::jsonb)
                from public.sea_zones z),
    'fleets', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'wave', public.fleet_wave(f.id))
                                         order by f.created_at), '[]'::jsonb)
                 from public.fleets f where v_player is not null and f.player_id = v_player));
end $$;

-- THE WALLS: every public.* reader is server-only; the one registered read is the client's
revoke all on function public.sea_cell_row(double precision) from public, anon, authenticated;
revoke all on function public.sea_cell_col(double precision) from public, anon, authenticated;
revoke all on function public.sea_conditions_on() from public, anon, authenticated;
revoke all on function public.sea_zone_at(double precision, double precision) from public, anon, authenticated;
revoke all on function public.harbour_zone(uuid) from public, anon, authenticated;
revoke all on function public.course_zones(jsonb) from public, anon, authenticated;
revoke all on function public.sea_leg_asks_derive(uuid) from public, anon, authenticated;
revoke all on function public.fleet_wave(uuid) from public, anon, authenticated;
revoke all on function public.title_level(uuid) from public, anon, authenticated;
revoke all on function public.sea_refusal(int, numeric, text[]) from public, anon, authenticated;
revoke all on function public.sea_gate(uuid, uuid, uuid, jsonb) from public, anon, authenticated;
revoke all on function world.sea_conditions() from public, anon;
grant execute on function world.sea_conditions() to authenticated;
alter table public.sea_zones enable row level security;
alter table public.sea_zone_boxes enable row level security;
alter table public.sea_zone_cells enable row level security;
alter table public.sea_leg_asks enable row level security;
alter table public.title_names enable row level security;
revoke all on table public.sea_zones, public.sea_zone_boxes, public.sea_zone_cells, public.sea_leg_asks, public.title_names
  from public, anon, authenticated;

-- ── 5. THE SHIP'S WAVE RESISTANCE, DERIVED ─────────────────────────────────────────────────────
alter table public.ship_classes add column wave int;
update public.ship_classes c
   set wave = 12 * cp.size
            + case c.rig when 'square' then 3 when 'mixed' then 1 when 'lateen' then 0 when 'oared' then -6 end
            + case cp.role when 'explorer' then 2 else 0 end
  from public.class_profile cp
 where cp.class_code = c.code;
alter table public.ship_classes alter column wave set not null;
alter table public.ship_classes add constraint ship_classes_wave_check check (wave between 1 and 100);
comment on column public.ship_classes.wave is
  '0215 (docs/SEA_CONDITIONS_AND_REGIONS.md §3.1): the hull''s WAVE RESISTANCE, DERIVED — 12 × class_profile.size + '
  'rig (square +3, mixed +1, lateen 0, oared −6) + role (explorer +2); barca 12, caravel 26, nau 39, galleon 51, '
  'Indiaman 63, carrack of state 75. Re-derived and asserted by 0215 and by the world guard, so a hand-set value is '
  'seen. Read as a base row of world.ship_stats, so gear adds to it exactly as to armour.';

-- ── 6. WHAT THE GEAR ADDS (scripts/build-gear.mjs WAVE_BY_BASE, `--sql-0215`) ───────────────────
alter table public.item_effects drop constraint item_effects_stat_check;
alter table public.item_effects add constraint item_effects_stat_check
  check (stat in ('hold', 'speed', 'handling', 'draft', 'durability', 'armour', 'attack', 'accuracy', 'reach', 'sighting', 'wave'));
insert into public.item_effects (item_code, stat, delta) values
  ('admiralty-anchor', 'wave', 5),
  ('admiralty-copper', 'wave', 3),
  ('anchor-and-cable', 'wave', 2),
  ('ancla-de-la-esperanza', 'wave', 5),
  ('ballast', 'wave', 1),
  ('bar-iron-sheet-anchor', 'wave', 4),
  ('batavia-double-planking', 'wave', 6),
  ('bentinck-pumps', 'wave', 3),
  ('bilge-pumps', 'wave', 1),
  ('bower-and-sheet-anchors', 'wave', 6),
  ('brake-pumps', 'wave', 3),
  ('callao-copper-ballast', 'wave', 2),
  ('cast-kentledge', 'wave', 3),
  ('cedar-planking', 'wave', 5),
  ('chain-pumps', 'wave', 2),
  ('copper-bolted-sheathing', 'wave', 4),
  ('copper-chain-pumps', 'wave', 3),
  ('copper-fast-anchor', 'wave', 5),
  ('copper-fast-sheet-anchor', 'wave', 6),
  ('copper-sheathing', 'wave', 2),
  ('danzig-oak-planking', 'wave', 4),
  ('deal-planking', 'wave', 3),
  ('diagonal-planking', 'wave', 6),
  ('double-duck-storm-canvas', 'wave', 3),
  ('doubled-copper', 'wave', 2),
  ('doubled-frames-1', 'wave', 2),
  ('doubled-frames-2', 'wave', 3),
  ('genoese-anchor', 'wave', 3),
  ('greenheart-planking', 'wave', 6),
  ('greenheart-sheathing', 'wave', 4),
  ('hemp-storm-canvas', 'wave', 3),
  ('holland-storm-canvas', 'wave', 5),
  ('iron-kentledge', 'wave', 1),
  ('lastro-de-sal', 'wave', 2),
  ('lead-ballast', 'wave', 2),
  ('live-oak-and-copper', 'wave', 3),
  ('live-oak-planking', 'wave', 5),
  ('malabar-chain-pumps', 'wave', 2),
  ('manila-anchor', 'wave', 3),
  ('monsoon-teak-sheathing', 'wave', 3),
  ('oak-planking', 'wave', 4),
  ('osmund-anchor', 'wave', 3),
  ('osmund-sheet-anchor', 'wave', 4),
  ('pig-iron-ballast', 'wave', 2),
  ('pompes-du-ponant', 'wave', 3),
  ('raised-forecastle-1', 'wave', 2),
  ('raised-forecastle-2', 'wave', 3),
  ('red-seal-ballast', 'wave', 2),
  ('sailcloth-storm-canvas', 'wave', 4),
  ('sheet-anchor', 'wave', 3),
  ('storm-canvas', 'wave', 2),
  ('storm-trysails', 'wave', 5),
  ('surat-teak-sheathing', 'wave', 3),
  ('swedish-anchor', 'wave', 4),
  ('swedish-sheet-anchor', 'wave', 5),
  ('tablazon-de-galeon', 'wave', 5),
  ('teak-and-copper', 'wave', 3),
  ('teak-chain-pumps', 'wave', 2),
  ('teak-planking', 'wave', 4),
  ('tersane-anchor', 'wave', 4),
  ('trimmed-kentledge', 'wave', 3),
  ('turtle-back-plating', 'wave', 5),
  ('typhoon-canvas', 'wave', 4),
  ('zavorra-dell-arsenale', 'wave', 2),
  ('zheng-he-bulkheads', 'wave', 6);

-- ── 7. THE PRE-IMAGES AND THE HUNKS ─────────────────────────────────────────────────────────────
create temp table defs_before_0215 on commit drop as
select f.ord, f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values (1, 'world.ship_stats(uuid)'),
               (2, 'world.ship_view(uuid)'),
               (3, 'world.fleets()'),
               (4, 'world.player()'),
               (5, 'public.client_rpc_entry_points()')) f(ord, fn);

create temp table hunks_0215 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0215 values
('world.ship_stats(uuid)', 1,
$h$('sighting',   c.sighting::numeric)) b(stat, base)
      left join d on d.stat = b.stat$h$,
$h$('sighting',   c.sighting::numeric),
                                ('wave',       c.wave::numeric)) b(stat, base)   -- 0215: + wave resistance, summed as the rest
      left join d on d.stat = b.stat$h$),
('world.ship_stats(uuid)', 2,
$h$('sighting',   c.sighting::numeric)) b(stat, base)
    left join d on d.stat = b.stat$h$,
$h$('sighting',   c.sighting::numeric),
                              ('wave',       c.wave::numeric)) b(stat, base)   -- 0215: + wave resistance, summed as the rest
    left join d on d.stat = b.stat$h$),
('world.ship_view(uuid)', 1,
$h$           'sighting', x.st->'sighting',
$h$,
$h$           'sighting', x.st->'sighting',
           'wave', x.st->'wave',   -- 0215: her wave resistance (world.ship_stats, the one computation)
$h$),
('world.fleets()', 1,
$h$    'free_hold', public.fleet_free_hold(f.id),
$h$,
$h$    'free_hold', public.fleet_free_hold(f.id),
    'wave', public.fleet_wave(f.id),   -- 0215: the fleet's wave resistance, the average of her hulls' (public.fleet_wave)
$h$),
('world.player()', 1,
$h$      'title_level',   v_row.title_level,
$h$,
$h$      'title_level',   public.title_level(v_id),   -- 0215: DERIVED (the lower of Trading and Exploration, capped title_max); the column is gone
      'title_name',    (select t.name from public.title_names t where t.level = public.title_level(v_id)),
$h$),
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'insurance',             '')
    ) as t(s, f, a)$h$,
$h$      ('world',       'insurance',             ''),
      -- 0215: the sea conditions — every zone's asks, the caller's title, her fleets' wave (docs/SEA_CONDITIONS_AND_REGIONS.md S1).
      ('world',       'sea_conditions',        '')
    ) as t(s, f, a)$h$);

-- the pre-image of world.ship_stats under a pg_temp name, for the parity proof below
do $$
begin
  if (select count(*) from defs_before_0215 where def is not null) <> 5 then
    raise exception '0215 self-assert FAIL: % of the 5 bodies found', (select count(*) from defs_before_0215 where def is not null);
  end if;
  execute replace((select def from defs_before_0215 where ord = 1),
                  'CREATE OR REPLACE FUNCTION world.ship_stats(', 'CREATE OR REPLACE FUNCTION pg_temp.ship_stats_old_0215(');
end $$;

do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
  v_n   int := 0;
begin
  for d in select * from defs_before_0215 order by ord loop
    v_def := d.def;
    for h in select * from hunks_0215 where fn = d.fn order by n loop
      if pg_temp.occurs_0215(v_def, h.old) <> 1 then
        raise exception '0215 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0215(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0215 self-assert FAIL: % has no hunk', d.fn;
    end if;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0215 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0215(v_rev, h.new) <> 1 then
        raise exception '0215 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0215 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0215 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config', d.fn, d.acl, p.acl;
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n <> 5 then
    raise exception '0215 self-assert FAIL: % bodies re-cut, not 5', v_n;
  end if;
end $$;

-- ── 8. THE DEAD COLUMN GOES (read by nothing now: world.player() is re-cut above) ───────────────
alter table public.players drop column title_level;

-- ── 9. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0215-4000-8000-000000000001';
  v_out    text;
  v_n      int;
  v_bad    int;
  v_txt    text;
  v_player uuid;
  v_fleet  uuid;
  v_npc    uuid;
  v_lis    uuid;
  v_hav    uuid;
  v_brs    uuid;
  v_cap    uuid;
  v_course jsonb;
  v_real   boolean := false;
  v_zones  text[];
  v_vert   text[];
  v_ref    jsonb;
  v_hull   uuid;
  j_old    jsonb;
  j_new    jsonb;
  v_t0     timestamptz;
  v_ms     numeric;
  v_old    numeric[] := '{}';
  v_new    numeric[] := '{}';
  v_cz     numeric[] := '{}';
  v_fw     numeric[] := '{}';
  v_tl     numeric[] := '{}';
  v_asks   record;
  v_lvl    jsonb;
  v_humans int;
  v_i      int;
begin
  -- (a) every class's wave IS the derivation; the three live hulls read 12 / 26 / 39
  select count(*), count(*) filter (where c.wave <> 12 * cp.size
                                       + case c.rig when 'square' then 3 when 'mixed' then 1 when 'lateen' then 0 when 'oared' then -6 end
                                       + case cp.role when 'explorer' then 2 else 0 end)
    into v_n, v_bad
    from public.ship_classes c join public.class_profile cp on cp.class_code = c.code;
  if v_n < 100 or v_bad <> 0 or v_n <> (select count(*) from public.ship_classes) then
    raise exception '0215 self-assert FAIL: % classes, % off the derivation (% without a profile)', v_n, v_bad, (select count(*) from public.ship_classes) - v_n;
  end if;
  if (select wave from public.ship_classes where code = 'barca') <> 12
     or (select wave from public.ship_classes where code = 'carlat') <> 26
     or (select wave from public.ship_classes where code = 'nau') <> 39 then
    raise exception '0215 self-assert FAIL: barca / carlat / nau read % / % / %, not 12 / 26 / 39',
      (select wave from public.ship_classes where code = 'barca'), (select wave from public.ship_classes where code = 'carlat'),
      (select wave from public.ship_classes where code = 'nau');
  end if;

  -- (b) every item of the nine base types has a 'wave' row, no other item has one
  select count(*) filter (where ip.base_type in ('Anchor', 'Sheet Anchor', 'Storm Canvas', 'Planking', 'Sheathing', 'Bilge Pumps', 'Ballast', 'Doubled Frames', 'Raised Forecastle')
                            and not exists (select 1 from public.item_effects e where e.item_code = ip.item_code and e.stat = 'wave')),
         count(*) filter (where ip.base_type not in ('Anchor', 'Sheet Anchor', 'Storm Canvas', 'Planking', 'Sheathing', 'Bilge Pumps', 'Ballast', 'Doubled Frames', 'Raised Forecastle')
                            and exists (select 1 from public.item_effects e where e.item_code = ip.item_code and e.stat = 'wave'))
    into v_n, v_bad
    from public.item_profile ip;
  if v_n <> 0 or v_bad <> 0 then
    raise exception '0215 self-assert FAIL: % family items without a wave row, % other items with one', v_n, v_bad;
  end if;
  if (select count(*) from public.item_effects where stat = 'wave') <> 65
     or (select count(*) from public.item_effects where stat = 'wave' and delta <= 0) <> 0 then
    raise exception '0215 self-assert FAIL: % wave rows (65 expected), % not a buy',
      (select count(*) from public.item_effects where stat = 'wave'), (select count(*) from public.item_effects where stat = 'wave' and delta <= 0);
  end if;

  -- (c) EVERY HULL: the ten old stats unchanged to the digit, and `wave` = class + what is mounted
  select count(*),
         count(*) filter (where pg_temp.ship_stats_old_0215(s.id) is distinct from (world.ship_stats(s.id) - 'wave')),
         count(*) filter (where (world.ship_stats(s.id)->>'wave')::numeric is distinct from
                            greatest(0, c.wave + coalesce((select sum(case when f.wear > 0 and e.delta > 0 then public.worn_delta(e.delta, f.wear) else e.delta end)
                                                             from public.fitted_units f join public.item_effects e on e.item_code = f.item_code and e.stat = 'wave'
                                                            where f.ship_id = s.id), 0)))
    into v_n, v_bad, v_i
    from public.ships s join public.ship_classes c on c.id = s.class_id;
  if v_n = 0 or v_bad <> 0 or v_i <> 0 then
    raise exception '0215 self-assert FAIL: of % hulls, % changed one of the ten old stats and % read a wave that is not class + mounted', v_n, v_bad, v_i;
  end if;
  v_txt := format('%s hulls: ten stats unchanged, wave = class + mounted (%s carry a wave piece)', v_n,
                  (select count(distinct f.ship_id) from public.fitted_units f join public.item_effects e on e.item_code = f.item_code and e.stat = 'wave'));

  -- TIMING, 8 calls each in this one session (the generic-plan cliff is after the 5th): old body vs new on one hull
  select s.id into v_hull from public.ships s join public.players p on p.id = s.player_id where not p.is_npc order by s.created_at limit 1;
  if v_hull is null then select s.id into v_hull from public.ships s order by s.created_at limit 1; end if;
  for v_i in 1 .. 8 loop
    v_t0 := clock_timestamp(); j_old := pg_temp.ship_stats_old_0215(v_hull); v_old := v_old || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
    v_t0 := clock_timestamp(); j_new := world.ship_stats(v_hull);          v_new := v_new || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
  end loop;

  -- (d) every harbour's roadstead names a zone, in the sea voyage.sea_at names; 238 harbours resolve
  select count(*),
         count(*) filter (where public.harbour_zone(p.id) is null),
         count(*) filter (where not exists (select 1 from public.sea_zone_boxes b join public.sea_zones z on z.code = b.zone_code
                                             where z.code = public.harbour_zone(p.id)
                                               and b.sea_id = voyage.sea_at(sr.roadstead_lat::float8, sr.roadstead_lon::float8)))
    into v_n, v_bad, v_i
    from public.ports p join public.sea_reaches sr on sr.port_id = p.id where p.kind = 'HARBOUR';
  if v_n < 200 or v_bad <> 0 or v_i <> 0 then
    raise exception '0215 self-assert FAIL: % harbours, % without a zone, % whose zone is not a box of voyage.sea_at''s sea', v_n, v_bad, v_i;
  end if;
  v_txt := v_txt || format('; %s harbours resolve a zone of their raster sea', v_n);
  -- and the zone raster agrees with the box rule on 2,000 cells spread over the chart (every 518th cell)
  select count(*) filter (where z.zone is not null), count(*) filter (where z.zone is distinct from z.rule)
    into v_n, v_bad
    from (select public.sea_zone_at(90 - (q.i / 1440 + 0.5) * 0.25, ((q.i % 1440) + 0.5) * 0.25 - 180) as zone,
                 (select zz.code from public.sea_zone_boxes b join public.sea_zones zz on zz.code = b.zone_code
                   where b.sea_id = voyage.sea_at(90 - (q.i / 1440 + 0.5) * 0.25, ((q.i % 1440) + 0.5) * 0.25 - 180)
                     and (b.lat_min is null or 90 - (q.i / 1440 + 0.5) * 0.25 >= b.lat_min) and (b.lat_max is null or 90 - (q.i / 1440 + 0.5) * 0.25 < b.lat_max)
                     and (b.lon_min is null or ((q.i % 1440) + 0.5) * 0.25 - 180 >= b.lon_min) and (b.lon_max is null or ((q.i % 1440) + 0.5) * 0.25 - 180 < b.lon_max)
                   order by b.ord limit 1) as rule
            from generate_series(0, 1036799, 518) q(i)) z;
  if v_n < 500 or v_bad <> 0 then
    raise exception '0215 self-assert FAIL: on 2,000 sampled cells (% water) the zone raster disagrees with the box rule % time(s)', v_n, v_bad;
  end if;
  -- the home waters: Lisbon NOR-EU, the Azores NOR-MAC, Havana GCO, Cape Town SOU-CAPE, Honolulu NRT-OPEN, Guam PHI, Paramaribo NOR-DOL
  if (select string_agg(public.harbour_zone(p.id), ' ' order by p.code) from public.ports p where p.code in ('LIS', 'PON', 'HAV', 'CPT', 'HNL', 'HAG', 'PAR'))
     <> 'SOU-CAPE PHI GCO NRT-OPEN NOR-EU NOR-DOL NOR-MAC' then
    raise exception '0215 self-assert FAIL: the seven named harbours read %',
      (select string_agg(p.code || '=' || coalesce(public.harbour_zone(p.id), '-'), ' ' order by p.code) from public.ports p where p.code in ('LIS', 'PON', 'HAV', 'CPT', 'HNL', 'HAG', 'PAR'));
  end if;

  -- (e) course_zones. THE POSITIVE CONTROL for sampling (the vertex-only miss): a two-vertex Lisbon → Havana course —
  -- its vertices name only the European Atlantic and the Gulf of Mexico; sampled every 30 nm it crosses Macaronesia,
  -- the Western Ocean and the American shore. (The design named the prod course Bristol → Cape Coast for this; read
  -- on prod 2026-10-20 that course hugs the African coast — never west of 17.6° W — and its vertices already name every
  -- zone it crosses, so it is asserted below for what it IS: the Doldrums and the Gulf of Guinea, no Western Ocean.)
  v_course := (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                 from public.sea_reaches a, public.sea_reaches b where a.code = 'LIS' and b.code = 'HAV');
  for v_i in 1 .. 8 loop
    v_t0 := clock_timestamp(); v_zones := public.course_zones(v_course); v_cz := v_cz || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
  end loop;
  select array_agg(distinct z) into v_vert
    from (select public.sea_zone_at((e->>0)::float8, (e->>1)::float8) as z from jsonb_array_elements(v_course) e) q where z is not null;
  if not (v_zones @> array['NOR-EU', 'NOR-MAC', 'NOR-MID', 'NOR-AM', 'GCO']) or v_vert @> array['NOR-MID'] or cardinality(v_vert) <> 2 then
    raise exception '0215 self-assert FAIL: the Lisbon → Havana line sampled crosses %, its two vertices name % — the vertex-only miss is not shown', v_zones, v_vert;
  end if;
  v_txt := v_txt || format('; Lisbon → Havana sampled crosses %s, its vertices alone %s', v_zones, v_vert);
  select id into v_brs from public.ports where code = 'BRS';
  select id into v_cap from public.ports where code = 'CAP';
  select c.course into v_course from public.npc_courses c where c.from_port = v_brs and c.to_port = v_cap order by c.nm limit 1;
  if v_course is null then
    select s.course into v_course from public.standing_route_stops s join public.standing_route_stops s2 on s2.route_id = s.route_id and s2.ord = s.ord + 1
     where s.port_id = v_brs and s2.port_id = v_cap limit 1;
  end if;
  v_real := v_course is not null;
  if v_real then
    v_zones := public.course_zones(v_course);
    if not (v_zones @> array['NOR-EU', 'NOR-DOL', 'GUL']) then
      raise exception '0215 self-assert FAIL: the prod course Bristol → Cape Coast (% vertices) crosses % — not the Doldrums and the Gulf of Guinea', jsonb_array_length(v_course), v_zones;
    end if;
    v_txt := v_txt || format('; the prod course Bristol → Cape Coast (%s vertices) crosses %s', jsonb_array_length(v_course), v_zones);
  else
    v_txt := v_txt || '; no Bristol → Cape Coast course in this world';
  end if;
  if public.course_zones(null) <> '{}'::text[] or public.course_zones('[]'::jsonb) <> '{}'::text[] then
    raise exception '0215 self-assert FAIL: an empty course crosses something';
  end if;

  -- (f) the pure rule: (1, 12, {NOR-MID}) refuses with the four figures; (4, 30, {NOR-MID}) is clear; a null side is skipped
  v_ref := public.sea_refusal(1, 12, array['NOR-MID']);
  if v_ref is null or v_ref->>'code' <> 'E_SEA_CLOSED'
     or (v_ref->'figures'->>'needs_title')::int <> 4 or (v_ref->'figures'->>'title')::int <> 1
     or (v_ref->'figures'->>'needs_wave')::int <> 30 or (v_ref->'figures'->>'wave')::numeric <> 12
     or v_ref->'figures'->>'zone' <> 'NOR-MID' or v_ref->'figures'->>'zone_name' <> 'The Western Ocean'
     or v_ref->>'sentence' <> 'The Western Ocean asks title 4 and wave resistance 30 — you are title 1 and your fleet holds 12' then
    raise exception '0215 self-assert FAIL: sea_refusal(1, 12, NOR-MID) = %', v_ref;
  end if;
  if public.sea_refusal(4, 30, array['NOR-MID']) is not null then
    raise exception '0215 self-assert FAIL: title 4 and wave 30 are refused the Western Ocean';
  end if;
  if public.sea_refusal(null, 12, array['NOR-MID']) is null or public.sea_refusal(null, 30, array['NOR-MID']) is not null then
    raise exception '0215 self-assert FAIL: with no title (a merchant) the wave alone must decide';
  end if;
  if public.sea_refusal(3, null, array['NOR-MID']) is null or public.sea_refusal(4, null, array['NOR-MID']) is not null then
    raise exception '0215 self-assert FAIL: with no wave (a title-only ask) the title alone must decide';
  end if;
  -- the FIRST zone in requirement order is the one named (NOR-MAC, ord 13, before NOR-MID, ord 27)
  if public.sea_refusal(1, 12, array['NOR-MID', 'NOR-MAC'])->'figures'->>'zone' <> 'NOR-MAC' then
    raise exception '0215 self-assert FAIL: the refusal does not name the first zone in requirement order';
  end if;
  if public.sea_refusal(8, 100, (select array_agg(code) from public.sea_zones)) is not null then
    raise exception '0215 self-assert FAIL: title 8 and wave 100 are refused somewhere';
  end if;

  -- (g) sea_leg_asks: 238² rows; Lisbon → Havana asks wave 30 / title 4; a harbour to itself asks its own zone's
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_hav from public.ports where code = 'HAV';
  select count(*) into v_n from public.ports where kind = 'HARBOUR';
  if (select count(*) from public.sea_leg_asks) <> v_n * v_n then
    raise exception '0215 self-assert FAIL: % leg asks for % harbours (% expected)', (select count(*) from public.sea_leg_asks), v_n, v_n * v_n;
  end if;
  select * into v_asks from public.sea_leg_asks where from_port = v_lis and to_port = v_hav;
  if v_asks.wave_min <> 30 or v_asks.title_min <> 4 then
    raise exception '0215 self-assert FAIL: Lisbon → Havana asks wave % / title %, not 30 / 4', v_asks.wave_min, v_asks.title_min;
  end if;
  select * into v_asks from public.sea_leg_asks where from_port = v_lis and to_port = v_lis;
  if v_asks.wave_min <> 0 or v_asks.title_min <> 1 then
    raise exception '0215 self-assert FAIL: Lisbon to itself asks wave % / title %', v_asks.wave_min, v_asks.title_min;
  end if;
  -- no leg asks less than its destination's own zone
  select count(*) into v_bad
    from public.sea_leg_asks a join public.sea_zones z on z.code = public.harbour_zone(a.to_port)
   where a.wave_min < z.wave_min or a.title_min < z.title_min;
  if v_bad <> 0 then
    raise exception '0215 self-assert FAIL: % legs ask less than their destination''s zone', v_bad;
  end if;
  -- the derivation re-run is the table (every leg out of Lisbon: the same function, the same inputs)
  select count(*), count(*) filter (where d.wave_min is distinct from a.wave_min or d.title_min is distinct from a.title_min)
    into v_i, v_bad
    from public.sea_leg_asks a
    full join public.sea_leg_asks_derive(v_lis) d on d.from_port = a.from_port and d.to_port = a.to_port
   where coalesce(a.from_port, d.from_port) = v_lis;
  if v_i <> v_n or v_bad <> 0 then
    raise exception '0215 self-assert FAIL: % legs out of Lisbon re-derived (% expected), % differ from the stored asks', v_i, v_n, v_bad;
  end if;

  -- (h) title_level = min of the two levels for every human, null for a merchant; fleet_wave of nau + 2 barcas = 21;
  --     sea_gate null while dark, E_SEA_CLOSED the moment the switch is lit — all on probe rows, rolled back whole
  select count(*), count(*) filter (where public.title_level(p.id) is distinct from
           least(public.wc_int('title_max'), least((public.player_progress(p.id)->'trading'->>'level')::int, (public.player_progress(p.id)->'exploration'->>'level')::int)))
    into v_humans, v_bad
    from public.players p where not p.is_npc;
  if v_bad <> 0 then
    raise exception '0215 self-assert FAIL: % of % humans read a title that is not the lower of their two levels', v_bad, v_humans;
  end if;
  if (select count(*) filter (where public.title_level(p.id) is not null) from public.players p where p.is_npc) <> 0 then
    raise exception '0215 self-assert FAIL: a merchant has a title';
  end if;
  if public.title_level(null) is not null or public.title_level('00000000-0215-4000-8000-00000000dead') is not null then
    raise exception '0215 self-assert FAIL: nobody has a title';
  end if;
  begin
    v_player := public.new_house(c_uid, 'Casa 0215', 'PRT', 'LIS', 'Gaivota', 'barca', 'Gaivota 0215', 100000);
    select f.id into v_fleet from public.fleets f where f.player_id = v_player order by f.created_at limit 1;
    -- room for three hulls in one fleet (0107: fleet_ship_base + SEAMANSHIP)
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, 5 from public.skills sk where sk.code = 'SEAMANSHIP';
    perform public.commission_ship(v_player, v_fleet, 'nau', 'Nau 0215', false, true);
    perform public.commission_ship(v_player, v_fleet, 'barca', 'Barca 0215', false, true);
    for v_i in 1 .. 8 loop
      v_t0 := clock_timestamp(); v_ms := public.fleet_wave(v_fleet); v_fw := v_fw || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
    end loop;
    if v_ms <> 21 then
      raise exception '0215 self-assert FAIL: a nau and two barcas read fleet_wave %, not 21', v_ms;
    end if;
    if public.fleet_wave('00000000-0215-4000-8000-00000000dead') is not null then
      raise exception '0215 self-assert FAIL: a fleet with no hull has a wave';
    end if;
    for v_i in 1 .. 8 loop
      v_t0 := clock_timestamp(); v_n := public.title_level(v_player); v_tl := v_tl || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
    end loop;
    if v_n <> 1 then
      raise exception '0215 self-assert FAIL: a new house is title %, not 1', v_n;
    end if;
    v_npc := public.new_house(null, 'Comptoir 0215', 'FRA', 'LIS', 'Flotte 0215', 'barca', 'Mouette 0215', 1000, true);
    if public.title_level(v_npc) is not null then
      raise exception '0215 self-assert FAIL: the probe merchant has a title';
    end if;
    -- world.player() serves the derived title and its name for the probe (as the signed-in house)
    -- (public.current_player_id reads auth.uid(); the probe is not signed in, so the reading is asked of the pieces)
    if (select t.name from public.title_names t where t.level = public.title_level(v_player)) <> 'Apprentice' then
      raise exception '0215 self-assert FAIL: title 1 is not Apprentice';
    end if;
    -- the gatherer, DARK: null for a barca at title 1 bound for Havana, while the rule itself refuses
    v_course := (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                   from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_hav);
    if public.sea_conditions_on() then
      raise exception '0215 self-assert FAIL: sea_conditions_bite is already lit';
    end if;
    if public.sea_gate(v_player, v_fleet, v_hav, v_course) is not null then
      raise exception '0215 self-assert FAIL: the gate refuses while dark';
    end if;
    v_ref := public.sea_refusal(public.title_level(v_player), public.fleet_wave(v_fleet), public.course_zones(v_course) || public.harbour_zone(v_hav));
    if v_ref is null or v_ref->'figures'->>'zone' <> 'NOR-MAC' then
      raise exception '0215 self-assert FAIL: the rule does not refuse a title-1 fleet the Lisbon → Havana line at Macaronesia: %', v_ref;
    end if;
    -- LIT (inside the rollback): the gate is the rule
    update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
    v_ref := public.sea_gate(v_player, v_fleet, v_hav, v_course);
    if v_ref is null or v_ref->>'code' <> 'E_SEA_CLOSED' or v_ref->'figures'->>'zone' <> 'NOR-MAC'
       or (v_ref->'figures'->>'needs_title')::int <> 2 or (v_ref->'figures'->>'title')::int <> 1 then
      raise exception '0215 self-assert FAIL: lit, the gate answers % for a title-1 fleet bound for Havana', v_ref;
    end if;
    -- lit, the same fleet may sail to Porto (every zone of the line is home water)
    if public.sea_gate(v_player, v_fleet, (select id from public.ports where code = 'OPO'),
                       (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                          from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = (select id from public.ports where code = 'OPO'))) is not null then
      raise exception '0215 self-assert FAIL: lit, Lisbon → Porto is refused';
    end if;
    -- lit, nobody is never refused; a merchant is judged on wave alone (title null): Havana's line asks 30 of a barca's 12
    if public.sea_gate(null, v_fleet, v_hav, v_course) is not null then
      raise exception '0215 self-assert FAIL: the gate refuses nobody';
    end if;
    v_ref := public.sea_gate(v_npc, (select f.id from public.fleets f where f.player_id = v_npc limit 1), v_hav, v_course);
    if v_ref is null or v_ref->'figures' ? 'title' or (v_ref->'figures'->>'needs_wave')::int <> 30 then
      raise exception '0215 self-assert FAIL: a merchant barca bound for Havana reads %', v_ref;
    end if;
    raise exception using errcode = 'ZX215', message = 'probe done';
  exception when sqlstate 'ZX215' then
    null;
  end;
  if exists (select 1 from public.players where auth_uid = c_uid or company_name in ('Casa 0215', 'Comptoir 0215')) then
    raise exception '0215 self-assert FAIL: the probe survived its rollback';
  end if;
  if public.sea_conditions_on() then
    raise exception '0215 self-assert FAIL: the switch is lit after the probe';
  end if;

  -- (i) the walls: the readers are server-only, the one read is registered and granted, the tables are shut
  if has_function_privilege('authenticated', 'public.sea_gate(uuid, uuid, uuid, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.sea_gate(uuid, uuid, uuid, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.sea_refusal(int, numeric, text[])', 'execute')
     or has_function_privilege('authenticated', 'public.title_level(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.fleet_wave(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.course_zones(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.sea_zone_at(double precision, double precision)', 'execute')
     or has_function_privilege('authenticated', 'public.harbour_zone(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.sea_leg_asks_derive(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.sea_conditions_on()', 'execute')
     or has_function_privilege('anon', 'world.sea_conditions()', 'execute')
     or not has_function_privilege('authenticated', 'world.sea_conditions()', 'execute') then
    raise exception '0215 self-assert FAIL: the walls do not hold';
  end if;
  if not exists (select 1 from public.client_rpc_entry_points() e where e.schema_name = 'world' and e.function_name = 'sea_conditions' and e.fn = 'world.sea_conditions()'::regprocedure) then
    raise exception '0215 self-assert FAIL: world.sea_conditions is not registered';
  end if;
  if exists (select 1 from public.client_rpc_entry_points() e where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute')) then
    raise exception '0215 self-assert FAIL: a registry row is not executable by authenticated';
  end if;
  if (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname in ('sea_zones', 'sea_zone_boxes', 'sea_zone_cells', 'sea_leg_asks', 'title_names') and c.relrowsecurity) <> 5
     or has_table_privilege('authenticated', 'public.sea_leg_asks', 'select') or has_table_privilege('anon', 'public.sea_zones', 'select') then
    raise exception '0215 self-assert FAIL: a new table is open to a client role';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'players' and column_name = 'title_level') then
    raise exception '0215 self-assert FAIL: players.title_level survived';
  end if;
  -- the reading serves the zones, the titles and the switch (for nobody: no title, no fleets)
  v_lvl := world.sea_conditions();
  if jsonb_array_length(v_lvl->'zones') <> 64 or jsonb_array_length(v_lvl->'titles') <> 11 or (v_lvl->>'bite')::boolean
     or (v_lvl->'zones'->26->>'code') <> 'NOR-MID' or (v_lvl->'zones'->26->>'wave_min')::int <> 30 then
    raise exception '0215 self-assert FAIL: world.sea_conditions serves %', left(v_lvl::text, 300);
  end if;

  v_out := format('ship_stats old %s ms → new %s ms (first 3 / last 3: %s / %s → %s / %s); course_zones Lisbon → Havana %s ms (first 3 / last 3 %s / %s); fleet_wave %s ms; title_level %s ms; %s humans titled',
                  round((select avg(x) from unnest(v_old) x), 2), round((select avg(x) from unnest(v_new) x), 2),
                  round((select avg(x) from unnest(v_old[1:3]) x), 2), round((select avg(x) from unnest(v_old[6:8]) x), 2),
                  round((select avg(x) from unnest(v_new[1:3]) x), 2), round((select avg(x) from unnest(v_new[6:8]) x), 2),
                  round((select avg(x) from unnest(v_cz) x), 2), round((select avg(x) from unnest(v_cz[1:3]) x), 2), round((select avg(x) from unnest(v_cz[6:8]) x), 2),
                  round((select avg(x) from unnest(v_fw) x), 2), round((select avg(x) from unnest(v_tl) x), 2), v_humans);
  raise notice '0215 self-assert ok: THE SEAS HAVE CONDITIONS (dark). 64 zones, 67 boxes, 11 titles; the zone raster and % leg asks derived; every class''s wave is the derivation; 65 wave rows; %. The rule refuses (1, 12, NOR-MID) with its four figures and clears (4, 30); Lisbon → Havana asks 30 / 4; the probe nau + 2 barcas read 21, its title 1, the merchant none; the gate is null dark and E_SEA_CLOSED lit (rolled back); five bodies re-cut and reversed; players.title_level dropped; the walls hold. TIMING: %. % ms in all.',
    (select count(*) from public.sea_leg_asks), v_txt, v_out,
    round(extract(epoch from clock_timestamp() - (select t0 from t0_0215)) * 1000);
end $$;

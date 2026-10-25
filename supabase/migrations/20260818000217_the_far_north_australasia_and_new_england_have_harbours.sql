-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0217 — EIGHT NEW HARBOURS: THE RUSSIAN NORTH, AUSTRALIA, NEW ZEALAND AND THE NORTHERN UNITED STATES
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (docs/OWNER_REQUESTS.md row 186, 2026-10-20) ──────────────────────────────────────
--   "There aren't a single city on top of Russia. Can there be like 2 more? Also 2 more in autrailia
--    and in new zeland. Also 2 on top of USA."
--
-- ── THE EIGHT (real places, data/ports.json; decided by default, the owner may reverse any) ─────
--   MEZ Mezen (Muscovy, White Sea) · PUS Pustozersk (Muscovy, the Pechora; Barents Sea)
--   DAR Darwin (Timor Sea) · FRE Fremantle (Indian Ocean)
--   AUK Auckland (South Pacific) · WLG Wellington (Tasman Sea)
--   PTL Portland, Maine (North Atlantic) · AST Astoria, Oregon (North Pacific)
--   Arkhangelsk, Vardo, Sydney, Hobart, Boston and New York already exist; these fill the rest of the
--   Russian Arctic shore the ice allows (0040's closure starts at 60° E), the west and north of
--   Australia, both islands of New Zealand, and the north of the United States on both coasts.
--   Small harbours (tier 3: four goods each, size 2), ten new goods where the place's own trade had
--   no good in the catalogue yet. ANACHRONISMS, said: Darwin (1869), Fremantle (1829), Auckland and
--   Wellington (1840) and Astoria (1811) are towns of a later age, like Sydney and Hobart before them;
--   their notes name what was there in the age of sail (the Makassan trepang coast, Vlamingh's Swan
--   River, the Maori harbours Tasman sighted, the Chinook market at the Columbia).
--
-- SUPERSEDES, by one hunk sliced from the live body: public.city_treasury_switch(boolean) (0122, re-cut by 0172):
-- its seed expression moves into the new public.city_seed_amount(uuid), part (cities).
--
-- ── HOW THIS FILE IS MADE: THREE PARTS, IN ORDER, EACH FROM ITS OWN GENERATOR OR RULE ───────────
--   (growth) scripts/build-world-growth.mjs 20260818000217 <this name>, against the applied chain:
--            the goods, the harbours, the offers, the market rows and 0089's buildings, with its
--            whole-world equality self-assert. Its market step is now three short statements
--            (72.6 s as one upsert before; 9.9 + 2.3 + 0.3 s now on native PostgreSQL 16).
--   (sea)    scripts/build-sea-migration.mjs with ADDS_PLACES_ONLY, against the chain plus the growth:
--            the eight roadsteads, their sailed distances to and from every place (the existing
--            distances kept to the tenth), and 48 merchant courses (each new harbour to and from its
--            three nearest by sea) so the merchant planner can find them.
--   (cities) the per-harbour rows six later systems seeded once over the harbours of their day:
--            purse (with 0122/0172's seed folded into public.city_seed_amount, one hunk in
--            public.city_treasury_switch), works, flag, tongue, the sea-condition leg asks, the hauls.
--   Each part carries its own self-assert and receipt.
--
-- ── WHAT CHANGES IN LIVE PLAY (measured on the chain, 2026-10-25; prod figures in the dev-log) ──
--   * 1,950 existing market rows (18 goods) change affinity (a new maker of their good is now within reach):
--     their stock is reset to the new target, as every growth since 0041 has done.
--   * 1,269 existing market rows take a shorter haul (0173): the good now has a nearer maker among the
--     eight, so its price there falls toward the maker's (haul factor median x0.970, at most x0.799).
--   * In a world whose cities were seeded (prod), each new harbour is seeded its standing purse
--     (2,000,000), posted as one SEED flow each — 16,000,000 minted to eight new purses.
--   * Nothing else: no player row, no existing roadstead or distance, no sea zone, no switch.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
--   The heaviest statements: the growth self-assert 15.8 s (reads only), the affinity derivation 9.9 s
--   (into a temp table, no lock on the game's tables), the cities self-assert 6.1 s, the leg asks 3.0 s,
--   the haul diff 3.0 s, the new market rows 2.3 s; the whole file 36 s on native PostgreSQL 16 (dev-log §4).
--
-- ROLLBACK (forward migration): delete the eight harbours' rows from sea_leg_asks, npc_courses,
-- port_language, port_allegiance, city_works, port_treasury (and their SEED flows only by a reversing
-- flow, never a DELETE), port_goods, port_buildings, port_specialties and sea_reaches, the new keys from
-- every sea_reaches.reaches, the ten goods' port_goods rows and the goods; re-run world.haul_rows() and
-- the affinity derivation; reverse the switch hunk (its OLD text is in part (cities)) and drop
-- public.city_seed_amount. No fleet can be docked at a new harbour before players sail there.
-- VERSION: 0217 = prod head 0216 + 1 at writing — RENUMBER TO PROD HEAD + 1 AT PUSH (and the _0217
-- suffixes and the self-assert tags with it).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0217 — THE FAR NORTH AUSTRALASIA AND NEW ENGLAND HAVE HARBOURS
--        The world grows to what data/*.json holds today: 246 harbours, 565 goods,
--        1380 port offers — landed as a DELTA on whatever world this
--        database holds, and pinned to the data by set equality at the foot of this file.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- GENERATED by scripts/build-world-growth.mjs from data/*.json against the applied chain
-- (baseline: every migration below 20260818000217, applied to a scratch PostgreSQL and read back).
-- Do not hand-edit: edit the data or the generator and run it again.
--
-- ── WHY A GROWTH MIGRATION EXISTS AT ALL ────────────────────────────────────────────────────────
-- 0003 seeded the world and then SHIPPED. On 2026-08-24 it was edited in place after production
-- had applied it — production kept the original 70 goods and 214 harbours while fresh rebuilds
-- got 243 goods, and the ten island ports existed in no database at all. 0003 is now reverted to
-- the exact bytes production ran (git blob eee9091), and THIS file carries the growth, so every
-- world — production's, a fresh browser's, CI's — arrives at the same place through the same door.
--
-- ── WHAT LANDS HERE (measured against the applied baseline, not remembered) ────────────────────
--   +8    harbour ports  (AST AUK DAR FRE MEZ PTL PUS WLG)
--   ~0    harbour rows updated (dev_* follow the roster)
--   +10   goods; ~0 changed (name, band, geography — codes never change)
--   (sea legs: RETIRED with 0049 — a new or moved port needs scripts/build-sea-migration.mjs
--    to cut a NEW raster/reaches migration AFTER this growth, or the new harbour has no roadstead
--    and no sailed distances; self-assert (g) names the harbours awaiting it and proof 08 refuses
--    a finished chain that never seeded them)
--   +32/-0 port offers, then port_goods re-derived for EVERY (harbour, good) pair
--   (each NEW pair asking world.demand_for() for its city's appetite, 0066)
--   the 8 new harbour(s) furnished by public.furnish_harbours(), 0089's one rule
--   the five affinity_* knobs reconciled to the chain's tuned values (0005 was edited in place
--   before the never-edit rule was enforced; a deployed world may still hold the old values)
--
-- ── WHAT THIS DELIBERATELY DOES NOT TOUCH ──────────────────────────────────────────────────────
--   Player rows (houses, fleets, ships, cargo, ledgers): no statement here reads or writes them.
--   ports.crew_pool on existing harbours (the running game owns it; 0007 hire drains it).
--   port_goods.stock / drift / season_mod where affinity is unchanged (real trade moved them).
--   SEA_PLACE rows (0036 owns them).
--
-- Depends on: 0002 (tables), 0003 (the seeded world), 0005 (port_goods, world.affinity_at, knobs),
--             0036 (ports.kind).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. Pre-image: the world this migration found (feeds the DELTA receipts below) ──────────────
create temporary table pre_0217 as
  select (select count(*) from public.ports    where kind = 'HARBOUR') as harbours,
         (select count(*) from public.goods)                           as goods,
         (select count(*) from public.port_specialties)                as offers,
         (select count(*) from public.port_goods)                      as market_rows,
         (select value from public.world_config where key = 'affinity_producer') as old_producer;

-- ── 1. The affinity knobs, reconciled to the chain's current tuned values ─────────────────────
--       0005 seeds these on a fresh world; a deployed world that applied an earlier 0005 keeps its
--       old values because a seed does not re-run. The grown catalogue was TUNED under the values
--       below (0005's measurement table: the old setting read 16.5% through proof 05 on 243 goods,
--       past the band; these bring it back). Idempotent: a world already holding them is untouched.
update public.world_config set value = '0.88'::jsonb where key = 'affinity_curve' and value <> '0.88'::jsonb;
update public.world_config set value = '1.00'::jsonb where key = 'affinity_home' and value <> '1.00'::jsonb;
update public.world_config set value = '0.93'::jsonb where key = 'affinity_producer' and value <> '0.93'::jsonb;
update public.world_config set value = '9500'::jsonb where key = 'affinity_reach_nm' and value <> '9500'::jsonb;
update public.world_config set value = '0.76'::jsonb where key = 'affinity_span' and value <> '0.76'::jsonb;

-- ── 2. The 10 new goods ───────────────────────────────────────────────────────────────────
insert into public.goods (code, name, base_value, bulk, perishable_pct_day, category, culture_mask, origin_regions, entrepot_ports, industry) values
  ('jarrah', 'Jarrah', 16.00, 1.400, 0.000, 'ship-supplies', '{}', '{OCE}', '{}', false),
  ('kauri-timber', 'Kauri Spars', 42.00, 1.400, 0.000, 'ship-supplies', '{}', '{OCE}', '{}', false),
  ('kauri-gum', 'Kauri Gum', 24.00, 0.800, 0.000, 'crafts', '{}', '{OCE}', '{}', false),
  ('harakeke', 'New Zealand Flax', 20.50, 1.200, 0.000, 'ship-supplies', '{}', '{OCE}', '{}', false),
  ('pounamu', 'Pounamu', 145.00, 0.300, 0.000, 'gems', '{}', '{OCE}', '{}', false),
  ('kumara', 'Kumara', 5.80, 1.000, 0.000, 'food', '{}', '{OCE}', '{}', false),
  ('mast-pine', 'Mast Pine', 45.00, 1.400, 0.000, 'ship-supplies', '{}', '{NOR}', '{}', false),
  ('beaver-pelts', 'Beaver Pelts', 120.00, 1.200, 0.000, 'cloth', '{}', '{NOR,PAC}', '{}', false),
  ('douglas-fir', 'Douglas Fir', 6.00, 1.400, 0.000, 'ship-supplies', '{}', '{PAC}', '{}', false),
  ('dentalium', 'Dentalium Shell', 60.00, 0.300, 0.000, 'crafts', '{}', '{PAC}', '{}', false)
on conflict (code) do nothing;

-- ── 3. The 8 new harbours ────────────────────────────────────────────────────────────────
insert into public.ports (
  code, name, country, nation_id, lat, lon, sea_id, region_id, culture,
  size_tier, max_draft, has_yard, yard_tier, has_academy,
  dev_industry, dev_commerce, dev_military, tax_rate, crew_pool
)
select v.code, v.name, v.country, n.id, v.lat, v.lon, s.id, r.id, v.culture,
       v.size_tier, v.max_draft, v.yard_tier > 0, v.yard_tier, v.academy,
       v.dev_i, v.dev_c, v.dev_m, 0.03, v.crew_pool
  from (values
    ('AST', 'Astoria', 'United States', null, 46.19, -123.83, 'NRT', 'PAC', 'latin', 2, 3, 0, false, 4, 9, 4, 160),
    ('AUK', 'Auckland', 'New Zealand', null, -36.85, 174.76, 'STH', 'OCE', 'oceanic', 2, 3, 0, false, 4, 9, 4, 160),
    ('DAR', 'Darwin', 'Australia', null, -12.44, 130.84, 'TIM', 'OCE', 'oceanic', 2, 3, 0, false, 4, 9, 4, 160),
    ('FRE', 'Fremantle', 'Australia', null, -32.05, 115.75, 'IND', 'OCE', 'oceanic', 2, 3, 0, false, 4, 9, 4, 160),
    ('MEZ', 'Mezen', 'Russia', 'RUS', 65.85, 44.23, 'WHI', 'SCA', 'nordic', 2, 3, 0, false, 4, 9, 4, 160),
    ('PTL', 'Portland', 'United States', null, 43.66, -70.26, 'NOR', 'NOR', 'anglo', 2, 3, 0, false, 4, 9, 4, 160),
    ('PUS', 'Pustozersk', 'Russia', 'RUS', 67.53, 52.64, 'BAR', 'SCA', 'nordic', 2, 3, 0, false, 4, 9, 4, 160),
    ('WLG', 'Wellington', 'New Zealand', null, -41.29, 174.78, 'TAS', 'OCE', 'oceanic', 2, 3, 0, false, 4, 9, 4, 160)
  ) as v(code, name, country, nation_code, lat, lon, sea_code, region_code, culture,
         size_tier, max_draft, yard_tier, academy, dev_i, dev_c, dev_m, crew_pool)
  join public.seas    s on s.code = v.sea_code
  join public.regions r on r.code = v.region_code
  left join public.nations n on n.code = v.nation_code
on conflict (code) do nothing;

-- ── 4b. 32 offers added ──────────────────────────────────────────────────────────────────
insert into public.port_specialties (port_id, good_id)
select p.id, g.id from (values
  ('AST', 'beaver-pelts'),
  ('AST', 'douglas-fir'),
  ('AST', 'pine-pitch'),
  ('AST', 'dentalium'),
  ('AUK', 'kauri-timber'),
  ('AUK', 'kauri-gum'),
  ('AUK', 'harakeke'),
  ('AUK', 'kumara'),
  ('DAR', 'trepang'),
  ('DAR', 'pandanus-mats'),
  ('DAR', 'wax'),
  ('DAR', 'kangaroo-skins'),
  ('FRE', 'sandalwood'),
  ('FRE', 'wattle-bark'),
  ('FRE', 'sperm-oil'),
  ('FRE', 'jarrah'),
  ('MEZ', 'stockfish'),
  ('MEZ', 'halibut'),
  ('MEZ', 'eiderdown'),
  ('MEZ', 'whale-bone-stays'),
  ('PTL', 'cod'),
  ('PTL', 'maple-sugar'),
  ('PTL', 'mast-pine'),
  ('PTL', 'beaver-pelts'),
  ('PUS', 'gyrfalcons'),
  ('PUS', 'russia-leather'),
  ('PUS', 'narwhal-horn'),
  ('PUS', 'angelica-root'),
  ('WLG', 'harakeke'),
  ('WLG', 'pounamu'),
  ('WLG', 'kumara'),
  ('WLG', 'sperm-oil')
) as v(port_code, good_code)
  join public.ports p on p.code = v.port_code
  join public.goods g on g.code = v.good_code
on conflict do nothing;

-- ── 6. THE MARKET FOLLOWS THE WORLD: port_goods re-derived for every (harbour, good) pair ─────
--
-- The same arithmetic as 0005's seed — the one formula world.affinity_at(), the same knobs-once +
-- distance-matrix shape — extended to the grown world. Three kinds of row come out of it:
--   * a MISSING pair (new good anywhere, any good at a new harbour): INSERTED, stock = target
--   * an EXISTING pair whose affinity moved (a source appeared/vanished nearby, or the knobs
--     changed): affinity/stock_target/production_rate re-derived, stock := the new target — a
--     retuned geometry with a stale stock displacement would price as a random shortage
--   * an EXISTING pair whose affinity is unchanged: NOT TOUCHED (stock/drift belong to the game)
--
-- THREE SHORT STATEMENTS, NOT ONE UPSERT (2026-10-25, 0217). The single INSERT … ON CONFLICT this
-- generator used to emit priced every pair of the world — world.demand_for() and three depth calls
-- on all ~139,000 rows, only for the conflict to throw ~132,000 of them away — and measured 72.6 s on
-- native PostgreSQL 16 as one statement; 0215's push lost its connection on a statement of that
-- length. Now the affinity is derived once into a temp table (the arithmetic is unchanged), and the
-- insert and the update each price only the rows they write.
create temporary table derived_0217 on commit drop as
with knob as (
  select public.wc_num('affinity_producer') as producer,
         public.wc_num('affinity_home')     as home,
         public.wc_num('affinity_span')     as span,
         public.wc_num('affinity_reach_nm') as reach_nm,
         public.wc_num('affinity_curve')    as curve
),
source_distance as (
  select p.id as port_id, src.id as src_id,
         voyage.gc_distance_nm(p.lat, p.lon, src.lat, src.lon) as nm
    from public.ports p
    cross join (select distinct port_id from public.port_specialties) s
    join public.ports src on src.id = s.port_id
   where p.kind = 'HARBOUR'
),
nearest as (
  select d.port_id, ps.good_id, min(d.nm) as nm
    from source_distance d
    join public.port_specialties ps on ps.port_id = d.src_id
   group by d.port_id, ps.good_id
)
select p.id as port_id, g.id as good_id, p.size_tier,
       world.affinity_at(
         exists (select 1 from public.port_specialties s
                  where s.port_id = p.id and s.good_id = g.id),
         n.nm, k.producer, k.home, k.span, k.reach_nm, k.curve) as affinity
  from public.ports p
  cross join public.goods g
  cross join knob k
  left join nearest n on n.port_id = p.id and n.good_id = g.id
 where p.kind = 'HARBOUR';

-- the MISSING pairs: inserted at their target stock, each asking world.demand_for() for its city's
-- appetite (0066); an existing pair keeps its demand (the region and the category did not move)
insert into public.port_goods (port_id, good_id, affinity, stock, stock_target, production_rate, demand)
select d.port_id,
       d.good_id,
       d.affinity,
       (world.market_depth_at(d.size_tier, d.affinity, public.wc_num('market_depth'))).stock_target,
       (world.market_depth_at(d.size_tier, d.affinity, public.wc_num('market_depth'))).stock_target,
       (world.market_depth_at(d.size_tier, d.affinity, public.wc_num('market_depth'))).production_rate,
       world.demand_for(d.port_id, d.good_id)
  from derived_0217 d
 where not exists (select 1 from public.port_goods pg where pg.port_id = d.port_id and pg.good_id = d.good_id);

-- the EXISTING pairs whose affinity moved: re-derived, stock := the new target
update public.port_goods pg
   set affinity        = d.affinity,
       stock_target    = (world.market_depth_at(d.size_tier, d.affinity, public.wc_num('market_depth'))).stock_target,
       production_rate = (world.market_depth_at(d.size_tier, d.affinity, public.wc_num('market_depth'))).production_rate,
       stock           = (world.market_depth_at(d.size_tier, d.affinity, public.wc_num('market_depth'))).stock_target,
       updated_at      = now()
  from derived_0217 d
 where pg.port_id = d.port_id and pg.good_id = d.good_id
   and pg.affinity is distinct from d.affinity;

-- ── 7. A NEW HARBOUR IS FURNISHED BY 0089's ONE RULE ─────────────────────────────────────────
-- public.furnish_harbours() inserts, for every harbour, each building row public.harbour_buildings
-- names that the city does not yet keep — and nothing else: a kept row is the game's. On a world
-- with no new harbour it writes 0 rows; the rows it writes here are exactly the new harbours'.
select public.furnish_harbours() as buildings_furnished;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
-- The migration's whole claim: after it, THE DATABASE'S WORLD EQUALS data/*.json — by set
-- equality over identities AND values, never by counts alone. The literals below are generated
-- from the data; the deltas are measured against the pre-image; the derivation rules (dev_*, the
-- offer band, affinity) are asserted as RULES over the live tables, so they hold for every row
-- including ones this migration never touched. The roster check carries its own positive control.
create temporary table want_ports_0217 (
  code text, name text, country text, nation_code text, lat numeric, lon numeric,
  sea_code text, region_code text, culture text, size_tier int, max_draft int,
  yard_tier int, academy boolean, dev_i int, dev_c int, dev_m int
);
insert into want_ports_0217 values
  ('ACA', 'Acapulco', 'Mexico', 'ESP', 16.86, -99.89, 'NRT', 'PAC', 'latin', 3, 4, 1, false, 8, 13, 7),
  ('ACC', 'Accra', 'Ghana', 'PRT', 5.56, -0.2, 'GUL', 'WST', 'guinean', 2, 3, 0, false, 6, 9, 4),
  ('ADE', 'Aden', 'Yemen', 'OTT', 12.8, 45.03, 'GLF', 'ARA', 'islamic', 3, 4, 1, false, 6, 14, 7),
  ('AGA', 'Agadir', 'Morocco', 'MAR', 30.42, -9.58, 'NOR', 'MAG', 'islamic', 2, 3, 0, false, 6, 9, 4),
  ('ALE', 'Alexandria', 'Egypt', 'OTT', 31.2, 29.89, 'MED', 'LEV', 'islamic', 5, 5, 3, true, 12, 20, 11),
  ('ALG', 'Algiers', 'Algeria', 'OTT', 36.78, 3.06, 'MED', 'MAG', 'islamic', 3, 4, 1, false, 6, 14, 7),
  ('AMB', 'Ambon', 'Indonesia', null, -3.7, 128.18, 'BAN', 'SOU', 'malay', 3, 4, 1, false, 6, 12, 7),
  ('AMS', 'Amsterdam', 'Netherlands', 'NLD', 52.37, 4.88, 'NEA', 'FRA', 'germanic', 5, 5, 3, true, 12, 20, 11),
  ('ANC', 'Ancona', 'Italy', null, 43.62, 13.52, 'ADR', 'ADR', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('ANG', 'Angra', 'Portugal', 'PRT', 38.66, -27.22, 'NOR', 'ATL', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('ANT', 'Antalya', 'Turkey', 'OTT', 36.91, 30.7, 'MED', 'AEG', 'islamic', 2, 3, 0, false, 6, 9, 4),
  ('ARP', 'Antwerp', 'Belgium', 'ESP', 51.22, 4.4, 'NEA', 'FRA', 'germanic', 5, 2, 3, true, 16, 20, 11),
  ('ARI', 'Arica', 'Chile', 'ESP', -18.48, -70.32, 'STH', 'PAC', 'latin', 3, 4, 1, false, 6, 13, 7),
  ('ARK', 'Arkhangelsk', 'Russia', 'RUS', 64.54, 40.54, 'WHI', 'SCA', 'nordic', 3, 2, 1, false, 6, 14, 7),
  ('AST', 'Astoria', 'United States', null, 46.19, -123.83, 'NRT', 'PAC', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('AUK', 'Auckland', 'New Zealand', null, -36.85, 174.76, 'STH', 'OCE', 'oceanic', 2, 3, 0, false, 4, 9, 4),
  ('AYU', 'Ayutthaya', 'Thailand', 'AYU', 14.36, 100.58, 'GND', 'SOU', 'malay', 3, 2, 1, false, 6, 14, 7),
  ('BAN', 'Banda Aceh', 'Indonesia', null, 5.55, 95.32, 'STR', 'SOU', 'malay', 3, 4, 1, false, 6, 13, 7),
  ('BND', 'Banda Neira', 'Indonesia', null, -4.51, 129.9, 'BAN', 'SOU', 'malay', 3, 4, 1, false, 6, 12, 7),
  ('BAS', 'Bandar Abbas', 'Iran', 'PER', 27.19, 56.28, 'PER', 'ARA', 'islamic', 3, 4, 1, false, 6, 14, 7),
  ('BNT', 'Banten', 'Indonesia', 'BAN', -6.04, 106.16, 'JAV', 'SOU', 'malay', 3, 4, 1, false, 8, 14, 7),
  ('BAR', 'Barcelona', 'Spain', 'ESP', 41.38, 2.18, 'MED', 'IBE', 'latin', 5, 5, 3, true, 10, 20, 11),
  ('NAV', 'Navidad', 'Mexico', 'ESP', 19.21, -104.68, 'NRT', 'PAC', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('BSR', 'Basra', 'Iraq', 'OTT', 30.52, 47.81, 'PER', 'ARA', 'islamic', 3, 2, 1, false, 6, 13, 7),
  ('BEI', 'Beirut', 'Lebanon', 'OTT', 33.89, 35.51, 'MED', 'LEV', 'islamic', 3, 4, 1, false, 8, 14, 7),
  ('BEL', 'Belem', 'Brazil', 'PRT', -1.46, -48.5, 'SOU', 'STH', 'latin', 2, 2, 0, false, 4, 9, 4),
  ('BER', 'Bergen', 'Norway', 'DNK', 60.39, 5.32, 'NRW', 'SCA', 'nordic', 3, 4, 1, false, 8, 13, 7),
  ('BIL', 'Bilbao', 'Spain', 'ESP', 43.26, -2.93, 'BAY', 'IBE', 'latin', 3, 4, 1, false, 6, 12, 7),
  ('BOR', 'Bordeaux', 'France', 'FRA', 44.84, -0.58, 'BAY', 'FRA', 'latin', 5, 2, 3, true, 12, 20, 11),
  ('BOS', 'Boston', 'United States', null, 42.36, -71.06, 'NOR', 'NOR', 'anglo', 3, 4, 1, false, 9, 12, 7),
  ('BRI', 'Bridgetown', 'Barbados', null, 13.1, -59.62, 'CAR', 'CAR', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('BRS', 'Bristol', 'United Kingdom', 'ENG', 51.45, -2.6, 'NOR', 'BRI', 'anglo', 3, 4, 1, false, 9, 14, 7),
  ('BRU', 'Bruges', 'Belgium', 'ESP', 51.21, 3.22, 'NEA', 'FRA', 'germanic', 2, 2, 0, false, 6, 9, 4),
  ('BUV', 'Buenaventura', 'Colombia', 'ESP', 3.88, -77.03, 'NRT', 'PAC', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('BUE', 'Buenos Aires', 'Argentina', 'ESP', -34.6, -58.38, 'SOU', 'STH', 'latin', 3, 2, 1, false, 6, 14, 7),
  ('BUS', 'Busan', 'South Korea', 'JOS', 35.18, 129.07, 'KOR', 'KOR', 'korean', 5, 5, 3, true, 10, 20, 11),
  ('CAD', 'Cadiz', 'Spain', 'ESP', 36.53, -6.3, 'NOR', 'IBE', 'latin', 5, 5, 3, true, 12, 20, 11),
  ('CAG', 'Cagliari', 'Italy', 'ESP', 39.22, 9.12, 'MED', 'WES', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('CAL', 'Calabar', 'Nigeria', null, 4.95, 8.32, 'GUL', 'WST', 'guinean', 2, 3, 0, false, 4, 9, 4),
  ('CLS', 'Calais', 'France', 'FRA', 50.95, 1.86, 'ENG', 'FRA', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('CLL', 'Callao', 'Peru', 'ESP', -12.05, -77.14, 'STH', 'PAC', 'latin', 5, 5, 3, true, 13, 20, 11),
  ('CAP', 'Cape Coast', 'Ghana', 'PRT', 5.1, -1.25, 'GUL', 'WST', 'guinean', 2, 3, 0, false, 4, 9, 4),
  ('CPT', 'Cape Town', 'South Africa', null, -33.93, 18.42, 'SOU', 'EAS', 'guinean', 3, 4, 1, false, 6, 12, 7),
  ('CAR', 'Cartagena', 'Colombia', 'ESP', 10.42, -75.53, 'CAR', 'CAR', 'latin', 5, 5, 3, true, 10, 20, 11),
  ('CEB', 'Cebu', 'Philippines', 'ESP', 10.29, 123.9, 'VIS', 'SOU', 'malay', 2, 3, 0, false, 6, 9, 4),
  ('CEU', 'Ceuta', 'Spain', 'ESP', 35.89, -5.3, 'MED', 'MAG', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('CHE', 'Chennai', 'India', null, 13.08, 80.28, 'BYF', 'EST', 'indic', 3, 4, 1, false, 6, 14, 7),
  ('CHS', 'Chios', 'Greece', 'GEN', 38.4, 26.02, 'AEG', 'AEG', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('CHI', 'Chittagong', 'Bangladesh', 'MUG', 22.34, 91.83, 'BYF', 'EST', 'indic', 2, 2, 0, false, 4, 9, 4),
  ('CID', 'Cidade Velha', 'Cape Verde', 'PRT', 14.92, -23.6, 'NOR', 'ATL', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('COL', 'Colombo', 'Sri Lanka', 'PRT', 6.93, 79.86, 'LAC', 'EST', 'indic', 3, 4, 1, false, 6, 14, 7),
  ('CON', 'Concepcion', 'Chile', 'ESP', -36.74, -72.99, 'STH', 'PAC', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('COP', 'Copenhagen', 'Denmark', 'DNK', 55.68, 12.57, 'BAL', 'BAL', 'germanic', 5, 5, 3, true, 10, 20, 11),
  ('COQ', 'Coquimbo', 'Chile', 'ESP', -29.95, -71.34, 'STH', 'PAC', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('COR', 'Corfu', 'Greece', 'VEN', 39.62, 19.92, 'ION', 'ADR', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('CRK', 'Cork', 'Ireland', 'ENG', 51.9, -8.47, 'NOR', 'BRI', 'anglo', 2, 3, 0, false, 4, 9, 4),
  ('CUM', 'Cumana', 'Venezuela', 'ESP', 10.45, -64.17, 'CAR', 'CAR', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('DAR', 'Darwin', 'Australia', null, -12.44, 130.84, 'TIM', 'OCE', 'oceanic', 2, 3, 0, false, 4, 9, 4),
  ('DIL', 'Dili', 'Timor-Leste', null, -8.55, 125.58, 'BAN', 'OCE', 'oceanic', 2, 3, 0, false, 6, 9, 4),
  ('DIU', 'Diu', 'India', 'PRT', 20.71, 70.98, 'ARA', 'WIA', 'indic', 2, 3, 0, false, 4, 9, 4),
  ('DUB', 'Dublin', 'Ireland', 'ENG', 53.35, -6.26, 'IRI', 'BRI', 'anglo', 3, 4, 1, false, 8, 14, 7),
  ('DBR', 'Dubrovnik', 'Croatia', null, 42.64, 18.11, 'ADR', 'ADR', 'latin', 3, 4, 1, false, 6, 14, 7),
  ('REA', 'Realejo', 'Nicaragua', 'ESP', 12.54, -87.17, 'NRT', 'PAC', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('ELM', 'Elmina', 'Ghana', 'PRT', 5.08, -1.35, 'GUL', 'WST', 'guinean', 3, 4, 1, false, 6, 13, 7),
  ('FAM', 'Famagusta', 'Cyprus', null, 35.12, 33.95, 'MED', 'LEV', 'latin', 2, 3, 0, false, 6, 9, 4),
  ('FEO', 'Feodosia', 'Ukraine', null, 45.05, 35.38, 'BLA', 'AEG', 'islamic', 2, 3, 0, false, 4, 9, 4),
  ('FRE', 'Fremantle', 'Australia', null, -32.05, 115.75, 'IND', 'OCE', 'oceanic', 2, 3, 0, false, 4, 9, 4),
  ('FUK', 'Fukuoka', 'Japan', 'JPN', 33.59, 130.4, 'KOR', 'JAP', 'japanese', 3, 4, 1, false, 6, 13, 7),
  ('FNC', 'Funchal', 'Portugal', 'PRT', 32.65, -16.92, 'NOR', 'ATL', 'latin', 3, 4, 1, false, 8, 11, 7),
  ('FUZ', 'Fuzhou', 'China', 'MNG', 26.08, 119.29, 'TAI', 'CHI', 'sinic', 2, 3, 0, false, 4, 9, 4),
  ('GAL', 'Galle', 'Sri Lanka', null, 6.03, 80.22, 'IND', 'EST', 'indic', 2, 3, 0, false, 4, 9, 4),
  ('GDA', 'Gdansk', 'Poland', 'POL', 54.35, 18.65, 'BAL', 'BAL', 'germanic', 5, 2, 3, true, 13, 20, 11),
  ('GOA', 'Genoa', 'Italy', 'GEN', 44.41, 8.93, 'MED', 'WES', 'latin', 5, 5, 3, true, 16, 20, 11),
  ('GIB', 'Gibraltar', 'Gibraltar', null, 36.14, -5.35, 'MED', 'IBE', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('GOR', 'Goree', 'Senegal', null, 14.67, -17.4, 'NOR', 'WST', 'guinean', 2, 3, 0, false, 4, 9, 4),
  ('GUA', 'Guangzhou', 'China', 'MNG', 23.13, 113.26, 'SOA', 'CHI', 'sinic', 5, 2, 3, true, 10, 20, 11),
  ('GYE', 'Guayaquil', 'Ecuador', 'ESP', -2.19, -79.89, 'STH', 'PAC', 'latin', 3, 2, 1, false, 6, 12, 7),
  ('HAD', 'Hadibu', 'Yemen', null, 12.65, 54.03, 'GLF', 'ARA', 'islamic', 2, 3, 0, false, 4, 9, 4),
  ('HAG', 'Hagatna', 'Guam', null, 13.48, 144.75, 'PHI', 'OCE', 'oceanic', 2, 3, 0, false, 4, 9, 4),
  ('HAM', 'Hamburg', 'Germany', 'HAN', 53.55, 10, 'NEA', 'BAL', 'germanic', 5, 2, 3, true, 15, 20, 11),
  ('HAN', 'Hanoi', 'Vietnam', null, 21.02, 105.84, 'GIN', 'SOU', 'malay', 2, 2, 0, false, 4, 9, 4),
  ('HAV', 'Havana', 'Cuba', 'ESP', 23.14, -82.36, 'CAR', 'CAR', 'latin', 5, 5, 3, true, 12, 20, 11),
  ('HER', 'Heraklion', 'Greece', 'VEN', 35.34, 25.13, 'MED', 'AEG', 'latin', 3, 4, 1, false, 6, 13, 7),
  ('HIR', 'Hirado', 'Japan', 'JPN', 33.37, 129.55, 'EAS', 'JAP', 'japanese', 3, 4, 1, false, 8, 13, 7),
  ('HOB', 'Hobart', 'Australia', null, -42.88, 147.32, 'TAS', 'OCE', 'oceanic', 2, 3, 0, false, 4, 9, 4),
  ('HOI', 'Hoi An', 'Vietnam', null, 15.88, 108.33, 'SOA', 'SOU', 'malay', 3, 4, 1, false, 6, 14, 7),
  ('HON', 'Hong Kong', 'Hong Kong', null, 22.28, 114.16, 'SOA', 'CHI', 'sinic', 2, 3, 0, false, 4, 9, 4),
  ('HNL', 'Honolulu', 'United States', null, 21.3, -157.86, 'NRT', 'OCE', 'oceanic', 2, 3, 0, false, 6, 9, 4),
  ('HOO', 'Hooghly', 'India', null, 22.91, 88.4, 'BYF', 'EST', 'indic', 3, 2, 1, false, 9, 14, 7),
  ('HRN', 'Hoorn', 'Netherlands', 'NLD', 52.65, 5.07, 'NEA', 'FRA', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('HOR', 'Hormuz', 'Iran', 'PRT', 27.07, 56.46, 'PER', 'ARA', 'islamic', 3, 4, 1, false, 6, 14, 7),
  ('HUA', 'Huatulco', 'Mexico', 'ESP', 15.76, -96.12, 'NRT', 'PAC', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('INC', 'Incheon', 'South Korea', 'JOS', 37.46, 126.65, 'YEL', 'KOR', 'korean', 3, 4, 1, false, 8, 14, 7),
  ('IST', 'Istanbul', 'Turkey', 'OTT', 41.01, 28.96, 'SEA', 'AEG', 'islamic', 5, 5, 3, true, 12, 20, 11),
  ('IZM', 'Izmir', 'Turkey', 'OTT', 38.41, 27.14, 'AEG', 'AEG', 'islamic', 3, 4, 1, false, 9, 14, 7),
  ('JAF', 'Jaffna', 'Sri Lanka', null, 9.66, 80.02, 'BYF', 'EST', 'indic', 2, 3, 0, false, 4, 9, 4),
  ('JAK', 'Jakarta', 'Indonesia', 'BAN', -6.18, 106.83, 'JAV', 'SOU', 'malay', 5, 5, 3, true, 12, 20, 11),
  ('JAM', 'Jamestown', 'United States', null, 37.21, -76.78, 'NOR', 'NOR', 'anglo', 3, 4, 1, false, 6, 12, 7),
  ('JED', 'Jeddah', 'Saudi Arabia', 'OTT', 21.53, 39.16, 'RED', 'ARA', 'islamic', 3, 4, 1, false, 6, 14, 7),
  ('JEJ', 'Jeju', 'South Korea', 'JOS', 33.51, 126.52, 'EAS', 'KOR', 'korean', 2, 3, 0, false, 4, 9, 4),
  ('KAG', 'Kagoshima', 'Japan', 'JPN', 31.6, 130.56, 'EAS', 'JAP', 'japanese', 2, 3, 0, false, 4, 9, 4),
  ('KAL', 'Kaliningrad', 'Russia', 'RUS', 54.72, 20.5, 'BAL', 'BAL', 'germanic', 2, 3, 0, false, 4, 9, 4),
  ('KAN', 'Kannur', 'India', 'MLB', 11.87, 75.36, 'LAC', 'WIA', 'indic', 2, 3, 0, false, 4, 9, 4),
  ('KAR', 'Karachi', 'Pakistan', 'MUG', 24.86, 67.01, 'ARA', 'WIA', 'indic', 2, 3, 0, false, 6, 9, 4),
  ('KHA', 'Khambhat', 'India', 'GUJ', 22.31, 72.62, 'ARA', 'WIA', 'indic', 3, 2, 1, false, 6, 14, 7),
  ('KIL', 'Kilwa', 'Tanzania', null, -8.98, 39.52, 'IND', 'EAS', 'swahili', 2, 3, 0, false, 6, 9, 4),
  ('KIN', 'Kingston upon Hull', 'United Kingdom', 'ENG', 53.74, -0.33, 'NEA', 'BRI', 'anglo', 2, 3, 0, false, 6, 9, 4),
  ('KOC', 'Kochi', 'India', 'MLB', 9.97, 76.28, 'LAC', 'WIA', 'indic', 5, 5, 3, true, 13, 20, 11),
  ('KOL', 'Kollam', 'India', 'MLB', 8.89, 76.59, 'LAC', 'WIA', 'indic', 2, 3, 0, false, 4, 9, 4),
  ('KOZ', 'Kozhikode', 'India', 'MLB', 11.25, 75.78, 'LAC', 'WIA', 'indic', 5, 5, 3, true, 12, 20, 11),
  ('KUP', 'Kupang', 'Indonesia', null, -10.16, 123.58, 'TIM', 'OCE', 'oceanic', 2, 3, 0, false, 4, 9, 4),
  ('LAR', 'La Rochelle', 'France', 'FRA', 46.16, -1.15, 'BAY', 'FRA', 'latin', 3, 4, 1, false, 6, 14, 7),
  ('LAG', 'Lagos', 'Nigeria', null, 6.46, 3.39, 'GUL', 'WST', 'guinean', 2, 3, 0, false, 4, 9, 4),
  ('LPA', 'Las Palmas', 'Spain', 'ESP', 28.13, -15.43, 'NOR', 'ATL', 'latin', 3, 4, 1, false, 6, 13, 7),
  ('LEH', 'Le Havre', 'France', 'FRA', 49.49, 0.11, 'ENG', 'FRA', 'latin', 2, 3, 0, false, 6, 9, 4),
  ('LEI', 'Leith', 'United Kingdom', 'ENG', 55.98, -3.17, 'NEA', 'BRI', 'anglo', 2, 3, 0, false, 4, 9, 4),
  ('LIS', 'Lisbon', 'Portugal', 'PRT', 38.71, -9.14, 'NOR', 'IBE', 'latin', 5, 5, 3, true, 18, 20, 11),
  ('LIV', 'Livorno', 'Italy', null, 43.55, 10.32, 'MED', 'WES', 'latin', 3, 4, 1, false, 6, 13, 7),
  ('LON', 'London', 'United Kingdom', 'ENG', 51.51, -0.13, 'NEA', 'BRI', 'anglo', 5, 2, 3, true, 19, 20, 11),
  ('LNG', 'Longyearbyen', 'Norway', 'DNK', 78.22, 15.63, 'ARC', 'SCA', 'nordic', 2, 3, 0, false, 4, 9, 4),
  ('LUA', 'Luanda', 'Angola', 'PRT', -8.84, 13.23, 'SOU', 'WST', 'guinean', 3, 4, 1, false, 9, 14, 7),
  ('LUB', 'Lubeck', 'Germany', 'HAN', 53.87, 10.69, 'BAL', 'BAL', 'germanic', 5, 5, 3, true, 13, 20, 11),
  ('MAC', 'Macau', 'Macau', 'PRT', 22.19, 113.54, 'SOA', 'CHI', 'sinic', 5, 5, 3, true, 10, 20, 11),
  ('MCH', 'Machilipatnam', 'India', null, 16.17, 81.13, 'BYF', 'EST', 'indic', 2, 3, 0, false, 7, 9, 4),
  ('MAK', 'Makassar', 'Indonesia', null, -5.13, 119.41, 'MAK', 'SOU', 'malay', 3, 4, 1, false, 6, 14, 7),
  ('MAL', 'Malacca', 'Malaysia', 'PRT', 2.19, 102.25, 'STR', 'SOU', 'malay', 5, 5, 3, true, 12, 20, 11),
  ('MLG', 'Malaga', 'Spain', 'ESP', 36.72, -4.42, 'MED', 'IBE', 'latin', 3, 4, 1, false, 6, 14, 7),
  ('MLE', 'Malé', 'Maldives', null, 4.18, 73.51, 'LAC', 'WIA', 'islamic', 2, 3, 0, false, 4, 9, 4),
  ('MLN', 'Malindi', 'Kenya', null, -3.22, 40.12, 'IND', 'EAS', 'swahili', 2, 3, 0, false, 6, 9, 4),
  ('MAN', 'Manama', 'Bahrain', null, 26.22, 50.58, 'PER', 'ARA', 'islamic', 2, 3, 0, false, 4, 9, 4),
  ('MNG', 'Mangaluru', 'India', 'MLB', 12.87, 74.84, 'ARA', 'WIA', 'indic', 2, 3, 0, false, 6, 9, 4),
  ('MNL', 'Manila', 'Philippines', 'ESP', 14.6, 120.98, 'SOA', 'SOU', 'malay', 5, 5, 3, true, 12, 20, 11),
  ('MRS', 'Marseille', 'France', 'FRA', 43.3, 5.38, 'MED', 'WES', 'latin', 5, 5, 3, true, 16, 20, 11),
  ('MAS', 'Massawa', 'Eritrea', null, 15.6, 39.43, 'RED', 'EAS', 'swahili', 2, 3, 0, false, 4, 9, 4),
  ('MAT', 'Matsumae', 'Japan', 'JPN', 41.43, 140.11, 'SFJ', 'JAP', 'japanese', 2, 3, 0, false, 4, 9, 4),
  ('MZT', 'Mazatlan', 'Mexico', 'ESP', 23.22, -106.41, 'NRT', 'PAC', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('MES', 'Messina', 'Italy', 'ESP', 38.19, 15.55, 'MED', 'WES', 'latin', 2, 3, 0, false, 6, 9, 4),
  ('MEZ', 'Mezen', 'Russia', 'RUS', 65.85, 44.23, 'WHI', 'SCA', 'nordic', 2, 3, 0, false, 4, 9, 4),
  ('MID', 'Middelburg', 'Netherlands', 'NLD', 51.5, 3.61, 'NEA', 'FRA', 'latin', 2, 3, 0, false, 6, 9, 4),
  ('MOC', 'Mocha', 'Yemen', 'OTT', 13.32, 43.25, 'RED', 'ARA', 'islamic', 3, 4, 1, false, 6, 13, 7),
  ('MOG', 'Mogadishu', 'Somalia', null, 2.04, 45.34, 'IND', 'EAS', 'swahili', 2, 3, 0, false, 4, 9, 4),
  ('MOK', 'Mokpo', 'South Korea', 'JOS', 34.79, 126.39, 'YEL', 'KOR', 'korean', 2, 3, 0, false, 6, 9, 4),
  ('MOM', 'Mombasa', 'Kenya', null, -4.05, 39.67, 'IND', 'EAS', 'swahili', 3, 4, 1, false, 9, 14, 7),
  ('MTY', 'Monterey', 'United States', null, 36.6, -121.89, 'NRT', 'PAC', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('ISL', 'Island of Mozambique', 'Mozambique', 'PRT', -15.04, 40.73, 'MOZ', 'EAS', 'swahili', 3, 4, 1, false, 8, 14, 7),
  ('MUM', 'Mumbai', 'India', null, 19.08, 72.88, 'ARA', 'WIA', 'indic', 3, 4, 1, false, 6, 14, 7),
  ('MUS', 'Muscat', 'Oman', null, 23.61, 58.59, 'GAN', 'ARA', 'islamic', 3, 4, 1, false, 6, 13, 7),
  ('MYE', 'Myeik', 'Myanmar', null, 12.44, 98.6, 'AND', 'EST', 'indic', 2, 3, 0, false, 6, 9, 4),
  ('NAG', 'Nagasaki', 'Japan', 'JPN', 32.75, 129.88, 'EAS', 'JAP', 'japanese', 5, 5, 3, true, 10, 20, 11),
  ('NAH', 'Naha', 'Japan', 'JPN', 26.21, 127.68, 'EAS', 'JAP', 'japanese', 3, 4, 1, false, 6, 14, 7),
  ('NAM', 'Nampo', 'North Korea', null, 38.73, 125.4, 'YEL', 'KOR', 'korean', 2, 3, 0, false, 4, 9, 4),
  ('NAN', 'Nantes', 'France', 'FRA', 47.22, -1.55, 'BAY', 'FRA', 'latin', 3, 2, 1, false, 8, 14, 7),
  ('NAP', 'Naples', 'Italy', 'ESP', 40.84, 14.25, 'MED', 'WES', 'latin', 3, 4, 1, false, 9, 14, 7),
  ('NEW', 'New York', 'United States', null, 40.71, -74.01, 'NOR', 'NOR', 'anglo', 3, 4, 1, false, 8, 13, 7),
  ('NIN', 'Ningbo', 'China', 'MNG', 29.88, 121.55, 'EAS', 'CHI', 'sinic', 3, 4, 1, false, 8, 14, 7),
  ('NUU', 'Nuuk', 'Greenland', null, 64.18, -51.73, 'NOR', 'SCA', 'nordic', 2, 3, 0, false, 4, 9, 4),
  ('OLD', 'Old Goa', 'India', 'PRT', 15.5, 73.91, 'ARA', 'WIA', 'indic', 5, 5, 3, true, 12, 20, 11),
  ('ORA', 'Oran', 'Algeria', 'OTT', 35.7, -0.63, 'MED', 'MAG', 'islamic', 2, 3, 0, false, 4, 9, 4),
  ('OSA', 'Osaka', 'Japan', 'JPN', 34.69, 135.5, 'SET', 'JAP', 'japanese', 5, 5, 3, true, 10, 20, 11),
  ('OUI', 'Ouidah', 'Benin', null, 6.37, 2.08, 'GUL', 'WST', 'guinean', 2, 3, 0, false, 4, 9, 4),
  ('PAI', 'Paita', 'Peru', 'ESP', -5.09, -81.11, 'STH', 'PAC', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('PAL', 'Palermo', 'Italy', 'ESP', 38.12, 13.36, 'MED', 'WES', 'latin', 3, 4, 1, false, 6, 14, 7),
  ('PLM', 'Palma de Mallorca', 'Spain', 'ESP', 39.57, 2.65, 'MED', 'WES', 'latin', 2, 3, 0, false, 6, 9, 4),
  ('PAN', 'Panama City', 'Panama', 'ESP', 8.97, -79.53, 'NRT', 'PAC', 'latin', 3, 4, 1, false, 9, 12, 7),
  ('PAR', 'Paramaribo', 'Suriname', null, 5.87, -55.17, 'NOR', 'STH', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('PAT', 'Patras', 'Greece', 'OTT', 38.25, 21.73, 'ION', 'ADR', 'latin', 2, 3, 0, false, 6, 9, 4),
  ('PTT', 'Pattani', 'Thailand', 'AYU', 6.87, 101.25, 'GND', 'SOU', 'malay', 2, 3, 0, false, 4, 9, 4),
  ('PLY', 'Plymouth', 'United Kingdom', 'ENG', 50.37, -4.14, 'ENG', 'BRI', 'anglo', 3, 4, 1, false, 8, 11, 7),
  ('PON', 'Ponta Delgada', 'Portugal', 'PRT', 37.74, -25.67, 'NOR', 'ATL', 'latin', 3, 4, 1, false, 6, 12, 7),
  ('PLO', 'Port Louis', 'Mauritius', null, -20.16, 57.5, 'IND', 'EAS', 'guinean', 2, 3, 0, false, 4, 9, 4),
  ('POR', 'Port Royal', 'Jamaica', null, 17.94, -76.84, 'CAR', 'CAR', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('PTL', 'Portland', 'United States', null, 43.66, -70.26, 'NOR', 'NOR', 'anglo', 2, 3, 0, false, 4, 9, 4),
  ('OPO', 'Porto', 'Portugal', 'PRT', 41.15, -8.61, 'NOR', 'IBE', 'latin', 3, 4, 1, false, 6, 12, 7),
  ('PRT', 'Portobelo', 'Panama', 'ESP', 9.55, -79.65, 'CAR', 'CAR', 'latin', 3, 4, 1, false, 6, 13, 7),
  ('PTH', 'Portsmouth', 'United Kingdom', 'ENG', 50.81, -1.09, 'ENG', 'BRI', 'anglo', 3, 4, 1, false, 6, 12, 7),
  ('PUL', 'Pulicat', 'India', null, 13.42, 80.32, 'BYF', 'EST', 'indic', 2, 3, 0, false, 7, 9, 4),
  ('PUS', 'Pustozersk', 'Russia', 'RUS', 67.53, 52.64, 'BAR', 'SCA', 'nordic', 2, 3, 0, false, 4, 9, 4),
  ('QUA', 'Quanzhou', 'China', 'MNG', 24.91, 118.59, 'TAI', 'CHI', 'sinic', 3, 4, 1, false, 9, 14, 7),
  ('QUE', 'Quebec City', 'Canada', null, 46.82, -71.22, 'GCE', 'NOR', 'latin', 3, 2, 1, false, 8, 12, 7),
  ('REC', 'Recife', 'Brazil', 'PRT', -8.05, -34.88, 'SOU', 'STH', 'latin', 3, 4, 1, false, 6, 14, 7),
  ('REY', 'Reykjavik', 'Iceland', 'DNK', 64.15, -21.93, 'NOR', 'SCA', 'nordic', 2, 3, 0, false, 4, 9, 4),
  ('RHO', 'Rhodes', 'Greece', 'OTT', 36.43, 28.22, 'AEG', 'AEG', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('RIG', 'Riga', 'Latvia', 'POL', 56.95, 24.11, 'BAL', 'BAL', 'germanic', 3, 2, 1, false, 9, 14, 7),
  ('RIO', 'Rio de Janeiro', 'Brazil', 'PRT', -22.91, -43.21, 'SOU', 'STH', 'latin', 3, 4, 1, false, 8, 13, 7),
  ('ROT', 'Rotterdam', 'Netherlands', 'NLD', 51.92, 4.48, 'NEA', 'FRA', 'germanic', 3, 4, 1, false, 6, 14, 7),
  ('SAF', 'Safi', 'Morocco', 'MAR', 32.28, -9.23, 'NOR', 'MAG', 'islamic', 2, 3, 0, false, 4, 9, 4),
  ('SAI', 'Saint-Louis', 'Senegal', null, 16.03, -16.5, 'NOR', 'WST', 'guinean', 2, 3, 0, false, 4, 9, 4),
  ('SNT', 'Saint-Malo', 'France', 'FRA', 48.65, -2.03, 'ENG', 'FRA', 'latin', 3, 4, 1, false, 8, 13, 7),
  ('SAK', 'Sakai', 'Japan', 'JPN', 34.57, 135.48, 'SET', 'JAP', 'japanese', 3, 4, 1, false, 8, 14, 7),
  ('SAL', 'Sale', 'Morocco', 'MAR', 34.05, -6.82, 'NOR', 'MAG', 'islamic', 2, 3, 0, false, 4, 9, 4),
  ('SLV', 'Salvador', 'Brazil', 'PRT', -12.98, -38.49, 'SOU', 'STH', 'latin', 5, 5, 3, true, 12, 20, 11),
  ('SDG', 'San Diego', 'United States', null, 32.72, -117.16, 'NRT', 'PAC', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('SFR', 'San Francisco', 'United States', null, 37.78, -122.42, 'NRT', 'PAC', 'latin', 3, 4, 1, false, 6, 12, 7),
  ('SAN', 'San Juan', 'Puerto Rico', null, 18.47, -66.12, 'CAR', 'CAR', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('SNL', 'Sanlucar de Barrameda', 'Spain', 'ESP', 36.78, -6.35, 'NOR', 'IBE', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('TEN', 'Santa Cruz de Tenerife', 'Spain', 'ESP', 28.47, -16.25, 'NOR', 'ATL', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('SGO', 'Santo Domingo', 'Dominican Republic', 'ESP', 18.46, -69.94, 'CAR', 'CAR', 'latin', 3, 4, 1, false, 6, 14, 7),
  ('SOS', 'Santos', 'Brazil', 'PRT', -23.93, -46.33, 'SOU', 'STH', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('SAO', 'Sao Tome', 'São Tomé and Principe', null, 0.34, 6.73, 'GUL', 'WST', 'guinean', 2, 3, 0, false, 4, 9, 4),
  ('SET', 'Setubal', 'Portugal', 'PRT', 38.52, -8.89, 'NOR', 'IBE', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('SVQ', 'Seville', 'Spain', 'ESP', 37.39, -5.99, 'NOR', 'IBE', 'latin', 5, 2, 3, true, 12, 20, 11),
  ('SHI', 'Shimonoseki', 'Japan', 'JPN', 33.96, 130.94, 'SET', 'JAP', 'japanese', 2, 3, 0, false, 4, 9, 4),
  ('SOF', 'Sofala', 'Mozambique', 'PRT', -20.15, 34.72, 'MOZ', 'EAS', 'swahili', 2, 3, 0, false, 4, 9, 4),
  ('SOY', 'Soyo', 'Angola', 'PRT', -6.13, 12.37, 'SOU', 'WST', 'guinean', 2, 3, 0, false, 6, 9, 4),
  ('SPL', 'Split', 'Croatia', null, 43.51, 16.44, 'ADR', 'ADR', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('STA', 'St. Augustine', 'United States', null, 29.89, -81.31, 'NOR', 'NOR', 'anglo', 2, 3, 0, false, 4, 9, 4),
  ('STG', 'St. George''s', 'Bermuda', null, 32.38, -64.68, 'NOR', 'NOR', 'anglo', 2, 3, 0, false, 6, 9, 4),
  ('STJ', 'St. John''s', 'Canada', null, 47.56, -52.71, 'NOR', 'NOR', 'anglo', 3, 4, 1, false, 8, 12, 7),
  ('STO', 'Stockholm', 'Sweden', 'SWE', 59.33, 18.07, 'BAL', 'BAL', 'germanic', 3, 4, 1, false, 9, 14, 7),
  ('SUA', 'Suakin', 'Sudan', 'OTT', 19.1, 37.33, 'RED', 'EAS', 'swahili', 2, 3, 0, false, 6, 9, 4),
  ('SUE', 'Suez', 'Egypt', 'OTT', 29.97, 32.53, 'RED', 'ARA', 'islamic', 2, 3, 0, false, 6, 9, 4),
  ('SUR', 'Surabaya', 'Indonesia', null, -7.25, 112.74, 'JAV', 'SOU', 'malay', 2, 3, 0, false, 6, 9, 4),
  ('SRT', 'Surat', 'India', 'GUJ', 21.21, 72.84, 'ARA', 'WIA', 'indic', 5, 5, 3, true, 13, 20, 11),
  ('SYD', 'Sydney', 'Australia', null, -33.87, 151.21, 'TAS', 'OCE', 'oceanic', 2, 3, 0, false, 6, 9, 4),
  ('TAI', 'Tainan', 'Taiwan', null, 22.99, 120.19, 'TAI', 'CHI', 'sinic', 3, 4, 1, false, 6, 12, 7),
  ('TAL', 'Tallinn', 'Estonia', null, 59.44, 24.75, 'BAL', 'BAL', 'germanic', 3, 4, 1, false, 6, 14, 7),
  ('TAN', 'Tangier', 'Morocco', 'MAR', 35.77, -5.8, 'MED', 'MAG', 'islamic', 2, 3, 0, false, 4, 9, 4),
  ('TER', 'Ternate', 'Indonesia', null, 0.78, 127.37, 'MOL', 'SOU', 'malay', 3, 4, 1, false, 6, 12, 7),
  ('THA', 'Thanlyin', 'Myanmar', null, 16.77, 96.25, 'AND', 'EST', 'indic', 2, 2, 0, false, 4, 9, 4),
  ('THE', 'Thessaloniki', 'Greece', 'OTT', 40.64, 22.94, 'AEG', 'AEG', 'islamic', 3, 4, 1, false, 6, 13, 7),
  ('TID', 'Tidore', 'Indonesia', null, 0.68, 127.4, 'MOL', 'SOU', 'malay', 2, 3, 0, false, 4, 9, 4),
  ('TOK', 'Tokyo', 'Japan', 'JPN', 35.69, 139.69, 'NRT', 'JAP', 'japanese', 5, 5, 3, true, 10, 20, 11),
  ('TON', 'Tongyeong', 'South Korea', 'JOS', 34.85, 128.42, 'KOR', 'KOR', 'korean', 2, 3, 0, false, 4, 9, 4),
  ('TOR', 'Torshavn', 'Faroe Islands', null, 62.01, -6.77, 'NRW', 'SCA', 'nordic', 2, 3, 0, false, 4, 9, 4),
  ('TOU', 'Toulon', 'France', 'FRA', 43.13, 5.93, 'MED', 'WES', 'latin', 2, 3, 0, false, 6, 9, 4),
  ('TRA', 'Trabzon', 'Turkey', 'OTT', 41.01, 39.72, 'BLA', 'AEG', 'islamic', 2, 3, 0, false, 6, 9, 4),
  ('TRI', 'Tripoli', 'Lebanon', 'OTT', 34.44, 35.83, 'MED', 'LEV', 'islamic', 2, 3, 0, false, 6, 9, 4),
  ('TRP', 'Tripoli', 'Libya', 'OTT', 32.89, 13.19, 'MED', 'MAG', 'islamic', 2, 3, 0, false, 4, 9, 4),
  ('TRO', 'Trondheim', 'Norway', 'DNK', 63.44, 10.4, 'NRW', 'SCA', 'nordic', 2, 3, 0, false, 4, 9, 4),
  ('TSU', 'Tsushima', 'Japan', 'JPN', 34.2, 129.29, 'KOR', 'JAP', 'japanese', 2, 3, 0, false, 7, 9, 4),
  ('TUN', 'Tunis', 'Tunisia', 'OTT', 36.8, 10.18, 'MED', 'MAG', 'islamic', 3, 4, 1, false, 8, 14, 7),
  ('TUR', 'Turku', 'Finland', 'SWE', 60.45, 22.27, 'BAL', 'BAL', 'germanic', 2, 3, 0, false, 4, 9, 4),
  ('ULS', 'Ulsan', 'South Korea', 'JOS', 35.55, 129.32, 'SFJ', 'KOR', 'korean', 2, 3, 0, false, 6, 9, 4),
  ('VAL', 'Valencia', 'Spain', 'ESP', 39.47, -0.38, 'MED', 'IBE', 'latin', 3, 4, 1, false, 6, 14, 7),
  ('VLL', 'Valletta', 'Malta', null, 35.9, 14.51, 'MED', 'WES', 'latin', 3, 4, 1, false, 8, 12, 7),
  ('VLP', 'Valparaiso', 'Chile', 'ESP', -33.05, -71.62, 'STH', 'PAC', 'latin', 2, 3, 0, false, 6, 9, 4),
  ('VAR', 'Vardo', 'Norway', 'DNK', 70.37, 31.11, 'BAR', 'SCA', 'nordic', 2, 3, 0, false, 4, 9, 4),
  ('VEN', 'Venice', 'Italy', 'VEN', 45.44, 12.33, 'ADR', 'ADR', 'latin', 5, 5, 3, true, 15, 20, 11),
  ('VER', 'Veracruz', 'Mexico', 'ESP', 19.19, -96.15, 'GCO', 'CAR', 'latin', 5, 5, 3, true, 10, 20, 11),
  ('VIS', 'Visby', 'Sweden', 'SWE', 57.63, 18.31, 'BAL', 'BAL', 'germanic', 2, 3, 0, false, 6, 9, 4),
  ('WLG', 'Wellington', 'New Zealand', null, -41.29, 174.78, 'TAS', 'OCE', 'oceanic', 2, 3, 0, false, 4, 9, 4),
  ('WIL', 'Willemstad', 'Curaçao', null, 12.11, -68.93, 'CAR', 'CAR', 'latin', 2, 3, 0, false, 4, 9, 4),
  ('XIA', 'Xiamen', 'China', 'MNG', 24.48, 118.08, 'TAI', 'CHI', 'sinic', 3, 4, 1, false, 8, 14, 7),
  ('YEO', 'Yeosu', 'South Korea', 'JOS', 34.76, 127.66, 'KOR', 'KOR', 'korean', 3, 4, 1, false, 6, 12, 7),
  ('ZAK', 'Zakynthos', 'Greece', 'VEN', 37.8, 20.75, 'ION', 'ADR', 'latin', 2, 3, 0, false, 6, 9, 4),
  ('ZAN', 'Zanzibar', 'Tanzania', null, -6.17, 39.2, 'IND', 'EAS', 'swahili', 3, 4, 1, false, 9, 14, 7);

create temporary table want_goods_0217 (
  code text, name text, base_value numeric, bulk numeric, perish numeric, category text, mask text[],
  origin text[], entrepot text[], industry boolean
);
insert into want_goods_0217 values
  ('black-pepper', 'Black Pepper', 30.00, 0.600, 0.000, 'spice', '{}', '{SOU,WIA,WST}', '{ADE,ALE,AMS,ARP,HOR,IST,JED,LIS}', false),
  ('cloves', 'Cloves', 210.00, 0.600, 0.000, 'spice', '{}', '{SOU}', '{}', false),
  ('nutmeg', 'Nutmeg', 240.00, 0.600, 0.000, 'spice', '{}', '{SOU}', '{}', false),
  ('mace', 'Mace', 270.00, 0.600, 0.000, 'spice', '{}', '{SOU}', '{}', false),
  ('cinnamon', 'Cinnamon', 120.00, 0.600, 0.000, 'spice', '{}', '{EST}', '{KOC,LIS,OLD}', false),
  ('ginger', 'Ginger', 37.00, 0.600, 0.000, 'spice', '{}', '{CAR,EST,STH,WIA}', '{}', false),
  ('cardamom', 'Cardamom', 100.00, 0.600, 0.000, 'spice', '{}', '{WIA}', '{}', false),
  ('long-pepper', 'Long Pepper', 37.00, 0.600, 0.000, 'spice', '{}', '{EST}', '{}', false),
  ('cubeb', 'Cubeb', 82.00, 0.600, 0.000, 'spice', '{}', '{SOU}', '{}', false),
  ('grains-of-paradise', 'Grains of Paradise', 45.00, 0.600, 0.000, 'spice', '{}', '{WST}', '{}', false),
  ('cassia', 'Cassia', 40.00, 0.600, 0.000, 'spice', '{}', '{CHI,SOU}', '{}', false),
  ('turmeric', 'Turmeric', 21.00, 0.600, 0.000, 'spice', '{}', '{EST,WIA}', '{}', false),
  ('saffron', 'Saffron', 390.00, 0.600, 0.000, 'spice', '{}', '{ARA,IBE}', '{}', false),
  ('chillies', 'Chillies', 18.00, 0.600, 0.000, 'spice', '{}', '{CAR,PAC,SOU,STH,WIA}', '{}', false),
  ('vanilla', 'Vanilla', 270.00, 0.600, 0.000, 'spice', '{}', '{CAR}', '{}', false),
  ('anise', 'Aniseed', 16.50, 0.600, 0.000, 'spice', '{}', '{ADR,IBE,WES}', '{}', false),
  ('cumin', 'Cumin', 19.50, 0.600, 0.000, 'spice', '{}', '{LEV,WIA}', '{}', false),
  ('coriander', 'Coriander', 16.50, 0.600, 0.000, 'spice', '{}', '{IBE,LEV}', '{}', false),
  ('galangal', 'Galangal', 34.00, 0.600, 0.000, 'spice', '{}', '{SOU}', '{}', false),
  ('star-anise', 'Star Anise', 40.00, 0.600, 0.000, 'spice', '{}', '{CHI,SOU}', '{}', false),
  ('allspice', 'Allspice', 48.00, 0.600, 0.000, 'spice', '{}', '{CAR}', '{}', false),
  ('zedoary', 'Zedoary', 45.00, 0.600, 0.000, 'spice', '{}', '{EST,SOU}', '{}', false),
  ('wool-cloth', 'Woollen Cloth', 18.00, 0.900, 0.000, 'cloth', '{}', '{ADR,AEG,BRI,FRA,IBE,MAG,SCA,WES}', '{HAM}', true),
  ('linen', 'Linen', 16.50, 0.900, 0.000, 'cloth', '{}', '{BAL,BRI,FRA,LEV}', '{}', true),
  ('cotton-cloth', 'Cotton Cloth', 21.00, 0.900, 0.000, 'cloth', '{}', '{ATL,EAS,EST,JAP,KOR,WES,WIA,WST}', '{JED}', true),
  ('muslin', 'Muslin', 92.00, 0.900, 0.000, 'cloth', '{}', '{EST}', '{}', true),
  ('chintz', 'Chintz', 52.00, 0.900, 0.000, 'cloth', '{}', '{EST}', '{}', true),
  ('silk-cloth', 'Silk Cloth', 122.00, 0.900, 0.000, 'cloth', '{}', '{ADR,AEG,ARA,CHI,IBE,JAP,WES,WIA}', '{ACA,MNL}', true),
  ('silk-raw', 'Raw Silk', 108.00, 0.900, 0.000, 'cloth', '{}', '{ADR,AEG,ARA,CHI,EST,IBE,LEV,SOU,WES}', '{FUK,HIR}', true),
  ('carpets', 'Carpets', 92.00, 0.900, 0.000, 'cloth', '{}', '{AEG,ARA}', '{}', true),
  ('ramie-cloth', 'Ramie Cloth', 21.00, 0.900, 0.000, 'cloth', '{}', '{CHI,KOR}', '{TSU}', true),
  ('says-serges', 'Says & Serges', 19.50, 0.900, 0.000, 'cloth', '{}', '{FRA}', '{}', true),
  ('velvet', 'Velvet', 225.00, 0.900, 0.000, 'cloth', '{}', '{ADR,WES}', '{}', true),
  ('lace', 'Lace', 120.00, 0.900, 0.000, 'cloth', '{}', '{ADR,FRA}', '{}', true),
  ('tapestries', 'Tapestries', 240.00, 0.900, 0.000, 'cloth', '{}', '{FRA}', '{}', true),
  ('batik', 'Batik Cloth', 45.00, 0.900, 0.000, 'cloth', '{}', '{SOU}', '{}', true),
  ('raffia-cloth', 'Raffia Cloth', 18.00, 0.900, 0.000, 'cloth', '{}', '{WST}', '{}', true),
  ('barkcloth', 'Barkcloth', 10.50, 0.900, 0.000, 'cloth', '{}', '{OCE}', '{}', true),
  ('camlets', 'Camlets', 58.00, 0.900, 0.000, 'cloth', '{}', '{AEG}', '{}', true),
  ('quilts', 'Bengal Quilts', 64.00, 0.900, 0.000, 'cloth', '{}', '{EST}', '{}', true),
  ('shawls', 'Kashmir Shawls', 210.00, 0.900, 0.000, 'cloth', '{}', '{WIA}', '{}', true),
  ('fustian', 'Fustian', 21.00, 0.900, 0.000, 'cloth', '{}', '{BAL,WES}', '{}', true),
  ('gold-thread', 'Gold Thread', 135.00, 0.900, 0.000, 'cloth', '{}', '{LEV,WES}', '{}', true),
  ('stockings', 'Knitted Stockings', 24.00, 0.900, 0.000, 'cloth', '{}', '{BRI,FRA}', '{}', true),
  ('felt-hats', 'Felt Hats', 84.00, 0.900, 0.000, 'cloth', '{}', '{BRI,FRA}', '{}', true),
  ('gold', 'Gold', 660.00, 0.800, 0.000, 'metal', '{}', '{CAR,CHI,EAS,MAG,PAC,SOU,WST}', '{}', true),
  ('silver', 'Silver', 450.00, 0.800, 0.000, 'metal', '{}', '{ADR,CAR,JAP,KOR,PAC,STH}', '{CAD,MAC,MNL,SVQ}', true),
  ('copper', 'Copper', 26.00, 0.800, 0.000, 'metal', '{}', '{AEG,ARA,BAL,JAP,MAG,PAC,SCA,WST}', '{}', true),
  ('tin', 'Tin', 40.00, 0.800, 0.000, 'metal', '{}', '{BRI,EST,SOU}', '{}', true),
  ('iron', 'Iron', 12.00, 0.800, 0.000, 'metal', '{}', '{BAL,BRI,CHI,IBE,JAP,KOR,SCA,WST}', '{}', true),
  ('lead', 'Lead', 10.50, 0.800, 0.000, 'metal', '{}', '{BAL,BRI}', '{}', true),
  ('quicksilver', 'Quicksilver', 430.00, 0.800, 0.000, 'metal', '{}', '{ADR,IBE,PAC}', '{}', true),
  ('wootz-steel', 'Wootz Steel', 105.00, 0.800, 0.000, 'metal', '{}', '{EST,WIA}', '{}', true),
  ('firearms', 'Muskets', 126.00, 0.800, 0.000, 'guns', '{}', '{FRA,JAP}', '{}', true),
  ('cannon', 'Cannon', 150.00, 0.800, 0.000, 'guns', '{}', '{BAL,BRI,SCA}', '{}', true),
  ('brassware', 'Brassware & Manillas', 24.00, 0.800, 0.000, 'crafts', '{}', '{BAL,FRA}', '{}', true),
  ('pewter', 'Pewterware', 27.00, 0.800, 0.000, 'crafts', '{}', '{BRI}', '{}', true),
  ('copper-cash', 'Copper Cash', 25.50, 0.800, 0.000, 'metal', '{}', '{CHI}', '{}', true),
  ('smallwares', 'Nuremberg Smallwares', 22.50, 0.800, 0.000, 'crafts', '{}', '{BAL,BRI,FRA}', '{}', true),
  ('armour', 'Armour', 90.00, 0.800, 0.000, 'weapons', '{}', '{WES}', '{}', true),
  ('gunpowder', 'Gunpowder', 60.00, 0.800, 0.000, 'guns', '{}', '{ADR,BRI,FRA}', '{}', true),
  ('porcelain', 'Porcelain', 84.00, 0.300, 0.000, 'crafts', '{}', '{CHI,JAP,SOU}', '{ACA,LIS,OLD}', false),
  ('lacquerware', 'Lacquerware', 78.00, 0.300, 0.000, 'crafts', '{}', '{CHI,JAP,KOR,SOU}', '{}', false),
  ('glassware', 'Glassware', 57.00, 0.300, 0.000, 'crafts', '{}', '{ADR,IBE}', '{}', false),
  ('pearls', 'Pearls', 330.00, 0.300, 0.000, 'gems', '{}', '{ARA,CAR,CHI,EST,PAC,WIA}', '{}', false),
  ('diamonds', 'Diamonds', 540.00, 0.300, 0.000, 'gems', '{}', '{EST,SOU}', '{ARP}', false),
  ('ivory', 'Ivory', 127.00, 0.300, 0.000, 'gems', '{}', '{EAS,EST,SOU,WST}', '{LIS}', false),
  ('ambergris', 'Ambergris', 600.00, 0.300, 0.000, 'medicine', '{}', '{ARA,ATL,EAS,NOR,SOU,WIA}', '{}', false),
  ('musk', 'Musk', 450.00, 0.300, 0.000, 'medicine', '{}', '{CHI}', '{}', false),
  ('coral', 'Coral', 69.00, 0.300, 0.000, 'gems', '{}', '{IBE,MAG,WES}', '{}', false),
  ('amber', 'Amber', 102.00, 0.300, 0.000, 'gems', '{}', '{BAL}', '{}', false),
  ('frankincense', 'Frankincense', 60.00, 0.300, 0.000, 'medicine', '{}', '{ARA,EAS}', '{}', false),
  ('myrrh', 'Myrrh', 63.00, 0.300, 0.000, 'medicine', '{}', '{ARA,EAS}', '{}', false),
  ('rubies', 'Rubies', 480.00, 0.300, 0.000, 'gems', '{}', '{EST}', '{}', false),
  ('emeralds', 'Emeralds', 510.00, 0.300, 0.000, 'gems', '{}', '{CAR}', '{}', false),
  ('carnelian', 'Carnelian & Agate', 60.00, 0.300, 0.000, 'gems', '{}', '{WIA}', '{}', false),
  ('books', 'Printed Books', 69.00, 0.300, 0.000, 'books', '{}', '{ADR,FRA}', '{}', false),
  ('paper', 'Paper', 24.00, 0.300, 0.000, 'books', '{}', '{CHI,FRA,IBE,JAP,KOR,WES}', '{}', false),
  ('tortoiseshell', 'Tortoiseshell', 105.00, 0.300, 0.000, 'gems', '{}', '{CAR,JAP,SOU}', '{}', false),
  ('mastic', 'Mastic', 118.00, 0.300, 0.000, 'medicine', '{}', '{AEG}', '{}', false),
  ('civet', 'Civet', 420.00, 0.300, 0.000, 'medicine', '{}', '{EAS}', '{}', false),
  ('rosewater', 'Rosewater', 54.00, 0.300, 0.000, 'medicine', '{}', '{ARA,LEV}', '{}', false),
  ('clocks', 'Clocks & Instruments', 270.00, 0.300, 0.000, 'art', '{}', '{BAL,FRA}', '{}', false),
  ('paintings', 'Paintings', 126.00, 0.300, 0.000, 'art', '{}', '{FRA}', '{}', false),
  ('bezoar', 'Bezoar Stones', 360.00, 0.300, 0.000, 'medicine', '{}', '{ARA,SOU,WIA}', '{}', false),
  ('rhino-horn', 'Rhinoceros Horn', 135.00, 0.300, 0.000, 'medicine', '{}', '{EAS,EST,SOU,WST}', '{}', false),
  ('lapis-lazuli', 'Lapis Lazuli', 390.00, 0.300, 0.000, 'gems', '{}', '{ARA}', '{}', false),
  ('turquoise', 'Turquoise', 126.00, 0.300, 0.000, 'gems', '{}', '{ARA}', '{}', false),
  ('folding-fans', 'Folding Fans', 48.00, 0.300, 0.000, 'crafts', '{}', '{JAP}', '{}', false),
  ('silver-plate', 'Silverware & Plate', 150.00, 0.300, 0.000, 'crafts', '{}', '{BAL,IBE}', '{}', false),
  ('majolica', 'Majolica', 57.00, 0.300, 0.000, 'crafts', '{}', '{IBE,WES}', '{}', false),
  ('celadon', 'Celadon Ware', 84.00, 0.300, 0.000, 'crafts', '{}', '{KOR,SOU}', '{}', false),
  ('stoneware', 'Rhenish Stoneware', 21.00, 0.300, 0.000, 'crafts', '{}', '{BAL,FRA}', '{}', false),
  ('martaban-jars', 'Martaban Jars', 51.00, 0.300, 0.000, 'crafts', '{}', '{EST}', '{}', false),
  ('glass-beads', 'Trade Beads', 22.50, 0.300, 0.000, 'crafts', '{}', '{ADR,FRA}', '{}', false),
  ('sea-charts', 'Sea Charts & Globes', 240.00, 0.300, 0.000, 'art', '{}', '{FRA,IBE}', '{}', false),
  ('ink-sticks', 'Ink & Brushes', 54.00, 0.300, 0.000, 'books', '{}', '{CHI,KOR}', '{}', false),
  ('sword-blades', 'Sword Blades', 143.00, 0.300, 0.000, 'weapons', '{}', '{BAL,IBE,JAP}', '{}', false),
  ('theriac', 'Venice Treacle', 120.00, 0.300, 0.000, 'medicine', '{}', '{ADR}', '{}', false),
  ('parrots', 'Parrots & Monkeys', 60.00, 0.300, 0.000, 'animals', '{}', '{STH,WST}', '{}', false),
  ('gyrfalcons', 'Gyrfalcons', 450.00, 0.300, 0.000, 'animals', '{}', '{SCA}', '{}', false),
  ('paradise-plumes', 'Bird-of-Paradise Plumes', 270.00, 0.300, 0.000, 'crafts', '{}', '{OCE,SOU}', '{}', false),
  ('wheat', 'Wheat', 8.00, 1.000, 0.002, 'grain', '{}', '{ADR,AEG,ARA,ATL,BAL,EAS,FRA,IBE,KOR,LEV,MAG,NOR,PAC,STH,WES}', '{}', false),
  ('rice', 'Rice', 8.80, 1.000, 0.002, 'grain', '{}', '{CHI,EST,IBE,JAP,KOR,OCE,SOU,WIA}', '{}', false),
  ('sugar', 'Sugar', 45.00, 1.000, 0.001, 'food', '{}', '{ATL,CAR,CHI,EAS,EST,JAP,LEV,MAG,SOU,STH,WES,WST}', '{ARP,LIS,NAN}', false),
  ('salt', 'Salt', 6.50, 1.000, 0.000, 'food', '{}', '{ADR,AEG,ARA,ATL,BAL,BRI,CAR,CHI,EAS,EST,FRA,IBE,JAP,KOR,LEV,MAG,NOR,OCE,WES,WIA,WST}', '{}', false),
  ('olive-oil', 'Olive Oil', 21.00, 1.000, 0.001, 'food', '{}', '{ADR,AEG,IBE,LEV,MAG,WES}', '{}', false),
  ('wine', 'Wine', 24.00, 1.000, 0.000, 'drink', '{islamic,swahili}', '{ADR,AEG,ATL,EAS,FRA,IBE,LEV,PAC,WES}', '{}', false),
  ('dried-fish', 'Dried & Salt Fish', 11.00, 1.000, 0.004, 'food', '{}', '{ARA,ATL,BAL,BRI,CHI,EAS,FRA,IBE,JAP,KOR,NOR,OCE,SCA,SOU,WES,WIA}', '{}', false),
  ('herring', 'Herring', 13.50, 1.000, 0.004, 'food', '{}', '{BAL,BRI,FRA,SCA}', '{}', false),
  ('cheese', 'Cheese', 16.50, 1.000, 0.004, 'food', '{}', '{AEG,ATL,BRI,FRA,WES}', '{}', false),
  ('salted-beef', 'Salt Meat', 18.00, 1.000, 0.003, 'food', '{indic,japanese}', '{ATL,BAL,BRI,CAR,EAS,FRA,NOR,STH}', '{}', false),
  ('coffee', 'Coffee', 118.00, 1.000, 0.000, 'drink', '{}', '{ARA}', '{ALE,MRS}', false),
  ('tea', 'Tea', 112.00, 1.000, 0.000, 'drink', '{}', '{CHI,JAP}', '{}', false),
  ('cacao', 'Cacao', 60.00, 1.000, 0.000, 'drink', '{}', '{CAR,PAC,STH}', '{}', false),
  ('dried-fruit', 'Raisins & Currants', 19.50, 1.000, 0.003, 'food', '{}', '{ADR,AEG,ATL,FRA,IBE,LEV,MAG,WES}', '{}', false),
  ('rye', 'Rye', 7.20, 1.000, 0.002, 'grain', '{}', '{BAL}', '{}', false),
  ('barley', 'Barley', 7.00, 1.000, 0.002, 'grain', '{}', '{BAL,BRI,SCA}', '{}', false),
  ('beer', 'Beer', 15.00, 1.000, 0.003, 'drink', '{islamic,swahili}', '{BAL,BRI,FRA}', '{}', false),
  ('sake', 'Sake', 24.00, 1.000, 0.002, 'drink', '{islamic,swahili}', '{JAP}', '{}', false),
  ('rum', 'Rum', 42.00, 1.000, 0.000, 'drink', '{islamic,swahili}', '{CAR}', '{}', false),
  ('brandy', 'Brandy', 45.00, 1.000, 0.000, 'drink', '{islamic,swahili}', '{FRA}', '{}', false),
  ('arrack', 'Arrack', 39.00, 1.000, 0.000, 'drink', '{islamic,swahili}', '{EST,SOU,WIA}', '{}', false),
  ('butter', 'Butter', 16.50, 1.000, 0.004, 'food', '{}', '{BAL,BRI,FRA}', '{}', false),
  ('honey', 'Honey', 18.00, 1.000, 0.000, 'food', '{}', '{AEG,BAL,MAG,WES}', '{}', false),
  ('dates', 'Dates', 18.00, 1.000, 0.002, 'food', '{}', '{ARA,LEV,MAG}', '{}', false),
  ('figs', 'Figs', 16.50, 1.000, 0.002, 'food', '{}', '{AEG,IBE,MAG,WES}', '{}', false),
  ('citrus', 'Lemons & Oranges', 18.00, 1.000, 0.005, 'food', '{}', '{ADR,IBE,MAG,WES}', '{}', false),
  ('almonds', 'Almonds', 21.00, 1.000, 0.001, 'food', '{}', '{ADR,IBE,MAG,WES}', '{}', false),
  ('coconuts', 'Coconuts & Copra', 9.50, 1.000, 0.002, 'food', '{}', '{EAS,EST,OCE,SOU,WIA}', '{}', false),
  ('sago', 'Sago', 8.80, 1.000, 0.002, 'grain', '{}', '{OCE,SOU}', '{}', false),
  ('maize', 'Maize', 8.00, 1.000, 0.002, 'grain', '{}', '{CAR,NOR,PAC,STH,WST}', '{}', false),
  ('cassava', 'Cassava Flour', 8.00, 1.000, 0.002, 'grain', '{}', '{CAR,STH,WST}', '{}', false),
  ('caviar', 'Caviar', 90.00, 1.000, 0.004, 'food', '{}', '{AEG,SCA}', '{}', false),
  ('salted-tuna', 'Salt Tuna', 16.50, 1.000, 0.004, 'food', '{}', '{IBE,MAG,WES}', '{}', false),
  ('soy-sauce', 'Soy Sauce', 21.00, 1.000, 0.000, 'food', '{}', '{CHI,JAP,KOR}', '{}', false),
  ('ghee', 'Ghee', 18.00, 1.000, 0.002, 'food', '{}', '{WIA}', '{}', false),
  ('sesame-oil', 'Sesame Oil', 18.00, 1.000, 0.001, 'food', '{}', '{ARA,EST,LEV}', '{}', false),
  ('palm-oil', 'Palm Oil', 10.50, 1.000, 0.001, 'food', '{}', '{WST}', '{}', false),
  ('birds-nests', 'Edible Birds’ Nests', 240.00, 1.000, 0.000, 'food', '{}', '{SOU}', '{}', false),
  ('sharks-fin', 'Shark Fin', 45.00, 1.000, 0.001, 'food', '{}', '{CHI,JAP,OCE,SOU}', '{}', false),
  ('trepang', 'Trepang', 42.00, 1.000, 0.001, 'food', '{}', '{OCE,SOU}', '{}', false),
  ('dried-abalone', 'Dried Abalone', 54.00, 1.000, 0.001, 'food', '{}', '{JAP,KOR}', '{}', false),
  ('seaweed', 'Dried Seaweed', 8.00, 1.000, 0.001, 'food', '{}', '{JAP,KOR}', '{}', false),
  ('palm-sugar', 'Palm Sugar', 9.50, 1.000, 0.001, 'food', '{}', '{EST,SOU,WIA}', '{}', false),
  ('molasses', 'Molasses', 15.00, 1.000, 0.001, 'food', '{}', '{ATL,CAR,STH}', '{}', false),
  ('tamarind', 'Tamarind', 19.50, 1.000, 0.001, 'food', '{}', '{EST,SOU,WIA}', '{}', false),
  ('hazelnuts', 'Hazelnuts', 15.00, 1.000, 0.001, 'food', '{}', '{AEG}', '{}', false),
  ('pistachios', 'Pistachios', 36.00, 1.000, 0.001, 'food', '{}', '{ARA,LEV}', '{}', false),
  ('lychees', 'Dried Lychees', 21.00, 1.000, 0.002, 'food', '{}', '{CHI}', '{}', false),
  ('tobacco', 'Tobacco', 51.00, 1.200, 0.000, 'tobacco', '{}', '{AEG,CAR,EST,LEV,NOR,STH}', '{}', false),
  ('indigo', 'Indigo', 118.00, 1.200, 0.000, 'dye', '{}', '{ARA,ATL,CAR,EST,SOU,WIA}', '{BOR,SVQ}', false),
  ('cochineal', 'Cochineal', 270.00, 1.200, 0.000, 'dye', '{}', '{CAR,PAC}', '{SVQ}', false),
  ('brazilwood', 'Brazilwood', 48.00, 1.200, 0.000, 'dye', '{}', '{STH}', '{}', false),
  ('logwood', 'Logwood', 45.00, 1.200, 0.000, 'dye', '{}', '{CAR}', '{}', false),
  ('alum', 'Alum', 24.00, 1.200, 0.000, 'dye', '{}', '{ADR,AEG,WES}', '{BRU}', false),
  ('saltpetre', 'Saltpetre', 57.00, 1.200, 0.000, 'guns', '{}', '{EST,WIA}', '{}', false),
  ('sulphur', 'Sulphur', 25.50, 1.200, 0.000, 'guns', '{}', '{JAP,SCA,WES}', '{}', false),
  ('hides', 'Hides', 21.00, 1.200, 0.001, 'cloth', '{}', '{ADR,AEG,ARA,ATL,BAL,BRI,CAR,CHI,EAS,IBE,JAP,KOR,LEV,MAG,NOR,PAC,SOU,STH,WES,WST}', '{}', false),
  ('furs', 'Furs', 99.00, 1.200, 0.001, 'cloth', '{}', '{AEG,BAL,JAP,NOR,SCA}', '{LAR,SNT}', false),
  ('wax', 'Beeswax', 27.00, 1.200, 0.000, 'crafts', '{}', '{ADR,BAL,CAR,EAS,MAG,OCE,PAC,SCA,SOU,STH,WST}', '{}', false),
  ('cotton-raw', 'Raw Cotton', 18.00, 1.200, 0.000, 'cloth', '{}', '{AEG,CAR,EST,LEV,MAG,STH,WIA}', '{MRS}', false),
  ('wool-raw', 'Raw Wool', 19.50, 1.200, 0.000, 'cloth', '{}', '{ADR,AEG,BRI,IBE,MAG,OCE,SCA,WES}', '{CLS}', false),
  ('gum-arabic', 'Gum Arabic', 54.00, 1.200, 0.000, 'dye', '{}', '{ARA,EAS,WST}', '{}', false),
  ('sandalwood', 'Sandalwood', 105.00, 1.200, 0.000, 'medicine', '{}', '{OCE,SOU,WIA}', '{NAG}', false),
  ('ginseng', 'Ginseng', 126.00, 1.200, 0.000, 'medicine', '{}', '{CHI,KOR}', '{TSU}', false),
  ('horses', 'Horses', 135.00, 1.200, 0.000, 'animals', '{}', '{ARA,ATL,JAP,KOR,LEV,MAG}', '{DIU,OLD}', false),
  ('potash', 'Potash', 11.00, 1.200, 0.000, 'dye', '{}', '{BAL,SCA}', '{}', false),
  ('tallow', 'Tallow', 9.50, 1.200, 0.000, 'crafts', '{}', '{BAL,CAR,PAC,SCA,STH}', '{}', false),
  ('woad', 'Woad', 22.50, 1.200, 0.000, 'dye', '{}', '{ATL,FRA,WES}', '{}', false),
  ('madder', 'Madder', 24.00, 1.200, 0.000, 'dye', '{}', '{AEG,FRA}', '{}', false),
  ('lac', 'Lac & Shellac', 45.00, 1.200, 0.000, 'dye', '{}', '{EST}', '{}', false),
  ('annatto', 'Annatto', 24.00, 1.200, 0.000, 'dye', '{}', '{CAR,STH}', '{}', false),
  ('orchil', 'Orchil', 21.00, 1.200, 0.000, 'dye', '{}', '{ATL,MAG}', '{}', false),
  ('henna', 'Henna', 18.00, 1.200, 0.000, 'dye', '{}', '{ARA,EAS,LEV,MAG}', '{}', false),
  ('camphor', 'Borneo Camphor', 300.00, 1.200, 0.000, 'medicine', '{}', '{JAP,SOU}', '{}', false),
  ('benzoin', 'Benzoin', 105.00, 1.200, 0.000, 'medicine', '{}', '{SOU}', '{}', false),
  ('aloeswood', 'Aloeswood', 330.00, 1.200, 0.000, 'medicine', '{}', '{CHI,SOU}', '{}', false),
  ('dragons-blood', 'Dragon’s Blood', 90.00, 1.200, 0.000, 'dye', '{}', '{ARA}', '{}', false),
  ('socotra-aloes', 'Socotrine Aloes', 54.00, 1.200, 0.000, 'medicine', '{}', '{ARA}', '{}', false),
  ('myrobalans', 'Myrobalans', 21.00, 1.200, 0.000, 'medicine', '{}', '{EST,WIA}', '{}', false),
  ('sappanwood', 'Sappanwood', 27.00, 1.200, 0.000, 'dye', '{}', '{EST,SOU}', '{NAH}', false),
  ('red-sanders', 'Red Sanders', 25.50, 1.200, 0.000, 'dye', '{}', '{EST}', '{}', false),
  ('camwood', 'Camwood', 24.00, 1.200, 0.000, 'dye', '{}', '{WST}', '{}', false),
  ('ebony', 'Ebony', 48.00, 1.200, 0.000, 'crafts', '{}', '{EAS,EST}', '{}', false),
  ('rattan', 'Rattan', 9.00, 1.200, 0.000, 'crafts', '{}', '{SOU}', '{}', false),
  ('opium', 'Opium', 120.00, 1.200, 0.000, 'medicine', '{}', '{EST,WIA}', '{}', false),
  ('areca-nuts', 'Areca Nuts', 16.50, 1.200, 0.000, 'medicine', '{}', '{EST,SOU,WIA}', '{}', false),
  ('kola-nuts', 'Kola Nuts', 19.50, 1.200, 0.000, 'medicine', '{}', '{WST}', '{}', false),
  ('sarsaparilla', 'Sarsaparilla', 51.00, 1.200, 0.000, 'medicine', '{}', '{CAR}', '{}', false),
  ('sassafras', 'Sassafras', 27.00, 1.200, 0.000, 'medicine', '{}', '{NOR}', '{}', false),
  ('senna', 'Senna', 45.00, 1.200, 0.000, 'medicine', '{}', '{ARA,EAS,LEV}', '{}', false),
  ('rhubarb', 'Chinese Rhubarb', 118.00, 1.200, 0.000, 'medicine', '{}', '{CHI}', '{}', false),
  ('china-root', 'China Root', 51.00, 1.200, 0.000, 'medicine', '{}', '{CHI}', '{}', false),
  ('mother-of-pearl', 'Mother-of-Pearl', 48.00, 1.200, 0.000, 'gems', '{}', '{ARA,JAP,SOU}', '{}', false),
  ('cowries', 'Cowrie Shells', 18.00, 1.200, 0.000, 'crafts', '{}', '{EST,WIA}', '{}', false),
  ('chank-shells', 'Chank Shells', 18.00, 1.200, 0.000, 'crafts', '{}', '{EST}', '{}', false),
  ('coir', 'Coir', 9.50, 1.200, 0.000, 'ship-supplies', '{}', '{EST,SOU,WIA}', '{}', false),
  ('gallnuts', 'Gallnuts', 42.00, 1.200, 0.000, 'dye', '{}', '{AEG,ARA,LEV}', '{}', false),
  ('cinchona-bark', 'Jesuit’s Bark', 210.00, 1.200, 0.000, 'medicine', '{}', '{PAC}', '{}', false),
  ('ostrich-feathers', 'Ostrich Feathers', 60.00, 1.200, 0.000, 'crafts', '{}', '{MAG,WST}', '{}', false),
  ('sponges', 'Sponges', 21.00, 1.200, 0.000, 'crafts', '{}', '{ADR,AEG}', '{}', false),
  ('baleen', 'Whalebone', 54.00, 1.200, 0.000, 'crafts', '{}', '{BRI,FRA,IBE,NOR,SCA}', '{}', false),
  ('sealskins', 'Sealskins', 18.00, 1.200, 0.000, 'cloth', '{}', '{NOR,OCE,SCA}', '{}', false),
  ('walrus-ivory', 'Walrus Ivory', 120.00, 1.200, 0.000, 'gems', '{}', '{SCA}', '{}', false),
  ('narwhal-horn', 'Narwhal Horn', 540.00, 1.200, 0.000, 'gems', '{}', '{SCA}', '{}', false),
  ('eiderdown', 'Eiderdown', 60.00, 1.200, 0.000, 'crafts', '{}', '{SCA}', '{}', false),
  ('coal', 'Sea Coal', 6.50, 1.200, 0.000, 'metal', '{}', '{BRI}', '{}', false),
  ('marble', 'Marble', 27.00, 1.200, 0.000, 'crafts', '{}', '{ADR,AEG,WES}', '{}', false),
  ('cork', 'Cork', 10.50, 1.200, 0.000, 'crafts', '{}', '{IBE}', '{}', false),
  ('copal', 'Copal', 42.00, 1.200, 0.000, 'crafts', '{}', '{CAR,EAS}', '{}', false),
  ('tiger-skins', 'Tiger Skins', 120.00, 1.200, 0.000, 'cloth', '{}', '{KOR}', '{}', false),
  ('isinglass', 'Isinglass', 84.00, 1.200, 0.000, 'food', '{}', '{AEG,BAL,SCA}', '{}', false),
  ('russia-leather', 'Russia Leather', 60.00, 1.200, 0.000, 'cloth', '{}', '{AEG,BAL,SCA}', '{}', false),
  ('morocco-leather', 'Morocco Leather', 57.00, 1.200, 0.000, 'cloth', '{}', '{MAG}', '{}', false),
  ('peru-balsam', 'Balsam of Peru', 105.00, 1.200, 0.000, 'medicine', '{}', '{CAR,PAC}', '{}', false),
  ('jalap', 'Jalap', 54.00, 1.200, 0.000, 'medicine', '{}', '{CAR}', '{}', false),
  ('vicuna-wool', 'Vicuña Wool', 210.00, 1.200, 0.000, 'cloth', '{}', '{PAC}', '{}', false),
  ('guaiacum', 'Guaiacum', 92.00, 1.200, 0.000, 'medicine', '{}', '{CAR}', '{}', false),
  ('verdigris', 'Verdigris', 45.00, 1.200, 0.000, 'dye', '{}', '{WES}', '{}', false),
  ('cobalt', 'Cobalt Blue', 120.00, 1.200, 0.000, 'dye', '{}', '{ARA}', '{}', false),
  ('gamboge', 'Gamboge', 48.00, 1.200, 0.000, 'dye', '{}', '{SOU}', '{}', false),
  ('safflower', 'Safflower', 21.00, 1.200, 0.000, 'dye', '{}', '{EST,LEV,WIA}', '{}', false),
  ('catechu', 'Catechu', 22.50, 1.200, 0.000, 'dye', '{}', '{EST,WIA}', '{}', false),
  ('elephants', 'War Elephants', 600.00, 1.200, 0.000, 'animals', '{}', '{EST}', '{}', false),
  ('spikenard', 'Spikenard', 105.00, 1.200, 0.000, 'medicine', '{}', '{EST}', '{}', false),
  ('asafoetida', 'Asafoetida', 54.00, 1.200, 0.000, 'medicine', '{}', '{ARA,WIA}', '{}', false),
  ('mecca-balsam', 'Balm of Mecca', 240.00, 1.200, 0.000, 'medicine', '{}', '{ARA}', '{}', false),
  ('linseed', 'Linseed', 9.50, 1.200, 0.000, 'crafts', '{}', '{BAL}', '{}', false),
  ('hops', 'Hops', 11.00, 1.200, 0.000, 'drink', '{}', '{BAL,FRA}', '{}', false),
  ('soap', 'Soap', 24.00, 1.200, 0.000, 'crafts', '{}', '{ADR,IBE,LEV,WES}', '{}', false),
  ('vermilion', 'Vermilion', 135.00, 1.200, 0.000, 'dye', '{}', '{CHI,FRA}', '{}', false),
  ('timber', 'Timber', 9.50, 1.400, 0.000, 'ship-supplies', '{}', '{AEG,ATL,BAL,BRI,CAR,CHI,EAS,EST,FRA,IBE,JAP,KOR,NOR,OCE,SCA,STH,WIA}', '{}', true),
  ('naval-timber', 'Masts & Spars', 51.00, 1.400, 0.000, 'ship-supplies', '{}', '{BAL,NOR,SCA,WES}', '{PTH}', true),
  ('tar', 'Tar & Pitch', 16.50, 1.400, 0.000, 'ship-supplies', '{}', '{BAL,SCA}', '{}', true),
  ('hemp', 'Hemp & Cordage', 22.50, 1.400, 0.000, 'ship-supplies', '{}', '{BAL,EAS,FRA,SCA,WES,WIA}', '{PTH}', true),
  ('flax', 'Flax & Sailcloth', 21.00, 1.400, 0.000, 'ship-supplies', '{}', '{ARA,BAL,FRA,LEV,SCA}', '{}', true),
  ('whale-oil', 'Whale & Train Oil', 48.00, 1.400, 0.000, 'ship-supplies', '{}', '{BRI,FRA,IBE,KOR,NOR,SCA,STH}', '{}', true),
  ('teak', 'Teak', 21.00, 1.400, 0.000, 'ship-supplies', '{}', '{EST,WIA}', '{}', true),
  ('rosin', 'Rosin & Turpentine', 10.50, 1.400, 0.000, 'ship-supplies', '{}', '{BAL,FRA,SCA}', '{}', true),
  ('cedar', 'Cedar Timber', 24.00, 1.400, 0.000, 'ship-supplies', '{}', '{CAR,LEV,NOR}', '{}', true),
  ('mangrove-poles', 'Mangrove Poles', 8.80, 1.400, 0.000, 'ship-supplies', '{}', '{EAS}', '{}', true),
  ('abaca', 'Manila Hemp', 18.00, 1.400, 0.000, 'ship-supplies', '{}', '{SOU}', '{}', true),
  ('port-wine', 'Port Wine', 8.80, 1.000, 0.000, 'drink', '{}', '{IBE}', '{}', false),
  ('sherry', 'Sherry', 13.40, 1.000, 0.000, 'drink', '{}', '{IBE}', '{}', false),
  ('madeira-wine', 'Madeira', 18.90, 1.000, 0.000, 'drink', '{}', '{ATL}', '{}', false),
  ('canary-sack', 'Canary Sack', 10.20, 1.000, 0.000, 'drink', '{}', '{ATL}', '{}', false),
  ('malmsey', 'Malmsey', 15.10, 1.000, 0.000, 'drink', '{}', '{AEG}', '{}', false),
  ('rhenish-wine', 'Rhenish Wine', 20.50, 1.000, 0.000, 'drink', '{}', '{FRA}', '{}', false),
  ('claret', 'Claret', 11.50, 1.000, 0.000, 'drink', '{}', '{FRA}', '{}', false),
  ('burgundy', 'Burgundy', 16.50, 1.000, 0.000, 'drink', '{}', '{FRA}', '{}', false),
  ('chianti', 'Chianti', 22.40, 1.000, 0.000, 'drink', '{}', '{WES}', '{}', false),
  ('retsina', 'Retsina', 13.10, 1.000, 0.000, 'drink', '{}', '{AEG}', '{}', false),
  ('commandaria', 'Commandaria', 18.20, 1.000, 0.000, 'drink', '{}', '{LEV}', '{}', false),
  ('tokay', 'Tokay', 9.60, 1.000, 0.000, 'drink', '{}', '{ADR}', '{}', false),
  ('english-ale', 'English Ale', 14.40, 1.000, 0.000, 'drink', '{}', '{BRI}', '{}', false),
  ('porter-beer', 'Porter', 19.80, 1.000, 0.000, 'drink', '{}', '{BRI}', '{}', false),
  ('hamburg-beer', 'Hamburg Beer', 10.90, 1.000, 0.000, 'drink', '{}', '{BAL}', '{}', false),
  ('kvass', 'Kvass', 16.10, 1.000, 0.000, 'drink', '{}', '{BAL}', '{}', false),
  ('vodka', 'Vodka', 21.60, 1.000, 0.000, 'drink', '{}', '{BAL}', '{}', false),
  ('whisky', 'Whisky', 12.40, 1.000, 0.000, 'drink', '{}', '{BRI}', '{}', false),
  ('gin', 'Genever', 17.50, 1.000, 0.000, 'drink', '{}', '{FRA}', '{}', false),
  ('aquavit', 'Aquavit', 9.10, 1.000, 0.000, 'drink', '{}', '{SCA}', '{}', false),
  ('cognac', 'Cognac', 14.00, 1.000, 0.000, 'drink', '{}', '{FRA}', '{}', false),
  ('grappa', 'Grappa', 19.30, 1.000, 0.000, 'drink', '{}', '{WES}', '{}', false),
  ('rakia', 'Rakia', 10.50, 1.000, 0.000, 'drink', '{}', '{ADR}', '{}', false),
  ('ouzo', 'Ouzo', 15.40, 1.000, 0.000, 'drink', '{}', '{AEG}', '{}', false),
  ('arak-levant', 'Levantine Arak', 20.90, 1.000, 0.000, 'drink', '{}', '{LEV}', '{}', false),
  ('baijiu', 'Baijiu', 11.80, 1.000, 0.000, 'drink', '{}', '{CHI}', '{}', false),
  ('soju', 'Soju', 17.10, 1.000, 0.000, 'drink', '{}', '{KOR}', '{}', false),
  ('shochu', 'Shochu', 22.80, 1.000, 0.000, 'drink', '{}', '{JAP}', '{}', false),
  ('pulque', 'Pulque', 13.40, 1.000, 0.000, 'drink', '{}', '{PAC}', '{}', false),
  ('chicha', 'Chicha', 18.60, 1.000, 0.000, 'drink', '{}', '{PAC,STH}', '{}', false),
  ('palm-wine', 'Palm Wine', 9.90, 1.000, 0.000, 'drink', '{}', '{WST}', '{}', false),
  ('cachaca', 'Cachaca', 14.80, 1.000, 0.000, 'drink', '{}', '{STH}', '{}', false),
  ('cider', 'Cider', 20.40, 1.000, 0.000, 'drink', '{}', '{BRI}', '{}', false),
  ('perry', 'Perry', 11.50, 1.000, 0.000, 'drink', '{}', '{FRA}', '{}', false),
  ('mead', 'Mead', 16.50, 1.000, 0.000, 'drink', '{}', '{SCA}', '{}', false),
  ('toddy', 'Toddy', 22.00, 1.000, 0.000, 'drink', '{}', '{WIA}', '{}', false),
  ('coconut-arrack', 'Coconut Arrack', 12.80, 1.000, 0.000, 'drink', '{}', '{SOU}', '{}', false),
  ('sherbet', 'Sherbet Syrup', 17.90, 1.000, 0.000, 'drink', '{}', '{ARA}', '{}', false),
  ('mint-tea', 'Mint Tea', 9.40, 1.000, 0.000, 'drink', '{}', '{MAG}', '{}', false),
  ('honeybush', 'Honeybush Tea', 14.40, 1.000, 0.000, 'drink', '{}', '{EAS}', '{}', false),
  ('virginia-leaf', 'Virginia Leaf', 57.10, 0.800, 0.000, 'tobacco', '{}', '{NOR}', '{}', false),
  ('maryland-leaf', 'Maryland Leaf', 31.30, 0.800, 0.000, 'tobacco', '{}', '{NOR}', '{}', false),
  ('brazil-twist', 'Brazil Twist', 45.70, 0.800, 0.000, 'tobacco', '{}', '{STH}', '{}', false),
  ('cuban-leaf', 'Cuban Leaf', 62.10, 0.800, 0.000, 'tobacco', '{}', '{CAR}', '{}', false),
  ('cigars', 'Cigars', 35.40, 0.800, 0.000, 'tobacco', '{}', '{CAR}', '{}', false),
  ('turkish-leaf', 'Turkish Leaf', 50.60, 0.800, 0.000, 'tobacco', '{}', '{AEG}', '{}', false),
  ('persian-tombak', 'Persian Tombak', 25.60, 0.800, 0.000, 'tobacco', '{}', '{ARA}', '{}', false),
  ('snuff', 'Snuff', 39.60, 0.800, 0.000, 'tobacco', '{}', '{FRA}', '{}', false),
  ('pipe-tobacco', 'Pipe Tobacco', 55.30, 0.800, 0.000, 'tobacco', '{}', '{BRI}', '{}', false),
  ('betel-quid', 'Betel Quid', 29.80, 0.800, 0.000, 'tobacco', '{}', '{SOU}', '{}', false),
  ('salmon', 'Salmon', 15.40, 1.000, 0.000, 'food', '{}', '{PAC,SCA}', '{}', false),
  ('cod', 'Cod', 20.80, 1.000, 0.000, 'food', '{}', '{NOR}', '{}', false),
  ('stockfish', 'Stockfish', 11.80, 1.000, 0.000, 'food', '{}', '{SCA}', '{}', false),
  ('tuna', 'Tuna', 16.80, 1.000, 0.000, 'food', '{}', '{WES}', '{}', false),
  ('sardines', 'Sardines', 22.40, 1.000, 0.000, 'food', '{}', '{IBE}', '{}', false),
  ('anchovies', 'Anchovies', 13.10, 1.000, 0.000, 'food', '{}', '{WES}', '{}', false),
  ('mackerel', 'Mackerel', 18.60, 1.000, 0.000, 'food', '{}', '{BRI}', '{}', false),
  ('smoked-eel', 'Smoked Eel', 9.90, 1.000, 0.000, 'food', '{}', '{FRA}', '{}', false),
  ('sturgeon', 'Sturgeon', 14.70, 1.000, 0.000, 'food', '{}', '{BAL}', '{}', false),
  ('bonito', 'Bonito', 20.10, 1.000, 0.000, 'food', '{}', '{JAP}', '{}', false),
  ('pollock', 'Pollock', 11.20, 1.000, 0.000, 'food', '{}', '{KOR}', '{}', false),
  ('halibut', 'Halibut', 16.40, 1.000, 0.000, 'food', '{}', '{SCA}', '{}', false),
  ('hake', 'Hake', 22.00, 1.000, 0.000, 'food', '{}', '{IBE}', '{}', false),
  ('pilchards', 'Pilchards', 12.70, 1.000, 0.000, 'food', '{}', '{BRI}', '{}', false),
  ('bacalhau', 'Bacalhau', 17.90, 1.000, 0.000, 'food', '{}', '{IBE}', '{}', false),
  ('katsuobushi', 'Katsuobushi', 9.30, 1.000, 0.000, 'food', '{}', '{JAP}', '{}', false),
  ('dried-squid', 'Dried Squid', 14.10, 1.000, 0.000, 'food', '{}', '{KOR}', '{}', false),
  ('salt-cod', 'Salt Cod', 19.70, 1.000, 0.000, 'food', '{}', '{NOR}', '{}', false),
  ('gochujang', 'Gochujang', 10.80, 1.000, 0.000, 'food', '{}', '{KOR}', '{}', false),
  ('doenjang', 'Doenjang', 15.80, 1.000, 0.000, 'food', '{}', '{KOR}', '{}', false),
  ('kimchi', 'Kimchi', 21.20, 1.000, 0.000, 'food', '{}', '{KOR}', '{}', false),
  ('miso', 'Miso', 12.10, 1.000, 0.000, 'food', '{}', '{JAP}', '{}', false),
  ('mirin', 'Mirin', 17.20, 1.000, 0.000, 'food', '{}', '{JAP}', '{}', false),
  ('rice-vinegar', 'Rice Vinegar', 8.80, 1.000, 0.000, 'food', '{}', '{CHI}', '{}', false),
  ('fish-sauce', 'Fish Sauce', 13.70, 1.000, 0.000, 'food', '{}', '{SOU}', '{}', false),
  ('shrimp-paste', 'Shrimp Paste', 19.00, 1.000, 0.000, 'food', '{}', '{SOU}', '{}', false),
  ('pickled-plums', 'Pickled Plums', 10.20, 1.000, 0.000, 'food', '{}', '{JAP}', '{}', false),
  ('olives', 'Olives', 15.10, 1.000, 0.000, 'food', '{}', '{WES}', '{}', false),
  ('capers', 'Capers', 20.50, 1.000, 0.000, 'food', '{}', '{WES}', '{}', false),
  ('harissa', 'Harissa', 11.50, 1.000, 0.000, 'food', '{}', '{MAG}', '{}', false),
  ('couscous', 'Couscous', 16.80, 1.000, 0.000, 'food', '{}', '{MAG}', '{}', false),
  ('maple-sugar', 'Maple Sugar', 22.40, 1.000, 0.000, 'food', '{}', '{NOR}', '{}', false),
  ('pemmican', 'Pemmican', 13.10, 1.000, 0.000, 'food', '{}', '{NOR}', '{}', false),
  ('charqui', 'Charqui', 18.30, 1.000, 0.000, 'food', '{}', '{PAC,STH}', '{}', false),
  ('cassava-bread', 'Cassava Bread', 9.70, 1.000, 0.000, 'food', '{}', '{CAR}', '{}', false),
  ('plantains', 'Plantains', 14.70, 1.000, 0.000, 'food', '{}', '{WST}', '{}', false),
  ('yams', 'Yams', 20.10, 1.000, 0.000, 'food', '{}', '{WST}', '{}', false),
  ('shea-butter', 'Shea Butter', 11.20, 1.000, 0.000, 'food', '{}', '{WST}', '{}', false),
  ('teff', 'Teff', 5.30, 1.200, 0.000, 'grain', '{}', '{EAS}', '{}', false),
  ('millet', 'Millet', 7.40, 1.200, 0.000, 'grain', '{}', '{WST}', '{}', false),
  ('sorghum', 'Sorghum', 4.00, 1.200, 0.000, 'grain', '{}', '{EAS}', '{}', false),
  ('oats', 'Oats', 6.00, 1.200, 0.000, 'grain', '{}', '{BRI}', '{}', false),
  ('buckwheat', 'Buckwheat', 2.80, 1.200, 0.000, 'grain', '{}', '{BAL}', '{}', false),
  ('quinoa', 'Quinoa', 4.60, 1.200, 0.000, 'grain', '{}', '{STH}', '{}', false),
  ('spelt', 'Spelt', 6.60, 1.200, 0.000, 'grain', '{}', '{FRA}', '{}', false),
  ('persian-carpet', 'Persian Carpet', 30.40, 0.900, 0.000, 'cloth', '{}', '{ARA}', '{}', false),
  ('kashmir-shawl', 'Kashmir Shawl', 45.00, 0.900, 0.000, 'cloth', '{}', '{WIA}', '{}', false),
  ('dhaka-muslin', 'Dhaka Muslin', 61.30, 0.900, 0.000, 'cloth', '{}', '{EST}', '{}', false),
  ('patola-silk', 'Patola Silk', 34.50, 0.900, 0.000, 'cloth', '{}', '{WIA}', '{}', false),
  ('nankeen', 'Nankeen Cloth', 49.50, 0.900, 0.000, 'cloth', '{}', '{CHI}', '{}', false),
  ('shantung-silk', 'Shantung Silk', 25.00, 0.900, 0.000, 'cloth', '{}', '{CHI}', '{}', false),
  ('nishijin-brocade', 'Nishijin Brocade', 38.90, 0.900, 0.000, 'cloth', '{}', '{JAP}', '{}', false),
  ('ramie-korea', 'Korean Ramie', 54.50, 0.900, 0.000, 'cloth', '{}', '{KOR}', '{}', false),
  ('hemp-cloth', 'Hemp Cloth', 28.90, 0.900, 0.000, 'cloth', '{}', '{KOR}', '{}', false),
  ('holland-linen', 'Holland Linen', 43.30, 0.900, 0.000, 'cloth', '{}', '{FRA}', '{}', false),
  ('flanders-lace', 'Flanders Lace', 59.40, 0.900, 0.000, 'cloth', '{}', '{FRA}', '{}', false),
  ('irish-linen', 'Irish Linen', 33.10, 0.900, 0.000, 'cloth', '{}', '{BRI}', '{}', false),
  ('kersey', 'Kersey', 47.80, 0.900, 0.000, 'cloth', '{}', '{BRI}', '{}', false),
  ('worsted', 'Worsted', 64.40, 0.900, 0.000, 'cloth', '{}', '{BRI}', '{}', false),
  ('baize', 'Baize', 37.30, 0.900, 0.000, 'cloth', '{}', '{BRI}', '{}', false),
  ('russia-hemp', 'Russia Hemp Cloth', 52.70, 0.900, 0.000, 'cloth', '{}', '{BAL}', '{}', false),
  ('sailcloth', 'Sailcloth', 27.40, 0.900, 0.000, 'cloth', '{}', '{BAL}', '{}', false),
  ('kente-cloth', 'Kente Cloth', 41.60, 0.900, 0.000, 'cloth', '{}', '{WST}', '{}', false),
  ('adire-cloth', 'Adire Cloth', 57.50, 0.900, 0.000, 'cloth', '{}', '{WST}', '{}', false),
  ('kanga-cloth', 'Kanga Cloth', 31.60, 0.900, 0.000, 'cloth', '{}', '{EAS}', '{}', false),
  ('alpaca-wool', 'Alpaca Wool', 46.30, 0.900, 0.000, 'cloth', '{}', '{PAC,STH}', '{}', false),
  ('tapa-cloth', 'Tapa Cloth', 62.50, 0.900, 0.000, 'cloth', '{}', '{OCE}', '{}', false),
  ('songket', 'Songket', 35.70, 0.900, 0.000, 'cloth', '{}', '{SOU}', '{}', false),
  ('ikat', 'Ikat', 50.90, 0.900, 0.000, 'cloth', '{}', '{SOU}', '{}', false),
  ('merino-wool', 'Merino Wool', 26.20, 0.900, 0.000, 'cloth', '{}', '{IBE}', '{}', false),
  ('damask', 'Damask', 40.00, 0.900, 0.000, 'cloth', '{}', '{LEV}', '{}', false),
  ('mohair', 'Mohair', 55.70, 0.900, 0.000, 'cloth', '{}', '{AEG}', '{}', false),
  ('angora', 'Angora Wool', 30.10, 0.900, 0.000, 'cloth', '{}', '{AEG}', '{}', false),
  ('tin-ingots', 'Tin Ingots', 44.60, 0.800, 0.000, 'metal', '{}', '{BRI}', '{}', false),
  ('swedish-iron', 'Swedish Iron', 60.60, 0.800, 0.000, 'metal', '{}', '{SCA}', '{}', false),
  ('osmund-iron', 'Osmund Iron', 34.10, 0.800, 0.000, 'metal', '{}', '{SCA}', '{}', false),
  ('japan-copper', 'Japan Copper', 49.20, 0.800, 0.000, 'metal', '{}', '{JAP}', '{}', false),
  ('potosi-silver', 'Potosi Silver', 65.90, 0.800, 0.000, 'metal', '{}', '{PAC,STH}', '{}', false),
  ('zacatecas-silver', 'Zacatecas Silver', 38.60, 0.800, 0.000, 'metal', '{}', '{PAC}', '{}', false),
  ('gold-dust', 'Gold Dust', 53.90, 0.800, 0.000, 'metal', '{}', '{PAC,WST}', '{}', false),
  ('antimony', 'Antimony', 28.60, 0.800, 0.000, 'metal', '{}', '{CHI}', '{}', false),
  ('zinc-spelter', 'Spelter', 42.90, 0.800, 0.000, 'metal', '{}', '{EST}', '{}', false),
  ('bar-iron', 'Bar Iron', 59.00, 0.800, 0.000, 'metal', '{}', '{BAL}', '{}', false),
  ('brass-ingots', 'Brass Ingots', 32.60, 0.800, 0.000, 'metal', '{}', '{FRA}', '{}', false),
  ('steel-billets', 'Steel Billets', 47.40, 0.800, 0.000, 'metal', '{}', '{ARA}', '{}', false),
  ('platinum', 'Platinum', 64.00, 0.800, 0.000, 'metal', '{}', '{PAC,STH}', '{}', false),
  ('lodestone', 'Lodestone', 37.00, 0.800, 0.000, 'metal', '{}', '{CHI}', '{}', false),
  ('alum-shale', 'Alum Shale', 52.10, 0.800, 0.000, 'metal', '{}', '{AEG}', '{}', false),
  ('cinnabar', 'Cinnabar', 27.10, 0.800, 0.000, 'metal', '{}', '{IBE}', '{}', false),
  ('matchlocks', 'Matchlocks', 120.00, 0.900, 0.000, 'guns', '{}', '{JAP}', '{}', false),
  ('arquebus', 'Arquebus', 163.60, 0.900, 0.000, 'guns', '{}', '{FRA}', '{}', false),
  ('culverin', 'Culverin', 92.00, 0.900, 0.000, 'guns', '{}', '{BRI}', '{}', false),
  ('falconet', 'Falconet', 132.40, 0.900, 0.000, 'guns', '{}', '{WES}', '{}', false),
  ('swivel-gun', 'Swivel Gun', 177.30, 0.900, 0.000, 'guns', '{}', '{ADR}', '{}', false),
  ('bombard', 'Bombard', 103.50, 0.900, 0.000, 'guns', '{}', '{AEG}', '{}', false),
  ('rocket-tubes', 'Rocket Tubes', 145.50, 0.900, 0.000, 'guns', '{}', '{WIA}', '{}', false),
  ('fire-lance', 'Fire Lance', 77.10, 0.900, 0.000, 'guns', '{}', '{CHI}', '{}', false),
  ('shot-and-ball', 'Shot and Ball', 115.60, 0.900, 0.000, 'guns', '{}', '{BAL}', '{}', false),
  ('slow-match', 'Slow Match', 158.70, 0.900, 0.000, 'guns', '{}', '{IBE}', '{}', false),
  ('toledo-blades', 'Toledo Blades', 29.80, 0.800, 0.000, 'weapons', '{}', '{IBE}', '{}', false),
  ('damascus-blades', 'Damascus Blades', 44.30, 0.800, 0.000, 'weapons', '{}', '{LEV}', '{}', false),
  ('katana', 'Katana', 60.20, 0.800, 0.000, 'weapons', '{}', '{JAP}', '{}', false),
  ('kris', 'Kris', 33.80, 0.800, 0.000, 'weapons', '{}', '{SOU}', '{}', false),
  ('talwar', 'Talwar', 48.80, 0.800, 0.000, 'weapons', '{}', '{WIA}', '{}', false),
  ('pike-heads', 'Pike Heads', 65.50, 0.800, 0.000, 'weapons', '{}', '{FRA}', '{}', false),
  ('crossbows', 'Crossbows', 38.00, 0.800, 0.000, 'weapons', '{}', '{ADR}', '{}', false),
  ('war-bows', 'War Bows', 53.50, 0.800, 0.000, 'weapons', '{}', '{KOR}', '{}', false),
  ('milanese-armour', 'Milanese Armour', 28.20, 0.800, 0.000, 'weapons', '{}', '{WES}', '{}', false),
  ('shields', 'Hide Shields', 42.60, 0.800, 0.000, 'weapons', '{}', '{EAS}', '{}', false),
  ('kyoto-fans', 'Kyoto Fans', 167.30, 0.500, 0.000, 'crafts', '{}', '{JAP}', '{}', false),
  ('imari-ware', 'Imari Ware', 95.20, 0.500, 0.000, 'crafts', '{}', '{JAP}', '{}', false),
  ('goryeo-celadon', 'Goryeo Celadon', 135.90, 0.500, 0.000, 'crafts', '{}', '{KOR}', '{}', false),
  ('mother-of-pearl-inlay', 'Nacre Inlay', 181.20, 0.500, 0.000, 'crafts', '{}', '{KOR}', '{}', false),
  ('canton-enamel', 'Canton Enamel', 106.70, 0.500, 0.000, 'crafts', '{}', '{CHI}', '{}', false),
  ('cloisonne', 'Cloisonne', 148.80, 0.500, 0.000, 'crafts', '{}', '{CHI}', '{}', false),
  ('benin-bronzes', 'Benin Bronzes', 80.00, 0.500, 0.000, 'crafts', '{}', '{WST}', '{}', false),
  ('ashanti-goldwork', 'Ashanti Goldwork', 119.00, 0.500, 0.000, 'crafts', '{}', '{WST}', '{}', false),
  ('zanzibar-doors', 'Carved Doors', 162.40, 0.500, 0.000, 'crafts', '{}', '{EAS}', '{}', false),
  ('damascene-work', 'Damascene Work', 91.10, 0.500, 0.000, 'crafts', '{}', '{LEV}', '{}', false),
  ('iznik-tiles', 'Iznik Tiles', 131.30, 0.500, 0.000, 'crafts', '{}', '{AEG}', '{}', false),
  ('murano-glass', 'Murano Glass', 176.10, 0.500, 0.000, 'crafts', '{}', '{ADR}', '{}', false),
  ('venetian-mirrors', 'Venetian Mirrors', 102.50, 0.500, 0.000, 'crafts', '{}', '{ADR}', '{}', false),
  ('delftware', 'Delftware', 144.10, 0.500, 0.000, 'crafts', '{}', '{FRA}', '{}', false),
  ('sheffield-plate', 'Sheffield Plate', 75.90, 0.500, 0.000, 'crafts', '{}', '{BRI}', '{}', false),
  ('amber-work', 'Amber Work', 114.30, 0.500, 0.000, 'crafts', '{}', '{BAL}', '{}', false),
  ('sami-craft', 'Sami Craft', 157.60, 0.500, 0.000, 'crafts', '{}', '{SCA}', '{}', false),
  ('talavera', 'Talavera', 87.00, 0.500, 0.000, 'crafts', '{}', '{PAC}', '{}', false),
  ('featherwork', 'Featherwork', 126.80, 0.500, 0.000, 'crafts', '{}', '{PAC}', '{}', false),
  ('tortoiseshell-combs', 'Tortoiseshell Combs', 171.10, 0.500, 0.000, 'crafts', '{}', '{CAR}', '{}', false),
  ('sandalwood-carving', 'Sandalwood Carving', 98.30, 0.500, 0.000, 'crafts', '{}', '{WIA}', '{}', false),
  ('bidriware', 'Bidriware', 139.40, 0.500, 0.000, 'crafts', '{}', '{EST}', '{}', false),
  ('nipa-mats', 'Nipa Mats', 185.10, 0.500, 0.000, 'crafts', '{}', '{SOU}', '{}', false),
  ('pandanus-mats', 'Pandanus Mats', 110.00, 0.500, 0.000, 'crafts', '{}', '{OCE}', '{}', false),
  ('azulejos', 'Azulejos', 152.50, 0.500, 0.000, 'crafts', '{}', '{IBE}', '{}', false),
  ('maghreb-brass', 'Maghreb Brasswork', 82.80, 0.500, 0.000, 'crafts', '{}', '{MAG}', '{}', false),
  ('saffian-leather', 'Saffian Leather', 122.40, 0.500, 0.000, 'crafts', '{}', '{MAG}', '{}', false),
  ('seed-pearls', 'Seed Pearls', 469.10, 0.200, 0.000, 'gems', '{}', '{ARA}', '{}', false),
  ('golconda-diamonds', 'Golconda Diamonds', 256.40, 0.200, 0.000, 'gems', '{}', '{EST}', '{}', false),
  ('ceylon-sapphires', 'Ceylon Sapphires', 376.40, 0.200, 0.000, 'gems', '{}', '{SOU}', '{}', false),
  ('burma-rubies', 'Burma Rubies', 510.30, 0.200, 0.000, 'gems', '{}', '{SOU}', '{}', false),
  ('jade', 'Jade', 290.70, 0.200, 0.000, 'gems', '{}', '{CHI}', '{}', false),
  ('nephrite', 'Nephrite', 414.80, 0.200, 0.000, 'gems', '{}', '{KOR}', '{}', false),
  ('emerald-muzo', 'Muzo Emeralds', 211.70, 0.200, 0.000, 'gems', '{}', '{STH}', '{}', false),
  ('opals', 'Opals', 326.20, 0.200, 0.000, 'gems', '{}', '{OCE}', '{}', false),
  ('baltic-amber', 'Baltic Amber', 454.30, 0.200, 0.000, 'gems', '{}', '{BAL}', '{}', false),
  ('malachite', 'Malachite', 244.40, 0.200, 0.000, 'gems', '{}', '{EAS}', '{}', false),
  ('onyx', 'Onyx', 362.90, 0.200, 0.000, 'gems', '{}', '{MAG}', '{}', false),
  ('peridot', 'Peridot', 495.10, 0.200, 0.000, 'gems', '{}', '{ARA}', '{}', false),
  ('black-coral', 'Black Coral', 278.00, 0.200, 0.000, 'gems', '{}', '{CAR}', '{}', false),
  ('attar-of-roses', 'Attar of Roses', 49.50, 0.500, 0.000, 'medicine', '{}', '{ARA}', '{}', false),
  ('mumia', 'Mumia', 25.00, 0.500, 0.000, 'medicine', '{}', '{LEV}', '{}', false),
  ('dragon-bone', 'Dragon Bone', 38.90, 0.500, 0.000, 'medicine', '{}', '{CHI}', '{}', false),
  ('ginseng-korea', 'Korean Ginseng', 54.50, 0.500, 0.000, 'medicine', '{}', '{KOR}', '{}', false),
  ('moxa', 'Moxa', 28.90, 0.500, 0.000, 'medicine', '{}', '{JAP}', '{}', false),
  ('kampo-herbs', 'Kampo Herbs', 43.30, 0.500, 0.000, 'medicine', '{}', '{JAP}', '{}', false),
  ('ayurvedic-oils', 'Ayurvedic Oils', 59.40, 0.500, 0.000, 'medicine', '{}', '{WIA}', '{}', false),
  ('neem', 'Neem', 33.10, 0.500, 0.000, 'medicine', '{}', '{WIA}', '{}', false),
  ('kino-gum', 'Kino Gum', 47.80, 0.500, 0.000, 'medicine', '{}', '{EST}', '{}', false),
  ('patchouli', 'Patchouli', 64.40, 0.500, 0.000, 'medicine', '{}', '{SOU}', '{}', false),
  ('clove-oil', 'Clove Oil', 37.30, 0.500, 0.000, 'medicine', '{}', '{SOU}', '{}', false),
  ('copaiba', 'Copaiba', 52.70, 0.500, 0.000, 'medicine', '{}', '{STH}', '{}', false),
  ('coca-leaf', 'Coca Leaf', 27.40, 0.500, 0.000, 'medicine', '{}', '{PAC,STH}', '{}', false),
  ('tolu-balsam', 'Tolu Balsam', 41.60, 0.500, 0.000, 'medicine', '{}', '{CAR}', '{}', false),
  ('sassafras-root', 'Sassafras Root', 57.50, 0.500, 0.000, 'medicine', '{}', '{NOR}', '{}', false),
  ('witch-hazel', 'Witch Hazel', 31.60, 0.500, 0.000, 'medicine', '{}', '{NOR}', '{}', false),
  ('grains-paradise-oil', 'Melegueta Oil', 46.30, 0.500, 0.000, 'medicine', '{}', '{WST}', '{}', false),
  ('myrrh-somali', 'Somali Myrrh', 62.50, 0.500, 0.000, 'medicine', '{}', '{EAS}', '{}', false),
  ('storax', 'Storax', 35.70, 0.500, 0.000, 'medicine', '{}', '{AEG}', '{}', false),
  ('theriaca-venetian', 'Venetian Treacle', 50.90, 0.500, 0.000, 'medicine', '{}', '{ADR}', '{}', false),
  ('angelica-root', 'Angelica Root', 26.20, 0.500, 0.000, 'medicine', '{}', '{SCA}', '{}', false),
  ('juniper-berries', 'Juniper Berries', 40.00, 0.500, 0.000, 'medicine', '{}', '{BAL}', '{}', false),
  ('kermes', 'Kermes', 55.70, 0.700, 0.000, 'dye', '{}', '{WES}', '{}', false),
  ('weld', 'Weld', 30.10, 0.700, 0.000, 'dye', '{}', '{FRA}', '{}', false),
  ('dyers-broom', 'Dyer''s Broom', 44.60, 0.700, 0.000, 'dye', '{}', '{IBE}', '{}', false),
  ('archil-lichen', 'Archil Lichen', 60.60, 0.700, 0.000, 'dye', '{}', '{ATL}', '{}', false),
  ('sappan-java', 'Java Sappan', 34.10, 0.700, 0.000, 'dye', '{}', '{SOU}', '{}', false),
  ('turmeric-dye', 'Turmeric Dye', 49.20, 0.700, 0.000, 'dye', '{}', '{EST}', '{}', false),
  ('persian-berries', 'Persian Berries', 65.90, 0.700, 0.000, 'dye', '{}', '{ARA}', '{}', false),
  ('saffron-dye', 'Saffron Dye', 38.60, 0.700, 0.000, 'dye', '{}', '{AEG}', '{}', false),
  ('sumac', 'Sumac', 53.90, 0.700, 0.000, 'dye', '{}', '{MAG}', '{}', false),
  ('tannin-bark', 'Tannin Bark', 28.60, 0.700, 0.000, 'dye', '{}', '{SCA}', '{}', false),
  ('prussian-blue', 'Prussian Blue', 42.90, 0.700, 0.000, 'dye', '{}', '{BAL}', '{}', false),
  ('smalt', 'Smalt', 59.00, 0.700, 0.000, 'dye', '{}', '{BAL}', '{}', false),
  ('ochre', 'Ochre', 32.60, 0.700, 0.000, 'dye', '{}', '{WST}', '{}', false),
  ('ultramarine', 'Ultramarine', 47.40, 0.700, 0.000, 'dye', '{}', '{ARA}', '{}', false),
  ('lead-white', 'Lead White', 64.00, 0.700, 0.000, 'dye', '{}', '{FRA}', '{}', false),
  ('riga-mast', 'Riga Mast', 4.00, 1.400, 0.000, 'ship-supplies', '{}', '{BAL}', '{}', false),
  ('memel-fir', 'Memel Fir', 6.00, 1.400, 0.000, 'ship-supplies', '{}', '{BAL}', '{}', false),
  ('norway-spruce', 'Norway Spruce', 2.80, 1.400, 0.000, 'ship-supplies', '{}', '{SCA}', '{}', false),
  ('stockholm-tar', 'Stockholm Tar', 4.60, 1.400, 0.000, 'ship-supplies', '{}', '{SCA}', '{}', false),
  ('oakum', 'Oakum', 6.70, 1.400, 0.000, 'ship-supplies', '{}', '{BRI}', '{}', false),
  ('cordage', 'Cordage', 3.40, 1.400, 0.000, 'ship-supplies', '{}', '{BRI,PAC}', '{}', false),
  ('canvas-duck', 'Canvas Duck', 5.30, 1.400, 0.000, 'ship-supplies', '{}', '{FRA}', '{}', false),
  ('live-oak', 'Live Oak', 7.40, 1.400, 0.000, 'ship-supplies', '{}', '{NOR}', '{}', false),
  ('greenheart', 'Greenheart', 4.00, 1.400, 0.000, 'ship-supplies', '{}', '{STH}', '{}', false),
  ('lignum-vitae', 'Lignum Vitae', 5.90, 1.400, 0.000, 'ship-supplies', '{}', '{CAR}', '{}', false),
  ('gutta-percha', 'Gutta-percha', 2.50, 1.400, 0.000, 'ship-supplies', '{}', '{SOU}', '{}', false),
  ('coco-fibre', 'Coco Fibre', 4.30, 1.400, 0.000, 'ship-supplies', '{}', '{WIA}', '{}', false),
  ('whale-bone-stays', 'Baleen Stays', 6.60, 1.400, 0.000, 'ship-supplies', '{}', '{SCA}', '{}', false),
  ('copper-sheet', 'Copper Sheathing', 3.10, 1.400, 0.000, 'ship-supplies', '{}', '{BRI}', '{}', false),
  ('ships-nails', 'Ship''s Nails', 5.00, 1.400, 0.000, 'ship-supplies', '{}', '{FRA}', '{}', false),
  ('portolan-charts', 'Portolan Charts', 487.50, 0.300, 0.000, 'art', '{}', '{ADR}', '{}', false),
  ('flemish-panels', 'Flemish Panels', 272.00, 0.300, 0.000, 'art', '{}', '{FRA}', '{}', false),
  ('italian-canvases', 'Italian Canvases', 393.80, 0.300, 0.000, 'art', '{}', '{WES}', '{}', false),
  ('ukiyo-e', 'Ukiyo-e Prints', 529.20, 0.300, 0.000, 'art', '{}', '{JAP}', '{}', false),
  ('scroll-paintings', 'Scroll Paintings', 306.80, 0.300, 0.000, 'art', '{}', '{CHI}', '{}', false),
  ('mughal-miniatures', 'Mughal Miniatures', 432.70, 0.300, 0.000, 'art', '{}', '{WIA}', '{}', false),
  ('astrolabes', 'Astrolabes', 226.30, 0.300, 0.000, 'art', '{}', '{ARA}', '{}', false),
  ('armillary-spheres', 'Armillary Spheres', 342.60, 0.300, 0.000, 'art', '{}', '{IBE}', '{}', false),
  ('globes', 'Terrestrial Globes', 472.80, 0.300, 0.000, 'art', '{}', '{FRA}', '{}', false),
  ('nautical-clocks', 'Nautical Clocks', 259.50, 0.300, 0.000, 'art', '{}', '{BRI}', '{}', false),
  ('korean-movable-type', 'Movable Type', 135.90, 0.400, 0.000, 'books', '{}', '{KOR}', '{}', false),
  ('sutra-scrolls', 'Sutra Scrolls', 181.20, 0.400, 0.000, 'books', '{}', '{JAP}', '{}', false),
  ('block-printed-books', 'Block-printed Books', 106.70, 0.400, 0.000, 'books', '{}', '{CHI}', '{}', false),
  ('quran-manuscripts', 'Quran Manuscripts', 148.80, 0.400, 0.000, 'books', '{}', '{MAG}', '{}', false),
  ('palm-leaf-manuscripts', 'Palm-leaf Manuscripts', 80.00, 0.400, 0.000, 'books', '{}', '{EST}', '{}', false),
  ('antwerp-presses', 'Antwerp Imprints', 119.00, 0.400, 0.000, 'books', '{}', '{FRA}', '{}', false),
  ('venetian-imprints', 'Venetian Imprints', 162.40, 0.400, 0.000, 'books', '{}', '{ADR}', '{}', false),
  ('parchment', 'Parchment', 91.10, 0.400, 0.000, 'books', '{}', '{BRI}', '{}', false),
  ('rice-paper', 'Rice Paper', 131.30, 0.400, 0.000, 'books', '{}', '{CHI}', '{}', false),
  ('arabian-horses', 'Arabian Horses', 176.10, 1.500, 0.000, 'animals', '{}', '{ARA}', '{}', false),
  ('andalusian-horses', 'Andalusian Horses', 102.50, 1.500, 0.000, 'animals', '{}', '{IBE}', '{}', false),
  ('camels', 'Camels', 144.10, 1.500, 0.000, 'animals', '{}', '{MAG}', '{}', false),
  ('zebu-cattle', 'Zebu Cattle', 75.90, 1.500, 0.000, 'animals', '{}', '{WIA}', '{}', false),
  ('merino-sheep', 'Merino Sheep', 114.30, 1.500, 0.000, 'animals', '{}', '{IBE}', '{}', false),
  ('falcons', 'Hunting Falcons', 157.60, 1.500, 0.000, 'animals', '{}', '{SCA}', '{}', false),
  ('songbirds', 'Songbirds', 87.00, 1.500, 0.000, 'animals', '{}', '{CHI}', '{}', false),
  ('macaws', 'Macaws', 126.80, 1.500, 0.000, 'animals', '{}', '{STH}', '{}', false),
  ('civet-cats', 'Civet Cats', 171.10, 1.500, 0.000, 'animals', '{}', '{EAS}', '{}', false),
  ('peacocks', 'Peacocks', 98.30, 1.500, 0.000, 'animals', '{}', '{EST}', '{}', false),
  ('sea-otter-pelts', 'Sea Otter Pelts', 260.00, 1.200, 0.000, 'cloth', '{}', '{PAC}', '{}', false),
  ('redwood', 'Redwood', 7.20, 1.400, 0.000, 'ship-supplies', '{}', '{PAC}', '{}', false),
  ('california-hides', 'California Hides', 16.00, 1.200, 0.000, 'cloth', '{}', '{PAC}', '{}', false),
  ('abalone-shell', 'Abalone Shell', 34.00, 0.500, 0.000, 'crafts', '{}', '{PAC}', '{}', false),
  ('mission-wine', 'Mission Wine', 11.00, 1.000, 0.000, 'drink', '{}', '{PAC}', '{}', false),
  ('brea', 'Brea', 5.40, 1.400, 0.000, 'ship-supplies', '{}', '{PAC}', '{}', false),
  ('baja-pearls', 'Baja Pearls', 310.00, 0.300, 0.000, 'gems', '{}', '{PAC}', '{}', false),
  ('dried-shrimp', 'Dried Shrimp', 13.00, 1.000, 0.000, 'food', '{}', '{PAC}', '{}', false),
  ('mezcal', 'Mezcal', 11.20, 1.000, 0.000, 'drink', '{}', '{PAC}', '{}', false),
  ('coconut-wine', 'Coconut Wine', 10.60, 1.000, 0.000, 'drink', '{}', '{PAC}', '{}', false),
  ('soconusco-cacao', 'Soconusco Cacao', 86.00, 1.000, 0.000, 'drink', '{}', '{PAC}', '{}', false),
  ('anil', 'Anil', 90.00, 1.200, 0.000, 'dye', '{}', '{PAC}', '{}', false),
  ('pine-pitch', 'Pine Pitch', 6.00, 1.400, 0.000, 'ship-supplies', '{}', '{PAC}', '{}', false),
  ('hammocks', 'Hammocks', 14.50, 1.200, 0.000, 'crafts', '{}', '{PAC}', '{}', false),
  ('balsa-wood', 'Balsa Wood', 5.40, 1.400, 0.000, 'ship-supplies', '{}', '{PAC}', '{}', false),
  ('guayaquil-cacao', 'Guayaquil Cacao', 52.00, 1.000, 0.000, 'drink', '{}', '{PAC}', '{}', false),
  ('toquilla-straw', 'Toquilla Straw', 13.50, 1.200, 0.000, 'crafts', '{}', '{PAC}', '{}', false),
  ('mangrove-bark', 'Mangrove Bark', 11.00, 1.200, 0.000, 'dye', '{}', '{PAC}', '{}', false),
  ('pisco', 'Pisco', 11.20, 1.000, 0.000, 'drink', '{}', '{PAC}', '{}', false),
  ('goatskins', 'Goatskins', 14.50, 1.200, 0.000, 'cloth', '{}', '{PAC}', '{}', false),
  ('piura-cotton', 'Piura Cotton', 14.50, 1.200, 0.000, 'cloth', '{}', '{PAC}', '{}', false),
  ('chuno', 'Chuño', 4.50, 1.200, 0.000, 'grain', '{}', '{PAC}', '{}', false),
  ('chilean-copper', 'Chilean Copper', 48.00, 0.800, 0.000, 'metal', '{}', '{PAC}', '{}', false),
  ('chilean-wine', 'Chilean Wine', 10.60, 1.000, 0.000, 'drink', '{}', '{PAC}', '{}', false),
  ('alerce-timber', 'Alerce Timber', 17.50, 1.400, 0.000, 'ship-supplies', '{}', '{PAC}', '{}', false),
  ('araucaria-nuts', 'Araucaria Nuts', 4.20, 1.000, 0.000, 'food', '{}', '{PAC}', '{}', false),
  ('andacollo-gold', 'Andacollo Gold', 116.00, 0.800, 0.000, 'metal', '{}', '{PAC}', '{}', false),
  ('mules', 'Mules', 43.00, 1.500, 0.000, 'animals', '{}', '{PAC}', '{}', false),
  ('huon-pine', 'Huon Pine', 17.50, 1.400, 0.000, 'ship-supplies', '{}', '{OCE}', '{}', false),
  ('sperm-oil', 'Sperm Oil', 43.00, 1.400, 0.000, 'ship-supplies', '{}', '{OCE}', '{}', false),
  ('wattle-bark', 'Wattle Bark', 12.00, 1.200, 0.000, 'dye', '{}', '{OCE}', '{}', false),
  ('kangaroo-skins', 'Kangaroo Skins', 14.50, 1.200, 0.000, 'cloth', '{}', '{OCE}', '{}', false),
  ('jarrah', 'Jarrah', 16.00, 1.400, 0.000, 'ship-supplies', '{}', '{OCE}', '{}', false),
  ('kauri-timber', 'Kauri Spars', 42.00, 1.400, 0.000, 'ship-supplies', '{}', '{OCE}', '{}', false),
  ('kauri-gum', 'Kauri Gum', 24.00, 0.800, 0.000, 'crafts', '{}', '{OCE}', '{}', false),
  ('harakeke', 'New Zealand Flax', 20.50, 1.200, 0.000, 'ship-supplies', '{}', '{OCE}', '{}', false),
  ('pounamu', 'Pounamu', 145.00, 0.300, 0.000, 'gems', '{}', '{OCE}', '{}', false),
  ('kumara', 'Kumara', 5.80, 1.000, 0.000, 'food', '{}', '{OCE}', '{}', false),
  ('mast-pine', 'Mast Pine', 45.00, 1.400, 0.000, 'ship-supplies', '{}', '{NOR}', '{}', false),
  ('beaver-pelts', 'Beaver Pelts', 120.00, 1.200, 0.000, 'cloth', '{}', '{NOR,PAC}', '{}', false),
  ('douglas-fir', 'Douglas Fir', 6.00, 1.400, 0.000, 'ship-supplies', '{}', '{PAC}', '{}', false),
  ('dentalium', 'Dentalium Shell', 60.00, 0.300, 0.000, 'crafts', '{}', '{PAC}', '{}', false);

create temporary table want_offers_0217 (port_code text, good_code text);
insert into want_offers_0217 values
  ('ACA', 'cacao'),
  ('ACA', 'cinchona-bark'),
  ('ACA', 'peru-balsam'),
  ('ACA', 'silver'),
  ('ACA', 'vicuna-wool'),
  ('ACA', 'zacatecas-silver'),
  ('ACC', 'grains-of-paradise'),
  ('ACC', 'kola-nuts'),
  ('ACC', 'parrots'),
  ('ACC', 'raffia-cloth'),
  ('ADE', 'dragons-blood'),
  ('ADE', 'myrrh'),
  ('ADE', 'persian-berries'),
  ('ADE', 'persian-carpet'),
  ('ADE', 'persian-tombak'),
  ('ADE', 'pistachios'),
  ('ADE', 'socotra-aloes'),
  ('AGA', 'almonds'),
  ('AGA', 'camels'),
  ('AGA', 'gold'),
  ('AGA', 'wax'),
  ('ALE', 'coffee'),
  ('ALE', 'cumin'),
  ('ALE', 'damascene-work'),
  ('ALE', 'damascus-blades'),
  ('ALE', 'damask'),
  ('ALE', 'linen'),
  ('ALE', 'mumia'),
  ('ALE', 'safflower'),
  ('ALE', 'senna'),
  ('ALE', 'sesame-oil'),
  ('ALG', 'citrus'),
  ('ALG', 'coral'),
  ('ALG', 'couscous'),
  ('ALG', 'figs'),
  ('ALG', 'harissa'),
  ('ALG', 'maghreb-brass'),
  ('ALG', 'wool-raw'),
  ('AMB', 'betel-quid'),
  ('AMB', 'burma-rubies'),
  ('AMB', 'cloves'),
  ('AMB', 'nutmeg'),
  ('AMB', 'sago'),
  ('AMS', 'glass-beads'),
  ('AMS', 'gunpowder'),
  ('AMS', 'pike-heads'),
  ('AMS', 'rhenish-wine'),
  ('AMS', 'sea-charts'),
  ('AMS', 'ships-nails'),
  ('AMS', 'smoked-eel'),
  ('AMS', 'snuff'),
  ('AMS', 'spelt'),
  ('AMS', 'vermilion'),
  ('ANC', 'crossbows'),
  ('ANC', 'murano-glass'),
  ('ANC', 'portolan-charts'),
  ('ANC', 'theriac'),
  ('ANG', 'indigo'),
  ('ANG', 'salted-beef'),
  ('ANG', 'wheat'),
  ('ANG', 'wine'),
  ('ANT', 'alum-shale'),
  ('ANT', 'angora'),
  ('ANT', 'carpets'),
  ('ANT', 'sponges'),
  ('ARP', 'books'),
  ('ARP', 'clocks'),
  ('ARP', 'cognac'),
  ('ARP', 'delftware'),
  ('ARP', 'diamonds'),
  ('ARP', 'felt-hats'),
  ('ARP', 'firearms'),
  ('ARP', 'paintings'),
  ('ARP', 'says-serges'),
  ('ARP', 'tapestries'),
  ('ARI', 'potosi-silver'),
  ('ARI', 'vicuna-wool'),
  ('ARI', 'coca-leaf'),
  ('ARI', 'chuno'),
  ('ARI', 'pisco'),
  ('ARI', 'alpaca-wool'),
  ('ARK', 'angelica-root'),
  ('ARK', 'aquavit'),
  ('ARK', 'caviar'),
  ('ARK', 'isinglass'),
  ('ARK', 'potash'),
  ('ARK', 'russia-leather'),
  ('ARK', 'walrus-ivory'),
  ('AST', 'beaver-pelts'),
  ('AST', 'douglas-fir'),
  ('AST', 'pine-pitch'),
  ('AST', 'dentalium'),
  ('AUK', 'kauri-timber'),
  ('AUK', 'kauri-gum'),
  ('AUK', 'harakeke'),
  ('AUK', 'kumara'),
  ('AYU', 'benzoin'),
  ('AYU', 'celadon'),
  ('AYU', 'ceylon-sapphires'),
  ('AYU', 'clove-oil'),
  ('AYU', 'galangal'),
  ('AYU', 'gamboge'),
  ('AYU', 'sappanwood'),
  ('BAN', 'benzoin'),
  ('BAN', 'camphor'),
  ('BAN', 'coconut-arrack'),
  ('BAN', 'fish-sauce'),
  ('BAN', 'gutta-percha'),
  ('BAN', 'ikat'),
  ('BND', 'kris'),
  ('BND', 'mace'),
  ('BND', 'nutmeg'),
  ('BND', 'paradise-plumes'),
  ('BND', 'sago'),
  ('BAS', 'arabian-horses'),
  ('BAS', 'asafoetida'),
  ('BAS', 'astrolabes'),
  ('BAS', 'dates'),
  ('BAS', 'lapis-lazuli'),
  ('BAS', 'rosewater'),
  ('BAS', 'turquoise'),
  ('BNT', 'batik'),
  ('BNT', 'camphor'),
  ('BNT', 'cubeb'),
  ('BNT', 'nipa-mats'),
  ('BNT', 'palm-sugar'),
  ('BNT', 'patchouli'),
  ('BNT', 'sappan-java'),
  ('BAR', 'almonds'),
  ('BAR', 'andalusian-horses'),
  ('BAR', 'armillary-spheres'),
  ('BAR', 'azulejos'),
  ('BAR', 'bacalhau'),
  ('BAR', 'cinnabar'),
  ('BAR', 'dyers-broom'),
  ('BAR', 'glassware'),
  ('BAR', 'hake'),
  ('BAR', 'saffron'),
  ('NAV', 'mezcal'),
  ('NAV', 'featherwork'),
  ('NAV', 'pulque'),
  ('NAV', 'coconut-wine'),
  ('BSR', 'attar-of-roses'),
  ('BSR', 'dates'),
  ('BSR', 'gallnuts'),
  ('BSR', 'horses'),
  ('BSR', 'peridot'),
  ('BSR', 'persian-berries'),
  ('BEI', 'cedar'),
  ('BEI', 'cotton-raw'),
  ('BEI', 'olive-oil'),
  ('BEI', 'pistachios'),
  ('BEI', 'rosewater'),
  ('BEI', 'sesame-oil'),
  ('BEI', 'soap'),
  ('BEL', 'alpaca-wool'),
  ('BEL', 'annatto'),
  ('BEL', 'brazil-twist'),
  ('BEL', 'parrots'),
  ('BER', 'falcons'),
  ('BER', 'halibut'),
  ('BER', 'herring'),
  ('BER', 'mead'),
  ('BER', 'norway-spruce'),
  ('BER', 'tar'),
  ('BIL', 'baleen'),
  ('BIL', 'merino-sheep'),
  ('BIL', 'merino-wool'),
  ('BIL', 'port-wine'),
  ('BIL', 'sardines'),
  ('BOR', 'antwerp-presses'),
  ('BOR', 'arquebus'),
  ('BOR', 'brandy'),
  ('BOR', 'brass-ingots'),
  ('BOR', 'burgundy'),
  ('BOR', 'canvas-duck'),
  ('BOR', 'claret'),
  ('BOR', 'rosin'),
  ('BOR', 'weld'),
  ('BOR', 'woad'),
  ('BOS', 'cod'),
  ('BOS', 'furs'),
  ('BOS', 'naval-timber'),
  ('BOS', 'salted-beef'),
  ('BOS', 'timber'),
  ('BRI', 'black-coral'),
  ('BRI', 'cassava-bread'),
  ('BRI', 'molasses'),
  ('BRI', 'rum'),
  ('BRS', 'baize'),
  ('BRS', 'cider'),
  ('BRS', 'coal'),
  ('BRS', 'copper-sheet'),
  ('BRS', 'cordage'),
  ('BRS', 'lead'),
  ('BRS', 'pewter'),
  ('BRU', 'cognac'),
  ('BRU', 'delftware'),
  ('BRU', 'flanders-lace'),
  ('BRU', 'lace'),
  ('BUV', 'platinum'),
  ('BUV', 'gold-dust'),
  ('BUV', 'balsa-wood'),
  ('BUV', 'hammocks'),
  ('BUE', 'cachaca'),
  ('BUE', 'charqui'),
  ('BUE', 'chicha'),
  ('BUE', 'coca-leaf'),
  ('BUE', 'copaiba'),
  ('BUE', 'salted-beef'),
  ('BUE', 'tallow'),
  ('BUS', 'celadon'),
  ('BUS', 'doenjang'),
  ('BUS', 'dried-squid'),
  ('BUS', 'ginseng'),
  ('BUS', 'ginseng-korea'),
  ('BUS', 'ink-sticks'),
  ('BUS', 'paper'),
  ('BUS', 'rice'),
  ('BUS', 'soju'),
  ('BUS', 'tiger-skins'),
  ('CAD', 'coriander'),
  ('CAD', 'dyers-broom'),
  ('CAD', 'hake'),
  ('CAD', 'merino-sheep'),
  ('CAD', 'merino-wool'),
  ('CAD', 'port-wine'),
  ('CAD', 'quicksilver'),
  ('CAD', 'salted-tuna'),
  ('CAD', 'silver-plate'),
  ('CAD', 'sword-blades'),
  ('CAG', 'anchovies'),
  ('CAG', 'capers'),
  ('CAG', 'chianti'),
  ('CAG', 'coral'),
  ('CAL', 'camwood'),
  ('CAL', 'ivory'),
  ('CAL', 'ostrich-feathers'),
  ('CAL', 'palm-oil'),
  ('CLS', 'flemish-panels'),
  ('CLS', 'gin'),
  ('CLS', 'globes'),
  ('CLS', 'holland-linen'),
  ('CLL', 'cacao'),
  ('CLL', 'cinchona-bark'),
  ('CLL', 'copper'),
  ('CLL', 'featherwork'),
  ('CLL', 'hides'),
  ('CLL', 'pulque'),
  ('CLL', 'silver'),
  ('CLL', 'tallow'),
  ('CLL', 'vicuna-wool'),
  ('CLL', 'wheat'),
  ('CAP', 'adire-cloth'),
  ('CAP', 'ashanti-goldwork'),
  ('CAP', 'ivory'),
  ('CAP', 'maize'),
  ('CPT', 'civet-cats'),
  ('CPT', 'honeybush'),
  ('CPT', 'kanga-cloth'),
  ('CPT', 'malachite'),
  ('CPT', 'myrrh-somali'),
  ('CAR', 'allspice'),
  ('CAR', 'chillies'),
  ('CAR', 'cigars'),
  ('CAR', 'cuban-leaf'),
  ('CAR', 'emeralds'),
  ('CAR', 'lignum-vitae'),
  ('CAR', 'pearls'),
  ('CAR', 'sarsaparilla'),
  ('CAR', 'tolu-balsam'),
  ('CAR', 'tortoiseshell-combs'),
  ('CEB', 'abaca'),
  ('CEB', 'mother-of-pearl'),
  ('CEB', 'shrimp-paste'),
  ('CEB', 'tortoiseshell'),
  ('CEU', 'mint-tea'),
  ('CEU', 'onyx'),
  ('CEU', 'orchil'),
  ('CEU', 'quran-manuscripts'),
  ('CHE', 'bidriware'),
  ('CHE', 'cinnamon'),
  ('CHE', 'dhaka-muslin'),
  ('CHE', 'golconda-diamonds'),
  ('CHE', 'red-sanders'),
  ('CHE', 'saltpetre'),
  ('CHE', 'turmeric'),
  ('CHS', 'bombard'),
  ('CHS', 'iznik-tiles'),
  ('CHS', 'malmsey'),
  ('CHS', 'mohair'),
  ('CHI', 'kino-gum'),
  ('CHI', 'long-pepper'),
  ('CHI', 'rhino-horn'),
  ('CHI', 'sesame-oil'),
  ('CID', 'horses'),
  ('CID', 'madeira-wine'),
  ('CID', 'orchil'),
  ('CID', 'salt'),
  ('COL', 'arrack'),
  ('COL', 'cowries'),
  ('COL', 'diamonds'),
  ('COL', 'elephants'),
  ('COL', 'palm-leaf-manuscripts'),
  ('COL', 'peacocks'),
  ('COL', 'turmeric-dye'),
  ('CON', 'chilean-wine'),
  ('CON', 'alerce-timber'),
  ('CON', 'charqui'),
  ('CON', 'araucaria-nuts'),
  ('COP', 'amber'),
  ('COP', 'amber-work'),
  ('COP', 'baltic-amber'),
  ('COP', 'bar-iron'),
  ('COP', 'barley'),
  ('COP', 'beer'),
  ('COP', 'buckwheat'),
  ('COP', 'butter'),
  ('COP', 'hamburg-beer'),
  ('COP', 'rye'),
  ('COQ', 'chilean-copper'),
  ('COQ', 'chilean-wine'),
  ('COQ', 'andacollo-gold'),
  ('COQ', 'mules'),
  ('COR', 'olive-oil'),
  ('COR', 'rakia'),
  ('COR', 'swivel-gun'),
  ('COR', 'theriaca-venetian'),
  ('CRK', 'butter'),
  ('CRK', 'culverin'),
  ('CRK', 'english-ale'),
  ('CRK', 'irish-linen'),
  ('CUM', 'black-coral'),
  ('CUM', 'cassava-bread'),
  ('CUM', 'cigars'),
  ('CUM', 'pearls'),
  ('DAR', 'trepang'),
  ('DAR', 'pandanus-mats'),
  ('DAR', 'wax'),
  ('DAR', 'kangaroo-skins'),
  ('DIL', 'barkcloth'),
  ('DIL', 'opals'),
  ('DIL', 'pandanus-mats'),
  ('DIL', 'tapa-cloth'),
  ('DIU', 'carnelian'),
  ('DIU', 'catechu'),
  ('DIU', 'coco-fibre'),
  ('DIU', 'cowries'),
  ('DUB', 'butter'),
  ('DUB', 'kersey'),
  ('DUB', 'linen'),
  ('DUB', 'mackerel'),
  ('DUB', 'nautical-clocks'),
  ('DUB', 'oakum'),
  ('DUB', 'oats'),
  ('DBR', 'crossbows'),
  ('DBR', 'murano-glass'),
  ('DBR', 'portolan-charts'),
  ('DBR', 'rakia'),
  ('DBR', 'tokay'),
  ('DBR', 'venetian-imprints'),
  ('DBR', 'venetian-mirrors'),
  ('REA', 'anil'),
  ('REA', 'pine-pitch'),
  ('REA', 'hammocks'),
  ('REA', 'cordage'),
  ('ELM', 'benin-bronzes'),
  ('ELM', 'black-pepper'),
  ('ELM', 'gold-dust'),
  ('ELM', 'grains-of-paradise'),
  ('ELM', 'kola-nuts'),
  ('ELM', 'palm-wine'),
  ('FAM', 'arak-levant'),
  ('FAM', 'commandaria'),
  ('FAM', 'cotton-raw'),
  ('FAM', 'gold-thread'),
  ('FEO', 'caviar'),
  ('FEO', 'ouzo'),
  ('FEO', 'retsina'),
  ('FEO', 'saffron-dye'),
  ('FRE', 'sandalwood'),
  ('FRE', 'wattle-bark'),
  ('FRE', 'sperm-oil'),
  ('FRE', 'jarrah'),
  ('FUK', 'bonito'),
  ('FUK', 'dried-abalone'),
  ('FUK', 'sake'),
  ('FUK', 'shochu'),
  ('FUK', 'sutra-scrolls'),
  ('FUK', 'ukiyo-e'),
  ('FNC', 'dried-fruit'),
  ('FNC', 'sugar'),
  ('FNC', 'timber'),
  ('FNC', 'wine'),
  ('FUZ', 'antimony'),
  ('FUZ', 'lacquerware'),
  ('FUZ', 'lychees'),
  ('FUZ', 'tea'),
  ('GAL', 'cowries'),
  ('GAL', 'ebony'),
  ('GAL', 'zedoary'),
  ('GAL', 'zinc-spelter'),
  ('GDA', 'amber'),
  ('GDA', 'beer'),
  ('GDA', 'juniper-berries'),
  ('GDA', 'kvass'),
  ('GDA', 'memel-fir'),
  ('GDA', 'potash'),
  ('GDA', 'prussian-blue'),
  ('GDA', 'rosin'),
  ('GDA', 'rye'),
  ('GDA', 'tar'),
  ('GOA', 'alum'),
  ('GOA', 'armour'),
  ('GOA', 'falconet'),
  ('GOA', 'fustian'),
  ('GOA', 'gold-thread'),
  ('GOA', 'grappa'),
  ('GOA', 'italian-canvases'),
  ('GOA', 'kermes'),
  ('GOA', 'marble'),
  ('GOA', 'velvet'),
  ('GIB', 'salted-tuna'),
  ('GIB', 'sherry'),
  ('GIB', 'slow-match'),
  ('GIB', 'toledo-blades'),
  ('GOR', 'grains-paradise-oil'),
  ('GOR', 'kente-cloth'),
  ('GOR', 'kola-nuts'),
  ('GOR', 'millet'),
  ('GUA', 'baijiu'),
  ('GUA', 'block-printed-books'),
  ('GUA', 'canton-enamel'),
  ('GUA', 'cassia'),
  ('GUA', 'cloisonne'),
  ('GUA', 'lacquerware'),
  ('GUA', 'porcelain'),
  ('GUA', 'star-anise'),
  ('GUA', 'tea'),
  ('GUA', 'vermilion'),
  ('GYE', 'guayaquil-cacao'),
  ('GYE', 'toquilla-straw'),
  ('GYE', 'balsa-wood'),
  ('GYE', 'cinchona-bark'),
  ('GYE', 'mangrove-bark'),
  ('HAD', 'frankincense'),
  ('HAD', 'persian-carpet'),
  ('HAD', 'persian-tombak'),
  ('HAD', 'seed-pearls'),
  ('HAG', 'coconuts'),
  ('HAG', 'dried-fish'),
  ('HAG', 'rice'),
  ('HAG', 'salt'),
  ('HAM', 'brassware'),
  ('HAM', 'buckwheat'),
  ('HAM', 'cannon'),
  ('HAM', 'clocks'),
  ('HAM', 'hamburg-beer'),
  ('HAM', 'hops'),
  ('HAM', 'juniper-berries'),
  ('HAM', 'silver-plate'),
  ('HAM', 'smallwares'),
  ('HAM', 'stoneware'),
  ('HAN', 'betel-quid'),
  ('HAN', 'cassia'),
  ('HAN', 'songket'),
  ('HAN', 'star-anise'),
  ('HAV', 'cedar'),
  ('HAV', 'cuban-leaf'),
  ('HAV', 'emeralds'),
  ('HAV', 'guaiacum'),
  ('HAV', 'jalap'),
  ('HAV', 'lignum-vitae'),
  ('HAV', 'peru-balsam'),
  ('HAV', 'tolu-balsam'),
  ('HAV', 'tortoiseshell-combs'),
  ('HAV', 'vanilla'),
  ('HER', 'alum-shale'),
  ('HER', 'angora'),
  ('HER', 'cheese'),
  ('HER', 'honey'),
  ('HER', 'storax'),
  ('HER', 'turkish-leaf'),
  ('HIR', 'dried-abalone'),
  ('HIR', 'firearms'),
  ('HIR', 'folding-fans'),
  ('HIR', 'imari-ware'),
  ('HIR', 'japan-copper'),
  ('HIR', 'kampo-herbs'),
  ('HOB', 'huon-pine'),
  ('HOB', 'sperm-oil'),
  ('HOB', 'wattle-bark'),
  ('HOB', 'kangaroo-skins'),
  ('HOI', 'aloeswood'),
  ('HOI', 'birds-nests'),
  ('HOI', 'burma-rubies'),
  ('HOI', 'cassia'),
  ('HOI', 'ceylon-sapphires'),
  ('HOI', 'clove-oil'),
  ('HOI', 'galangal'),
  ('HON', 'aloeswood'),
  ('HON', 'dragon-bone'),
  ('HON', 'fire-lance'),
  ('HON', 'jade'),
  ('HNL', 'barkcloth'),
  ('HNL', 'dried-fish'),
  ('HNL', 'salt'),
  ('HNL', 'sandalwood'),
  ('HOO', 'bidriware'),
  ('HOO', 'chank-shells'),
  ('HOO', 'muslin'),
  ('HOO', 'opium'),
  ('HOO', 'quilts'),
  ('HOO', 'saltpetre'),
  ('HOO', 'spikenard'),
  ('HRN', 'antwerp-presses'),
  ('HRN', 'arquebus'),
  ('HRN', 'brass-ingots'),
  ('HRN', 'burgundy'),
  ('HOR', 'cobalt'),
  ('HOR', 'lapis-lazuli'),
  ('HOR', 'seed-pearls'),
  ('HOR', 'sherbet'),
  ('HOR', 'socotra-aloes'),
  ('HOR', 'steel-billets'),
  ('HOR', 'turquoise'),
  ('HUA', 'soconusco-cacao'),
  ('HUA', 'anil'),
  ('HUA', 'mezcal'),
  ('HUA', 'talavera'),
  ('INC', 'ginseng'),
  ('INC', 'gochujang'),
  ('INC', 'goryeo-celadon'),
  ('INC', 'ink-sticks'),
  ('INC', 'paper'),
  ('INC', 'ramie-cloth'),
  ('INC', 'rice'),
  ('IST', 'alum'),
  ('IST', 'angora'),
  ('IST', 'bombard'),
  ('IST', 'camlets'),
  ('IST', 'caviar'),
  ('IST', 'gallnuts'),
  ('IST', 'hazelnuts'),
  ('IST', 'isinglass'),
  ('IST', 'iznik-tiles'),
  ('IST', 'mastic'),
  ('IZM', 'bombard'),
  ('IZM', 'camlets'),
  ('IZM', 'carpets'),
  ('IZM', 'figs'),
  ('IZM', 'hazelnuts'),
  ('IZM', 'madder'),
  ('IZM', 'mastic'),
  ('JAF', 'chank-shells'),
  ('JAF', 'dhaka-muslin'),
  ('JAF', 'golconda-diamonds'),
  ('JAF', 'kino-gum'),
  ('JAK', 'arrack'),
  ('JAK', 'batik'),
  ('JAK', 'cloves'),
  ('JAK', 'coconut-arrack'),
  ('JAK', 'fish-sauce'),
  ('JAK', 'gamboge'),
  ('JAK', 'gutta-percha'),
  ('JAK', 'ikat'),
  ('JAK', 'kris'),
  ('JAK', 'nutmeg'),
  ('JAM', 'furs'),
  ('JAM', 'live-oak'),
  ('JAM', 'maple-sugar'),
  ('JAM', 'sassafras'),
  ('JAM', 'tobacco'),
  ('JED', 'arabian-horses'),
  ('JED', 'asafoetida'),
  ('JED', 'astrolabes'),
  ('JED', 'attar-of-roses'),
  ('JED', 'mecca-balsam'),
  ('JED', 'myrrh'),
  ('JED', 'ultramarine'),
  ('JEJ', 'dried-abalone'),
  ('JEJ', 'hemp-cloth'),
  ('JEJ', 'horses'),
  ('JEJ', 'seaweed'),
  ('KAG', 'bonito'),
  ('KAG', 'imari-ware'),
  ('KAG', 'japan-copper'),
  ('KAG', 'sulphur'),
  ('KAL', 'amber'),
  ('KAL', 'linseed'),
  ('KAL', 'riga-mast'),
  ('KAL', 'rye'),
  ('KAN', 'areca-nuts'),
  ('KAN', 'ayurvedic-oils'),
  ('KAN', 'cardamom'),
  ('KAN', 'coco-fibre'),
  ('KAR', 'asafoetida'),
  ('KAR', 'ghee'),
  ('KAR', 'kashmir-shawl'),
  ('KAR', 'shawls'),
  ('KHA', 'carnelian'),
  ('KHA', 'cumin'),
  ('KHA', 'ghee'),
  ('KHA', 'mughal-miniatures'),
  ('KHA', 'myrobalans'),
  ('KHA', 'neem'),
  ('KHA', 'opium'),
  ('KIL', 'ambergris'),
  ('KIL', 'mangrove-poles'),
  ('KIL', 'shields'),
  ('KIL', 'sorghum'),
  ('KIN', 'coal'),
  ('KIN', 'herring'),
  ('KIN', 'lead'),
  ('KIN', 'parchment'),
  ('KOC', 'areca-nuts'),
  ('KOC', 'cardamom'),
  ('KOC', 'coir'),
  ('KOC', 'cumin'),
  ('KOC', 'kashmir-shawl'),
  ('KOC', 'mughal-miniatures'),
  ('KOC', 'myrobalans'),
  ('KOC', 'neem'),
  ('KOC', 'teak'),
  ('KOC', 'wootz-steel'),
  ('KOL', 'coconuts'),
  ('KOL', 'coir'),
  ('KOL', 'patola-silk'),
  ('KOL', 'rocket-tubes'),
  ('KOZ', 'areca-nuts'),
  ('KOZ', 'ayurvedic-oils'),
  ('KOZ', 'cardamom'),
  ('KOZ', 'coir'),
  ('KOZ', 'sandalwood-carving'),
  ('KOZ', 'talwar'),
  ('KOZ', 'teak'),
  ('KOZ', 'toddy'),
  ('KOZ', 'turmeric'),
  ('KOZ', 'zebu-cattle'),
  ('KUP', 'sandalwood'),
  ('KUP', 'sharks-fin'),
  ('KUP', 'trepang'),
  ('KUP', 'wax'),
  ('LAR', 'brandy'),
  ('LAR', 'lead-white'),
  ('LAR', 'paintings'),
  ('LAR', 'perry'),
  ('LAR', 'pike-heads'),
  ('LAR', 'rhenish-wine'),
  ('LAR', 'ships-nails'),
  ('LAG', 'black-pepper'),
  ('LAG', 'camwood'),
  ('LAG', 'ochre'),
  ('LAG', 'palm-oil'),
  ('LPA', 'archil-lichen'),
  ('LPA', 'canary-sack'),
  ('LPA', 'indigo'),
  ('LPA', 'orchil'),
  ('LPA', 'sugar'),
  ('LPA', 'wine'),
  ('LEH', 'canvas-duck'),
  ('LEH', 'claret'),
  ('LEH', 'cognac'),
  ('LEH', 'felt-hats'),
  ('LEI', 'barley'),
  ('LEI', 'coal'),
  ('LEI', 'herring'),
  ('LEI', 'pilchards'),
  ('LIS', 'anise'),
  ('LIS', 'black-pepper'),
  ('LIS', 'cinnamon'),
  ('LIS', 'cork'),
  ('LIS', 'iron'),
  ('LIS', 'porcelain'),
  ('LIS', 'quicksilver'),
  ('LIS', 'silk-cloth'),
  ('LIS', 'silk-raw'),
  ('LIS', 'wool-cloth'),
  ('LIV', 'alum'),
  ('LIV', 'majolica'),
  ('LIV', 'marble'),
  ('LIV', 'milanese-armour'),
  ('LIV', 'olives'),
  ('LIV', 'tuna'),
  ('LON', 'beer'),
  ('LON', 'cannon'),
  ('LON', 'felt-hats'),
  ('LON', 'gunpowder'),
  ('LON', 'pewter'),
  ('LON', 'pipe-tobacco'),
  ('LON', 'porter-beer'),
  ('LON', 'sheffield-plate'),
  ('LON', 'stockings'),
  ('LON', 'tin'),
  ('LNG', 'osmund-iron'),
  ('LNG', 'salmon'),
  ('LNG', 'sami-craft'),
  ('LNG', 'walrus-ivory'),
  ('LUA', 'cassava'),
  ('LUA', 'copper'),
  ('LUA', 'palm-wine'),
  ('LUA', 'plantains'),
  ('LUA', 'raffia-cloth'),
  ('LUA', 'shea-butter'),
  ('LUA', 'yams'),
  ('LUB', 'amber-work'),
  ('LUB', 'hops'),
  ('LUB', 'linen'),
  ('LUB', 'russia-hemp'),
  ('LUB', 'sailcloth'),
  ('LUB', 'shot-and-ball'),
  ('LUB', 'smallwares'),
  ('LUB', 'smalt'),
  ('LUB', 'sturgeon'),
  ('LUB', 'vodka'),
  ('MAC', 'china-root'),
  ('MAC', 'jade'),
  ('MAC', 'lodestone'),
  ('MAC', 'musk'),
  ('MAC', 'nankeen'),
  ('MAC', 'rhubarb'),
  ('MAC', 'rice-paper'),
  ('MAC', 'rice-vinegar'),
  ('MAC', 'scroll-paintings'),
  ('MAC', 'shantung-silk'),
  ('MCH', 'chintz'),
  ('MCH', 'diamonds'),
  ('MCH', 'turmeric'),
  ('MCH', 'wootz-steel'),
  ('MAK', 'birds-nests'),
  ('MAK', 'cloves'),
  ('MAK', 'mace'),
  ('MAK', 'nipa-mats'),
  ('MAK', 'patchouli'),
  ('MAK', 'sago'),
  ('MAK', 'trepang'),
  ('MAL', 'abaca'),
  ('MAL', 'aloeswood'),
  ('MAL', 'benzoin'),
  ('MAL', 'betel-quid'),
  ('MAL', 'bezoar'),
  ('MAL', 'rattan'),
  ('MAL', 'sappan-java'),
  ('MAL', 'shrimp-paste'),
  ('MAL', 'songket'),
  ('MAL', 'zedoary'),
  ('MLG', 'andalusian-horses'),
  ('MLG', 'anise'),
  ('MLG', 'armillary-spheres'),
  ('MLG', 'azulejos'),
  ('MLG', 'bacalhau'),
  ('MLG', 'cinnabar'),
  ('MLG', 'figs'),
  ('MLE', 'catechu'),
  ('MLE', 'coco-fibre'),
  ('MLE', 'kashmir-shawl'),
  ('MLE', 'mughal-miniatures'),
  ('MLN', 'ambergris'),
  ('MLN', 'hemp'),
  ('MLN', 'teff'),
  ('MLN', 'zanzibar-doors'),
  ('MAN', 'dates'),
  ('MAN', 'mother-of-pearl'),
  ('MAN', 'sherbet'),
  ('MAN', 'steel-billets'),
  ('MNG', 'neem'),
  ('MNG', 'palm-sugar'),
  ('MNG', 'patola-silk'),
  ('MNG', 'teak'),
  ('MNL', 'abaca'),
  ('MNL', 'ikat'),
  ('MNL', 'kris'),
  ('MNL', 'mace'),
  ('MNL', 'nipa-mats'),
  ('MNL', 'paradise-plumes'),
  ('MNL', 'patchouli'),
  ('MNL', 'rattan'),
  ('MNL', 'sappan-java'),
  ('MNL', 'shrimp-paste'),
  ('MRS', 'anise'),
  ('MRS', 'cotton-cloth'),
  ('MRS', 'milanese-armour'),
  ('MRS', 'olives'),
  ('MRS', 'silk-cloth'),
  ('MRS', 'tuna'),
  ('MRS', 'velvet'),
  ('MRS', 'verdigris'),
  ('MRS', 'woad'),
  ('MRS', 'wool-cloth'),
  ('MAS', 'civet'),
  ('MAS', 'civet-cats'),
  ('MAS', 'copal'),
  ('MAS', 'honeybush'),
  ('MAT', 'kampo-herbs'),
  ('MAT', 'katana'),
  ('MAT', 'katsuobushi'),
  ('MAT', 'kyoto-fans'),
  ('MZT', 'baja-pearls'),
  ('MZT', 'zacatecas-silver'),
  ('MZT', 'mezcal'),
  ('MZT', 'dried-shrimp'),
  ('MES', 'anchovies'),
  ('MES', 'armour'),
  ('MES', 'capers'),
  ('MES', 'citrus'),
  ('MEZ', 'stockfish'),
  ('MEZ', 'halibut'),
  ('MEZ', 'eiderdown'),
  ('MEZ', 'whale-bone-stays'),
  ('MID', 'delftware'),
  ('MID', 'flanders-lace'),
  ('MID', 'madder'),
  ('MID', 'says-serges'),
  ('MOC', 'coffee'),
  ('MOC', 'frankincense'),
  ('MOC', 'gum-arabic'),
  ('MOC', 'myrrh'),
  ('MOC', 'senna'),
  ('MOC', 'ultramarine'),
  ('MOG', 'civet'),
  ('MOG', 'frankincense'),
  ('MOG', 'kanga-cloth'),
  ('MOG', 'malachite'),
  ('MOK', 'kimchi'),
  ('MOK', 'korean-movable-type'),
  ('MOK', 'ramie-cloth'),
  ('MOK', 'seaweed'),
  ('MOM', 'hemp'),
  ('MOM', 'mangrove-poles'),
  ('MOM', 'myrrh-somali'),
  ('MOM', 'rhino-horn'),
  ('MOM', 'shields'),
  ('MOM', 'sorghum'),
  ('MOM', 'teff'),
  ('MTY', 'sea-otter-pelts'),
  ('MTY', 'abalone-shell'),
  ('MTY', 'california-hides'),
  ('MTY', 'salmon'),
  ('ISL', 'civet'),
  ('ISL', 'civet-cats'),
  ('ISL', 'copal'),
  ('ISL', 'ebony'),
  ('ISL', 'henna'),
  ('ISL', 'mangrove-poles'),
  ('ISL', 'zanzibar-doors'),
  ('MUM', 'catechu'),
  ('MUM', 'rocket-tubes'),
  ('MUM', 'safflower'),
  ('MUM', 'sandalwood-carving'),
  ('MUM', 'talwar'),
  ('MUM', 'tamarind'),
  ('MUM', 'toddy'),
  ('MUS', 'arabian-horses'),
  ('MUS', 'astrolabes'),
  ('MUS', 'attar-of-roses'),
  ('MUS', 'cobalt'),
  ('MUS', 'dragons-blood'),
  ('MUS', 'lapis-lazuli'),
  ('MYE', 'lac'),
  ('MYE', 'long-pepper'),
  ('MYE', 'sappanwood'),
  ('MYE', 'tin'),
  ('NAG', 'camphor'),
  ('NAG', 'katana'),
  ('NAG', 'katsuobushi'),
  ('NAG', 'kyoto-fans'),
  ('NAG', 'matchlocks'),
  ('NAG', 'mirin'),
  ('NAG', 'miso'),
  ('NAG', 'moxa'),
  ('NAG', 'soy-sauce'),
  ('NAG', 'sulphur'),
  ('NAH', 'mother-of-pearl'),
  ('NAH', 'nishijin-brocade'),
  ('NAH', 'pickled-plums'),
  ('NAH', 'sappanwood'),
  ('NAH', 'sharks-fin'),
  ('NAH', 'shochu'),
  ('NAH', 'tortoiseshell'),
  ('NAM', 'ginseng'),
  ('NAM', 'mother-of-pearl-inlay'),
  ('NAM', 'nephrite'),
  ('NAM', 'tiger-skins'),
  ('NAN', 'antwerp-presses'),
  ('NAN', 'brandy'),
  ('NAN', 'smoked-eel'),
  ('NAN', 'snuff'),
  ('NAN', 'spelt'),
  ('NAN', 'tapestries'),
  ('NAN', 'weld'),
  ('NAP', 'almonds'),
  ('NAP', 'chianti'),
  ('NAP', 'falconet'),
  ('NAP', 'fustian'),
  ('NAP', 'grappa'),
  ('NAP', 'hemp'),
  ('NAP', 'verdigris'),
  ('NEW', 'furs'),
  ('NEW', 'maryland-leaf'),
  ('NEW', 'naval-timber'),
  ('NEW', 'pemmican'),
  ('NEW', 'salt-cod'),
  ('NEW', 'tobacco'),
  ('NIN', 'copper-cash'),
  ('NIN', 'ink-sticks'),
  ('NIN', 'lodestone'),
  ('NIN', 'paper'),
  ('NIN', 'porcelain'),
  ('NIN', 'rhubarb'),
  ('NIN', 'tea'),
  ('NUU', 'narwhal-horn'),
  ('NUU', 'sealskins'),
  ('NUU', 'stockfish'),
  ('NUU', 'walrus-ivory'),
  ('OLD', 'arrack'),
  ('OLD', 'bezoar'),
  ('OLD', 'cinnamon'),
  ('OLD', 'opium'),
  ('OLD', 'palm-sugar'),
  ('OLD', 'patola-silk'),
  ('OLD', 'rocket-tubes'),
  ('OLD', 'safflower'),
  ('OLD', 'sandalwood-carving'),
  ('OLD', 'shawls'),
  ('ORA', 'camels'),
  ('ORA', 'saffian-leather'),
  ('ORA', 'sumac'),
  ('ORA', 'wool-raw'),
  ('OSA', 'folding-fans'),
  ('OSA', 'matchlocks'),
  ('OSA', 'mirin'),
  ('OSA', 'miso'),
  ('OSA', 'moxa'),
  ('OSA', 'nishijin-brocade'),
  ('OSA', 'pickled-plums'),
  ('OSA', 'sake'),
  ('OSA', 'shochu'),
  ('OSA', 'soy-sauce'),
  ('OUI', 'adire-cloth'),
  ('OUI', 'ashanti-goldwork'),
  ('OUI', 'benin-bronzes'),
  ('OUI', 'palm-oil'),
  ('PAI', 'pisco'),
  ('PAI', 'goatskins'),
  ('PAI', 'piura-cotton'),
  ('PAI', 'chicha'),
  ('PAL', 'citrus'),
  ('PAL', 'italian-canvases'),
  ('PAL', 'kermes'),
  ('PAL', 'milanese-armour'),
  ('PAL', 'olives'),
  ('PAL', 'salted-tuna'),
  ('PAL', 'tuna'),
  ('PLM', 'anchovies'),
  ('PLM', 'armour'),
  ('PLM', 'cheese'),
  ('PLM', 'verdigris'),
  ('PAN', 'cacao'),
  ('PAN', 'gold'),
  ('PAN', 'hides'),
  ('PAN', 'pearls'),
  ('PAN', 'silver'),
  ('PAR', 'annatto'),
  ('PAR', 'cotton-raw'),
  ('PAR', 'emerald-muzo'),
  ('PAR', 'greenheart'),
  ('PAT', 'silk-raw'),
  ('PAT', 'swivel-gun'),
  ('PAT', 'theriac'),
  ('PAT', 'theriaca-venetian'),
  ('PTT', 'birds-nests'),
  ('PTT', 'burma-rubies'),
  ('PTT', 'celadon'),
  ('PTT', 'ceylon-sapphires'),
  ('PLY', 'tin'),
  ('PLY', 'tin-ingots'),
  ('PLY', 'whisky'),
  ('PLY', 'worsted'),
  ('PON', 'archil-lichen'),
  ('PON', 'cheese'),
  ('PON', 'madeira-wine'),
  ('PON', 'wheat'),
  ('PON', 'woad'),
  ('PLO', 'ebony'),
  ('PLO', 'honeybush'),
  ('PLO', 'kanga-cloth'),
  ('PLO', 'malachite'),
  ('POR', 'allspice'),
  ('POR', 'annatto'),
  ('POR', 'logwood'),
  ('POR', 'rum'),
  ('PTL', 'cod'),
  ('PTL', 'maple-sugar'),
  ('PTL', 'mast-pine'),
  ('PTL', 'beaver-pelts'),
  ('OPO', 'cork'),
  ('OPO', 'dyers-broom'),
  ('OPO', 'hake'),
  ('OPO', 'merino-sheep'),
  ('OPO', 'merino-wool'),
  ('PRT', 'allspice'),
  ('PRT', 'black-coral'),
  ('PRT', 'cassava-bread'),
  ('PRT', 'cigars'),
  ('PRT', 'cochineal'),
  ('PRT', 'sarsaparilla'),
  ('PTH', 'baize'),
  ('PTH', 'cider'),
  ('PTH', 'copper-sheet'),
  ('PTH', 'cordage'),
  ('PTH', 'culverin'),
  ('PUL', 'chintz'),
  ('PUL', 'martaban-jars'),
  ('PUL', 'muslin'),
  ('PUL', 'palm-leaf-manuscripts'),
  ('PUS', 'gyrfalcons'),
  ('PUS', 'russia-leather'),
  ('PUS', 'narwhal-horn'),
  ('PUS', 'angelica-root'),
  ('QUA', 'copper-cash'),
  ('QUA', 'iron'),
  ('QUA', 'nankeen'),
  ('QUA', 'rhubarb'),
  ('QUA', 'rice-paper'),
  ('QUA', 'rice-vinegar'),
  ('QUA', 'scroll-paintings'),
  ('QUE', 'cod'),
  ('QUE', 'naval-timber'),
  ('QUE', 'sassafras-root'),
  ('QUE', 'virginia-leaf'),
  ('QUE', 'witch-hazel'),
  ('REC', 'brazilwood'),
  ('REC', 'cassava'),
  ('REC', 'macaws'),
  ('REC', 'molasses'),
  ('REC', 'platinum'),
  ('REC', 'potosi-silver'),
  ('REC', 'quinoa'),
  ('REY', 'eiderdown'),
  ('REY', 'gyrfalcons'),
  ('REY', 'stockholm-tar'),
  ('REY', 'sulphur'),
  ('RHO', 'isinglass'),
  ('RHO', 'iznik-tiles'),
  ('RHO', 'malmsey'),
  ('RHO', 'sponges'),
  ('RIG', 'baltic-amber'),
  ('RIG', 'bar-iron'),
  ('RIG', 'brassware'),
  ('RIG', 'buckwheat'),
  ('RIG', 'flax'),
  ('RIG', 'linseed'),
  ('RIG', 'potash'),
  ('RIO', 'alpaca-wool'),
  ('RIO', 'brazil-twist'),
  ('RIO', 'brazilwood'),
  ('RIO', 'cachaca'),
  ('RIO', 'cassava'),
  ('RIO', 'whale-oil'),
  ('ROT', 'flemish-panels'),
  ('ROT', 'gin'),
  ('ROT', 'globes'),
  ('ROT', 'holland-linen'),
  ('ROT', 'lead-white'),
  ('ROT', 'perry'),
  ('ROT', 'stoneware'),
  ('SAF', 'couscous'),
  ('SAF', 'harissa'),
  ('SAF', 'honey'),
  ('SAF', 'maghreb-brass'),
  ('SAI', 'gold-dust'),
  ('SAI', 'grains-of-paradise'),
  ('SAI', 'grains-paradise-oil'),
  ('SAI', 'gum-arabic'),
  ('SNT', 'arquebus'),
  ('SNT', 'brass-ingots'),
  ('SNT', 'burgundy'),
  ('SNT', 'canvas-duck'),
  ('SNT', 'claret'),
  ('SNT', 'stockings'),
  ('SAK', 'bonito'),
  ('SAK', 'firearms'),
  ('SAK', 'folding-fans'),
  ('SAK', 'sake'),
  ('SAK', 'sutra-scrolls'),
  ('SAK', 'sword-blades'),
  ('SAK', 'ukiyo-e'),
  ('SAL', 'mint-tea'),
  ('SAL', 'morocco-leather'),
  ('SAL', 'onyx'),
  ('SAL', 'ostrich-feathers'),
  ('SLV', 'brazil-twist'),
  ('SLV', 'brazilwood'),
  ('SLV', 'cachaca'),
  ('SLV', 'charqui'),
  ('SLV', 'chicha'),
  ('SLV', 'coca-leaf'),
  ('SLV', 'copaiba'),
  ('SLV', 'emerald-muzo'),
  ('SLV', 'molasses'),
  ('SLV', 'whale-oil'),
  ('SDG', 'california-hides'),
  ('SDG', 'mission-wine'),
  ('SDG', 'sea-otter-pelts'),
  ('SDG', 'brea'),
  ('SFR', 'sea-otter-pelts'),
  ('SFR', 'redwood'),
  ('SFR', 'california-hides'),
  ('SFR', 'salmon'),
  ('SFR', 'mission-wine'),
  ('SAN', 'cuban-leaf'),
  ('SAN', 'emeralds'),
  ('SAN', 'ginger'),
  ('SAN', 'guaiacum'),
  ('SNL', 'port-wine'),
  ('SNL', 'sardines'),
  ('SNL', 'sea-charts'),
  ('SNL', 'sherry'),
  ('TEN', 'canary-sack'),
  ('TEN', 'dried-fruit'),
  ('TEN', 'madeira-wine'),
  ('TEN', 'sugar'),
  ('SGO', 'ginger'),
  ('SGO', 'guaiacum'),
  ('SGO', 'jalap'),
  ('SGO', 'lignum-vitae'),
  ('SGO', 'maize'),
  ('SGO', 'peru-balsam'),
  ('SGO', 'tallow'),
  ('SOS', 'greenheart'),
  ('SOS', 'macaws'),
  ('SOS', 'parrots'),
  ('SOS', 'platinum'),
  ('SAO', 'kente-cloth'),
  ('SAO', 'maize'),
  ('SAO', 'millet'),
  ('SAO', 'ochre'),
  ('SET', 'andalusian-horses'),
  ('SET', 'armillary-spheres'),
  ('SET', 'slow-match'),
  ('SET', 'toledo-blades'),
  ('SVQ', 'cochineal'),
  ('SVQ', 'coriander'),
  ('SVQ', 'quicksilver'),
  ('SVQ', 'saffron'),
  ('SVQ', 'sardines'),
  ('SVQ', 'sea-charts'),
  ('SVQ', 'sherry'),
  ('SVQ', 'silver-plate'),
  ('SVQ', 'slow-match'),
  ('SVQ', 'toledo-blades'),
  ('SHI', 'imari-ware'),
  ('SHI', 'japan-copper'),
  ('SHI', 'kampo-herbs'),
  ('SHI', 'katana'),
  ('SOF', 'myrrh-somali'),
  ('SOF', 'senna'),
  ('SOF', 'shields'),
  ('SOF', 'sorghum'),
  ('SOY', 'camwood'),
  ('SOY', 'palm-wine'),
  ('SOY', 'plantains'),
  ('SOY', 'raffia-cloth'),
  ('SPL', 'books'),
  ('SPL', 'tokay'),
  ('SPL', 'venetian-imprints'),
  ('SPL', 'venetian-mirrors'),
  ('STA', 'live-oak'),
  ('STA', 'maple-sugar'),
  ('STA', 'maryland-leaf'),
  ('STA', 'sassafras'),
  ('STG', 'cedar'),
  ('STG', 'pemmican'),
  ('STG', 'sassafras'),
  ('STG', 'tobacco'),
  ('STJ', 'baleen'),
  ('STJ', 'salt-cod'),
  ('STJ', 'sassafras-root'),
  ('STJ', 'virginia-leaf'),
  ('STJ', 'whale-oil'),
  ('STO', 'cannon'),
  ('STO', 'clocks'),
  ('STO', 'hamburg-beer'),
  ('STO', 'hops'),
  ('STO', 'juniper-berries'),
  ('STO', 'kvass'),
  ('STO', 'tar'),
  ('SUA', 'cotton-cloth'),
  ('SUA', 'gum-arabic'),
  ('SUA', 'teff'),
  ('SUA', 'zanzibar-doors'),
  ('SUE', 'coffee'),
  ('SUE', 'flax'),
  ('SUE', 'mecca-balsam'),
  ('SUE', 'peridot'),
  ('SUR', 'batik'),
  ('SUR', 'clove-oil'),
  ('SUR', 'cubeb'),
  ('SUR', 'rattan'),
  ('SRT', 'ayurvedic-oils'),
  ('SRT', 'bezoar'),
  ('SRT', 'carnelian'),
  ('SRT', 'ghee'),
  ('SRT', 'myrobalans'),
  ('SRT', 'saltpetre'),
  ('SRT', 'shawls'),
  ('SRT', 'tamarind'),
  ('SRT', 'wootz-steel'),
  ('SRT', 'zebu-cattle'),
  ('SYD', 'dried-fish'),
  ('SYD', 'sealskins'),
  ('SYD', 'timber'),
  ('SYD', 'wool-raw'),
  ('TAI', 'antimony'),
  ('TAI', 'baijiu'),
  ('TAI', 'block-printed-books'),
  ('TAI', 'shantung-silk'),
  ('TAI', 'songbirds'),
  ('TAL', 'memel-fir'),
  ('TAL', 'prussian-blue'),
  ('TAL', 'riga-mast'),
  ('TAL', 'russia-hemp'),
  ('TAL', 'russia-leather'),
  ('TAL', 'sailcloth'),
  ('TAL', 'shot-and-ball'),
  ('TAN', 'honey'),
  ('TAN', 'morocco-leather'),
  ('TAN', 'quran-manuscripts'),
  ('TAN', 'saffian-leather'),
  ('TER', 'coconut-arrack'),
  ('TER', 'cubeb'),
  ('TER', 'fish-sauce'),
  ('TER', 'paradise-plumes'),
  ('TER', 'sharks-fin'),
  ('THA', 'elephants'),
  ('THA', 'lac'),
  ('THA', 'martaban-jars'),
  ('THA', 'rubies'),
  ('THE', 'mastic'),
  ('THE', 'mohair'),
  ('THE', 'ouzo'),
  ('THE', 'retsina'),
  ('THE', 'saffron-dye'),
  ('THE', 'storax'),
  ('TID', 'galangal'),
  ('TID', 'gamboge'),
  ('TID', 'gutta-percha'),
  ('TID', 'tortoiseshell'),
  ('TOK', 'katsuobushi'),
  ('TOK', 'kyoto-fans'),
  ('TOK', 'matchlocks'),
  ('TOK', 'mirin'),
  ('TOK', 'miso'),
  ('TOK', 'moxa'),
  ('TOK', 'nishijin-brocade'),
  ('TOK', 'pickled-plums'),
  ('TOK', 'soy-sauce'),
  ('TOK', 'sword-blades'),
  ('TON', 'lacquerware'),
  ('TON', 'pollock'),
  ('TON', 'ramie-korea'),
  ('TON', 'soju'),
  ('TOR', 'eiderdown'),
  ('TOR', 'sealskins'),
  ('TOR', 'swedish-iron'),
  ('TOR', 'tannin-bark'),
  ('TOU', 'capers'),
  ('TOU', 'chianti'),
  ('TOU', 'falconet'),
  ('TOU', 'fustian'),
  ('TRA', 'alum-shale'),
  ('TRA', 'carpets'),
  ('TRA', 'hazelnuts'),
  ('TRA', 'turkish-leaf'),
  ('TRI', 'gallnuts'),
  ('TRI', 'pistachios'),
  ('TRI', 'silk-raw'),
  ('TRI', 'soap'),
  ('TRP', 'camels'),
  ('TRP', 'henna'),
  ('TRP', 'ostrich-feathers'),
  ('TRP', 'sumac'),
  ('TRO', 'angelica-root'),
  ('TRO', 'aquavit'),
  ('TRO', 'falcons'),
  ('TRO', 'whale-bone-stays'),
  ('TSU', 'ramie-cloth'),
  ('TSU', 'silk-cloth'),
  ('TSU', 'sutra-scrolls'),
  ('TSU', 'ukiyo-e'),
  ('TUN', 'coral'),
  ('TUN', 'couscous'),
  ('TUN', 'dried-fruit'),
  ('TUN', 'harissa'),
  ('TUN', 'henna'),
  ('TUN', 'olive-oil'),
  ('TUN', 'wool-cloth'),
  ('TUR', 'amber-work'),
  ('TUR', 'smalt'),
  ('TUR', 'sturgeon'),
  ('TUR', 'vodka'),
  ('ULS', 'doenjang'),
  ('ULS', 'dried-squid'),
  ('ULS', 'iron'),
  ('ULS', 'war-bows'),
  ('VAL', 'azulejos'),
  ('VAL', 'bacalhau'),
  ('VAL', 'cinnabar'),
  ('VAL', 'coriander'),
  ('VAL', 'cork'),
  ('VAL', 'majolica'),
  ('VAL', 'saffron'),
  ('VLL', 'gold-thread'),
  ('VLL', 'grappa'),
  ('VLL', 'italian-canvases'),
  ('VLL', 'kermes'),
  ('VLL', 'majolica'),
  ('VLP', 'copper'),
  ('VLP', 'hides'),
  ('VLP', 'pulque'),
  ('VLP', 'talavera'),
  ('VAR', 'baleen'),
  ('VAR', 'gyrfalcons'),
  ('VAR', 'halibut'),
  ('VAR', 'mead'),
  ('VEN', 'books'),
  ('VEN', 'crossbows'),
  ('VEN', 'glass-beads'),
  ('VEN', 'glassware'),
  ('VEN', 'gunpowder'),
  ('VEN', 'lace'),
  ('VEN', 'soap'),
  ('VEN', 'sponges'),
  ('VEN', 'theriac'),
  ('VEN', 'velvet'),
  ('VER', 'chillies'),
  ('VER', 'cochineal'),
  ('VER', 'indigo'),
  ('VER', 'jalap'),
  ('VER', 'logwood'),
  ('VER', 'rum'),
  ('VER', 'sarsaparilla'),
  ('VER', 'tolu-balsam'),
  ('VER', 'tortoiseshell-combs'),
  ('VER', 'vanilla'),
  ('VIS', 'baltic-amber'),
  ('VIS', 'bar-iron'),
  ('VIS', 'barley'),
  ('VIS', 'brassware'),
  ('WLG', 'harakeke'),
  ('WLG', 'pounamu'),
  ('WLG', 'kumara'),
  ('WLG', 'sperm-oil'),
  ('WIL', 'chillies'),
  ('WIL', 'ginger'),
  ('WIL', 'logwood'),
  ('WIL', 'vanilla'),
  ('XIA', 'canton-enamel'),
  ('XIA', 'china-root'),
  ('XIA', 'cloisonne'),
  ('XIA', 'copper-cash'),
  ('XIA', 'dragon-bone'),
  ('XIA', 'fire-lance'),
  ('XIA', 'lychees'),
  ('YEO', 'ginseng-korea'),
  ('YEO', 'gochujang'),
  ('YEO', 'goryeo-celadon'),
  ('YEO', 'hemp-cloth'),
  ('YEO', 'seaweed'),
  ('ZAK', 'glass-beads'),
  ('ZAK', 'glassware'),
  ('ZAK', 'lace'),
  ('ZAK', 'marble'),
  ('ZAN', 'ambergris'),
  ('ZAN', 'coconuts'),
  ('ZAN', 'copal'),
  ('ZAN', 'cotton-cloth'),
  ('ZAN', 'gold'),
  ('ZAN', 'ivory'),
  ('ZAN', 'rhino-horn');

do $$
declare
  pre         record;
  v_n         int;
  v_m         int;
  v_extra     int;
  v_list      text;
  v_harbours  int;
  v_goods     int;
  v_reachable int;
  v_ports_all int;
  v_probe_extra int;
begin
  select * into pre from pre_0217;

  ---------------------------------------------------------------------------------------------
  -- (a) DELTAS against the world this migration found. Both legal baselines (production after
  --     the original 0003, and a fresh rebuild of the reverted chain) present the same world
  --     here, so the deltas are exact.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_harbours from public.ports where kind = 'HARBOUR';
  select count(*) into v_goods    from public.goods;
  if v_harbours - pre.harbours <> 8 or v_goods - pre.goods <> 10 then
    raise exception '0217 self-assert FAIL: expected +8 harbours and +10 goods over the pre-image; got +% harbours (% now) and +% goods (% now)',
      v_harbours - pre.harbours, v_harbours, v_goods - pre.goods, v_goods;
  end if;
  select count(*) into v_n from public.port_specialties;
  if v_n - pre.offers <> 32 then
    raise exception '0217 self-assert FAIL: offers moved by % (expected +32-0 = 32)', v_n - pre.offers;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (b) EVERY HARBOUR EQUALS ITS DATA ROW — identity AND every derived column, both directions.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_n from want_ports_0217 wp
   where not exists (select 1 from public.ports p where p.code = wp.code and p.kind = 'HARBOUR');
  select count(*) into v_extra from public.ports p
   where p.kind = 'HARBOUR' and not exists (select 1 from want_ports_0217 wp where wp.code = p.code);
  if v_n <> 0 or v_extra <> 0 then
    select string_agg(x.code, ', ') into v_list from (
      select wp.code from want_ports_0217 wp
       where not exists (select 1 from public.ports p where p.code = wp.code and p.kind = 'HARBOUR')
      union all
      select p.code from public.ports p
       where p.kind = 'HARBOUR' and not exists (select 1 from want_ports_0217 wp where wp.code = p.code)
    ) x;
    raise exception '0217 self-assert FAIL: the harbour set does not equal the data (% missing, % extra): %', v_n, v_extra, v_list;
  end if;
  select count(*) into v_n
    from want_ports_0217 wp
    join public.ports p on p.code = wp.code
    join public.seas s on s.id = p.sea_id
    join public.regions r on r.id = p.region_id
    left join public.nations n on n.id = p.nation_id
   where (p.name, p.country, coalesce(n.code, ''), p.lat, p.lon, s.code, r.code, p.culture,
          p.size_tier, p.max_draft, p.yard_tier, p.has_academy, p.dev_industry, p.dev_commerce,
          p.dev_military)
         is distinct from
         (wp.name, wp.country, coalesce(wp.nation_code, ''), wp.lat, wp.lon, wp.sea_code,
          wp.region_code, wp.culture, wp.size_tier, wp.max_draft, wp.yard_tier, wp.academy,
          wp.dev_i, wp.dev_c, wp.dev_m);
  if v_n <> 0 then
    select string_agg(wp.code, ', ') into v_list
      from want_ports_0217 wp
      join public.ports p on p.code = wp.code
      join public.seas s on s.id = p.sea_id
      join public.regions r on r.id = p.region_id
      left join public.nations n on n.id = p.nation_id
     where (p.name, p.country, coalesce(n.code, ''), p.lat, p.lon, s.code, r.code, p.culture,
            p.size_tier, p.max_draft, p.yard_tier, p.has_academy, p.dev_industry, p.dev_commerce,
            p.dev_military)
           is distinct from
           (wp.name, wp.country, coalesce(wp.nation_code, ''), wp.lat, wp.lon, wp.sea_code,
            wp.region_code, wp.culture, wp.size_tier, wp.max_draft, wp.yard_tier, wp.academy,
            wp.dev_i, wp.dev_c, wp.dev_m);
    raise exception '0217 self-assert FAIL: % harbour row(s) disagree with the data column-for-column: %', v_n, v_list;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (c) EVERY GOOD EQUALS ITS DATA ROW, both directions, every column.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_n from want_goods_0217 wg
   where not exists (select 1 from public.goods g where g.code = wg.code);
  select count(*) into v_extra from public.goods g
   where not exists (select 1 from want_goods_0217 wg where wg.code = g.code);
  if v_n <> 0 or v_extra <> 0 then
    raise exception '0217 self-assert FAIL: the goods set does not equal the data (% missing, % extra)', v_n, v_extra;
  end if;
  select count(*) into v_n
    from want_goods_0217 wg
    join public.goods g on g.code = wg.code
   where (g.name, g.base_value, g.bulk, g.perishable_pct_day, g.category, g.culture_mask, g.origin_regions, g.entrepot_ports, g.industry)
         is distinct from (wg.name, wg.base_value, wg.bulk, wg.perish, wg.category, wg.mask, wg.origin, wg.entrepot, wg.industry);
  if v_n <> 0 then
    select string_agg(wg.code, ', ') into v_list from want_goods_0217 wg
      join public.goods g on g.code = wg.code
     where (g.name, g.base_value, g.bulk, g.perishable_pct_day, g.category, g.culture_mask, g.origin_regions, g.entrepot_ports, g.industry)
           is distinct from (wg.name, wg.base_value, wg.bulk, wg.perish, wg.category, wg.mask, wg.origin, wg.entrepot, wg.industry);
    raise exception '0217 self-assert FAIL: % good row(s) disagree with the data column-for-column (geography included): %', v_n, v_list;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (d) EVERY PORT'S OFFERS EQUAL ITS goods ARRAY, AS A SET — with a POSITIVE CONTROL first:
  --     a deliberately planted bogus offer must be SEEN by the very query that certifies zero,
  --     then is removed. A certifying query that cannot see a planted wrong row certifies nothing.
  ---------------------------------------------------------------------------------------------
  insert into public.port_specialties (port_id, good_id)
  select p.id, g.id from public.ports p, public.goods g
   where p.code = 'LIS' and g.code = 'cloves';
  select count(*) into v_probe_extra from public.port_specialties ps
    join public.ports p on p.id = ps.port_id
    join public.goods g on g.id = ps.good_id
   where not exists (select 1 from want_offers_0217 wo
                      where wo.port_code = p.code and wo.good_code = g.code);
  if v_probe_extra <> 1 then
    raise exception '0217 self-assert FAIL (positive control): planted 1 bogus offer (LIS, cloves) and the extra-offers query found % — the certifying query is blind', v_probe_extra;
  end if;
  delete from public.port_specialties ps
   using public.ports p, public.goods g
   where ps.port_id = p.id and ps.good_id = g.id and p.code = 'LIS' and g.code = 'cloves';

  select count(*) into v_n from want_offers_0217 wo
   where not exists (select 1 from public.port_specialties ps
                       join public.ports p on p.id = ps.port_id
                       join public.goods g on g.id = ps.good_id
                      where p.code = wo.port_code and g.code = wo.good_code);
  select count(*) into v_extra from public.port_specialties ps
    join public.ports p on p.id = ps.port_id
    join public.goods g on g.id = ps.good_id
   where not exists (select 1 from want_offers_0217 wo
                      where wo.port_code = p.code and wo.good_code = g.code);
  if v_n <> 0 or v_extra <> 0 then
    select string_agg(x.pair, ', ') into v_list from (
      select wo.port_code || '·' || wo.good_code as pair from want_offers_0217 wo
       where not exists (select 1 from public.port_specialties ps
                           join public.ports p on p.id = ps.port_id
                           join public.goods g on g.id = ps.good_id
                          where p.code = wo.port_code and g.code = wo.good_code)
      union all
      select p.code || '·' || g.code from public.port_specialties ps
        join public.ports p on p.id = ps.port_id
        join public.goods g on g.id = ps.good_id
       where not exists (select 1 from want_offers_0217 wo
                          where wo.port_code = p.code and wo.good_code = g.code)
      limit 20
    ) x;
    raise exception '0217 self-assert FAIL: the offer set does not equal the rosters (% missing, % extra): %', v_n, v_extra, v_list;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (e) RETIRED with 0049: the leg graph is gone. The water's own integrity (every place
  --     reaches every other, sailed >= great circle, symmetric table) is asserted by the
  --     0046-family migration that generates it, at its own position in the chain.
  ---------------------------------------------------------------------------------------------

  ---------------------------------------------------------------------------------------------
  -- (f) THE DERIVATION RULES HOLD ON EVERY ROW — the rule, not the seed, so rows this migration
  --     never touched are held to the same law. dev_* restate the roster; the offer band is the
  --     owner's 4-9 rule keyed to size (tier-1 up to 9, tier-2 up to 7, tier-3 exactly 4-5).
  ---------------------------------------------------------------------------------------------
  select count(*) into v_n
    from public.ports p
    join lateral (select count(*) as c from public.port_specialties s where s.port_id = p.id) sc on true
    join lateral (select count(*) as c from public.port_specialties s
                    join public.goods g on g.id = s.good_id
                   where s.port_id = p.id and g.industry) ic on true
   where p.kind = 'HARBOUR'
     and (p.dev_commerce <> greatest(0, least(20, round(p.size_tier * 2.4 + sc.c)))
       or p.dev_industry <> greatest(0, least(20, round(p.size_tier * 2.0 + ic.c * 1.5)))
       or p.dev_military <> greatest(0, least(20, round(p.size_tier * 1.8 + case when p.yard_tier > 0 then 2 else 0 end))));
  if v_n <> 0 then
    raise exception '0217 self-assert FAIL: % harbour(s) have dev_* columns that do not restate their roster and size', v_n;
  end if;
  select count(*) into v_n
    from public.ports p
    join lateral (select count(*) as c from public.port_specialties s where s.port_id = p.id) sc on true
   where p.kind = 'HARBOUR'
     and ((p.size_tier = 5 and sc.c <> 10)
       or (p.size_tier = 3 and sc.c not between 4 and 8)
       or (p.size_tier = 2 and sc.c <> 4));
  if v_n <> 0 then
    select string_agg(p.code, ', ') into v_list from public.ports p
      join lateral (select count(*) as c from public.port_specialties s where s.port_id = p.id) sc on true
     where p.kind = 'HARBOUR'
       and ((p.size_tier = 5 and sc.c <> 10)
         or (p.size_tier = 3 and sc.c not between 4 and 8) or (p.size_tier = 2 and sc.c <> 4));
    raise exception '0217 self-assert FAIL: % harbour(s) break the roster count law (capital 10, mid 4-8, small 4): %', v_n, v_list;
  end if;
  --     0062's law: every offer is NATIVE (the port's region is among the good's origin_regions) or
  --     a NAMED ENTREPOT (the port's code is in the good's entrepot_ports). No third case.
  select count(*) into v_n
    from public.port_specialties s
    join public.ports p on p.id = s.port_id
    join public.regions r on r.id = p.region_id
    join public.goods g on g.id = s.good_id
   where not (r.code = any(g.origin_regions)) and not (p.code = any(g.entrepot_ports));
  if v_n <> 0 then
    select string_agg(p.code || '·' || g.code, ', ') into v_list
      from public.port_specialties s
      join public.ports p on p.id = s.port_id
      join public.regions r on r.id = p.region_id
      join public.goods g on g.id = s.good_id
     where not (r.code = any(g.origin_regions)) and not (p.code = any(g.entrepot_ports));
    raise exception '0217 self-assert FAIL: % offer(s) are neither native nor a named entrepot (0062): %', v_n, v_list;
  end if;
  --     ... and every good is produced somewhere and buyable at a producer (0062 (d)).
  select count(*) into v_n from public.goods g
   where cardinality(g.origin_regions) = 0
      or not exists (select 1 from public.port_specialties s join public.ports p on p.id = s.port_id
                       join public.regions r on r.id = p.region_id
                      where s.good_id = g.id and r.code = any(g.origin_regions));
  if v_n <> 0 then
    raise exception '0217 self-assert FAIL: % good(s) have no origin or are buyable at no producer (0062)', v_n;
  end if;
  --     0065's law: no good sits in four cities.
  select count(*) into v_n from (
    select good_id from public.port_specialties group by good_id having count(*) > 3) x;
  if v_n <> 0 then
    select string_agg(g.code || '×' || x.c, ', ') into v_list from (
      select good_id, count(*) as c from public.port_specialties group by good_id having count(*) > 3) x
      join public.goods g on g.id = x.good_id;
    raise exception '0217 self-assert FAIL: % good(s) sit in four or more cities (0065): %', v_n, v_list;
  end if;
  --     0089's rule: no harbour lacks a building the rule names (tiers are the game's, so only
  --     the KIND is asserted; 0089 itself proves the tiers on the world it found).
  select count(*) into v_n
    from public.ports p
    cross join lateral public.harbour_buildings(p.id) b
   where p.kind = 'HARBOUR'
     and not exists (select 1 from public.port_buildings pb where pb.port_id = p.id and pb.kind = b.kind);
  if v_n <> 0 then
    raise exception '0217 self-assert FAIL: % (harbour, building) row(s) the one rule names are missing — furnish_harbours did not run or did not reach them', v_n;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (g) THE WATER, AT THIS FILE'S OWN POSITION. sea_reaches (the 0046 family) is cut by
  --     scripts/build-sea-migration.mjs from the APPLIED chain, so a harbour inserted HERE cannot
  --     have a reach row until the sea migration that follows this one. What CAN be asserted here,
  --     and is: every port that existed before this file still carries a reach row over the
  --     pre-image's ports, and the ONLY ports lacking a full row are EXACTLY the harbours this
  --     file inserted — named. A pre-existing port that lost its water, or a stray port from
  --     nowhere, is refused. The finished chain is held to "every port carries a full reach row"
  --     by scripts/db/proofs/08 (REACH_TOTAL_AT_EVERY_PORT), so a growth pushed without its sea
  --     migration is red in db:proof.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_ports_all from public.ports;
  select count(*) into v_reachable from public.sea_reaches sr
   where (select count(*) from jsonb_object_keys(sr.reaches)) = v_ports_all - 1 - 8;
  if v_reachable <> v_ports_all - 8 then
    raise exception '0217 self-assert FAIL: % of the % pre-existing ports carry a reach row over the pre-existing world — the water this file found is not whole', v_reachable, v_ports_all - 8;
  end if;
  select string_agg(p.code, ', ' order by p.code) into v_list
    from public.ports p
   where not exists (select 1 from public.sea_reaches sr where sr.port_id = p.id);
  if coalesce(v_list, '') is distinct from 'AST, AUK, DAR, FRE, MEZ, PTL, PUS, WLG' then
    raise exception '0217 self-assert FAIL: the ports without a reach row are [%], expected exactly the harbours this file inserted [AST, AUK, DAR, FRE, MEZ, PTL, PUS, WLG] — the sea migration that follows must seed them', coalesce(v_list, '');
  end if;

  ---------------------------------------------------------------------------------------------
  -- (h) THE MARKET COVERS THE WORLD AND RESTATES THE FORMULA. One row per (harbour, good);
  --     every affinity equals the one formula recomputed from today's specialties and knobs;
  --     stock_target and production_rate restate 0005's seed arithmetic on every row.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_n from public.port_goods;
  if v_n <> v_harbours * v_goods then
    raise exception '0217 self-assert FAIL: % port_goods rows for % harbours × % goods (expected %)',
      v_n, v_harbours, v_goods, v_harbours * v_goods;
  end if;
  with knob as (
    select public.wc_num('affinity_producer') as producer,
           public.wc_num('affinity_home')     as home,
           public.wc_num('affinity_span')     as span,
           public.wc_num('affinity_reach_nm') as reach_nm,
           public.wc_num('affinity_curve')    as curve
  ),
  source_distance as (
    select p.id as port_id, src.id as src_id,
           voyage.gc_distance_nm(p.lat, p.lon, src.lat, src.lon) as nm
      from public.ports p
      cross join (select distinct port_id from public.port_specialties) s
      join public.ports src on src.id = s.port_id
     where p.kind = 'HARBOUR'
  ),
  nearest as (
    select d.port_id, ps.good_id, min(d.nm) as nm
      from source_distance d
      join public.port_specialties ps on ps.port_id = d.src_id
     group by d.port_id, ps.good_id
  )
  select count(*) into v_n
    from public.port_goods pg
    join public.ports p on p.id = pg.port_id
    left join nearest n on n.port_id = pg.port_id and n.good_id = pg.good_id
    cross join knob k
   where pg.affinity is distinct from world.affinity_at(
           exists (select 1 from public.port_specialties s
                    where s.port_id = pg.port_id and s.good_id = pg.good_id),
           n.nm, k.producer, k.home, k.span, k.reach_nm, k.curve);
  if v_n <> 0 then
    raise exception '0217 self-assert FAIL: % port_goods row(s) hold an affinity the formula does not derive from today''s world', v_n;
  end if;
  select count(*) into v_n
    from public.port_goods pg
    join public.ports p on p.id = pg.port_id
   where pg.stock_target is distinct from (world.market_depth_at(p.size_tier, pg.affinity, public.wc_num('market_depth'))).stock_target
      or pg.production_rate is distinct from
         (world.market_depth_at(p.size_tier, pg.affinity, public.wc_num('market_depth'))).production_rate;
  if v_n <> 0 then
    raise exception '0217 self-assert FAIL: % port_goods row(s) break 0005''s stock_target/production_rate arithmetic', v_n;
  end if;
  --     0066: every market row of a harbour this file inserted carries the demand the one
  --     derivation answers (the default 1.000 would be a city with no appetite among 25 that have).
  select count(*) into v_n
    from public.port_goods pg
    join public.ports p on p.id = pg.port_id
   where p.code in ('AST', 'AUK', 'DAR', 'FRE', 'MEZ', 'PTL', 'PUS', 'WLG')
     and pg.demand is distinct from world.demand_for(pg.port_id, pg.good_id);
  if v_n <> 0 then
    raise exception '0217 self-assert FAIL: % market row(s) at the new harbours carry a demand the one derivation does not answer', v_n;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (i) The knobs hold the tuned values, and the lockdown of 0001/0018/0023 still stands.
  ---------------------------------------------------------------------------------------------
  if (select value from public.world_config where key = 'affinity_curve') <> '0.88'::jsonb
     or (select value from public.world_config where key = 'affinity_home') <> '1.00'::jsonb
     or (select value from public.world_config where key = 'affinity_producer') <> '0.93'::jsonb
     or (select value from public.world_config where key = 'affinity_reach_nm') <> '9500'::jsonb
     or (select value from public.world_config where key = 'affinity_span') <> '0.76'::jsonb then
    raise exception '0217 self-assert FAIL: the affinity knobs do not hold the tuned values (curve=0.88 home=1.00 producer=0.93 reach_nm=9500 span=0.76)';
  end if;
  select count(*) into v_n from public.client_write_grants();
  select count(*) into v_m from public.client_executable_writers();
  select count(*) into v_extra from public.caller_evaluated_functions();
  if v_n <> 0 or v_m <> 0 or v_extra <> 0 then
    raise exception '0217 self-assert FAIL: the growth minted % client write grant(s), % client-executable writer(s), % read-wall gap(s)', v_n, v_m, v_extra;
  end if;

  raise notice '0217 self-assert ok: THE WORLD EQUALS THE DATA — % harbours (+% over the world this file found) and % goods (+%) with every column equal to data/*.json (origin and entrepot columns included); the offer set equals every roster as a set (positive control: a planted bogus offer WAS seen, then removed); dev_* restate every roster, all % harbours satisfy the roster count law (capital 10 / mid 4-8 / small 4), every offer is native or a named entrepot, every good is buyable at a producer, no good sits in four cities, no harbour lacks a building the one rule names; all % pre-existing ports carry a reach row and the 8 inserted harbour(s) await the sea migration that follows; % market rows = harbours × goods (% more than the % this file found), every affinity re-derivable from the one formula, 0005''s stock arithmetic holding on every row, every new row carrying its city''s demand; knobs at curve 0.88, home 1.00, producer 0.93, reach_nm 9500, span 0.76; 0 client write grants, 0 client-executable writers, 0 read-wall gaps',
    v_harbours, v_harbours - pre.harbours, v_goods, v_goods - pre.goods,
    v_harbours, v_ports_all - 8,
    (select count(*) from public.port_goods),
    (select count(*) from public.port_goods) - pre.market_rows, pre.market_rows;
end $$;

drop table pre_0217;
drop table want_ports_0217;
drop table want_goods_0217;
drop table want_offers_0217;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0217 (sea) — THE WATER REACHES THE NEW HARBOURS: 8 roadstead(s) and their sailed distances
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- GENERATED by scripts/build-sea-migration.mjs with ADDS_PLACES_ONLY (see that switch's note) against the
-- applied chain plus the growth above. Do not hand-edit: edit the data or the generator and run it again.
--   * the raster is byte-identical to public.sea_raster (545,972 water cells): NOT rewritten;
--   * 0 existing roadsteads move; voyage.channels, voyage.channel_foot and voyage.water_roadstead are
--     untouched (0091's bodies stand);
--   * 8 new row(s) in public.sea_reaches (AST AUK DAR FRE MEZ PTL PUS WLG), each reaching all 259 other places;
--   * every one of the 252 existing rows gains the 8 new key(s) and keeps every key it had, to the
--     tenth of a mile (asserted against its pre-image below).
--     AST Astoria: roadstead (46.125, -124.125), 12.87 nm off the quay
--     AUK Auckland: roadstead (-36.625, 175.125), 22.16 nm off the quay
--     DAR Darwin: roadstead (-12.375, 130.625), 13.20 nm off the quay
--     FRE Fremantle: roadstead (-32.125, 115.625), 7.79 nm off the quay
--     MEZ Mezen: roadstead (66.375, 43.875), 32.68 nm off the quay
--     PTL Portland: roadstead (43.375, -70.125), 18.09 nm off the quay
--     PUS Pustozersk: roadstead (68.375, 51.625), 55.65 nm off the quay
--     WLG Wellington: roadstead (-41.375, 174.625), 8.65 nm off the quay
--   * 48 merchant course(s) in public.npc_courses: each new harbour to and from its 3 nearest
--     existing harbours by sea, the pathfinder's own course, so public.npc_known_legs can offer them.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
create temporary table reaches_before_0217 on commit drop as
  select code, snap_nm, roadstead_lat, roadstead_lon, reaches from public.sea_reaches;

insert into public.sea_reaches (port_id, code, snap_nm, roadstead_lat, roadstead_lon, reaches)
select p.id, v.code, v.snap_nm::numeric, v.rlat::numeric, v.rlon::numeric, v.reaches::jsonb
  from (values
    ('AST', 12.87, 46.125, -124.125, '{"ACA":2347.5,"ACC":11850.7,"ADE":10696.4,"AGA":12955.1,"ALE":15168.9,"ALG":13788.1,"AMB":6349.1,"AMS":14509.8,"ANC":14984.7,"ANG":13077.4,"ANT":15163.3,"ARI":5061.9,"ARK":16374.2,"ARP":14480.3,"AUK":5950.3,"AYU":7090.8,"BAB":10746.3,"BAN":7614.6,"BAR":13815.1,"BAS":10380.6,"BEI":15328.2,"BEL":11257.7,"BER":14790.3,"BIL":13834.2,"BIS":13801.8,"BND":6326,"BNT":7362.1,"BOR":13990.9,"BOS":13965.6,"BRI":12254.8,"BRS":14128.7,"BRU":14286,"BSR":10891.5,"BUE":8325.4,"BUS":4532.6,"BUV":3873,"CAD":13280.3,"CAG":14039.4,"CAL":12031.6,"CAP":11738.4,"CAR":13234.6,"CEB":5861.1,"CEU":13309.3,"CHE":8626.9,"CHI":8506.9,"CHS":14883.9,"CID":11778.3,"CLL":4493.3,"CLS":14234,"COL":8588.7,"CON":5775.6,"COP":14901.1,"COQ":5502.5,"COR":14613.3,"CPT":10488.7,"CRK":13997.1,"CSV":13219.7,"CUM":12482.1,"DAR":6772.4,"DBR":14752.1,"DIL":6629.7,"DIU":9585.9,"DLD":11173,"DOG":14440,"DRK":7002.2,"DUB":14133.1,"ELM":11738.4,"FAM":15265.8,"FEO":15488.9,"FNC":12825.2,"FRE":8343.1,"FUK":4576.1,"FUZ":5282,"GAL":8523.4,"GBK":13661.9,"GDA":15132.6,"GIB":13305.7,"GOA":14147.7,"GOR":11842.3,"GUA":5738.4,"GYE":4032.3,"HAD":10122.2,"HAG":4869,"HAM":14604.9,"HAN":6115.3,"HAV":13768.3,"HER":14806.2,"HIR":4610.7,"HLT":12628.1,"HNL":2233.9,"HOB":7134.6,"HOI":6114.3,"HON":5663.8,"HOO":8653.9,"HOR":10380.6,"HRN":14388.9,"HUA":2569.6,"INC":4871.6,"ISL":11344.2,"IST":15095.2,"IZM":14890.1,"JAF":8612.1,"JAK":7349.1,"JAM":13809.8,"JED":11341,"JEJ":4705,"KAG":4724.9,"KAL":15172.5,"KAN":9004.3,"KAR":9900.6,"KHA":9604,"KIL":11067,"KIN":14410,"KOC":8872.1,"KOL":8809.7,"KOZ":8951.9,"KUP":6806.7,"LAG":11950.9,"LAR":13945.7,"LEH":14132.3,"LEI":14581.2,"LIS":13297,"LIV":14175.1,"LNG":15611.4,"LON":14283.4,"LPA":12608.3,"LUA":11546,"LUB":14981.2,"MAC":5696.3,"MAK":6795.9,"MAL":7144,"MAN":10670.6,"MAS":11041.9,"MAT":3905,"MCH":8630.5,"MES":14308.6,"MEZ":16122.7,"MID":14307.4,"MLE":8921.8,"MLG":13383.9,"MLN":11030.5,"MNG":9072.4,"MNL":5876.9,"MOC":10772.9,"MOG":10599.2,"MOK":4725.4,"MOM":11093.6,"MRS":13997,"MTY":602.5,"MUM":9466.2,"MUS":10149.1,"MYE":7844.9,"MZT":1850.7,"NAG":4657.5,"NAH":4975.3,"NAM":4977.1,"NAN":13963,"NAP":14273.9,"NAV":2019.4,"NEW":13893.1,"NIN":5016.5,"NUU":14671.7,"OLD":9246.4,"OPO":13434.9,"ORA":13536.7,"OSA":4444,"OUI":11908.7,"PAI":4026.2,"PAL":14221.7,"PAN":3748.9,"PAR":11831.7,"PAT":14611.6,"PLM":13763.5,"PLO":10445.1,"PLY":14000.5,"PON":12988.7,"POR":13345.3,"PRT":13498.8,"PTH":14115.7,"PTL":13991.7,"PTT":6870.3,"PUL":8638.7,"PUS":16168.3,"QUA":5354.4,"QUE":14498.4,"REA":3113,"REC":10196.4,"REY":14588.2,"RHO":14945.6,"RIG":15349.4,"RIO":9157.4,"ROT":14329.4,"RRF":10376.5,"SAF":13010,"SAI":11952.3,"SAK":4444,"SAL":13171.2,"SAN":12758.8,"SAO":11780.5,"SDG":949.6,"SET":13286.4,"SFR":542.2,"SGO":12964,"SGS":12885.1,"SHI":4537.3,"SKC":11036.7,"SLV":9829.8,"SNL":13299.6,"SNT":14041.3,"SOF":11783.8,"SOG":13295,"SOH":10363.3,"SOM":7245.2,"SOS":9048.2,"SOY":11645,"SPL":14825.6,"SRT":9587.1,"STA":13835.8,"STG":13238.8,"STJ":13827.3,"STO":15252.2,"SUA":11273.5,"SUE":11940.3,"SUR":7065.8,"SVQ":13340,"SYD":6685.6,"TAI":5416,"TAL":15389,"TAN":13285.7,"TEN":12611.5,"TER":6149.4,"THA":8117.5,"THE":14964,"TID":6164.4,"TOK":4135.2,"TON":4586.7,"TOR":14584.4,"TOU":14013.5,"TRA":15650.4,"TRI":15341,"TRO":15033.8,"TRP":14406.6,"TSU":4575.8,"TUN":14090.1,"TUR":15360.5,"ULS":4502.2,"VAL":13690.3,"VAR":15702.4,"VEN":15011.2,"VER":14514.1,"VIS":15158.1,"VLL":14307.5,"VLP":5646.3,"WIL":12780.7,"WLG":6244.5,"XIA":5395,"YEO":4615.4,"ZAK":14597,"ZAN":11051.5}'),
    ('AUK', 22.16, -36.625, 175.125, '{"ACA":5760.9,"ACC":9303.8,"ADE":8035.9,"AGA":10464.1,"ALE":12676.6,"ALG":11296,"AMB":3339.9,"AMS":12011.1,"ANC":12492.4,"ANG":10579.7,"ANT":12671,"ARI":5850,"ARK":13873.2,"ARP":11981.6,"AST":5950.3,"AYU":5488.8,"BAB":8128.8,"BAN":5439.7,"BAR":11391.6,"BAS":7990.5,"BEI":12904.7,"BEL":8836.5,"BER":12365.9,"BIL":11409.1,"BIS":11380.7,"BND":3220.3,"BNT":4610.3,"BOR":11573.5,"BOS":11452.1,"BRI":9833.6,"BRS":11701.8,"BRU":11861.9,"BSR":8501,"BUE":5892.8,"BUS":5070.2,"BUV":6383.8,"CAD":10858.8,"CAG":11615.9,"CAL":9120,"CAP":9261.2,"CAR":10813.4,"CEB":4128.1,"CEU":10885.8,"CHE":6452,"CHI":6332.3,"CHS":12460.4,"CID":9359.8,"CLL":5795.3,"CLS":11809.9,"COL":6239,"CON":5019.6,"COP":12476.9,"COQ":5344.6,"COR":12189.8,"CPT":6641.7,"CRK":11571.8,"CSV":10796.9,"CUM":10060.9,"DAR":3105.7,"DBR":12328.6,"DIL":3390.9,"DIU":7210.6,"DLD":8754.5,"DOG":12015.9,"DRK":4459.5,"DUB":11707.4,"ELM":9261.2,"FAM":12842.3,"FEO":13065.4,"FNC":10401.8,"FRE":3171.4,"FUK":5009.6,"FUZ":4930.9,"GAL":6177.5,"GBK":11240.7,"GDA":12708.5,"GIB":10882.2,"GOA":11724.2,"GOR":9424,"GUA":5116.7,"GYE":6047.6,"HAD":7549.4,"HAG":3552.9,"HAM":12180.7,"HAN":5252.1,"HAV":11347.1,"HER":12382.7,"HIR":4965.1,"HLT":10206.9,"HNL":3790.2,"HOB":1475.7,"HOI":5002.5,"HON":5042.1,"HOO":6479.3,"HOR":7990.5,"HRN":11964.7,"HUA":5900.1,"INC":5266.3,"ISL":7084,"IST":12671.8,"IZM":12466.6,"JAF":6413.8,"JAK":4565.5,"JAM":11388.6,"JED":8723.4,"JEJ":5039.9,"KAG":4852.7,"KAL":12748.4,"KAN":6629.1,"KAR":7524.9,"KHA":7228.6,"KIL":7368.8,"KIN":11985.9,"KOC":6497.8,"KOL":6434.5,"KOZ":6577,"KUP":3491.7,"LAG":9318.2,"LAR":11528.3,"LEH":11708.2,"LEI":12157.1,"LIS":10873.5,"LIV":11751.6,"LNG":13184.6,"LON":11859.3,"LPA":10184.5,"LUA":8298.1,"LUB":12557.1,"MAC":5074.6,"MAK":3841.5,"MAL":4965.8,"MAN":8280.2,"MAS":8424.3,"MAT":5138.8,"MCH":6455.6,"MES":11885.2,"MEZ":13698.3,"MID":11883.3,"MLE":6337.7,"MLG":10960.5,"MLN":7511.5,"MNG":6697,"MNL":4480.2,"MOC":8155.4,"MOG":7505.8,"MOK":5122.1,"MOM":7493,"MRS":11573.6,"MTY":5613.6,"MUM":7090.8,"MUS":7755.6,"MYE":5670.3,"MZT":5692.9,"NAG":4916.9,"NAH":4640.3,"NAM":5371.8,"NAN":11545.1,"NAP":11850.4,"NAV":5623.2,"NEW":11471.9,"NIN":5018.4,"NUU":12250.5,"OLD":6871.1,"OPO":11009.9,"ORA":11113.2,"OSA":4835,"OUI":9342.2,"PAI":5870.5,"PAL":11798.2,"PAN":6480.5,"PAR":9410.5,"PAT":12188.1,"PLM":11340.1,"PLO":6080.3,"PLY":11574.6,"PON":10566.5,"POR":10924.1,"PRT":11077.6,"PTH":11691.5,"PTL":11576.3,"PTT":5229.1,"PUL":6463.9,"PUS":13743.9,"QUA":4884.6,"QUE":12077.2,"REA":6202.6,"REC":7773.6,"REY":12166.6,"RHO":12522.2,"RIG":12925.3,"RIO":6734.1,"ROT":11905.3,"RRF":6152.7,"SAF":10588.8,"SAI":9532.2,"SAK":4835,"SAL":10747.7,"SAN":10337.6,"SAO":8909.8,"SDG":5620.4,"SET":10863.3,"SFR":5652.9,"SGO":10542.8,"SGS":10463.9,"SHI":5042,"SKC":7684.3,"SLV":7412.3,"SNL":10877.9,"SNT":11617.2,"SOF":6949.3,"SOG":10871.5,"SOH":7973.2,"SOM":5070.3,"SOS":6620.2,"SOY":8437.6,"SPL":12402.2,"SRT":7211.7,"STA":11414.6,"STG":10817.6,"STJ":11406.1,"STO":12828.1,"SUA":8655.9,"SUE":9322.7,"SUR":4195.8,"SVQ":10918.4,"SYD":1251.7,"TAI":4766.1,"TAL":12964.9,"TAN":10862.2,"TEN":10188,"TER":3559.7,"THA":5942.9,"THE":12540.5,"TID":3545,"TOK":4785,"TON":5062,"TOR":12160.7,"TOU":11590,"TRA":13227,"TRI":12917.6,"TRO":12609.4,"TRP":11983.1,"TSU":5014.7,"TUN":11666.6,"TUR":12936.4,"ULS":5100.6,"VAL":11266.8,"VAR":13278,"VEN":12587.8,"VER":12092.9,"VIS":12734,"VLL":11884,"VLP":5204.7,"WIL":10359.5,"WLG":547.2,"XIA":4875.3,"YEO":5063.2,"ZAK":12173.5,"ZAN":7455.1}'),
    ('DAR', 13.20, -12.375, 130.625, '{"ACA":7963,"ACC":8686.3,"ADE":5596.7,"AGA":10774.4,"ALE":12988.4,"ALG":11610.5,"AMB":540.7,"AMS":12302.8,"ANC":12804.2,"ANG":11239.7,"ANT":12982.8,"ARI":8910.2,"ARK":14193.5,"ARP":12273.3,"AST":6772.4,"AUK":3105.7,"AYU":2629.7,"BAB":5446,"BAN":2471.8,"BAR":11700.6,"BAS":5263.7,"BEI":13207,"BEL":10340.4,"BER":12717.6,"BIL":11805.9,"BIS":11749.7,"BND":474.2,"BNT":1557.3,"BOR":11929,"BOS":12809.3,"BRI":11283.1,"BRS":12113.7,"BRU":12217.5,"BSR":5778.2,"BUE":8649.2,"BUS":2865.2,"BUV":9129.9,"CAD":11155.2,"CAG":11921.6,"CAL":8566.6,"CAP":8681.8,"CAR":12343.3,"CEB":1529.5,"CEU":11197.1,"CHE":3505.1,"CHI":3343.1,"CHS":12777.1,"CID":9869.7,"CLL":8795,"CLS":12164.4,"COL":3458.5,"CON":8064.7,"COP":12821.2,"COQ":8401.9,"COR":12505.4,"CPT":6081.7,"CRK":11929.3,"CSV":11089.4,"CUM":11482.3,"DBR":12663.6,"DIL":424.4,"DIU":4375.7,"DLD":9311.8,"DOG":12423.5,"DRK":7267.4,"DUB":12138.1,"ELM":8805.1,"FAM":13177.3,"FEO":13400.4,"FNC":10769.6,"FRE":1793.5,"FUK":2795.1,"FUZ":2463.9,"GAL":3303.8,"GBK":12142.8,"GDA":13116.1,"GIB":11217.2,"GOA":12059.2,"GOR":9687.2,"GUA":2386.5,"GYE":8976.3,"HAD":4833.8,"HAG":1904.1,"HAM":12588.4,"HAN":2496.7,"HAV":12865.9,"HER":12717.7,"HIR":2750.5,"HLT":11162.8,"HNL":4965,"HOB":2981.1,"HOI":2247.1,"HON":2311.9,"HOO":3468.6,"HOR":5170.3,"HRN":12372.4,"HUA":8236.8,"INC":2997.4,"ISL":5281.8,"IST":13006.7,"IZM":12801.6,"JAF":3441.8,"JAK":1487.2,"JAM":12877.3,"JED":6149.5,"JEJ":2769.4,"KAG":2644.7,"KAL":13156,"KAN":3794.1,"KAR":4690.3,"KHA":4393.7,"KIL":5352.6,"KIN":12393.6,"KOC":3661.8,"KOL":3599.4,"KOZ":3741.6,"KUP":429.1,"LAG":8778.4,"LAR":11937,"LEH":12116.1,"LEI":12564.8,"LIS":11255.5,"LIV":12086.6,"LNG":13585.9,"LON":12267,"LPA":10531.6,"LUA":7741.4,"LUB":12964.8,"MAC":2333.9,"MAK":876.4,"MAL":1958.6,"MAN":5460.3,"MAS":5850.4,"MAT":3453.8,"MCH":3445.2,"MES":12220.1,"MEZ":14155.8,"MID":12291,"MLE":3619.6,"MLG":11295.5,"MLN":5378.1,"MNG":3862.1,"MNL":1761.3,"MOC":5581.4,"MOG":5134.8,"MOK":2853.1,"MOM":5394.5,"MRS":11908.5,"MTY":6891.3,"MUM":4255.9,"MUS":4938.7,"MYE":2659.6,"MZT":7655.1,"NAG":2705.2,"NAH":2327.1,"NAM":3096.7,"NAN":11957.5,"NAP":12185.4,"NAV":7734.5,"NEW":12844.8,"NIN":2678.5,"NUU":12969.6,"OLD":4036.1,"OPO":11403.5,"ORA":11448.2,"OSA":2821.4,"OUI":8806.3,"PAI":8803.4,"PAL":12133.2,"PAN":9323,"PAR":10919.4,"PAT":12523.1,"PLM":11675,"PLO":4210.1,"PLY":11987.7,"PON":11139.6,"POR":12442.1,"PRT":12590.6,"PTH":12099.2,"PTL":12770.4,"PTT":2203.2,"PUL":3471.5,"PUS":14205.9,"QUA":2417.6,"QUE":13040.5,"REA":8750.5,"REC":9294.2,"REY":12685.9,"RHO":12857.1,"RIG":13332.9,"RIO":8733.6,"ROT":12312.9,"RRF":5613.2,"SAF":10921.2,"SAI":9781.5,"SAK":2821.4,"SAL":11077.6,"SAN":11855.2,"SAO":8360.3,"SDG":7089.4,"SET":11236.4,"SFR":6888.8,"SGO":12060.6,"SGS":11895.9,"SHI":2827.5,"SKC":7129.3,"SLV":9165.7,"SNL":11220.6,"SNT":12025.5,"SOF":5512.6,"SOG":11206.5,"SOH":5153,"SOM":2061.9,"SOS":8739.7,"SOY":7880.9,"SPL":12737.1,"SRT":4376.8,"STA":12928.9,"STG":12253.6,"STJ":12290.5,"STO":13235.7,"SUA":6082,"SUE":6748.7,"SUR":1117.5,"SVQ":11261,"SYD":2372.8,"TAI":2299.1,"TAL":13372.5,"TAN":11197.2,"TEN":10533.2,"TER":828.3,"THA":2932.2,"THE":12875.5,"TID":813.3,"TOK":2926.9,"TON":2841.1,"TOR":12605.2,"TOU":11925,"TRA":13561.9,"TRI":13252.5,"TRO":13041.3,"TRP":12318.1,"TSU":2800.2,"TUN":12001.6,"TUR":13344,"ULS":2888,"VAL":11601.8,"VAR":13736.8,"VEN":12922.7,"VER":13610.9,"VIS":13141.7,"VLL":12219,"VLP":8263.4,"WIL":11872.8,"WLG":3236.3,"XIA":2408.6,"YEO":2829.5,"ZAK":12508.5,"ZAN":5407.5}'),
    ('FRE', 7.79, -32.125, 115.625, '{"ACA":8896.4,"ACC":7278.7,"ADE":4906.1,"AGA":9380.1,"ALE":11594.1,"ALG":10216.2,"AMB":2040.7,"AMS":10908.5,"ANC":11409.9,"ANG":9832.1,"ANT":11588.5,"ARI":7854.1,"ARK":12799.2,"ARP":10879,"AST":8343.1,"AUK":3171.4,"AYU":3018.4,"BAB":5013.8,"BAN":2554.4,"BAR":10306.3,"BAS":4901.9,"BEI":11812.8,"BEL":8859.1,"BER":11323.4,"BIL":10411.7,"BIS":10355.4,"BND":2070.3,"BNT":1748.7,"BOR":10534.7,"BOS":11401.7,"BRI":9766.2,"BRS":10719.5,"BRU":10823.2,"BSR":5412.6,"BUE":6907.5,"BUS":4257.7,"BUV":9005,"CAD":9761,"CAG":10527.3,"CAL":7159,"CAP":7274.2,"CAR":10861.2,"CEB":2723.1,"CEU":9802.8,"CHE":3376.6,"CHI":3644.6,"CHS":11382.8,"CID":8475.4,"CLL":8103.9,"CLS":10770.1,"COL":3119,"CON":6764,"COP":11426.9,"COQ":7175.7,"COR":11111.2,"CPT":4687.4,"CRK":10535.1,"CSV":9695.1,"CUM":9960.4,"DAR":1793.5,"DBR":11248.4,"DIL":1741.9,"DIU":4110.5,"DLD":7918.2,"DOG":10976.5,"DRK":5460.8,"DUB":10664.2,"ELM":7274.2,"FAM":11767.2,"FEO":11967.4,"FNC":9346.9,"FUK":4187.1,"FUZ":3532.3,"GAL":3056.4,"GBK":10757.6,"GDA":11730.9,"GIB":9831.9,"GOA":10674,"GOR":8301.9,"GUA":3462.5,"GYE":8612.1,"HAD":4439.4,"HAG":3457.2,"HAM":11203.1,"HAN":3351.8,"HAV":11433.5,"HER":11332.4,"HIR":4142.7,"HLT":9777.6,"HNL":6575.1,"HOB":1825.8,"HOI":3067.1,"HON":3390,"HOO":3675,"HOR":4902,"HRN":10987.1,"HUA":8992,"INC":4305.1,"ISL":4404.3,"IST":11621.5,"IZM":11416.4,"JAF":3296.3,"JAK":1763.3,"JAM":11443.3,"JED":5612.2,"JEJ":4080.3,"KAG":4080.3,"KAL":11770.8,"KAN":3528.9,"KAR":4425.1,"KHA":4128.5,"KIL":4420.2,"KIN":11008.3,"KOC":3396.6,"KOL":3334.2,"KOZ":3476.4,"KUP":1539.1,"LAG":7393.2,"LAR":10551.7,"LEH":10730.9,"LEI":11179.5,"LIS":9870.3,"LIV":10701.3,"LNG":12200.6,"LON":10881.7,"LPA":9146.4,"LUA":6356.1,"LUB":11579.5,"MAC":3401.5,"MAK":1736.2,"MAL":2275.8,"MAN":5191.8,"MAS":5313.1,"MAT":4845.9,"MCH":3503.1,"MES":10834.9,"MEZ":12770.6,"MID":10905.7,"MLE":3242.2,"MLG":9910.2,"MLN":4554.7,"MNG":3596.9,"MNL":2869.2,"MOC":5044.1,"MOG":4455.6,"MOK":4177.5,"MOM":4548,"MRS":10523.3,"MTY":8609.4,"MUM":3990.7,"MUS":4667.6,"MYE":2980.2,"MZT":8804.2,"NAG":4112.7,"NAH":3755.2,"NAM":4369.9,"NAN":10572.2,"NAP":10800.2,"NAV":8781.5,"NEW":11484,"NIN":3856.6,"NUU":11584.4,"OLD":3770.9,"OPO":10018.2,"ORA":10063,"OSA":4303.8,"OUI":7421.1,"PAI":8410.7,"PAL":10747.9,"PAN":9306.9,"PAR":9485.4,"PAT":11137.9,"PLM":10289.8,"PLO":3176.7,"PLY":10602.5,"PON":9754.3,"POR":11009.7,"PRT":11157.8,"PTH":10714,"PTL":11385.2,"PTT":2601.6,"PUL":3413.1,"PUS":12820.6,"QUA":3474.1,"QUE":11655.2,"REA":9157.6,"REC":7855.3,"REY":11300.6,"RHO":11471.9,"RIG":11947.7,"RIO":7312,"ROT":10927.7,"RRF":4216.3,"SAF":9535.9,"SAI":8396.3,"SAK":4303.8,"SAL":9692.3,"SAN":10422.8,"SAO":6975,"SDG":8690,"SET":9851.2,"SFR":8630.4,"SGO":10628.3,"SGS":10472.7,"SHI":4220.3,"SKC":5744.1,"SLV":7726.5,"SNL":9835.3,"SNT":10640.2,"SOF":4341.7,"SOG":9821.2,"SOH":4884.7,"SOM":2380.3,"SOS":7327.3,"SOY":6495.7,"SPL":11351.9,"SRT":4111.6,"STA":11495.8,"STG":10829,"STJ":10905.2,"STO":11850.5,"SUA":5544.7,"SUE":6211.4,"SUR":1660.4,"SVQ":9875.7,"SYD":2151.7,"TAI":3367.6,"TAL":11987.3,"TAN":9812,"TEN":9148,"TER":2241.7,"THA":3231.3,"THE":11490.3,"TID":2227.3,"TOK":4453.9,"TON":4194.4,"TOR":11220,"TOU":10539.7,"TRA":12176.7,"TRI":11867.3,"TRO":11656.1,"TRP":10932.8,"TSU":4182.1,"TUN":10616.3,"TUR":11958.8,"ULS":4266,"VAL":10216.5,"VAR":12351.6,"VEN":11537.5,"VER":12178.5,"VIS":11756.4,"VLL":10833.7,"VLP":7034,"WIL":10439.9,"WLG":3005.8,"XIA":3446.9,"YEO":4170,"ZAK":11123.2,"ZAN":4517.4}'),
    ('MEZ', 32.68, 66.375, 43.875, '{"ACA":13983.3,"ACC":5832.6,"ADE":12175.3,"AGA":3473,"ALE":5071.1,"ALG":3697.4,"AMB":14361.4,"AMS":1933.6,"ANC":4886.9,"ANG":3141,"ANT":5065.5,"ARI":11714.2,"ARK":187.4,"ARP":2049.3,"AST":16122.7,"AUK":13698.3,"AYU":14577.7,"BAB":12282.9,"BAN":13097.9,"BAR":3787.5,"BAS":12799.6,"BEI":5289.7,"BEL":5807.8,"BER":1483.1,"BIL":2660.6,"BIS":2534.3,"BND":14412.8,"BNT":13205.6,"BOR":2645.1,"BOS":3943.6,"BRI":5139.1,"BRS":2275,"BRU":2026,"BSR":13309.3,"BUE":8132,"BUS":16107.6,"BUV":13130.4,"CAD":3226.4,"CAG":4008.7,"CAL":6328.8,"CAP":5762.8,"CAR":5597.5,"CEB":14876.9,"CEU":3284.8,"CHE":12842.8,"CHI":13569.6,"CHS":4859.8,"CID":4486.1,"CLL":12071.3,"CLS":2045.7,"COL":12512.3,"CON":10618.7,"COP":1919.5,"COQ":11024.8,"COR":4588.1,"CPT":8045.2,"CRK":2208,"CSV":3081.8,"CUM":5349.8,"DAR":14155.8,"DBR":4725.4,"DIL":14072.7,"DIU":12707,"DLD":5112.9,"DOG":1828.5,"DRK":9255.7,"DUB":2055.2,"ELM":5762.8,"FAM":5244.2,"FEO":5444.4,"FNC":3369.2,"FRE":12770.6,"FUK":16066.1,"FUZ":15354.7,"GAL":12492.7,"GBK":3190.6,"GDA":2144.7,"GIB":3280.1,"GOA":4120.3,"GOR":4469.1,"GUA":15104.4,"GYE":12717,"HAD":11784.6,"HAG":15791.5,"HAM":1944.9,"HAN":14937.3,"HAV":4977,"HER":4777.1,"HIR":16021.6,"HLT":3800.5,"HNL":15725.4,"HOB":13519.4,"HOI":14672.4,"HON":15048.7,"HOO":13495.8,"HOR":12799.6,"HRN":1918.4,"HUA":13871.5,"INC":16157.7,"ISL":9937.8,"IST":5070.3,"IZM":4864.5,"JAF":12559.2,"JAK":13253.1,"JAM":4089.3,"JED":12877.7,"JEJ":15989.4,"KAG":15971.1,"KAL":2187.3,"KAN":12478.6,"KAR":12764.2,"KHA":12784.9,"KIL":10341.7,"KIN":1841.3,"KOC":12446.5,"KOL":12421.4,"KOZ":12471.4,"KUP":13901.9,"LAG":6042.5,"LAR":2565.4,"LEH":2161.3,"LEI":1780.9,"LIS":2976.5,"LIV":4147.3,"LNG":832.6,"LON":2073.4,"LPA":3625,"LUA":6814.6,"LUB":2003,"MAC":15043.1,"MAK":13978.3,"MAL":13573.1,"MAN":13090.2,"MAS":12573,"MAT":16724.9,"MCH":13044.9,"MES":4298.8,"MID":1979,"MLE":12041.3,"MLG":3300.9,"MLN":10612.5,"MNG":12399.8,"MNL":14736.3,"MOC":12144,"MOG":10972.9,"MOK":15876.6,"MOM":10555.4,"MRS":3915.4,"MTY":15663.2,"MUM":12593.4,"MUS":12489.2,"MYE":13473.3,"MZT":14719.3,"NAG":15869.4,"NAH":15504.7,"NAM":16069,"NAN":2477.9,"NAP":4192.1,"NAV":14459.7,"NEW":4103,"NIN":15555.7,"NUU":2632.4,"OLD":12475.1,"OPO":2772.3,"ORA":3455.6,"OSA":16124.2,"OUI":5931.4,"PAI":12630.6,"PAL":4140.1,"PAN":13524.3,"PAR":5533.5,"PAT":4530.2,"PLM":3681.9,"PLO":10357.4,"PLY":2236.9,"PON":3122,"POR":5162.2,"PRT":5675.4,"PTH":2119.1,"PTL":3888.8,"PTT":14075.7,"PUL":12772,"PUS":313.8,"QUA":15152.2,"QUE":3938.3,"REA":13762.5,"REC":5984.9,"REY":1806.9,"RHO":4864.3,"RIG":2324.3,"RIO":7116.8,"ROT":1938.1,"RRF":8506.8,"SAF":3280.8,"SAI":4338.8,"SAK":16124.2,"SAL":3221.9,"SAN":4914.1,"SAO":6218,"SDG":15374.1,"SET":2967.4,"SFR":15740.4,"SGO":5062,"SGS":4275.3,"SHI":15984.5,"SKC":7087,"SLV":6375.2,"SNL":3168.8,"SNT":2223.1,"SOF":9490.6,"SOG":3212.8,"SOH":12709,"SOM":13471,"SOS":7321,"SOY":6711.4,"SPL":4744.3,"SRT":12696.9,"STA":4770.7,"STG":4102.6,"STJ":3053.6,"STO":2227.1,"SUA":12644.6,"SUE":13311.3,"SUR":13606.6,"SVQ":3206.3,"SYD":13979.6,"TAI":15091.8,"TAL":2363.9,"TAN":3206.8,"TEN":3580.9,"TER":14449.9,"THA":13564.4,"THE":4882.6,"TID":14437.1,"TOK":16366.7,"TON":15941.8,"TOR":1552.5,"TOU":3931.9,"TRA":5569,"TRI":5259.6,"TRO":1148.6,"TRP":4325.2,"TSU":15936.6,"TUN":4008.7,"TUR":2335.4,"ULS":16019.7,"VAL":3608.7,"VAR":392.2,"VEN":4929.8,"VER":5750.7,"VIS":2133,"VLL":4226.1,"VLP":10911.5,"WIL":5334.8,"WLG":13499.6,"XIA":15111.6,"YEO":15914.1,"ZAK":4515.6,"ZAN":10445.2}'),
    ('PTL', 18.09, 43.375, -70.125, '{"ACA":11852.4,"ACC":4521.7,"ADE":10789.9,"AGA":2931.1,"ALE":4741,"ALG":3371,"AMB":12976,"AMS":3068.7,"ANC":4556.8,"ANG":1942.4,"ANT":4735.4,"ARI":9583.3,"ARK":3993.2,"ARP":3038.6,"AST":13991.7,"AUK":11576.3,"AYU":13192.3,"BAB":10897.5,"BAN":11712.5,"BAR":3461.2,"BAS":11414.2,"BEI":4959.7,"BEL":2939,"BER":2924.5,"BIL":2865.7,"BIS":2741.4,"BND":13027.4,"BNT":11820.3,"BOR":2916,"BOS":63.9,"BRI":1897.1,"BRS":2723,"BRU":2983.4,"BSR":11923.9,"BUE":5975.9,"BUS":14722.2,"BUV":10999.4,"CAD":2895.7,"CAG":3681.3,"CAL":5018,"CAP":4451.9,"CAR":1999.8,"CEB":13491.5,"CEU":2955.4,"CHE":11457.4,"CHI":12184.2,"CHS":4529.7,"CID":2923.6,"CLL":9940.4,"CLS":2929.5,"COL":11126.9,"CON":8487.7,"COP":3264.3,"COQ":8893.9,"COR":4258.1,"CPT":6696,"CRK":2506.7,"CSV":2754.7,"CUM":1978,"DAR":12770.4,"DBR":4395.3,"DIL":12687.3,"DIU":11321.6,"DLD":3474.2,"DOG":3055.9,"DRK":7138.9,"DUB":2659.3,"ELM":4451.9,"FAM":4914.1,"FEO":5114.3,"FNC":2552.7,"FRE":11385.2,"FUK":14680.7,"FUZ":13969.3,"GAL":11107.3,"GBK":832,"GDA":3489.6,"GIB":2952.7,"GOA":3794,"GOR":3183.2,"GUA":13719,"GYE":10586,"HAD":10399.2,"HAG":14406.1,"HAM":3280.8,"HAN":13551.9,"HAV":1384.7,"HER":4447,"HIR":14636.2,"HLT":1626.7,"HNL":13594.5,"HOB":11973.8,"HOI":13287,"HON":13663.3,"HOO":12108.7,"HOR":11414.2,"HRN":3085.5,"HUA":11740.6,"INC":14772.3,"ISL":8552.4,"IST":4740.3,"IZM":4534.5,"JAF":11173.8,"JAK":11867.7,"JAM":507.8,"JED":11492.3,"JEJ":14604,"KAG":14585.7,"KAL":3532.1,"KAN":11093.2,"KAR":11378.9,"KHA":11399.5,"KIL":8956.3,"KIN":3069.2,"KOC":11061.1,"KOL":11036,"KOZ":11086,"KUP":12516.5,"LAG":4731.7,"LAR":2850.4,"LEH":2830.7,"LEI":2924.6,"LIS":2695.9,"LIV":3820.9,"LNG":3160.3,"LON":2980.1,"LPA":2763.8,"LUA":5507.7,"LUB":3347.9,"MAC":13657.7,"MAK":12592.9,"MAL":12186,"MAN":11703.1,"MAS":11187.6,"MAT":15339.5,"MCH":11659.5,"MES":3972.5,"MEZ":3888.8,"MID":2999.5,"MLE":10675.1,"MLG":3029.4,"MLN":9290.9,"MNG":11112.4,"MNL":13433.9,"MOC":10925.3,"MOG":9634.3,"MOK":14629.9,"MOM":9225.8,"MRS":3643.4,"MTY":13410.9,"MUM":11305.7,"MUS":11177.3,"MYE":12112,"MZT":12352.9,"NAG":14609.2,"NAH":14306.9,"NAM":14834,"NAN":2834.4,"NAP":3920.3,"NAV":12078.4,"NEW":311.1,"NIN":14296.3,"NUU":1812.1,"OLD":11182.8,"OPO":2652.6,"ORA":3186.9,"OSA":14928.9,"OUI":4662.2,"PAI":10376.1,"PAL":3865,"PAN":11224.1,"PAR":2372.9,"PAT":4256.4,"PLM":3405,"PLO":8988.5,"PLY":2690.3,"PON":2031.4,"POR":1637.3,"PRT":2130.2,"PTH":2801.4,"PTT":12790,"PUL":11481.8,"PUS":3962.1,"QUA":13866.6,"QUE":1109.1,"REA":11416.8,"REC":3673.7,"REY":2238.3,"RHO":4591.1,"RIG":3670.9,"RIO":4785.3,"ROT":3024.2,"RRF":7186.6,"SAF":2880.7,"SAI":3163.7,"SAK":14838.6,"SAL":2931.1,"SAN":1505.9,"SAO":4947,"SDG":13028.4,"SET":2730.4,"SFR":13394.7,"SGO":1615.6,"SGS":1045,"SHI":14698.9,"SKC":5821.2,"SLV":4058.6,"SNL":2896.8,"SNT":2788.8,"SOF":8198.6,"SOG":2941,"SOH":11416.8,"SOM":12185.2,"SOS":4989.4,"SOY":5392.3,"SPL":4471.1,"SRT":11404.7,"STA":1005.2,"STG":708.4,"STJ":837.4,"STO":3573.7,"SUA":11352.4,"SUE":12019.2,"SUR":12320.9,"SVQ":2934.6,"SYD":12038.9,"TAI":13806.2,"TAL":3710.5,"TAN":2937.9,"TEN":2716.5,"TER":13160.2,"THA":12278.6,"THE":4609.4,"TID":13147.4,"TOK":15081,"TON":14656.2,"TOR":2579,"TOU":3658.9,"TRA":5295.9,"TRI":4986.5,"TRO":3029.8,"TRP":4052,"TSU":14650.9,"TUN":3735.5,"TUR":3682,"ULS":14734.1,"VAL":3335.7,"VAR":3498.7,"VEN":4656.7,"VER":2174.7,"VIS":3479.6,"VLL":3952.9,"VLP":8565.7,"WIL":1889,"WLG":11156.2,"XIA":13826,"YEO":14628.5,"ZAK":4242.4,"ZAN":9153.1}'),
    ('PUS', 55.65, 68.375, 51.625, '{"ACA":14028.9,"ACC":5882.6,"ADE":12225.3,"AGA":3523.1,"ALE":5121.2,"ALG":3747.5,"AMB":14411.4,"AMS":1980,"ANC":4937.1,"ANG":3185.3,"ANT":5115.7,"ARI":11759.8,"ARK":424.3,"ARP":2095.7,"AST":16168.3,"AUK":13743.9,"AYU":14627.8,"BAB":12332.9,"BAN":13147.9,"BAR":3837.7,"BAS":12849.7,"BEI":5339.9,"BEL":5855.3,"BER":1529.4,"BIL":2705,"BIS":2578.7,"BND":14462.9,"BNT":13255.7,"BOR":2689.5,"BOS":3993.2,"BRI":5183.9,"BRS":2319.5,"BRU":2072.3,"BSR":13359.3,"BUE":8177.6,"BUS":16157.6,"BUV":13175.9,"CAD":3276.5,"CAG":4058.9,"CAL":6378.9,"CAP":5812.8,"CAR":5644.4,"CEB":14926.9,"CEU":3335,"CHE":12892.8,"CHI":13619.7,"CHS":4909.9,"CID":4536.1,"CLL":12116.9,"CLS":2092,"COL":12562.3,"CON":10664.3,"COP":1965.8,"COQ":11070.4,"COR":4638.3,"CPT":8095.2,"CRK":2252.4,"CSV":3131.9,"CUM":5394.7,"DAR":14205.9,"DBR":4775.5,"DIL":14122.7,"DIU":12757,"DLD":5162.9,"DOG":1874.9,"DRK":9301.3,"DUB":2099.6,"ELM":5812.8,"FAM":5294.4,"FEO":5494.5,"FNC":3419.2,"FRE":12820.6,"FUK":16116.1,"FUZ":15404.7,"GAL":12542.7,"GBK":3240.1,"GDA":2191.1,"GIB":3330.3,"GOA":4170.5,"GOR":4519.2,"GUA":15154.5,"GYE":12762.6,"HAD":11834.7,"HAG":15841.5,"HAM":1991.2,"HAN":14987.3,"HAV":5026.3,"HER":4827.3,"HIR":16071.7,"HLT":3845.5,"HNL":15771,"HOB":13569.4,"HOI":14722.4,"HON":15098.8,"HOO":13545.9,"HOR":12849.7,"HRN":1964.8,"HUA":13917.1,"INC":16207.8,"ISL":9987.9,"IST":5120.5,"IZM":4914.7,"JAF":12609.2,"JAK":13303.1,"JAM":4138.8,"JED":12927.8,"JEJ":16039.4,"KAG":16021.1,"KAL":2233.6,"KAN":12528.7,"KAR":12814.3,"KHA":12834.9,"KIL":10391.8,"KIN":1897.3,"KOC":12496.5,"KOL":12471.4,"KOZ":12521.4,"KUP":13952,"LAG":6092.6,"LAR":2609.9,"LEH":2207.6,"LEI":1827.7,"LIS":3026.7,"LIV":4197.4,"LNG":828.7,"LON":2119.8,"LPA":3675,"LUA":6864.6,"LUB":2049.4,"MAC":15093.2,"MAK":14028.4,"MAL":13623.2,"MAN":13140.2,"MAS":12623,"MAT":16774.9,"MCH":13094.9,"MES":4349,"MEZ":313.8,"MID":2065.7,"MLE":12110.5,"MLG":3409.6,"MLN":10726.4,"MNG":12547.8,"MNL":14869.3,"MOC":12360.7,"MOG":11069.7,"MOK":16065.3,"MOM":10661.3,"MRS":4019.9,"MTY":15587.5,"MUM":12741.1,"MUS":12612.7,"MYE":13549.2,"MZT":14529.4,"NAG":16044.6,"NAH":15742.3,"NAM":16269.4,"NAN":2571.1,"NAP":4296.7,"NAV":14254.9,"NEW":4176.8,"NIN":15731.7,"NUU":2704,"OLD":12618.2,"OPO":2878.5,"ORA":3562.4,"OSA":16364.4,"OUI":6023.1,"PAI":12552.6,"PAL":4240.4,"PAN":13400.6,"PAR":5509,"PAT":4636.6,"PLM":3781.4,"PLO":10423.9,"PLY":2321,"PON":3176,"POR":5261.6,"PRT":5768.2,"PTH":2203.4,"PTL":3962.1,"PTT":14255.5,"PUL":12943.1,"QUA":15149,"QUE":3969,"REA":13769.5,"REC":5991.9,"REY":1798,"RHO":4856.8,"RIG":2323.5,"RIO":7123.8,"ROT":1937.4,"RRF":8503.6,"SAF":3273.3,"SAI":4337.7,"SAK":16121,"SAL":3214.4,"SAN":4941.3,"SAO":6214.8,"SDG":15381.1,"SET":2959.9,"SFR":15747.5,"SGO":5095,"SGS":4297.7,"SHI":15981.2,"SKC":7083.7,"SLV":6382.2,"SNL":3161.4,"SNT":2222.9,"SOF":9487.3,"SOG":3205.4,"SOH":12705.7,"SOM":13467.7,"SOS":7328,"SOY":6708.2,"SPL":4736.8,"SRT":12693.6,"STA":4801.4,"STG":4139.3,"STJ":3085.9,"STO":2226.3,"SUA":12641.3,"SUE":13308.1,"SUR":13603.4,"SVQ":3198.9,"SYD":13976.4,"TAI":15088.5,"TAL":2363.1,"TAN":3199.3,"TEN":3576.7,"TER":14446.7,"THA":13561.1,"THE":4875.2,"TID":14433.9,"TOK":16363.4,"TON":15938.6,"TOR":1535.9,"TOU":3924.4,"TRA":5561.6,"TRI":5252.2,"TRO":1158,"TRP":4317.7,"TSU":15933.3,"TUN":4001.2,"TUR":2334.6,"ULS":16016.4,"VAL":3601.2,"VAR":447.7,"VEN":4922.4,"VER":5931.4,"VIS":2132.2,"VLL":4218.6,"VLP":10918.5,"WIL":5363.9,"WLG":13506.6,"XIA":15108.4,"YEO":15910.9,"ZAK":4508.1,"ZAN":10441.9}'),
    ('WLG', 8.65, -41.375, 174.625, '{"ACA":5886.3,"ACC":8735.1,"ADE":7778.6,"AGA":10200.7,"ALE":12413.2,"ALG":11032.6,"AMB":3470.1,"AMS":11747.7,"ANC":12229.1,"ANG":10316.4,"ANT":12407.6,"ARI":5716,"ARK":13609.9,"ARP":11718.3,"AST":6244.5,"AUK":547.2,"AYU":5603.4,"BAB":7886.3,"BAN":5653.2,"BAR":11122.8,"BAS":7813.8,"BEI":12631.9,"BEL":8503.1,"BER":12218.5,"BIL":11269.6,"BIS":11216.6,"BND":3358.7,"BNT":4736,"BOR":11395.7,"BOS":11272.2,"BRI":9455.5,"BRS":11596,"BRU":11662.5,"BSR":8332.6,"BUE":5601.8,"BUS":5258.4,"BUV":6376.3,"CAD":10571.6,"CAG":11343.7,"CAL":8562.6,"CAP":8730.6,"CAR":10492.2,"CEB":4304.9,"CEU":10619.2,"CHE":6316.2,"CHI":6524.4,"CHS":12201.9,"CID":8969.7,"CLL":5712.2,"CLS":11609.3,"COL":6048.3,"CON":4829.8,"COP":12266.2,"COQ":5173.8,"COR":11930.3,"CPT":6221.4,"CRK":11276.7,"CSV":10492.1,"CUM":9664.3,"DAR":3236.3,"DBR":12067.5,"DIL":3521.4,"DIU":7036.9,"DLD":8420.4,"DOG":11819.3,"DRK":4193.6,"DUB":11416.3,"ELM":8730.6,"FAM":12586.4,"FEO":12786.5,"FNC":10091,"FRE":3005.8,"FUK":5197.8,"FUZ":5117.4,"GAL":5985.9,"GBK":10763.9,"GDA":12491.4,"GIB":10615.5,"GOA":11455.6,"GOR":9111.2,"GUA":5260.2,"GYE":6020.6,"HAD":7324.9,"HAG":3688.6,"HAM":11990.7,"HAN":5373.2,"HAV":11010,"HER":12119.2,"HIR":5153.3,"HLT":9788.4,"HNL":4123,"HOB":1240.6,"HOI":5123.6,"HON":5185.8,"HOO":6670.5,"HOR":7813.8,"HRN":11768.1,"HUA":6008.6,"INC":5452.5,"ISL":6611.9,"IST":12412.5,"IZM":12206.7,"JAF":6221.8,"JAK":4690.7,"JAM":11052,"JED":8481.1,"JEJ":5226.2,"KAG":5039.3,"KAL":12537.5,"KAN":6455.3,"KAR":7384,"KHA":7054.8,"KIL":7006.8,"KIN":11788.8,"KOC":6355.3,"KOL":6260.7,"KOZ":6402.8,"KUP":3622.3,"LAG":8678.8,"LAR":11345.2,"LEH":11515.2,"LEI":11957.9,"LIS":10574.4,"LIV":11482.5,"LNG":12938.2,"LON":11659.2,"LPA":9881.6,"LUA":7743.1,"LUB":12349.7,"MAC":5218.7,"MAK":3999.5,"MAL":5171.3,"MAN":8111.8,"MAS":8176.3,"MAT":5381.7,"MCH":6448.4,"MES":11634.1,"MEZ":13499.6,"MID":11678.5,"MLE":6171,"MLG":10701.6,"MLN":7233.2,"MNG":6522.3,"MNL":4642.1,"MOC":7914,"MOG":7278.3,"MOK":5307.2,"MOM":7203.6,"MRS":11305,"MTY":5878.6,"MUM":6948.3,"MUS":7586.6,"MYE":5863.2,"MZT":5866.4,"NAG":5105.2,"NAH":4824,"NAM":5558,"NAN":11369.4,"NAP":11581.8,"NAV":5775.2,"NEW":11109.7,"NIN":5195.6,"NUU":11844.4,"OLD":6697.6,"OPO":10715.5,"ORA":10854.4,"OSA":5042,"OUI":8699.5,"PAI":5832.4,"PAL":11492.8,"PAN":6572,"PAR":9078.5,"PAT":11928.6,"PLM":11066.5,"PLO":5771,"PLY":11382.9,"PON":10267.7,"POR":10490.3,"PRT":10676.2,"PTH":11499.7,"PTL":11156.2,"PTT":5369.5,"PUL":6353.7,"PUS":13506.6,"QUA":5069.6,"QUE":11799.5,"REA":6267.8,"REC":7446.8,"REY":11868.2,"RHO":12263.7,"RIG":12722.2,"RIO":6426.8,"ROT":11705.1,"RRF":5630.7,"SAF":10298.2,"SAI":9222,"SAK":5042,"SAL":10478.9,"SAN":10004.6,"SAO":8293.6,"SDG":5861.1,"SET":10560.7,"SFR":5921.7,"SGO":10130,"SGS":10088.7,"SHI":5230.2,"SKC":7121.2,"SLV":7124.7,"SNL":10583.5,"SNT":11428.2,"SOF":6506,"SOG":10607.5,"SOH":7796.7,"SOM":5263.3,"SOS":6313.3,"SOY":7865.9,"SPL":12140.6,"SRT":7037.9,"STA":11010,"STG":10446.4,"STJ":10931.5,"STO":12609.4,"SUA":8414.5,"SUE":9085,"SUR":4320.6,"SVQ":10621.6,"SYD":1192.5,"TAI":4951.7,"TAL":12749,"TAN":10588.4,"TEN":9879.9,"TER":3691.5,"THA":6135.8,"THE":12280,"TID":3677.4,"TOK":4971.5,"TON":5250.1,"TOR":11844,"TOU":11321.4,"TRA":12939.2,"TRI":12659.1,"TRO":12427.4,"TRP":11714.5,"TSU":5202.9,"TUN":11416.6,"TUR":12724.4,"ULS":5288.8,"VAL":10997.8,"VAR":13099.8,"VEN":12328.2,"VER":11658.8,"VIS":12522,"VLL":11613.4,"VLP":5023.5,"WIL":10011.2,"XIA":5060.2,"YEO":5250.7,"ZAK":11903.9,"ZAN":7160}')
  ) as v(code, snap_nm, rlat, rlon, reaches)
  join public.ports p on p.code = v.code;

update public.sea_reaches sr
   set reaches = sr.reaches || v.added::jsonb
  from (values
    ('ACA', '{"AST":2347.5,"AUK":5760.9,"DAR":7963,"FRE":8896.4,"MEZ":13983.3,"PTL":11852.4,"PUS":14028.9,"WLG":5886.3}'),
    ('ACC', '{"AST":11850.7,"AUK":9303.8,"DAR":8686.3,"FRE":7278.7,"MEZ":5832.6,"PTL":4521.7,"PUS":5882.6,"WLG":8735.1}'),
    ('ADE', '{"AST":10696.4,"AUK":8035.9,"DAR":5596.7,"FRE":4906.1,"MEZ":12175.3,"PTL":10789.9,"PUS":12225.3,"WLG":7778.6}'),
    ('AGA', '{"AST":12955.1,"AUK":10464.1,"DAR":10774.4,"FRE":9380.1,"MEZ":3473,"PTL":2931.1,"PUS":3523.1,"WLG":10200.7}'),
    ('ALE', '{"AST":15168.9,"AUK":12676.6,"DAR":12988.4,"FRE":11594.1,"MEZ":5071.1,"PTL":4741,"PUS":5121.2,"WLG":12413.2}'),
    ('ALG', '{"AST":13788.1,"AUK":11296,"DAR":11610.5,"FRE":10216.2,"MEZ":3697.4,"PTL":3371,"PUS":3747.5,"WLG":11032.6}'),
    ('AMB', '{"AST":6349.1,"AUK":3339.9,"DAR":540.7,"FRE":2040.7,"MEZ":14361.4,"PTL":12976,"PUS":14411.4,"WLG":3470.1}'),
    ('AMS', '{"AST":14509.8,"AUK":12011.1,"DAR":12302.8,"FRE":10908.5,"MEZ":1933.6,"PTL":3068.7,"PUS":1980,"WLG":11747.7}'),
    ('ANC', '{"AST":14984.7,"AUK":12492.4,"DAR":12804.2,"FRE":11409.9,"MEZ":4886.9,"PTL":4556.8,"PUS":4937.1,"WLG":12229.1}'),
    ('ANG', '{"AST":13077.4,"AUK":10579.7,"DAR":11239.7,"FRE":9832.1,"MEZ":3141,"PTL":1942.4,"PUS":3185.3,"WLG":10316.4}'),
    ('ANT', '{"AST":15163.3,"AUK":12671,"DAR":12982.8,"FRE":11588.5,"MEZ":5065.5,"PTL":4735.4,"PUS":5115.7,"WLG":12407.6}'),
    ('ARI', '{"AST":5061.9,"AUK":5850,"DAR":8910.2,"FRE":7854.1,"MEZ":11714.2,"PTL":9583.3,"PUS":11759.8,"WLG":5716}'),
    ('ARK', '{"AST":16374.2,"AUK":13873.2,"DAR":14193.5,"FRE":12799.2,"MEZ":187.4,"PTL":3993.2,"PUS":424.3,"WLG":13609.9}'),
    ('ARP', '{"AST":14480.3,"AUK":11981.6,"DAR":12273.3,"FRE":10879,"MEZ":2049.3,"PTL":3038.6,"PUS":2095.7,"WLG":11718.3}'),
    ('AYU', '{"AST":7090.8,"AUK":5488.8,"DAR":2629.7,"FRE":3018.4,"MEZ":14577.7,"PTL":13192.3,"PUS":14627.8,"WLG":5603.4}'),
    ('BAB', '{"AST":10746.3,"AUK":8128.8,"DAR":5446,"FRE":5013.8,"MEZ":12282.9,"PTL":10897.5,"PUS":12332.9,"WLG":7886.3}'),
    ('BAN', '{"AST":7614.6,"AUK":5439.7,"DAR":2471.8,"FRE":2554.4,"MEZ":13097.9,"PTL":11712.5,"PUS":13147.9,"WLG":5653.2}'),
    ('BAR', '{"AST":13815.1,"AUK":11391.6,"DAR":11700.6,"FRE":10306.3,"MEZ":3787.5,"PTL":3461.2,"PUS":3837.7,"WLG":11122.8}'),
    ('BAS', '{"AST":10380.6,"AUK":7990.5,"DAR":5263.7,"FRE":4901.9,"MEZ":12799.6,"PTL":11414.2,"PUS":12849.7,"WLG":7813.8}'),
    ('BEI', '{"AST":15328.2,"AUK":12904.7,"DAR":13207,"FRE":11812.8,"MEZ":5289.7,"PTL":4959.7,"PUS":5339.9,"WLG":12631.9}'),
    ('BEL', '{"AST":11257.7,"AUK":8836.5,"DAR":10340.4,"FRE":8859.1,"MEZ":5807.8,"PTL":2939,"PUS":5855.3,"WLG":8503.1}'),
    ('BER', '{"AST":14790.3,"AUK":12365.9,"DAR":12717.6,"FRE":11323.4,"MEZ":1483.1,"PTL":2924.5,"PUS":1529.4,"WLG":12218.5}'),
    ('BIL', '{"AST":13834.2,"AUK":11409.1,"DAR":11805.9,"FRE":10411.7,"MEZ":2660.6,"PTL":2865.7,"PUS":2705,"WLG":11269.6}'),
    ('BIS', '{"AST":13801.8,"AUK":11380.7,"DAR":11749.7,"FRE":10355.4,"MEZ":2534.3,"PTL":2741.4,"PUS":2578.7,"WLG":11216.6}'),
    ('BND', '{"AST":6326,"AUK":3220.3,"DAR":474.2,"FRE":2070.3,"MEZ":14412.8,"PTL":13027.4,"PUS":14462.9,"WLG":3358.7}'),
    ('BNT', '{"AST":7362.1,"AUK":4610.3,"DAR":1557.3,"FRE":1748.7,"MEZ":13205.6,"PTL":11820.3,"PUS":13255.7,"WLG":4736}'),
    ('BOR', '{"AST":13990.9,"AUK":11573.5,"DAR":11929,"FRE":10534.7,"MEZ":2645.1,"PTL":2916,"PUS":2689.5,"WLG":11395.7}'),
    ('BOS', '{"AST":13965.6,"AUK":11452.1,"DAR":12809.3,"FRE":11401.7,"MEZ":3943.6,"PTL":63.9,"PUS":3993.2,"WLG":11272.2}'),
    ('BRI', '{"AST":12254.8,"AUK":9833.6,"DAR":11283.1,"FRE":9766.2,"MEZ":5139.1,"PTL":1897.1,"PUS":5183.9,"WLG":9455.5}'),
    ('BRS', '{"AST":14128.7,"AUK":11701.8,"DAR":12113.7,"FRE":10719.5,"MEZ":2275,"PTL":2723,"PUS":2319.5,"WLG":11596}'),
    ('BRU', '{"AST":14286,"AUK":11861.9,"DAR":12217.5,"FRE":10823.2,"MEZ":2026,"PTL":2983.4,"PUS":2072.3,"WLG":11662.5}'),
    ('BSR', '{"AST":10891.5,"AUK":8501,"DAR":5778.2,"FRE":5412.6,"MEZ":13309.3,"PTL":11923.9,"PUS":13359.3,"WLG":8332.6}'),
    ('BUE', '{"AST":8325.4,"AUK":5892.8,"DAR":8649.2,"FRE":6907.5,"MEZ":8132,"PTL":5975.9,"PUS":8177.6,"WLG":5601.8}'),
    ('BUS', '{"AST":4532.6,"AUK":5070.2,"DAR":2865.2,"FRE":4257.7,"MEZ":16107.6,"PTL":14722.2,"PUS":16157.6,"WLG":5258.4}'),
    ('BUV', '{"AST":3873,"AUK":6383.8,"DAR":9129.9,"FRE":9005,"MEZ":13130.4,"PTL":10999.4,"PUS":13175.9,"WLG":6376.3}'),
    ('CAD', '{"AST":13280.3,"AUK":10858.8,"DAR":11155.2,"FRE":9761,"MEZ":3226.4,"PTL":2895.7,"PUS":3276.5,"WLG":10571.6}'),
    ('CAG', '{"AST":14039.4,"AUK":11615.9,"DAR":11921.6,"FRE":10527.3,"MEZ":4008.7,"PTL":3681.3,"PUS":4058.9,"WLG":11343.7}'),
    ('CAL', '{"AST":12031.6,"AUK":9120,"DAR":8566.6,"FRE":7159,"MEZ":6328.8,"PTL":5018,"PUS":6378.9,"WLG":8562.6}'),
    ('CAP', '{"AST":11738.4,"AUK":9261.2,"DAR":8681.8,"FRE":7274.2,"MEZ":5762.8,"PTL":4451.9,"PUS":5812.8,"WLG":8730.6}'),
    ('CAR', '{"AST":13234.6,"AUK":10813.4,"DAR":12343.3,"FRE":10861.2,"MEZ":5597.5,"PTL":1999.8,"PUS":5644.4,"WLG":10492.2}'),
    ('CEB', '{"AST":5861.1,"AUK":4128.1,"DAR":1529.5,"FRE":2723.1,"MEZ":14876.9,"PTL":13491.5,"PUS":14926.9,"WLG":4304.9}'),
    ('CEU', '{"AST":13309.3,"AUK":10885.8,"DAR":11197.1,"FRE":9802.8,"MEZ":3284.8,"PTL":2955.4,"PUS":3335,"WLG":10619.2}'),
    ('CHE', '{"AST":8626.9,"AUK":6452,"DAR":3505.1,"FRE":3376.6,"MEZ":12842.8,"PTL":11457.4,"PUS":12892.8,"WLG":6316.2}'),
    ('CHI', '{"AST":8506.9,"AUK":6332.3,"DAR":3343.1,"FRE":3644.6,"MEZ":13569.6,"PTL":12184.2,"PUS":13619.7,"WLG":6524.4}'),
    ('CHS', '{"AST":14883.9,"AUK":12460.4,"DAR":12777.1,"FRE":11382.8,"MEZ":4859.8,"PTL":4529.7,"PUS":4909.9,"WLG":12201.9}'),
    ('CID', '{"AST":11778.3,"AUK":9359.8,"DAR":9869.7,"FRE":8475.4,"MEZ":4486.1,"PTL":2923.6,"PUS":4536.1,"WLG":8969.7}'),
    ('CLL', '{"AST":4493.3,"AUK":5795.3,"DAR":8795,"FRE":8103.9,"MEZ":12071.3,"PTL":9940.4,"PUS":12116.9,"WLG":5712.2}'),
    ('CLS', '{"AST":14234,"AUK":11809.9,"DAR":12164.4,"FRE":10770.1,"MEZ":2045.7,"PTL":2929.5,"PUS":2092,"WLG":11609.3}'),
    ('COL', '{"AST":8588.7,"AUK":6239,"DAR":3458.5,"FRE":3119,"MEZ":12512.3,"PTL":11126.9,"PUS":12562.3,"WLG":6048.3}'),
    ('CON', '{"AST":5775.6,"AUK":5019.6,"DAR":8064.7,"FRE":6764,"MEZ":10618.7,"PTL":8487.7,"PUS":10664.3,"WLG":4829.8}'),
    ('COP', '{"AST":14901.1,"AUK":12476.9,"DAR":12821.2,"FRE":11426.9,"MEZ":1919.5,"PTL":3264.3,"PUS":1965.8,"WLG":12266.2}'),
    ('COQ', '{"AST":5502.5,"AUK":5344.6,"DAR":8401.9,"FRE":7175.7,"MEZ":11024.8,"PTL":8893.9,"PUS":11070.4,"WLG":5173.8}'),
    ('COR', '{"AST":14613.3,"AUK":12189.8,"DAR":12505.4,"FRE":11111.2,"MEZ":4588.1,"PTL":4258.1,"PUS":4638.3,"WLG":11930.3}'),
    ('CPT', '{"AST":10488.7,"AUK":6641.7,"DAR":6081.7,"FRE":4687.4,"MEZ":8045.2,"PTL":6696,"PUS":8095.2,"WLG":6221.4}'),
    ('CRK', '{"AST":13997.1,"AUK":11571.8,"DAR":11929.3,"FRE":10535.1,"MEZ":2208,"PTL":2506.7,"PUS":2252.4,"WLG":11276.7}'),
    ('CSV', '{"AST":13219.7,"AUK":10796.9,"DAR":11089.4,"FRE":9695.1,"MEZ":3081.8,"PTL":2754.7,"PUS":3131.9,"WLG":10492.1}'),
    ('CUM', '{"AST":12482.1,"AUK":10060.9,"DAR":11482.3,"FRE":9960.4,"MEZ":5349.8,"PTL":1978,"PUS":5394.7,"WLG":9664.3}'),
    ('DBR', '{"AST":14752.1,"AUK":12328.6,"DAR":12663.6,"FRE":11248.4,"MEZ":4725.4,"PTL":4395.3,"PUS":4775.5,"WLG":12067.5}'),
    ('DIL', '{"AST":6629.7,"AUK":3390.9,"DAR":424.4,"FRE":1741.9,"MEZ":14072.7,"PTL":12687.3,"PUS":14122.7,"WLG":3521.4}'),
    ('DIU', '{"AST":9585.9,"AUK":7210.6,"DAR":4375.7,"FRE":4110.5,"MEZ":12707,"PTL":11321.6,"PUS":12757,"WLG":7036.9}'),
    ('DLD', '{"AST":11173,"AUK":8754.5,"DAR":9311.8,"FRE":7918.2,"MEZ":5112.9,"PTL":3474.2,"PUS":5162.9,"WLG":8420.4}'),
    ('DOG', '{"AST":14440,"AUK":12015.9,"DAR":12423.5,"FRE":10976.5,"MEZ":1828.5,"PTL":3055.9,"PUS":1874.9,"WLG":11819.3}'),
    ('DRK', '{"AST":7002.2,"AUK":4459.5,"DAR":7267.4,"FRE":5460.8,"MEZ":9255.7,"PTL":7138.9,"PUS":9301.3,"WLG":4193.6}'),
    ('DUB', '{"AST":14133.1,"AUK":11707.4,"DAR":12138.1,"FRE":10664.2,"MEZ":2055.2,"PTL":2659.3,"PUS":2099.6,"WLG":11416.3}'),
    ('ELM', '{"AST":11738.4,"AUK":9261.2,"DAR":8805.1,"FRE":7274.2,"MEZ":5762.8,"PTL":4451.9,"PUS":5812.8,"WLG":8730.6}'),
    ('FAM', '{"AST":15265.8,"AUK":12842.3,"DAR":13177.3,"FRE":11767.2,"MEZ":5244.2,"PTL":4914.1,"PUS":5294.4,"WLG":12586.4}'),
    ('FEO', '{"AST":15488.9,"AUK":13065.4,"DAR":13400.4,"FRE":11967.4,"MEZ":5444.4,"PTL":5114.3,"PUS":5494.5,"WLG":12786.5}'),
    ('FNC', '{"AST":12825.2,"AUK":10401.8,"DAR":10769.6,"FRE":9346.9,"MEZ":3369.2,"PTL":2552.7,"PUS":3419.2,"WLG":10091}'),
    ('FUK', '{"AST":4576.1,"AUK":5009.6,"DAR":2795.1,"FRE":4187.1,"MEZ":16066.1,"PTL":14680.7,"PUS":16116.1,"WLG":5197.8}'),
    ('FUZ', '{"AST":5282,"AUK":4930.9,"DAR":2463.9,"FRE":3532.3,"MEZ":15354.7,"PTL":13969.3,"PUS":15404.7,"WLG":5117.4}'),
    ('GAL', '{"AST":8523.4,"AUK":6177.5,"DAR":3303.8,"FRE":3056.4,"MEZ":12492.7,"PTL":11107.3,"PUS":12542.7,"WLG":5985.9}'),
    ('GBK', '{"AST":13661.9,"AUK":11240.7,"DAR":12142.8,"FRE":10757.6,"MEZ":3190.6,"PTL":832,"PUS":3240.1,"WLG":10763.9}'),
    ('GDA', '{"AST":15132.6,"AUK":12708.5,"DAR":13116.1,"FRE":11730.9,"MEZ":2144.7,"PTL":3489.6,"PUS":2191.1,"WLG":12491.4}'),
    ('GIB', '{"AST":13305.7,"AUK":10882.2,"DAR":11217.2,"FRE":9831.9,"MEZ":3280.1,"PTL":2952.7,"PUS":3330.3,"WLG":10615.5}'),
    ('GOA', '{"AST":14147.7,"AUK":11724.2,"DAR":12059.2,"FRE":10674,"MEZ":4120.3,"PTL":3794,"PUS":4170.5,"WLG":11455.6}'),
    ('GOR', '{"AST":11842.3,"AUK":9424,"DAR":9687.2,"FRE":8301.9,"MEZ":4469.1,"PTL":3183.2,"PUS":4519.2,"WLG":9111.2}'),
    ('GUA', '{"AST":5738.4,"AUK":5116.7,"DAR":2386.5,"FRE":3462.5,"MEZ":15104.4,"PTL":13719,"PUS":15154.5,"WLG":5260.2}'),
    ('GYE', '{"AST":4032.3,"AUK":6047.6,"DAR":8976.3,"FRE":8612.1,"MEZ":12717,"PTL":10586,"PUS":12762.6,"WLG":6020.6}'),
    ('HAD', '{"AST":10122.2,"AUK":7549.4,"DAR":4833.8,"FRE":4439.4,"MEZ":11784.6,"PTL":10399.2,"PUS":11834.7,"WLG":7324.9}'),
    ('HAG', '{"AST":4869,"AUK":3552.9,"DAR":1904.1,"FRE":3457.2,"MEZ":15791.5,"PTL":14406.1,"PUS":15841.5,"WLG":3688.6}'),
    ('HAM', '{"AST":14604.9,"AUK":12180.7,"DAR":12588.4,"FRE":11203.1,"MEZ":1944.9,"PTL":3280.8,"PUS":1991.2,"WLG":11990.7}'),
    ('HAN', '{"AST":6115.3,"AUK":5252.1,"DAR":2496.7,"FRE":3351.8,"MEZ":14937.3,"PTL":13551.9,"PUS":14987.3,"WLG":5373.2}'),
    ('HAV', '{"AST":13768.3,"AUK":11347.1,"DAR":12865.9,"FRE":11433.5,"MEZ":4977,"PTL":1384.7,"PUS":5026.3,"WLG":11010}'),
    ('HER', '{"AST":14806.2,"AUK":12382.7,"DAR":12717.7,"FRE":11332.4,"MEZ":4777.1,"PTL":4447,"PUS":4827.3,"WLG":12119.2}'),
    ('HIR', '{"AST":4610.7,"AUK":4965.1,"DAR":2750.5,"FRE":4142.7,"MEZ":16021.6,"PTL":14636.2,"PUS":16071.7,"WLG":5153.3}'),
    ('HLT', '{"AST":12628.1,"AUK":10206.9,"DAR":11162.8,"FRE":9777.6,"MEZ":3800.5,"PTL":1626.7,"PUS":3845.5,"WLG":9788.4}'),
    ('HNL', '{"AST":2233.9,"AUK":3790.2,"DAR":4965,"FRE":6575.1,"MEZ":15725.4,"PTL":13594.5,"PUS":15771,"WLG":4123}'),
    ('HOB', '{"AST":7134.6,"AUK":1475.7,"DAR":2981.1,"FRE":1825.8,"MEZ":13519.4,"PTL":11973.8,"PUS":13569.4,"WLG":1240.6}'),
    ('HOI', '{"AST":6114.3,"AUK":5002.5,"DAR":2247.1,"FRE":3067.1,"MEZ":14672.4,"PTL":13287,"PUS":14722.4,"WLG":5123.6}'),
    ('HON', '{"AST":5663.8,"AUK":5042.1,"DAR":2311.9,"FRE":3390,"MEZ":15048.7,"PTL":13663.3,"PUS":15098.8,"WLG":5185.8}'),
    ('HOO', '{"AST":8653.9,"AUK":6479.3,"DAR":3468.6,"FRE":3675,"MEZ":13495.8,"PTL":12108.7,"PUS":13545.9,"WLG":6670.5}'),
    ('HOR', '{"AST":10380.6,"AUK":7990.5,"DAR":5170.3,"FRE":4902,"MEZ":12799.6,"PTL":11414.2,"PUS":12849.7,"WLG":7813.8}'),
    ('HRN', '{"AST":14388.9,"AUK":11964.7,"DAR":12372.4,"FRE":10987.1,"MEZ":1918.4,"PTL":3085.5,"PUS":1964.8,"WLG":11768.1}'),
    ('HUA', '{"AST":2569.6,"AUK":5900.1,"DAR":8236.8,"FRE":8992,"MEZ":13871.5,"PTL":11740.6,"PUS":13917.1,"WLG":6008.6}'),
    ('INC', '{"AST":4871.6,"AUK":5266.3,"DAR":2997.4,"FRE":4305.1,"MEZ":16157.7,"PTL":14772.3,"PUS":16207.8,"WLG":5452.5}'),
    ('ISL', '{"AST":11344.2,"AUK":7084,"DAR":5281.8,"FRE":4404.3,"MEZ":9937.8,"PTL":8552.4,"PUS":9987.9,"WLG":6611.9}'),
    ('IST', '{"AST":15095.2,"AUK":12671.8,"DAR":13006.7,"FRE":11621.5,"MEZ":5070.3,"PTL":4740.3,"PUS":5120.5,"WLG":12412.5}'),
    ('IZM', '{"AST":14890.1,"AUK":12466.6,"DAR":12801.6,"FRE":11416.4,"MEZ":4864.5,"PTL":4534.5,"PUS":4914.7,"WLG":12206.7}'),
    ('JAF', '{"AST":8612.1,"AUK":6413.8,"DAR":3441.8,"FRE":3296.3,"MEZ":12559.2,"PTL":11173.8,"PUS":12609.2,"WLG":6221.8}'),
    ('JAK', '{"AST":7349.1,"AUK":4565.5,"DAR":1487.2,"FRE":1763.3,"MEZ":13253.1,"PTL":11867.7,"PUS":13303.1,"WLG":4690.7}'),
    ('JAM', '{"AST":13809.8,"AUK":11388.6,"DAR":12877.3,"FRE":11443.3,"MEZ":4089.3,"PTL":507.8,"PUS":4138.8,"WLG":11052}'),
    ('JED', '{"AST":11341,"AUK":8723.4,"DAR":6149.5,"FRE":5612.2,"MEZ":12877.7,"PTL":11492.3,"PUS":12927.8,"WLG":8481.1}'),
    ('JEJ', '{"AST":4705,"AUK":5039.9,"DAR":2769.4,"FRE":4080.3,"MEZ":15989.4,"PTL":14604,"PUS":16039.4,"WLG":5226.2}'),
    ('KAG', '{"AST":4724.9,"AUK":4852.7,"DAR":2644.7,"FRE":4080.3,"MEZ":15971.1,"PTL":14585.7,"PUS":16021.1,"WLG":5039.3}'),
    ('KAL', '{"AST":15172.5,"AUK":12748.4,"DAR":13156,"FRE":11770.8,"MEZ":2187.3,"PTL":3532.1,"PUS":2233.6,"WLG":12537.5}'),
    ('KAN', '{"AST":9004.3,"AUK":6629.1,"DAR":3794.1,"FRE":3528.9,"MEZ":12478.6,"PTL":11093.2,"PUS":12528.7,"WLG":6455.3}'),
    ('KAR', '{"AST":9900.6,"AUK":7524.9,"DAR":4690.3,"FRE":4425.1,"MEZ":12764.2,"PTL":11378.9,"PUS":12814.3,"WLG":7384}'),
    ('KHA', '{"AST":9604,"AUK":7228.6,"DAR":4393.7,"FRE":4128.5,"MEZ":12784.9,"PTL":11399.5,"PUS":12834.9,"WLG":7054.8}'),
    ('KIL', '{"AST":11067,"AUK":7368.8,"DAR":5352.6,"FRE":4420.2,"MEZ":10341.7,"PTL":8956.3,"PUS":10391.8,"WLG":7006.8}'),
    ('KIN', '{"AST":14410,"AUK":11985.9,"DAR":12393.6,"FRE":11008.3,"MEZ":1841.3,"PTL":3069.2,"PUS":1897.3,"WLG":11788.8}'),
    ('KOC', '{"AST":8872.1,"AUK":6497.8,"DAR":3661.8,"FRE":3396.6,"MEZ":12446.5,"PTL":11061.1,"PUS":12496.5,"WLG":6355.3}'),
    ('KOL', '{"AST":8809.7,"AUK":6434.5,"DAR":3599.4,"FRE":3334.2,"MEZ":12421.4,"PTL":11036,"PUS":12471.4,"WLG":6260.7}'),
    ('KOZ', '{"AST":8951.9,"AUK":6577,"DAR":3741.6,"FRE":3476.4,"MEZ":12471.4,"PTL":11086,"PUS":12521.4,"WLG":6402.8}'),
    ('KUP', '{"AST":6806.7,"AUK":3491.7,"DAR":429.1,"FRE":1539.1,"MEZ":13901.9,"PTL":12516.5,"PUS":13952,"WLG":3622.3}'),
    ('LAG', '{"AST":11950.9,"AUK":9318.2,"DAR":8778.4,"FRE":7393.2,"MEZ":6042.5,"PTL":4731.7,"PUS":6092.6,"WLG":8678.8}'),
    ('LAR', '{"AST":13945.7,"AUK":11528.3,"DAR":11937,"FRE":10551.7,"MEZ":2565.4,"PTL":2850.4,"PUS":2609.9,"WLG":11345.2}'),
    ('LEH', '{"AST":14132.3,"AUK":11708.2,"DAR":12116.1,"FRE":10730.9,"MEZ":2161.3,"PTL":2830.7,"PUS":2207.6,"WLG":11515.2}'),
    ('LEI', '{"AST":14581.2,"AUK":12157.1,"DAR":12564.8,"FRE":11179.5,"MEZ":1780.9,"PTL":2924.6,"PUS":1827.7,"WLG":11957.9}'),
    ('LIS', '{"AST":13297,"AUK":10873.5,"DAR":11255.5,"FRE":9870.3,"MEZ":2976.5,"PTL":2695.9,"PUS":3026.7,"WLG":10574.4}'),
    ('LIV', '{"AST":14175.1,"AUK":11751.6,"DAR":12086.6,"FRE":10701.3,"MEZ":4147.3,"PTL":3820.9,"PUS":4197.4,"WLG":11482.5}'),
    ('LNG', '{"AST":15611.4,"AUK":13184.6,"DAR":13585.9,"FRE":12200.6,"MEZ":832.6,"PTL":3160.3,"PUS":828.7,"WLG":12938.2}'),
    ('LON', '{"AST":14283.4,"AUK":11859.3,"DAR":12267,"FRE":10881.7,"MEZ":2073.4,"PTL":2980.1,"PUS":2119.8,"WLG":11659.2}'),
    ('LPA', '{"AST":12608.3,"AUK":10184.5,"DAR":10531.6,"FRE":9146.4,"MEZ":3625,"PTL":2763.8,"PUS":3675,"WLG":9881.6}'),
    ('LUA', '{"AST":11546,"AUK":8298.1,"DAR":7741.4,"FRE":6356.1,"MEZ":6814.6,"PTL":5507.7,"PUS":6864.6,"WLG":7743.1}'),
    ('LUB', '{"AST":14981.2,"AUK":12557.1,"DAR":12964.8,"FRE":11579.5,"MEZ":2003,"PTL":3347.9,"PUS":2049.4,"WLG":12349.7}'),
    ('MAC', '{"AST":5696.3,"AUK":5074.6,"DAR":2333.9,"FRE":3401.5,"MEZ":15043.1,"PTL":13657.7,"PUS":15093.2,"WLG":5218.7}'),
    ('MAK', '{"AST":6795.9,"AUK":3841.5,"DAR":876.4,"FRE":1736.2,"MEZ":13978.3,"PTL":12592.9,"PUS":14028.4,"WLG":3999.5}'),
    ('MAL', '{"AST":7144,"AUK":4965.8,"DAR":1958.6,"FRE":2275.8,"MEZ":13573.1,"PTL":12186,"PUS":13623.2,"WLG":5171.3}'),
    ('MAN', '{"AST":10670.6,"AUK":8280.2,"DAR":5460.3,"FRE":5191.8,"MEZ":13090.2,"PTL":11703.1,"PUS":13140.2,"WLG":8111.8}'),
    ('MAS', '{"AST":11041.9,"AUK":8424.3,"DAR":5850.4,"FRE":5313.1,"MEZ":12573,"PTL":11187.6,"PUS":12623,"WLG":8176.3}'),
    ('MAT', '{"AST":3905,"AUK":5138.8,"DAR":3453.8,"FRE":4845.9,"MEZ":16724.9,"PTL":15339.5,"PUS":16774.9,"WLG":5381.7}'),
    ('MCH', '{"AST":8630.5,"AUK":6455.6,"DAR":3445.2,"FRE":3503.1,"MEZ":13044.9,"PTL":11659.5,"PUS":13094.9,"WLG":6448.4}'),
    ('MES', '{"AST":14308.6,"AUK":11885.2,"DAR":12220.1,"FRE":10834.9,"MEZ":4298.8,"PTL":3972.5,"PUS":4349,"WLG":11634.1}'),
    ('MID', '{"AST":14307.4,"AUK":11883.3,"DAR":12291,"FRE":10905.7,"MEZ":1979,"PTL":2999.5,"PUS":2065.7,"WLG":11678.5}'),
    ('MLE', '{"AST":8921.8,"AUK":6337.7,"DAR":3619.6,"FRE":3242.2,"MEZ":12041.3,"PTL":10675.1,"PUS":12110.5,"WLG":6171}'),
    ('MLG', '{"AST":13383.9,"AUK":10960.5,"DAR":11295.5,"FRE":9910.2,"MEZ":3300.9,"PTL":3029.4,"PUS":3409.6,"WLG":10701.6}'),
    ('MLN', '{"AST":11030.5,"AUK":7511.5,"DAR":5378.1,"FRE":4554.7,"MEZ":10612.5,"PTL":9290.9,"PUS":10726.4,"WLG":7233.2}'),
    ('MNG', '{"AST":9072.4,"AUK":6697,"DAR":3862.1,"FRE":3596.9,"MEZ":12399.8,"PTL":11112.4,"PUS":12547.8,"WLG":6522.3}'),
    ('MNL', '{"AST":5876.9,"AUK":4480.2,"DAR":1761.3,"FRE":2869.2,"MEZ":14736.3,"PTL":13433.9,"PUS":14869.3,"WLG":4642.1}'),
    ('MOC', '{"AST":10772.9,"AUK":8155.4,"DAR":5581.4,"FRE":5044.1,"MEZ":12144,"PTL":10925.3,"PUS":12360.7,"WLG":7914}'),
    ('MOG', '{"AST":10599.2,"AUK":7505.8,"DAR":5134.8,"FRE":4455.6,"MEZ":10972.9,"PTL":9634.3,"PUS":11069.7,"WLG":7278.3}'),
    ('MOK', '{"AST":4725.4,"AUK":5122.1,"DAR":2853.1,"FRE":4177.5,"MEZ":15876.6,"PTL":14629.9,"PUS":16065.3,"WLG":5307.2}'),
    ('MOM', '{"AST":11093.6,"AUK":7493,"DAR":5394.5,"FRE":4548,"MEZ":10555.4,"PTL":9225.8,"PUS":10661.3,"WLG":7203.6}'),
    ('MRS', '{"AST":13997,"AUK":11573.6,"DAR":11908.5,"FRE":10523.3,"MEZ":3915.4,"PTL":3643.4,"PUS":4019.9,"WLG":11305}'),
    ('MTY', '{"AST":602.5,"AUK":5613.6,"DAR":6891.3,"FRE":8609.4,"MEZ":15663.2,"PTL":13410.9,"PUS":15587.5,"WLG":5878.6}'),
    ('MUM', '{"AST":9466.2,"AUK":7090.8,"DAR":4255.9,"FRE":3990.7,"MEZ":12593.4,"PTL":11305.7,"PUS":12741.1,"WLG":6948.3}'),
    ('MUS', '{"AST":10149.1,"AUK":7755.6,"DAR":4938.7,"FRE":4667.6,"MEZ":12489.2,"PTL":11177.3,"PUS":12612.7,"WLG":7586.6}'),
    ('MYE', '{"AST":7844.9,"AUK":5670.3,"DAR":2659.6,"FRE":2980.2,"MEZ":13473.3,"PTL":12112,"PUS":13549.2,"WLG":5863.2}'),
    ('MZT', '{"AST":1850.7,"AUK":5692.9,"DAR":7655.1,"FRE":8804.2,"MEZ":14719.3,"PTL":12352.9,"PUS":14529.4,"WLG":5866.4}'),
    ('NAG', '{"AST":4657.5,"AUK":4916.9,"DAR":2705.2,"FRE":4112.7,"MEZ":15869.4,"PTL":14609.2,"PUS":16044.6,"WLG":5105.2}'),
    ('NAH', '{"AST":4975.3,"AUK":4640.3,"DAR":2327.1,"FRE":3755.2,"MEZ":15504.7,"PTL":14306.9,"PUS":15742.3,"WLG":4824}'),
    ('NAM', '{"AST":4977.1,"AUK":5371.8,"DAR":3096.7,"FRE":4369.9,"MEZ":16069,"PTL":14834,"PUS":16269.4,"WLG":5558}'),
    ('NAN', '{"AST":13963,"AUK":11545.1,"DAR":11957.5,"FRE":10572.2,"MEZ":2477.9,"PTL":2834.4,"PUS":2571.1,"WLG":11369.4}'),
    ('NAP', '{"AST":14273.9,"AUK":11850.4,"DAR":12185.4,"FRE":10800.2,"MEZ":4192.1,"PTL":3920.3,"PUS":4296.7,"WLG":11581.8}'),
    ('NAV', '{"AST":2019.4,"AUK":5623.2,"DAR":7734.5,"FRE":8781.5,"MEZ":14459.7,"PTL":12078.4,"PUS":14254.9,"WLG":5775.2}'),
    ('NEW', '{"AST":13893.1,"AUK":11471.9,"DAR":12844.8,"FRE":11484,"MEZ":4103,"PTL":311.1,"PUS":4176.8,"WLG":11109.7}'),
    ('NIN', '{"AST":5016.5,"AUK":5018.4,"DAR":2678.5,"FRE":3856.6,"MEZ":15555.7,"PTL":14296.3,"PUS":15731.7,"WLG":5195.6}'),
    ('NUU', '{"AST":14671.7,"AUK":12250.5,"DAR":12969.6,"FRE":11584.4,"MEZ":2632.4,"PTL":1812.1,"PUS":2704,"WLG":11844.4}'),
    ('OLD', '{"AST":9246.4,"AUK":6871.1,"DAR":4036.1,"FRE":3770.9,"MEZ":12475.1,"PTL":11182.8,"PUS":12618.2,"WLG":6697.6}'),
    ('OPO', '{"AST":13434.9,"AUK":11009.9,"DAR":11403.5,"FRE":10018.2,"MEZ":2772.3,"PTL":2652.6,"PUS":2878.5,"WLG":10715.5}'),
    ('ORA', '{"AST":13536.7,"AUK":11113.2,"DAR":11448.2,"FRE":10063,"MEZ":3455.6,"PTL":3186.9,"PUS":3562.4,"WLG":10854.4}'),
    ('OSA', '{"AST":4444,"AUK":4835,"DAR":2821.4,"FRE":4303.8,"MEZ":16124.2,"PTL":14928.9,"PUS":16364.4,"WLG":5042}'),
    ('OUI', '{"AST":11908.7,"AUK":9342.2,"DAR":8806.3,"FRE":7421.1,"MEZ":5931.4,"PTL":4662.2,"PUS":6023.1,"WLG":8699.5}'),
    ('PAI', '{"AST":4026.2,"AUK":5870.5,"DAR":8803.4,"FRE":8410.7,"MEZ":12630.6,"PTL":10376.1,"PUS":12552.6,"WLG":5832.4}'),
    ('PAL', '{"AST":14221.7,"AUK":11798.2,"DAR":12133.2,"FRE":10747.9,"MEZ":4140.1,"PTL":3865,"PUS":4240.4,"WLG":11492.8}'),
    ('PAN', '{"AST":3748.9,"AUK":6480.5,"DAR":9323,"FRE":9306.9,"MEZ":13524.3,"PTL":11224.1,"PUS":13400.6,"WLG":6572}'),
    ('PAR', '{"AST":11831.7,"AUK":9410.5,"DAR":10919.4,"FRE":9485.4,"MEZ":5533.5,"PTL":2372.9,"PUS":5509,"WLG":9078.5}'),
    ('PAT', '{"AST":14611.6,"AUK":12188.1,"DAR":12523.1,"FRE":11137.9,"MEZ":4530.2,"PTL":4256.4,"PUS":4636.6,"WLG":11928.6}'),
    ('PLM', '{"AST":13763.5,"AUK":11340.1,"DAR":11675,"FRE":10289.8,"MEZ":3681.9,"PTL":3405,"PUS":3781.4,"WLG":11066.5}'),
    ('PLO', '{"AST":10445.1,"AUK":6080.3,"DAR":4210.1,"FRE":3176.7,"MEZ":10357.4,"PTL":8988.5,"PUS":10423.9,"WLG":5771}'),
    ('PLY', '{"AST":14000.5,"AUK":11574.6,"DAR":11987.7,"FRE":10602.5,"MEZ":2236.9,"PTL":2690.3,"PUS":2321,"WLG":11382.9}'),
    ('PON', '{"AST":12988.7,"AUK":10566.5,"DAR":11139.6,"FRE":9754.3,"MEZ":3122,"PTL":2031.4,"PUS":3176,"WLG":10267.7}'),
    ('POR', '{"AST":13345.3,"AUK":10924.1,"DAR":12442.1,"FRE":11009.7,"MEZ":5162.2,"PTL":1637.3,"PUS":5261.6,"WLG":10490.3}'),
    ('PRT', '{"AST":13498.8,"AUK":11077.6,"DAR":12590.6,"FRE":11157.8,"MEZ":5675.4,"PTL":2130.2,"PUS":5768.2,"WLG":10676.2}'),
    ('PTH', '{"AST":14115.7,"AUK":11691.5,"DAR":12099.2,"FRE":10714,"MEZ":2119.1,"PTL":2801.4,"PUS":2203.4,"WLG":11499.7}'),
    ('PTT', '{"AST":6870.3,"AUK":5229.1,"DAR":2203.2,"FRE":2601.6,"MEZ":14075.7,"PTL":12790,"PUS":14255.5,"WLG":5369.5}'),
    ('PUL', '{"AST":8638.7,"AUK":6463.9,"DAR":3471.5,"FRE":3413.1,"MEZ":12772,"PTL":11481.8,"PUS":12943.1,"WLG":6353.7}'),
    ('QUA', '{"AST":5354.4,"AUK":4884.6,"DAR":2417.6,"FRE":3474.1,"MEZ":15152.2,"PTL":13866.6,"PUS":15149,"WLG":5069.6}'),
    ('QUE', '{"AST":14498.4,"AUK":12077.2,"DAR":13040.5,"FRE":11655.2,"MEZ":3938.3,"PTL":1109.1,"PUS":3969,"WLG":11799.5}'),
    ('REA', '{"AST":3113,"AUK":6202.6,"DAR":8750.5,"FRE":9157.6,"MEZ":13762.5,"PTL":11416.8,"PUS":13769.5,"WLG":6267.8}'),
    ('REC', '{"AST":10196.4,"AUK":7773.6,"DAR":9294.2,"FRE":7855.3,"MEZ":5984.9,"PTL":3673.7,"PUS":5991.9,"WLG":7446.8}'),
    ('REY', '{"AST":14588.2,"AUK":12166.6,"DAR":12685.9,"FRE":11300.6,"MEZ":1806.9,"PTL":2238.3,"PUS":1798,"WLG":11868.2}'),
    ('RHO', '{"AST":14945.6,"AUK":12522.2,"DAR":12857.1,"FRE":11471.9,"MEZ":4864.3,"PTL":4591.1,"PUS":4856.8,"WLG":12263.7}'),
    ('RIG', '{"AST":15349.4,"AUK":12925.3,"DAR":13332.9,"FRE":11947.7,"MEZ":2324.3,"PTL":3670.9,"PUS":2323.5,"WLG":12722.2}'),
    ('RIO', '{"AST":9157.4,"AUK":6734.1,"DAR":8733.6,"FRE":7312,"MEZ":7116.8,"PTL":4785.3,"PUS":7123.8,"WLG":6426.8}'),
    ('ROT', '{"AST":14329.4,"AUK":11905.3,"DAR":12312.9,"FRE":10927.7,"MEZ":1938.1,"PTL":3024.2,"PUS":1937.4,"WLG":11705.1}'),
    ('RRF', '{"AST":10376.5,"AUK":6152.7,"DAR":5613.2,"FRE":4216.3,"MEZ":8506.8,"PTL":7186.6,"PUS":8503.6,"WLG":5630.7}'),
    ('SAF', '{"AST":13010,"AUK":10588.8,"DAR":10921.2,"FRE":9535.9,"MEZ":3280.8,"PTL":2880.7,"PUS":3273.3,"WLG":10298.2}'),
    ('SAI', '{"AST":11952.3,"AUK":9532.2,"DAR":9781.5,"FRE":8396.3,"MEZ":4338.8,"PTL":3163.7,"PUS":4337.7,"WLG":9222}'),
    ('SAK', '{"AST":4444,"AUK":4835,"DAR":2821.4,"FRE":4303.8,"MEZ":16124.2,"PTL":14838.6,"PUS":16121,"WLG":5042}'),
    ('SAL', '{"AST":13171.2,"AUK":10747.7,"DAR":11077.6,"FRE":9692.3,"MEZ":3221.9,"PTL":2931.1,"PUS":3214.4,"WLG":10478.9}'),
    ('SAN', '{"AST":12758.8,"AUK":10337.6,"DAR":11855.2,"FRE":10422.8,"MEZ":4914.1,"PTL":1505.9,"PUS":4941.3,"WLG":10004.6}'),
    ('SAO', '{"AST":11780.5,"AUK":8909.8,"DAR":8360.3,"FRE":6975,"MEZ":6218,"PTL":4947,"PUS":6214.8,"WLG":8293.6}'),
    ('SDG', '{"AST":949.6,"AUK":5620.4,"DAR":7089.4,"FRE":8690,"MEZ":15374.1,"PTL":13028.4,"PUS":15381.1,"WLG":5861.1}'),
    ('SET', '{"AST":13286.4,"AUK":10863.3,"DAR":11236.4,"FRE":9851.2,"MEZ":2967.4,"PTL":2730.4,"PUS":2959.9,"WLG":10560.7}'),
    ('SFR', '{"AST":542.2,"AUK":5652.9,"DAR":6888.8,"FRE":8630.4,"MEZ":15740.4,"PTL":13394.7,"PUS":15747.5,"WLG":5921.7}'),
    ('SGO', '{"AST":12964,"AUK":10542.8,"DAR":12060.6,"FRE":10628.3,"MEZ":5062,"PTL":1615.6,"PUS":5095,"WLG":10130}'),
    ('SGS', '{"AST":12885.1,"AUK":10463.9,"DAR":11895.9,"FRE":10472.7,"MEZ":4275.3,"PTL":1045,"PUS":4297.7,"WLG":10088.7}'),
    ('SHI', '{"AST":4537.3,"AUK":5042,"DAR":2827.5,"FRE":4220.3,"MEZ":15984.5,"PTL":14698.9,"PUS":15981.2,"WLG":5230.2}'),
    ('SKC', '{"AST":11036.7,"AUK":7684.3,"DAR":7129.3,"FRE":5744.1,"MEZ":7087,"PTL":5821.2,"PUS":7083.7,"WLG":7121.2}'),
    ('SLV', '{"AST":9829.8,"AUK":7412.3,"DAR":9165.7,"FRE":7726.5,"MEZ":6375.2,"PTL":4058.6,"PUS":6382.2,"WLG":7124.7}'),
    ('SNL', '{"AST":13299.6,"AUK":10877.9,"DAR":11220.6,"FRE":9835.3,"MEZ":3168.8,"PTL":2896.8,"PUS":3161.4,"WLG":10583.5}'),
    ('SNT', '{"AST":14041.3,"AUK":11617.2,"DAR":12025.5,"FRE":10640.2,"MEZ":2223.1,"PTL":2788.8,"PUS":2222.9,"WLG":11428.2}'),
    ('SOF', '{"AST":11783.8,"AUK":6949.3,"DAR":5512.6,"FRE":4341.7,"MEZ":9490.6,"PTL":8198.6,"PUS":9487.3,"WLG":6506}'),
    ('SOG', '{"AST":13295,"AUK":10871.5,"DAR":11206.5,"FRE":9821.2,"MEZ":3212.8,"PTL":2941,"PUS":3205.4,"WLG":10607.5}'),
    ('SOH', '{"AST":10363.3,"AUK":7973.2,"DAR":5153,"FRE":4884.7,"MEZ":12709,"PTL":11416.8,"PUS":12705.7,"WLG":7796.7}'),
    ('SOM', '{"AST":7245.2,"AUK":5070.3,"DAR":2061.9,"FRE":2380.3,"MEZ":13471,"PTL":12185.2,"PUS":13467.7,"WLG":5263.3}'),
    ('SOS', '{"AST":9048.2,"AUK":6620.2,"DAR":8739.7,"FRE":7327.3,"MEZ":7321,"PTL":4989.4,"PUS":7328,"WLG":6313.3}'),
    ('SOY', '{"AST":11645,"AUK":8437.6,"DAR":7880.9,"FRE":6495.7,"MEZ":6711.4,"PTL":5392.3,"PUS":6708.2,"WLG":7865.9}'),
    ('SPL', '{"AST":14825.6,"AUK":12402.2,"DAR":12737.1,"FRE":11351.9,"MEZ":4744.3,"PTL":4471.1,"PUS":4736.8,"WLG":12140.6}'),
    ('SRT', '{"AST":9587.1,"AUK":7211.7,"DAR":4376.8,"FRE":4111.6,"MEZ":12696.9,"PTL":11404.7,"PUS":12693.6,"WLG":7037.9}'),
    ('STA', '{"AST":13835.8,"AUK":11414.6,"DAR":12928.9,"FRE":11495.8,"MEZ":4770.7,"PTL":1005.2,"PUS":4801.4,"WLG":11010}'),
    ('STG', '{"AST":13238.8,"AUK":10817.6,"DAR":12253.6,"FRE":10829,"MEZ":4102.6,"PTL":708.4,"PUS":4139.3,"WLG":10446.4}'),
    ('STJ', '{"AST":13827.3,"AUK":11406.1,"DAR":12290.5,"FRE":10905.2,"MEZ":3053.6,"PTL":837.4,"PUS":3085.9,"WLG":10931.5}'),
    ('STO', '{"AST":15252.2,"AUK":12828.1,"DAR":13235.7,"FRE":11850.5,"MEZ":2227.1,"PTL":3573.7,"PUS":2226.3,"WLG":12609.4}'),
    ('SUA', '{"AST":11273.5,"AUK":8655.9,"DAR":6082,"FRE":5544.7,"MEZ":12644.6,"PTL":11352.4,"PUS":12641.3,"WLG":8414.5}'),
    ('SUE', '{"AST":11940.3,"AUK":9322.7,"DAR":6748.7,"FRE":6211.4,"MEZ":13311.3,"PTL":12019.2,"PUS":13308.1,"WLG":9085}'),
    ('SUR', '{"AST":7065.8,"AUK":4195.8,"DAR":1117.5,"FRE":1660.4,"MEZ":13606.6,"PTL":12320.9,"PUS":13603.4,"WLG":4320.6}'),
    ('SVQ', '{"AST":13340,"AUK":10918.4,"DAR":11261,"FRE":9875.7,"MEZ":3206.3,"PTL":2934.6,"PUS":3198.9,"WLG":10621.6}'),
    ('SYD', '{"AST":6685.6,"AUK":1251.7,"DAR":2372.8,"FRE":2151.7,"MEZ":13979.6,"PTL":12038.9,"PUS":13976.4,"WLG":1192.5}'),
    ('TAI', '{"AST":5416,"AUK":4766.1,"DAR":2299.1,"FRE":3367.6,"MEZ":15091.8,"PTL":13806.2,"PUS":15088.5,"WLG":4951.7}'),
    ('TAL', '{"AST":15389,"AUK":12964.9,"DAR":13372.5,"FRE":11987.3,"MEZ":2363.9,"PTL":3710.5,"PUS":2363.1,"WLG":12749}'),
    ('TAN', '{"AST":13285.7,"AUK":10862.2,"DAR":11197.2,"FRE":9812,"MEZ":3206.8,"PTL":2937.9,"PUS":3199.3,"WLG":10588.4}'),
    ('TEN', '{"AST":12611.5,"AUK":10188,"DAR":10533.2,"FRE":9148,"MEZ":3580.9,"PTL":2716.5,"PUS":3576.7,"WLG":9879.9}'),
    ('TER', '{"AST":6149.4,"AUK":3559.7,"DAR":828.3,"FRE":2241.7,"MEZ":14449.9,"PTL":13160.2,"PUS":14446.7,"WLG":3691.5}'),
    ('THA', '{"AST":8117.5,"AUK":5942.9,"DAR":2932.2,"FRE":3231.3,"MEZ":13564.4,"PTL":12278.6,"PUS":13561.1,"WLG":6135.8}'),
    ('THE', '{"AST":14964,"AUK":12540.5,"DAR":12875.5,"FRE":11490.3,"MEZ":4882.6,"PTL":4609.4,"PUS":4875.2,"WLG":12280}'),
    ('TID', '{"AST":6164.4,"AUK":3545,"DAR":813.3,"FRE":2227.3,"MEZ":14437.1,"PTL":13147.4,"PUS":14433.9,"WLG":3677.4}'),
    ('TOK', '{"AST":4135.2,"AUK":4785,"DAR":2926.9,"FRE":4453.9,"MEZ":16366.7,"PTL":15081,"PUS":16363.4,"WLG":4971.5}'),
    ('TON', '{"AST":4586.7,"AUK":5062,"DAR":2841.1,"FRE":4194.4,"MEZ":15941.8,"PTL":14656.2,"PUS":15938.6,"WLG":5250.1}'),
    ('TOR', '{"AST":14584.4,"AUK":12160.7,"DAR":12605.2,"FRE":11220,"MEZ":1552.5,"PTL":2579,"PUS":1535.9,"WLG":11844}'),
    ('TOU', '{"AST":14013.5,"AUK":11590,"DAR":11925,"FRE":10539.7,"MEZ":3931.9,"PTL":3658.9,"PUS":3924.4,"WLG":11321.4}'),
    ('TRA', '{"AST":15650.4,"AUK":13227,"DAR":13561.9,"FRE":12176.7,"MEZ":5569,"PTL":5295.9,"PUS":5561.6,"WLG":12939.2}'),
    ('TRI', '{"AST":15341,"AUK":12917.6,"DAR":13252.5,"FRE":11867.3,"MEZ":5259.6,"PTL":4986.5,"PUS":5252.2,"WLG":12659.1}'),
    ('TRO', '{"AST":15033.8,"AUK":12609.4,"DAR":13041.3,"FRE":11656.1,"MEZ":1148.6,"PTL":3029.8,"PUS":1158,"WLG":12427.4}'),
    ('TRP', '{"AST":14406.6,"AUK":11983.1,"DAR":12318.1,"FRE":10932.8,"MEZ":4325.2,"PTL":4052,"PUS":4317.7,"WLG":11714.5}'),
    ('TSU', '{"AST":4575.8,"AUK":5014.7,"DAR":2800.2,"FRE":4182.1,"MEZ":15936.6,"PTL":14650.9,"PUS":15933.3,"WLG":5202.9}'),
    ('TUN', '{"AST":14090.1,"AUK":11666.6,"DAR":12001.6,"FRE":10616.3,"MEZ":4008.7,"PTL":3735.5,"PUS":4001.2,"WLG":11416.6}'),
    ('TUR', '{"AST":15360.5,"AUK":12936.4,"DAR":13344,"FRE":11958.8,"MEZ":2335.4,"PTL":3682,"PUS":2334.6,"WLG":12724.4}'),
    ('ULS', '{"AST":4502.2,"AUK":5100.6,"DAR":2888,"FRE":4266,"MEZ":16019.7,"PTL":14734.1,"PUS":16016.4,"WLG":5288.8}'),
    ('VAL', '{"AST":13690.3,"AUK":11266.8,"DAR":11601.8,"FRE":10216.5,"MEZ":3608.7,"PTL":3335.7,"PUS":3601.2,"WLG":10997.8}'),
    ('VAR', '{"AST":15702.4,"AUK":13278,"DAR":13736.8,"FRE":12351.6,"MEZ":392.2,"PTL":3498.7,"PUS":447.7,"WLG":13099.8}'),
    ('VEN', '{"AST":15011.2,"AUK":12587.8,"DAR":12922.7,"FRE":11537.5,"MEZ":4929.8,"PTL":4656.7,"PUS":4922.4,"WLG":12328.2}'),
    ('VER', '{"AST":14514.1,"AUK":12092.9,"DAR":13610.9,"FRE":12178.5,"MEZ":5750.7,"PTL":2174.7,"PUS":5931.4,"WLG":11658.8}'),
    ('VIS', '{"AST":15158.1,"AUK":12734,"DAR":13141.7,"FRE":11756.4,"MEZ":2133,"PTL":3479.6,"PUS":2132.2,"WLG":12522}'),
    ('VLL', '{"AST":14307.5,"AUK":11884,"DAR":12219,"FRE":10833.7,"MEZ":4226.1,"PTL":3952.9,"PUS":4218.6,"WLG":11613.4}'),
    ('VLP', '{"AST":5646.3,"AUK":5204.7,"DAR":8263.4,"FRE":7034,"MEZ":10911.5,"PTL":8565.7,"PUS":10918.5,"WLG":5023.5}'),
    ('WIL', '{"AST":12780.7,"AUK":10359.5,"DAR":11872.8,"FRE":10439.9,"MEZ":5334.8,"PTL":1889,"PUS":5363.9,"WLG":10011.2}'),
    ('XIA', '{"AST":5395,"AUK":4875.3,"DAR":2408.6,"FRE":3446.9,"MEZ":15111.6,"PTL":13826,"PUS":15108.4,"WLG":5060.2}'),
    ('YEO', '{"AST":4615.4,"AUK":5063.2,"DAR":2829.5,"FRE":4170,"MEZ":15914.1,"PTL":14628.5,"PUS":15910.9,"WLG":5250.7}'),
    ('ZAK', '{"AST":14597,"AUK":12173.5,"DAR":12508.5,"FRE":11123.2,"MEZ":4515.6,"PTL":4242.4,"PUS":4508.1,"WLG":11903.9}'),
    ('ZAN', '{"AST":11051.5,"AUK":7455.1,"DAR":5407.5,"FRE":4517.4,"MEZ":10445.2,"PTL":9153.1,"PUS":10441.9,"WLG":7160}')
  ) as v(code, added)
 where sr.code = v.code;

-- The measure is the save door's (0203): voyage.segments_from_course over the course itself.
insert into public.npc_courses (from_port, to_port, course, nm)
select a.id, b.id, v.course::jsonb,
       (select sum((x->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(v.course::jsonb)) x)
  from (values
    ('AST', 'SFR', '[[46.125,-124.125],[42.625,-124.625],[40.375,-124.625],[39.125,-124.125],[37.875,-122.875],[37.8,-122.42]]'),
    ('SFR', 'AST', '[[37.8,-122.42],[37.875,-122.875],[39.125,-124.125],[40.625,-124.625],[45.625,-124.625],[46.125,-124.125]]'),
    ('AST', 'MTY', '[[46.125,-124.125],[42.625,-124.625],[40.375,-124.625],[39.125,-124.125],[36.875,-122.375],[36.625,-122.125]]'),
    ('MTY', 'AST', '[[36.625,-122.125],[37.125,-122.625],[39.125,-124.125],[40.625,-124.625],[45.625,-124.625],[46.125,-124.125]]'),
    ('AST', 'SDG', '[[46.125,-124.125],[42.625,-124.625],[40.375,-124.625],[39.125,-124.125],[34.375,-120.625],[32.625,-117.375]]'),
    ('SDG', 'AST', '[[32.625,-117.375],[34.625,-120.875],[39.125,-124.125],[40.625,-124.625],[45.625,-124.625],[46.125,-124.125]]'),
    ('AUK', 'SYD', '[[-36.625,175.125],[-35.875,174.875],[-35.125,174.375],[-34.375,173.125],[-34.125,151.375]]'),
    ('SYD', 'AUK', '[[-34.125,151.375],[-34.375,173.125],[-35.375,174.625],[-36.375,175.125],[-36.625,175.125]]'),
    ('AUK', 'HOB', '[[-36.625,175.125],[-35.875,174.875],[-35.125,174.375],[-34.375,173.125],[-34.375,172.625],[-43.125,147.625]]'),
    ('HOB', 'AUK', '[[-43.125,147.625],[-34.375,172.875],[-34.375,173.125],[-35.375,174.625],[-36.375,175.125],[-36.625,175.125]]'),
    ('AUK', 'BND', '[[-36.625,175.125],[-35.875,174.875],[-35.125,174.375],[-10.625,142.625],[-6.125,131.625],[-4.51,129.9]]'),
    ('BND', 'AUK', '[[-4.51,129.9],[-10.625,140.125],[-10.625,142.625],[-35.375,174.625],[-36.375,175.125],[-36.625,175.125]]'),
    ('DAR', 'DIL', '[[-12.375,130.625],[-8.125,127.375],[-8.375,125.625]]'),
    ('DIL', 'DAR', '[[-8.375,125.625],[-8.125,127.375],[-12.375,130.625]]'),
    ('DAR', 'KUP', '[[-12.375,130.625],[-10.375,123.625]]'),
    ('KUP', 'DAR', '[[-10.375,123.625],[-12.375,130.625]]'),
    ('DAR', 'BND', '[[-12.375,130.625],[-4.51,129.9]]'),
    ('BND', 'DAR', '[[-4.51,129.9],[-12.375,130.625]]'),
    ('FRE', 'KUP', '[[-32.125,115.625],[-26.625,113.125],[-23.875,113.125],[-22.125,113.625],[-10.375,123.625]]'),
    ('KUP', 'FRE', '[[-10.375,123.625],[-22.125,113.625],[-24.125,113.125],[-29.875,113.375],[-32.125,115.625]]'),
    ('FRE', 'SUR', '[[-32.125,115.625],[-26.625,113.125],[-23.875,113.125],[-8.375,115.875],[-8.125,115.625],[-7.625,114.625],[-7.125,112.875]]'),
    ('SUR', 'FRE', '[[-7.125,112.875],[-7.875,115.125],[-8.125,115.625],[-8.375,115.875],[-24.375,113.125],[-29.875,113.375],[-32.125,115.625]]'),
    ('FRE', 'MAK', '[[-32.125,115.625],[-26.625,113.125],[-23.875,113.125],[-8.625,116.625],[-4.875,119.375]]'),
    ('MAK', 'FRE', '[[-4.875,119.375],[-8.625,116.625],[-24.125,113.125],[-29.875,113.375],[-32.125,115.625]]'),
    ('MEZ', 'ARK', '[[66.375,43.875],[66.625,42.375],[66.375,40.875],[65.375,39.875],[64.875,40.125]]'),
    ('ARK', 'MEZ', '[[64.875,40.125],[65.375,39.875],[66.625,41.125],[66.625,43.625],[66.375,43.875]]'),
    ('MEZ', 'VAR', '[[66.375,43.875],[70.375,35.625],[70.37,31.11]]'),
    ('VAR', 'MEZ', '[[70.37,31.11],[67.875,42.375],[66.375,43.875]]'),
    ('MEZ', 'LNG', '[[66.375,43.875],[76.625,22.375],[76.625,15.625],[77.125,14.375]]'),
    ('LNG', 'MEZ', '[[77.125,14.375],[67.125,43.125],[66.375,43.875]]'),
    ('PTL', 'BOS', '[[43.375,-70.125],[42.375,-70.625]]'),
    ('BOS', 'PTL', '[[42.375,-70.625],[43.375,-70.125]]'),
    ('PTL', 'NEW', '[[43.375,-70.125],[41.875,-69.625],[41.375,-70.125],[40.625,-72.375],[40.625,-73.875]]'),
    ('NEW', 'PTL', '[[40.625,-73.875],[40.625,-72.125],[41.375,-70.125],[41.875,-69.625],[43.375,-70.125]]'),
    ('PTL', 'JAM', '[[43.375,-70.125],[41.875,-69.625],[41.375,-70.125],[37.125,-75.875],[37.125,-76.125]]'),
    ('JAM', 'PTL', '[[37.125,-76.125],[37.625,-75.375],[41.625,-69.875],[41.875,-69.625],[43.375,-70.125]]'),
    ('PUS', 'ARK', '[[68.375,51.625],[68.625,43.125],[65.375,39.875],[64.875,40.125]]'),
    ('ARK', 'PUS', '[[64.875,40.125],[65.375,39.875],[68.625,43.375],[68.375,51.625]]'),
    ('PUS', 'VAR', '[[68.375,51.625],[70.37,31.11]]'),
    ('VAR', 'PUS', '[[70.37,31.11],[68.375,51.625]]'),
    ('PUS', 'LNG', '[[68.375,51.625],[76.875,14.625],[77.125,14.375]]'),
    ('LNG', 'PUS', '[[77.125,14.375],[76.625,15.875],[68.375,51.625]]'),
    ('WLG', 'SYD', '[[-41.375,174.625],[-40.875,174.125],[-40.375,172.625],[-34.125,151.375]]'),
    ('SYD', 'WLG', '[[-34.125,151.375],[-40.375,172.875],[-40.875,174.125],[-41.375,174.625]]'),
    ('WLG', 'HOB', '[[-41.375,174.625],[-40.875,174.125],[-40.375,172.625],[-43.125,147.625]]'),
    ('HOB', 'WLG', '[[-43.125,147.625],[-40.375,172.875],[-40.875,174.125],[-41.375,174.625]]'),
    ('WLG', 'BND', '[[-41.375,174.625],[-40.875,174.125],[-10.625,142.625],[-6.125,131.625],[-4.51,129.9]]'),
    ('BND', 'WLG', '[[-4.51,129.9],[-10.625,140.125],[-10.625,142.625],[-41.125,174.375],[-41.375,174.625]]')
  ) as v(from_code, to_code, course)
  join public.ports a on a.code = v.from_code
  join public.ports b on b.code = v.to_code
on conflict (from_port, to_port) do nothing;

do $$
declare
  v_n int; v_bad int; v_ports int;
begin
  -- (a) every place has a row, and every row reaches every other place
  select count(*) into v_ports from public.ports;
  select count(*) into v_n from public.sea_reaches;
  if v_n <> v_ports or v_ports <> 260 then
    raise exception '0217 self-assert FAIL: % reach row(s) for % place(s), 260 expected', v_n, v_ports;
  end if;
  select count(*) into v_bad from public.sea_reaches sr
   where (select count(*) from jsonb_object_keys(sr.reaches)) <> v_ports - 1;
  if v_bad <> 0 then
    raise exception '0217 self-assert FAIL: % row(s) do not reach every other place', v_bad;
  end if;
  -- (b) the existing rows kept everything they had, to the tenth: roadstead, snap and every old key
  select count(*) into v_n from reaches_before_0217;
  if v_n <> 252 then
    raise exception '0217 self-assert FAIL: % rows before, 252 expected — the pre-image is not this file''s', v_n;
  end if;
  select count(*) into v_bad from reaches_before_0217 b join public.sea_reaches sr on sr.code = b.code
   where (sr.snap_nm, sr.roadstead_lat, sr.roadstead_lon) is distinct from (b.snap_nm, b.roadstead_lat, b.roadstead_lon)
      or (sr.reaches - array['AST', 'AUK', 'DAR', 'FRE', 'MEZ', 'PTL', 'PUS', 'WLG']::text[]) is distinct from b.reaches
      or (select count(*) from jsonb_object_keys(sr.reaches) k where k in ('AST', 'AUK', 'DAR', 'FRE', 'MEZ', 'PTL', 'PUS', 'WLG')) <> 8;
  if v_bad <> 0 then
    raise exception '0217 self-assert FAIL: % existing row(s) changed beyond gaining the new places', v_bad;
  end if;
  -- (c) the new roadsteads are what the ONE SQL rule answers, snap_nm long, on sailable water
  select count(*) into v_bad from public.sea_reaches sr join public.ports p on p.id = sr.port_id
   cross join lateral voyage.water_roadstead(p.lat, p.lon) w
   where sr.code in ('AST', 'AUK', 'DAR', 'FRE', 'MEZ', 'PTL', 'PUS', 'WLG')
     and (w.lat is distinct from sr.roadstead_lat or w.lon is distinct from sr.roadstead_lon
          or abs(w.nm - sr.snap_nm) > 0.01
          or abs(voyage.gc_distance_nm(p.lat::float8, p.lon::float8, sr.roadstead_lat::float8, sr.roadstead_lon::float8) - sr.snap_nm) > 0.01);
  if v_bad <> 0 then
    raise exception '0217 self-assert FAIL: % new roadstead(s) are not what voyage.water_roadstead answers', v_bad;
  end if;
  -- (d) symmetric, and never under the great circle between the two roadsteads
  select count(*) into v_bad from public.sea_reaches a join public.sea_reaches b on b.code <> a.code
   where a.code in ('AST', 'AUK', 'DAR', 'FRE', 'MEZ', 'PTL', 'PUS', 'WLG')
     and ((a.reaches->>b.code) is null or (b.reaches->>a.code) is null
          or (a.reaches->>b.code)::numeric <> (b.reaches->>a.code)::numeric
          or (a.reaches->>b.code)::numeric < voyage.gc_distance_nm(a.roadstead_lat::float8, a.roadstead_lon::float8, b.roadstead_lat::float8, b.roadstead_lon::float8) - 0.1);
  if v_bad <> 0 then
    raise exception '0217 self-assert FAIL: % pair(s) with a new place are missing, one-way or under the great circle', v_bad;
  end if;
  -- (e) POSITIVE CONTROL: the check (b) bites — bend one old key and it is seen, exactly once
  update public.sea_reaches set reaches = jsonb_set(reaches, array['ACC'], '1'::jsonb) where code = 'ACA';
  select count(*) into v_bad from reaches_before_0217 b join public.sea_reaches sr on sr.code = b.code
   where (sr.reaches - array['AST', 'AUK', 'DAR', 'FRE', 'MEZ', 'PTL', 'PUS', 'WLG']::text[]) is distinct from b.reaches;
  if v_bad <> 1 then
    raise exception '0217 self-assert FAIL: a bent distance was found % time(s), expected exactly 1 — check (b) cannot bite', v_bad;
  end if;
  update public.sea_reaches sr set reaches = b.reaches || (sr.reaches - (select array_agg(k) from jsonb_object_keys(b.reaches) k))
    from reaches_before_0217 b where sr.code = b.code and sr.code = 'ACA';
  select count(*) into v_bad from reaches_before_0217 b join public.sea_reaches sr on sr.code = b.code
   where (sr.reaches - array['AST', 'AUK', 'DAR', 'FRE', 'MEZ', 'PTL', 'PUS', 'WLG']::text[]) is distinct from b.reaches;
  if v_bad <> 0 then
    raise exception '0217 self-assert FAIL: the bent control was not restored (% row(s))', v_bad;
  end if;
  -- (f) the merchant courses: every one held, starting and ending at the two roadsteads, never under the great
  --     circle and never 10 % over the sea table (a pulled string may cut a corner the table's flood keeps —
  --     measured: Mezen -> Arkhangelsk 173.4 nm against the table's 187.4; 0203 records the two measures
  --     differing), and refused by nothing the land guard knows
  select count(*) into v_n from public.npc_courses c join public.ports a on a.id = c.from_port join public.ports b on b.id = c.to_port
   where a.code in ('AST', 'AUK', 'DAR', 'FRE', 'MEZ', 'PTL', 'PUS', 'WLG') or b.code in ('AST', 'AUK', 'DAR', 'FRE', 'MEZ', 'PTL', 'PUS', 'WLG');
  if v_n <> 48 then
    raise exception '0217 self-assert FAIL: % merchant course(s) touch a new harbour, 48 were emitted', v_n;
  end if;
  select count(*) into v_bad from public.npc_courses c
    join public.ports a on a.id = c.from_port join public.ports b on b.id = c.to_port
    join public.sea_reaches ra on ra.port_id = a.id join public.sea_reaches rb on rb.port_id = b.id
   where (a.code in ('AST', 'AUK', 'DAR', 'FRE', 'MEZ', 'PTL', 'PUS', 'WLG') or b.code in ('AST', 'AUK', 'DAR', 'FRE', 'MEZ', 'PTL', 'PUS', 'WLG'))
     and ((c.course->0->>0)::numeric <> ra.roadstead_lat or (c.course->0->>1)::numeric <> ra.roadstead_lon
          or (c.course->-1->>0)::numeric <> rb.roadstead_lat or (c.course->-1->>1)::numeric <> rb.roadstead_lon
          or c.nm < voyage.gc_distance_nm(ra.roadstead_lat::float8, ra.roadstead_lon::float8, rb.roadstead_lat::float8, rb.roadstead_lon::float8) - 0.1
          or c.nm > 1.10 * (ra.reaches->>b.code)::numeric
          or voyage.path_refusal(c.course, ra.roadstead_lat, ra.roadstead_lon, rb.roadstead_lat, rb.roadstead_lon,
                                 public.wc_num('course_join_nm'), 25, 25) is not null);
  if v_bad <> 0 then
    raise exception '0217 self-assert FAIL: % merchant course(s) do not run roadstead to roadstead, fall under the great circle or 10 per cent over the sea table, or cross land', v_bad;
  end if;
  raise notice '0217 (sea) self-assert ok: THE WATER REACHES THE NEW HARBOURS — % places, each reaching every other; 8 new roadstead(s) (AST AUK DAR FRE MEZ PTL PUS WLG) equal voyage.water_roadstead, symmetric and never under the great circle; the 252 existing rows kept every roadstead and every distance (a bent one IS seen, then restored); the raster is not rewritten; 48 merchant courses (each new harbour to and from its 3 nearest by sea) run roadstead to roadstead, never under the great circle nor 10 per cent over the sea table, and cross no land.', v_ports;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0217 (cities) — A NEW HARBOUR IS A CITY LIKE THE OTHERS: its purse, its works, its flag, its
--                  tongue, what its waters ask, and what its goods cost after the sea they crossed
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- The growth above inserted the harbours with 0089's buildings; the sea part gave them roadsteads,
-- distances and merchant courses. Six systems built AFTER 0090 seeded their per-harbour rows once,
-- inline, over the harbours of their day, so a harbour born later has none. MEASURED on 2026-10-25
-- (every foreign key to public.ports on the grown chain: the small harbours' coverage against the
-- eight's): port_treasury 121/121 vs 0/8, city_works 121/121 vs 0/8, port_allegiance 121/121 vs 0/8,
-- port_language 121/121 vs 0/8, sea_leg_asks 121/121 vs 0/8; and port_goods.haul (0173), which the
-- world guard holds equal to world.haul_rows() on every row. Each is landed here by ITS OWN rule:
--   (1) port_treasury (0122) — the row every harbour has, its reserve, and, IN A WORLD WHOSE CITIES
--       WERE ONCE SEEDED (a SEED flow exists: prod), the seed the switch gives a harbour, read from
--       ONE function: public.city_seed_amount(port). The expression lived only inside
--       public.city_treasury_switch (0122, + 0172's standing purse); writing it a second time here
--       would be the second author NO_SPAGHETTI §1 forbids, so it MOVES into the function and the
--       switch calls it (one hunk, sliced from the live body, asserted to occur once and to reverse
--       to its pre-image, ACL / volatility / definer / config unchanged). In a world never seeded
--       (a fresh chain, CI) nothing is posted: the switch seeds every harbour, these included, the
--       day it is lit. Both branches are acceptable outcomes (§7C).
--   (2) city_works (0123) — the four works, at level 0, 0123's own statement over the harbours
--       that lack them (tick_city carries the same insert; this does not wait an hour for it).
--   (3) port_allegiance (0143, 0187) — the rule the world holds today, measured over all 238:
--       a harbour founded by a GREAT POWER flies its founder (92 + 38 home), every other harbour
--       has no holder (105) and is contested; its founder, if any, is its RULER (0187), read from
--       ports.nation_id by world.allegiance. Mezen and Pustozersk are Muscovite (a ruler, no
--       holder); the other six were founded by no seeded power, like Sydney and Boston. None is
--       a home city (data/home-ports.json is untouched).
--   (4) port_language (0156) — each harbour's tongue, as scripts/build-captains.mjs derives it
--       (data/captains.generated.json `harbours`; the world guard holds the table equal to it).
--   (5) sea_leg_asks (0215) — every leg out of and into a new harbour, from the ONE derivation
--       public.sea_leg_asks_derive() (2.3 s for the whole world; filtered to the new legs).
--   (6) port_goods.haul_nm / haul (0173) — re-derived from world.haul_rows() wherever it differs:
--       every row of a new harbour and of a new good, and the existing rows whose nearest maker is
--       now one of the eight (a nearer maker shortens the haul, so the price there falls — the
--       intended effect of a new source, measured in docs/dev-log/2026-10-25-new-harbours.md).
-- WHAT IT DOES NOT TOUCH: player rows; any existing harbour's purse, works, flag or tongue; the sea
-- zones and their boxes (0215); the passage gate (0216, dark); the merchant roster (no house is
-- founded: the courses above put the eight on offer to the planner).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard_0217$
begin
  if to_regprocedure('public.city_treasury_switch(boolean)') is null or to_regprocedure('public.city_standing(uuid)') is null
     or to_regprocedure('public.sea_leg_asks_derive(uuid)') is null or to_regprocedure('world.haul_rows()') is null
     or to_regclass('public.port_language') is null or to_regclass('public.port_allegiance') is null then
    raise exception '0217 refuses: 0122, 0143, 0156, 0172, 0173 or 0215 is not in this world';
  end if;
  if to_regprocedure('public.city_seed_amount(uuid)') is not null then
    raise exception '0217 refuses: public.city_seed_amount already exists — this has been applied once';
  end if;
end $guard_0217$;

create or replace function pg_temp.occurs_0217(p_hay text, p_needle text)
returns int language sql immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table new_harbours_0217 on commit drop as
select p.id, p.code from public.ports p where p.code in ('AST', 'AUK', 'DAR', 'FRE', 'MEZ', 'PTL', 'PUS', 'WLG');

-- ── (1) THE SEED RULE, ONE FUNCTION ────────────────────────────────────────────────────────────
create function public.city_seed_amount(p_port uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0217: what a harbour is SEEDED when its city keeps a purse (0122's seed: city_seed_days of its SELL outflow,
  -- never under city_seed_min; 0172: never under its standing purse). Moved here from public.city_treasury_switch,
  -- which calls it, so the switch and a harbour born after the switch read one rule.
  select greatest(public.city_standing(p_port), public.wc_int('city_seed_min'),
                  round(public.wc_num('city_seed_days') * public.city_sell_outflow(p_port)))::bigint
$$;
revoke all on function public.city_seed_amount(uuid) from public, anon, authenticated;

create temp table switch_before_0217 on commit drop as
select replace(pg_get_functiondef('public.city_treasury_switch(boolean)'::regprocedure), E'\r', '') as def,
       coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef,
       coalesce(p.proconfig::text, '') as cfg, p.proowner as owner
  from pg_proc p where p.oid = 'public.city_treasury_switch(boolean)'::regprocedure;

create temp table hunks_0217 (n int, old text, new text) on commit drop;
insert into hunks_0217 values
(1,
$h$                    greatest(public.city_standing(p.id), public.wc_int('city_seed_min'),   -- 0172: its standing purse
                             round(public.wc_num('city_seed_days') * public.city_sell_outflow(p.id)))::bigint as s
$h$,
$h$                    public.city_seed_amount(p.id) as s   -- 0217: the one seed rule (0122's, with 0172's standing purse)
$h$);

do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
begin
  select * into d from switch_before_0217;
  v_def := d.def;
  for h in select * from hunks_0217 order by n loop
    if pg_temp.occurs_0217(v_def, h.old) <> 1 then
      raise exception '0217 self-assert FAIL: public.city_treasury_switch hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
        h.n, pg_temp.occurs_0217(v_def, h.old);
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
  v_rev := replace(pg_get_functiondef('public.city_treasury_switch(boolean)'::regprocedure), E'\r', '');
  for h in select * from hunks_0217 order by n desc loop
    if pg_temp.occurs_0217(v_rev, h.new) <> 1 then
      raise exception '0217 self-assert FAIL: public.city_treasury_switch new hunk % is not in the live body once', h.n;
    end if;
    v_rev := replace(v_rev, h.new, h.old);
  end loop;
  if v_rev <> d.def then
    raise exception '0217 self-assert FAIL: public.city_treasury_switch does not reverse to its pre-image';
  end if;
  select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
         coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
    into p from pg_proc pr where pr.oid = 'public.city_treasury_switch(boolean)'::regprocedure;
  if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
    raise exception '0217 self-assert FAIL: public.city_treasury_switch changed its ACL (% → %), owner, volatility, definer or config', d.acl, p.acl;
  end if;
end $$;

-- the purse row every harbour has (0122), its reserve (0122's rule), and the seed where cities were seeded
insert into public.port_treasury (port_id)
select n.id from new_harbours_0217 n
on conflict (port_id) do nothing;
update public.port_treasury t set reserve = public.treasury_reserve(t.port_id), updated_at = now()
 where t.port_id in (select id from new_harbours_0217);

create temp table seeded_world_0217 on commit drop as
select exists (select 1 from public.treasury_flows where kind = 'SEED')
    or exists (select 1 from public.treasury_daybook where kind = 'SEED') as seeded;

do $$
declare r record;
begin
  if (select seeded from seeded_world_0217) then
    for r in select n.id, public.city_seed_amount(n.id) as s from new_harbours_0217 n order by n.code loop
      perform public.treasury_post(r.id, 'SEED', r.s, null, null);
    end loop;
    update public.port_treasury t set seeded_at = now() where t.port_id in (select id from new_harbours_0217);
  end if;
end $$;

-- ── (2) THE WORKS (0123's statement, over the harbours that lack them) ────────────────────────
insert into public.city_works (port_id, kind)
select p.id, k.kind from public.ports p
 cross join (values ('docks'), ('market'), ('production'), ('inn')) k(kind)
 where p.kind = 'HARBOUR'
on conflict (port_id, kind) do nothing;

-- ── (3) THE FLAG (0143's row; 0187's rule: a great power's foundation flies its founder) ───────
insert into public.port_allegiance (port_id, nation_id, home)
select n.id, (select gp.nation_id from public.great_powers gp where gp.nation_id = p.nation_id), false
  from new_harbours_0217 n join public.ports p on p.id = n.id
on conflict (port_id) do nothing;

-- ── (4) THE TONGUE (data/captains.generated.json `harbours`, scripts/build-captains.mjs) ────────
insert into public.port_language (port_id, language)
select p.id, v.language
  from (values
  ('AST', 'SPANISH'),
  ('AUK', 'MALAY'),
  ('DAR', 'MALAY'),
  ('FRE', 'MALAY'),
  ('MEZ', 'SLAVIC'),
  ('PTL', 'ENGLISH'),
  ('PUS', 'SLAVIC'),
  ('WLG', 'MALAY')
  ) as v(code, language)
  join public.ports p on p.code = v.code
on conflict (port_id) do nothing;

-- ── (5) WHAT THE WATERS ASK, OUT OF AND INTO EACH NEW HARBOUR (0215's one derivation) ─────────
create temp table t_asks_0217 on commit drop as select clock_timestamp() as t0;
insert into public.sea_leg_asks (from_port, to_port, wave_min, title_min)
select d.from_port, d.to_port, d.wave_min, d.title_min
  from public.sea_leg_asks_derive() d
 where d.from_port in (select id from new_harbours_0217) or d.to_port in (select id from new_harbours_0217);
create temp table t_asks_done_0217 on commit drop as select clock_timestamp() as t1;

-- ── (6) THE HAUL (0173): every market row equal to world.haul_rows() again ───────────────────────
create temp table haul_moved_0217 on commit drop as
select pg.port_id, pg.good_id, pg.haul_nm as old_nm, pg.haul as old_haul, h.haul_nm as new_nm, h.haul as new_haul
  from public.port_goods pg
  join world.haul_rows() h on h.port_id = pg.port_id and h.good_id = pg.good_id
 where (pg.haul_nm, pg.haul) is distinct from (h.haul_nm, h.haul);
update public.port_goods pg
   set haul_nm = m.new_nm, haul = m.new_haul
  from haul_moved_0217 m
 where pg.port_id = m.port_id and pg.good_id = m.good_id;
create temp table t_haul_done_0217 on commit drop as select clock_timestamp() as t2;

-- ── SELF-ASSERT (its own rows: the eight harbours, the ten goods, and the hauls it moved) ───────
do $$
declare
  v_n int; v_bad int; v_h int; v_seeded boolean; v_sum bigint; v_new_rows int; v_old_rows int; v_old_ports int;
begin
  select count(*) into v_h from new_harbours_0217;
  if v_h <> 8 then
    raise exception '0217 self-assert FAIL: % new harbour(s) found, 8 expected', v_h;
  end if;
  -- (a) the seed rule moved without changing: for EVERY harbour the function equals the switch's old expression
  select count(*) into v_bad from public.ports p
   where p.kind = 'HARBOUR'
     and public.city_seed_amount(p.id) is distinct from
         greatest(public.city_standing(p.id), public.wc_int('city_seed_min'),
                  round(public.wc_num('city_seed_days') * public.city_sell_outflow(p.id)))::bigint;
  if v_bad <> 0 then
    raise exception '0217 self-assert FAIL: city_seed_amount differs from the switch''s pre-image expression at % harbour(s)', v_bad;
  end if;
  -- a new harbour is no capital, so its seed is the ordinary standing purse, BY AMOUNT
  select count(*) into v_bad from new_harbours_0217 n
   where public.city_seed_amount(n.id) <> greatest(public.wc_int('city_purse_city'), public.wc_int('city_seed_min'));
  if v_bad <> 0 then
    raise exception '0217 self-assert FAIL: % new harbour(s) would not be seeded the ordinary standing purse', v_bad;
  end if;
  -- (b) the purse: a row each, its reserve; seeded exactly city_seed_amount where the world was seeded, else nothing
  select seeded into v_seeded from seeded_world_0217;
  select count(*) into v_bad from new_harbours_0217 n left join public.port_treasury t on t.port_id = n.id
   where t.port_id is null or t.reserve <> public.treasury_reserve(n.id)
      or (v_seeded and (t.seeded_at is null or public.treasury_balance(n.id) <> public.city_seed_amount(n.id)))
      or (not v_seeded and (t.seeded_at is not null or public.treasury_balance(n.id) <> 0));
  if v_bad <> 0 then
    raise exception '0217 self-assert FAIL: % new harbour purse(s) are not what the rule gives (seeded world: %)', v_bad, v_seeded;
  end if;
  select coalesce(sum(public.treasury_balance(n.id)), 0) into v_sum from new_harbours_0217 n;
  -- (c) the works, the flag, the tongue: one of each kind, the rule's values
  select count(*) into v_n from public.city_works w where w.port_id in (select id from new_harbours_0217) and w.level = 0 and w.subscribed = 0;
  if v_n <> 4 * v_h then
    raise exception '0217 self-assert FAIL: % works at the new harbours, % expected', v_n, 4 * v_h;
  end if;
  select count(*) into v_bad from new_harbours_0217 n join public.ports p on p.id = n.id
    left join public.port_allegiance a on a.port_id = n.id
   where a.port_id is null or a.home
      or a.nation_id is distinct from (select gp.nation_id from public.great_powers gp where gp.nation_id = p.nation_id);
  if v_bad <> 0 then
    raise exception '0217 self-assert FAIL: % new harbour(s) fly the wrong flag', v_bad;
  end if;
  select count(*) into v_n from public.ports p join new_harbours_0217 n on n.id = p.id
    join public.nations nn on nn.id = p.nation_id where nn.code = 'RUS';
  if v_n <> 2 then
    raise exception '0217 self-assert FAIL: % new harbour(s) ruled by Muscovy, 2 expected (Mezen, Pustozersk)', v_n;
  end if;
  select count(*) into v_n from public.port_language l where l.port_id in (select id from new_harbours_0217);
  if v_n <> v_h then
    raise exception '0217 self-assert FAIL: % new harbour(s) have a tongue, % expected', v_n, v_h;
  end if;
  -- (d) the waters' asks: the table is whole again (harbours²), and every new leg equals the derivation
  select count(*) into v_n from public.ports where kind = 'HARBOUR';
  if (select count(*) from public.sea_leg_asks) <> v_n * v_n then
    raise exception '0217 self-assert FAIL: % leg asks for % harbours (% expected)', (select count(*) from public.sea_leg_asks), v_n, v_n * v_n;
  end if;
  select count(*) into v_bad
    from (select from_port, to_port, wave_min, title_min from public.sea_leg_asks
           where from_port in (select id from new_harbours_0217) or to_port in (select id from new_harbours_0217)
          except
          select from_port, to_port, wave_min, title_min from public.sea_leg_asks_derive()
           where from_port in (select id from new_harbours_0217) or to_port in (select id from new_harbours_0217)) x;
  if v_bad <> 0 then
    raise exception '0217 self-assert FAIL: % new leg ask(s) differ from public.sea_leg_asks_derive()', v_bad;
  end if;
  select count(*) into v_n from public.sea_leg_asks
   where from_port in (select id from new_harbours_0217) or to_port in (select id from new_harbours_0217);
  if v_n <> 2 * v_h * (select count(*) from public.ports where kind = 'HARBOUR') - v_h * v_h then
    raise exception '0217 self-assert FAIL: % leg asks touch a new harbour', v_n;
  end if;
  -- (e) the hauls: every market row equals world.haul_rows() — and the rows this file moved are exactly its own:
  --     a new harbour's, a new good's, or an existing row whose nearest maker is now one of the eight
  select count(*) into v_bad from public.port_goods pg left join world.haul_rows() h on h.port_id = pg.port_id and h.good_id = pg.good_id
   where (pg.haul_nm, pg.haul) is distinct from (h.haul_nm, h.haul);
  if v_bad <> 0 then
    raise exception '0217 self-assert FAIL: % market row(s) differ from world.haul_rows()', v_bad;
  end if;
  select count(*) into v_new_rows from haul_moved_0217 m
   where m.port_id in (select id from new_harbours_0217)
      or m.good_id in (select g.id from public.goods g where g.code in ('jarrah', 'kauri-timber', 'kauri-gum', 'harakeke', 'pounamu', 'kumara', 'mast-pine', 'beaver-pelts', 'douglas-fir', 'dentalium'));
  select count(*) into v_old_rows from haul_moved_0217 m
   where m.port_id not in (select id from new_harbours_0217)
     and m.good_id not in (select g.id from public.goods g where g.code in ('jarrah', 'kauri-timber', 'kauri-gum', 'harakeke', 'pounamu', 'kumara', 'mast-pine', 'beaver-pelts', 'douglas-fir', 'dentalium'));
  select count(*) into v_bad from haul_moved_0217 m
   where m.port_id not in (select id from new_harbours_0217)
     and m.good_id not in (select g.id from public.goods g where g.code in ('jarrah', 'kauri-timber', 'kauri-gum', 'harakeke', 'pounamu', 'kumara', 'mast-pine', 'beaver-pelts', 'douglas-fir', 'dentalium'))
     and not ((m.old_nm is null or m.new_nm < m.old_nm)
              and exists (select 1 from public.port_specialties s where s.good_id = m.good_id and s.port_id in (select id from new_harbours_0217)));
  if v_bad <> 0 then
    raise exception '0217 self-assert FAIL: % existing market row(s) changed haul without a new maker of the good drawing nearer', v_bad;
  end if;
  select count(distinct m.port_id) into v_old_ports from haul_moved_0217 m where m.port_id not in (select id from new_harbours_0217);
  raise notice '0217 (cities) self-assert ok: A NEW HARBOUR IS A CITY LIKE THE OTHERS — % harbours; the seed rule is one function (public.city_seed_amount equals the switch''s pre-image expression at every harbour; the switch re-cut by 1 hunk that reverses to its pre-image, ACL unchanged); purses: % (seeded world: %, % ducats posted as SEED); 4 works each at level 0; flags by 0187''s rule (2 ruled by Muscovy, no holder; none a home); a tongue each; % leg asks touch them, equal to sea_leg_asks_derive(), the table whole again; % market rows took their haul from world.haul_rows() (% of a new harbour or good, % existing rows at % harbours whose good now has a nearer maker among the eight). TIMING: asks % ms, haul % ms.',
    v_h, v_h, v_seeded, v_sum, v_n,
    (select count(*) from haul_moved_0217), v_new_rows, v_old_rows, v_old_ports,
    round(extract(epoch from ((select t1 from t_asks_done_0217) - (select t0 from t_asks_0217))) * 1000),
    round(extract(epoch from ((select t2 from t_haul_done_0217) - (select t1 from t_asks_done_0217))) * 1000);
end $$;

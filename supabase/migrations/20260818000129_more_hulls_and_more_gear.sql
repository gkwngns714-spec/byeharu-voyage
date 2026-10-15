-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0129 — MORE HULLS AND MORE GEAR  (docs/SHIPS_AND_GEAR.md §6 S5, §7 S6, §8 S7)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-15, queue item 3: *"make more ship types and more gear"*, and the same evening *"we need
-- levels, stats too."* 0127 gave hulls and captains their levels (dark); this file gives the yards
-- and the workstations something to make with them.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) EIGHT NEW SHIP TYPES (S5), eleven in all, three families and three tiers — pinnace and dhow
--     (tier 1), caravela redonda, fluyt, xebec and junk (tier 2), galleon and East Indiaman (tier
--     3): their ship_classes rows (the six 0074 stats with guns = attack/10, so S4's escort re-cut
--     stays a no-op for an unfitted hull of every class), class_slots, class_cabins, the level
--     unlocks of §6.2 (public.class_slot_unlocks, 0127's table — bites only while levels_bite is
--     on), and their hull recipes (timber out of the warehouse, fittings out of the store, labour).
-- (2) TWO NEW YARD RULES, in their one home cmd.do_build (two hunks) and printed by
--     world.building_yard (two hunks): hull_recipes.yard_regions (NEW, null = any yard of her
--     tier) — a dhow or a junk is laid down in the East, a fluyt in the North, a xebec in the
--     Mediterranean: E_WRONG_COAST elsewhere; hull_recipes.min_level (NEW, default 1) — the
--     company's TRADING level she asks (public.player_progress): E_LEVEL with figures, ONLY while
--     levels_bite is on (0127's switch, shipped dark). The three hulls of today ask level 1 and
--     no coast, so nothing a player can build today is taken away.
-- (3) TWELVE NEW FITTINGS (S6), twenty-four in all: item_kinds, item_effects (each buys one stat and
--     spends another), item_recipes (2-5 goods, every one sold somewhere), and the SHIP level eight
--     of them ask (public.item_level_asks, 0127's table; E_SHIP_LEVEL from public.mount_fitting,
--     only while levels_bite is on). Gear changes no combat: nothing reads attack, armour,
--     accuracy, reach or sighting until S4.
-- (4) S7: scripts/db/world-guard.mjs now holds ship_classes, class_slots, class_cabins,
--     class_slot_unlocks, hull_recipes (+ goods, items), item_kinds, item_effects, item_recipes,
--     item_level_asks and npc_loadouts EQUAL to data/ship_stats.json, data/hulls.json,
--     data/fittings.json and data/npc-loadouts.json on every apply (positive control first). The
--     rows below are generated from those files by scripts/build-ships-gear-0129.mjs.
--
-- ── MERCHANTS: THE NEW CLASSES ARE PLAYER-ONLY ──────────────────────────────────────────────────
-- public.npc_fit_loadout refuses E_NO_LOADOUT for a class with no authored loadout (0126), and no
-- loadout is authored for the eight: a merchant is founded from the authored roster, which names
-- barca, carlat and nau only. The self-assert proves no merchant sails a new class, every class a
-- merchant sails has a loadout, and none of the eight has one — so npc_found refusing a new class
-- is the rule, not an accident. Giving merchants the new hulls is a roster + loadout change, later.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- lock_timeout 5 s. ALTER TABLE hull_recipes (two ADD COLUMNs with constant defaults, metadata
-- only) holds ACCESS EXCLUSIVE on hull_recipes until commit — read only by cmd.do_build and
-- world.building_yard, so a yard screen opened during the apply waits seconds. The catalogue
-- INSERTs take ROW EXCLUSIVE (reads go on) and KEY SHARE on the rows their FKs reference. ships,
-- fleets, voyages and every table the arrivals tick writes are never written or locked: the probe
-- writes only its own house's rows (a hull, its shed, its store, its ledger lines) and rolls back.
-- No LOCK TABLE, no set role, no begin/commit. THE WHOLE FILE IS ONE `do` BLOCK, so it is atomic
-- however the runner groups statements: a failed assert leaves nothing behind.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- One forward migration: re-cut cmd.do_build and world.building_yard back (every OLD hunk is below
-- verbatim and the self-assert proves each live body reverses to its pre-image by them), delete the
-- twelve fittings and the eight classes' rows (assert first that no ship, ship_fittings or
-- player_items row references them), drop hull_recipes.yard_regions and min_level.
--
-- SUPERSEDES: cmd.do_build (0072 as cut by 0096/0122), world.building_yard (0072) — hunks sliced
-- from the LIVE bodies (LF-normalised), each asserted to occur exactly once. No new entry point, no
-- client write, no cron, nothing in the arrivals tick.
-- VERSION: 0129, on production head 0128.

do $m0129$
declare
  v_def      text;
  v_back     text;
  v_n        int;
  v_fn       text;
  v_bad      int;
  v_txt      text;
  hk         record;
  v_player   uuid;
  v_fleet    uuid;
  v_barca    uuid;
  v_junk     uuid;
  v_west     uuid;
  v_east     uuid;
  v_great    uuid;
  v_ws2      uuid;
  v_purse    bigint;
  v_err      text;
  v_detail   text;
  v_res      jsonb;
  v_yard     jsonb;
  v_t0       timestamptz := clock_timestamp();
  c_uid      constant uuid := '00000000-0129-4000-8000-000000000001';
  c_new_cls  constant text[] := array['pinnace', 'dhow', 'carred', 'fluyt', 'xebec', 'junk', 'galleon', 'indiaman'];
  c_new_gear constant text[] := array['storm-canvas', 'studding-sails', 'whipstaff', 'binnacle-and-charts', 'sheet-anchor',
                                      'capstan', 'bilge-pumps', 'doubled-planking', 'swivel-guns', 'stern-chasers',
                                      'carronades', 'topgallant-mast'];
  c_yard_new constant text[] := array['coast', 'on_coast', 'min_level', 'your_level'];
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 1. THE PRE-IMAGES ────────────────────────────────────────────────────────────────────────
  -- Plain temp tables (not ON COMMIT DROP): they live as long as this block needs them however the
  -- runner groups statements, and are dropped at its end.
  create temp table defs_before_0129 as
  select f.fn,
         replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
         coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
    from unnest(array['cmd.do_build(uuid, jsonb)', 'world.building_yard(uuid)']) f(fn);

  -- every catalogue row an earlier file put in, as text — none of it may move.
  create temp table catalogue_before_0129 as
  select 'ship_classes' as t, (select string_agg((to_jsonb(c) - 'id')::text, '|' order by c.code) from public.ship_classes c) as rows
  union all select 'class_slots', (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.slot) from public.class_slots x)
  union all select 'class_cabins', (select string_agg(to_jsonb(x)::text, '|' order by x.class_code) from public.class_cabins x)
  union all select 'class_slot_unlocks', (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.slot, x.min_level) from public.class_slot_unlocks x)
  union all select 'hull_recipes', (select string_agg(to_jsonb(x)::text, '|' order by x.class_code) from public.hull_recipes x)
  union all select 'hull_recipe_goods', (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.good_id) from public.hull_recipe_goods x)
  union all select 'hull_recipe_items', (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.item_code) from public.hull_recipe_items x)
  union all select 'item_kinds', (select string_agg(to_jsonb(x)::text, '|' order by x.code) from public.item_kinds x)
  union all select 'item_effects', (select string_agg(to_jsonb(x)::text, '|' order by x.item_code, x.stat) from public.item_effects x)
  union all select 'item_recipes', (select string_agg(to_jsonb(x)::text, '|' order by x.item_code, x.good_id) from public.item_recipes x)
  union all select 'item_level_asks', (select string_agg(to_jsonb(x)::text, '|' order by x.item_code) from public.item_level_asks x)
  union all select 'npc_loadouts', (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.pattern, x.item_code) from public.npc_loadouts x);

  -- every yard as the screen serves it today (no viewer: the `have` columns read 0).
  create temp table yards_before_0129 as
  select b.port_id, world.building_yard(b.port_id) as view
    from public.port_buildings b where b.kind = 'building_yard';

  create temp table posture_before_0129 as
  select (select count(*) from public.client_rpc_entry_points()) as entry_points;

  if exists (select 1 from public.ship_classes where code = any (c_new_cls))
     or exists (select 1 from public.item_kinds where code = any (c_new_gear)) then
    raise exception '0129 self-assert FAIL: a new class or fitting is already in the world — this file was cut against a world without them';
  end if;

  -- ── 2. THE YARD'S TWO NEW COLUMNS ────────────────────────────────────────────────────────────
  alter table public.hull_recipes add column if not exists yard_regions text[];
  alter table public.hull_recipes add column if not exists min_level int not null default 1
    check (min_level between 1 and 20);
  comment on column public.hull_recipes.yard_regions is
    '0129: the region codes whose yards lay her down (a junk in the East); null = any yard of her tier. Read by '
    'cmd.do_build (E_WRONG_COAST) and world.building_yard. Authored in data/hulls.json and guarded.';
  comment on column public.hull_recipes.min_level is
    '0129: the company''s TRADING level she asks (public.player_progress) — cmd.do_build refuses E_LEVEL only while '
    'levels_bite is on. Authored in data/hulls.json and guarded.';

  -- ── 3. THE ROWS (S5, S6) ─────────────────────────────────────────────────────────────────────
  -- <generated:0129> by scripts/build-ships-gear-0129.mjs from data/ship_stats.json, data/hulls.json and
  -- data/fittings.json. Do not edit by hand: change the data and re-run the script.
  insert into public.ship_classes (code, name, family, rig, tier, hold, crew_required, crew_max, speed_kn, durability,
                                   guns, draft, build_hours, build_cost, handling, armour, attack, accuracy, reach, sighting, stat_note) values
    ('pinnace', 'Pinnace', 'Western', 'mixed', 1, 35, 6, 16, 6.4, 300, 0, 1, 20, 10000, 86, 4, 0, 0, 20, 10,
     'A scout: fast, handy and sharp-eyed, and she carries next to nothing.'),
    ('dhow', 'Dhow', 'Eastern', 'lateen', 1, 75, 9, 22, 5.2, 380, 0, 1, 22, 11000, 72, 5, 0, 0, 20, 8,
     'The Indian Ocean coaster: one great lateen, a sewn hull, and a better hold than a barca.'),
    ('carred', 'Caravela redonda', 'Western', 'square', 2, 130, 16, 40, 5.6, 650, 4, 2, 44, 34000, 68, 14, 40, 42, 50, 11,
     'The square-rigged caravel: the all-round trader, with four guns because the open sea asks for them.'),
    ('fluyt', 'Fluyt', 'Western', 'square', 2, 240, 10, 26, 4.9, 700, 2, 2, 48, 40000, 55, 10, 20, 35, 45, 9,
     'The Dutch bulk hauler: a nau''s share of cargo on a caravel''s wages, and slow to answer the helm.'),
    ('xebec', 'Xebec', 'Mediterranean', 'mixed', 2, 70, 28, 90, 6.6, 480, 5, 1, 40, 30000, 88, 8, 50, 38, 30, 11,
     'The Mediterranean raider: lateen and oars, a huge crew, a small hold, and quicker than anything she meets.'),
    ('junk', 'Junk', 'Eastern', 'mixed', 2, 200, 20, 60, 4.8, 850, 2, 2, 46, 38000, 58, 20, 20, 30, 40, 9,
     'The eastern trader: battened sails and watertight bulkheads, hard to hurt and harder to sink.'),
    ('galleon', 'Galleon', 'Western', 'square', 3, 320, 80, 220, 4.7, 2100, 17, 3, 110, 150000, 42, 36, 170, 58, 75, 14,
     'The armed convoy: two gun decks and a high stern, and she fights at a distance.'),
    ('indiaman', 'East Indiaman', 'Western', 'square', 3, 520, 70, 180, 4.5, 2000, 11, 3, 120, 170000, 40, 30, 110, 50, 65, 13,
     'The long-haul trader: more hold than anything afloat, and guns enough to keep it.');
  insert into public.class_slots (class_code, slot, count) values
    ('pinnace', 'rig', 1),
    ('pinnace', 'weapon', 1),
    ('pinnace', 'ground-tackle', 1),
    ('pinnace', 'lookout', 1),
    ('dhow', 'rig', 1),
    ('dhow', 'weapon', 1),
    ('dhow', 'ground-tackle', 1),
    ('dhow', 'hull', 1),
    ('carred', 'rig', 2),
    ('carred', 'weapon', 2),
    ('carred', 'ground-tackle', 1),
    ('carred', 'steering', 1),
    ('fluyt', 'rig', 1),
    ('fluyt', 'weapon', 1),
    ('fluyt', 'ground-tackle', 1),
    ('fluyt', 'steering', 1),
    ('fluyt', 'hull', 2),
    ('xebec', 'rig', 2),
    ('xebec', 'weapon', 2),
    ('xebec', 'ground-tackle', 1),
    ('xebec', 'steering', 1),
    ('junk', 'rig', 2),
    ('junk', 'weapon', 1),
    ('junk', 'ground-tackle', 1),
    ('junk', 'hull', 2),
    ('galleon', 'rig', 2),
    ('galleon', 'weapon', 4),
    ('galleon', 'ground-tackle', 1),
    ('galleon', 'steering', 1),
    ('galleon', 'hull', 1),
    ('galleon', 'lookout', 1),
    ('galleon', 'flourish', 1),
    ('indiaman', 'rig', 2),
    ('indiaman', 'weapon', 3),
    ('indiaman', 'ground-tackle', 2),
    ('indiaman', 'steering', 1),
    ('indiaman', 'hull', 2),
    ('indiaman', 'lookout', 1),
    ('indiaman', 'flourish', 1);
  insert into public.class_cabins (class_code, cabins) values
    ('pinnace', 3),
    ('dhow', 3),
    ('carred', 4),
    ('fluyt', 4),
    ('xebec', 4),
    ('junk', 4),
    ('galleon', 5),
    ('indiaman', 5);
  insert into public.class_slot_unlocks (class_code, slot, count, min_level) values
    ('pinnace', 'flourish', 1, 3),
    ('dhow', 'lookout', 1, 3),
    ('carred', 'hull', 1, 4),
    ('carred', 'lookout', 1, 6),
    ('fluyt', 'hull', 1, 5),
    ('xebec', 'weapon', 1, 5),
    ('junk', 'weapon', 1, 5),
    ('galleon', 'weapon', 1, 6),
    ('galleon', 'hull', 1, 10),
    ('indiaman', 'hull', 1, 6),
    ('indiaman', 'rig', 1, 10);
  insert into public.hull_recipes (class_code, yard_tier, ducats, yard_regions, min_level, note) values
    ('pinnace', 1, 2500, null, 1,
     'A scout''s hull: light frames, a tall rig and a hold you could fill from one quay.'),
    ('dhow', 1, 2800, array['WIA', 'ARA', 'EAS', 'SOU'], 1,
     'Teak planks sewn with coir and one great lateen - the Indian Ocean builds her and nobody else.'),
    ('carred', 2, 9000, array['IBE', 'FRA', 'BRI', 'WES', 'ADR', 'BAL', 'CAR', 'STH', 'PAC'], 2,
     'The caravel squared off for the open ocean: two suits of sail and a proper rudder.'),
    ('fluyt', 2, 10000, array['FRA', 'BAL', 'BRI'], 3,
     'A long box of northern spruce with a narrow deck - the Low Countries build her by the hundred.'),
    ('xebec', 2, 8000, array['WES', 'ADR', 'LEV', 'AEG', 'IBE'], 3,
     'Lean, lateen-rigged and full of men - a Mediterranean yard builds her to catch what runs.'),
    ('junk', 1, 9500, array['CHI', 'JAP', 'KOR', 'SOU'], 2,
     'Teak bulkheads, rattan-battened sails and a stern rudder - the hull the eastern yards have always built.'),
    ('galleon', 3, 38000, null, 5,
     'Two gun decks over live oak and copper - only the seven great yards can lay one down.'),
    ('indiaman', 3, 42000, null, 6,
     'The biggest hold afloat, sheathed for the long haul east - a great yard''s work for a year.');
  insert into public.hull_recipe_goods (class_code, good_id, qty)
  select w.class_code, g.id, w.qty from (values
    ('pinnace', 'timber', 25),
    ('pinnace', 'tar', 5),
    ('pinnace', 'cordage', 4),
    ('pinnace', 'ships-nails', 6),
    ('dhow', 'teak', 30),
    ('dhow', 'coir', 8),
    ('dhow', 'tar', 4),
    ('dhow', 'ships-nails', 4),
    ('carred', 'timber', 80),
    ('carred', 'naval-timber', 25),
    ('carred', 'tar', 12),
    ('carred', 'cordage', 12),
    ('carred', 'ships-nails', 20),
    ('fluyt', 'timber', 110),
    ('fluyt', 'norway-spruce', 20),
    ('fluyt', 'tar', 15),
    ('fluyt', 'cordage', 10),
    ('fluyt', 'ships-nails', 24),
    ('xebec', 'naval-timber', 40),
    ('xebec', 'timber', 50),
    ('xebec', 'tar', 10),
    ('xebec', 'cordage', 14),
    ('xebec', 'ships-nails', 16),
    ('junk', 'teak', 70),
    ('junk', 'timber', 40),
    ('junk', 'tar', 10),
    ('junk', 'rattan', 10),
    ('junk', 'ships-nails', 12),
    ('galleon', 'live-oak', 110),
    ('galleon', 'naval-timber', 50),
    ('galleon', 'timber', 70),
    ('galleon', 'tar', 30),
    ('galleon', 'ships-nails', 50),
    ('indiaman', 'live-oak', 100),
    ('indiaman', 'naval-timber', 60),
    ('indiaman', 'timber', 80),
    ('indiaman', 'tar', 30),
    ('indiaman', 'ships-nails', 50)) w(class_code, good_code, qty) join public.goods g on g.code = w.good_code;
  insert into public.hull_recipe_items (class_code, item_code, qty) values
    ('pinnace', 'suit-of-sails', 1),
    ('pinnace', 'anchor-and-cable', 1),
    ('dhow', 'suit-of-sails', 1),
    ('dhow', 'anchor-and-cable', 1),
    ('carred', 'suit-of-sails', 2),
    ('carred', 'anchor-and-cable', 1),
    ('carred', 'rudder-and-helm', 1),
    ('fluyt', 'suit-of-sails', 1),
    ('fluyt', 'anchor-and-cable', 1),
    ('fluyt', 'rudder-and-helm', 1),
    ('fluyt', 'hold-fittings', 1),
    ('xebec', 'suit-of-sails', 2),
    ('xebec', 'anchor-and-cable', 1),
    ('xebec', 'rudder-and-helm', 1),
    ('xebec', 'boarding-gear', 1),
    ('junk', 'suit-of-sails', 2),
    ('junk', 'anchor-and-cable', 1),
    ('junk', 'hold-fittings', 1),
    ('galleon', 'suit-of-sails', 3),
    ('galleon', 'anchor-and-cable', 2),
    ('galleon', 'rudder-and-helm', 1),
    ('galleon', 'copper-sheathing', 1),
    ('galleon', 'broadside-guns', 1),
    ('indiaman', 'suit-of-sails', 3),
    ('indiaman', 'anchor-and-cable', 2),
    ('indiaman', 'rudder-and-helm', 1),
    ('indiaman', 'hold-fittings', 2),
    ('indiaman', 'copper-sheathing', 1);
  insert into public.item_kinds (code, name, slot, buys, spends, note, volume, ws_tier) values
    ('storm-canvas', 'Storm Canvas', 'rig', 'Durability, Handling', 'Speed',
     'Heavy small sails that will not blow out - she survives the gale and crawls in fair weather.', 3, 1),
    ('studding-sails', 'Studding Sails', 'rig', 'Speed', 'Handling, Durability',
     'Extra canvas set out on booms beyond the yards: all speed, no manners, and the first thing to carry away.', 4, 2),
    ('whipstaff', 'Whipstaff', 'steering', 'Handling', 'Hold',
     'A lever on the tiller - cheap, simple, and better than shouting down a hatch.', 2, 1),
    ('binnacle-and-charts', 'Binnacle & Charts', 'steering', 'Sighting, Handling', 'Hold',
     'A lit compass and a chest of good charts: she knows where she is and what lies ahead.', 2, 3),
    ('sheet-anchor', 'Sheet Anchor', 'ground-tackle', 'Durability (weather-holding), Handling', 'Hold',
     'The biggest anchor aboard, kept for the night every other one drags.', 5, 2),
    ('capstan', 'Capstan', 'ground-tackle', 'Handling, and a little Speed', 'Hold',
     'Twenty men on the bars weigh anchor in half the time.', 3, 2),
    ('bilge-pumps', 'Bilge Pumps', 'hull', 'Durability', 'Hold',
     'Chain pumps that keep a leaking hull afloat long enough to reach a yard.', 3, 1),
    ('doubled-planking', 'Doubled Planking', 'hull', 'Armour, Durability', 'Speed, Hold',
     'A second skin of oak over the first: shot bounces, and so does a little of her speed.', 6, 2),
    ('swivel-guns', 'Swivel Guns', 'weapon', 'Attack, Accuracy', 'Handling',
     'Small guns on the rail - a coaster''s answer to a boarding party.', 2, 2),
    ('stern-chasers', 'Stern Chasers', 'weapon', 'Reach, Accuracy', 'Hold',
     'Long guns run out aft, for the ship that is chasing you.', 4, 3),
    ('carronades', 'Carronades', 'weapon', 'Attack', 'Reach, Hold, Handling',
     'Short, heavy smashers: terrible close in, useless at a distance, and they want a stout hull.', 5, 3),
    ('topgallant-mast', 'Topgallant Mast', 'lookout', 'Sighting, and a little Speed', 'Handling, Durability',
     'A third mast above the topmast: a longer horizon and more canvas, and more to lose aloft.', 3, 2);
  insert into public.item_effects (item_code, stat, delta) values
    ('storm-canvas', 'durability', 50),
    ('storm-canvas', 'handling', 4),
    ('storm-canvas', 'speed', -0.25),
    ('studding-sails', 'speed', 0.9),
    ('studding-sails', 'handling', -14),
    ('studding-sails', 'durability', -30),
    ('whipstaff', 'handling', 7),
    ('whipstaff', 'hold', -2),
    ('binnacle-and-charts', 'sighting', 3),
    ('binnacle-and-charts', 'handling', 5),
    ('binnacle-and-charts', 'hold', -3),
    ('sheet-anchor', 'durability', 60),
    ('sheet-anchor', 'handling', 2),
    ('sheet-anchor', 'hold', -10),
    ('capstan', 'handling', 6),
    ('capstan', 'speed', 0.1),
    ('capstan', 'hold', -5),
    ('bilge-pumps', 'durability', 90),
    ('bilge-pumps', 'hold', -5),
    ('doubled-planking', 'armour', 10),
    ('doubled-planking', 'durability', 160),
    ('doubled-planking', 'speed', -0.45),
    ('doubled-planking', 'hold', -12),
    ('swivel-guns', 'attack', 20),
    ('swivel-guns', 'accuracy', 8),
    ('swivel-guns', 'handling', -2),
    ('stern-chasers', 'reach', 20),
    ('stern-chasers', 'accuracy', 10),
    ('stern-chasers', 'hold', -8),
    ('carronades', 'attack', 90),
    ('carronades', 'reach', -15),
    ('carronades', 'hold', -14),
    ('carronades', 'handling', -4),
    ('topgallant-mast', 'sighting', 7),
    ('topgallant-mast', 'speed', 0.2),
    ('topgallant-mast', 'handling', -8),
    ('topgallant-mast', 'durability', -30);
  insert into public.item_recipes (item_code, good_id, qty)
  select w.item_code, g.id, w.qty from (values
    ('storm-canvas', 'canvas-duck', 4),
    ('storm-canvas', 'cordage', 2),
    ('storm-canvas', 'tar', 1),
    ('studding-sails', 'sailcloth', 5),
    ('studding-sails', 'norway-spruce', 2),
    ('studding-sails', 'cordage', 3),
    ('whipstaff', 'timber', 3),
    ('whipstaff', 'iron', 1),
    ('whipstaff', 'hemp', 1),
    ('binnacle-and-charts', 'sea-charts', 2),
    ('binnacle-and-charts', 'brass-ingots', 1),
    ('binnacle-and-charts', 'lignum-vitae', 1),
    ('sheet-anchor', 'iron', 6),
    ('sheet-anchor', 'hemp', 6),
    ('sheet-anchor', 'tar', 1),
    ('capstan', 'live-oak', 3),
    ('capstan', 'iron', 2),
    ('capstan', 'tallow', 1),
    ('bilge-pumps', 'timber', 3),
    ('bilge-pumps', 'lead', 2),
    ('bilge-pumps', 'hides', 1),
    ('doubled-planking', 'live-oak', 6),
    ('doubled-planking', 'ships-nails', 4),
    ('doubled-planking', 'oakum', 2),
    ('doubled-planking', 'pine-pitch', 1),
    ('swivel-guns', 'bar-iron', 3),
    ('swivel-guns', 'timber', 1),
    ('swivel-guns', 'shot-and-ball', 1),
    ('stern-chasers', 'culverin', 2),
    ('stern-chasers', 'live-oak', 2),
    ('stern-chasers', 'shot-and-ball', 2),
    ('carronades', 'bar-iron', 8),
    ('carronades', 'brass-ingots', 2),
    ('carronades', 'gunpowder', 2),
    ('topgallant-mast', 'riga-mast', 2),
    ('topgallant-mast', 'cordage', 3),
    ('topgallant-mast', 'tar', 1)) w(item_code, good_code, qty) join public.goods g on g.code = w.good_code;
  insert into public.item_level_asks (item_code, min_level) values
    ('studding-sails', 4),
    ('binnacle-and-charts', 3),
    ('sheet-anchor', 2),
    ('capstan', 3),
    ('doubled-planking', 3),
    ('stern-chasers', 4),
    ('carronades', 5),
    ('topgallant-mast', 3);
  -- </generated:0129>

  -- ── 4. THE HUNKS (old = verbatim from the live bodies; new = what replaces it) ───────────────
  create temp table hunks_0129 (fn text, n int, old text, new text);
  insert into hunks_0129 values
  ('cmd.do_build(uuid, jsonb)', 1,
$h$  v_ship   uuid;
  r        record;
begin
$h$,
$h$  v_ship   uuid;
  r        record;
  v_region text;   -- 0129: the yard's region code
  v_lvl    int;    -- 0129: the house's trading level, read only while levels_bite is on
begin
$h$),
  ('cmd.do_build(uuid, jsonb)', 2,
$h$      c.name, h.yard_tier, v_tier using errcode = 'P0001';
  end if;
$h$,
$h$      c.name, h.yard_tier, v_tier using errcode = 'P0001';
  end if;

  -- 0129: THE COAST. A hull with yard_regions is laid down only by a yard in one of them — a dhow or a
  -- junk in the East, a fluyt in the North, a xebec in the Mediterranean. Null = any yard of her tier.
  if h.yard_regions is not null then
    select rg.code into v_region
      from public.ports p join public.regions rg on rg.id = p.region_id where p.id = f.port_id;
    if v_region is null or not (v_region = any (h.yard_regions)) then
      perform cmd.refuse('E_WRONG_COAST',
        format('a %s is laid down only in %s, and this yard is in %s', c.name,
               (select string_agg(rg.name, ', ' order by rg.name) from public.regions rg where rg.code = any (h.yard_regions)),
               coalesce((select rg.name from public.regions rg where rg.code = v_region), 'no region')));
    end if;
  end if;
  -- 0129: THE HOUSE'S TRADING LEVEL she asks (hull_recipes.min_level) — only while levels_bite is on.
  if h.min_level > 1 and public.levels_bite_on() then
    v_lvl := coalesce((public.player_progress(f.player_id)->'trading'->>'level')::int, 1);
    if v_lvl < h.min_level then
      perform cmd.refuse('E_LEVEL',
        format('a %s is laid down for a house of trading level %s, and yours is level %s', c.name, h.min_level, v_lvl),
        cmd.figures(v_lvl, h.min_level, 'level'));
    end if;
  end if;
$h$),
  ('world.building_yard(uuid)', 1,
$h$   where b.port_id = p_port and b.kind = 'building_yard';

  return jsonb_build_object(
$h$,
$h$   where b.port_id = p_port and b.kind = 'building_yard';
  -- 0129: the yard's coast, and (only while levels_bite is on) your trading level — the two rules
  -- cmd.do_build added, read here so the screen says why not rather than working it out.
  select rg.code into v_region
    from public.ports p join public.regions rg on rg.id = p.region_id where p.id = p_port;
  if v_player is not null and public.levels_bite_on() then
    v_lvl := coalesce((public.player_progress(v_player)->'trading'->>'level')::int, 1);
  end if;

  return jsonb_build_object(
$h$),
  ('world.building_yard(uuid)', 2,
$h$  v_tier   int;
begin
$h$,
$h$  v_tier   int;
  v_region text;   -- 0129
  v_lvl    int;    -- 0129: null while levels_bite is off, or for no viewer
begin
$h$),
  ('world.building_yard(uuid)', 3,
$h$        'buildable', v_tier is not null and v_tier >= h.yard_tier,
$h$,
$h$        'buildable', v_tier is not null and v_tier >= h.yard_tier
                     -- 0129: and on her coast, and (lit) at your trading level.
                     and (h.yard_regions is null or coalesce(v_region = any (h.yard_regions), false))
                     and (v_lvl is null or v_lvl >= h.min_level),
        -- 0129: the regions that lay her down (names; null = any yard of her tier), whether this yard is
        -- one, the trading level she asks, and yours (null while levels_bite is off).
        'coast', case when h.yard_regions is not null then
                   (select jsonb_agg(rg.name order by rg.name) from public.regions rg where rg.code = any (h.yard_regions)) end,
        'on_coast', h.yard_regions is null or coalesce(v_region = any (h.yard_regions), false),
        'min_level', h.min_level,
        'your_level', v_lvl,
$h$);

  for v_fn in select fn from defs_before_0129 order by fn loop
    v_def := (select def from defs_before_0129 where fn = v_fn);
    for hk in select * from hunks_0129 where fn = v_fn order by n loop
      v_n := (length(v_def) - length(replace(v_def, hk.old, ''))) / length(hk.old);
      if v_n <> 1 then
        raise exception '0129 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
          hk.n, v_fn, v_n;
      end if;
      v_def := replace(v_def, hk.old, hk.new);
    end loop;
    execute v_def;
  end loop;

  -- ── 5. SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
  -- (a) PARITY BY REVERSE SUBSTITUTION; ACLs unmoved; each hunk in its new body exactly once.
  for v_fn in select fn from defs_before_0129 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for hk in select * from hunks_0129 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, hk.new, ''))) / length(hk.new);
      if v_n <> 1 then
        raise exception '0129 self-assert FAIL: hunk % of % is in the new body % time(s), not once', hk.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, hk.new, hk.old);
    end loop;
    if v_back <> (select def from defs_before_0129 where fn = v_fn) or v_def = v_back then
      raise exception '0129 self-assert FAIL: % is not its pre-image plus only 0129''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0129 where fn = v_fn) then
      raise exception '0129 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) NOTHING AN EARLIER FILE PUT IN MOVED: every pre-existing catalogue row is byte-equal (the
  --     hull recipes compared without the two new columns, which read null / 1 on all three).
  select string_agg(b.t, ', ') into v_txt
    from catalogue_before_0129 b
   where b.rows is distinct from case b.t
     when 'ship_classes' then (select string_agg((to_jsonb(c) - 'id')::text, '|' order by c.code) from public.ship_classes c where c.code <> all (c_new_cls))
     when 'class_slots' then (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.slot) from public.class_slots x where x.class_code <> all (c_new_cls))
     when 'class_cabins' then (select string_agg(to_jsonb(x)::text, '|' order by x.class_code) from public.class_cabins x where x.class_code <> all (c_new_cls))
     when 'class_slot_unlocks' then (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.slot, x.min_level) from public.class_slot_unlocks x where x.class_code <> all (c_new_cls))
     when 'hull_recipes' then (select string_agg((to_jsonb(x) - 'yard_regions' - 'min_level')::text, '|' order by x.class_code) from public.hull_recipes x where x.class_code <> all (c_new_cls))
     when 'hull_recipe_goods' then (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.good_id) from public.hull_recipe_goods x where x.class_code <> all (c_new_cls))
     when 'hull_recipe_items' then (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.item_code) from public.hull_recipe_items x where x.class_code <> all (c_new_cls))
     when 'item_kinds' then (select string_agg(to_jsonb(x)::text, '|' order by x.code) from public.item_kinds x where x.code <> all (c_new_gear))
     when 'item_effects' then (select string_agg(to_jsonb(x)::text, '|' order by x.item_code, x.stat) from public.item_effects x where x.item_code <> all (c_new_gear))
     when 'item_recipes' then (select string_agg(to_jsonb(x)::text, '|' order by x.item_code, x.good_id) from public.item_recipes x where x.item_code <> all (c_new_gear))
     when 'item_level_asks' then (select string_agg(to_jsonb(x)::text, '|' order by x.item_code) from public.item_level_asks x where x.item_code <> all (c_new_gear))
     when 'npc_loadouts' then (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.pattern, x.item_code) from public.npc_loadouts x)
   end;
  if v_txt is not null then
    raise exception '0129 self-assert FAIL: an earlier file''s rows moved in %', v_txt;
  end if;
  if exists (select 1 from public.hull_recipes where class_code <> all (c_new_cls) and (yard_regions is not null or min_level <> 1)) then
    raise exception '0129 self-assert FAIL: a hull a player can build today asks a coast or a level';
  end if;

  -- (c) THE ELEVEN CLASSES: all eight landed with slots, cabins and a recipe; guns = attack/10 for
  --     every class (S4's no-op); slots grow with the tier at level 1 — every tier-2 hull carries more
  --     than every tier-1, every tier-3 more than every tier-2; cabins 3 / 4 / 5 by tier.
  if (select count(*) from public.ship_classes) <> 11
     or (select count(*) from public.ship_classes where code = any (c_new_cls)) <> 8 then
    raise exception '0129 self-assert FAIL: % ship class(es), expected 11 with all eight new', (select count(*) from public.ship_classes);
  end if;
  if exists (select 1 from public.ship_classes where guns * 10 <> attack) then
    raise exception '0129 self-assert FAIL: a class''s guns is not attack/10 — S4''s escort re-cut would move it';
  end if;
  select count(*) into v_bad from public.ship_classes c
   where not exists (select 1 from public.class_slots s where s.class_code = c.code)
      or not exists (select 1 from public.class_cabins k where k.class_code = c.code and k.cabins = c.tier + 2)
      or not exists (select 1 from public.hull_recipes r where r.class_code = c.code);
  if v_bad <> 0 then
    raise exception '0129 self-assert FAIL: % class(es) lack slots, cabins for their tier or a recipe', v_bad;
  end if;
  if exists (
    with t as (select c.tier, sum(s.count) as total from public.ship_classes c join public.class_slots s on s.class_code = c.code group by c.code, c.tier)
    select 1 from t a, t b where b.tier = a.tier + 1 and b.total <= a.total) then
    raise exception '0129 self-assert FAIL: a hull of a higher tier carries no more fittings than one of the tier below';
  end if;
  if exists (select 1 from public.class_slot_unlocks u
              where not exists (select 1 from public.ship_classes c where c.code = u.class_code))
     or (select count(*) from public.class_slot_unlocks where class_code = any (c_new_cls)) <> 11 then
    raise exception '0129 self-assert FAIL: the eight classes'' level unlocks are not the eleven of §6.2';
  end if;

  -- (d) 0072 OVER ALL ELEVEN HULLS: (a) timber AND fittings; (b) every material sold somewhere and
  --     every fitting makeable somewhere; (c) every hull has a real yard — of her tier AND on her
  --     coast; (d) she fits in the shed of EVERY yard that may lay her down.
  select count(*) into v_bad from public.hull_recipes h
   where not exists (select 1 from public.hull_recipe_goods g where g.class_code = h.class_code)
      or not exists (select 1 from public.hull_recipe_items i where i.class_code = h.class_code);
  if v_bad <> 0 or (select count(*) from public.hull_recipes) <> 11 then
    raise exception '0129 self-assert FAIL: % hull(s) are not timber AND fittings (or not 11 recipes)', v_bad;
  end if;
  select count(*) into v_bad from public.hull_recipe_goods hg
   where not exists (select 1 from public.port_goods pg join public.ports p on p.id = pg.port_id
                      where pg.good_id = hg.good_id and public.port_offers(p.id, hg.good_id));
  if v_bad <> 0 then
    raise exception '0129 self-assert FAIL: % hull material(s) are sold in NO city', v_bad;
  end if;
  select count(*) into v_bad from public.hull_recipe_items hi join public.item_kinds k on k.code = hi.item_code
   where not exists (select 1 from public.port_buildings b where b.kind = 'workstation' and b.tier >= k.ws_tier);
  if v_bad <> 0 then
    raise exception '0129 self-assert FAIL: % hull fitting(s) can be made in no city', v_bad;
  end if;
  select string_agg(h.class_code, ', ') into v_txt from public.hull_recipes h
   where not exists (select 1 from public.port_buildings b join public.ports p on p.id = b.port_id
                       join public.regions rg on rg.id = p.region_id
                      where b.kind = 'building_yard' and b.tier >= h.yard_tier
                        and (h.yard_regions is null or rg.code = any (h.yard_regions)));
  if v_txt is not null then
    raise exception '0129 self-assert FAIL: no yard in the world may lay down %', v_txt;
  end if;
  select string_agg(x.class_code, ', ') into v_txt from (
    select h.class_code, sum(hg.qty * g.bulk) as tuns
      from public.hull_recipes h
      join public.hull_recipe_goods hg on hg.class_code = h.class_code
      join public.goods g on g.id = hg.good_id
     group by h.class_code) x
   where x.tuns > (select min(public.storage_cap(b.port_id))
                     from public.port_buildings b join public.ports p on p.id = b.port_id
                     join public.regions rg on rg.id = p.region_id
                     join public.hull_recipes h on h.class_code = x.class_code
                    where b.kind = 'building_yard' and b.tier >= h.yard_tier
                      and (h.yard_regions is null or rg.code = any (h.yard_regions)));
  if v_txt is not null then
    raise exception '0129 self-assert FAIL: % want(s) more timber than a yard that may build her can store', v_txt;
  end if;

  -- (e) 0068 AND 0074 OVER ALL TWENTY-FOUR FITTINGS: 2-5 inputs; no dead ingredient; makeable
  --     somewhere; every one buys a stat and spends one (the figurehead the one exception); every one
  --     has a slot some hull carries; the eight level asks of §7.
  if (select count(*) from public.item_kinds) <> 24 then
    raise exception '0129 self-assert FAIL: % fitting kind(s), expected 24', (select count(*) from public.item_kinds);
  end if;
  select count(*) into v_bad from (select item_code, count(*) c from public.item_recipes group by item_code) x where x.c < 2 or x.c > 5;
  if v_bad <> 0 or exists (select 1 from public.item_kinds k where not exists (select 1 from public.item_recipes r where r.item_code = k.code)) then
    raise exception '0129 self-assert FAIL: % recipe(s) are not 2-5 inputs (or a fitting has none)', v_bad;
  end if;
  select string_agg(distinct g.code, ', ') into v_txt
    from public.item_recipes ir join public.goods g on g.id = ir.good_id
   where not exists (select 1 from public.port_goods pg join public.ports p on p.id = pg.port_id
                      where pg.good_id = ir.good_id and public.port_offers(p.id, ir.good_id));
  if v_txt is not null then
    raise exception '0129 self-assert FAIL: fitting material(s) sold in no city: %', v_txt;
  end if;
  select count(*) into v_bad from public.item_kinds k
   where not exists (select 1 from public.port_buildings b where b.kind = 'workstation' and b.tier >= k.ws_tier);
  if v_bad <> 0 then
    raise exception '0129 self-assert FAIL: % fitting(s) can be made in no city', v_bad;
  end if;
  select count(*) into v_bad from public.item_kinds k
   where k.code <> 'figurehead'
     and not (exists (select 1 from public.item_effects e where e.item_code = k.code and e.delta > 0)
          and exists (select 1 from public.item_effects e where e.item_code = k.code and e.delta < 0));
  if v_bad <> 0 or exists (select 1 from public.item_effects where item_code = 'figurehead') then
    raise exception '0129 self-assert FAIL: % fitting(s) buy a stat without spending one (or the figurehead costs one)', v_bad;
  end if;
  select count(*) into v_bad from public.item_kinds k
   where not exists (select 1 from public.class_slots cs where cs.slot = k.slot);
  if v_bad <> 0 then
    raise exception '0129 self-assert FAIL: % fitting(s) fit no hull in the world', v_bad;
  end if;
  if (select count(*) from public.item_level_asks where item_code = any (c_new_gear)) <> 8
     or exists (select 1 from public.item_level_asks where item_code <> all (c_new_gear)) then
    raise exception '0129 self-assert FAIL: the level asks are not the eight of §7 (and only them)';
  end if;

  -- (f) MERCHANTS: THE NEW CLASSES ARE PLAYER-ONLY. No merchant sails one; every class a merchant
  --     sails has an authored loadout; none of the eight has one (npc_fit_loadout's E_NO_LOADOUT is
  --     then the rule for a merchant founded in one, not an accident).
  if exists (select 1 from public.ships s join public.ship_classes c on c.id = s.class_id where c.code = any (c_new_cls)) then
    raise exception '0129 self-assert FAIL: a hull of a new class already sails';
  end if;
  if exists (select 1 from public.ships s join public.players p on p.id = s.player_id and p.is_npc
               join public.ship_classes c on c.id = s.class_id
              where not exists (select 1 from public.npc_loadouts l where l.class_code = c.code))
     or exists (select 1 from public.npc_loadouts where class_code = any (c_new_cls)) then
    raise exception '0129 self-assert FAIL: a merchant sails a class with no loadout, or a new class has one';
  end if;

  -- (g) THE YARD SCREEN, FOR THE THREE HULLS OF TODAY, IS ITS PRE-IMAGE at every yard in the world
  --     (the four new keys stripped); every yard now serves eleven.
  select count(*) into v_bad
    from yards_before_0129 yb
   cross join lateral (select world.building_yard(yb.port_id) as now_view) n
   where jsonb_array_length(n.now_view->'hulls') <> 11
      or (select jsonb_agg(x - c_yard_new order by x->>'class') from jsonb_array_elements(n.now_view->'hulls') x
           where x->>'class' <> all (c_new_cls))
         is distinct from (select jsonb_agg(x order by x->>'class') from jsonb_array_elements(yb.view->'hulls') x)
      or (n.now_view - 'hulls') is distinct from (yb.view - 'hulls');
  if v_bad <> 0 or (select count(*) from yards_before_0129) = 0 then
    raise exception '0129 self-assert FAIL: % yard(s) serve today''s hulls differently (or there are no yards)', v_bad;
  end if;

  -- (h) POSTURE: no new entry point, no client write, the catalogue's private tables stay private.
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from posture_before_0129)
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or has_table_privilege('authenticated', 'public.item_level_asks', 'select')
     or has_table_privilege('authenticated', 'public.class_slot_unlocks', 'select')
     or has_function_privilege('authenticated', 'cmd.do_build(uuid, jsonb)', 'execute') then
    raise exception '0129 self-assert FAIL: the registry, the grant wall or the read wall';
  end if;

  -- (i) THE PROBES — a probe house of its own, never a live fleet, merchant or market row; rolled back.
  select b.port_id into v_west from public.port_buildings b join public.ports p on p.id = b.port_id
    join public.regions rg on rg.id = p.region_id
   where b.kind = 'building_yard' and rg.code not in (select unnest(yard_regions) from public.hull_recipes where class_code = 'junk')
   order by b.tier desc, p.code limit 1;
  select b.port_id into v_east from public.port_buildings b join public.ports p on p.id = b.port_id
    join public.regions rg on rg.id = p.region_id
   where b.kind = 'building_yard' and rg.code in (select unnest(yard_regions) from public.hull_recipes where class_code = 'junk')
     and b.tier >= (select yard_tier from public.hull_recipes where class_code = 'junk')
     and rg.code not in (select unnest(yard_regions) from public.hull_recipes where class_code = 'fluyt')
   order by p.code limit 1;
  select b.port_id into v_great from public.port_buildings b join public.ports p on p.id = b.port_id
   where b.kind = 'building_yard' and b.tier >= 3 order by p.code limit 1;
  select b.port_id into v_ws2 from public.port_buildings b join public.ports p on p.id = b.port_id
   where b.kind = 'workstation' and b.tier >= 2 order by p.code limit 1;
  if v_west is null or v_east is null or v_great is null or v_ws2 is null then
    raise exception '0129 self-assert FAIL: the probe found no western yard, eastern yard, great yard or tier-2 workstation';
  end if;

  begin
    v_player := public.new_house(c_uid, 'Casa do Estaleiro Novo', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    select id into v_barca from public.ships where fleet_id = v_fleet;
    perform public.credit(v_player, 'PROBE_0129', 2000000);
    perform cmd.assume_identity(c_uid);

    -- A JUNK IS REFUSED IN THE WEST, by her coast and in words.
    update public.fleets set port_id = v_west where id = v_fleet;
    v_err := null;
    begin
      perform cmd.do_build(v_fleet, jsonb_build_object('class', 'junk', 'name', 'Junco Errado'));
    exception when sqlstate 'P0001' then v_err := sqlerrm;
    end;
    if v_err is null or v_err not like 'E_WRONG_COAST: a Junk is laid down only in %' then
      raise exception '0129 self-assert FAIL: a junk at a western yard was not refused E_WRONG_COAST (%)', v_err;
    end if;
    v_yard := world.building_yard(v_west);
    if (select (x->>'on_coast')::boolean or (x->>'buildable')::boolean
          from jsonb_array_elements(v_yard->'hulls') x where x->>'class' = 'junk') then
      raise exception '0129 self-assert FAIL: a western yard serves the junk as buildable here';
    end if;

    -- AND LAID DOWN IN THE EAST, end to end: the shed and the store empty, the yard paid its labour.
    update public.fleets set port_id = v_east where id = v_fleet;
    insert into public.player_storage (player_id, port_id, good_id, qty)
    select v_player, v_east, hg.good_id, hg.qty from public.hull_recipe_goods hg where hg.class_code = 'junk';
    insert into public.player_items (player_id, port_id, item_code, qty)
    select v_player, v_east, hi.item_code, hi.qty from public.hull_recipe_items hi where hi.class_code = 'junk';
    v_yard := world.building_yard(v_east);
    if not (select (x->>'on_coast')::boolean and (x->>'buildable')::boolean
              from jsonb_array_elements(v_yard->'hulls') x where x->>'class' = 'junk')
       or (select (x->>'on_coast')::boolean or (x->>'buildable')::boolean
             from jsonb_array_elements(v_yard->'hulls') x where x->>'class' = 'fluyt') then
      raise exception '0129 self-assert FAIL: an eastern yard does not serve the junk buildable and the fluyt off her coast';
    end if;
    select ducats into v_purse from public.players where id = v_player;
    v_res := cmd.do_build(v_fleet, jsonb_build_object('class', 'junk', 'name', 'Junco Probado'));
    v_junk := (v_res->>'ship')::uuid;
    if (select c.code from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = v_junk) is distinct from 'junk'
       or exists (select 1 from public.player_storage where player_id = v_player and port_id = v_east and qty > 0)
       or exists (select 1 from public.player_items where player_id = v_player and port_id = v_east and qty > 0)
       or v_purse - (select ducats from public.players where id = v_player) <> (select ducats from public.hull_recipes where class_code = 'junk') then
      raise exception '0129 self-assert FAIL: the junk was not laid down from her shed, her store and her labour (%)', v_res;
    end if;

    -- A GALLEON ASKS TRADING LEVEL 5 — refused E_LEVEL with figures ONLY while levels_bite is on.
    update public.fleets set port_id = v_great where id = v_fleet;
    v_err := null;
    begin
      perform cmd.do_build(v_fleet, jsonb_build_object('class', 'galleon', 'name', 'Galeao Escuro'));
    exception when sqlstate 'P0001' then v_err := sqlerrm;
    end;
    if v_err is null or v_err not like 'E_NO_TIMBER:%' then
      raise exception '0129 self-assert FAIL: dark, a galleon at a great yard was refused % rather than for her timber', v_err;
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'levels_bite';
    v_err := null;
    begin
      perform cmd.do_build(v_fleet, jsonb_build_object('class', 'galleon', 'name', 'Galeao Aceso'));
    exception when sqlstate 'P0001' then
      v_err := sqlerrm;
      get stacked diagnostics v_detail = pg_exception_detail;
    end;
    if v_err is null or v_err not like 'E_LEVEL:%' or v_detail::jsonb <> '{"have": 1, "need": 5, "unit": "level"}'::jsonb then
      raise exception '0129 self-assert FAIL: lit, a galleon was not refused E_LEVEL with figures (% / %)', v_err, v_detail;
    end if;
    v_yard := world.building_yard(v_great);
    if (select (x->>'buildable')::boolean or (x->>'your_level')::int <> 1 or (x->>'min_level')::int <> 5
          from jsonb_array_elements(v_yard->'hulls') x where x->>'class' = 'galleon')
       or not (select (x->>'buildable')::boolean from jsonb_array_elements(v_yard->'hulls') x where x->>'class' = 'nau') then
      raise exception '0129 self-assert FAIL: lit, the great yard does not serve the galleon refused at level 1 and the nau open';
    end if;
    update public.world_config set value = 'false'::jsonb where key = 'levels_bite';

    -- SWIVEL GUNS ARE MADE AT A TIER-2 WORKSTATION AND GO IN A BARCA'S ONE WEAPON SLOT.
    update public.fleets set port_id = v_ws2 where id = v_fleet;
    perform public.fleet_load(v_fleet, g.code, ir.qty, 1)
       from public.item_recipes ir join public.goods g on g.id = ir.good_id where ir.item_code = 'swivel-guns';
    perform cmd.do_make(v_fleet, jsonb_build_object('item', 'swivel-guns'));
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'swivel-guns', 'ship',
                                                   (select name from public.ships where id = v_barca)));
    if (select qty from public.ship_fittings where ship_id = v_barca and item_code = 'swivel-guns') is distinct from 1
       or (world.ship_stats(v_barca)->>'attack')::numeric <> 20 or (world.ship_stats(v_barca)->>'accuracy')::numeric <> 8 then
      raise exception '0129 self-assert FAIL: swivel guns were not made and mounted on a barca as authored (%)', world.ship_stats(v_barca);
    end if;

    -- CARRONADES ASK A LEVEL-5 SHIP: dark they go on a level-1 junk; lit they are refused
    -- E_SHIP_LEVEL with figures, and go on once she is level 5.
    insert into public.player_items (player_id, port_id, item_code, qty) values (v_player, v_ws2, 'carronades', 1);
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'carronades', 'ship', 'Junco Probado'));
    perform cmd.do_unfit(v_fleet, jsonb_build_object('item', 'carronades', 'ship', 'Junco Probado'));
    update public.world_config set value = 'true'::jsonb where key = 'levels_bite';
    v_err := null;
    begin
      perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'carronades', 'ship', 'Junco Probado'));
    exception when sqlstate 'P0001' then
      v_err := sqlerrm;
      get stacked diagnostics v_detail = pg_exception_detail;
    end;
    if v_err is null or v_err not like 'E_SHIP_LEVEL:%' or v_detail::jsonb <> '{"have": 1, "need": 5, "unit": "level"}'::jsonb then
      raise exception '0129 self-assert FAIL: lit, carronades on a level-1 hull were not refused E_SHIP_LEVEL with figures (% / %)', v_err, v_detail;
    end if;
    insert into public.ship_xp (ship_id, xp) values (v_junk, public.level_points(5));
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'carronades', 'ship', 'Junco Probado'));
    if (world.ship_stats(v_junk)->>'attack')::numeric
       <> (select attack from public.ship_classes where code = 'junk') + 90 then
      raise exception '0129 self-assert FAIL: a level-5 junk did not mount carronades as authored (%)', world.ship_stats(v_junk);
    end if;

    raise exception 'ROLLBACK_0129';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0129' then raise; end if;
  end;
  if exists (select 1 from public.players where auth_uid = c_uid) or public.levels_bite_on() then
    raise exception '0129 self-assert FAIL: the probe world was not rolled back';
  end if;

  drop table defs_before_0129, hunks_0129, catalogue_before_0129, yards_before_0129, posture_before_0129;

  raise notice '0129 self-assert ok: MORE HULLS AND MORE GEAR. Eleven ship classes (pinnace, dhow, caravela redonda, fluyt, xebec, junk, galleon, East Indiaman added) with guns = attack/10 for every one, slots that grow with the tier, cabins by tier and eleven new level unlocks; eleven hull recipes, each timber AND fittings, every material sold somewhere, every hull with a real yard of her tier on her coast and fitting its shed. Twenty-four fittings, each 2-5 inputs sold somewhere, makeable somewhere, buying one stat and spending another, with a slot to go in; eight ask a ship level. Nothing an earlier file put in moved; every yard serves today''s three hulls exactly as before. cmd.do_build and world.building_yard reverse to their pre-images by their hunks, ACLs unmoved. The new classes are player-only: no merchant sails one and none has a loadout. Probe (rolled back): a junk refused E_WRONG_COAST in the west and laid down in the east from her shed, store and labour; a galleon refused E_LEVEL {1/5} only while lit; swivel guns made at a tier-2 workstation and mounted on a barca; carronades refused E_SHIP_LEVEL {1/5} lit and mounted on a level-5 junk. % ms. No new entry point, no client write.',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m0129$;

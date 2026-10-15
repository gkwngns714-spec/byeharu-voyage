-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0129 — TWELVE MORE FITTINGS  (docs/SHIPS_AND_GEAR.md §7 S6, §8 S7)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-15, queue item 3: *"make more ship types and more gear"*. The ship types (S5) are held:
-- the owner is redesigning hulls EVE-style (class × tier × country of origin), so this file adds
-- GEAR ONLY and touches no ship class, slot, yard or recipe of a hull.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) TWELVE NEW FITTINGS (S6), twenty-four in all — storm canvas, studding sails, whipstaff,
--     binnacle & charts, sheet anchor, capstan, bilge pumps, doubled planking, swivel guns, stern
--     chasers, carronades, topgallant mast: item_kinds, item_effects (each buys one stat and spends
--     another), item_recipes (2-5 goods, every one sold somewhere; made at a workstation of the
--     kind's ws_tier), and the SHIP level eight of them ask (public.item_level_asks, 0127's table:
--     public.mount_fitting refuses E_SHIP_LEVEL only while levels_bite is on — dark today).
--     Gear changes no combat: nothing reads attack, armour, accuracy, reach or sighting until S4.
-- (2) S7: scripts/db/world-guard.mjs now holds ship_classes, class_slots, class_cabins,
--     class_slot_unlocks, hull_recipes (+ goods, items), item_kinds, item_effects, item_recipes,
--     item_level_asks and npc_loadouts EQUAL to data/ship_stats.json, data/hulls.json,
--     data/fittings.json and data/npc-loadouts.json on every apply (positive control first). The
--     rows below are generated from data/fittings.json by scripts/build-gear-0129.mjs.
--
-- ── MERCHANTS ───────────────────────────────────────────────────────────────────────────────────
-- Unchanged. Their loadouts (0126) name only the twelve fittings of before; no merchant gains or
-- loses anything, and the self-assert proves npc_loadouts is byte-equal.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- lock_timeout 5 s. Only INSERTs into the catalogue tables (ROW EXCLUSIVE; reads go on) and the KEY
-- SHARE their FKs take on goods / item_kinds rows. No ALTER, no function re-cut. ships, fleets,
-- voyages and every table the arrivals tick writes are never written or locked: the probe writes
-- only its own house's rows and rolls back. No LOCK TABLE, no set role, no begin/commit. THE WHOLE
-- FILE IS ONE `do` BLOCK, so it is atomic however the runner groups statements.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- One forward migration deleting the twelve item_kinds (cascades to effects, recipes, level asks)
-- after asserting no ship_fittings, player_items or hull_recipe_items row references them.
--
-- No new entry point, no client write, no cron, nothing in the arrivals tick.
-- VERSION: 0129, on production head 0128.

do $m0129$
declare
  v_bad      int;
  v_txt      text;
  v_player   uuid;
  v_fleet    uuid;
  v_barca    uuid;
  v_ws2      uuid;
  v_err      text;
  v_detail   text;
  v_t0       timestamptz := clock_timestamp();
  c_uid      constant uuid := '00000000-0129-4000-8000-000000000001';
  c_new_gear constant text[] := array['storm-canvas', 'studding-sails', 'whipstaff', 'binnacle-and-charts', 'sheet-anchor',
                                      'capstan', 'bilge-pumps', 'doubled-planking', 'swivel-guns', 'stern-chasers',
                                      'carronades', 'topgallant-mast'];
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 1. THE PRE-IMAGES ────────────────────────────────────────────────────────────────────────
  -- Plain temp tables (not ON COMMIT DROP): they live as long as this block needs them however the
  -- runner groups statements, and are dropped at its end.
  create temp table catalogue_before_0129 as
  select 'ship_classes' as t, (select string_agg((to_jsonb(c) - 'id')::text, '|' order by c.code) from public.ship_classes c) as rows
  union all select 'class_slots', (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.slot) from public.class_slots x)
  union all select 'hull_recipes', (select string_agg(to_jsonb(x)::text, '|' order by x.class_code) from public.hull_recipes x)
  union all select 'hull_recipe_items', (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.item_code) from public.hull_recipe_items x)
  union all select 'item_kinds', (select string_agg(to_jsonb(x)::text, '|' order by x.code) from public.item_kinds x)
  union all select 'item_effects', (select string_agg(to_jsonb(x)::text, '|' order by x.item_code, x.stat) from public.item_effects x)
  union all select 'item_recipes', (select string_agg(to_jsonb(x)::text, '|' order by x.item_code, x.good_id) from public.item_recipes x)
  union all select 'item_level_asks', (select string_agg(to_jsonb(x)::text, '|' order by x.item_code) from public.item_level_asks x)
  union all select 'npc_loadouts', (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.pattern, x.item_code) from public.npc_loadouts x);

  create temp table posture_before_0129 as
  select (select count(*) from public.client_rpc_entry_points()) as entry_points;

  if exists (select 1 from public.item_kinds where code = any (c_new_gear)) then
    raise exception '0129 self-assert FAIL: a new fitting is already in the world — this file was cut against a world without them';
  end if;

  -- ── 2. THE ROWS (S6) ─────────────────────────────────────────────────────────────────────────
  -- <generated:0129> by scripts/build-gear-0129.mjs from data/fittings.json.
  -- Do not edit by hand: change the data and re-run the script.
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

  -- ── 3. SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
  -- (a) NOTHING AN EARLIER FILE PUT IN MOVED — every ship and every fitting of before, byte-equal.
  select string_agg(b.t, ', ') into v_txt
    from catalogue_before_0129 b
   where b.rows is distinct from case b.t
     when 'ship_classes' then (select string_agg((to_jsonb(c) - 'id')::text, '|' order by c.code) from public.ship_classes c)
     when 'class_slots' then (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.slot) from public.class_slots x)
     when 'hull_recipes' then (select string_agg(to_jsonb(x)::text, '|' order by x.class_code) from public.hull_recipes x)
     when 'hull_recipe_items' then (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.item_code) from public.hull_recipe_items x)
     when 'item_kinds' then (select string_agg(to_jsonb(x)::text, '|' order by x.code) from public.item_kinds x where x.code <> all (c_new_gear))
     when 'item_effects' then (select string_agg(to_jsonb(x)::text, '|' order by x.item_code, x.stat) from public.item_effects x where x.item_code <> all (c_new_gear))
     when 'item_recipes' then (select string_agg(to_jsonb(x)::text, '|' order by x.item_code, x.good_id) from public.item_recipes x where x.item_code <> all (c_new_gear))
     when 'item_level_asks' then (select string_agg(to_jsonb(x)::text, '|' order by x.item_code) from public.item_level_asks x where x.item_code <> all (c_new_gear))
     when 'npc_loadouts' then (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.pattern, x.item_code) from public.npc_loadouts x)
   end;
  if v_txt is not null then
    raise exception '0129 self-assert FAIL: an earlier file''s rows moved in %', v_txt;
  end if;

  -- (b) 0068 AND 0074 OVER ALL TWENTY-FOUR: 2-5 inputs; no dead ingredient; makeable somewhere;
  --     each buys a stat and spends one (the figurehead the one exception); each has a slot some
  --     hull carries; the eight level asks of §7 and only them.
  if (select count(*) from public.item_kinds) <> 24
     or (select count(*) from public.item_kinds where code = any (c_new_gear)) <> 12 then
    raise exception '0129 self-assert FAIL: % fitting kind(s), expected 24 with all twelve new', (select count(*) from public.item_kinds);
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

  -- (c) POSTURE: no new entry point, no client write, the level asks stay private.
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from posture_before_0129)
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or has_table_privilege('authenticated', 'public.item_level_asks', 'select') then
    raise exception '0129 self-assert FAIL: the registry, the grant wall or the read wall';
  end if;

  -- (d) THE PROBES — a probe house of its own, never a live fleet, merchant or market row; rolled back.
  select b.port_id into v_ws2 from public.port_buildings b join public.ports p on p.id = b.port_id
   where b.kind = 'workstation' and b.tier >= 2 order by p.code limit 1;
  if v_ws2 is null then
    raise exception '0129 self-assert FAIL: the probe found no tier-2 workstation';
  end if;

  begin
    v_player := public.new_house(c_uid, 'Casa da Oficina Nova', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    select id into v_barca from public.ships where fleet_id = v_fleet;
    perform public.credit(v_player, 'PROBE_0129', 1000000);
    update public.fleets set port_id = v_ws2 where id = v_fleet;
    if (select c.code from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = v_barca) <> 'barca' then
      raise exception '0129 self-assert FAIL: the probe house''s hull is not a barca';
    end if;

    -- CARRONADES ASK A LEVEL-5 SHIP: dark they go on a level-1 barca; lit they are refused
    -- E_SHIP_LEVEL with figures, and go on once she is level 5.
    insert into public.player_items (player_id, port_id, item_code, qty) values (v_player, v_ws2, 'carronades', 1);
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'carronades'));
    perform cmd.do_unfit(v_fleet, jsonb_build_object('item', 'carronades'));
    update public.world_config set value = 'true'::jsonb where key = 'levels_bite';
    v_err := null;
    begin
      perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'carronades'));
    exception when sqlstate 'P0001' then
      v_err := sqlerrm;
      get stacked diagnostics v_detail = pg_exception_detail;
    end;
    if v_err is null or v_err not like 'E_SHIP_LEVEL:%' or v_detail::jsonb <> '{"have": 1, "need": 5, "unit": "level"}'::jsonb then
      raise exception '0129 self-assert FAIL: lit, carronades on a level-1 hull were not refused E_SHIP_LEVEL with figures (% / %)', v_err, v_detail;
    end if;
    insert into public.ship_xp (ship_id, xp) values (v_barca, public.level_points(5))
    on conflict (ship_id) do update set xp = excluded.xp;
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'carronades'));
    if (world.ship_stats(v_barca)->>'attack')::numeric <> (select attack from public.ship_classes where code = 'barca') + 90 then
      raise exception '0129 self-assert FAIL: a level-5 barca did not mount carronades as authored (%)', world.ship_stats(v_barca);
    end if;
    perform cmd.do_unfit(v_fleet, jsonb_build_object('item', 'carronades'));
    update public.world_config set value = 'false'::jsonb where key = 'levels_bite';

    -- SWIVEL GUNS ARE MADE AT A TIER-2 WORKSTATION, OUT OF THE HOLD, AND GO IN A BARCA'S WEAPON SLOT.
    perform public.fleet_load(v_fleet, g.code, ir.qty, 1)
       from public.item_recipes ir join public.goods g on g.id = ir.good_id where ir.item_code = 'swivel-guns';
    perform cmd.do_make(v_fleet, jsonb_build_object('item', 'swivel-guns'));
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'swivel-guns'));
    if (select qty from public.ship_fittings where ship_id = v_barca and item_code = 'swivel-guns') is distinct from 1
       or (world.ship_stats(v_barca)->>'attack')::numeric <> (select attack from public.ship_classes where code = 'barca') + 20
       or (world.ship_stats(v_barca)->>'accuracy')::numeric <> (select accuracy from public.ship_classes where code = 'barca') + 8 then
      raise exception '0129 self-assert FAIL: swivel guns were not made and mounted on a barca as authored (%)', world.ship_stats(v_barca);
    end if;

    raise exception 'ROLLBACK_0129';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0129' then raise; end if;
  end;
  if exists (select 1 from public.players where auth_uid = c_uid) or public.levels_bite_on() then
    raise exception '0129 self-assert FAIL: the probe world was not rolled back';
  end if;

  drop table catalogue_before_0129, posture_before_0129;

  raise notice '0129 self-assert ok: TWELVE MORE FITTINGS. Twenty-four fittings, each 2-5 inputs sold somewhere, makeable at a workstation somewhere, buying one stat and spending another (the figurehead the one exception), with a slot some hull carries; eight ask a ship level (bites only while levels_bite is on). No ship class, slot, hull recipe, earlier fitting or merchant loadout moved. Probe (rolled back): carronades went on a level-1 barca dark, were refused E_SHIP_LEVEL {1/5} lit and went on at level 5; swivel guns were made at a tier-2 workstation out of the hold and mounted on a barca. % ms. No new entry point, no client write.',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m0129$;

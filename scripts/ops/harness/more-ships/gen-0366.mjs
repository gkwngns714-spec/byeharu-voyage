// gen-0366.mjs - writes migration 0366 from the generator's Wave E (scripts/build-ships.mjs), so the file and the generator cannot disagree.
//
//   node scripts/ops/harness/more-ships/gen-0366.mjs            writes supabase/migrations/20260818000366_more_ships_to_trade_carry_and_fight.sql and, beside this file,
//                                                               before.sql and after.sql (the two read-only prod checks) and rollback-0366.sql (a draft)
//   node scripts/ops/harness/more-ships/gen-0366.mjs --check    fails if any of the four is not what this gives
//
// BEFORE THE DEPLOY ONLY. Once 0366 is applied on prod the file is frozen and this script is history (scripts/db/world-guard.mjs holds the database to the generator from then on).
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { generateShips } from '../../../build-ships.mjs'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..')
const FILE = 'supabase/migrations/20260818000366_more_ships_to_trade_carry_and_fight.sql'
const q = (s) => `'${String(s).replace(/'/g, "''")}'`
const H = generateShips().hulls.filter((h) => h.wave === 'E')
const rows = (list) => list.join(',\n')
const nGoods = H.reduce((n, h) => n + h.goods.length, 0)
const nReqs = H.reduce((n, h) => n + h.requirements.length, 0)
const nSlots = H.reduce((n, h) => n + Object.values(h.racks).filter((x) => x > 0).length, 0)
const count = (f) => H.filter(f).length
const jobs = ['raider', 'gunship', 'boarder', 'line', 'escort', 'armed', 'carrier'].map((j) => `${count((h) => h.job === j)} ${j}`).join(', ')

/** Every catalogue row a hull is made of, for every class but the new ones, as one md5. `codes` is a text[] expression. One text for the migration and the two prod checks. */
const oldRows = (codes) => `  select md5(concat_ws('#',
    (select string_agg(to_jsonb(c)::text, '|' order by c.code) from public.ship_classes c where c.code <> all (${codes})),
    (select string_agg(to_jsonb(x)::text, '|' order by x.class_code) from public.class_profile x where x.class_code <> all (${codes})),
    (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.slot) from public.class_slots x where x.class_code <> all (${codes})),
    (select string_agg(to_jsonb(x)::text, '|' order by x.class_code) from public.class_cabins x where x.class_code <> all (${codes})),
    (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.slot) from public.class_slot_unlocks x),
    (select string_agg(to_jsonb(x)::text, '|' order by x.class_code) from public.hull_recipes x where x.class_code <> all (${codes})),
    (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.good_id) from public.hull_recipe_goods x where x.class_code <> all (${codes})),
    (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.item_code) from public.hull_recipe_items x),
    (select string_agg(to_jsonb(x)::text, '|' order by x.subject_kind, x.subject_code, x.skill_code) from public.skill_requirements x
      where not (x.subject_kind = 'hull' and x.subject_code = any (${codes}))),
    (select string_agg(to_jsonb(x)::text, '|' order by x.code) from public.ship_lines x),
    (select string_agg(to_jsonb(x)::text, '|' order by x.live_class, x.line_code) from public.npc_line_hulls x),
    (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.pattern, x.item_code) from public.npc_loadouts x),
    (select string_agg(to_jsonb(x)::text, '|' order by x.class_code, x.stat) from public.ship_variety x)))`
/** Every function of the four schemas: its definition, ACL, volatility, definer and config, as one md5. */
const FUNCTIONS = `select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\\r', '')) || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''),
                        ',' order by p.oid::regprocedure::text))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')`

const sql = `-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0366 - MORE SHIPS, TO TRADE, TO CARRY AND ABOVE ALL TO FIGHT  (owner row 322)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY: the owner, 2026-11-13, row 322: "i need more trade ships, cargo, and especially combat related ships."
--
-- WHAT THIS FILE DOES: it adds ${H.length} classes of hull (Wave E of scripts/build-ships.mjs) and NOTHING ELSE. Rows only:
--   public.ship_classes (${H.length}), public.class_profile (${H.length}), public.class_slots (${nSlots}), public.class_cabins (${H.length}),
--   public.hull_recipes (${H.length}), public.hull_recipe_goods (${nGoods}), public.skill_requirements (${nReqs}).
--   No function, no knob, no table, no column, no grant, no job. cmd.do_build is one verb over public.hull_recipes with no list of hulls in it,
--   world.snapshot and world.building_yard serve every class there is, so a hull that has these rows is in the yard and the Codex at once.
--
-- THE ${H.length}: ${count((h) => h.role === 'combat')} combat (${jobs.split(', ').slice(0, 4).join(', ')}), ${count((h) => h.role === 'support')} support (escort), ${count((h) => h.role === 'trade')} trade
--   (${count((h) => h.job === null)} plain traders, ${count((h) => h.job === 'armed')} armed traders, ${count((h) => h.job === 'carrier')} cargo carriers). Every one is a real ship type of its coast in or near 1507, and every one is T1:
--   it asks the hull skill of its line and size and nothing new (the existing ladder), at its line's yards (public.yard_wrong_country, unchanged), for the
--   size's materials with its line's own goods, plus iron for a gunned job. Each is the archetype of its size and role x its line x ONE JOB; a job gives in
--   one place and takes in another, and is paid for in yard labour. The generator refuses a hull that outclasses another of its size for the same labour or
--   less, and one that is outclassed by a hull costing no more. Every figure and its reason: docs/dev-log/2026-11-13-more-ships.md.
--
-- THE FIGURES ARE THE DESIGN'S, AND THE TWO SCALES ARE APPLIED HERE: hold x hold_scale (0208) and speed x speed_scale (0220), read from the knobs at apply,
--   as scripts/db/world-guard.mjs reads them when it holds the database to data/ships.generated.json. No number of this file is typed twice.
--
-- WHAT DOES NOT CHANGE, ASSERTED BELOW: every class, profile, slot, cabin, recipe, material, fitting and requirement that existed is the same text before and
--   after; so are public.ship_lines, public.npc_line_hulls (the hull a merchant sails), public.npc_loadouts, public.ship_variety, every world_config row and
--   every function of public, cmd, world and voyage. No ship of a new class exists, no merchant is offered one (S18's table is Waves A-D's), no crown knob
--   names one. A probe of voyage.fight_resolve (the golden digest's hulls, scripts/ops/harness/two-sides/golden.sql, on fewer days) answers the same text
--   before and after, and so do the raiders (voyage.raider_hulls). An NPC's fight and voyage read only her own class and the knobs, and neither moved.
--   The Barca's rows are not read by name and not written (0363, open on another branch, changes her fittings: this file applies with it and without it).
--
-- THIS FILE RUNS NO GAME STEP (docs/OPS_HEALTH.md section 4): no build, no voyage, no gold. The live paths are proved in CI by proof 67,
--   scripts/db/proofs/67_more_ships.sql: a hull of every job laid down through cmd.do_build, and new combat hulls fought through public.fight_sides.
--   The balance, fought by the real engine: scripts/ops/harness/more-ships/duels.mjs (local).
--
-- LOCKS: row inserts on seven small catalogue tables. No ALTER, no lock on ships, fleets or markets. BUDGET: ONE DO block, statement_timeout 45 s,
--   lock_timeout 5 s first; the self-assert fails above 45 s. COST: no reader grows a loop: every reader of a class is keyed by the ship's own class.
--   world.snapshot and world.building_yard return ${H.length} more rows of a static list.
-- NEWS: this file posts its own UPDATE row, public.news_update('0366', 'New ships: ${H.length} hulls', '새 선박: ${H.length}종') (0347's law, tests/news.lint.spec.ts).
-- ROLLBACK (forward, a NEW migration, owner only): scripts/ops/harness/more-ships/rollback-0366.sql, a draft: it deletes the ${H.length} classes' rows and refuses
--   while a ship of one of them exists (such a ship is somebody's property; it is dealt with first, by the owner).
-- GENERATED by scripts/ops/harness/more-ships/gen-0366.mjs from scripts/build-ships.mjs (\`--check\` holds this file to it until it is deployed).
-- VERSION: 0366. 0357-0365 are held by other open branches; none of them writes a row this file reads except 0363 (the Barca's fittings and note), which
--   this file is proved with and without.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  c_new  constant text[] := array[${H.map((h) => q(h.class)).join(', ')}];
  c_gold constant uuid := '00000000-0320-4000-8000-0000000000ff';
  v_hold  int;
  v_speed numeric;
  v_n     int;
  v_bad   text;
  v_f     jsonb;
  v_old_before  text;
  v_fn_before   text;
  v_cfg_before  text;
  v_gold_before text;
  v_raid_before text;
  v_classes_before int;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.ship_classes c where c.code = any (c_new)) then
    raise exception '0366 refuses: it has been applied once (a class of it is already in this world)';
  end if;
  if to_regprocedure('public.news_update(text,text,text)') is null or to_regprocedure('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)') is null
     or to_regprocedure('voyage.fight_resolve(uuid,integer,numeric,numeric,jsonb)') is null or to_regprocedure('voyage.raider_hulls(numeric)') is null
     or to_regprocedure('public.yard_wrong_country(uuid,text)') is null or to_regclass('public.npc_line_hulls') is null then
    raise exception '0366 refuses: 0130 / 0167 / 0320 / 0347 are not all in this world';
  end if;
  v_hold := public.wc_int('hold_scale');
  v_speed := public.wc_num('speed_scale');
  if v_hold is null or v_hold < 1 or v_speed is null or v_speed <= 0 then
    raise exception '0366 refuses: hold_scale (%) or speed_scale (%) is not a scale', v_hold, v_speed;
  end if;

  -- ── 1. THE PRE-IMAGES (every row and body this file must not move) ──
  execute $f$
create function pg_temp.old_0366(p_new text[])
returns text
language sql
stable
as $b$
  -- every catalogue row a hull is made of, for every class but the new ones, as text
${oldRows('p_new')}
$b$
  $f$;
  execute $f$
create function pg_temp.gold_0366(p_seed uuid)
returns text
language sql
stable
as $b$
  -- the golden digest's hulls (scripts/ops/harness/two-sides/golden.sql), on 20 and 5 days: every answer of the skin, as text
  with s(ships, esc) as (values
    ('[{"id":"00000000-0320-4000-8000-0000000000a1","name":"Probe Carlat","tier":1,"hull":550,"maxd":550,"crew":12,"attack":55,"accuracy":40,"reach":25,"armour":12,"sighting":10,"gear":["Boarding Gear"]}]'::jsonb, 11.74::numeric),
    ('[{"id":"00000000-0320-4000-8000-0000000000a2","name":"Probe Barca","tier":1,"hull":400,"maxd":400,"crew":8,"attack":35,"accuracy":0,"reach":0,"armour":5,"sighting":8}]'::jsonb, 6.66::numeric)),
  c(ships) as (values ('[{"id":"00000000-0320-4000-8000-0000000000a3","name":"Probe Nau","tier":3,"hull":1500,"maxd":1800,"crew":90,"attack":180,"accuracy":55,"reach":60,"armour":30,"sighting":40,"boarder_pct":0.12,"boarder":"Probe Boarder","gunner":"Probe Gunner","gear":["Swivel Guns","Boarding Gear"]},{"id":"00000000-0320-4000-8000-0000000000a4","name":"Probe Galion","tier":4,"hull":2400,"maxd":2400,"crew":140,"attack":260,"accuracy":48,"reach":40,"armour":44,"sighting":22}]'::jsonb)),
  f as materialized (
    select 1 as o, s.esc, r.r, d, voyage.fight_resolve(p_seed, d, r.r, s.esc, s.ships) j
      from s cross join (values (6.0), (12.0), (18.0), (24.0)) r(r) cross join generate_series(1, 20) d
    union all
    select 2, 30.5, r.r, d, voyage.fight_resolve(p_seed, d, r.r, 30.5, c.ships)
      from c cross join (values (10.0), (24.0), (60.0), (120.0)) r(r) cross join generate_series(1, 5) d)
  select count(*) || ':' || md5(string_agg(j::text, E'\\n' order by o, esc, r, d)) from f
$b$
  $f$;

  v_old_before := pg_temp.old_0366(c_new);
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\\r', '')) || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''),
                        ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  v_gold_before := pg_temp.gold_0366(c_gold);
  v_raid_before := md5(voyage.raider_hulls(12.7)::text || voyage.raider_hulls(63.5)::text);
  select count(*) into v_classes_before from public.ship_classes;
  if v_old_before is null or v_fn_before is null or v_cfg_before is null or v_gold_before is null or v_gold_before not like '180:%' then
    raise exception '0366 refuses: a pre-image is empty (rows %, functions %, knobs %, fights %)', v_old_before, v_fn_before, v_cfg_before, v_gold_before;
  end if;

  -- ── 2. THE ${H.length} HULLS (scripts/build-ships.mjs --sql E: the design's figures; hold and speed x the two scales) ──
  insert into public.ship_classes
    (code, name, family, rig, hold, crew_required, crew_max, speed_kn, durability, guns, draft,
     build_hours, build_cost, tier, handling, armour, attack, accuracy, reach, sighting, wave)
  select v.code, v.name, v.family, v.rig, v.hold * v_hold, v.crew_required, v.crew_max, v.speed_kn * v_speed, v.durability, v.guns, v.draft,
         v.build_hours, v.build_cost, v.tier, v.handling, v.armour, v.attack, v.accuracy, v.reach, v.sighting, v.wave
    from (values
${rows(H.map((h) => `  (${q(h.class)}, ${q(h.name)}, ${q(h.family)}, ${q(h.rig)}, ${h.hold}, ${h.crewRequired}, ${h.crewMax}, ${h.speedKn.toFixed(2)}, ${h.durability}, ${h.guns}, ${h.draft}, ${h.buildHours.toFixed(2)}, ${h.buildCost.toFixed(2)}, ${h.tier}, ${h.handling}, ${h.armour}, ${h.attack}, ${h.accuracy}, ${h.reach}, ${h.sighting.toFixed(1)}, ${h.waveResistance})`))}
    ) v(code, name, family, rig, hold, crew_required, crew_max, speed_kn, durability, guns, draft, build_hours, build_cost, tier, handling, armour, attack, accuracy, reach, sighting, wave);

  insert into public.class_profile (class_code, line_code, size, role, tech, deck, any_yard) values
${rows(H.map((h) => `  (${q(h.class)}, ${q(h.line)}, ${h.size}, ${q(h.role)}, ${q(h.tech)}, ${h.deck}, ${h.anyYard})`))};

  insert into public.class_slots (class_code, slot, count) values
${rows(H.flatMap((h) => Object.entries(h.racks).filter(([, n]) => n > 0).map(([r, n]) => `  (${q(h.class)}, ${q(r)}, ${n})`)))};

  insert into public.class_cabins (class_code, cabins) values
${rows(H.map((h) => `  (${q(h.class)}, ${h.cabins})`))};

  insert into public.hull_recipes (class_code, yard_tier, ducats, note) values
${rows(H.map((h) => `  (${q(h.class)}, ${h.yardTier}, ${h.ducats}, ${q(h.note)})`))};

  insert into public.hull_recipe_goods (class_code, good_id, qty)
  select w.class_code, g.id, w.qty
    from (values
${rows(H.flatMap((h) => h.goods.map((g) => `  (${q(h.class)}, ${q(g.in)}, ${g.qty})`)))}
    ) w(class_code, good_code, qty)
    join public.goods g on g.code = w.good_code;

  insert into public.skill_requirements (subject_kind, subject_code, skill_code, level) values
${rows(H.flatMap((h) => h.requirements.map((r) => `  ('hull', ${q(h.class)}, ${q(r.skill)}, ${r.level})`)))};

  -- ── 3. THE SELF-ASSERT: the catalogue and stable reads. No game step, no row but the catalogue's. ──
  -- 3a. what was there is what is there
  if pg_temp.old_0366(c_new) is distinct from v_old_before then
    raise exception '0366 self-assert FAIL: a class, profile, slot, cabin, recipe, material, fitting, requirement, line, merchant hull or loadout that existed has moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\\r', '')) || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''),
                            ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) is distinct from v_fn_before then
    raise exception '0366 self-assert FAIL: a function moved (this file writes rows only)';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) is distinct from v_cfg_before then
    raise exception '0366 self-assert FAIL: a world_config row moved';
  end if;
  if pg_temp.gold_0366(c_gold) is distinct from v_gold_before then
    raise exception '0366 self-assert FAIL: a raid of the golden probe answers differently (% before, % after)', v_gold_before, pg_temp.gold_0366(c_gold);
  end if;
  if md5(voyage.raider_hulls(12.7)::text || voyage.raider_hulls(63.5)::text) is distinct from v_raid_before then
    raise exception '0366 self-assert FAIL: the raiders are built differently';
  end if;

  -- 3b. the new rows are whole
  if (select count(*) from public.ship_classes) <> v_classes_before + ${H.length}
     or (select count(*) from public.ship_classes c where c.code = any (c_new)) <> ${H.length}
     or (select count(*) from public.class_profile x where x.class_code = any (c_new)) <> ${H.length}
     or (select count(*) from public.class_slots x where x.class_code = any (c_new)) <> ${nSlots}
     or (select count(*) from public.class_cabins x where x.class_code = any (c_new)) <> ${H.length}
     or (select count(*) from public.hull_recipes x where x.class_code = any (c_new)) <> ${H.length}
     or (select count(*) from public.hull_recipe_goods x where x.class_code = any (c_new)) <> ${nGoods}
     or (select count(*) from public.skill_requirements x where x.subject_kind = 'hull' and x.subject_code = any (c_new)) <> ${nReqs} then
    raise exception '0366 self-assert FAIL: the new rows are not ${H.length} classes, ${H.length} profiles, ${nSlots} slots, ${H.length} cabins, ${H.length} recipes, ${nGoods} materials (a good of the recipe is no good of this world?) and ${nReqs} requirements';
  end if;
  -- every rule a class is held to by the files before this one: the tier of its size (0130), guns = attack / 10 (0074), the one wave rule (0215), T1 at its line's yards
  select string_agg(c.code, ', ' order by c.code) into v_bad
    from public.ship_classes c join public.class_profile cp on cp.class_code = c.code join public.hull_recipes h on h.class_code = c.code
   where c.code = any (c_new)
     and (c.tier <> least(cp.size, 5) or c.guns * 10 <> c.attack or cp.tech <> 'T1' or cp.any_yard
          or c.wave <> 12 * cp.size + case c.rig when 'square' then 3 when 'mixed' then 1 when 'lateen' then 0 else -6 end + case cp.role when 'explorer' then 2 else 0 end
          or h.yard_tier <> least(cp.size, 3) or c.build_cost <> h.ducats * 4 or c.hold % v_hold <> 0
          or (c.attack = 0) <> (c.accuracy = 0) or c.stat_note is not null
          or not exists (select 1 from public.class_slots s where s.class_code = c.code and s.slot = 'high')
          or not exists (select 1 from public.class_slots s where s.class_code = c.code and s.slot = 'mid')
          or (select count(*) from public.hull_recipe_goods g where g.class_code = c.code) < 3
          or (select count(*) from public.skill_requirements r where r.subject_kind = 'hull' and r.subject_code = c.code) < 1);
  if v_bad is not null then
    raise exception '0366 self-assert FAIL: not a whole class by the rules of 0074 / 0130 / 0135 / 0215: %', v_bad;
  end if;
  -- a requirement names the hull's own line, and a skill of the ladder
  select string_agg(r.subject_code || ' needs ' || r.skill_code, ', ' order by r.subject_code) into v_bad
    from public.skill_requirements r join public.class_profile cp on cp.class_code = r.subject_code
   where r.subject_kind = 'hull' and r.subject_code = any (c_new)
     and r.skill_code not like cp.line_code || '\\_%' and r.skill_code not in ('MERCHANT_SHIPS', 'SHIPS_OF_WAR', 'ESCORT_SUPPORT', 'COMMAND', 'FLEET_COMMAND');
  if v_bad is not null then
    raise exception '0366 self-assert FAIL: a requirement outside the hull''s own ladder: %', v_bad;
  end if;
  -- no name or code is another class's (cmd.resolve_class answers a class by either)
  select string_agg(a.code || ' / ' || b.code, ', ' order by a.code) into v_bad
    from public.ship_classes a join public.ship_classes b on b.code <> a.code
     and (cmd.fold(a.name) = cmd.fold(b.name) or cmd.fold(a.name) = cmd.fold(b.code) or cmd.fold(a.code) = cmd.fold(b.name))
   where a.code = any (c_new);
  if v_bad is not null then
    raise exception '0366 self-assert FAIL: two classes answer to one name: %', v_bad;
  end if;
  -- every one can be laid down somewhere: a build yard of her tier in a country of her line (the one country rule, public.yard_wrong_country)
  select string_agg(c.code, ', ' order by c.code) into v_bad
    from public.ship_classes c join public.hull_recipes h on h.class_code = c.code
   where c.code = any (c_new)
     and not exists (select 1 from public.port_buildings b
                      where b.kind = 'building_yard' and b.tier >= h.yard_tier and public.yard_wrong_country(b.port_id, c.code) is null);
  if v_bad is not null then
    raise exception '0366 self-assert FAIL: no build yard of this world can lay down: %', v_bad;
  end if;
  -- and her materials fit the biggest shed (0072 (d); scripts/build-ships.mjs SHED_TUNS)
  select string_agg(x.class_code || ' ' || x.tons, ', ' order by x.class_code) into v_bad
    from (select hg.class_code, sum(hg.qty * g.bulk) as tons from public.hull_recipe_goods hg join public.goods g on g.id = hg.good_id
           where hg.class_code = any (c_new) group by 1) x
   where x.tons > 750;
  if v_bad is not null then
    raise exception '0366 self-assert FAIL: materials over 750 tuns, which no shed holds: %', v_bad;
  end if;

  -- 3c. no NPC and no crown is given one
  if exists (select 1 from public.npc_line_hulls x where x.class_code = any (c_new) or x.live_class = any (c_new))
     or exists (select 1 from public.npc_loadouts x where x.class_code = any (c_new))
     or exists (select 1 from public.world_config k where jsonb_typeof(k.value) = 'string' and k.value #>> '{}' = any (c_new))
     or exists (select 1 from public.ships s join public.ship_classes c on c.id = s.class_id where c.code = any (c_new)) then
    raise exception '0366 self-assert FAIL: a merchant, a loadout, a knob or a ship names a new class';
  end if;

  -- 3d. the two reads serve them, and the engine fights them (pure: public.fight_sides names no table)
  if (select count(*) from jsonb_array_elements(world.snapshot() -> 'ship_classes') s
       where s ->> 'code' = any (c_new) and s ->> 'tech' = 'T1' and s ->> 'role' in ('trade', 'combat', 'support') and s ->> 'line' is not null and not s ? 'crown') <> ${H.length} then
    raise exception '0366 self-assert FAIL: world.snapshot does not serve the ${H.length} classes with their line, size, role and tech';
  end if;
  select string_agg(c.code, ', ' order by c.code) into v_bad
    from public.ship_classes c
   where c.code in ('greatgalley', 'holk', 'almiranta')
     and not exists (select 1 from jsonb_array_elements(world.building_yard(
                       (select b.port_id from public.port_buildings b join public.hull_recipes h on h.class_code = c.code
                         where b.kind = 'building_yard' and b.tier >= h.yard_tier and public.yard_wrong_country(b.port_id, c.code) is null order by b.port_id limit 1)) -> 'hulls') s
                      where s ->> 'class' = c.code and (s ->> 'ducats')::bigint = public.hull_labour(c.code));
  if v_bad is not null then
    raise exception '0366 self-assert FAIL: a yard of her own country does not offer, at the recipe''s labour: %', v_bad;
  end if;
  -- a gunship set upon by a boarder: at LONG range only the longer reach fires (the engine's rule, on the new rows)
  select public.fight_sides('00000000-0366-4000-8000-0000000000ff'::uuid, 1,
           (select jsonb_agg(jsonb_build_object('id', '00000000-0366-4000-8000-0000000000a1', 'name', c.name, 'tier', c.tier, 'hull', c.durability, 'maxd', c.durability, 'crew', c.crew_max,
                     'attack', c.attack, 'accuracy', c.accuracy, 'reach', c.reach, 'armour', c.armour, 'sighting', c.sighting)) from public.ship_classes c where c.code = 'greatgalley'),
           (select jsonb_agg(jsonb_build_object('id', '00000000-0366-4000-8000-0000000000b1', 'name', c.name, 'tier', c.tier, 'hull', c.durability, 'maxd', c.durability, 'crew', c.crew_max,
                     'attack', c.attack, 'accuracy', c.accuracy, 'reach', c.reach, 'armour', c.armour, 'sighting', c.sighting)) from public.ship_classes c where c.code = 'daemaeng'))
    into v_f;
  if v_f ->> 'outcome' is null or (v_f ->> 'rounds_fought')::int < 1
     or exists (select 1 from jsonb_array_elements(v_f -> 'rounds') r where r ->> 'range' = 'LONG' and ((r -> 'b' ->> 'fired')::int <> 0 or (r -> 'a' ->> 'fired')::int <> 1)) then
    raise exception '0366 self-assert FAIL: the Great Galley does not out-range the Daemaengseon at long range: %', v_f;
  end if;

  -- ── 4. THE NEWS (0347's law: one row, idempotent by its number) ──
  perform public.news_update('0366', 'New ships: ${H.length} hulls', '새 선박: ${H.length}종');

  drop function pg_temp.old_0366(text[]);
  drop function pg_temp.gold_0366(uuid);
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0366 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0366 self-assert ok: MORE SHIPS: % classes of hull added (% combat, % support, % trade), % slots, % materials, % requirements, hold x % and speed x %. Every older class, recipe, requirement, line, merchant hull, loadout, knob and function is the same text before and after; the golden probe (%) and the raiders answer the same; every new hull has a yard of her own country and fits the shed; no merchant, knob or ship names one; no game step ran (proof 67 runs them in CI). % ms.',
    ${H.length}, ${count((h) => h.role === 'combat')}, ${count((h) => h.role === 'support')}, ${count((h) => h.role === 'trade')}, ${nSlots}, ${nGoods}, ${nReqs}, v_hold, v_speed, v_gold_before,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
`

// ── THE PROD CHECKS AND THE ROLLBACK DRAFT (scripts/ops/harness/more-ships/): the same code list and the same digest texts as the migration ──
const DIR = 'scripts/ops/harness/more-ships'
const CODES = `array[${H.map((h) => q(h.class)).join(', ')}]::text[]`
const goodsUsed = [...new Set(H.flatMap((h) => h.goods.map((g) => g.in)))].sort()
const skillsUsed = [...new Set(H.flatMap((h) => h.requirements.map((r) => r.skill)))].sort()
const reads = (when) => `begin transaction read only;
with n(codes) as (values (${CODES})),
     nm(code, name) as (values ${H.map((h) => `(${q(h.class)}, ${q(h.name)})`).join(', ')})
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'classes', (select count(*) from public.ship_classes),
  'new_classes', (select count(*) from public.ship_classes c, n where c.code = any (n.codes)),
  'new_rows', jsonb_build_object(
     'profiles', (select count(*) from public.class_profile x, n where x.class_code = any (n.codes)),
     'slots', (select count(*) from public.class_slots x, n where x.class_code = any (n.codes)),
     'cabins', (select count(*) from public.class_cabins x, n where x.class_code = any (n.codes)),
     'recipes', (select count(*) from public.hull_recipes x, n where x.class_code = any (n.codes)),
     'materials', (select count(*) from public.hull_recipe_goods x, n where x.class_code = any (n.codes)),
     'requirements', (select count(*) from public.skill_requirements x, n where x.subject_kind = 'hull' and x.subject_code = any (n.codes))),
  'old_rows', (
${oldRows('(select codes from n)::text[]')}),
  'functions', (${FUNCTIONS}),
  'scales', jsonb_build_object('hold', public.wc_int('hold_scale'), 'speed', public.wc_num('speed_scale')),
  'name_clash', (select count(*) from nm join public.ship_classes c on c.code <> nm.code
                  and (cmd.fold(c.name) = cmd.fold(nm.name) or cmd.fold(c.code) = cmd.fold(nm.name) or cmd.fold(c.name) = cmd.fold(nm.code))),
  'goods_missing', (select count(*) from unnest(array[${goodsUsed.map(q).join(', ')}]) g(code) where not exists (select 1 from public.goods x where x.code = g.code)),
  'skills_missing', (select count(*) from unnest(array[${skillsUsed.map(q).join(', ')}]) s(code) where not exists (select 1 from public.skills x where x.code = s.code)),
  'lines_with_no_tier3_yard', (select count(*) from public.ship_lines sl
                                where not exists (select 1 from public.port_buildings b where b.kind = 'building_yard' and b.tier >= 3 and public.port_countries(b.port_id) && sl.builder_nations)),
  'named_by_npc_or_knob', (select count(*) from n where exists (select 1 from public.npc_line_hulls x where x.class_code = any (n.codes))
                              or exists (select 1 from public.npc_loadouts x where x.class_code = any (n.codes))
                              or exists (select 1 from public.world_config k where jsonb_typeof(k.value) = 'string' and k.value #>> '{}' = any (n.codes))),
  'ships_of_new_classes', (select count(*) from public.ships s join public.ship_classes c on c.id = s.class_id, n where c.code = any (n.codes)),
  'news_row', (select count(*) from public.world_news w where w.key = 'update:0366')
)::text as j;
commit;
`
const before = `-- 0366 PROD CHECK (before), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f ${DIR}/before.sql
-- Wanted: head the migration before 0366; classes 103; new_classes 0 and every new_rows figure 0; scales hold 3, speed 3; name_clash, goods_missing, skills_missing,
-- lines_with_no_tier3_yard, named_by_npc_or_knob, ships_of_new_classes and news_row all 0. KEEP old_rows and functions: after.sql must print the same two texts.
-- Then take the golden digest: ${'scripts/ops/harness/two-sides/golden.sql'} (keep \`digest\`).
-- Every function read is STABLE or IMMUTABLE (wc_int, wc_num, cmd.fold, port_countries, pg_get_functiondef); no game function is called; nothing is written.
-- Generated by ${DIR}/gen-0366.mjs with the migration, from the same code list and the same digest texts.
${reads('before')}`
const after = `-- 0366 PROD CHECK (after), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f ${DIR}/after.sql
-- Wanted: head 20260818000366; classes 157; new_classes ${H.length}; new_rows profiles ${H.length}, slots ${nSlots}, cabins ${H.length}, recipes ${H.length}, materials ${nGoods}, requirements ${nReqs};
-- old_rows and functions THE SAME TEXT as before.sql printed (no older class, recipe, requirement, line, merchant hull, loadout or function moved); name_clash 0;
-- named_by_npc_or_knob 0; news_row 1; ships_of_new_classes 0 at the deploy (it grows as players build: that is the feature).
-- Then the golden digest again (${'scripts/ops/harness/two-sides/golden.sql'}): the same \`digest\` as before. NO 30-minute fight after-check is needed: no rule, knob or NPC hull moved.
-- Every function read is STABLE or IMMUTABLE; no game function is called; nothing is written.
-- Generated by ${DIR}/gen-0366.mjs with the migration, from the same code list and the same digest texts.
${reads('after')}`
const rollback = `-- 0366 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add its own news line
-- (\`-- news: none\`), and deploy it as any migration (owner only). It deletes the ${H.length} classes' catalogue rows, and nothing else.
-- IT REFUSES WHILE A SHIP OF ONE OF THEM EXISTS: such a ship is a company's property. The owner decides first what becomes of her (the usual answer is not to roll back:
-- a class can be made unbuildable instead by deleting its public.hull_recipes row, which leaves every built ship whole and cmd.do_build answering E_NOT_BUILDABLE).
-- The news row of 0366 stays (news is append-only). Tested locally: ${DIR}/q.mjs applies 0366, runs this, and the old-rows digest is the one from before 0366.
-- Generated by ${DIR}/gen-0366.mjs.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  c_new constant text[] := ${CODES};
  v_n   int;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);
  if (select count(*) from public.ship_classes c where c.code = any (c_new)) <> ${H.length} then
    raise exception '0366 rollback refuses: the ${H.length} classes of 0366 are not all in this world';
  end if;
  select count(*) into v_n from public.ships s join public.ship_classes c on c.id = s.class_id where c.code = any (c_new);
  if v_n > 0 then
    raise exception '0366 rollback refuses: % ship(s) of the new classes exist; they are somebody''s property and are dealt with first', v_n;
  end if;
  if exists (select 1 from public.npc_line_hulls x where x.class_code = any (c_new)) or exists (select 1 from public.npc_loadouts x where x.class_code = any (c_new))
     or exists (select 1 from public.world_config k where jsonb_typeof(k.value) = 'string' and k.value #>> '{}' = any (c_new)) then
    raise exception '0366 rollback refuses: a merchant, a loadout or a knob names a new class';
  end if;
  delete from public.skill_requirements x where x.subject_kind = 'hull' and x.subject_code = any (c_new);
  delete from public.hull_recipes x where x.class_code = any (c_new);          -- its materials go with it (on delete cascade)
  delete from public.class_cabins x where x.class_code = any (c_new);
  delete from public.class_slots x where x.class_code = any (c_new);
  delete from public.class_profile x where x.class_code = any (c_new);
  delete from public.ship_classes c where c.code = any (c_new);
  if exists (select 1 from public.hull_recipe_goods x where x.class_code = any (c_new)) or exists (select 1 from public.ship_classes c where c.code = any (c_new)) then
    raise exception '0366 rollback FAIL: a row of the new classes is left';
  end if;
  raise notice '0366 rollback ok: ${H.length} classes and their rows deleted; every older row untouched (compare ${DIR}/before.sql old_rows)';
end
$r$;
`
const outputs = [[FILE, sql], [`${DIR}/before.sql`, before], [`${DIR}/after.sql`, after], [`${DIR}/rollback-0366.sql`, rollback]]
if (process.argv.includes('--check')) {
  for (const [file, text] of outputs) {
    if (readFileSync(join(ROOT, file), 'utf8') !== text) { console.error(`${file} is NOT what gen-0366.mjs gives: re-run it (before the deploy only).`); process.exit(1) }
  }
  console.log(`${outputs.map(([f]) => f).join(', ')} equal gen-0366.mjs (${H.length} hulls).`)
} else {
  for (const [file, text] of outputs) writeFileSync(join(ROOT, file), text)
  console.log(`wrote ${outputs.map(([f]) => f).join(', ')}: ${H.length} hulls, ${nSlots} slots, ${nGoods} materials, ${nReqs} requirements`)
}

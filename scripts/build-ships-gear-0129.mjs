// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-ships-gear-0129.mjs — the S5/S6 catalogue rows of migration 0129, FROM data/*.json
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/SHIPS_AND_GEAR.md §6 (eight ship types) and §7 (twelve fittings). The data files are the one
// authority — data/ship_stats.json (classes, slots, cabins, level unlocks), data/hulls.json
// (recipes, yard tier, coast, trading level), data/fittings.json (kinds, effects, recipes, the ship
// level a fitting asks) — and scripts/db/world-guard.mjs holds the applied world equal to them on
// every apply. This script only writes the INSERTs for the rows 0129 ADDS (the eight classes and
// the twelve fittings below) into the generated region of the migration, between the markers
// `-- <generated:0129>` and `-- </generated:0129>`. It never emits a row for a class or fitting an
// earlier migration put in: those are proved unmoved by 0129's self-assert, not re-written.
//
//   node scripts/build-ships-gear-0129.mjs          # rewrite the region
//   node scripts/build-ships-gear-0129.mjs --check  # exit 1 if the region is not what the data says
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import fs from 'node:fs'
import { deriveWorld } from './lib/world-derive.mjs'

const MIGRATION = 'supabase/migrations/20260818000129_more_hulls_and_more_gear.sql'
const NEW_CLASSES = ['pinnace', 'dhow', 'carred', 'fluyt', 'xebec', 'junk', 'galleon', 'indiaman']
const NEW_GEAR = ['storm-canvas', 'studding-sails', 'whipstaff', 'binnacle-and-charts', 'sheet-anchor', 'capstan',
  'bilge-pumps', 'doubled-planking', 'swivel-guns', 'stern-chasers', 'carronades', 'topgallant-mast']
const SLOT_KINDS = ['rig', 'weapon', 'ground-tackle', 'steering', 'hull', 'lookout', 'flourish']
const STATS = ['hold', 'speed', 'handling', 'draft', 'durability', 'armour', 'attack', 'accuracy', 'reach', 'sighting']

const read = (f) => JSON.parse(fs.readFileSync(f, 'utf8'))
const stats = read('data/ship_stats.json')
const hulls = read('data/hulls.json').hulls
const fittings = read('data/fittings.json').fittings
const goods = new Set(read('data/goods.json').goods.map((g) => g.id))
const regions = new Set(deriveWorld().regions.map((r) => r.code))
const items = new Set(fittings.map((f) => f.code))

const q = (s) => `'${String(s).replace(/'/g, "''")}'`
const fail = (m) => { throw new Error(`build-ships-gear-0129: ${m}`) }
const one = (list, key, code, what) => list.find((x) => x[key] === code) ?? fail(`${what} ${code} is not in the data`)

// ── the data's own rules, checked before a line is written (the migration re-checks in the world) ──
for (const code of NEW_CLASSES) {
  const c = one(stats.classes, 'class', code, 'class')
  const h = one(hulls, 'class', code, 'hull recipe')
  one(stats.slots, 'class', code, 'slot row')
  if (c.guns * 10 !== c.attack) fail(`${code}: guns must be attack/10 (S4's escort re-cut is a no-op only then)`)
  for (const g of h.goods) if (!goods.has(g.in)) fail(`${code} wants good ${g.in}, which data/goods.json does not define`)
  for (const i of h.items) if (!items.has(i.in)) fail(`${code} wants fitting ${i.in}, which data/fittings.json does not define`)
  for (const r of h.yard_regions ?? []) if (!regions.has(r)) fail(`${code} is laid down in region ${r}, which the derived world (data/regions.json) does not define`)
  if (h.goods.length < 2 || h.items.length < 1) fail(`${code}: a hull is timber AND fittings (0072 row 58)`)
}
for (const code of NEW_GEAR) {
  const f = one(fittings, 'code', code, 'fitting')
  if (!SLOT_KINDS.includes(f.slot)) fail(`${code}: slot ${f.slot} is not one of the seven kinds`)
  if (f.recipe.length < 2 || f.recipe.length > 5) fail(`${code}: a recipe is 2-5 inputs (0068)`)
  for (const g of f.recipe) if (!goods.has(g.in)) fail(`${code} wants good ${g.in}, which data/goods.json does not define`)
  if (!f.effects.some((e) => e.delta > 0) || !f.effects.some((e) => e.delta < 0)) fail(`${code}: every fitting buys one stat and spends another (0074)`)
  for (const e of f.effects) if (!STATS.includes(e.stat)) fail(`${code}: ${e.stat} is not one of the ten stats`)
}

// ── the rows ──────────────────────────────────────────────────────────────────────────────────
const L = []
const rows = (head, list, tail) => { L.push(head); L.push(list.join(',\n') + tail) }

rows('  insert into public.ship_classes (code, name, family, rig, tier, hold, crew_required, crew_max, speed_kn, durability,\n' +
  '                                   guns, draft, build_hours, build_cost, handling, armour, attack, accuracy, reach, sighting, stat_note) values',
NEW_CLASSES.map((code) => {
  const c = one(stats.classes, 'class', code, 'class')
  return `    (${q(code)}, ${q(c.name)}, ${q(c.family)}, ${q(c.rig)}, ${c.tier}, ${c.hold}, ${c.crew_required}, ${c.crew_max}, ${c.speed_kn}, ` +
    `${c.durability}, ${c.guns}, ${c.draft}, ${c.build_hours}, ${c.build_cost}, ${c.handling}, ${c.armour}, ${c.attack}, ${c.accuracy}, ` +
    `${c.reach}, ${c.sighting},\n     ${q(c.note)})`
}), ';')

rows('  insert into public.class_slots (class_code, slot, count) values',
  NEW_CLASSES.flatMap((code) => {
    const s = one(stats.slots, 'class', code, 'slot row')
    return SLOT_KINDS.filter((k) => s[k] > 0).map((k) => `    (${q(code)}, ${q(k)}, ${s[k]})`)
  }), ';')

rows('  insert into public.class_cabins (class_code, cabins) values',
  NEW_CLASSES.map((code) => `    (${q(code)}, ${one(stats.slots, 'class', code, 'slot row').cabins})`), ';')

rows('  insert into public.class_slot_unlocks (class_code, slot, count, min_level) values',
  stats.unlocks.filter((u) => NEW_CLASSES.includes(u.class))
    .map((u) => `    (${q(u.class)}, ${q(u.slot)}, ${u.count}, ${u.min_level})`), ';')

rows('  insert into public.hull_recipes (class_code, yard_tier, ducats, yard_regions, min_level, note) values',
  NEW_CLASSES.map((code) => {
    const h = one(hulls, 'class', code, 'hull recipe')
    const reg = h.yard_regions === null ? 'null' : `array[${h.yard_regions.map(q).join(', ')}]`
    return `    (${q(code)}, ${h.yard_tier}, ${h.ducats}, ${reg}, ${h.min_level},\n     ${q(h.note)})`
  }), ';')

rows('  insert into public.hull_recipe_goods (class_code, good_id, qty)\n' +
  '  select w.class_code, g.id, w.qty from (values',
  NEW_CLASSES.flatMap((code) => one(hulls, 'class', code, 'hull recipe').goods.map((g) => `    (${q(code)}, ${q(g.in)}, ${g.qty})`)),
  ') w(class_code, good_code, qty) join public.goods g on g.code = w.good_code;')

rows('  insert into public.hull_recipe_items (class_code, item_code, qty) values',
  NEW_CLASSES.flatMap((code) => one(hulls, 'class', code, 'hull recipe').items.map((i) => `    (${q(code)}, ${q(i.in)}, ${i.qty})`)), ';')

rows('  insert into public.item_kinds (code, name, slot, buys, spends, note, volume, ws_tier) values',
  NEW_GEAR.map((code) => {
    const f = one(fittings, 'code', code, 'fitting')
    return `    (${q(code)}, ${q(f.name)}, ${q(f.slot)}, ${q(f.buys)}, ${q(f.spends)},\n     ${q(f.note)}, ${f.volume}, ${f.ws_tier})`
  }), ';')

rows('  insert into public.item_effects (item_code, stat, delta) values',
  NEW_GEAR.flatMap((code) => one(fittings, 'code', code, 'fitting').effects.map((e) => `    (${q(code)}, ${q(e.stat)}, ${e.delta})`)), ';')

rows('  insert into public.item_recipes (item_code, good_id, qty)\n' +
  '  select w.item_code, g.id, w.qty from (values',
  NEW_GEAR.flatMap((code) => one(fittings, 'code', code, 'fitting').recipe.map((r) => `    (${q(code)}, ${q(r.in)}, ${r.qty})`)),
  ') w(item_code, good_code, qty) join public.goods g on g.code = w.good_code;')

rows('  insert into public.item_level_asks (item_code, min_level) values',
  NEW_GEAR.map((code) => one(fittings, 'code', code, 'fitting')).filter((f) => (f.min_level ?? 1) > 1)
    .map((f) => `    (${q(f.code)}, ${f.min_level})`), ';')

const block = '  -- <generated:0129> by scripts/build-ships-gear-0129.mjs from data/ship_stats.json, data/hulls.json and\n' +
  '  -- data/fittings.json. Do not edit by hand: change the data and re-run the script.\n' +
  L.join('\n') + '\n  -- </generated:0129>'

const sql = fs.readFileSync(MIGRATION, 'utf8')
const re = /  -- <generated:0129>[\s\S]*?-- <\/generated:0129>/
if (!re.test(sql)) fail(`${MIGRATION} has no generated region`)
const next = sql.replace(re, block)
if (process.argv.includes('--check')) {
  if (next !== sql) { console.error('0129: the generated region is not what the data says — run node scripts/build-ships-gear-0129.mjs'); process.exit(1) }
  console.log('0129: the generated region equals the data')
} else {
  fs.writeFileSync(MIGRATION, next)
  console.log(`0129: wrote ${NEW_CLASSES.length} classes and ${NEW_GEAR.length} fittings into ${MIGRATION}`)
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-gear-0129.mjs — the S6 catalogue rows of migration 0129, FROM data/fittings.json
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/SHIPS_AND_GEAR.md §7 (twelve fittings). data/fittings.json is the one authority (kinds,
// effects, recipes, the ship level a fitting asks) and scripts/db/world-guard.mjs holds the applied
// world equal to it on every apply. This script only writes the INSERTs for the twelve rows 0129
// ADDS into the generated region of the migration, between `-- <generated:0129>` and
// `-- </generated:0129>`. It never emits a fitting an earlier migration put in: those are proved
// unmoved by 0129's self-assert, not re-written.
//
//   node scripts/build-gear-0129.mjs          # rewrite the region
//   node scripts/build-gear-0129.mjs --check  # exit 1 if the region is not what the data says
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import fs from 'node:fs'

const MIGRATION = 'supabase/migrations/20260818000129_twelve_more_fittings.sql'
const NEW_GEAR = ['storm-canvas', 'studding-sails', 'whipstaff', 'binnacle-and-charts', 'sheet-anchor', 'capstan',
  'bilge-pumps', 'doubled-planking', 'swivel-guns', 'stern-chasers', 'carronades', 'topgallant-mast']
const SLOT_KINDS = ['rig', 'weapon', 'ground-tackle', 'steering', 'hull', 'lookout', 'flourish']
const STATS = ['hold', 'speed', 'handling', 'draft', 'durability', 'armour', 'attack', 'accuracy', 'reach', 'sighting']

const read = (f) => JSON.parse(fs.readFileSync(f, 'utf8'))
const fittings = read('data/fittings.json').fittings
const goods = new Set(read('data/goods.json').goods.map((g) => g.id))

const q = (s) => `'${String(s).replace(/'/g, "''")}'`
const fail = (m) => { throw new Error(`build-gear-0129: ${m}`) }
const one = (list, key, code, what) => list.find((x) => x[key] === code) ?? fail(`${what} ${code} is not in the data`)

// ── the data's own rules, checked before a line is written (the migration re-checks in the world) ──
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

const block = '  -- <generated:0129> by scripts/build-gear-0129.mjs from data/fittings.json.\n' +
  '  -- Do not edit by hand: change the data and re-run the script.\n' +
  L.join('\n') + '\n  -- </generated:0129>'

const sql = fs.readFileSync(MIGRATION, 'utf8')
const re = /  -- <generated:0129>[\s\S]*?-- <\/generated:0129>/
if (!re.test(sql)) fail(`${MIGRATION} has no generated region`)
const next = sql.replace(re, block)
if (process.argv.includes('--check')) {
  if (next !== sql) { console.error('0129: the generated region is not what the data says — run node scripts/build-gear-0129.mjs'); process.exit(1) }
  console.log('0129: the generated region equals the data')
} else {
  fs.writeFileSync(MIGRATION, next)
  console.log(`0129: wrote ${NEW_GEAR.length} fittings into ${MIGRATION}`)
}

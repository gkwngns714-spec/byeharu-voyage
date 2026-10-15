// ═══════════════════════════════════════════════════════════════════════════════════════════════
// world-guard.mjs — ON EVERY APPLY: the applied world must EQUAL data/*.json, or the run fails.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// WHY THIS EXISTS. On 2026-08-24 migration 0003 was found to have been edited AFTER production
// applied it: production held 70 goods while every fresh rebuild got 243, and ten island ports in
// data/ports.json existed in no database at all. Nothing red happened anywhere — the chain was
// green, the proofs were green, and the world was simply not the data. This guard makes that class
// of drift impossible to commit silently: apply-chain.mjs calls it after the chain lands, so
// `npm run db:apply`, `npm run db:proof` and CI's apply-proof job all fail loudly the moment the
// chain's world and data/*.json disagree — whichever of the two moved.
//
// WHAT "EQUAL" MEANS HERE
//   * harbours    every port in data/ports.json exists (by pinned code), every column the chain
//                 derives from the data is equal, both directions — EXCEPT crew_pool, which is
//                 seeded once and then owned by the running game (0007 hire drains it)
//   * goods       every good, every column, both directions
//   * offers      every port's port_specialties rows equal its `goods` array, as a set
//   * (legs)      RETIRED 2026-08-24 with migration 0049: public.legs and data/sea-routes.json
//                 are both gone — the raster (0046) is the one authority for what water connects
//                 to what, cross-checked against 0040's sea-membership at generation. Sea places
//                 are still checked to exist and sit where data/sea-places.json says.
//   * seas/regions/nations   the code+name sets are equal
//   * market      exactly one port_goods row per (harbour, good) — the market covers the world
//   * ships/gear  (0129, S7) ship_classes, class_slots, class_cabins, class_slot_unlocks,
//                 hull_recipes (+ goods, items), item_kinds, item_effects, item_recipes,
//                 item_level_asks and npc_loadouts EQUAL data/ship_stats.json, data/hulls.json,
//                 data/fittings.json and data/npc-loadouts.json, row for row, both directions
//
// WHAT IT DOES NOT CHECK (and why): runtime state (stock, drift, season_mod, crew_pool — the
// game's, not the data's); affinity values (0041's self-assert pins them to the one formula, and
// re-runs on every chain apply); the browser's own apply (src/lib/db) — the chain FINGERPRINT
// guarantees the browser applies the same bytes this guard just certified.
//
// POSITIVE CONTROL, EVERY RUN: before certifying, the comparator is aimed at a deliberately
// mutated copy of the derived world (one harbour dropped, one good's value bent) and MUST report both
// wounds. A guard that cannot see a planted drift certifies nothing (proofs-never-assert rule).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { deriveWorld, REPO_ROOT, round2 } from '../lib/world-derive.mjs'

/** Compare the applied world (queried once, below) against a derived world. Pure. */
function drift(db_, want) {
  const out = []
  const say = (s) => out.push(s)

  // harbours
  const wPorts = new Map(want.ports.map((p) => [p.code, p]))
  for (const p of db_.ports) if (!wPorts.has(p.code)) say(`harbour ${p.code} (${p.name}) is in the database but not in data/ports.json`)
  for (const p of want.ports) {
    const d = db_.ports.find((x) => x.code === p.code)
    if (!d) { say(`harbour ${p.code} (${p.name}) is in data/ports.json but not in the database`); continue }
    const pairs = [
      ['name', d.name, p.name], ['country', d.country, p.country],
      ['nation', d.nation_code ?? null, p.nation_code ?? null],
      ['lat', Number(d.lat), p.lat], ['lon', Number(d.lon), p.lon],
      ['sea', d.sea_code, p.sea_code], ['region', d.region_code, p.region_code],
      ['culture', d.culture, p.culture], ['size_tier', Number(d.size_tier), p.size_tier],
      ['max_draft', Number(d.max_draft), p.max_draft], ['yard_tier', Number(d.yard_tier), p.yard_tier],
      ['has_yard', Boolean(d.has_yard), p.has_yard], ['has_academy', Boolean(d.has_academy), p.has_academy],
      ['dev_industry', Number(d.dev_industry), p.dev_industry],
      ['dev_commerce', Number(d.dev_commerce), p.dev_commerce],
      ['dev_military', Number(d.dev_military), p.dev_military],
    ]
    for (const [col, got, wanted] of pairs) {
      if (String(got) !== String(wanted)) say(`harbour ${p.code}.${col}: database has ${got}, data says ${wanted}`)
    }
  }

  // goods
  const wGoods = new Map(want.goods.map((g) => [g.code, g]))
  for (const g of db_.goods) if (!wGoods.has(g.code)) say(`good ${g.code} is in the database but not in data/goods.json`)
  for (const g of want.goods) {
    const d = db_.goods.find((x) => x.code === g.code)
    if (!d) { say(`good ${g.code} (${g.name}) is in data/goods.json but not in the database`); continue }
    const arr = (v) => (Array.isArray(v) ? v : String(v ?? '{}').replace(/[{}"]/g, '').split(',').filter(Boolean))
    const dMask = arr(d.culture_mask)
    // 0062: origin/entrepot are world data like any other column — drift here is drift.
    if (JSON.stringify(arr(d.origin_regions)) !== JSON.stringify(g.origin_regions)) {
      say(`good ${g.code}.origin_regions: {${arr(d.origin_regions)}} vs {${g.origin_regions}}`)
    }
    if (JSON.stringify(arr(d.entrepot_ports)) !== JSON.stringify(g.entrepot_ports)) {
      say(`good ${g.code}.entrepot_ports: {${arr(d.entrepot_ports)}} vs {${g.entrepot_ports}}`)
    }
    if (d.name !== g.name) say(`good ${g.code}.name: database has ${d.name}, data says ${g.name}`)
    if (Math.abs(Number(d.base_value) - g.base_value) > 1e-9) say(`good ${g.code}.base_value: ${d.base_value} vs ${g.base_value}`)
    if (Math.abs(Number(d.bulk) - g.bulk) > 1e-9) say(`good ${g.code}.bulk: ${d.bulk} vs ${g.bulk}`)
    if (Math.abs(Number(d.perishable_pct_day) - g.perishable_pct_day) > 1e-9) say(`good ${g.code}.perishable: ${d.perishable_pct_day} vs ${g.perishable_pct_day}`)
    if (d.category !== g.category) say(`good ${g.code}.category: ${d.category} vs ${g.category}`)
    if (JSON.stringify(dMask) !== JSON.stringify(g.culture_mask)) say(`good ${g.code}.culture_mask: {${dMask}} vs {${g.culture_mask}}`)
  }

  // offers
  const dSpec = new Set(db_.spec.map((s) => `${s.port}|${s.good}`))
  const wSpec = new Set(want.specialtyPairs.map(([p, g]) => `${p}|${g}`))
  for (const k of wSpec) if (!dSpec.has(k)) say(`offer ${k.replace('|', '·')} is in a data roster but not in port_specialties`)
  for (const k of dSpec) if (!wSpec.has(k)) say(`offer ${k.replace('|', '·')} is in port_specialties but in no data roster`)

  // sea places
  const wPlaces = new Map(want.places.map((p) => [p.code, p]))
  for (const p of db_.places) if (!wPlaces.has(p.code)) say(`sea place ${p.code} (${p.name}) is in the database but not in data/sea-places.json`)
  for (const p of want.places) {
    const d = db_.places.find((x) => x.code === p.code)
    if (!d) { say(`sea place ${p.code} (${p.name}) is in data/sea-places.json but not in the database`); continue }
    if (d.name !== p.name) say(`sea place ${p.code}.name: ${d.name} vs ${p.name}`)
    if (Math.abs(Number(d.lat) - round2(p.lat)) > 1e-9 || Math.abs(Number(d.lon) - round2(p.lon)) > 1e-9) {
      say(`sea place ${p.code} sits at (${d.lat}, ${d.lon}); data says (${round2(p.lat)}, ${round2(p.lon)})`)
    }
  }

  // seas / regions / nations
  const setCheck = (dbRows, wantRows, what) => {
    const ds = new Set(dbRows.map((x) => `${x.code}|${x.name}`))
    const ws = new Set(wantRows.map((x) => `${x.code}|${x.name}`))
    for (const k of ws) if (!ds.has(k)) say(`${what} ${k.replace('|', ' ')} is derived from the data but absent from the database`)
    for (const k of ds) if (!ws.has(k)) say(`${what} ${k.replace('|', ' ')} is in the database but the data does not derive it`)
  }
  setCheck(db_.seas, want.seas, 'sea')
  setCheck(db_.regions, want.regions, 'region')
  setCheck(db_.nations, want.nations, 'nation')

  // market coverage
  const expected = want.ports.length * want.goods.length
  if (Number(db_.marketRows) !== expected) {
    say(`port_goods holds ${db_.marketRows} rows; ${want.ports.length} harbours × ${want.goods.length} goods = ${expected} — the market does not cover the world`)
  }

  // ships and gear (0129, S7): every catalogue row, both directions, as one line per row
  const dShips = new Set(db_.shipLines)
  const wShips = new Set(want.shipLines)
  for (const k of wShips) if (!dShips.has(k)) say(`ships/gear: ${k} — in data/*.json but not in the database`)
  for (const k of dShips) if (!wShips.has(k)) say(`ships/gear: ${k} — in the database but not in data/*.json`)

  return out
}

// ── SHIPS AND GEAR (0129, docs/SHIPS_AND_GEAR.md S7) ───────────────────────────────────────────
// data/ship_stats.json (classes, slots, cabins, level unlocks), data/hulls.json (recipes, coast,
// trading level), data/fittings.json (kinds, effects, recipes, the ship level a fitting asks) and
// data/npc-loadouts.json are the one authority for the ship and gear catalogue. Each table row is
// spelled as ONE canonical line — `table key col=value …` — from the data and from the database
// alike, and the two sets must be equal. Numbers go through Number() so 4.40 and 4.4 are the same.

const n = (v) => (v === null || v === undefined ? 'null' : String(Number(v)))
const arr = (v) => (v === null || v === undefined ? 'null' : JSON.stringify([...v]))
const SLOT_KINDS = ['rig', 'weapon', 'ground-tackle', 'steering', 'hull', 'lookout', 'flourish']

function classLine(c) {
  return `ship_classes ${c.code} name=${c.name} family=${c.family} rig=${c.rig} tier=${n(c.tier)} hold=${n(c.hold)} ` +
    `crew=${n(c.crew_required)}/${n(c.crew_max)} speed_kn=${n(c.speed_kn)} durability=${n(c.durability)} guns=${n(c.guns)} ` +
    `draft=${n(c.draft)} build_hours=${n(c.build_hours)} build_cost=${n(c.build_cost)} handling=${n(c.handling)} ` +
    `armour=${n(c.armour)} attack=${n(c.attack)} accuracy=${n(c.accuracy)} reach=${n(c.reach)} sighting=${n(c.sighting)} ` +
    `note=${c.stat_note}`
}

/** The catalogue as data/*.json says it, one line per row. */
export function shipLinesFromData(root) {
  const read = (f) => JSON.parse(readFileSync(join(root, 'data', f), 'utf8'))
  const stats = read('ship_stats.json')
  const hulls = read('hulls.json').hulls
  const fittings = read('fittings.json').fittings
  const loadouts = read('npc-loadouts.json').patterns
  const L = []
  for (const c of stats.classes) L.push(classLine({ ...c, code: c.class, stat_note: c.note }))
  for (const s of stats.slots) {
    for (const k of SLOT_KINDS) if (s[k] > 0) L.push(`class_slots ${s.class} ${k} count=${n(s[k])}`)
    L.push(`class_cabins ${s.class} cabins=${n(s.cabins)}`)
  }
  for (const u of stats.unlocks ?? []) L.push(`class_slot_unlocks ${u.class} ${u.slot} @${n(u.min_level)} count=${n(u.count)}`)
  for (const h of hulls) {
    L.push(`hull_recipes ${h.class} yard_tier=${n(h.yard_tier)} ducats=${n(h.ducats)} yard_regions=${arr(h.yard_regions)} ` +
      `min_level=${n(h.min_level ?? 1)} note=${h.note}`)
    for (const g of h.goods) L.push(`hull_recipe_goods ${h.class} ${g.in} qty=${n(g.qty)}`)
    for (const i of h.items) L.push(`hull_recipe_items ${h.class} ${i.in} qty=${n(i.qty)}`)
  }
  for (const f of fittings) {
    L.push(`item_kinds ${f.code} name=${f.name} slot=${f.slot} buys=${f.buys} spends=${f.spends} volume=${n(f.volume)} ` +
      `ws_tier=${n(f.ws_tier)} note=${f.note}`)
    for (const e of f.effects) L.push(`item_effects ${f.code} ${e.stat} delta=${n(e.delta)}`)
    for (const r of f.recipe) L.push(`item_recipes ${f.code} ${r.in} qty=${n(r.qty)}`)
    if ((f.min_level ?? 1) > 1) L.push(`item_level_asks ${f.code} min_level=${n(f.min_level)}`)
  }
  for (const p of loadouts) for (const i of p.items) L.push(`npc_loadouts ${p.class} #${n(p.pattern)} ${i.item} qty=${n(i.qty)}`)
  return L
}

/** The catalogue as the applied database holds it, one line per row. */
async function shipLinesFromDb(db) {
  const rows = async (sql) => (await db.query(sql)).rows
  const L = []
  for (const c of await rows(`select * from public.ship_classes`)) L.push(classLine(c))
  for (const r of await rows(`select class_code, slot, count from public.class_slots`)) L.push(`class_slots ${r.class_code} ${r.slot} count=${n(r.count)}`)
  for (const r of await rows(`select class_code, cabins from public.class_cabins`)) L.push(`class_cabins ${r.class_code} cabins=${n(r.cabins)}`)
  for (const r of await rows(`select class_code, slot, count, min_level from public.class_slot_unlocks`)) {
    L.push(`class_slot_unlocks ${r.class_code} ${r.slot} @${n(r.min_level)} count=${n(r.count)}`)
  }
  for (const r of await rows(`select class_code, yard_tier, ducats, yard_regions, min_level, note from public.hull_recipes`)) {
    L.push(`hull_recipes ${r.class_code} yard_tier=${n(r.yard_tier)} ducats=${n(r.ducats)} yard_regions=${arr(r.yard_regions)} ` +
      `min_level=${n(r.min_level)} note=${r.note}`)
  }
  for (const r of await rows(`select hg.class_code, g.code, hg.qty from public.hull_recipe_goods hg join public.goods g on g.id = hg.good_id`)) {
    L.push(`hull_recipe_goods ${r.class_code} ${r.code} qty=${n(r.qty)}`)
  }
  for (const r of await rows(`select class_code, item_code, qty from public.hull_recipe_items`)) L.push(`hull_recipe_items ${r.class_code} ${r.item_code} qty=${n(r.qty)}`)
  for (const r of await rows(`select * from public.item_kinds`)) {
    L.push(`item_kinds ${r.code} name=${r.name} slot=${r.slot} buys=${r.buys} spends=${r.spends} volume=${n(r.volume)} ` +
      `ws_tier=${n(r.ws_tier)} note=${r.note}`)
  }
  for (const r of await rows(`select item_code, stat, delta from public.item_effects`)) L.push(`item_effects ${r.item_code} ${r.stat} delta=${n(r.delta)}`)
  for (const r of await rows(`select ir.item_code, g.code, ir.qty from public.item_recipes ir join public.goods g on g.id = ir.good_id`)) {
    L.push(`item_recipes ${r.item_code} ${r.code} qty=${n(r.qty)}`)
  }
  for (const r of await rows(`select item_code, min_level from public.item_level_asks`)) L.push(`item_level_asks ${r.item_code} min_level=${n(r.min_level)}`)
  for (const r of await rows(`select class_code, pattern, item_code, qty from public.npc_loadouts`)) {
    L.push(`npc_loadouts ${r.class_code} #${n(r.pattern)} ${r.item_code} qty=${n(r.qty)}`)
  }
  return L
}

/**
 * The standing check. Reads the applied world from `db` (a live PGlite/PG connection), derives
 * the wanted world from data/*.json, and THROWS with every difference if they are not equal.
 * apply-chain.mjs calls this after the last migration, so every local and CI apply is gated.
 */
export async function assertWorldMatchesData(db, { log = console.log } = {}) {
  const hasKind = (await db.query(
    `select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'ports' and column_name = 'kind'`,
  )).rows.length > 0
  if (!hasKind) throw new Error('world-guard: ports.kind is missing — the chain no longer reaches 0036, so this guard cannot tell harbours from sea places')

  const db_ = {}
  db_.ports = (await db.query(`
    select p.code, p.name, p.country, n.code as nation_code, p.lat::float8 lat, p.lon::float8 lon,
           s.code as sea_code, r.code as region_code, p.culture, p.size_tier, p.max_draft,
           p.has_yard, p.yard_tier, p.has_academy, p.dev_industry, p.dev_commerce, p.dev_military
      from public.ports p
      join public.seas s on s.id = p.sea_id
      join public.regions r on r.id = p.region_id
      left join public.nations n on n.id = p.nation_id
     where p.kind = 'HARBOUR' order by p.code`)).rows
  db_.places = (await db.query(`
    select p.code, p.name, p.lat::float8 lat, p.lon::float8 lon
      from public.ports p where p.kind = 'SEA_PLACE' order by p.code`)).rows
  db_.goods = (await db.query(`
    select code, name, base_value::float8 base_value, bulk::float8 bulk,
           perishable_pct_day::float8 perishable_pct_day, category, culture_mask,
           origin_regions, entrepot_ports
      from public.goods order by code`)).rows
  db_.spec = (await db.query(`
    select p.code as port, g.code as good from public.port_specialties s
      join public.ports p on p.id = s.port_id join public.goods g on g.id = s.good_id`)).rows
  db_.seas = (await db.query(`select code, name from public.seas`)).rows
  db_.regions = (await db.query(`select code, name from public.regions`)).rows
  db_.nations = (await db.query(`select code, name from public.nations`)).rows
  db_.marketRows = (await db.query(`select count(*)::int as n from public.port_goods`)).rows[0].n
  db_.shipLines = await shipLinesFromDb(db)

  const want = deriveWorld()
  want.places = JSON.parse(readFileSync(join(REPO_ROOT, 'data', 'sea-places.json'), 'utf8')).places
  want.shipLines = shipLinesFromData(REPO_ROOT)

  // ── POSITIVE CONTROL: the comparator must SEE a planted drift before it may certify zero ─────
  // 0129: and a dropped ship class and a bent fitting effect, both directions of the ships lines.
  const droppedClass = want.shipLines.find((s) => s.startsWith('ship_classes '))
  const bentEffect = want.shipLines.find((s) => s.startsWith('item_effects '))
  const wounded = {
    ...want,
    ports: want.ports.slice(1),                                      // one harbour dropped
    goods: want.goods.map((g, i) => (i === 0 ? { ...g, base_value: g.base_value + 500 } : g)), // one value bent
    shipLines: want.shipLines.filter((s) => s !== droppedClass)      // one class dropped
      .map((s) => (s === bentEffect ? s.replace(/delta=(\S+)$/, (_, d) => `delta=${Number(d) + 7}`) : s)), // one effect bent
  }
  const seen = drift(db_, wounded)
  const sawDrop = seen.some((s) => s.includes(`${want.ports[0].code}`))
  const sawBend = seen.some((s) => s.includes('.base_value:'))
  const sawClass = seen.some((s) => s.includes(droppedClass) && s.endsWith('in the database but not in data/*.json'))
  const sawEffect = seen.some((s) => s.includes(bentEffect) && s.endsWith('in the database but not in data/*.json'))
    && seen.some((s) => s.startsWith('ships/gear: item_effects ') && s.endsWith('in data/*.json but not in the database'))
  if (!sawDrop || !sawBend || !sawClass || !sawEffect) {
    throw new Error(
      'WORLD GUARD IS BLIND: a deliberately dropped harbour ' +
        `(${want.ports[0].code}), bent good value, dropped ship class or bent fitting effect was NOT reported by ` +
        `the comparator (saw ${seen.length} finding(s)). A guard that cannot see a planted drift certifies nothing.`,
    )
  }

  const findings = drift(db_, want)
  if (findings.length > 0) {
    const head = findings.slice(0, 40)
    throw new Error(
      [
        'WORLD DRIFT: the applied chain and data/*.json disagree ' +
          `(${findings.length} difference(s)). The world the players get is not the world the data ` +
          'describes. If the data moved, generate a growth migration ' +
          '(scripts/build-world-growth.mjs); a shipped migration is never edited.',
        ...head.map((s) => `  * ${s}`),
        findings.length > head.length ? `  … and ${findings.length - head.length} more` : null,
      ].filter(Boolean).join('\n'),
    )
  }

  log(
    `world-guard ok: the applied world EQUALS data/*.json — ${want.ports.length} harbours, ` +
      `${want.goods.length} goods, ${want.specialtyPairs.length} offers, ` +
      `${want.places.length} sea places, ${db_.marketRows} market rows, ${want.shipLines.length} ship/gear catalogue rows ` +
      `(positive control: a planted dropped-harbour, bent-good-value, dropped-class and bent-effect were all seen)`,
  )
}

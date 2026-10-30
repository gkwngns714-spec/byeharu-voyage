// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-raw-goods-migration.mjs — emit 0280 from docs/design/raw-materials-economy/*.csv
//
// WHAT IT WRITES
//   * supabase/migrations/20260818000280_every_city_makes_one_or_two_things.sql
//   * data/goods.json — a `tier` on every good, and the 64 goods the design needs but the
//     catalogue did not yet carry.
//
// THE THREE SOURCES, and why each is read
//   GOODS_SAVED.csv  the complete catalogue: 565 existing goods + 19 NEW design goods, each with
//                    its tier (0 raw, 1-3 crafted). The 565 ids are the same 565 in data/goods.json.
//   RECIPES.csv      287 crafted goods -> 2-6 distinct ingredients + integer quantities.
//   RAW_MATERIALS.csv / CITY_RAW.csv  the raw-material vocabulary (305) and the ports that
//                    historically supplied each; the 45 ingredients a recipe names that are NOT
//                    yet catalogue goods are added as tier-0 goods (design gap, owner 2026-10-30).
//
// THE CITY-PRODUCTION RULE (decided by default; the owner reverses it)
//   * Every harbour produces 1-2 goods, stored in public.city_production with rank 1/2.
//   * Size decides the tier ceiling and the count (prod ports.size_tier: 5 -> 3 & 2 outputs,
//     3 -> 2 & 2 outputs, 2 -> 1 & 1 output). Bigger cities therefore make higher-tier goods.
//   * The first output of a big/middling city is its highest-tier authored roster good within the
//     ceiling (data/ports.json `goods`); that keeps 0062's native-or-entrepot law true.
//   * Every raw good the catalogue holds is guaranteed at least one producing harbour (a
//     bipartite matching over historically-native ports), so no good is unbuyable and no recipe
//     is orphaned when the quay later sells only what a city makes.
//   * A city's INPUT DEMAND is derived, never stored: the recipe ingredients of what it produces,
//     minus what it makes itself. public.city_inputs(port) is the one reading.
//
// THIS FILE IS A GENERATOR, never a migration. Run it after editing the design CSVs.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { deriveWorld } from './lib/world-derive.mjs'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.resolve(HERE, '..')
const DESIGN = path.join(ROOT, 'docs', 'design', 'raw-materials-economy')
const MIGRATION_NAME = '20260818000280_every_city_makes_one_or_two_things.sql'

// ── CSV ────────────────────────────────────────────────────────────────────────────────────────
function parseCsv(text) {
  text = text.replace(/^﻿/, '')
  const rows = []
  let row = []
  let field = ''
  let quoted = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++ } else quoted = false
      } else field += c
      continue
    }
    if (c === '"') { quoted = true; continue }
    if (c === ',') { row.push(field); field = ''; continue }
    if (c === '\n') { row.push(field); rows.push(row); row = []; field = ''; continue }
    if (c === '\r') continue
    field += c
  }
  if (field.length || row.length) { row.push(field); rows.push(row) }
  const header = rows.shift()
  return rows
    .filter((r) => r.length > 1 || (r[0] ?? '') !== '')
    .map((r) => Object.fromEntries(header.map((h, j) => [h, r[j] ?? ''])))
}
const csv = (name) => parseCsv(readFileSync(path.join(DESIGN, name), 'utf8'))
const slurpJson = (rel) => JSON.parse(readFileSync(path.join(ROOT, rel), 'utf8'))
const sorted = (xs) => [...xs].sort()

// ── Sources ───────────────────────────────────────────────────────────────────────────────────
const saved = csv('GOODS_SAVED.csv')
const recipesCsv = csv('RECIPES.csv')
const rawCsv = csv('RAW_MATERIALS.csv')
const cityCsv = csv('CITY_RAW.csv')
const goodsDoc = slurpJson('data/goods.json')
const portsDoc = slurpJson('data/ports.json')
const regionsDoc = slurpJson('data/regions.json')

// The database keys ports and regions by CODE (ACA, LIS, IBE…), while data/*.json keys them by id
// (acapulco, lisbon, iberia). This is the SAME one derivation the world guard uses; the generator
// must not invent a second mapping.
const derived = deriveWorld()
const PORT_CODE = derived.portCode
const REGION_CODE = derived.regionCode
const codeOfPort = (id) => {
  const c = PORT_CODE.get(id)
  if (!c) throw new Error(`port ${id} has no derived code`)
  return c
}
const codeOfRegion = (id) => {
  const c = REGION_CODE.get(id)
  if (!c) throw new Error(`region ${id} has no derived code`)
  return c
}

const tierOf = new Map(saved.map((g) => [g.id, Number(g.tier)]))
const savedById = new Map(saved.map((g) => [g.id, g]))
const rawByCode = new Map(rawCsv.map((r) => [r.code, r]))
const regionByName = new Map(regionsDoc.regions.map((r) => [r.name, r.id]))
const roster = new Map(portsDoc.ports.map((p) => [p.id, p.goods]))
const portTier = new Map(portsDoc.ports.map((p) => [p.id, p.tier]))
const portRegion = new Map(portsDoc.ports.map((p) => [p.id, p.region]))
const cityRaw = new Map(cityCsv.map((c) => [c.port_id, c.raw_materials.split(',').map((s) => s.trim()).filter(Boolean)]))
const providing = new Map(rawCsv.map((r) => [r.code, new Set(r.providing_cities.split(',').map((s) => s.trim()).filter((p) => roster.has(p)))]))

const GOODS = sorted([...tierOf.keys()])
if (GOODS.length !== 584) throw new Error(`GOODS_SAVED has ${GOODS.length} rows, expected 584`)

// ── Category / bulk / value defaults for the goods the design left unpriced ───────────────────
const CAT_BULK = {
  spice: 1.0, cloth: 0.9, metal: 0.8, guns: 0.9, crafts: 0.5, weapons: 0.8, gems: 0.2,
  medicine: 0.5, books: 0.4, art: 0.3, animals: 1.5, grain: 1.2, food: 1.0, drink: 1.0,
  tobacco: 0.8, dye: 0.7, 'ship-supplies': 1.4,
}
const RAW_CATEGORY = {
  Food: 'food', Marine: 'food', Mineral: 'metal', Timber: 'ship-supplies', Fibre: 'cloth',
  Animal: 'animals', Medicine: 'medicine', Dyestuff: 'dye', Gemstone: 'gems', Resin: 'crafts',
  Water: 'ship-supplies',
}
const RAW_BASE = {
  food: 20, metal: 30, 'ship-supplies': 25, cloth: 30, animals: 40, medicine: 50, dye: 40,
  gems: 200, crafts: 40,
}
const parseRange = (s) => {
  const m = String(s).match(/\[\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\]/)
  if (!m) throw new Error(`cannot parse baseValue ${s}`)
  return [Number(m[1]), Number(m[2])]
}
const splitList = (s) => String(s ?? '').split(',').map((x) => x.trim()).filter(Boolean)

// ── The 19 design-NEW goods ───────────────────────────────────────────────────────────────────
const designNew = saved.filter((g) => g.source.startsWith('NEW'))
if (designNew.length !== 19) throw new Error(`design NEW goods ${designNew.length}, expected 19`)
const designNewGoods = designNew.map((g) => {
  const [lo, hi] = parseRange(g.baseValue)
  return {
    id: g.id,
    name: g.name,
    category: g.category,
    valueBand: Number(g.valueBand),
    baseValue: [lo, hi],
    note: g.recipe || g.source,
    origin: splitList(g.origin),
    cultureMask: [],
    entrepots: splitList(g.entrepots),
    bulk: CAT_BULK[g.category] ?? 1.0,
    tier: Number(g.tier),
    source: 'new-design',
  }
})

// ── The 45 recipe ingredients that are not yet catalogue goods ────────────────────────────────
// Every ingredient named by RECIPES must resolve to a good. The design's raw vocabulary (305)
// is finer than the catalogue (565): 45 codes it uses were never goods. They are added as tier-0
// goods, because the owner's model makes those raw inputs the things a city imports.
const ingredientCodes = new Set()
for (const r of recipesCsv) for (let i = 1; i <= 6; i++) if (r[`ingredient_${i}`]) ingredientCodes.add(r[`ingredient_${i}`])
const missingGoods = sorted([...ingredientCodes].filter((c) => !tierOf.has(c)))
const missingRawGoods = missingGoods.map((code) => {
  const raw = rawByCode.get(code)
  if (!raw) throw new Error(`ingredient ${code} is neither a catalogue good nor a RAW_MATERIALS row`)
  const category = RAW_CATEGORY[raw.category]
  if (!category) throw new Error(`raw ${code} has category ${raw.category}, no catalogue mapping`)
  const water = code === 'fresh-water'
  const value = water ? 4 : RAW_BASE[category]
  const origin = sorted(new Set(String(raw.real_region).split(';').map((s) => s.trim()).filter(Boolean).map((n) => {
    const id = regionByName.get(n)
    if (!id) throw new Error(`raw ${code} names region "${n}", which data/regions.json does not define`)
    return id
  })))
  return {
    id: code,
    name: raw.name,
    category,
    valueBand: 1,
    baseValue: [value, value],
    note: raw.notes,
    origin,
    cultureMask: [],
    entrepots: [],
    bulk: water ? 1.0 : (CAT_BULK[category] ?? 1.0),
    tier: 0,
    source: 'new-raw-input',
  }
})

const newGoods = [...designNewGoods, ...missingRawGoods]
const newIds = new Set(newGoods.map((g) => g.id))
if (newIds.size !== 64) throw new Error(`new goods ${newIds.size}, expected 64 (19 design + 45 raw inputs)`)

// The generator is IDEMPOTENT: data/goods.json may already carry the 64 goods from an earlier run,
// so the authored 565 are whatever remains after removing them.
const baseGoods = goodsDoc.goods.filter((g) => !newIds.has(g.id))
const existingById = new Map(baseGoods.map((g) => [g.id, g]))
const existingIds = new Set(baseGoods.map((g) => g.id))
if (existingIds.size !== 565) throw new Error(`data/goods.json has ${existingIds.size} authored goods, expected 565`)
for (const g of newGoods) if (existingIds.has(g.id)) throw new Error(`new good ${g.id} already exists`)

// The complete tier map the migration writes: 565 existing (from the design), 19 design new, 45 raw.
const allTiers = new Map([...tierOf])
for (const g of newGoods) allTiers.set(g.id, g.tier)
for (const id of existingIds) if (!allTiers.has(id)) throw new Error(`existing good ${id} has no tier in GOODS_SAVED`)

// ── Origins the design left blank on the 19 new goods ────────────────────────────────────────
// check-ports.mjs refuses a good with no origin (0062's law), and the 19 design goods carry an
// empty `origin`. A raw takes its RAW_MATERIALS real_region; a crafted good takes the union of
// its ingredients' origins — the regions where it can actually be made.
const ingByProduct = new Map()
for (const r of recipesCsv) {
  const ings = []
  for (let i = 1; i <= 6; i++) if (r[`ingredient_${i}`]) ings.push(r[`ingredient_${i}`])
  ingByProduct.set(r.good_id, ings)
}
const regionSetFromRaw = (raw) => new Set(String(raw.real_region).split(';').map((s) => s.trim()).filter(Boolean).map((n) => {
  const id = regionByName.get(n)
  if (!id) throw new Error(`raw ${raw.code} names region "${n}", which data/regions.json does not define`)
  return id
}))
function deriveOrigin(g, seen = new Set()) {
  if (existingById.has(g)) return new Set(existingById.get(g).origin ?? [])
  const n = newGoods.find((x) => x.id === g)
  if (!n) return new Set()
  if (n.origin.length) return new Set(n.origin)
  if (n.tier === 0 && rawByCode.has(g)) return regionSetFromRaw(rawByCode.get(g))
  if (seen.has(g)) return new Set()
  seen.add(g)
  const s = new Set()
  for (const i of ingByProduct.get(g) ?? []) for (const r of deriveOrigin(i, seen)) s.add(r)
  return s
}
for (const g of newGoods) {
  if (g.origin.length) continue
  const o = sorted(deriveOrigin(g.id))
  if (!o.length) throw new Error(`new good ${g.id} derives no origin region`)
  g.origin = o
}

// ── Native-or-entrepot, the 0062 law, over the catalogue + the new raw inputs ─────────────────
const originOf = (g) => {
  if (existingById.has(g)) return [new Set(existingById.get(g).origin ?? []), new Set(existingById.get(g).entrepots ?? [])]
  const n = newGoods.find((x) => x.id === g)
  if (n) return [new Set(n.origin), new Set(n.entrepots)]
  throw new Error(`no origin for ${g}`)
}
const native = (port, good) => {
  const [o, e] = originOf(good)
  return o.has(portRegion.get(port)) || e.has(port)
}

// ── Every RAW good must have a producer somewhere ────────────────────────────────────────────
// Not only recipe ingredients: if the quay later sells only what a city makes, a raw good with no
// producing harbour would be unbuyable anywhere. 246 harbours x 2 slots is 492, above the 342 raw
// goods, so the model can cover the whole raw catalogue.
const rawTargets = sorted([...allTiers.keys()].filter((g) => allTiers.get(g) === 0))
const producersOf = (g) => {
  const s = new Set(providing.get(g) ?? [])
  for (const p of roster.keys()) if (roster.get(p).includes(g) || cityRaw.get(p)?.includes(g)) s.add(p)
  const curated = sorted([...s].filter((p) => native(p, g)))
  if (curated.length) return curated
  // A design-new raw (milk, eggs) has no RAW_MATERIALS row; its authored origin regions are the
  // historical supply fact, so every native harbour is a legitimate producer.
  return sorted([...roster.keys()].filter((p) => native(p, g)))
}

// ── Machinery: a bipartite matching (Kuhn) raw ingredient -> a reserved producing slot ────────
// A city that can make a crafted good keeps one slot for it; a city with no crafted candidate
// offers both slots to raw coverage. This guarantees every raw ingredient in a recipe has at
// least one producing harbour, without letting a small city exceed its 1-2 outputs.
const cap = (t) => (t === 1 ? 3 : t === 2 ? 2 : 1)
const craftedCandidates = new Map()
for (const p of portsDoc.ports) {
  const c = cap(p.tier)
  const list = p.goods.filter((g) => (allTiers.get(g) ?? 0) >= 1 && (allTiers.get(g) ?? 0) <= c)
  list.sort((a, b) => (allTiers.get(b) - allTiers.get(a)) || (p.goods.indexOf(a) - p.goods.indexOf(b)))
  craftedCandidates.set(p.id, list)
}
const adj = new Map(rawTargets.map((g) => [g, producersOf(g).sort((a, b) =>
  (craftedCandidates.get(a).length ? 1 : 0) - (craftedCandidates.get(b).length ? 1 : 0) ||
  (portTier.get(a) ?? 9) - (portTier.get(b) ?? 9) ||
  a.localeCompare(b))]))
const fitOrder = [...rawTargets].sort((a, b) => adj.get(a).length - adj.get(b).length || a.localeCompare(b))

// First pass: a city that can make a crafted good keeps one of its slots for it. If the raw
// catalogue cannot fit in the remaining slots, fall back to two raw slots everywhere and add
// crafted goods only where a slot is still free — the owner's 1-2 outputs hold either way.
function runMatch(capOf) {
  const matchSlot = new Map() // `${port}#${slot}` -> raw
  const matchIngredient = new Map()
  function augment(ing, seen) {
    for (const port of adj.get(ing)) {
      const n = Math.min(2, capOf(port))
      for (let k = 0; k < n; k++) {
        const key = `${port}#${k}`
        if (seen.has(key)) continue
        seen.add(key)
        if (!matchSlot.has(key) || augment(matchSlot.get(key), seen)) {
          matchSlot.set(key, ing)
          matchIngredient.set(ing, key)
          return true
        }
      }
    }
    return false
  }
  for (const ing of fitOrder) if (!augment(ing, new Set())) {
    const missing = fitOrder.filter((x) => !matchIngredient.has(x))
    return { ok: false, missing }
  }
  return { ok: true, matchSlot, matchIngredient }
}
let matched = runMatch((port) => (craftedCandidates.get(port).length ? 1 : 2))
if (!matched.ok) {
  const second = runMatch(() => 2)
  if (!second.ok) throw new Error(`no producing harbour for raw good(s): ${second.missing.join(', ')}`)
  matched = second
}
const { matchSlot, matchIngredient } = matched

const production = new Map(portsDoc.ports.map((p) => [p.id, []]))
for (const [key, ing] of matchSlot) production.get(key.split('#')[0]).push(ing)

// 1. A crafted output wherever a slot is still free, biggest cities first.
for (const tier of [1, 2]) {
  for (const p of portsDoc.ports.filter((x) => x.tier === tier)) {
    if (production.get(p.id).length >= 2) continue
    const crafted = craftedCandidates.get(p.id).find((g) => !production.get(p.id).includes(g))
    if (crafted) production.get(p.id).push(crafted)
  }
}
// 2. Local repair: where a raw catalogue bottleneck filled a crafted-capable city's two slots,
//    move one raw to a harbour with a free slot (preferring small, non-crafted harbours) and put
//    the crafted good back. Only a structural bottleneck keeps a city on two raws.
for (const tier of [1, 2]) {
  for (const p of portsDoc.ports.filter((x) => x.tier === tier)) {
    if (production.get(p.id).length !== 2 || !craftedCandidates.get(p.id).length) continue
    const crafted = craftedCandidates.get(p.id).find((g) => !production.get(p.id).includes(g))
    if (!crafted) continue
    for (const raw of [...production.get(p.id)]) {
      const dests = (adj.get(raw) ?? []).filter((q) =>
        q !== p.id && production.get(q).length < 2 && !production.get(q).includes(raw))
      const dest = dests.find((q) => !craftedCandidates.get(q).length) ?? dests[0]
      if (!dest) continue
      production.set(p.id, production.get(p.id).filter((g) => g !== raw))
      production.get(dest).push(raw)
      production.get(p.id).push(crafted)
      break
    }
  }
}
// 3. Every harbour makes at least one thing.
for (const p of portsDoc.ports) {
  if (production.get(p.id).length) continue
  const crafted = craftedCandidates.get(p.id).find((g) => !production.get(p.id).includes(g))
  if (crafted) { production.get(p.id).push(crafted); continue }
  const pool = [...p.goods.filter((g) => (allTiers.get(g) ?? 0) === 0), ...(cityRaw.get(p.id) ?? [])]
  const pick = pool.find((g) => native(p.id, g) && allTiers.has(g) && !production.get(p.id).includes(g))
  if (!pick) throw new Error(`port ${p.id} has no native output`)
  production.get(p.id).push(pick)
}
for (const p of portsDoc.ports) {
  // deterministic rank: highest tier first, then earlier in the authored roster / raw list
  const order = (g) => [allTiers.get(g), p.goods.indexOf(g) >= 0 ? p.goods.indexOf(g) : 100 + (cityRaw.get(p.id) ?? []).indexOf(g), g]
  production.get(p.id).sort((a, b) => {
    const [ta, ia, ca] = order(a); const [tb, ib, cb] = order(b)
    return tb - ta || ia - ib || ca.localeCompare(cb)
  })
}

// ── Recipe rows ──────────────────────────────────────────────────────────────────────────────
const recipeRows = []
for (const r of recipesCsv) {
  const tier = Number(r.tier)
  if (tier !== allTiers.get(r.good_id)) throw new Error(`recipe ${r.good_id}: tier ${tier} != goods tier ${allTiers.get(r.good_id)}`)
  const ings = []
  for (let i = 1; i <= 6; i++) {
    const g = r[`ingredient_${i}`]
    if (!g) continue
    if (!allTiers.has(g)) throw new Error(`recipe ${r.good_id}: ingredient ${g} not a good`)
    if (g === r.good_id) throw new Error(`recipe ${r.good_id}: self-ingredient`)
    if (allTiers.get(g) >= tier) throw new Error(`recipe ${r.good_id}: ingredient ${g} tier ${allTiers.get(g)} >= ${tier}`)
    ings.push([g, Number(r[`qty_${i}`])])
  }
  if (ings.length < 2 || ings.length > 6) throw new Error(`recipe ${r.good_id}: ${ings.length} ingredients`)
  if (new Set(ings.map((x) => x[0])).size !== ings.length) throw new Error(`recipe ${r.good_id}: duplicate ingredients`)
  recipeRows.push({ product: r.good_id, tier, ings })
}
if (recipeRows.length !== 287) throw new Error(`recipes ${recipeRows.length}, expected 287`)

// ── Input demand (derived; kept here only to report the figure) ──────────────────────────────
const recipeByProduct = new Map(recipeRows.map((r) => [r.product, r.ings.map((x) => x[0])]))
const inputDemand = new Map()
for (const p of portsDoc.ports) {
  const made = production.get(p.id)
  const demand = new Set()
  for (const g of made) for (const ing of recipeByProduct.get(g) ?? []) if (!made.includes(ing)) demand.add(ing)
  inputDemand.set(p.id, sorted(demand))
}

// ── data/goods.json: a tier on every good, then the 64 new goods ─────────────────────────────
const mergedGoods = baseGoods.map((g) => {
  if (!allTiers.has(g.id)) throw new Error(`data/goods.json good ${g.id} has no tier`)
  return { ...g, tier: allTiers.get(g.id) }
})
for (const g of newGoods.slice().sort((a, b) => a.id.localeCompare(b.id))) {
  mergedGoods.push({
    id: g.id,
    name: g.name,
    category: g.category,
    valueBand: g.valueBand,
    baseValue: g.baseValue,
    note: g.note,
    origin: g.origin,
    cultureMask: g.cultureMask,
    entrepots: g.entrepots,
    bulk: g.bulk,
    tier: g.tier,
  })
}
const nextGoodsDoc = { ...goodsDoc, goods: mergedGoods }
writeFileSync(path.join(ROOT, 'data', 'goods.json'), JSON.stringify(nextGoodsDoc, null, 2) + '\n', 'utf8')

// ── SQL helpers ──────────────────────────────────────────────────────────────────────────────
const q = (s) => `'${String(s).replace(/'/g, "''")}'`
const arr = (xs) => `array[${xs.map(q).join(', ')}]::text[]`
const tierValues = [...allTiers.entries()].sort((a, b) => a[0].localeCompare(b[0]))
const goodsRowsSql = newGoods
  .slice()
  .sort((a, b) => a.id.localeCompare(b.id))
  .map((g) => `  (${q(g.id)}, ${q(g.name)}, ${((g.baseValue[0] + g.baseValue[1]) / 2).toFixed(2)} * public.wc_num('goods_price_level'), ${g.bulk.toFixed(3)}, 0.000, ${q(g.category)}, '{}', ${arr(g.origin.map(codeOfRegion).sort())}, ${arr(g.entrepots.map(codeOfPort).sort())}, false, ${g.tier})`)
  .join(',\n')
const recipeRowsSql = recipeRows
  .slice()
  .sort((a, b) => a.product.localeCompare(b.product))
  .flatMap((r) => r.ings.map(([ing, qty]) => `  (${q(r.product)}, ${q(ing)}, ${qty}, ${r.tier})`))
  .join(',\n')
const productionRowsSql = portsDoc.ports
  .slice()
  .sort((a, b) => a.id.localeCompare(b.id))
  .flatMap((p) => production.get(p.id).map((g, i) => `  (${q(codeOfPort(p.id))}, ${q(g)}, ${i + 1})`))
  .join(',\n')
const recipeExpectedRows = recipeRows.reduce((n, r) => n + r.ings.length, 0)
const productionExpectedRows = [...production.values()].reduce((n, v) => n + v.length, 0)
const producedCount = new Set([...production.values()].flat()).size

const sql = `-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0280 — EVERY CITY MAKES ONE OR TWO THINGS
--        The raw-material / multi-tier economy, as DATA: a tier and an is_raw flag on every good,
--        the 287 recipes, each city's 1-2 production outputs and the input demand derived from
--        them. This file changes NO price, restock, market or quay function — the sim slice that
--        reads this data is a later slice (see the dev-log).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- GENERATED by scripts/build-raw-goods-migration.mjs from docs/design/raw-materials-economy/*.csv.
-- Do not hand-edit: edit the design or the generator and run it again.
--
-- ── THE OWNER (2026-10-30) ───────────────────────────────────────────────────────────────────────
--   "in each cities, the city will produce 1~2 items. Therefore those raw materials needed will be
--    sold at higher prices. bigger cities will produce an higher tier trade goods. All should be
--    considered as real-time world region too."
--
-- ── WHAT LANDS HERE (all DATA; no sim) ──────────────────────────────────────────────────────────
--   * goods.tier 0-3 and the generated goods.is_raw (tier = 0). 565 existing + 19 design-new +
--     45 raw inputs the design's recipes name but the catalogue never carried = 629 goods.
--   * public.goods_recipes: ${recipeRows.length} recipes, ${recipeExpectedRows} ingredient rows. Every ingredient is a good;
--     2-6 DISTINCT ingredients; ingredient tier < product tier; no self-ingredient; acyclic.
--   * public.city_production: ${productionExpectedRows} rows, 1-2 outputs per harbour. Bigger cities make higher tiers
--     (size_tier 5 -> up to tier 3, 3 -> up to tier 2, 2 -> tier 0). Every raw good has at least
--     one producing harbour, so no good is unbuyable when the quay is re-cut to this table.
--   * public.city_inputs(port) / public.city_wants_input(port, good): the derived import demand
--     (the recipe ingredients of what the city makes, minus what it makes itself). Server-only.
--   * port_goods rows for the 64 new goods, seeded with 0005's own arithmetic from city_production.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
--   * No price, restock, drift, season, region-taste or quay function is re-cut. port_offers,
--     world.price_why, world.mid_terms, world.quote, public.restock_rate and public.port_offered_goods
--     are byte-identical before and after (asserted). The DATA is dark until the sim slice:
--       1. re-cut public.port_offered_goods to read city_production (the quay sells what is made);
--       2. add the input-demand premium for city_inputs to world.mid_terms / world.quote_priced;
--       3. add the real-time region factor (see the dev-log: what exists today and what is missing);
--       4. re-derive port_goods.affinity and rarity from city_production (they still read
--          port_specialties, the historical roster) and serve tier/is_raw on snapshot/market.
--   * Nothing is DELETEd from an append-only table. Existing goods and market rows are untouched;
--     the migration only ADDS rows and columns. The reverse is at the foot of the dev-log.
--
-- Depends on: 0002 (goods/ports), 0005 (world.affinity_at and the market arithmetic),
--             0065 (the grown catalogue), 0136 (port_offered_goods), 0245 (restock).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '15min', true);
  perform set_config('lock_timeout', '5s', true);
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'goods' and column_name = 'tier') then
    raise exception '0280 refuses: goods.tier already exists';
  end if;
  if to_regclass('public.goods_recipes') is not null or to_regclass('public.city_production') is not null then
    raise exception '0280 refuses: a table this migration creates already exists';
  end if;
  if (select count(*) from public.goods) <> 565 then
    raise exception '0280 refuses: the catalogue is % goods, this file was cut against 565', (select count(*) from public.goods);
  end if;
end $guard$;

create or replace function pg_temp.occurs_0280(p_hay text, p_needle text)
returns int language sql immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGE: the affected tables, and the functions this file promises not to move ───
create temp table pre_0280 on commit drop as
select
  (select count(*) from public.goods) as goods_n,
  (select count(*) from public.port_goods) as port_goods_n,
  (select count(*) from public.port_specialties) as specialties_n,
  (select md5(coalesce(string_agg(g.code || '|' || g.name || '|' || g.base_value || '|' || g.bulk || '|' ||
      g.perishable_pct_day || '|' || g.category || '|' || array_to_string(g.culture_mask, ',') || '|' ||
      array_to_string(g.origin_regions, ',') || '|' || array_to_string(g.entrepot_ports, ',') || '|' || g.industry,
      E'\\n' order by g.code), '')) from public.goods g) as goods_hash,
  (select md5(coalesce(string_agg(pg.port_id::text || '|' || pg.good_id::text || '|' || pg.affinity || '|' ||
      pg.stock || '|' || pg.stock_target || '|' || pg.production_rate || '|' || pg.drift || '|' || pg.season_mod,
      E'\\n' order by pg.port_id, pg.good_id), '')) from public.port_goods pg) as port_goods_hash,
  (select md5(coalesce(string_agg(ps.port_id::text || '|' || ps.good_id::text,
      E'\\n' order by ps.port_id, ps.good_id), '')) from public.port_specialties ps) as specialties_hash;

create temp table defs_pre_0280 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\\r', '') as def
  from (values ('world.price_why(uuid, uuid)'),
               ('world.mid_terms(uuid, uuid)'),
               ('world.price(uuid, uuid)'),
               ('world.quote(uuid, uuid, numeric, text, numeric, uuid)'),
               ('public.restock_rate(uuid)'),
               ('public.port_offers(uuid, uuid)'),
               ('public.port_offered_goods(uuid)')) f(fn);

-- ── 1. TIER AND IS_RAW ─────────────────────────────────────────────────────────────────────────
alter table public.goods add column tier int not null default 0;
alter table public.goods add constraint goods_tier_range check (tier between 0 and 3);
alter table public.goods add column is_raw boolean generated always as (tier = 0) stored;
comment on column public.goods.tier is
  '0280: 0 = a raw material a city produces; 1-3 = a crafted good, made by the Forge and, in the '
  'larger cities, by the city itself. A recipe''s ingredients are always a strictly lower tier.';
comment on column public.goods.is_raw is
  '0280: generated from tier = 0. The raw/crafted split is never a second authored fact.';

-- The 565 existing goods take the design's tier. New goods carry theirs in the INSERT below.
update public.goods g set tier = v.tier
  from (values
${tierValues.map(([id, t]) => `    (${q(id)}, ${t})`).join(',\n')}
  ) v(code, tier)
 where g.code = v.code;

-- ── 2. THE 64 NEW GOODS: 19 design additions + the 45 raw inputs a recipe names ───────────────
insert into public.goods (code, name, base_value, bulk, perishable_pct_day, category, culture_mask,
                          origin_regions, entrepot_ports, industry, tier) values
${goodsRowsSql};

-- ── 3. THE RECIPES ────────────────────────────────────────────────────────────────────────────
create table public.goods_recipes (
  product_id    uuid not null references public.goods(id) on delete cascade,
  ingredient_id uuid not null references public.goods(id) on delete cascade,
  qty           int  not null check (qty between 1 and 99),
  tier          int  not null check (tier between 1 and 3),  -- the product's tier; asserted = goods.tier
  primary key (product_id, ingredient_id),
  check (product_id <> ingredient_id)
);
create index goods_recipes_ingredient_idx on public.goods_recipes (ingredient_id);
comment on table public.goods_recipes is
  '0280: THE recipe graph. One row per (product, ingredient): a product has 2-6 distinct '
  'ingredients, each of a strictly lower tier; ingredient_id and product_id are goods. '
  'tier restates the product''s goods.tier for the contract and is asserted equal, never authoritative.';

insert into public.goods_recipes (product_id, ingredient_id, qty, tier)
select p.id, i.id, v.qty, v.tier
  from (values
${recipeRowsSql}
  ) v(product, ingredient, qty, tier)
  join public.goods p on p.code = v.product
  join public.goods i on i.code = v.ingredient;

-- ── 4. THE CITY'S 1-2 OUTPUTS ─────────────────────────────────────────────────────────────────
create table public.city_production (
  port_id uuid not null references public.ports(id) on delete cascade,
  good_id uuid not null references public.goods(id) on delete cascade,
  rank    int  not null check (rank between 1 and 2),
  primary key (port_id, good_id),
  unique (port_id, rank)
);
create index city_production_good_idx on public.city_production (good_id);
comment on table public.city_production is
  '0280: what each harbour MAKES, 1-2 goods (rank 1 then 2). Bigger cities make higher tiers: '
  'size_tier 5 -> up to 3, 3 -> up to 2, 2 -> tier 0. The quay does not read this yet; '
  'public.port_offered_goods will be re-cut to it in the sim slice.';

insert into public.city_production (port_id, good_id, rank)
select p.id, g.id, v.rank
  from (values
${productionRowsSql}
  ) v(port, good, rank)
  join public.ports p on p.code = v.port
  join public.goods g on g.code = v.good;

-- ── 5. THE DERIVED IMPORT DEMAND (one reading; server-only) ───────────────────────────────────
create function public.city_inputs(p_port uuid)
returns table (good_id uuid)
language sql stable security definer set search_path = public, pg_temp
as $$
  -- 0280: what a city must BUY to make what it makes: the recipe ingredients of its produced
  -- goods, minus anything it produces itself. The recipes and city_production are the authorities;
  -- this is derived, so it cannot drift from them.
  select distinct r.ingredient_id
    from public.city_production cp
    join public.goods_recipes r on r.product_id = cp.good_id
   where cp.port_id = p_port
     and not exists (select 1 from public.city_production own
                      where own.port_id = cp.port_id and own.good_id = r.ingredient_id)
   order by 1
$$;
comment on function public.city_inputs(uuid) is
  '0280: the imports a harbour needs to make its 1-2 outputs. Derived from city_production x '
  'goods_recipes; never stored. The sim slice reads it for the input-demand premium.';

create function public.city_wants_input(p_port uuid, p_good uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (select 1 from public.city_inputs(p_port) i where i.good_id = p_good)
$$;
comment on function public.city_wants_input(uuid, uuid) is
  '0280: one-good predicate over public.city_inputs; the shape the price sim will ask per row.';

revoke all on function public.city_inputs(uuid) from public, anon, authenticated;
revoke all on function public.city_wants_input(uuid, uuid) from public, anon, authenticated;

-- ── 6. THE MARKET ROWS FOR THE NEW GOODS (same arithmetic as 0005's seed) ────────────────────
-- Existing market rows are untouched. Only the 64 new goods get rows, for every harbour at once,
-- so world.price/world.quote can price them the moment a hold carries one.
with knob as (
  select public.wc_num('affinity_producer') as producer, public.wc_num('affinity_home') as home,
         public.wc_num('affinity_span') as span, public.wc_num('affinity_reach_nm') as reach_nm,
         public.wc_num('affinity_curve') as curve
),
newg as (select id from public.goods where code in (${newGoods.map((g) => q(g.id)).join(', ')})),
source_distance as (
  select p.id as port_id, src.id as src_id, voyage.gc_distance_nm(p.lat, p.lon, src.lat, src.lon) as nm
    from public.ports p
    cross join (select distinct cp.port_id from public.city_production cp join newg n on n.id = cp.good_id) s
    join public.ports src on src.id = s.port_id
),
nearest as (
  select d.port_id, cp.good_id, min(d.nm) as nm
    from source_distance d
    join public.city_production cp on cp.port_id = d.src_id
    join newg n on n.id = cp.good_id
   group by d.port_id, cp.good_id
)
insert into public.port_goods (port_id, good_id, affinity, stock, stock_target, production_rate)
select p.id, g.id, aff.affinity,
       greatest(60, round(200 * p.size_tier * (1.60 - aff.affinity))),
       greatest(60, round(200 * p.size_tier * (1.60 - aff.affinity))),
       case when aff.affinity < 0.80
            then round(greatest(60, 200 * p.size_tier * (1.60 - aff.affinity)) * 0.05, 2) else 0 end
  from public.ports p
  cross join newg g
  cross join knob k
  left join nearest n on n.port_id = p.id and n.good_id = g.id
  cross join lateral (
    select world.affinity_at(
             exists (select 1 from public.city_production cp where cp.port_id = p.id and cp.good_id = g.id),
             n.nm, k.producer, k.home, k.span, k.reach_nm, k.curve) as affinity
  ) aff
 where p.kind = 'HARBOUR'
on conflict (port_id, good_id) do nothing;

-- The new rows must carry the same derived demand every other market row does (0185). This is the
-- one authority public.demand_for; it is not a second formula.
update public.port_goods pg
   set demand = world.demand_for(pg.port_id, pg.good_id)
 where pg.good_id in (select g.id from public.goods g where g.code in (${newGoods.map((g) => q(g.id)).join(', ')}));

-- ── 7. SELF-ASSERT ────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_new        int;
  v_goods      int;
  v_crafted    int;
  v_recipes    int;
  v_recipe_rows int;
  v_bad        int;
  v_port       uuid;
  v_count      int;
  v_rows       int;
  v_prod_rows  int;
  v_ports      int;
  v_producer   int;
  v_pair       int;
  v_notfinite  int;
  v_state      text;
  v_hash       text;
  v_rate       numeric;
  v_price_rec  record;
  v_good_rec   record;
  v_port_rec   record;
  v_def_rec    record;
begin
  -- (a) The rows this file wrote, and only those.
  select count(*) into v_new from public.goods where code in (${newGoods.map((g) => q(g.id)).join(', ')});
  if v_new <> ${newGoods.length} then
    raise exception '0280 self-assert FAIL: % of the ${newGoods.length} new goods landed', v_new;
  end if;
  select count(*) into v_goods from public.goods;
  if v_goods <> 629 then
    raise exception '0280 self-assert FAIL: % goods after this file, expected 629 (565 + 19 design + 45 raw inputs)', v_goods;
  end if;
  if exists (select 1 from public.goods where tier not between 0 and 3 or is_raw is distinct from (tier = 0)) then
    raise exception '0280 self-assert FAIL: a good has no valid tier / is_raw pair';
  end if;

  -- (b) RECIPE INVARIANTS. Every crafted good has a recipe; 2-6 DISTINCT ingredients; every
  --     ingredient a good; ingredient tier < product tier; no self-ingredient; acyclic.
  select count(*) into v_crafted from public.goods where tier between 1 and 3;
  select count(distinct product_id) into v_recipes from public.goods_recipes;
  select count(*) into v_recipe_rows from public.goods_recipes;
  if v_crafted <> ${recipeRows.length} or v_recipes <> ${recipeRows.length} then
    raise exception '0280 self-assert FAIL: % crafted goods, % recipe products (want ${recipeRows.length}); an orphan recipe exists',
      v_crafted, v_recipes;
  end if;
  if v_recipe_rows <> ${recipeExpectedRows} then
    raise exception '0280 self-assert FAIL: % recipe ingredient rows, expected ${recipeExpectedRows} (a code did not resolve)',
      v_recipe_rows;
  end if;
  select count(*) into v_bad
    from (select gr.product_id, count(*) n, count(distinct gr.ingredient_id) d
            from public.goods_recipes gr group by gr.product_id) t
   where t.n < 2 or t.n > 6 or t.n <> t.d;
  if v_bad <> 0 then
    raise exception '0280 self-assert FAIL: % recipe(s) are not 2-6 distinct ingredients', v_bad;
  end if;
  if exists (select 1 from public.goods_recipes where product_id = ingredient_id) then
    raise exception '0280 self-assert FAIL: a recipe is its own ingredient';
  end if;
  select count(*) into v_bad
    from public.goods_recipes gr
    join public.goods p on p.id = gr.product_id
    join public.goods i on i.id = gr.ingredient_id
   where gr.tier <> p.tier or i.tier >= p.tier;
  if v_bad <> 0 then
    raise exception '0280 self-assert FAIL: % recipe row(s) break the tier rule (ingredient tier must be below product tier)', v_bad;
  end if;
  -- acyclic: bounded recursion (max tier 3 -> depth 4). Any product reachable from itself fails.
  with recursive reach(product_id, ingredient_id, depth) as (
    select product_id, ingredient_id, 1 from public.goods_recipes
    union all
    select rc.product_id, gr.ingredient_id, rc.depth + 1
      from reach rc join public.goods_recipes gr on gr.product_id = rc.ingredient_id
     where rc.depth < 4
  )
  select count(*) into v_bad from reach where ingredient_id = product_id;
  if v_bad <> 0 then
    raise exception '0280 self-assert FAIL: the recipe graph has % cycle edge(s)', v_bad;
  end if;

  -- (c) PRODUCTION INVARIANTS. 1-2 outputs per harbour; rank 1 always; tier ceiling by size;
  --     native-or-entrepot (0062); every raw ingredient has a producer.
  select count(*) into v_prod_rows from public.city_production;
  select count(*) into v_ports from public.ports where kind = 'HARBOUR';
  if v_prod_rows <> ${productionExpectedRows} then
    raise exception '0280 self-assert FAIL: % production rows, expected ${productionExpectedRows}', v_prod_rows;
  end if;
  select count(*) into v_bad from public.ports p
   where p.kind = 'HARBOUR'
     and (select count(*) from public.city_production cp where cp.port_id = p.id) not between 1 and 2;
  if v_bad <> 0 then
    raise exception '0280 self-assert FAIL: % harbour(s) do not make 1-2 goods', v_bad;
  end if;
  select count(*) into v_bad from public.ports p
   where p.kind = 'HARBOUR'
     and not exists (select 1 from public.city_production cp where cp.port_id = p.id and cp.rank = 1);
  if v_bad <> 0 then
    raise exception '0280 self-assert FAIL: % harbour(s) have no rank-1 output', v_bad;
  end if;
  select count(*) into v_bad
    from public.city_production cp
    join public.ports p on p.id = cp.port_id
    join public.goods g on g.id = cp.good_id
   where p.kind <> 'HARBOUR'
      or g.tier > (case p.size_tier when 5 then 3 when 3 then 2 when 2 then 1 else 0 end);
  if v_bad <> 0 then
    raise exception '0280 self-assert FAIL: % production row(s) exceed the city''s tier ceiling (size 5->3, 3->2, 2->1)', v_bad;
  end if;
  select count(*) into v_bad
    from public.city_production cp
    join public.ports p on p.id = cp.port_id
    join public.goods g on g.id = cp.good_id
    join public.regions r on r.id = p.region_id
   where not (r.code = any(g.origin_regions) or p.code = any(g.entrepot_ports));
  if v_bad <> 0 then
    raise exception '0280 self-assert FAIL: % production row(s) violate 0062 (not native, not an entrepot)', v_bad;
  end if;
  -- every RAW good has at least one producing harbour (recipe ingredient or not): with the quay
  -- later selling only what a city makes, a raw good with no producer would be unbuyable anywhere.
  select count(*) into v_bad
    from public.goods g
   where g.tier = 0
     and not exists (select 1 from public.city_production cp where cp.good_id = g.id);
  if v_bad <> 0 then
    raise exception '0280 self-assert FAIL: % raw good(s) have no producing harbour — an unbuyable good or an orphaned recipe', v_bad;
  end if;

  -- (d) INPUT DEMAND is derived and non-empty for every city that makes a crafted good; every
  --     demand is a good the city does not itself make.
  select count(*) into v_bad from public.ports p
   where p.kind = 'HARBOUR'
     and exists (select 1 from public.city_production cp join public.goods g on g.id = cp.good_id
                  where cp.port_id = p.id and g.tier >= 1)
     and not exists (select 1 from public.city_inputs(p.id));
  if v_bad <> 0 then
    raise exception '0280 self-assert FAIL: % crafted-producing harbour(s) derive no input demand', v_bad;
  end if;
  select count(*) into v_bad
    from public.ports p cross join lateral public.city_inputs(p.id) ci
   where exists (select 1 from public.city_production cp where cp.port_id = p.id and cp.good_id = ci.good_id);
  if v_bad <> 0 then
    raise exception '0280 self-assert FAIL: % input-demand row(s) are goods the city already makes itself', v_bad;
  end if;

  -- (e) CLOSED-ECONOMY PRICE INVARIANTS, measured through the real functions on every pair this
  --     file makes relevant: each (harbour, produced good) and each (harbour, input good). Price,
  --     ask, bid and every price_why term must be finite, non-negative, ask > bid.
  v_pair := 0;
  for v_port_rec in select id from public.ports where kind = 'HARBOUR' loop
    for v_good_rec in
      select cp.good_id from public.city_production cp where cp.port_id = v_port_rec.id
      union
      select ci.good_id from public.city_inputs(v_port_rec.id) ci
    loop
      v_pair := v_pair + 1;
      select * into v_price_rec from world.price(v_port_rec.id, v_good_rec.good_id);
      if v_price_rec.mid is null or v_price_rec.mid <= 0 or v_price_rec.ask is null or v_price_rec.ask <= 0 or v_price_rec.bid is null or v_price_rec.bid <= 0
         or v_price_rec.ask <= v_price_rec.bid
         or v_price_rec.mid::text in ('NaN', 'Infinity', '-Infinity') then
        raise exception '0280 self-assert FAIL: price at % / % is not finite and positive: %', v_port_rec.id, v_good_rec.good_id, v_price_rec;
      end if;
      perform world.price_why(v_port_rec.id, v_good_rec.good_id);
    end loop;
  end loop;
  if v_pair < ${productionExpectedRows} then
    raise exception '0280 self-assert FAIL: the price probe examined % pairs, fewer than the ${productionExpectedRows} production rows', v_pair;
  end if;
  -- restock stays the day's rate in [0,1], finite, on every harbour
  select count(*) into v_bad from public.ports p
   where p.kind = 'HARBOUR'
     and (public.restock_rate(p.id) is null or public.restock_rate(p.id) < 0
          or public.restock_rate(p.id) > 1 or public.restock_rate(p.id)::text in ('NaN', 'Infinity', '-Infinity'));
  if v_bad <> 0 then
    raise exception '0280 self-assert FAIL: % harbour(s) have a non-finite restock rate', v_bad;
  end if;
  -- ...and every NEW good at a deterministic six-harbour sample, including the Forge outputs no
  -- city makes or demands (the 695 pairs above cannot reach those).
  select count(*) into v_bad
    from public.goods g
    cross join (select id from public.ports where kind = 'HARBOUR' order by code limit 6) p
    cross join lateral world.price(p.id, g.id) pr
   where g.code in (${newGoods.map((g) => q(g.id)).join(', ')})
     and (pr.mid is null or pr.mid <= 0 or pr.ask is null or pr.ask <= 0 or pr.bid is null or pr.bid <= 0
          or pr.ask <= pr.bid or pr.mid::text in ('NaN', 'Infinity', '-Infinity'));
  if v_bad <> 0 then
    raise exception '0280 self-assert FAIL: % new-good price row(s) at the six-harbour sample are not finite and positive', v_bad;
  end if;

  -- (f) THE SIM IS UNMOVED. Every function named in the pre-image is byte-identical, and the
  --     three tables this file did not extend carry the same digest / row counts.
  for v_def_rec in select * from defs_pre_0280 loop
    if replace(pg_get_functiondef(v_def_rec.fn::regprocedure), E'\\r', '') <> v_def_rec.def then
      raise exception '0280 self-assert FAIL: % moved — this file must change no price, restock or quay function', v_def_rec.fn;
    end if;
  end loop;
  if (select count(*) from public.port_specialties) <> (select specialties_n from pre_0280)
     or md5((select coalesce(string_agg(ps.port_id::text || '|' || ps.good_id::text, E'\\n' order by ps.port_id, ps.good_id), '') from public.port_specialties ps))
        <> (select specialties_hash from pre_0280) then
    raise exception '0280 self-assert FAIL: port_specialties moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0280 self-assert FAIL: a client-write wall moved';
  end if;
  if has_function_privilege('authenticated', 'public.city_inputs(uuid)', 'execute')
     or has_function_privilege('anon', 'public.city_inputs(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.city_wants_input(uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'public.city_wants_input(uuid, uuid)', 'execute') then
    raise exception '0280 self-assert FAIL: a client role can execute a derived-demand helper';
  end if;

  -- (g) REVERSIBILITY. In a rolled-back sub-transaction, undo every hunk: drop the two new tables
  --     and the two helper functions, delete the 64 new goods (their port_goods / recipe /
  --     production rows cascade), drop the two columns, and restore port_offered_goods' pre-image
  --     (it was never re-cut, so this is a no-op proof). The digest must equal the pre-image.
  begin
    drop function public.city_wants_input(uuid, uuid);
    drop function public.city_inputs(uuid);
    drop table public.city_production;
    drop table public.goods_recipes;
    delete from public.goods where code in (${newGoods.map((g) => q(g.id)).join(', ')});
    alter table public.goods drop column is_raw;
    alter table public.goods drop column tier;
    select md5(coalesce(string_agg(g.code || '|' || g.name || '|' || g.base_value || '|' || g.bulk || '|' ||
        g.perishable_pct_day || '|' || g.category || '|' || array_to_string(g.culture_mask, ',') || '|' ||
        array_to_string(g.origin_regions, ',') || '|' || array_to_string(g.entrepot_ports, ',') || '|' || g.industry,
        E'\\n' order by g.code), '')) into v_hash from public.goods g;
    if v_hash <> (select goods_hash from pre_0280)
       or (select count(*) from public.goods) <> (select goods_n from pre_0280)
       or (select count(*) from public.port_goods) <> (select port_goods_n from pre_0280) then
      raise exception '0280 self-assert FAIL: the reverse does not restore the pre-image';
    end if;
    raise exception using errcode = 'ZX280', message = 'reverse ok';
  exception when sqlstate 'ZX280' then
    null;
  end;

  raise notice '0280 self-assert ok: % goods (+64: 19 design, 45 raw inputs), % recipes / % ingredient rows, % production rows across % harbours (1-2 each), every raw good has a producer, every crafted good has a recipe, % price pairs finite and positive, restock finite on every harbour, sim functions unmoved, reverse restores the pre-image',
    v_goods, v_recipes, v_recipe_rows, v_prod_rows, v_ports, v_pair;
end $$;
`

writeFileSync(path.join(ROOT, 'supabase', 'migrations', MIGRATION_NAME), sql, 'utf8')

// ── Report for the dev-log ────────────────────────────────────────────────────────────────────
const outDist = {}
for (const v of production.values()) outDist[v.length] = (outDist[v.length] ?? 0) + 1
const producedByTier = {}
for (const v of production.values()) for (const g of v) {
  const t = allTiers.get(g)
  producedByTier[t] = (producedByTier[t] ?? 0) + 1
}
const inputRows = [...inputDemand.values()].reduce((n, v) => n + v.length, 0)
const inputPorts = [...inputDemand.values()].filter((v) => v.length).length
const craftedByPortTier = {}
const outputsByPortTier = {}
for (const p of portsDoc.ports) {
  outputsByPortTier[p.tier] = (outputsByPortTier[p.tier] ?? 0) + production.get(p.id).length
  for (const g of production.get(p.id)) {
    if (allTiers.get(g) >= 1) craftedByPortTier[p.tier] = (craftedByPortTier[p.tier] ?? 0) + 1
  }
}
console.log(JSON.stringify({
  migration: MIGRATION_NAME,
  goods: { total: 629, existing: 565, designNew: 19, rawInputs: 45 },
  recipes: { count: recipeRows.length, ingredientRows: recipeExpectedRows },
  production: { rows: productionExpectedRows, ports: portsDoc.ports.length, portsPerCount: outDist, producedGoods: producedCount, byTier: producedByTier, craftedByPortTier, outputsByPortTier },
  inputDemand: { rows: inputRows, ports: inputPorts },
  regions: regionsDoc.regions.length,
}, null, 2))

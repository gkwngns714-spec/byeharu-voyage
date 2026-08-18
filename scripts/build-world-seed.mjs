// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE REAL WORLD, WRITTEN AS SQL — generates migration 0003 from data/*.json.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The world is DATA (214 sourced harbours, 70 traded goods, 782 generated sea legs) and the chain
// is the only place the game reads it from. Rather than keep a second copy by hand, this script
// writes the seed migration, so the migration and data/*.json cannot drift: change the data, run
// this, and the chain follows.
//
// WHAT IS DERIVED HERE, AND FROM WHAT — every rule is stated once, below, and applied to all 214:
//   code          three letters from the name, deduplicated; the twelve V0 codes are preserved
//   size_tier     dataset tier 1/2/3 → 5/3/2 (a great entrepôt, a working port, a small harbour)
//   max_draft     from size_tier, minus the river and bar ports which are shallow by geography
//   yard/academy  from size_tier: a great port refits and teaches, a small one does neither
//   dev_*         from size_tier and what the port actually trades
//   culture       from its region, with the overrides history demands (Ceuta is a Latin garrison)
//   nation        the 1550 sovereign, where one of the seeded powers plainly held it; else null
//
// WHAT IS NOT DERIVED: coordinates (Wikidata P625, never touched), the specialty lists (editorial,
// sourced in docs/WORLD_DATA.md), and the leg distances (scripts/build-sea-routes.mjs).
//
// Run: node scripts/build-world-seed.mjs
// Writes: supabase/migrations/20260818000003_the_real_world_and_the_water_between_it.sql
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const DATA = join(ROOT, 'data')
const OUT = join(ROOT, 'supabase', 'migrations', '20260818000003_the_real_world_and_the_water_between_it.sql')

const ports = JSON.parse(readFileSync(join(DATA, 'ports.json'), 'utf8')).ports
const goods = JSON.parse(readFileSync(join(DATA, 'goods.json'), 'utf8')).goods
const regions = JSON.parse(readFileSync(join(DATA, 'regions.json'), 'utf8')).regions
const seas = JSON.parse(readFileSync(join(DATA, 'seas.json'), 'utf8')).seas
const routes = JSON.parse(readFileSync(join(DATA, 'sea-routes.json'), 'utf8'))

const q = (s) => (s === null || s === undefined ? 'null' : `'${String(s).replace(/'/g, "''")}'`)
const NM_PER_RAD = 3440.065
const rad = (d) => (d * Math.PI) / 180
const gcNm = (lat1, lon1, lat2, lon2) =>
  2 * NM_PER_RAD * Math.asin(Math.min(1, Math.sqrt(
    Math.sin(rad(lat2 - lat1) / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lon2 - lon1) / 2) ** 2,
  )))

// ── CODES ─────────────────────────────────────────────────────────────────────────────────────
// ports.code is `^[A-Z]{3}$` and unique. The twelve ports the design named keep the codes the
// design gave them, so every worked example in DESIGN.md still addresses the same harbour.
const PINNED_CODES = {
  lisbon: 'LIS', porto: 'OPO', seville: 'SVQ', cadiz: 'CAD', ceuta: 'CEU', safi: 'SAF',
  funchal: 'FNC', 'las-palmas': 'LPA', marseille: 'MRS', genoa: 'GOA', tunis: 'TUN', naples: 'NAP',
}
const fold = (s) =>
  s.normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase().replace(/[^A-Z]/g, '')

function assignCodes(items, pinned = {}) {
  const used = new Set(Object.values(pinned))
  const out = new Map()
  for (const it of items) if (pinned[it.id]) out.set(it.id, pinned[it.id])
  for (const it of items) {
    if (out.has(it.id)) continue
    const letters = fold(it.name)
    const tries = []
    if (letters.length >= 3) {
      tries.push(letters.slice(0, 3))
      tries.push(letters[0] + letters.slice(1).replace(/[AEIOU]/g, '').slice(0, 2))
      tries.push(letters[0] + letters.slice(-2))
      for (let i = 1; i < letters.length - 1; i++) tries.push(letters[0] + letters[i] + letters[letters.length - 1])
    }
    for (let a = 0; a < 26; a++) for (let b = 0; b < 26; b++) {
      tries.push((letters[0] ?? 'X') + String.fromCharCode(65 + a) + String.fromCharCode(65 + b))
    }
    const code = tries.find((c) => /^[A-Z]{3}$/.test(c) && !used.has(c))
    if (!code) throw new Error(`no free code for ${it.id}`)
    used.add(code)
    out.set(it.id, code)
  }
  return out
}

const portCode = assignCodes(ports, PINNED_CODES)
const seaCode = assignCodes(seas)
const regionCode = assignCodes(regions)

// ── CULTURE ───────────────────────────────────────────────────────────────────────────────────
// One token per port, because goods.culture_mask matches it by equality. Assigned by region — the
// unit the dataset already groups by — with the overrides that history plainly requires.
const CULTURE_BY_REGION = {
  iberia: 'latin', 'atlantic-isles': 'latin', 'british-isles': 'anglo',
  'france-low-countries': 'latin', baltic: 'germanic', 'scandinavia-arctic': 'nordic',
  'western-mediterranean': 'latin', 'adriatic-ionian': 'latin', 'aegean-anatolia': 'islamic',
  levant: 'islamic', maghreb: 'islamic', 'west-africa': 'guinean', 'east-africa': 'swahili',
  'arabia-gulf': 'islamic', 'western-india': 'indic', 'eastern-india': 'indic',
  'southeast-asia': 'malay', 'china-coast': 'sinic', korea: 'korean', japan: 'japanese',
  caribbean: 'latin', 'north-america-atlantic': 'anglo', 'south-america-atlantic': 'latin',
  'pacific-americas': 'latin', oceania: 'oceanic',
}
const CULTURE_OVERRIDE = {
  ceuta: 'latin',            // a Portuguese garrison town from 1415
  'quebec-city': 'latin',    // French from its founding
  malacca: 'malay', goa: 'indic',
  'cape-town': 'guinean',    // a Dutch victualling station on a Khoi coast; not a Swahili port
  amsterdam: 'germanic', antwerp: 'germanic', rotterdam: 'germanic', bruges: 'germanic',
  athens: 'islamic', heraklion: 'latin',   // Ottoman Greece; Venetian Crete until 1669
}

// ── NATIONS ───────────────────────────────────────────────────────────────────────────────────
// The powers whose flag a port could fly in 1550, and their capital port. A port is given a nation
// only where one of these plainly held it; everywhere else nation_id is NULL and the port's
// `country` text — which comes from the dataset — is the honest answer. Inventing a sovereign for
// two hundred harbours would be worse than admitting the game does not model one.
const NATIONS = [
  ['PRT', 'Portugal', '⚓', 'LIS'],
  ['ESP', 'Castile-Spain', '⚔', 'SVQ'],
  ['FRA', 'France', '⚜', 'MRS'],
  ['ENG', 'England', '☩', null],
  ['NLD', 'The Netherlands', '⚑', null],
  ['DNK', 'Denmark-Norway', '✠', null],
  ['SWE', 'Sweden', '✦', null],
  ['POL', 'Poland-Lithuania', '⚔', null],
  ['RUS', 'Muscovy', '☦', null],
  ['HAN', 'The Hanse', '⚖', null],
  ['VEN', 'Venice', '⚔', null],
  ['GEN', 'Genoa', '⚓', null],
  ['OTT', 'Ottoman Empire', '☾', null],
  ['PER', 'Safavid Persia', '☾', null],
  ['MAR', 'Morocco', '☾', null],
  ['MUG', 'Mughal India', '☾', null],
  ['MNG', 'Ming China', '龍', null],
  ['JPN', 'Japan', '⛩', null],
  ['JOS', 'Joseon', '☰', null],
  ['AYU', 'Ayutthaya', '⛨', null],
]
/** Modern country code → the 1550 power, where it is not in dispute. */
const NATION_BY_COUNTRY = {
  PT: 'PRT', ES: 'ESP', FR: 'FRA', GB: 'ENG', IE: 'ENG', NL: 'NLD', BE: 'NLD',
  DE: 'HAN', DK: 'DNK', NO: 'DNK', IS: 'DNK', SE: 'SWE', FI: 'SWE', PL: 'POL', LT: 'POL',
  RU: 'RUS', TR: 'OTT', GR: 'OTT', EG: 'OTT', LY: 'OTT', TN: 'OTT', DZ: 'OTT', SY: 'OTT',
  LB: 'OTT', IL: 'OTT', PS: 'OTT', IQ: 'OTT', YE: 'OTT', SA: 'OTT', SD: 'OTT',
  MA: 'MAR', IR: 'PER', CN: 'MNG', JP: 'JPN', KR: 'JOS', TH: 'AYU',
  MX: 'ESP', CU: 'ESP', DO: 'ESP', PA: 'ESP', CO: 'ESP', VE: 'ESP', PE: 'ESP', CL: 'ESP',
  AR: 'ESP', UY: 'ESP', PH: 'ESP', BR: 'PRT', AO: 'PRT', MZ: 'PRT', CV: 'PRT', GH: 'PRT',
  BD: 'MUG', PK: 'MUG',
}
const NATION_OVERRIDE = {
  venice: 'VEN', genoa: 'GEN', naples: 'ESP', palermo: 'ESP', messina: 'ESP',
  malacca: 'PRT', goa: 'PRT', colombo: 'PRT', 'mozambique-island': 'PRT', sofala: 'PRT',
  elmina: 'PRT', luanda: 'PRT', macau: 'PRT', nagasaki: 'JPN', hormuz: 'PRT', diu: 'PRT',
  antwerp: 'ESP', bruges: 'ESP', // the Habsburg Netherlands answered to Madrid in 1550
  hamburg: 'HAN', lubeck: 'HAN', bremen: 'HAN', gdansk: 'POL', riga: 'POL',
}
/** The capitals, set here rather than guessed from the roster. */
const CAPITALS = {
  ENG: 'london', NLD: 'amsterdam', DNK: 'copenhagen', SWE: 'stockholm', POL: 'gdansk',
  RUS: 'arkhangelsk', HAN: 'hamburg', VEN: 'venice', GEN: 'genoa', OTT: 'istanbul',
  PER: 'bandar-abbas', MAR: 'safi', MUG: 'surat', MNG: 'guangzhou', JPN: 'sakai',
  JOS: 'busan', AYU: 'ayutthaya',
}

// ── PORTS: the derived columns ────────────────────────────────────────────────────────────────
const SIZE_BY_TIER = { 1: 5, 2: 3, 3: 2 }
/** Harbours reached up a river or over a bar: deep hulls cannot enter, whatever the town's size. */
const SHALLOW = new Set([
  'seville', 'hooghly', 'quebec-city', 'guangzhou', 'london', 'nantes', 'bordeaux', 'hamburg',
  'bremen', 'antwerp', 'bruges', 'ayutthaya', 'thanlyin', 'basra', 'buenos-aires', 'belem',
  'gdansk', 'riga', 'arkhangelsk', 'chittagong', 'khambhat', 'suzhou', 'nanjing', 'hanoi',
])
const goodById = new Map(goods.map((g) => [g.id, g]))
const INDUSTRY_CATEGORIES = new Set(['metal', 'textile', 'naval-stores'])

function derivePort(p) {
  const size = SIZE_BY_TIER[p.tier]
  const specialties = (p.goods ?? []).filter((g) => goodById.has(g))
  const industrial = specialties.filter((g) => INDUSTRY_CATEGORIES.has(goodById.get(g).category)).length
  const yardTier = size === 5 ? 3 : size === 3 ? 1 : 0
  const clamp = (n) => Math.max(0, Math.min(20, Math.round(n)))
  return {
    code: portCode.get(p.id),
    size_tier: size,
    max_draft: SHALLOW.has(p.id) ? 2 : size === 5 ? 5 : size === 3 ? 4 : 3,
    yard_tier: yardTier,
    has_yard: yardTier > 0,
    has_academy: size === 5,
    dev_commerce: clamp(size * 2.4 + specialties.length),
    dev_industry: clamp(size * 2.0 + industrial * 1.5),
    dev_military: clamp(size * 1.8 + (yardTier > 0 ? 2 : 0)),
    crew_pool: size * 80,
    culture: CULTURE_OVERRIDE[p.id] ?? CULTURE_BY_REGION[p.region] ?? 'latin',
    nation: NATION_OVERRIDE[p.id] ?? NATION_BY_COUNTRY[p.country] ?? null,
    specialties,
  }
}
const derived = new Map(ports.map((p) => [p.id, derivePort(p)]))

// ── GOODS ─────────────────────────────────────────────────────────────────────────────────────
// base_value is the midpoint of the dataset's researched price band. bulk and spoilage are by
// category: a tun of pepper is not a tun of timber, and fish rots while iron does not.
const BULK = { spice: 0.6, textile: 0.9, metal: 0.8, luxury: 0.3, foodstuff: 1.0, raw: 1.2, 'naval-stores': 1.4 }
const PERISH = { 'dried-fish': 0.004, herring: 0.004, cheese: 0.004, 'salted-beef': 0.003, 'dried-fruit': 0.003, wheat: 0.002, rice: 0.002, sugar: 0.001, 'olive-oil': 0.001, hides: 0.001, furs: 0.001 }
/** DESIGN B.4/G.3: cultures that will not trade the good at all. */
const CULTURE_MASK = { wine: ['islamic', 'swahili'] }

// ── SQL ───────────────────────────────────────────────────────────────────────────────────────
const lines = []
const w = (s = '') => lines.push(s)

const legRows = routes.legs.map((l) => {
  const a = ports.find((p) => p.id === l.from)
  const b = ports.find((p) => p.id === l.to)
  // The chain recomputes the great circle from the STORED coordinates, which are rounded to 0.01°.
  // Rounding can lengthen the great circle by a few tenths of a mile, so the stored distance is
  // taken as the larger of the sailed figure and that rounded great circle — the leg can never
  // come out shorter than the line the database itself will draw.
  const gcRounded = gcNm(round2(a.lat), round2(a.lon), round2(b.lat), round2(b.lon))
  const nm = Math.max(l.nm, Math.ceil(gcRounded * 10) / 10)
  const [from, to] = derived.get(a.id).code < derived.get(b.id).code ? [a, b] : [b, a]
  return { from: derived.get(from.id).code, to: derived.get(to.id).code, nm, hazard: l.hazard_mult, note: l.note }
})
function round2(n) { return Math.round(n * 100) / 100 }

const specialtyRows = []
for (const p of ports) {
  for (const g of derived.get(p.id).specialties) specialtyRows.push([derived.get(p.id).code, g])
}

const nationsWithPorts = new Set([...derived.values()].map((d) => d.nation).filter(Boolean))
const seasUsed = new Set(ports.map((p) => p.sea))
const regionsUsed = new Set(ports.map((p) => p.region))

w(`-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0003 — THE REAL WORLD, AND THE WATER BETWEEN IT
--        ${NATIONS.length} nations, ${seasUsed.size} seas, ${regionsUsed.size} regions, ${ports.length} ports, ${legRows.length} legs, ${goods.length} goods, 3 ship classes.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- GENERATED by scripts/build-world-seed.mjs from data/*.json. Do not hand-edit: edit the data or
-- the generator and run it again. The generator's header states every derivation rule.
--
-- ── WHERE THE NUMBERS COME FROM ─────────────────────────────────────────────────────────────────
--   Coordinates    Wikidata P625 (CC0). Every one records the item it came from in data/ports.json.
--                  Stored to 0.01°, which is about half a nautical mile.
--   Distances      SAILED distances from scripts/build-sea-routes.mjs: the shortest path through
--                  WATER on a 0.25° raster of the Natural Earth land polygons. That is why Lisboa
--                  to Cádiz is ${legRows.find((l) => (l.from === 'CAD' && l.to === 'LIS') || (l.from === 'LIS' && l.to === 'CAD'))?.nm ?? '—'} nm and not the 188 nm of the straight line: Cape St Vincent is
--                  in the way, and a ship goes round it.
--   Everything else is derived from the dataset by a stated rule, or authored in the generator
--   where history requires it (which power held a port in 1550, and which harbours are shallow).
--
-- ── THE WORLD THIS PRODUCES ─────────────────────────────────────────────────────────────────────
--   There is no Suez and no Panama, because there was none: they were cut in 1869 and 1914. The
--   generator did not encode that. It falls out of the water: Alexandria to Aden is 10,944 nm
--   round the Cape, and Veracruz to Acapulco is 10,860 nm round Cape Horn, because that is where
--   the sea goes. Every port is reachable from every other — asserted below, by walking the graph.
--
-- ── WHAT IT SELF-ASSERTS ────────────────────────────────────────────────────────────────────────
--   Counts · every leg's endpoints resolve · canonical ordering, no duplicate unordered pair ·
--   distance_nm >= the great circle for ALL ${legRows.length} legs · the graph is CONNECTED (all ${ports.length} ports
--   reachable from Lisboa) · every nation's capital resolves · the culture mask both blocks and
--   permits · no port is left without a sea lane · the 0001 lockdown still holds.
--
-- Depends ONLY on: 0001 (lockdown), 0002 (the tables, voyage.gc_distance_nm).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
`)

w('-- ── Nations: the powers whose flag a port could fly in 1550 ────────────────────────────────────')
w('insert into public.nations (code, name, flag_char, capital_port_code) values')
w(NATIONS.map(([code, name, flag]) => {
  const capitalPort = CAPITALS[code]
  const capital = capitalPort ? derived.get(capitalPort)?.code : NATIONS.find((n) => n[0] === code)[3]
  return `  (${q(code)}, ${q(name)}, ${q(flag)}, ${q(capital ?? NATIONS.find((n) => n[0] === code)[3])})`
}).join(',\n') + '\non conflict (code) do nothing;\n')

w('-- ── Seas (data/seas.json). hazard_base sits inside DESIGN B.6\'s 0.006-0.020 band; the open')
w('--    oceans and the pirate waters are the dangerous end of it. ──────────────────────────────────')
const PIRATE_SEAS = new Set(['mediterranean-sea', 'strait-of-malacca', 'caribbean-sea', 'gulf-of-guinea', 'south-china-sea', 'gulf-of-aden', 'red-sea', 'persian-gulf', 'arabian-sea'])
const OPEN_OCEANS = new Set(['arctic-ocean', 'north-atlantic', 'south-atlantic', 'indian-ocean', 'north-pacific', 'south-pacific', 'norwegian-sea', 'barents-sea'])
w('insert into public.seas (code, name, hazard_base, piracy_index) values')
w(seas.map((s) => {
  const hazard = OPEN_OCEANS.has(s.id) ? 0.018 : PIRATE_SEAS.has(s.id) ? 0.012 : 0.008
  const piracy = PIRATE_SEAS.has(s.id) ? 0.45 : OPEN_OCEANS.has(s.id) ? 0.12 : 0.2
  return `  (${q(seaCode.get(s.id))}, ${q(s.name)}, ${hazard.toFixed(4)}, ${piracy.toFixed(2)})`
}).join(',\n') + '\non conflict (code) do nothing;\n')

w('-- ── Regions (data/regions.json) — the price-affinity unit ────────────────────────────────────')
w('insert into public.regions (code, name) values')
w(regions.map((r) => `  (${q(regionCode.get(r.id))}, ${q(r.name)})`).join(',\n') + '\non conflict (code) do nothing;\n')

w(`-- ── The ${ports.length} ports ─────────────────────────────────────────────────────────────────────────────`)
w(`insert into public.ports (
  code, name, country, nation_id, lat, lon, sea_id, region_id, culture,
  size_tier, max_draft, has_yard, yard_tier, has_academy,
  dev_industry, dev_commerce, dev_military, tax_rate, crew_pool
)
select v.code, v.name, v.country, n.id, v.lat, v.lon, s.id, r.id, v.culture,
       v.size_tier, v.max_draft, v.yard_tier > 0, v.yard_tier, v.academy,
       v.dev_i, v.dev_c, v.dev_m, 0.03, v.crew_pool
  from (values`)
w(ports.map((p) => {
  const d = derived.get(p.id)
  return `    (${q(d.code)}, ${q(p.name)}, ${q(p.countryName)}, ${q(d.nation)}, ${round2(p.lat)}, ${round2(p.lon)}, ${q(seaCode.get(p.sea))}, ${q(regionCode.get(p.region))}, ${q(d.culture)}, ${d.size_tier}, ${d.max_draft}, ${d.yard_tier}, ${d.has_academy}, ${d.dev_industry}, ${d.dev_commerce}, ${d.dev_military}, ${d.crew_pool})`
}).join(',\n'))
w(`  ) as v(code, name, country, nation_code, lat, lon, sea_code, region_code, culture,
         size_tier, max_draft, yard_tier, academy, dev_i, dev_c, dev_m, crew_pool)
  join public.seas    s on s.code = v.sea_code
  join public.regions r on r.code = v.region_code
  left join public.nations n on n.code = v.nation_code
on conflict (code) do nothing;
`)

w(`-- ── The ${goods.length} goods (data/goods.json; base_value is the midpoint of the researched band) ─────────`)
w('insert into public.goods (code, name, base_value, bulk, perishable_pct_day, category, culture_mask) values')
w(goods.map((g) => {
  const base = (g.baseValue[0] + g.baseValue[1]) / 2
  const bulk = BULK[g.category] ?? 1.0
  const perish = PERISH[g.id] ?? 0
  const mask = CULTURE_MASK[g.id] ?? []
  return `  (${q(g.id)}, ${q(g.name)}, ${base.toFixed(2)}, ${bulk.toFixed(3)}, ${perish.toFixed(3)}, ${q(g.category)}, '{${mask.join(',')}}')`
}).join(',\n') + '\non conflict (code) do nothing;\n')

w(`-- ── What each port is KNOWN FOR (${specialtyRows.length} rows) ────────────────────────────────────────────────
--    Editorial, sourced in docs/WORLD_DATA.md: the goods a harbour actually dealt in. 0005 turns
--    this into the price gradient — a port that produces a good sells it cheap, and everywhere
--    else pays by how far it is from the nearest place that does. That is the whole economy, and
--    it is derived from THIS table rather than from a matrix nobody could check.`)
w('insert into public.port_specialties (port_id, good_id)')
w('select p.id, g.id from (values')
w(specialtyRows.map(([code, good]) => `  (${q(code)}, ${q(good)})`).join(',\n'))
w(`) as v(port_code, good_code)
  join public.ports p on p.code = v.port_code
  join public.goods g on g.code = v.good_code
on conflict do nothing;
`)

w(`-- ── The ${legRows.length} sea legs (scripts/build-sea-routes.mjs; canonical from.code < to.code) ──────────────`)
w('insert into public.legs (from_port_id, to_port_id, distance_nm, hazard_mult, notes)')
w('select pf.id, pt.id, v.nm, v.hz, v.note')
w('  from (values')
w(legRows.map((l) => `    (${q(l.from)}, ${q(l.to)}, ${l.nm.toFixed(1)}, ${l.hazard.toFixed(3)}, ${q(l.note)})`).join(',\n'))
w(`  ) as v(f, t, nm, hz, note)
  join public.ports pf on pf.code = v.f
  join public.ports pt on pt.code = v.t
on conflict do nothing;
`)

w(`-- ── The three V0 hulls (DESIGN C.2, the rows marked "V0") ─────────────────────────────────────
insert into public.ship_classes
  (code, name, family, rig, hold, crew_required, crew_max, speed_kn, durability, guns, draft,
   build_hours, build_cost, tier) values
  ('barca',  'Barca',            'Western', 'lateen',  60,  8,  20, 5.00,  400,  0, 1,  24.0,  12000, 1),
  ('carlat', 'Caravela latina',  'Western', 'lateen',  90, 12,  30, 6.00,  550,  2, 1,  40.0,  26000, 2),
  ('nau',    'Nau / Carrack',    'Western', 'square', 400, 60, 140, 4.40, 1800, 12, 3,  96.0, 120000, 3)
on conflict (code) do nothing;
`)

// ── the self-assert ───────────────────────────────────────────────────────────────────────────
w(`-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_ports        int;
  v_legs         int;
  v_goods        int;
  v_seas         int;
  v_regions      int;
  v_nations      int;
  v_specialties  int;
  v_n            int;
  v_worst_ratio  numeric;
  v_worst_leg    text;
  v_reachable    int;
  v_lonely       text;
  v_wine_blocked int;
  v_wine_ok      int;
  v_lis_cad      numeric;
begin
  select count(*) into v_ports       from public.ports;
  select count(*) into v_legs        from public.legs;
  select count(*) into v_goods       from public.goods;
  select count(*) into v_seas        from public.seas;
  select count(*) into v_regions     from public.regions;
  select count(*) into v_nations     from public.nations;
  select count(*) into v_specialties from public.port_specialties;

  if v_ports <> ${ports.length} or v_legs <> ${legRows.length} or v_goods <> ${goods.length}
     or v_seas <> ${seas.length} or v_regions <> ${regions.length} or v_nations <> ${NATIONS.length}
     or v_specialties <> ${specialtyRows.length} then
    raise exception '0003 self-assert FAIL: seeded % ports / % legs / % goods / % seas / % regions / % nations / % specialties, expected ${ports.length}/${legRows.length}/${goods.length}/${seas.length}/${regions.length}/${NATIONS.length}/${specialtyRows.length}',
      v_ports, v_legs, v_goods, v_seas, v_regions, v_nations, v_specialties;
  end if;

  -- (b) Canonical ordering: every leg is stored lower-code first, exactly once. The graph is
  --     undirected and a reversed duplicate would be a second authority for one distance.
  select count(*) into v_n
    from public.legs l
    join public.ports a on a.id = l.from_port_id
    join public.ports b on b.id = l.to_port_id
   where a.code >= b.code;
  if v_n <> 0 then
    raise exception '0003 self-assert FAIL: % leg(s) are not in canonical (lower code first) order', v_n;
  end if;

  -- (c) THE INVARIANT: a leg may detour round land; it may never be a shortcut through the Earth.
  select max(l.distance_nm / nullif(voyage.gc_distance_nm(a.lat, a.lon, b.lat, b.lon), 0)),
         min(l.distance_nm / nullif(voyage.gc_distance_nm(a.lat, a.lon, b.lat, b.lon), 0))
    into v_worst_ratio, v_lis_cad
    from public.legs l
    join public.ports a on a.id = l.from_port_id
    join public.ports b on b.id = l.to_port_id;
  if v_lis_cad < 0.9999 then
    select a.code || '-' || b.code || ' ' || l.distance_nm || ' nm vs ' ||
           round(voyage.gc_distance_nm(a.lat, a.lon, b.lat, b.lon)::numeric, 1) || ' nm great circle'
      into v_worst_leg
      from public.legs l
      join public.ports a on a.id = l.from_port_id
      join public.ports b on b.id = l.to_port_id
     where l.distance_nm < voyage.gc_distance_nm(a.lat, a.lon, b.lat, b.lon)
     limit 1;
    raise exception '0003 self-assert FAIL: a leg is SHORTER than the great circle between its ports: %', v_worst_leg;
  end if;

  -- (d) THE GRAPH IS CONNECTED. Walk it from Lisboa and count what is reachable. A world with an
  --     unreachable half is not a world, and this is the only check that can tell.
  with recursive reached(id) as (
      select id from public.ports where code = 'LIS'
    union
      select case when l.from_port_id = r.id then l.to_port_id else l.from_port_id end
        from reached r
        join public.legs l on l.from_port_id = r.id or l.to_port_id = r.id
  )
  select count(*) into v_reachable from reached;
  if v_reachable <> v_ports then
    raise exception '0003 self-assert FAIL: only % of % ports are reachable from Lisboa', v_reachable, v_ports;
  end if;

  -- (e) No port is left without a sea lane at all.
  select count(*) into v_n
    from public.ports p
   where not exists (select 1 from public.legs l where l.from_port_id = p.id or l.to_port_id = p.id);
  if v_n <> 0 then
    raise exception '0003 self-assert FAIL: % port(s) have no leg', v_n;
  end if;

  -- (f) Every nation's capital code resolves to a real port.
  select count(*) into v_n
    from public.nations n
   where n.capital_port_code is not null
     and not exists (select 1 from public.ports p where p.code = n.capital_port_code);
  if v_n <> 0 then
    raise exception '0003 self-assert FAIL: % nation(s) name a capital port that does not exist', v_n;
  end if;

  -- (g) The culture mask BLOCKS and PERMITS. A mask that blocked nothing would pass every other
  --     check in this file, so both directions are counted.
  select count(*) into v_wine_blocked
    from public.ports p, public.goods g
   where g.code = 'wine' and p.culture = any(g.culture_mask);
  select count(*) into v_wine_ok
    from public.ports p, public.goods g
   where g.code = 'wine' and not (p.culture = any(g.culture_mask));
  if v_wine_blocked = 0 or v_wine_ok = 0 then
    raise exception '0003 self-assert FAIL: wine is blocked at % ports and traded at % — the mask is not doing anything',
      v_wine_blocked, v_wine_ok;
  end if;

  -- (h) Every port trades something, or the economy has a hole in it.
  select count(*) into v_n
    from public.ports p
   where not exists (select 1 from public.port_specialties s where s.port_id = p.id);
  if v_n <> 0 then
    select string_agg(p.code, ', ') into v_lonely
      from public.ports p
     where not exists (select 1 from public.port_specialties s where s.port_id = p.id);
    raise exception '0003 self-assert FAIL: % port(s) are known for nothing: %', v_n, v_lonely;
  end if;

  -- (i) The 0001 lockdown still holds after seeding eight tables.
  select count(*) into v_n from public.client_write_grants();
  if v_n <> 0 then
    raise exception '0003 self-assert FAIL: seeding the world minted % client write grant(s)', v_n;
  end if;

  select round((l.distance_nm)::numeric, 1) into v_lis_cad
    from public.legs l
    join public.ports a on a.id = l.from_port_id
    join public.ports b on b.id = l.to_port_id
   where (a.code, b.code) in (('CAD', 'LIS'), ('LIS', 'CAD'));

  raise notice '0003 self-assert ok: % ports, % legs, % goods, % seas, % regions, % nations, % specialty rows; every leg is canonical and >= its great circle (worst detour %.2fx); all % ports reachable from Lisboa; Lisboa-Cádiz is % nm sailed round Cape St Vincent; wine is refused at % ports and traded at %; 0 client write grants',
    v_ports, v_legs, v_goods, v_seas, v_regions, v_nations, v_specialties,
    v_worst_ratio, v_reachable, v_lis_cad, v_wine_blocked, v_wine_ok;
end $$;
`)

const sql = lines.join('\n')
writeFileSync(OUT, sql, 'utf8')
console.log(`wrote ${OUT.replace(ROOT, '.')}`)
console.log(`  ${ports.length} ports · ${legRows.length} legs · ${goods.length} goods · ${seas.length} seas · ${regions.length} regions · ${NATIONS.length} nations · ${specialtyRows.length} specialty rows`)
console.log(`  ${(sql.length / 1024).toFixed(0)} KB of SQL`)
console.log(`  nations actually holding a port: ${[...nationsWithPorts].sort().join(' ')}`)
console.log(`  ports with no nation: ${[...derived.values()].filter((d) => !d.nation).length}`)

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ONE DERIVATION: data/*.json → the world's rows, as the database should hold them.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Extracted VERBATIM from scripts/build-world-seed.mjs (2026-08-24) so that three callers can
// compose ONE authority instead of each keeping a copy:
//
//   * scripts/build-world-growth.mjs   — emits a GROWTH migration: the delta from the world the
//                                        applied chain holds to the world data/*.json describes
//   * scripts/db/world-guard.mjs       — the standing check, on every apply: the applied world
//                                        EQUALS the derived world, or the run fails
//   * scripts/build-world-seed.mjs     — retired to a refusal stub (0003 is applied to production
//                                        and frozen); its derivation lives here now
//
// Every rule is stated once, below, and applied to every port:
//   code          three letters from the name, deduplicated; the twelve V0 codes are preserved
//   size_tier     dataset tier 1/2/3 → 5/3/2 (a great entrepôt, a working port, a small harbour)
//   max_draft     from size_tier, minus the river and bar ports which are shallow by geography
//   yard/academy  from size_tier: a great port refits and teaches, a small one does neither
//   dev_*         from size_tier and what the port actually trades
//   culture       from its region, with the overrides history demands (Ceuta is a Latin garrison)
//   nation        the 1550 sovereign, where one of the seeded powers plainly held it; else null
//
// WHAT IS NOT DERIVED: coordinates (Wikidata P625, never touched), the specialty lists (editorial,
// sourced in docs/WORLD_DATA.md). The leg distances retired with the graph (0049).
//
// ⚠ CODE STABILITY IS A DEPLOYED CONTRACT. assignCodes() walks data/ports.json in ARRAY ORDER and
// hands out first-free codes, so inserting a port in the middle of the array can steal the code a
// later port already holds IN PRODUCTION. New ports are APPENDED; deriveWorld() cannot see the
// deployed world, so the growth generator and the guard both verify code agreement against the
// database and fail loudly if an existing port's code would change.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

export const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..')
const DATA = join(REPO_ROOT, 'data')

const NM_PER_RAD = 3440.065
const rad = (d) => (d * Math.PI) / 180
export const gcNm = (lat1, lon1, lat2, lon2) =>
  2 * NM_PER_RAD * Math.asin(Math.min(1, Math.sqrt(
    Math.sin(rad(lat2 - lat1) / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lon2 - lon1) / 2) ** 2,
  )))

export function round2(n) { return Math.round(n * 100) / 100 }

/** SQL string literal — null becomes SQL null. */
export const q = (s) => (s === null || s === undefined ? 'null' : `'${String(s).replace(/'/g, "''")}'`)

// ── CODES ─────────────────────────────────────────────────────────────────────────────────────
// ports.code is `^[A-Z]{3}$` and unique — and once a code has SHIPPED it is that port's identity
// for ever: fleets dock at it, DESIGN.md's worked examples address it, and production rows carry
// it.
//
// THE LAW (2026-08-24): EVERY port's code is PINNED here, and deriveWorld() REFUSES a port that
// has no pin. Codes used to be assigned by walking data/ports.json in array order and handing out
// first-free codes — so when ten island ports were inserted ALPHABETICALLY, Chios stole CHI from
// Chittagong, Port Louis stole POR from Port Royal, Port Royal then stole PRT from Portobelo, and
// Tidore stole TRI from Tripoli: four deployed harbours silently renamed by an insertion order
// (caught by diffing the derived world against the applied 0003 before any of it shipped). A pin
// map cannot be reordered into a different world. To add a port: append its pin (the error message
// suggests a free one); NEVER change a shipped pin. The 214 pins below are byte-equal to what
// production 0003 applied; the ten island pins are authored here, first shipped by 0041.
const PORT_CODES = {
  'acapulco': 'ACA',
  'accra': 'ACC',
  'aden': 'ADE',
  'agadir': 'AGA',
  'alexandria': 'ALE',
  'algiers': 'ALG',
  'ambon': 'AMB',
  'amsterdam': 'AMS',
  'ancona': 'ANC',
  'angra-do-heroismo': 'ANG',
  'antalya': 'ANT',
  'antwerp': 'ARP',
  'arkhangelsk': 'ARK',
  'ayutthaya': 'AYU',
  'banda-aceh': 'BAN',
  'banda-neira': 'BND',
  'bandar-abbas': 'BAS',
  'banten': 'BNT',
  'barcelona': 'BAR',
  'basra': 'BSR',
  'beirut': 'BEI',
  'belem': 'BEL',
  'bergen': 'BER',
  'bilbao': 'BIL',
  'bordeaux': 'BOR',
  'boston': 'BOS',
  'bridgetown': 'BRI',
  'bristol': 'BRS',
  'bruges': 'BRU',
  'buenos-aires': 'BUE',
  'busan': 'BUS',
  'cadiz': 'CAD',
  'cagliari': 'CAG',
  'calabar': 'CAL',
  'calais': 'CLS',
  'callao': 'CLL',
  'cape-coast': 'CAP',
  'cape-town': 'CPT',
  'cartagena': 'CAR',
  'cebu': 'CEB',
  'ceuta': 'CEU',
  'chennai': 'CHE',
  'chios': 'CHS',
  'chittagong': 'CHI',
  'cidade-velha': 'CID',
  'colombo': 'COL',
  'copenhagen': 'COP',
  'corfu': 'COR',
  'cork': 'CRK',
  'cumana': 'CUM',
  'dili': 'DIL',
  'diu': 'DIU',
  'dublin': 'DUB',
  'dubrovnik': 'DBR',
  'elmina': 'ELM',
  'famagusta': 'FAM',
  'feodosia': 'FEO',
  'fukuoka': 'FUK',
  'funchal': 'FNC',
  'fuzhou': 'FUZ',
  'galle': 'GAL',
  'gdansk': 'GDA',
  'genoa': 'GOA',
  'gibraltar': 'GIB',
  'goree': 'GOR',
  'guangzhou': 'GUA',
  'hadibu': 'HAD',
  'hagatna': 'HAG',
  'hamburg': 'HAM',
  'hanoi': 'HAN',
  'havana': 'HAV',
  'heraklion': 'HER',
  'hirado': 'HIR',
  'hoi-an': 'HOI',
  'hong-kong': 'HON',
  'honolulu': 'HNL',
  'hooghly': 'HOO',
  'hoorn': 'HRN',
  'hormuz': 'HOR',
  'incheon': 'INC',
  'istanbul': 'IST',
  'izmir': 'IZM',
  'jaffna': 'JAF',
  'jakarta': 'JAK',
  'jamestown': 'JAM',
  'jeddah': 'JED',
  'jeju': 'JEJ',
  'kagoshima': 'KAG',
  'kaliningrad': 'KAL',
  'kannur': 'KAN',
  'karachi': 'KAR',
  'khambhat': 'KHA',
  'kilwa': 'KIL',
  'kingston-upon-hull': 'KIN',
  'kochi': 'KOC',
  'kollam': 'KOL',
  'kozhikode': 'KOZ',
  'kupang': 'KUP',
  'la-rochelle': 'LAR',
  'lagos-ng': 'LAG',
  'las-palmas': 'LPA',
  'le-havre': 'LEH',
  'leith': 'LEI',
  'lisbon': 'LIS',
  'livorno': 'LIV',
  'london': 'LON',
  'longyearbyen': 'LNG',
  'luanda': 'LUA',
  'lubeck': 'LUB',
  'macau': 'MAC',
  'machilipatnam': 'MCH',
  'makassar': 'MAK',
  'malacca': 'MAL',
  'malaga': 'MLG',
  'male': 'MLE',
  'malindi': 'MLN',
  'manama': 'MAN',
  'mangaluru': 'MNG',
  'manila': 'MNL',
  'marseille': 'MRS',
  'massawa': 'MAS',
  'matsumae': 'MAT',
  'messina': 'MES',
  'middelburg': 'MID',
  'mocha': 'MOC',
  'mogadishu': 'MOG',
  'mokpo': 'MOK',
  'mombasa': 'MOM',
  'mozambique-island': 'ISL',
  'mumbai': 'MUM',
  'muscat': 'MUS',
  'myeik': 'MYE',
  'nagasaki': 'NAG',
  'naha': 'NAH',
  'nampo': 'NAM',
  'nantes': 'NAN',
  'naples': 'NAP',
  'new-york': 'NEW',
  'ningbo': 'NIN',
  'nuuk': 'NUU',
  'old-goa': 'OLD',
  'oran': 'ORA',
  'osaka': 'OSA',
  'ouidah': 'OUI',
  'palermo': 'PAL',
  'palma': 'PLM',
  'panama-city': 'PAN',
  'paramaribo': 'PAR',
  'patras': 'PAT',
  'pattani': 'PTT',
  'plymouth': 'PLY',
  'ponta-delgada': 'PON',
  'port-louis': 'PLO',
  'port-royal': 'POR',
  'porto': 'OPO',
  'portobelo': 'PRT',
  'portsmouth': 'PTH',
  'pulicat': 'PUL',
  'quanzhou': 'QUA',
  'quebec-city': 'QUE',
  'recife': 'REC',
  'reykjavik': 'REY',
  'rhodes': 'RHO',
  'riga': 'RIG',
  'rio-de-janeiro': 'RIO',
  'rotterdam': 'ROT',
  'safi': 'SAF',
  'saint-louis': 'SAI',
  'saint-malo': 'SNT',
  'sakai': 'SAK',
  'sale': 'SAL',
  'salvador': 'SLV',
  'san-juan': 'SAN',
  'sanlucar': 'SNL',
  'santa-cruz-de-tenerife': 'TEN',
  'santo-domingo': 'SGO',
  'santos': 'SOS',
  'sao-tome': 'SAO',
  'setubal': 'SET',
  'seville': 'SVQ',
  'shimonoseki': 'SHI',
  'sofala': 'SOF',
  'soyo': 'SOY',
  'split': 'SPL',
  'st-augustine': 'STA',
  'st-georges-bermuda': 'STG',
  'st-johns-nl': 'STJ',
  'stockholm': 'STO',
  'suakin': 'SUA',
  'suez': 'SUE',
  'surabaya': 'SUR',
  'surat': 'SRT',
  'sydney': 'SYD',
  'tainan': 'TAI',
  'tallinn': 'TAL',
  'tangier': 'TAN',
  'ternate': 'TER',
  'thanlyin': 'THA',
  'thessaloniki': 'THE',
  'tidore': 'TID',
  'tokyo': 'TOK',
  'tongyeong': 'TON',
  'torshavn': 'TOR',
  'toulon': 'TOU',
  'trabzon': 'TRA',
  'tripoli-lb': 'TRI',
  'tripoli-ly': 'TRP',
  'trondheim': 'TRO',
  'tsushima': 'TSU',
  'tunis': 'TUN',
  'turku': 'TUR',
  'ulsan': 'ULS',
  'valencia': 'VAL',
  'valletta': 'VLL',
  'valparaiso': 'VLP',
  'vardo': 'VAR',
  'venice': 'VEN',
  'veracruz': 'VER',
  'visby': 'VIS',
  'willemstad': 'WIL',
  'xiamen': 'XIA',
  'yeosu': 'YEO',
  'zakynthos': 'ZAK',
  'zanzibar': 'ZAN',
}

const fold = (s) =>
  s.normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase().replace(/[^A-Z]/g, '')

export function assignCodes(items, pinned = {}) {
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
  chios: 'latin',            // the Genoese Maona held the island until 1566
  male: 'islamic',           // the Maldives, an Islamic sultanate since 1153
  'port-louis': 'guinean',   // like cape-town: a Dutch station on an ocean coast, not a Swahili port
}

// ── NATIONS ───────────────────────────────────────────────────────────────────────────────────
// The powers whose flag a port could fly in 1550, and their capital port. A port is given a nation
// only where one of these plainly held it; everywhere else nation_id is NULL and the port's
// `country` text — which comes from the dataset — is the honest answer. Inventing a sovereign for
// two hundred harbours would be worse than admitting the game does not model one.
export const NATIONS = [
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
  heraklion: 'VEN', corfu: 'VEN', zakynthos: 'VEN', // Venice's sea empire: Crete until 1669, the Ionians throughout
  chios: 'GEN',              // the Genoese Maona until 1566
  cagliari: 'ESP',           // Sardinia under the Crown of Aragon
  hadibu: null,              // Socotra answered to the Mahra sultans, not the Porte — an explicit "no seeded power"
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
const INDUSTRY_CATEGORIES = new Set(['metal', 'textile', 'naval-stores'])

// ── GOODS ─────────────────────────────────────────────────────────────────────────────────────
// base_value is the midpoint of the dataset's researched price band. bulk and spoilage are by
// category: a tun of pepper is not a tun of timber, and fish rots while iron does not.
const BULK = { spice: 0.6, textile: 0.9, metal: 0.8, luxury: 0.3, foodstuff: 1.0, raw: 1.2, 'naval-stores': 1.4 }
const PERISH = {
  'dried-fish': 0.004, herring: 0.004, cheese: 0.004, 'salted-beef': 0.003, 'dried-fruit': 0.003,
  wheat: 0.002, rice: 0.002, sugar: 0.001, 'olive-oil': 0.001, hides: 0.001, furs: 0.001,
  // the catalogue growth to 243: same rule — fish and fresh stores spoil, grain slowly, durables never
  butter: 0.004, citrus: 0.005, beer: 0.003, sake: 0.002, caviar: 0.004, 'salted-tuna': 0.004,
  seaweed: 0.001, 'dried-abalone': 0.001, trepang: 0.001, molasses: 0.001, dates: 0.002,
  figs: 0.002, almonds: 0.001, hazelnuts: 0.001, pistachios: 0.001, lychees: 0.002,
  coconuts: 0.002, sago: 0.002, maize: 0.002, cassava: 0.002, rye: 0.002, barley: 0.002,
  'palm-sugar': 0.001, ghee: 0.002, 'sesame-oil': 0.001, 'palm-oil': 0.001, 'sharks-fin': 0.001,
  tamarind: 0.001,
}
/** DESIGN B.4/G.3: cultures that will not trade the good at all. ONE rule for every alcohol. */
const ALCOHOL_MASK = ['islamic', 'swahili']
const CULTURE_MASK = { wine: ALCOHOL_MASK, beer: ALCOHOL_MASK, sake: ALCOHOL_MASK, rum: ALCOHOL_MASK, brandy: ALCOHOL_MASK, arrack: ALCOHOL_MASK }

/**
 * Derive the whole world from data/*.json — the rows the database should hold, keyed the way the
 * database keys them (port/good/sea/region/nation CODES).
 */
export function deriveWorld() {
  const ports = JSON.parse(readFileSync(join(DATA, 'ports.json'), 'utf8')).ports
  const goods = JSON.parse(readFileSync(join(DATA, 'goods.json'), 'utf8')).goods
  const regions = JSON.parse(readFileSync(join(DATA, 'regions.json'), 'utf8')).regions
  const seas = JSON.parse(readFileSync(join(DATA, 'seas.json'), 'utf8')).seas

  const portCode = new Map()
  for (const p of ports) {
    const pin = PORT_CODES[p.id]
    if (!pin) {
      // the old assignment rule, run against every pinned code, names a free candidate
      const taken = Object.fromEntries(Object.values(PORT_CODES).map((c, i) => [`__taken${i}`, c]))
      const free = assignCodes([{ id: p.id, name: p.name }], taken).get(p.id)
      throw new Error(
        `port '${p.id}' has no pinned code. A code is a shipped identity, so it is authored, not ` +
        `derived: add  '${p.id}': '${free}',  to PORT_CODES in scripts/lib/world-derive.mjs ` +
        `(${free} is free by the assignment rule) and never change a shipped pin.`)
    }
    portCode.set(p.id, pin)
  }
  {
    const seen = new Set()
    for (const c of portCode.values()) {
      if (seen.has(c)) throw new Error(`PORT_CODES pins the code ${c} twice`)
      seen.add(c)
    }
  }
  const seaCode = assignCodes(seas)
  const regionCode = assignCodes(regions)

  const goodById = new Map(goods.map((g) => [g.id, g]))

  function derivePort(p) {
    const size = SIZE_BY_TIER[p.tier]
    const specialties = (p.goods ?? []).filter((g) => goodById.has(g))
    const industrial = specialties.filter((g) => INDUSTRY_CATEGORIES.has(goodById.get(g).category)).length
    const yardTier = size === 5 ? 3 : size === 3 ? 1 : 0
    const clamp = (n) => Math.max(0, Math.min(20, Math.round(n)))
    return {
      id: p.id,
      code: portCode.get(p.id),
      name: p.name,
      country: p.countryName,
      lat: round2(p.lat),
      lon: round2(p.lon),
      sea_code: seaCode.get(p.sea),
      region_code: regionCode.get(p.region),
      size_tier: size,
      max_draft: SHALLOW.has(p.id) ? 2 : size === 5 ? 5 : size === 3 ? 4 : 3,
      yard_tier: yardTier,
      has_yard: yardTier > 0,
      has_academy: size === 5,
      dev_commerce: clamp(size * 2.4 + specialties.length),
      dev_industry: clamp(size * 2.0 + industrial * 1.5),
      dev_military: clamp(size * 1.8 + (yardTier > 0 ? 2 : 0)),
      tax_rate: 0.03,
      crew_pool: size * 80,
      culture: CULTURE_OVERRIDE[p.id] ?? CULTURE_BY_REGION[p.region] ?? 'latin',
      nation_code: Object.hasOwn(NATION_OVERRIDE, p.id) ? NATION_OVERRIDE[p.id] : NATION_BY_COUNTRY[p.country] ?? null,
      specialties,
    }
  }
  const derivedPorts = ports.map(derivePort)
  const byId = new Map(derivedPorts.map((d) => [d.id, d]))

  const PIRATE_SEAS = new Set(['mediterranean-sea', 'strait-of-malacca', 'caribbean-sea', 'gulf-of-guinea', 'south-china-sea', 'gulf-of-aden', 'red-sea', 'persian-gulf', 'arabian-sea'])
  const OPEN_OCEANS = new Set(['arctic-ocean', 'north-atlantic', 'south-atlantic', 'indian-ocean', 'north-pacific', 'south-pacific', 'norwegian-sea', 'barents-sea'])
  const derivedSeas = seas.map((s) => ({
    code: seaCode.get(s.id),
    name: s.name,
    hazard_base: OPEN_OCEANS.has(s.id) ? 0.018 : PIRATE_SEAS.has(s.id) ? 0.012 : 0.008,
    piracy_index: PIRATE_SEAS.has(s.id) ? 0.45 : OPEN_OCEANS.has(s.id) ? 0.12 : 0.2,
  }))

  const derivedRegions = regions.map((r) => ({ code: regionCode.get(r.id), name: r.name }))

  const derivedNations = NATIONS.map(([code, name, flag, fallbackCapital]) => {
    const capitalPort = CAPITALS[code]
    const capital = capitalPort ? byId.get(capitalPort)?.code : fallbackCapital
    return { code, name, flag_char: flag, capital_port_code: capital ?? fallbackCapital }
  })

  const derivedGoods = goods.map((g) => ({
    code: g.id,
    name: g.name,
    base_value: (g.baseValue[0] + g.baseValue[1]) / 2,
    bulk: BULK[g.category] ?? 1.0,
    perishable_pct_day: PERISH[g.id] ?? 0,
    category: g.category,
    culture_mask: CULTURE_MASK[g.id] ?? [],
  }))

  // (legs) RETIRED 2026-08-24 with migration 0049: public.legs and data/sea-routes.json are
  // gone — the raster (0046) is the one authority for what water connects to what.

  const specialtyPairs = []
  for (const d of derivedPorts) for (const g of d.specialties) specialtyPairs.push([d.code, g])

  return {
    ports: derivedPorts,
    goods: derivedGoods,
    seas: derivedSeas,
    regions: derivedRegions,
    nations: derivedNations,
    specialtyPairs,
    portCode,
    seaCode,
    regionCode,
  }
}

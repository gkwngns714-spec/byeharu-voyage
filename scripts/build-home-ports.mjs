// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-home-ports.mjs — every country's HOME CITIES (docs/INFLUENCE.md §3, OWNER O1, rule D1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-17: "each country will have 3~4 cities around them, and rest of them can be
// competitive". A home city never changes hands; every other harbour is contested.
//
// THE RULE (D1), computed once from the applied chain's sailed distances (public.sea_reaches, the
// miles the SAIL picker uses), then AUTHORED: data/home-ports.json is the one list, the owner may
// edit it, and migrations 0143 / 0187 + the world guard hold the database equal to it.
// Since GP1 (0187, docs/GREAT_POWERS.md) only the TEN GREAT POWERS have homes:
//   1. Each great power takes its capital, then the harbours it FOUNDED in order of sailed miles from
//      the capital (ties: port code), up to 4.
//   2. A power left short takes the nearest harbours no great power founded (free, or founded by one
//      of the thirteen local rulers) — shortest distance first across the whole world, so no harbour
//      is home to two powers and no great power loses a city. (Mughal India: Surat, Khambhat.)
//
// Usage:
//   node scripts/build-home-ports.mjs           write data/home-ports.json and print the table
//   node scripts/build-home-ports.mjs --check   only report where the rule and the file differ
//                                               (exit 0 either way: the file is authored)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import path from 'node:path'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { applyWithPrefixCache } from './db/prefix-cache.mjs'
import { BROWSER_VARIANT, IMAGE_CACHE_DIR, chainAndFingerprint } from './db/build-image.mjs'
import { GREAT_POWERS } from './lib/world-derive.mjs'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const OUT = path.resolve(HERE, '..', 'data', 'home-ports.json')
const check = process.argv.includes('--check')

const { files } = await chainAndFingerprint()
const { db } = await applyWithPrefixCache({
  variant: BROWSER_VARIANT, files, cacheDir: path.join(IMAGE_CACHE_DIR, 'prefix'), log: () => {},
})
const q = async (s) => (await db.query(s)).rows

const great = new Set(GREAT_POWERS)
const nations = (await q(`select n.code, n.name, n.capital_port_code as capital from public.nations n order by n.code`))
  .filter((n) => great.has(n.code))
const harbours = await q(`select p.code, p.name, n.code as nation from public.ports p
                            left join public.nations n on n.id = p.nation_id where p.kind = 'HARBOUR'`)
const reaches = new Map((await q(`select code, reaches from public.sea_reaches`)).map((r) => [r.code, r.reaches]))
const nameOf = new Map(harbours.map((h) => [h.code, h.name]))
const miles = (from, to) => (from === to ? 0 : Number(reaches.get(from)?.[to] ?? Infinity))

const homes = {}
const want = {}
for (const n of nations) {
  const own = harbours.filter((h) => h.nation === n.code)
  if (!own.some((h) => h.code === n.capital)) throw new Error(`${n.code}: its capital ${n.capital} is not one of its harbours`)
  own.sort((a, b) => (a.code === n.capital ? -1 : b.code === n.capital ? 1 : 0)
    || miles(n.capital, a.code) - miles(n.capital, b.code) || a.code.localeCompare(b.code))
  want[n.code] = 4
  homes[n.code] = own.slice(0, want[n.code]).map((h) => h.code)
}
const free = harbours.filter((h) => h.nation === null || !great.has(h.nation))
const offers = []
for (const n of nations) {
  if (homes[n.code].length >= want[n.code]) continue
  for (const h of free) offers.push({ nation: n.code, port: h.code, nm: miles(n.capital, h.code) })
}
offers.sort((a, b) => a.nm - b.nm || a.nation.localeCompare(b.nation) || a.port.localeCompare(b.port))
const taken = new Set()
for (const o of offers) {
  if (taken.has(o.port) || homes[o.nation].length >= want[o.nation]) continue
  homes[o.nation].push(o.port)
  taken.add(o.port)
}
for (const n of nations) {
  if (homes[n.code].length !== want[n.code]) throw new Error(`${n.code}: found ${homes[n.code].length} homes, wants ${want[n.code]}`)
}

const table = nations.map((n) => `${n.code}  ${homes[n.code].map((c) => {
  const founder = harbours.find((h) => h.code === c).nation
  const top = founder === n.code ? '' : founder === null ? ' (free)' : ` (founded by ${founder})`
  return `${nameOf.get(c)} ${Math.round(miles(n.capital, c))}${top}`
}).join(' · ')}`).join('\n')

if (check) {
  const file = existsSync(OUT) ? JSON.parse(readFileSync(OUT, 'utf8')).homes : {}
  const diffs = nations.filter((n) => JSON.stringify(file[n.code] ?? []) !== JSON.stringify(homes[n.code]))
  if (diffs.length === 0) console.log('home-ports --check: data/home-ports.json equals the computed rule (D1).')
  for (const n of diffs) console.log(`home-ports --check: ${n.code} file ${JSON.stringify(file[n.code] ?? [])} vs rule ${JSON.stringify(homes[n.code])}`)
} else {
  writeFileSync(OUT, JSON.stringify({
    _comment: 'Every country\'s home cities (docs/INFLUENCE.md §3, rule D1). AUTHORED after scripts/build-home-ports.mjs wrote it once; a home city never changes hands. Only the ten great powers have homes (docs/GREAT_POWERS.md, 0187). Migrations 0143 and 0187 seed public.port_allegiance.home from it, and scripts/db/world-guard.mjs holds the database equal to it.',
    homes,
  }, null, 2) + '\n')
  console.log(table)
  console.log(`wrote ${OUT}: ${Object.values(homes).flat().length} home cities`)
}
process.exit(0)

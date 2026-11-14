// gen-legs.mjs: THE SEAS OF EVERY PAIR THAT TOUCHES A HUB OF 0410, as scripts/build-sea-legs.mjs names them (the browser's pathfinder, then the
// door's own sampler public.course_zones), for the new pairs only: the pairs of the 249 old harbours are kept as data/sea-legs.json has them.
// LOCAL ONLY. It restores the cached head world (never from zero), reads its raster and roadsteads, adds the hubs' roadsteads from gen-sea's
// file, and writes (1) data/sea-legs.json with the five harbours in code order and (2) the rows 0410 embeds ([from, to, "ZONES"]).
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/pacific-pirates/gen-legs.mjs <sea.json> <out-rows.json>
import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { navFromServed, findPath } from '../../../../src/lib/sea/index.ts'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, REPO_ROOT, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
const [, , SEA, OUT] = process.argv
const sea = JSON.parse(await readFile(SEA, 'utf8'))
const files = []
for (const name of await migrationFiles()) { if (name.slice(10, 14) >= '0408') continue; files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') }) }
const { db } = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const raster = (await db.query(`select cols, rows, cell_deg::float8 as cell_deg, bits_per_cell, replace(encode(cells, 'base64'), e'\n', '') as cells_base64 from public.sea_raster where id = 1`)).rows[0]
const nav = navFromServed(raster)
const old = (await db.query(`select p.code, sr.roadstead_lat::float8 as lat, sr.roadstead_lon::float8 as lon from public.ports p join public.sea_reaches sr on sr.port_id = p.id where p.kind = 'HARBOUR' order by p.code collate "C"`)).rows
const file = JSON.parse(await readFile(path.join(REPO_ROOT, 'data', 'sea-legs.json'), 'utf8'))
if (JSON.stringify(file.harbours) !== JSON.stringify(old.map((h) => h.code))) throw new Error('data/sea-legs.json is not the cached world\'s harbours (already run?)')
const hubs = sea.hubs.map((h) => ({ code: h.code, lat: h.rlat, lon: h.rlon, hub: true }))
const all = [...old, ...hubs].sort((a, b) => (a.code < b.code ? -1 : 1))
const sets = [...file.sets]; const setIdx = new Map(sets.map((s, i) => [s, i]))
const idxOf = (z) => { const k = z.join(' '); if (!setIdx.has(k)) { setIdx.set(k, sets.length); sets.push(k) } return setIdx.get(k) }
const oldIdx = new Map(file.harbours.map((c, i) => [c, i]))
const pairs = []
for (const a of all) for (const b of all) if (a !== b && (a.hub || b.hub)) {
  const r = findPath(nav, { lat: a.lat, lon: a.lon }, { lat: b.lat, lon: b.lon })
  if (!r) throw new Error(`${a.code} to ${b.code}: no water course`)
  pairs.push({ f: a.code, t: b.code, c: r.path })
}
const rows = new Map()
for (let i = 0; i < pairs.length; i += 200) {
  const part = pairs.slice(i, i + 200)
  const q = await db.query(`select (e->>'k')::int as k, public.course_zones(e->'c') as zones from jsonb_array_elements($1::jsonb) with ordinality x(e, o)`, [JSON.stringify(part.map((p, k) => ({ k, c: p.c })))])
  for (const r of q.rows) { if (!r.zones.length) throw new Error('a course crosses no sea'); rows.set(`${part[r.k].f} ${part[r.k].t}`, r.zones) }
}
const own = new Map()
for (const h of hubs) own.set(h.code, (await db.query(`select public.sea_zone_at($1::float8, $2::float8) as z`, [h.lat, h.lon])).rows[0].z)
const legs = all.map((a) => all.map((b) => {
  if (a === b) return a.hub ? idxOf([own.get(a.code)]) : file.legs[oldIdx.get(a.code)][oldIdx.get(a.code)]
  if (!a.hub && !b.hub) return file.legs[oldIdx.get(a.code)][oldIdx.get(b.code)]
  return idxOf(rows.get(`${a.code} ${b.code}`))
}))
const note = JSON.stringify(file.note)
const body = `{\n"note": ${note},\n"harbours": ${JSON.stringify(all.map((h) => h.code))},\n"sets": ${JSON.stringify(sets)},\n"legs": [\n${legs.map((r) => JSON.stringify(r)).join(',\n')}\n]\n}\n`
await writeFile(path.join(REPO_ROOT, 'data', 'sea-legs.json'), body)
await writeFile(OUT, JSON.stringify({ own: Object.fromEntries(own), rows: [...rows].map(([k, z]) => [...k.split(' '), z.join(' ')]) }))
console.log(`pairs ${pairs.length}, sets ${file.sets.length} -> ${sets.length}, hub zones ${JSON.stringify(Object.fromEntries(own))}`)
await db.close(); process.exit(0)

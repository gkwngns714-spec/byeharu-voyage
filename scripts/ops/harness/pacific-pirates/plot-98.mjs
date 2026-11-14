// plot-98.mjs: THE COURSES PROOF 98 HOLDS, FOR THE FIVE HAVENS OF 0414. LOCAL ONLY; not in CI.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/pacific-pirates/plot-98.mjs
// Proof 98 (0403) holds, as data, the course the client's pathfinder plots from Acapulco and from Sakai to EVERY other harbour, and compares Trade's
// tag with the sail door on each. 0414 adds five harbours, so the proof needs their ten courses too. This plots them exactly as
// scripts/build-sea-legs.mjs plots the others (src/lib/sea findPath over the raster the world serves, roadstead to roadstead, on the world WITH 0414)
// and prints the ten fixture rows to paste into the proof's $fix$ list.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { navFromServed, findPath } from '../../../../src/lib/sea/index.ts'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
const files = []
for (const name of await migrationFiles()) { if (name.slice(10, 14) > '0414') continue; files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') }) }
const { db } = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const raster = (await db.query(`select cols, rows, cell_deg::float8 as cell_deg, bits_per_cell, replace(encode(cells, 'base64'), e'\n', '') as cells_base64 from public.sea_raster where id = 1`)).rows[0]
const nav = navFromServed(raster)
const hs = (await db.query(`select p.code, sr.roadstead_lat::float8 as lat, sr.roadstead_lon::float8 as lon from public.ports p join public.sea_reaches sr on sr.port_id = p.id
                             where p.code in ('ACA', 'SAK', 'PTC', 'MWY', 'TDC', 'FLO', 'DGA') order by p.code collate "C"`)).rows
const at = (c) => hs.find((h) => h.code === c)
for (const a of ['ACA', 'SAK']) for (const b of ['DGA', 'FLO', 'MWY', 'PTC', 'TDC']) {
  const r = findPath(nav, { lat: at(a).lat, lon: at(a).lon }, { lat: at(b).lat, lon: at(b).lon })
  if (!r) throw new Error(`${a} to ${b}: no water course`)
  console.log(JSON.stringify([a, b, r.path]) + ',')
}
await db.close(); process.exit(0)

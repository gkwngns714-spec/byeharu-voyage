// The storage shape is the cost. One 1 MB bytea (TOASTed) vs 720 inline rows of 1,440 bytes.
import { loadPGlite } from './pglite-loader.mjs'
const PGlite = await loadPGlite()
import { readFileSync } from 'node:fs'
import { buildNavGrid, findPath, COLS, ROWS, CELL_DEG } from './pathfind.mjs'

const nav = buildNavGrid()
const db = await new PGlite()
for (const f of ['./raster.sql', './verify.sql', './verify3.sql']) {
  await db.exec(readFileSync(new URL(f, import.meta.url), 'utf8'))
}
await db.query(`insert into sea.raster (id, cols, rows, cell_deg, cells) values (1,$1,$2,$3,$4)`,
  [COLS, ROWS, CELL_DEG, nav])
let t = performance.now()
for (let r = 0; r < ROWS; r++) {
  await db.query(`insert into sea.raster_rows (row_idx, cells) values ($1, $2)`,
    [r, nav.subarray(r * COLS, r * COLS + COLS)])
}
console.log(`720 raster rows loaded in ${(performance.now() - t).toFixed(0)} ms`)
const sz = await db.query(`select pg_total_relation_size('sea.raster_rows') a, pg_total_relation_size('sea.raster') b`)
console.log(`sea.raster_rows on disk: ${(Number(sz.rows[0].a) / 1024).toFixed(0)} KiB   sea.raster: ${(Number(sz.rows[0].b) / 1024).toFixed(0)} KiB`)

const scratch = { g: new Float64Array(COLS * ROWS), prev: new Int32Array(COLS * ROWS),
                  seen: new Int32Array(COLS * ROWS), stamp: 0 }
const P = { LIS: { lat: 38.71, lon: -9.14 }, CAD: { lat: 36.53, lon: -6.29 },
            NAG: { lat: 32.74, lon: 129.87 }, CAL: { lat: 11.25, lon: 75.78 },
            AMS: { lat: 52.37, lon: 4.90 }, VEN: { lat: 45.44, lon: 12.34 },
            BCN: { lat: 41.38, lon: 2.18 }, SSA: { lat: -12.97, lon: -38.51 } }

console.log('\nroute                  | pts |    nm | 1-bytea ms | 720-rows ms | agree')
console.log('-----------------------+-----+-------+------------+-------------+------')
for (const [name, a, b] of [['Lisboa → Cádiz', 'LIS', 'CAD'], ['Lisboa → Amsterdam', 'LIS', 'AMS'],
                            ['Lisboa → Salvador', 'LIS', 'SSA'], ['Amsterdam → Venice', 'AMS', 'VEN'],
                            ['Lisboa → Calicut', 'LIS', 'CAL'], ['Lisboa → Nagasaki', 'LIS', 'NAG']]) {
  const r = findPath(nav, P[a], P[b], scratch)
  const json = JSON.stringify(r.path)
  const REP = 20
  let t1 = performance.now(); let l
  for (let i = 0; i < REP; i++) l = (await db.query(`select sea.path_is_navigable($1::jsonb,40,40) ok`, [json])).rows[0].ok
  const oneMs = (performance.now() - t1) / REP
  t1 = performance.now(); let s
  for (let i = 0; i < REP; i++) s = (await db.query(`select sea.path_is_navigable_rows($1::jsonb,40,40) ok`, [json])).rows[0].ok
  const rowMs = (performance.now() - t1) / REP
  console.log(`${name.padEnd(22)} | ${r.path.length.toString().padStart(3)} | ${Math.round(r.nm).toString().padStart(5)} | ${oneMs.toFixed(1).padStart(10)} | ${rowMs.toFixed(1).padStart(11)} | ${l === s ? 'yes' : '*** NO ***'}`)
}

console.log('\n── the anti-proof on the row-storage version ────────────────────────────────')
for (const [name, path] of [
  ['Lisboa → Barcelona straight across Iberia', [[38.71, -9.14], [41.38, 2.18]]],
  ['Alexandria → Aden straight through Arabia', [[31.20, 29.92], [12.79, 45.03]]],
  ['Veracruz → Acapulco straight across Mexico', [[19.19, -96.14], [16.85, -99.90]]],
  ['Lisboa → Nagasaki great circle over Asia', [[38.71, -9.14], [32.74, 129.87]]],
  ['a leg over the Sahara', [[30.0, -10.0], [25.0, 20.0]]],
  ['the Northeast Passage along the Siberian coast', [[70.0, 60.0], [70.0, 170.0]]],
  ['the Northwest Passage through the Canadian arctic', [[74.0, -95.0], [71.0, -130.0]]],
]) {
  const ok = (await db.query(`select sea.path_is_navigable_rows($1::jsonb,40,40) ok`, [JSON.stringify(path)])).rows[0].ok
  console.log(`  ${(ok === false ? 'REFUSED' : '*** ACCEPTED ***').padEnd(17)} ${name}`)
}
const good = findPath(nav, P.LIS, P.BCN, scratch)
const ok2 = (await db.query(`select sea.path_is_navigable_rows($1::jsonb,40,40) ok`, [JSON.stringify(good.path)])).rows[0].ok
console.log(`  ${(ok2 ? 'ACCEPTED' : '*** REFUSED ***').padEnd(17)} the real Lisboa → Barcelona, ${Math.round(good.nm)} nm round Gibraltar`)
await db.close()

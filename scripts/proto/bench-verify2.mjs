// Loop vs set-based verification, and the anti-proof for both.
import { loadPGlite } from './pglite-loader.mjs'
const PGlite = await loadPGlite()
import { readFileSync } from 'node:fs'
import { buildNavGrid, findPath, COLS, ROWS, CELL_DEG } from './pathfind.mjs'

const nav = buildNavGrid()
const db = await new PGlite()
for (const f of ['./raster.sql', './verify.sql', './verify2.sql']) {
  await db.exec(readFileSync(new URL(f, import.meta.url), 'utf8'))
}
await db.query(`insert into sea.raster (id, cols, rows, cell_deg, cells) values (1,$1,$2,$3,$4)`,
  [COLS, ROWS, CELL_DEG, nav])

const scratch = { g: new Float64Array(COLS * ROWS), prev: new Int32Array(COLS * ROWS),
                  seen: new Int32Array(COLS * ROWS), stamp: 0 }
const P = { LIS: { lat: 38.71, lon: -9.14 }, CAD: { lat: 36.53, lon: -6.29 },
            NAG: { lat: 32.74, lon: 129.87 }, CAL: { lat: 11.25, lon: 75.78 },
            AMS: { lat: 52.37, lon: 4.90 }, VEN: { lat: 45.44, lon: 12.34 },
            BCN: { lat: 41.38, lon: 2.18 }, SSA: { lat: -12.97, lon: -38.51 } }

console.log('route                  | pts |    nm | loop ms | set ms | agree')
console.log('-----------------------+-----+-------+---------+--------+------')
for (const [name, a, b] of [['Lisboa → Cádiz', 'LIS', 'CAD'], ['Lisboa → Amsterdam', 'LIS', 'AMS'],
                            ['Lisboa → Salvador', 'LIS', 'SSA'], ['Amsterdam → Venice', 'AMS', 'VEN'],
                            ['Lisboa → Calicut', 'LIS', 'CAL'], ['Lisboa → Nagasaki', 'LIS', 'NAG']]) {
  const r = findPath(nav, P[a], P[b], scratch)
  const json = JSON.stringify(r.path)
  const REP = 20
  let t = performance.now(); let l
  for (let i = 0; i < REP; i++) l = (await db.query(`select sea.path_is_navigable($1::jsonb,40,40) ok`, [json])).rows[0].ok
  const loopMs = (performance.now() - t) / REP
  t = performance.now(); let s
  for (let i = 0; i < REP; i++) s = (await db.query(`select sea.path_is_navigable_set($1::jsonb,40,40) ok`, [json])).rows[0].ok
  const setMs = (performance.now() - t) / REP
  console.log(`${name.padEnd(22)} | ${r.path.length.toString().padStart(3)} | ${Math.round(r.nm).toString().padStart(5)} | ${loopMs.toFixed(1).padStart(7)} | ${setMs.toFixed(1).padStart(6)} | ${l === s ? 'yes' : '*** NO ***'}`)
}

console.log('\n── the anti-proof, on BOTH implementations ──────────────────────────────────')
const bad = [
  ['Lisboa → Barcelona straight across Iberia', [[38.71, -9.14], [41.38, 2.18]]],
  ['Alexandria → Aden straight through Arabia', [[31.20, 29.92], [12.79, 45.03]]],
  ['Veracruz → Acapulco straight across Mexico', [[19.19, -96.14], [16.85, -99.90]]],
  ['Lisboa → Nagasaki great circle over Asia', [[38.71, -9.14], [32.74, 129.87]]],
  ['a leg over the Sahara', [[30.0, -10.0], [25.0, 20.0]]],
  ['one point only (not a path)', [[38.71, -9.14]]],
]
for (const [name, path] of bad) {
  const j = JSON.stringify(path)
  const l = (await db.query(`select sea.path_is_navigable($1::jsonb,40,40) ok`, [j])).rows[0].ok
  const s = (await db.query(`select sea.path_is_navigable_set($1::jsonb,40,40) ok`, [j])).rows[0].ok
  console.log(`  loop=${String(l).padEnd(5)} set=${String(s).padEnd(5)} ${l === false && s === false ? 'REFUSED  ' : '*** LEAK '}${name}`)
}
const good = findPath(nav, P.LIS, P.BCN, scratch)
const j = JSON.stringify(good.path)
const l2 = (await db.query(`select sea.path_is_navigable($1::jsonb,40,40) ok`, [j])).rows[0].ok
const s2 = (await db.query(`select sea.path_is_navigable_set($1::jsonb,40,40) ok`, [j])).rows[0].ok
console.log(`  loop=${l2} set=${s2}  ACCEPTED the real Lisboa → Barcelona, ${Math.round(good.nm)} nm round Gibraltar`)
await db.close()

// Measures the plpgsql A* inside PGlite — the runtime the game actually ships on.
// `node scripts/proto/bench-pglite.mjs`
import { PGlite } from '@electric-sql/pglite'
import { readFileSync } from 'node:fs'
import { buildNavGrid, COLS, ROWS, CELL_DEG } from './pathfind.mjs'

const sql = readFileSync(new URL('./pglite-astar.sql', import.meta.url), 'utf8')

const nav = buildNavGrid()
console.log(`nav grid ${COLS}x${ROWS}, ${nav.length} bytes`)

let t = performance.now()
const db = await new PGlite()
await db.query('select 1')
console.log(`PGlite boot: ${(performance.now() - t).toFixed(0)} ms`)

await db.exec(sql)

// The raster goes in as one bytea. Hex is the portable way through the wire protocol.
t = performance.now()
await db.query(
  `insert into sea.raster (id, cols, rows, cell_deg, cells) values (1, $1, $2, $3, $4)
   on conflict (id) do update set cells = excluded.cells`,
  [COLS, ROWS, CELL_DEG, nav])
console.log(`raster loaded (${(nav.length / 1024).toFixed(0)} KiB): ${(performance.now() - t).toFixed(0)} ms`)
const size = await db.query(`select pg_column_size(cells) sz, octet_length(cells) ol from sea.raster`)
console.log(`stored: ${size.rows[0].sz} bytes on disk (TOAST-compressed), ${size.rows[0].ol} logical`)

const CASES = [
  ['Lisboa → Cádiz', 38.71, -9.14, 36.53, -6.29],
  ['Lisboa → Amsterdam', 38.71, -9.14, 52.37, 4.90],
  ['Lisboa → Salvador', 38.71, -9.14, -12.97, -38.51],
  ['Amsterdam → Venice', 52.37, 4.90, 45.44, 12.34],
  ['Lisboa → Calicut', 38.71, -9.14, 11.25, 75.78],
  ['Lisboa → Nagasaki', 38.71, -9.14, 32.74, 129.87],
]

console.log('\nroute                     |     ms |  expanded |      nm')
console.log('--------------------------+--------+-----------+--------')
for (const [name, a, b, c, d] of CASES) {
  const t0 = performance.now()
  let r
  try {
    r = await db.query(`select * from sea.find_path($1, $2, $3, $4)`, [a, b, c, d])
  } catch (e) {
    console.log(`${name.padEnd(25)} | FAILED: ${e.message}`)
    continue
  }
  const ms = performance.now() - t0
  const row = r.rows[0]
  console.log(`${name.padEnd(25)} | ${ms.toFixed(0).padStart(6)} | ${(row ? row.expanded : 0).toString().padStart(9)} | ${row ? Math.round(row.nm) : 'null'}`)
}
await db.close()

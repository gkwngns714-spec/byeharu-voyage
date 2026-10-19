// apply.mjs <image> <migration...> — apply migrations on a world image (PGlite), print their notices and timing
import { readFile } from 'node:fs/promises'
import { readFileSync } from 'node:fs'
import { gunzipSync } from 'node:zlib'
import { createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'
const require = createRequire('C:/Users/gkwng/dev/bv-raid/package.json')
const { PGlite } = await import(pathToFileURL(require.resolve('@electric-sql/pglite')).href)
const [image, ...migs] = process.argv.slice(2)
const db = await PGlite.create({ loadDataDir: new Blob([gunzipSync(await readFile(image))], { type: 'application/x-tar' }) })
for (const m of migs) {
  const notices = []; const t0 = Date.now()
  try { await db.exec(readFileSync(m, 'utf8').replace(/\r\n/g, '\n'), { onNotice: (n) => notices.push(n.message) }) }
  catch (e) { console.log('FAILED', m.split('/').pop(), e.message); for (const n of notices) console.log('NOTICE', n); process.exit(1) }
  console.log('applied', m.split('/').pop(), Date.now() - t0, 'ms'); for (const n of notices) console.log('NOTICE', n)
}
console.log('combat_bite', (await db.query(`select value from public.world_config where key = 'combat_bite'`)).rows[0].value)
process.exit(0)

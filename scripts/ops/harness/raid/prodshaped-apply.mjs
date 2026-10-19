// prodshaped-apply.mjs <image> <migration...> — redesign-scratch's prod-shaped world (setup.mjs: prod's knobs, stocks, purses, treasuries, loops), then the migrations
import { readFileSync } from 'node:fs'
import { open, setup, log } from './setup.mjs'
const [image, ...migs] = process.argv.slice(2)
const db = await open(image, [])
await setup(db, false)
for (const m of migs) {
  const notices = []; const t0 = Date.now()
  try { await db.exec(readFileSync(m, 'utf8').replace(/\r\n/g, '\n'), { onNotice: (n) => notices.push(n.message) }) } catch (e) { log('FAILED', m, e.message); process.exit(1) }
  log('applied', m.split('/').pop(), Date.now() - t0, 'ms'); for (const n of notices) console.log('NOTICE', n.slice(0, 1500))
}
process.exit(0)

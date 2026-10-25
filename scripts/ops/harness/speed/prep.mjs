// prep.mjs <merchant-world.tar.gz> <out.tar.gz> <migration.sql>... — the paired sim's common ground (2026-10-25, 0219).
// Opens the arrfast merchant world, lays prod's state over it (arrfast/setup.mjs: knobs, stocks, purses,
// treasuries, loops; no kickoff), applies the migrations prod applied after that state (here 0205–0216, in
// order, as prod did), and dumps the result ONCE. Both arms of the pair and players.mjs open this dump, so
// the only difference between the arms is the migration under test. Run from the repo root with
// ARRFAST_SETUP=0 on the arms (sim.mjs then skips the setup this file already did).
import { readFileSync, writeFileSync } from 'node:fs'
import { open, setup, log } from '../arrfast/setup.mjs'
const [image, out, ...migs] = process.argv.slice(2)
const db = await open(image, [])
await setup(db, false)
// The setup posts its treasury adjustments as kind 'SIM', a kind prod never carries; 0214 refuses a flow kind
// it has no word for. They ARE the seed of the cities' purses here, so they wear that word.
// (both tables are append-only by trigger on prod; this is the sim's own seed row being renamed, so the
//  guard is lifted for the one statement and put back)
await db.exec(`alter table public.treasury_flows disable trigger user; alter table public.treasury_daybook disable trigger user;
  update public.treasury_flows set kind = 'SEED' where kind = 'SIM'; update public.treasury_daybook set kind = 'SEED' where kind = 'SIM';
  alter table public.treasury_flows enable trigger user; alter table public.treasury_daybook enable trigger user`)
for (const m of migs) {
  const notices = []; const t0 = Date.now()
  await db.exec(readFileSync(m, 'utf8').replace(/\r\n/g, '\n'), { onNotice: (n) => notices.push(n.message) })
  log('applied', m.split(/[\/]/).pop(), Date.now() - t0, 'ms'); for (const n of notices) if (/self-assert/.test(n)) log('NOTICE', n.slice(0, 400))
}
await db.query('checkpoint')
writeFileSync(out, Buffer.from(await (await db.dumpDataDir('gzip')).arrayBuffer()))
log('wrote', out)
process.exit(0)

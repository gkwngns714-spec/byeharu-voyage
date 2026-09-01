// MEASURE THE DEMAND AMPLITUDE — where does the opening voyage leave proof 05's band?
//
// Run: node scripts/db/measure-demand-amplitude.mjs
//
// This produced the 0.300 that migration 0066 ships. A MEASUREMENT, not a gate. Applies the chain once, then re-derives demand at each amplitude
// through world.demand_for() and runs proof 05's own SQL, so the number is the gate's number.
import { readFile } from 'node:fs/promises'
import { applyChain } from './apply-chain.mjs'
import { installMarketFixture } from './market-fixture.mjs'
const { db } = await applyChain({ quiet: true, log: () => {} })
await installMarketFixture(db)
const sql = await readFile(new URL('./proofs/05_first_voyage_balance.sql', import.meta.url), 'utf8')
for (const amp of [0, 0.15, 0.30, 0.45, 0.60, 0.80]) {
  await db.query(`update public.world_config set value = to_jsonb($1::numeric) where key = 'demand_amplitude'`, [amp])
  await db.query(`update public.port_goods pg set demand = world.demand_for(pg.port_id, pg.good_id)`)
  await db.query('begin')
  let out = 'IN BAND (13.0-20.0)'
  try { await db.exec(sql) } catch (e) {
    const m = /returns ([0-9.]+) per cent/.exec(e.message)
    out = m ? `${m[1]}%  OUT OF BAND` : e.message.slice(0, 120)
  }
  await db.query('rollback')
  console.log(`amp ${String(amp).padEnd(5)} -> ${out}`)
}

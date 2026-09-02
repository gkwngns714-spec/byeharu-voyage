import { applyChain } from './scripts/db/apply-chain.mjs'
const { db } = await applyChain({ quiet: true, log: () => {} })
const { rows } = await db.query(`select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='world' and p.proname='fleets'`)
const s = rows[0].prosrc
const i = s.indexOf("'ships'")
console.log(JSON.stringify(s.slice(i, i + 900)))

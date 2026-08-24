// Throwaway: apply the chain once and dump the LIVE definition of every function 0050 touches.
// Ground truth for the slice hunks. Delete after use.
import { applyChain } from './apply-chain.mjs'
import { writeFileSync } from 'node:fs'

const out = process.argv[2]
const { db } = await applyChain({ quiet: true, log: () => {} })

const rows = await db.query(`
  select n.nspname || '.' || p.proname as fn,
         pg_get_function_identity_arguments(p.oid) as args,
         pg_get_functiondef(p.oid) as def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('cmd','voyage','world','public')
     and (p.prosrc like '%E_ENDURANCE%' or p.prosrc like '%E_HOLD_FULL%'
       or p.prosrc like '%E_INSUFFICIENT_FUNDS%' or p.prosrc like '%E_DAILY_CAP%'
       or p.prosrc like '%E_CREW_%' or p.prosrc like '%E_DRAFT%'
       or p.prosrc like '%E_PRESET_CAP%' or p.prosrc like '%E_NO_STOCK%'
       or p.prosrc like '%sail_refusal%' or p.proname in ('execute_order','issue','preview','queue','fixes','advance'))
   order by 1, 2
`)

let s = ''
for (const r of rows.rows) {
  s += `\n===== ${r.fn}(${r.args}) =====\n${r.def}\n`
}
writeFileSync(out, s.replace(/\r\n/g, '\n'), 'utf8')
console.log(`dumped ${rows.rows.length} function(s) to ${out}`)
for (const r of rows.rows) console.log(`  ${r.fn}(${r.args})`)
process.exit(0)

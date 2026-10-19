// rows.mjs <out.json> — print the rows of a supabase db query json output
import { readFileSync } from 'node:fs'
const t = readFileSync(process.argv[2], 'utf8')
const j = JSON.parse(t.slice(t.indexOf('{'), t.lastIndexOf('}') + 1))
console.log(JSON.stringify(j.rows ?? j).slice(0, Number(process.argv[3] ?? 4000)))

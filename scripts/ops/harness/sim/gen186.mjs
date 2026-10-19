// gen186.mjs <N> <out.sql> — writes the "a merchant's route always pays" migration from the hunk files
// (hunks_plan.json from genplan.py, hunks_cand.json from mkcand.py) and the template tpl186.sql.
import { readFileSync, writeFileSync } from 'node:fs'
const [N, out] = process.argv.slice(2)
const D = 'C:/Users/gkwng/dev/bv-harness/redesign-scratch/'
const hunks = [...JSON.parse(readFileSync(D + 'hunks_plan.json', 'utf8')), ...JSON.parse(readFileSync(D + 'hunks_cand.json', 'utf8'))]
const n = {}
const vals = hunks.map((h) => {
  n[h.fn] = (n[h.fn] ?? 0) + 1
  for (const t of [h.old, h.new]) if (t.includes('$h$')) throw new Error('a hunk holds $h$')
  return `('${h.fn}', ${n[h.fn]},\n$h$${h.old}$h$,\n$h$${h.new}$h$)`
}).join(',\n')
let sql = readFileSync(D + 'tpl186.sql', 'utf8').replace(/\r\n/g, '\n')
sql = sql.replace('--@HUNKS@', () => vals + ';').replaceAll('NNNN', N)
if (sql.includes('\r')) throw new Error('CR in output')
writeFileSync(out, sql)
console.log(hunks.length, 'hunks', Object.entries(n).map(([k, v]) => `${k} ${v}`).join('; '))

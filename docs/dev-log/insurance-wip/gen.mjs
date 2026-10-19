// _gen.mjs [margin] — assemble the 0211 migration from _mig.src.sql + _probes.src.sql, filling
// @@L:fn:a-b@@ with lines a..b of that function's dumped live body (block line 1 = the ===== header).
import { readFileSync, writeFileSync } from 'node:fs'
const margin = process.argv[2] ?? '0.10'
const all = readFileSync('node_modules/.cache/ins-dump/all.sql', 'utf8').split('\n')
function block(fn) {
  const i = all.findIndex((l) => l.startsWith(`===== ${fn}(`))
  if (i < 0) throw new Error('no body for ' + fn)
  let j = i + 1
  while (j < all.length && !all[j].startsWith('=====')) j++
  return all.slice(i, j)
}
let s = readFileSync('_mig.src.sql', 'utf8').replace(/\r\n/g, '\n')
s = s.replace(/@@L:([a-z_.]+):(\d+)-(\d+)@@/g, (_, fn, a, b) => block(fn).slice(Number(a) - 1, Number(b)).join('\n'))
s = s.replace('@@MARGIN@@', margin)
const probes = readFileSync('_probes.src.sql', 'utf8').replace(/\r\n/g, '\n')
s = s.replace('@@PROBES@@', () => probes)
const out = 'supabase/migrations/20260818000211_a_cargo_can_be_insured.sql'
writeFileSync(out, s.endsWith('\n') ? s : s + '\n')
console.log('wrote', out, s.length)

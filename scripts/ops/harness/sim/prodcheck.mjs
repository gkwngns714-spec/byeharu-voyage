// prodcheck.mjs <migration> <out.sql> — a READ-ONLY prod query: does each hunk's OLD text occur exactly once in the live body?
import { readFileSync, writeFileSync } from 'node:fs'
const s = readFileSync(process.argv[2], 'utf8').replace(/\r\n/g, '\n')
const a = s.indexOf('insert into hunks_' + process.argv[4] + ' values'), b = s.indexOf('\ndo $$', a)
const block = s.slice(a, b)
const re = /\('([^']+)', (\d+),\n\$h\$([\s\S]*?)\$h\$,\n\$h\$([\s\S]*?)\$h\$\)/g
let m, rows = []
while ((m = re.exec(block))) rows.push([m[1], +m[2], m[3]])
const q = (t) => '$q' + rows.length + '$' + t + '$q' + rows.length + '$'
const vals = rows.map(([fn, n, old], i) => `('${fn}', ${n}, $o${i}$${old}$o${i}$)`).join(',\n')
writeFileSync(process.argv[3], `begin transaction read only;
select json_agg(json_build_array(fn, n, (length(d) - length(replace(d, old, ''))) / length(old)) order by fn, n)
  from (select v.fn, v.n, v.old, replace(pg_get_functiondef(v.fn::regprocedure), E'\r', '') d from (values ${vals}) v(fn, n, old)) z;
rollback;
`)
console.log(rows.length, 'hunks')

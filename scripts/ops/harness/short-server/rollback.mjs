// 0433 FORWARD ROLLBACK, the bodies (a draft for the owner; see rollback-0433.sql). Reads the hunks from the migration file itself and prints a DO
// block that reverses each one: the new text found once in the live body and put back to the old, function by function, last hunk first.
//   node scripts/ops/harness/short-server/rollback.mjs > rollback-0433-bodies.sql
import { readFileSync } from 'node:fs'

const mig = readFileSync(new URL('../../../../supabase/migrations/20260818000433_the_server_says_have_and_need.sql', import.meta.url), 'utf8').replaceAll('\r', '')
const re = /jsonb_build_array\('([^']+\([^)]*\))',\n\$h\$([\s\S]*?)\$h\$,\n\$h\$([\s\S]*?)\$h\$\)/g
const hunks = [...mig.matchAll(re)].map((m) => ({ fn: m[1], old: m[2], neu: m[3] }))
const q = (s) => `$h$${s}$h$`
let out = "do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;\n"
out += 'do $r$\ndeclare\n  v_def text;\nbegin\n'
for (const fn of [...new Set(hunks.map((h) => h.fn))]) {
  out += `  v_def := replace(pg_get_functiondef('${fn}'::regprocedure), E'\\r', '');\n`
  for (const h of hunks.filter((x) => x.fn === fn).reverse()) {
    out += `  if (length(v_def) - length(replace(v_def, ${q(h.neu)}, ''))) / length(${q(h.neu)}) <> 1 then\n`
    out += `    raise exception 'rollback-0433 refuses: a hunk of ${fn} is not in the live body once';\n  end if;\n`
    out += `  v_def := replace(v_def, ${q(h.neu)}, ${q(h.old)});\n`
  }
  out += '  execute v_def;\n'
}
out += `  raise notice 'rollback-0433 (bodies) ok: ${hunks.length} hunks reversed';\nend $r$;\n`
process.stdout.write(out)
console.error(`${hunks.length} hunks`)

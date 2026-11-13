// ═══════════════════════════════════════════════════════════════════════════════
// proof-0353.mjs — A FIGHT KEEPS ITS LOG, A FLEET HAS A STANDING ORDER (migration 0353): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/combat-log/proof-0353.mjs [--no-mutations] [--only=<text>] [--with=28,30,31,34,46] [--cost] [--orders] [--lit-purses]
//
// Restores the cached world at the head before 0353 (never from zero; nothing is written to the cache), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 56 on the world with no file: it must fail (its hunks are not in the live bodies);
//   POSITIVE CONTROL  - the real file, then proof 56: every marker it declares. --lit-purses applies the file a second time on a world whose city purses are lit
//                       (as prod's may be), so the probe of the doors takes the branch with a payee;
//   --with            - the real file followed by each named existing proof (the fight, the raid, the battles, the pirates), one transaction each;
//   --cost            - cost.sql after the file: a PIRATES day through the real voyage.settle, the OLD bodies against the NEW, interleaved, for a merchant and for a company
//                       (with a log; under Flee; under Pay), and a departure. The old bodies are put back from the migration's own hunks (gen-checks.mjs), in a subtransaction;
//   --orders          - orders-scene.sql after the file: what Fight, Flee and Pay each do to a weak trader and to a gunned fleet over seeded raids (the choice must be real);
//   MUTATION CONTROLS - deliberate breakages (mutations-0353.mjs), each required to FAIL the file's own self-assert, or proof 56 right after it, for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
import { hunks } from './gen-checks.mjs'

const NAME = '20260818000353_a_fight_keeps_its_log.sql'
const PROOF = 'scripts/db/proofs/56_combat_log.sql'
const HERE = 'scripts/ops/harness/combat-log'
const failures = []
const say = (...a) => console.log(...a)
const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const has = (k) => process.argv.includes(`--${k}`)

const files = []
for (const name of await migrationFiles()) {
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const proof = (await readFile(PROOF, 'utf8')).replaceAll('\r', '')
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied`)
if (arg('with')) {
  await (await import('../../../db/proof-courses.mjs')).installProofCourses(db)
  await (await import('../../../db/market-fixture.mjs')).installMarketFixture(db, { log: () => {} })
}

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from.slice(0, 120)}`)
  return sql.replace(from, () => to)
}

async function attempt(...sqls) {
  const notes = []
  const onNotice = (n) => notes.push(n.message)
  await db.exec('begin')
  let err = null
  try {
    for (const sql of sqls) if (sql) await db.exec(sql, { onNotice })
  } catch (e) {
    err = e.message
  }
  try { await db.exec('rollback') } catch { /* already aborted */ }
  return { err, notes }
}

// the OLD bodies, for a scene that asks for them: the migration's own hunks, each NEW text once in the live body, reversed. Called inside a subtransaction the scene rolls back.
const TO_OLD = `
create temp table hunks_scene (fn text, n int, old text, new text) on commit drop;
insert into hunks_scene (fn, n, old, new) values
${hunks.map((h) => `  ('${h.fn}', ${h.n}, $h$${h.old}$h$, $h$${h.new}$h$)`).join(',\n')};
create function pg_temp.to_old_scene() returns void language plpgsql as $b$
declare
  f record; h record; v_def text;
begin
  for f in select distinct x.fn from hunks_scene x order by x.fn loop
    v_def := replace(pg_get_functiondef(f.fn::regprocedure), E'\\r', '');
    for h in select * from hunks_scene x where x.fn = f.fn order by x.n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception 'scene: hunk % of % is not in the live body exactly once', h.n, f.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    execute v_def;
  end loop;
end
$b$;
`

const MUTATIONS = (await import('./mutations-0353.mjs')).mutations
const only = arg('only')

if (!only) {
  // RED FIRST
  const red = await attempt(proof)
  say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 160) : 'IT PASSED'}`)
  if (!red.err) failures.push('proof 56 passed with no file')

  // POSITIVE CONTROL
  const t2 = Date.now()
  const whole = await attempt(file, proof)
  say(`whole: ${Date.now() - t2} ms`)
  if (whole.err) failures.push(`proof 56 failed: ${whole.err}`)
  for (const n of whole.notes.filter((x) => /^(PASS:)/.test(x) || /self-assert ok/.test(x))) say('  ', n.slice(0, 1600))
  if (whole.err) say('   ERROR', whole.err)
  const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
  const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
  if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)

  if (has('lit-purses')) {
    const lit = await attempt(
      `update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
       insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;`,
      file,
    )
    const note = lit.notes.find((x) => /self-assert ok/.test(x)) ?? ''
    say(`LIT PURSES: ${lit.err ? 'RED ' + lit.err : 'green: ' + (note.match(/The doors \(probe, rolled back\): ([^.]*)\./)?.[1] ?? '?')}`)
    if (lit.err || !/a payee: a ransom of \d+ moved/.test(note)) failures.push(`the file on lit purses: ${lit.err ?? 'the probe found no payee'}`)
  }
}

for (const [flag, scene] of [['cost', 'cost.sql'], ['orders', 'orders-scene.sql']]) {
  if (!has(flag)) continue
  const sql = (await readFile(path.join(HERE, scene), 'utf8')).replaceAll('\r', '')
  if (!sql.includes("if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'")) throw new Error(`${scene} has no guard`)
  const t = Date.now()
  const r = await attempt(file, TO_OLD, sql)
  if (r.err) failures.push(`${scene}: ${r.err}`)
  for (const n of r.notes.filter((x) => /^(COST|ORDERS|LOG): /.test(x))) say(`  ${n}`)
  say(`${scene}: ${r.err ? 'ERROR ' + r.err : 'ok'}, ${Date.now() - t} ms`)
}

// THE PROOFS THAT SHARE ITS CODE
if (arg('with')) {
  const all = await readdir('scripts/db/proofs')
  for (const n of arg('with').split(',')) {
    const f = all.find((x) => x.startsWith(`${n}_`))
    const sql = (await readFile(path.join('scripts/db/proofs', f), 'utf8')).replaceAll('\r', '')
    const want = [...sql.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
    const t = Date.now()
    const r = await attempt(file, sql)
    const missing = want.filter((m) => !r.notes.some((x) => x.includes(`PASS: ${m}`)))
    say(`WITH ${f}: ${r.err ? 'RED ' + r.err.slice(0, 500) : missing.length ? 'MISSING ' + missing.join(', ') : `green, ${want.length} of ${want.length} markers`}, ${Date.now() - t} ms`)
    if (r.err || missing.length) failures.push(`proof ${n}: ${(r.err ?? 'markers missing').slice(0, 300)}`)
  }
}

if (!has('no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, from, to, expected] of MUTATIONS) {
    if (only && !label.includes(only)) continue
    // a breakage inside a hunk is made in proof 56's copy of that hunk too, so the proof judges what the body DOES and not that its text moved
    const r = await attempt(swap(file, from, to), proof.includes(from) ? proof.replace(from, () => to) : proof)
    const hit = r.err && expected.test(r.err)
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${(r.err ?? 'it passed').slice(0, 300)}`}`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

// THE SLOW MACHINE (--bounded). Prod ran the first 0353 about six times slower than this PC and the file refused itself at 49 s. The self-assert's pure fights are now cut by the clock
// (7 s, 4 s, 4 s, 1 s). Here the four bounds are cut to a sixth, which on this PC is what prod's bounds are on prod: the real file must still pass with every least met, and a
// mutant ENGINE must still go red inside that subset. And each mutant engine is put under the REAL file (by replacing the live body) and must go red in proof 56's whole matrix.
if (has('bounded')) {
  const sixth = (s) =>
    swap(swap(swap(swap(s, `c_guard_parity constant interval := interval '7 seconds'`, `c_guard_parity constant interval := interval '1170 milliseconds'`),
      `c_guard_orders constant interval := interval '4 seconds'`, `c_guard_orders constant interval := interval '670 milliseconds'`),
      `c_guard_skin   constant interval := interval '4 seconds'`, `c_guard_skin   constant interval := interval '670 milliseconds'`),
      `c_guard_words  constant interval := interval '1 second'`, `c_guard_words  constant interval := interval '170 milliseconds'`)
  say('\nTHE SLOW MACHINE: the four clock bounds cut to a sixth')
  for (let i = 0; i < 3; i++) {
    const r = await attempt(sixth(file))
    if (r.err) failures.push(`bounded: the real file failed: ${r.err.slice(0, 300)}`)
    const ok = r.notes.find((x) => /self-assert ok/.test(x)) ?? ''
    say(`  ${r.err ? 'RED ' + r.err.slice(0, 300) : 'green'}: ${(r.notes.find((x) => /0353 timings/.test(x)) ?? '').slice(0, 260)}`)
    say(`    ${(ok.match(/ENGINE PARITY, bounded by the clock: (\d+ pairs on \d+)/)?.[1] ?? '?')} fights; skin ${ok.match(/SKIN PARITY: (\d+) raids/)?.[1] ?? '?'} raids; orders on ${ok.match(/ORDERS on (\d+) fights/)?.[1] ?? '?'} fights`)
  }
  const engine = hunks.filter((h) => h.fn === 'public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)')
  for (const [label, from, to, expected] of MUTATIONS) {
    if (!engine.some((h) => h.new.includes(from))) continue
    const r = await attempt(swap(sixth(file), from, to))
    const hit = r.err && expected.test(r.err)
    say(`  ${hit ? 'red inside the bounded subset' : 'WRONG'}: ${label}${hit ? '' : ` -- ${(r.err ?? 'it passed').slice(0, 300)}`}`)
    if (!hit) failures.push(`bounded: mutant engine not caught: ${label}`)
    if (/names a table/.test(String(expected))) continue   // a guard of the text, not of what a fight answers: proof 56 fights, it does not read the body
    const q = (t) => `'${t.replaceAll("'", "''")}'`
    const under = await attempt(
      file,
      `do $$ begin execute replace(replace(pg_get_functiondef('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)'::regprocedure), chr(13), ''), ${q(from)}, ${q(to)}); end $$;`,
      proof.includes(from) ? proof.replace(from, () => to) : proof,
    )
    const caught = under.err && /PROOF 56 FAIL/.test(under.err)
    say(`  ${caught ? 'red in proof 56' : 'WRONG'}: ${label} under the real file${caught ? ': ' + under.err.slice(0, 110) : ` -- ${(under.err ?? 'it passed').slice(0, 300)}`}`)
    if (!caught) failures.push(`proof 56 did not catch the mutant engine: ${label}`)
  }
}

await db.close()
const ran =has('no-mutations') ? 'mutations NOT run' : `${MUTATIONS.length} mutations red`
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${ran}, red first, the real file and proof 56 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)

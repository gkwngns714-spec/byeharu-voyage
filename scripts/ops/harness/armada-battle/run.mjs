// run.mjs — scenes on the LOCAL cached world (PGlite) for 0395 (an armada fights as one). LOCAL ONLY; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/armada-battle/run.mjs [--apply] [--dump=<dir>] [--fns=<a;b>] [--proofs=69,60] [--after=<dir>] [--secrets=<n>] [--secret=<word>] [--lit] [--notes] <scene.sql> [...]
//
// Restores the cached world at the head before 0395 (never from zero; the cache is only read), then, in ONE transaction that is
// ROLLED BACK: applies 0395 when --apply is given, writes the live bodies of the functions 0395 cuts (and any named by --fns) to
// --dump (LF), and runs each scene at a savepoint, printing its notices and its last rows. A PROD CHECK file can be run here too,
// to see what it will answer. --proofs runs the named proofs (each in its own rolled-back transaction, after 0395 when --apply is
// given), with the proof courses and the market fixture installed as scripts/db/proof.mjs installs them.
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { createHash } from 'node:crypto'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000395'
const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const say = (...a) => console.log(...a)
// a world_secret of a word: 128 hex characters, as 0031 makes them (the table refuses a short one)
const secretOf = (word) => createHash('sha512').update(word).digest('hex')
const files = []
let mine = null
for (const name of await migrationFiles()) {
  if (name.startsWith(NAME)) mine = name
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: process.env.AB_SNAPSHOT === '1' })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored`)
const onNotice = (n) => say('  ', n.message)
const apply = process.argv.includes('--apply')
const file = apply ? (await readFile(path.join(MIGRATIONS_DIR, mine), 'utf8')).replaceAll('\r', '') : null
let failed = false

// the bodies 0395 cuts, read from the migration's own hunks (gen-checks.mjs)
import { CUT } from './gen-checks.mjs'

if (arg('proofs')) {
  await (await import('../../../db/proof-courses.mjs')).installProofCourses(db)
  await (await import('../../../db/market-fixture.mjs')).installMarketFixture(db, { log: () => {} })
  if (file) {
    const t = Date.now()
    await db.exec(file, { onNotice })
    say(`applied ${mine} in ${Date.now() - t} ms (committed in this throwaway world)`)
  }
  // --after=<dir>: the migrations of a tree that is ahead of this one (a batch branch), applied after 0395 in name order, so a proof can be run beneath them
  if (arg('after')) {
    for (const n of (await readdir(arg('after'))).filter((x) => x.endsWith('.sql')).sort()) {
      const t = Date.now()
      await db.exec((await readFile(path.join(arg('after'), n), 'utf8')).replaceAll('\r', ''), { onNotice: () => {} })
      say(`applied after it: ${n} in ${Date.now() - t} ms`)
    }
  }
  const all = await readdir('scripts/db/proofs')
  for (const n of arg('proofs').split(',')) {
    const f = all.find((x) => x.startsWith(`${n}_`)) ?? all.find((x) => x.startsWith(n))   // two proofs may share a number: name more of the file
    const sql = (await readFile(path.join('scripts/db/proofs', f), 'utf8')).replaceAll('\r', '')
    const want = [...sql.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
    // --secrets=N: the proof N times, the first under the world's own world_secret and each other under one of its own (every roll of a fight is keyed by it: 0031),
    // written inside the proof's own rolled-back transaction. A proof must hold under ANY dice (docs/dev-log/2026-11-12-live-rounds.md, its last section).
    for (let k = 0; k < Number(arg('secrets') ?? 1); k++) {
      const notes = []
      const t = Date.now()
      let err = null
      await db.exec('begin')
      if (k > 0) await db.exec(`update public.world_config set value = to_jsonb('${secretOf(`armada-battle-${k}`)}'::text) where key = 'world_secret'`)
      try { await db.exec(sql, { onNotice: (x) => notes.push(x.message) }) } catch (e) { err = e.message + (e.where ? ' | where: ' + String(e.where).slice(0, 600) : '') + (e.internalQuery ? ' | query: ' + String(e.internalQuery).slice(0, 300) : '') }
      try { await db.exec('rollback') } catch { /* aborted */ }
      const missing = want.filter((m) => !notes.some((x) => x.includes(`PASS: ${m}`)))
      if (err || missing.length) failed = true
      say(`PROOF ${f}${k > 0 ? ` (secret ${k})` : ''}: ${err ? 'RED ' + err.slice(0, 2500) : missing.length ? 'MISSING ' + missing.join(', ') : `green, ${want.length} of ${want.length} markers`}, ${Date.now() - t} ms`)
      if (process.argv.includes('--notes')) for (const x of notes) say('   ', x.slice(0, 1200))
    }
  }
  await db.close()
  process.exit(failed ? 1 : 0)
}

await db.exec('begin')
// --secret=<word>: the file applied under another world_secret (the self-assert's probe fights real rounds: it must hold under any dice)
if (arg('secret')) await db.exec(`update public.world_config set value = to_jsonb('${secretOf(arg('secret'))}'::text), updated_at = updated_at where key = 'world_secret'`)
// --lit: the file applied on a world where the owner has lit attacks (0395 may deploy after the lighting: it takes the switch as it finds it)
if (process.argv.includes('--lit')) await db.exec("update public.world_config set value = 'true'::jsonb where key = 'attack_enabled'")
if (file) {
  const t = Date.now()
  try {
    await db.exec(file, { onNotice })
    say(`applied ${mine} in ${Date.now() - t} ms`)
  } catch (e) {
    say(`APPLY ERROR after ${Date.now() - t} ms: ${e.message}
  where: ${e.where ?? ""}
  detail: ${e.detail ?? ""} pos ${e.position ?? ""} iq ${(e.internalQuery ?? "").slice(0, 600)}`)
    await db.close()
    process.exit(1)
  }
}
if (arg('dump')) {
  await mkdir(arg('dump'), { recursive: true })
  const names = (arg('fns') ?? '').split(';').filter(Boolean)
  for (const f of [...CUT, ...names]) {
    const r = await db.query(`select replace(pg_get_functiondef(to_regprocedure($1)), E'\r', '') as d`, [f])
    if (!r.rows[0].d) { say(`no such function: ${f}`); continue }
    await writeFile(path.join(arg('dump'), f.replace(/\(.*/, '') + '.sql'), r.rows[0].d)
  }
  say(`dumped to ${arg('dump')}`)
}
for (const scene of process.argv.slice(2).filter((a) => !a.startsWith('--'))) {
  const sql = (await readFile(scene, 'utf8'))
    .replaceAll('\r', '')
    .replace(/^begin transaction read only;$/m, '')
    .replace(/^commit;$/m, '')
    .replace('(select max(version) from supabase_migrations.schema_migrations)', "'(not on PGlite)'::text")
  await db.exec('savepoint scene')
  const t0 = Date.now()
  try {
    const res = await db.exec(sql, { onNotice })
    const last = res.findLast((r) => r.rows?.length)
    for (const r of last?.rows ?? []) say('  ', JSON.stringify(r))
    say(`${scene}: ok, ${Date.now() - t0} ms`)
  } catch (e) {
    failed = true
    say(`${scene}: ERROR ${e.message}`)
  }
  await db.exec('rollback to savepoint scene')
}
await db.exec('rollback')
await db.close()
process.exit(failed ? 1 : 0)

// run.mjs - LOCAL ONLY (PGlite, the cached world; never from zero; nothing is written to the cache; it opens no network connection).
// The one local runner of the attack files (0374 loot follows the risk taken, 0375 a company may attack): proofs, scenes and prod checks on the chain as it stands.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/attacks/run.mjs [--before=<migration name prefix>] [--lit=<keys,comma>] [--proofs=74,75,34] [--dice=10]
//                                                                         [--cron] [--notes] [file.sql ...]
//
//   --before=20260818000375   the chain stops short of that file (the world before a migration).
//   --lit=regard_enabled,npc_ship_level_enabled,convoy_armed_enabled
//                             those switches are set true FIRST, in a transaction of their own that is kept for the run (and thrown away with the process): the world as production
//                             will be when 0369 to 0373 have been lit. With --apply the named migration is then applied on that world.
//   --apply=<file>            apply one more migration after the switches (0375 on a world lit as prod will be).
//   --proofs=74,75            run those proofs of scripts/db/proofs, each in its own rolled-back transaction, holding every `-- @pass` marker it declares.
//   --dice=10                 run the proofs again under 10 OTHER world secrets (0031: every built world has its own dice; a proof may assume no outcome of a roll).
//   file.sql ...              LOCAL SCENES and PROD CHECKS, in the order given, IN ONE TRANSACTION that is rolled back at the end: so `scene-battles.sql after-battles.sql
//                             after-rounds.sql after-loot.sql after-held.sql` reads the battles the scene fought. A prod check's wrapper is taken off (the runner holds the
//                             transaction) and supabase_migrations, which PGlite has not, reads '(not on PGlite)'.
//   --cron                    a stand-in for pg_cron's two tables, made in that transaction, so after-job.sql can be parsed and answered here (it is a PROD read).
import { readFile, readdir } from 'node:fs/promises'
import { randomBytes } from 'node:crypto'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, REPO_ROOT, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3) ?? null
const has = (k) => process.argv.includes(`--${k}`)
const say = (...a) => console.log(...a)
const before = arg('before')
const files = []
for (const name of await migrationFiles()) {
  if (before && name >= before) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const t0 = Date.now()
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: process.env.BYEHARU_PREFIX_CACHE === 'required', snapshots: false })
const db = out.db
if ((await db.query(`select inet_server_addr() is not null as real`)).rows[0].real) throw new Error('local PGlite world only')
say(`world: head ${files.at(-1).name.slice(0, 18)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).map((r) => r.name.slice(8, 18)).join(' ')} applied, ${((Date.now() - t0) / 1000).toFixed(1)} s`)
const onNotice = (n) => { if (has('notes') || /self-assert ok|refuses|FAIL/.test(n.message)) say('  NOTICE:', n.message.slice(0, 1500)) }
let failed = false

if (arg('lit')) {
  const keys = arg('lit').split(',').filter(Boolean)
  const r = await db.query(`update public.world_config set value = 'true'::jsonb where key = any($1::text[]) returning key`, [keys])
  if (r.rows.length !== keys.length) throw new Error(`--lit: ${keys.length} keys named, ${r.rows.length} found`)
  await db.exec(`select public.crown_hull_level_fix()`)
  say(`lit: ${keys.join(', ')}`)
}
if (arg('apply')) {
  const name = (await readdir(MIGRATIONS_DIR)).find((f) => f.includes(arg('apply'))) ?? arg('apply')
  const sql = (await readFile(path.isAbsolute(name) ? name : path.join(MIGRATIONS_DIR, name), 'utf8')).replaceAll('\r', '')
  const t = Date.now()
  try {
    await db.exec(sql, { onNotice })
    say(`applied ${path.basename(name)} in ${Date.now() - t} ms`)
  } catch (e) {
    say(`APPLY RED ${path.basename(name)} after ${Date.now() - t} ms: ${e.message}`)
    if (has('expect-red')) { await db.close(); process.exit(0) }
    await db.close()
    process.exit(1)
  }
  if (has('expect-red')) { say('EXPECTED A REFUSAL AND GOT NONE'); await db.close(); process.exit(1) }
}

if (arg('proofs')) {
  const dir = path.join(REPO_ROOT, 'scripts', 'db', 'proofs')
  const all = await readdir(dir)
  const dice = Number(arg('dice') ?? 0)
  const secrets = [null, ...Array.from({ length: dice }, (_, i) => `dice-${i + 1}-${randomBytes(32).toString('hex')}`)]   // 0031: a secret is at least 64 characters
  for (const secret of secrets) {
    const line = []
    for (const n of arg('proofs').split(',').filter(Boolean)) {
      const f = all.find((x) => x.startsWith(`${n}_`))
      if (!f) { say(`no proof ${n}`); failed = true; continue }
      const sql = (await readFile(path.join(dir, f), 'utf8')).replaceAll('\r', '')
      const want = [...sql.matchAll(/^\s*--\s*@pass\s+([A-Z][A-Z0-9_]*)\b/gm)].map((m) => m[1])
      const notes = []
      const t = Date.now()
      let err = null
      await db.exec('begin')
      try {
        if (secret) await db.query(`update public.world_config set value = to_jsonb($1::text) where key = 'world_secret'`, [secret])
        await db.exec(sql, { onNotice: (x) => notes.push(x.message) })
      } catch (e) { err = e.message }
      try { await db.exec('rollback') } catch { /* aborted */ }
      const missing = want.filter((m) => !notes.some((x) => x.includes(`PASS: ${m}`)))
      if (err || missing.length || want.length === 0) failed = true
      const verdict = err ? `RED ${err.slice(0, 900)}` : missing.length ? `MISSING ${missing.join(', ')}` : `green ${want.length}/${want.length}`
      line.push(`${n}: ${verdict} (${((Date.now() - t) / 1000).toFixed(1)} s)`)
      if (has('notes')) for (const x of notes) say('   ', x.slice(0, 1400))
      // how the proof's fights went under this secret, where it says (the endings differ from world to world, which is the point)
      const ends = notes.flatMap((x) => [...x.matchAll(/\b(PLUNDERED|RANSOM|DRIVEN_OFF|EVADED|BROKEN_OFF)\b/g)].map((m) => m[1]))
      if (ends.length) line.push(`[${[...new Set(ends)].join(',')}]`)
    }
    say(`${secret ? secret.slice(0, 22) + '…' : 'this world'} | ${line.join(' | ')}`)
  }
}

const scenes = process.argv.slice(2).filter((a) => !a.startsWith('--'))
if (scenes.length) {
  await db.exec('begin')
  if (has('cron')) {
    await db.exec(`create schema if not exists cron;
      create table cron.job (jobid bigint primary key, jobname text, schedule text, command text, active boolean);
      create table cron.job_run_details (jobid bigint, status text, start_time timestamptz, end_time timestamptz, return_message text);
      insert into cron.job values (1, 'byeharu-voyage:battles', '* * * * *', 'select public.tick_battles()', true);
      insert into cron.job_run_details select 1, 'succeeded', now() - make_interval(mins => g), now() - make_interval(mins => g) + interval '40 milliseconds', '1 row' from generate_series(0, 29) g;`)
  }
  for (const scene of scenes) {
    const sql = (await readFile(scene, 'utf8'))
      .replaceAll('\r', '')
      .replace(/^begin transaction read only;$/m, '')
      .replace(/^commit;$/m, '')
      .replace('(select max(version) from supabase_migrations.schema_migrations)', "'(not on PGlite)'::text")
    await db.exec('savepoint scene')
    const t = Date.now()
    try {
      const res = await db.exec(sql, { onNotice: (n) => say('  NOTICE:', n.message.slice(0, 2500)) })
      const last = res.findLast((r) => r.rows?.length)
      for (const r of last?.rows ?? []) say('  ', JSON.stringify(r))
      say(`${path.basename(scene)}: ok, ${Date.now() - t} ms`)
      await db.exec('release savepoint scene')
    } catch (e) {
      failed = true
      say(`${path.basename(scene)}: ERROR ${e.message}`)
      await db.exec('rollback to savepoint scene')
    }
  }
  await db.exec('rollback')
}
await db.close()
process.exit(failed ? 1 : 0)

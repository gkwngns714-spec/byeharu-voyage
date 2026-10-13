// ═══════════════════════════════════════════════════════════════════════════════════════════════
// apply-chain.mjs — apply the WHOLE migration chain to a real PostgreSQL, on this machine
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// WHAT THIS PROVES
//   That every file in supabase/migrations/ applies, in filename order, to a real PostgreSQL 18 —
//   and that every in-migration `do $$ ... $$` self-assert passes against real data. A self-assert
//   is only a promise until something runs it. This runs it, in about ten seconds, with no Docker.
//
// HOW
//   @electric-sql/pglite is PostgreSQL compiled to WebAssembly. It is not a parser and not a
//   simulator: it is the real backend, with the real planner, the real plpgsql, real constraints,
//   real triggers and real GRANTs. DEV_LOG D6 records the measurement that established this on
//   this machine (PostgreSQL 18.3 / PGlite 0.5.5, running a plpgsql haversine with RAISE).
//
// THE SUPABASE-SHAPED PREAMBLE  (scripts/db/supabase-preamble.sql)
//   A bare PGlite starts EMPTY: no `anon`, no `authenticated`, and no ALTER DEFAULT PRIVILEGES
//   entries whatsoever. Migration 0001's lockdown therefore had nothing to revoke here and its
//   "no default ACL grants a client a write" assert had nothing to find — it passed VACUOUSLY,
//   locally, while failing on CI's disposable Supabase with 16 entries to find (2026-08-18,
//   DEV_LOG D8). Every grant / default-ACL assert in the chain was in that same position.
//
//   So this file applies supabase-preamble.sql BEFORE migration 0001: the Supabase roles, and the
//   ALTER DEFAULT PRIVILEGES a real project ships, installed under a grantor that is NOT the role
//   applying the chain. The local run now starts from the same hostile state CI does. The fixture
//   asserts its own effect (exactly 16 assert-visible entries) and raises if it stops modelling it.
//
//   It is a FIXTURE, never a migration. It lives in scripts/, so the Supabase CLI — which only
//   ever reads supabase/migrations/ — cannot deploy it.
//
// WHAT IT STILL DOES NOT PROVE
//   * It is not Supabase. The preamble models the roles and the default ACLs; it does not model
//     GoTrue, PostgREST, Realtime, Storage, `pg_cron`, the real `auth` schema, the hosted
//     extension set, or the fact that on Supabase the migration role is NOT a superuser. CI's
//     disposable-Supabase job is still the only place those are tested. Neither replaces the other.
//   * PGlite runs single-user as a superuser. RLS is BYPASSED for the session owner, so a proof
//     that wants RLS must `set local role anon` first — see scripts/db/proofs/.
//   * There is no pg_cron. Tick functions are proven by calling them, not by being scheduled.
//
// USAGE
//   node scripts/db/apply-chain.mjs            # apply, print every RAISE NOTICE
//   node scripts/db/apply-chain.mjs --quiet    # apply, print only the per-file receipt
//   import { applyChain } from './apply-chain.mjs'   # returns the live db for a proof run
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readdir, readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const HERE = path.dirname(fileURLToPath(import.meta.url))
export const REPO_ROOT = path.resolve(HERE, '..', '..')
export const MIGRATIONS_DIR = path.join(REPO_ROOT, 'supabase', 'migrations')

/**
 * The Supabase-shaped hostile starting state, applied before migration 0001.
 * A TEST FIXTURE. It is deliberately NOT in supabase/migrations/, so it can never be deployed.
 */
export const PREAMBLE_PATH = path.join(REPO_ROOT, 'scripts', 'db', 'supabase-preamble.sql')

/** Filenames the chain consists of, in the order PostgreSQL will see them. */
export async function migrationFiles() {
  const entries = await readdir(MIGRATIONS_DIR)
  return entries.filter((f) => f.endsWith('.sql')).sort()
}

/**
 * Apply scripts/db/supabase-preamble.sql to `db` and require its own receipt. ONE authority for
 * "the hostile Supabase-shaped starting state": applyChain() below and the prefix cache's
 * `preamble` variant (scripts/db/prefix-cache.mjs, which proof.mjs boots through) both call this,
 * so the proofs can never start from a different base than `npm run db:apply` does.
 *
 * @returns {Promise<string[]>} the preamble's notices
 */
export async function applyPreamble(db) {
  const preambleRaw = await readFile(PREAMBLE_PATH, 'utf8')
  if (preambleRaw.includes('\r')) {
    throw new Error('CRLF in supabase-preamble.sql: it must be LF-only, like the migrations.')
  }
  const preambleNotices = []
  try {
    await db.exec(preambleRaw, { onNotice: (n) => preambleNotices.push(n.message ?? String(n)) })
  } catch (err) {
    throw new Error(
      `SUPABASE PREAMBLE FAILED (${PREAMBLE_PATH}): ${err.message}\n` +
        '  The local gate refuses to run without it — a run that starts from an empty database ' +
        'proves the grant lockdown against nothing.',
    )
  }
  if (!preambleNotices.some((l) => /supabase-preamble ok:/i.test(l))) {
    throw new Error(
      'SUPABASE PREAMBLE printed no "supabase-preamble ok:" receipt. It is supposed to assert its ' +
        'own effect; without that receipt it may have stopped modelling the hostile state, which ' +
        'is exactly the blindness it exists to remove.',
    )
  }
  return preambleNotices
}

/**
 * Boot a fresh in-memory PostgreSQL and apply every migration in order.
 *
 * Fails loudly: the thrown Error names the offending FILE and carries the raw PostgreSQL error
 * fields (code, detail, hint, where), because "migration 7 failed" without the SQLSTATE and the
 * plpgsql context line is a bug report you cannot act on.
 *
 * @returns {Promise<{db: import('@electric-sql/pglite').PGlite, applied: string[], notices: Map<string,string[]>}>}
 */
export async function applyChain({ quiet = false, log = console.log, stopBefore = null } = {}) {
  const { PGlite } = await import('@electric-sql/pglite')
  // A BARE `new PGlite()` KEEPS THE WHOLE WORLD IN WASM MEMORY, and this chain has outgrown that on
  // some machines: the process dies with NO error, no SQLSTATE and no partial receipt, at a
  // different migration each run (measured 2026-10-11: 0012, then 0052, then 0065, then 0089 once a
  // bigger V8 heap let it run faster before the same ceiling) on a host with 47 GB free. A gate that
  // dies without a message is worse than a slow one, so BV_CHAIN_DATA_DIR puts the data on disk
  // instead, where the ceiling is the disk's.
  //
  // IN-MEMORY IS STILL THE DEFAULT, deliberately: CI applies the chain exactly as it always has, and
  // nothing about the proof changes with where the bytes live. This is an escape hatch for a big
  // machine running the chain by hand, named in one place rather than copied into a wrapper script.
  const dataDir = process.env.BV_CHAIN_DATA_DIR || undefined
  const db = await new PGlite(dataDir)
  if (dataDir && !quiet) log(`data:   ${dataDir} (BV_CHAIN_DATA_DIR; in-memory is the default)`)

  // `stopBefore` (a filename prefix, e.g. '20260818000098'): apply only the files that sort before
  // it. For a GENERATOR that must measure the chain its own output will be appended to
  // (scripts/build-npc-0098.mjs) — never for a gate, which always applies the whole chain.
  const files = (await migrationFiles()).filter((f) => !stopBefore || f < stopBefore)
  const notices = new Map()
  const applied = []

  const version = await db.query('select version() as v')
  if (!quiet) log(`engine: ${version.rows[0].v.split(' on ')[0]}`)
  if (!quiet) log(`chain:  ${files.length} migration(s) in supabase/migrations/`)
  if (files.length === 0) {
    throw new Error(
      'EMPTY CHAIN: supabase/migrations/ holds no .sql files. A green run over nothing is not a proof.',
    )
  }

  // ── The Supabase-shaped preamble, before anything else ───────────────────────────────────────
  // Without it, every grant / default-ACL assert in the chain is vacuous here: it passes because
  // a bare PGlite has nothing for it to find. See the header, and DEV_LOG D8.
  const preambleNotices = await applyPreamble(db)
  if (!quiet) {
    log('\n── preamble: scripts/db/supabase-preamble.sql  (test fixture, never deployed)')
    for (const line of preambleNotices) log(`    ${line}`)
  }

  for (const file of files) {
    const full = path.join(MIGRATIONS_DIR, file)
    const raw = await readFile(full, 'utf8')

    // LF is a deploy precondition, not a style preference (.gitattributes header, DEV_LOG D2).
    // A \r baked into a function body can never match pg_get_functiondef() output, which is LF.
    if (raw.includes('\r')) {
      throw new Error(`CRLF in ${file}: migrations must be LF-only. Fix the file, not this check.`)
    }

    const captured = []
    const t0 = Date.now()
    try {
      await db.exec(raw, { onNotice: (n) => captured.push(n.message ?? String(n)) })
    } catch (err) {
      notices.set(file, captured)
      for (const line of captured) log(`    notice: ${line}`)
      const e = new Error(
        [
          '',
          '═══════════════════════════════════════════════════════════════════════',
          `MIGRATION FAILED: ${file}`,
          '═══════════════════════════════════════════════════════════════════════',
          `  message: ${err.message}`,
          err.code ? `  sqlstate: ${err.code}` : null,
          err.detail ? `  detail: ${err.detail}` : null,
          err.hint ? `  hint: ${err.hint}` : null,
          err.where ? `  context: ${err.where}` : null,
          err.position ? `  position: ${err.position}` : null,
          `  file: ${full}`,
        ]
          .filter(Boolean)
          .join('\n'),
      )
      e.cause = err
      e.migration = file
      throw e
    }
    const ms = Date.now() - t0
    notices.set(file, captured)
    applied.push(file)

    if (!quiet) {
      log(`\n── ${file}  (${ms} ms)`)
      if (captured.length === 0) {
        log('    (no notices — this migration printed no self-assert receipt)')
      } else {
        for (const line of captured) log(`    ${line}`)
      }
    }
  }

  return { db, applied, notices }
}

/** Where the `preamble` variant's prefix snapshots live. Under node_modules/.cache: never committed. */
export const PREFIX_CACHE_DIR = path.join(REPO_ROOT, 'node_modules', '.cache', 'byeharu-chain-prefix')

/**
 * The base the GATE's world starts from: a fresh PGlite with supabase-preamble.sql applied. The
 * preamble's own text is part of the key, so an edited fixture can never be served a snapshot built
 * over the old one.
 */
export async function preambleVariant() {
  const { createHash } = await import('node:crypto')
  const text = await readFile(PREAMBLE_PATH, 'utf8')
  return {
    name: 'preamble',
    baseId: `new PGlite() + supabase-preamble.sql sha256 ${createHash('sha256').update(text).digest('hex')}`,
    async create() {
      const { PGlite } = await import('@electric-sql/pglite')
      const db = await new PGlite()
      await applyPreamble(db)
      return db
    },
  }
}

/**
 * The whole chain over the preamble — like applyChain() above, but restoring the longest cached
 * prefix (scripts/db/prefix-cache.mjs) and applying only the files after it. For the PROOF run
 * (proof.mjs, pglite-gate), whose unique value is the proofs and not a second from-zero apply;
 * `npm run db:apply` stays a from-zero apply, and so does CI's disposable-chain job.
 *
 * Reads the files RAW, like applyChain() above, so a CRLF file is refused (src/lib/db/chain.ts
 * `assertChainIsSane`) rather than silently normalised.
 *
 * @returns {Promise<{db: import('@electric-sql/pglite').PGlite, applied: string[], notices: Map<string,string[]>,
 *   records: object[], restored: number, restoredFrom: string|null, key: string, ms: number}>}
 */
export async function applyChainCached({ log = console.log, fresh, cacheDir = PREFIX_CACHE_DIR } = {}) {
  const { applyWithPrefixCache } = await import('./prefix-cache.mjs')
  const names = await migrationFiles()
  if (names.length === 0) {
    throw new Error('EMPTY CHAIN: supabase/migrations/ holds no .sql files. A green run over nothing is not a proof.')
  }
  const files = []
  for (const name of names) files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
  const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir, log, fresh })
  return {
    db: out.db,
    applied: out.applied.map((r) => r.name),
    notices: new Map(out.applied.map((r) => [r.name, r.notices])),
    records: out.applied,
    restored: out.restored,
    restoredFrom: out.restoredFrom,
    key: out.key,
    ms: out.ms,
  }
}

/** Count how many notices across the chain look like a self-assert receipt. */
export function selfAssertReceipts(notices) {
  let n = 0
  for (const lines of notices.values()) {
    for (const line of lines) if (/self-assert ok:/i.test(line)) n += 1
  }
  return n
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))
if (isMain) {
  const quiet = process.argv.includes('--quiet')
  try {
    const { db, applied, notices } = await applyChain({ quiet })
    const receipts = selfAssertReceipts(notices)
    console.log('')
    console.log('═══════════════════════════════════════════════════════════════════════')
    console.log(`CHAIN APPLIED: ${applied.length} migration(s), ${receipts} self-assert receipt(s)`)
    console.log('═══════════════════════════════════════════════════════════════════════')

    // Non-vacuity floor. A chain whose migrations stopped printing their receipts is a chain
    // whose self-asserts may have quietly stopped asserting. Every migration must produce one.
    if (receipts < applied.length) {
      console.error(
        `FAIL: ${applied.length} migration(s) applied but only ${receipts} printed a ` +
          `"self-assert ok:" receipt. Every migration must prove itself out loud.`,
      )
      await db.close()
      process.exit(1)
    }

    // ── THE WORLD GUARD: the applied world must EQUAL data/*.json, on every apply ────────────
    // Added 2026-08-24, after 0003 was edited post-deploy and the divergence stayed green for a
    // whole working day. See scripts/db/world-guard.mjs. proof.mjs runs the same gate. It sits
    // here in the CLI (not inside applyChain()) because tools like build-sea-places.mjs apply
    // DELIBERATELY partial chains through the library and must not be judged as worlds.
    const { assertWorldMatchesData } = await import('./world-guard.mjs')
    await assertWorldMatchesData(db, { log: console.log })

    await db.close()
    process.exit(0)
  } catch (err) {
    console.error(err.message)
    process.exit(1)
  }
}

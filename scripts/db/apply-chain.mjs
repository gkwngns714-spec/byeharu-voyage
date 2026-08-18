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
// WHAT IT DOES NOT PROVE
//   * It is not Supabase. `anon` / `authenticated` / `service_role` and `auth.uid()` do not exist
//     in a bare PostgreSQL, so migration 0001 mints them ONLY IF ABSENT (a gap-filling shim, never
//     an overwrite). What that means here: the grant lockdown is proven against roles this chain
//     created, and CI's disposable Supabase is where it is proven against the roles Supabase
//     itself creates with its own default GRANT ALL. Both are needed. Neither replaces the other.
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

/** Filenames the chain consists of, in the order PostgreSQL will see them. */
export async function migrationFiles() {
  const entries = await readdir(MIGRATIONS_DIR)
  return entries.filter((f) => f.endsWith('.sql')).sort()
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
export async function applyChain({ quiet = false, log = console.log } = {}) {
  const { PGlite } = await import('@electric-sql/pglite')
  const db = await new PGlite()

  const files = await migrationFiles()
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
    await db.close()
    process.exit(0)
  } catch (err) {
    console.error(err.message)
    process.exit(1)
  }
}

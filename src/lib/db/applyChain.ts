// ═══════════════════════════════════════════════════════════════════════════════════════════════
// applyChain — the browser equivalent of scripts/db/apply-chain.mjs, statement for statement
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Same files, same order, same failure report. The ONE thing that differs is where the text came
// from (a build-time asset instead of `fs.readFile`), and that difference is confined to
// chainSource.ts / chainSource.node.mjs.
//
// Every migration in this chain proves its own effect in the transaction that applies it and says
// so with `raise notice '... self-assert ok: ...'`. Those notices are captured here rather than
// discarded, because a migration that stopped printing its receipt is a migration whose
// self-assert may have quietly stopped asserting (see apply-chain.mjs's non-vacuity floor).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { MigrationFile } from './chain'
import { assertChainIsSane, orderChain } from './chain'

/** The slice of PGlite this module needs. Structural, so a test can hand in a stub. */
export interface PgExecutor {
  exec(sql: string, options?: { onNotice?: (notice: { message?: string }) => void }): Promise<unknown>
  query<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<{ rows: T[] }>
}

export interface AppliedMigration {
  name: string
  ms: number
  notices: string[]
  /** True when this migration printed a `self-assert ok:` receipt. */
  receipt: boolean
}

export interface ApplyResult {
  applied: AppliedMigration[]
  /** Total migrations that printed a self-assert receipt. */
  receipts: number
  ms: number
}

/** Called before each file starts, so a UI can name the migration it is waiting on. */
export type ApplyProgress = (step: { name: string; index: number; total: number }) => void

const RECEIPT_RE = /self-assert ok:/i

/**
 * Apply every migration, in filename order, to a live Postgres.
 *
 * Fails LOUDLY: the thrown Error names the offending FILE and carries the raw PostgreSQL fields
 * (sqlstate, detail, hint, plpgsql context), because "migration 7 failed" without them is a bug
 * report nobody can act on — and because a half-applied chain must never be mistaken for a slow one.
 */
export async function applyChain(
  db: PgExecutor,
  files: readonly MigrationFile[],
  onProgress?: ApplyProgress,
): Promise<ApplyResult> {
  assertChainIsSane(files)
  const ordered = orderChain(files)
  const applied: AppliedMigration[] = []
  const t0 = now()

  for (let i = 0; i < ordered.length; i += 1) {
    const file = ordered[i]
    onProgress?.({ name: file.name, index: i, total: ordered.length })
    const notices: string[] = []
    const t = now()
    try {
      await db.exec(file.sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
    } catch (err) {
      throw migrationError(file.name, err, notices)
    }
    applied.push({
      name: file.name,
      ms: Math.round(now() - t),
      notices,
      receipt: notices.some((line) => RECEIPT_RE.test(line)),
    })
  }

  return {
    applied,
    receipts: applied.filter((a) => a.receipt).length,
    ms: Math.round(now() - t0),
  }
}

/** The error a failed migration throws: the file, the SQLSTATE, and the notices it got to first. */
export class MigrationFailure extends Error {
  readonly migration: string
  readonly sqlstate: string | null
  readonly notices: string[]
  constructor(message: string, migration: string, sqlstate: string | null, notices: string[], cause: unknown) {
    super(message)
    this.name = 'MigrationFailure'
    this.migration = migration
    this.sqlstate = sqlstate
    this.notices = notices
    this.cause = cause
  }
}

function migrationError(name: string, err: unknown, notices: string[]): MigrationFailure {
  const e = err as { message?: string; code?: string; detail?: string; hint?: string; where?: string }
  const lines = [
    `MIGRATION FAILED: ${name}`,
    `  message: ${e?.message ?? String(err)}`,
    e?.code ? `  sqlstate: ${e.code}` : null,
    e?.detail ? `  detail: ${e.detail}` : null,
    e?.hint ? `  hint: ${e.hint}` : null,
    e?.where ? `  context: ${e.where}` : null,
    notices.length ? `  notices before the failure:\n    ${notices.join('\n    ')}` : null,
  ].filter(Boolean)
  return new MigrationFailure(lines.join('\n'), name, e?.code ?? null, notices, err)
}

function now(): number {
  return typeof performance !== 'undefined' ? performance.now() : Date.now()
}

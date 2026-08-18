// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SQL, into a Node process — the same directory, read off disk
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The browser gets the chain through Vite (chainSource.ts). A spec does not run through Vite, so
// it reads the files directly — from supabase/migrations/, the same and only place SQL lives.
//
// WHY THIS FILE IS .mjs AND NOT .ts
//   tsconfig.test.json deliberately withholds Node's ambient types from specs, so that a spec is
//   held to exactly the same rules as the source it imports (see the note in that file). Reading a
//   directory needs `node:fs`. Rather than loosen that bar for every spec, the Node-only transport
//   lives in plain JavaScript with a hand-written .d.mts beside it: the type surface a spec sees is
//   two functions and a shape, and nothing pulls `process` or `fs` into ambient scope.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { mkdtemp, readdir, readFile, rm } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { tmpdir } from 'node:os'
import path from 'node:path'

const HERE = path.dirname(fileURLToPath(import.meta.url))

/** supabase/migrations/ — the ONE place SQL lives, resolved from this file, not from a cwd. */
export const MIGRATIONS_DIR = path.resolve(HERE, '..', '..', '..', 'supabase', 'migrations')

/** Every migration on disk, in apply order, with CRLF normalised the same way the browser does. */
export async function loadChain() {
  const entries = await readdir(MIGRATIONS_DIR)
  const names = entries.filter((f) => f.endsWith('.sql')).sort()
  const files = []
  for (const name of names) {
    const sql = await readFile(path.join(MIGRATIONS_DIR, name), 'utf8')
    files.push({ name, sql: sql.replace(/\r\n/g, '\n') })
  }
  return files
}

/**
 * The same chain with ONE migration altered, for proving that the fingerprint actually moves.
 * A change-detector nobody has ever seen change is not known to detect anything.
 */
export async function loadChainWithEdit(name, edit) {
  const files = await loadChain()
  return files.map((f) => (f.name === name ? { name: f.name, sql: edit(f.sql) } : f))
}

/**
 * A scratch directory a Node process can point PGlite at, so a spec can CLOSE the engine and open
 * it again over the same bytes. The browser persists to IndexedDB and Node cannot; what both share
 * — the stored fingerprint, the rebuild decision and the schema-level demolition — is what a spec
 * needs a durable dataDir to exercise at all.
 *
 * Returned as a bare path, not a `file://` URL: PGlite strips exactly seven characters off that
 * prefix, which mangles a Windows drive letter.
 */
export function scratchDataDir(label = 'byeharu') {
  return mkdtemp(path.join(tmpdir(), `pglite-${label}-`))
}

export function removeScratchDataDir(dir) {
  return rm(dir, { recursive: true, force: true })
}

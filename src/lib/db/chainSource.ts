// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SQL, into the browser — as build-time assets, from the ONE place SQL lives
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// `import.meta.glob` is resolved by Vite AT BUILD TIME against the real directory. There is no
// generated file to regenerate, no copy to keep in step, and no way for this to serve a chain the
// repository does not contain: add a migration and it is in the next build; change one and the
// fingerprint moves and every stored browser database rebuilds itself.
//
// BROWSER ONLY. `import.meta.glob` is a Vite transform, so a Node process that imports this file
// gets an empty object rather than a chain. Node (the specs, and anything running outside Vite)
// uses chainSource.node.mjs, which reads the same directory off disk. Two transports, one source
// of truth — the alternative was a build step that copies the SQL into a .ts file, which is
// exactly the duplicate that drifts.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { MigrationFile } from './chain'
import { orderChain } from './chain'

const MODULES = import.meta.glob('../../../supabase/migrations/*.sql', {
  query: '?raw',
  import: 'default',
  eager: true,
}) as Record<string, string>

/** Every migration this build carries, in apply order. Synchronous: the text is already here. */
export function chainFiles(): MigrationFile[] {
  const files: MigrationFile[] = Object.entries(MODULES).map(([path, sql]) => ({
    name: path.slice(path.lastIndexOf('/') + 1),
    // A Windows checkout can hand Vite CRLF even when git says otherwise. Normalising on READ is
    // the rule this repo already follows for sliced migrations: a `\r` inside a function body can
    // never match pg_get_functiondef()'s LF output, and the failure surfaces migrations later.
    sql: sql.replace(/\r\n/g, '\n'),
  }))
  return orderChain(files)
}

/** The shape openLocalDb() asks for. */
export function loadChain(): Promise<MigrationFile[]> {
  return Promise.resolve(chainFiles())
}

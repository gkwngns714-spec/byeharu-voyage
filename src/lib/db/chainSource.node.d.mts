// Types for chainSource.node.mjs — hand-written so that importing the Node transport does NOT drag
// Node's ambient globals into a spec's scope (see the note at the top of the .mjs, and the reason
// tsconfig.test.json withholds them).

export interface MigrationFile {
  name: string
  sql: string
}

/** Absolute path to supabase/migrations/. */
export declare const MIGRATIONS_DIR: string

/** Every migration on disk, in apply order, CRLF normalised. */
export declare function loadChain(): Promise<MigrationFile[]>

/** The same chain with one migration's text rewritten — for proving the fingerprint moves. */
export declare function loadChainWithEdit(
  name: string,
  edit: (sql: string) => string,
): Promise<MigrationFile[]>

/** A throwaway durable dataDir, so a spec can close the engine and open it again. */
export declare function scratchDataDir(label?: string): Promise<string>

export declare function removeScratchDataDir(dir: string): Promise<void>

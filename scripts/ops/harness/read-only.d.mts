// Types for read-only.mjs — hand-written, as scripts/db/prefix-cache.d.mts is: the module is plain JavaScript
// run by Node (the ops shell scripts call it), while tests/harness.guard.spec.ts gets a checked surface.

export interface Tokens {
  /** The file's top-level text: comments gone, every literal AND every dollar-quoted body one word. */
  top: string
  /** As `top`, but a `do` body and an `execute` literal inside one are inlined: where a scene writes. */
  code: string
}

export function tokenize(text: string): Tokens
export function statements(top: string): string[]
export function writesIn(code: string): string[]
export function gameCallsIn(code: string): string[]
export function isReadOnlyTransaction(stmts: string[]): boolean

/** THE RULE for a file about to be sent to production: first statement `begin transaction read only`,
 *  last `commit` or `rollback`, no write verb outside comments and literals. */
export function readOnlyVerdict(text: string): { ok: boolean; reason: string }

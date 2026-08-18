// Collapsible fold-state persistence — PURE helpers (no React/DOM). The <Collapsible> primitive
// composes these over window.localStorage; specs drive them with an injected reader so nothing
// here ever touches real storage.
//
// KEY CONVENTION: a `byeharu-voyage.` prefix + a versioned namespace. Fold state is pure UI
// preference (which sections a player keeps open), carries no game state and no per-account
// meaning, so it is deliberately NOT user-scoped.

/** The one localStorage key builder for a persisted fold. `id` is the caller's stable SECTION id
 *  (e.g. 'command.orders'); never a per-row/per-entity id — unbounded ids grow storage forever. */
export function foldStorageKey(id: string): string {
  return `byeharu-voyage.fold.v1:${id}`
}

/** Serialize an open/closed state for storage ('1' open / '0' closed). */
export function foldStateValue(open: boolean): '1' | '0' {
  return open ? '1' : '0'
}

/**
 * Read a persisted fold state through an injected reader (localStorage.getItem-shaped).
 * ONLY the two values this module writes are trusted; absence, garbage, or a throwing reader
 * (private-mode storage) all fall back to `defaultOpen` — a corrupt byte can never wedge a
 * section shut.
 */
export function readFoldState(
  read: (key: string) => string | null,
  id: string,
  defaultOpen: boolean,
): boolean {
  try {
    const raw = read(foldStorageKey(id))
    if (raw === '1') return true
    if (raw === '0') return false
    return defaultOpen
  } catch {
    return defaultOpen
  }
}

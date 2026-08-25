// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BOOT STATE — one observable, so a slow boot can be shown honestly instead of as a hang
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Booting the local engine is not instant: a ~10 MB WebAssembly Postgres has to compile, initdb
// has to run, and ten migrations that each PROVE THEMSELVES have to apply. That is seconds, not
// milliseconds. A spinner with no words turns those seconds into "the app is broken", and — worse
// — a spinner is also what a FAILURE looks like if the failure is swallowed.
//
// So the boot has a state machine, it names the migration it is on, and `failed` is a state with
// an error in it, not an absence of `ready`.
//
//   idle → booting → applying → seeding → ready
//                         └──────┴──────────→ failed
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export type BootPhase = 'idle' | 'booting' | 'applying' | 'seeding' | 'ready' | 'failed'

export interface BootState {
  phase: BootPhase
  /** The migration currently applying, e.g. `20260818000007_a_fleet_arrives...`. Null otherwise. */
  migration: string | null
  /** 0-based index of that migration, and how many there are. Both 0 outside `applying`. */
  migrationIndex: number
  migrationCount: number
  /** 0..1 — how much of the whole boot is done. For a bar that does not lie about being nearly done. */
  progress: number
  /** Human sentence for the current phase. Always safe to print. */
  message: string
  /** Set only in `failed`, and never cleared by a later phase of the same boot. */
  error: string | null
  /** The applied chain's fingerprint, once known. */
  fingerprint: string | null
  /** True when the stored database was thrown away and rebuilt because the chain had changed. */
  rebuilt: boolean
  /** Set when a rebuild demolished a world that had a player's rows in it. THE PLAYER MUST BE TOLD:
   *  a purse that silently returns to 8,000 ducats reads as the game losing their money, which is
   *  exactly how it was reported (DEV_LOG D11c). See lib/db/rescue.ts. */
  rescued: { rows: number; tables: number; stored: boolean; note: string | null } | null
  /** Set when a PRE-BUILT world was downloaded and then REFUSED because the fingerprint written
   *  inside it is not this build's chain. The boot recovers by applying the chain, so the game
   *  still starts — but a shipped world that disagrees with the shipped chain is the D23 defect
   *  wearing new clothes, and it must never pass in silence. See lib/db/appLocal.ts. */
  imageRefused: string | null
  /** Wall-clock ms since the boot started. Frozen when it reaches `ready` or `failed`. */
  elapsedMs: number
}

const INITIAL: BootState = {
  phase: 'idle',
  migration: null,
  migrationIndex: 0,
  migrationCount: 0,
  progress: 0,
  message: 'The local engine has not been asked for yet.',
  error: null,
  fingerprint: null,
  rebuilt: false,
  rescued: null,
  imageRefused: null,
  elapsedMs: 0,
}

type Listener = () => void

/** A minimal observable: `useSyncExternalStore` wants exactly this pair plus a stable snapshot. */
export interface BootChannel {
  get(): BootState
  subscribe(listener: Listener): () => void
  set(patch: Partial<BootState>): void
  reset(): void
}

export function createBootChannel(): BootChannel {
  let state: BootState = INITIAL
  const listeners = new Set<Listener>()
  return {
    get: () => state,
    subscribe(listener) {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },
    set(patch) {
      // A new object every time, because useSyncExternalStore compares by identity.
      state = { ...state, ...patch }
      for (const l of listeners) l()
    },
    reset() {
      state = INITIAL
      for (const l of listeners) l()
    },
  }
}

/** THE channel the app's local database reports on. One boot, one channel. */
export const bootChannel: BootChannel = createBootChannel()

/** The phase weights the progress bar uses. Applying the chain is most of the wall clock. */
export function progressFor(phase: BootPhase, migrationIndex: number, migrationCount: number): number {
  switch (phase) {
    case 'idle':
      return 0
    case 'booting':
      return 0.08
    case 'applying':
      return migrationCount > 0 ? 0.1 + 0.8 * (migrationIndex / migrationCount) : 0.1
    case 'seeding':
      return 0.94
    case 'ready':
      return 1
    case 'failed':
      return 1
  }
}

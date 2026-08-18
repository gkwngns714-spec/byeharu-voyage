import { createContext, useContext } from 'react'

// The shell's shared-state contract, in its own non-component module (the react-refresh rule
// forbids exporting hooks from a component file).
//
// THE RULE THIS FILE EXISTS TO KEEP: shared server state is polled ONCE, in AppShell, and reaches
// every tab through this context. A tab never mounts its own poller. byeharu had to retrofit that
// rule after several screens had grown private copies of the same fetch; here it is the shape from
// the first commit, so there is nowhere for a second copy to appear.
//
// Today the shell carries exactly one thing — the clock — because there is no game data yet. When
// the first read RPC lands (fleets, port, market), its hook mounts in AppShell and gains a field
// on ShellState. That is the ONLY way a tab gets server data.

export interface ShellState {
  /**
   * THE ONE CLOCK. A ticking wall-clock reading, in ms, shared by every screen.
   *
   * This game is full of "arrives in 4h 12m": each of those is a countdown, and a countdown needs
   * something to re-render it. Mounted once here, N countdowns cost ONE timer; mounted per
   * component they cost N timers all firing at slightly different moments, which is both wasteful
   * and visibly inconsistent (two panels showing 4h 12m and 4h 11m at the same instant).
   *
   * It is a DISPLAY value only. Time that decides anything — whether a voyage has arrived, whether
   * an offer expired — is decided by the server, in the RPC, from the database clock. A client
   * clock can be wrong or deliberately changed, so it may never gate an outcome.
   */
  nowMs: number
}

export const ShellStateContext = createContext<ShellState | null>(null)

export function useShellState(): ShellState {
  const v = useContext(ShellStateContext)
  if (!v) throw new Error('useShellState must be used within AppShell')
  return v
}

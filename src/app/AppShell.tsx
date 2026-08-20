import { useEffect, useMemo, useState } from 'react'
import { Link, Outlet } from 'react-router-dom'
import { ShellStateContext } from './shellState'
import { NavBar } from './NavBar'
import { RebuildNotice } from './RebuildNotice'
import { SignTheBook } from '../features/found/SignTheBook'
import { useWorld } from '../live/worldStore'

// THE PERSISTENT SHELL: a slim header, the tab content, and the ONE tab bar. Mounted once for the
// whole authenticated app; the shared data layer (see shellState.ts) mounts HERE and nowhere else.

/** How often the shell reads the world again. THE READ IS THE CATCH-UP (DESIGN D.2): every read
 *  settles every voyage server-side before it answers, so this interval is not a poll for changes
 *  — it IS how time passes in this game. Thirty seconds is well inside a voyage-day (three real
 *  minutes at TIME_COMPRESSION 480), so nothing can arrive without the next read noticing. */
const READ_INTERVAL_MS = 30_000

export function AppShell() {
  // THE ONE CLOCK (shellState.ts explains why it is here and not in the countdowns themselves).
  // One second is the coarsest tick that still lets a "12s" readout look alive.
  const [nowMs, setNowMs] = useState(() => Date.now())
  useEffect(() => {
    const id = window.setInterval(() => setNowMs(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [])

  // THE WORLD OPENS HERE, ONCE, and reaches every tab through the store. That is shellState.ts's
  // own rule — "shared server state is polled ONCE, in AppShell; a tab never mounts its own
  // poller" — applied to the real chain instead of to a stand-in.
  useEffect(() => {
    void useWorld.getState().open()
  }, [])

  useEffect(() => {
    const id = window.setInterval(() => {
      const world = useWorld.getState()
      // Only when the world is up, and never on top of a read already in flight: a second read
      // would settle the same voyages twice for nothing and race the first one's answer.
      if (world.phase === 'ready' && !world.busy) void world.refresh()
    }, READ_INTERVAL_MS)
    return () => window.clearInterval(id)
  }, [])

  // A tab regaining focus is a player coming back, and coming back is exactly the moment the
  // ledger should have moved. Reading here is what makes "it moved while I was away" true.
  useEffect(() => {
    const onVisible = () => {
      const world = useWorld.getState()
      if (document.visibilityState === 'visible' && world.phase === 'ready' && !world.busy) {
        void world.refresh()
      }
    }
    document.addEventListener('visibilitychange', onVisible)
    return () => document.removeEventListener('visibilitychange', onVisible)
  }, [])

  // The register gate's two inputs, selected as PRIMITIVES and not as one object: a selector
  // returning `{phase, fleets}` builds a fresh object every render, and zustand compares with
  // Object.is — so it would re-render the whole shell on every market fetch, which is the opposite
  // of what selecting is for.
  const worldPhase = useWorld((s) => s.phase)
  const houseUnfounded = useWorld((s) => s.fleets.length === 0)

  const shell = useMemo(() => ({ nowMs }), [nowMs])

  return (
    <ShellStateContext.Provider value={shell}>
      <div className="flex h-[100dvh] flex-col bg-app text-ink">
        {/* The wordmark is quiet chrome, not a control. The only affordance in the header is the
            route to Profile — identity is something you CHECK, so it stays out of the thumb bar's
            eight destinations... except that Profile IS one of the eight here, so this header link
            is a shortcut, not a second authority. */}
        <header className="flex min-h-11 shrink-0 items-center justify-between border-b border-edge bg-surface px-4">
          <span className="font-mono text-xs uppercase tracking-[0.2em] text-ink-faint">Byeharu Voyage</span>
          <Link
            to="/profile"
            className="font-mono text-[11px] uppercase tracking-wider text-ink-faint transition hover:text-ink"
          >
            Account
          </Link>
        </header>

        {/* A world that was demolished and rebuilt says so, once, above everything — see
            RebuildNotice.tsx. It renders nothing on an ordinary boot. */}
        <RebuildNotice />

        {/* A SIGNED-IN CAPTAIN WITH NO HOUSE GETS ONE DOOR, NOT EIGHT TABS.
            On a real project `public.new_house()` is revoked from every client role, so a new
            account arrives owning nothing — and every tab would be an empty shell of a screen. The
            register replaces the whole tab content until the book is signed, so there is nothing to
            navigate around and nothing to misread as broken.

            `fleets.length === 0` is only meaningful once the world is READY: while it is opening or
            after it has failed the list is empty too, and those are not the same state. Local mode
            founds its captain during boot, so this never appears there. */
        }
        {worldPhase === 'ready' && houseUnfounded ? (
          <main className="min-h-0 flex-1 overflow-hidden">
            <SignTheBook />
          </main>
        ) : (
          <>
            {/* Tab content gets the viewport minus header and tab bar; each screen owns its own
                scroll (see the Screen primitive), so the page itself never scrolls. */}
            <main className="min-h-0 flex-1 overflow-hidden">
              <Outlet />
            </main>

            <NavBar />
          </>
        )}
      </div>
    </ShellStateContext.Provider>
  )
}

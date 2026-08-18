import { useEffect, useMemo, useState } from 'react'
import { Link, Outlet } from 'react-router-dom'
import { ShellStateContext } from './shellState'
import { NavBar } from './NavBar'

// THE PERSISTENT SHELL: a slim header, the tab content, and the ONE tab bar. Mounted once for the
// whole authenticated app; the shared data layer (see shellState.ts) mounts HERE and nowhere else.

export function AppShell() {
  // THE ONE CLOCK (shellState.ts explains why it is here and not in the countdowns themselves).
  // One second is the coarsest tick that still lets a "12s" readout look alive.
  const [nowMs, setNowMs] = useState(() => Date.now())
  useEffect(() => {
    const id = window.setInterval(() => setNowMs(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [])

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

        {/* Tab content gets the viewport minus header and tab bar; each screen owns its own scroll
            (see the Screen primitive), so the page itself never scrolls. */}
        <main className="min-h-0 flex-1 overflow-hidden">
          <Outlet />
        </main>

        <NavBar />
      </div>
    </ShellStateContext.Provider>
  )
}

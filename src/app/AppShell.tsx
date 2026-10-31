import { useEffect, useMemo, useState } from 'react'
import { Outlet, useNavigate } from 'react-router-dom'
import { ShellStateContext } from './shellState'
import { NavBar } from './NavBar'
import { TopBar } from './TopBar'
import { RebuildNotice } from './RebuildNotice'
import { SignTheBook } from '../features/found/SignTheBook'
import { useWorld } from '../live/worldStore'
import { serverNow } from '../lib/serverClock'
import { useGoTo } from '../chart'
import { useLocale } from '../lib/i18n'
import { readIntervalMs } from '../domain/readClock'

// THE PERSISTENT SHELL: a slim header, the tab content, and the ONE tab bar. Mounted once for the
// whole authenticated app; the shared data layer (see shellState.ts) mounts HERE and nowhere else.

/** THE READ CADENCE lives in src/app/readClock.ts now — one authority for "how often the world is
 *  read", shared with the resource cache's default lifetime (worldStore.readEveryMs). The rule is
 *  unchanged: the served clock decides it. */

export function AppShell() {
  // THE LANGUAGE (src/lib/i18n): read here so a switch re-renders the whole tree in place — no
  // reload, no remount; a screen's own `useT()` then hands it the new words.
  useLocale()
  // THE ONE CLOCK (shellState.ts explains why it is here and not in the countdowns themselves).
  // One second is the coarsest tick that still lets a "12s" readout look alive.
  // On the SERVER's time (lib/serverClock.ts), so every player's clock and countdowns agree.
  const [nowMs, setNowMs] = useState(() => serverNow())
  useEffect(() => {
    const id = window.setInterval(() => setNowMs(serverNow()), 1000)
    return () => window.clearInterval(id)
  }, [])

  // THE WORLD OPENS HERE, ONCE, and reaches every tab through the store. That is shellState.ts's
  // own rule — "shared server state is polled ONCE, in AppShell; a tab never mounts its own
  // poller" — applied to the real chain instead of to a stand-in.
  useEffect(() => {
    void useWorld.getState().open()
  }, [])

  // GO TO (src/chart/goTo.ts): a place named on any tab brings the Map tab up — the one navigator
  // the request uses, registered here because this is the shell, inside the router.
  const navigate = useNavigate()
  useEffect(() => {
    useGoTo.setState({ openMap: () => navigate('/map') })
    return () => useGoTo.setState({ openMap: null })
  }, [navigate])

  // The cadence follows the SERVED clock, so it is right for whatever the world's compression is —
  // and it re-arms if that knob ever changes under a running tab.
  const compression = useWorld((w) => w.snapshot?.config.time_compression)
  useEffect(() => {
    const every = readIntervalMs(compression)
    // THE BEAT IS ALSO THE CACHE'S DEFAULT LIFETIME: a served read is kept for exactly one beat,
    // so a remount inside it downloads nothing and the beat's own read still refreshes the world.
    useWorld.setState({ readEveryMs: every })
    const id = window.setInterval(() => {
      const world = useWorld.getState()
      // Only when the world is up, and never on top of a read already in flight: a second read
      // would settle the same voyages twice for nothing and race the first one's answer.
      if (world.phase === 'ready' && !world.reading) void world.refresh()
    }, every)
    return () => window.clearInterval(id)
  }, [compression])

  // A tab regaining focus is a player coming back, and coming back is exactly the moment the
  // ledger should have moved. Reading here is what makes "it moved while I was away" true.
  useEffect(() => {
    const onVisible = () => {
      const world = useWorld.getState()
      if (document.visibilityState === 'visible' && world.phase === 'ready' && !world.reading) {
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
      {/* THE WORLD IS BEHIND THE GLASS (docs/UI_DIRECTION.md rule 6). The shell root is a lit sea
          rather than a flat colour, and it does NOT scroll — each screen scrolls its own panels
          over it, so the horizon stays put the way it would from a deck. The bar and the tab rail
          paint their own opaque material on top.
          `data-world` IS THE STORE'S LOAD PHASE, said on the shell (2026-10-18). Each screen draws
          its own "not yet" — COMMAND a "Loading…" row, the map "opening the chart…", the other tabs
          WorldLoading's skeleton — so nothing screen-shaped can say "the world is up" for every
          route. The phase can: it is the one authority every screen gates on. The browser specs'
          ready() (tests/appReady.fixture.ts) waits on it; nothing in the app reads it. */}
      <div className="bv-sea flex h-[100dvh] flex-col text-ink" data-world={worldPhase}>
        {/* The persistent game chrome, and since step 3 it is a 32px STATUS STRIP: the purse, and
            the market countdown while you are on a trade screen. TopBar.tsx carries what the
            wordmark and the live-read dot were costing, and why neither is missed. */}
        <TopBar />

        {/* A world that was demolished and rebuilt says so, once, above everything — one `Note`,
            see RebuildNotice.tsx. It renders nothing on an ordinary boot. */}
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

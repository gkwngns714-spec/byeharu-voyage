import { useEffect, useMemo, useState } from 'react'
import { Outlet } from 'react-router-dom'
import { ShellStateContext } from './shellState'
import { NavBar } from './NavBar'
import { TopBar } from './TopBar'
import { RebuildNotice } from './RebuildNotice'
import { SignTheBook } from '../features/found/SignTheBook'
import { useWorld } from '../live/worldStore'

// THE PERSISTENT SHELL: a slim header, the tab content, and the ONE tab bar. Mounted once for the
// whole authenticated app; the shared data layer (see shellState.ts) mounts HERE and nowhere else.

/** How often the shell reads the world again. THE READ IS THE CATCH-UP (DESIGN D.2): every read
 *  settles every voyage server-side before it answers, so this interval is not a poll for changes
 *  — it IS how time passes in this game, and it is also how often a fleet's position on the chart
 *  can move.
 *
 *  THIS USED TO BE A FLAT 30 SECONDS, and its own comment justified that as "well inside a
 *  voyage-day (three real minutes at TIME_COMPRESSION 480)". Migration 0045 took the compression to
 *  9600 for testing, which makes a voyage-day NINE SECONDS — so thirty seconds became THREE AND A
 *  THIRD voyage-days between reads. A short passage could begin and end between two of them, and a
 *  fleet under way jumped across the chart instead of crawling. The owner: *"i want the location of
 *  my fleet moving in map to be shown more often, updated more often"*.
 *
 *  So the cadence is DERIVED from the served clock rather than pinned beside it. The rule is "read
 *  several times per voyage-day", which is what the old comment actually meant; the number 30_000
 *  was that rule evaluated once, by hand, against a knob that has since moved. A second hand-tuned
 *  constant would drift again the next time anyone touches the compression.
 *
 *  Clamped at both ends: never faster than 3 s (a read settles voyages server-side, and hammering
 *  it buys nothing a player can see), never slower than 30 s (the old cadence remains the floor on
 *  a slow world, so nothing can arrive unnoticed). */
const READS_PER_VOYAGE_DAY = 4
const READ_MIN_MS = 3_000
const READ_MAX_MS = 30_000

function readIntervalMs(timeCompression: number | undefined): number {
  if (!timeCompression || timeCompression <= 0) return READ_MAX_MS
  const voyageDaySeconds = (24 * 3600) / timeCompression
  const ms = (voyageDaySeconds / READS_PER_VOYAGE_DAY) * 1000
  return Math.min(READ_MAX_MS, Math.max(READ_MIN_MS, Math.round(ms)))
}

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

  // The cadence follows the SERVED clock, so it is right for whatever the world's compression is —
  // and it re-arms if that knob ever changes under a running tab.
  const compression = useWorld((w) => w.snapshot?.config.time_compression)
  useEffect(() => {
    const every = readIntervalMs(compression)
    const id = window.setInterval(() => {
      const world = useWorld.getState()
      // Only when the world is up, and never on top of a read already in flight: a second read
      // would settle the same voyages twice for nothing and race the first one's answer.
      if (world.phase === 'ready' && !world.busy) void world.refresh()
    }, every)
    return () => window.clearInterval(id)
  }, [compression])

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
      {/* THE WORLD IS BEHIND THE GLASS (docs/UI_DIRECTION.md rule 6). The shell root is a lit sea
          rather than a flat colour, and it does NOT scroll — each screen scrolls its own panels
          over it, so the horizon stays put the way it would from a deck. The bar and the tab rail
          paint their own opaque material on top. */}
      <div className="bv-sea flex h-[100dvh] flex-col text-ink">
        {/* The persistent game chrome: wordmark, the live-read dot, and the purse. TopBar.tsx
            explains why it carries exactly one figure and no back chevron. */}
        <TopBar />

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

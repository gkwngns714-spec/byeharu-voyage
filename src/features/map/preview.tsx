import { StrictMode, useEffect, useState } from 'react'
import { createRoot } from 'react-dom/client'
import '../../index.css'
import { ShellStateContext } from '../../app/shellState'
import { useWorld } from '../../live/worldStore'
import { MapScreen } from './MapScreen'

// RENDER HARNESS — dev only. See preview.html for what it is and why it exists.
//
// It mounts the REAL MapScreen with the REAL design tokens and, since the map came off its stub
// data, the REAL world: it opens the live store exactly as AppShell does, so what you look at here
// is 214 harbours, 782 sea lanes and whatever fleets the local chain has, not a demonstration.
//
// The two things it supplies that the app supplies elsewhere:
//   · `open()` — AppShell owns this in the app. Here there is no shell, so the harness opens the
//     world itself. It is the store's own idempotent call, not a second loader.
//   · the shell clock — one interval, the same 1 Hz cadence AppShell uses, because the map counts a
//     voyage down against it. The map does NOT move a glyph with it; nothing here can drift.
//
// `vite build` only compiles index.html, so nothing here reaches a production bundle.

// Exported so this entry file has an export: without one, Fast Refresh cannot swap the component
// and the harness would need a full reload on every edit — which is the opposite of what it is for.
export function Harness() {
  const open = useWorld((s) => s.open)
  const [nowMs, setNowMs] = useState(() => Date.now())

  useEffect(() => {
    void open()
  }, [open])

  useEffect(() => {
    const id = window.setInterval(() => setNowMs(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [])

  return (
    <ShellStateContext.Provider value={{ nowMs }}>
      <MapScreen />
    </ShellStateContext.Provider>
  )
}

const host = document.getElementById('map-preview')
if (host) {
  createRoot(host).render(
    <StrictMode>
      <Harness />
    </StrictMode>,
  )
}

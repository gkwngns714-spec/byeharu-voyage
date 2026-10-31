import { useEffect } from 'react'
import { readIntervalMs } from '../domain/readClock'
import { useWorld } from './worldStore'

// THE ONE BEAT — the world's read cadence, armed by whichever screen owns the world's clock.
//
// The shell arms it for the tabs (AppShell). The City page stands OUTSIDE the shell and provides
// the clock itself, so it arms the same beat here; before this hook it armed none, which meant
// every served read on the city page (the hall, the market, the requests) was asked once and then
// frozen until the player left the city — prices and boards did not move under a standing player.
//
// A second spelling of the interval is exactly what this hook exists to prevent: the cadence is
// `readIntervalMs` over the served compression, and it re-arms if that knob changes under a
// running screen. The rules are AppShell's own, moved here verbatim: only when the world is up, and
// never on top of a read already in flight.
export function useWorldBeat(): void {
  const compression = useWorld((w) => w.snapshot?.config.time_compression)
  useEffect(() => {
    const every = readIntervalMs(compression)
    // THE BEAT IS ALSO THE CACHE'S DEFAULT LIFETIME: a served read is kept for exactly one beat,
    // so a remount inside it downloads nothing and the beat's own read still refreshes the world.
    useWorld.setState({ readEveryMs: every })
    const id = window.setInterval(() => {
      const world = useWorld.getState()
      if (world.phase === 'ready' && !world.reading) void world.refresh()
    }, every)
    return () => window.clearInterval(id)
  }, [compression])
}

import { useEffect, useState } from 'react'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CHART'S CLOCK — a wall-clock reading, sampled per animation frame.
//
// WHY THIS SURFACE HAS ITS OWN AND THE SHELL'S ONE-CLOCK RULE IS NOT BROKEN.
// `src/app/shellState.ts` carries a 1 Hz clock so that N countdowns cost ONE timer instead of N.
// That rule is about not letting every panel grow a private poller. The map is one surface with
// one timer, and it needs frames rather than seconds: a glyph that jumps once a second on a
// six-minute passage reads as broken. Everything the map draws AND everything its panels print
// (position, ETA, nautical miles) is derived from THIS single reading, so no two things on the
// chart can ever be showing different instants.
//
// It samples `Date.now()`; it never accumulates. That is the point — see ./voyage.ts. A frame that
// never fires (a hidden tab: requestAnimationFrame stops) costs nothing, because the next frame
// asks the wall clock where the fleet is now, not where it was plus a delta.
//
// `prefers-reduced-motion` drops it to DESIGN §E.5's stated 1 Hz. A player who has asked the
// system for less movement gets the slower cadence; the positions are identical arithmetic.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function useWallClock(): number {
  const [nowMs, setNowMs] = useState(() => Date.now())

  useEffect(() => {
    const reduceMotion =
      typeof window.matchMedia === 'function' &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches

    if (reduceMotion) {
      const id = window.setInterval(() => setNowMs(Date.now()), 1000)
      return () => window.clearInterval(id)
    }

    let frame = 0
    const step = () => {
      setNowMs(Date.now())
      frame = window.requestAnimationFrame(step)
    }
    frame = window.requestAnimationFrame(step)
    return () => window.cancelAnimationFrame(frame)
  }, [])

  return nowMs
}

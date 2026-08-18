import { useEffect, useState } from 'react'
import { loadCoastline, type CoastlineData } from './coastline'

// Fetches and decimates the vendored world outline once per mount (see ./coastline.ts for why it
// is fetched rather than bundled). The chart draws sea, ports and fleets IMMEDIATELY and the coast
// arrives a moment later — a backdrop must never be the thing that makes the map wait.
//
// A failure is reported, not thrown: the map without a coastline is still a working map, and a
// missing decoration may not take a tab down.

export interface CoastlineState {
  readonly data: CoastlineData | null
  readonly error: string | null
}

export function useCoastline(): CoastlineState {
  const [state, setState] = useState<CoastlineState>({ data: null, error: null })

  useEffect(() => {
    const controller = new AbortController()
    loadCoastline(controller.signal)
      .then((data) => setState({ data, error: null }))
      .catch((cause: unknown) => {
        // An abort is this effect cleaning up (React 19 StrictMode mounts twice in development),
        // not a failure to report.
        if (controller.signal.aborted) return
        setState({ data: null, error: cause instanceof Error ? cause.message : 'chart unavailable' })
      })
    return () => controller.abort()
  }, [])

  return state
}

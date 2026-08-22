import { useEffect, useState } from 'react'
import type { CoastlineData } from './coastlineBuild'

// Fetches and decimates the vendored world outline once per mount (see ./coastline.ts for why it
// is fetched rather than bundled). The chart draws sea, ports and fleets IMMEDIATELY and the coast
// arrives a moment later — a backdrop must never be the thing that makes the map wait.
//
// A failure is reported, not thrown: the map without a coastline is still a working map, and a
// missing decoration may not take a tab down.
//
// ── WHY `./coastline` IS IMPORTED INSIDE THE EFFECT (2026-08-23) ────────────────────────────────
// It is the one module in this section that a BUNDLER has to resolve: `import … from
// '../../data/world-110m.json?url'` is a Vite instruction, and a plain Node process loading it dies
// with *"needs an import attribute of type: json"*. Statically, that made the whole section
// unloadable outside a browser build the moment `./index.ts` re-exported anything that reached it.
//
// That mattered immediately and it was found by the guard rather than argued about:
// `tests/map.*.spec.ts` are pure Node specs, and `coastlineBuild.ts`'s own header says its
// decimation figures are *"measured by running THIS function over it"* rather than estimated —
// which is only true while a spec can import it. So the bundler-only edge is deferred to the
// moment the coast is actually wanted, and the section's entrance stays loadable by a spec.
//
// It costs one small extra chunk on the first open of a chart, ahead of the 280 KB JSON that chunk
// exists to fetch. `loadCoastline` is deliberately NOT on the section's entrance for the same
// reason: nothing outside should be able to pull the bundler edge back into a static graph.

export interface CoastlineState {
  readonly data: CoastlineData | null
  readonly error: string | null
}

export function useCoastline(): CoastlineState {
  const [state, setState] = useState<CoastlineState>({ data: null, error: null })

  useEffect(() => {
    const controller = new AbortController()
    import('./coastline')
      .then(({ loadCoastline }) => loadCoastline(controller.signal))
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

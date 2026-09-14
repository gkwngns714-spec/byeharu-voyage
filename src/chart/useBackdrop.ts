import { useEffect, useMemo, useState } from 'react'
import type { Point } from '../lib/geo'
import type { SnapshotPort } from '../lib/rpc'
import type { CoastlineData } from './coastlineBuild'
import { landfallPorts } from './landfall'
import { mapPortsOf } from './liveWorld'
import type { MapPort, MapSea } from './mapTypes'
import type { RegionTint } from './regions'

// Fetches and decimates the vendored world outline, and reads the seas' names, once per mount
// (see ./backdrop.ts for why they are fetched rather than bundled). The chart draws sea, ports and
// fleets IMMEDIATELY and the backdrop arrives a moment later — furniture must never be the thing
// that makes the map wait.
//
// It was ./useCoastline.ts; row 90 widened what it carries, not what it does.
//
// ── AND SINCE ROW 92 (2026-09-14) IT ALSO SETS THE PORTS ON THE SHORE ──────────────────────────
// "Some cities are in the ocean." The harbour table is served with the cities' true coordinates
// and the coast is drawn from a 110m file, and at 110m a true coordinate can fall a few miles
// into drawn water (./landfall.ts measures it: 79 of 224 harbours, 52 of them within 10 nm of
// the drawn shore, 28 on islands the file has no polygon for at all). The mark, the name, the
// tap target, the roadstead's dotted line and a docked fleet's glyph all read ONE coordinate
// off `MapPort`, so the move is made ONCE, here, where the served table and the drawn coast
// first meet — and every surface that draws ports (the Map tab, `SmallChart`) gets its ports
// from this hook and can never hold a second, unmoved copy. Until the coast arrives the ports
// are the served coordinates; they step onto the shore in the frame the shore is drawn.
//
// `islets` are the 28: a harbour whose island the file lacks gets a speck of land under its
// mark (CoastlineLayer draws them) — "a harbour is where land meets water" is already the rule
// `openingBounds` frames by, and a mark on bare water where a town stands is the picture the
// owner objected to.
//
// A failure is reported, not thrown: the map without a coastline is still a working map, and a
// missing decoration may not take a tab down.
//
// ── WHY `./backdrop` IS IMPORTED INSIDE THE EFFECT (2026-08-23) ─────────────────────────────────
// It is the one module in this section that a BUNDLER has to resolve: `import … from
// '../../data/world-110m.json?url'` is a Vite instruction, and a plain Node process loading it dies
// with *"needs an import attribute of type: json"*. Statically, that made the whole section
// unloadable outside a browser build the moment `./index.ts` re-exported anything that reached it.
//
// That mattered immediately and it was found by the guard rather than argued about:
// `tests/map.*.spec.ts` are pure Node specs, and `coastlineBuild.ts`'s own header says its
// decimation figures are *"measured by running THIS function over it"* rather than estimated —
// which is only true while a spec can import it. So the bundler-only edge is deferred to the
// moment the backdrop is actually wanted, and the section's entrance stays loadable by a spec.
//
// It costs one small extra chunk on the first open of a chart, ahead of the 280 KB JSON that chunk
// exists to fetch. `loadBackdrop` is deliberately NOT on the section's entrance for the same
// reason: nothing outside should be able to pull the bundler edge back into a static graph.

export interface BackdropState {
  /** The coast, or null until it has arrived (or if it failed). */
  readonly coast: CoastlineData | null
  /** The seas' names — empty until the backdrop has arrived, which draws no names, truthfully. */
  readonly seas: readonly MapSea[]
  /** The regions' tints (row 93) — empty until the backdrop has arrived. Painted only when a
   *  surface hands them to `ChartCanvas`, which it does only while the filter is on. */
  readonly regions: readonly RegionTint[]
  /** THE PORT TABLE AS THIS CHART DRAWS IT (row 92): `mapPortsOf` the served rows, every harbour
   *  set on the drawn shore once the coast is here. The one list every layer, the hit test and
   *  the frame read. */
  readonly ports: readonly MapPort[]
  /** Harbours the drawn coast has no land for within `LANDFALL_CAP_NM` — an island the file
   *  lacks — as chart points; a speck of land is drawn under each. Empty until the coast is here. */
  readonly islets: readonly Point[]
  readonly error: string | null
}

const NO_SEAS: readonly MapSea[] = []
const NO_REGIONS: readonly RegionTint[] = []

interface Loaded {
  readonly coast: CoastlineData | null
  readonly seas: readonly MapSea[]
  readonly regions: readonly RegionTint[]
  readonly error: string | null
}

export function useBackdrop(snapshotPorts: readonly SnapshotPort[]): BackdropState {
  const [loaded, setLoaded] = useState<Loaded>({ coast: null, seas: NO_SEAS, regions: NO_REGIONS, error: null })

  useEffect(() => {
    const controller = new AbortController()
    import('./backdrop')
      .then(({ loadBackdrop }) => loadBackdrop(controller.signal))
      .then((data) => setLoaded({ coast: data.coast, seas: data.seas, regions: data.regions, error: null }))
      .catch((cause: unknown) => {
        // An abort is this effect cleaning up (React 19 StrictMode mounts twice in development),
        // not a failure to report.
        if (controller.signal.aborted) return
        setLoaded({
          coast: null,
          seas: NO_SEAS,
          regions: NO_REGIONS,
          error: cause instanceof Error ? cause.message : 'chart unavailable',
        })
      })
    return () => controller.abort()
  }, [])

  const served = useMemo(() => mapPortsOf(snapshotPorts), [snapshotPorts])
  const landed = useMemo(() => landfallPorts(served, loaded.coast), [served, loaded.coast])

  return {
    coast: loaded.coast,
    seas: loaded.seas,
    regions: loaded.regions,
    ports: landed.ports,
    islets: landed.islets,
    error: loaded.error,
  }
}

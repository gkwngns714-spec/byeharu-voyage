// THE BACKDROP LOADER — the one part of the chart that touches the bundler and the network.
//
// It was ./coastline.ts, and it loaded the coast alone. Row 90 (2026-09-13) put the seas' names
// on the water, and the seas are a backdrop exactly as the coast is — authored data, not the
// server's — so they arrive through the same door, in the same fetch cycle, and the chart has
// ONE notion of "the backdrop has arrived" instead of two hooks that could disagree about it.
//
// It is separated from ./coastlineBuild.ts and ./seaNames.ts on purpose: those are pure (data
// in, decision out) and can therefore be run and MEASURED outside a browser, while this file owns
// the `?url` and `?raw` imports, which only a bundler can resolve. Keeping them apart is what
// lets the rendered path size in docs be a measured number instead of an estimate, and what lets
// tests/map.atmosphere.spec.ts run `mapSeasOf` over the real file in plain Node.

import { buildCoastline, type CoastlineData } from './coastlineBuild'
import type { MapSea } from './mapTypes'
import { mapSeasOf } from './seaNames'

// Vite hands back the URL of the vendored file as a build asset (hashed, cacheable, and NOT in the
// JS bundle — `npm run build` emits it as dist/assets/world-110m-*.json). `data/` belongs to
// another agent; this module only ever reads it.
import worldUrl from '../../data/world-110m.json?url'
// The seas are 7.7 KB, so they ride INSIDE this lazy chunk as text rather than costing a second
// round trip: `?raw` is a string at build time, parsed once here, and never in the main bundle.
import seasRaw from '../../data/seas.json?raw'

/** What a chart is handed once the world's furniture has arrived. */
export interface Backdrop {
  readonly coast: CoastlineData
  readonly seas: readonly MapSea[]
}

/** Fetch the vendored world file, build the path, and read the seas. One network read per
 *  session; the browser cache handles the rest. */
export async function loadBackdrop(signal?: AbortSignal): Promise<Backdrop> {
  const response = await fetch(worldUrl, { signal })
  if (!response.ok) throw new Error(`coastline: ${response.status} ${response.statusText}`)
  const coast = buildCoastline(await response.json())
  const seas = mapSeasOf(JSON.parse(seasRaw))
  return { coast, seas }
}

// THE COASTLINE LOADER — the one part of the coastline that touches the network.
//
// It is separated from ./coastlineBuild.ts on purpose: the builder is pure (points in, path out)
// and can therefore be run and MEASURED outside a browser, while this file owns the `?url` import,
// which only a bundler can resolve. Keeping the two apart is what let the rendered path size in
// docs be a measured number instead of an estimate.

import { buildCoastline, type CoastlineData } from './coastlineBuild'

// Vite hands back the URL of the vendored file as a build asset (hashed, cacheable, and NOT in the
// JS bundle — `npm run build` emits it as dist/assets/world-110m-*.json). `data/` belongs to
// another agent; this module only ever reads it.
import worldUrl from '../../../data/world-110m.json?url'

/** Fetch the vendored world file and build the path. One network read per session; the browser
 *  cache handles the rest. */
export async function loadCoastline(signal?: AbortSignal): Promise<CoastlineData> {
  const response = await fetch(worldUrl, { signal })
  if (!response.ok) throw new Error(`coastline: ${response.status} ${response.statusText}`)
  return buildCoastline(await response.json())
}

export type { CoastlineData }

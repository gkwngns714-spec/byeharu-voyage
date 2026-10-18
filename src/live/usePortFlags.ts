import { useMemo } from 'react'
import { portNationOf, useWorld } from './worldStore'

// 0143 (docs/INFLUENCE.md D14) — the map's flags, read through the one allegiance the store holds
// (`world.allegiance`, through `portNationOf`). Since 2026-10-18 the value is the holder's NATION
// CODE, and the chart's names draw that nation's bundled flag (src/chart/LabelsLayer.tsx, through
// the design system's `flagSrc`) — the same picture PortFlag puts beside a city's name in a tray.

/** Every harbour's holder by port code, for the map's names. Null when off, so the chart draws
 *  exactly what it did; a harbour no country holds (or not yet read) is simply absent. */
export function usePortFlags(on: boolean): ReadonlyMap<string, string> | null {
  const allegiance = useWorld((s) => s.allegiance)
  return useMemo(() => {
    if (!on) return null
    const flags = new Map<string, string>()
    for (const port of Object.keys(allegiance)) {
      const nation = portNationOf(allegiance, port)?.nation
      if (nation) flags.set(port, nation)
    }
    return flags
  }, [on, allegiance])
}

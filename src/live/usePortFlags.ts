import { useMemo } from 'react'
import { useWorld } from './worldStore'

// 0143 (docs/INFLUENCE.md D14) — the map's flags, read through the one allegiance the store holds
// (`world.allegiance`); a city's title line draws its flag with CityFlag.

/** Every harbour's flag character by port code, for the map's names while the Regions filter is on
 *  (D14: the map stays clean otherwise). Null when off, so the chart draws exactly what it did. */
export function usePortFlags(on: boolean): ReadonlyMap<string, string> | null {
  const allegiance = useWorld((s) => s.allegiance)
  const nationByCode = useWorld((s) => s.nationByCode)
  return useMemo(() => {
    if (!on) return null
    const flags = new Map<string, string>()
    for (const a of Object.values(allegiance)) {
      const flag = a.nation ? nationByCode[a.nation]?.flag_char : undefined
      if (flag) flags.set(a.port, flag)
    }
    return flags
  }, [on, allegiance, nationByCode])
}

import { useEffect, useSyncExternalStore } from 'react'
import { askFlag, flagSymbolId, flagSymbolOf, flagsVersion, subscribeFlags } from './flagSymbolStore'

// The chart's flag <defs> — one <symbol> per nation. What a symbol is, where it comes from and why
// it is one per nation: ./flagSymbolStore.ts.

/** The chart's `<defs>` of flags, for the nations `codes` names. One per nation, however many
 *  names carry it. */
export function MapFlagDefs({ codes }: { codes: readonly string[] }) {
  useSyncExternalStore(subscribeFlags, flagsVersion)
  const key = [...new Set(codes)].sort().join(',')
  useEffect(() => {
    for (const code of key.split(',')) if (code) askFlag(code)
  }, [key])
  return (
    <defs data-testid="map-flag-symbols">
      {key
        .split(',')
        .filter((code) => flagSymbolOf(code))
        .map((code) => {
          const s = flagSymbolOf(code)!
          return (
            <symbol
              key={code}
              id={flagSymbolId(code)}
              viewBox={s.viewBox}
              preserveAspectRatio="xMidYMid meet"
              overflow="visible"
              dangerouslySetInnerHTML={{ __html: s.body }}
            />
          )
        })}
    </defs>
  )
}

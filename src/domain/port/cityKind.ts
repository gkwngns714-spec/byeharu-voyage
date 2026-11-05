import type { TKey } from '../../lib/i18n/translate'
import { ISLAND_PORTS } from './islandPorts'

// WHAT A HARBOUR IS: ONE FUNCTION, ONE PLACE (owner order 2026-11-06: *"show what they are, if they are city, capital city,
// island city etc."*). Three facts, each from its one authority, are folded into one plain label:
//   * CAPITAL: the nation's `capital` port code (SnapshotNation.capital) is this port's code;
//   * SIZE:    the served `size_tier` (0058: 5 = a great entrepot, 3 = a working port, 2 = a small harbour). The great ones
//              are a City; the working and small ones are a Town (the fewest words that say it);
//   * ISLAND:  `ISLAND_PORTS` (islandPorts.ts), the one authored list. The client holds the served name, so it matches on it.
// A capital is a Capital whatever its size. The label is one of six: Capital, Island capital, City, Island city, Town,
// Island town. The Stats list, the Stats city page and the City page all read it from here.

export interface CityKind {
  capital: boolean
  island: boolean
  /** 'city' is size_tier 5; every smaller harbour is a 'town'. A capital's size is not drawn. */
  size: 'city' | 'town'
  /** The dictionary key of the whole label. */
  label: TKey
}

export interface KindPort {
  code: string
  name: string
  size_tier: number
  nation: string | null
}

const ISLAND_NAMES: ReadonlySet<string> = new Set(Object.values(ISLAND_PORTS))
const GREAT_TIER = 5

export const isIslandPort = (name: string): boolean => ISLAND_NAMES.has(name)

export function cityKind(port: KindPort, nationByCode: Readonly<Record<string, { capital: string | null }>>): CityKind {
  const capital = port.nation !== null && nationByCode[port.nation]?.capital === port.code
  const island = isIslandPort(port.name)
  const size = port.size_tier >= GREAT_TIER ? 'city' : 'town'
  const label: TKey = capital
    ? island ? 'port.kindIslandCapital' : 'port.kindCapital'
    : size === 'city'
      ? island ? 'port.kindIslandCity' : 'port.kindCity'
      : island ? 'port.kindIslandTown' : 'port.kindTown'
  return { capital, island, size, label }
}

/** The Kind filter's choices, as the facets they pick: any capital, any city, any town, any island harbour. */
export const KIND_FILTERS = ['capital', 'city', 'town', 'island'] as const
export type KindFilter = (typeof KIND_FILTERS)[number]

export function matchesKind(kind: CityKind, f: KindFilter): boolean {
  return f === 'capital' ? kind.capital : f === 'island' ? kind.island : f === 'city' ? !kind.capital && kind.size === 'city' : !kind.capital && kind.size === 'town'
}

/** The dictionary key of a Kind filter's word. */
export const kindFilterWord = (f: KindFilter): TKey =>
  ({ capital: 'port.kindCapital', city: 'port.kindCity', town: 'port.kindTown', island: 'port.kindIsland' } as const satisfies Record<KindFilter, TKey>)[f]

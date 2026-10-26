import type { TKey } from '../../lib/i18n/translate'
import type { StatsArea, StatsCityRow, StatsMerchantRow } from '../../lib/rpc'

// THE STATS FACES' FILTERS AND SORTS (owner row 228, 2026-10-26: *"also create filter for all parts in stats, for
// example in cities such as by area (continents), or by richest, etc"*) — pure, so a spec can pin them without JSX.
// A filter or a sort is a VIEW over what the server served: it never computes a figure. The area of a city is the
// server's (public.region_area, 0241); the order of the eight areas below is only the order of the chips.

export const STATS_AREAS: readonly StatsArea[] = ['europe', 'africa', 'middle_east', 'india', 'se_asia', 'east_asia', 'americas', 'oceania']

/** The dictionary key of an area's word. */
export const areaWord = (a: StatsArea): TKey =>
  ({
    europe: 'stats.areaEurope',
    africa: 'stats.areaAfrica',
    middle_east: 'stats.areaMiddleEast',
    india: 'stats.areaIndia',
    se_asia: 'stats.areaSeAsia',
    east_asia: 'stats.areaEastAsia',
    americas: 'stats.areaAmericas',
    oceania: 'stats.areaOceania',
  } as const satisfies Record<StatsArea, TKey>)[a]

/** "Every one" in a chip row or a picker. */
export const ALL = 'all'

// ── Cities ──────────────────────────────────────────────────────────────────────────────────────
export const CITY_SORTS = ['richest', 'traded', 'invested', 'stock', 'name'] as const
export type CitySort = (typeof CITY_SORTS)[number]

export interface CityFilter {
  area: string
  country: string
  mine: boolean
}

export function filterCities(rows: readonly StatsCityRow[], f: CityFilter): StatsCityRow[] {
  return rows.filter(
    (c) => (f.area === ALL || c.area === f.area) && (f.country === ALL || c.nation === f.country) && (!f.mine || c.mine === true),
  )
}

const cityTraded = (c: StatsCityRow) => (c.sold_1d ?? 0) + (c.bought_1d ?? 0)

/** Biggest first for every figure (an unknown stock last), A→Z for the name; the name breaks every tie. */
export function sortCities(rows: readonly StatsCityRow[], sort: CitySort, nameOf: (c: StatsCityRow) => string): StatsCityRow[] {
  const by = (pick: (c: StatsCityRow) => number) => (a: StatsCityRow, b: StatsCityRow) =>
    pick(b) - pick(a) || nameOf(a).localeCompare(nameOf(b))
  const list = [...rows]
  if (sort === 'name') return list.sort((a, b) => nameOf(a).localeCompare(nameOf(b)))
  if (sort === 'traded') return list.sort(by(cityTraded))
  if (sort === 'invested') return list.sort(by((c) => c.invested ?? 0))
  if (sort === 'stock') return list.sort(by((c) => c.stock ?? -1))
  return list.sort(by((c) => c.purse ?? 0))
}

/** The countries present in a list, as codes (the picker's options). */
export function countriesOf(codes: readonly (string | null | undefined)[]): string[] {
  return [...new Set(codes.filter((c): c is string => typeof c === 'string' && c.length > 0))]
}

// ── Merchants ───────────────────────────────────────────────────────────────────────────────────
export const MERCHANT_SORTS = ['richest', 'earned', 'laps', 'fleet', 'name'] as const
export type MerchantSort = (typeof MERCHANT_SORTS)[number]

export function sortMerchants(rows: readonly StatsMerchantRow[], sort: MerchantSort): StatsMerchantRow[] {
  const col = sort === 'richest' ? 2 : sort === 'fleet' ? 3 : sort === 'earned' ? 4 : 5
  const list = [...rows]
  if (sort === 'name') return list.sort((a, b) => a[0].localeCompare(b[0]))
  return list.sort((a, b) => b[col] - a[col] || a[0].localeCompare(b[0]))
}

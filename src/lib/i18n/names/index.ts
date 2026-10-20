// PROPER NOUNS — one map each (ports, nations, regions, goods, categories, Korean hulls). In
// English every function returns the served name untouched; in Korean, the map's entry or, when
// there is none, the served name (a truthful lesser answer, NO_SPAGHETTI §7C). Officer, captain
// and fleet names are people's and players' and never pass through here.
import { getLocale, type Locale } from '../locale'
import { KO_PORTS } from './ports'
import { KO_GOODS } from './goods'
import { KO_CATEGORIES, KO_CULTURES, KO_HULLS, KO_NATIONS, KO_REGIONS } from './realms'

export type NameKind = 'port' | 'nation' | 'region' | 'good' | 'category' | 'culture' | 'hull'

const KO: Record<NameKind, Readonly<Record<string, string>>> = {
  port: KO_PORTS,
  nation: KO_NATIONS,
  region: KO_REGIONS,
  good: KO_GOODS,
  category: KO_CATEGORIES,
  culture: KO_CULTURES,
  hull: KO_HULLS,
}

/** `key` is the map's key (a code, or for ports and hulls the served name); `served` is what the
 *  server said, printed in English and whenever Korean has no entry. */
export function properName(kind: NameKind, key: string, served: string, locale: Locale = getLocale()): string {
  return locale === 'ko' ? (KO[kind][key] ?? served) : served
}

export const koPortName = (name: string) => KO_PORTS[name]
export const koNationName = (code: string) => KO_NATIONS[code]
export const koGoodName = (code: string) => KO_GOODS[code]
export const koCategoryName = (code: string) => KO_CATEGORIES[code]
export const koCultureName = (code: string) => KO_CULTURES[code]
export const koRegionName = (code: string) => KO_REGIONS[code]

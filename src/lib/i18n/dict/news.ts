import { defineDict } from '../define'
import { properName } from '../names'
import { tFor } from '../translate'
import type { Locale } from '../locale'
import { formatDucats, formatInt } from '../../format'
import type { NewsMark } from '../../rpc'

// THE CHART NEWS (0279, owner row 216): the words a pressed marker speaks — one template per kind, in the
// design's own spelling (docs/NEWS_AND_MARKERS.md §2.2). The SERVER serves the figures and the names in
// `detail`; `newsHeadline` fills this dict's template with them, so the client computes nothing the server
// could serve — it only words what was served. Shortest plain words (owner 2026-10-25).
//
// A marker of an unmapped kind prints its kind — the truthful lesser answer (NO_SPAGHETTI §7C), the same
// rule properName keeps. The card's own labels live here too: the card is this file's only caller.

export const newsDict = defineDict({
  en: {
    cardLabel: 'News',
    more: '+{n} more',
    openCity: 'Open city',
    updateClosed: 'Update: Economy closed',
    updateOpen: 'Update: Economy open',
    sold: '{company} sold {qty} {good} at {city}: {n}',
    soldNoCity: '{company} sold {qty} {good}: {n}',
    bought: '{company} bought {qty} {good} at {city}: {n}',
    boughtNoCity: '{company} bought {qty} {good}: {n}',
    broke: '{company} is broke',
  },
  ko: {
    cardLabel: '소식',
    more: '+{n}개 더',
    openCity: '도시 열기',
    updateClosed: '업데이트: 경제 폐쇄',
    updateOpen: '업데이트: 경제 개방',
    sold: '{company}, {city}에 {good} {qty} 판매: {n}',
    soldNoCity: '{company}, {good} {qty} 판매: {n}',
    bought: '{company}, {city}에서 {good} {qty} 구매: {n}',
    boughtNoCity: '{company}, {good} {qty} 구매: {n}',
    broke: '{company} 파산',
  },
})

/** The one headline a marker speaks, in one locale: the dict's template filled with the SERVER's detail
 *  (`company` as served, `good` and `city` through properName — the one authority for Korean names — and
 *  the figures through lib/format). Pure, so tests/newsMarks.spec.ts proves it in Node. */
export function newsHeadline(mark: NewsMark, locale: Locale): string {
  const t = tFor(locale)
  const d = mark.detail ?? {}
  const good = (): string =>
    typeof d.good === 'string' ? properName('good', d.good, d.good_name ?? d.good, locale) : ''
  const city = (): string =>
    typeof d.city_name === 'string' ? properName('port', d.city_name, d.city_name, locale) : ''

  switch (mark.kind) {
    case 'ECONOMY_SWITCH':
      return t(d.closed ? 'news.updateClosed' : 'news.updateOpen')
    case 'SOLD':
      return typeof d.city_name === 'string'
        ? t('news.sold', {
            company: d.company ?? '',
            qty: formatInt(d.qty ?? 0),
            good: good(),
            city: city(),
            n: formatDucats(d.total ?? 0),
          })
        : t('news.soldNoCity', { company: d.company ?? '', qty: formatInt(d.qty ?? 0), good: good(), n: formatDucats(d.total ?? 0) })
    case 'BOUGHT':
      return typeof d.city_name === 'string'
        ? t('news.bought', {
            company: d.company ?? '',
            qty: formatInt(d.qty ?? 0),
            good: good(),
            city: city(),
            n: formatDucats(d.total ?? 0),
          })
        : t('news.boughtNoCity', { company: d.company ?? '', qty: formatInt(d.qty ?? 0), good: good(), n: formatDucats(d.total ?? 0) })
    case 'NPC_REFOUNDED':
      return t('news.broke', { company: d.company ?? '' })
    default:
      return mark.kind
  }
}

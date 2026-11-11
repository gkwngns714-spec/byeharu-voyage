import { properName, type Locale } from '../lib/i18n'
import type { NewsItem, NewsWord } from '../lib/rpc'

// A NEWS HEADLINE IN THE READER'S LANGUAGE (0347, owner row 216). The server keeps ONE template per kind in each language
// (public.news_kinds: "New harbour: {city}" / "새 항구: {city}") and the words of each item (world_news.detail.words); this fills the
// one with the other. A word is plain text, the two languages, or a proper name localised by the one name map (properName). No kind
// is named here: a new kind is a server row, never a branch in this file.

/** One word of a headline, in `locale`. */
export function newsWord(w: NewsWord | undefined, locale: Locale): string {
  if (w === undefined || w === null) return ''
  if (typeof w === 'string' || typeof w === 'number') return String(w)
  if ('en' in w) return locale === 'ko' ? w.ko : w.en
  return properName(w.kind, w.key, w.name, locale)
}

/** The item's headline, its template filled. A word the item does not carry reads as nothing rather than as `{name}`. */
export function newsHeadline(item: NewsItem, locale: Locale): string {
  const template = locale === 'ko' ? item.ko : item.en
  return template.replace(/\{([a-z_]+)\}/g, (_, key: string) => newsWord(item.detail.words?.[key], locale))
}

/** "before → after", when the item says a figure moved; null when it does not. */
export function newsMove(item: NewsItem, locale: Locale): string | null {
  const { before, after } = item.detail
  if (before === undefined || after === undefined) return null
  return `${newsWord(before, locale)} → ${newsWord(after, locale)}`
}

/** An item's instant in ms (null when it does not parse). */
export const newsAtMs = (item: NewsItem): number | null => {
  const ms = Date.parse(item.at)
  return Number.isFinite(ms) ? ms : null
}

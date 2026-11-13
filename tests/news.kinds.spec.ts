// PURE UNIT SPEC — the five news kinds of migration 0362 (owner row 216; docs/NEWS_AND_MARKERS.md N4, N5 and the gift of N6). No browser, no server.
//
// THE CLIENT NAMES NO KIND: a headline is the server's template (a row of public.news_kinds, one in each language) filled with the words the writer put in
// world_news.detail.words (src/live/newsWords.ts). So what must hold for a new kind is read here from the migration itself:
//   * each of the five kinds has its row, at importance 2, with an English and a Korean template naming the SAME words;
//   * filled with the words its writer gives (a company's name as text, a figure as text with thousands commas, a good and a city as proper names the client
//     localises), each headline reads right in English and in Korean, and no `{name}` is left unfilled;
//   * a spike's card line is "before → after";
//   * proof 64 (scripts/db/proofs/64_news_kinds.sql) rebuilds the old bodies from 0362's own hunks: every hunk of the migration stands in the proof word for word.

import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { properName } from '../src/lib/i18n'
import { newsHeadline, newsMove } from '../src/live/newsWords'
import type { NewsItem, NewsWord } from '../src/lib/rpc'

const MIG = path.resolve('supabase', 'migrations', '20260818000362_the_news_tells_of_trades_prices_pirates_and_gifts.sql')
const PROOF = path.resolve('scripts', 'db', 'proofs', '64_news_kinds.sql')
const mig = readFileSync(MIG, 'utf8').replaceAll('\r', '')

const kinds = Object.fromEntries(
  [...mig.matchAll(/^ {2}\('([A-Z_]+)',\s+(\d), '([a-z]+)',\s+'([^']+)',\s+'([^']+)'\)[,;]$/gm)].map((m) => [m[1], { importance: Number(m[2]), scope: m[3], en: m[4], ko: m[5] }]),
)
const city: NewsWord = { kind: 'port', key: 'Lisbon', name: 'Lisbon' }
const good: NewsWord = { kind: 'good', key: 'pepper', name: 'Pepper' }
// the words each writer gives (public.news_big_trade, news_price_spikes, news_pirates, news_gift)
const WORDS: Record<string, Record<string, NewsWord>> = {
  BIG_SALE: { company: 'Casa Nova', qty: '120', good, city, n: '300,000' },
  BIG_BUY: { company: 'Casa Nova', qty: '120', good, city, n: '300,000' },
  PRICE_SPIKE: { good, city, p: '+25%' },
  PIRATES: { company: 'Casa Nova', n: '52,000' },
  CAPITAL_GIFT: { capital: city, company: 'Casa Nova', n: '40,000' },
}
const item = (kind: string, extra: Record<string, unknown> = {}): NewsItem => ({
  id: 1,
  at: '2026-11-13T00:00:00Z',
  kind,
  importance: kinds[kind].importance,
  scope: kinds[kind].scope as NewsItem['scope'],
  port_id: null,
  good_id: null,
  company_id: null,
  power: null,
  en: kinds[kind].en,
  ko: kinds[kind].ko,
  detail: { words: WORDS[kind], ...extra },
})

test('the five kinds of 0362 are rows with an English and a Korean template naming the same words', () => {
  expect(Object.keys(kinds).sort()).toEqual(['BIG_BUY', 'BIG_SALE', 'CAPITAL_GIFT', 'PIRATES', 'PRICE_SPIKE'])
  for (const [kind, k] of Object.entries(kinds)) {
    const names = (s: string) => [...s.matchAll(/\{([a-z_]+)\}/g)].map((m) => m[1]).sort()
    expect(k.importance, kind).toBe(2)
    expect(names(k.ko), `${kind}: the Korean template names other words than the English`).toEqual(names(k.en))
    expect(Object.keys(WORDS[kind]).sort(), `${kind}: the writer's words are the template's`).toEqual(names(k.en))
    expect(k.en.length, kind).toBeLessThanOrEqual(80)
    expect(k.ko.length, kind).toBeLessThanOrEqual(80)
  }
})

test('each headline reads right in English and in Korean, with every word filled', () => {
  const lis = properName('port', 'Lisbon', 'Lisbon', 'ko')
  const pep = properName('good', 'pepper', 'Pepper', 'ko')
  expect(newsHeadline(item('BIG_SALE'), 'en')).toBe('Casa Nova sold 120 Pepper at Lisbon: 300,000')
  expect(newsHeadline(item('BIG_SALE'), 'ko')).toBe(`Casa Nova, ${lis}에 ${pep} 120 판매: 300,000`)
  expect(newsHeadline(item('BIG_BUY'), 'en')).toBe('Casa Nova bought 120 Pepper at Lisbon: 300,000')
  expect(newsHeadline(item('BIG_BUY'), 'ko')).toBe(`Casa Nova, ${lis}에서 ${pep} 120 구매: 300,000`)
  expect(newsHeadline(item('PRICE_SPIKE'), 'en')).toBe('Pepper at Lisbon +25% in an hour')
  expect(newsHeadline(item('PRICE_SPIKE'), 'ko')).toBe(`${lis} ${pep} 1시간 +25%`)
  expect(newsHeadline(item('PIRATES'), 'en')).toBe('Pirates took 52,000 from Casa Nova')
  expect(newsHeadline(item('PIRATES'), 'ko')).toBe('해적이 Casa Nova에서 52,000 약탈')
  expect(newsHeadline(item('CAPITAL_GIFT'), 'en')).toBe('Lisbon gave Casa Nova 40,000')
  expect(newsHeadline(item('CAPITAL_GIFT'), 'ko')).toBe(`${lis}, Casa Nova에 40,000 지원`)
  for (const kind of Object.keys(kinds)) for (const locale of ['en', 'ko'] as const) expect(newsHeadline(item(kind), locale), `${kind} ${locale}`).not.toMatch(/[{}]/)
})

test('a spike says before → after on its card; a trade says none', () => {
  expect(newsMove(item('PRICE_SPIKE', { before: 412, after: 506.5 }), 'en')).toBe('412 → 506.5')
  expect(newsMove(item('BIG_SALE'), 'en')).toBeNull()
})

test('every hunk of migration 0362 stands in proof 64 word for word, and the proof pins no body by digest', () => {
  const proof = readFileSync(PROOF, 'utf8').replaceAll('\r', '')
  const re = /\('([a-z_.]+\([a-z ,]*\))', (\d+),\n\$o\$([\s\S]*?)\$o\$,\n\$n\$([\s\S]*?)\$n\$\)/g
  const hunks = [...mig.matchAll(re)].map((m) => ({ fn: m[1], n: m[2], old: m[3], new: m[4] }))
  expect(hunks, 'migration 0362 holds 7 hunks').toHaveLength(7)
  const missing = hunks.filter((h) => !proof.includes(`('${h.fn}', ${h.n}, $h$${h.old}$h$, $h$${h.new}$h$)`)).map((h) => `${h.fn} #${h.n}`)
  expect(missing, `proof 64 does not hold these hunks of 0362 word for word: ${missing.join(', ')}`).toEqual([])
  expect(proof.match(/^ {2}\('[a-z_.]+\([a-z ,]*\)', \d+, \$h\$/gm) ?? []).toHaveLength(7)
  expect(proof.match(/'[0-9a-f]{32}'/g) ?? [], 'proof 64 pins a body by an md5 literal').toEqual([])
  expect(proof).toContain('does not come back to the live body')
})

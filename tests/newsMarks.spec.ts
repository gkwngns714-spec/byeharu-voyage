// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE NEWS DOTS (0279, owner row 216) — pure geometry and the one headline, proved in Node without a
// browser. `newsMarksModel` is what BOTH chart painters call; the two chart models never see a mark, so
// the series cannot change because of one — that is the "old vs new digest" read in code, asserted here.
// ═══════════════════════════════════════════════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test'
import { newsMarksModel, MARKS_CLUSTER_PX, MARK_R } from '../src/components/ui/newsMarksModel'
import { seriesChartModel } from '../src/components/ui/seriesChartModel'
import { priceChartModel } from '../src/components/ui/priceChartModel'
import { newsHeadline } from '../src/lib/i18n/dict/news'
import type { NewsMark } from '../src/lib/rpc'

const PLOT = { x: 48, y: 10, w: 284, h: 120 }
const WINDOW = { fromMs: Date.parse('2026-10-26T00:00:00Z'), toMs: Date.parse('2026-10-27T00:00:00Z') }

const mark = (over: Partial<NewsMark>): NewsMark => ({
  id: '00000000-0279-4000-8000-000000000001',
  at: '2026-10-26T12:00:00Z',
  kind: 'SOLD',
  importance: 2,
  scope: 'port',
  port_id: null,
  good_id: null,
  company_id: null,
  detail: {},
  ...over,
})

test('a mark stands on the time axis at its own instant, on the floor line', () => {
  const dots = newsMarksModel(
    [mark({ at: '2026-10-26T00:00:00Z' }), mark({ at: '2026-10-26T12:00:00Z', id: 'b' }), mark({ at: '2026-10-27T00:00:00Z', id: 'c' })],
    PLOT,
    WINDOW,
  )
  expect(dots.map((d) => d.x)).toEqual([PLOT.x, PLOT.x + PLOT.w / 2, PLOT.x + PLOT.w])
  expect(dots.every((d) => d.y === PLOT.y + PLOT.h)).toBe(true)
  expect(dots.every((d) => d.r === MARK_R)).toBe(true)
  expect(dots.every((d) => d.count === 1 && d.items.length === 1)).toBe(true)
})

test('importance 3 draws accent, 1-2 muted — the painter reads the tone, never the number', () => {
  const dots = newsMarksModel(
    [mark({ importance: 1 }), mark({ importance: 3, at: '2026-10-26T15:00:00Z', id: 'b' })],
    PLOT,
    WINDOW,
  )
  expect(dots).toHaveLength(2)
  expect(dots[0].tone).toBe('muted')
  expect(dots[1].tone).toBe('accent')
})

test('dots closer than 12 px merge into one dot with a count and the highest importance', () => {
  // two marks 15 minutes apart on a one-day window stand ~3 px apart: one dot, count 2, newest first
  const a = mark({ at: '2026-10-26T12:00:00Z', importance: 2 })
  const b = mark({ at: '2026-10-26T12:15:00Z', importance: 3, id: 'b' })
  const dots = newsMarksModel([a, b], PLOT, WINDOW)
  expect(dots).toHaveLength(1)
  expect(dots[0].count).toBe(2)
  expect(dots[0].items.map((m) => m.id)).toEqual(['b', a.id]) // newest first
  expect(dots[0].importance).toBe(3)
  expect(dots[0].tone).toBe('accent')
})

test('dots at or beyond the cluster distance stay two dots', () => {
  const t = (minutes: number) => new Date(Date.parse('2026-10-26T12:00:00Z') + minutes * 60_000).toISOString()
  const pxPerMin = PLOT.w / (24 * 60) // one day across the plot
  const minutes = Math.ceil(MARKS_CLUSTER_PX / pxPerMin)
  const dots = newsMarksModel([mark({}), mark({ at: t(minutes), id: 'b' })], PLOT, WINDOW)
  expect(dots).toHaveLength(2)
  expect(dots[0].x + MARKS_CLUSTER_PX).toBeLessThanOrEqual(dots[1].x)
})

test('a mark outside the drawn window keeps its true x and is flagged out', () => {
  const dots = newsMarksModel([mark({ at: '2026-10-25T12:00:00Z' })], PLOT, WINDOW)
  expect(dots[0].inWindow).toBe(false)
  expect(dots[0].x).toBeLessThan(PLOT.x)
  const inside = newsMarksModel([mark({})], PLOT, WINDOW)
  expect(inside[0].inWindow).toBe(true)
})

test('the series geometry is a pure function of the served series alone — marks cannot change it', () => {
  // the digest: the two chart models know nothing of marks; computing dots off their plot and window
  // leaves every field of the model exactly as a fresh computation makes it.
  const points = [
    { atMs: Date.parse('2026-10-26T00:00:00Z'), value: 10 },
    { atMs: Date.parse('2026-10-26T06:00:00Z'), value: 20 },
    { atMs: Date.parse('2026-10-26T12:00:00Z'), value: 15 },
    { atMs: Date.parse('2026-10-27T00:00:00Z'), value: 25 },
  ]
  const series = seriesChartModel(points)
  if (!series) throw new Error('series model refused')
  const dots = newsMarksModel([mark({})], series.plot, series.window)
  expect(dots.length).toBeGreaterThan(0)
  expect(seriesChartModel(points)).toEqual(series) // byte-identical with or without marks

  const pricePoints = [
    { at: '2026-10-26T00:00:00Z', ask: 10, bid: 9 },
    { at: '2026-10-26T06:00:00Z', ask: 20, bid: 19 },
    { at: '2026-10-26T12:00:00Z', ask: 15, bid: 14 },
    { at: '2026-10-27T00:00:00Z', ask: 25, bid: 24 },
  ]
  const price = priceChartModel(pricePoints, 6 * 3600, Date.parse('2026-10-27T00:00:00Z'))
  if (!price) throw new Error('price model refused')
  newsMarksModel([mark({})], price.plot, price.window)
  expect(priceChartModel(pricePoints, 6 * 3600, Date.parse('2026-10-27T00:00:00Z'))).toEqual(price)
})

test('the one headline: each kind speaks the design’s words in both languages, names localised, figures formatted', () => {
  const COIN = ' 🪙' // formatDucats' own suffix — the headline composes the one formatter, it does not re-spell money
  const sold = mark({
    kind: 'SOLD',
    detail: { company: 'Casa da India', good: 'black-pepper', good_name: 'Black pepper', qty: 500, total: 300000, city: 'LIS', city_name: 'Lisbon' },
  })
  expect(newsHeadline(sold, 'en')).toBe(`Casa da India sold 500 Black pepper at Lisbon: 300,000${COIN}`)
  expect(newsHeadline(sold, 'ko')).toBe(`Casa da India, 리스본에 후추 500 판매: 300,000${COIN}`)

  const bought = mark({
    kind: 'BOUGHT',
    detail: { company: 'Casa da India', good: 'silk-cloth', good_name: 'Silk cloth', qty: 400, total: 300000, city: 'OPO', city_name: 'Porto' },
  })
  expect(newsHeadline(bought, 'en')).toBe(`Casa da India bought 400 Silk cloth at Porto: 300,000${COIN}`)
  expect(newsHeadline(bought, 'ko')).toBe(`Casa da India, 포르투에서 비단 400 구매: 300,000${COIN}`)

  // a pre-0277 trade has no city: the shorter template speaks, and it still reads
  const oldSale = mark({ kind: 'SOLD', detail: { company: 'Casa', good: 'wine', good_name: 'Wine', qty: 10, total: 5000 } })
  expect(newsHeadline(oldSale, 'en')).toBe(`Casa sold 10 Wine: 5,000${COIN}`)
  expect(newsHeadline(oldSale, 'ko')).toBe(`Casa, 포도주 10 판매: 5,000${COIN}`)

  const broke = mark({ kind: 'NPC_REFOUNDED', detail: { company: 'Casa', amount: 12000, week: 1 } })
  expect(newsHeadline(broke, 'en')).toBe('Casa is broke')
  expect(newsHeadline(broke, 'ko')).toBe('Casa 파산')

  const closed = mark({ kind: 'ECONOMY_SWITCH', detail: { closed: true } })
  expect(newsHeadline(closed, 'en')).toBe('Update: Economy closed')
  expect(newsHeadline(closed, 'ko')).toBe('업데이트: 경제 폐쇄')
  expect(newsHeadline(mark({ kind: 'ECONOMY_SWITCH', detail: { closed: false }, id: 'b' }), 'en')).toBe('Update: Economy open')

  // a kind without words prints its kind — the truthful lesser answer
  expect(newsHeadline(mark({ kind: 'SOMETHING_NEW', id: 'c' }), 'en')).toBe('SOMETHING_NEW')
})

// PURE UNIT SPEC — the news law of the chain and the dots' geometry (0347, owner row 216; docs/NEWS_AND_MARKERS.md).
//
// THE LAW (§2.2, decided by default): every migration after 0347 tells the world it happened — ONE `public.news_update(` call (its
// "Update: {title}" row, idempotent by its number) — or says plainly that it is not news with a `-- news: none` line. A file with
// neither fails here, so no update slips past the News face and the charts' dots. 0347 itself posts its own row.
// THE DOTS: newsMarksModel.ts (pure): a mark stands on the floor at its instant, none outside the axis, marks closer than a press target (44 px) are one
// dot, newest first, at the highest importance; each dot's target is 44 px square, inside the chart's box, and no two targets overlap. THE WORDS: newsWords.ts fills a template from the item's words, in each language.

import { test, expect } from '@playwright/test'
import { readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { NEWS_HIT_PX, newsMarksModel } from '../src/components/ui/newsMarksModel'
import { newsHeadline, newsMove } from '../src/live/newsWords'
import type { NewsItem } from '../src/lib/rpc'

const DIR = path.resolve('supabase', 'migrations')
const FIRST = 347

test('every migration from 0347 on posts its UPDATE row once, or says it is not news', () => {
  const files = readdirSync(DIR).filter((f) => /^\d{14}_.+\.sql$/.test(f))
  const checked = files.filter((f) => Number(f.slice(8, 14)) >= FIRST)
  expect(checked.length, 'no migration from 0347 on — the law reads nothing').toBeGreaterThan(0)
  const bad: string[] = []
  for (const f of checked) {
    const sql = readFileSync(path.join(DIR, f), 'utf8')
    const calls = (sql.match(/\bselect\s+public\.news_update\(|\bperform\s+public\.news_update\(/gi) ?? []).length
    const none = /^--\s*news:\s*none\b/m.test(sql)
    if (calls === 0 && !none) bad.push(`${f}: no public.news_update( call and no "-- news: none" line`)
    if (calls > 1) bad.push(`${f}: ${calls} news_update calls — one row per file`)
    if (calls > 0 && none) bad.push(`${f}: both a news_update call and "-- news: none"`)
  }
  expect(bad, bad.join('\n')).toEqual([])
})

const plot = { x: 10, y: 5, w: 200, h: 100 }
const axis = { fromMs: 0, toMs: 1000 }

test('a dot stands on the floor at its instant; none outside the axis; close ones are one dot, newest first, at the highest importance', () => {
  const dots = newsMarksModel(
    [
      { id: 1, atMs: 0, importance: 1 },
      { id: 2, atMs: 500, importance: 1 },
      { id: 3, atMs: 520, importance: 3 }, // 4 px from id 2: one dot
      { id: 4, atMs: 1000, importance: 2 },
      { id: 5, atMs: 1001, importance: 3 }, // outside
      { id: 6, atMs: -1, importance: 3 }, // outside
    ],
    plot,
    axis,
  )
  expect(dots.map((d) => d.ids)).toEqual([[1], [3, 2], [4]])
  expect(dots[0].x).toBe(10)
  expect(dots[2].x).toBe(210)
  expect(dots.every((d) => d.y === 105)).toBe(true)
  expect(dots[1].importance).toBe(3)
  expect(Math.abs(dots[1].x - 112)).toBeLessThan(0.01)
  // two marks NEWS_HIT_PX apart are two dots; a hair closer and they are one
  const at = (px: number) => (px / plot.w) * 1000
  const apart = newsMarksModel([{ id: 1, atMs: 0, importance: 1 }, { id: 2, atMs: at(NEWS_HIT_PX), importance: 1 }], plot, axis)
  expect(apart).toHaveLength(2)
  expect(newsMarksModel([{ id: 1, atMs: 0, importance: 1 }, { id: 2, atMs: at(NEWS_HIT_PX - 1), importance: 1 }], plot, axis)).toHaveLength(1)
  // without a box a target is centred on its mark
  expect(dots.every((d) => d.hitX === d.x && d.hitY === d.y)).toBe(true)
  expect(newsMarksModel([{ id: 1, atMs: 0, importance: 1 }], plot, { fromMs: 5, toMs: 5 })).toEqual([])
})

test('a press target is 44 px square: inside the chart box, never over its neighbour, and its mark is inside it', () => {
  expect(NEWS_HIT_PX).toBe(44)
  const half = NEWS_HIT_PX / 2
  // the plot fills its box edge to edge and its floor is 8 px above the box's foot: the worst case for a target
  const tight = { x: 0, y: 0, w: 300, h: 100 }
  const box = { w: 300, h: 108 }
  for (const xs of [[0, 45, 300], [0, 300], [150], [0, 50, 100, 150, 200, 250], [255, 300], [0, 45, 90, 135, 180, 225]]) {
    const dots = newsMarksModel(xs.map((x, i) => ({ id: i + 1, atMs: (x / tight.w) * 1000, importance: 1 })), tight, axis, box)
    expect(dots.length, `marks at ${xs.join(', ')}`).toBe(xs.length)
    dots.forEach((d, i) => {
      const where = `marks at ${xs.join(', ')}, dot ${i}`
      expect(d.hitX - half, where).toBeGreaterThanOrEqual(0)
      expect(d.hitX + half, where).toBeLessThanOrEqual(box.w)
      expect(d.hitY - half, where).toBeGreaterThanOrEqual(0)
      expect(d.hitY + half, where).toBeLessThanOrEqual(box.h)
      expect(Math.abs(d.x - d.hitX), `${where}: the mark is outside its target`).toBeLessThanOrEqual(half)
      expect(Math.abs(d.y - d.hitY), `${where}: the mark is outside its target`).toBeLessThanOrEqual(half)
      if (i > 0) expect(d.hitX - dots[i - 1].hitX, `${where}: its target lies over the one before`).toBeGreaterThanOrEqual(NEWS_HIT_PX)
    })
  }
})

const item = (en: string, ko: string, detail: NewsItem['detail']): NewsItem => ({
  id: 1, at: '2026-11-11T00:00:00Z', kind: 'X', importance: 3, scope: 'world', port_id: null, good_id: null, company_id: null, power: null, en, ko, detail,
})

test('a headline is its kind template filled from the item words, in each language', () => {
  const rel = item('{a} and {b}: now {stance}', '{a}–{b}: {stance}', {
    words: { a: { kind: 'nation', key: 'ESP', name: 'Spain' }, b: { kind: 'nation', key: 'NLD', name: 'Netherlands' }, stance: { en: 'at war', ko: '전쟁' } },
    before: { en: 'rivals', ko: '적대' },
    after: { en: 'at war', ko: '전쟁' },
  })
  expect(newsHeadline(rel, 'en')).toBe('Spain and Netherlands: now at war')
  const ko = newsHeadline(rel, 'ko')
  expect(ko).toContain('–')
  expect(ko).toContain('전쟁')
  expect(ko).not.toContain('{')
  expect(newsMove(rel, 'en')).toBe('rivals → at war')
  expect(newsMove(rel, 'ko')).toBe('적대 → 전쟁')
  expect(newsHeadline(item('Update: {title}', '업데이트: {title}', { words: { title: { en: 'News', ko: '소식' } } }), 'ko')).toBe('업데이트: 소식')
  // a word the item does not carry reads as nothing, never as its {name}
  expect(newsHeadline(item('New harbour: {city}', '새 항구: {city}', {}), 'en')).toBe('New harbour: ')
  expect(newsMove(item('x {a}', 'x {a}', {}), 'en')).toBeNull()
})

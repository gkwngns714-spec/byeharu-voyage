import { test, expect } from '@playwright/test'
import { COUNT_UP_MS, countUpEase, countUpValue } from '../src/components/ui/countUp'
import { flowRanks } from '../src/features/stats/statsFaces'

// THE MOVING FIGURE (owner request 188, 2026-10-20: "no number moving around") — the arithmetic of
// the walk, proved without a browser, and the one rule the Stats tab's ranked bars add to it: the
// server's SIDE decides the tone, never the client's opinion of the number.
//
// PURE SPEC. No `page` fixture, so Playwright runs it as a plain Node process in about a second.

test('a walk starts at the old number and ends exactly on the served one', () => {
  expect(countUpValue(0, 8000, 0)).toBe(0)
  expect(countUpValue(0, 8000, 1)).toBe(8000)
  // past the end, and before the start, are both the ends — a figure never overshoots its answer
  expect(countUpValue(0, 8000, 2)).toBe(8000)
  expect(countUpValue(0, 8000, -1)).toBe(0)
  // and it walks downhill the same way
  expect(countUpValue(8000, 0, 1)).toBe(0)
})

test('it eases OUT: past halfway by the halfway point, and never backwards', () => {
  const half = countUpValue(0, 1000, 0.5)
  expect(half).toBeGreaterThan(500)
  expect(half).toBeLessThan(1000)
  let last = -Infinity
  for (let i = 0; i <= 10; i++) {
    const v = countUpValue(0, 1000, i / 10)
    expect(v).toBeGreaterThanOrEqual(last)
    last = v
  }
  expect(countUpEase(0)).toBe(0)
  expect(countUpEase(1)).toBe(1)
})

test('a figure that is not a number is not walked to — it is simply the answer', () => {
  expect(countUpValue(NaN, 500, 0.5)).toBe(500)
  expect(Number.isNaN(countUpValue(500, NaN, 0.5))).toBe(true)
  // two folds (180 ms) and well under the world's 3-s beat, so a counter is never caught mid-walk
  expect(COUNT_UP_MS).toBeGreaterThan(180)
  expect(COUNT_UP_MS).toBeLessThan(3000)
})

test('a money flow wears the tone of the SERVER\'s side, biggest first', () => {
  const rows = flowRanks([
    { kind: 'SELL', word: 'Goods sold', side: 'moved', ducats: -500 },
    { kind: 'IMPORT_DEMAND', word: 'Import demand', side: 'minted', ducats: 1200 },
    { kind: 'CROWN_TAX', word: 'Crown tax', side: 'removed', ducats: -900 },
  ])
  expect(rows.map((r) => r.id)).toEqual(['IMPORT_DEMAND', 'CROWN_TAX', 'SELL'])
  expect(rows.map((r) => r.tone)).toEqual(['success', 'danger', 'neutral'])
  // green and red mean new money and burned money here; money that only changed hands is neither
  expect(rows[2].note).toBe('moved')
})

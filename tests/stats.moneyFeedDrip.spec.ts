// THE MONEY LOG'S DRIP (MoneyLog.tsx / moneyDrip.ts, owner 223: "it is not updated every second is it?"): a 60-row batch
// is revealed over time, a few rows a second, not at once — and drained within 14 s; a batch landing mid-drip drains
// the remainder on the next tick. Pure queue, no browser.
import { test, expect } from '@playwright/test'
import { DRIP_TICKS, emptyDrip, enqueue, step } from '../src/features/stats/moneyDrip'
import type { MoneyMove } from '../src/lib/rpc'

const batch = (n: number, from = 0, base = Date.parse('2026-10-26T10:00:00Z')): MoneyMove[] =>
  Array.from({ length: n }, (_, i) => ({
    key: `k${from + i}`, at: new Date(base + (from + i) * 100).toISOString(), delta: 10, holder: 'city', kind: 'BUY', who: 'x', word: 'w', own: false,
  }) as unknown as MoneyMove)

test('a 60-row batch is revealed over time, oldest first, not at once', () => {
  let d = enqueue(emptyDrip, batch(60).reverse())
  const sizes: number[] = []
  const order: string[] = []
  for (let t = 0; t < 30 && d.queue.length > 0; t++) {
    const s = step(d)
    sizes.push(s.released.length)
    order.push(...s.released.map((m) => m.key))
    d = s.next
  }
  expect(sizes[0]).toBeLessThan(60)
  expect(sizes.length).toBeGreaterThan(5)
  expect(sizes.length).toBeLessThanOrEqual(DRIP_TICKS)
  expect(sizes.reduce((a, b) => a + b, 0)).toBe(60)
  expect(order).toEqual(Array.from({ length: 60 }, (_, i) => `k${i}`))
})

test('a batch landing mid-drip drains the remainder on the next tick, then starts the new batch', () => {
  let d = enqueue(emptyDrip, batch(60))
  d = step(d).next
  const left = d.queue.length
  d = enqueue(d, batch(60, 60))
  const s = step(d)
  expect(s.released.map((m) => m.key)).toEqual(Array.from({ length: left }, (_, i) => `k${60 - left + i}`))
  expect(step(s.next).released.length).toBeLessThan(60)
})

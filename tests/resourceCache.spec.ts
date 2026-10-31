import { test, expect } from '@playwright/test'
import {
  clearResourceCache,
  invalidateLiveResources,
  invalidateResource,
  msUntilEdge,
  peekResource,
  readResource,
  resourceCacheSize,
  SESSION_MS,
} from '../src/store/resourceCache'
import type { RpcResult } from '../src/lib/rpc/result'

// THE RESOURCE CACHE (src/store/resourceCache.ts, 2026-10-31) — no browser. The desk's old
// servedMemo proofs live on here (a question on the wire is asked once, a fresh answer is reused,
// the edge/force asks again, a refusal and a zero-freshness answer are not kept), plus the three
// rules the cache-once slice added: SESSION entries survive a mutation, finite entries do not,
// and a named verb drops the session entry it changes (a hire drops the officer roster).

const counting = <V>(value: V) => {
  let n = 0
  const ask = async (): Promise<RpcResult<V>> => {
    n += 1
    await new Promise((r) => setTimeout(r, 10))
    return { ok: true, value }
  }
  return { ask, asked: () => n }
}

test.beforeEach(() => clearResourceCache())

test('a question on the wire is asked once, and its fresh answer is reused', async () => {
  const { ask, asked } = counting({ v: 1 })
  const [a, b] = await Promise.all([
    readResource('world.test|a|1', ask, () => 60_000),
    readResource('world.test|a|1', ask, () => 60_000),
  ])
  expect(asked()).toBe(1)
  expect(a).toEqual(b)
  expect(peekResource('world.test|a|1')).toEqual({ v: 1 })
  await readResource('world.test|a|1', ask, () => 60_000)
  expect(asked()).toBe(1)
})

test('the edge (force) asks again and replaces the kept answer', async () => {
  let v = 1
  let n = 0
  const ask = async (): Promise<RpcResult<{ v: number }>> => {
    n += 1
    return { ok: true, value: { v } }
  }
  await readResource('world.test|b|1', ask, () => 60_000)
  v = 2
  await readResource('world.test|b|1', ask, () => 60_000, true)
  expect(n).toBe(2)
  expect(peekResource('world.test|b|1')).toEqual({ v: 2 })
})

test('a refusal is not kept, and neither is an answer with no freshness left', async () => {
  let n = 0
  const refuse = async (): Promise<RpcResult<number>> => {
    n += 1
    return { ok: false, refusal: { code: 'E_TEST', message: 'no', fixes: [] } as never }
  }
  await readResource('world.test|c|1', refuse, () => 60_000)
  expect(peekResource('world.test|c|1')).toBeUndefined()
  await readResource('world.test|c|1', refuse, () => 60_000)
  expect(n).toBe(2)

  const { ask, asked } = counting(7)
  await readResource('world.test|c|2', ask, () => 0)
  expect(peekResource('world.test|c|2')).toBeUndefined()
  await readResource('world.test|c|2', ask, () => 0)
  expect(asked()).toBe(2)
})

test('a SESSION answer survives a mutation; a beat answer does not', async () => {
  const { ask, asked } = counting('catalogue')
  await readResource('worldOfficers', ask, SESSION_MS)
  await readResource('worldMarket|p1', ask, () => 60_000)
  expect(resourceCacheSize()).toBe(2)

  invalidateLiveResources()

  // The catalogue is still there and is not asked again; the market is gone and asks.
  expect(peekResource('worldOfficers')).toBe('catalogue')
  await readResource('worldOfficers', ask, SESSION_MS)
  expect(asked()).toBe(2) // the market's first ask + the catalogue's first ask
  expect(peekResource('worldMarket|p1')).toBeUndefined()
  await readResource('worldMarket|p1', ask, () => 60_000)
  expect(asked()).toBe(3)
})

test('a verb can name the SESSION entry it changes — a hire drops the officer roster', async () => {
  const { ask } = counting('roster')
  await readResource('worldOfficers', ask, SESSION_MS)
  expect(peekResource('worldOfficers')).toBe('roster')

  invalidateLiveResources(['worldOfficers'])
  expect(peekResource('worldOfficers')).toBeUndefined()

  // And a named drop does not take an unrelated session entry with it.
  await readResource('worldOfficers', ask, SESSION_MS)
  await readResource('worldSkills', ask, SESSION_MS)
  invalidateResource('worldOfficers')
  expect(peekResource('worldOfficers')).toBeUndefined()
  expect(peekResource('worldSkills')).toBe('roster')
})

test('an ask that was flying before a mutation cannot write the cache after it', async () => {
  let release: (r: RpcResult<string>) => void = () => undefined
  const slow = () =>
    new Promise<RpcResult<string>>((resolve) => {
      release = resolve
    })
  const before = readResource('worldMarket|p2', slow, () => 60_000)
  invalidateLiveResources()
  release({ ok: true, value: 'computed-before-the-trade' })
  await before
  expect(peekResource('worldMarket|p2')).toBeUndefined()

  const { ask } = counting('after')
  await readResource('worldMarket|p2', ask, () => 60_000)
  expect(peekResource('worldMarket|p2')).toBe('after')
})

test('the edge is the served clock, capped and never negative', () => {
  const at = (now: string, next: string) => msUntilEdge({ now, next_change_at: next })
  expect(at('2026-10-31T10:00:10Z', '2026-10-31T10:01:00Z')).toBe(50_000)
  expect(at('2026-10-31T10:01:00Z', '2026-10-31T10:00:00Z')).toBe(0)
  expect(at('not a date', '2026-10-31T10:01:00Z')).toBe(0)
  expect(at('2026-10-31T10:00:00Z', '2026-11-01T10:00:00Z')).toBe(120_000)
})

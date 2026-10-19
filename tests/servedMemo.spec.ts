import { test, expect } from '@playwright/test'
import { askServed, peekServed } from '../src/live/servedMemo'
import type { RpcResult } from '../src/lib/rpc'

// THE DESK'S MEMORY OF SERVED ANSWERS (src/live/servedMemo.ts, 2026-10-19) — no browser. A question on the
// wire is asked once; a fresh answer is reused without asking; the edge (force) asks again; a refusal and an
// answer past its freshness are not kept.

const counting = <V>(value: V) => {
  let n = 0
  const ask = async (): Promise<RpcResult<V>> => {
    n += 1
    await new Promise((r) => setTimeout(r, 10))
    return { ok: true, value }
  }
  return { ask, asked: () => n }
}

test('a question on the wire is asked once, and its fresh answer is reused', async () => {
  const { ask, asked } = counting({ v: 1 })
  const [a, b] = await Promise.all([askServed('t1', ask, () => 60_000), askServed('t1', ask, () => 60_000)])
  expect(asked()).toBe(1)
  expect(a).toEqual(b)
  expect(peekServed('t1')).toEqual({ v: 1 })
  await askServed('t1', ask, () => 60_000)
  expect(asked()).toBe(1)
})

test('the edge (force) asks again and replaces the kept answer', async () => {
  let v = 1
  let n = 0
  const ask = async (): Promise<RpcResult<{ v: number }>> => {
    n += 1
    return { ok: true, value: { v } }
  }
  await askServed('t2', ask, () => 60_000)
  v = 2
  await askServed('t2', ask, () => 60_000, true)
  expect(n).toBe(2)
  expect(peekServed('t2')).toEqual({ v: 2 })
})

test('a refusal is not kept, and neither is an answer with no freshness left', async () => {
  let n = 0
  const refuse = async (): Promise<RpcResult<number>> => {
    n += 1
    return { ok: false, refusal: { code: 'E_TEST', message: 'no', fixes: [] } as never }
  }
  await askServed('t3', refuse, () => 60_000)
  expect(peekServed('t3')).toBeUndefined()
  await askServed('t3', refuse, () => 60_000)
  expect(n).toBe(2)

  const { ask, asked } = counting(7)
  await askServed('t4', ask, () => 0)
  expect(peekServed('t4')).toBeUndefined()
  await askServed('t4', ask, () => 0)
  expect(asked()).toBe(2)
})

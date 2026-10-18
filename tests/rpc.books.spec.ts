// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BOOKS ADD UP — world.books (0177, docs/COMMAND_DESK.md §3.8, D7)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The Profit face's one read, through the client wrapper, as a company founded at Lisbon: a sale, a purchase and
// wages through public.credit (the one money mover) move today's net by exactly the purse's change, each line under
// its word, and every net is the sum of its lines. It names books so CI's rule S selects it.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, createLocalBackend, setBackend, worldBooks } from '../src/lib/rpc'

let db: LocalDb

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Livros Spec', 'PRT') as result`)
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

const purse = () => db.callAs<number>(`select ducats::bigint as result from public.players where id = public.current_player_id()`)

test('today moves by exactly the purse, each line under its word, and every net is its lines', async () => {
  const before = await worldBooks(7)
  expect(before.ok).toBe(true)
  const p0 = Number(await purse())
  await db.callAs(`select public.credit(public.current_player_id(), 'SELL', 500)::text as result`)
  await db.callAs(`select public.credit(public.current_player_id(), 'BUY', -200)::text as result`)
  await db.callAs(`select public.credit(public.current_player_id(), 'WAGES', -30)::text as result`)
  const after = await worldBooks(7)
  expect(after.ok).toBe(true)
  if (!before.ok || !after.ok) return
  const p1 = Number(await purse())
  expect(after.value.today - before.value.today).toBe(p1 - p0)
  expect(p1 - p0).toBe(270)
  const today = after.value.books[0]
  const word = (w: string) => today.lines.find((l) => l.word === w)?.ducats
  expect(word('Sold')).toBe(500)
  expect(word('Bought')).toBe(-200)
  expect(word('Wages')).toBe(-30)
  for (const d of after.value.books) expect(d.net).toBe(d.lines.reduce((s, l) => s + l.ducats, 0))
  expect(after.value.window).toBe(after.value.books.reduce((s, d) => s + d.net, 0))
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT YOU HOLD — world.holdings (0176, docs/COMMAND_DESK.md §3.7, D6)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The Invest face's one read, through the client wrapper, as a company founded at Lisbon: it reads empty with
// no shares, and reads back exactly the register's rows (planted on this spec's own in-memory world) with the
// town hall's share price. It names holdings so CI's rule S selects it whenever a migration re-defines it.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, createLocalBackend, setBackend, worldHoldings } from '../src/lib/rpc'

let db: LocalDb

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Haveres Spec', 'PRT') as result`)
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('a company with no shares reads empty; planted shares read back as the register holds them', async () => {
  const empty = await worldHoldings()
  expect(empty.ok).toBe(true)
  if (empty.ok) {
    expect(empty.value.rows).toEqual([])
    expect(empty.value.held).toBe(0)
    expect(empty.value.paid).toEqual({ today: 0, yesterday: 0 })
  }
  await db.callAs(`
    insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day)
    select p.id, 'docks', public.current_player_id(), 2, 400, 9, world.game_day() from public.ports p where p.code = 'LIS'
    returning 1 as result`)
  const r = await worldHoldings()
  expect(r.ok).toBe(true)
  if (!r.ok) return
  expect(r.value.rows).toHaveLength(1)
  const row = r.value.rows[0]
  expect(row).toMatchObject({ port: 'LIS', kind: 'docks', shares: 2, paid: 400, owed: 9 })
  const price = await db.callAs<number | null>(
    `select case when $1::int < public.wc_int('works_level_max') then public.works_share_price($1::int) end as result`,
    [row.level],
  )
  expect(row.share_price).toBe(price === null ? null : Number(price))
  expect(r.value.held).toBe(400)
  expect(r.value.owed).toBe(9)
})

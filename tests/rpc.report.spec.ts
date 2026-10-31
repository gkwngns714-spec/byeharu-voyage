// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE REPORT ADDS UP — world.report (0286, docs/COMMAND_REDESIGN.md §4; owner rows 192, 244)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The Report face's one read, through the client wrapper, as a company founded at Lisbon: a sale, a
// purchase and wages through public.credit (the one money mover) move the report's total by exactly
// the purse's change; each kind stands in its design section; the sections are their lines; the
// places are the sections (no double count — these rows name no point, so they read as the ONE
// Earlier place, last). The day axis is one game day, zero-filled, net = the total; the week is the
// served seven. An unknown span is refused, not defaulted.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, createLocalBackend, setBackend, worldReport } from '../src/lib/rpc'

let db: LocalDb

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Relatorio Spec', 'PRT') as result`)
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

const purse = () => db.callAs<number>(`select ducats::bigint as result from public.players where id = public.current_player_id()`)

test('the report sums the ledger by section; the total moves by exactly the purse', async () => {
  const before = await worldReport('day')
  expect(before.ok).toBe(true)
  if (!before.ok) return
  // a new company's starting money is capital (FOUNDING), so it has made nothing yet
  expect(before.value.total).toBe(0)

  const p0 = Number(await purse())
  await db.callAs(`select public.credit(public.current_player_id(), 'SELL', 500)::text as result`)
  await db.callAs(`select public.credit(public.current_player_id(), 'BUY', -200)::text as result`)
  await db.callAs(`select public.credit(public.current_player_id(), 'WAGES', -30)::text as result`)
  const after = await worldReport('day')
  expect(after.ok).toBe(true)
  if (!after.ok) return

  const p1 = Number(await purse())
  expect(after.value.total - before.value.total).toBe(p1 - p0)
  expect(p1 - p0).toBe(270)

  const section = (id: string) => after.value.sections.find((s) => s.id === id)
  expect(section('trade')?.ducats).toBe(300) // Sold 500 + Bought −200
  expect(section('crew')?.ducats).toBe(-30) // Wages
  expect(section('trade')?.lines.find((l) => l.kind === 'SELL')?.ducats).toBe(500)
  expect(section('trade')?.lines.find((l) => l.kind === 'BUY')?.ducats).toBe(-200)
  expect(section('crew')?.lines.find((l) => l.kind === 'WAGES')?.ducats).toBe(-30)
  for (const s of after.value.sections) expect(s.ducats).toBe(s.lines.reduce((n, l) => n + l.ducats, 0))
  expect(after.value.sections.reduce((n, s) => n + s.ducats, 0)).toBe(after.value.total)
  expect(after.value.places.reduce((n, p) => n + p.ducats, 0)).toBe(after.value.total)

  // these rows name no point (credit with no ref event): the ONE Earlier place, and it is last
  expect(after.value.places).toHaveLength(1)
  expect(after.value.places[0].kind).toBe('earlier')
  expect(after.value.places[0].ducats).toBe(270)

  // the day axis: one game day, net = the total
  expect(after.value.days).toHaveLength(1)
  expect(after.value.days[0].game_day).toBe(after.value.game_day)
  expect(after.value.days[0].net).toBe(after.value.total)

  // the week is seven game days and holds the same rows
  const week = await worldReport('week')
  expect(week.ok).toBe(true)
  if (week.ok) {
    expect(week.value.days).toHaveLength(7)
    expect(week.value.total).toBe(after.value.total)
    expect(week.value.days[6].game_day).toBe(week.value.game_day)
  }

  // an unknown span is refused, not defaulted
  const bad = await worldReport('month' as never)
  expect(bad.ok).toBe(false)
})

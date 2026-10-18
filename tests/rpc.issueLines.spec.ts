// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A PLAN IS QUEUED WHOLE — cmd.issue_lines (0175, docs/COMMAND_DESK.md §7.4, D4)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The plan builder's "Queue it once" sends every line of a plan in one call. This spec reads the verb back
// off a real PostgreSQL (the build's own world) through the CLIENT wrapper (`cmdIssueLines`) as a company
// founded at Lisbon, and holds it to the plan's one promise: all of it is queued, or none of it is.
// It names issue_lines so CI's rule S selects it whenever a migration re-defines it.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, cmdIssueLines, createLocalBackend, setBackend } from '../src/lib/rpc'

let db: LocalDb
let fleet: string
let good: string

const queued = () =>
  db.callAs<{ text: string; status: string }[] | null>(
    `select jsonb_agg(jsonb_build_object('text', raw_text, 'status', status) order by seq) as result
       from public.orders where fleet_id = $1::uuid`,
    [fleet],
  )

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Plano Spec', 'PRT') as result`)
  fleet = await db.callAs<string>(`select f.id as result from public.fleets f where f.player_id = public.current_player_id() limit 1`)
  good = await db.callAs<string>(
    `select g.code as result from public.goods g
      where public.port_offers((select id from public.ports where code = 'LIS'), g.id) order by g.code limit 1`,
  )
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('a bad third line queues none, and the refusal names it', async () => {
  const r = await cmdIssueLines(fleet, [
    { text: `BUY ${good} 10` },
    { text: `SELL ${good} ALL AT >= 1` },
    { text: 'SELL nosuchgood ALL' },
    { text: `SELL ${good} ALL` },
  ])
  expect(r.ok).toBe(false)
  if (!r.ok) expect(r.refusal.sentence).toMatch(/^Line 3 \(SELL nosuchgood ALL\):/)
  expect(await queued()).toBeNull()
})

test('a plan larger than the room is refused whole', async () => {
  const max = await db.callAs<number>(`select public.wc_int('order_queue_max') as result`)
  const r = await cmdIssueLines(fleet, Array.from({ length: max + 1 }, () => ({ text: `BUY ${good} 1` })))
  expect(r.ok).toBe(false)
  if (!r.ok) expect(r.refusal.code).toBe('E_QUEUE_FULL')
  expect(await queued()).toBeNull()
})

test('the lines queue together, in order, and a docked fleet starts on the first', async () => {
  const r = await cmdIssueLines(fleet, [
    { text: `BUY ${good} 10 AT <= 100000` },
    { text: `SELL ${good} 5 AT >= 1` },
    { text: `SELL ${good} ALL AT >= 1` },
  ])
  expect(r.ok).toBe(true)
  if (r.ok) expect(r.value.orders).toHaveLength(3)
  const q = (await queued())!
  expect(q.map((o) => o.text)).toEqual([`BUY ${good} 10 AT <= 100000`, `SELL ${good} 5 AT >= 1`, `SELL ${good} ALL AT >= 1`])
  // the docked fleet ran its first line at once (cmd.advance), as after cmd.issue
  expect(q[0].status).not.toBe('pending')
})

test('another company\'s fleet is refused', async () => {
  const other = await db.callAs<string>(`select f.id as result from public.fleets f where f.player_id <> public.current_player_id() limit 1`)
  const r = await cmdIssueLines(other, [{ text: `BUY ${good} 1` }])
  expect(r.ok).toBe(false)
  if (!r.ok) expect(r.refusal.code).toBe('E_NO_SUCH_FLEET')
})

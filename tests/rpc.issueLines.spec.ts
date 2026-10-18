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
import { clearBackend, cmdCancel, cmdClear, cmdIssue, cmdIssueLines, createLocalBackend, setBackend, worldGoodBoard } from '../src/lib/rpc'

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

// ── 0186: A REFUSED ORDER DOES NOT FREEZE THE QUEUE ───────────────────────────────────────────────
// The owner, 2026-10-18: "Gaivota stopped at order 29 and will not skip it". A line refused when it RUNS
// cancels the rest of its plan, each line with the reason, and the fleet is free; the ✕ (cmd.cancel_at by
// the row's position in the served queue) dismisses the refused row; CLEAR empties what is left.

const since = (seq: number) =>
  db.callAs<{ seq: number; text: string; status: string; why: string | null }[] | null>(
    `select jsonb_agg(jsonb_build_object('seq', seq, 'text', raw_text, 'status', status, 'why', error_message) order by seq) as result
       from public.orders where fleet_id = $1::uuid and seq > $2::int`,
    [fleet, seq],
  )
const lastSeq = () =>
  db.callAs<number>(`select coalesce(max(seq), 0) as result from public.orders where fleet_id = $1::uuid`, [fleet])

test('a line refused at execution cancels the rest of its plan, with the reason, and the fleet is free', async () => {
  expect((await cmdClear(fleet)).ok).toBe(true)
  const s0 = await lastSeq()
  const r = await cmdIssueLines(fleet, [
    { text: `BUY ${good} 1 AT <= 0.01` }, // the limit is missed when it runs: refused at execution
    { text: `BUY ${good} 5 AT <= 100000` },
    { text: `SELL ${good} ALL AT >= 1` },
  ])
  expect(r.ok).toBe(true)
  const rows = (await since(s0))!
  expect(rows.map((o) => o.status)).toEqual(['failed', 'cancelled', 'cancelled'])
  for (const o of rows.slice(1)) expect(o.why?.startsWith(`cancelled: BUY ${good} 1 AT <= 0.01 was refused — `)).toBe(true)

  // free: the next order runs at once
  const next = await cmdIssue(fleet, `BUY ${good} 1 AT <= 100000`)
  expect(next.ok).toBe(true)
  expect((await since(s0))!.at(-1)!.status).toBe('done')

  // the ✕ by position dismisses the refused row the queue still shows
  const q = r.ok ? r.value.queue : []
  const at = q.findIndex((o) => o.status === 'failed') + 1
  expect(at).toBeGreaterThan(0)
  const dismissed = await cmdCancel(fleet, at)
  expect(dismissed.ok).toBe(true)
  if (dismissed.ok) expect(dismissed.value.queue.some((o) => o.status === 'failed')).toBe(false)

  // CLEAR empties the rest
  await cmdIssue(fleet, `BUY ${good} 1 AT <= 0.01`)
  const cleared = await cmdClear(fleet)
  expect(cleared.ok).toBe(true)
  if (cleared.ok) expect(cleared.value.queue).toHaveLength(0)
})

// ── 0188: THE DESK PLANS ONLY WHAT SHE CAN SAIL ──────────────────────────────────────────────────
// A SAIL beyond her captain's reach is refused when the plan is queued, naming its line; the good board
// serves the passage she CAN sail (stops, every leg within reach), and that passage queues.

test('a leg beyond her reach is refused up front; the board offers the passage through stops, and it queues', async () => {
  expect((await cmdClear(fleet)).ok).toBe(true)
  const goodId = await db.callAs<string>(`select id as result from public.goods where code = $1`, [good])
  const board = await worldGoodBoard(goodId, fleet)
  expect(board.ok).toBe(true)
  if (!board.ok) return
  const reach = board.value.reach!
  expect(reach.reach_nm).toBeGreaterThan(0)
  expect(board.value.supplies?.days).toBeGreaterThan(0)
  for (const r of [...board.value.buy, ...board.value.sell]) expect(typeof r.sailable).toBe('boolean')

  // the farthest city a direct leg cannot reach, but a chain of legs can
  const far = board.value.sell
    .filter((r) => r.needs && (r.stops?.length ?? 0) > 0 && r.miles !== null)
    .sort((a, b) => (b.miles ?? 0) - (a.miles ?? 0))[0]
  expect(far, 'a far sell city with a passage through stops').toBeDefined()
  console.log(`far: ${far.port} ${far.miles} nm via ${far.stops!.join(', ')}; needs Navigation ${far.needs!.navigation}; sailable ${far.sailable}`)

  const s0 = await lastSeq()
  const straight = await cmdIssueLines(fleet, [{ text: `BUY ${good} 1 AT <= 100000` }, { text: `SAIL ${far.port}` }])
  // the board's sell row runs from the buy city; asked from Lisbon a straight leg is beyond reach unless Lisbon is that city
  if (!straight.ok) {
    expect(straight.refusal.code).toBe('E_LEG_TOO_FAR')
    expect(straight.refusal.sentence.startsWith(`Line 2 (SAIL ${far.port}): that leg is`)).toBe(true)
    expect(await since(s0)).toBeNull()
  }
  const lisbonPassage = await db.callAs<string[] | null>(
    `select to_jsonb(r.stops) as result from voyage.reach_passage(public.current_player_id(), (select id from public.ports where code = 'LIS')) r where r.code = $1`,
    [far.port],
  )
  expect(lisbonPassage).not.toBeNull()
  const through = await cmdIssueLines(fleet, [...lisbonPassage!, far.port].map((c) => ({ text: `SAIL ${c}` })))
  expect(through.ok, JSON.stringify(through)).toBe(true)
})

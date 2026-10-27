// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A LOCAL TAB DOES NOT FREEZE AT A SLOT EDGE — the price record as src/lib/rpc/localBackend.ts plays it
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// In a tab there is no pg_cron, so the first record read (world.price_series, world.watchlist) after each
// 15-minute drift-slot edge plays public.tick_price_snapshot (0226) on the one PGlite queue; while it runs
// nothing else is answered. Unsteered, the planner computed every port_goods row's price to keep the
// recorded pairs: 9.1 s native on main's image (2026-10-27), tens of seconds in a tab — the freeze of
// docs/WORK_QUEUE.md #349. localBackend's RECORD_PLAN_SQL lets the planner keep the writer's written
// join order: 0.27 s. This spec proves (1) the steered job writes byte-for-byte what the bare job writes,
// and (2) a record read on an empty present slot (the state right after an edge) answers inside a budget
// the unsteered job cannot meet on any machine this suite runs on.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, createLocalBackend, setBackend, worldPriceSeries } from '../src/lib/rpc'
import { RECORD_PLAN_SQL } from '../src/lib/rpc/localBackend'

/** The edge job's budget. Steered: ~0.3 s native here. Unsteered: ~9 s native — over this on any runner. */
const EDGE_BUDGET_MS = 3_000

let db: LocalDb

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

/** Everything the job writes: the fine record, both folds and the marks. */
async function written(): Promise<string> {
  const r = await db.pg.query<{ d: string }>(`select concat_ws(' | ',
      (select md5(coalesce(string_agg(concat_ws(',', port_id, good_id, slot, at, mid, stock, ask, bid), ';' order by port_id, good_id, slot), '')) || ':' || count(*) from public.price_history),
      (select md5(coalesce(string_agg(concat_ws(',', port_id, good_id, hour, ask_o, ask_h, ask_l, ask_c, bid_o, bid_h, bid_l, bid_c, n), ';' order by port_id, good_id, hour), '')) || ':' || count(*) from public.price_history_hour),
      (select md5(coalesce(string_agg(concat_ws(',', port_id, good_id, day, ask_o, ask_h, ask_l, ask_c, bid_o, bid_h, bid_l, bid_c, n), ';' order by port_id, good_id, day), '')) || ':' || count(*) from public.price_history_day),
      (select row_to_json(m)::text from public.price_rollup m)) as d`)
  return r.rows[0].d
}

/** Run the job at `at` inside a transaction that is rolled back; what it wrote and how long it took. */
async function jobAt(at: string, steered: boolean): Promise<{ ms: number; out: string; result: unknown }> {
  await db.pg.query('begin')
  try {
    if (steered) await db.pg.query(`select ${RECORD_PLAN_SQL}`)
    const t0 = performance.now()
    const r = await db.pg.query<{ r: unknown }>('select public.tick_price_snapshot($1::timestamptz) as r', [at])
    const ms = Math.round(performance.now() - t0)
    return { ms, out: await written(), result: r.rows[0].r }
  } finally {
    await db.pg.query('rollback')
  }
}

test('the steered edge job writes exactly what the bare job writes, inside the budget', async () => {
  test.setTimeout(240_000)
  // One slot ahead: a slot nothing has recorded yet, i.e. the job as it runs right after an edge.
  const at = (await db.pg.query<{ t: Date }>(`select now() + interval '15 minutes' as t`)).rows[0].t.toISOString()
  const bare = await jobAt(at, false)
  const steered = await jobAt(at, true)
  console.log(`[recordEdge] tick_price_snapshot at a fresh slot: bare ${bare.ms} ms, steered ${steered.ms} ms`)
  expect(steered.result, 'the job reports the same run').toEqual(bare.result)
  expect((bare.result as { wrote: number }).wrote, 'the job recorded something (non-vacuous)').toBeGreaterThan(0)
  expect(steered.out, 'price_history, _hour, _day and the rollup marks, byte for byte').toBe(bare.out)
  expect(steered.ms, `the edge job held the tab's one queue for ${steered.ms} ms`).toBeLessThan(EDGE_BUDGET_MS)
})

test('a record read right after a slot edge answers inside the budget, and records the slot', async () => {
  test.setTimeout(120_000)
  const pair = (
    await db.pg.query<{ port_id: string; good_id: string }>('select port_id, good_id from public.price_record_pairs() limit 1')
  ).rows[0]
  expect(pair, 'the world records some pair').toBeTruthy()
  // The state an edge leaves: nothing in the present slot.
  await db.pg.query('delete from public.price_history where slot = public.drift_slot_of(now())')
  const t0 = performance.now()
  const series = await worldPriceSeries(pair.port_id, pair.good_id, '1d')
  const ms = Math.round(performance.now() - t0)
  console.log(`[recordEdge] world.price_series on an empty present slot: ${ms} ms`)
  expect(series.ok, JSON.stringify(series)).toBe(true)
  const kept = await db.pg.query<{ n: number }>('select count(*)::int as n from public.price_history where slot = public.drift_slot_of(now())')
  expect(kept.rows[0].n, 'the read played the job: the present slot holds the record').toBeGreaterThan(0)
  expect(ms, `the first record read after an edge held the tab's one queue for ${ms} ms`).toBeLessThan(EDGE_BUDGET_MS)
})

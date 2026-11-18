// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TAB PLAYS THE DRIFT JOB (2026-11-18, docs/dev-log/2026-11-18-play-faults.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FAULT. In the default local world a best-sale card said "Setubal +22,416" for 50 cinnamon and the sale paid +617. The card, the
// plan and the sale all price through world.quote; what differed was the market row it read. On Supabase the drift job
// (public.tick_market_drift_each_port) brings every harbour's rows to the present slot and game day each minute; in a tab nothing did,
// and a harbour's rows moved only when its own market was read (world.market ticks that one quay). Setubal's cinnamon stood at the
// stock the world image was built with (868.5 of 2,390, hundreds of game days behind), so the quote paid 1,116 a unit; by the sale its
// rows had been brought up (2,390), and it paid 680.
// THE LAW HELD HERE, on the build's own world: after the tab's market step (src/lib/rpc/localBackend.ts `playMarket`, which
// src/lib/rpc/init.ts runs at boot and every minute)
//   * no market row is behind the present game day, and none behind the present drift slot that can step;
//   * the row a quote reads is the row a trade reads: catching one harbour up as world.market does changes no quote there;
//   * a second step in the same slot changes nothing.
// Nothing here asserts a price.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { playMarket } from '../src/lib/rpc/localBackend'

let db: LocalDb

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
})

test.afterAll(async () => {
  await db?.close()
})

const behind = async () =>
  (
    await db.pg.query<{ day: number; slot: number }>(
      `select count(*) filter (where pg.last_regen_day < world.game_day())::int as day,
              count(*) filter (where pg.drift_slot < public.drift_slot_of(now()))::int as slot
         from public.port_goods pg`,
    )
  ).rows[0]

test('the tab\'s market step brings every harbour to the present, and a quote then reads the row a trade reads', async () => {
  test.setTimeout(300_000)
  const before = await behind()
  console.log(`MARKET rows behind before the step: ${before.day} by game day, ${before.slot} by slot`)
  await playMarket(db)
  const after = await behind()
  expect(after.day, 'a market row is still behind the game day').toBe(0)
  expect(after.slot, 'a market row is still behind the drift slot').toBe(0)

  // every harbour that sells a good she can quote: the quote now, then that harbour caught up as world.market catches it, then the quote
  // again. One statement each side (one snapshot); the harbours are the ones the shipped world's market rows name.
  const quotes = () =>
    db.pg.query<{ k: string; total: string | null }>(
      `select p.code || ':' || g.code as k, q.total::text as total
         from (select pg.port_id, pg.good_id from public.port_goods pg order by pg.port_id, pg.good_id limit 400) x
         join public.ports p on p.id = x.port_id
         join public.goods g on g.id = x.good_id
        cross join lateral (select * from world.quote(x.port_id, x.good_id, 10, 'sell')) q
        order by 1`,
    )
  const q0 = (await quotes()).rows
  expect(q0.length, 'no quote was read').toBeGreaterThan(0)
  await db.pg.query(`select public.tick_market_drift(now(), x.port_id) from (select distinct port_id from public.port_goods) x`)
  const q1 = (await quotes()).rows
  expect(q1, 'a harbour caught up as world.market catches it quotes differently: the quote read a stale row').toEqual(q0)

  // the step is idempotent within a slot
  await playMarket(db)
  expect(await behind()).toEqual({ day: 0, slot: 0 })
})

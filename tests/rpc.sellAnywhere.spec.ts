// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE OWNER'S SELL CASE, ON A REAL POSTGRES (owner row 231, 2026-10-26)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"the command, sell tab is not good enough, i can't sell because i can't dock. and i can't move to that location."*
// Prod, read-only, 2026-10-26 ~12:20 UTC: Gaivota DOCKED at Banda Aceh (BAN), 120 Borneo camphor aboard, purse 0,
// credit lit (world.player on_credit). Camphor is OFFERED at 3 harbours of 246 (public.port_offers), and world.market
// lists a good only where it is offered or she lies with it (public.quay_shows) — so at every other city the Sell
// card had no market row, read "No buyer", and would not press: she could neither pick a city nor sail to it.
// The server buys camphor there all the same (world.good_board serves a sell row at every harbour whose culture
// takes it; world.price_why serves the bid). The client fix prices that card from world.price_why.
//
// This spec builds that shape in the build's own world (her house moved to BAN, the cargo, the purse emptied
// through the ledger, the purses lit and the economy closed — the switches prod stands on) and holds the reads the
// Sell face now stands on: the quay of a near city lists no camphor; price_why bids for it there; the board sells it
// there; and the one press — SAIL there, SELL camphor ALL — queues and she sails with an empty purse, on credit.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, cmdIssueLines, createLocalBackend, setBackend, worldGoodBoard, worldMarket, worldPlayer, worldPriceWhy } from '../src/lib/rpc'

let db: LocalDb
let fleet: string
let camphor: string
const port = (code: string) => db.callAs<string>(`select id as result from public.ports where code = $1`, [code])

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Sell Anywhere Spec', 'PRT') as result`)
  const me = await db.callAs<string>(`select public.current_player_id() as result`)
  fleet = await db.callAs<string>(`select f.id as result from public.fleets f where f.player_id = public.current_player_id() limit 1`)
  camphor = await db.callAs<string>(`select id as result from public.goods where code = 'camphor'`)
  // THE OWNER'S SHAPE (the engine's own superuser: a spec's fixture, never a game path)
  await db.pg.query(
    `update public.fleets f set port_id = p.id, lat = null, lon = null, status = 'DOCKED', ready_at = null, busy_until = null,
            version = f.version + 1
       from public.ports p where p.code = 'BAN' and f.id = $1`,
    [fleet],
  )
  await db.pg.query(`update public.ships set cargo = '{"camphor": 120}'::jsonb where fleet_id = $1`, [fleet])
  await db.pg.transaction(async (tx) => {
    await tx.query(`insert into public.ledger (player_id, kind, ducats_delta, balance_after) select id, 'BUY', -ducats, 0 from public.players where id = $1`, [me])
    await tx.query(`update public.players set ducats = 0, version = version + 1 where id = $1`, [me])
  })
  await db.pg.query(`select public.city_treasury_switch(true)`)
  await db.pg.query(`select public.economy_close_switch(true)`)
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('docked at BAN with camphor and an empty purse: a near city that does not list it bids for it, and she sails there to sell', async () => {
  test.setTimeout(240_000)
  const player = await worldPlayer()
  expect(player.ok).toBe(true)
  if (player.ok) {
    expect(player.value.player?.ducats).toBe(0)
    expect(player.value.player?.on_credit, 'credit is lit, as on prod').toBe(true)
  }

  // a near city whose quay does not list camphor: the board's nearest sailable sell row not offered there
  const board = await worldGoodBoard(camphor, fleet)
  expect(board.ok).toBe(true)
  if (!board.ok) return
  expect(board.value.qty.basis).toBe('on_board')
  const offered = new Set(
    await db.callAs<string[]>(
      `select coalesce(jsonb_agg(p.code), '[]'::jsonb) as result from public.ports p where public.port_offers(p.id, $1::uuid)`,
      [camphor],
    ),
  )
  expect(offered.size, 'camphor is offered at only a few harbours').toBeLessThan(10)
  const near = board.value.sell
    .filter((r) => r.port !== 'BAN' && !offered.has(r.port) && r.sailable === true && r.days !== null)
    .sort((a, b) => (a.days ?? 0) - (b.days ?? 0))[0]
  expect(near, 'a near sailable city that does not offer camphor').toBeDefined()
  console.log(`near: ${near.port} ${near.days} days via ${(near.stops ?? []).join(', ') || '(direct)'}`)

  // THE CAUSE: its quay lists no camphor (the card had no row: "No buyer")…
  const quay = await worldMarket(await port(near.port))
  expect(quay.ok).toBe(true)
  if (quay.ok) expect(quay.value.goods.some((g) => g.code === 'camphor')).toBe(false)
  // …while the served bid is there (what the card now prints and the panel trades at)
  const why = await worldPriceWhy(await port(near.port), camphor)
  expect(why.ok).toBe(true)
  if (why.ok) expect(why.value.bid).toBeGreaterThan(0)

  // THE ONE PRESS: SAIL (through the board's stops) and SELL camphor ALL, with a purse of 0
  const lines = [...(near.stops ?? []), near.port].map((c) => ({ text: `SAIL ${c}` })).concat([{ text: 'SELL camphor ALL' }])
  const r = await cmdIssueLines(fleet, lines)
  expect(r.ok, JSON.stringify(r)).toBe(true)
  const state = await db.callAs<{ status: string; ducats: number; orders: { text: string; status: string }[] }>(
    `select jsonb_build_object('status', f.status, 'ducats', p.ducats,
              'orders', (select jsonb_agg(jsonb_build_object('text', o.raw_text, 'status', o.status) order by o.seq) from public.orders o where o.fleet_id = f.id)) as result
       from public.fleets f join public.players p on p.id = f.player_id where f.id = $1::uuid`,
    [fleet],
  )
  console.log(JSON.stringify(state))
  expect(state.status, 'she left with an empty purse (her stores on credit)').toBe('SAILING')
  expect(state.orders.at(0)?.status).toBe('done')
  expect(state.orders.at(-1)).toEqual({ text: 'SELL camphor ALL', status: 'pending' })
})

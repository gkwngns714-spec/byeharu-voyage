import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, cmdMoveShip, createLocalBackend, setBackend, worldFleets, worldShipMoves } from '../src/lib/rpc'
import { headline } from '../src/features/ledger/headline'

// ═════════════════════════════════════════════════
// A SHIP CHANGES FLEETS, THE SEAM (0321, docs/FLEETS_AND_SLOTS.md section 2.4): the real doors, through the client's one RPC layer, on the built world.
// Proof 29 proves the server's rules. This proves what the proof cannot reach: the player's whole list reads with an empty fleet in it, because voyage.fleet_speed_at raises E_NO_SHIPS.
// The law: dark, nothing changes for anyone.
// ═════════════════════════════════════════════════

let db: LocalDb

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Room Spec', 'PRT') as result`)
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

async function fleets() {
  const r = await worldFleets()
  expect(r.ok).toBe(true)
  return r.ok ? r.value : []
}

test('dark: the read offers nothing and the door refuses', async () => {
  // 0370 lit fleet room in the built world: this test sets it back in its own database first (the lit test below lights it again)
  await db.callAs(`
    with dark as (update public.world_config set value = 'false'::jsonb where key = 'fleet_room_bite' returning 1)
    select count(*)::int as result from dark`)
  const [fleet] = await fleets()
  const read = await worldShipMoves(fleet.id)
  expect(read.ok && read.value).toEqual({ on: false })
  const moved = await cmdMoveShip(fleet.ships[0].id, null, 'Nova Armada')
  expect(!moved.ok && moved.refusal.code).toBe('E_NOT_IN_USE')
  expect(await fleets()).toHaveLength(1)
})

test('lit: a new fleet, an empty fleet in the list, and back', async () => {
  await db.callAs(`
    with lit as (update public.world_config set value = 'true'::jsonb where key = 'fleet_room_bite' returning 1)
    select count(*)::int as result from lit`)
  const [first] = await fleets()
  const ship = first.ships[0]
  const read = await worldShipMoves(first.id)
  expect(read.ok && read.value).toEqual({ on: true, targets: [], can_new: true })

  const moved = await cmdMoveShip(ship.id, null, 'Nova Armada')
  expect(moved.ok).toBe(true)
  if (!moved.ok) return
  expect(moved.value).toMatchObject({ ship: ship.name, from: first.name, to: 'Nova Armada', new_fleet: true, empty: true })

  // THE SEAM: world.fleets reads with no ship in one of them, and says so
  const after = await fleets()
  expect(after).toHaveLength(2)
  const empty = after.find((f) => f.id === first.id)!
  const nova = after.find((f) => f.id === moved.value.fleet_id)!
  expect(empty).toMatchObject({ status: 'UNABLE_TO_SAIL', speed_kn: 0, ships: [] })
  expect(nova.status).toBe('DOCKED')
  expect(nova.ships[0].is_flagship).toBe(true)
  expect(nova.speed_kn).toBeGreaterThan(0)

  // an empty fleet offers nothing of her own, and is offered to the fleet that has a ship
  const fromEmpty = await worldShipMoves(first.id)
  expect(fromEmpty.ok && fromEmpty.value).toEqual({ on: true, targets: [], can_new: false })
  const fromNova = await worldShipMoves(nova.id)
  expect(fromNova.ok && fromNova.value).toEqual({ on: true, targets: [{ id: first.id, name: first.name, empty: true }], can_new: false })

  // the book's word
  const words = headline(
    { kind: 'SHIP_MOVED', payload: { ship: ship.name, from: first.name, to: 'Nova Armada' } } as never,
    (code) => code,
  )
  expect(words).toContain('Nova Armada')

  const back = await cmdMoveShip(ship.id, first.id, null)
  expect(back.ok).toBe(true)
  const last = await fleets()
  expect(last.find((f) => f.id === first.id)).toMatchObject({ status: 'DOCKED', ships: [{ id: ship.id, is_flagship: true }] })
  expect(last.find((f) => f.id === nova.id)).toMatchObject({ status: 'UNABLE_TO_SAIL', ships: [] })
})

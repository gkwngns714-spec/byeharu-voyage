import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, cmdBuyRoom, cmdRenameFleet, createLocalBackend, setBackend, worldFleets, worldHouseRoom, worldLedger } from '../src/lib/rpc'
import { headline } from '../src/features/ledger/headline'

// ═════════════════════════════════════════════════
// ROOM IS BOUGHT, A FLEET READS ITS TOTALS, A FLEET IS RENAMED: THE SEAM (0354, docs/FLEETS_AND_SLOTS.md F3 + F4): the real doors and reads, through the client's one RPC layer,
// on the built world. Proof 57 proves the server's rules. This proves the shapes the client types promise, and the law: dark, nothing can be bought.
// ═════════════════════════════════════════════════

let db: LocalDb

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Sala Spec', 'PRT') as result`)
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

async function room() {
  const r = await worldHouseRoom()
  expect(r.ok).toBe(true)
  if (!r.ok || !r.value.company) throw new Error('no room read for a founded company')
  return r.value
}

test('the fleet reads its totals, and they are the sums of her ships', async () => {
  const [fleet] = await fleets()
  const s = fleet.totals!
  expect(s.ships).toBe(fleet.ships.length)
  expect(s.attack).toBe(fleet.ships.reduce((n, x) => n + x.attack, 0))
  expect(s.hull).toBe(fleet.ships.reduce((n, x) => n + x.durability, 0))
  expect(s.hull_max).toBe(fleet.ships.reduce((n, x) => n + x.max_durability, 0))
  expect(s.crew).toBe(fleet.ships.reduce((n, x) => n + x.crew, 0))
  expect(s.crew_required).toBe(fleet.ships.reduce((n, x) => n + x.crew_required, 0))
  expect(s.crew_max).toBe(fleet.ships.reduce((n, x) => n + x.crew_max, 0))
  expect(s.short_crew).toEqual(fleet.ships.filter((x) => x.crew < x.crew_required).map((x) => x.name).sort())
  expect(s.wages_day).toBeGreaterThan(0)
  const slowest = [...fleet.ships].sort((a, b) => a.speed - b.speed || a.name.localeCompare(b.name))[0]
  expect(s.slowest).toEqual({ id: slowest.id, name: slowest.name, speed: slowest.speed })
})

test('dark: the room read says so, and the buying door refuses and takes nothing', async () => {
  const before = await room()
  expect(before.on).toBe(false)
  expect(before.fleets).toMatchObject({ used: 1, top: 5, free: 2, bought: 0, full: false, price: 60000 })
  expect(before.ships).toMatchObject({ used: 1, top: 7, free: 2, bought: 0, full: false, price: 10000 })
  expect(before.fleets.steps.map((s) => (s.how === 'level' ? `${s.tracks.join('+')} ${s.level}` : s.price))).toEqual(['trading 3', 'trading 6', 60000, 1000000])
  expect(before.ships.steps.filter((s) => s.how === 'level')).toHaveLength(5)
  expect(before.ships.steps.filter((s) => s.how === 'gold').map((s) => s.how === 'gold' && s.price)).toEqual([10000, 20000, 40000, 80000, 160000])
  for (const kind of ['FLEET', 'SHIP'] as const) {
    const bought = await cmdBuyRoom(kind)
    expect(!bought.ok && bought.refusal.code).toBe('E_NOT_IN_USE')
  }
  expect(await room()).toEqual(before)
})

test('a fleet takes a new name whatever the switch says; a bad or taken name is refused', async () => {
  const [fleet] = await fleets()
  const renamed = await cmdRenameFleet(fleet.id, '  Frota Nova  ')
  expect(renamed.ok && renamed.value).toMatchObject({ fleet_id: fleet.id, from: fleet.name, to: 'Frota Nova', changed: true })
  const [after] = await fleets()
  expect(after.name).toBe('Frota Nova')
  expect(after.version).toBe(fleet.version)
  const bad = await cmdRenameFleet(fleet.id, 'ab')
  expect(!bad.ok && bad.refusal.code).toBe('E_BAD_NAME')
  const none = await cmdRenameFleet('00000000-0000-4000-8000-000000000000', 'Frota de Ninguem')
  expect(!none.ok && none.refusal.code).toBe('E_NO_SUCH_FLEET')
  expect((await fleets())[0].name).toBe('Frota Nova')
  // the book's words
  expect(headline({ kind: 'FLEET_RENAMED', payload: { from: fleet.name, to: 'Frota Nova' } } as never, (code) => code)).toContain('Frota Nova')
  expect(headline({ kind: 'ROOM_OPENED', payload: { kind: 'SHIP', step: 1, price: 10000, room: 3 } } as never, (code) => code)).toContain('10,000')
})

test('lit: a ship step is bought at the knob price, and a fleet step she cannot pay is refused with both figures', async () => {
  await db.callAs(`
    with lit as (update public.world_config set value = 'true'::jsonb where key = 'fleet_room_bite' returning 1)
    select count(*)::int as result from lit`)
  const before = await room()
  expect(before.on).toBe(true)
  expect(before.ships.have).toBe(2)
  const next = before.ships.steps.find((s) => s.how === 'gold' && s.next)
  expect(next).toMatchObject({ price: 10000, can_pay: before.purse >= 10000 })

  const bought = await cmdBuyRoom('SHIP')
  expect(bought.ok && bought.value).toMatchObject({ kind: 'SHIP', step: 1, price: 10000, purse: before.purse - 10000, fleet_ship_max: 3 })
  const after = await room()
  expect(after.purse).toBe(before.purse - 10000)
  expect(after.ships).toMatchObject({ have: 3, ladder: 3, bought: 1, price: 20000 })
  expect(after.hulls.have).toBe(after.fleets.have * after.ships.have)

  // the purse a company is founded with does not cover a fleet step
  expect(after.purse).toBeLessThan(60000)
  const short = await cmdBuyRoom('FLEET')
  expect(!short.ok && short.refusal.code).toBe('E_INSUFFICIENT_FUNDS')
  if (!short.ok) expect(short.refusal.figures).toMatchObject({ have: after.purse, need: 60000, unit: 'ducats' })
  expect((await room()).purse).toBe(after.purse)

  // the book carries the buy
  const ledger = await worldLedger(null, 50)
  expect(ledger.ok && ledger.value.events.some((e) => e.kind === 'ROOM_OPENED')).toBe(true)
})

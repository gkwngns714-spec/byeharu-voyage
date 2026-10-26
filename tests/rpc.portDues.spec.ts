import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, createLocalBackend, setBackend, worldFleets, worldTownHall } from '../src/lib/rpc'
import { duesWords } from '../src/domain/port'

// 0237 (docs/CLOSED_ECONOMY.md §4c, owner row 215): EVERY PORT CHARGES AND TAKES A MINUTE. Dark, the Town Hall serves no
// `dues` and a fleet no `ready_at`. Lit (the economy closed, in this in-memory world only), a Dutch company reads
// Lisbon's dues — at war with Portugal: tax 2×, dock fee 50 × 2 — and her fleet, just in port, serves `ready_at`. The
// client's new lines read exactly these keys.

let db: LocalDb
let lisbon: string
let fleet: string
let player: string

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Haven Spec', 'NLD') as result`)
  lisbon = await db.callAs<string>(`select p.id as result from public.ports p where p.code = 'LIS'`)
  // the signed-in company (the door founds one, or she already has hers)
  player = await db.callAs<string>(`select public.current_player_id() as result`)
  fleet = await db.callAs<string>(`select f.id as result from public.fleets f where f.player_id = $1 order by f.id limit 1`, [player])
  // her country is the Netherlands (whatever she was founded as): at war with Portugal (0196's relations)
  await db.callAs(
    `with x as (update public.players set nation_id = (select n.id from public.nations n where n.code = 'NLD') where id = $1 returning 1)
     select count(*)::int as result from x`,
    [player],
  )
  await db.callAs(`
    with lit as (update public.world_config set value = 'true'::jsonb
                  where key in ('city_treasury_enabled', 'influence_enabled') returning 1)
    select count(*)::int as result from lit`)
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('dark: the Town Hall serves no dues and no fleet a port time', async () => {
  const hall = await worldTownHall(lisbon)
  expect(hall.ok && 'dues' in hall.value).toBe(false)
  const fleets = await worldFleets()
  expect(fleets.ok).toBe(true)
  expect(fleets.ok && fleets.value.some((f) => 'ready_at' in f)).toBe(false)
})

test('lit: a Dutch company at Lisbon reads tax 2× (at war) and a dock fee of 100, and her fleet is making ready', async () => {
  await db.callAs(`
    with lit as (update public.world_config set value = 'true'::jsonb where key = 'economy_closed' returning 1)
    select count(*)::int as result from lit`)
  const hall = await worldTownHall(lisbon)
  expect(hall.ok).toBe(true)
  if (!hall.ok) return
  expect(hall.value.dues).toMatchObject({ stance: 'war', factor: 2, fee: 100, fee_base: 50, prep_seconds: 60 })
  // the one reading of it (domain/port): "Tax 2× (at war) · Dock fee 100" / "세금 2× (전쟁) · 입항료 100", in the locale in force
  expect(duesWords(hall.value.dues!)).toMatch(/2× \(.+\) · .*100/)
  // she has just made her harbour: the one writer of a port call sets her port time
  await db.callAs(
    `select public.port_call($1, (select f.port_id from public.fleets f where f.id = $1), $2, now(), now(), null) as result`,
    [fleet, player],
  )
  const fleets = await worldFleets()
  expect(fleets.ok).toBe(true)
  if (!fleets.ok) return
  const mine = fleets.value.find((f) => f.id === fleet)
  expect(mine?.ready_at).toBeTruthy()
  expect(Date.parse(mine!.ready_at!) - Date.now()).toBeGreaterThan(30_000)
})

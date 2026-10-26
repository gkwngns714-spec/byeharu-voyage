import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, createLocalBackend, setBackend, worldNpcFleetCard, worldTownHall } from '../src/lib/rpc'

// 0234 (docs/CLOSED_ECONOMY.md §5.2–5.3, owner row 212): A CAPITAL GIVES. Dark, the Town Hall serves no `gifts` and a
// merchant's card no `last_gift`. Lit (the economy closed, in this in-memory world only), a broke merchant of Portugal
// is given her capital by Lisbon, and both reads serve it — the client's two new lines read exactly these keys.

let db: LocalDb
let lisbon: string
let fleet: string

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Dadiva Spec', 'PRT') as result`)
  lisbon = await db.callAs<string>(`select p.id as result from public.ports p where p.code = 'LIS'`)
  await db.callAs(`
    with lit as (update public.world_config set value = 'true'::jsonb
                  where key in ('city_treasury_enabled', 'npc_traders_enabled', 'standing_routes_enabled') returning 1)
    select count(*)::int as result from lit`)
  const m = await db.callAs<string>(
    `select public.new_house(null, 'Casa Spec 0234', 'PRT', 'LIS', p_ducats => 500, p_is_npc => true) as result`,
  )
  await db.callAs(
    `with h as (insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience, wares)
                values ($1, (select coalesce(max(roster_ord), 0) + 1 from public.npc_houses), 'prt', 'A spec probe house.',
                        'Mestre Spec', $2, 5000, 0.1, '{}') returning 1)
     select count(*)::int as result from h`,
    [m, lisbon],
  )
  fleet = await db.callAs<string>(`select f.id as result from public.fleets f where f.player_id = $1 order by f.id limit 1`, [m])
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('dark: no gift is given and neither read serves a gift key', async () => {
  const pass = await db.callAs<unknown>(
    `select public.capital_gift_pass(now(), (select player_id from public.npc_houses h join public.players p on p.id = h.player_id
                                             where p.company_name = 'Casa Spec 0234')) as result`,
  )
  expect(pass).toBeNull()
  const hall = await worldTownHall(lisbon)
  expect(hall.ok && 'gifts' in hall.value).toBe(false)
  const card = await worldNpcFleetCard(fleet)
  expect(card.ok, card.ok ? '' : card.refusal.sentence).toBe(true)
  expect(card.ok && 'last_gift' in card.value.company).toBe(false)
})

test('lit: Lisbon gives the broke merchant her capital, and the Town Hall and her card show it', async () => {
  await db.callAs(`select public.treasury_post($1, 'SPEC_0234', 1000000, null, null) as result`, [lisbon])
  await db.callAs(`
    with lit as (update public.world_config set value = 'true'::jsonb where key = 'economy_closed' returning 1)
    select count(*)::int as result from lit`)
  const pass = await db.callAs<{ gifted: number; gift_ducats: number }>(
    `select public.capital_gift_pass(now(), (select player_id from public.npc_houses h join public.players p on p.id = h.player_id
                                             where p.company_name = 'Casa Spec 0234')) as result`,
  )
  expect(pass.gifted).toBe(1)
  expect(pass.gift_ducats).toBe(5000)
  const hall = await worldTownHall(lisbon)
  expect(hall.ok).toBe(true)
  if (!hall.ok) return
  expect(hall.value.gifts?.[0]).toMatchObject({ name: 'Casa Spec 0234', ducats: 5000, called_from: null })
  const card = await worldNpcFleetCard(fleet)
  expect(card.ok).toBe(true)
  if (!card.ok) return
  expect(card.value.company.last_gift).toMatchObject({ port: 'LIS', ducats: 5000 })
  expect(card.value.company.fortune).toBe(5500)
})

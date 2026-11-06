import { test, expect } from '@playwright/test'
import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, cmdAttack, cmdPreviewAttack, createLocalBackend, setBackend, worldCargoShipCard, worldFleets, type CargoShipCard } from '../src/lib/rpc'
import { headline } from '../src/features/ledger/headline'
import { translateMaybe } from '../src/lib/i18n'
import { sectorOf } from '../src/features/stats/moneySectors'
import { AttackSection } from '../src/live/AttackSection'

// ═════════════════════════════════════════════════════════════════
// A PLAYER ATTACKS, THE SEAM (0327, docs/WORLD_POWERS.md §4.2): the real doors, through the client's one RPC layer, on the built world.
// Proof 33 proves the server's rules and the gold. This proves the client reads what the server serves: dark, the card serves no key, the section draws nothing and the doors
// refuse; lit, the card says so, the dry run's words all have labels, the press opens a battle, and a report with gold reads as gold. The law: dark, nothing changes for anyone.
// ═════════════════════════════════════════════════════════════════

let db: LocalDb
let fleet: string
let target: string

const light = (keys: string[], on: boolean) =>
  db.callAs(`with lit as (update public.world_config set value = $2::jsonb where key = any($1::text[]) returning 1) select count(*)::int as result from lit`, [keys, on ? 'true' : 'false'])

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Attack Spec', 'PRT') as result`)
  await db.callAs(`with t as (update public.port_treasury set ducats = 50000000, reserve = 0 returning 1) select count(*)::int as result from t`)
  await light(['city_treasury_enabled', 'convoys_enabled'], true)
  // a cargo ship of another country, at sea, carrying funds, and the company's one fleet at anchor on her very point
  const realm = await db.callAs<string>(`select g.nation_id as result from public.great_powers g join public.nations n on n.id = g.nation_id where n.code <> 'PRT' order by n.code limit 1`)
  for (let i = 0; i < 3; i++) await db.callAs(`select public.tick_cargo_ships(now(), $1::uuid) is null as result`, [realm])
  target = await db.callAs<string>(`select c.fleet_id as result from public.cargo_ships c where c.nation_id = $1 and c.ord = 1`, [realm])
  await db.callAs(
    `select public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, 100000) is null, public.cargo_ship_step(c.fleet_id, now()) as result from public.cargo_ships c where c.fleet_id = $1`,
    [target],
  )
  const fleets = await worldFleets()
  expect(fleets.ok).toBe(true)
  if (!fleets.ok) return
  fleet = fleets.value[0].id
  await db.callAs(
    `with p as (select * from voyage.fleet_point($2, now())),
          g as (update public.ships set class_id = (select c.id from public.ship_classes c order by c.attack desc, c.code limit 1), cargo = '{}'::jsonb where fleet_id = $1 returning 1),
          f as (update public.fleets x set status = 'ANCHORED', port_id = null, lat = p.lat, lon = p.lon from p where x.id = $1 returning 1)
     select (select count(*)::int from f) + (select count(*)::int from g) as result`,
    [fleet, target],
  )
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('dark: the card serves no key, the section draws nothing, and both doors refuse', async () => {
  const card = await worldCargoShipCard(target)
  expect(card.ok, JSON.stringify(card)).toBe(true)
  if (!card.ok) return
  expect('attack' in card.value).toBe(false)
  expect(renderToStaticMarkup(createElement(AttackSection, { card: card.value }))).toBe('')
  for (const r of [await cmdPreviewAttack(fleet, target), await cmdAttack(fleet, target, null)]) {
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.refusal.code).toBe('E_NOT_IN_USE')
  }
})

test('lit: the card says so, the dry run reads in plain words, and the press opens a battle', async () => {
  await light(['attack_enabled'], true)
  const card = await worldCargoShipCard(target)
  expect(card.ok, JSON.stringify(card)).toBe(true)
  if (!card.ok) return
  expect(card.value.attack).toBe(true)
  const dry = await cmdPreviewAttack(fleet, target)
  expect(dry.ok, JSON.stringify(dry)).toBe(true)
  if (!dry.ok) return
  expect(dry.value.battle_id).toBeUndefined()
  for (const locale of ['en', 'ko'] as const) {
    expect(translateMaybe(locale, 'map', `attackWord_${dry.value.word}`)).toBeTruthy()
    expect(translateMaybe(locale, 'map', `attackFunds_${dry.value.funds}`)).toBeTruthy()
  }
  const hit = await cmdAttack(fleet, target, null)
  expect(hit.ok, JSON.stringify(hit)).toBe(true)
  if (!hit.ok) return
  expect(hit.value.battle_id).toBeTruthy()
  expect(hit.value.word).toBe(dry.value.word)
  expect(hit.value.funds).toBe(dry.value.funds)
  // a second press is refused in words the player can read
  const again = await cmdAttack(fleet, target, null)
  expect(again.ok).toBe(false)
  if (!again.ok) expect(again.refusal.code).toBe('E_FLEET_BUSY')
})

test('every refusal of the door has its words, English and Korean, and the figures their units', () => {
  const codes = ['E_NO_GUNS', 'E_HOLD_NOT_EMPTY', 'E_TARGET_DOCKED', 'E_OUT_OF_REACH', 'E_SHIP_FOUGHT_THIS_LAP', 'E_ATTACK_COOLDOWN', 'E_FLEET_BUSY', 'E_YOUR_OWN_COUNTRY', 'E_HUMAN_TARGET', 'E_NOT_A_TARGET', 'E_NOT_IN_USE', 'unit_miles', 'unit_minutes']
  for (const locale of ['en', 'ko'] as const) for (const code of codes) expect(translateMaybe(locale, 'codes', code), `${locale} ${code}`).toBeTruthy()
})

test('the report reads as gold when there was gold, and as it did when there was none', () => {
  const event = (payload: Record<string, unknown>) => ({ id: 'e', kind: 'BATTLE_REPORT', payload, created_at: new Date(0).toISOString() }) as never
  expect(headline(event({ fleet: 'Gaivota', loot: 60000 }), (c) => c)).toContain('60,000')
  expect(headline(event({ fleet: 'Gaivota', loot: 0 }), (c) => c)).toBe(headline(event({ fleet: 'Gaivota' }), (c) => c))
  expect(translateMaybe('ko', 'feed', 'k_LOOT')).toBeTruthy()
  expect(sectorOf('LOOT', 'player')).toBe('other')
})

test('the card type stays optional: a card from before 0327 draws nothing', () => {
  const old = { fleet: { id: 'x', name: 'x', status: 'SAILING', port: null }, nation_code: 'ESP', home: 'SVQ', funds: 0, to: null, eta: null, next: [], stops_left: 0, ships: [] } as CargoShipCard
  expect(renderToStaticMarkup(createElement(AttackSection, { card: old }))).toBe('')
})

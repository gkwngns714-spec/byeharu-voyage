import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, cmdPayFine, createLocalBackend, setBackend, worldTownHall } from '../src/lib/rpc'
import { duesWords, regardBandWord } from '../src/domain/port'
import { headline } from '../src/features/ledger/headline'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A HOUSE HAS A REGARD, THE SEAM (0319, docs/WORLD_POWERS.md §2.1): the real doors, through the client's one RPC layer, on the built world.
// Proof 27 proves the server's arithmetic. This proves the client reads what the server serves: dark, the hall serves no line and the door refuses;
// lit, the hall's line, the words, the door, and the receipt. The law: dark, nothing changes for anyone.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

let db: LocalDb
let lisbon: string
let porto: string
let player: string
let portugal: string

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Regard Spec', 'PRT') as result`)
  lisbon = await db.callAs<string>(`select p.id as result from public.ports p where p.code = 'LIS'`)
  porto = await db.callAs<string>(`select p.id as result from public.ports p where p.code = 'OPO'`)
  player = await db.callAs<string>(`select public.current_player_id() as result`)
  portugal = await db.callAs<string>(`select n.id as result from public.nations n where n.code = 'PRT'`)
  await db.callAs(
    `with x as (update public.players set nation_id = $2 where id = $1 returning 1) select count(*)::int as result from x`,
    [player, portugal],
  )
  await db.callAs(`
    with lit as (update public.world_config set value = 'true'::jsonb
                  where key in ('city_treasury_enabled', 'influence_enabled', 'economy_closed') returning 1)
    select count(*)::int as result from lit`)
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('dark: the hall serves no regard, the words are the old words, and the door refuses', async () => {
  const hall = await worldTownHall(lisbon)
  expect(hall.ok).toBe(true)
  if (!hall.ok) return
  expect(hall.value.dues).toBeTruthy()
  expect('regard' in hall.value.dues!).toBe(false)
  expect(duesWords(hall.value.dues!)).not.toMatch(/Friendly|우호/)
  const paid = await cmdPayFine(lisbon, 20_000)
  expect(paid.ok).toBe(false)
  if (!paid.ok) expect(paid.refusal.code).toBe('E_NOT_IN_USE')
})

test('lit: the hall reads her band and her fine, the door pays it, and the capital alone offers it', async () => {
  await db.callAs(`with lit as (update public.world_config set value = 'true'::jsonb where key = 'regard_enabled' returning 1) select count(*)::int as result from lit`)
  // she stands at Portugal's home: +200. Earned -150 makes her 50, Neutral, and 150 points owed at 200 d. each: inside her starting purse.
  await db.callAs(
    `with r as (insert into public.house_regard (player_id, nation_id, points) values ($1, $2, -150) returning 1) select count(*)::int as result from r`,
    [player, portugal],
  )
  const hall = await worldTownHall(lisbon)
  expect(hall.ok).toBe(true)
  if (!hall.ok) return
  expect(hall.value.dues!.regard).toEqual({ score: 50, band: 'neutral', factor: 1, fine: 30_000 })
  expect(duesWords(hall.value.dues!)).toContain(regardBandWord('neutral'))

  const away = await worldTownHall(porto)
  expect(away.ok && away.value.dues?.regard?.fine).toBe(0)

  const before = await db.callAs<number>(`select ducats::int as result from public.players where id = $1`, [player])
  const paid = await cmdPayFine(lisbon, 30_000)
  expect(paid.ok).toBe(true)
  if (!paid.ok) return
  expect(paid.value).toMatchObject({ amount: 30_000, owed: 0, score: 200, band: 'friendly', purse: before - 30_000 })

  const after = await worldTownHall(lisbon)
  expect(after.ok && after.value.dues?.regard).toEqual({ score: 200, band: 'friendly', factor: 0.9, fine: 0 })
  // dues.factor is the factor she really pays: home 0.25 × Friendly 0.9
  expect(after.ok && after.value.dues?.factor).toBe(0.225)

  const again = await cmdPayFine(lisbon, 20_000)
  expect(again.ok).toBe(false)
  if (!again.ok) expect(again.refusal.code).toBe('E_NO_FINE')
})

test('the history lines read the two new events, in the country\'s name and the band\'s word', () => {
  const event = (kind: string, payload: Record<string, unknown>) => ({ id: 'x', kind, at: '2026-11-06T00:00:00Z', ducats_delta: 0, balance_after: 0, payload })
  const up = headline(event('REGARD_CHANGED', { nation: 'PRT', delta: 10, score: 210, band: 'friendly' }), (c) => c)
  expect(up).toContain(regardBandWord('friendly'))
  expect(up).toContain('210')
  const down = headline(event('REGARD_CHANGED', { nation: 'PRT', delta: -150, score: -350, band: 'hostile' }), (c) => c)
  expect(down).toContain(regardBandWord('hostile'))
  expect(down).not.toBe(up)
  expect(headline(event('FINE_PAID', { port: 'LIS', port_name: 'Lisbon', amount: 20000, nation: 'PRT' }), (c) => c)).toContain('20,000')
})

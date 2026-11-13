import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, cmdRaidOrder, createLocalBackend, setBackend, worldFleets, worldLedger, worldRaidRead, type RaidOrderWord } from '../src/lib/rpc'
import { payloadFights } from '../src/features/ledger/headline'
import { translateMaybe } from '../src/lib/i18n'
import { fightRows } from '../src/live/fightLines'

// ═════════════════════════════════════════════════════════════════════════════════════════════════
// A FLEET'S STANDING ORDER, THE SEAM (0353, docs/COMBAT_LOG.md 2.1, 6.2): the real doors, through the client's one RPC
// layer, on the built world. Proof 56 proves the server's rules and the gold. This proves the client reads what the
// server serves: dark (the world as it ships), the read says off and the door refuses, so the picker draws nothing;
// lit, the door takes Fight, Flee and Pay, the read's every word has a label in both languages, a bad word is refused
// with a code the dictionary knows, and a raid sailed under Flee comes back as a log the client's reader takes.
// ═════════════════════════════════════════════════════════════════════════════════════════════════

let db: LocalDb
let fleet: string

const one = async <T>(sql: string, params: unknown[] = []): Promise<T> =>
  (Object.values((await db.pg.query<Record<string, T>>(sql, params)).rows[0] ?? {})[0]) as T

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Ordem Spec', 'PRT') as result`)
  const fleets = await worldFleets()
  expect(fleets.ok).toBe(true)
  if (!fleets.ok) return
  fleet = fleets.value[0].id
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('dark (the world before 0371, and after its rollback): the read says off, the door refuses, no row is written', async () => {
  // 0371 lit standing orders in the built world: this test sets them back in its own database first (the lit tests below light them again)
  expect(await one<boolean>(`select public.raid_orders_on()`)).toBe(true)
  await db.pg.exec(`update public.world_config set value = 'false'::jsonb where key = 'raid_orders_enabled'`)
  expect(await one<boolean>(`select public.raid_orders_on()`)).toBe(false)
  const read = await worldRaidRead(fleet)
  expect(read.ok, JSON.stringify(read)).toBe(true)
  if (read.ok) expect(read.value).toEqual({ on: false })
  for (const order of ['FIGHT', 'FLEE', 'PAY'] as const) {
    const r = await cmdRaidOrder(fleet, order)
    expect(r.ok).toBe(false)
    if (!r.ok) {
      expect(r.refusal.code).toBe('E_NOT_IN_USE')
      for (const lang of ['en', 'ko'] as const) expect(translateMaybe(lang, 'codes', r.refusal.code), `no ${lang} label for ${r.refusal.code}`).toBeTruthy()
    }
  }
  expect(await one<number>(`select count(*)::int from public.fleet_raid_orders`)).toBe(0)
})

test('lit: the door takes each order, and every word the read serves has a label in English and Korean', async () => {
  await db.pg.exec(`update public.world_config set value = 'true'::jsonb where key = 'raid_orders_enabled'`)
  for (const order of ['FLEE', 'PAY', 'FIGHT', 'FLEE'] as RaidOrderWord[]) {
    const r = await cmdRaidOrder(fleet, order)
    expect(r.ok, JSON.stringify(r)).toBe(true)
    if (r.ok) expect(r.value.order).toBe(order)
    const read = await worldRaidRead(fleet)
    expect(read.ok).toBe(true)
    if (!read.ok) return
    expect(read.value.on).toBe(true)
    expect(read.value.order).toBe(order)
    // FIGHT is no row; FLEE and PAY are one
    expect(await one<number>(`select count(*)::int from public.fleet_raid_orders where fleet_id = $1`, [fleet])).toBe(order === 'FIGHT' ? 0 : 1)
  }
  const read = await worldRaidRead(fleet)
  if (!read.ok) throw new Error('unreachable')
  // the founding barca: no guns, an empty hold, and a slip word
  expect(read.value.guns).toBe(false)
  expect(read.value.pay).toBe(0)
  expect(['poor', 'fair', 'good']).toContain(read.value.slip)
  expect(read.value.foes!.length).toBeGreaterThan(0)
  for (const lang of ['en', 'ko'] as const) {
    expect(translateMaybe(lang, 'fight', `oddsSlip_${read.value.slip}`), `no ${lang} word for slip ${read.value.slip}`).toBeTruthy()
    for (const f of read.value.foes!) {
      expect(f.danger).toBeGreaterThanOrEqual(1)
      expect(f.danger).toBeLessThanOrEqual(5)
      expect(translateMaybe(lang, 'map', `attackWord_${f.word}`), `no ${lang} word for raiders ${f.word}`).toBeTruthy()
    }
  }
  // a hold with cargo prices Pay: the server's ransom share of the cargo at cost
  await db.pg.exec(`update public.ships set cargo = '{"wine": 10}'::jsonb, cargo_basis = '{"wine": 2000}'::jsonb where fleet_id = '${fleet}'`)
  const priced = await worldRaidRead(fleet)
  expect(priced.ok && priced.value.pay).toBe(await one<number>(`select floor(20000 * public.wc_num('ransom_share'))::int`))

  // a bad word, and a fleet that is not hers
  const bad = await cmdRaidOrder(fleet, 'RUN' as RaidOrderWord)
  expect(bad.ok).toBe(false)
  if (!bad.ok) {
    expect(bad.refusal.code).toBe('E_BAD_ORDER')
    for (const lang of ['en', 'ko'] as const) expect(translateMaybe(lang, 'codes', 'E_BAD_ORDER')).toBeTruthy()
  }
  const other = await one<string>(`select f.id from public.fleets f join public.players p on p.id = f.player_id where p.is_npc limit 1`)
  if (other) {
    const r = await cmdRaidOrder(other, 'FLEE')
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.refusal.code).toBe('E_NO_SUCH_FLEET')
    const theirs = await worldRaidRead(other)
    expect(theirs.ok && theirs.value).toEqual({ on: false })
  }
})

test('lit: a raided passage sailed under Flee comes back as a log the reader takes, every round a run', async () => {
  test.setTimeout(300_000)
  await db.pg.exec(`
    update public.world_config set value = 'true'::jsonb where key in ('combat_bite', 'raid_orders_enabled');
    update public.world_config set value = '1'::jsonb where key = 'hazard_p_max';
    update public.voyage_event_kinds set mix_base = case when code = 'PIRATES' then 1 else 0.0001 end where in_sea_mix;
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = '${fleet}';`)
  expect((await cmdRaidOrder(fleet, 'FLEE')).ok).toBe(true)
  // the real departure freezes the order; every day of the passage is a raid (ledger.fights.spec's own passage)
  const voyage = await one<string>(`
    select voyage.depart(f.id, (select jsonb_agg(e || jsonb_build_object('hazard_mult', 1000) order by o)
                                  from jsonb_array_elements(voyage.segments_from_course(jsonb_build_array(
                                         jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon)))) with ordinality t(e, o)),
           a.port_id, b.port_id, now() - interval '30 days')
      from public.fleets f
      join public.sea_reaches a on a.port_id = f.port_id
      join public.sea_reaches b on b.port_id = (select id from public.ports where code = 'FNC')
     where f.id = $1`, [fleet])
  expect(await one<number>(`select count(*)::int from public.voyages v, jsonb_array_elements(v.path) e where v.id = $1 and e->>'order' is distinct from 'FLEE'`, [voyage]), 'a segment left without her order').toBe(0)
  await db.pg.query(`select voyage.settle($1, now())`, [fleet])
  const page = await worldLedger(null, 200)
  expect(page.ok).toBe(true)
  if (!page.ok) return
  const report = page.value.events.find((e) => e.kind === 'VOYAGE_REPORT' && e.payload['voyage_id'] === voyage)
  expect(report, 'no VOYAGE_REPORT for the passage').toBeTruthy()
  const fights = payloadFights(report!.payload)
  expect(fights.length, 'the forced passage met no raid: it proves nothing').toBeGreaterThan(0)
  let ran = 0
  for (const f of fights) {
    expect(f.log, 'a company raid day kept no log the reader takes').not.toBeNull()
    expect(f.log!.order).toBe('FLEE')
    expect(f.loss).not.toBeNull()
    for (const row of fightRows(f.log!)) {
      expect(row.you.kind).toBe('run')
      expect(row.slipPct).not.toBeNull()
      ran += 1
    }
    expect(['STOOD', 'SLIP', 'FLED', 'THREW', 'TERMS', 'TAKEN', 'GAVE']).toContain(f.log!.end)
    for (const lang of ['en', 'ko'] as const) expect(translateMaybe(lang, 'fight', `end_${f.log!.end}`)).toBeTruthy()
  }
  expect(ran, 'no round was run in the whole passage').toBeGreaterThan(0)
})

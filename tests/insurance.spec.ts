// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A CARGO CAN BE INSURED — 0211 (docs/dev-log/2026-10-19-insurance.md), the client's side of the contract
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The server prices and charges the insurance (public.insure_voyage, called by cmd.do_sail); the client
// only reads the quote off a SAIL's estimate (`sailEstimate(...).insurance`, the ONE reading), writes the
// grammar's word INSURED through the one line composer, and reads the book (world.insurance). This spec
// takes that seam end to end on its own in-memory world: a company founded at Lisbon with a cargo of a
// known cost previews the passage to Funchal (quoted, nothing charged), previews it INSURED (the same
// price, still nothing charged), sails it INSURED (charged once, the book has the policy, History says so),
// and the plan builder's lines carry the word on the laden legs alone.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { courseBetweenPorts, seaNav } from './seaCourse.fixture'
import { sailEstimate } from '../src/domain/order'
import { planLines } from '../src/features/command/plans/planLines'
import { headline } from '../src/features/ledger/headline'
import {
  clearBackend,
  cmdIssue,
  cmdPreview,
  createLocalBackend,
  expectOk,
  setBackend,
  worldFleets,
  worldInsurance,
  worldLedger,
  worldSnapshot,
  type FleetView,
  type SnapshotPort,
} from '../src/lib/rpc'

let db: LocalDb
let fleet: FleetView
let lis: SnapshotPort
let fnc: SnapshotPort
let portByCode: Record<string, SnapshotPort>
let course: [number, number][]
/** The cargo's cost basis: 20 units at 50 — a cargo worth exactly 1,000. */
const VALUE = 1000

const one = async <T>(sql: string, params: unknown[] = []): Promise<T> =>
  Object.values((await db.pg.query<Record<string, T>>(sql, params)).rows[0] ?? {})[0] as T

const purse = () => db.callAs<number>(`select ducats::bigint as result from public.players where id = public.current_player_id()`)
const charges = () =>
  db.callAs<number>(
    `select count(*)::int as result from public.ledger where player_id = public.current_player_id() and kind = 'INSURANCE'`,
  )

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Seguro Spec', 'PRT') as result`)
  const snap = expectOk(await worldSnapshot())
  portByCode = Object.fromEntries(snap.ports.map((p) => [p.code, p]))
  lis = portByCode['LIS']
  fnc = portByCode['FNC']
  expect(lis && fnc, 'the world has no Lisbon or no Funchal').toBeTruthy()
  fleet = expectOk(await worldFleets())[0]
  expect(fleet.port, 'the founded fleet is not docked at Lisbon').toBe('LIS')
  // a cargo of a known cost, loaded through the one load (the server's superuser side; a player would BUY)
  const good = await one<string>(`select code from public.goods where bulk = 1 order by code limit 1`)
  const loaded = await one<string>(`select public.fleet_load($1::uuid, $2::text, 20, 50)::text`, [fleet.id, good])
  expect(Number(loaded)).toBe(20)
  expect(Number(await one<string>(`select public.fleet_stock_at_cost($1::uuid)::text`, [fleet.id]))).toBe(VALUE)
  // a deep purse, so the price is never the refusal
  await db.callAs(`select public.credit(public.current_player_id(), 'SPEC', 100000)::text as result`)
  course = courseBetweenPorts(await seaNav(), lis, fnc)
  fleet = expectOk(await worldFleets())[0]
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('an unasked SAIL quotes the price and charges nothing; asked INSURED, the preview quotes the same and still charges nothing', async () => {
  const p0 = Number(await purse())
  const plain = expectOk(await cmdPreview(fleet.id, 'SAIL FNC', course))
  const quote = sailEstimate(plain.estimate).insurance
  expect(quote, 'the SAIL estimate carried no insurance quote').not.toBeNull()
  expect(quote!.insured).toBe(false)
  expect(quote!.value).toBe(VALUE)
  expect(quote!.price).toBeGreaterThanOrEqual(1)
  // the ONE price: value × risk × (1 − keep) × (1 + margin), rounded up — the server's risk, the server's knobs
  const risk = Number((plain.estimate!['insurance'] as Record<string, unknown>)['risk'])
  expect(risk).toBeGreaterThan(0)
  const keep = Number(await one<string>(`select public.wc_num('insurance_keep_pct')::text`))
  const margin = Number(await one<string>(`select public.wc_num('insurance_margin')::text`))
  expect(quote!.price).toBe(Math.max(1, Math.ceil(VALUE * risk * (1 - keep) * (1 + margin))))

  const asked = expectOk(await cmdPreview(fleet.id, 'SAIL FNC INSURED', course))
  const written = sailEstimate(asked.estimate).insurance
  expect(written).toEqual({ insured: true, value: VALUE, price: quote!.price })
  expect(await charges()).toBe(0)
  expect(Number(await purse())).toBe(p0)
})

test('SAIL … INSURED charges the price once, Lisbon insures it, and the book and History say so', async () => {
  test.setTimeout(120_000)
  const p0 = Number(await purse())
  const quote = sailEstimate(expectOk(await cmdPreview(fleet.id, 'SAIL FNC', course)).estimate).insurance!
  const sailed = expectOk(await cmdIssue(fleet.id, 'SAIL FNC INSURED', null, course))
  expect(sailed.order.status).toBe('done')
  expect(Number(await purse())).toBe(p0 - quote.price)
  expect(await charges()).toBe(1)

  const book = expectOk(await worldInsurance())
  expect(book.keep_pct).toBeGreaterThan(0)
  expect(book.active).toHaveLength(1)
  const policy = book.active[0]
  expect(policy.fleet).toBe(fleet.name)
  expect(policy.port).toBe('LIS')
  expect(policy.to).toBe('FNC')
  expect(Number(policy.value)).toBe(VALUE)
  expect(Number(policy.price)).toBe(quote.price)
  expect(Number(policy.paid)).toBe(0)
  expect(book.paid).toEqual([])

  const page = expectOk(await worldLedger(null, 50))
  const insured = page.events.find((e) => e.kind === 'INSURED')
  expect(insured, 'no INSURED event in History').toBeTruthy()
  const name = (c: string) => portByCode[c]?.name ?? c
  expect(headline(insured!, name)).toBe(`${fleet.name}'s cargo (1,000 🪙) insured at ${lis.name} for ${quote.price} 🪙.`)
  // the payout's sentence, from a payload shaped as public.insurance_claim writes it
  const paid = headline(
    {
      id: 'x',
      kind: 'INSURANCE_PAID',
      at: insured!.at,
      ducats_delta: 1800,
      balance_after: null,
      payload: { fleet: fleet.name, port: 'LIS', lost_value: 2000, owed: 1800, paid: 1800, short: 0, cause: 'PLUNDERED' },
    },
    name,
  )
  expect(paid).toBe(`${lis.name}'s insurance paid ${fleet.name} 1,800 🪙 for cargo lost to pirates (worth 2,000 🪙).`)
})

test('the plan builder writes INSURED on the laden legs alone, and only when asked', async () => {
  const nav = await seaNav()
  const docked = { ...fleet, status: 'DOCKED' as const, port: 'LIS', voyage: null }
  const base = { good: 'cloves', units: null, max: null, min: null }
  // buy at Funchal, sell at Lisbon: out empty, back laden
  const trade = planLines({ ...base, buyAt: 'FNC', sellAt: 'LIS', insure: true }, docked, nav, portByCode)
  expect(trade.ok).toBe(true)
  if (!trade.ok) return
  expect(trade.lines.map((l) => l.text)).toEqual(['SAIL FNC', 'BUY cloves ALL', 'SAIL LIS INSURED', 'SELL cloves ALL'])
  // selling what is on board: laden from the quay
  const sell = planLines({ ...base, buyAt: null, sellAt: 'FNC', insure: true }, docked, nav, portByCode)
  expect(sell.ok && sell.lines.map((l) => l.text)).toEqual(['SAIL FNC INSURED', 'SELL cloves ALL'])
  // not asked (and a draft from before 0211, with no field at all): no word anywhere
  const plain = planLines({ ...base, buyAt: 'FNC', sellAt: 'LIS' }, docked, nav, portByCode)
  expect(plain.ok && plain.lines.map((l) => l.text).join(' ')).not.toContain('INSURED')
})

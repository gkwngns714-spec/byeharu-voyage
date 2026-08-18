// PURE UNIT SPEC — the G.1 price formation and the %NBR derivation the MARKET tab is built on.
// No browser.
//
// This spec is also the CHECK ON THE FIXTURE. src/fixtures/v0.ts claims the arithmetic in it can
// be verified by hand; here it is verified by machine, against the formula in the design document
// rather than against a recorded output. If someone retunes an affinity, the numbers K.1's opening
// session depends on move, and this file says so.

import { test, expect } from '@playwright/test'
import { gcDistanceNm } from '../src/features/command/geo'
import {
  BUY_BAND_MAX,
  NEIGHBOUR_RADIUS_NM,
  SELL_BAND_MIN,
  askPrice,
  bandOf,
  bidPrice,
  buildMarketRows,
  buildPriceIndex,
  effectiveTaxRate,
  isAvailable,
  midPrice,
  nbrPercent,
  rowKey,
  spreadOf,
  steppedBuyCost,
  stockBand,
} from '../src/features/market/prices'
import { GOODS, PLAYER, PORTS, PORT_GOODS, buildV0World, FIXTURE_INSTANT_MS } from '../src/fixtures/v0'
import type { GoodCode, PortCode } from '../src/fixtures/types'

const index = buildPriceIndex(PORTS, GOODS, PORT_GOODS)
const port = (code: PortCode) => PORTS.find((p) => p.code === code)!
const good = (code: GoodCode) => GOODS.find((g) => g.code === code)!
const row = (p: PortCode, g: GoodCode) => index.rows.get(rowKey(p, g))!

test('B.3 haversine reproduces the distances the design document publishes', () => {
  const d = (a: PortCode, b: PortCode) =>
    gcDistanceNm(port(a).lat, port(a).lon, port(b).lat, port(b).lon)
  expect(Math.round(d('LIS', 'CAD'))).toBe(188)
  expect(Math.round(d('CAD', 'CEU'))).toBe(61)
  expect(Math.round(d('LIS', 'FNC'))).toBe(525)
  expect(Math.round(d('LIS', 'MRS'))).toBe(712)
  expect(Math.round(d('LIS', 'LPA'))).toBe(709)
  expect(Math.round(d('CEU', 'TUN'))).toBe(751)
})

test('spread narrows with dev_commerce and floors at 2% (G.1)', () => {
  expect(spreadOf(port('LIS'))).toBeCloseTo(0.06 - 0.002 * 17, 10)
  expect(spreadOf(port('SAF'))).toBeCloseTo(0.05, 10)
  // A hypothetical dev_commerce of 20 would give 0.02; the floor holds it there.
  expect(spreadOf({ ...port('LIS'), devCommerce: 30 })).toBe(0.02)
})

test('the player pays the Mayor rate less their relief, never below zero', () => {
  expect(effectiveTaxRate(port('LIS'), PLAYER.taxRelief)).toBeCloseTo(0.03, 10)
  expect(effectiveTaxRate(port('LIS'), 0.99)).toBe(0)
})

test('mid is the G.1 product, recomputed here from the raw terms', () => {
  const p = port('LIS')
  const g = good('sal')
  const r = row('LIS', 'sal')
  const expected =
    g.baseValue *
    r.affinity *
    Math.sqrt(r.stockTarget / r.stock) *
    (1 + r.drift) *
    (1 + r.seasonMod) *
    (1 - 0.004 * p.devCommerce)
  expect(midPrice(g, p, r)).toBeCloseTo(expected, 10)
})

test('mid is clamped to the G.1 price band, so no spike is reachable', () => {
  const g = good('sal')
  const p = port('LIS')
  const r = row('LIS', 'sal')
  expect(midPrice(g, p, { ...r, affinity: 99 })).toBe(3.5 * g.baseValue)
  expect(midPrice(g, p, { ...r, affinity: 0.001 })).toBe(0.35 * g.baseValue)
})

test('K.1 opening session: Lisboa salt asks 7 d./t and Cadiz bids 10 d./t', () => {
  const lisMid = midPrice(good('sal'), port('LIS'), row('LIS', 'sal'))!
  const cadMid = midPrice(good('sal'), port('CAD'), row('CAD', 'sal'))!
  expect(Math.round(askPrice(lisMid, port('LIS'), PLAYER.taxRelief))).toBe(7)
  expect(Math.round(bidPrice(cadMid, port('CAD'), PLAYER.taxRelief))).toBe(10)
  // Which is the ledger's 55-tun trade: -385 out, +550 back, +165 realised.
  expect(55 * 7).toBe(385)
  expect(55 * 10).toBe(550)
})

test('the ledger prices are the prices the formula produces today', () => {
  const at = (p: PortCode, g: GoodCode, side: 'ask' | 'bid') => {
    const mid = midPrice(good(g), port(p), row(p, g))!
    return Math.round(
      side === 'ask'
        ? askPrice(mid, port(p), PLAYER.taxRelief)
        : bidPrice(mid, port(p), PLAYER.taxRelief),
    )
  }
  expect(at('CAD', 'couro', 'ask')).toBe(52) // Gaivota bought 48 t at 52
  expect(at('LIS', 'couro', 'bid')).toBe(71) // and sold them at 71
  expect(at('LIS', 'trigo', 'ask')).toBe(9) // Aurora's 120 t of wheat
  expect(at('LIS', 'sal', 'ask')).toBe(7) // Aurora's 40 t of salt
})

test('%NBR is this port over the mean of the ports within 600 nm', () => {
  const neighbours = index.neighbours.get('LIS')!
  // Verify the neighbour set is a distance fact, not a list.
  for (const code of neighbours) {
    expect(gcDistanceNm(port('LIS').lat, port('LIS').lon, port(code).lat, port(code).lon))
      .toBeLessThanOrEqual(NEIGHBOUR_RADIUS_NM)
  }
  expect([...neighbours].sort()).toEqual(['CAD', 'CEU', 'FNC', 'OPO', 'SAF', 'SVQ'])

  const here = midPrice(good('sal'), port('LIS'), row('LIS', 'sal'))!
  const mean =
    neighbours
      .map((c) => midPrice(good('sal'), port(c), row(c, 'sal'))!)
      .reduce((a, b) => a + b, 0) / neighbours.length
  expect(nbrPercent(index, 'LIS', 'sal')).toBeCloseTo((here / mean) * 100, 10)
})

test('the V0 gradient reads the way E.4 promises: buy salt in Lisboa, sell it in Cadiz', () => {
  const lis = nbrPercent(index, 'LIS', 'sal')!
  const cad = nbrPercent(index, 'CAD', 'sal')!
  expect(Math.round(lis)).toBe(71)
  expect(Math.round(cad)).toBe(113)
  expect(bandOf(lis)).toBe('buy')
  expect(bandOf(cad)).toBe('sell')
  expect(lis).toBeLessThan(BUY_BAND_MAX)
  expect(cad).toBeGreaterThan(SELL_BAND_MIN)
})

test('the SOARING event puts Funchal hides at 211% — the hook K.1 ends the session on', () => {
  expect(Math.round(nbrPercent(index, 'FNC', 'couro')!)).toBe(211)
  expect(row('FNC', 'couro').event?.kind).toBe('SOARING')
})

test('a culture that refuses a good has no row and no opinion about its price', () => {
  expect(isAvailable(good('vinho'), 'maghrebi')).toBe(false)
  expect(index.rows.get(rowKey('TUN', 'vinho'))).toBeUndefined()
  expect(index.rows.get(rowKey('SAF', 'vinho'))).toBeUndefined()
  expect(nbrPercent(index, 'TUN', 'vinho')).toBeNull()
  // ... and the ports that DO trade it are not dragged toward zero by the ones that do not.
  const cadNeighbours = index.neighbours.get('CAD')!
  const trading = cadNeighbours.filter((c) => index.rows.get(rowKey(c, 'vinho')))
  expect(trading.length).toBeLessThan(cadNeighbours.length)
  expect(nbrPercent(index, 'CAD', 'vinho')).not.toBeNull()
})

test('bands split the table exactly as E.4 draws it', () => {
  expect(bandOf(62)).toBe('buy')
  expect(bandOf(89.9)).toBe('buy')
  expect(bandOf(90)).toBe('hold')
  expect(bandOf(110)).toBe('hold')
  expect(bandOf(110.1)).toBe('sell')
  expect(bandOf(null)).toBe('hold')
})

test('G.2 price impact: a bigger order pays a genuinely worse average', () => {
  const g = good('sal')
  const p = port('LIS')
  const r = row('LIS', 'sal')
  const small = steppedBuyCost(g, p, r, 10, PLAYER.taxRelief)
  const large = steppedBuyCost(g, p, r, 1000, PLAYER.taxRelief)
  expect(large.average).toBeGreaterThan(small.average)
  expect(large.filled).toBe(1000)
  // ... and the total is not simply quantity x opening price.
  const opening = askPrice(midPrice(g, p, r)!, p, PLAYER.taxRelief)
  expect(large.total).toBeGreaterThan(opening * 1000)
})

test('the stock band renders six cells and shades a real shortage', () => {
  expect(stockBand({ ...row('LIS', 'sal'), stock: 1000, stockTarget: 1000 })).toHaveLength(6)
  expect(stockBand({ ...row('LIS', 'sal'), stock: 1000, stockTarget: 1000 })).toBe('██████')
  expect(stockBand({ ...row('LIS', 'sal'), stock: 100, stockTarget: 1000 })).toBe('▓░░░░░')
})

test('every V0 good in Lisboa yields a row, a band and a seven-point history', () => {
  const rows = buildMarketRows(index, 'LIS', PLAYER.taxRelief)
  expect(rows).toHaveLength(12)
  for (const r of rows) {
    expect(r.ask).toBeGreaterThan(r.bid)
    expect(r.history7).toHaveLength(7)
    // The series ends on today's mid — sparkline and price column are one fact.
    expect(r.history7[6]).toBeCloseTo(r.mid, 1)
    expect(r.dailyCap).toBe(Math.round(0.35 * r.row.stockTarget))
  }
  expect(rows.filter((r) => r.band === 'buy').length).toBeGreaterThan(0)
  expect(rows.filter((r) => r.band === 'sell').length).toBeGreaterThan(0)
})

test('the fixture is internally closed: the ledger runs to the player balance', () => {
  const world = buildV0World(FIXTURE_INSTANT_MS)
  const last = world.ledger[world.ledger.length - 1]
  expect(last.balanceAfter).toBe(world.player.ducats)
  let running = world.ledger[0].balanceAfter - world.ledger[0].ducatsDelta
  for (const entry of world.ledger) {
    running += entry.ducatsDelta
    expect(entry.balanceAfter).toBe(running)
  }
  expect(world.ports).toHaveLength(12)
  expect(world.goods).toHaveLength(12)
  expect(world.legs).toHaveLength(22)
  expect(world.shipClasses).toHaveLength(3)
  expect(world.fleets).toHaveLength(2)
  expect(world.ships).toHaveLength(3)
  // ... and inside K.1's V0 cap of two fleets and four ships.
  expect(world.fleets.length).toBeLessThanOrEqual(world.player.maxFleets)
  expect(world.ships.length).toBeLessThanOrEqual(world.player.maxShips)
  // Exactly one flagship per fleet (C.4).
  for (const fleet of world.fleets) {
    expect(world.ships.filter((s) => s.fleetId === fleet.id && s.isFlagship)).toHaveLength(1)
  }
})

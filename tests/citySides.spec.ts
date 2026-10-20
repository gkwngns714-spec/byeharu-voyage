// PURE UNIT SPEC — src/features/command/markets/citySides.ts. No browser: this file never asks for
// the `page` fixture, so Playwright runs it as a plain Node process.
//
// WHAT IT PINS (owner request 178, 2026-10-20): both sides of a city's price come from the board's
// own two lists, joined by city, and NOTHING is derived. A side the board did not price stays null —
// it is never computed from the other side, because the spread, the tax and the city's bid factor are
// the server's (world.price_sides) and a round trip never pays (0211).

import { test, expect } from '@playwright/test'
import { citySides, sidesAt } from '../src/features/command/markets/citySides'
import type { BoardBuyRow, BoardSellRow, GoodBoard } from '../src/lib/rpc'

const buyRow = (port: string, price: number | null): BoardBuyRow =>
  ({
    port,
    name: port,
    here: false,
    units: 100,
    cost: 100,
    price_each: price,
    stock: 500,
    miles: null,
    days: null,
    arrive_at: null,
    at_arrival: null,
    best: null,
  }) as BoardBuyRow

const sellRow = (port: string, mid: number, quoted: boolean, price: number | null): BoardSellRow =>
  ({
    port,
    name: port,
    mid,
    quoted,
    miles: null,
    days: null,
    arrive_at: null,
    units: quoted ? 100 : null,
    price_each: price,
    proceeds: null,
    cost: null,
    profit_tax: null,
    port_fee: null,
    wages: null,
    net: null,
    net_per_ton: null,
    cap_left: null,
    at_arrival: null,
    best: null,
    request: null,
  }) as BoardSellRow

/** A board with the two lists only — the rest of the payload is nothing to this join. */
const board = (buy: BoardBuyRow[], sell: BoardSellRow[]): GoodBoard => ({ buy, sell }) as GoodBoard

test('a city that stands in both lists carries both sides, each from its own list', () => {
  const sides = citySides(board([buyRow('MOC', 94)], [sellRow('MOC', 90, true, 86), sellRow('LIS', 150, true, 141)]))
  expect(sides.MOC).toEqual({ pay: 94, get: 86, mid: 90 })
  // Lisbon buys it and does not sell it: there is no ask to serve, and none is invented.
  expect(sides.LIS).toEqual({ pay: null, get: 141, mid: 150 })
})

test('a sell row the board did not price in full keeps its middle price and no bid', () => {
  const sides = citySides(board([], [sellRow('CAD', 120, false, null)]))
  expect(sides.CAD).toEqual({ pay: null, get: null, mid: 120 })
})

test('a seller with no stock to fill the amount has no ask, not a nought', () => {
  const sides = citySides(board([buyRow('MOC', null)], []))
  expect(sides.MOC).toEqual({ pay: null, get: null, mid: null })
})

test('a city the board never names, and a board still on the wire, read as the empty pair', () => {
  const sides = citySides(board([buyRow('MOC', 94)], []))
  expect(sidesAt(sides, 'MOC').pay).toBe(94)
  expect(sidesAt(sides, 'LIS')).toEqual({ pay: null, get: null, mid: null })
  expect(sidesAt(sides, null)).toEqual({ pay: null, get: null, mid: null })
  expect(sidesAt(citySides(null), 'MOC')).toEqual({ pay: null, get: null, mid: null })
})

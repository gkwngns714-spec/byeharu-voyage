// PURE UNIT SPEC — src/store/manifest. No browser: this file never asks for the `page` fixture, so
// Playwright runs it as a plain Node process and no browser binary is needed.
//
// What it pins: how the staged manifest is kept tidy — one line per good, replaced in place, and
// a basket that belongs to ONE (fleet, port). Neither is a rule of the game (E_MANIFEST_DUPLICATE
// and cmd.trade_basket's two arguments are the authorities, 0083); they are what the eye sees in
// the tray, and a list that shuffled under the finger would be a defect no server assert catches.

import { test, expect } from '@playwright/test'
import { linesFor, stageLine, useManifest } from '../src/store/manifest'
import type { ManifestLine } from '../src/lib/rpc'

const buy = (good: string, qty: number): ManifestLine => ({ side: 'buy', good, qty })
const sell = (good: string, qty: number): ManifestLine => ({ side: 'sell', good, qty })

test('stageLine appends a new good and keeps the order it was staged in', () => {
  const a = stageLine([], buy('pepper', 80))
  const b = stageLine(a, sell('wool', 120))
  const c = stageLine(b, buy('olive_oil', 60))
  expect(c.map((l) => l.good)).toEqual(['pepper', 'wool', 'olive_oil'])
  // Pure: the input is never written to.
  expect(a).toHaveLength(1)
  expect(b).toHaveLength(2)
})

test('stageLine replaces the line for a good already staged, in place, on either side', () => {
  const lines = [buy('pepper', 80), sell('wool', 120), buy('olive_oil', 60)]
  // Same side, new quantity: the line keeps its position.
  const requantified = stageLine(lines, buy('wool', 40))
  expect(requantified.map((l) => `${l.side}:${l.good}:${l.qty}`)).toEqual(['buy:pepper:80', 'buy:wool:40', 'buy:olive_oil:60'])
  // The other side for the same good: still ONE line for that good — the server would refuse two
  // (E_MANIFEST_DUPLICATE), and the list must never show what the quay will not take.
  const turned = stageLine(lines, sell('pepper', 10))
  expect(turned).toHaveLength(3)
  expect(turned[0]).toEqual(sell('pepper', 10))
  expect(turned.filter((l) => l.good === 'pepper')).toHaveLength(1)
})

test('linesFor answers only the (fleet, port) the manifest belongs to', () => {
  const state = { key: { fleet: 'f1', port: 'LIS' }, lines: [buy('pepper', 80)] }
  expect(linesFor(state, 'f1', 'LIS')).toBe(state.lines)
  expect(linesFor(state, 'f2', 'LIS')).toEqual([])
  expect(linesFor(state, 'f1', 'CAD')).toEqual([])
  expect(linesFor({ key: null, lines: [] }, 'f1', 'LIS')).toEqual([])
  // The empty answer is ONE reference: a selector that returned a fresh [] per read would
  // re-render forever (worldStore's selector rule).
  expect(linesFor(state, 'f2', 'LIS')).toBe(linesFor(state, 'f1', 'CAD'))
})

test('the store: a new key drops the old lines, remove empties the key, settle spends the lines', () => {
  const s = useManifest.getState()
  s.clear()
  s.stage('f1', 'LIS', buy('pepper', 80))
  s.stage('f1', 'LIS', sell('wool', 120))
  expect(useManifest.getState().lines).toHaveLength(2)
  // Another quay: a basket cannot straddle two ports, so the old lines go.
  s.stage('f1', 'CAD', buy('salt', 10))
  expect(useManifest.getState().key).toEqual({ fleet: 'f1', port: 'CAD' })
  expect(useManifest.getState().lines).toEqual([buy('salt', 10)])
  s.remove('salt')
  expect(useManifest.getState().key).toBeNull()
  expect(useManifest.getState().lines).toEqual([])

  s.stage('f1', 'LIS', buy('pepper', 80))
  const receipt = { ok: true as const, kind: 'manifest' as const, port: 'LIS', fleet: 'f1', game_day: 1, at: '', lines: [],
    totals: { goods_at_mid: 0, tax: 0, spread: 0, haggle_saved: 0, profit: null, bought: 0, sold: 0, net: 0 },
    purse: { before: 0, after: 0 }, hold: { free_before: 0, free_after: 0, tuns_delta: 0 },
    trading: { points_before: 0, points_after: 0, delta: 0, level_before: 0, level_after: 0, turnover_after: 0 } }
  s.settle(receipt)
  expect(useManifest.getState().lines).toEqual([])
  expect(useManifest.getState().key).toBeNull()
  expect(useManifest.getState().receipt).toBe(receipt)
  s.dismissReceipt()
  expect(useManifest.getState().receipt).toBeNull()
})

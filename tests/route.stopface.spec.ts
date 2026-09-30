// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A ROUTE STOP READS AS ITS SELL AND ITS BUY — the owner, 2026-09-30, made to fail
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"right now command sell all buy all is ... in one line and not distinguished which is confusing
// and looks very simple."* A stop was ONE faint caption (`Sell all · Buy Iron, 20 units, Max 12 🪙
// each`); the editor put `Sell all` and every `Buy <good>` in one row of identical chips; the Units
// and Max fields mounted only after a chip was pressed, pushing everything below down (owner row
// 15); and the orders a route wrote reached the queue raw (`Sell iron ALL >= 12.5`).
//
// TWO HALVES:
//   1. PURE — the words. domain/order's `tradeLineWords` / `queuedOrderWords` and domain/route's
//      `routeStopLines` say each line once: side, amount, limit. No raw `ALL` or `>=` reaches a
//      player, a BUY of null units is `All that fit`, a floor is `Min`, `at_profit` is `Only sell
//      above cost` (docs/WORDS.md).
//   2. BROWSER — the face, at 390×844 and at 1440×900, with routes SWITCHED ON. The local build
//      ships routes dark (0092 `standing_routes_enabled = false`) and the page has no seam to flip
//      it, so this spec builds its own: it opens the build's pre-built world image in Node, sets
//      that one world_config row, and serves the result in place of `db/world-<fp>.tar.gz`. The
//      chain fingerprint inside the image is untouched, so the boot's pairing check passes exactly
//      as it does for the shipped image — only the flag differs.
//
// Screenshots land in this test's output folder, and also in $STOPFACE_SHOTS when it is set.

import { test, expect, type Page } from '@playwright/test'
import { copyFileSync, mkdirSync } from 'node:fs'
import path from 'node:path'
import { PHONE, ready, reachable } from './appReady.fixture'
import { serveRoutesOn } from './routesOn.fixture'
import { queuedOrderWords, tradeLineWords } from '../src/domain/order'
import { routeStopLines } from '../src/domain/route'
import type { QueuedOrder, SnapshotGood, StandingRouteStop } from '../src/lib/rpc'

// ── 1. THE WORDS ─────────────────────────────────────────────────────────────────────────────────

const GOODS = {
  iron: { name: 'Iron', category: 'metal' },
  'black-pepper': { name: 'Pepper', category: 'spice' },
} as unknown as Record<string, SnapshotGood>
const PORTS = { LIS: { name: 'Lisbon' }, CAD: { name: 'Cádiz' } }

const order = (text: string, verb: string): QueuedOrder =>
  ({ id: text, seq: 1, text, verb, status: 'pending', error_code: null, error_message: null, figures: null, result: null }) as QueuedOrder

test('a trade line is said as side, amount and limit — never ALL, never >=', () => {
  expect(tradeLineWords({ kind: 'SELL', qty: null, price_limit: null, at_profit: false })).toEqual({
    side: 'Sell',
    amount: 'All',
    limit: 'Any price',
  })
  expect(tradeLineWords({ kind: 'SELL', qty: null, price_limit: null, at_profit: true }).limit).toBe('Only sell above cost')
  expect(tradeLineWords({ kind: 'SELL', qty: 20, price_limit: 14, at_profit: false })).toEqual({
    side: 'Sell',
    amount: '20 units',
    limit: 'Min 14 🪙 each',
  })
  expect(tradeLineWords({ kind: 'BUY', qty: null, price_limit: 12, at_profit: false })).toEqual({
    side: 'Buy',
    amount: 'All that fit',
    limit: 'Max 12 🪙 each',
  })

  // The orders a route writes (0092 `cmd.standing_route_lines`), as the queue prints them.
  const words = (text: string, verb: string) => queuedOrderWords(order(text, verb), 'Gaivota', PORTS, GOODS)
  expect(words('SELL iron ALL AT >= 12.5', 'SELL')).toBe('Sell Iron · All · Min 13 🪙 each')
  expect(words('SELL black-pepper 20', 'SELL')).toBe('Sell Pepper · 20 units · Any price')
  expect(words('BUY iron ALL AT 12', 'BUY')).toBe('Buy Iron · All that fit · Max 12 🪙 each')
  expect(words('PROVISION DAYS 5', 'PROVISION')).toBe('Resupply to 5 days')
  expect(words('SAIL Gaivota TO CAD', 'SAIL')).toBe('Sail Cádiz')
  for (const t of ['SELL iron ALL AT >= 12.5', 'BUY iron ALL', 'PROVISION DAYS 5']) {
    expect(words(t, t.split(' ')[0]), t).not.toMatch(/\bALL\b|>=|DAYS/)
  }
})

test('a stop is its sell lines and its buy lines, apart', () => {
  const stop: StandingRouteStop = {
    ord: 0,
    port: 'LIS',
    repair: true,
    lines: [
      { ord: 1, kind: 'SELL', good: null, qty: null, price_limit: null, at_profit: true },
      { ord: 2, kind: 'SELL', good: 'black-pepper', qty: 20, price_limit: 14, at_profit: false },
      { ord: 3, kind: 'BUY', good: 'iron', qty: null, price_limit: 12, at_profit: false },
    ],
  } as unknown as StandingRouteStop
  const { sell, buy, quiet } = routeStopLines(stop, GOODS)
  expect(sell.map((l) => [l.name, l.amount, l.limit])).toEqual([
    ['Everything on board', 'All', 'Only sell above cost'],
    ['Pepper', '20 units', 'Min 14 🪙 each'],
  ])
  expect(buy.map((l) => [l.name, l.amount, l.limit, l.category])).toEqual([['Iron', 'All that fit', 'Max 12 🪙 each', 'metal']])
  expect(quiet).toBe('Resupply if low · Repair')
})

// ── 2. THE FACE ──────────────────────────────────────────────────────────────────────────────────

const WIDE = { width: 1440, height: 900 }

async function shot(page: Page, name: string, info: import('@playwright/test').TestInfo) {
  const file = info.outputPath(name)
  await page.screenshot({ path: file, fullPage: true })
  const out = process.env.STOPFACE_SHOTS
  if (out) {
    mkdirSync(out, { recursive: true })
    copyFileSync(file, path.join(out, name))
  }
}

type Box = { top: number; bottom: number; left: number; width: number }

test.use({ viewport: PHONE })

test('COMMAND: a route stop is a Sell group above a Buy group, a buy press moves nothing, and a running route reads the same', async ({
  page,
  request,
  baseURL,
}, info) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await serveRoutesOn(page)

  // A route cannot start without a keep level (E_NO_KEEP) — set one on FLEETS, the way a player does.
  await page.goto('fleets')
  await ready(page)
  await page.getByTestId('fleet-row').first().click()
  // The stepper's typed figure commits on Enter or blur (Stepper.tsx), never on the keystroke.
  const typed = page.getByLabel(/days of supplies to keep .* at, typed/)
  await typed.fill('10')
  await typed.press('Enter')
  await page.getByTestId('fleet-keep').click()
  await expect(page.getByTestId('fleet-keep')).toHaveCount(0, { timeout: 60_000 })
  await page.getByTestId('fleet-command').click()
  await expect(page.getByTestId('command')).toBeVisible()

  const routeRow = page.getByTestId('route-row')
  await expect(routeRow).toContainText('No route', { timeout: 60_000 })
  await routeRow.click()
  await page.getByTestId('route-setup').click()
  const stops = page.getByTestId('route-editor-stop')
  await expect(stops).toHaveCount(2)

  // Pick the second stop: the first harbour the port field offers that is not where she lies.
  await page.getByTestId('port-field').click()
  const home = (await stops.nth(0).getByTestId('route-stop-port').innerText()).trim()
  const chips = page.getByTestId('port-chip')
  await expect(chips.first()).toBeVisible()
  const n = await chips.count()
  for (let i = 0; i < n; i++) {
    if ((await chips.nth(i).innerText()).trim() !== home) {
      await chips.nth(i).click()
      break
    }
  }
  for (let i = 0; i < 2; i++) await expect(stops.nth(i).getByTestId('route-buy-good').first()).toBeVisible({ timeout: 60_000 })
  await page.waitForTimeout(400)

  // (a) Each stop: SELL and BUY are two boxes, sell wholly above buy, each with its side word.
  const groups = async (root: string) =>
    page.evaluate((sel) => {
      const box = (el: Element | null): Box | null => {
        if (!el) return null
        const r = el.getBoundingClientRect()
        return { top: Math.round(r.top), bottom: Math.round(r.bottom), left: Math.round(r.left), width: Math.round(r.width) }
      }
      return [...document.querySelectorAll(sel)].map((s) => ({
        sell: box(s.querySelector('[data-testid="route-stop-sell"]')),
        buy: box(s.querySelector('[data-testid="route-stop-buy"]')),
        sellWord: (s.querySelector('[data-testid="route-stop-sell"] > span')?.textContent ?? '').trim(),
        buyWord: (s.querySelector('[data-testid="route-stop-buy"] > span')?.textContent ?? '').trim(),
      }))
    }, root)
  const editorGroups = await groups('[data-testid="route-editor-stop"]')
  console.log(`route editor groups @${PHONE.width}px: ${JSON.stringify(editorGroups)}`)
  expect(editorGroups).toHaveLength(2)
  for (const g of editorGroups) {
    expect(g.sell, 'a stop has no Sell group').not.toBeNull()
    expect(g.buy, 'a stop has no Buy group').not.toBeNull()
    expect(g.sell!.bottom, 'Sell is not above Buy').toBeLessThanOrEqual(g.buy!.top)
    expect([g.sellWord, g.buyWord]).toEqual(['Sell', 'Buy'])
  }
  // Sell and Buy are no longer chips in one row: the sell chip is in the Sell group, the goods in Buy.
  await expect(stops.nth(0).getByTestId('route-stop-sell').getByTestId('route-sell-all')).toHaveCount(1)
  await expect(stops.nth(0).getByTestId('route-stop-sell').getByTestId('route-buy-good')).toHaveCount(0)

  // (b) Owner row 15: the Units / Max fields stand BEFORE a good is picked, and a press moves nothing.
  await expect(stops.nth(0).getByTestId('route-buy-fields')).toBeVisible()
  const below = () =>
    page.evaluate(() => {
      const top = (sel: string) => Math.round(document.querySelectorAll(sel)[0]?.getBoundingClientRect().top ?? -1)
      return {
        secondStop: Math.round(document.querySelectorAll('[data-testid="route-editor-stop"]')[1]?.getBoundingClientRect().top ?? -1),
        start: top('[data-testid="route-start"]'),
        queue: top('[data-testid="command-queue"]'),
      }
    })
  const before = await below()
  await shot(page, 'route-editor-390.png', info)
  await stops.nth(0).getByTestId('route-buy-good').first().click()
  await expect(stops.nth(0).getByTestId('route-buy-good').first()).toHaveAttribute('aria-pressed', 'true')
  await page.waitForTimeout(400)
  const after = await below()
  console.log(`route editor, before/after a buy press: ${JSON.stringify({ before, after })}`)
  expect(after, 'pressing a buy chip moved what is below it (owner row 15)').toEqual(before)
  await shot(page, 'route-editor-picked-390.png', info)

  // (c) Start it, and read the running route: the same two groups, per stop.
  await page.getByTestId('route-start').click()
  await expect(page.getByTestId('route-editor')).toHaveCount(0, { timeout: 60_000 })
  await expect(routeRow).toContainText('Route ·', { timeout: 60_000 })
  const face = page.getByTestId('route-stop')
  await expect(face).toHaveCount(2)
  const faceGroups = await groups('[data-testid="route-stop"]')
  console.log(`route face groups @${PHONE.width}px: ${JSON.stringify(faceGroups)}`)
  for (const g of faceGroups) {
    expect(g.sell!.bottom, 'Sell is not above Buy on the running route').toBeLessThanOrEqual(g.buy!.top)
    expect([g.sellWord, g.buyWord]).toEqual(['Sell', 'Buy'])
  }
  await expect(face.nth(0).getByTestId('route-stop-sell')).toContainText('Everything on board')
  await expect(face.nth(0).getByTestId('route-stop-buy')).toContainText('All that fit')
  await expect(face.nth(0).getByTestId('route-stop-buy')).toContainText('Any price')
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)

  // The queue: a route's orders, once written, read in the same words — no raw ALL / >= / DAYS.
  const rows = page.getByTestId('queue-row')
  await expect(rows.first()).toBeVisible({ timeout: 90_000 }).catch(() => undefined)
  const labels = await rows.allInnerTexts()
  console.log(`queue rows after Start: ${JSON.stringify(labels)}`)
  for (const l of labels) expect(l, 'a raw order token reached the queue').not.toMatch(/\bALL\b|>=|\bDAYS\b/)
  await shot(page, 'route-face-390.png', info)

  await page.setViewportSize(WIDE)
  await page.waitForTimeout(600)
  const wideGroups = await groups('[data-testid="route-stop"]')
  console.log(`route face groups @${WIDE.width}px: ${JSON.stringify(wideGroups)}`)
  for (const g of wideGroups) expect(g.sell!.bottom).toBeLessThanOrEqual(g.buy!.top)
  await shot(page, 'route-face-1440.png', info)
  await page.getByRole('button', { name: 'Edit' }).last().click()
  await expect(page.getByTestId('route-editor')).toBeVisible()
  await page.waitForTimeout(400)
  await shot(page, 'route-editor-1440.png', info)
})

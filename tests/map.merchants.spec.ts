// ═══════════════════════════════════════════════════════════════════════════════════════════════
// MERCHANTS ON THE CHART, AND THE SHEET (owner rows 109-111, docs/NPC_TRADERS.md §8, §11)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// UNIT: the merchants arrive through their OWN list (`model.traffic`) and nothing that is about the
// player's fleets — `model.fleets`, the roles, the opening frame's focus and motion points — ever
// sees one; `buildChartModel.length` stays 2; an own fleet wins a tie hit; a merchant's position is
// COPIED from the served one; only the open merchant (more than two served course points) draws a
// track; the eight nation inks exist and stand off the sea in both schemes.
//
// BROWSER, with the merchants switched on (tests/npcOn.fixture.ts): at 390 × 844 from a Lisbon
// start, merchant hulls are on the opening frame; a sailing one MOVES between beats; a tap opens the
// read-only sheet (company, route, earnings, laps, ships, officers, Skills) with no button but the
// tray's own; the player's own fleet tray does not open (the command draft is not touched); PORT at
// Lisbon lists the merchant laid up there and opens the same sheet. With the shipped image (switch
// OFF) there are no merchant hulls and no "Merchants in port". Screenshots land in docs/npc-traders/.

import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { PHONE, reachable, ready } from './appReady.fixture'
import { LAID_UP_AT_LISBON, serveNpcOn } from './npcOn.fixture'
import { buildChartModel, hitTest, mapTrafficOf, type MapFleet, type MapPort } from '../src/chart'
import type { TrafficFleet } from '../src/lib/rpc'
import { project } from '../src/lib/geo'

const SHOTS = path.resolve('docs', 'npc-traders')

// ── UNIT ───────────────────────────────────────────────────────────────────────────────────────

const LIS: MapPort = {
  code: 'LIS', name: 'Lisbon', country: 'Portugal', lat: 38.7, lon: -9.14, sizeTier: 5, kind: 'HARBOUR',
  roadstead: { lat: 38.6, lon: -9.4 }, roadsteadNm: 12,
}
const FNC: MapPort = {
  code: 'FNC', name: 'Funchal', country: 'Portugal', lat: 32.65, lon: -16.9, sizeTier: 3, kind: 'HARBOUR',
  roadstead: { lat: 32.6, lon: -16.95 }, roadsteadNm: 3,
}
const OWN: MapFleet = { kind: 'docked', id: 'own-1', name: 'Gaivota', enduranceDays: 20, portCode: 'LIS' }

function sailingRow(id: string, course: [number, number][], at: [number, number]): TrafficFleet {
  return {
    id, company: 'Casa da Prova', nation_code: 'PRT', ink: 'prt', name: `Prova ${id}`, status: 'SAILING', ships: 2,
    port: null, roadstead: null, anchor: null, next_lap_at: null,
    voyage: {
      to: 'FNC', dest_point: null, course, eta: new Date(Date.now() + 60_000).toISOString(), total_nm: 500, nm_done: 100,
      waters: [], departed_at: new Date(Date.now() - 30_000).toISOString(),
      position: { seg_index: 0, leg_frac: 0.25, nm_done: 100, total_nm: 500, lat: at[0], lon: at[1], seg_nm: 400 },
    },
  }
}
const dockedRow: TrafficFleet = {
  id: 'm-dock', company: 'Casa da Prova', nation_code: 'PRT', ink: 'prt', name: 'Prova Doca', status: 'DOCKED', ships: 2,
  port: 'LIS', roadstead: [38.6, -9.4], anchor: null, voyage: null, next_lap_at: new Date(Date.now() + 90_000).toISOString(),
}

test('merchants live in their own list and nothing about your fleets sees them', () => {
  expect(buildChartModel.length).toBe(2)
  const rows = [sailingRow('m-1', [[38.6, -9.4], [32.6, -16.95]], [37.1, -11.3]), dockedRow]
  const traffic = mapTrafficOf(rows)
  const bare = buildChartModel([OWN], [LIS, FNC])
  const withTraffic = buildChartModel([OWN], [LIS, FNC], [], null, traffic)
  expect(withTraffic.traffic).toHaveLength(2)
  expect(withTraffic.fleets).toEqual(bare.fleets)
  expect(withTraffic.focusPoints).toEqual(bare.focusPoints)
  expect(withTraffic.motionPoints).toEqual(bare.motionPoints)
  expect([...withTraffic.portRoles]).toEqual([...bare.portRoles])
  expect([...withTraffic.destinationPoints]).toEqual([...bare.destinationPoints])
  // POSITION COPIED: the served point, and the docked merchant at the served roadstead
  expect(withTraffic.traffic[0].at).toEqual({ lat: 37.1, lon: -11.3 })
  expect(withTraffic.traffic[1].at).toEqual({ lat: 38.6, lon: -9.4 })
  expect(traffic[1].docked).toBe(true)
  expect(traffic[1].berthCode).toBe('LIS')
  // NO TRACK for a merchant served the current segment only; one for the open merchant's full course
  expect(withTraffic.traffic[0].track).toBeNull()
  const open = mapTrafficOf(rows, {
    id: 'm-1',
    voyage: { ...rows[0].voyage!, id: 'v-1', course: [[38.6, -9.4], [36, -12], [32.6, -16.95]] },
  })
  const openModel = buildChartModel([OWN], [LIS, FNC], [], null, open)
  expect(openModel.traffic[0].track).not.toBeNull()
  expect(openModel.traffic[1].track).toBeNull()
})

test('an own fleet wins a tie with a merchant; a merchant wins over open water', () => {
  const own: MapFleet = { kind: 'anchored', id: 'own-2', name: 'Gaivota', enduranceDays: 20, at: { lat: 37.1, lon: -11.3 } }
  const traffic = mapTrafficOf([sailingRow('m-1', [[38.6, -9.4], [32.6, -16.95]], [37.1, -11.3])])
  const model = buildChartModel([own], [LIS, FNC], [], null, traffic)
  const at = project({ lat: 37.1, lon: -11.3 })
  expect(hitTest(model, [], at, 1)).toEqual({ kind: 'fleet', id: 'own-2' })
  const alone = buildChartModel([], [LIS, FNC], [], null, traffic)
  expect(hitTest(alone, [], at, 1)).toEqual({ kind: 'merchant', id: 'm-1' })
})

// ── BROWSER ────────────────────────────────────────────────────────────────────────────────────

test.use({ viewport: PHONE })

async function merchantsInView(page: Page): Promise<{ total: number; inView: number; sailing: number }> {
  return page.evaluate(() => {
    const chart = document.querySelector('[data-testid="map-chart"]')!.getBoundingClientRect()
    const hulls = [...document.querySelectorAll('[data-testid="map-merchant"]')]
    let inView = 0
    let sailing = 0
    for (const h of hulls) {
      const r = h.getBoundingClientRect()
      const cx = r.left + r.width / 2
      const cy = r.top + r.height / 2
      if (cx >= chart.left && cx <= chart.right && cy >= chart.top && cy <= chart.bottom) inView++
      if (h.getAttribute('data-merchant-docked') === 'false') sailing++
    }
    return { total: hulls.length, inView, sailing }
  })
}


/** A merchant hull whose centre is on the chart's glass, so a tap can land on it. */
async function hullInView(page: Page, sailing: boolean): Promise<string> {
  const id = await page.evaluate((wantSailing) => {
    const chart = document.querySelector('[data-testid="map-chart"]')!.getBoundingClientRect()
    for (const h of document.querySelectorAll('[data-testid="map-merchant"]')) {
      if ((h.getAttribute('data-merchant-docked') === 'false') !== wantSailing) continue
      const r = h.getBoundingClientRect()
      const cx = r.left + r.width / 2
      const cy = r.top + r.height / 2
      if (cx > chart.left + 60 && cx < chart.right - 120 && cy > chart.top + 100 && cy < chart.bottom - 120) {
        return h.getAttribute('data-merchant-id')
      }
    }
    return null
  }, sailing)
  if (!id) throw new Error(`no ${sailing ? 'sailing' : 'docked'} merchant hull on the glass`)
  return id
}

/** Tap a merchant hull where it is drawn NOW (it drifts between frames). */
async function tapHull(page: Page, id: string): Promise<void> {
  const box = await page.locator(`[data-merchant-id="${id}"]`).boundingBox()
  if (!box) throw new Error('the hull has no box')
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2)
}

test('the merchants sail on the chart, and a tap opens a read-only sheet', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  mkdirSync(SHOTS, { recursive: true })
  await serveNpcOn(page)
  await page.goto('map')
  await ready(page)

  // ON THE OPENING FRAME of a Lisbon start: merchant hulls, at sea and at anchor.
  await expect.poll(async () => (await merchantsInView(page)).inView, { timeout: 60_000 }).toBeGreaterThanOrEqual(2)
  const seen = await merchantsInView(page)
  expect(seen.total).toBeGreaterThanOrEqual(20)
  await page.screenshot({ path: path.join(SHOTS, 'map-merchants-390.png') })

  // A SAILING HULL MOVES between beats (the served segment, drifted by the one clock).
  const sailingId = await hullInView(page, true)
  const hull = page.locator(`[data-merchant-id="${sailingId}"]`)
  const t0 = await hull.getAttribute('transform')
  await expect.poll(async () => hull.getAttribute('transform'), { timeout: 30_000 }).not.toBe(t0)

  // A TAP OPENS THE SHEET — and never the player's own fleet tray.
  await tapHull(page, sailingId)
  const sheet = page.getByTestId('merchant-sheet')
  await expect(sheet).toBeVisible({ timeout: 30_000 })
  await expect(page.getByTestId('map-detail-tray')).toHaveCount(0)
  await expect(page.getByTestId('merchant-sheet-body')).toBeVisible({ timeout: 60_000 })
  // her leg is drawn while she is open
  await expect(page.getByTestId('map-merchant-track')).toHaveCount(1, { timeout: 30_000 })

  // half: earnings, laps, route, fortune, blurb
  await expect(page.getByTestId('merchant-earnings-day')).toBeVisible()
  await expect(page.getByTestId('merchant-route')).toContainText('→')
  await expect(page.getByTestId('merchant-blurb')).not.toBeEmpty()
  // full: ships, officers, Skills
  await expect(page.getByTestId('merchant-ship-tile').first()).toBeAttached()
  expect(await page.getByTestId('merchant-ship-tile').count()).toBeGreaterThanOrEqual(1)
  await expect(page.locator('[data-testid^="skill-"]')).toHaveCount(4)
  await expect(sheet.getByText('Skills', { exact: true })).toBeAttached()
  await expect(sheet.getByText('Officers', { exact: true })).toBeAttached()
  // READ-ONLY: the only buttons are the tray's own (its handle and its close)
  const labels = await sheet.locator('button').evaluateAll((bs) => bs.map((b) => b.getAttribute('aria-label') ?? b.textContent ?? ''))
  expect(labels.length).toBeGreaterThan(0)
  for (const l of labels) expect(l).toMatch(/^(Close|Resize)$/)
  await page.screenshot({ path: path.join(SHOTS, 'merchant-sheet-peek-390.png') })

  // open it to full (the handle steps the detent from the keyboard) and record the ships, officers, Skills
  const resize = sheet.getByRole('button', { name: 'Resize' })
  await resize.press('ArrowUp')
  await resize.press('ArrowUp')
  await page.waitForTimeout(600)
  await page.screenshot({ path: path.join(SHOTS, 'merchant-sheet-full-390.png') })
  // the officers and the company's Skills, further down the same sheet
  await page.locator('[data-testid^="skill-"]').last().scrollIntoViewIfNeeded()
  await page.waitForTimeout(300)
  await page.screenshot({ path: path.join(SHOTS, 'merchant-sheet-officers-skills-390.png') })
})

test('PORT at Lisbon lists the merchant in port and opens the same sheet', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await serveNpcOn(page)
  await page.goto('port')
  await ready(page)
  const section = page.getByTestId('port-merchants')
  await expect(section).toBeVisible({ timeout: 60_000 })
  const row = section.getByTestId('port-merchant-row').filter({ hasText: LAID_UP_AT_LISBON })
  await expect(row).toHaveCount(1)
  await row.click()
  await expect(page.getByTestId('merchant-sheet')).toBeVisible()
  await expect(page.getByTestId('merchant-sheet-name')).toHaveText(LAID_UP_AT_LISBON, { timeout: 60_000 })
  mkdirSync(SHOTS, { recursive: true })
  await page.screenshot({ path: path.join(SHOTS, 'port-merchants-390.png') })
})

test.describe('wide', () => {
  test.use({ viewport: { width: 1280, height: 800 } })
  test('the merchants at 1280 × 800, with one open', async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    mkdirSync(SHOTS, { recursive: true })
    await serveNpcOn(page)
    await page.goto('map')
    await ready(page)
    await expect.poll(async () => (await merchantsInView(page)).inView, { timeout: 60_000 }).toBeGreaterThanOrEqual(2)
    await page.screenshot({ path: path.join(SHOTS, 'map-merchants-1280.png') })
    await tapHull(page, await hullInView(page, true))
    await expect(page.getByTestId('merchant-sheet-body')).toBeVisible({ timeout: 60_000 })
    await page.waitForTimeout(800)
    await page.screenshot({ path: path.join(SHOTS, 'merchant-sheet-1280.png') })
  })
})

test('with the shipped image (merchants dark) there are no merchant hulls and no merchants in port', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.goto('map')
  await ready(page)
  await expect(page.getByTestId('map-chart')).toBeVisible({ timeout: 60_000 })
  // longer than one of the shell's 3-s beats, so a traffic read would have landed
  await page.waitForTimeout(7_000)
  await expect(page.getByTestId('map-merchant')).toHaveCount(0)
  await page.goto('port')
  await ready(page)
  await expect(page.getByTestId('port')).toBeVisible()
  await expect(page.getByTestId('port-merchants')).toHaveCount(0)
})

test('the eight nation inks exist in both schemes and stand off the sea', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.goto('map')
  await ready(page)
  for (const theme of ['dark', 'light'] as const) {
    const ratios = await page.evaluate((t) => {
      document.documentElement.setAttribute('data-theme', t)
      const css = getComputedStyle(document.documentElement)
      const canvas = document.createElement('canvas')
      canvas.width = canvas.height = 1
      const ctx = canvas.getContext('2d', { willReadFrequently: true })!
      const rgb = (v: string) => {
        ctx.clearRect(0, 0, 1, 1)
        ctx.fillStyle = '#000'
        ctx.fillStyle = v
        ctx.fillRect(0, 0, 1, 1)
        const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data
        return [r, g, b].map((c) => {
          const x = c / 255
          return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4
        })
      }
      const lum = (v: string) => {
        const [r, g, b] = rgb(v)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
      }
      const sea = lum(css.getPropertyValue('--color-chart-sea').trim())
      const out: Record<string, number> = {}
      for (const n of ['prt', 'esp', 'nld', 'eng', 'han', 'ita', 'ott', 'east']) {
        const v = css.getPropertyValue(`--color-nation-${n}`).trim()
        if (!v) { out[n] = 0; continue }
        const l = lum(v)
        out[n] = (Math.max(l, sea) + 0.05) / (Math.min(l, sea) + 0.05)
      }
      return out
    }, theme)
    for (const [n, ratio] of Object.entries(ratios)) {
      expect(ratio, `${theme}: --color-nation-${n} against the sea`).toBeGreaterThanOrEqual(3)
    }
  }
})

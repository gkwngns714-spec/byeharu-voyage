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
  // POSITION COPIED for a merchant at sea: the served point, exactly.
  expect(withTraffic.traffic[0].at).toEqual({ lat: 37.1, lon: -11.3 })
  // A MERCHANT IN PORT lies at her own BERTH on the served roads — the roads are an anchorage, not
  // a pinpoint, and the server serves one point for them (./liveWorld.ts `fannedBerth`). Her place
  // is within the berth ring of that point, and it is hers alone (asserted below).
  const berth = withTraffic.traffic[1].at
  expect(Math.abs(berth.lat - 38.6)).toBeLessThanOrEqual(0.1)
  expect(Math.abs(berth.lon - -9.4)).toBeLessThanOrEqual(0.2)
  expect(traffic[1].docked).toBe(true)
  expect(traffic[1].berthCode).toBe('LIS')
  // NO TRACK for a merchant served the current segment only; one for the open merchant's full course
  expect(withTraffic.traffic[0].track).toBeNull()
  const openRows = [sailingRow('m-1', [[38.6, -9.4], [36, -12]], [37.1, -11.3]), dockedRow]
  const open = mapTrafficOf(openRows, {
    id: 'm-1',
    voyage: { ...openRows[0].voyage!, course: [[38.6, -9.4], [36, -12], [32.6, -16.95]] },
  })
  const openModel = buildChartModel([OWN], [LIS, FNC], [], null, open)
  expect(openModel.traffic[0].track).not.toBeNull()
  expect(openModel.traffic[1].track).toBeNull()
})

// THE CARD LENDS A TRACK AND NEVER A POSITION. The card is re-asked on the beat and lands after it,
// so a selected hull placed from the card's own voyage stepped BACKWARDS on every beat and then
// leapt forward when the new card arrived (measured at 390: -25.2 / -20.0 / -6.5 px, each followed
// ~70 ms later by a +20.9..+24.6 px leap; no unselected hull ever moved backwards). These two hold
// the rule: the position is the beat's, the polyline may be the card's, and a card that does not
// contain the served segment lends nothing at all.
test('the open merchant takes her TRACK from the card and her POSITION from the beat', () => {
  const row = sailingRow('m-1', [[38.6, -9.4], [36, -12]], [37.1, -11.3])
  const stale = {
    ...row.voyage!,
    course: [[38.6, -9.4], [36, -12], [32.6, -16.95]] as [number, number][],
    // the card is a beat behind AND further along: neither figure may reach the chart
    position: { ...row.voyage!.position!, seg_index: 1, leg_frac: 0.8, lat: 34.2, lon: -14.1 },
  }
  const [m] = mapTrafficOf([row], { id: 'm-1', voyage: stale })
  if (m.kind !== 'sailing') throw new Error('the probe merchant is at sea')
  expect(m.voyage.at).toEqual({ lat: 37.1, lon: -11.3 })
  expect(m.voyage.legFrac).toBe(0.25)
  // the WHOLE course, with the served segment located inside it
  expect(m.voyage.course).toHaveLength(3)
  expect(m.voyage.segIndex).toBe(0)
  const model = buildChartModel([OWN], [LIS, FNC], [], null, [m])
  expect(model.traffic[0].at).toEqual({ lat: 37.1, lon: -11.3 })
  expect(model.traffic[0].track).not.toBeNull()
})

test('the open merchant draws the whole loop she runs, not only the leg she is on', () => {
  // OWNER ROW 112: "show routes for the ships of npcs as well". The card serves the BAKED courses
  // of her loop (0099); the chart draws them under the leg she is on, and for a merchant in port
  // as well — a route is what she runs, not what she is doing this minute.
  const row = sailingRow('m-1', [[38.6, -9.4], [36, -12]], [37.1, -11.3])
  const legs = [
    { course: [[38.6, -9.4], [36, -12]] as [number, number][] },
    { course: [[36, -12], [32.6, -16.95]] as [number, number][] },
    { course: [[32.6, -16.95], [38.6, -9.4]] as [number, number][] },
  ]
  const open = mapTrafficOf([row, dockedRow], { id: 'm-1', voyage: row.voyage, legs })
  expect(open[0].loop).toHaveLength(3)
  expect(open[1].loop).toBeNull()
  const model = buildChartModel([OWN], [LIS, FNC], [], null, open)
  expect(model.traffic[0].loopD).toBeTruthy()
  expect(model.traffic[1].loopD).toBeNull()
  // and a merchant lying in PORT draws her loop too, with no leg of her own
  const berthed = mapTrafficOf([dockedRow], { id: dockedRow.id, voyage: null, legs })
  const berthedModel = buildChartModel([], [LIS, FNC], [], null, berthed)
  expect(berthedModel.traffic[0].loopD).toBeTruthy()
  expect(berthedModel.traffic[0].track).toBeNull()
  // a leg of fewer than two points is never drawn as a guessed line
  const degenerate = mapTrafficOf([row], { id: 'm-1', voyage: row.voyage, legs: [{ course: [[38.6, -9.4]] }] })
  expect(degenerate[0].loop).toHaveLength(0)
})

test('a card that does not hold the served segment lends nothing', () => {
  // she has moved on to the next leg; the card still carries the one before it
  const row = sailingRow('m-1', [[36, -12], [32.6, -16.95]], [34, -14])
  const behind = {
    ...row.voyage!,
    course: [[38.6, -9.4], [36, -12]] as [number, number][],
    position: { ...row.voyage!.position!, lat: 38, lon: -10 },
  }
  const [m] = mapTrafficOf([row], { id: 'm-1', voyage: behind })
  if (m.kind !== 'sailing') throw new Error('the probe merchant is at sea')
  expect(m.voyage.course).toEqual([{ lat: 36, lon: -12 }, { lat: 32.6, lon: -16.95 }])
  expect(m.voyage.at).toEqual({ lat: 34, lon: -14 })
  expect(m.voyage.segIndex).toBe(0)
})

test('merchants lying at one berth are fanned, and the harbour keeps its own dot', () => {
  const second: TrafficFleet = { ...dockedRow, id: 'm-dock-2', name: 'Prova Doca II' }
  const third: TrafficFleet = { ...dockedRow, id: 'm-dock-3', name: 'Prova Doca III' }
  const traffic = mapTrafficOf([dockedRow, second, third])
  const at = traffic.map((t) => (t.kind === 'anchored' ? `${t.at.lat},${t.at.lon}` : 'sailing'))
  expect(new Set(at).size).toBe(3)
  // AND HER PLACE IS HERS: the same three, with one of them gone and a fourth arrived, leave every
  // remaining hull exactly where she was. A slot counted off the served list moved them all.
  const fourth: TrafficFleet = { ...dockedRow, id: 'm-dock-4', name: 'Prova Doca IV' }
  const later = mapTrafficOf([second, fourth, third])
  const placeOf = (rows: ReturnType<typeof mapTrafficOf>, id: string) => {
    const m = rows.find((t) => t.id === id)
    return m && m.kind === 'anchored' ? `${m.at.lat},${m.at.lon}` : null
  }
  expect(placeOf(later, 'm-dock-2')).toBe(placeOf(traffic, 'm-dock-2'))
  expect(placeOf(later, 'm-dock-3')).toBe(placeOf(traffic, 'm-dock-3'))
  // and each of the three can be opened from the chart, which a stack of three could not be
  const model = buildChartModel([], [LIS, FNC], [], null, traffic)
  const opened = new Set<string>()
  for (const t of model.traffic) {
    const hit = hitTest(model, [], project(t.at), 1)
    if (hit?.kind === 'merchant') opened.add(hit.id)
  }
  expect(opened).toEqual(new Set(['m-dock', 'm-dock-2', 'm-dock-3']))
  // THE DOT CITY KEEPS ITS TAP: Lisbon is drawn as a dot, a merchant is moored on it, and a tap on
  // the mark opens the PORT — the hull answers only at the dot's own reach.
  const onLisbon = mapTrafficOf([{ ...dockedRow, roadstead: [LIS.lat, LIS.lon] }])
  const dotModel = buildChartModel([], [LIS, FNC], [], null, onLisbon)
  const atMark = project({ lat: LIS.lat, lon: LIS.lon })
  expect(hitTest(dotModel, [], atMark, 40, [LIS], 20)).toEqual({ kind: 'port', code: 'LIS' })
  // AND THE REACH ITSELF, which the tie above cannot see: a tap BETWEEN the dot's reach and the
  // full mark reach used to open the merchant moored on the city. It now answers nothing, which is
  // the tap landing on open water beside the harbour.
  const berthed = onLisbon[0]
  if (berthed.kind !== 'anchored') throw new Error('the probe merchant lies in port')
  const off = project(berthed.at)
  expect(hitTest(dotModel, [], { x: off.x + 30, y: off.y }, 40, [LIS], 20)).toBeNull()
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
async function hullInView(page: Page, sailing: boolean | null, skip: ReadonlySet<string> = new Set()): Promise<string> {
  // OPEN WATER FIRST, THEN ANYWHERE. A hull within a harbour's reach loses the tap to the harbour —
  // correctly — so a hull clear of every mark is the one to aim at. But on a frame where every
  // visible merchant is lying at a quay there is no such hull, and refusing to pick one at all
  // turned a crowded sea into "no merchant hull on the glass" (CI, 2026-10-11). So the clear ones
  // are preferred and the rest are the fallback; `tapHull` proves the tap landed either way.
  return (
    (await hullInViewClearOf(page, sailing, skip, 48)) ||
    (await hullInViewClearOf(page, sailing, skip, 20)) ||
    (await hullInViewClearOf(page, sailing, skip, 0))
  )
}

async function hullInViewClearOf(
  page: Page,
  sailing: boolean | null,
  skip: ReadonlySet<string>,
  clearPx: number,
): Promise<string> {
  const id = await page.evaluate(
    ({ wantSailing, seen, clear }) => {
      const chart = document.querySelector('[data-testid="map-chart"]')!.getBoundingClientRect()
      for (const h of document.querySelectorAll('[data-testid="map-merchant"]')) {
        if (wantSailing !== null && (h.getAttribute('data-merchant-docked') === 'false') !== wantSailing) continue
        const mid = h.getAttribute('data-merchant-id')
        if (mid && seen.includes(mid)) continue
        const r = h.getBoundingClientRect()
        const cx = r.left + r.width / 2
        const cy = r.top + r.height / 2
        if (!(cx > chart.left + 60 && cx < chart.right - 120 && cy > chart.top + 100 && cy < chart.bottom - 120)) continue
        // AND IN OPEN WATER. A hull lying within a harbour's own reach loses the tap to the
        // harbour — correctly: a mark as near as a hull is the city (hitTest.ts, and a berthed
        // merchant answers only at the dot's reach). With 76 fleets on the sea that case is common
        // enough that a spec which ignores it taps a port six times and calls the feature broken.
        // The tie rule has its own unit test; this one is about opening a merchant.
        let nearMark = false
        if (clear > 0) {
          // YOUR OWN FLEETS COUNT AS MARKS HERE. An own fleet wins a tie with a merchant by the
          // chart's own rule (hitTest.ts), so a merchant drifting over Gaivota at her quay cannot
          // be opened — correctly — and a spec that aims there taps the player's own tray six times.
          for (const own of document.querySelectorAll('[data-testid="map-ship"]')) {
            const orr = own.getBoundingClientRect()
            if (orr.width === 0 && orr.height === 0) continue
            const dx = orr.left + orr.width / 2 - cx
            const dy = orr.top + orr.height / 2 - cy
            if (Math.hypot(dx, dy) < clear) { nearMark = true; break }
          }
          if (nearMark) continue
          for (const p of document.querySelectorAll('[data-port-code]')) {
            const pr = p.getBoundingClientRect()
            if (pr.width === 0 && pr.height === 0) continue
            const dx = pr.left + pr.width / 2 - cx
            const dy = pr.top + pr.height / 2 - cy
            if (Math.hypot(dx, dy) < clear) { nearMark = true; break }
          }
        }
        if (!nearMark) return mid
      }
      return null
    },
    { wantSailing: sailing, seen: [...skip], clear: clearPx },
  )
  if (!id && skip.size === 0 && clearPx === 0) {
    throw new Error(`no ${sailing === null ? '' : sailing ? 'sailing ' : 'docked '}merchant hull on the glass`)
  }
  return id ?? ''
}

/**
 * Open a merchant the record can say something about — one with a LAP AVERAGE on her sheet.
 *
 * The owner read `docs/npc-traders/merchant-sheet-1280.png` on 2026-10-08 and found an earnings
 * sheet showing `0` and `no lap yet`: a true reading of a merchant that had not finished anything,
 * and a useless picture of the feature. The fixture warps a few legs, so WHICH merchants have laps
 * behind them depends on their loops; this tries the hulls on the glass until one of them has a
 * figure, and settles for the last one if none has (the shot is still taken, the test still
 * passes — a screenshot is not an assertion).
 *
 * Returns the id that is open.
 */
async function openMerchantWorthReading(page: Page, sailing: boolean | null): Promise<string> {
  const tried = new Set<string>()
  let last = ''
  for (let attempt = 1; attempt <= 3; attempt++) {
    const id = await hullInView(page, sailing, tried)
    if (!id) break
    tried.add(id)
    last = id
    await tapHull(page, id)
    await expect(page.getByTestId('merchant-sheet-body')).toBeVisible({ timeout: 60_000 })
    const lap = await page.getByTestId('merchant-earnings-lap').textContent()
    // a lap average is printed as `≈ <figure>`; the two absences say so in words
    if (lap && lap.includes('≈')) return id
    // Only give this one up for a candidate that EXISTS: closing the sheet and then finding nothing
    // else on the glass would leave the caller with no sheet at all, which is how this helper went
    // red on its first run.
    if (attempt === 3 || !(await hullInView(page, sailing, tried))) break
    const close = page.getByTestId('tray-close')
    if (await close.isVisible().catch(() => false)) await close.click()
  }
  if (!last) throw new Error('no merchant hull on the glass to open')
  // Whatever the path above took, the caller is handed an OPEN sheet.
  if (!(await page.getByTestId('merchant-sheet').isVisible().catch(() => false))) await tapHull(page, last)
  await expect(page.getByTestId('merchant-sheet-body')).toBeVisible({ timeout: 60_000 })
  return last
}

/**
 * Tap a merchant hull where it is drawn NOW, and PROVE the tap landed on her.
 *
 * A hull at sea drifts every frame, so a click aimed at a box measured a moment ago can land beside
 * her — and if she has drifted over one of YOUR fleets, the chart gives the tap to your fleet by its
 * own tie rule (hitTest.ts: an own fleet wins a tie). That is correct behaviour and a race this
 * suite used to lose about one run in five, opening `Gaivota · Lisbon` instead of the sheet. So the
 * tap is AIMED AGAIN at her new place, with whatever else it selected closed first, instead of
 * being asserted once and hoped for.
 */
async function tapHull(page: Page, id: string): Promise<void> {
  const sheet = page.getByTestId('merchant-sheet')
  for (let aim = 1; aim <= 6; aim++) {
    const box = await page.locator(`[data-merchant-id="${id}"]`).boundingBox()
    if (!box) throw new Error(`merchant ${id} has no hull on the glass`)
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2)
    try {
      await sheet.waitFor({ state: 'visible', timeout: 3_000 })
      return
    } catch {
      // something else took the tap: close it, and aim at where she is now.
      const close = page.getByTestId('tray-close')
      if (await close.isVisible().catch(() => false)) await close.click()
    }
  }
  throw new Error(`six taps at merchant ${id} never opened her sheet`)
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

  // A TAP OPENS THE SHEET — and never the player's own fleet tray. The merchant opened is one with
  // something in her books if any hull on the glass has (the shots below are the feature's record).
  await openMerchantWorthReading(page, true)
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
    // the wide frame sits close on Lisbon: whichever merchant is on the glass, at sea or at anchor —
    // preferring one whose sheet has a lap figure to show (see openMerchantWorthReading)
    await openMerchantWorthReading(page, null)
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

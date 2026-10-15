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

import { test, expect, type Locator, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { PHONE, reachable, ready } from './appReady.fixture'
import { LAID_UP_AT_LISBON, RESTING_AT_PORTO, RESTING_PORT_CODE, serveNpcOn } from './npcOn.fixture'
import { buildChartModel, hitTest, mapTrafficOf, type MapFleet, type MapPort } from '../src/chart'
import type { MerchantDoing, PortMerchant, TrafficFleet } from '../src/lib/rpc'
import { project } from '../src/lib/geo'
import { harbourSides, merchantsSummary } from '../src/live/merchantGroups'

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
    id, company: 'Casa da Prova', nation_code: 'PRT', ink: 'prt', name: `Prova ${id}`, status: 'SAILING',
    ships: 2, hulls: ['nau', 'barca'],
    port: null, roadstead: null, anchor: null, next_lap_at: null, lane: null,
    voyage: {
      to: 'FNC', dest_point: null, course, eta: new Date(Date.now() + 60_000).toISOString(), total_nm: 500, nm_done: 100,
      waters: [], departed_at: new Date(Date.now() - 30_000).toISOString(),
      position: { seg_index: 0, leg_frac: 0.25, nm_done: 100, total_nm: 500, lat: at[0], lon: at[1], seg_nm: 400 },
    },
  }
}
const dockedRow: TrafficFleet = {
  id: 'm-dock', company: 'Casa da Prova', nation_code: 'PRT', ink: 'prt', name: 'Prova Doca', status: 'DOCKED',
  ships: 2, hulls: ['carlat', 'barca'],
  port: 'LIS', roadstead: [38.6, -9.4], anchor: null, voyage: null, next_lap_at: new Date(Date.now() + 90_000).toISOString(),
  lane: null,
}

test('merchants live in their own list and nothing about your fleets sees them', () => {
  expect(buildChartModel.length).toBe(2)
  const rows = [sailingRow('m-1', [[38.6, -9.4], [32.6, -16.95]], [37.1, -11.3]), dockedRow]
  const traffic = mapTrafficOf(rows)
  const bare = buildChartModel([OWN], [LIS, FNC])
  const withTraffic = buildChartModel([OWN], [LIS, FNC], [], null, traffic)
  // RESTING MERCHANTS ARE NOT ON THE CHART (owner, 2026-10-13): a merchant in port is counted in her city's tray instead.
  expect(withTraffic.traffic).toHaveLength(1)
  expect(withTraffic.fleets).toEqual(bare.fleets)
  expect(withTraffic.focusPoints).toEqual(bare.focusPoints)
  expect(withTraffic.motionPoints).toEqual(bare.motionPoints)
  expect([...withTraffic.portRoles]).toEqual([...bare.portRoles])
  expect([...withTraffic.destinationPoints]).toEqual([...bare.destinationPoints])
  // POSITION COPIED for a merchant at sea: the served point, exactly.
  expect(withTraffic.traffic[0].at).toEqual({ lat: 37.1, lon: -11.3 })
  // A MERCHANT IN PORT is still mapped (her berth is kept for her card), but the model drops her.
  expect(withTraffic.traffic.some((t) => t.fleet.id === dockedRow.id)).toBe(false)
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
  expect(openModel.traffic).toHaveLength(1)
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
  expect(model.traffic).toHaveLength(1)
  // a merchant lying in PORT is not on the chart at all, loop or not (owner, 2026-10-13)
  const berthed = mapTrafficOf([dockedRow], { id: dockedRow.id, voyage: null, legs })
  expect(berthed[0].loop).toHaveLength(3)
  expect(buildChartModel([], [LIS, FNC], [], null, berthed).traffic).toHaveLength(0)
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
  // and none of the three is on the chart to be tapped: RESTING MERCHANTS ARE NOT ON THE CHART (owner, 2026-10-13): a merchant in port is counted in her city's tray instead.
  const model = buildChartModel([], [LIS, FNC], [], null, traffic)
  expect(model.traffic).toHaveLength(0)
  for (const t of traffic) {
    if (t.kind !== 'anchored') continue
    expect(hitTest(model, [], project(t.at), 1)?.kind).not.toBe('merchant')
  }
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

// THE CITY'S PORT TAB (owner, 2026-10-15: *"by clicking on [port] it should show incomming ships,
// resting ships"*). The harbour's ranked list is split by WHERE each merchant is — the one rule,
// src/domain/fleet/where.ts — into In port (soonest rest-end first) and Incoming (soonest ETA
// first); one away on her loop is in neither, and nothing is counted twice.
test("a harbour's merchants split into in port and incoming by the one where-rule", () => {
  const docked = (id: string, doing: MerchantDoing, next_lap_at: string | null = null): PortMerchant => {
    const facts: Omit<TrafficFleet, 'lane'> = dockedRow
    return { ...facts, id, name: `Prova ${id}`, port: 'LIS', next_lap_at, doing, level: 3, stops: ['LIS', 'FNC'] }
  }
  const sailing = (id: string, doing: MerchantDoing, to: string, etaInMs: number): PortMerchant => {
    const { lane: _lane, ...facts } = sailingRow(id, [[38.6, -9.4], [32.6, -16.95]], [36, -12])
    void _lane
    return { ...facts, voyage: { ...facts.voyage!, to, eta: new Date(Date.now() + etaInMs).toISOString() }, doing, level: 3, stops: ['LIS', 'FNC'] }
  }
  const soon = new Date(Date.now() + 60_000).toISOString()
  const later = new Date(Date.now() + 300_000).toISOString()
  const rows = [
    docked('a', 'laid_up', later), docked('b', 'resting', later), docked('c', 'resting', soon), docked('d', 'starting'),
    sailing('e', 'ending', 'LIS', 600_000), sailing('f', 'passing', 'LIS', 120_000), sailing('g', 'away', 'FNC', 60_000),
  ]
  const sides = harbourSides(rows, 'LIS')
  // IN PORT, SOONEST FIRST; a laid-up merchant's hold is not a promise, and `starting` lies here too
  expect(sides.inPort.map((r) => r.id)).toEqual(['c', 'b', 'a', 'd'])
  // INCOMING, SOONEST ARRIVAL FIRST; one bound elsewhere is in neither list
  expect(sides.incoming.map((r) => r.id)).toEqual(['f', 'e'])
  expect(harbourSides([], 'LIS')).toEqual({ inPort: [], incoming: [] })
  // THE PEEK LINE counts everyone the city concerns before the ones lying here — the Port tab's count
  expect(merchantsSummary(rows, 'LIS')).toBe('7 merchants · 4 in port')
  expect(merchantsSummary([sailing('e', 'ending', 'LIS', 1)], 'LIS')).toBe('1 merchant')
  expect(merchantsSummary([], 'LIS')).toBe('')
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


/**
 * WAIT FOR TWO MERCHANTS ON THE GLASS, PULLING BACK A STEP AT A TIME IF THE SEA HERE IS EMPTY
 * (2026-10-16). Everything near Lisbon SAILS, on the real clock: each tab's first tick settles every
 * voyage-day since the merchants-on world was dumped, so how many hulls stand inside a frame close
 * on Lisbon depends on how many minutes into its shard a test runs. CI run 38784220784 waited 60 s
 * at 1280 and at 1440 with one merchant in view. The spec sets its own precondition instead of
 * assuming the sea's: up to four presses of Zoom out (each a sea-wider frame, where a 320-merchant
 * roster always has ships), and the count asked is still two. Returns how many presses it took, so
 * a caller that needs the opening frame back (a harbour's NAME is tapped on it) presses Zoom in as
 * many times — the zoom is about the glass's centre, so that is the same frame.
 */
async function merchantsOnTheGlass(page: Page): Promise<number> {
  for (let presses = 0; ; presses++) {
    const two = await expect
      .poll(async () => (await merchantsInView(page)).inView, { timeout: 20_000 })
      .toBeGreaterThanOrEqual(2)
      .then(() => true, () => false)
    if (two) return presses
    if (presses === 4) throw new Error('fewer than two merchants on the glass, even four zoom steps out from Lisbon')
    await page.getByLabel('Zoom out').click()
    await page.waitForTimeout(800)
  }
}

/** Back to the frame `merchantsOnTheGlass` started from. */
async function backIn(page: Page, presses: number): Promise<void> {
  for (let i = 0; i < presses; i++) await page.getByLabel('Zoom in').click()
  if (presses > 0) await page.waitForTimeout(800)
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
  let opened = ''
  // THE LAST HULL WHOSE SHEET DID OPEN, kept when the loop closes it to try another (2026-10-16).
  // The "is there another candidate?" check and the next pass's pick are two reads of a moving sea:
  // PR #130's CI trace shows the sheet OPEN (body visible, no lap average yet), a second hull
  // present at the check, gone 0.4 s later at the pick — and the helper then reported "1 merchant
  // hull(s) were tapped and none opened her sheet", a false account of a working tap. The
  // contract above — settle for the last one if none has a figure — is kept by re-opening her.
  let lastOpened = ''
  let seen = 0
  // WALK THE HULLS, not one hull repeatedly. A tap can be lost to a harbour or to one of your own
  // fleets — both outrank a merchant by the chart's own rule — and no amount of re-aiming at that
  // hull will win it. So each candidate gets a few aims and then the NEXT hull is tried; the first
  // that opens is kept, and the first that ALSO has a lap average to show is preferred, because
  // these screenshots are the record of the feature (the owner read `0 / no lap yet` off one).
  const MAX_HULLS = 8
  for (let attempt = 1; attempt <= MAX_HULLS; attempt++) {
    const id = await hullInView(page, sailing, tried)
    if (!id) break
    tried.add(id)
    seen += 1
    if (!(await tapHull(page, id))) continue
    await expect(page.getByTestId('merchant-sheet-body')).toBeVisible({ timeout: 60_000 })
    opened = id
    lastOpened = id
    const lap = await page.getByTestId('merchant-earnings-lap').textContent()
    // a lap average is printed as `≈ <figure>`; the two absences say so in words
    if (lap && lap.includes('≈')) return id
    // Keep this one unless there is another to try: a closed sheet and no candidate left would
    // hand the caller nothing, which is how this helper went red on its first run.
    // AND THE LAST ATTEMPT IS "NO CANDIDATE LEFT" TOO (2026-10-13). PR #94's CI opened the sheet on
    // SEVEN of eight hulls — every tap landed, every sheet rendered (trace of run 38312840082) — but
    // none of the eight had a lap average yet, so the eighth was closed because a ninth hull was on
    // the glass, the loop then ran out, and the helper reported "8 merchant hull(s) were tapped and
    // none opened her sheet": a false account of a working feature. With 837 merchants and the
    // window-capped read (0102) most hulls on the opening frame are on their first lap, which is
    // what made it bite now. The contract in this helper's own doc comment — settle for the last one
    // if none has a figure — is what is kept here; nothing about the assertion is loosened.
    if (attempt === MAX_HULLS || !(await hullInView(page, sailing, tried))) break
    const close = page.getByTestId('tray-close')
    if (await close.isVisible().catch(() => false)) await close.click()
    opened = ''
  }
  if (!opened) opened = lastOpened
  if (!opened) {
    if (seen === 0) throw new Error('no merchant hull on the glass to open')
    throw new Error(`${seen} merchant hull(s) were tapped and none opened her sheet`)
  }
  if (!(await page.getByTestId('merchant-sheet').isVisible().catch(() => false))) {
    if (!(await tapHull(page, opened))) throw new Error(`merchant ${opened} would not re-open`)
  }
  await expect(page.getByTestId('merchant-sheet-body')).toBeVisible({ timeout: 60_000 })
  return opened
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
async function tapHull(page: Page, id: string): Promise<boolean> {
  const sheet = page.getByTestId('merchant-sheet')
  for (let aim = 1; aim <= 3; aim++) {
    const box = await page.locator(`[data-merchant-id="${id}"]`).boundingBox()
    if (!box) return false
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2)
    try {
      await sheet.waitFor({ state: 'visible', timeout: 3_000 })
      return true
    } catch {
      // Something else took the tap. Close it and aim again at where she is NOW — she drifts — but
      // only a few times: if the thing that took it is a harbour or one of your own fleets, which
      // both outrank a merchant by the chart's own rule, aiming at the same hull again will keep
      // losing. The caller moves to a DIFFERENT hull, which is the only thing that can help.
      const close = page.getByTestId('tray-close')
      if (await close.isVisible().catch(() => false)) await close.click()
    }
  }
  return false
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
  // SINCE 2026-10-14 THE CHART DRAWS ONLY THE MERCHANTS ON THE GLASS (src/chart/shipMarks.ts culls
  // to the view, with the same margin the harbours keep), so the DOM holds the sheet's merchants
  // and not the roster's 800: the honest count is the one in view, and it is at least the two the
  // poll above waited for. `total` ≥ `inView` is the margin.
  expect(seen.inView).toBeGreaterThanOrEqual(2)
  expect(seen.total).toBeGreaterThanOrEqual(seen.inView)
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
  // READ-ONLY: the tray's own buttons (its handle and its close), and since 2026-10-15 openers of
  // READ panels — her ships (PR #113), her figures and lap pills (0121's trades). None is a verb.
  const labels = await sheet.locator('button').evaluateAll((bs) => bs.map((b) => b.getAttribute('aria-label') ?? b.textContent ?? ''))
  // (A SIDE panel has no Resize handle — src/components/ui/Tray.tsx — so only Close is required.)
  expect(labels).toContain('Close')
  for (const l of labels) expect(l).not.toMatch(/\b(Buy|Sell|Sail|Fit|Unfit|Hire|Dismiss|Send|Assign|Save|Delete|Repair|Board)\b/i)
  await page.screenshot({ path: path.join(SHOTS, 'merchant-sheet-peek-390.png') })

  // open it to full (the handle steps the detent from the keyboard) and record the ships, officers, Skills
  const resize = sheet.getByRole('button', { name: 'Resize' })
  if ((await resize.count()) > 0) {
    await resize.press('ArrowUp')
    await resize.press('ArrowUp')
  }
  await page.waitForTimeout(600)
  await page.screenshot({ path: path.join(SHOTS, 'merchant-sheet-full-390.png') })
  // the officers and the company's Skills, further down the same sheet
  await page.locator('[data-testid^="skill-"]').last().scrollIntoViewIfNeeded()
  await page.waitForTimeout(300)
  await page.screenshot({ path: path.join(SHOTS, 'merchant-sheet-officers-skills-390.png') })

  // 0124 — HER SHIP'S PANEL IS YOUR OWN SHIP'S PANEL: one builder (world.ship_view) serves both, so
  // a merchant's hull shows her whole equipment grid — every slot her class has, fitted or empty,
  // counted `n / m` with m the class's slots — and the six combat figures under Speed and Cargo.
  await page.getByTestId('merchant-ship-open').first().click()
  const panel = page.getByTestId('map-ship-panel')
  await expect(panel).toBeVisible({ timeout: 30_000 })
  const equipment = panel.getByTestId('ship-equipment')
  await expect(equipment).toBeVisible()
  const count = (await equipment.locator('h3 + span').textContent()) ?? ''
  const m = /^(\d+) \/ (\d+)$/.exec(count.trim())
  expect(m, `the equipment count reads "${count}"`).not.toBeNull()
  expect(Number(m![2])).toBeGreaterThanOrEqual(1)
  expect(Number(m![1])).toBeLessThanOrEqual(Number(m![2]))
  await expect(equipment.locator('.grid > div')).toHaveCount(Number(m![2]))
  const stats = panel.getByTestId('ship-stats')
  await expect(stats.locator('dt')).toHaveCount(8)
  for (const label of ['Speed', 'Cargo', 'Attack', 'Accuracy', 'Reach', 'Armour', 'Handling', 'Sighting']) {
    await expect(stats.getByText(label, { exact: true })).toBeVisible()
  }
  await page.screenshot({ path: path.join(SHOTS, 'merchant-ship-panel-390.png') })
})

test('PORT at Lisbon lists the merchant in port and opens the same sheet', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await serveNpcOn(page)
  await page.goto('port')
  await ready(page)
  const section = page.getByTestId('port-merchants')
  await expect(section).toBeVisible({ timeout: 60_000 })
  const row = section.getByTestId('merchant-row').filter({ hasText: LAID_UP_AT_LISBON })
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
    await merchantsOnTheGlass(page)
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

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY'S LIST (owner, 2026-10-11: *"By clicking the city, i get to see what trading ships
// started, resting, ending etc."* · 2026-10-13: *"when i press city … i want there to be a list,
// showing the total level, and its current time till the resting finishes."* · 2026-10-14: *"i
// press a city and i see no ship info. Why did this revert back?"*). A resting merchant is drawn
// nowhere on the chart since 2026-10-13, so the city's tray is the one place she shows on the map
// — and since 0116 she rests two real minutes, so a tray that listed only the merchants LYING in
// the city was blank on almost every city. The tray lists EVERY merchant the harbour's read serves,
// in groups (src/live/merchantGroups.ts), and a city with merchants is never blank.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** The PORT TAB's two sections (2026-10-15, owner: *"incomming ships, resting ships"*), split by
 *  where each merchant IS (src/live/merchantGroups.ts `harbourSides`), with the served words a
 *  merchant in each may carry. Away merchants are in neither. */
const GROUPS = [
  { id: 'map-harbour-in-port', heading: 'In port', words: ['Laid up', 'Resting', 'Starting', 'Passing'] },
  { id: 'map-harbour-incoming', heading: 'Incoming', words: ['Ending', 'Passing'] },
] as const

/**
 * THE NAMED HARBOURS ON THE GLASS, where each one's name is drawn — the tap targets a player has.
 */
async function harbourLabels(page: Page): Promise<{ id: string; x: number; y: number }[]> {
  const labels = await page.evaluate(() =>
    [...document.querySelectorAll('[data-label-id^="port:"]')].map((e) => {
      const r = e.getBoundingClientRect()
      return { id: e.getAttribute('data-label-id') ?? '', x: r.x + r.width / 2, y: r.y + r.height / 2 }
    }),
  )
  expect(labels.length, 'no harbour is named on the opening frame').toBeGreaterThan(0)
  return labels
}

async function closeTray(page: Page): Promise<void> {
  const x = page.getByTestId('tray-close')
  if (await x.isVisible().catch(() => false)) await x.click()
  await page.waitForTimeout(300)
}

/**
 * Tap ONE named harbour and stand its tray at half.
 *
 *   'listed'  the city's tray is at half with its merchant list on the glass
 *   'empty'   the city's tray is at half and no list came (nobody's loop calls here)
 *   'taken'   the tap never opened the CITY: a merchant hull drifting over the name, open water
 *             beside a long name, or one of your own fleets, won it by the chart's own tie rule (hitTest.ts) — three aims, a
 *             second apart, because a sailing hull moves on. Correct behaviour, not a defect, and
 *             it happened locally for Cadiz with `Flotte de Nantes` passing over the name.
 *
 * The caller decides what each means: for the fixture's harbour 'taken' and 'empty' are failures
 * it states; for a sweep they are a harbour that is not the city's to answer this second.
 */
async function openHarbour(
  page: Page,
  label: { id: string; x: number; y: number },
): Promise<'listed' | 'empty' | 'taken'> {
  const tray = page.getByTestId('map-detail-tray')
  const send = page.getByTestId('map-send-fleet')
  for (let aim = 1; aim <= 3; aim++) {
    await closeTray(page)
    await page.mouse.click(label.x, label.y)
    // the city's tray, with its one control — anything else that opened took the tap
    // A CITY, NOT A POINT OF WATER (2026-10-16). Open sea wears the same tray and the same `Send
    // fleet` press, so those two alone took a tap that fell on WATER beside a long name (CI run
    // 38776868688: "28.1°N 13.9°W · Open sea" off the Canaries) for a city — which then never
    // answered with a harbour list. Only a city has the City tabs; anything else took the tap.
    const city = await send.waitFor({ state: 'visible', timeout: 2_000 }).then(() => true, () => false)
    const tabs = tray.getByRole('tablist', { name: 'City' })
    if (city && (await tray.isVisible()) && (await tabs.isVisible())) {
      await send.click()
      await expect(tray).toHaveAttribute('data-tray-detent', 'half')
      // THE HARBOUR'S READ IS WAITED FOR UNTIL IT ANSWERS, not for a fixed 8 s (2026-10-16). Until
      // it lands the tray shows a placeholder (`map-harbour-loading`), and only an ANSWER prints the
      // list or "No ships in port or bound here." The fixed wait was the flake on PR #130 and #131:
      // each tab's first reads run `tick_arrivals` over every voyage-day since the merchants-on
      // world was dumped, so the read slows as a shard goes on, and an unanswered read was being
      // reported as "Porto's tray lists no merchants". A city nobody's loop calls at still answers
      // with no list at all — 'empty' now means exactly that.
      // (`data-landed`: your own fleets are listed before the merchants' read answers, so a list
      // on the glass is not yet the answer either.)
      const answer = page.locator('[data-testid="map-harbour"][data-landed="true"], [data-testid="map-harbour-empty"]')
      await answer.first().waitFor({ state: 'visible', timeout: 60_000 })
      return (await page.getByTestId('map-harbour').isVisible()) ? 'listed' : 'empty'
    }
    await page.waitForTimeout(1_000)
  }
  return 'taken'
}

/**
 * THE FIXTURE'S HARBOUR — Porto, where tests/npcOn.fixture.ts put `RESTING_AT_PORTO` to rest with
 * a known rest end. Its name must be on the opening frame (it is, at 390 and at 1440: the frame is
 * built on your fleet at Lisbon), and it must not be under your own fleet's mark, which wins the tap
 * (hitTest.ts) — which is why the fixture chose Porto and not Lisbon. A frame without Porto's name
 * is a failed precondition and says so; it is never a pass.
 */
async function openPorto(page: Page): Promise<void> {
  const porto = (await harbourLabels(page)).find((l) => l.id === `port:${RESTING_PORT_CODE}`)
  if (!porto) throw new Error(`Porto (port:${RESTING_PORT_CODE}) is not named on the opening frame — the fixture rests ${RESTING_AT_PORTO} there`)
  const opened = await openHarbour(page, porto)
  if (opened === 'taken') throw new Error(`Porto's name could not be tapped: a hull or a fleet took the tap three times running`)
  if (opened === 'empty') throw new Error(`Porto's tray lists no merchants, but the fixture rests ${RESTING_AT_PORTO} there`)
}

/** Every row of one group section as the things a player reads on it. */
async function groupRows(section: Locator): Promise<{ name: string; level: string; doing: string; rest: string | null }[]> {
  return section.evaluate((el) =>
    [...el.querySelectorAll('[data-testid="merchant-row"]')].map((row) => {
      const read = (id: string) => (row.querySelector(`[data-testid="${id}"]`)?.textContent ?? '').trim()
      return {
        name: read('merchant-row-name'),
        level: read('merchant-row-level'),
        doing: read('merchant-row-doing'),
        rest: row.querySelector('[data-testid="merchant-row-rest"]') ? read('merchant-row-rest') : null,
      }
    }),
  )
}

/**
 * THE LIST, READ BACK AS ITS CONTRACT: the groups that are printed stand in the server's rank with
 * no empty one among them; every row carries a level (0113) and a word that belongs to its group;
 * a resting merchant carries the time her rest ends and a laid-up one does not; in port the soonest
 * stands first; each heading's count is its rows; the head's count is every row. Holds for ANY
 * harbour with merchants — nothing here needs a particular merchant to be anywhere. Returns the
 * rows, grouped, for the caller.
 */
async function readCityList(page: Page, city: string) {
  const list = page.getByTestId('map-harbour')
  await expect(list).toBeVisible()
  const printed: { heading: string; rows: Awaited<ReturnType<typeof groupRows>> }[] = []
  for (const g of GROUPS) {
    const section = page.getByTestId(g.id)
    if ((await section.count()) === 0) continue
    const rows = await groupRows(section)
    expect(rows.length, `${city}: the ${g.heading} group is printed with nobody in it`).toBeGreaterThanOrEqual(1)
    await expect(section.locator('h2')).toHaveText(g.heading)
    // the heading counts every row in it — your own fleets (map-harbour-own) and the merchants
    const own = await section.getByTestId('map-harbour-own').count()
    await expect(section.getByTestId('map-harbour-count')).toHaveText(String(rows.length + own))
    for (const r of rows) {
      expect(r.level, `${city}: the level of ${r.name}`).toMatch(/^\d+$/)
      expect(g.words as readonly string[], `${city}: "${r.doing}" on ${r.name} is not a ${g.heading} word`).toContain(r.doing)
      if (r.doing === 'Resting') {
        // `2 h 14 min`, `4.7 min`, or `ends soon` — src/lib/format's one real-span spelling.
        expect(r.rest, `${city}: ${r.name} is resting with no time`).toMatch(/(\d+ h( \d+ min)?|\d+(\.\d)? min|ends soon)/)
      }
      if (r.doing === 'Laid up') expect(r.rest, `${city}: a laid-up merchant's hold is not a promise`).toBeNull()
    }
    if (g.id === 'map-harbour-in-port') {
      // SOONEST FIRST: a row without a time never stands above one with.
      const timed = rows.map((r) => (r.rest ? '1' : '0')).join('')
      expect(timed, `${city}: a row without a time stands above one with`).not.toMatch(/01/)
    }
    printed.push({ heading: g.heading, rows })
  }
  // THE GROUPS STAND IN THE SERVER'S RANK — the order GROUPS lists them, which is 0104's.
  const order = printed.map((p) => GROUPS.findIndex((g) => g.heading === p.heading))
  expect(order).toEqual([...order].sort((a, b) => a - b))
  // Every row stands in a section; the head line's in-port count is the In port section's — one
  // rule (`harbourSides`) for both. The head still counts every merchant the city concerns, the
  // ones away on their loops too, so it is at least the rows listed.
  const all = await list.getByTestId('merchant-row').count()
  expect(all, `${city}: rows outside every section`).toBe(printed.reduce((n, p) => n + p.rows.length, 0))
  expect(all, `${city}: a list with no rows`).toBeGreaterThanOrEqual(1)
  const inPort = printed.find((p) => p.heading === 'In port')?.rows.length ?? 0
  const line = page.getByTestId('map-place-name-line')
  const head = Number(((await line.textContent()) ?? '').match(/(\d+) merchants?/)?.[1] ?? '0')
  expect(head, `${city}: the head counts fewer merchants than the tab lists`).toBeGreaterThanOrEqual(all)
  if (inPort > 0) await expect(line).toContainText(`· ${inPort} in port`)
  else await expect(line).not.toContainText('in port')
  return printed
}

test('Porto lists every merchant it concerns, grouped — the fixture\'s resting one with the time her rest ends — and her row opens her sheet', async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  mkdirSync(SHOTS, { recursive: true })
  await serveNpcOn(page)
  await page.goto('map')
  await ready(page)
  await backIn(page, await merchantsOnTheGlass(page))

  // THE PRECONDITION IS THE FIXTURE'S, NOT THE CLOCK'S: Porto has RESTING_AT_PORTO at rest with
  // six hours on her hold, whatever the other merchants are doing this minute.
  await openPorto(page)
  await expect(page.getByTestId('map-place-name')).toHaveText('Porto')
  const printed = await readCityList(page, 'Porto')
  expect(printed[0].heading, 'the In port group stands first').toBe('In port')
  const resting = printed[0].rows.find((r) => r.name === RESTING_AT_PORTO)
  expect(resting, `${RESTING_AT_PORTO} is not in Porto's In port group: ${JSON.stringify(printed[0].rows)}`).toBeTruthy()
  expect(resting?.doing).toBe('Resting')
  // Hours, not minutes: the hold was written six hours out when the world was built, and a kept
  // world is at most ninety minutes old (NPC_ON_MAX_AGE_MS) — so at least 4 h 30 min remain.
  expect(resting?.rest, 'the time her rest ends').toMatch(/^\d+ h( \d+ min)?$/)
  expect(Number((resting?.rest ?? '0').split(' ')[0]), 'hours left on her rest').toBeGreaterThanOrEqual(4)
  // YOUR FLEETS are still here, under the list, so the owner's send flow did not move.
  await expect(page.getByTestId('map-send-fleets')).toBeVisible()
  await page.screenshot({ path: path.join(SHOTS, 'city-tray-half-390.png') })

  // HER ROW OPENS THE SAME READ-ONLY SHEET a hull on the water opens — and a resting merchant is
  // served by the harbour and not by the sea window, so this is the one way to reach her from the
  // map. The sheet's level is the number the row printed.
  const row = page.getByTestId('map-harbour-in-port').getByTestId('merchant-row').filter({ hasText: RESTING_AT_PORTO })
  await expect(row).toHaveCount(1)
  const level = ((await row.getByTestId('merchant-row-level').textContent()) ?? '').trim()
  await row.click()
  await expect(page.getByTestId('merchant-sheet')).toBeVisible()
  await expect(page.getByTestId('map-detail-tray')).toHaveCount(0)
  await expect(page.getByTestId('merchant-sheet-name')).toHaveText(RESTING_AT_PORTO, { timeout: 60_000 })
  await expect(page.getByTestId('merchant-sheet-body')).toBeVisible({ timeout: 60_000 })
  await expect(page.getByTestId('merchant-level')).toContainText(level)
  await page.screenshot({ path: path.join(SHOTS, 'city-tray-merchant-from-list-390.png') })
})

// THE REGRESSION THE OWNER HIT (2026-10-14). On main the list was `map-resting` — the merchants
// LYING in the city and nothing else — and it rendered NOTHING for a city whose merchants were all
// at sea, which with a two-minute rest is almost every city. This sweep fails there, on Porto at
// the latest. It asserts NOTHING about which cities have whom this minute: every named harbour on
// the frame is opened, and each one that has merchants must print them all, grouped, never blank.
// (Which harbours have nobody in port is the clock's business; the unit test above proves a list
// of merchants all at sea is still a list. The at-sea shot is taken if the frame offers one — a
// screenshot is a record, not an assertion.)
test('every named harbour with merchants lists them all, grouped, never blank', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  mkdirSync(SHOTS, { recursive: true })
  await serveNpcOn(page)
  await page.goto('map')
  await ready(page)
  await backIn(page, await merchantsOnTheGlass(page))

  const listed: string[] = []
  let atSeaShot = false
  // Every named harbour, Lisbon too: since 2026-10-15 a fleet DOCKED in a harbour yields the tap to
  // it (hitTest.ts), so Lisbon's label opens the city with your fleet first in its Port tab.
  for (const l of await harbourLabels(page)) {
    if ((await openHarbour(page, l)) !== 'listed') continue
    const printed = await readCityList(page, l.id)
    listed.push(l.id)
    if (!atSeaShot && !printed.some((p) => p.heading === 'In port')) {
      await page.screenshot({ path: path.join(SHOTS, 'city-tray-at-sea-390.png') })
      atSeaShot = true
    }
  }
  // At least Porto, by the fixture; the rest is whatever the frame named.
  expect(listed, 'no named harbour listed a merchant').toContain(`port:${RESTING_PORT_CODE}`)
})

test.describe('wide city tray', () => {
  test.use({ viewport: { width: 1440, height: 900 } })
  test('the city tray at 1440 × 900 lists the merchants in their groups', async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    mkdirSync(SHOTS, { recursive: true })
    await serveNpcOn(page)
    await page.goto('map')
    await ready(page)
    await backIn(page, await merchantsOnTheGlass(page))
    await openPorto(page)
    const printed = await readCityList(page, 'Porto')
    expect(printed[0].rows.map((r) => r.name)).toContain(RESTING_AT_PORTO)
    await page.waitForTimeout(600)
    await page.screenshot({ path: path.join(SHOTS, 'city-tray-half-1440.png') })
  })
})

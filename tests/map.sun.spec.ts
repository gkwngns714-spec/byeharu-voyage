// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SUN ON THE CHART — owner, 2026-10-14
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   *"show ships when zoomed out … i want there to be sunlight based on real science. The sunlight
//    touching the earth should have colors similar to daytime earth."*
//
// This file was tests/map.night.spec.ts — row 125's NIGHT CHART, which made night a ZOOM: pulled
// back, the cities became lights and the ships became embers, whatever the hour. The owner wants
// the real thing, so the night is now the Sun's (src/chart/sun.ts) and a ship is a ship at every
// zoom (src/chart/shipMarks.ts). What this file holds:
//
//   THE ALMANAC      the subsolar point on dated instants — the equinoxes, the solstices and
//                    Greenwich noon — against the published values, to a tenth of a degree
//   THE SHADE        the elevation is the dot product on the sphere, the daylight falls 1 → 0
//                    through the three twilights, the raster is the shade sampled per degree
//   THE LIGHTS       a harbour burns by its size (row 125's ramp, unchanged), and burns only
//                    where the Sun is down: `--night` on the glass follows `daylightAt`
//   THE SHIPS        at the globe every merchant on the sheet is a HULL — zero embers, no dots —
//                    and the hulls are still there on the way back in
//
// BROWSER, merchants on (./npcOn.fixture.ts): the Sun the chart used is read OFF the chart
// (`data-sun-*`), never assumed from the clock; the day picture is on the sheet; and every
// harbour's `--night` equals the almanac's daylight for the Sun the chart says it used.
// Screenshots land in docs/map-wrap-sun/ so the owner can judge "daytime Earth" by eye.

import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { PHONE, reachable, ready } from './appReady.fixture'
import { serveNpcOn } from './npcOn.fixture'
import type { TrafficFleet } from '../src/lib/rpc'
import {
  DAYLIGHT_RASTER_HEIGHT,
  DAYLIGHT_RASTER_WIDTH,
  daylightAt,
  daylightOf,
  daylightRaster,
  DOT_SPAN_DEG,
  GLYPH,
  harbourLightHalo,
  harbourLightStrength,
  HULL_GROUP_MAX_UNITS_PER_PX,
  LANE_SPAN_DEG,
  mapTrafficOf,
  solarElevationDeg,
  subsolarPoint,
  SUN_REFRESH_MS,
  TWILIGHT,
  zoomPercent,
} from '../src/chart'

const SHOTS = path.resolve('docs', 'map-wrap-sun')

/** The eight merchant inks, as the server spells them. */
const NATION_INKS = ['prt', 'esp', 'nld', 'eng', 'han', 'ita', 'ott', 'east']

// ── THE ALMANAC ────────────────────────────────────────────────────────────────────────────────

test('the subsolar latitude is the declination: zero at the equinoxes, ±23.44° at the solstices', () => {
  // The 2026 equinoxes and solstices, UTC, from the almanac (USNO / IMCCE), to the minute.
  expect(subsolarPoint(Date.parse('2026-03-20T14:46:00Z')).lat).toBeCloseTo(0, 1)
  expect(subsolarPoint(Date.parse('2026-09-22T23:05:00Z')).lat).toBeCloseTo(0, 1)
  expect(subsolarPoint(Date.parse('2026-06-21T08:25:00Z')).lat).toBeCloseTo(23.44, 1)
  expect(subsolarPoint(Date.parse('2026-12-21T20:50:00Z')).lat).toBeCloseTo(-23.44, 1)
  // J2000.0 itself: declination −23.03°, equation of time −3.3 min.
  const j2000 = subsolarPoint(Date.parse('2000-01-01T12:00:00Z'))
  expect(j2000.lat).toBeCloseTo(-23.03, 1)
  expect(j2000.equationOfTimeMin).toBeCloseTo(-3.3, 0)
  // And the latitude never leaves the tropics, on any day of a year, at any hour.
  for (let d = 0; d < 366; d += 7) {
    for (const h of [0, 6, 12, 18]) {
      const s = subsolarPoint(Date.parse('2026-01-01T00:00:00Z') + d * 86_400_000 + h * 3_600_000)
      expect(Math.abs(s.lat)).toBeLessThanOrEqual(23.45)
      expect(Math.abs(s.lon)).toBeLessThanOrEqual(180)
    }
  }
})

test('solar noon at Greenwich is 12:00 UTC less the equation of time, to the minute', () => {
  // 3 November: the equation of time is at its yearly maximum, +16.4 min — the Sun crosses
  // Greenwich at 11:43:36 UTC. At that instant the subsolar longitude is 0; at 12:00 it is
  // 16.4 minutes WEST (−4.1°), because the Sun has already gone over.
  const nov3noon = subsolarPoint(Date.parse('2026-11-03T11:43:36Z'))
  expect(nov3noon.lon).toBeCloseTo(0, 1)
  expect(nov3noon.equationOfTimeMin).toBeCloseTo(16.4, 0)
  expect(subsolarPoint(Date.parse('2026-11-03T12:00:00Z')).lon).toBeCloseTo(-4.1, 1)
  // 11 February: the yearly minimum, −14.2 min — the Sun is still 3.6° EAST of Greenwich at noon.
  const feb11 = subsolarPoint(Date.parse('2026-02-11T12:00:00Z'))
  expect(feb11.equationOfTimeMin).toBeCloseTo(-14.2, 0)
  expect(feb11.lon).toBeCloseTo(3.55, 1)
  // At 12:00 UTC on every day of the year the Sun is within 4.2° of Greenwich — the equation of
  // time is bounded at ±16.5 minutes — and at 00:00 it is over the antimeridian.
  for (let d = 0; d < 366; d += 3) {
    const noon = subsolarPoint(Date.parse('2026-01-01T12:00:00Z') + d * 86_400_000)
    expect(Math.abs(noon.lon)).toBeLessThan(4.2)
    const midnight = subsolarPoint(Date.parse('2026-01-01T00:00:00Z') + d * 86_400_000)
    expect(180 - Math.abs(midnight.lon)).toBeLessThan(4.2)
  }
  // The Sun moves 15° west an hour: six hours after noon it is over 90°W, give or take the
  // equation of time's drift across six hours (seconds).
  const six = subsolarPoint(Date.parse('2026-10-14T18:00:00Z'))
  const noon = subsolarPoint(Date.parse('2026-10-14T12:00:00Z'))
  expect(six.lon - noon.lon).toBeCloseTo(-90, 1)
})

// ── THE SHADE ──────────────────────────────────────────────────────────────────────────────────

test('the elevation is 90° under the Sun, −90° at its antipode, 0° a quarter-turn away', () => {
  const sun = subsolarPoint(Date.parse('2026-10-14T12:00:00Z'))
  expect(solarElevationDeg(sun, sun)).toBeCloseTo(90, 6)
  expect(solarElevationDeg({ lat: -sun.lat, lon: sun.lon + 180 }, sun)).toBeCloseTo(-90, 6)
  // On the equator at the equinox the terminator is the meridians ±90° from the Sun.
  const equinox = { lat: 0, lon: 0 }
  expect(solarElevationDeg({ lat: 0, lon: 90 }, equinox)).toBeCloseTo(0, 6)
  expect(solarElevationDeg({ lat: 0, lon: -90 }, equinox)).toBeCloseTo(0, 6)
  expect(solarElevationDeg({ lat: 90, lon: 0 }, equinox)).toBeCloseTo(0, 6)
  // At the June solstice the north pole has the Sun 23.44° up all day; the south pole never.
  const june = { lat: 23.44, lon: 50 }
  expect(solarElevationDeg({ lat: 90, lon: -120 }, june)).toBeCloseTo(23.44, 6)
  expect(solarElevationDeg({ lat: -90, lon: 10 }, june)).toBeCloseTo(-23.44, 6)
})

test('daylight falls from 1 to 0 through civil, nautical and astronomical twilight, and never outside [0, 1]', () => {
  // THE BANDS ARE THE ALMANAC'S: the refracted upper limb, then −6, −12, −18.
  expect(TWILIGHT.map((t) => t.elevationDeg)).toEqual([-0.833, -6, -12, -18])
  expect(TWILIGHT[0].daylight).toBe(1)
  expect(TWILIGHT[TWILIGHT.length - 1].daylight).toBe(0)
  // Monotonic: a higher Sun is never a darker sky.
  let last = Infinity
  for (let h = 90; h >= -90; h -= 0.25) {
    const d = daylightOf(h)
    expect(d).toBeGreaterThanOrEqual(0)
    expect(d).toBeLessThanOrEqual(1)
    expect(d).toBeLessThanOrEqual(last)
    last = d
  }
  expect(daylightOf(45)).toBe(1)
  expect(daylightOf(0)).toBe(1)
  expect(daylightOf(-6)).toBeCloseTo(TWILIGHT[1].daylight, 9)
  expect(daylightOf(-12)).toBeCloseTo(TWILIGHT[2].daylight, 9)
  expect(daylightOf(-18)).toBe(0)
  expect(daylightOf(-40)).toBe(0)
  expect(daylightOf(Number.NaN)).toBe(0)
  // Composed: a point under the Sun is day, its antipode night.
  const sun = { lat: 10, lon: 20 }
  expect(daylightAt(sun, sun)).toBe(1)
  expect(daylightAt({ lat: -10, lon: -160 }, sun)).toBe(0)
})

test('the raster is the shade sampled once per degree: half the world lit, the rest dark, a band between', () => {
  const sun = subsolarPoint(Date.parse('2026-03-20T14:46:00Z'))
  const r = daylightRaster(sun)
  expect(r.length).toBe(DAYLIGHT_RASTER_WIDTH * DAYLIGHT_RASTER_HEIGHT)
  expect(DAYLIGHT_RASTER_WIDTH).toBe(360)
  expect(DAYLIGHT_RASTER_HEIGHT).toBe(180)
  // The cell under the Sun is full day; the cell at its antipode is full night.
  const cellOf = (lat: number, lon: number) =>
    r[Math.min(179, Math.floor(90 - lat)) * 360 + Math.min(359, Math.floor(lon + 180))]
  expect(cellOf(sun.lat, sun.lon)).toBe(255)
  expect(cellOf(-sun.lat, sun.lon > 0 ? sun.lon - 180 : sun.lon + 180)).toBe(0)
  // At the equinox the day cap is half the sphere: by area, half the cells weighted by cos(lat)
  // are lit. The raster is equirectangular, so count with that weight.
  let lit = 0
  let total = 0
  for (let row = 0; row < 180; row++) {
    const w = Math.cos(((90 - row - 0.5) * Math.PI) / 180)
    for (let col = 0; col < 360; col++) {
      total += w
      lit += (w * r[row * 360 + col]) / 255
    }
  }
  // Half the sphere plus the twilight's contribution: the band from 0° to −18° is
  // (sin 0 − sin −18°) / 2 = 15.5 % of the sphere, lit at ~0.45 on average, so ~0.57 in all.
  expect(lit / total).toBeGreaterThan(0.5)
  expect(lit / total).toBeLessThan(0.6)
  // Every row sees the Sun up somewhere (equinox: the Sun is on the equator and every meridian
  // has it overhead once a day), and every row inside ±70° also sees full night — the pole's
  // lowest Sun at the equinox is only −(90° − |lat|), so past 72° it never gets below −18° and
  // the polar rows stay in twilight all day. That is the almanac, and the raster agrees with it.
  for (let row = 0; row < 180; row++) {
    const vals = Array.from(r.subarray(row * 360, row * 360 + 360))
    const lat = 90 - row - 0.5
    expect(Math.max(...vals), `row at ${lat}°`).toBe(255)
    if (Math.abs(lat) <= 72) expect(Math.min(...vals), `row at ${lat}°`).toBe(0)
    else expect(Math.min(...vals), `row at ${lat}° never leaves twilight`).toBeGreaterThan(0)
  }
  // Refreshed once a minute: the Sun moves a quarter-degree a minute, a pixel at the widest zoom.
  expect(SUN_REFRESH_MS).toBe(60_000)
})

// ── THE LIGHTS AND THE LADDER ──────────────────────────────────────────────────────────────────

test('a harbour burns by its size, between a floor and a ceiling', () => {
  // MONOTONIC AND BOUNDED. Every tier is brighter than the one below it, the smallest coast is
  // still a light (the floor is what `harbourLightTierSpread` leaves behind), and the brightest is
  // the whole halo and never more — so no harbour can bloom off the sheet.
  const strengths = [1, 2, 3, 4, 5].map(harbourLightStrength)
  expect(strengths).toEqual([0, 0.25, 0.5, 0.75, 1])
  for (let i = 1; i < strengths.length; i++) expect(strengths[i]).toBeGreaterThan(strengths[i - 1])
  expect(harbourLightStrength(0)).toBe(0)
  expect(harbourLightStrength(99)).toBe(1)
  expect(harbourLightStrength(Number.NaN)).toBe(0)
  expect(Number.isFinite(harbourLightHalo(Number.NaN, 0.5))).toBe(true)
  for (const upp of [0.05, 0.2, 0.5, 0.92]) {
    for (const tier of [1, 2, 3, 4, 5]) expect(harbourLightHalo(tier, upp)).toBeGreaterThan(GLYPH.portDotRadius * upp)
    expect(harbourLightHalo(5, upp)).toBeGreaterThan(harbourLightHalo(1, upp))
  }
})

test('the ladder has two rungs and no ember; the wide sheet’s two spans are in order and reachable', () => {
  // THE EMBER IS GONE, structurally: there is no constant for it to be keyed on and no size for it.
  expect(GLYPH).not.toHaveProperty('emberRadius')
  expect(GLYPH).not.toHaveProperty('emberHaloScale')
  expect(HULL_GROUP_MAX_UNITS_PER_PX).toBeCloseTo(45 / 390, 10)
  // The lanes come up first on the way out, then the marks give way to dots; the whole world is
  // past both on every screen, which is the whole point of measuring these in degrees.
  expect(DOT_SPAN_DEG).toBeGreaterThan(LANE_SPAN_DEG)
  expect(360).toBeGreaterThan(DOT_SPAN_DEG)
  expect(zoomPercent(360)).toBe(0)
  expect(zoomPercent(LANE_SPAN_DEG)).toBeGreaterThan(zoomPercent(DOT_SPAN_DEG))
})

test('a lane is copied, never invented, and a stub of one draws nothing', () => {
  const row = (over: Partial<TrafficFleet>): TrafficFleet => ({
    id: 'm-1', company: 'Casa da Prova', nation_code: 'PRT', ink: 'prt', name: 'Prova', status: 'DOCKED',
    ships: 3, hulls: ['nau', 'nau', 'barca'],
    port: 'LIS', roadstead: [38.6, -9.4], anchor: null, voyage: null, next_lap_at: null, lane: null,
    ...over,
  })
  const laneOf = (over: Partial<TrafficFleet>) => mapTrafficOf([row(over)])[0]?.lane ?? null
  expect(laneOf({})).toBeNull()
  expect(laneOf({ ships: 1, hulls: ['barca'], lane: [[38.6, -9.4], [32.6, -16.9]] })).toEqual([
    { lat: 38.6, lon: -9.4 },
    { lat: 32.6, lon: -16.9 },
  ])
  expect(laneOf({ lane: [[38.6, -9.4]] })).toBeNull()
  expect(laneOf({ lane: [] })).toBeNull()
})

// ── THE GLASS ──────────────────────────────────────────────────────────────────────────────────

/** What is actually drawn: the Sun the chart used, the harbours and their `--night`, the ships. */
async function sunOnTheGlass(page: Page) {
  return page.evaluate(() => {
    const chart = document.querySelector('[data-testid="map-chart"]')!
    const root = chart.querySelector('[data-sun-at]')!
    const svg = chart.querySelector('svg')
    const vb = svg?.getAttribute('viewBox')?.split(/\s+/).map(Number) ?? []
    const unitsPerPx = vb.length === 4 && svg ? vb[2] / (svg as SVGSVGElement).clientWidth : Number.NaN
    const lights = [...document.querySelectorAll('[data-port-mark]')].map((g) => {
      const rings = [...g.querySelectorAll('circle[class*="harbour-light/"]')]
      return {
        code: g.getAttribute('data-port-code') ?? '',
        tier: Number(g.getAttribute('data-port-tier')),
        mark: g.getAttribute('data-port-mark') ?? '',
        x: Number(g.getAttribute('data-port-x')),
        y: Number(g.getAttribute('data-port-y')),
        night: Number((g as SVGGElement).style.getPropertyValue('--night')),
        rings: rings.length,
        ringOpacity: rings.map((c) => Number(getComputedStyle(c).opacity)),
        ringRadii: rings.map((c) => Number(c.getAttribute('r'))),
        core: Number(g.querySelector('circle[class*="bv-sun-core"]')?.getAttribute('r') ?? Number.NaN),
        paths: g.querySelectorAll('path').length,
      }
    })
    const ships = [...document.querySelectorAll('[data-testid="map-merchant"], [data-testid="map-ship"]')].map((g) => ({
      hulls: Number(g.getAttribute('data-hulls')),
      paths: g.querySelectorAll('path[data-hull-class]').length,
      night: Number((g as SVGGElement).style.getPropertyValue('--night')),
      lightOpacity: Number(getComputedStyle(g.querySelector('[data-ship-light]')!).opacity),
      blink: g.querySelector('[data-ship-light]')?.classList.contains('bv-ship-blink') ?? false,
    }))
    const lanes = [...document.querySelectorAll('[data-testid="map-merchant-lane"]')].map((p) => ({
      ink: p.getAttribute('data-lane-ink') ?? '',
      d: p.getAttribute('d') ?? '',
      cls: p.getAttribute('class') ?? '',
    }))
    const pct = document.querySelector('[data-testid="map-zoom-percent"]')
    return {
      sunAt: Number(root.getAttribute('data-sun-at')),
      sunLat: Number(root.getAttribute('data-sun-lat')),
      sunLon: Number(root.getAttribute('data-sun-lon')),
      unitsPerPx,
      spanDeg: vb.length === 4 ? vb[2] : Number.NaN,
      zoomPercent: pct ? Number(pct.getAttribute('data-zoom-percent')) : Number.NaN,
      lights,
      ships,
      lanes,
      embers: document.querySelectorAll('[data-fleet-mark="ember"]').length,
      hullPaths: document.querySelectorAll('path[data-hull-class]').length,
      portMarkPaths: document.querySelectorAll('[data-port-mark="full"] path').length,
      daySea: document.querySelectorAll('[data-testid="map-sea-day"]').length,
      dayCoast: document.querySelectorAll('[data-testid="map-coast-day"]').length,
      masks: document.querySelectorAll('[data-testid="map-daylight-mask"] image').length,
    }
  })
}

test('at the globe the ships are hulls, the day picture is on the sheet, and every light follows the Sun', async ({
  page,
  request,
  baseURL,
}) => {
  // The merchants-on fixture is built once per worker and the first spec pays for it (~9 min
  // measured) — tests/map.hulls.spec.ts carries the same note.
  test.setTimeout(1_200_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  mkdirSync(SHOTS, { recursive: true })
  await serveNpcOn(page)
  await page.setViewportSize(PHONE)
  await page.goto('map')
  await ready(page)
  await page.evaluate(() => document.documentElement.setAttribute('data-theme', 'dark'))

  // The merchants have to be on the glass before pulling back, or a hull count of zero would be
  // true for the honest reason that nobody is at sea yet.
  await expect.poll(async () => (await sunOnTheGlass(page)).hullPaths, { timeout: 60_000 }).toBeGreaterThanOrEqual(2)

  const out = page.getByLabel('Zoom out')
  for (let i = 0; i < 12; i++) await out.click()
  await page.waitForTimeout(800)
  const wide = await sunOnTheGlass(page)

  // THE SUN THE CHART USED IS THE ALMANAC'S, for the instant it says it read. Read off the chart,
  // never assumed from this process's clock (the two differ by the read's own latency).
  const expected = subsolarPoint(wide.sunAt)
  expect(wide.sunLat).toBeCloseTo(expected.lat, 3)
  expect(wide.sunLon).toBeCloseTo(expected.lon, 3)
  expect(Math.abs(wide.sunAt - Date.now())).toBeLessThan(SUN_REFRESH_MS + 60_000)
  const sun = { lat: wide.sunLat, lon: wide.sunLon }

  expect(wide.spanDeg).toBeGreaterThanOrEqual(DOT_SPAN_DEG)
  expect(wide.zoomPercent).toBe(0)

  // THE DAY PICTURE IS ON THE SHEET: the day sea in the view's svg, the day coast on the sheet,
  // both through the Sun's mask.
  expect(wide.daySea).toBe(1)
  expect(wide.dayCoast).toBeGreaterThanOrEqual(1)
  expect(wide.masks).toBeGreaterThanOrEqual(2)

  // EVERY CITY IS ITS DOT at the globe, and EVERY DOT CARRIES ITS LIGHT — whose brightness is the
  // Sun's: `--night` on the group is 1 − daylightAt, and the two rings' opacity is that number.
  expect(wide.lights.length).toBeGreaterThanOrEqual(20)
  expect(wide.lights.filter((l) => l.mark !== 'dot')).toEqual([])
  expect(wide.portMarkPaths).toBe(0)
  let lit = 0
  let dark = 0
  for (const l of wide.lights) {
    expect(l.rings).toBe(2)
    expect(l.ringRadii[0]).toBeGreaterThan(l.ringRadii[1])
    expect(l.ringRadii[1]).toBeGreaterThan(l.core)
    expect(l.paths).toBe(0)
    const night = 1 - daylightAt({ lat: -l.y, lon: l.x }, sun)
    expect(l.night).toBeCloseTo(night, 2)
    expect(l.ringOpacity[0]).toBeCloseTo(night, 2)
    expect(l.ringOpacity[1]).toBeCloseTo(night, 2)
    if (night > 0.99) lit++
    if (night < 0.01) dark++
  }
  // The world is 360° across, so BOTH sides of the terminator are on the glass: some lamps lit,
  // some out. (At the equinox or the solstice alike — half the sphere is always night.)
  expect(lit).toBeGreaterThan(0)
  expect(dark).toBeGreaterThan(0)

  // EVERY SHIP STILL ON THE SHEET IS A HULL — no ember, no dot, and the count on the glass is the
  // thinned roster, not the 49 major fleets the old sheet drew. Her riding light follows the Sun
  // exactly as a harbour's does.
  expect(wide.embers).toBe(0)
  expect(wide.ships.length).toBeGreaterThanOrEqual(2)
  expect(wide.hullPaths).toBeGreaterThanOrEqual(wide.ships.length)
  for (const s of wide.ships) {
    expect(s.hulls).toBeGreaterThanOrEqual(1)
    expect(s.paths).toBe(s.hulls)
    expect(s.blink).toBe(true)
    expect(s.lightOpacity).toBeCloseTo(s.night, 1)
  }
  // Pulled back past the group rung, every one is her flagship alone (row 120's collapse holds).
  expect([...new Set(wide.ships.map((s) => s.hulls))]).toEqual([1])

  // AND THE MAJOR FLEETS SHOW THEIR ROUTES — *"major fleet shoud also show the routes as well"*.
  expect(wide.lanes.length).toBeGreaterThanOrEqual(1)
  for (const l of wide.lanes) {
    expect((l.d.match(/[ML]/g) ?? []).length).toBeGreaterThanOrEqual(2)
    expect(NATION_INKS).toContain(l.ink)
    expect(l.cls).toContain('stroke-merchant')
  }

  console.log(
    `sun at ${new Date(wide.sunAt).toISOString()} over ${wide.sunLat.toFixed(2)}°, ${wide.sunLon.toFixed(2)}°: ` +
      `${wide.lights.length} harbours (${lit} lit, ${dark} dark), ${wide.ships.length} ship(s) drawn as ${wide.hullPaths} hull(s), ` +
      `0 embers, ${wide.lanes.length} lane(s)`,
  )
  await page.screenshot({ path: path.join(SHOTS, 'globe-390.png') })

  await page.setViewportSize({ width: 1440, height: 900 })
  await page.waitForTimeout(600)
  const desktop = await sunOnTheGlass(page)
  expect(desktop.embers).toBe(0)
  expect(desktop.ships.length).toBeGreaterThanOrEqual(2)
  console.log(`1440×900 globe: ${desktop.lights.length} harbours, ${desktop.ships.length} ship(s), ${desktop.hullPaths} hull(s)`)
  await page.screenshot({ path: path.join(SHOTS, 'globe-1440.png') })

  // AND IT IS A BAND FOR THE DOTS, NOT FOR THE SHIPS: zoom back in and the marks return; the hulls
  // never left.
  await page.setViewportSize(PHONE)
  const inBtn = page.getByLabel('Zoom in')
  for (let i = 0; i < 12; i++) await inBtn.click()
  await page.waitForTimeout(800)
  const close = await sunOnTheGlass(page)
  expect(close.spanDeg).toBeLessThan(DOT_SPAN_DEG)
  expect(close.embers).toBe(0)
  expect(close.lanes).toEqual([])

  await page.goto('map')
  await ready(page)
  await expect.poll(async () => (await sunOnTheGlass(page)).lights.length, { timeout: 60_000 }).toBeGreaterThanOrEqual(1)
  const opening = await sunOnTheGlass(page)
  expect(opening.spanDeg).toBeLessThan(LANE_SPAN_DEG)
  expect(opening.zoomPercent).toBeGreaterThan(0)
  expect(opening.lights.some((l) => l.mark === 'full')).toBe(true)
  for (const l of opening.lights) expect(l.night).toBeCloseTo(1 - daylightAt({ lat: -l.y, lon: l.x }, { lat: opening.sunLat, lon: opening.sunLon }), 2)
  expect(opening.lanes).toEqual([])
  await page.screenshot({ path: path.join(SHOTS, 'opening-390.png') })
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE NIGHT CHART — owner row 125, 2026-10-12
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   *"when i zoom out, i want cities to be bright light, in a dark map, visually beautiful. so are
//    ships but in tiny dots. right now ships are distinguished by size and colors, i want the color
//    to be in darker tone, size smaller, but like cities, there should be light, and major fleet
//    shoud also show the routes as well"*
//
// Four claims, and this file exists because the first three were written and then ANNOUNCED AS DONE
// before anybody counted a single element on the glass. They are counted here.
//
//   CITIES ARE LIGHT     a harbour past its mark band draws a bright core AND a halo around it, and
//                        the halo is wider for a great entrepôt than for a one-quay coast
//   SHIPS ARE EMBERS     past `HULL_EMBER_MAX_UNITS_PER_PX` a fleet is a dot with its own faint
//                        light and NO hull path at all
//   DIMMER AND SMALLER   an ember's core is strictly smaller than a harbour's, and strictly fainter,
//                        BY THE NUMBERS — "so are ships but in tiny dots" is an ordering between the
//                        two channels and not a vibe
//   THE INK IS HERS      an ember keeps her nation's fill and drops the stroke, so the "darker tone"
//                        is the same eight inks at lower opacity rather than a ninth grey
//
// UNIT: the arithmetic, which needs no browser — the tier ramp is monotonic and bounded, an ember is
// smaller than a harbour core at every density, and the ember threshold sits ABOVE the group
// threshold so the ladder has three rungs in the right order.
//
// BROWSER, merchants on (./npcOn.fixture.ts): zoomed out to the globe, every harbour on the glass is
// two circles and every merchant is an ember with no hull path; zoomed back in, the hulls return.
// The screenshot lands in docs/npc-traders/ so the owner can see the thing they asked for.

import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { PHONE, reachable, ready } from './appReady.fixture'
import { serveNpcOn } from './npcOn.fixture'
import type { TrafficFleet } from '../src/lib/rpc'
import {
  GLYPH,
  mapTrafficOf,
  HARBOUR_LIGHT_MIN_UNITS_PER_PX,
  HULL_EMBER_MAX_UNITS_PER_PX,
  HULL_GROUP_MAX_UNITS_PER_PX,
  harbourLightHalo,
  harbourLightStrength,
} from '../src/chart'

const SHOTS = path.resolve('docs', 'npc-traders')

/** A harbour light's halo opacity, as ./PortsLayer.tsx renders it (`fill-harbour-light/20`). The
 *  ships are held strictly under it — owner row 125's "darker tone", as an ordering. */
const HARBOUR_HALO_OPACITY = 20

/** The eight merchant inks, as the server spells them. */
const NATION_INKS = ['prt', 'esp', 'nld', 'eng', 'han', 'ita', 'ott', 'east']

// ── THE ARITHMETIC ─────────────────────────────────────────────────────────────────────────────

test('a harbour burns by its size, between a floor and a ceiling', () => {
  // MONOTONIC AND BOUNDED. Every tier is brighter than the one below it, the smallest coast is
  // still a light (the floor is what `harbourLightTierSpread` leaves behind), and the brightest is
  // the whole halo and never more — so no harbour can bloom off the sheet.
  const strengths = [1, 2, 3, 4, 5].map(harbourLightStrength)
  expect(strengths).toEqual([0, 0.25, 0.5, 0.75, 1])
  for (let i = 1; i < strengths.length; i++) expect(strengths[i]).toBeGreaterThan(strengths[i - 1])

  // OUT-OF-RANGE TIERS ARE CLAMPED, NOT TRUSTED. A tier the world has not invented yet, or a null
  // that arrived as NaN, must still draw a light — a harbour that renders as radius NaN is an
  // invisible city, which is the one failure mode the owner would see and could not describe.
  expect(harbourLightStrength(0)).toBe(0)
  expect(harbourLightStrength(99)).toBe(1)
  expect(harbourLightStrength(Number.NaN)).toBe(0)
  expect(Number.isFinite(harbourLightHalo(Number.NaN, 0.5))).toBe(true)

  // THE HALO IS ALWAYS WIDER THAN THE CORE IT SURROUNDS, at every tier and every density — that
  // relation IS the glow, and a halo inside its core would simply be a brighter dot.
  for (const upp of [0.05, 0.2, 0.5, 0.92]) {
    for (const tier of [1, 2, 3, 4, 5]) {
      const halo = harbourLightHalo(tier, upp)
      expect(halo).toBeGreaterThan(GLYPH.portDotRadius * upp)
    }
    // …and a tier-5 entrepôt out-burns a tier-1 coast at the same density.
    expect(harbourLightHalo(5, upp)).toBeGreaterThan(harbourLightHalo(1, upp))
  }
})

test('a ship is smaller and dimmer than a city, and the ladder has three rungs in order', () => {
  // "SO ARE SHIPS BUT IN TINY DOTS" IS AN ORDERING, so it is asserted as one. An ember's core is
  // strictly inside a harbour's core, and its halo strictly inside a harbour's halo at the DIMMEST
  // tier — a ship can never out-shout even the smallest city on the same sheet.
  expect(GLYPH.emberRadius).toBeLessThan(GLYPH.portDotRadius)
  for (const upp of [0.4, 0.92]) {
    expect(GLYPH.emberRadius * GLYPH.emberHaloScale * upp).toBeLessThan(harbourLightHalo(1, upp))
  }

  // THE LADDER: silhouettes and squadrons · flagship only · an ember. The ember rung must sit ABOVE
  // the group rung, or a fleet would turn into a dot while still being drawn as a squadron.
  expect(HULL_EMBER_MAX_UNITS_PER_PX).toBeGreaterThan(HULL_GROUP_MAX_UNITS_PER_PX)

  // AND THE GLOBE IS PAST IT. 360° across a 390 px phone is the widest the chart ever goes; if that
  // did not cross the threshold this whole file would be asserting a branch nobody can reach.
  expect(360 / PHONE.width).toBeGreaterThan(HULL_EMBER_MAX_UNITS_PER_PX)
})

test('a lane is copied, never invented, and a stub of one draws nothing', () => {
  // THE CLIENT DECIDES NOTHING ABOUT WHO KEEPS A LANE. `fleet_lane_min_ships` lives in the world
  // config and 0111 applies it, so `mapTrafficOf` copies whatever arrived — a three-hull fleet with
  // no lane served draws none, and a one-hull fleet the server DID serve one draws it. Anything else
  // would be a second authority on the word "major", and the one that is not the server is the one
  // that goes stale.
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
  // A STUB IS NOT A LINE. One point cannot be drawn, and guessing a second would be inventing water
  // — the same rule the loop keeps (./liveWorld.ts).
  expect(laneOf({ lane: [[38.6, -9.4]] })).toBeNull()
  expect(laneOf({ lane: [] })).toBeNull()
})

// ── THE GLASS ──────────────────────────────────────────────────────────────────────────────────

/** What is actually drawn: the harbour lights, the embers, and the density they were drawn at. */
async function nightOnTheGlass(page: Page) {
  return page.evaluate(() => {
    const svg = document.querySelector('[data-testid="map-chart"] svg')
    const vb = svg?.getAttribute('viewBox')?.split(/\s+/).map(Number) ?? []
    const unitsPerPx = vb.length === 4 && svg ? vb[2] / (svg as SVGSVGElement).clientWidth : Number.NaN

    // EVERY HARBOUR ON THE SHEET, in whichever of its two renderings this zoom draws — the light
    // belongs to the harbour, so a spec that only looked at the dots would miss the great ports,
    // which is exactly the defect this file found.
    const lights = [...document.querySelectorAll('[data-port-mark]')].map((g) => {
      // Attribute match, not a class selector: the halo's Tailwind class carries a `/` for the
      // opacity and escaping that inside a selector inside a page-evaluate string is three layers of
      // backslash nobody should have to read.
      const halo = g.querySelector('circle[class*="harbour-light/20"]')
      return {
        tier: Number(g.getAttribute('data-port-tier')),
        mark: g.getAttribute('data-port-mark') ?? '',
        lit: g.getAttribute('data-port-lit') === 'yes',
        halo: halo ? Number(halo.getAttribute('r')) : null,
        core: Number(
          g.querySelector('circle[class="fill-harbour-light"]')?.getAttribute('r') ?? Number.NaN,
        ),
        circles: g.querySelectorAll('circle').length,
        paths: g.querySelectorAll('path').length,
        ring: g.querySelector('[data-testid="map-port-ring"]') !== null,
        haloIsFirst: halo !== null && g.firstElementChild === halo,
      }
    })
    const embers = [...document.querySelectorAll('[data-fleet-mark="ember"]')].map((g) => {
      const circles = [...g.querySelectorAll('circle')]
      return {
        hulls: Number(g.getAttribute('data-hulls')),
        circles: circles.length,
        radii: circles.map((c) => Number(c.getAttribute('r'))),
        classes: circles.map((c) => c.getAttribute('class') ?? ''),
        paths: g.querySelectorAll('path[data-hull-class]').length,
      }
    })
    // THE MAJOR FLEETS' LANES (owner row 125's last clause). Counted, and their ink read back, so
    // "the routes show" is a number and the ink is proven to be the company's own.
    const lanes = [...document.querySelectorAll('[data-testid="map-merchant-lane"]')].map((p) => ({
      ink: p.getAttribute('data-lane-ink') ?? '',
      d: p.getAttribute('d') ?? '',
      cls: p.getAttribute('class') ?? '',
    }))

    return {
      unitsPerPx,
      lights,
      embers,
      lanes,
      // The marks of the OTHER band, so "the hulls came back" is a count and not a feeling.
      hullPaths: document.querySelectorAll('path[data-hull-class]').length,
    }
  })
}

test('zoomed out, the cities are lights and the ships are embers', async ({ page, request, baseURL }) => {
  // TWENTY MINUTES, AND THE FIXTURE IS WHY. `npcOn()` builds the merchants-on world ONCE PER WORKER
  // — it opens the shipped image, lays up a merchant at Lisbon, runs the switch over 837 fleets and
  // warps six legs — and WHICHEVER SPEC IN THE WORKER RUNS FIRST PAYS FOR ALL OF IT. Measured here
  // at ~9 minutes, which left this test under one minute for twelve zoom-out clicks, the counting,
  // a screenshot and twelve clicks back, and it timed out at 600_000 with the chart entirely
  // correct. ./map.hulls.spec.ts carries the same 600_000 and passes only because it has so far
  // always run second, on an image this file had already built — a budget that depends on
  // alphabetical order is not a budget. The drive itself is about 90 seconds.
  test.setTimeout(1_200_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  mkdirSync(SHOTS, { recursive: true })
  await serveNpcOn(page)
  await page.setViewportSize(PHONE)
  await page.goto('map')
  await ready(page)
  await page.evaluate(() => document.documentElement.setAttribute('data-theme', 'dark'))

  // The merchants have to be on the glass before pulling back, or the ember count would be zero for
  // the honest reason that nobody is at sea yet — which is not the claim this file makes.
  await expect
    .poll(async () => (await nightOnTheGlass(page)).hullPaths, { timeout: 60_000 })
    .toBeGreaterThanOrEqual(2)

  const out = page.getByLabel('Zoom out')
  for (let i = 0; i < 12; i++) await out.click()
  await page.waitForTimeout(800)

  const wide = await nightOnTheGlass(page)

  // THE DENSITY IS PAST THE THRESHOLD — read off the glass, not assumed from a click count, because
  // "twelve presses reaches the globe" is a fact about the zoom ladder and not about this file.
  expect(wide.unitsPerPx).toBeGreaterThan(HULL_EMBER_MAX_UNITS_PER_PX)

  // EVERY CITY IS A LIGHT — EVERY ONE, not just the ones drawn as dots. The first cut of row 125
  // lit the dot and left the full mark dark, and because `PORT_TIER_BANDS` keeps the GREAT ports
  // drawn as marks longest, the harbours left unlit at the globe were precisely the biggest cities
  // in the world: 35 of them. So the count below is over every `data-port-mark` on the sheet and
  // the assertion is "not one of you is dark".
  expect(wide.lights.length).toBeGreaterThanOrEqual(20)
  expect(wide.lights.filter((l) => !l.lit)).toEqual([])
  // Both renderings are present at this density, so this really is the mixed sheet that caught it.
  expect(wide.lights.some((l) => l.mark === 'dot')).toBe(true)
  expect(wide.lights.some((l) => l.mark === 'full')).toBe(true)
  for (const l of wide.lights) {
    expect(l.halo).not.toBeNull()
    expect(Number.isFinite(l.halo!) && l.halo! > 0).toBe(true)
    // THE HALO IS ALWAYS THE FIRST CHILD, so it is painted BEHIND whatever the harbour's mark is
    // — a glow over a triangle would hide the mark it is meant to announce.
    expect(l.haloIsFirst).toBe(true)
    if (l.mark === 'dot') {
      // A dot is its halo and its core, and nothing else.
      expect(l.circles).toBe(2)
      expect(l.halo!).toBeGreaterThan(l.core)
    } else {
      // A FULL MARK KEEPS EVERYTHING IT ALREADY HAD. Its triangle is still a path, and a tier-5
      // entrepôt still wears row 90's ring — which is why this is not `circles === 1`: the first
      // cut of this assertion said so, and the 35 great ports failed it for the correct reason
      // that their ring was exactly where row 90 put it.
      expect(l.paths).toBeGreaterThanOrEqual(1)
      if (l.ring) expect(l.circles).toBe(2)
      else expect(l.circles).toBe(1)
    }
  }
  // AND THE BRIGHTNESS REALLY FOLLOWS SIZE. If this frame holds more than one tier, the bigger
  // tier's halo must be the wider one; if it holds only one, the claim is not made rather than faked.
  const byTier = new Map<number, number>()
  for (const l of wide.lights) byTier.set(l.tier, l.halo!)
  if (byTier.size > 1) {
    const tiers = [...byTier.keys()].sort((a, b) => a - b)
    expect(byTier.get(tiers.at(-1)!)!).toBeGreaterThan(byTier.get(tiers[0])!)
  }

  // EVERY SHIP IS AN EMBER, and the hull paths are GONE — not hidden, not zero-sized, absent.
  expect(wide.embers.length).toBeGreaterThanOrEqual(2)
  expect(wide.hullPaths).toBe(0)
  const smallestCore = Math.min(...wide.lights.filter((l) => l.mark === 'dot').map((l) => l.core))
  for (const e of wide.embers) {
    expect(e.circles).toBe(2)
    expect(e.paths).toBe(0)
    expect(e.radii[0]).toBeGreaterThan(e.radii[1])
    // SMALLER THAN THE SMALLEST CITY ON THE SHEET, measured on the glass and not in the arithmetic.
    expect(e.radii[1]).toBeLessThan(smallestCore)
    // DIMMER, TOO — AND DIMMER THAN A CITY, READ OFF THE RENDERED CLASS. The ink is hers at
    // reduced opacity and the stroke that outlined a hull is gone; but "dimmer" also has to be a
    // RELATION, because the arithmetic above can only compare one ember to one harbour and the
    // sheet holds 240 of the first against 252 of the second. The first cut rendered the ember's
    // halo at /25 against a harbour light's /20 — the ship's glow more opaque than the city's —
    // and every numeric assertion in this file passed while the screenshot showed the European
    // coast as saturated confetti over the lights it was meant to sit beneath. So the OPACITIES
    // are compared, both of them, strictly.
    expect(e.classes.join(' ')).not.toMatch(/stroke-/)
    const emberHaloOp = Number(/opacity-(\d+)/.exec(e.classes[0])?.[1] ?? Number.NaN)
    const emberCoreOp = Number(/opacity-(\d+)/.exec(e.classes[1])?.[1] ?? Number.NaN)
    expect(Number.isFinite(emberHaloOp) && Number.isFinite(emberCoreOp)).toBe(true)
    expect(emberHaloOp).toBeLessThan(HARBOUR_HALO_OPACITY)
    expect(emberCoreOp).toBeLessThan(100) // a harbour's core carries no opacity class at all
    expect(emberHaloOp).toBeLessThan(emberCoreOp)
    // The ember still says what she is, so a click still has something to select.
    expect(e.hulls).toBeGreaterThanOrEqual(1)
  }

  // AND THE MAJOR FLEETS SHOW THEIR ROUTES — *"major fleet shoud also show the routes as well"*.
  // Every lane on the sheet is a real path in a real nation's ink, and there are fewer lanes than
  // embers, because only the major fleets keep one (0111 `fleet_lane_min_ships`).
  expect(wide.lanes.length).toBeGreaterThanOrEqual(1)
  expect(wide.lanes.length).toBeLessThanOrEqual(wide.embers.length)
  for (const l of wide.lanes) {
    // A real polyline: more than one vertex, so no lane is a dot pretending to be a route.
    expect(l.d.length).toBeGreaterThan(8)
    expect((l.d.match(/[ML]/g) ?? []).length).toBeGreaterThanOrEqual(2)
    // HER OWN INK, which is the same channel the ember uses — so a lane and the fleet keeping it
    // read as one thing with no legend.
    expect(NATION_INKS).toContain(l.ink)
    expect(l.cls).toContain(`stroke-nation-${l.ink}`)
    expect(l.cls).toContain('fill-none')
  }

  // WHAT THE GLASS ACTUALLY HELD, printed so the run is evidence and not a tick. These figures are
  // not pinned — a fixture that sails her merchants has every right to a different sea next run —
  // but a reader should be able to see the night chart's three channels in one line.
  console.log(
    `night chart at ${wide.unitsPerPx.toFixed(3)} °/px: ` +
      `${wide.lights.length} harbour light(s) (${wide.lights.filter((l) => l.mark === 'full').length} full marks, ` +
      `${wide.lights.filter((l) => l.mark === 'dot').length} dots, tiers ${[...byTier.keys()].sort((a, b) => a - b).join('/')}), ` +
      `${wide.embers.length} ember(s) with ${wide.hullPaths} hull path(s), ` +
      `${wide.lanes.length} lane(s) in ${new Set(wide.lanes.map((l) => l.ink)).size} nation ink(s)`,
  )

  await page.screenshot({ path: path.join(SHOTS, 'map-night-390-globe.png') })

  // AND IT IS A BAND, NOT A ONE-WAY DOOR. Zoom back in and the hulls return, the embers go: a
  // rendering branch that could not be left would be a bug the owner would find by moving the map.
  const inBtn = page.getByLabel('Zoom in')
  for (let i = 0; i < 12; i++) await inBtn.click()
  await page.waitForTimeout(800)
  const close = await nightOnTheGlass(page)
  expect(close.unitsPerPx).toBeLessThan(HULL_EMBER_MAX_UNITS_PER_PX)
  expect(close.embers.length).toBe(0)
  expect(close.hullPaths).toBeGreaterThanOrEqual(2)

  expect(close.unitsPerPx).toBeLessThan(HARBOUR_LIGHT_MIN_UNITS_PER_PX)
  // THE LANES GO WITH THE LIGHTS. Close in the sheet is a working chart, and a lane is THINNED —
  // straight where the real course bends — so drawing it at a span where that shows would be
  // putting a wrong line on the water somebody is reading.
  expect(close.lanes).toEqual([])

  // AND NOTHING GLOWS CLOSE IN, ON A SHEET THAT HAS HARBOURS ON IT TO NOT GLOW. A working chart is
  // names, roads and silhouettes, and a glow laid over the detail somebody zoomed in to read is a
  // smudge — so the close view must be exactly what it was before row 125. Asserted, because "it
  // only shows when you zoom out" is the owner's own framing of this row and an unasserted gate is
  // a gate that drifts.
  //
  // READ OFF A FRESH OPENING FRAME rather than off wherever twelve clicks back in happened to land.
  // The first cut of this asserted `close.lights.length >= 1` on that landing frame and went red
  // with ZERO harbours — out past the globe and back in, the chart had put the view over open water
  // where there is no harbour to draw, which is a true fact about panning and nothing at all about
  // the lights. The claim needs a sheet with harbours on it; the opening frame is the one frame
  // this suite can count on for that, and it is well below the night band (~0.038 against 0.115).
  await page.goto('map')
  await ready(page)
  await expect.poll(async () => (await nightOnTheGlass(page)).lights.length, { timeout: 60_000 }).toBeGreaterThanOrEqual(1)
  const opening = await nightOnTheGlass(page)
  expect(opening.unitsPerPx).toBeLessThan(HARBOUR_LIGHT_MIN_UNITS_PER_PX)
  expect(opening.lights.filter((l) => l.lit)).toEqual([])
  expect(opening.lights.filter((l) => l.halo !== null)).toEqual([])
  expect(opening.lanes).toEqual([])
})

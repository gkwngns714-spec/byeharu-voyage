import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { serveNpcOn } from './npcOn.fixture'
import { serveLitSeas } from './seasLit.fixture'
import { buildChartModel, quietHarbours, type PortRole } from '../src/chart/chartModel'
import { clampView, maxSpanX, MAX_SPAN_X, viewBoxOf, zoomAt } from '../src/chart/chartView'
import { GLYPH, harbourLightHalo, WIDE_SCALE, wideScale } from '../src/chart/glyphs'
import { LABEL_PRIORITY, planLabels, type LabelRequest } from '../src/chart/labels'
import type { MapFleet, MapPort, MapTraffic } from '../src/chart/mapTypes'
import { shipMarks, stableSlot, THIN_DENSITY, THIN_MOD } from '../src/chart/shipMarks'
import { CHART_HEIGHT, type ViewBox } from '../src/lib/geo'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MAP AS ONE PICTURE (2026-11-14; docs/dev-log/2026-11-14-map-look.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, on a phone: *"and fix the graphics overall, especially map. it is weird"*. Two days of marks had been added
// to the chart (battle rings, merchants and their kinds, the closed seas' shade and its key, the route bar), each tested
// alone. Looked at together on a phone they made a picture nobody had judged. These are the laws that picture now keeps:
//
//   (1) A PICTURE MARK SHRINKS WITH THE DENSITY (glyphs.ts `wideScale`): full size on a coast, never under the floor, the
//       same on a wide glass showing the same water with room to spare. A harbour's light is never wider than its token.
//   (2) A PORTRAIT GLASS NEVER SHOWS MORE THAN THE WORLD IS TALL (chartView.ts `maxSpanX`): furthest out, the world covers
//       the glass's height and east-west is a pan. A landscape glass still reaches the whole world.
//   (3) MERCHANTS ARE THINNED BY THE GLASS, YOURS NEVER (shipMarks.ts `THIN_DENSITY`): by a fact about the ship alone, so
//       the kept ones are the same at every pan; cargo, navy and pirate ships are not in the rule.
//   (3b) PAST A COAST, A HARBOUR WITH NO NAME ON THE GLASS IS A QUIET DOT (chartModel.ts `quietHarbours`): no triangle, ring,
//       light or roads; never a harbour your fleet is using, never the pressed one.
//   (4) ON THE DENSE WORLD NO TWO NAMES OVERLAP at the opening view, a sea and furthest out; every name's halo is round;
//       every merchant hull and harbour light is inside its bound; the graticule ends where the world does.
//   (5) THE CLOSED SEAS' SHADE IS UNDER EVERY MARK AND NAME, and the chrome on the glass (fleets list open, zoom column,
//       the shade's key, the minimap) covers none of itself at 320 and 390, in English and Korean.

// ── (1) the density scale ───────────────────────────────────────────────────────────────────────
test('a picture mark is full size on a coast, shrinks evenly as a phone takes in more world, and never passes the floor', () => {
  expect(wideScale(5 / 390)).toBe(1)
  expect(wideScale(WIDE_SCALE.fromUnitsPerPx)).toBe(1)
  expect(wideScale(WIDE_SCALE.toUnitsPerPx)).toBeCloseTo(WIDE_SCALE.floor, 9)
  expect(wideScale(5)).toBeCloseTo(WIDE_SCALE.floor, 9)
  for (const bad of [Number.NaN, Number.POSITIVE_INFINITY, 0, -1]) expect(wideScale(bad)).toBe(1)
  let last = 1
  for (let span = 20; span <= 360; span += 10) {
    const s = wideScale(span / 390)
    expect(s).toBeLessThanOrEqual(last)
    expect(s).toBeGreaterThanOrEqual(WIDE_SCALE.floor)
    last = s
  }
  // the same water on a wide glass keeps bigger marks than on a phone
  expect(wideScale(180 / 1280)).toBeGreaterThan(wideScale(180 / 390))
  // a harbour's light: on a coast its token's size, on a phone's ocean smaller in pixels, never under the dot
  const px = (upp: number) => harbourLightHalo(5, upp) / upp
  expect(px(0.01)).toBeCloseTo(GLYPH.portDotRadius * GLYPH.harbourLightHaloScale, 9)
  expect(px(90 / 390)).toBeLessThan(px(0.01))
  expect(px(1)).toBeGreaterThan(GLYPH.portDotRadius)
})

// ── (2) the loosest view ────────────────────────────────────────────────────────────────────────
test('furthest out, a portrait glass is covered pole to pole; a landscape glass still holds the whole world', () => {
  for (const [w, h] of [[390, 756], [320, 552], [360, 640], [768, 1024]]) {
    const aspect = w / h
    expect(maxSpanX(aspect)).toBeCloseTo(CHART_HEIGHT * aspect, 9)
    const box = viewBoxOf(clampView({ cx: 0, cy: 0, spanX: 1e6 }, aspect), aspect)
    expect(box.height).toBeCloseTo(CHART_HEIGHT, 6)
    expect(box.y).toBeCloseTo(-CHART_HEIGHT / 2, 6)
    // no wheel or pinch passes it either
    let v = clampView({ cx: 10, cy: -30, spanX: 30 }, aspect)
    for (let i = 0; i < 30; i++) v = zoomAt(v, aspect, 1 / 1.6, 0.3, 0.7)
    expect(v.spanX).toBeCloseTo(maxSpanX(aspect), 9)
    expect(viewBoxOf(v, aspect).height).toBeLessThanOrEqual(CHART_HEIGHT + 1e-6)
  }
  for (const aspect of [1, 1280 / 768, 2.4, Number.NaN, 0]) expect(maxSpanX(aspect)).toBe(MAX_SPAN_X)
})

// ── (3) who is thinned ──────────────────────────────────────────────────────────────────────────
const sailing = (id: string, lat: number, lon: number, extra: { cargo?: true; navy?: true; pirate?: true } = {}): MapTraffic => ({
  kind: 'sailing',
  id,
  name: id,
  hulls: ['barca'],
  voyage: {
    course: [{ lat, lon }, { lat: lat + 1, lon: lon + 1 }],
    segIndex: 0,
    legFrac: 0,
    segNm: 100,
    at: { lat, lon },
    sailedNm: 0,
    totalNm: 100,
    etaMs: 1_000_000,
    heldUntilMs: null,
    departedMs: 0,
    destinationCode: null,
    destPoint: null,
    waters: [],
  },
  enduranceDays: 20,
  company: 'Casa', ink: 'prt', docked: false, berthCode: null, berthIndex: 0, nextLapAtMs: null, loop: null, lane: null, tracked: false,
  ...extra,
})
const mine = (id: string, lat: number, lon: number): MapFleet => ({ kind: 'anchored', id, name: id, hulls: ['carlat'], enduranceDays: 20, at: { lat, lon } })

test('the glass thins the merchants by a fact about each ship; your fleets and the marked kinds are never thinned', () => {
  const merchants = Array.from({ length: 80 }, (_, i) => sailing(`m${i}`, (i % 9) - 4, (i % 13) - 6))
  const kinds = [sailing('cargo-1', 1, 1, { cargo: true }), sailing('navy-1', 2, 2, { navy: true }), sailing('pirate-1', 3, 3, { pirate: true })]
  const fleets = [mine('own-1', 0, 0), mine('own-2', 2, -3)]
  const model = buildChartModel(fleets, [], [], null, [...merchants, ...kinds])
  const view: ViewBox = { x: -20, y: -20, width: 40, height: 40 }
  const drawn = (upp?: number) => shipMarks(model.fleets, model.traffic, view, upp)
  const ids = (upp?: number) => drawn(upp).traffic.map((t) => t.fleet.id)

  // no glass named (a spec, the old callers) and a coast: every merchant
  expect(ids()).toHaveLength(83)
  expect(ids(0.02)).toHaveLength(83)
  let last = 83
  for (const tier of [...THIN_DENSITY].reverse()) {
    const kept = ids(tier.fromUnitsPerPx)
    // exactly the merchants whose own slot is under the tier's count, and every marked kind
    expect([...kept].sort()).toEqual([...merchants.filter((m) => stableSlot(m.id) < tier.keep).map((m) => m.id), 'cargo-1', 'navy-1', 'pirate-1'].sort())
    expect(kept.length).toBeLessThanOrEqual(last)
    last = kept.length
    // yours: all of them, at every density
    expect(drawn(tier.fromUnitsPerPx).fleets.map((f) => f.fleet.id).sort()).toEqual(['own-1', 'own-2'])
  }
  // where a pixel is two thirds of a degree or more no plain merchant is drawn at all
  expect(ids(1)).toEqual(expect.arrayContaining(['cargo-1', 'navy-1', 'pirate-1']))
  expect(ids(1)).toHaveLength(3)
  // a ship kept on a tighter rung is kept on every looser one: nothing appears as you pull back
  const tiers = [...THIN_DENSITY].sort((a, b) => a.fromUnitsPerPx - b.fromUnitsPerPx)
  for (let i = 1; i < tiers.length; i++) for (const id of ids(tiers[i].fromUnitsPerPx)) expect(ids(tiers[i - 1].fromUnitsPerPx)).toContain(id)
  expect(Math.max(...THIN_DENSITY.map((t) => t.keep))).toBeLessThan(THIN_MOD)
})

// ── (3b) which harbours are quiet dots ──────────────────────────────────────────────────────────
test('past a coast, a harbour with no name on the glass is a quiet dot; yours and the pressed one never are', () => {
  const port = (code: string) => ({ code }) as MapPort
  const full = ['LIS', 'CAD', 'SVQ', 'TNG', 'CEU'].map(port)
  const named = new Set(['LIS', 'CAD'])
  const roles = new Map<string, PortRole>([['SVQ', 'anchorage']])
  // on a coast (a phone holding 20 degrees or less) nothing is quiet
  expect([...quietHarbours(full, named, roles, null, 15 / 390)]).toEqual([])
  // at a sea: the unnamed ones, less the harbour a fleet of yours is using and the pressed one
  expect([...quietHarbours(full, named, roles, null, 45 / 390)].sort()).toEqual(['CEU', 'TNG'])
  expect([...quietHarbours(full, named, roles, 'TNG', 45 / 390)]).toEqual(['CEU'])
})

/** A name over or under its mark: the gap (9 px), half a great name's line (8 px) and the mark's own lean, with room. */
const NAME_REACH_PX = 26

test('past a coast a name is set over or under its own mark, a lesser name gives way, and nothing steps out', () => {
  const at = (id: string, text: string, x: number, y: number, priority: number): LabelRequest => ({ id, text, at: { x, y }, priority, tone: 'port-quiet' })
  const view = { x: 0, y: 0, width: 40, height: 80 }
  const upp = 40 / 390
  // three harbours in a row, 3 px apart on the glass: a side placement of each would lie across its neighbours
  const row = [at('port:A', 'Barcelona', 20, 40, 15), at('port:B', 'Valencia', 20.3, 40, 13), at('port:C', 'Tarragona', 19.7, 40, 12)]
  const wide = planLabels(row, { viewBox: view, unitsPerPx: upp, centredOnMark: true })
  expect(wide.map((l) => l.side).every((s) => s === 'above' || s === 'below'), wide.map((l) => `${l.text}:${l.side}`).join(' ')).toBe(true)
  expect(wide.every((l) => l.leader === undefined)).toBe(true)
  // the greatest is named, and its name's middle is on its own mark's meridian
  const first = wide.find((l) => l.id === 'port:A')!
  expect(first.side).toBe('above')
  expect(first.box.x + first.box.width / 2).toBeCloseTo(20, 6)
  // there are two places (over, under) for three names here: the least is the one that is not drawn
  expect(wide.map((l) => l.id).sort()).toEqual(['port:A', 'port:B'])
  // a harbour a fleet of yours is using may still take a side when over and under are taken
  const mine = planLabels([...row, { ...at('port:D', 'Sagunto', 20.1, 40, LABEL_PRIORITY.anchorage), tone: 'port-active' }], { viewBox: view, unitsPerPx: upp, centredOnMark: true })
  expect(mine.find((l) => l.id === 'port:D')?.side).toBe('above')
  // and on a coast the rule is off: a harbour alone takes the right, as it always did, and with the rule on it is named over its mark
  expect(planLabels([row[0]], { viewBox: view, unitsPerPx: upp })[0].side).toBe('right')
  expect(planLabels([row[0]], { viewBox: view, unitsPerPx: upp, centredOnMark: true })[0].side).toBe('above')
})

// ── the running game ────────────────────────────────────────────────────────────────────────────
type Box = { x: number; y: number; w: number; h: number; name: string }
const hits = (a: Box, b: Box, slack = 0) => a.x + slack < b.x + b.w && b.x + slack < a.x + a.w && a.y + slack < b.y + b.h && b.y + slack < a.y + a.h

async function openMap(page: Page, lang: 'en' | 'ko') {
  await page.addInitScript((l) => {
    try {
      localStorage.setItem('bv.locale', l)
    } catch {
      /* a private window */
    }
  }, lang)
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g')
  await page.evaluate(() => document.fonts.ready)
}

/** The view's box, once it has stopped gliding. */
async function restingView(page: Page): Promise<{ width: number; height: number; y: number; px: number }> {
  const read = () =>
    page.evaluate(() => {
      const svg = document.querySelector('[data-testid="map-view"]') as SVGSVGElement
      const b = svg.viewBox.baseVal
      return { width: b.width, height: b.height, y: b.y, px: svg.getBoundingClientRect().width }
    })
  let prev = await read()
  await expect
    .poll(async () => {
      await page.waitForTimeout(150)
      const now = await read()
      const still = Math.abs(now.width - prev.width) < 1e-6
      prev = now
      return still
    })
    .toBe(true)
  return prev
}

/** Press the zoom column's + or − `times` times, as a player does. */
async function press(page: Page, which: 'in' | 'out', times: number) {
  const button = page.getByTestId('map-view-controls').locator('button').nth(which === 'in' ? 0 : 1)
  for (let i = 0; i < times; i++) {
    await button.click()
    await page.waitForTimeout(120)
  }
  return restingView(page)
}

/** What the picture holds, measured on the glass. */
const measure = (page: Page) =>
  page.evaluate(() => {
    const box = (e: Element, name: string) => {
      const r = e.getBoundingClientRect()
      return { x: r.x, y: r.y, w: r.width, h: r.height, name }
    }
    // a name is its letters and, when it has one, its flag: the group holds both
    const names = [...document.querySelectorAll('[data-testid="map-labels"] text')].map((t) => {
      const flag = t.parentElement?.hasAttribute('data-label-flag') ? t.parentElement.querySelector('[data-testid="map-label-flag"]') : null
      const a = box(t, t.textContent ?? '')
      if (!flag) return a
      const f = box(flag, a.name)
      const x = Math.min(a.x, f.x)
      const y = Math.min(a.y, f.y)
      return { x, y, w: Math.max(a.x + a.w, f.x + f.w) - x, h: Math.max(a.y + a.h, f.y + f.h) - y, name: a.name }
    })
    const joins = [...document.querySelectorAll('[data-testid="map-labels"] text, [data-testid="map-sea-names"] text')].map((t) => getComputedStyle(t).strokeLinejoin)
    const hulls = [...document.querySelectorAll('[data-testid="map-merchant"] path[data-hull-class]')].map((p) => {
      const r = p.getBoundingClientRect()
      return Math.max(r.width, r.height)
    })
    const lights = [...document.querySelectorAll('[data-testid="map-ports"] circle.bv-sun-light')].map((c) => c.getBoundingClientRect().width / 2)
    // every harbour's name, the side it was set on, and how far its middle is from its own mark (the nearest copy of the sheet)
    const beside = [...document.querySelectorAll('[data-testid="map-labels"] text[data-label-id^="port:"]')].map((t) => {
      const code = (t.getAttribute('data-label-id') ?? '').slice('port:'.length)
      const flag = t.parentElement?.hasAttribute('data-label-flag') ? t.parentElement.querySelector('[data-testid="map-label-flag"]') : null
      const a = t.getBoundingClientRect()
      const f = flag ? flag.getBoundingClientRect() : a
      const cx = (Math.min(a.left, f.left) + Math.max(a.right, f.right)) / 2
      const cy = (Math.min(a.top, f.top) + Math.max(a.bottom, f.bottom)) / 2
      let far = Infinity
      for (const m of document.querySelectorAll(`[data-testid="map-ports"] [data-port-code="${code}"]`)) {
        // the mark's own point: its smallest drawn piece is centred on it (a light's halo and a road are wider and may lean)
        let best: DOMRect | null = null
        for (const piece of m.querySelectorAll('circle, path, use')) {
          const r = piece.getBoundingClientRect()
          if (r.width > 0 && (!best || r.width * r.height < best.width * best.height)) best = r
        }
        const r = best ?? m.getBoundingClientRect()
        far = Math.min(far, Math.hypot(r.left + r.width / 2 - cx, r.top + r.height / 2 - cy))
      }
      return { name: t.textContent ?? '', side: t.getAttribute('data-label-side') ?? '', far }
    })
    const grid = document.querySelector('[data-testid="map-graticule"]') as SVGGraphicsElement | null
    const g = grid ? grid.getBBox() : null
    return { beside, names, joins, hulls, lights, grid: g ? { top: g.y, foot: g.y + g.height } : null, merchants: document.querySelectorAll('[data-testid="map-merchant"]').length, mine: document.querySelectorAll('[data-testid="map-ship"], [data-port-code] path.fill-accent').length }
  })

for (const glass of [
  { tag: '390', width: 390, height: 844 },
  { tag: '320', width: 320, height: 640 },
]) {
  test.describe(`the dense world on a ${glass.tag} px phone`, () => {
    test.use({ viewport: { width: glass.width, height: glass.height }, hasTouch: true, deviceScaleFactor: 2, locale: 'en-US' })

    test('no two names overlap, marks keep their bounds and the furthest view covers the glass', async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      test.setTimeout(600_000)
      await serveNpcOn(page)
      await openMap(page, 'en')

      // the opening view (a coast), a sea (two presses out) and furthest out (pressed until it stops)
      const rungs: { name: string; view: Awaited<ReturnType<typeof restingView>> }[] = []
      rungs.push({ name: 'the opening view', view: await restingView(page) })
      const check = async (rung: (typeof rungs)[number]) => {
        const upp = rung.view.width / rung.view.px
        const scale = wideScale(upp)
        const seen = await measure(page)
        // (4a) no two names overlap. 1 px of slack: two halos may touch, two words may not share a pixel of letters.
        const clash: string[] = []
        for (let i = 0; i < seen.names.length; i++) for (let j = i + 1; j < seen.names.length; j++) if (hits(seen.names[i], seen.names[j], 2)) clash.push(`${seen.names[i].name} / ${seen.names[j].name}`)
        expect(clash, `names overlap at ${rung.name} (${glass.tag})`).toEqual([])
        expect(seen.names.length, `no names at ${rung.name}`).toBeGreaterThan(0)
        // (4a') PAST A COAST A NAME STANDS AT ITS OWN CITY (2026-11-14, the second look pass): over or under its mark, its middle within
        // NAME_REACH_PX of it. "Barcelona" stood beside Lisbon and "Bordeaux" off Galicia when a name was set to one side. Only a
        // harbour a fleet of yours is using may take a side (the one fleet of this world lies in one harbour).
        if (upp > WIDE_SCALE.fromUnitsPerPx) {
          const aside = seen.beside.filter((b) => b.side !== 'above' && b.side !== 'below')
          expect(aside.length, `names set to one side at ${rung.name}: ${aside.map((b) => b.name).join(', ')}`).toBeLessThanOrEqual(1)
          const adrift = seen.beside.filter((b) => (b.side === 'above' || b.side === 'below') && !(b.far <= NAME_REACH_PX))
          expect(adrift.map((b) => `${b.name} ${Math.round(b.far)} px`), `names away from their marks at ${rung.name}`).toEqual([])
        }
        // (4b) every halo is round: no spike past a letter
        expect([...new Set(seen.joins)], `a name's halo is not round at ${rung.name}`).toEqual(['round'])
        // (4c) a merchant hull: never longer than the biggest class at this density (and its keyline), never a speck
        const longest = 2 * Math.max(...Object.values(GLYPH.hullHalfLength), GLYPH.cargoHullHalfLength, GLYPH.navyHullHalfLength, GLYPH.pirateHullHalfLength, GLYPH.shipHalfLength)
        for (const h of seen.hulls) {
          expect(h, `a hull is too big at ${rung.name}`).toBeLessThanOrEqual(longest * scale + 3)
          expect(h, `a hull is a speck at ${rung.name}`).toBeGreaterThanOrEqual(2)
        }
        // (4d) a harbour's light: never wider than the token at this density
        const widest = GLYPH.portDotRadius * GLYPH.harbourLightHaloScale * scale
        for (const r of seen.lights) expect(r, `a harbour light is too wide at ${rung.name}`).toBeLessThanOrEqual(widest + 0.75)
        // (4e) the graticule ends where the world does
        if (seen.grid) {
          expect(seen.grid.top).toBeGreaterThanOrEqual(-CHART_HEIGHT / 2 - 1e-6)
          expect(seen.grid.foot).toBeLessThanOrEqual(CHART_HEIGHT / 2 + 1e-6)
        }
        // yours is on the picture at every rung: her hull at sea, or her harbour's brass mark
        expect(seen.mine, `your fleet is not on the picture at ${rung.name}`).toBeGreaterThan(0)
        return seen
      }
      const coast = await check(rungs[0])
      rungs.push({ name: 'a sea', view: await press(page, 'out', 2) })
      await check(rungs[1])
      rungs.push({ name: 'furthest out', view: await press(page, 'out', 12) })
      const far = await check(rungs[2])

      // (2) furthest out the world covers the glass's height: no empty band above or below it
      expect(rungs[2].view.height).toBeLessThanOrEqual(CHART_HEIGHT + 1e-6)
      expect(rungs[2].view.width).toBeLessThan(MAX_SPAN_X)
      // (3) and the glass holds fewer merchants per degree than the coast did: the far view is 6 times the water or more
      expect(rungs[2].view.width / rungs[0].view.width).toBeGreaterThan(4)
      expect(far.merchants, 'the far view is still a pile of hulls').toBeLessThan(Math.max(40, coast.merchants * 6))
    })
  })
}

for (const lang of ['en', 'ko'] as const) {
  for (const glass of [
    { tag: '390', width: 390, height: 844 },
    { tag: '320', width: 320, height: 640 },
  ]) {
    test.describe(`the closed seas and the chrome at ${glass.tag} px, ${lang}`, () => {
      test.use({ viewport: { width: glass.width, height: glass.height }, hasTouch: true, deviceScaleFactor: 2, locale: lang === 'ko' ? 'ko-KR' : 'en-US' })

      test('no shade on the water, and nothing on the glass covers anything else on it', async ({ page, request, baseURL }) => {
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
        test.setTimeout(600_000)
        await serveLitSeas(page)
        await openMap(page, lang)
        // the sea is one colour: no shade on the water and no key for one (owner, 2026-11-14)
        await page.waitForTimeout(3000)
        await expect(page.getByTestId('map-closed-seas')).toHaveCount(0)
        await expect(page.getByTestId('map-closed-seas-key')).toHaveCount(0)

        // (5c) the chrome, with the fleets list open and the chart pulled back so the minimap is up
        await press(page, 'out', 2)
        await page.getByTestId('map-fleets-corner').locator('button[aria-expanded]').click()
        await expect(page.getByTestId('map-fleet-row').first()).toBeVisible()
        await expect(page.getByTestId('map-minimap')).toBeVisible()
        const chrome = await page.evaluate(() =>
          ['map-fleets-corner', 'map-view-controls', 'map-minimap'].map((id) => {
            const r = document.querySelector(`[data-testid="${id}"]`)!.getBoundingClientRect()
            return { x: r.x, y: r.y, w: r.width, h: r.height, name: id }
          }),
        )
        const covered: string[] = []
        for (let i = 0; i < chrome.length; i++) for (let j = i + 1; j < chrome.length; j++) if (hits(chrome[i], chrome[j])) covered.push(`${chrome[i].name} / ${chrome[j].name}`)
        expect(covered, `chrome covers chrome at ${glass.tag} ${lang}`).toEqual([])
        for (const c of chrome) {
          expect(c.x, `${c.name} is off the glass`).toBeGreaterThanOrEqual(0)
          expect(c.x + c.w, `${c.name} is off the glass`).toBeLessThanOrEqual(glass.width)
        }
        // the zoom column ends on one right edge
        const edges = await page.getByTestId('map-view-controls').evaluate((col) => [...col.children].map((c) => Math.round(c.getBoundingClientRect().right)))
        expect(new Set(edges).size, `the zoom column's right edge is ragged: ${edges.join(' ')}`).toBe(1)
      })
    })
  }
}

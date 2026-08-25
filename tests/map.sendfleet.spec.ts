import { test, expect } from '@playwright/test'
import { fitToViewBox } from '../src/lib/geo'
import { FIT_PADDING, openingBounds } from '../src/chart'
import { REAL_PORTS } from './mapWorld.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MAP'S ONE ACT, DRIVEN — three defects found in a real browser on the running game, each one
// with an assertion that fails without its fix.
//
// They were found by playing, not by reading, and they are all one class: **a screen that looks
// like it worked.** A tap that misses a harbour opens a plausible OPEN SEA panel for a different
// destination. A fold that can use a standing order but not write one looks like a control with
// one dead option. An opening frame with no land in it looks like a broken renderer. None of them
// throws, none of them logs, and the first two cost the player a voyage.
//
//   1. A TAP ON A HARBOUR'S NAME IS A TAP ON THE HARBOUR   (browser, and it was not)
//   2. THE RATIO IS SET ON THE FOLD, AND SETTING IT SENDS NOTHING   (browser)
//   3. THE OPENING FRAME ALWAYS HAS A COAST IN IT   (pure + browser)
//
// ── HOW EACH ONE IS PROVEN, AND WHY IT CANNOT PASS VACUOUSLY ───────────────────────────────────
// The browser half drives THE REAL GAME: a real PostgreSQL (PGlite) in the tab running the real
// migration chain, the §K.1 founding house, real `cmd.preview` dry runs. Nothing here is stubbed,
// so a green line means the chain answered. Every assertion is measured off the DOM the player
// actually touches — the text element of a port's name, the rendered coastline path — never off a
// prop or a constant this file also owns.
//
// It SKIPS with a stated reason when nothing is served rather than passing (tests/layout.spec.ts's
// rule, and the reason acceptance.yml has a non-vacuity floor).
//
// Run it: npm run build && npm run preview, then `npx playwright test map.sendfleet.spec.ts`.
// Point it elsewhere with PLAYWRIGHT_BASE_URL.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** iPhone 14 Pro logical viewport — the device the owner's rules are written for. */
const PHONE = { width: 390, height: 844 }
const PHONE_ASPECT = PHONE.width / PHONE.height

/** Every harbour there is, as the chart takes them. A harbour is where land meets water, which is
 *  why the opening frame can find land with no coastline in hand (src/chart/chartView.ts). */
const WORLD = REAL_PORTS.map((p) => ({ lat: p.lat, lon: p.lon }))

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 3a. THE OPENING FRAME ALWAYS HAS A COAST IN IT — pure, no browser.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** What the player would actually be looking at: `openingBounds` as `useChartSurface` uses it —
 *  through `fitView`, so the padding and the aspect are the real ones and not this file's idea. */
function opensOn(focus: { lat: number; lon: number }) {
  const bounds = openingBounds([focus], [focus], WORLD, PHONE_ASPECT)
  const box = fitToViewBox(bounds, PHONE_ASPECT, FIT_PADDING)
  return {
    minLon: box.x,
    maxLon: box.x + box.width,
    // The projection is y = −lat (src/lib/geo/projection.ts), so the box's top is the HIGHER
    // latitude. Read through it rather than assuming a sign.
    minLat: -(box.y + box.height),
    maxLat: -box.y,
  }
}

function harboursIn(frame: ReturnType<typeof opensOn>): string[] {
  return REAL_PORTS.filter(
    (p) =>
      p.lon >= frame.minLon && p.lon <= frame.maxLon && p.lat >= frame.minLat && p.lat <= frame.maxLat,
  ).map((p) => p.code)
}

test.describe('the opening frame is never a frame of empty water', () => {
  // The case that made the rule. A fleet may ride at anchor on any point of open water (0039,
  // OWNER_REQUESTS row 42), and the old frame was 12° of whatever was around her — which mid-ocean
  // is 12° of nothing. Measured on the seeded world: this point's frame held ZERO harbours before
  // the fix, and the tab therefore opened on a featureless field with a few names floating on it.
  test('a fleet anchored in the middle of the Atlantic still opens on a coast', () => {
    const frame = opensOn({ lat: 35, lon: -40 })
    const found = harboursIn(frame)
    expect(
      found.length,
      `the opening frame for a mid-Atlantic anchor holds no harbour, so it holds no coast: ` +
        `${frame.minLat.toFixed(1)}…${frame.maxLat.toFixed(1)}°N by ` +
        `${frame.minLon.toFixed(1)}…${frame.maxLon.toFixed(1)}°E`,
    ).toBeGreaterThan(0)
  })

  // The far case, stated rather than left undefined: mid-Pacific, the nearest land is genuinely an
  // ocean away, and the frame is as wide as it has to be. That is the honest picture of where she
  // is; `clampView` caps the worst case at the globe, which is still a map.
  test('mid-Pacific, the frame widens as far as it must — and says where she is by showing it', () => {
    const frame = opensOn({ lat: 0, lon: -140 })
    expect(harboursIn(frame).length).toBeGreaterThan(0)
  })

  // A frame that already held a coast must not move: the rule only ever WIDENS, exactly like the
  // 12° floor it sits behind. Lisbon is the §K.1 opening house, so this is the frame every new
  // player sees, and it must be the same frame after the fix as before it.
  test('a fleet lying in a harbour is not re-framed — the rule only widens', () => {
    const lisbon = { lat: 38.72, lon: -9.13 }
    const bounds = openingBounds([lisbon], [lisbon], WORLD, PHONE_ASPECT)
    // 12° across is `OPENING_MIN_SPAN_DEG`'s own floor, untouched by the coast rule.
    expect(bounds.maxLon - bounds.minLon).toBeCloseTo(12, 6)
    expect(harboursIn(opensOn(lisbon)).length).toBeGreaterThan(1)
  })
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BROWSER HALF — the real chain, the real chart, at 390×844.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.describe('the whole send, driven on a phone', () => {
  test.use({ viewport: PHONE })
  // The local engine applies the WHOLE migration chain to a real PostgreSQL in the tab on first
  // boot. That is the point — nothing here is a fixture — and it is why this one drive is given a
  // long clock rather than being split into tests that would each pay for it again.
  test.setTimeout(600_000)

  test('a harbour is tappable by its name, and a ratio can be set without sailing', async ({
    page,
    request,
    baseURL,
  }) => {
    const reachable = await request
      .get(baseURL ?? '')
      .then((r) => r.ok())
      .catch(() => false)
    test.skip(
      !reachable,
      `nothing served at ${baseURL} — run \`npm run build && npm run preview\` (or set ` +
        `PLAYWRIGHT_BASE_URL) and re-run`,
    )

    await page.goto('map')
    await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
    const chart = page.locator('svg[aria-label^="Chart of the world"]')
    await expect(chart.getByTestId('map-coastline')).toHaveCount(1)

    // ── DEFECT 3, at the glass ────────────────────────────────────────────────────────────────
    // Not "the coastline element exists" — that is true of an opening frame in mid-ocean, which is
    // the defect. LAND IS ON SCREEN: a grid of points over the viewBox actually on the glass, each
    // asked of the rendered path itself through `isPointInFill`, which is the browser's own answer
    // to "is this spot land". Nothing in this measurement comes from the app's own arithmetic.
    const grid = await chart.evaluate((svg) => {
      const path = svg.querySelector('[data-testid="map-coastline"]') as SVGGeometryElement | null
      const box = (svg as SVGSVGElement).viewBox.baseVal
      if (!path || box.width <= 0) return { samples: 0, land: 0 }
      const step = 24
      let samples = 0
      let land = 0
      for (let i = 0; i < step; i += 1) {
        for (let j = 0; j < step; j += 1) {
          const x = box.x + ((i + 0.5) / step) * box.width
          const y = box.y + ((j + 0.5) / step) * box.height
          samples += 1
          if (path.isPointInFill(new DOMPoint(x, y))) land += 1
        }
      }
      return { samples, land }
    })
    expect(grid.samples, 'the coastline path was never sampled — the measurement is vacuous').toBe(576)
    // MEASURED on the §K.1 house at 390×844: 154 of 576 sample points (26.7%) fall on land, which
    // is Iberia and north-west Africa in the opening frame. The floor is set at a twentieth of the
    // sheet — far enough below the measurement to survive a coastline retune, far enough above zero
    // that "a few floating names on a dark field" cannot pass it.
    expect(
      grid.land / grid.samples,
      `the opening frame is ${((grid.land / grid.samples) * 100).toFixed(1)}% land — a chart that ` +
        `shows the player no coast teaches them nothing about a game whose one spatial law is ` +
        `"she never touches land"`,
    ).toBeGreaterThan(0.05)
    await page.screenshot({ path: 'map-open-390.png' })

    // ── DEFECT 1: the name IS the harbour ─────────────────────────────────────────────────────
    // The player reads a name and puts a thumb on it. Measured in a browser drive at 1389×900
    // before the fix: the centre of the word "Cadiz" is 24.8 px from its mark, the reach was 22 px,
    // and a tap there returned `OPEN SEA 36.4°N 6.4°W` — a plausible panel for a wasted voyage.
    const name = await chart.evaluate((svg) => {
      const text = svg.querySelector('text[data-label-id="port:CAD"]')
      if (!text) return null
      const r = text.getBoundingClientRect()
      return { cx: r.x + r.width / 2, cy: r.y + r.height / 2, width: r.width }
    })
    expect(name, 'Cadiz was not named on the opening frame — nothing was aimed at').not.toBeNull()
    await page.mouse.click(name!.cx, name!.cy)

    const detail = page.getByTestId('map-detail-panel')
    await expect(detail).toBeVisible()
    await expect(
      detail,
      'a tap on the word "Cadiz" did not select Cadiz — the harbour a player sees is the mark AND ' +
        'its name, and missing it silently offers a different destination',
    ).toContainText('Cadiz')

    // ── DEFECT 2: the fold can now WRITE a ratio, and writing it is not sailing ────────────────
    await page.getByTestId('map-send-fleet').click()
    const row = page.getByTestId('map-send-row-head').first()
    await expect(row).toBeVisible()
    const her = (await row.innerText()).split('\n')[0]
    await row.click()

    const keep = page.getByTestId('map-send-keep')
    await expect(keep).toBeVisible()
    const ratio = page.getByTestId('map-send-ratio')
    await expect(
      ratio,
      'the fold offers no way to SET a ratio, so a house with no standing order must leave the ' +
        'map to write one — the screen-hop OWNER_REQUESTS row 45 exists to delete',
    ).toBeVisible()

    const figures = page.getByTestId('map-send-ratio-figures')
    const before = await figures.innerText()
    await page.getByTestId('map-send-ratio-more').click()
    await page.getByTestId('map-send-ratio-more').click()
    await expect(figures).not.toHaveText(before)
    const deeper = await figures.innerText()
    await page.getByTestId('map-send-ratio-less').click()
    await expect(figures).not.toHaveText(deeper)

    // ARMED, NOT FIRED. Three independent readings of "she has not sailed", because this is the
    // dangerous half: a ratio control one stray tap from dispatching a real voyage would be worse
    // than no control.
    await expect(page.getByTestId('map-send-busy')).toHaveCount(0)
    await expect(page.getByTestId('map-send-sent')).toHaveCount(0)
    // A fleet that HAS been sent loses her row head (`pressable` flips) and gains a note in its
    // place, so the head still standing with her own name on it is the world saying she is where
    // she was.
    await expect(page.getByTestId('map-send-row-head').first()).toContainText(her)

    // NOTHING WAS COLLAPSED, REPLACED OR DESTROYED — the owner's standing rule. Every step of the
    // fold that was open before the ratio moved is open after it.
    await expect(page.getByTestId('map-send-fleet')).toHaveAttribute('aria-expanded', 'true')
    await expect(page.getByTestId('map-send-fleets')).toBeVisible()
    await expect(keep).toBeVisible()
    await expect(page.getByTestId('map-send-keep-none')).toBeVisible()
    // And the one control that WILL sail her is present, named, and separate.
    await expect(page.getByTestId('map-send-ratio-send')).toBeEnabled()

    await page.screenshot({ path: 'map-fold-ratio-390.png' })
  })
})

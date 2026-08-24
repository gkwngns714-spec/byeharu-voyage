import { test, expect } from '@playwright/test'
import { portMarkScale, portStrokeWidth } from '../src/chart'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CHART'S INK — how far land is from water, and how loud a great port is beside a small one.
//
// Two defects, both found by LOOKING at the running game at 390×844 and both then measured:
//
//   1. LAND AND SEA WERE ONE OBJECT. `--color-chart-land` #1b2635 on `--color-chart-sea` #0a1220 is
//      a contrast ratio of 1.23 : 1, and the layer drawing it said so in its own header ("a ~5%
//      value step") and shipped anyway. On screen it was worse: the chart painted no sea at all, so
//      the land sat on the `.bv-sea` gradient, whose top stop `--color-sky` (#142438) put Iberia
//      against the Atlantic at 1.03 : 1. At arm's length there was no coast.
//
//   2. EVERY PORT WAS THE SAME TRIANGLE. `size_tier` already decided which ports are drawn at each
//      zoom (PORT_TIER_BANDS) and already scaled the mark — but only by 0.12 per tier, which put a
//      tier-3 mark 6.77 px wide beside a tier-5 at 8.50 px, in identical colour and line weight.
//      26% apart is 214 harbours told with equal emphasis.
//
// TWO KINDS OF ASSERTION, deliberately. The mark hierarchy is arithmetic, so it is proved as
// arithmetic, in a plain Node process. The colours are the browser's — `color-mix`, the theme
// cascade and Tailwind's utility generation all get a vote — so they are proved by MEASURING THE
// RUNNING CHART, never by re-implementing color-mix here. A second implementation of a colour would
// be exactly the kind of copy `docs/NO_SPAGHETTI.md` exists to stop, and it would go green while
// the shipped page was wrong.
//
// HOW TO RUN THE BROWSER HALF: `npm run build && npm run preview`, then this file. With nothing
// served it SKIPS with the reason stated, in the discipline tests/layout.spec.ts sets out.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// ── 1. THE HIERARCHY, AS ARITHMETIC ────────────────────────────────────────────────────────────

/** The tiers migration 0003 actually seeds: 100 ports at 2, 79 at 3, 35 at 5. */
const SEEDED_TIERS = [2, 3, 5] as const

test.describe('a great harbour does not look like a roadstead', () => {
  test('both channels rise with the tier, and neither ever falls', () => {
    for (let tier = 2; tier <= 5; tier++) {
      expect(portMarkScale(tier), `size, tier ${tier}`).toBeGreaterThan(portMarkScale(tier - 1))
      expect(portStrokeWidth(tier), `weight, tier ${tier}`).toBeGreaterThan(portStrokeWidth(tier - 1))
    }
  })

  test('the step across the tiers the world uses is one you can SEE', () => {
    const [small, , great] = SEEDED_TIERS
    // The measured `before` was 1.26× on size and 1.00× on weight (one stroke width for all five
    // tiers). The floor is stated as a number so a future retune cannot quietly walk it back.
    expect(portMarkScale(great) / portMarkScale(small)).toBeGreaterThanOrEqual(1.6)
    expect(portStrokeWidth(great) / portStrokeWidth(small)).toBeGreaterThanOrEqual(1.6)
  })

  test('the smallest mark is still a mark — hierarchy is never bought by hiding a port', () => {
    // 3.6 px is GLYPH.quietPortHalfWidth, so this is the drawn width of the smallest harbour.
    expect(2 * 3.6 * portMarkScale(1)).toBeGreaterThanOrEqual(4)
    expect(portStrokeWidth(1)).toBeGreaterThanOrEqual(0.6)
  })

  test('bad data clamps rather than un-draws a port', () => {
    for (const bad of [0, -3, 9, Number.NaN, Number.POSITIVE_INFINITY]) {
      expect(portMarkScale(bad), `scale(${bad})`).toBeGreaterThanOrEqual(portMarkScale(1))
      expect(portMarkScale(bad), `scale(${bad})`).toBeLessThanOrEqual(portMarkScale(5))
      expect(portStrokeWidth(bad), `weight(${bad})`).toBeGreaterThanOrEqual(portStrokeWidth(1))
      expect(portStrokeWidth(bad), `weight(${bad})`).toBeLessThanOrEqual(portStrokeWidth(5))
    }
  })
})

// ── 2. THE COLOURS, AS MEASURED ────────────────────────────────────────────────────────────────

/**
 * WCAG 2.x relative luminance of an `rgb(r, g, b)` string, and the contrast ratio between two. The
 * formula is the standard's, and it lives here rather than in src/ because nothing the GAME does
 * depends on it: this is a measuring instrument, not a rule of the game.
 *
 * IT ONLY EVER SEES `rgb(r, g, b)`, and that is load-bearing. Chrome serialises a `color-mix()`
 * token as `color(srgb 0.35 0.39 0.44)` — 0-to-1 channels — and the first version of this file
 * pattern-matched the numbers out of whatever string it was handed, read those as 0-to-255, and
 * reported a 3.12 : 1 stroke as 1.12 : 1. The page now normalises every colour through a canvas
 * before it crosses the wire (see `readInk`), so there is one syntax to parse and it is the one
 * syntax a canvas can produce.
 */
function luminance(css: string): number {
  const parts = /^rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(css)
  if (!parts) throw new Error(`not an rgb() colour: ${css}`)
  const channel = (n: number) => {
    const c = n / 255
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  }
  return (
    0.2126 * channel(Number(parts[1])) +
    0.7152 * channel(Number(parts[2])) +
    0.0722 * channel(Number(parts[3]))
  )
}

function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x)
  return (hi + 0.05) / (lo + 0.05)
}

test.describe('the contrast maths itself', () => {
  test('black on white is 21 : 1, and a colour against itself is 1 : 1', () => {
    expect(contrast('rgb(0, 0, 0)', 'rgb(255, 255, 255)')).toBeCloseTo(21, 1)
    expect(contrast('rgb(27, 38, 53)', 'rgb(27, 38, 53)')).toBeCloseTo(1, 5)
  })

  test('it reproduces the defect it was written to measure', () => {
    // The two colours this chart shipped with, and the two numbers that made them a defect.
    expect(contrast('rgb(27, 38, 53)', 'rgb(10, 18, 32)')).toBeCloseTo(1.23, 2) // land : chart sea
    expect(contrast('rgb(27, 38, 53)', 'rgb(20, 36, 56)')).toBeCloseTo(1.03, 2) // land : .bv-sea sky
  })
})

test.describe('land reads as land at 390px', () => {
  test.use({ viewport: { width: 390, height: 844 } })

  test('the coast is drawn on the chart’s OWN sea, and stands clear of it', async ({
    page,
    request,
    baseURL,
  }) => {
    // The same measured budget layout.spec's ready() carries: a cold boot builds the whole chain
    // in the tab — ~100 s at 39 migrations plus 0041's 52k-row affinity recompute, more under
    // parallel load — and the old 180 s purse wait failed a CORRECT build. The standing cure is
    // the pre-built database image (DEV_LOG D21).
    test.setTimeout(420_000)
    let served: boolean
    try {
      served = (await request.get(baseURL ?? '')).ok()
    } catch {
      served = false
    }
    test.skip(
      !served,
      `nothing served at ${baseURL} — run \`npm run build && npm run preview\` (or set ` +
        `PLAYWRIGHT_BASE_URL) and re-run. A colour proof that measures no pixels is not a proof.`,
    )

    await page.goto('map')
    // READY is the world open, not the bundle downloaded: the migration chain applies in this tab
    // and the purse holds a dash until `world.snapshot()` answers.
    await page.waitForFunction(
      () => !/—/.test(document.querySelector('[data-testid="purse"]')?.textContent ?? '—'),
      undefined,
      { timeout: 300_000 },
    )
    if (/\/auth$/.test(new URL(page.url()).pathname)) {
      test.skip(true, 'this build is in CLOUD mode and redirected to /auth — build without .env.local')
    }
    await page.waitForFunction(
      () => (document.querySelector('[data-testid="map-coastline"]')?.getAttribute('d') ?? '').length > 1000,
      undefined,
      { timeout: 60_000 },
    )

    // EVERY COLOUR IS COMPOSITED IN THE PAGE, over the thing it is actually drawn on, and read back
    // as sRGB bytes off a canvas. That does two jobs at once: it settles the serialisation (see
    // `luminance`), and it makes the figure the one the EYE gets — the quiet port mark carries an
    // 85% alpha, so its ink over land is a different colour from its ink, and only the composite
    // means anything.
    const ink = await page.evaluate(() => {
      const coast = document.querySelector('[data-testid="map-coastline"]')
      const sea = document.querySelector('[data-testid="map-sea"]')
      if (!coast || !sea) return null

      const canvas = document.createElement('canvas')
      canvas.width = 1
      canvas.height = 1
      const ctx = canvas.getContext('2d', { willReadFrequently: true })!
      const over = (fg: string, bg: string) => {
        ctx.clearRect(0, 0, 1, 1)
        ctx.fillStyle = bg
        ctx.fillRect(0, 0, 1, 1)
        ctx.fillStyle = fg
        ctx.fillRect(0, 0, 1, 1)
        const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data
        return `rgb(${r}, ${g}, ${b})`
      }

      const seaCss = getComputedStyle(sea).fill
      const solidSea = over(seaCss, 'rgb(0, 0, 0)')
      const land = over(getComputedStyle(coast).fill, solidSea)
      // A QUIET mark: hollow, so its ink is the stroke. The loud one is a brass FILL and means
      // something else entirely (a fleet of yours is there), so it is not the ground's rival.
      const quiet = [...document.querySelectorAll('[data-testid="map-ports"] path')].find(
        (p) => !/^rgb\(/.test(getComputedStyle(p).fill),
      )
      return {
        sea: solidSea,
        land,
        stroke: over(getComputedStyle(coast).stroke, solidSea),
        markOnLand: quiet ? over(getComputedStyle(quiet).stroke, land) : null,
      }
    })
    expect(ink, 'the chart drew no sea rect — ChartCanvas paints its own ground').not.toBeNull()

    const landOnSea = contrast(ink!.land, ink!.sea)
    const coastOnSea = contrast(ink!.stroke, ink!.sea)

    // THE BOUNDARY meets WCAG 1.4.11 (3:1 for a graphic that carries meaning). This is what makes
    // §E.5's "a single pale stroke" a fact rather than an intention.
    expect(coastOnSea, `coast stroke on sea is only ${coastOnSea.toFixed(2)} : 1`).toBeGreaterThanOrEqual(3)
    // THE BODY is a real step and no longer a rumour — 1.23 : 1 was the defect.
    expect(landOnSea, `land on sea is only ${landOnSea.toFixed(2)} : 1`).toBeGreaterThanOrEqual(1.9)
    // …and it stays GROUND. If the land ever out-shouts the marks the chart has swapped subject for
    // background, which is the failure in the other direction and just as bad.
    expect(landOnSea, `land on sea is ${landOnSea.toFixed(2)} : 1 — that is terrain, not a chart`)
      .toBeLessThan(2.6)
    if (ink!.markOnLand) {
      expect(
        contrast(ink!.markOnLand, ink!.land),
        'a port mark no longer dominates the ground it sits on',
      ).toBeGreaterThan(landOnSea)
    }
  })
})

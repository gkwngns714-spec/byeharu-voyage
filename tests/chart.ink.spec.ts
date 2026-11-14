import { test, expect } from '@playwright/test'
import { GLYPH, portMarkScale, portStrokeWidth } from '../src/chart'
import { ready, reachable } from './appReady.fixture'
import { clockDayMs } from '../src/lib/format/time'

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
//   3. THE NIGHT HALF WAS NEAR-BLACK, AND EVERY LAW HERE WAS GREEN (owner, 2026-11-14: "find the root cause, make it so
//      that this problem does not occur again"; docs/dev-log/2026-11-14-night-look.md). The night sea was #070c14, a step
//      of the page's background: 1.07 : 1 off pure black. This file measured only RATIOS against that ground (the coast
//      3 : 1 on it, the land inside [1.9, 2.6) of it), so a ground nobody could see passed every one of them, and the
//      land's ceiling on a black sea is a dull dark grey. Section 3 below measures what was missing: the ground's own
//      light and colour, the land's colour, the coast against BOTH its sides, the step
//      from night to day, and the painted glass itself with the Sun held on the far side of the world.
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

// ── 1b. THE FOURTH MARK — the roadstead (0076), which must read as none of the other three ─────

test.describe('the roadstead is not any other round thing on this chart', () => {
  test('it is the smallest of them, and nowhere near the destination ring', () => {
    // Three round marks were already on this sheet before 0076:
    //   destination ring  r 11, dashed 3 3, brass   ·   fleet dot  r 4.4, FILLED brass, haloed
    // The roads have to be readable as neither, and RADIUS is the channel they use — fill and ink
    // are spoken for (a filled mark means "a fleet of yours", brass means "yours").
    // Pin moved deliberately 2026-09-13 (owner row 90): the fleet's dot became a HULL, and its
    // size is `shipHalfLength` (6.5 px from centre to bow). The property is the same — the roads
    // are smaller than the fleet's own mark — measured against the mark that is drawn now.
    expect(GLYPH.roadsteadRadius).toBeLessThan(GLYPH.shipHalfLength)
    expect(GLYPH.destinationRingRadius / GLYPH.roadsteadRadius).toBeGreaterThanOrEqual(4)
    // …and smaller than the quiet harbour mark at the tier both ramps are centred on, so a coast
    // full of roadsteads still reads as a coast of ports: 5.2 px across against 7.2.
    expect(2 * GLYPH.roadsteadRadius).toBeLessThan(2 * GLYPH.quietPortHalfWidth)
  })

  test('the zoom floor is the smallest LOUD mark this chart draws — the derivation, not the number', () => {
    // glyphs.ts states 6 px as `2 × loudPortHalfWidth × portMarkScale(1)`. Asserting the DERIVATION
    // rather than the literal is what makes it go red if either ramp is retuned — at which point
    // somebody decides what the floor is, instead of it quietly ceasing to be the width of a mark.
    expect(GLYPH.roadsteadMinPx).toBeCloseTo(2 * GLYPH.loudPortHalfWidth * portMarkScale(1), 9)
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
    // THE ONE "IS THE APP UP" APPARATUS — tests/appReady.fixture.ts. This file used to carry its
    // own copy: its own served-probe and its own boot wait keyed on the PURSE. That copy could not
    // do the one thing it had an /auth guard for. On a cloud build every route redirects to /auth,
    // where there is no purse at all, so the wait burned its full 300 s and FAILED — with the skip
    // that was meant to catch it sitting on the line after, never reached. The fixture's wait keys
    // on the loading skeleton instead, which settles on /auth like anywhere else, so it reaches its
    // own guard and skips with a reason. Measured 2026-09-07: 3 timeouts, 0 explained.
    test.skip(
      !(await reachable(request, baseURL ?? '')),
      `nothing served at ${baseURL} — run \`npm run build && npm run preview\` (or set ` +
        `PLAYWRIGHT_BASE_URL) and re-run. A colour proof that measures no pixels is not a proof.`,
    )

    await page.goto('map')
    await ready(page)
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
      // THE NIGHT PEN IS WHAT THIS PROOF PINS (2026-10-14, src/chart/sun.ts). Every mark mixes its
      // ink toward the day's by its own `--night`, and at Lisbon the real clock may well say day
      // when this runs — so the marks are read with the night forced on them, through a sheet that
      // outranks the group's inline value, and the DAY pen is measured separately below from its
      // own tokens. Removed again before the function returns.
      const night = document.createElement('style')
      night.textContent = '[data-port-code] { --night: 1 !important; }'
      document.head.appendChild(night)
      const coast = document.querySelector('[data-testid="map-coastline"]')
      // Pin moved deliberately 2026-09-13 (owner row 90): the coast STROKE is its own element
      // now — `map-coast`, the outline with the inland borders dropped — because a country file's
      // shared edges cannot be stroked on the same element as the body without drawing borders.
      // The body's fill is still `map-coastline`; the stroke's token is measured where it is drawn.
      const line = document.querySelector('[data-testid="map-coast"]')
      const sea = document.querySelector('[data-testid="map-sea"]')
      if (!coast || !line || !sea) return null

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
      const markOnLand = quiet ? over(getComputedStyle(quiet).stroke, land) : null
      night.remove()
      // THE DAY PEN, from its own tokens (docs/MAP_ATMOSPHERE.md §11.3): the day's dark mark on the
      // day's land — the temperate green most harbours stand on — and the day coast on the day sea.
      const rootCss = getComputedStyle(document.documentElement)
      const token = (name: string) => rootCss.getPropertyValue(name).trim()
      const dayLand = over(token('--color-chart-day-temperate'), 'rgb(0, 0, 0)')
      const daySea = over(token('--color-chart-day-sea'), 'rgb(0, 0, 0)')
      return {
        sea: solidSea,
        land,
        stroke: over(getComputedStyle(line).stroke, solidSea),
        markOnLand,
        dayLand,
        daySea,
        dayMarkOnLand: over(token('--color-chart-day-mark'), dayLand),
        dayCoastOnSea: over(token('--color-chart-day-coast'), daySea),
      }
    })
    expect(ink, 'the chart drew no sea rect — ChartCanvas paints its own ground').not.toBeNull()
    // THE DAY SIDE holds the same floors: the coast line on the sea at 3 : 1, the land a real step
    // off the sea, and the mark above the land it stands on.
    expect(contrast(ink!.dayCoastOnSea, ink!.daySea), 'day coast on the day sea').toBeGreaterThanOrEqual(3)
    expect(contrast(ink!.dayLand, ink!.daySea), 'day land on the day sea').toBeGreaterThanOrEqual(1.5)
    expect(contrast(ink!.dayMarkOnLand, ink!.dayLand), 'the day mark on the day land').toBeGreaterThan(3)

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

    // ── 3. THE NIGHT IS A NIGHT VERSION OF THE SAME WORLD (2026-11-14; the header's defect 3) ────────────────────────
    // What the ratios above never said. Each floor is a number, beside the value measured the day it was written and
    // the value of the near-black night it replaces, so a retune cannot quietly walk back to black.
    const BLACK = 'rgb(0, 0, 0)'
    const rgb = (css: string) => (css.match(/\d+/g) ?? []).slice(0, 3).map(Number)
    // THE GROUND IS SEEN: the night sea is lighter than black by a step the eye gets. Measured 1.22 (was 1.07).
    const seaOnBlack = contrast(ink!.sea, BLACK)
    expect(seaOnBlack, `the night sea is ${seaOnBlack.toFixed(2)} : 1 off black: that is black, not water`).toBeGreaterThanOrEqual(1.15)
    // …AND IT IS WATER: blue before green before red, by a margin (11, 27, 51 today; 7, 12, 20 was a tinted black).
    const [seaR, seaG, seaB] = rgb(ink!.sea)
    expect(seaB - seaR, `the night sea ${ink!.sea} is not blue`).toBeGreaterThanOrEqual(30)
    expect(seaB, `the night sea ${ink!.sea} is not blue`).toBeGreaterThan(seaG)
    expect(seaG, `the night sea ${ink!.sea} is not blue`).toBeGreaterThan(seaR)
    // THE LAND KEEPS THE LAND'S COLOUR: green leads red and blue (55, 82, 63 today; the grey before it led by 2).
    const [landR, landG, landB] = rgb(ink!.land)
    expect(landG - Math.max(landR, landB), `the night land ${ink!.land} is grey`).toBeGreaterThanOrEqual(12)
    // THE COAST IS AN EDGE FROM BOTH SIDES. On the sea it was held to 3 above; on the land it was never measured, and it
    // read 1.86 there: a line seen from the water only. Measured 6.35 on the sea, 3.17 on the land.
    const coastOnLand = contrast(ink!.stroke, ink!.land)
    expect(coastOnSea, `coast on sea is only ${coastOnSea.toFixed(2)} : 1`).toBeGreaterThanOrEqual(4.5)
    expect(coastOnLand, `coast on land is only ${coastOnLand.toFixed(2)} : 1`).toBeGreaterThanOrEqual(2.5)
    // AND IT IS STILL NIGHT: the day's water and land stand well above the night's. Measured 3.84 and 3.19. This is the
    // ceiling on the floors above: a night lifted until it is a second day fails here.
    const daySeaOverNight = contrast(ink!.daySea, ink!.sea)
    const dayLandOverNight = contrast(ink!.dayLand, ink!.land)
    expect(daySeaOverNight, 'the day sea over the night sea').toBeGreaterThanOrEqual(3)
    expect(dayLandOverNight, 'the day land over the night land').toBeGreaterThanOrEqual(2.5)

    // ── THE PAINTED GLASS, WITH THE SUN HELD (the pixels, not the tokens) ────────────────────────────────────────────
    // Everything above reads a token off the element that wears it. This reads the picture: the Sun is put on the far
    // side of the world from the middle of the glass (the game clock runs a day per `clockDayMs()` from the served anchor, and local mode's
    // serverNow() is Date.now(), so Playwright's clock holds it), the glass is photographed, and its DARK pixels are
    // measured. A sea, a sheet or an overlay that paints the night black again fails here whatever its
    // token says. Then the Sun is put overhead and the same glass must be clearly lighter.
    const glass = page.getByTestId('map-chart')
    const centreLon = await page.getByTestId('map-view').evaluate((svg) => {
      const [x, , w] = (svg.getAttribute('viewBox') ?? '').split(/[\s,]+/).map(Number)
      return x + w / 2
    })
    const gameDayMs = clockDayMs()
    const holdSunOver = async (lon: number) => {
      // The Sun stands over longitude 0 at the game's noon and goes west 360 degrees a game day. Where the clock stands
      // now is read off the top bar (its hour is the Sun's, lib/format gameTimeOfDayMs; since 0413 it counts from the
      // served anchor, not from the Unix epoch), and the glass's clock is put forward to the hour wanted.
      const want = (((0.5 - lon / 360) % 1) + 1) % 1
      const [h, m] = ((await page.getByTestId('game-clock').textContent()) ?? '').split(':').map(Number)
      expect(Number.isFinite(h) && Number.isFinite(m), 'the top bar shows the game clock').toBe(true)
      const have = (h * 60 + m + 0.5) / 1440
      const now = await page.evaluate(() => Date.now())
      await page.clock.setFixedTime(now + ((((want - have) % 1) + 1) % 1) * gameDayMs)
      await page.waitForTimeout(1500) // the glide re-places the mask on its next frames (DaylightSheet.tsx)
    }
    /** WCAG luminance of the glass's pixels: the 10th percentile (its dark end) and the median. */
    const glassLight = async () => {
      const shot = (await glass.screenshot()).toString('base64')
      return page.evaluate(async (b64) => {
        const img = new Image()
        img.src = `data:image/png;base64,${b64}`
        await img.decode()
        const c = document.createElement('canvas')
        c.width = img.naturalWidth
        c.height = img.naturalHeight
        const g = c.getContext('2d', { willReadFrequently: true })!
        g.drawImage(img, 0, 0)
        const px = g.getImageData(0, 0, c.width, c.height).data
        const channel = (n: number) => {
          const v = n / 255
          return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4
        }
        const lum: number[] = []
        for (let i = 0; i < px.length; i += 4 * 7) {
          lum.push(0.2126 * channel(px[i]) + 0.7152 * channel(px[i + 1]) + 0.0722 * channel(px[i + 2]))
        }
        lum.sort((a, b) => a - b)
        return { dark: lum[Math.floor(lum.length * 0.1)], median: lum[Math.floor(lum.length * 0.5)] }
      }, shot)
    }
    await holdSunOver(centreLon + 180)
    const nightGlass = await glassLight()
    await holdSunOver(centreLon)
    const dayGlass = await glassLight()
    const darkOnBlack = (nightGlass.dark + 0.05) / 0.05
    const dayOverNight = (dayGlass.median + 0.05) / (nightGlass.median + 0.05)
    console.log(
      `night glass: dark end ${darkOnBlack.toFixed(3)} : 1 off black; day over night ${dayOverNight.toFixed(2)} : 1; ` +
        `sea ${ink!.sea} ${seaOnBlack.toFixed(2)}, land ${ink!.land} ${landOnSea.toFixed(2)}, ` +
        `coast ${ink!.stroke} ${coastOnSea.toFixed(2)} / ${coastOnLand.toFixed(2)}, ` +
        `mark on land ${ink!.markOnLand ? contrast(ink!.markOnLand, ink!.land).toFixed(2) : '-'}, ` +
        `day sea ${daySeaOverNight.toFixed(2)}, day land ${dayLandOverNight.toFixed(2)}`,
    )
    expect(darkOnBlack, `the dark end of the night glass is ${darkOnBlack.toFixed(2)} : 1 off black`).toBeGreaterThanOrEqual(1.12)
    expect(dayOverNight, `the day glass is only ${dayOverNight.toFixed(2)} : 1 over the night glass`).toBeGreaterThanOrEqual(2)
  })
})

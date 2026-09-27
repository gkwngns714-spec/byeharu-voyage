import { test, expect, type Page } from '@playwright/test'
import type { ViewBox } from '../src/lib/geo'
import { coastPaperBox, nextCoastPaper, PAPER_MARGIN, paperOf, settleCoastPaper } from '../src/chart'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A PAN MOVES THE COAST; IT DOES NOT REPAINT IT — owner, 2026-09-27: "check the map lag".
//
// Measured before the fix (docs/MAP_ATMOSPHERE.md §10): every pointermove of a pan changed the one
// `<svg>`'s viewBox, and Chrome re-rasterised the whole coast under it — three wide shallows, the
// body, the relief and the line — at 18–36 ms of GPU a frame; the owner saw 22 fps. The fix draws
// the coast on its own composited sheet over a rectangle wider than the view (`paperOf`), so a pan
// only translates that sheet.
//
// These proofs hold the MECHANISM, not a stopwatch — a wall-clock threshold on a shared CI runner
// is a flake. Pure: the sheet always covers the view, is the identical rectangle across a pan inside
// its half-glass cell, and a zoom draws over the view alone until it settles. Browser: during a real
// drag the coast's path data and the sheet's viewBox do not change while the view's does, the sheet
// covers the glass at every step, and it is a compositor layer.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const VIEW: ViewBox = { x: -20, y: -50, width: 30, height: 15 }

const covers = (outer: ViewBox, inner: ViewBox, eps = 1e-9) =>
  outer.x <= inner.x + eps &&
  outer.y <= inner.y + eps &&
  outer.x + outer.width >= inner.x + inner.width - eps &&
  outer.y + outer.height >= inner.y + inner.height - eps

test.describe('the coast sheet, as arithmetic', () => {
  test('every view is inside its sheet, the sheet is the view grown by the margin on each side', () => {
    for (const width of [1.5, 7, 30, 120, 360]) {
      for (const aspect of [390 / 752, 1545 / 752, 1]) {
        const height = width / aspect
        for (let i = 0; i < 200; i++) {
          const box = { x: -180 + ((i * 37.3) % 360), y: -90 + ((i * 11.7) % 180), width, height }
          const paper = paperOf(box)
          expect(covers(paper, box), `${JSON.stringify(box)} not inside ${JSON.stringify(paper)}`).toBe(true)
          expect(paper.width).toBeCloseTo(width * (1 + 2 * PAPER_MARGIN), 9)
          expect(paper.height).toBeCloseTo(height * (1 + 2 * PAPER_MARGIN), 9)
        }
      }
    }
  })

  test('a pan keeps the IDENTICAL sheet until it has travelled half a glass', () => {
    // One glass of travel in 100 steps: the sheet changes at most once per half glass.
    const seen = new Set<string>()
    for (let i = 0; i <= 100; i++) {
      const box = { ...VIEW, x: VIEW.x + (i / 100) * VIEW.width }
      seen.add(JSON.stringify(paperOf(box)))
    }
    expect(seen.size).toBeLessThanOrEqual(3)
    expect(seen.size).toBeGreaterThanOrEqual(2)
  })

  test('a zoom draws over the view alone; a pan or the settle brings the wide sheet back', () => {
    const opening = nextCoastPaper(null, VIEW)
    expect(opening.narrow).toBeNull()
    expect(coastPaperBox(opening, VIEW)).toEqual(paperOf(VIEW))
    // Nothing changed: the same object, so the caller sets no state.
    expect(nextCoastPaper(opening, { ...VIEW })).toBe(opening)

    const zoomed: ViewBox = { x: -15, y: -47.5, width: 20, height: 10 }
    const afterZoom = nextCoastPaper(opening, zoomed)
    expect(afterZoom.narrow).toEqual(zoomed)
    expect(coastPaperBox(afterZoom, zoomed)).toEqual(zoomed)
    // A re-render of the same view (a new object with the same numbers) keeps it narrow.
    expect(nextCoastPaper(afterZoom, { ...zoomed })).toBe(afterZoom)
    // The first pan grows it at once.
    const panned = { ...zoomed, x: zoomed.x + 0.1 }
    const afterPan = nextCoastPaper(afterZoom, panned)
    expect(afterPan.narrow).toBeNull()
    expect(coastPaperBox(afterPan, panned)).toEqual(paperOf(panned))
    // Or the settle does, with the view where it is.
    expect(settleCoastPaper(afterZoom)).toEqual({ width: zoomed.width, narrow: null })
    expect(settleCoastPaper(afterPan)).toBe(afterPan)
  })
})

// ── THE RUNNING CHART ──────────────────────────────────────────────────────────────────────────

async function openMap(page: Page) {
  await page.goto('map')
  await ready(page)
  await page.waitForFunction(
    () => (document.querySelector('[data-testid="map-coastline"]')?.getAttribute('d') ?? '').length > 1000,
    undefined,
    { timeout: 60_000 },
  )
  await page.waitForTimeout(300)
}

/** The view's viewBox (the first sheet), the coast sheet's, and whether the coast sheet covers the
 *  glass — in CSS pixels, to half a pixel (the sheet is placed on the device-pixel grid). */
async function sheets(page: Page) {
  return page.evaluate(() => {
    const chart = document.querySelector('[data-testid="map-chart"]')!
    const view = chart.querySelector('svg')!.getAttribute('viewBox')
    const sheet = chart.querySelector('[data-testid="map-coast-sheet"]') as HTMLElement
    const paper = sheet.querySelector('svg')!.getAttribute('viewBox')
    const g = chart.getBoundingClientRect()
    const s = sheet.getBoundingClientRect()
    const covered = s.left <= g.left + 0.5 && s.top <= g.top + 0.5 && s.right >= g.right - 0.5 && s.bottom >= g.bottom - 0.5
    return { view, paper, covered, willChange: getComputedStyle(sheet).willChange }
  })
}

for (const viewport of [
  { width: 1545, height: 784 },
  { width: 390, height: 844 },
]) {
  test.describe(`a pan moves the coast, it does not repaint it — ${viewport.width}×${viewport.height}`, () => {
    test.use({ viewport })

    test('the coast path data and its sheet hold still under a drag; the glass is covered at every step; a zoom settles wide', async ({
      page,
      request,
      baseURL,
    }) => {
      test.setTimeout(420_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run build && npm run preview\` and re-run.`,
      )
      await openMap(page)
      const before = await sheets(page)
      expect(before.willChange, 'the coast is its own compositor layer').toContain('transform')
      expect(before.covered).toBe(true)

      // Count every change to the coast's own content — the path data above all — during the drag.
      await page.evaluate(() => {
        const sheet = document.querySelector('[data-testid="map-coast-sheet"]')!
        const w = window as unknown as { __coastMut: { d: number; other: number }; __coastMo: MutationObserver }
        w.__coastMut = { d: 0, other: 0 }
        w.__coastMo = new MutationObserver((list) => {
          for (const m of list) {
            if (m.target === sheet) continue // the sheet's own translate — the one thing a pan changes
            if (m.attributeName === 'd') w.__coastMut.d += 1
            else w.__coastMut.other += 1
          }
        })
        w.__coastMo.observe(sheet, { subtree: true, attributes: true, childList: true })
      })

      // A drag of a fifth of the glass, in 20 steps: the sheet may be re-based at most once.
      const box = (await page.locator('[data-testid="map-chart"]').boundingBox())!
      const x0 = box.x + box.width * 0.5
      const y0 = box.y + box.height * 0.5
      const dx = -box.width * 0.2
      await page.mouse.move(x0, y0)
      await page.mouse.down()
      const views = new Set<string | null>()
      const papers = new Set<string | null>()
      for (let i = 1; i <= 20; i++) {
        await page.mouse.move(x0 + (dx * i) / 20, y0 + (dx * i) / 60)
        const now = await sheets(page)
        views.add(now.view)
        papers.add(now.paper)
        expect(now.covered, `step ${i}: the coast sheet left part of the glass bare`).toBe(true)
      }
      await page.mouse.up()
      const mut = await page.evaluate(() => {
        const w = window as unknown as { __coastMut: { d: number; other: number }; __coastMo: MutationObserver }
        w.__coastMo.disconnect()
        return w.__coastMut
      })

      expect(views.size, 'the view itself moved on (nearly) every step').toBeGreaterThanOrEqual(15)
      expect(papers.size, 'the coast sheet was re-based more than once in a fifth of a glass').toBeLessThanOrEqual(2)
      expect(mut.d, 'a pan rewrote the coast path data').toBe(0)
      // At most one re-base: the sheet svg's viewBox, and nothing else inside the sheet.
      expect(mut.other).toBeLessThanOrEqual(1)

      // A zoom draws the coast over the view alone, then settles to the wide sheet.
      await page.getByRole('button', { name: 'Zoom in' }).click()
      const zoomed = await sheets(page)
      expect(zoomed.paper, 'just after a zoom the coast is drawn over exactly the view').toBe(zoomed.view)
      expect(zoomed.covered).toBe(true)
      await page.waitForFunction(() => {
        const chart = document.querySelector('[data-testid="map-chart"]')!
        const view = chart.querySelector('svg')!.viewBox.baseVal
        const paper = chart.querySelector('[data-testid="map-coast-sheet"] svg') as SVGSVGElement
        return paper.viewBox.baseVal.width > view.width * 1.4
      })
      const settled = await sheets(page)
      expect(settled.covered).toBe(true)
      console.log(
        `${viewport.width}×${viewport.height}: drag of 0.2 glass → ${views.size} views, ${papers.size} coast sheet(s), ` +
          `${mut.d} path rewrites; zoom → narrow ${zoomed.paper}, settled ${settled.paper}`,
      )
    })
  })
}

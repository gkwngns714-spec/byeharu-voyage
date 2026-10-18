import { test, expect, type CDPSession, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A FAST PAN NEVER BLINKS — owner, 2026-10-18: "when i move map, it blinks too much..." and "move
// the map faster, it will show blink, way faster."
//
// THE CAUSE, MEASURED (docs/dev-log/2026-10-18-map-no-blink.md). In headed Chrome on the GPU, a pan
// of 3,000 px in 300 ms put frames on the glass with tiles Chrome had not rasterised: the land gone
// to sea in rectangles, the day side flashing to night, once the whole page dark. It was Chrome's
// tile-memory budget: the same drag with `--force-gpu-mem-available-mb=4096` showed no such frame,
// the default 4–17 per run. The chart was eight glass-sized compositor surfaces plus two mask
// surfaces: the day coast's mask sheet rode INSIDE the moving coast sheet, a graticule svg and both
// seas were re-drawn over the view on every frame of the drag.
//
// WHAT THIS HOLDS. A headless runner rasterises in software and never runs out of tile memory, so
// a frame grab there cannot see the blink (it showed none before the fix either). These proofs hold
// the MECHANISM the fix rests on, on a real fast pan — mouse and touch, 3,000 px in 300 ms, at
// 1440×900 and 390×844 — and each of them is false of the build before it:
//   1. THE SEAS DO NOT MOVE. Neither sea's svg is touched by a pan: they are pictures of the glass.
//   2. THE GRID RIDES THE PAPER. The graticule is on the night coast sheet, moved by its translate.
//   3. NO MASK RIDES A MOVING SHEET. Every daylight mask is a sheet of the glass itself.
//   4. NO SHEET IS UNMOUNTED by a pan, and the night coast sheet covers the glass on every frame.
//   5. THE SURFACE COUNT. At most 7 compositor layers as large as half the glass (it was 8).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

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

/** Start watching: every mutation to either sea's svg, every removal of a chart sheet, and whether
 *  the night coast sheet covered the glass on every animation frame. */
async function watch(page: Page) {
  await page.evaluate(() => {
    type W = { __noblink: { sea: number; removed: number; frames: number; bare: number; on: boolean }; __noblinkMo: MutationObserver[] }
    const w = window as unknown as W
    const chart = document.querySelector('[data-testid="map-chart"]')!
    w.__noblink = { sea: 0, removed: 0, frames: 0, bare: 0, on: true }
    const seas = [document.querySelector('[data-testid="map-sea"]'), document.querySelector('[data-testid="map-sea-day"]')]
      .map((el) => el?.closest('svg'))
      .filter((el): el is SVGSVGElement => !!el)
    const seaMo = new MutationObserver((list) => (w.__noblink.sea += list.length))
    for (const svg of seas) seaMo.observe(svg, { subtree: true, attributes: true, childList: true })
    const SHEETS = '[data-testid="map-coast-sheet"], [data-testid="map-coast-sheet-day"], [data-testid="map-daylight-mask"]'
    const treeMo = new MutationObserver((list) => {
      for (const m of list)
        for (const n of m.removedNodes) if (n instanceof Element && (n.matches(SHEETS) || n.querySelector(SHEETS))) w.__noblink.removed += 1
    })
    treeMo.observe(chart, { subtree: true, childList: true })
    w.__noblinkMo = [seaMo, treeMo]
    const frame = () => {
      if (!w.__noblink.on) return
      const sheet = chart.querySelector('[data-testid="map-coast-sheet"]')
      const glass = chart.getBoundingClientRect()
      const s = sheet?.getBoundingClientRect()
      w.__noblink.frames += 1
      if (!s || s.left > glass.left + 0.5 || s.top > glass.top + 0.5 || s.right < glass.right - 0.5 || s.bottom < glass.bottom - 0.5)
        w.__noblink.bare += 1
      requestAnimationFrame(frame)
    }
    requestAnimationFrame(frame)
  })
}

async function stopWatching(page: Page) {
  return page.evaluate(() => {
    type W = { __noblink: { sea: number; removed: number; frames: number; bare: number; on: boolean }; __noblinkMo: MutationObserver[] }
    const w = window as unknown as W
    w.__noblink.on = false
    for (const mo of w.__noblinkMo) mo.disconnect()
    return w.__noblink
  })
}

/** FAST PANS: `strokes` strokes of 3,000 px in 300 ms (one move per 16 ms), alternating left and
 *  right with a vertical wave, by mouse or by one finger. */
async function fastPans(page: Page, cdp: CDPSession, input: 'mouse' | 'touch', strokes = 4) {
  const box = (await page.locator('[data-testid="map-chart"]').boundingBox())!
  const y0 = box.y + box.height * 0.5
  const N = 19
  for (let r = 0; r < strokes; r++) {
    const dir = r % 2 === 0 ? -1 : 1
    const x0 = dir < 0 ? box.x + box.width * 0.9 : box.x + box.width * 0.1
    const at = (i: number) => ({ x: x0 + (dir * 3000 * i) / N, y: y0 + Math.sin(i / 3) * box.height * 0.1 })
    if (input === 'mouse') {
      await page.mouse.move(x0, y0)
      await page.mouse.down()
      for (let i = 1; i <= N; i++) {
        await page.mouse.move(at(i).x, at(i).y)
        await page.waitForTimeout(16)
      }
      await page.mouse.up()
    } else {
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: x0, y: y0, id: 1 }] })
      for (let i = 1; i <= N; i++) {
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ ...at(i), id: 1 }] })
        await page.waitForTimeout(16)
      }
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
    }
    await page.waitForTimeout(100)
  }
}

/** The compositor layers that draw content over at least half the glass, from Chrome's own tree. */
async function largeLayers(page: Page, cdp: CDPSession) {
  const glass = (await page.locator('[data-testid="map-chart"]').boundingBox())!
  let layers: { width: number; height: number; drawsContent: boolean }[] = []
  cdp.on('LayerTree.layerTreeDidChange', (e) => {
    if (e.layers) layers = e.layers
  })
  await cdp.send('LayerTree.enable')
  // One small drag, so the tree is reported after a commit.
  await page.mouse.move(glass.x + glass.width / 2, glass.y + glass.height / 2)
  await page.mouse.down()
  await page.mouse.move(glass.x + glass.width / 2 - 40, glass.y + glass.height / 2)
  await page.mouse.up()
  await expect.poll(() => layers.length, { timeout: 10_000 }).toBeGreaterThan(0)
  await page.waitForTimeout(500)
  await cdp.send('LayerTree.disable')
  // Layer sizes are in device pixels.
  const dpr = await page.evaluate(() => window.devicePixelRatio)
  const half = (glass.width * dpr * glass.height * dpr) / 2
  return layers.filter((l) => l.drawsContent && l.width * l.height >= half).length
}

for (const { viewport, isMobile } of [
  { viewport: { width: 1440, height: 900 }, isMobile: false },
  { viewport: { width: 390, height: 844 }, isMobile: true },
]) {
  test.describe(`a fast pan never blinks — ${viewport.width}×${viewport.height}`, () => {
    test.use({ viewport, hasTouch: true, isMobile })

    test('the seas stand still, the grid and the day coast ride the paper under masks of the glass, no sheet is unmounted, and the chart is few surfaces', async ({
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

      // 2 and 3 — the structure.
      const shape = await page.evaluate(() => {
        const chart = document.querySelector('[data-testid="map-chart"]')!
        const grid = chart.querySelector('[data-testid="map-graticule"]')
        return {
          gridOnPaper: !!grid?.closest('[data-testid="map-coast-sheet"]'),
          masks: chart.querySelectorAll('[data-testid="map-daylight-mask"]').length,
          masksOnMovingSheet: [...chart.querySelectorAll('[data-testid="map-daylight-mask"]')].filter(
            (m) => !!m.parentElement?.closest('[data-testid="map-coast-sheet"], [data-testid="map-coast-sheet-day"]'),
          ).length,
          dayCoastUnderMask: !!chart.querySelector('[data-testid="map-daylight-mask"] [data-testid="map-coast-sheet-day"]'),
        }
      })
      expect(shape.gridOnPaper, 'the graticule is drawn on the coast sheet, so a pan moves it').toBe(true)
      expect(shape.masks, 'the day sea and the day coast each have their mask').toBe(2)
      expect(shape.masksOnMovingSheet, 'a daylight mask rides a sheet the pan moves').toBe(0)
      expect(shape.dayCoastUnderMask, 'the day coast is a sheet under a mask of the glass').toBe(true)

      // 1 and 4 — a real fast pan, by mouse and by finger.
      const cdp = await page.context().newCDPSession(page)
      await watch(page)
      const where = () =>
        page.evaluate(() => {
          const sheet = document.querySelector('[data-testid="map-coast-sheet"]') as HTMLElement
          return `${sheet.querySelector('svg')!.getAttribute('viewBox')} ${sheet.style.transform}`
        })
      const before = await where()
      await fastPans(page, cdp, 'mouse')
      await fastPans(page, cdp, 'touch')
      const seen = await stopWatching(page)
      expect(await where(), 'the pans moved the chart').not.toBe(before)
      expect(seen.frames, 'frames were sampled through the pans').toBeGreaterThan(20)
      expect(seen.sea, 'a pan re-drew a sea — they are pictures of the glass').toBe(0)
      expect(seen.removed, 'a pan unmounted a chart sheet').toBe(0)
      expect(seen.bare, 'the night coast sheet left part of the glass bare').toBe(0)

      // 5 — the surfaces.
      expect(await largeLayers(page, cdp), 'compositor layers at least half the glass').toBeLessThanOrEqual(7)
    })
  })
}

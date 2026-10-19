import { test, expect, type CDPSession, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { GAME_CLOCK_RATE } from '../src/lib/format/time'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DAYLIGHT MASK IS STILL WHEN NOTHING ON IT MOVED (2026-10-19, docs/dev-log/2026-10-19-daylight-raster.md).
//
// THE WASTE, MEASURED. On the owner's machine (Intel Arc, DPR 2) Chrome's own trace showed both
// `map-daylight-mask` layers — 2884×1288 device px each — re-rasterised on EVERY animation frame,
// at rest as much as in a pan: ~4,670 tile rasters each per probe run, four times the coast's. The
// cause was DaylightSheet's Sun glide: a fresh `mask-position` (to 1/100 px) written every frame,
// and every new value repaints the mask, however little the Sun had moved.
//
// WHAT THIS HOLDS. The view is left alone and the clock is advanced in steps so small that the Sun
// travels HALF A DEVICE PIXEL on the mask in 2 s — every step a new `mask-position` on the build
// before the fix, no visible change on either. Chrome's LayerTree must report no paint of either
// mask layer over those 2 s (the paint count is Chrome's, read off LayerTree before and after).
// Then the control: the clock jumps a degree of the Sun's travel (2 real seconds), and the masks
// MUST repaint — the glide still runs, it only waits until the Sun has gone far enough to show.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const MS_PER_DAY = 24 * 60 * 60 * 1000

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

/** Chrome's own paint count of the two daylight-mask layers. LayerTree counts a layer's paints only
 *  while the domain is ENABLED, so it is enabled once, before the window, and each reading asks for
 *  a fresh tree. */
async function watchMasks(page: Page, cdp: CDPSession) {
  type Layer = { layerId: string; backendNodeId?: number; paintCount?: number; drawsContent: boolean }
  let layers: Layer[] = []
  let reports = 0
  cdp.on('LayerTree.layerTreeDidChange', (e: { layers?: Layer[] }) => {
    if (e.layers) {
      layers = e.layers
      reports += 1
    }
  })
  await cdp.send('DOM.enable')
  await cdp.send('DOM.getDocument', { depth: -1 })
  await cdp.send('LayerTree.enable')
  const read = async (): Promise<{ masks: number; paints: number }> => {
    // No input — the view must stay still. Chrome reports the tree when its STRUCTURE changes, so
    // a speck with a layer of its own is added to the page and taken away again, off the chart.
    const seen = reports
    await page.evaluate(async () => {
      const speck = document.createElement('div')
      speck.style.cssText = 'position:fixed;left:0;top:0;width:1px;height:1px;will-change:transform;pointer-events:none'
      document.body.appendChild(speck)
      await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))
      speck.remove()
    })
    await expect.poll(() => reports, { timeout: 15_000 }).toBeGreaterThan(seen)
    let masks = 0
    let paints = 0
    for (const l of layers) {
      if (!l.backendNodeId || !l.drawsContent) continue
      const d = await cdp.send('DOM.describeNode', { backendNodeId: l.backendNodeId })
      const a = d.node.attributes ?? []
      const i = a.indexOf('data-testid')
      if (i >= 0 && a[i + 1] === 'map-daylight-mask') {
        masks += 1
        paints += l.paintCount ?? 0
      }
    }
    return { masks, paints }
  }
  return { read, stop: () => cdp.send('LayerTree.disable') }
}

test.describe('the daylight mask at rest', () => {
  test.use({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 })

  test('is not repainted while the view is still and the Sun has not moved a device pixel, and is once it has', async ({
    page,
    request,
    baseURL,
  }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), 'no preview server at the base URL')
    await openMap(page)

    // THE SUN, HELD BY THE CLOCK. serverNow() is Date.now() in local mode, and the glide reads it.
    let t = await page.evaluate(() => Date.now())
    await page.clock.setFixedTime(t)
    await page.waitForTimeout(500)
    // PLACED FOR THE HELD SUN, before anything is counted. The glide re-places the mask once the Sun
    // has gone a step since its LAST placement (DaylightSheet.tsx), so the mask a running clock left
    // may lag the held Sun by most of a step, and the half-pixel walk below then tipped it over: one
    // placement, both masks, 2 paints (main, 2026-10-19 03:02). A degree's jump places it exactly.
    t += 1 / ((360 * GAME_CLOCK_RATE) / MS_PER_DAY)
    await page.clock.setFixedTime(t)
    await page.waitForTimeout(500)

    // How far the Sun moves on the mask per real millisecond, in device pixels: one tile of the
    // mask (its `mask-size` width) is one turn of the world, one game day.
    const { tilePx, dpr } = await page.evaluate(() => {
      const el = document.querySelector<HTMLElement>('[data-testid="map-daylight-mask"]')!
      const size = getComputedStyle(el).getPropertyValue('mask-size') || getComputedStyle(el).getPropertyValue('-webkit-mask-size')
      return { tilePx: parseFloat(size), dpr: window.devicePixelRatio }
    })
    expect(tilePx, 'the mask has a tile').toBeGreaterThan(0)
    const devicePxPerMs = (tilePx * dpr * GAME_CLOCK_RATE) / MS_PER_DAY
    console.log(`mask tile ${tilePx.toFixed(0)} css px at dpr ${dpr}: the Sun moves ${(devicePxPerMs * 1000).toFixed(1)} device px per real second`)

    const cdp = await page.context().newCDPSession(page)
    const watch = await watchMasks(page, cdp)
    const before = await watch.read()
    expect(before.masks, 'both daylight masks are compositor layers').toBe(2)

    // 2 s, 20 steps, the Sun travelling half a device pixel in all. Each step moves it 0.0125 css
    // px, enough to change a `mask-position` written to 1/100 px.
    const STEPS = 20
    const stepMs = 0.5 / devicePxPerMs / STEPS
    for (let i = 0; i < STEPS; i++) {
      t += stepMs
      await page.clock.setFixedTime(t)
      await page.waitForTimeout(100)
    }
    const rest = await watch.read()
    const still = rest.paints - before.paints
    console.log(`mask paints over 2 s idle, the Sun moving 0.5 device px: ${still}`)

    // THE CONTROL: a degree of longitude, and the masks repaint.
    t += 1 / ((360 * GAME_CLOCK_RATE) / MS_PER_DAY)
    await page.clock.setFixedTime(t)
    await page.waitForTimeout(500)
    const moved = (await watch.read()).paints - rest.paints
    await watch.stop()
    console.log(`mask paints after the Sun moved a degree: ${moved}`)

    expect(still, 'no mask paint while nothing on it moved a device pixel').toBe(0)
    expect(moved, 'the masks repaint once the Sun has moved a pixel').toBeGreaterThan(0)
  })
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FRAME COST OF THE CHART, PRINTED — the apparatus behind the figures in docs/MAP_ATMOSPHERE.md
// §11 (2026-10-14: ships at every zoom, the continuous sheet, the Sun).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A measurement, not a gate: nothing here pins a wall-clock number (a threshold on a shared CI
// runner is a flake — tests/map.lag.spec.ts's header). It prints, at the globe and at the opening
// frame, on the phone and on the desktop glass, with the merchants sailing:
//
//   zoom step   `zoomStepMs` — twelve wheel steps, two animation frames each (row 90's apparatus)
//   idle        the animation-frame interval over five seconds of nobody touching anything — the
//               drift tick (1 Hz) and the ship-light blink are what run; mean, p95 and worst
//   pan         the frame interval during a real drag of a fifth of the glass
//   DOM         how many hull paths and harbour groups the sheet holds
//
// Written so that it runs unchanged against `main` before this work (it imports only what main
// exports), which is how the before/after figures in §11 were taken: same spec, two builds.

import { test, expect, type Page } from '@playwright/test'
import { PHONE, reachable, ready, zoomStepMs } from './appReady.fixture'
import { serveNpcOn } from './npcOn.fixture'

/** rAF intervals over `ms`, measured inside the page. */
async function frameIntervals(page: Page, ms: number): Promise<{ mean: number; p95: number; max: number; frames: number }> {
  return page.evaluate(async (budget) => {
    const gaps: number[] = []
    let last = performance.now()
    const start = last
    await new Promise<void>((resolve) => {
      const tick = () => {
        const now = performance.now()
        gaps.push(now - last)
        last = now
        if (now - start < budget) requestAnimationFrame(tick)
        else resolve()
      }
      requestAnimationFrame(tick)
    })
    gaps.shift()
    const sorted = [...gaps].sort((a, b) => a - b)
    const mean = gaps.reduce((s, g) => s + g, 0) / Math.max(1, gaps.length)
    return { mean, p95: sorted[Math.floor(sorted.length * 0.95)] ?? 0, max: sorted[sorted.length - 1] ?? 0, frames: gaps.length }
  }, ms)
}

async function domCounts(page: Page) {
  return page.evaluate(() => {
    // Null-safe: before the world has opened there is no chart on the page, and the poll below
    // reads zero hulls rather than a thrown error.
    const chart = document.querySelector('[data-testid="map-chart"]')
    const svg = chart?.querySelector('[data-testid="map-view"]')
    return {
      hulls: document.querySelectorAll('path[data-hull-class]').length,
      ships: document.querySelectorAll('[data-testid="map-merchant"], [data-testid="map-ship"]').length,
      embers: document.querySelectorAll('[data-fleet-mark="ember"]').length,
      harbours: document.querySelectorAll('[data-port-code]').length,
      nodes: chart ? chart.querySelectorAll('*').length : 0,
      span: svg ? Number(svg.getAttribute('viewBox')!.split(/\s+/)[2]) : Number.NaN,
    }
  })
}

async function panFrames(page: Page): Promise<{ mean: number; p95: number; max: number }> {
  const chart = (await page.locator('[data-testid="map-chart"]').boundingBox())!
  const x0 = chart.x + chart.width * 0.6
  const y = chart.y + chart.height / 2
  await page.evaluate(() => {
    const w = window as unknown as { __gaps: number[]; __last: number; __on: boolean }
    w.__gaps = []
    w.__last = performance.now()
    w.__on = true
    const tick = () => {
      const now = performance.now()
      w.__gaps.push(now - w.__last)
      w.__last = now
      if (w.__on) requestAnimationFrame(tick)
    }
    requestAnimationFrame(tick)
  })
  await page.mouse.move(x0, y)
  await page.mouse.down()
  for (let i = 1; i <= 30; i++) {
    await page.mouse.move(x0 - (chart.width * 0.2 * i) / 30, y)
    await page.waitForTimeout(16)
  }
  await page.mouse.up()
  return page.evaluate(() => {
    const w = window as unknown as { __gaps: number[]; __on: boolean }
    w.__on = false
    const gaps = w.__gaps.slice(1)
    const sorted = [...gaps].sort((a, b) => a - b)
    return {
      mean: gaps.reduce((s, g) => s + g, 0) / Math.max(1, gaps.length),
      p95: sorted[Math.floor(sorted.length * 0.95)] ?? 0,
      max: sorted[sorted.length - 1] ?? 0,
    }
  })
}

test('the frame cost of the chart, printed at the globe and at the opening frame', async ({ page, request, baseURL }) => {
  test.setTimeout(1_200_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await serveNpcOn(page)
  const out: string[] = []
  for (const viewport of [PHONE, { width: 1440, height: 900 }]) {
    await page.setViewportSize(viewport)
    await page.goto('map')
    await ready(page)
    // The merchants-on world boots off a 26 MB image in the tab; on a loaded machine that is past
    // a minute, so this waits three.
    await expect.poll(async () => (await domCounts(page)).hulls, { timeout: 180_000 }).toBeGreaterThanOrEqual(1)
    await page.waitForTimeout(1500)
    const opening = await domCounts(page)
    const openingIdle = await frameIntervals(page, 5000)
    const openingPan = await panFrames(page)
    const openingZoom = await zoomStepMs(page)
    for (let i = 0; i < 12; i++) await page.getByLabel('Zoom out').click()
    await page.waitForTimeout(1500)
    const globe = await domCounts(page)
    const globeIdle = await frameIntervals(page, 5000)
    const globePan = await panFrames(page)
    const globeZoom = await zoomStepMs(page)
    const f = (n: number) => n.toFixed(1)
    out.push(
      `${viewport.width}×${viewport.height} opening (${opening.span.toFixed(1)}°): ${opening.ships} ships / ${opening.hulls} hulls / ${opening.embers} embers / ${opening.harbours} harbours / ${opening.nodes} nodes · ` +
        `idle ${f(openingIdle.mean)} ms mean, p95 ${f(openingIdle.p95)}, max ${f(openingIdle.max)} · pan ${f(openingPan.mean)} mean, p95 ${f(openingPan.p95)}, max ${f(openingPan.max)} · zoom step ${f(openingZoom)} ms`,
    )
    out.push(
      `${viewport.width}×${viewport.height} globe (${globe.span.toFixed(1)}°): ${globe.ships} ships / ${globe.hulls} hulls / ${globe.embers} embers / ${globe.harbours} harbours / ${globe.nodes} nodes · ` +
        `idle ${f(globeIdle.mean)} ms mean, p95 ${f(globeIdle.p95)}, max ${f(globeIdle.max)} · pan ${f(globePan.mean)} mean, p95 ${f(globePan.p95)}, max ${f(globePan.max)} · zoom step ${f(globeZoom)} ms`,
    )
  }
  console.log('\n' + out.join('\n'))
})

import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MAP'S SIDE TRAY SLIDES FROM THE EDGE OF THE PAGE (owner, 2026-11-05: *"when pressing a
// location on map, a pop up shows right side of the map, but not totally fully on the right. i
// want it to slide from the right slide from the edge of the page"*).
//
// Measured off the running app, never off a class: at 1440, 1280, 1024 and a phone the tray's right
// edge IS window.innerWidth; its first painted frame is off the page (left >= innerWidth) and it
// then travels in; closing it travels back out before it leaves the DOM; the page never gains a
// horizontal scroll; the map (chart box + viewBox) does not move under it.
//
// Run it: npm run build && npx vite preview --port 4391, then
// PLAYWRIGHT_BASE_URL=http://localhost:4391/byeharu-voyage/ npx playwright test map.tray.edge.spec.ts
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { name: '1440', width: 1440, height: 900 },
  { name: '1280', width: 1280, height: 800 },
  { name: '1024', width: 1024, height: 768 },
  { name: 'phone', width: 390, height: 844 },
]

async function pressAPort(page: Page) {
  const pos = await page.evaluate(() => {
    const svg = document.querySelector('[aria-label^="Chart of the world"]')!
    const box = svg.getBoundingClientRect()
    const labels = [...svg.querySelectorAll('text[data-label-id^="port:"]')]
      .map((t) => t.getBoundingClientRect())
      .filter(
        (r) =>
          r.width > 0 &&
          r.x > box.x + 8 &&
          r.x + r.width < box.x + box.width * 0.6 &&
          r.y > box.y + 80 &&
          r.y + r.height < box.y + box.height - 40,
      )
    const r = labels[0]
    return r ? { x: r.x + r.width / 2, y: r.y + r.height / 2 } : null
  })
  expect(pos, 'no port name on the opening frame to press').not.toBeNull()
  await page.mouse.click(pos!.x, pos!.y)
}

type Probe = { __lefts: number[] }

for (const size of SIZES) {
  test(`the map tray slides in from the page edge and out again at ${size.name}`, async ({ page, request, baseURL }) => {
    test.setTimeout(420_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await page.setViewportSize({ width: size.width, height: size.height })
    await page.goto('map')
    await ready(page)
    await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })

    // Record the tray's left edge on every frame while it stands.
    await page.evaluate(() => {
      const w = window as unknown as Probe
      w.__lefts = []
      const tick = () => {
        const el = document.querySelector('[data-testid="map-detail-tray"]')
        if (el) w.__lefts.push(el.getBoundingClientRect().left)
        requestAnimationFrame(tick)
      }
      requestAnimationFrame(tick)
    })
    const chartBox = () =>
      page.evaluate(() => {
        const svg = document.querySelector('[aria-label^="Chart of the world"]')!
        const r = svg.getBoundingClientRect()
        const view = document.querySelector('[data-testid="map-view"]')!.getAttribute('viewBox')
        return { x: r.x, y: r.y, w: r.width, h: r.height, view }
      })
    const before = await chartBox()

    await pressAPort(page)
    const tray = page.getByTestId('map-detail-tray')
    await expect(tray).toBeVisible()
    await expect(tray).toHaveAttribute('data-tray-mode', 'side')
    await page.waitForTimeout(800)

    const win = await page.evaluate(() => window.innerWidth)
    const box = await tray.boundingBox()
    expect(box).not.toBeNull()
    expect(box!.x + box!.width, 'tray right edge vs window width').toBeCloseTo(win, 1)

    const lefts = await page.evaluate(() => (window as unknown as Probe).__lefts)
    expect(lefts.length).toBeGreaterThan(2)
    expect(lefts[0], 'first painted frame starts off the page').toBeGreaterThanOrEqual(win - 1)
    expect(lefts[lefts.length - 1]).toBeLessThan(win - 100)

    // No sideways scroll, and the map has not moved.
    const flow = await page.evaluate(() => ({
      doc: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      body: document.body.scrollWidth - document.documentElement.clientWidth,
    }))
    expect(flow.doc).toBeLessThanOrEqual(0)
    expect(flow.body).toBeLessThanOrEqual(0)
    expect(await chartBox()).toEqual(before)

    // Closing slides back out before the tray leaves the DOM.
    await page.evaluate(() => {
      ;(window as unknown as Probe).__lefts = []
    })
    await tray.getByTestId('tray-close').first().click()
    await expect(tray).toHaveCount(0)
    const out = await page.evaluate(() => (window as unknown as Probe).__lefts)
    expect(out.length, 'tray left the DOM without sliding out').toBeGreaterThan(2)
    expect(out[out.length - 1]).toBeGreaterThan(out[0] + 50)
    const after = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
    expect(after).toBeLessThanOrEqual(0)
  })
}

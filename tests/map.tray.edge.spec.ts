import { test, expect, type Page } from '@playwright/test'
import { arrivedAtEdge, reachable, ready } from './appReady.fixture'

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
    const win = await page.evaluate(() => window.innerWidth)
    // Not a sleep (see arrivedAtEdge): the slide's start follows the runner's speed. The assertions below stay the verdict.
    await arrivedAtEdge(tray, win)

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

// ── A TRAY ON ITS WAY OUT TAKES NO TAP ─────────────────────────────────────────────────────────
// The red on PR #492's acceptance (tests/map.sendfleet.spec.ts:436): a tap in the slide-out landed ON the leaving tray where it
// covers the harbour (a phone's whole glass; a wide glass's right column), the chart never saw it, and the tray then finished
// closing on nothing. At the real 240 ms it is a race, so the way out is held to 3 s here: the tap lands in it every time.
const SLOW_EXIT = '.bv-slide-to-right { animation-duration: 3s !important; }'
const HARBOUR_UNDER_TRAY = [
  { name: 'phone', width: 390, height: 844, code: 'AGA', word: 'Agadir' },
  { name: '1440', width: 1440, height: 900, code: 'CEU', word: 'Ceuta' },
]

async function openTheMap(page: Page, width: number, height: number) {
  await page.setViewportSize({ width, height })
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
  await page.waitForTimeout(1200)
}

async function pressHarbour(page: Page, code: string) {
  const at = await page.evaluate((c) => {
    const r = document.querySelector(`g[data-port-code="${c}"] path`)?.getBoundingClientRect()
    return r ? { x: r.x + r.width / 2, y: r.y + r.height / 2 } : null
  }, code)
  expect(at, `${code}'s mark is not on the glass`).not.toBeNull()
  await page.mouse.click(at!.x, at!.y)
}

for (const size of HARBOUR_UNDER_TRAY) {
  test(`another harbour tapped during the slide-out shows its own tray, slid in, at ${size.name}`, async ({ page, request, baseURL }) => {
    test.setTimeout(420_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await openTheMap(page, size.width, size.height)
    await page.addStyleTag({ content: SLOW_EXIT })
    await pressHarbour(page, 'CAD')
    const tray = page.getByTestId('map-detail-tray')
    await expect(tray).toContainText('Cadiz')
    await page.waitForTimeout(500)
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
    await tray.getByTestId('tray-close').first().click()
    await page.waitForTimeout(100)
    await expect(tray, 'the slide-out is not under way, so this tap proves nothing').toHaveClass(/bv-slide-to-right/)
    await page.evaluate(() => {
      ;(window as unknown as Probe).__lefts = []
    })
    await pressHarbour(page, size.code)

    await expect(tray, 'the tap fell on the leaving tray and the chart never saw it').toContainText(size.word, { timeout: 2000 })
    await expect(tray).not.toHaveClass(/bv-slide-to-right/)
    // Past the end of the old slide-out: nothing left over from it closes the new tray.
    await page.waitForTimeout(3300)
    await expect(tray).toContainText(size.word)
    const win = size.width
    const lefts = await page.evaluate(() => (window as unknown as Probe).__lefts)
    expect(lefts.some((l) => l >= win - 1), 'the new tray did not start off the page').toBe(true)
    expect(lefts[lefts.length - 1]).toBeLessThan(win - 100)
  })
}

// ── A CLOSE ALWAYS COMPLETES ───────────────────────────────────────────────────────────────────
// The way out is a picture of the close, never a condition of it: no animation, no `animationend`, and the tray still goes.
test('a close completes when no slide-out animation runs at all', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  await openTheMap(page, 1440, 900)
  await page.addStyleTag({ content: '.bv-slide-to-right { animation: none !important; }' })
  await pressHarbour(page, 'CAD')
  const tray = page.getByTestId('map-detail-tray')
  await expect(tray).toBeVisible()
  await tray.getByTestId('tray-close').first().click()
  await expect(tray, 'no animation ran, so nothing ever closed the tray').toHaveCount(0, { timeout: 2000 })
})

test('a close completes for a player who asks for reduced motion', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await openTheMap(page, 1440, 900)
  expect(await page.evaluate(() => matchMedia('(prefers-reduced-motion: reduce)').matches), 'the emulation did not take').toBe(true)
  await pressHarbour(page, 'CAD')
  const tray = page.getByTestId('map-detail-tray')
  await expect(tray).toBeVisible()
  await tray.getByTestId('tray-close').first().click()
  await expect(tray).toHaveCount(0, { timeout: 2000 })
})

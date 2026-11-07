import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DRIVE AUDIT, 2026-11-08 — THE MAP, DRIVEN AS THE OWNER WOULD
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/OWNER_REQUESTS.md row 72: *"create a perpendicular helper line (dotted) that is the shortest
// point between the land city and nearby shore - sea. Then create a point there, and when the ship
// arrive at that point, consider it as the ship have landed on land"*. The chart half (the dotted
// line and the roadstead ring) has a pure spec; nobody has looked for them ON THE RENDERED CHART,
// and no browser spec has sent a fleet and watched her come to lie. This does both: it finds the
// marks on the glass at Lisbon, reads the send tray's own sentence about the roads, sends the only
// fleet to the nearest harbour, and waits for Fleets to say she lies there.
// Row 278 (the tray on the window's edge) is COVERED by map.tray.edge.spec.ts; one read here at the
// owner's own 1440 glass, for the picture.

const OUT = 'docs/dev-log/2026-11-08-drive-audit'
const WIDE = { width: 1280, height: 800 }
const LAPTOP = { width: 1440, height: 900 }

test.use({ deviceScaleFactor: 2 })

async function shot(page: Page, name: string) {
  await page.waitForTimeout(300)
  await page.screenshot({ path: `${OUT}/${name}.png` })
}

async function openMap(page: Page, request: Parameters<typeof reachable>[0], baseURL: string | undefined, size: { width: number; height: number }) {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(size)
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 120_000 })
  await page.waitForTimeout(1500)
}

/** The centre of a harbour's mark inside the chart, or null. */
async function markAt(page: Page, code: string) {
  return page.evaluate((c) => {
    const chart = document.querySelector('[data-testid="map-chart"]')?.getBoundingClientRect()
    if (!chart) return null
    for (const e of document.querySelectorAll(`[data-testid="map-ports"] [data-port-code="${c}"]`)) {
      const r = e.getBoundingClientRect()
      const x = r.x + r.width / 2
      const y = r.y + r.height / 2
      if (r.width > 0 && x > chart.left && x < chart.right && y > chart.top && y < chart.bottom) return { x, y }
    }
    return null
  }, code)
}

test('Map: the dotted line and the roadstead ring stand off Lisbon on the glass; a send ends in the roads and she comes to lie at the harbour (row 72)', async ({ page, request, baseURL }) => {
  await openMap(page, request, baseURL, WIDE)
  // zoom in twice on the home harbour so the roadstead marks are past their minimum size
  const zoomIn = page.getByLabel(/Zoom in|확대/)
  for (let i = 0; i < 2; i++) {
    await zoomIn.click()
    await page.waitForTimeout(500)
  }
  await page.waitForTimeout(800)
  const roads = await page.evaluate(() => {
    const layer = document.querySelector('[data-testid="map-roadsteads"]')
    if (!layer) return null
    const out: { code: string; dashed: boolean; ring: boolean; dx: number }[] = []
    for (const g of layer.querySelectorAll('g[data-roadstead-code]')) {
      const path = g.querySelector('path')
      const circle = g.querySelector('circle')
      const dash = path ? getComputedStyle(path).strokeDasharray : ''
      const gb = g.getBoundingClientRect()
      out.push({ code: g.getAttribute('data-roadstead-code') ?? '?', dashed: dash !== '' && dash !== 'none', ring: !!circle, dx: Math.round(gb.width) })
    }
    return out
  })
  console.log(`roadstead marks on the glass: ${JSON.stringify(roads?.slice(0, 12))} (${roads?.length ?? 0} total)`)
  expect(roads, 'no roadsteads layer on the chart').not.toBeNull()
  const lis = roads!.find((r) => r.code === 'LIS')
  expect(lis, 'Lisbon has no roadstead mark on the glass').toBeDefined()
  expect(lis!.dashed, 'the helper line to the roads is not dotted').toBe(true)
  expect(lis!.ring, 'the roads have no point (ring)').toBe(true)
  await shot(page, 'map-roadstead-lisbon-1280@2x')

  // the nearest harbour to the home mark, not the home mark itself
  const target = await page.evaluate(() => {
    const chart = document.querySelector('[data-testid="map-chart"]')?.getBoundingClientRect()
    const home = document.querySelector('[data-testid="map-ports"] [data-port-code="LIS"]')?.getBoundingClientRect()
    if (!chart || !home) return null
    const hx = home.x + home.width / 2
    const hy = home.y + home.height / 2
    let best: { code: string; x: number; y: number; d: number } | null = null
    for (const e of document.querySelectorAll('[data-testid="map-ports"] [data-port-code]')) {
      const code = e.getAttribute('data-port-code') ?? ''
      if (code === 'LIS') continue
      const r = e.getBoundingClientRect()
      const x = r.x + r.width / 2
      const y = r.y + r.height / 2
      if (r.width <= 0 || x < chart.left + 40 || x > chart.right - 40 || y < chart.top + 90 || y > chart.bottom - 70) continue
      const d = Math.hypot(x - hx, y - hy)
      if (!best || d < best.d) best = { code, x, y, d }
    }
    return best
  })
  expect(target, 'no harbour near Lisbon on the chart').not.toBeNull()
  await page.mouse.click(target!.x, target!.y)
  await expect(page.getByTestId('map-detail-tray')).toBeVisible({ timeout: 30_000 })
  const placeName = (await page.getByTestId('map-place-name').first().innerText()).trim()
  console.log(`sailing to ${placeName} (${target!.code})`)
  await page.getByTestId('map-send-fleet').click()
  await expect(page.getByTestId('map-send-row-head').first()).not.toContainText(/checking/i, { timeout: 60_000 })
  await page.getByTestId('map-send-row-head').first().click()
  await page.waitForTimeout(1200)
  const roadsHint = page.getByTestId('map-send-roads')
  await expect(roadsHint, 'the send tray says nothing about the roads').toBeVisible({ timeout: 30_000 })
  const hint = (await roadsHint.innerText()).replace(/\s+/g, ' ')
  console.log(`send tray: ${hint}`)
  // the plain-words slice calls the roads "the anchorage" and the distance "miles offshore"
  expect(hint).toMatch(/roads|anchorage|offshore|정박지|nm|miles/)
  await shot(page, 'map-send-roads-1280@2x')
  await page.getByTestId('map-send-ratio-send').click()
  await page.waitForTimeout(3000)

  // SHE COMES TO LIE AT THE HARBOUR: Fleets names the destination as where she is, no longer "to …"
  await page.goto('fleets')
  await ready(page)
  const row = page.getByTestId('fleet-row').first()
  await expect(row).toBeVisible({ timeout: 60_000 })
  const t0 = Date.now()
  const underWay = (await row.innerText()).replace(/\s+/g, ' ')
  console.log(`under way, the fleet row reads: ${underWay}`)
  expect(underWay, 'the send did not put her to sea').toMatch(new RegExp(`\\bto\\s+${placeName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`))
  // she lies at the harbour when the row names it WITHOUT "to": the roadstead is her landfall
  await expect
    .poll(
      async () => {
        const text = (await row.innerText()).replace(/\s+/g, ' ')
        return !/\bto\s+\S/.test(text) && text.includes(placeName) ? 'docked' : text
      },
      { timeout: 300_000, intervals: [2000] },
    )
    .toBe('docked')
  const where = (await row.innerText()).replace(/\s+/g, ' ')
  console.log(`after ${Math.round((Date.now() - t0) / 1000)} s the fleet row reads: ${where}`)
  await expect(page.getByTestId('fleets-underway')).toContainText('0')
  await shot(page, 'fleets-arrived-1280@2x')
})

test('Map @1440: a harbour\'s tray lands on the window\'s own edge (row 278, the owner\'s laptop)', async ({ page, request, baseURL }) => {
  await openMap(page, request, baseURL, LAPTOP)
  const at = await markAt(page, 'CAD')
  test.skip(!at, 'Cadiz is not on the opening chart')
  await page.mouse.click(at!.x, at!.y)
  const tray = page.getByTestId('map-detail-tray')
  await expect(tray).toBeVisible({ timeout: 30_000 })
  await expect.poll(async () => {
    const b = await tray.boundingBox()
    return b ? Math.round(b.x + b.width) : -1
  }, { timeout: 10_000 }).toBe(LAPTOP.width)
  await expect(page.getByTestId('map-place-name').first()).toContainText('Cadiz')
  await shot(page, 'map-tray-1440@2x')
  await page.getByTestId('tray-close').first().click()
  await expect(tray).toHaveCount(0, { timeout: 10_000 })
})

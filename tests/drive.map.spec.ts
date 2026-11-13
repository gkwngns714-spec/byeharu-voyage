import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { LANDS_WITHIN_MS } from './arrivalWait.fixture'
import { chartOpen } from './seaFrame.fixture'
import { watchMeter, type MeterWindow } from './mapMeter.fixture'

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
  // The sea may delay any voyage (tests/arrivalWait.fixture.ts): the test's ten minutes kept, with the old 300 s wait replaced by the shared one.
  test.setTimeout(600_000 - 300_000 + LANDS_WITHIN_MS)
  await page.goto('fleets')
  await ready(page)
  const row = page.getByTestId('fleet-row').first()
  await expect(row).toBeVisible({ timeout: 60_000 })
  const t0 = Date.now()
  const underWay = (await row.innerText()).replace(/\s+/g, ' ')
  console.log(`the fleet row reads (right after the send, on the Fleets page): ${underWay}`)
  // NOT asserted: that this first read still says "to <harbour>". A short hop (Lisbon to Setubal) can be over before the Fleets page has
  // loaded on a shared CI runner (it was: "Gaivota Setubal ..." with no "to", in plain shard 1/3 and in the npc pool). The proof that the
  // send put her to sea is the line below: she started at Lisbon and ends lying at the NEW harbour; had the send failed she would never get there.
  // she lies at the harbour when the row names it WITHOUT "to": the roadstead is her landfall
  await expect
    .poll(
      async () => {
        const text = (await row.innerText()).replace(/\s+/g, ' ')
        return !/\bto\s+\S/.test(text) && text.includes(placeName) ? 'docked' : text
      },
      { timeout: LANDS_WITHIN_MS, intervals: [2000], message: 'she did not come to lie at the harbour; the value below is what her Fleets row still says' },
    )
    .toBe('docked')
  const where = (await row.innerText()).replace(/\s+/g, ' ')
  console.log(`after ${Math.round((Date.now() - t0) / 1000)} s the fleet row reads: ${where}`)
  await expect(page.getByTestId('fleets-underway')).toContainText('0')
  await shot(page, 'fleets-arrived-1280@2x')
})

// ── ROW 255: THE MAP'S LOADING PERCENTAGE (D6 of the drive audit) ────────────────────────────────
// The owner: *"when reloading, for example opening the city, or loading the map, show percentage of its loading time"*. The city's
// meter (`LoadMeter`, held by tests/city.audit.spec.ts) is MEASURED WORK: one `done` per real read, no timer. The map composes the
// SAME component over the same world steps (World · Sea · Fleets, the store's `boot`) and its own last one, the first roster of the
// ships at sea. The meter's own writes are read off the page (an observer installed before the first paint, so a step that lands
// in a few milliseconds is still seen): the percentage may only rise and takes the steps' own values, the meter is an overlay (the
// chart's box is the same with it and without it), and it goes only once the world is ready. Back from the HQ the world is already
// up and the map's one pending read is the roster, so the meter shows that step alone, then goes.
const FIX = 'docs/dev-log/2026-11-08-axis-map-load-words'
const PHONE = { width: 390, height: 844 }
for (const size of [WIDE, PHONE]) {
  test(`Map @${size.width}: the loading percentage is measured work — the world's steps and the ships, rising only, an overlay, gone at ready (row 255, D6)`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    // the test's own fresh context (DPR 2 and the suite's dark skin), so the first load is cold
    await page.setViewportSize(size)
    await page.addInitScript(watchMeter)
    // a cold load on a slowed wire, so the world's reads are really on it (the city's meter is held the same way)
    const cdp = await page.context().newCDPSession(page)
    await cdp.send('Network.enable')
    await cdp.send('Network.setCacheDisabled', { cacheDisabled: true })
    await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 120, downloadThroughput: 2_000_000, uploadThroughput: 1_000_000 })
    await page.goto(new URL('map', baseURL ?? '').href, { waitUntil: 'commit' })
    // the picture: what stands on the sea while the world downloads (the meter, or the old plain line)
    await page.waitForSelector('[data-testid="map-load"], [data-testid="map-loading"]', { timeout: 120_000 }).catch(() => null)
    await page.waitForTimeout(400)
    await page.screenshot({ path: `${FIX}/map-loading-${size.width}@2x.png` })
    await ready(page)
    await chartOpen(page)
    await expect(page.getByTestId('map-load')).toHaveCount(0, { timeout: 60_000 })
    const cold = await page.evaluate(() => (window as unknown as MeterWindow).__meter ?? [])
    console.log(`AUDIT map meter @${size.width}, cold: ${JSON.stringify(cold)}`)
    const shown = cold.filter((e) => !e.gone)
    expect(shown.length, 'the map showed no loading percentage').toBeGreaterThan(0)
    for (let i = 1; i < shown.length; i++) expect(shown[i].pct, `the meter went backwards: ${shown.map((e) => e.pct).join(',')}`).toBeGreaterThanOrEqual(shown[i - 1].pct ?? 0)
    expect(shown.every((e) => [0, 25, 50, 75].includes(e.pct ?? -1)), `a percentage not tied to a step: ${shown.map((e) => e.pct).join(',')}`).toBe(true)
    expect(shown.every((e) => ['world', 'sea', 'fleets', 'ships'].includes(e.step ?? '')), `an unknown step: ${shown.map((e) => e.step).join(',')}`).toBe(true)
    expect(shown.every((e) => e.position === 'absolute'), 'the meter takes flow space on the chart').toBe(true)
    const gone = cold.filter((e) => e.gone)
    expect(gone.length, 'the meter never went').toBeGreaterThan(0)
    expect(gone[gone.length - 1].world, 'the meter went before the world was ready').toBe('ready')
    // NO LAYOUT JUMP: the chart's box with the meter on it is the chart's box without it
    const after = await page.getByTestId('map-chart').evaluate((el) => {
      const r = el.getBoundingClientRect()
      return [r.x, r.y, r.width, r.height].map(Math.round).join(',')
    })
    for (const e of shown) if (e.chart !== null) expect(e.chart, 'the chart moved under the meter').toBe(after)

    // THE SHIPS ARE A STEP OF THEIR OWN: to the HQ and back, the meter counts the roster alone (nothing is kept of a dark roster)
    await page.evaluate(() => {
      ;(window as unknown as MeterWindow).__meter = []
    })
    await page.getByTestId('nav-cell-/city').first().click()
    await expect(page.getByTestId('city-rail')).toBeVisible({ timeout: 120_000 })
    await page.getByTestId('nav-cell-/map').first().click()
    await chartOpen(page)
    await expect(page.getByTestId('map-load')).toHaveCount(0, { timeout: 60_000 })
    const warm = await page.evaluate(() => (window as unknown as MeterWindow).__meter ?? [])
    console.log(`AUDIT map meter @${size.width}, back from the HQ: ${JSON.stringify(warm)}`)
    const warmShown = warm.filter((e) => !e.gone)
    expect(warmShown.length, 'back on the map, the ships were not counted as a step').toBeGreaterThan(0)
    expect(warmShown.map((e) => e.step), 'a step other than the ships was pending on a warm map').toEqual(warmShown.map(() => 'ships'))
    expect(warmShown.map((e) => e.pct)).toEqual(warmShown.map(() => 75))
  })
}

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

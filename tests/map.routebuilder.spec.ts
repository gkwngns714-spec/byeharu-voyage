import { test, expect, type Page } from '@playwright/test'
import { ready, reachable, WORLD_BOOT_MS } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ROUTE BUILDER ON THE MAP, DRIVEN (owner row 209, docs/ROUTE_BUILDER.md B2)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-26: *"in the map, let me click set route, and let me press city, undo, then confirm each visiting
// city, then press final - something like that."* Driven on THE REAL GAME in the tab — the real chain on PGlite, the
// §K.1 house at Lisbon, the real world.route_legs (0346) judging every leg and the real cmd.issue_lines queuing them —
// at the owner's two widths: Set route → a city → another city (a press replaces the next stop) → Undo → the first
// city again → Confirm → a second city → Confirm → Final. Then her queue is on the chart (numbered stops), and a city
// tap opens the city tray exactly as before route mode. The bar never moves while stops are added.
//
// Each city is a harbour NAMED on the opening frame, picked off the DOM the player sees, and kept only when the
// SERVER calls its leg open (Confirm's `data-reason`), so the drive never relies on a city this file guessed.
// It SKIPS with a stated reason when nothing is served (tests/appReady.fixture.ts).
//
// Run it: npm run build && npx vite preview --port 4173, then `npx playwright test map.routebuilder.spec.ts`.

async function openMap(page: Page) {
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: WORLD_BOOT_MS })
}

/** The centres of the harbour names drawn on the glass (not Lisbon, not under the route bar), nearest the chart's
 *  middle first — what a player would put a thumb on. */
async function namedCities(page: Page): Promise<{ code: string; x: number; y: number }[]> {
  const bar = (await page.getByTestId('route-bar').count()) > 0 ? await page.getByTestId('route-bar').boundingBox() : null
  return page.evaluate((barTop) => {
    const chart = document.querySelector('[data-testid="map-chart"]')!.getBoundingClientRect()
    const mid = { x: chart.x + chart.width / 2, y: chart.y + chart.height / 2 }
    return [...document.querySelectorAll('text[data-label-id^="port:"]')]
      .map((el) => {
        const r = el.getBoundingClientRect()
        return { code: (el.getAttribute('data-label-id') ?? '').slice(5), x: r.x + r.width / 2, y: r.y + r.height / 2 }
      })
      .filter((c) => c.code !== 'LIS' && c.x > chart.x + 60 && c.x < chart.right - 60 && c.y > chart.y + 70 && c.y < Math.min(chart.bottom, barTop) - 16)
      .sort((a, b) => Math.hypot(a.x - mid.x, a.y - mid.y) - Math.hypot(b.x - mid.x, b.y - mid.y))
  }, bar ? bar.y : Number.POSITIVE_INFINITY)
}

/** Tap a city in route mode and wait for the server's verdict on its leg; the verdict (Confirm's data-reason). */
async function tapCity(page: Page, c: { code: string; x: number; y: number }): Promise<string> {
  await page.mouse.click(c.x, c.y)
  const pending = page.locator('[data-testid="route-leg"][data-pending]')
  await expect(pending).toHaveAttribute('data-to', c.code)
  const confirm = page.getByTestId('route-confirm')
  await expect(confirm).not.toHaveAttribute('data-reason', 'checking', { timeout: 60_000 })
  return (await confirm.getAttribute('data-reason')) ?? ''
}

async function drive(page: Page, label: string) {
  await openMap(page)

  // HER TRAY, from the fleets corner, and its Set route press
  const pill = page.getByTestId('map-fleets-corner').locator('button[aria-expanded]')
  await pill.click()
  await page.getByTestId('map-fleet-row').first().click()
  const tray = page.getByTestId('map-detail-tray')
  await expect(tray).toBeVisible()
  await page.getByTestId('map-set-route').click()
  // the fleets list folds back once the tray has given way to the bar, so no harbour name is under it
  if ((await pill.getAttribute('aria-expanded')) === 'true') await pill.click()

  const bar = page.getByTestId('route-bar')
  await expect(bar).toBeVisible()
  await expect(tray, 'a tray stayed open in route mode').toHaveCount(0)
  await expect(bar).toHaveAttribute('data-kept', '0')
  const box0 = await bar.boundingBox()
  expect(box0).not.toBeNull()

  // TWO CITIES THE SERVER CALLS OPEN: the nearest named harbours, each tried until its leg is open
  const cities = await namedCities(page)
  expect(cities.length, 'fewer than two harbours are named on the opening frame').toBeGreaterThanOrEqual(2)
  let first: (typeof cities)[number] | null = null
  for (const c of cities) {
    if ((await tapCity(page, c)) === 'open') {
      first = c
      break
    }
  }
  expect(first, 'no named city near Lisbon has an open leg').not.toBeNull()
  const second = cities.find((c) => c.code !== first!.code)!

  // A PRESS REPLACES THE NEXT STOP, and Undo takes the next stop away
  await tapCity(page, second)
  await expect(page.getByTestId('route-leg')).toHaveCount(1)
  await page.getByTestId('route-undo').click()
  await expect(page.getByTestId('route-leg')).toHaveCount(0)

  // THE FIRST CITY AGAIN, CONFIRMED
  expect(await tapCity(page, first!)).toBe('open')
  await page.getByTestId('route-confirm').click()
  await expect(bar).toHaveAttribute('data-kept', '1')
  await expect(page.locator('[data-testid="route-leg"][data-pending]')).toHaveCount(0)

  // A SECOND STOP, from the first: tried city by city until the server calls the leg open
  let kept2 = false
  for (const c of await namedCities(page)) {
    if (c.code === first!.code) continue
    if ((await tapCity(page, c)) === 'open') {
      await page.getByTestId('route-confirm').click()
      kept2 = true
      break
    }
  }
  expect(kept2, 'no second named city has an open leg from the first').toBe(true)
  await expect(bar).toHaveAttribute('data-kept', '2')
  await expect(page.getByTestId('route-leg')).toHaveCount(2)

  // THE BAR NEVER MOVED while stops were added and taken away (the owner's law: a press never re-flows)
  const box2 = await bar.boundingBox()
  expect(box2, 'the route bar moved or changed height when a stop was added').toEqual(box0)
  // nothing scrolls sideways
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.screenshot({ path: `test-results/route-builder-${label}.png` })

  // FINAL: the two SAILs are queued; route mode ends and her queue is drawn as numbered stops
  await page.getByTestId('route-final').click()
  await expect(bar).toHaveCount(0, { timeout: 60_000 })
  await expect(page.getByTestId('map-detail-tray')).toBeVisible()
  await expect(page.locator('[data-testid="map-path-stop"]').first()).toBeVisible({ timeout: 60_000 })
  expect(await page.locator('[data-testid="map-path-stop"]').count()).toBeGreaterThanOrEqual(1)
  await page.screenshot({ path: `test-results/route-builder-${label}-final.png` })

  // OUT OF ROUTE MODE, A CITY TAP SELECTS AS BEFORE: the city tray opens with its name
  await page.getByTestId('map-detail-tray').getByTestId('tray-close').click()
  await expect(page.getByTestId('map-detail-tray')).toHaveCount(0)
  const again = (await namedCities(page))[0]
  await page.mouse.click(again.x, again.y)
  await expect(page.getByTestId('map-place-name')).toBeVisible()
}

for (const [label, viewport] of [
  ['390', { width: 390, height: 844 }],
  ['1280', { width: 1280, height: 800 }],
] as const) {
  test.describe(`the route builder at ${label}`, () => {
    test.use({ viewport, deviceScaleFactor: 2 })
    test.setTimeout(600_000)
    test(`Set route, tap, Undo, Confirm twice, Final — at ${label}`, async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run build && npx vite preview\``)
      await drive(page, label)
    })
  })
}

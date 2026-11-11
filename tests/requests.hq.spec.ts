import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { openCityFace } from './desk.fixture'
import { openCityPanel } from './openCity.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// "REQUESTS" MEANT TWO THINGS (remaster S7, 2026-11-11; owner rows 279, 293)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Trade > City > Requests drew the harbour's delivery jobs; HQ > Market > Requests drew only the
// player's OWN request, so a new player never found the jobs. Now the HQ tab and the Map's port tray
// draw the SAME RequestBoard under "City requests", and the player's own "New request" stands
// beneath, under its own heading "Your orders". Run it: npm run build && npx vite preview --port 4291,
// then PLAYWRIGHT_BASE_URL=http://localhost:4291/byeharu-voyage/ npx playwright test requests.hq.spec.ts

const ROW = '[data-testid="request-row"]'

/** Name, served prices, quantity, budget and the time in seconds of every job row on screen. */
async function jobs(page: Page) {
  await expect(page.locator(ROW).first()).toBeVisible({ timeout: 60_000 })
  return page.locator(ROW).evaluateAll((rows) =>
    rows.map((r) => {
      const e = r as HTMLElement
      const txt = (s: string) => (r.querySelector(`[data-testid="${s}"]`) as HTMLElement | null)?.innerText.replace(/\s+/g, ' ').trim() ?? ''
      const m = /(?:(\d+):)?(\d+):(\d\d)$/.exec(txt('request-time'))
      return {
        name: (e.innerText.split('\n')[0] ?? '').trim(),
        each: e.dataset.priceEach,
        bonus: e.dataset.bonus,
        want: txt('request-want').replace(/ · Held.*/, ''),
        budget: txt('request-budget'),
        secs: m ? Number(m[1] ?? 0) * 3600 + Number(m[2]) * 60 + Number(m[3]) : NaN,
      }
    }),
  )
}

type Job = Awaited<ReturnType<typeof jobs>>[number]
// A young world winds more jobs onto the board as it is read (0087), so a later face may list MORE
// jobs than Trade did; what must hold is that every job Trade showed stands there, figure for figure.
const same = (a: Job[], b: Job[], what: string) => {
  for (const j of a) {
    const found = b.find((x) => x.name === j.name && x.each === j.each && x.bonus === j.bonus && x.want === j.want && x.budget === j.budget)
    expect(found, `${what}: Trade's "${j.name}" job is missing or differs`).toBeTruthy()
    expect(Math.abs(found!.secs - j.secs), `${what}: time left differs`).toBeLessThan(180)
  }
}

for (const size of [{ width: 1280, height: 800 }, { width: 390, height: 844 }]) {
  test(`at ${size.width}: HQ Requests and the Map tray show the same city jobs as Trade, and New request keeps its own heading`, async ({ page, request, baseURL }) => {
    test.setTimeout(900_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(size)

    // Trade > City > Requests: the reference
    await page.goto('command')
    await ready(page)
    await openCityFace(page)
    await page.getByRole('tablist', { name: 'Trade faces' }).getByRole('tab', { name: /^Requests$/ }).click()
    const trade = await jobs(page)
    expect(trade[0].each, 'no reward on the job').toBeTruthy()
    expect(trade[0].secs, 'no timer on the job').toBeGreaterThan(0)

    // HQ > Market > Requests
    await page.goto('city')
    await ready(page)
    await expect(page.getByTestId('city-building-market')).toBeVisible({ timeout: 120_000 })
    await page.getByTestId('city-building-market').click()
    await page.getByRole('tab', { name: /^(Requests|요청)$/ }).click()
    const panel = page.getByTestId('city-market-requests')
    await expect(panel).toBeVisible({ timeout: 60_000 })
    same(trade, await jobs(page), 'HQ')
    const jobsHead = page.getByTestId('city-jobs-heading')
    const ownHead = page.getByTestId('city-own-heading')
    await expect(jobsHead).toHaveText('City requests')
    await expect(ownHead).toHaveText('Your orders')
    const newReq = page.getByTestId('city-request-new')
    await expect(newReq, 'New request is gone').toBeVisible()
    const y = async (l: ReturnType<Page['locator']>) => (await l.boundingBox())!.y
    expect(await y(jobsHead)).toBeLessThan(await y(page.locator(ROW).first()))
    expect(await y(page.locator(ROW).last())).toBeLessThan(await y(ownHead))
    expect(await y(ownHead)).toBeLessThan(await y(newReq))
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'sideways scroll').toBe(true)

    // Map port tray
    await page.goto('map')
    await ready(page)
    await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
    await openCityPanel(page, 'LIS', 'Lisbon')
    await page.getByTestId('map-city-tabs').getByRole('tab', { name: /^Market$/ }).click()
    await page.getByTestId('map-city-market').getByRole('tab', { name: /^Requests$/ }).click()
    same(trade, await jobs(page), 'Map')
  })
}

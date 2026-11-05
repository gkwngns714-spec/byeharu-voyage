import { test, expect } from '@playwright/test'
import { ready, reachable, PHONE } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY PAGE IS LIVE LIKE STATS (owner, 2026-11-05: "the HQ, city hall, population and gold
// change, can it be live like stats?"). `world.town_hall(port)` feeds the HQ header (gold,
// population, status) and the Town Hall panel. It is asked through the ONE live hook
// (src/live/liveRead.ts): once on mount, then every second while the page is mounted, ONE ask for
// both faces, nothing while the document is hidden, never stacked, and the figures change in place.
//
// Measured on the running app through the rpc debug line (`[rpc] world.town_hall(...)`), the same
// counter tests/cache.once.spec.ts uses.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ viewport: PHONE })

test('the City page asks town_hall once a second, in place, and stops while hidden', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)

  await page.addInitScript(() => {
    const log: number[] = []
    const debug = console.debug.bind(console)
    console.debug = (...args: unknown[]) => {
      if (args[0] === '[rpc]' && typeof args[1] === 'string' && args[1].startsWith('world.town_hall')) log.push(performance.now())
      debug(...args)
    }
    ;(window as unknown as { __hallAsks: number[] }).__hallAsks = log
  })

  await page.goto('command')
  await ready(page)
  await page.getByRole('tab', { name: 'City', exact: true }).click()
  await page.getByTestId('desk-city-open').click()
  await expect(page).toHaveURL(/\/city\?port=[A-Z]{3}/)
  await ready(page)
  await expect(page.getByTestId('city-gold')).toContainText(/\d/, { timeout: 60_000 })
  await expect(page.getByTestId('city-population')).toHaveAttribute('data-population', /^\d+$/)

  // the figures are DOM nodes that stay: a live update changes their text, never replaces them
  await page.evaluate(() => {
    for (const id of ['city-gold', 'city-population', 'city-status']) {
      ;(document.querySelector(`[data-testid="${id}"]`) as HTMLElement).dataset.mark = 'kept'
    }
  })

  const asks = () => page.evaluate(() => (window as unknown as { __hallAsks: number[] }).__hallAsks.length)

  // ── ASKS A SECOND: one open page, 8 s, no command ──
  const a0 = await asks()
  await page.waitForTimeout(8_000)
  const rate = ((await asks()) - a0) / 8
  console.log(`town_hall asks a second on the open City page: ${rate.toFixed(2)}`)
  expect(rate, 'the City page does not re-ask town_hall every second').toBeGreaterThanOrEqual(0.7)
  expect(rate, 'the City page asks town_hall more than once a second (two pollers?)').toBeLessThanOrEqual(1.3)

  // ── A HIDDEN DOCUMENT ASKS NOTHING ──
  const hide = (state: 'hidden' | 'visible') =>
    page.evaluate((s) => {
      Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => s })
      document.dispatchEvent(new Event('visibilitychange'))
    }, state)
  await hide('hidden')
  await page.waitForTimeout(1_500) // an ask already on the wire may land
  const h0 = await asks()
  await page.waitForTimeout(4_000)
  expect(await asks() - h0, 'town_hall is asked while the document is hidden').toBe(0)
  await hide('visible')
  await expect.poll(asks, { timeout: 10_000 }).toBeGreaterThan(h0)

  // ── NOTHING WAS REPLACED: the figures updated in place ──
  for (const id of ['city-gold', 'city-population', 'city-status']) {
    await expect(page.getByTestId(id), `${id} was re-created by an update`).toHaveAttribute('data-mark', 'kept')
  }
})

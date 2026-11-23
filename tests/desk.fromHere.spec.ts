import { test, expect } from '@playwright/test'
import { PHONE, ready, reachable } from './appReady.fixture'

// THE "FROM HERE" LINE (roadmap 2026-11-23 slice 4, the client half) AND THE ROUTES TAB FOLDED IN (X3).
//
//   1. Where she lies, the desk names the best sale to each of up to three harbours: one tile a harbour, each the profit of a goods
//      card that sells there (the same served figure, world.best_sales), and the best of that harbour's cards. On a phone the
//      tiles stand on one 44-px line; a tile that does not fit gives way whole (hidden), never cut.
//   2. A tile pressed is its card pressed: the trip opens, sold at that harbour, and the tile is lit.
//   3. X3: the Menu has no Routes; an old /routes link opens the Trade desk; the world's lanes stand at /lanes, behind a row on
//      Stats > Markets, with the Stats cell lit there.

test.beforeEach(async ({ request, baseURL }) => {
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
})

for (const size of [PHONE, { width: 1280, height: 800 }]) {
  test(`From here at ${size.width}: the best card per harbour, pressed opens its trip`, async ({ page }) => {
    await page.setViewportSize(size)
    await page.goto('command')
    await ready(page)
    const line = page.getByTestId('from-here')
    await expect(line).toBeVisible({ timeout: 90_000 })
    // the cards' own sales, as served: each harbour's best profit
    await expect(page.locator('[data-testid="best-sale"][data-state="sale"]').first()).toBeVisible({ timeout: 60_000 })
    const cards = await page.locator('[data-testid="best-sale"][data-state="sale"][data-pays="true"]').evaluateAll((els) =>
      els.map((e) => ({ port: e.getAttribute('data-port') ?? '', profit: Number(e.getAttribute('data-profit')), near: e.getAttribute('data-near') })),
    )
    const best = new Map<string, number>()
    for (const c of cards) if (c.near !== 'false' && c.profit > 0) best.set(c.port, Math.max(best.get(c.port) ?? 0, c.profit))

    const tiles = await page.getByTestId('from-here-tile').evaluateAll((els) =>
      els.map((e) => ({ port: e.getAttribute('data-port') ?? '', profit: Number(e.getAttribute('data-profit')), gone: e.hasAttribute('data-gave-way'), h: e.getBoundingClientRect().height })),
    )
    expect(tiles.length, 'the line names one to three harbours').toBeGreaterThanOrEqual(1)
    expect(tiles.length).toBeLessThanOrEqual(3)
    expect(new Set(tiles.map((x) => x.port)).size, 'a harbour stands once').toBe(tiles.length)
    for (const x of tiles) expect(x.profit, `${x.port}: the tile's profit is that harbour's best card`).toBe(best.get(x.port))
    // the three that pay most of the harbours the cards name
    const top = [...best.values()].sort((a, b) => b - a).slice(0, 3)
    expect(tiles.map((x) => x.profit).sort((a, b) => b - a)).toEqual(top)

    if (size.width < 1024) {
      // ONE LINE: the row is 44 px and every tile still seen stands on it, whole
      const box = (await page.getByTestId('from-here-tiles').boundingBox())!
      expect(Math.round(box.height)).toBe(44)
      const seen = page.locator('[data-testid="from-here-tile"]:not([data-gave-way])')
      expect(await seen.count(), 'at least the nearest tile stands').toBeGreaterThanOrEqual(1)
      for (const el of await seen.all()) {
        const r = (await el.boundingBox())!
        expect(r.y, 'a seen tile stands on the line').toBeGreaterThanOrEqual(box.y - 1)
        expect(r.y + r.height, 'a seen tile stands on the line').toBeLessThanOrEqual(box.y + box.height + 1)
        const cut = await el.evaluate((e) => [...e.querySelectorAll('span')].some((s) => s.scrollWidth > s.clientWidth + 1))
        expect(cut, 'a name or a profit is cut').toBe(false)
      }
    }

    // A TILE PRESSED IS ITS CARD PRESSED: the trip, sold there
    const first = page.locator('[data-testid="from-here-tile"]:not([data-gave-way])').first()
    const port = (await first.getAttribute('data-port'))!
    await first.click()
    await expect(page.locator(`[data-testid="trade-sale-choice"][data-port="${port}"][data-on="true"]`)).toBeVisible({ timeout: 60_000 })
    await expect(first).toHaveAttribute('aria-pressed', 'true')
  })
}

test('X3: no Routes in the Menu; /routes opens the desk; the lanes stand behind Stats > Markets', async ({ page }) => {
  await page.setViewportSize(PHONE)
  await page.goto('routes')
  await ready(page)
  await expect(page).toHaveURL(/\/command$/)

  await page.getByTestId('nav-cell-cabin').click()
  await expect(page.getByRole('link', { name: /^Routes$/ })).toHaveCount(0)
  await page.keyboard.press('Escape')

  await page.goto('stats?face=markets')
  await ready(page)
  const door = page.getByTestId('stats-lanes-row')
  await expect(door).toBeVisible({ timeout: 60_000 })
  await door.click()
  await expect(page).toHaveURL(/\/lanes$/)
  await expect(page.getByTestId('routes')).toBeVisible()
  await expect(page.getByTestId('routes-list')).toBeVisible({ timeout: 60_000 })
})

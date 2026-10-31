import { test, expect } from '@playwright/test'
import { closeDetail, openDetail, ready, reachable } from './appReady.fixture'
import { buyHere, closeTradeMap, findCarry, openTradeMap } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PLAN'S MINI ROUTE MAP — now a POP-UP PAGE (owner, 2026-10-31). The compact Trade face carries
// one summary row for the map; a press opens the map's page where the plan's stops and legs are
// drawn (no pan, no zoom). Cargo and Orders are pages too: a sell row is chosen on the cargo page,
// the SAIL lines are read on the orders page. Both sizes.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

for (const size of SIZES) {
  test.describe(`the plan's mini route map at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test("the plan's map page draws its stops and legs; the SAIL lines queue", async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const face = page.getByTestId('desk-trade')

      // A GOOD ABOARD, bought where she lies (chips, not the map).
      const { code, home } = await findCarry(page)
      await buyHere(page, code)

      const cargoBlock = () =>
        page.getByTestId('cargo-best').locator(`[data-testid="cargo-good"][data-good="${code}"]`).locator(`[data-testid="cargo-place"]:not([data-port="${home}"])`)
      const panel = page.getByTestId('good-detail')
      const act = page.getByTestId('trade-act')

      // THE CARGO PAGE: choose the first sell row; the panel behind takes the city.
      await openDetail(page, 'cargo-open')
      await expect(cargoBlock().first()).toBeVisible({ timeout: 120_000 })
      const to0 = (await cargoBlock().first().getAttribute('data-port'))!
      await cargoBlock().first().click()
      await closeDetail(page)
      await expect(panel).toHaveAttribute('data-city', to0)

      // THE MAP PAGE: the plan's stops only, still, no zoom controls.
      await openTradeMap(face)
      const map = face.getByTestId('trade-map')
      const chart = map.getByTestId('small-chart')
      const legs = map.getByTestId('plan-leg')
      await expect(legs.first()).toBeVisible({ timeout: 60_000 })
      const stops = [...new Set((await legs.evaluateAll((es) => es.map((e) => e.getAttribute('data-to') ?? ''))).filter(Boolean))]
      expect(stops.length, 'the plan has no stops').toBeGreaterThan(0)
      expect(stops, 'the pressed city is not a stop of the plan').toContain(to0)
      await expect(map).toHaveAttribute('data-cities', stops.join(' '))
      const drawn = [...new Set(await chart.locator('[data-port-code]').evaluateAll((es) => es.map((e) => e.getAttribute('data-port-code') ?? '')))]
      expect(drawn.length, 'the plan map draws no stop').toBeGreaterThan(0)
      for (const c of drawn) expect(stops, `${c} is drawn and is not a stop of the plan`).toContain(c)
      expect(drawn.sort(), 'a stop of the plan is missing from its map').toEqual([...stops].sort())
      // STILL: the plan's chart wears no zoom column (row 191: no pan, no zoom)
      await expect(chart.getByTestId('small-chart-controls')).toHaveCount(0)
      const box0 = await chart.boundingBox()
      await closeTradeMap(face)

      // A SECOND SELL ROW: the plan updates; the map page's frame keeps its size.
      await openDetail(page, 'cargo-open')
      await expect(cargoBlock().nth(1)).toBeVisible({ timeout: 60_000 })
      const to1 = (await cargoBlock().nth(1).getAttribute('data-port'))!
      await cargoBlock().nth(1).click()
      await closeDetail(page)
      await expect(panel).toHaveAttribute('data-city', to1)
      await openTradeMap(face)
      const box1 = await face.getByTestId('trade-map').getByTestId('small-chart').boundingBox()
      expect({ w: Math.round(box1!.width), h: Math.round(box1!.height) }, 'the map page frame resized between two plans').toEqual({
        w: Math.round(box0!.width),
        h: Math.round(box0!.height),
      })
      await closeTradeMap(face)

      // A READY TRIP: walk the cargo rows, remember the longest ready passage.
      let best: { i: number; days: number } | null = null
      // six probes at most; the row count is read INSIDE the cargo page below (the page is closed here)
      const tries = 6
      for (let i = 0; i < tries; i++) {
        await openDetail(page, 'cargo-open')
        if ((await cargoBlock().nth(i).count()) === 0) {
          await closeDetail(page)
          break
        }
        const days = Number.parseFloat((await cargoBlock().nth(i).getByTestId('cargo-place-days').innerText()).replace(',', '.')) || 0
        await cargoBlock().nth(i).click()
        await closeDetail(page)
        await expect(act).toHaveText(/Sail & sell|Too far|Cargo full|Shut|No money/, { timeout: 60_000 })
        if ((await act.innerText()).trim() === 'Sail & sell' && (await act.isEnabled())) {
          if (!best || days > best.days) best = { i, days }
        }
      }
      expect(best, 'no sell row made a trip ready to sail').not.toBeNull()

      // Choose the longest, read its legs on the map page, then SEND.
      await openDetail(page, 'cargo-open')
      await cargoBlock().nth(best!.i).click()
      await closeDetail(page)
      await expect(act).toHaveText(/^Sail & sell$/, { timeout: 60_000 })
      await expect(act).toBeEnabled()
      await openTradeMap(face)
      const sailLines = await face.getByTestId('trade-map').getByTestId('plan-leg').count()
      expect(sailLines, 'the plan has no leg line').toBeGreaterThan(0)
      await closeTradeMap(face)
      await act.click()
      await expect(page.getByTestId('trade-toast')).toContainText('Sailing to', { timeout: 60_000 })

      // THE ORDERS PAGE: the SAIL lines queued (queued SAILs + the passage under way) equal the legs.
      await openDetail(page, 'command-queue')
      await expect
        .poll(
          async () =>
            (await page.getByTestId('queue-row').allInnerTexts()).filter((t) => /^\s*Sail\b/i.test(t)).length +
            (await page.getByTestId('queue-passage').count()),
          { timeout: 90_000, message: `${sailLines} legs, so ${sailLines} SAIL lines (queued SAILs + the passage under way)` },
        )
        .toBe(sailLines)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}

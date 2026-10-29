import { test, expect, type Locator } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { pressCity } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// SELL OPENS ON HER CARGO, A CITY PRESSED IS A CITY GONE TO, AND EVERY CITY SHE CAN SELL AT PRESSES (owner row 231,
// 2026-10-26: *"the command, sell tab is not good enough, i can't sell because i can't dock. and i can't move to that
// location. buying and selling when pressed a city, move the map to that location. make the sell tab more
// convenient. come on!"*). A new company docked at Lisbon, in the in-tab (PGlite) world, desktop and phone:
//   · Buy one good at Lisbon; Sell opens with "Your cargo": that good, a "Here" row and the best cities to sail to,
//     each with a figure; one press on a city row opens THAT city and THAT good with "Sail & sell";
//   · a city pressed (chip strip, Buy and Sell) glides the map until the city sits in its middle;
//   · the near cities: none reads "No buyer" for what she carries (a quay that does not list the good is still bid
//     for — before row 231 every such card was greyed and would not press, the owner's "i can't move there");
//   · "Here" → Sell, all aboard, ONE press: sold, the hold empty.
// The owner's exact case (Banda Aceh, camphor, purse 0, credit lit) is tests/rpc.sellAnywhere.spec.ts.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ locale: 'en-US' })

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

/** The city's mark sits in the middle of the map, east-west (the glide has landed; the sheet wraps, so even the whole
 *  world turns to it), and on the glass north-south (as near the middle as the sheet's edge allows). */
async function expectCentred(map: Locator, code: string) {
  await expect
    .poll(
      async () => {
        const chart = await map.getByTestId('small-chart').boundingBox()
        const mark = await map.locator(`[data-port-code="${code}"]`).first().boundingBox()
        if (!chart || !mark) return Infinity
        const dx = mark.x + mark.width / 2 - (chart.x + chart.width / 2)
        const y = mark.y + mark.height / 2
        return y < chart.y || y > chart.y + chart.height ? Infinity : Math.round(Math.abs(dx))
      },
      { timeout: 10_000, message: `${code} glides to the middle of the map` },
    )
    .toBeLessThan(8)
}

for (const size of SIZES) {
  test.describe(`Sell cargo at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('Sell opens on her cargo, a city press moves the map, every near city bids, and Here sells all in one press', async ({
      page,
      request,
      baseURL,
    }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const faces = page.getByRole('tablist', { name: 'Desk faces' })

      // BUY ONE GOOD AT LISBON
      await faces.getByRole('tab', { name: 'Buy', exact: true }).click()
      const buy = page.getByTestId('desk-buy')
      await pressCity(page, buy.getByTestId('trade-map'), 'LIS')
      const card = buy.locator('[data-testid="city-good"]:not([disabled])').first()
      await expect(card).toBeVisible({ timeout: 120_000 })
      const code = (await card.getAttribute('data-good'))!
      await card.click()
      const panel = page.getByTestId('good-detail')
      await expect(panel.getByTestId('stepper-figure')).toBeVisible({ timeout: 60_000 })
      await panel.getByTestId('stepper-figure').fill('1')
      await panel.getByTestId('stepper-figure').press('Enter')
      const act = page.getByTestId('trade-act')
      await expect(act).toBeEnabled({ timeout: 60_000 })
      await act.click()
      await expect(page.getByTestId('trade-toast')).toContainText(/^Bought 1 /, { timeout: 60_000 })

      // A CITY PRESSED ON BUY: the map glides to it
      const buyChip = buy.getByTestId('city-chip').nth(2)
      const buyCity = (await buyChip.getAttribute('data-port'))!
      await buyChip.click()
      await expectCentred(buy.getByTestId('trade-map'), buyCity)

      // SELL OPENS ON HER CARGO: the good, "Here", and the cities to sail to, each with a figure
      await faces.getByRole('tab', { name: 'Sell', exact: true }).click()
      const sell = page.getByTestId('desk-sell')
      const cargo = sell.getByTestId('cargo-best')
      await expect(cargo).toBeVisible()
      const block = cargo.locator(`[data-testid="cargo-good"][data-good="${code}"]`)
      await expect(block).toBeVisible()
      const places = block.getByTestId('cargo-place')
      await expect(places.first()).toBeVisible({ timeout: 120_000 })
      await expect(block.locator('[data-testid="cargo-place"][data-port="LIS"]')).toContainText('Here')
      for (const p of await places.all()) await expect(p.getByTestId('cargo-place-price')).toHaveText(/\d/)
      // 0251: THE NEAR CITIES ARE PRICED — the board prices the nearest she can sail to as well as the dearest, so the
      // list holds a city within a few days of Lisbon (not only the dearest, a month away), with a profit
      await expect
        .poll(async () => {
          const days = await block.locator('[data-testid="cargo-place"]:not([data-port="LIS"]) [data-testid="cargo-place-days"]').allTextContents()
          return days.map((d) => parseFloat(d.replace(',', '.'))).filter((d) => Number.isFinite(d) && d < 5).length
        }, { timeout: 60_000, message: 'a near city (under 5 days) is on the cargo list' })
        .toBeGreaterThan(0)

      // one press on a city row: that city and that good, "Sail & sell", the map at the city
      const away = block.locator('[data-testid="cargo-place"]:not([data-port="LIS"])').first()
      if ((await away.count()) > 0) {
        const to = (await away.getAttribute('data-port'))!
        await away.click()
        await expect(away).toHaveAttribute('aria-pressed', 'true')
        await expect(sell.getByTestId('city-goods')).toHaveAttribute('data-city', to)
        await expect(panel).toHaveAttribute('data-city', to)
        await expect(panel).toHaveAttribute('data-good', code)
        await expect(act).toHaveAttribute('data-act', 'sail-sell')
        await expect(act).toHaveText(/Sail & sell|Too far|Cargo full|Shut|No money/, { timeout: 60_000 })
        // a button that will not press says why, in a sentence
        if (!(await act.isEnabled())) await expect(panel.getByTestId('trade-why').or(panel.getByRole('note'))).toBeVisible()
        // ROW 191: on the plan's map the pressed city is a STOP, drawn — the plan's view is static (no glide)
        await expect(sell.getByTestId('trade-map').locator(`[data-port-code="${to}"]`).first()).toBeAttached({ timeout: 30_000 })
        // closed (the panel lets the good go)
        await panel.getByTestId('tray-close').click()
        await expect(panel).toHaveCount(0)
      }

      // THE NEAR CITIES: what she carries is bid for at every one (no "No buyer" where the quay lists no row)
      const chips = sell.getByTestId('city-chip')
      const near = (await chips.evaluateAll((es) => es.map((e) => e.getAttribute('data-port') ?? ''))).filter((c) => c && c !== 'LIS')
      expect(near.length).toBeGreaterThan(3)
      const board = sell.getByTestId('city-goods')
      for (const c of near.slice(0, 5)) {
        await sell.locator(`[data-testid="city-chip"][data-port="${c}"]`).click()
        await expect(board).toHaveAttribute('data-city', c)
        await expect(board).toHaveAttribute('data-docked', 'false')
        const mine = board.locator(`[data-testid="city-good"][data-good="${code}"]`)
        await expect(mine.getByTestId('city-good-price'), `${c} bids for ${code}`).toHaveText(/\d/, { timeout: 60_000 })
        await expect(mine).toBeEnabled()
      }
      // the last one pressed: the map glides to it; its card opens Sail & sell
      const last = near[Math.min(4, near.length - 1)]
      await expectCentred(sell.getByTestId('trade-map'), last)
      await board.locator(`[data-testid="city-good"][data-good="${code}"]`).click()
      await expect(panel).toHaveAttribute('data-city', last)
      await expect(act).toHaveAttribute('data-act', 'sail-sell')
      await panel.getByTestId('tray-close').click()
      await expect(panel).toHaveCount(0)

      // HERE: Sell, all aboard, one press
      await block.locator('[data-testid="cargo-place"][data-port="LIS"]').click()
      await expect(panel).toHaveAttribute('data-city', 'LIS')
      await expect(act).toHaveAttribute('data-act', 'sell')
      await expect(panel.getByTestId('stepper-figure')).toHaveValue('1')
      await expect(act).toBeEnabled({ timeout: 60_000 })
      await act.click()
      await expect(page.getByTestId('trade-toast')).toContainText(/^Sold 1 /, { timeout: 60_000 })
      await expect(cargo.getByTestId('cargo-best-empty')).toBeVisible({ timeout: 60_000 })

      // no sideways scroll
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}

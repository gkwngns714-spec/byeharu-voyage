import { test, expect, type Locator } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PLAN'S MINI ROUTE MAP (owner row 191; docs/COMMAND_REDESIGN.md §3) — on a local build, at the
// owner's desktop (1440×900) and the phone (390×844):
//   · the plan's chart draws THE STOPS ONLY, numbered: every harbour on it is a stop of the plan;
//   · the chart is STILL: no zoom column, no pan/zoom surface;
//   · pressing a second sell row moves neither the map box nor the card (a press selects);
//   · the leg lines under the map are the trip's SAIL lines: one line per leg, and Go queues exactly
//     that many SAIL orders.
// Nothing here asserts a price: presence, membership, geometry and counts are the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

test.use({ locale: 'en-US' })

/** An element's LAYOUT box: where it stands in its offset parent, and its size. A press may scroll a
 *  row into reach; a scroll is not a move, so the viewport rect is not what this measures. */
async function layoutBox(l: Locator) {
  return l.evaluate((e) => {
    const el = e as HTMLElement
    const r = el.getBoundingClientRect()
    return {
      x: Math.round(el.offsetLeft * 10) / 10,
      y: Math.round(el.offsetTop * 10) / 10,
      w: Math.round(r.width * 10) / 10,
      h: Math.round(r.height * 10) / 10,
    }
  })
}

/** An element's box on the glass — the card is fixed (phone) or fills a pane (wide), so this is its place. */
async function screenBox(l: Locator) {
  return l.evaluate((e) => {
    const r = (e as HTMLElement).getBoundingClientRect()
    return { x: Math.round(r.x * 10) / 10, y: Math.round(r.y * 10) / 10, w: Math.round(r.width * 10) / 10, h: Math.round(r.height * 10) / 10 }
  })
}

for (const size of SIZES) {
  test.describe(`the plan's mini route map at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('the plan draws its stops only, still; a second sell row moves nothing; the legs are the SAIL lines', async ({
      page,
      request,
      baseURL,
    }) => {
      test.setTimeout(600_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const faces = page.getByRole('tablist', { name: 'Desk faces' })

      // A GOOD ABOARD, bought where she lies — Sell opens on her cargo, and its rows make the trips
      await faces.getByRole('tab', { name: 'Buy', exact: true }).click()
      const buy = page.getByTestId('desk-buy')
      const buyBoard = buy.getByTestId('city-goods')
      const home = (await buy.getByTestId('city-chip').first().getAttribute('data-port'))!
      await buy.getByTestId('city-chip').first().click()
      await expect(buyBoard).toHaveAttribute('data-city', home)
      const good = buy.locator('[data-testid="city-good"]:not([disabled])').first()
      await expect(good).toBeVisible({ timeout: 120_000 })
      const code = (await good.getAttribute('data-good'))!
      await good.click()
      const panel = page.getByTestId('good-detail')
      await expect(panel.getByTestId('stepper-figure')).toBeVisible({ timeout: 60_000 })
      await panel.getByTestId('stepper-figure').fill('1')
      await panel.getByTestId('stepper-figure').press('Enter')
      const act = page.getByTestId('trade-act')
      await expect(act).toBeEnabled({ timeout: 60_000 })
      await act.click()
      await expect(page.getByTestId('trade-toast')).toContainText(/^Bought 1 /, { timeout: 60_000 })

      // SELL: her cargo, and the rows that make a trip (never "Here" — this is the plan's map that is under test)
      await faces.getByRole('tab', { name: 'Sell', exact: true }).click()
      const sell = page.getByTestId('desk-sell')
      const block = sell.locator(`[data-testid="cargo-good"][data-good="${code}"]`)
      await expect(block).toBeVisible()
      const rows = block.locator(`[data-testid="cargo-place"]:not([data-port="${home}"])`)
      await expect(rows.first()).toBeVisible({ timeout: 120_000 })
      expect(await rows.count(), 'fewer than two sell rows to press').toBeGreaterThanOrEqual(2)

      const map = sell.getByTestId('trade-map')
      const chart = map.getByTestId('small-chart')
      const legs = map.getByTestId('plan-leg')

      /** A row pressed: its city is in hand, the card is up, and the plan's mini map is drawn. */
      const pressRow = async (row: Locator) => {
        const to = (await row.getAttribute('data-port'))!
        await row.evaluate((e) => e.scrollIntoView({ block: 'start' }))
        await row.click()
        await expect(panel).toHaveAttribute('data-city', to, { timeout: 60_000 })
        await expect(legs.first()).toBeVisible({ timeout: 60_000 })
        return to
      }

      // THE FIRST SELL ROW: the plan's map is the ROUTE — its stops only
      const to0 = await pressRow(rows.first())
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

      // A SECOND SELL ROW PRESSED: the map box and the card stay exactly where they are
      const mapBefore = await layoutBox(chart)
      const cardBefore = await screenBox(panel)
      const to1 = await pressRow(rows.nth(1))
      expect(to1, 'the second row is the same city').not.toBe(to0)
      expect(await layoutBox(chart), 'pressing a sell row moved the map box').toEqual(mapBefore)
      expect(await screenBox(panel), 'pressing a sell row moved the card').toEqual(cardBefore)

      // THE LEG COUNT IS THE SAIL LINES: a ready row's plan, then Go, then the queue. THE LONGEST ready
      // passage is chosen because the queue is observable only while a voyage is under way: a next-door
      // trip lands and its SAIL line leaves the queue before the fleet read that would draw it (measured:
      // a 1-leg row to the nearest city read 0 SAIL rows for the whole 90 s). A long first leg keeps that
      // window open (measured: 4:26 still to run with 353 of 1,433 miles sailed).
      // A SAIL that has DEPARTED is `done`, and `cmd.queue` serves only pending / active / failed: that
      // one line stands as the voyage row (`queue-passage`) and the SAIL lines still queued are N − 1, so
      // their SUM is the plan's leg count (measured: 10 queued + 1 under way = 11 legs).
      let best: { i: number; days: number } | null = null
      const tries = Math.min(await rows.count(), 6)
      for (let i = 0; i < tries; i++) {
        await pressRow(rows.nth(i))
        await expect(act).toHaveText(/Sail & sell|Too far|Cargo full|Shut|No money/, { timeout: 60_000 })
        if ((await act.innerText()).trim() === 'Sail & sell' && (await act.isEnabled())) {
          const days = Number.parseFloat((await rows.nth(i).getByTestId('cargo-place-days').innerText()).replace(',', '.'))
          if (!best || (Number.isFinite(days) && days > best.days)) best = { i, days: Number.isFinite(days) ? days : 0 }
        }
      }
      if (!best) throw new Error('no sell row made a trip ready to sail')
      await pressRow(rows.nth(best.i))
      await expect(act).toHaveText(/^Sail & sell$/, { timeout: 60_000 })
      await expect(act).toBeEnabled({ timeout: 60_000 })
      const sailLines = await legs.count()
      expect(sailLines, 'the plan has no leg line').toBeGreaterThan(0)
      await act.click()
      await expect(page.getByTestId('trade-toast')).toContainText('Sailing to', { timeout: 60_000 })
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

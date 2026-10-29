import { test, expect, type Locator, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { pressCity } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE REPORT FACE — world.report (0278, docs/COMMAND_REDESIGN.md §4, R4; owner row 192: *"the profit tab on
// command, change it to report, saving all the earnings and losses by sections, points, that is saved."*).
// At the owner's desktop (1440×900) and the phone (390×844), on a local build:
//   · the face opens from the Report tab: the span chips (Day / Week / All), the total, "By section" and
//     "By place" stand;
//   · a span chip press SELECTS: the figures change in place — the total's box does not move, and nothing
//     below re-flows (the sections' first row keeps its place); the bars change with the span (1 a day / 7
//     a week);
//   · after a same-port trade through the real UI (Buy 1 aboard, Sell it back at Lisbon), the sections stand
//     with their kind lines (Trade: the buy, the sell, the tax) and the places stand with the port and
//     "Earlier" (the tax row has no event, so no point names it) — at both widths.
// Nothing here asserts a price; "a figure, not a dash" is the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ locale: 'en-US' })

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

/** The box of the total's figure on the glass — the in-place claim's measure. */
const box = (page: Page, id: string) =>
  page.getByTestId(id).first().evaluate((e) => {
    const b = e.getBoundingClientRect()
    return { top: Math.round(b.top), left: Math.round(b.left) }
  })

const openReport = async (page: Page) => {
  await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Report', exact: true }).click()
  await expect(page.getByTestId('desk-report')).toBeVisible({ timeout: 60_000 })
}

/** A same-port trade through the real UI: Buy 1 of a good Lisbon offers, then Sell it back (a flip). */
const flipAtLisbon = async (page: Page, faces: Locator) => {
  await faces.getByRole('tab', { name: 'Buy', exact: true }).click()
  const buy = page.getByTestId('desk-buy')
  await pressCity(page, buy.getByTestId('trade-map'), 'LIS')
  const goods = buy.getByTestId('city-goods')
  await expect(goods).toHaveAttribute('data-city', 'LIS')
  const card = goods.getByTestId('city-good').first()
  await expect(card).toBeVisible({ timeout: 120_000 })
  const code = (await card.getAttribute('data-good')) ?? ''
  await card.click()
  const act = page.getByTestId('trade-act')
  await expect(act).toHaveAttribute('data-act', 'buy')
  await expect(act).toBeEnabled({ timeout: 60_000 })
  await act.click()
  await expect(page.getByTestId('good-detail')).toHaveCount(0, { timeout: 60_000 })

  await faces.getByRole('tab', { name: 'Sell', exact: true }).click()
  const sell = page.getByTestId('desk-sell')
  await pressCity(page, sell.getByTestId('trade-map'), 'LIS')
  const cargo = sell.getByTestId('city-goods')
  await expect(cargo).toHaveAttribute('data-city', 'LIS')
  const mine = cargo.locator(`[data-testid="city-good"][data-good="${code}"]`)
  await expect(mine).toBeVisible({ timeout: 60_000 })
  await expect(mine.getByTestId('city-good-aboard')).toHaveText('Aboard 1', { timeout: 60_000 })
  await mine.click()
  const sellAct = page.getByTestId('trade-act')
  await expect(sellAct).toHaveAttribute('data-act', 'sell')
  await expect(sellAct).toBeEnabled({ timeout: 60_000 })
  await sellAct.click()
  await expect(page.getByTestId('good-detail')).toHaveCount(0, { timeout: 60_000 })
  return code
}

for (const size of SIZES) {
  test.describe(`the Report face at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('the span chips select and change the figures in place; sections and places stand', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const faces = page.getByRole('tablist', { name: 'Desk faces' })
      await openReport(page)
      const report = page.getByTestId('desk-report')

      // the span chips, the total, the two lists — all stand
      const spans = page.getByRole('tablist', { name: 'Report spans' })
      await expect(spans.getByRole('tab', { name: 'Day', exact: true })).toHaveAttribute('aria-selected', 'true')
      await expect(report.getByTestId('report-total')).toContainText(/\d/, { timeout: 30_000 })
      await expect(report.getByTestId('report-sections')).toBeVisible()
      await expect(report.getByTestId('report-places')).toBeVisible()

      // a span press SELECTS and changes the figures IN PLACE: the total's box and the chips' row do not
      // move; nothing below re-flows. The bars change with the span: one bar a day, seven a week.
      const totalBefore = await box(page, 'report-total')
      const spansBefore = await box(page, 'report-sections')
      expect(await report.getByTestId('report-bars').locator(':scope > div').count()).toBe(1)
      await spans.getByRole('tab', { name: 'Week', exact: true }).click()
      await expect(spans.getByRole('tab', { name: 'Week', exact: true })).toHaveAttribute('aria-selected', 'true')
      await expect
        .poll(() => report.getByTestId('report-bars').locator(':scope > div').count(), { timeout: 30_000 })
        .toBe(7)
      expect(await box(page, 'report-total')).toEqual(totalBefore)
      expect(await box(page, 'report-sections')).toEqual(spansBefore)
      await spans.getByRole('tab', { name: 'All', exact: true }).click()
      await expect(spans.getByRole('tab', { name: 'All', exact: true })).toHaveAttribute('aria-selected', 'true')
      expect(await box(page, 'report-total')).toEqual(totalBefore)
      expect(await box(page, 'report-sections')).toEqual(spansBefore)
      await expect(faces.getByRole('tab', { name: 'Report', exact: true })).toHaveAttribute('aria-selected', 'true')
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })

    test('after a same-port trade, the sections stand with their lines and the places with their rows', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const faces = page.getByRole('tablist', { name: 'Desk faces' })
      await flipAtLisbon(page, faces)
      await openReport(page)
      const report = page.getByTestId('desk-report')

      // the sections stand, each with its kind lines (Trade: the buy, the sell, and the tax row the
      // sell always writes — 0 for a losing flip)
      const sections = report.getByTestId('report-section')
      await expect(sections.first()).toBeVisible({ timeout: 60_000 })
      expect(await sections.count()).toBeGreaterThanOrEqual(1)
      const lines = report.getByTestId('report-section-line')
      await expect(lines.first()).toBeVisible()
      const kinds = await lines.evaluateAll((es) => es.map((e) => e.getAttribute('data-kind') ?? ''))
      expect(kinds).toContain('SELL')
      expect(kinds).toContain('BUY')
      expect(kinds).toContain('TAX')

      // the places stand: the port she traded at, and "Earlier" — the tax row has no event, so no
      // point names it
      const places = report.getByTestId('report-place')
      await expect(places.first()).toBeVisible()
      const placeKinds = await places.evaluateAll((es) => es.map((e) => e.getAttribute('data-place') ?? ''))
      expect(placeKinds).toContain('port')
      expect(placeKinds).toContain('earlier')

      // the total reads a figure, not a dash
      await expect(report.getByTestId('report-total')).toContainText(/\d/, { timeout: 60_000 })
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}

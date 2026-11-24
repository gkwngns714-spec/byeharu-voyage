import { test, expect, type Locator, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HQ IN PLACE (2026-11-24, docs/design/simplify-2026-11-24.md S1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-24: *"when i press HQ - city, a whole new tab shows up then i cannot go back to the previous page … i can make
// trade in HQ, or trade in trade tab. it routes to trade tab."*
//
// THE LAW: from HQ scrolled to the board, every press opens its activity IN PLACE — the URL stays `/city` — as a sheet with a visible
// back; its back arrow (or ✕), Escape and the browser's back EACH close it; and after the close HQ's scroll and its open plate are
// exactly as they were. HQ draws no City door (`city-office-city`: the second city on the Office, with no way back). Nothing scrolls
// sideways. At 390 × 844 and 1440 × 900, in English and in Korean.

const SIZES = [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
] as const
const OUT = 'test-results/hq-in-place'
const WAYS = ['arrow', 'escape', 'back'] as const
type Way = (typeof WAYS)[number]

/** What a press must leave as it was: the URL, HQ's scroll, the open plate. */
async function hqState(page: Page) {
  return {
    url: page.url(),
    scrollTop: await page.getByTestId('city-page').evaluate((el) => Math.round(el.scrollTop)),
    plate: await page.evaluate(() => document.querySelector('[data-testid="city-buildings"] [aria-pressed="true"]')?.getAttribute('data-testid') ?? null),
  }
}

/** HQ at rest: a read landing late above the press (the bridge's rate line) re-flows the page by itself; a press is read against a
 *  page that has stopped moving for a second. */
async function atRest(page: Page) {
  const height = () => page.getByTestId('city-page').evaluate((el) => el.scrollHeight)
  await expect
    .poll(
      async () => {
        const a = await height()
        await page.waitForTimeout(1000)
        return a === (await height())
      },
      { timeout: 60_000 },
    )
    .toBe(true)
}

/** The sheet's own close: a DetailPage's back arrow, else a tray's ✕. */
async function closeBy(page: Page, way: Way) {
  if (way === 'escape') await page.keyboard.press('Escape')
  else if (way === 'back') await page.goBack()
  else {
    const arrow = page.locator('[data-detail-page] [data-detail-back]')
    if ((await arrow.count()) > 0) await arrow.last().click()
    else await page.getByTestId('tray-close').last().click()
  }
  // the history entry the sheet pushed is taken back before the next press
  await page.waitForFunction(() => !((history.state as Record<string, unknown> | null)?.bvLayer))
}

/** Open a sheet by `press`, and close it each of the three ways; nothing of HQ moves. */
async function inPlace(page: Page, what: string, opener: Locator, sheet: Locator, size: { width: number }) {
  for (const way of WAYS) {
    await opener.scrollIntoViewIfNeeded()
    await atRest(page)
    const before = await hqState(page)
    await opener.click()
    await expect(sheet, `${what}: no sheet opened`).toBeVisible({ timeout: 60_000 })
    expect(page.url(), `${what}: the press left HQ`).toBe(before.url)
    const sideways = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth)
    expect(sideways, `${what} scrolls sideways`).toBe(false)
    if (way === 'arrow') await page.screenshot({ path: `${OUT}/${what}-${size.width}.png` })
    await closeBy(page, way)
    await expect(sheet, `${what}: ${way} did not close it`).toHaveCount(0)
    await page.waitForTimeout(300)
    expect(await hqState(page), `${what}: ${way} left HQ other than it was`).toEqual(before)
  }
}

for (const size of SIZES)
  for (const locale of ['en-US', 'ko-KR'] as const)
    test.describe(`${locale}`, () => {
      test.use({ locale })
      test(`HQ @${size.width} ${locale}: every press opens in place, and back, Escape and its arrow each close it with HQ as it was (S1)`, async ({
        page,
        request,
        baseURL,
      }) => {
        test.setTimeout(900_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        await page.setViewportSize(size)
        await page.goto('city')
        await ready(page)
        await expect(page.getByTestId('city-hall-figures')).toBeVisible({ timeout: 300_000 })
        await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })
        await expect(page.getByTestId('city-office-city'), 'HQ still draws the City door').toHaveCount(0)

        // FROM THE BOARD: a trade card, a hire card, a fleet row
        await page.getByTestId('hq-moves').scrollIntoViewIfNeeded()
        const trade = page.locator('[data-testid="hq-move"][data-kind="trade"]').first()
        await expect(trade, 'no trade card on the board').toBeVisible({ timeout: 120_000 })
        await inPlace(page, 'trade-card', trade, page.getByTestId('good-detail'), size)
        const hire = page.locator('[data-testid="hq-move"][data-kind="crew"]').first()
        await expect(hire, 'no hire card on the board').toBeVisible()
        await inPlace(page, 'hire-card', hire, page.getByTestId('hq-sheet-inn'), size)
        await inPlace(page, 'fleet-row', page.getByTestId('hq-fleet-press').first(), page.getByTestId('hq-sheet-fleet'), size)

        // THE DOORS: Invest and Report
        await inPlace(page, 'invest', page.getByTestId('city-office-invest'), page.getByTestId('hq-sheet-invest'), size)
        await inPlace(page, 'report', page.getByTestId('city-office-report'), page.getByTestId('hq-sheet-report'), size)

        // THE PLATES: each opens its panel where it stands (the URL unmoved); a building's own page opens over HQ
        for (const plate of ['hall', 'market', 'port', 'inn'] as const) {
          const url = page.url()
          await page.getByTestId(`city-building-${plate}`).click()
          await expect(page.getByTestId(`city-building-${plate}`)).toHaveAttribute('aria-pressed', 'true')
          expect(page.url(), `the ${plate} plate left HQ`).toBe(url)
          if (plate === 'market') {
            await expect(page.getByTestId('city-market-buy')).toBeVisible({ timeout: 60_000 })
            const buy = page.locator('[data-testid="city-market-buy"] [data-testid="trade-good"]').nth(1).getByRole('button', { name: /^(buy|사기)/i }).first()
            await inPlace(page, 'market-buy', buy, page.getByTestId('good-detail'), size)
          }
          if (plate === 'port') await inPlace(page, 'port-yard', page.getByTestId('city-port-yard'), page.getByTestId('city-port-yard-page'), size)
          if (plate === 'inn') await inPlace(page, 'inn-crew', page.getByTestId('city-inn-crew'), page.getByTestId('city-inn-page'), size)
        }
        // with a plate open (the inn), a board card's sheet leaves it open
        await expect(page.getByTestId('city-building-inn')).toHaveAttribute('aria-pressed', 'true')
        await inPlace(page, 'trade-card-on-inn', trade, page.getByTestId('good-detail'), size)
        await expect(page.getByTestId('city-building-inn')).toHaveAttribute('aria-pressed', 'true')

        // A NAVIGATION OVER A SHEET lands where it was pressed and stays there: the sheet takes no step back on its way out, and its
        // step is replaced by the new page's, so the browser's back from there is HQ (the rail stands beside a sheet from `lg`)
        if (size.width >= 1024) {
          await page.getByTestId('city-office-report').click()
          await expect(page.getByTestId('hq-sheet-report')).toBeVisible({ timeout: 60_000 })
          await page.getByTestId('nav-cell-/map').first().click()
          await expect(page).toHaveURL(/\/map$/)
          await expect(page.getByTestId('map-chart')).toBeVisible({ timeout: 120_000 })
          await page.waitForTimeout(1500)
          await expect(page, 'the map bounced back').toHaveURL(/\/map$/)
          await page.goBack()
          await expect(page).toHaveURL(/\/city/)
          await expect(page.getByTestId('city-building-grid')).toBeVisible({ timeout: 120_000 })
          await expect(page.getByTestId('hq-sheet-report')).toHaveCount(0)
        }
        // A SHEET CLOSED BY ITS ARROW, THEN A NAVIGATION AT ONCE: the navigation lands (no back left to fire after it)
        await page.getByTestId('city-office-report').scrollIntoViewIfNeeded()
        await page.getByTestId('city-office-report').click()
        await expect(page.getByTestId('hq-sheet-report')).toBeVisible({ timeout: 60_000 })
        await page.locator('[data-detail-page] [data-detail-back]').last().click()
        await page.goto('fleets')
        await expect(page).toHaveURL(/\/fleets$/)
        await expect(page.getByTestId('fleets')).toBeVisible({ timeout: 120_000 })
        await page.waitForTimeout(1500)
        await expect(page, 'the goto was bounced').toHaveURL(/\/fleets$/)
      })
    })

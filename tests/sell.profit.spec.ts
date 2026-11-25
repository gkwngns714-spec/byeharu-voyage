import { test, expect, type Page } from '@playwright/test'
import { ready } from './appReady.fixture'
import { openOfficeFace } from './desk.fixture'
import { formatPriceDelta } from '../src/lib/format'
import { translate } from '../src/lib/i18n'
import { LOCALES } from './korean.paused'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A SALE SHOWS ITS PROFIT BEFORE THE PRESS (migration 0490; docs/design/simplify-2026-11-24.md, slice S2)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-24: "when i sell, i want to see the price i bought, the price i will get, how much profit earn and such."
// A new company at Lisbon buys 204 Woollen Cloth and opens its sell face. Before the press the face shows Bought (what she paid a
// unit, the cargo's served basis, and the total), Sells for, and Profit: the sale's own dry run's `trip_net` (cmd.do_sell, rolled
// back), the ONE profit (0474) the SOLD event then tells. After the press, the figure that was shown is what her purse moved and what
// Report's Today profit moved over the buy and the sale. Your cargo's "Here" prints the same served profit. The tax, wages and dock
// fee are drawn only when not 0: a scene with all three is proof 193's (scripts/db/proofs/193_a_sale_shows_its_profit_before_the_press.sql).

const SIZES = [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
] as const
const LANGS = ([
  { locale: 'en-US', lang: 'en' },
  { locale: 'ko-KR', lang: 'ko' },
] as const).filter((l) => LOCALES.includes(l.locale))
const GOOD = 'wool-cloth'
const UNITS = 204

/** A signed figure as drawn (commas, the coin, a minus sign U+2212 or '-'), whole ducats. */
function signed(text: string): number {
  const s = text.replace(/\s/g, '')
  const n = Number(s.replace(/[^\d]/g, ''))
  return /[−-]/.test(s) ? -n : n
}

async function reportToday(page: Page, lang: 'en' | 'ko'): Promise<number> {
  await openOfficeFace(page, translate(lang, 'command.f_report'))
  const total = page.getByTestId('desk-report').getByTestId('report-total')
  await expect(total).toContainText(/\d/, { timeout: 120_000 })
  return signed(await total.innerText())
}

/** The units on the sheet's stepper (after its clamp). */
async function unitsOn(page: Page): Promise<number> {
  const n = Number((await page.getByTestId('good-detail').getByTestId('stepper-figure').inputValue()).replace(/\D/g, ''))
  expect(n, 'no units on the stepper').toBeGreaterThan(0)
  return n
}

async function purse(page: Page): Promise<number> {
  const p = page.getByTestId('purse')
  await expect(p).toContainText(/\d/, { timeout: 120_000 })
  return signed(await p.innerText())
}

for (const { locale, lang } of LANGS) {
  for (const size of SIZES) {
    test.describe(`the sell face at ${size.width}×${size.height}, ${lang}`, () => {
      test.use({ viewport: size, locale })

      test('Bought, Sells for and Profit before the press; the profit shown is the one the sale settles', async ({ page }) => {
        test.setTimeout(900_000)
        await page.goto('command')
        await ready(page)
        const r0 = await reportToday(page, lang)
        await page.goto('command')
        await ready(page)
        const p0 = await purse(page)

        // BUY 204 Woollen Cloth at Lisbon
        const board = page.getByTestId('desk-trade').getByTestId('trade-board')
        await expect(board).toHaveAttribute('data-docked', 'true', { timeout: 120_000 })
        const card = board.locator(`[data-testid="trade-good"][data-good="${GOOD}"]`)
        await expect(card).toBeVisible({ timeout: 120_000 })
        await card.getByTestId('trade-buy').click()
        const panel = page.getByTestId('good-detail')
        const act = page.getByTestId('trade-act')
        await expect(panel).toHaveAttribute('data-side', 'buy')
        await expect(panel.getByTestId('stepper-figure')).toBeVisible({ timeout: 60_000 })
        await panel.getByTestId('stepper-figure').fill(String(UNITS))
        await panel.getByTestId('stepper-figure').press('Enter')
        // 204 asked; the stepper clamps to what her hold and purse take (the served bound), and that is what she buys
        await expect(act).toBeEnabled({ timeout: 60_000 })
        const units = await unitsOn(page)
        await act.click()
        await expect(panel).toHaveCount(0, { timeout: 60_000 })
        await expect(card.getByTestId('trade-good-aboard')).toContainText(units.toLocaleString('en-US'), { timeout: 60_000 })

        // THE SELL FACE, BEFORE THE PRESS
        await card.getByTestId('trade-sell').click()
        await expect(panel).toHaveAttribute('data-side', 'sell')
        await expect(panel.getByTestId('stepper-figure')).toHaveValue(units.toLocaleString('en-US'))
        const lines = panel.getByTestId('sale-lines')
        await expect(lines).toHaveAttribute('data-profit', /^-?\d+$/, { timeout: 120_000 })
        await expect(act).toBeEnabled({ timeout: 60_000 })
        const shown = Number(await lines.getAttribute('data-profit'))
        const bought = lines.getByTestId('sale-bought')
        await expect(bought).toContainText(translate(lang, 'trade.bought'))
        await expect(lines.getByTestId('sale-sells')).toContainText(translate(lang, 'trade.sellsFor'))
        await expect(lines.getByTestId('sale-profit')).toContainText(translate(lang, 'desk.profit'))
        await expect(lines.getByTestId('sale-profit')).toContainText(formatPriceDelta(shown))
        // the pinned line by the button carries the same profit
        await expect(panel.getByTestId('trade-profit')).toContainText(formatPriceDelta(shown))
        // Bought is the cargo's served basis (FleetView.cargo_basis): Your cargo prints the same figure a unit
        const each = Number(await bought.getAttribute('data-each'))
        expect(each, 'Bought a unit is not a price').toBeGreaterThan(0)
        // nothing scrolls sideways
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)

        // SELL
        await act.click()
        await expect(panel).toHaveCount(0, { timeout: 60_000 })
        await expect(card.getByTestId('trade-good-aboard')).not.toContainText(units.toLocaleString('en-US'), { timeout: 60_000 })

        // THE FIGURE SHOWN IS THE ONE SETTLED: her purse moved it over the buy and the sale, and Report's Today profit too
        await expect.poll(() => purse(page), { timeout: 60_000 }).toBe(p0 + shown)
        expect(await reportToday(page, lang), 'Report Today moved other than the profit shown before the press').toBe(r0 + shown)
      })
    })
  }
}

test.describe('Your cargo prints Bought and Here\'s served profit', () => {
  test.use({ viewport: { width: 390, height: 844 }, locale: 'en-US' })
  test('a good aboard: Bought a unit beside it, and Here\'s profit is the sell face\'s', async ({ page }) => {
    test.setTimeout(900_000)
    await page.goto('command')
    await ready(page)
    const board = page.getByTestId('desk-trade').getByTestId('trade-board')
    const card = board.locator(`[data-testid="trade-good"][data-good="${GOOD}"]`)
    await expect(card).toBeVisible({ timeout: 120_000 })
    await card.getByTestId('trade-buy').click()
    const panel = page.getByTestId('good-detail')
    const act = page.getByTestId('trade-act')
    await expect(panel.getByTestId('stepper-figure')).toBeVisible({ timeout: 60_000 })
    await panel.getByTestId('stepper-figure').fill(String(UNITS))
    await panel.getByTestId('stepper-figure').press('Enter')
    await expect(act).toBeEnabled({ timeout: 60_000 })
    const units = await unitsOn(page)
    await act.click()
    await expect(panel).toHaveCount(0, { timeout: 60_000 })
    await expect(card.getByTestId('trade-good-aboard')).toContainText(units.toLocaleString('en-US'), { timeout: 60_000 })

    await card.getByTestId('trade-sell').click()
    const lines = panel.getByTestId('sale-lines')
    await expect(lines).toHaveAttribute('data-profit', /^-?\d+$/, { timeout: 120_000 })
    const shown = Number(await lines.getAttribute('data-profit'))
    const each = await lines.getByTestId('sale-bought').getAttribute('data-each')
    await panel.getByTestId('tray-close').click()
    await expect(panel).toHaveCount(0, { timeout: 30_000 })

    await page.getByTestId('cargo-open').click()
    const block = page.getByTestId('cargo-best').locator(`[data-testid="cargo-good"][data-good="${GOOD}"]`)
    // the same served basis: the dry run's at full precision, FleetView.cargo_basis to the hundredth
    await expect(block.getByTestId('cargo-good-bought')).toHaveAttribute('data-each', /\d/, { timeout: 120_000 })
    // rounded to the hundredth is at most half a hundredth away, the half itself included (84.175 is served as 84.18)
    const drawn = Number(await block.getByTestId('cargo-good-bought').getAttribute('data-each'))
    expect(Math.abs(drawn - Number(each)), `${drawn} is not ${each} to the hundredth`).toBeLessThanOrEqual(0.005 + 1e-9)
    const home = (await board.getAttribute('data-city'))!
    await expect(block.locator(`[data-testid="cargo-place"][data-port="${home}"]`).getByTestId('cargo-place-profit')).toHaveText(formatPriceDelta(shown), {
      timeout: 120_000,
    })
  })
})

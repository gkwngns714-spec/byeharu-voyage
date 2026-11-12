import { test, expect, type Locator } from '@playwright/test'
import { ready } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// EVERY CARD NAMES ITS BEST SALE (0348, owner row 307 — the remaster: "make it playable, make it fun").
// The playtest: to learn which good pays where, a player pressed 8 city chips and read 10 cards each, and
// "Max" on a good locked in a loss with no warning. A NEW company docked at Lisbon, at the desktop and the
// phone:
//   · WITHOUT PRESSING A CITY CHIP, a goods card names a city and the profit (world.best_sales, one read);
//     the card is the same height before and after the line lands;
//   · pressing that line opens THE trip — bought here, sold there (data-sell-at) — whose served profit is
//     the card's figure to the coin (same row of world.good_board, same units);
//   · a good that does not pay is marked "No gain" BEFORE any buy (a nearly full hold: a few units cannot
//     carry a voyage's wages — from her own city, else from a farther one), and its Buy tray says so above the
//     units and their Max.
// 0351 (docs/SUCCESS_PLAN.md T5): A BEST SALE A NEW PLAYER CAN USE. The sale a card names is one her purse can buy, the
// best per day, and the line says how long it takes in real time; its tray's Total is the card's cost and its button is
// NOT stopped by "No money"; the dearer, farther sale is one quiet row in that tray ("Far"), pressed: the same trip
// to that city, still within her purse, with the way back ("Near").
// Nothing here asserts a price: the claim is that the card and the tray print the same served figure.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ locale: 'en-US' })

const SIZES = [
  { width: 1280, height: 900 },
  { width: 390, height: 844 },
] as const

const saleOf = (card: Locator) => card.getByTestId('best-sale')

for (const size of SIZES) {
  test.describe(`Best sale at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size, deviceScaleFactor: 2 })

    test('a card names its best sale, opens that trip at the same figure, and a loss is marked before buying', async ({ page }) => {
      test.setTimeout(600_000)
      await page.goto('command')
      await ready(page)
      await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Goods', exact: true }).click()
      const face = page.getByTestId('desk-trade')
      const board = face.getByTestId('trade-board')
      await expect(board).toBeVisible()
      const home = await board.getAttribute('data-city')
      expect(home, 'the board opens on the city she lies at').toBeTruthy()
      await expect(board).toHaveAttribute('data-docked', 'true')
      const cards = board.getByTestId('trade-good')
      await expect(cards.first()).toBeVisible({ timeout: 120_000 })

      // THE LINE HOLDS ITS HEIGHT: every card's best-sale row is there (a quiet placeholder) before it lands
      const first = cards.first()
      await expect(saleOf(first)).toHaveCount(1)
      const before = (await first.boundingBox())!.height

      // NO CHIP PRESSED: a card names a city and a profit
      const named = board.locator('[data-testid="best-sale"][data-state="sale"][data-pays="true"]')
      await expect(named.first()).toBeVisible({ timeout: 180_000 })
      expect((await first.boundingBox())!.height, 'the card grew when its best sale landed').toBe(before)
      await expect(board).toHaveAttribute('data-city', home!)
      // 0351: a card whose near sale is not its dearest (a new company's purse at Lisbon: the hop that pays, and the far city)
      const line = board.locator('[data-testid="best-sale"][data-state="sale"][data-pays="true"][data-far]').first()
      await expect(line).toBeVisible()
      const card = line.locator('xpath=ancestor::*[@data-testid="trade-good"][1]')
      const good = (await card.getAttribute('data-good'))!
      const port = (await line.getAttribute('data-port'))!
      expect(port).not.toBe(home)
      const figure = (await line.getByTestId('best-sale-profit').textContent())!.trim()
      expect(figure).toMatch(/^\+\d/)
      await expect(line).toContainText(/\p{L}/u) // the city's name
      // 0351: how long, in real time, beside the profit; what it costs, served
      await expect(line.getByTestId('best-sale-time')).toHaveText(/^·[0-9]+(s|m|h[0-9][0-9]m)$/)
      const cost = Number((await line.getAttribute('data-cost'))!)
      expect(cost).toBeGreaterThan(0)
      const far = (await line.getAttribute('data-far'))!
      expect(far).not.toBe(port)
      expect(far).not.toBe(home)

      // PRESSED: the trip — bought here, sold there — and its served profit is the card's
      await line.click()
      const panel = page.getByTestId('good-detail')
      await expect(panel).toBeVisible()
      await expect(panel).toHaveAttribute('data-good', good)
      await expect(panel).toHaveAttribute('data-side', 'buy')
      await expect(panel).toHaveAttribute('data-city', home!)
      await expect(panel).toHaveAttribute('data-sell-at', port)
      await expect(page.getByTestId('trade-act')).toHaveAttribute('data-act', 'buy-sell')
      await expect(panel.getByTestId('trade-profit')).toContainText(figure, { timeout: 120_000 })
      await expect(panel.getByTestId('stepper-figure')).toHaveValue(Number((await line.getAttribute('data-units'))!).toLocaleString('en-US'))
      // 0351: the tray's Total is the card's cost, and the trip is one she can pay for: the button is Buy & sell, not "No money"
      await expect(panel.getByTestId('good-detail-total')).toContainText(cost.toLocaleString('en-US'))
      const go = page.getByTestId('trade-act')
      await expect(go).toBeEnabled({ timeout: 120_000 })
      await expect(go).toHaveText('Buy & sell')
      // THE FAR SALE: one quiet row in the tray — pressed, the same trip to the dearer city, still within her purse; and the way back
      const other = panel.getByTestId('trade-other-sale')
      await expect(other).toHaveAttribute('data-kind', 'far')
      await expect(other).toHaveAttribute('data-port', far)
      await expect(other).toContainText('Far')
      // the row's own figure (the served far profit) is the figure the far trip's tray prints
      const farFigure = ((await other.getByTestId('trade-other-sale-figure').textContent()) ?? '').match(/\+[\d,]+/)?.[0]
      expect(farFigure, 'the far row prints its profit').toBeTruthy()
      await other.click()
      const farPanel = page.getByTestId('good-detail')
      await expect(farPanel).toHaveAttribute('data-sell-at', far)
      await expect(farPanel).toHaveAttribute('data-good', good)
      await expect(farPanel.getByTestId('trade-profit')).toContainText(farFigure!, { timeout: 120_000 })
      await expect(page.getByTestId('trade-act')).toBeEnabled({ timeout: 120_000 })
      await expect(page.getByTestId('trade-act')).toHaveText('Buy & sell')
      const back = farPanel.getByTestId('trade-other-sale')
      await expect(back).toHaveAttribute('data-kind', 'near')
      await expect(back).toHaveAttribute('data-port', port)
      await back.click()
      await expect(page.getByTestId('good-detail')).toHaveAttribute('data-sell-at', port)
      await expect(page.getByTestId('good-detail').getByTestId('trade-profit')).toContainText(figure, { timeout: 120_000 })
      // the board did not move to the sell city: the press opened a trip, it did not pick a chip
      await expect(board).toHaveAttribute('data-city', home!)

      // A LOSS, MARKED BEFORE BUYING. Fill the hold with the first good but for five units of it: what is left
      // is a few tuns, and a few units cannot carry a long voyage's wages.
      // the trip's tray closed first (on a phone it covers the board)
      await panel.getByTestId('tray-close').click()
      await expect(panel).toHaveCount(0)
      const filler = cards.first()
      await filler.getByTestId('trade-buy').click()
      const buyPanel = page.getByTestId('good-detail')
      await expect(buyPanel).toHaveAttribute('data-good', (await filler.getAttribute('data-good'))!)
      await expect(buyPanel).not.toHaveAttribute('data-sell-at', /./)
      const act = page.getByTestId('trade-act')
      await expect(act).toHaveAttribute('data-act', 'buy')
      const max = buyPanel.getByRole('button', { name: 'Max', exact: true })
      await expect(max).toBeVisible({ timeout: 60_000 })
      await max.click()
      const all = Number((await buyPanel.getByTestId('stepper-figure').inputValue()).replace(/\D/g, ''))
      expect(all).toBeGreaterThan(5)
      await buyPanel.getByTestId('stepper-figure').fill(String(all - 5))
      await buyPanel.getByTestId('stepper-figure').press('Enter')
      await expect(act).toBeEnabled({ timeout: 60_000 })
      await act.click()
      await expect(page.getByTestId('trade-toast')).toContainText(/^Bought /, { timeout: 60_000 })

      // the board re-asks for her new hold (a trade is a new question). Where a few units still pay at her own city,
      // a farther city in hand adds the sail there to the wages: the chips are pressed farthest first until one shows it.
      // (0351: a good she cannot pay for says "No money", not "No gain": it is not the loss looked for here)
      const loss = board.locator('[data-testid="best-sale"][data-pays="false"]:not([data-short])')
      const landed = board.locator('[data-testid="best-sale"]:not([data-state="wait"])')
      await expect(landed.first()).toBeVisible({ timeout: 180_000 })
      // the strip re-orders as a city is pressed (the city in hand leads), so its codes are read once, nearest first
      // (the strip stands in the board on a phone and in the desk's left pane on a wide glass: it is read off the face)
      const codes = await face.getByTestId('city-chip').evaluateAll((els) => els.map((e) => e.getAttribute('data-port') ?? ''))
      for (const code of codes.filter((c) => c !== home).reverse()) {
        if ((await loss.count()) > 0) break
        await face.locator(`[data-testid="city-chip"][data-port="${code}"]`).click()
        await expect(board).toHaveAttribute('data-city', code)
        await expect(landed.first()).toBeVisible({ timeout: 180_000 })
      }
      await expect(loss.first()).toBeVisible()
      await expect(loss.first()).toContainText('No gain')
      await expect(loss.first()).toHaveClass(/text-danger/)
      const lossCard = loss.first().locator('xpath=ancestor::*[@data-testid="trade-good"][1]')
      const lossGood = (await lossCard.getAttribute('data-good'))!

      // its Buy tray says so ABOVE the units and their Max — before anything is bought
      await lossCard.getByTestId('trade-buy').click()
      const lossPanel = page.getByTestId('good-detail')
      await expect(lossPanel).toHaveAttribute('data-good', lossGood)
      const warn = lossPanel.getByTestId('trade-no-gain')
      await expect(warn).toBeVisible({ timeout: 60_000 })
      await expect(warn).toContainText('No city you can sail to pays more than this costs.')
      const qty = lossPanel.getByTestId('trade-tray-qty').or(lossPanel.getByTestId('trade-units-none'))
      await expect(qty.first()).toBeVisible()
      expect((await warn.boundingBox())!.y).toBeLessThan((await qty.first().boundingBox())!.y)

      // no sideways scroll
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}

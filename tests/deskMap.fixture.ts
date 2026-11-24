// A CITY PRESSED ON A SMALL MAP (owner row 218) — the way a player presses it: on the harbour's NAME where
// one is drawn, else on its mark, through the chart's own tap (the picture takes no pointer; the surface under it
// does, and THE map tab's hit test answers). Never an element click.
//
// THE TRADE LIST IS HQ'S MARKET PLATE (H3 `desk-into-hq`, 2026-11-24; it was the Trade desk's board): a city chip is the city read,
// a card's Buy or Sell opens the trade sheet over HQ. The map of a fleet's orders is a page of her sheet (her HQ row's press).
// These helpers drive those; the test ids are MarketFace.tsx's and HqSheet.tsx's.
import { expect, type Locator, type Page } from '@playwright/test'
import { closeTop, openFleetSheet, openMarket } from './desk.fixture'

/** THE MAP IS A PAGE of her sheet: her HQ row pressed (unless her sheet is open), then the sheet's Map row. Returns the page
 *  (`trade-map` inside). */
export async function openTradeMap(page: Page, fleet?: string): Promise<Locator> {
  if ((await page.getByTestId('hq-sheet-fleet').count()) === 0) await openFleetSheet(page, fleet)
  await page.getByTestId('hq-sheet-fleet-map').click()
  const map = page.getByTestId('hq-sheet-fleet-map-page')
  await expect(map).toBeVisible()
  return map
}

/** Close the map's page by its back press, and her sheet under it (`sheet: false` leaves her sheet open). */
export async function closeTradeMap(page: Page, { sheet = true }: { sheet?: boolean } = {}): Promise<void> {
  await page.getByTestId('hq-sheet-fleet-map-page').locator('[data-detail-back]').first().click()
  await expect(page.getByTestId('hq-sheet-fleet-map-page')).toHaveCount(0)
  if (!sheet) return
  await closeTop(page)
  await expect(page.getByTestId('hq-sheet-fleet')).toHaveCount(0)
}

export async function pressCity(page: Page, map: Locator, code: string): Promise<void> {
  const mark = map.locator(`[data-port-code="${code}"]`).first()
  await expect(mark).toBeAttached({ timeout: 60_000 })
  await mark.evaluate((e) => e.scrollIntoView({ block: 'center' }))
  const name = map.locator(`[data-label-id="port:${code}"]`).first()
  const middle = async (l: Locator) => {
    const box = await l.boundingBox()
    return box && { x: box.x + box.width / 2, y: box.y + box.height / 2 }
  }
  // the name, if it is drawn on the glass and nothing (the zoom buttons) stands over its middle
  const open = async (p: { x: number; y: number }) =>
    map.evaluate((m, q) => {
      const hit = document.elementFromPoint(q.x, q.y)
      return !!hit && m.contains(hit) && !hit.closest('button')
    }, p)
  const centre = async () => {
    if (await name.count()) {
      const p = await middle(name)
      if (p && (await open(p))) return p
    }
    return (await middle(mark))!
  }
  let at = await centre()
  await expect
    .poll(
      async () => {
        await page.waitForTimeout(100)
        const now = await centre()
        const still = Math.abs(now.x - at.x) < 0.05 && Math.abs(now.y - at.y) < 0.05
        at = now
        return still
      },
      { message: `the map under ${code} stops moving`, timeout: 10_000 },
    )
    .toBe(true)
  await page.mouse.click(at.x, at.y)
}

/** THE NEAREST CITY SHE IS NOT AT (owner row 229): the second chip of the Market's strip (the first is HQ's own city, where she
 *  lies). Pressed; its code returned. */
export async function pressNearCity(page: Page): Promise<string> {
  const read = await openMarket(page)
  const chip = page.getByTestId('city-chip').nth(1)
  await expect(chip).toBeVisible({ timeout: 60_000 })
  const code = (await chip.getAttribute('data-port'))!
  await chip.click()
  await expect(read).toHaveAttribute('data-city', code)
  return code
}

const LIST = '[data-testid="city-market-buy"]'
const BUYABLE = `${LIST} [data-testid="trade-good"]:has([data-testid="trade-buy"]:not([disabled]))`

/** A good to BUY, pressed on the Market's list: the first card whose Buy button is live — its code. */
export async function pressFirstPricedCard(page: Page): Promise<string> {
  const card = page.locator(BUYABLE).first()
  await expect(card).toBeVisible({ timeout: 120_000 })
  const code = (await card.getAttribute('data-good'))!
  await card.getByTestId('trade-buy').click()
  return code
}

/** A GOOD TO CARRY, FOUND THE WAY A PLAYER FINDS ONE (owner row 229: no list of where to sell — press cities): on HQ's Market
 *  plate, the goods where she lies, then the harbours nearest her (the chip strip) pressed one by one until one deals in a good
 *  she can buy here — a city that sells a good buys it too (its market row has a bid).
 *  Returns the good, that city and where she lies; the list is left back on where she lies. */
export async function findCarry(page: Page, skip: readonly string[] = []): Promise<{ code: string; city: string; home: string }> {
  const read = await openMarket(page)
  const chips = page.getByTestId('city-chip')
  await expect(chips.first()).toBeVisible({ timeout: 60_000 })
  const home = (await chips.first().getAttribute('data-port'))!
  const goodsOf = async () => {
    // its buyable cards, or a list that has landed with none — a city that sells nothing is answered at once, not waited out
    await expect(page.locator(BUYABLE).first().or(page.locator(`${LIST}:not(:has([data-testid="trade-good"]))`))).toBeVisible({ timeout: 60_000 })
    return page.locator(BUYABLE).evaluateAll((es) => es.map((e) => e.getAttribute('data-good') ?? ''))
  }
  await chips.first().click()
  await expect(read).toHaveAttribute('data-city', home)
  const here = new Set(await goodsOf())
  const near = (await chips.evaluateAll((es) => es.map((e) => e.getAttribute('data-port') ?? ''))).slice(1)
  const tried = new Set<string>([home, ...skip])
  for (const city of near) {
    if (!city || tried.has(city)) continue
    tried.add(city)
    await page.locator(`[data-testid="city-chip"][data-port="${city}"]`).click()
    if (!(await expect(read).toHaveAttribute('data-city', city, { timeout: 3_000 }).then(() => true, () => false))) continue
    const there = await goodsOf().catch(() => [] as string[])
    const code = there.find((c) => here.has(c))
    if (!code) continue
    await page.locator(`[data-testid="city-chip"][data-port="${home}"]`).click()
    await expect(read).toHaveAttribute('data-city', home)
    return { code, city, home }
  }
  throw new Error('no harbour deals in a good sold where she lies')
}

/** Sell → the city → the good → Sail & sell (owner row 229). Its estimate's labels are 1–2 words (row 202). */
export async function sailAndSell(page: Page, code: string, city: string): Promise<void> {
  const read = await openMarket(page)
  await page.locator(`[data-testid="city-chip"][data-port="${city}"]`).click()
  await expect(read).toHaveAttribute('data-city', city)
  await expect(read).toHaveAttribute('data-here', 'false')
  const card = page.locator(`${LIST} [data-testid="trade-good"][data-good="${code}"]`)
  await expect(card.getByTestId('trade-good-sell')).toHaveText(/\d/, { timeout: 60_000 })
  await card.getByTestId('trade-sell').click()
  const act = page.getByTestId('trade-act')
  await expect(act).toHaveAttribute('data-act', 'sail-sell')
  await expect(act).toHaveText('Sail & sell', { timeout: 60_000 })
  for (const label of await page.getByTestId('plan-estimate').locator('.text-t-label').allInnerTexts()) {
    if (label.trim()) expect(label.trim().split(/\s+/).length, `a label is not 1–2 words: "${label}"`).toBeLessThanOrEqual(2)
  }
  await act.click()
  await expect(page.getByTestId('good-detail')).toHaveCount(0, { timeout: 60_000 })
}

/** Buy, where she lies, the good's first count (the sheet's one button). The sheet stays for the next lot, so it is closed here. */
export async function buyHere(page: Page, code: string): Promise<void> {
  await openMarket(page)
  const card = page.locator(`${LIST} [data-testid="trade-good"][data-good="${code}"]`)
  await expect(card).toBeVisible({ timeout: 60_000 })
  await card.getByTestId('trade-buy').click()
  const act = page.getByTestId('trade-act')
  await expect(act).toHaveAttribute('data-act', 'buy')
  await expect(act).toBeEnabled({ timeout: 60_000 })
  const toast = page.getByTestId('trade-toast').waitFor({ state: 'visible', timeout: 60_000 })
  await act.click()
  await toast
  await page.getByTestId('tray-close').last().click()
  await expect(page.getByTestId('good-detail')).toHaveCount(0, { timeout: 60_000 })
}

// A CITY PRESSED ON THE DESK'S SMALL MAP (owner row 218) — the way a player presses it: on the harbour's NAME where
// one is drawn, else on its mark, through the chart's own tap (the picture takes no pointer; the surface under it
// does, and THE map tab's hit test answers). Never an element click.
//
// The Trade face is ONE screen now (owner 2026-10-30: Buy and Sell are one combined list; the map is small, at the
// bottom, foldable). These helpers drive that face: a city pressed on the map or the chip strip is the city in hand,
// a card's Buy or Sell button opens the panel. The test ids below are the combined board's (TradeBoard.tsx).
import { expect, type Locator, type Page } from '@playwright/test'

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

/** THE NEAREST CITY SHE IS NOT AT (owner row 229): the second chip of the strip (the first is where she lies).
 *  Pressed; its code returned. */
export async function pressNearCity(face: Locator): Promise<string> {
  const chip = face.getByTestId('city-chip').nth(1)
  await expect(chip).toBeVisible({ timeout: 60_000 })
  const code = (await chip.getAttribute('data-port'))!
  await chip.click()
  await expect(face.getByTestId('trade-board')).toHaveAttribute('data-city', code)
  return code
}

/** A good to BUY, pressed on the combined board: the first card whose Buy button is live — its code. */
export async function pressFirstPricedCard(face: Locator): Promise<string> {
  const buyable = face.locator('[data-testid="trade-good"]:has([data-testid="trade-buy"]:not([disabled]))')
  const card = buyable.first()
  await expect(card).toBeVisible({ timeout: 120_000 })
  const code = (await card.getAttribute('data-good'))!
  await card.getByTestId('trade-buy').click()
  return code
}

/** A GOOD TO CARRY, FOUND THE WAY A PLAYER FINDS ONE (owner row 229: no list of where to sell — press cities): on the
 *  Trade face, the goods where she lies, then the harbours nearest her (the chip strip, then the map) pressed one by
 *  one until one deals in a good she can buy here — a city that sells a good buys it too (its market row has a bid).
 *  Returns the good, that city and where she lies; the face is left back on where she lies. */
export async function findCarry(page: Page, skip: readonly string[] = []): Promise<{ code: string; city: string; home: string }> {
  const face = page.getByTestId('desk-trade')
  const board = face.getByTestId('trade-board')
  const chips = face.getByTestId('city-chip')
  await expect(chips.first()).toBeVisible({ timeout: 60_000 })
  const home = (await chips.first().getAttribute('data-port'))!
  const goodsOf = async () => {
    // its buyable cards, or an empty board — a city that sells nothing is answered at once, not waited out
    await expect(face.locator('[data-testid="trade-good"]:has([data-testid="trade-buy"]:not([disabled]))').first().or(face.getByTestId('trade-board-empty'))).toBeVisible({ timeout: 60_000 })
    return face.locator('[data-testid="trade-good"]:has([data-testid="trade-buy"]:not([disabled]))').evaluateAll((es) => es.map((e) => e.getAttribute('data-good') ?? ''))
  }
  await chips.first().click()
  await expect(board).toHaveAttribute('data-city', home)
  const here = new Set(await goodsOf())
  const near = (await chips.evaluateAll((es) => es.map((e) => e.getAttribute('data-port') ?? ''))).slice(1)
  const map = face.getByTestId('trade-map')
  const all = await map.locator('[data-port-code]').evaluateAll((es) => es.map((e) => e.getAttribute('data-port-code') ?? ''))
  const tried = new Set<string>([home, ...skip])
  for (const city of [...near, ...all]) {
    if (!city || tried.has(city)) continue
    tried.add(city)
    const chip = face.locator(`[data-testid="city-chip"][data-port="${city}"]`)
    if (await chip.count()) await chip.click()
    else await pressCity(page, map, city)
    if (!(await expect(board).toHaveAttribute('data-city', city, { timeout: 3_000 }).then(() => true, () => false))) continue
    const there = await goodsOf().catch(() => [] as string[])
    const code = there.find((c) => here.has(c))
    if (!code) continue
    await face.locator(`[data-testid="city-chip"][data-port="${home}"]`).click()
    await expect(board).toHaveAttribute('data-city', home)
    return { code, city, home }
  }
  throw new Error('no harbour deals in a good sold where she lies')
}

/** Sell → the city → the good → Sail & sell (owner row 229). Its estimate's labels are 1–2 words (row 202). */
export async function sailAndSell(page: Page, code: string, city: string): Promise<void> {
  const face = page.getByTestId('desk-trade')
  const board = face.getByTestId('trade-board')
  const chip = face.locator(`[data-testid="city-chip"][data-port="${city}"]`)
  if (await chip.count()) await chip.click()
  else await pressCity(page, face.getByTestId('trade-map'), city)
  await expect(board).toHaveAttribute('data-city', city)
  await expect(board).toHaveAttribute('data-docked', 'false')
  const card = face.locator(`[data-testid="trade-good"][data-good="${code}"]`)
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

/** Buy, where she lies, the good's first count (the panel's one button). */
export async function buyHere(page: Page, code: string): Promise<void> {
  const face = page.getByTestId('desk-trade')
  const card = face.locator(`[data-testid="trade-good"][data-good="${code}"]`)
  await expect(card).toBeVisible({ timeout: 60_000 })
  await card.getByTestId('trade-buy').click()
  const act = page.getByTestId('trade-act')
  await expect(act).toHaveAttribute('data-act', 'buy')
  await expect(act).toBeEnabled({ timeout: 60_000 })
  await act.click()
  await expect(page.getByTestId('good-detail')).toHaveCount(0, { timeout: 60_000 })
}

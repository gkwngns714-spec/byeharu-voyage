// A CITY PRESSED ON THE DESK'S MINI MAP (owner row 218) — the way a player presses it: on the harbour's NAME where
// one is drawn, else on its mark, through the chart's own tap (the picture takes no pointer; the surface under it
// does, and THE map tab's hit test answers). Never an element click.
//
// THE NAME FIRST, AND A STILL MAP (CI run 40449328997, 390×844): on the phone's whole-world sheet Amsterdam's mark
// lies 1.2 px from Antwerp's (0.5 px east, 1.1 px north, measured) and under the crowd of names with leaders; a
// press on its mark's centre was answered "ARP". The hit test answers a drawn name before any mark (hitTest.ts), so
// the name is what a player's thumb is sure of on a crowded sheet — and what this presses. And a city pressed
// glides the map (row 231), so the target is read only once it stops moving: a box read mid-glide is a press
// somewhere else by the time it lands.
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

/** THE NEAREST CITY SHE IS NOT AT (owner row 229): the second chip of the strip under the map (the first is where she
 *  lies). Pressed; its code returned. */
export async function pressNearCity(face: Locator): Promise<string> {
  const chip = face.getByTestId('city-chip').nth(1)
  await expect(chip).toBeVisible({ timeout: 60_000 })
  const code = (await chip.getAttribute('data-port'))!
  await chip.click()
  await expect(face.getByTestId('city-goods')).toHaveAttribute('data-city', code)
  return code
}

/** A good pressed on the city's board, the first that has a price: its code. */
export async function pressFirstPricedCard(face: Locator): Promise<string> {
  const card = face.locator('[data-testid="city-good"]:not([disabled])').first()
  await expect(card).toBeVisible({ timeout: 120_000 })
  const code = (await card.getAttribute('data-good'))!
  await card.click()
  return code
}

/** A GOOD TO CARRY, FOUND THE WAY A PLAYER FINDS ONE (owner row 229: no list of where to sell — press cities): on Buy,
 *  the goods where she lies, then the harbours nearest her (the chip strip, then the map) pressed one by one until
 *  one deals in a good she can buy here — a city that sells a good buys it too (its market row has a bid). Returns
 *  the good, that city and where she lies; the Buy face is left back on where she lies. */
export async function findCarry(page: Page, skip: readonly string[] = []): Promise<{ code: string; city: string; home: string }> {
  const faces = page.getByRole('tablist', { name: 'Desk faces' })
  await faces.getByRole('tab', { name: 'Buy', exact: true }).click()
  const face = page.getByTestId('desk-buy')
  const board = face.getByTestId('city-goods')
  const chips = face.getByTestId('city-chip')
  await expect(chips.first()).toBeVisible({ timeout: 60_000 })
  const home = (await chips.first().getAttribute('data-port'))!
  const goodsOf = async () => {
    // its cards, or "Sells nothing" — a city that sells nothing is answered at once, not waited out
    await expect(face.getByTestId('city-good').first().or(face.getByTestId('city-goods-none'))).toBeVisible({ timeout: 60_000 })
    return face.getByTestId('city-good').evaluateAll((es) => es.map((e) => e.getAttribute('data-good') ?? ''))
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
  const faces = page.getByRole('tablist', { name: 'Desk faces' })
  await faces.getByRole('tab', { name: 'Sell', exact: true }).click()
  const face = page.getByTestId('desk-sell')
  const board = face.getByTestId('city-goods')
  const chip = face.locator(`[data-testid="city-chip"][data-port="${city}"]`)
  if (await chip.count()) await chip.click()
  else await pressCity(page, face.getByTestId('trade-map'), city)
  await expect(board).toHaveAttribute('data-city', city)
  await expect(board).toHaveAttribute('data-docked', 'false')
  const good = face.locator(`[data-testid="city-good"][data-good="${code}"]`)
  await expect(good.getByTestId('city-good-price')).toHaveText(/\d/, { timeout: 60_000 })
  if ((await good.getAttribute('aria-pressed')) !== 'true') await good.click()
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
  const face = page.getByTestId('desk-buy')
  const card = face.locator(`[data-testid="city-good"][data-good="${code}"]`)
  await expect(card).toBeVisible({ timeout: 60_000 })
  await card.click()
  const act = page.getByTestId('trade-act')
  await expect(act).toHaveAttribute('data-act', 'buy')
  await expect(act).toBeEnabled({ timeout: 60_000 })
  await act.click()
  await expect(page.getByTestId('good-detail')).toHaveCount(0, { timeout: 60_000 })
}

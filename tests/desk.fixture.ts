// HQ'S FACES, OPENED THE WAY A PLAYER OPENS THEM (H3 `desk-into-hq`, 2026-11-24). The Trade desk (`/command`) and the Office
// (`/office`) are gone: the goods list is HQ's Market plate, a fleet's cargo, route, orders and map are her sheet over HQ, and the
// buildings are HQ's plates (tests/hq.desk.spec.ts carries the whole table). These helpers make those presses; the URL stays `/city`.
import { expect, type Locator, type Page } from '@playwright/test'
import { toPlaces } from './hqPlaces.fixture'

/** One of HQ's plates, pressed open (`hall`, `market`, `production`, `port`, `inn`). */
export async function openPlate(page: Page, id: string): Promise<void> {
  await toPlaces(page)
  const plate = page.getByTestId(`city-building-${id}`)
  if ((await plate.getAttribute('aria-pressed')) !== 'true') await plate.click()
  await expect(plate).toHaveAttribute('aria-pressed', 'true')
}

/** HQ's Market plate, open on its first read: the one trade list (the city chips, the goods cards). Returns the read's wrapper
 *  (`city-market-read`: `data-city` the city read, `data-here` whether the fleet that trades lies there). */
export async function openMarket(page: Page): Promise<Locator> {
  const read = page.getByTestId('city-market-read')
  if ((await read.count()) === 0) await openPlate(page, 'market')
  await expect(read).toBeVisible({ timeout: 120_000 })
  return read
}

/** A fleet's sheet over HQ (her row's press): where she is, her cargo, her route, her orders, her map, her ship. */
export async function openFleetSheet(page: Page, fleet?: string): Promise<Locator> {
  const row = fleet ? page.locator(`[data-testid="hq-fleet"][data-fleet="${fleet}"]`) : page.getByTestId('hq-fleet').first()
  await row.getByTestId('hq-fleet-press').click()
  const sheet = page.getByTestId('hq-sheet-fleet')
  await expect(sheet).toBeVisible({ timeout: 60_000 })
  return sheet
}

/** The build yard: HQ's Port plate, its Build row, the yard's page (`port-yard`). `word`, when given, is the row's own word. */
export async function openYard(page: Page, word?: string): Promise<Locator> {
  await openPlate(page, 'port')
  const door = page.getByTestId('city-port-yard')
  if (word) await expect(door).toContainText(word)
  await door.click()
  const yard = page.getByTestId('port-yard')
  await expect(yard).toBeVisible({ timeout: 60_000 })
  return yard
}

/** Close the top layer over HQ by its own back: a page's arrow, else the trade sheet's close. */
export async function closeTop(page: Page): Promise<void> {
  const arrow = page.locator('[data-detail-page] [data-detail-back]')
  if ((await arrow.count()) > 0) await arrow.last().click()
  else await page.getByTestId('tray-close').last().click()
}

/** THE TRADE SHEET, IN PLACE (2026-11-24, simplify S1; src/app/HqSheet.tsx): a Buy or Sell pressed on the HQ Market opens THE trade
 *  sheet over the page it was pressed on, on that city, that good and that side — the URL does not move. This waits for the sheet
 *  and runs the trade there (`n` units), the press a player makes: the count, the one big button, the toast. The sheet stays open
 *  after a trade where she lies; the browser's back (or its ✕, or Escape) closes it.
 *  (The name is X1's, kept so the specs read it unchanged.) */
export async function tradeOnDesk(page: Page, n = 1): Promise<void> {
  const before = page.url()
  const figure = page.getByTestId('good-detail').getByTestId('stepper-figure')
  await expect(figure).toBeVisible({ timeout: 60_000 })
  expect(page.url(), 'the Buy / Sell press left the page it was pressed on').toBe(before)
  await figure.fill(String(n))
  await figure.press('Enter')
  await expect(page.getByTestId('trade-act')).toBeEnabled({ timeout: 60_000 })
  // the toast stands 3.2 s: it is watched from BEFORE the press, in the page, so a busy tab (the world read back after the trade) cannot
  // show and drop it between two polls from here (seen once at 390 with two workers)
  const toast = page.getByTestId('trade-toast').waitFor({ state: 'visible', timeout: 60_000 })
  await page.getByTestId('trade-act').click()
  await toast
}

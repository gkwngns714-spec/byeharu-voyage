// THE DESK'S CITY FACE, OPENED THE WAY A PLAYER OPENS IT (2026-10-18, docs/COMMAND_DESK.md D8). PORT is gone:
// every building it carried is a face of COMMAND · City, so a spec that used to `goto('port')` opens the desk
// and turns to City — the press a player makes. (An old `/port` link lands here too, through the router.)
//
// OPENED MEANS SETTLED. City opens on Trade, and Trade stands a Skeleton until the quay's market read lands
// (src/features/command/city/City.tsx). The specs used to sleep 1200 ms after this and then count ledger
// rows once; under CI load the read took longer and they counted 0 beside the Skeleton (runs 39097978019,
// 39107062920, 39107806852). So the face is returned only once it has drawn its first read.
//
// AND ITS SECOND READ. The quay's fair (src/live/PortFair.tsx `QuayFair`) is read apart from the market and draws
// NOTHING until it lands — no Skeleton — then, only while a fair is on at this port, a 52-px accent Row above
// the trade pane (src/features/command/city/City.tsx). So `settled` alone returned the face with that read still
// in flight, and whenever the clock and the world's seed (migration 0026, `buff_season_of`) had a fair live, the
// row could land between a spec's "before" and "after" measurements and shift everything under it by 52 px
// (tests/layout.spec.ts, the three "a press moves nothing" laws, 2026-11-10). City marks its frame
// `data-fair-loaded` once the store holds the quay's buffs — the same store state that draws the row, in the same
// commit — so waiting on the mark is waiting on the row, fair or no fair.
import { expect, type Page } from '@playwright/test'
import { settled, WORLD_BOOT_MS } from './appReady.fixture'

/** THE OFFICE'S FACE (2026-11-16: City, Invest and Report left the Trade desk for the Office; 2026-11-24, simplify S1: HQ's City door
 *  is gone — HQ is the city, and Invest and Report open as sheets over HQ). The Office stands only on its route until S4 removes it, so
 *  the route is the way in (in place, as the router would take it, never a reload); then the face in the Office's strip. */
export async function openOfficeFace(page: Page, face: string | RegExp): Promise<void> {
  if (!new URL(page.url()).pathname.endsWith('/office'))
    await page.evaluate(() => {
      history.pushState({}, '', `${location.pathname.replace(/\/[^/]*$/, '')}/office`)
      dispatchEvent(new PopStateEvent('popstate'))
    })
  const office = page.getByTestId('office')
  await expect(office).toBeVisible({ timeout: WORLD_BOOT_MS })
  await office.getByRole('tablist').first().getByRole('tab', typeof face === 'string' ? { name: face, exact: true } : { name: face }).click()
}

export async function openCityFace(page: Page): Promise<void> {
  await openOfficeFace(page, 'City')
  const city = page.getByTestId('desk-city')
  await expect(city).toBeVisible()
  await settled(city)
  await expect(city, "the quay's fair read has not landed").toHaveAttribute('data-fair-loaded', '', { timeout: WORLD_BOOT_MS })
}

/** THE TRADE SHEET, IN PLACE (2026-11-24, simplify S1; src/features/city/HqSheet.tsx): a Buy or Sell pressed on the HQ Market or on
 *  Office > City > Market opens THE trade sheet over the page it was pressed on, on that city, that good and that side — the URL does
 *  not move. This waits for the sheet and runs the trade there (`n` units), the press a player makes: the count, the one big button,
 *  the toast. The sheet stays open after a trade where she lies; the browser's back (or its ✕, or Escape) closes it.
 *  (The name is X1's, kept so S3's specs read it unchanged until S3 renames it.) */
export async function tradeOnDesk(page: Page, n = 1): Promise<void> {
  const before = page.url()
  const figure = page.getByTestId('good-detail').getByTestId('stepper-figure')
  await expect(figure).toBeVisible({ timeout: 60_000 })
  expect(page.url(), 'the Buy / Sell press left the page it was pressed on').toBe(before)
  await figure.fill(String(n))
  await figure.press('Enter')
  await expect(page.getByTestId('trade-act')).toBeEnabled({ timeout: 60_000 })
  await page.getByTestId('trade-act').click()
  await expect(page.getByTestId('trade-toast')).toBeVisible({ timeout: 60_000 })
}

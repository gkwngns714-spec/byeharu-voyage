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

export async function openCityFace(page: Page): Promise<void> {
  await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'City', exact: true }).click()
  const city = page.getByTestId('desk-city')
  await expect(city).toBeVisible()
  await settled(city)
  await expect(city, "the quay's fair read has not landed").toHaveAttribute('data-fair-loaded', '', { timeout: WORLD_BOOT_MS })
}

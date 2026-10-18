// THE DESK'S CITY FACE, OPENED THE WAY A PLAYER OPENS IT (2026-10-18, docs/COMMAND_DESK.md D8). PORT is gone:
// every building it carried is a face of COMMAND · City, so a spec that used to `goto('port')` opens the desk
// and turns to City — the press a player makes. (An old `/port` link lands here too, through the router.)
//
// OPENED MEANS SETTLED. City opens on Trade, and Trade stands a Skeleton until the quay's market read lands
// (src/features/command/city/City.tsx). The specs used to sleep 1200 ms after this and then count ledger
// rows once; under CI load the read took longer and they counted 0 beside the Skeleton (runs 39097978019,
// 39107062920, 39107806852). So the face is returned only once it has drawn its first read.
import { expect, type Page } from '@playwright/test'
import { settled } from './appReady.fixture'

export async function openCityFace(page: Page): Promise<void> {
  await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'City', exact: true }).click()
  const city = page.getByTestId('desk-city')
  await expect(city).toBeVisible()
  await settled(city)
}

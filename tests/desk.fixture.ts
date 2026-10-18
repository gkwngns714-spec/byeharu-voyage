// THE DESK'S CITY FACE, OPENED THE WAY A PLAYER OPENS IT (2026-10-18, docs/COMMAND_DESK.md D8). PORT is gone:
// every building it carried is a face of COMMAND · City, so a spec that used to `goto('port')` opens the desk
// and turns to City — the press a player makes. (An old `/port` link lands here too, through the router.)
import { expect, type Page } from '@playwright/test'

export async function openCityFace(page: Page): Promise<void> {
  await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'City', exact: true }).click()
  await expect(page.getByTestId('desk-city')).toBeVisible()
}

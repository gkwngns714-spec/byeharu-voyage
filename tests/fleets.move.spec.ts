import { test, expect, type Page } from '@playwright/test'
import { PHONE, ready, reachable } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// A SHIP CHANGES FLEETS, ON THE PAGE (0321): a world set dark draws no Move (the shipped world is lit since 0370), and a world with the room lit moves the founding ship into a new fleet. The fleet she leaves is
// empty: it still has its row and its page, offers no Command, and the map, the desk and the list all survive it.

const lit = () => patchedWorldImage('fleet-room', async (pg) => {
  await pg.exec(`update public.world_config set value = 'true'::jsonb where key = 'fleet_room_bite'`)
})

// 0370 lit fleet room in the shipped world. The dark page is still proven, on a copy of the image with the switch set back (what a rollback of 0370 would show).
const dark = () => patchedWorldImage('fleet-room-dark', async (pg) => {
  await pg.exec(`update public.world_config set value = 'false'::jsonb where key = 'fleet_room_bite'`)
})

async function openFirstFleet(page: Page) {
  await page.goto('fleets')
  await ready(page)
  await page.getByTestId('fleet-row').first().click()
  await expect(page.getByTestId('fleet-page')).toBeVisible()
}

test.use({ viewport: PHONE })

test('dark: no Move on a ship', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), 'no served build')
  await serveWorldImage(page, await dark())
  await openFirstFleet(page)
  await expect(page.getByTestId('fleet-fold')).toBeVisible()
  await expect(page.getByTestId('ship-move')).toHaveCount(0)
})

test('lit: the only ship moves to a new fleet, and the empty fleet stands', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), 'no served build')
  await serveWorldImage(page, await lit())
  await openFirstFleet(page)
  await page.getByTestId('ship-move').click()
  await page.getByTestId('ship-move-name').fill('Nova Armada')
  await page.getByTestId('ship-move-new').click()
  await expect(page.getByTestId('ship-move-page')).toHaveCount(0)

  await expect(page.getByTestId('fleet-no-ships')).toBeVisible()
  await expect(page.getByTestId('fleet-command')).toHaveCount(0)
  await page.keyboard.press('Escape')
  await expect(page.getByTestId('fleet-row')).toHaveCount(2)

  // the desk offers the fleet with a ship, and never the empty one
  await page.goto('command')
  await ready(page)
  await expect(page.getByTestId('fleet-picker').first()).toContainText('Nova Armada')

  // the map stands
  await page.goto('map')
  await ready(page)
  await expect(page.locator('body')).not.toContainText('E_NO_SHIPS')
})

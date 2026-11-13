import { test, expect, type Page } from '@playwright/test'
import { PHONE, ready, reachable } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// THE FLEET'S TOTALS, THE RENAME DOOR AND THE ROOM ROWS, ON THE PAGE (0354). The shipped world is dark: the room card says "Not open yet" and draws no Buy, the fleet's page
// carries her totals line and Rename, and a rename shows on the row. A world with the room lit offers one Buy, and a press raises the ships a fleet may hold.

const lit = () => patchedWorldImage('fleet-room', async (pg) => {
  await pg.exec(`update public.world_config set value = 'true'::jsonb where key = 'fleet_room_bite'`)
})

async function openFleets(page: Page) {
  await page.goto('fleets')
  await ready(page)
  await expect(page.getByTestId('fleet-row').first()).toBeVisible()
}

test.use({ viewport: PHONE })

test('dark: the room says it is not open and offers no press; the fleet shows her totals and takes a new name', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), 'no served build')
  await openFleets(page)

  const room = page.getByTestId('fleet-room')
  await expect(room).toBeVisible()
  await expect(room.getByTestId('fleet-room-dark')).toHaveText('Not open yet')
  await expect(room.getByTestId('fleet-room-buy')).toHaveCount(0)
  await expect(room.locator('button')).toHaveCount(0)
  await expect(room.getByTestId('fleet-room-fleet').getByTestId('fleet-room-step')).toHaveCount(4)
  await expect(room.getByTestId('fleet-room-fleet')).toContainText('Trading 3')
  await expect(room.getByTestId('fleet-room-fleet')).toContainText('60,000')
  await expect(room.getByTestId('fleet-room-ship')).toContainText('Seamanship or Command 1')
  await expect(room.getByTestId('fleet-room-ship').getByTestId('fleet-room-step')).toHaveCount(10)
  // nothing in the card shears sideways on a phone
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)

  await page.getByTestId('fleet-row').first().click()
  const fold = page.getByTestId('fleet-fold')
  await expect(fold).toBeVisible()
  const totals = fold.getByTestId('fleet-totals')
  await expect(totals).toBeVisible()
  for (const id of ['fleet-total-attack', 'fleet-total-hull', 'fleet-total-crew', 'fleet-total-wages', 'fleet-total-slowest']) await expect(totals.getByTestId(id)).toBeVisible()
  // the slowest ship is named whole: nothing in the line is clipped or cut with dots
  const cut = await totals.evaluate((el) => [...el.querySelectorAll('span')].filter((n) => n.scrollWidth > n.clientWidth + 1 || (n.textContent ?? '').includes('…')).length)
  expect(cut, 'a figure or a name on the totals line is cut').toBe(0)
  expect(await totals.getByTestId('fleet-total-slowest').textContent()).toMatch(/Slowest \S.* \d/)

  await fold.getByTestId('fleet-rename').click()
  const renamePage = page.getByTestId('fleet-rename-page')
  await expect(renamePage).toBeVisible()
  await renamePage.getByTestId('fleet-rename-name').fill('ab')
  await expect(renamePage.getByTestId('fleet-rename-save')).toBeDisabled()
  await renamePage.getByTestId('fleet-rename-name').fill('Armada de Sao Vicente')
  await renamePage.getByTestId('fleet-rename-save').click()
  await expect(renamePage).toHaveCount(0)
  await page.keyboard.press('Escape')
  await expect(page.getByTestId('fleet-row').first()).toContainText('Armada de Sao Vicente')
})

test('lit: one Buy stands on the price she can pay, and a press opens room for a third ship', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), 'no served build')
  await serveWorldImage(page, await lit())
  await openFleets(page)
  const room = page.getByTestId('fleet-room')
  await expect(room).toBeVisible()
  await expect(room.getByTestId('fleet-room-dark')).toHaveCount(0)
  const ships = room.getByTestId('fleet-room-ship')
  await expect(ships.getByTestId('fleet-room-have')).toContainText('1 / 2')
  // a founding purse covers the first ship step (10,000) and not the first fleet step (60,000): one Buy, on the ships
  await expect(room.getByTestId('fleet-room-buy')).toHaveCount(1)
  await ships.getByTestId('fleet-room-buy').click()
  await expect(ships.getByTestId('fleet-room-have')).toContainText('1 / 3')
  await expect(page.locator('body')).not.toContainText('E_')
})

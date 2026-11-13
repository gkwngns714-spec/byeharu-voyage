import { test, expect, type Page } from '@playwright/test'
import { PHONE, ready, reachable } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// THE FLEET'S TOTALS, THE RENAME DOOR AND THE ROOM ROWS, ON THE PAGE (0354). The shipped world is LIT since 0370. A world set dark: the room card says "Not open yet" and draws no Buy, the fleet's page
// carries her totals line and Rename, and a rename shows on the row. A world with the room lit offers one Buy, and a press raises the ships a fleet may hold.

const lit = () => patchedWorldImage('fleet-room', async (pg) => {
  await pg.exec(`update public.world_config set value = 'true'::jsonb where key = 'fleet_room_bite'`)
})

// 0370 lit fleet room in the shipped world. The dark page is still proven, on a copy of the image with the switch set back (what a rollback of 0370 would show).
const dark = () => patchedWorldImage('fleet-room-dark', async (pg) => {
  await pg.exec(`update public.world_config set value = 'false'::jsonb where key = 'fleet_room_bite'`)
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
  await serveWorldImage(page, await dark())
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

// THE ROOM CARD, LIT, AS SHIPPED (0370: fleet_room_bite true, fleet_hard_max 6), ON A PHONE AND ON A WIDE SCREEN, IN ENGLISH AND IN KOREAN. No patch: this is the world a player
// gets. The fleet ladder is the whole way to SIX fleets: the free two, Trading 3, Trading 6, 60,000 and 1,000,000, each step on its own line with its level or its price.
const ROOM_WORDS = {
  en: { rungs: ['Trading 3', 'Trading 6'], notOpen: 'Not open yet', buy: 'Buy' },
  ko: { rungs: ['교역 3', '교역 6'], notOpen: '아직 안 열림', buy: '구매' },
} as const

for (const glass of [{ width: 390, height: 844 }, { width: 1280, height: 800 }]) {
  for (const lang of ['en', 'ko'] as const) {
    test.describe(`the room card as shipped, ${glass.width}px ${lang}`, () => {
      test.use({ viewport: glass, locale: lang === 'ko' ? 'ko-KR' : 'en-US' })

      test('lit: the fleet ladder shows both level steps and both prices, one Buy, nothing cut', async ({ page, request, baseURL }) => {
        test.setTimeout(480_000)
        test.skip(!(await reachable(request, baseURL ?? '')), 'no served build')
        await openFleets(page)
        const w = ROOM_WORDS[lang]
        const room = page.getByTestId('fleet-room')
        await expect(room).toBeVisible()
        await expect(room.getByTestId('fleet-room-dark')).toHaveCount(0)
        await expect(room).not.toContainText(w.notOpen)
        const fleetSteps = room.getByTestId('fleet-room-fleet').getByTestId('fleet-room-step')
        await expect(fleetSteps).toHaveCount(4)
        await expect(fleetSteps.nth(0)).toContainText(w.rungs[0])
        await expect(fleetSteps.nth(1)).toContainText(w.rungs[1])
        await expect(fleetSteps.nth(2)).toContainText('60,000')
        await expect(fleetSteps.nth(3)).toContainText('1,000,000')
        await expect(room.getByTestId('fleet-room-fleet').getByTestId('fleet-room-have')).toContainText('1 / 2')
        // a founding purse pays the first ship step only: one Buy on the card, in her language
        await expect(room.getByTestId('fleet-room-buy')).toHaveCount(1)
        await expect(room.getByTestId('fleet-room-buy')).toHaveText(w.buy)
        // nothing in the card is clipped, cut with dots, or pushed off the glass
        const cut = await room.evaluate((el) => [...el.querySelectorAll('span, li')].filter((n) => n.scrollWidth > n.clientWidth + 1 || (n.textContent ?? '').includes('…')).length)
        expect(cut, 'a step of the room card is cut').toBe(0)
        const box = await room.boundingBox()
        expect(box!.x).toBeGreaterThanOrEqual(0)
        expect(box!.x + box!.width).toBeLessThanOrEqual(glass.width + 0.5)
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
        if (process.env.FLEET_ROOM_SHOTS) {
          await room.scrollIntoViewIfNeeded()
          await page.screenshot({ path: `${process.env.FLEET_ROOM_SHOTS}/fleet-room-lit-${glass.width}-${lang}.png` })
        }
      })
    })
  }
}

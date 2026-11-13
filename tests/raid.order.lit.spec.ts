import { test, expect, type Page } from '@playwright/test'
import { ready, reachable, WORLD_BOOT_MS } from './appReady.fixture'

// THE STANDING ORDER'S PICKER, LIT, AS SHIPPED (0353 built it; 0371 lit `raid_orders_enabled`, owner rows 315 and 324). No patch: this is the world a player gets.
// src/live/RaidOrder.tsx has two mounts: the fleet's page and the map's Send tray, under the picked fleet. Each is driven here on a phone (390 px) and on the narrow
// phone (320 px), in English and in Korean: the three words stand in her language, a press is kept by the real door (cmd.raid_order) and shown back by the real read
// (world.raid_read), and nothing is cut or pushed off the glass.

const WORDS = {
  en: { orders: ['Fight', 'Flee', 'Pay'] },
  ko: { orders: ['전투', '도주', '지불'] },
} as const
const GLASSES = [{ width: 390, height: 844 }, { width: 320, height: 640 }] as const
/** Harbours a founding barca reaches from Lisbon in one leg, the nearest first. */
const NEAR = ['CAD', 'OPO', 'SEV', 'FNC']

async function pickerLaws(page: Page, where: string, glass: { width: number }) {
  const picker = page.getByTestId('raid-order')
  const cut = await picker.evaluate((el) => [...el.querySelectorAll('span, button')].filter((n) => n.scrollWidth > n.clientWidth + 1 || (n.textContent ?? '').includes('…')).length)
  expect(cut, `${where}: a word of the picker is cut`).toBe(0)
  const box = (await picker.boundingBox())!
  expect(box.x, `${where}: the picker starts off the glass`).toBeGreaterThanOrEqual(0)
  expect(box.x + box.width, `${where}: the picker runs off the glass`).toBeLessThanOrEqual(glass.width + 0.5)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), `${where}: the page scrolls sideways`).toBe(true)
}

async function words(page: Page) {
  return [await page.getByTestId('raid-order-FIGHT').innerText(), await page.getByTestId('raid-order-FLEE').innerText(), await page.getByTestId('raid-order-PAY').innerText()]
}

async function shot(page: Page, name: string) {
  if (process.env.RAID_ORDER_SHOTS) await page.screenshot({ path: `${process.env.RAID_ORDER_SHOTS}/raid-order-${name}.png` })
}

for (const glass of GLASSES) {
  for (const lang of ['en', 'ko'] as const) {
    test.describe(`the order picker as shipped, ${glass.width}px ${lang}`, () => {
      test.use({ viewport: glass, locale: lang === 'ko' ? 'ko-KR' : 'en-US' })

      test('the fleet page: Fight / Flee / Pay, a press is kept, nothing cut', async ({ page, request, baseURL }) => {
        test.setTimeout(480_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
        await page.goto('fleets')
        await ready(page)
        await page.getByTestId('fleet-row').first().click()
        await expect(page.getByTestId('fleet-fold')).toBeVisible()
        // THE PICKER LANDS IN PLACE: while its read is on its way the same rows stand with no figures (raid-order-waiting), and the answer fills them without changing
        // the picker's height by a pixel, so nothing under it moves. Measured as the picker's own height at first sight (waiting, when the read is still out) against its
        // height once the figures are in: other parts of the page land on their own reads and are not this law's.
        const either = page.locator('[data-testid="raid-order"], [data-testid="raid-order-waiting"]')
        await expect(either).toBeVisible()
        const first = await either.evaluate((el) => ({ h: el.getBoundingClientRect().height, waiting: el.getAttribute('data-testid') === 'raid-order-waiting' }))
        const picker = page.getByTestId('raid-order')
        await expect(picker).toBeVisible()
        await expect(page.getByTestId('raid-order-waiting')).toHaveCount(0)
        const landed = await picker.evaluate((el) => el.getBoundingClientRect().height)
        console.log(`picker ${glass.width} ${lang}: first seen ${first.waiting ? 'waiting' : 'landed'} at ${first.h} px, landed at ${landed} px`)
        expect(landed, `the picker changed height when its read landed (first seen ${first.waiting ? 'waiting' : 'landed'})`).toBe(first.h)
        await picker.scrollIntoViewIfNeeded()
        await expect(picker).toHaveAttribute('data-order', 'FIGHT') // a fleet that never chose fights
        expect(await words(page)).toEqual([...WORDS[lang].orders])
        await expect(page.getByTestId('raid-order-foe')).toHaveAttribute('data-word', /^(weaker|even|stronger|far_stronger)$/)
        await expect(page.getByTestId('raid-order-slip')).toHaveAttribute('data-word', /^(poor|fair|good)$/)
        await pickerLaws(page, 'the fleet page', glass)
        await page.getByTestId('raid-order-FLEE').click()
        await expect(picker).toHaveAttribute('data-order', 'FLEE')
        await expect(page.getByTestId('raid-order-refusal')).toHaveCount(0)
        await pickerLaws(page, 'the fleet page under Flee', glass)
        await shot(page, `fleet-page-${glass.width}-${lang}`)
        await page.getByTestId('raid-order-FIGHT').click()
        await expect(picker).toHaveAttribute('data-order', 'FIGHT')
      })

      test('the Send tray: the picker stands under the picked fleet, and a press is kept', async ({ page, request, baseURL }) => {
        test.setTimeout(600_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
        await page.goto('map')
        await ready(page)
        await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: WORLD_BOOT_MS })
        let open = false
        for (const code of NEAR) {
          const at = await page.evaluate((c) => {
            const g = document.querySelector(`[data-port-code="${c}"]`)
            if (!g) return null
            const r = g.getBoundingClientRect()
            const onGlass = r.width > 0 && r.x > 0 && r.y > 60 && r.x < window.innerWidth && r.y < window.innerHeight - 120
            return onGlass ? { x: r.x + r.width / 2, y: r.y + r.height / 2 } : null
          }, code)
          if (!at) continue
          await page.mouse.click(at.x, at.y)
          if (!(await page.getByTestId('map-detail-tray').isVisible().catch(() => false))) continue
          if ((await page.getByTestId('map-send-fleet').count()) === 0) {
            await page.getByTestId('map-detail-tray').getByTestId('tray-close').click()
            continue
          }
          await page.getByTestId('map-send-fleet').click()
          await expect(page.getByTestId('map-send-row').first()).toBeVisible()
          await expect(page.locator('[data-testid="map-send-passage"], [data-testid="map-send-refusal"]').first()).toBeVisible({ timeout: 180_000 })
          if ((await page.getByTestId('map-send-passage').count()) > 0) {
            open = true
            break
          }
          await page.getByTestId('map-detail-tray').getByTestId('tray-close').click()
        }
        expect(open, `none of ${NEAR.join(' ')} gave the founding fleet a passage on the opening chart`).toBe(true)
        // the picker stands under the PICKED fleet: pick her (a press on her passage figure, inside the row's head) unless the tray already has
        const picker = page.getByTestId('raid-order')
        await expect(page.getByTestId('map-send-row-head').first()).toBeVisible()
        if ((await picker.count()) === 0) await page.getByTestId('map-send-passage').first().click()
        await expect(picker).toBeVisible({ timeout: 30_000 })
        await picker.scrollIntoViewIfNeeded()
        expect(await words(page)).toEqual([...WORDS[lang].orders])
        await expect(picker).toHaveAttribute('data-order', 'FIGHT')
        await pickerLaws(page, 'the Send tray', glass)
        await page.getByTestId('raid-order-PAY').click()
        await expect(picker).toHaveAttribute('data-order', 'PAY')
        await expect(page.getByTestId('raid-order-refusal')).toHaveCount(0)
        await pickerLaws(page, 'the Send tray under Pay', glass)
        await shot(page, `send-tray-${glass.width}-${lang}`)
      })
    })
  }
}

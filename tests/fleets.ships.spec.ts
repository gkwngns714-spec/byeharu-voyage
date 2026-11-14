import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { ready, reachable } from './appReady.fixture'
import { SECOND_SHIP, serveLitTwoShipsLaden } from './fleetsPage.fixture'

// A FLEET IS HER SHIPS; A SHIP IS HER CARGO AND SUPPLIES (owner, 2026-11-14; docs/dev-log/2026-11-14-fleet-ships.md).
//
// *"in fleets, when pressed a fleet, show only ships, then when i press the ship, show cargo and supplies."*
//
// The world is a throwaway copy of this build's image: a founding fleet of two ships with three goods aboard (tests/fleetsPage.fixture.ts). Proven at a phone (390×844), a
// narrow phone (320×640) and a laptop (1280×800), in English and in Korean:
//
//   STEP 1   a pressed fleet shows one row per ship, each name whole, and NOTHING of what used to stand beside them: no cargo row, no supplies row, no totals, no order
//            picker, no Command, no Rename, no ship place, no Stats. One `More` row stands under the ships.
//   STEP 2   a pressed ship opens her own page: her hold gauge, her goods, her water and food, the fleet's days. The goods on the two ships' pages add up to the three
//            goods loaded. Back gives the ships list as it stood; Stats opens her sheet over her page and Escape gives the page back.
//   MORE     the row opens the fleet's totals, Command, Rename and the ship places; Escape gives the ships back.
//   THE LAWS nothing scrolls sideways and no name is cut on any of the three pages.
//
// No test here may skip: a build that is not served is a failure, not a pass.

const GLASSES = [
  { name: 'phone390', width: 390, height: 844 },
  { name: 'phone320', width: 320, height: 640 },
  { name: 'desktop', width: 1280, height: 800 },
] as const
const WORDS = {
  en: { more: 'More', wholeFleet: 'Whole fleet', water: 'Water', food: 'Food' },
  ko: { more: '더 보기', wholeFleet: '선단 전체', water: '물', food: '식량' },
} as const

/** What a pressed fleet no longer shows on its first page. */
const GONE = ['fleet-cargo-row', 'hold-breakdown', 'fleet-stores-days', 'fleet-stores-space', 'fleet-totals', 'fleet-command', 'fleet-rename', 'fleet-place-locked', 'fleet-place-empty', 'ship-stats', 'ship-move', 'raid-order', 'fleet-ship-tile']

/** The pictures of the dev-log, written only when FLEET_SHIPS_SHOTS names a folder. */
async function shot(page: Page, name: string) {
  const to = process.env.FLEET_SHIPS_SHOTS
  if (!to) return
  mkdirSync(path.resolve(to), { recursive: true })
  await page.screenshot({ path: path.join(path.resolve(to), `${name}.png`) })
}

async function noSideways(page: Page, what: string) {
  const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(over, `${what} scrolls sideways by ${over} px`).toBeLessThanOrEqual(0)
}

/** No text under `testid` is cut: nothing ends in an ellipsis and no box hides part of its own line. */
async function nothingCut(page: Page, testid: string) {
  const cut = await page.getByTestId(testid).evaluate((root) => {
    const out: string[] = []
    for (const el of root.querySelectorAll<HTMLElement>('*')) {
      if (el.children.length > 0) continue
      const text = el.textContent?.trim() ?? ''
      if (!text) continue
      if (text.includes('…')) out.push(`ellipsis: "${text}"`)
      if (getComputedStyle(el).textOverflow === 'ellipsis' && el.scrollWidth > el.clientWidth + 1) out.push(`clipped: "${text}"`)
    }
    return out
  })
  expect(cut, `${testid}: a word is cut`).toEqual([])
}

for (const glass of GLASSES) {
  for (const lang of ['en', 'ko'] as const) {
    test.describe(`a fleet is her ships, ${glass.name} ${lang}`, () => {
      test.use({ viewport: { width: glass.width, height: glass.height }, locale: lang === 'ko' ? 'ko-KR' : 'en-US' })

      test('press a fleet: only ships; press a ship: her cargo and supplies', async ({ page, request, baseURL }) => {
        expect(await reachable(request, baseURL ?? ''), `nothing is served at ${baseURL}: run a preview of this build first`).toBe(true)
        const w = WORDS[lang]
        await serveLitTwoShipsLaden(page)
        await page.goto('fleets')
        await ready(page)

        // STEP 1: the fleet's page is her ships
        await page.getByTestId('fleet-row').first().click()
        const fleetPage = page.getByTestId('fleet-page')
        await expect(fleetPage).toBeVisible()
        const rows = fleetPage.getByTestId('fleet-ship-row')
        await expect(rows).toHaveCount(2)
        await expect(rows.nth(1).getByTestId('fleet-ship-name')).toHaveText(SECOND_SHIP)
        for (const row of await rows.all()) {
          await expect(row.getByTestId('cargo-bar')).toHaveCount(1)
          const box = await row.boundingBox()
          expect(box?.height ?? 0, 'a ship row is a press target').toBeGreaterThanOrEqual(44)
        }
        for (const id of GONE) await expect(fleetPage.getByTestId(id), `${id} still stands on the fleet's first page`).toHaveCount(0)
        await expect(fleetPage.getByTestId('fleet-more')).toHaveCount(1)
        await expect(fleetPage.getByTestId('fleet-more')).toContainText(w.more)
        await noSideways(page, 'the fleet page')
        await nothingCut(page, 'fleet-page')
        const before = await fleetPage.getByTestId('fleet-fold').boundingBox()
        await shot(page, `after-fleet-${glass.name}-${lang}`)

        // STEP 2: each ship's own page; the goods on the two add up to the three loaded
        let goods = 0
        for (let i = 0; i < 2; i++) {
          const name = (await rows.nth(i).getByTestId('fleet-ship-name').textContent()) ?? ''
          await rows.nth(i).click()
          const shipPage = page.getByTestId('fleet-ship-page')
          await expect(shipPage).toBeVisible()
          await expect(shipPage.locator('h1')).toHaveText(name)
          await expect(shipPage.getByTestId('fleet-fold-section')).toHaveCount(2)
          await expect(shipPage.getByTestId('cargo-bar')).toBeVisible()
          await expect(shipPage.getByTestId('ship-stores-water')).toContainText(w.water)
          await expect(shipPage.getByTestId('ship-stores-food')).toContainText(w.food)
          await expect(shipPage.getByTestId('fleet-stores-days')).toContainText(w.wholeFleet)
          await expect(shipPage.getByTestId('ship-stats')).toBeVisible()
          const here = await shipPage.getByTestId('fleet-cargo-row').count()
          goods += here
          await noSideways(page, `${name}'s page`)
          await nothingCut(page, 'fleet-ship-page')
          if (here > 0) await shot(page, `after-ship-${glass.name}-${lang}`)
          if (i === 0) {
            // Stats opens her sheet over her page; Escape leaves the sheet first and her page stands
            await shipPage.getByTestId('ship-stats').click()
            await expect(page.getByTestId('map-ship-panel')).toBeVisible()
            await page.keyboard.press('Escape')
            await expect(page.getByTestId('map-ship-panel')).toHaveCount(0)
            await expect(shipPage).toBeVisible()
          }
          // the clear way back: the page's own back press gives the ships list as it stood
          await shipPage.locator('[data-detail-back]').click()
          await expect(shipPage).toHaveCount(0)
          await expect(rows).toHaveCount(2)
          expect(await fleetPage.getByTestId('fleet-fold').boundingBox(), 'the ships list moved behind the ship page').toEqual(before)
        }
        expect(goods, 'the three goods loaded stand on the ships that carry them').toBeGreaterThanOrEqual(3)

        // MORE: what belongs to the fleet as a whole is one row further, and nothing was lost
        await fleetPage.getByTestId('fleet-more').click()
        const more = page.getByTestId('fleet-more-page')
        await expect(more).toBeVisible()
        for (const id of ['fleet-totals', 'fleet-command', 'fleet-rename']) await expect(more.getByTestId(id)).toBeVisible()
        await expect(more.getByTestId('fleet-place-locked').first()).toBeVisible()
        await noSideways(page, 'the More page')
        await nothingCut(page, 'fleet-more-page')
        await shot(page, `after-more-${glass.name}-${lang}`)
        await page.keyboard.press('Escape')
        await expect(more).toHaveCount(0)
        await expect(rows).toHaveCount(2)
      })
    })
  }
}

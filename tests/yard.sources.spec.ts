import { test, expect, type Locator, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// S8 — A YARD A PLAYER CAN FINISH (owner rows 180 and 305; world.yard_sources, 0349)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The playtest (2026-11-11): Port > Build listed 50+ hulls, the cheapest wanting six materials, and nothing said where any
// of them is sold, so no player could plan a second ship. A fresh company at Lisbon, at 390 and 1280, DPR 2:
//   - the hulls it can build here and now stand first; the rest wait under ONE "More" row, which opens below itself and
//     moves nothing above it;
//   - a hull's sheet names, for each missing material, the nearest harbour that sells it (with the miles), and the press
//     on a good opens the Trade desk on that city with that good in hand; a fitting made here opens this city's Workshop;
//   - nothing scrolls sideways.
// The Build button itself is proven where the world can be given the materials: tests/rpc.yardSources.spec.ts.

const GLASSES = [
  { width: 1280, height: 800 },
  { width: 390, height: 844 },
] as const

async function noSideways(page: Page, what: string) {
  const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(over, `${what} scrolls sideways by ${over} px`).toBeLessThanOrEqual(0)
}

async function yard(page: Page) {
  await page.goto('port')
  await ready(page)
  await page.getByRole('tablist', { name: 'City buildings' }).getByRole('tab', { name: 'Build', exact: true }).click()
  await expect(page.getByTestId('port-yard')).toBeVisible({ timeout: 60_000 })
}

async function box(l: Locator) {
  const b = await l.boundingBox()
  expect(b, 'not on the page').not.toBeNull()
  return b!
}

for (const glass of GLASSES) {
  test.describe(`the yard at ${glass.width}×${glass.height}`, () => {
    test.use({ viewport: glass, deviceScaleFactor: 2 })

    test('buildable first, the rest under More, and a missing material names where it is sold', async ({ page, request, baseURL }, info) => {
      test.setTimeout(240_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await yard(page)

      // 1. what you can build here and now, first; the rest are not on the page until More is pressed
      const now = page.getByTestId('yard-now')
      await expect(now).toBeVisible()
      const barca = now.getByTestId('hull-barca')
      await expect(barca, 'the Barca is not among the hulls a new company can build at Lisbon').toBeVisible()
      await expect(page.getByTestId('yard-elsewhere')).toHaveCount(0)
      const more = page.getByTestId('yard-more')
      await expect(more).toBeVisible()
      await noSideways(page, 'the yard')
      await page.screenshot({ path: info.outputPath('yard.png') })

      // 2. More opens below itself and moves nothing above it
      await more.scrollIntoViewIfNeeded()
      const nowBefore = await box(now)
      const moreBefore = await box(more)
      await more.click()
      await expect(page.getByTestId('yard-elsewhere')).toBeVisible()
      await expect(more).toHaveAttribute('aria-expanded', 'true')
      const nowAfter = await box(now)
      const moreAfter = await box(more)
      expect(nowAfter.y, 'More moved the hulls above it').toBe(nowBefore.y)
      expect(moreAfter.y, 'More moved itself').toBe(moreBefore.y)
      await noSideways(page, 'the yard, opened')

      // 3. the Barca's sheet: a missing good names its nearest seller with the miles, and a fitting where it is made
      await barca.scrollIntoViewIfNeeded()
      await barca.click()
      const tray = page.getByTestId('yard-tray')
      await expect(tray).toBeVisible()
      const timber = tray.getByTestId('yard-source-timber')
      await expect(timber, 'the missing Timber names no seller').toBeVisible({ timeout: 30_000 })
      const seller = await timber.getAttribute('data-port')
      expect(seller, 'the seller has no harbour code').toMatch(/^[A-Z]{3}$/)
      await expect(timber).toContainText(/^Buy (here|at .+)/)
      await expect(tray.getByTestId('yard-store-hint')).toBeVisible()
      // a fitting Lisbon's Workshop makes says so
      await expect(tray.getByTestId('yard-source-suit-of-sails')).toContainText(/^Make (here|at .+)/)
      await noSideways(page, 'the yard sheet')
      await page.screenshot({ path: info.outputPath('yard-sheet.png') })
      const sellerName = ((await timber.textContent()) ?? '').replace(/^Buy at /, '').replace(/\d[\d,.]*\s*\S+$/, '').trim()

      // 4. the press goes where it is bought: the Trade desk, reading that city, the Timber in hand
      await timber.click()
      await expect(page).toHaveURL(/\/command$/)
      const hand = await page.evaluate(() => sessionStorage.getItem('byeharu-voyage.desk-good.v1'))
      expect(JSON.parse(hand ?? '{}').state).toMatchObject({ code: 'timber', focus: seller })
      if (sellerName) await expect(page.getByText(sellerName, { exact: false }).first()).toBeVisible({ timeout: 30_000 })
      await noSideways(page, 'the Trade desk')
      await page.screenshot({ path: info.outputPath('trade-at-seller.png') })
    })
  })
}

test.describe('a fitting made here, and the words in Korean', () => {
  test.use({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, locale: 'ko-KR' })

  test('Make here opens the Workshop; the yard reads in Korean', async ({ page, request, baseURL }, info) => {
    test.setTimeout(240_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.goto('port')
    await ready(page)
    await page.getByRole('tablist').getByRole('tab', { name: '건조', exact: true }).click()
    await expect(page.getByTestId('yard-more')).toContainText('더보기')
    await page.getByTestId('yard-now').getByTestId('hull-barca').click()
    const sails = page.getByTestId('yard-tray').getByTestId('yard-source-suit-of-sails')
    await expect(sails).toBeVisible({ timeout: 30_000 })
    await expect(page.getByTestId('yard-tray').getByTestId('yard-source-timber')).toContainText('구매')
    await noSideways(page, 'the Korean yard sheet')
    await page.screenshot({ path: info.outputPath('yard-sheet-ko.png') })
    if ((await sails.getAttribute('data-port')) === 'LIS') {
      await expect(sails).toContainText('여기서 제작')
      await sails.click()
      await expect(page).toHaveURL(/\/command$/)
      await expect(page.getByTestId('port-workstation')).toBeVisible({ timeout: 60_000 })
      await page.screenshot({ path: info.outputPath('workshop.png') })
    }
  })
})

import { expect, test, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE HQ'S PRODUCTION PAGE (owner, 2026-11-06)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"On HQ, merge storage and forge. left side is storage, center is cargo, right side is recipes. i should be able to move cargo -
// storage. then once the production is made on right, i should also move from recipe - cargo. get it?"* The tab's word is Production.
//
// WHAT IT HOLDS, through the real doors of the canary world:
//   1. the tile is Production, and the old Storage and Forge tiles are gone;
//   2. from 1,024 px three columns across, Storage · Cargo · Recipes, left to right, at one top;
//   3. below it one column under a fixed Storage · Cargo · Recipes control, and pressing it moves nothing above it;
//   4. cargo to storage, storage to cargo and Finished to cargo each move the count asked for, and a press moves no list;
//   5. nothing scrolls sideways at any of them.
// The forge press itself needs three goods one harbour never sells together, so its seam is proven in tests/rpc.forge.spec.ts
// (a forged product goes aboard by the one TAKE). Silk Cloth is a recipe's product and sold at the starter port, so it stands in
// Finished here without one.

const GOOD = 'silk-cloth'

async function buyOneLot(page: Page) {
  await page.goto('command')
  await ready(page)
  await page.getByRole('tab', { name: 'City', exact: true }).first().click()
  await expect(page.getByTestId('desk-city')).toBeVisible()
  const row = page.getByTestId('trade-row').filter({ hasText: 'Silk Cloth' }).first()
  await expect(row).toBeVisible({ timeout: 60_000 })
  await row.getByRole('button').filter({ hasText: /^buy/i }).first().click()
  const send = page.getByTestId('trade-tray').getByTestId('trade-tray-send')
  await expect(send).toBeEnabled({ timeout: 30_000 })
  await send.click()
  await expect(page.getByTestId('trade-tray')).toHaveCount(0, { timeout: 30_000 })
  await expect(row).toContainText(/\d units? on board/, { timeout: 30_000 })
}

/** The desk's tab is the door: an old way to Storage lands on the merged page. */
async function openProduction(page: Page) {
  await page.getByRole('tab', { name: 'Production', exact: true }).first().click()
  await expect(page).toHaveURL(/place=production/)
  await expect(page.getByTestId('port-production')).toBeVisible({ timeout: 60_000 })
  // THE PAGE HAS LANDED: the hall's load meter has left and the recipes' read is drawn, so a box read now is the page's and not its loading.
  await expect(page.getByTestId('city-load-host')).toHaveCount(0, { timeout: 60_000 })
  await expect(page.locator('[data-testid^="forge-product-"]').first()).toBeVisible({ timeout: 60_000 })
}

const unitsIn = async (page: Page, cell: string) => Number(((await page.getByTestId(cell).innerText()).match(/(\d[\d,]*) unit/)?.[1] ?? '0').replace(/,/g, ''))

async function move(page: Page, cell: string, qty: number, word: RegExp) {
  const list = page.getByTestId('production-columns')
  const before = await list.boundingBox()
  await page.getByTestId(cell).click()
  const tray = page.getByTestId('storage-tray')
  await expect(tray).toBeVisible()
  await page.waitForTimeout(400)
  expect(await list.boundingBox(), `opening ${cell} moved the columns`).toEqual(before)
  await tray.getByTestId('storage-qty').locator('input[type="range"]').fill(String(qty))
  const act = tray.getByTestId('storage-act')
  await expect(act).toHaveText(word, { timeout: 20_000 })
  await expect(act).toBeEnabled({ timeout: 20_000 })
  await act.click()
  await expect(tray).toHaveCount(0, { timeout: 30_000 })
}

const noSideways = async (page: Page, where: string) => {
  const d = await page.evaluate(() => ({
    w: document.documentElement.scrollWidth,
    cw: document.documentElement.clientWidth,
    sheet: [...document.querySelectorAll('[data-sheet]')].map((s) => s.scrollWidth - s.clientWidth),
  }))
  expect(d.w, `${where} scrolls sideways`).toBeLessThanOrEqual(d.cw)
  for (const over of d.sheet) expect(over, `${where}: the page scrolls sideways`).toBeLessThanOrEqual(0)
}

test('Production, three columns: cargo to storage, storage to cargo and Finished to cargo, each the count asked for', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize({ width: 1440, height: 900 })
  await buyOneLot(page)
  await openProduction(page)

  await expect(page.getByTestId('city-building-production')).toHaveText('Production')
  await expect(page.getByTestId('city-building-storage')).toHaveCount(0)
  await expect(page.getByTestId('city-building-forge')).toHaveCount(0)
  await expect(page.getByTestId('port-production').getByRole('tab', { name: 'Storage', exact: true })).toBeHidden()

  // LEFT, CENTRE, RIGHT, at one top.
  const [s, c, r] = await Promise.all(['production-storage', 'production-cargo', 'production-recipes'].map((id) => page.getByTestId(id).boundingBox()))
  expect(s!.x + s!.width, 'Storage is not left of Cargo').toBeLessThanOrEqual(c!.x)
  expect(c!.x + c!.width, 'Cargo is not left of Recipes').toBeLessThanOrEqual(r!.x)
  expect(s!.y).toBe(c!.y)
  expect(c!.y).toBe(r!.y)
  await noSideways(page, '1440')

  // CARGO TO STORAGE, part of the lot: one good on both sides.
  const bought = await unitsIn(page, `storage-put-${GOOD}`)
  expect(bought, 'the lot is too small to split').toBeGreaterThanOrEqual(3)
  await move(page, `storage-put-${GOOD}`, 2, /^Put 2 units in storage$/)
  await expect.poll(() => unitsIn(page, `storage-take-${GOOD}`), { timeout: 30_000 }).toBe(2)
  await expect.poll(() => unitsIn(page, `storage-put-${GOOD}`)).toBe(bought - 2)

  // A RECIPE'S PRODUCT ASHORE IS FINISHED, and the same stock.
  await expect(page.getByTestId('finished-row').filter({ hasText: 'Silk Cloth' })).toBeVisible()
  expect(await unitsIn(page, `finished-take-${GOOD}`)).toBe(2)

  // FINISHED TO CARGO, the owner's "recipe - cargo": the one TAKE, and storage says so too.
  await move(page, `finished-take-${GOOD}`, 1, /^Take 1 unit on board$/)
  await expect.poll(() => unitsIn(page, `storage-put-${GOOD}`), { timeout: 30_000 }).toBe(bought - 1)
  await expect.poll(() => unitsIn(page, `storage-take-${GOOD}`)).toBe(1)
  await expect.poll(() => unitsIn(page, `finished-take-${GOOD}`)).toBe(1)

  // STORAGE TO CARGO, the last of it: the row leaves both lists.
  await move(page, `storage-take-${GOOD}`, 1, /^Take 1 unit on board$/)
  await expect.poll(() => unitsIn(page, `storage-put-${GOOD}`), { timeout: 30_000 }).toBe(bought)
  await expect(page.getByTestId('storage-row')).toHaveCount(0)
  await expect(page.getByTestId('finished-row')).toHaveCount(0)
})

for (const glass of [{ width: 1280, height: 800 }, { width: 1024, height: 768 }] as const) {
  test(`Production stands three across at ${glass.width}`, async ({ page, request, baseURL }) => {
    test.setTimeout(300_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(glass)
    await page.goto('city?place=production')
    await ready(page)
    await expect(page.getByTestId('port-production')).toBeVisible({ timeout: 60_000 })
    await expect(page.getByTestId('production-storage')).toBeVisible()
    await expect(page.getByTestId('production-cargo')).toBeVisible()
    await expect(page.getByTestId('production-recipes')).toBeVisible()
    await noSideways(page, `${glass.width}`)
  })
}

test('Production on a phone: one column under a fixed control, and a press moves nothing above it', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto('city')
  await ready(page)
  await page.getByTestId('city-building-production').click()
  const face = page.getByTestId('port-production')
  await expect(face).toBeVisible({ timeout: 60_000 })
  const control = face.getByRole('tablist', { name: 'Production', exact: true })
  await expect(control.getByRole('tab')).toHaveText(['Storage', 'Cargo', 'Recipes'])
  const before = await control.boundingBox()
  const only = { Storage: 'production-storage', Cargo: 'production-cargo', Recipes: 'production-recipes' } as const
  for (const [word, id] of Object.entries(only)) {
    await control.getByRole('tab', { name: word, exact: true }).click()
    for (const other of Object.values(only)) {
      if (other === id) await expect(page.getByTestId(other)).toBeVisible()
      else await expect(page.getByTestId(other)).toBeHidden()
    }
    expect(await control.boundingBox(), `pressing ${word} moved the control`).toEqual(before)
    await noSideways(page, `390 ${word}`)
  }
})

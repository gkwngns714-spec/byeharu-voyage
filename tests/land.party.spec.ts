import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// THE LAND TAB (migration 0455, docs/design/land-2026-11.md 6.7 and 8 L1), in a local world, headless.
//   DARK (the shipped image): no Land cell on the bar; a typed /land says "Not open yet." and nothing else.
//   LIT (a copy of the image with land_enabled true, the owner's switch, by worldImage.fixture's one seam), at 390 px and 1,280 px:
//     * the bar has its Land cell; at 320 and 390 every cell of the phone's bar is a real tap target (over 44 px) and no label is cut;
//     * Mining lists all 57 minerals; Iron is the home land's, Sea Coal is far and names its land and its trip, Platinum is grey with
//       "Mining 1 / 96" (have / need);
//     * pressing a row opens the Send tray OVER the page: the job list does not move; Send sends the party: the Party face says where
//       it is, and a second Send is refused in its place (E_LAND_OUT);
//     * nothing scrolls sideways.

const landLit = () =>
  patchedWorldImage('land-lit', async (pg) => {
    await pg.exec(`update public.world_config set value = 'true'::jsonb where key = 'land_enabled'`)
  })

// 0461 (L2, the smith): the land lit AND Smithing's own switch lit (land_smith_enabled, the owner's), by the same one seam
const smithLit = () =>
  patchedWorldImage('smith-lit', async (pg) => {
    await pg.exec(`update public.world_config set value = 'true'::jsonb where key in ('land_enabled', 'land_smith_enabled')`)
  })

const GLASSES = [
  { width: 390, height: 844 },
  { width: 1280, height: 900 },
] as const

async function noSideways(page: Page, where: string) {
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth),
    `${where}: the page scrolls sideways`,
  ).toBe(true)
}

test.describe('the land, dark as shipped', () => {
  test.use({ viewport: { width: 390, height: 844 } })
  test('no Land cell; /land says it is not open', async ({ page, request, baseURL }) => {
    test.setTimeout(480_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await page.goto('land')
    await ready(page)
    await expect(page.getByTestId('land-dark')).toBeVisible({ timeout: 60_000 })
    await expect(page.getByTestId('nav-bar').getByTestId('nav-cell-/land')).toHaveCount(0)
    await expect(page.getByTestId('land-jobs')).toHaveCount(0)
  })
})

for (const glass of GLASSES) {
  test.describe(`the land, lit, ${glass.width}px`, () => {
    test.use({ viewport: glass })

    test('Mining lists the catalogue, a press moves nothing, Send sends the party', async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      await serveWorldImage(page, await landLit())
      await page.goto('land')
      await ready(page)
      await expect(page.getByTestId('land-party')).toBeVisible({ timeout: 90_000 })
      if (glass.width < 1024) await expect(page.getByTestId('nav-bar').getByTestId('nav-cell-/land')).toBeVisible()
      await noSideways(page, 'the Party face')

      // 0461: Smithing is behind its own switch, dark here: no Smithing face
      await expect(page.getByRole('tab', { name: /Smithing/ })).toHaveCount(0)

      // the Mining face
      await page.getByRole('tab', { name: /Mining/ }).click()
      const jobs = page.getByTestId('land-job')
      await expect(jobs).toHaveCount(57, { timeout: 30_000 })
      const iron = page.locator('[data-testid="land-job"][data-job="iron"]')
      const coal = page.locator('[data-testid="land-job"][data-job="coal"]')
      const platinum = page.locator('[data-testid="land-job"][data-job="platinum"]')
      await expect(iron.getByTestId('land-job-land')).toContainText('Home land')
      await expect(coal.getByTestId('land-job-land')).toContainText('Far')
      await expect(coal.getByTestId('land-job-land')).toContainText('British Isles')
      await expect(platinum).toHaveAttribute('data-open', 'false')
      await expect(platinum.getByTestId('land-job-level')).toHaveText('Mining 1 / 96')
      await noSideways(page, 'the Mining face')

      // a press opens the tray over the page: the list does not move
      const before = await coal.boundingBox()
      await coal.click()
      const tray = page.getByTestId('land-send-tray')
      await expect(tray.getByTestId('land-send-passage')).toBeVisible()
      const after = await coal.boundingBox()
      expect(after?.y, 'pressing a job moved the list').toBe(before?.y)
      expect(after?.x).toBe(before?.x)
      await noSideways(page, 'the Send tray')

      // Send sends the party on the far trip; the Party face says it is on passage
      await tray.getByTestId('land-send').click()
      await expect(tray.getByTestId('land-send-passage')).toHaveCount(0, { timeout: 30_000 })
      await page.getByRole('tab', { name: /Party/ }).click()
      await expect(page.getByTestId('land-phase')).toHaveAttribute('data-phase', /out|march/, { timeout: 30_000 })
      await expect(page.getByTestId('land-far-line')).toContainText('British Isles')

      // a second Send is refused, in its place
      await page.getByRole('tab', { name: /Mining/ }).click()
      await iron.click()
      await page.getByTestId('land-send-tray').getByTestId('land-send').click()
      await expect(page.getByTestId('land-send-tray').getByTestId('land-send-short')).toBeVisible({ timeout: 30_000 })
      await noSideways(page, 'a refused Send')
    })

    // 0458 (L1c): Repeat and the mules on the Party face, the rare finds in the Send tray
    test('Repeat and a mule: a press moves nothing; a far job names its finds', async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      await serveWorldImage(page, await landLit())
      await page.goto('land')
      await ready(page)
      await expect(page.getByTestId('land-party')).toBeVisible({ timeout: 90_000 })
      const here = page.getByTestId('land-here')
      const repeat = page.getByTestId('land-repeat')
      await expect(repeat).toHaveAttribute('data-on', 'true')
      // each control is brought into view BEFORE it is measured, so the press itself scrolls nothing: what moves, re-flowed
      await repeat.scrollIntoViewIfNeeded()
      const hereAt = (await here.boundingBox())?.y
      const repeatAt = (await repeat.boundingBox())?.y

      // Repeat off: the server says off, nothing moved
      await repeat.getByRole('tab', { name: 'Off' }).click()
      await expect(repeat).toHaveAttribute('data-on', 'false', { timeout: 30_000 })
      expect((await repeat.boundingBox())?.y, 'Repeat moved itself').toBe(repeatAt)
      expect((await here.boundingBox())?.y, 'Repeat moved the page').toBe(hereAt)

      // a mule: 6 packs to 10, the next is 15; nothing moved
      await expect(page.getByTestId('land-packs-now')).toHaveText('Packs 6 → 10')
      await page.getByTestId('land-mule-buy').scrollIntoViewIfNeeded()
      const hereBefore = (await here.boundingBox())?.y
      await page.getByTestId('land-mule-buy').click()
      await expect(page.getByTestId('land-packs-now')).toHaveText('Packs 10 → 15', { timeout: 30_000 })
      expect((await here.boundingBox())?.y, 'a mule moved the page').toBe(hereBefore)
      await noSideways(page, 'Repeat and the mules')

      // Amber lies in the Baltic alone: its tray names the find of that land (Baltic Amber), and the packs are the mule's
      await page.getByRole('tab', { name: /Mining/ }).click()
      await page.locator('[data-testid="land-job"][data-job="amber"]').click()
      const tray = page.getByTestId('land-send-tray')
      await expect(tray.getByTestId('land-send-finds')).toContainText('Amber')
      await noSideways(page, 'a tray with finds')
    })
  })
}

// 0461 (L2): Smithing lit: its face lists the catalogue's 21 metal recipes, each with what one unit uses; a press opens the tray over
// the page and moves nothing; with nothing in Storage the tray says what each input holds against what it needs, and Send waits
for (const glass of GLASSES) {
  test.describe(`the smith, lit, ${glass.width}px`, () => {
    test.use({ viewport: glass })
    test('Smithing lists its recipes, a press moves nothing, nothing scrolls sideways', async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      await serveWorldImage(page, await smithLit())
      await page.goto('land')
      await ready(page)
      await expect(page.getByTestId('land-party')).toBeVisible({ timeout: 90_000 })
      const strip = page.getByRole('tab', { name: /Party/ })
      const stripAt = (await strip.boundingBox())?.y
      await page.getByRole('tab', { name: /Smithing/ }).click()
      const jobs = page.getByTestId('land-job')
      await expect(jobs).toHaveCount(21, { timeout: 30_000 })
      expect((await strip.boundingBox())?.y, 'the strip moved on a press').toBe(stripAt)
      const bars = page.locator('[data-testid="land-job"][data-job="iron-bars"]')
      await expect(bars.getByTestId('land-job-land')).toContainText('Uses')
      await expect(bars.getByTestId('land-job-land')).toContainText('Iron')
      await expect(page.locator('[data-testid="land-job"][data-job="steel-billets"]').getByTestId('land-job-level')).toHaveText('Smithing 1 / 10')
      await noSideways(page, 'the Smithing face')

      const before = await bars.boundingBox()
      await bars.click()
      const tray = page.getByTestId('land-send-tray')
      await expect(tray.getByTestId('land-send-can')).toHaveText('0')
      await expect(tray.getByTestId('land-send-input').first()).toContainText('0 /')
      await expect(tray.getByTestId('land-send')).toBeDisabled()
      await expect(tray.getByTestId('land-send-short')).toBeVisible()
      const after = await bars.boundingBox()
      expect(after?.y, 'pressing a recipe moved the list').toBe(before?.y)
      expect(after?.x).toBe(before?.x)
      await noSideways(page, 'the Send tray of a recipe')
    })
  })
}

test.describe('the bar, lit, on a phone', () => {
  for (const width of [320, 390]) {
    // SIX since 2026-11-23 (the visual overhaul's slice 2, X2): HQ · Trade · Fleets · Map · Land · Menu, the Office's faces HQ's doors
    test(`six cells at ${width} px, each a real tap target, no label cut`, async ({ browser, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      const page = await browser.newPage({ viewport: { width, height: 700 } })
      await serveWorldImage(page, await landLit())
      await page.goto('land')
      await ready(page)
      await expect(page.getByTestId('land-party')).toBeVisible({ timeout: 90_000 })
      const cells = page.locator('[data-testid="nav-bar"] > a, [data-testid="nav-bar"] > button')
      await expect(cells).toHaveCount(6)
      for (const c of await cells.all()) {
        const box = await c.boundingBox()
        expect(box?.width ?? 0, 'a cell under the 44-px reach floor').toBeGreaterThanOrEqual(44)
        const cut = await c.evaluate((el) => [...el.querySelectorAll('span')].some((s) => s.scrollWidth > s.clientWidth + 1))
        expect(cut, 'a nav label is cut').toBe(false)
      }
      await noSideways(page, `the bar at ${width}`)
      await page.close()
    })
  }
})

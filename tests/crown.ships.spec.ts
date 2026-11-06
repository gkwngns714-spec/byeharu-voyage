import { test, expect, type Locator, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A PLAYER BUILDS THE CROWN'S SHIPS: the cargo ship and the navy ship, named where a hull is chosen (migration 0332)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   *"you need to make ships too, so that players can build these cargo and navy ships too."* (the owner, 2026-11-06)
//
// The seam: the server names the classes (`crown`, from the knobs) and this walks what a player sees at the three design widths, DPR 2.
// Lisbon's yard, a fresh company: the three crown hulls stand first among the hulls built abroad, each with its word; a press opens the tray
// and moves nothing; the Codex finds them by filter and by word. Nothing scrolls sideways. The hulls are not built here: proof 39 runs the verb.

const GLASSES = [
  { width: 1440, height: 900 },
  { width: 1024, height: 768 },
  { width: 390, height: 844 },
] as const

async function noSideways(page: Page, what: string) {
  const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(over, `${what} scrolls sideways by ${over} px`).toBeLessThanOrEqual(0)
}

/** A press selects: what was pressed has not moved when the tray has opened. The tray rides over it (dont-restructure-on-press). */
async function pressKeepsPlace(page: Page, target: Locator, tray: string) {
  await target.scrollIntoViewIfNeeded()
  const before = await target.boundingBox()
  await target.click()
  await expect(page.getByTestId(tray)).toBeVisible()
  await page.waitForTimeout(400)
  const after = await target.boundingBox()
  expect(after?.x, 'the press moved the row sideways').toBe(before?.x)
  expect(after?.y, 'the press moved the row').toBe(before?.y)
}

async function yard(page: Page) {
  await page.goto('port')
  await ready(page)
  await page.getByRole('tablist', { name: 'City buildings' }).getByRole('tab', { name: 'Build', exact: true }).click()
  await expect(page.getByTestId('port-yard')).toBeVisible({ timeout: 60_000 })
}

async function ships(page: Page) {
  await page.goto('compendium')
  await ready(page)
  await page.getByTestId('codex').getByRole('tab', { name: 'Ships', exact: true }).click()
  await expect(page.getByTestId('ship-tile').first()).toBeVisible({ timeout: 60_000 })
}

for (const glass of GLASSES) {
  test.describe(`the crown's ships at ${glass.width}×${glass.height}`, () => {
    test.use({ viewport: glass, deviceScaleFactor: 2 })

    test('the yard names them, first, and a press moves nothing', async ({ page, request, baseURL }, info) => {
      test.setTimeout(170_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await yard(page)

      const elsewhere = page.getByTestId('yard-elsewhere')
      await expect(elsewhere.getByTestId('hull-crown')).toHaveCount(3)
      const order = await elsewhere.evaluate((el) =>
        Array.from(el.querySelectorAll('[data-testid^="hull-"]'))
          .map((e) => e.getAttribute('data-testid') ?? '')
          .filter((id) => !['hull-country', 'hull-tech', 'hull-crown'].includes(id)),
      )
      expect(order.slice(0, 3).sort(), 'the crown hulls do not stand first').toEqual(['hull-galion', 'hull-navire', 'hull-qpinnace'])
      await expect(page.getByTestId('hull-navire').getByTestId('hull-crown')).toHaveText('Cargo ship')
      await expect(page.getByTestId('hull-qpinnace').getByTestId('hull-crown')).toHaveText('Cargo ship')
      await expect(page.getByTestId('hull-galion').getByTestId('hull-crown')).toHaveText('Navy ship')
      await expect(page.getByTestId('hull-barca').getByTestId('hull-crown')).toHaveCount(0)
      // the word stays in one piece: at 1440 the narrow tile once split "Cargo / ship" across two lines of its pill
      for (const rects of await elsewhere.getByTestId('hull-crown').evaluateAll((els) => els.map((e) => e.getClientRects().length))) {
        expect(rects, 'a crown badge broke across lines').toBe(1)
      }
      await noSideways(page, 'the yard')
      await page.screenshot({ path: info.outputPath('yard.png') })

      // the same tray as any hull: her own to run, and the gates as served
      await pressKeepsPlace(page, page.getByTestId('hull-galion'), 'yard-tray')
      const tray = page.getByTestId('yard-tray')
      await expect(tray.getByTestId('yard-crown-note')).toContainText('you pay crew and supplies')
      await expect(tray.getByTestId('yard-country')).toBeVisible()
      await expect(tray.getByTestId('yard-needs')).toBeVisible()
      await noSideways(page, 'the yard tray')
      await page.screenshot({ path: info.outputPath('yard-tray.png') })
    })

    test('the Codex names them, a filter finds them, and a press moves nothing', async ({ page, request, baseURL }, info) => {
      test.setTimeout(170_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await ships(page)
      const rows = page.getByTestId('ship-tile')
      const pick = page.getByTestId('filter-pick-crown')
      await expect(pick).toBeVisible()
      await noSideways(page, 'the Codex')

      await pick.selectOption('CARGO')
      await expect(rows).toHaveCount(2)
      await pick.selectOption('NAVY')
      await expect(rows).toHaveCount(1)
      await expect(rows.first()).toContainText('Galion')
      await expect(rows.first().getByTestId('hull-crown')).toHaveText('Navy ship')
      await noSideways(page, 'the Codex, filtered')
      await page.screenshot({ path: info.outputPath('codex.png') })

      await pressKeepsPlace(page, rows.first(), 'ship-tray')
      await expect(page.getByTestId('codex-crown-build')).toBeVisible()
      await noSideways(page, 'the Codex tray')
      await page.screenshot({ path: info.outputPath('codex-tray.png') })
      await page.getByTestId('tray-close').click()

      // the word finds her too
      await pick.selectOption('all')
      await page.getByTestId('codex-search').fill('navy ship')
      await expect(rows).toHaveCount(1)
    })
  })
}

test.describe('the words, in Korean', () => {
  test.use({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, locale: 'ko-KR' })

  test('the yard and the Codex at 390', async ({ page, request, baseURL }, info) => {
    test.setTimeout(170_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.goto('port')
    await ready(page)
    await page.getByRole('tablist').getByRole('tab', { name: '건조', exact: true }).click()
    await expect(page.getByTestId('hull-navire').getByTestId('hull-crown')).toHaveText('화물선')
    await expect(page.getByTestId('hull-galion').getByTestId('hull-crown')).toHaveText('군함')
    await page.getByTestId('hull-navire').click()
    await expect(page.getByTestId('yard-crown-note')).toContainText('내 배입니다')
    await noSideways(page, 'the Korean yard')
    await page.screenshot({ path: info.outputPath('yard-ko.png') })
  })
})

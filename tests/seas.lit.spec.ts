import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import { ready, reachable, WORLD_BOOT_MS } from './appReady.fixture'
import { serveLitSeas } from './seasLit.fixture'

// THE SEA CONDITIONS, LIT, DRIVEN (docs/SEA_CONDITIONS_AND_REGIONS.md section 10; owner rows 166, 324).
//
// A throwaway local world with the one switch thrown (seasLit.fixture.ts). The founding company is title 1 with one
// barca at Lisbon, so:
//   - the Codex's Seas face lists every sea, Europe's open and the rest closed, each closed one saying what it asks
//   - the map shades the closed seas, and a harbour in one says why on a press: no passage is offered
//   - a harbour in open water still sails
// And in the shipped (dark) world none of it shows: no shade, no closed sea.
// Every figure asserted is the server's: the spec reads the wall's sea off `data-sea-wall`, never a sentence it wrote.
//
// Run it: npm run build, then npx vite preview --port 4423, then
//   PLAYWRIGHT_BASE_URL=http://localhost:4423/byeharu-voyage/ npx playwright test seas.lit.spec.ts

const SHOTS = process.env.SEAS_SHOTS ?? 'test-results'
const shot = (name: string) => `${SHOTS}/${name}.png`

async function openCodexSeas(page: Page) {
  await page.goto('compendium')
  await ready(page)
  await page.getByTestId('codex').getByRole('tab', { name: /^(Seas|바다)$/ }).click({ timeout: 30_000 })
  await expect(page.getByTestId('seas-state')).toBeVisible({ timeout: WORLD_BOOT_MS })
}

async function openChart(page: Page) {
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: WORLD_BOOT_MS })
}

/** Zoom out until the harbour's mark is on the glass, then tap it and press Send fleet. */
async function askCity(page: Page, code: string) {
  const chart = (await page.getByTestId('map-chart').boundingBox())!
  for (let i = 0; i < 8; i++) {
    const at = await page.evaluate((c) => {
      const g = document.querySelector(`[data-port-code="${c}"]`)
      if (!g) return null
      const r = g.getBoundingClientRect()
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 }
    }, code)
    if (at && at.x > chart.x + 8 && at.x < chart.x + chart.width - 8 && at.y > chart.y + 8 && at.y < chart.y + chart.height - 8) {
      await page.mouse.click(at.x, at.y)
      if (await page.getByTestId('map-detail-tray').isVisible().catch(() => false)) break
    }
    await page.mouse.move(chart.x + chart.width / 2, chart.y + chart.height / 2)
    await page.mouse.wheel(0, 600)
    await page.waitForTimeout(700)
  }
  await expect(page.getByTestId('map-detail-tray')).toBeVisible()
  await page.getByTestId('map-send-fleet').click()
  await expect(page.getByTestId('map-send-row').first()).toBeVisible()
  await expect(page.locator('[data-testid="map-send-passage"], [data-testid="map-send-refusal"]').first()).toBeVisible({ timeout: 180_000 })
}

const noSideScroll = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)

for (const glass of [
  { width: 390, height: 844, locale: 'en-US', tag: '390-en' },
  { width: 320, height: 640, locale: 'en-US', tag: '320-en' },
  { width: 390, height: 844, locale: 'ko-KR', tag: '390-ko' },
  { width: 320, height: 640, locale: 'ko-KR', tag: '320-ko' },
] as const) {
  const ko = glass.locale === 'ko-KR'
  test.describe(`the seas, lit, at ${glass.tag}`, () => {
    test.use({ viewport: { width: glass.width, height: glass.height }, locale: glass.locale })
    test.setTimeout(900_000)
    test.beforeAll(() => mkdirSync(SHOTS, { recursive: true }))

    test('the Codex lists every sea: Europe open, the rest closed, each closed sea saying what it asks', async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      await serveLitSeas(page)
      await openCodexSeas(page)
      await expect(page.getByTestId('seas-state')).toHaveAttribute('data-bite', 'yes')
      await expect(page.getByTestId('sea-row')).toHaveCount(64)
      // the server's verdicts for a title-1 barca: the twelve home seas open, fifty-two closed
      await expect(page.locator('[data-testid="sea-row"][data-open="yes"]')).toHaveCount(12)
      await expect(page.locator('[data-testid="sea-row"][data-open="no"]')).toHaveCount(52)
      await expect(page.locator('[data-testid="sea-row"][data-sea="MED"]')).toHaveAttribute('data-open', 'yes')
      const ocean = page.locator('[data-testid="sea-row"][data-sea="NOR-MID"]')
      await expect(ocean).toHaveAttribute('data-open', 'no')
      // title AND hull are short there: both asks and both pieces of advice are said
      await expect(ocean.getByTestId('sea-row-why')).toHaveText(ko ? /직함 4.*내파 30.*교역.*닻/ : /title 4.*wave resistance 30.*Trading.*anchors/)
      // a coastal sea a barca holds: only the title is short, and nothing is said of her hull
      const guinea = page.locator('[data-testid="sea-row"][data-sea="GUL"]')
      await expect(guinea.getByTestId('sea-row-why')).toHaveText(ko ? /직함 3/ : /title 3/)
      await expect(guinea.getByTestId('sea-row-why')).not.toHaveText(ko ? /내파/ : /wave resistance/)
      await expect(page.getByTestId('seas-title')).toContainText('1')
      await expect(page.getByTestId('seas-waves')).toContainText('12')
      expect(await noSideScroll(page), `the Seas face scrolls sideways at ${glass.tag}`).toBe(true)
      // no sea's name is cut: every label's box holds its text
      const cut = await page.evaluate(() =>
        [...document.querySelectorAll('[data-testid="sea-row"] [data-row-cell="label"]')].filter((e) => e.scrollWidth > e.clientWidth + 1).map((e) => e.textContent),
      )
      expect(cut, 'a sea name is cut').toEqual([])
      await page.screenshot({ path: shot(`codex-seas-${glass.tag}`) })
      await ocean.scrollIntoViewIfNeeded()
      await page.screenshot({ path: shot(`codex-seas-closed-${glass.tag}`) })
    })

    test('the map shades the closed seas; a harbour in one says why and offers no passage; one in open water sails', async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      await serveLitSeas(page)
      await openChart(page)
      const veil = page.getByTestId('map-closed-seas').first()
      await expect(veil).toBeAttached({ timeout: 120_000 })
      expect(Number(await veil.getAttribute('data-closed'))).toBe(52)

      // LAS PALMAS lies in Macaronesia (title 2): closed to a title-1 company
      await askCity(page, 'LPA')
      const row = page.getByTestId('map-send-row').first()
      const refusal = row.getByTestId('map-send-refusal')
      await expect(refusal).toBeVisible()
      await expect(refusal.locator('[data-sea-wall]')).toHaveAttribute('data-sea-wall', 'NOR-MAC')
      await expect(refusal).toHaveText(ko ? /직함 2 필요. 현재 1/ : /title 2\. Yours is 1/)
      await expect(row.getByTestId('map-send-passage')).toHaveCount(0)
      await expect(page.getByTestId('map-place-sea')).toHaveAttribute('data-closed', 'yes')
      expect(await noSideScroll(page), `the tray scrolls sideways at ${glass.tag}`).toBe(true)
      await page.screenshot({ path: shot(`map-closed-city-${glass.tag}`) })
      await page.getByTestId('map-detail-tray').getByTestId('tray-close').click()
      await page.screenshot({ path: shot(`map-shaded-${glass.tag}`) })

      // FUNCHAL lies in the European Atlantic (title 1): open, priced, and it sails
      await askCity(page, 'FNC')
      const open = page.getByTestId('map-send-row').first()
      await expect(open.getByTestId('map-send-refusal')).toHaveCount(0)
      await expect(open.getByTestId('map-send-passage')).toBeVisible()
      await expect(page.getByTestId('map-place-sea')).toHaveAttribute('data-closed', 'no')
      await page.screenshot({ path: shot(`map-open-city-${glass.tag}`) })
      if (glass.tag === '390-en') {
        await page.getByTestId('map-send-row-head').first().click()
        await page.getByTestId('map-send-ratio-send').click()
        await expect(page.getByTestId('map-send-row-note').first()).toBeVisible({ timeout: 60_000 })
        await expect(page.getByTestId('map-send-issue-refusal')).toHaveCount(0)
      }
    })
  })
}

test.describe('the shipped world: the sea conditions are dark', () => {
  test.use({ viewport: { width: 390, height: 844 }, locale: 'en-US' })
  test.setTimeout(600_000)

  test('no sea is shaded and none is called closed', async ({ page, request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await openCodexSeas(page)
    await expect(page.getByTestId('seas-state')).toHaveAttribute('data-bite', 'no')
    await expect(page.getByTestId('sea-row')).toHaveCount(64)
    await expect(page.locator('[data-testid="sea-row"][data-open]')).toHaveCount(0)
    await expect(page.getByTestId('seas-closed')).toHaveCount(0)
    await page.screenshot({ path: shot('codex-seas-dark-390-en') })
    await openChart(page)
    await page.waitForTimeout(3000)
    await expect(page.getByTestId('map-closed-seas')).toHaveCount(0)
  })
})

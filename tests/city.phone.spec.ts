import { expect, test, type Page } from '@playwright/test'
import { ready, reachable, settled } from './appReady.fixture'
import { GLASSES, phoneLaws as defects, readGlass, type Glass } from './unfold.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE HQ ON A PHONE — the law that keeps every building's face legible (2026-11-02)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, verbatim: *"you know that this game is also for mobile right?"* (row 247) · *"make it concise and
// simple so that it is easy to see in one eye without scrolling down"* (251) · *"the same screen dividends (city
// view, then right side the info) should stay the same for all"* (255) · *"compact EVERYWHERE; label and figure
// close … with full detail"* (258/260).
//
// WHY IT NEEDED A LAW. The split keeps the right panel at half the glass: 171 px at 390 and 136 px at 320. Every
// face was written for the wide column, and in the phone's panel the Market's good names stood one letter wide
// ("W / S / i / l / k"), its BUY and SELL tiles ran over the name and out of the panel, the Warehouse's "Space"
// was a column of letters under "0 / 750 tons", an Inn row read "Capt…" with nothing to press to read it, and the
// chart's axis labels stood on each other. None of the specs that existed measured the panel at that width.
//
// WHAT IT HOLDS — at 320×640, 390×844 and 1280×800, after pressing each of the six tiles, inside the right panel
// (and, on the Market, the chart on the glass's left):
//   (a) no two sibling boxes overlap by more than 2 px² — tiles, figures, labels, a chart's axis labels
//   (b) no text of three or more characters is laid out narrower than 1.4 × its font size (one letter per line)
//   (c) no text is cut without its full text: an ellipsis carries a `title` (a `Clip`: it opens in place on a press),
//       a row's LABEL is never cut at all, and nothing is clipped by the panel's edge
//   (d) the document never scrolls sideways, and neither does anything inside the panel
// plus the crossing of two text boxes (the Segmented's "Sell" under "Requests"), measured by the one apparatus the
// unfold slice made (tests/unfold.fixture.ts). The frame not moving between presses is city.density's, not repeated.
//
// THE PANEL AT 1280×800 IS HELD TOO: the wide look must not change, and a defect that only the phone showed is a
// defect that the wide glass proves it did not cause.

const TILES = ['hall', 'market', 'storage', 'forge', 'port', 'inn'] as const
type Tile = (typeof TILES)[number]

/** Press one building tile and wait until its panel has been drawn and its first read has landed. */
async function press(page: Page, tile: Tile) {
  await page.getByTestId(`city-building-${tile}`).click()
  const panel = page.getByTestId(tile === 'hall' ? 'city-hall-panel' : 'city-face-panel')
  await expect(panel, `the ${tile} panel is missing`).toBeVisible()
  if (tile !== 'hall') await expect(panel, `the ${tile} panel is not the pressed building`).toHaveAttribute('data-building', tile)
  await settled(panel)
  if (tile === 'market') await settled(page.getByTestId('city-market-chart'))
  await page.waitForTimeout(400)
}

/** Press the six tiles in turn and read the right panel (and the Market's chart and its three faces) at each. */
async function walk(page: Page, glass: Glass): Promise<string[]> {
  await page.setViewportSize(glass)
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('city-screen')).toBeVisible()
  await expect(page.getByTestId('city-hall-panel')).toBeVisible()
  await settled(page.getByTestId('city-hall-panel'))
  const found: string[] = []
  const at = `${glass.width}×${glass.height}`
  for (const tile of TILES) {
    await press(page, tile)
    const panel = tile === 'hall' ? 'city-hall-panel' : 'city-face-panel'
    found.push(...defects(`${at} ${tile}`, await readGlass(page, panel, null, `[data-testid="${panel}"]`)))
    if (tile !== 'market') continue
    // THE MARKET IS THREE FACES AND A CHART: the chart stands in the glass's left region, and Buy · Sell · Requests are
    // one Segmented in the panel — pressed by place, so the same walk holds in either language
    found.push(...defects(`${at} market chart`, await readGlass(page, 'city-market-chart', null, '[data-testid="city-info-image"]')))
    const faces = page.locator('[data-testid="city-face-panel"] [role="tablist"] [role="tab"]')
    const names = ['buy', 'sell', 'requests']
    for (const i of [1, 2, 0]) {
      if ((await faces.count()) <= i) continue
      await faces.nth(i).click()
      await page.waitForTimeout(500)
      found.push(...defects(`${at} market ${names[i]}`, await readGlass(page, 'city-face-panel', null, '[data-testid="city-face-panel"]')))
    }
    // THE REQUEST PAGE (the house's home city: Requests is a face of its own there) — its list of goods, then the chart step: a 256-px box once held a
    // 276–420-px card, and at 1280 the inputs sat over the span picker
    if ((await faces.count()) > 2) {
      await faces.nth(2).click()
      await page.getByTestId('city-request-new').click()
      await expect(page.getByTestId('city-request-page')).toBeVisible()
      await page.waitForTimeout(500)
      found.push(...defects(`${at} request page · goods`, await readGlass(page, 'city-request-page', null, '[data-testid="city-request-page"]')))
      await page.locator('[data-testid^="city-request-good-"]').first().click()
      await expect(page.getByTestId('city-request-chart')).toBeVisible()
      await settled(page.getByTestId('city-request-page'))
      await page.waitForTimeout(600)
      found.push(...defects(`${at} request page · chart`, await readGlass(page, 'city-request-page', null, '[data-testid="city-request-page"]')))
      await page.locator('[data-detail-back]').last().click()
      await expect(page.locator('[data-detail-page]')).toHaveCount(0)
      await faces.nth(0).click()
    }
  }
  return found
}

for (const glass of GLASSES) {
  test(`the HQ's six faces are legible and clean at ${glass.width}×${glass.height}`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    const found = await walk(page, glass)
    expect(found, `the HQ is not clean on a ${glass.width}-px glass:\n${found.join('\n')}`).toEqual([])
  })
}

// THE OWNER PLAYS IN KOREAN: the words are shorter and break by word (`word-break: keep-all`), so the same panel is walked in
// his language on the two phone glasses — the place the Market's names stood on top of the BUY tile.
test.describe('in Korean', () => {
  test.use({ locale: 'ko-KR' })
  for (const glass of GLASSES.filter((g) => g.width < 400)) {
    test(`the HQ's six faces are legible and clean at ${glass.width}×${glass.height}`, async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      const found = await walk(page, glass)
      expect(found, `the HQ is not clean on a ${glass.width}-px glass in Korean:\n${found.join('\n')}`).toEqual([])
    })
  }
})

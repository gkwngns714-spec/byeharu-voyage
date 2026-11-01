import { test, expect } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { GLASSES, openFace, readGlass } from './unfold.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// STATS, UNFOLDED — the owner's law, measured on every face at three glasses (2026-11-02)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"everything is folded in stats this is soo wrong. make it compact showing everything possible."*
// (owner row 260) and *"make things unfolded, minimize scrolling, everything compact with full info."*
// The laws of docs/dev-log/2026-11-01-ui-unfold.md, as lines of this file, for every Stats face at
// 390×844, 320×640 and 1280×800 (docs/dev-log/2026-11-01-unfold-stats.md has the budget they hold):
//
//   U2  THE PAGE NEVER SCROLLS — the document and the tab's Sheet are flat; nothing scrolls sideways.
//       The figure block may scroll INSIDE itself only on the short glass (320×640) — at 390×844 and
//       1280×800 every figure is on the glass without a scroll, which is the budget's claim.
//   U1  THE LIST IS ON THE SCREEN — its panel stands in the viewport with at least N of its rows whole
//       inside it, before any press. N is stated per face and per glass in `FACES` below.
//   U3  NOTHING IS REMOVED — every figure the old face had (by test id) is still on the face.
//   U5  NO OVERLAP, NO CUT TEXT — no two text boxes (clipped to the panes that hold them) cross; text
//       that is cut carries its full text.
//   U8  A PRESS OPENS ONE ITEM'S PAGE AND BACK RETURNS — a city's row; a chart's large view; neither
//       moves what stands under it.
//
// It replaces what `onepage` and `consistency` used to prove of Stats by walking summary rows, which
// are gone from this tab by law (U1).

interface Face {
  tab: string
  /** The panel (a `ListPanel`) and the row whose count the law holds. `row: null` where a fresh world has none. */
  panel: string
  row: string | null
  /** How many rows must stand WHOLE inside the panel's body, per glass width. */
  rows: Record<number, number>
  /** Every figure / block the old face had, by test id — still on the face. */
  ids: readonly string[]
}

const FACES: readonly Face[] = [
  {
    tab: 'Overview',
    panel: 'money-log',
    row: 'money-move',
    rows: { 390: 2, 320: 1, 1280: 8 },
    ids: ['stats-live', 'stats-live-purse', 'stats-live-world', 'stats-live-sea', 'stats-live-trades', 'stats-money', 'stats-new-money', 'stats-watch', 'stats-overview'],
  },
  {
    tab: 'Markets',
    panel: 'stats-goods',
    row: 'stats-good',
    rows: { 390: 4, 320: 1, 1280: 6 },
    ids: ['stats-markets', 'stats-markets-day', 'stats-markets-window', 'stats-movers', 'stats-risers', 'stats-fallers', 'stats-most-traded', 'stats-markets-filters', 'stats-markets-sort'],
  },
  {
    tab: 'Cities',
    panel: 'stats-cities',
    row: 'stats-city-open',
    rows: { 390: 6, 320: 2, 1280: 6 },
    ids: ['stats-cities', 'stats-cities-filters', 'stats-cities-sort'],
  },
  {
    tab: 'Merchants',
    panel: 'stats-merchants-all',
    row: 'stats-merchant',
    rows: { 390: 3, 320: 1, 1280: 6 },
    ids: ['stats-merchants', 'stats-merchant-figures', 'stats-merchant-fold', 'stats-merchant-states', 'stats-merchants-filters', 'stats-merchants-sort'],
  },
  {
    tab: 'Me',
    panel: 'stats-best-trades',
    row: null,
    rows: { 390: 0, 320: 0, 1280: 0 },
    ids: ['stats-me', 'stats-me-week', 'stats-me-bars'],
  },
]

for (const glass of GLASSES) {
  test(`every Stats face is unfolded at ${glass.width}×${glass.height}: flat page, its list on the glass, every old figure, no overlap`, async ({ page, request, baseURL }) => {
    test.setTimeout(900_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(glass)
    await page.goto('stats')
    await ready(page)
    await expect(page.getByTestId('stats')).toBeVisible()

    const failures: string[] = []
    let panelsMet = 0
    for (const face of FACES) {
      await openFace(page, face.tab)
      const where = `${face.tab} @${glass.width}×${glass.height}`
      const m = await readGlass(page, face.panel, face.row)
      console.log(`UNFOLD ${where}: doc ${m.doc.sh}/${m.doc.ch}, sheet ${m.sheet?.sh}/${m.sheet?.ch}, above ${m.above ? `${m.above.sh}/${m.above.ch}` : '-'}, rows ${m.rows.whole}/${m.rows.total}`)

      // U2 — the page is flat
      if (m.doc.sh > m.doc.ch + 1) failures.push(`${where}: the document scrolls ${m.doc.sh}/${m.doc.ch}`)
      if (m.doc.sw > m.doc.cw + 1) failures.push(`${where}: the document scrolls sideways ${m.doc.sw}/${m.doc.cw}`)
      if (m.sheet === null) failures.push(`${where}: no Sheet`)
      else {
        if (m.sheet.top > 0) failures.push(`${where}: the Sheet arrived scrolled`)
        if (m.sheet.sh > m.sheet.ch + 1) failures.push(`${where}: the Sheet scrolls ${m.sheet.sh}/${m.sheet.ch}`)
      }
      for (const s of m.sideways) failures.push(`${where}: ${s} scrolls sideways`)
      // the budget's claim: on a tall phone and on a desktop the figure block is whole (the short glass may scroll it, inside itself)
      if (glass.height >= 800 && m.above !== null && m.above.sh > m.above.ch + 1)
        failures.push(`${where}: the figures do not fit — their block scrolls ${m.above.sh}/${m.above.ch}`)

      // U1 — the list is on the glass, with its rows
      if (!m.rows.found) failures.push(`${where}: no list panel (${face.panel})`)
      else {
        panelsMet++
        if (!m.rows.inView) failures.push(`${where}: the list panel is not inside the glass`)
        const need = face.rows[glass.width]
        if (m.rows.whole < need) failures.push(`${where}: ${m.rows.whole} whole rows of ${m.rows.total} stand in the list; the law is ${need}`)
      }

      // U3 — nothing was removed
      for (const id of face.ids) {
        if ((await page.getByTestId(id).count()) === 0) failures.push(`${where}: the old figure ${id} is gone`)
      }

      // U5 — no overlap, no cut text
      for (const o of m.overlaps) failures.push(`${where}: text overlaps ${o}`)
      for (const c of m.cuts) failures.push(`${where}: cut text with no full text ${c}`)
    }

    // NON-VACUITY: five panels were found and measured
    expect(panelsMet, 'the walk measured fewer than five list panels — did the faces render?').toBe(FACES.length)
    expect(failures, 'the Stats faces are not unfolded').toEqual([])
  })
}

test('the Overview keeps its four holders, its charts and its stacked bar on the face — no press', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(GLASSES[0])
  await page.goto('stats')
  await ready(page)
  await expect(page.getByTestId('stats-overview')).toBeVisible({ timeout: 120_000 })
  // the world's money by holder: ONE stacked bar and its four figures, each beside its own line
  await expect(page.getByTestId('stats-holder')).toHaveCount(4)
  await expect(page.getByTestId('stats-money').locator('[role="img"]').first()).toBeVisible()
  // the purse line, the sold line and the bought line are three mini charts, each a press to its large view
  expect(await page.getByTestId('stats-chart-tap').count()).toBeGreaterThanOrEqual(3)
  // the day's four figures and the net bars
  const flows = page.getByTestId('stats-new-money')
  for (const word of [/Printed/, /Burned/, /Moved/, /Trades/]) await expect(flows).toContainText(word)
  await expect(flows.locator('[role="img"]').first()).toBeVisible()
  // the economy watch: the figures the server served, none of them a dash
  const watch = page.getByTestId('stats-watch')
  await expect(watch).toContainText(/New money/)
  expect(((await watch.innerText()) ?? '').includes('—'), 'the watch prints a dash where a figure is owed').toBe(false)
})

test('a row press opens its page and Back returns; a chart press opens the large chart and moves nothing', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(GLASSES[0])
  await page.goto('stats')
  await ready(page)

  // THE CHART: pressed, it opens the large view in a tray; the figures under it keep their places
  await expect(page.getByTestId('stats-overview')).toBeVisible({ timeout: 120_000 })
  const holder = () => page.getByTestId('stats-holder').first().boundingBox()
  const before = await holder()
  await page.getByTestId('stats-chart-tap').first().click()
  const big = page.getByTestId('stats-big-chart')
  await expect(big).toBeVisible()
  await expect(big.getByTestId('span-picker')).toBeVisible()
  expect(await holder(), 'a chart press moved the figures under it').toEqual(before)
  await page.getByTestId('tray-close').click()
  await expect(big).toHaveCount(0)

  // THE SHORT GLASS: where the figure block SCROLLS inside itself (320×640) the tray it opens must still be on
  // the glass and under a finger. (A `mask-image` fade on that block once clipped the fixed tray to the block's own
  // box — drawn and unpressable — which the wide-glass chart spec found at 1280×707.) Playwright's click is the
  // proof: it fails if anything else is on top at the point it presses.
  await page.setViewportSize(GLASSES[1])
  await page.getByTestId('stats-chart-tap').first().click()
  await expect(big).toBeVisible()
  await big.getByTestId('span-picker').getByRole('tab', { name: '1 week', exact: true }).click({ timeout: 10_000 })
  await big.getByTestId('span-picker').getByRole('tab', { name: '1 day', exact: true }).click({ timeout: 10_000 })
  await page.getByTestId('tray-close').click({ timeout: 10_000 })
  await expect(big).toHaveCount(0)
  await page.setViewportSize(GLASSES[0])

  // THE ROW: a city's row opens THAT city's page; Back returns to the list as it was
  await openFace(page, 'Cities')
  const rows = page.getByTestId('stats-city-open')
  await expect.poll(() => rows.count(), { timeout: 60_000 }).toBeGreaterThan(10)
  const first = (await rows.first().getByTestId('stats-city-name').innerText()).trim()
  await rows.first().click()
  const pageEl = page.getByTestId('stats-city-page')
  await expect(pageEl).toBeVisible()
  await expect(pageEl.getByTestId('stats-city-overview')).toBeVisible({ timeout: 60_000 })
  await expect(pageEl.locator('[data-detail-back]')).toBeVisible()
  await expect(pageEl.getByRole('heading', { level: 1 })).toContainText(first)
  await page.locator('[data-detail-back]').last().click()
  await expect(page.locator('[data-detail-page]')).toHaveCount(0)
  await expect(page.getByTestId('stats-cities')).toBeVisible()
  expect(await rows.count(), 'Back returned to a shorter list').toBeGreaterThan(10)

  // THE PANEL'S VIEWS: the Merchants' best and worst days are views of the one panel, not pages
  await openFace(page, 'Merchants')
  await page.getByRole('tab', { name: 'Best day', exact: true }).click()
  await expect(page.getByTestId('stats-merchants-top')).toBeVisible()
  await page.getByRole('tab', { name: 'Worst day', exact: true }).click()
  await expect(page.getByTestId('stats-merchants-bottom')).toBeVisible()
  await page.getByRole('tab', { name: 'Companies', exact: true }).click()
  await expect(page.getByTestId('stats-merchants-all')).toBeVisible()
  expect(await page.locator('[data-detail-page]').count(), 'a view opened a page').toBe(0)
})

test('the band is live: its "Updated" line moves on its own', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(GLASSES[0])
  await page.goto('stats')
  await ready(page)
  const line = page.getByTestId('stats-updated')
  await expect(line).toContainText(/Updated \d\d:\d\d:\d\d/, { timeout: 60_000 })
  const first = await line.innerText()
  // asked every second (statsLive.ts): the served instant is a different second a few seconds on
  await expect.poll(async () => line.innerText(), { timeout: 15_000, intervals: [1000] }).not.toBe(first)
})

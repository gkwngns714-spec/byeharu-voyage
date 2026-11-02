import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { phoneLaws, readGlass } from './unfold.fixture'
import { DESIGN_GLASSES, ROW_MAX_REM, boxesOf, readDesign, trayBox } from './design.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// STATS IS A PAGE — the owner's design order, measured on every face at five glasses, in English and Korean (2026-11-02)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake."* (owner, 2026-11-02, row 267.)
//
// THIS FILE REPLACES `stats.unfold.spec.ts`. That spec was written on 2026-11-02 for the order *"make it compact showing
// everything possible"* (rows 249-260) and held the packed design: U2 "THE PAGE NEVER SCROLLS" (the document, the Sheet and
// the figure block flat), U1 "N whole rows of the list on the glass before a press" (rows per glass, 6 to 8 at 1,280), and the
// 12-rem floor of the list panel. Row 267 reverses exactly that — *"too packed"* — so U1 and U2 are gone, with the sweep's
// "empty glass" row they leaned on. What it was right about stands here, restated: U3 (nothing removed), U5 (no overlap, no
// cut text), U8 (a press opens one item's page and Back returns; a chart opens its large view and moves nothing).
//
// THE NEW LAWS (docs/dev-log/2026-11-02-stats-design.md; screenLayout.ts "THE PAGE"), at 1,440×900, 1,280×800, 1,024×768,
// 390×844 and 320×640:
//   (a) USE THE WIDTH. From 1,024 px the content block (the visible text of the sheet, leftmost to rightmost) is centred — the
//       band empty at its right is no wider than the margin at its left, so nothing is kept clear for a tray that is shut — and
//       from 1,280 it spans at least 80 % of the glass. (The unfold column spanned 59 % at 1,280 with 476 px empty at the right.)
//   (b) THE DEFECT RULES STAND: no sideways scroll, no two text or figure boxes crossing, no text narrower than 1.4 × its font
//       size (the one-letter wrap), no cut text without its full text, every control at least 44 × 44.
//   (c) THE HIERARCHY: a key figure at least 24 px, its label at least 13 px, a list row at least 52 px — and no list row wider
//       than 36 rem, so the 2026-09-13 complaint ("too much blank space" between a name and its price) cannot come back.
//   (d) A TRAY OPENED FROM A CHART MOVES NOTHING BEHIND IT, and from 1,024 it slides over the page's SIDE column — the same x and
//       width — because the side is the tray's column.
//   (f) NO SCROLL TRAP: nothing but the sheet scrolls — the page scrolls (the owner, 2026-11-02: a long stack may), a list never
//       scrolls inside itself.
//
// WHICH WERE RED BEFORE: the same file, run against the build of origin/main 3e05ab32 (the packed column), fails (a), (c) (the
// figures are 16 px, the labels 12, the log rows 49), (d)'s side column and (f) (the lists scroll inside themselves; at 320 the
// figures block too) at every glass; (b) and the no-move half of (d) were already green there — they are guards, kept from
// the sweep. The numbers are in the dev-log.

const FIGURES = ['stats-live-purse', 'stats-live-sea', 'stats-live-trades', 'stats-live-world'] as const
const ROWS = ['money-move', 'stats-good', 'stats-city-open', 'stats-merchant'] as const

/** The five faces, by their place in the tab strip (a Korean strip has other words), the panel and row each stands, and every
 *  figure / block the old faces had by test id — still on the face (U3). */
const FACES = [
  { name: 'Overview', panel: 'money-log', row: 'money-move', ids: ['stats-live', 'stats-live-purse', 'stats-live-world', 'stats-live-sea', 'stats-live-trades', 'stats-money', 'stats-holder', 'stats-new-money', 'stats-watch', 'stats-overview'] },
  { name: 'Markets', panel: 'stats-goods', row: 'stats-good', ids: ['stats-markets', 'stats-markets-day', 'stats-markets-window', 'stats-risers', 'stats-fallers', 'stats-most-traded', 'stats-markets-filters', 'stats-markets-sort'] },
  { name: 'Cities', panel: 'stats-cities', row: 'stats-city-open', ids: ['stats-cities', 'stats-cities-filters', 'stats-cities-sort'] },
  { name: 'Merchants', panel: 'stats-merchants-all', row: 'stats-merchant', ids: ['stats-merchants', 'stats-merchant-figures', 'stats-merchant-fold', 'stats-merchant-states', 'stats-merchants-filters', 'stats-merchants-sort'] },
  { name: 'Me', panel: 'stats-best-trades', row: null, ids: ['stats-me', 'stats-me-week', 'stats-me-bars'] },
] as const

const SHEET = '[data-testid="stats"]'


async function open(page: Page, glass: { width: number; height: number }) {
  await page.setViewportSize(glass)
  await page.goto('stats')
  await ready(page)
  await expect(page.getByTestId('stats')).toBeVisible()
}

async function openFace(page: Page, index: number) {
  await page.getByRole('tablist').first().getByRole('tab').nth(index).click()
  await page.waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 }).catch(() => {})
  await page.waitForTimeout(700)
}

for (const locale of ['en-US', 'ko-KR'] as const) {
  test.describe(`Stats is a page — ${locale}`, () => {
    test.use({ locale })

    for (const glass of DESIGN_GLASSES) {
      test(`every Stats face, at ${glass.width}×${glass.height}: the glass used, the hierarchy, no overlap, no trap, a tray over the side`, async ({ page, request, baseURL }) => {
        test.setTimeout(900_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        await open(page, glass)

        const failures: string[] = []
        let figuresMet = 0
        let rowsMet = 0
        for (const [i, face] of FACES.entries()) {
          await openFace(page, i)
          const where = `${locale} ${face.name} @${glass.width}×${glass.height}`
          const d = await readDesign(page, { sheet: SHEET, figureIds: FIGURES, rowIds: ROWS })
          const flat = await readGlass(page, face.panel, face.row, SHEET)
          console.log(
            `DESIGN ${where}: span ${d.span ? `${Math.round(d.span.left)}..${Math.round(d.span.right)}` : '-'} · figures ${d.figures.map((f) => f.font).join('/')} · rows ${d.rows.length}x${d.rows.length ? Math.round(Math.min(...d.rows.map((r) => r.h))) : '-'} · scrollers ${d.scrollers.length}`,
          )

          // (a) USE THE WIDTH — from 1,024 the block is centred (nothing kept clear at the right), from 1,280 it spans 80 % of the glass
          if (d.span === null) failures.push(`${where}: (a) the sheet has no visible text`)
          else if (glass.width >= 1024) {
            const band = d.glass.w - d.span.right
            const share = (d.span.right - d.span.left) / d.glass.w
            if (band > d.span.left + 2) failures.push(`${where}: (a) ${Math.round(band)} px are empty at the right of the content and ${Math.round(d.span.left)} at its left — a column is kept clear for a tray`)
            if (glass.width >= 1280 && share < 0.8) failures.push(`${where}: (a) the content spans ${(share * 100).toFixed(0)} % of the glass — the law is 80 %`)
          }

          // (b) THE DEFECT RULES: overlap, one-letter wrap, cut text, sideways scroll, the 44-px floor — and the document is flat (the SHEET scrolls)
          // (the fixture numbers its laws a-d; they are all (b) here — the defect rules of the 2026-11-02 sweep)
          failures.push(...phoneLaws(where, flat).map((m) => m.replace(/: \([abcd]\) /, ': (b) ')))
          if (flat.doc.sh > flat.doc.ch + 1) failures.push(`${where}: (b) the document scrolls ${flat.doc.sh}/${flat.doc.ch}`)
          if (flat.sheet !== null && flat.sheet.top > 0) failures.push(`${where}: (b) the Sheet arrived scrolled`)
          for (const c of d.smallControls) failures.push(`${where}: (b) a control under 44 px — ${c}`)

          // (c) THE HIERARCHY — key figures 24 px, their labels 13, a list row 52 and no wider than 35 rem
          for (const f of d.figures) {
            figuresMet++
            if (f.font < 24) failures.push(`${where}: (c) the figure ${f.id} is ${f.font} px — the law is 24`)
            if (f.label !== null && f.label < 13) failures.push(`${where}: (c) the label of ${f.id} is ${f.label} px — the law is 13`)
          }
          // (a row is counted once per rule: the worst one is named, the rest are a number)
          const short = d.rows.filter((r) => r.h < 52 - 0.5)
          const wide = d.rows.filter((r) => r.w > ROW_MAX_REM * 16 + 1)
          rowsMet += d.rows.length
          if (short.length > 0) failures.push(`${where}: (c) ${short.length} list rows are under 52 px — the shortest is a ${short[0].id} row of ${Math.round(Math.min(...short.map((r) => r.h)))}`)
          if (wide.length > 0) failures.push(`${where}: (c) ${wide.length} list rows are wider than ${ROW_MAX_REM} rem — the widest is a ${wide[0].id} row of ${Math.round(Math.max(...wide.map((r) => r.w)))} px`)

          // (f) NO SCROLL TRAP — only the sheet scrolls
          for (const s of d.scrollers) failures.push(`${where}: (f) a box scrolls inside itself — ${s}`)

          // U3 — NOTHING WAS REMOVED
          for (const id of face.ids) {
            if ((await page.getByTestId(id).count()) === 0) failures.push(`${where}: U3 the figure ${id} is gone`)
          }
          // U5 — cut text carries its full text; overlaps are in phoneLaws
        }

        // NON-VACUITY: the walk measured the live strip on every face and a list's rows on four of them
        expect(figuresMet, 'the walk measured no stat figures — did the strip render?').toBeGreaterThanOrEqual(FACES.length * FIGURES.length)
        expect(rowsMet, 'the walk measured almost no list rows — did the lists render?').toBeGreaterThan(8)
        expect(failures, 'Stats is not the page the owner asked for').toEqual([])
      })
    }
  })
}

// (d) A TRAY OPENED FROM A CHART MOVES NOTHING BEHIND IT; from 1,024 it stands over the SIDE column — same x, same width
for (const glass of DESIGN_GLASSES) {
  test(`a chart's tray moves nothing behind it and stands over the side column, at ${glass.width}×${glass.height}`, async ({ page, request, baseURL }) => {
    test.setTimeout(480_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await open(page, glass)
    await expect(page.getByTestId('stats-overview')).toBeVisible({ timeout: 120_000 })
    // the watch and the log stand after the first live read: measure once they do, or a card arriving would read as a move
    await expect(page.getByTestId('stats-watch')).toBeVisible({ timeout: 60_000 })
    await expect(page.getByTestId('money-log')).toBeVisible({ timeout: 60_000 })
    const ids = ['stats-live-purse', 'stats-live-world', 'stats-money', 'stats-new-money', 'stats-watch', 'money-log']
    const taps = page.getByTestId('stats-chart-tap')
    await expect.poll(() => taps.count(), { timeout: 60_000 }).toBeGreaterThanOrEqual(3)
    // bring the first chart under the finger FIRST, then measure: a scroll the browser makes to reach a control is not a move
    await taps.first().scrollIntoViewIfNeeded()
    await page.waitForTimeout(400)
    const before = await boxesOf(page, SHEET, ids)
    const side = (await readDesign(page, { sheet: SHEET, figureIds: [], rowIds: [] })).side
    await taps.first().click()
    const big = page.getByTestId('stats-big-chart')
    await expect(big).toBeVisible()
    await expect(big.getByTestId('span-picker')).toBeVisible()
    await page.waitForTimeout(500)
    expect(await boxesOf(page, SHEET, ids), 'a chart press moved the cards behind its tray').toEqual(before)
    const tray = await trayBox(page)
    expect(tray, 'the tray has no box').not.toBeNull()
    if (glass.width >= 1024) {
      expect(side, 'the page has no side column for the tray to stand over').not.toBeNull()
      expect(Math.abs(tray!.l - side!.l), `the tray stands at x=${Math.round(tray!.l)} and the side column at x=${Math.round(side!.l)}`).toBeLessThanOrEqual(2)
      expect(Math.abs(tray!.w - side!.w), `the tray is ${Math.round(tray!.w)} px wide and the side column ${Math.round(side!.w)}`).toBeLessThanOrEqual(2)
    } else {
      expect(tray!.t + tray!.h, 'the tray hangs below the glass').toBeLessThanOrEqual(glass.height + 1)
    }
    await page.getByTestId('tray-close').click({ timeout: 10_000 })
    await expect(big).toHaveCount(0)
    expect(await boxesOf(page, SHEET, ids), 'closing the tray moved the cards').toEqual(before)
  })
}

// U8 — A PRESS OPENS ONE ITEM'S PAGE AND BACK RETURNS (a city's row); a view of a panel is not a page (the Merchants' best and worst day)
test('a city row opens its page and Back returns; the Merchants views are views, not pages', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await open(page, { width: 1280, height: 800 })
  await openFace(page, 2)
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

  await openFace(page, 3)
  await page.getByRole('tab', { name: 'Best day', exact: true }).click()
  await expect(page.getByTestId('stats-merchants-top')).toBeVisible()
  await page.getByRole('tab', { name: 'Worst day', exact: true }).click()
  await expect(page.getByTestId('stats-merchants-bottom')).toBeVisible()
  await page.getByRole('tab', { name: 'Companies', exact: true }).click()
  await expect(page.getByTestId('stats-merchants-all')).toBeVisible()
  expect(await page.locator('[data-detail-page]').count(), 'a view opened a page').toBe(0)
})

// THE SHORT GLASS: a chart's tray must be on the glass and under a finger at 320×640 (a `mask-image` fade once clipped the fixed tray to
// its scroller's box — drawn and unpressable; Playwright's click is the proof: it fails if anything else is on top at the point it presses)
test('the large chart opens and answers a press on the short glass', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await open(page, { width: 320, height: 640 })
  await expect(page.getByTestId('stats-overview')).toBeVisible({ timeout: 120_000 })
  await page.getByTestId('stats-chart-tap').first().click()
  const big = page.getByTestId('stats-big-chart')
  await expect(big).toBeVisible()
  await big.getByTestId('span-picker').getByRole('tab', { name: '1 week', exact: true }).click({ timeout: 10_000 })
  await big.getByTestId('span-picker').getByRole('tab', { name: '1 day', exact: true }).click({ timeout: 10_000 })
  await page.getByTestId('tray-close').click({ timeout: 10_000 })
  await expect(big).toHaveCount(0)
})

test('the Overview keeps its four holders, its charts, its stacked bar and its watch on the face — no press', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await open(page, { width: 1280, height: 800 })
  await expect(page.getByTestId('stats-overview')).toBeVisible({ timeout: 120_000 })
  await expect(page.getByTestId('stats-holder')).toHaveCount(4)
  await expect(page.getByTestId('stats-money').locator('[role="img"]').first()).toBeVisible()
  expect(await page.getByTestId('stats-chart-tap').count()).toBeGreaterThanOrEqual(3)
  const flows = page.getByTestId('stats-new-money')
  for (const word of [/Printed/, /Burned/, /Moved/, /Trades/]) await expect(flows).toContainText(word)
  await expect(flows.locator('[role="img"]').first()).toBeVisible()
  const watch = page.getByTestId('stats-watch')
  await expect(watch).toContainText(/New money/)
  expect(((await watch.innerText()) ?? '').includes('—'), 'the watch prints a dash where a figure is owed').toBe(false)
})

test('the band is live: its "Updated" line moves on its own', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await open(page, { width: 1280, height: 800 })
  const line = page.getByTestId('stats-updated')
  await expect(line).toContainText(/Updated \d\d:\d\d:\d\d/, { timeout: 60_000 })
  const first = await line.innerText()
  // asked every second (statsLive.ts): the served instant is a different second a few seconds on
  await expect.poll(async () => line.innerText(), { timeout: 15_000, intervals: [1000] }).not.toBe(first)
})

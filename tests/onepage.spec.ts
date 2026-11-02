import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ONE PAGE — the owner's law, measured on every main tab, every face and every pop-up page
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i hate to scroll down on things, make it so that all the info is packed on one page. all the
// game"* — then, on the mechanism: *"make everything small, compact and once clicked show new page
// popping up."* The laws this file holds, at 390×844 and 1280×800:
//
//   1. THE DOCUMENT NEVER SCROLLS — scrollHeight ≤ clientHeight + 1 and the same for width.
//   1b. THE TAB'S OWN SHEET NEVER SCROLLS — `Sheet` carries `data-sheet`; scrollHeight equals
//      clientHeight at rest, scrollTop 0, on every route and every face (all but Map and the City
//      page, which are one glass).
//   1c. EVERY SUMMARY ROW OPENS A PAGE, AND THE PAGE ITSELF DOES NOT SCROLL — `[data-detail-page]`
//      is fixed, its own root does not overflow, and its content scrolls inside (a ScrollPane).
//   2. THE MAIN LANDMARK IS THERE AND VISIBLE on every tab.
//   3. EVERY SET OF TAPPABLE CHOICES IS AN ORDERED GRID — each `[data-choice-grid]` has equal cells
//      on shared column lines, every cell ≥ 44 px — on the compact screen and inside every page.
//
// The City page already carried its own no-scroll proof (tests/city.page.spec.ts) and is asserted
// here too, without touching src/features/city/** (another slice owns those files).

const ROUTES = ['command', 'fleets', 'map', 'stats', 'ledger', 'rank', 'routes', 'compendium', 'profile', 'city'] as const
const SIZES = [
  { width: 390, height: 844 },
  { width: 1280, height: 800 },
] as const

interface DocReport {
  docW: number
  docH: number
  clientW: number
  clientH: number
  scrollY: number
  main: { top: number; bottom: number; width: number; height: number } | null
  sheet: { h: number; ch: number; top: number; page: boolean } | null
  grids: { label: string; cells: { l: number; t: number; w: number; h: number }[] }[]
}

async function read(page: Page): Promise<DocReport> {
  return page.evaluate(() => {
    const de = document.documentElement
    const visible = (el: Element) => {
      const r = el.getBoundingClientRect()
      return r.width > 1 && r.height > 1 && r.bottom > 0 && r.top < window.innerHeight
    }
    const main = document.querySelector('main')
    const box = main?.getBoundingClientRect() ?? null
    const sheet = document.querySelector('[data-sheet]') as HTMLElement | null
    const grids = [...document.querySelectorAll('[data-choice-grid]')]
      .filter(visible)
      .map((g) => ({
        label: g.getAttribute('aria-label') ?? g.getAttribute('data-testid') ?? 'grid',
        cells: [...g.querySelectorAll(':scope > button')]
          .filter(visible)
          .map((c) => {
            const r = c.getBoundingClientRect()
            return { l: Math.round(r.left), t: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) }
          }),
      }))
    return {
      docW: de.scrollWidth,
      docH: de.scrollHeight,
      clientW: de.clientWidth,
      clientH: de.clientHeight,
      scrollY: window.scrollY,
      main: box === null ? null : { top: Math.round(box.top), bottom: Math.round(box.bottom), width: Math.round(box.width), height: Math.round(box.height) },
      sheet: sheet === null ? null : { h: sheet.scrollHeight, ch: sheet.clientHeight, top: sheet.scrollTop, page: sheet.getAttribute('data-sheet-layout') === 'page' },
      grids,
    }
  })
}

type GridReport = DocReport['grids'][number]

/** THE GRID LAW: equal cells, one line, ordered lefts, every cell ≥ 44 px. Returns the count. */
function assertGrids(grids: readonly GridReport[], _size: { width: number }, where: string): number {
  let n = 0
  for (const g of grids) {
    if (g.cells.length < 2) continue
    n++
    const [a, b] = g.cells
    expect(Math.abs(a.w - b.w), `${where}: grid "${g.label}" first two cells differ in width (${a.w} vs ${b.w})`).toBeLessThanOrEqual(1)
    expect(Math.abs(a.h - b.h), `${where}: grid "${g.label}" first two cells differ in height (${a.h} vs ${b.h})`).toBeLessThanOrEqual(1)
    expect(Math.abs(a.t - b.t), `${where}: grid "${g.label}" first two cells are not on one line`).toBeLessThanOrEqual(1)
    expect(b.l, `${where}: grid "${g.label}" second cell is not right of the first`).toBeGreaterThan(a.l)
    for (const c of g.cells) {
      expect(c.h, `${where}: grid "${g.label}" a cell is ${c.h}px tall, under the 44px floor`).toBeGreaterThanOrEqual(44)
      expect(c.w, `${where}: grid "${g.label}" a cell is ${c.w}px wide, under the 44px floor`).toBeGreaterThanOrEqual(44)
    }
  }
  return n
}

/** EVERY SUMMARY ROW OPENS A PAGE, AND THE PAGE ITSELF DOES NOT SCROLL. Walks the compact screen's
 *  rows, opens each as a player does, holds the page to the no-scroll law, closes with the back
 *  press, and returns how many pages it measured. */
async function walkPages(page: Page, size: { width: number; height: number }): Promise<number> {
  const rows = page.locator('[data-summary-row]')
  const count = await rows.count()
  let opened = 0
  for (let i = 0; i < count; i++) {
    const row = rows.nth(i)
    if (!(await row.isVisible())) continue
    const label = (await row.getAttribute('data-testid')) ?? `summary #${i}`
    await row.click()
    const dialog = page.locator('[data-detail-page]')
    await expect(dialog, `${label} opened no page at ${size.width}px`).toBeVisible()
    await expect(dialog.locator('[data-detail-back]'), `${label}'s page has no back press`).toBeVisible()
    await page.waitForTimeout(150)
    const m = await read(page)
    const root = await page.evaluate(() => {
      const pg = document.querySelector('[data-detail-page]') as HTMLElement
      return { h: pg.scrollHeight, ch: pg.clientHeight, top: pg.scrollTop }
    })
    console.log(
      `ONEPAGE @${size.width} page ${label}: root ${root.h}/${root.ch}, ` +
        `doc ${m.docW}×${m.docH} / ${m.clientW}×${m.clientH}, grids ${m.grids.length}`,
    )
    expect(m.docH, `${label}'s page scrolls the DOCUMENT at ${size.width}px`).toBeLessThanOrEqual(m.clientH + 1)
    expect(m.docW, `${label}'s page shears the DOCUMENT sideways at ${size.width}px`).toBeLessThanOrEqual(m.clientW + 1)
    expect(root.top, `${label}'s page is already scrolled`).toBe(0)
    expect(root.h, `${label}'s PAGE ITSELF scrolls at ${size.width}px: ${root.h} > ${root.ch}`).toBeLessThanOrEqual(root.ch + 1)
    assertGrids(m.grids, size, `${label} page`)
    await page.locator('[data-detail-back]').last().click()
    await expect(page.locator('[data-detail-page]')).toHaveCount(0)
    opened++
  }
  return opened
}

/** EVERY FACE INSIDE A TAB IS STILL THE SAME SHEET, and every face's summaries open pages. */
async function walkFaces(
  page: Page,
  size: { width: number; height: number },
  listName: RegExp | null,
  faces: readonly string[],
): Promise<number> {
  let pages = 0
  for (const face of faces) {
    const strip = listName === null ? page.getByRole('tablist').first() : page.getByRole('tablist', { name: listName })
    await strip.getByRole('tab', { name: face, exact: true }).click()
    await page
      .waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 60_000 })
      .catch(() => {})
    await page.waitForTimeout(350)
    const m = await read(page)
    console.log(
      `ONEPAGE @${size.width} face ${face}: doc ${m.docW}×${m.docH} / ${m.clientW}×${m.clientH}, ` +
        `sheet ${m.sheet === null ? 'none' : `${m.sheet.h}/${m.sheet.ch}`}, Y ${m.scrollY}`,
    )
    expect(m.docH, `face ${face} scrolls the PAGE down at ${size.width}px`).toBeLessThanOrEqual(m.clientH + 1)
    expect(m.docW, `face ${face} scrolls the PAGE sideways at ${size.width}px`).toBeLessThanOrEqual(m.clientW + 1)
    if (m.sheet !== null) {
      expect(m.sheet.top, `face ${face}'s Sheet is already scrolled`).toBe(0)
      // A PAGE SCROLLS AS A PAGE (2026-11-02, owner row 267: *"too packed"* — the cost of room is length); #413's law still binds every
      // Sheet that is not one (a tab that takes the page layout leaves this law the day it does, with its own spec).
      if (!m.sheet.page) {
        expect(
          m.sheet.h,
          `face ${face} scrolls its own Sheet at ${size.width}px: ${m.sheet.h} > ${m.sheet.ch}.`,
        ).toBeLessThanOrEqual(m.sheet.ch + 1)
      }
    }
    pages += await walkPages(page, size)
  }
  return pages
}

for (const size of SIZES) {
  test(`one page at ${size.width}×${size.height}: every tab, face, page and choice grid`, async ({ page, request, baseURL }) => {
    test.setTimeout(1_800_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(size)

    let gridsMeasured = 0
    let pagesMeasured = 0
    for (const route of ROUTES) {
      await page.goto(route)
      await ready(page)
      const m = await read(page)
      console.log(
        `ONEPAGE @${size.width} ${route}: doc ${m.docW}×${m.docH} / ${m.clientW}×${m.clientH}, ` +
          `sheet ${m.sheet === null ? 'none' : `${m.sheet.h}/${m.sheet.ch}`}, Y ${m.scrollY}, grids ${m.grids.length}`,
      )

      // 1. THE DOCUMENT NEVER SCROLLS.
      expect(m.docH, `${route} scrolls the PAGE down at ${size.width}px: ${m.docH} > ${m.clientH}`).toBeLessThanOrEqual(m.clientH + 1)
      expect(m.docW, `${route} scrolls the PAGE sideways at ${size.width}px: ${m.docW} > ${m.clientW}`).toBeLessThanOrEqual(m.clientW + 1)
      expect(m.scrollY, `${route} is already scrolled on arrival`).toBe(0)

      // 2. THE MAIN LANDMARK.
      expect(m.main, `${route} rendered no main landmark`).not.toBeNull()
      expect(m.main!.width, `${route}'s main landmark has no width`).toBeGreaterThan(0)
      expect(m.main!.height, `${route}'s main landmark has no height`).toBeGreaterThan(0)
      expect(m.main!.bottom, `${route}'s main landmark hangs below the glass`).toBeLessThanOrEqual(size.height + 1)

      // 2b. THE TAB'S OWN SHEET NEVER SCROLLS.
      if (m.sheet !== null) {
        expect(m.sheet.top, `${route}'s Sheet is already scrolled at ${size.width}px`).toBe(0)
        expect(m.sheet.ch, `${route}'s Sheet has no height at ${size.width}px`).toBeGreaterThan(0)
        // (a Sheet that is a PAGE — Stats, 2026-11-02, owner row 267 — scrolls as one; tests/stats.design.spec.ts holds its laws)
        if (!m.sheet.page) {
          expect(
            m.sheet.h,
            `${route} scrolls its own Sheet at ${size.width}px: ${m.sheet.h} > ${m.sheet.ch}.`,
          ).toBeLessThanOrEqual(m.sheet.ch + 1)
        }
      }

      // 3. EVERY CHOICE GRID ON THE COMPACT SCREEN.
      gridsMeasured += assertGrids(m.grids, size, `${route} @${size.width}`)

      // 3b. EVERY FACE INSIDE THE TAB, AND EVERY PAGE ITS SUMMARIES OPEN.
      if (route === 'command') pagesMeasured += await walkFaces(page, size, /desk faces/i, ['City', 'Invest', 'Report', 'Trade'])
      else if (route === 'stats') pagesMeasured += await walkFaces(page, size, null, ['Markets', 'Cities', 'Merchants', 'Me', 'Overview'])
      else pagesMeasured += await walkPages(page, size)

      // 3c. A FACE KEEPS ITS INFORMATION WHERE IT STANDS (the unfold slice, 2026-11-02, owner row 260: Stats has no
      // summary rows any more — U1): the day's money flows draw their figures and net bars ON the Overview, with no
      // press. The walk above ends on the Overview, so that is the face on the glass.
      if (route === 'stats') {
        const flows = page.getByTestId('stats-new-money')
        await expect(flows, 'the Money flows block is not on the Overview').toBeVisible()
        await expect(flows.locator('[role="img"]').first(), 'the Money flows block drew no figures').toBeVisible({ timeout: 30_000 })
        expect(await page.locator('[data-detail-page]').count(), 'the Stats Overview opened a page').toBe(0)
      }
    }

    // NON-VACUITY: choice grids on several screens, and many summary pages actually opened.
    expect(gridsMeasured, 'the walk met almost no choice grids — did the screens render?').toBeGreaterThan(3)
    expect(pagesMeasured, 'the walk opened almost no summary pages — did the summaries render?').toBeGreaterThan(8)
  })
}

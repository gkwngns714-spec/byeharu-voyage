import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ONE PAGE — the owner's law, measured on every main tab (2026-10-31)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i hate to scroll down on things, make it so that all the info is packed on one page. all the
// game."* The law this file holds, at the phone (390×844) and the wide desk (1280×800):
//
//   1. THE DOCUMENT NEVER SCROLLS — `documentElement.scrollHeight <= clientHeight + 1` and the same
//      for width, on every main tab. A tab may own a bounded pane that scrolls inside itself
//      (`ScrollPane`, data-scroll-pane); the PAGE never moves.
//   1b. THE TAB'S OWN SHEET NEVER SCROLLS — the surface the owner actually feels. `Sheet` carries
//      `data-sheet`; its scrollHeight must equal its clientHeight at rest, scrollTop 0, on every
//      route that draws one (all but Map and the City page, which are one glass).
//   2. THE MAIN LANDMARK IS THERE AND VISIBLE on every tab.
//   3. EVERY SET OF TAPPABLE CHOICES IS AN ORDERED GRID — each `[data-choice-grid]` has equal
//      cells on shared column lines (the owner: *"make it into square and allign properly orderly.
//      this applies to all the places throughout the game."*), every cell ≥ 44 px.
//   4. A FOLDED SECONDARY SECTION OPENS ITS OWN BODY when pressed and keeps its information
//      (owner: *"make things foldable"*) — the Stats "New and moved money" block is the witness.
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
  sheet: { h: number; ch: number; top: number } | null
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
      sheet: sheet === null ? null : { h: sheet.scrollHeight, ch: sheet.clientHeight, top: sheet.scrollTop },
      grids,
    }
  })
}

/** EVERY FACE INSIDE A TAB IS STILL THE SAME SHEET. The desk has four faces and Stats five; a
 *  face that starts the Sheet scrolling is the same defect one press in. Switch the faces the way
 *  a player does and hold each one to the two laws (page and Sheet). `listName === null` means the
 *  page's first tab list (Stats draws exactly one). */
async function walkFaces(
  page: Page,
  size: { width: number; height: number },
  listName: RegExp | null,
  faces: readonly string[],
) {
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
      expect(
        m.sheet.h,
        `face ${face} scrolls its own Sheet at ${size.width}px: ${m.sheet.h} > ${m.sheet.ch}. ` +
          `Fold the secondary blocks and bound the lists.`,
      ).toBeLessThanOrEqual(m.sheet.ch + 1)
    }
  }
}

for (const size of SIZES) {
  test(`one page at ${size.width}×${size.height}: every tab, every choice grid`, async ({ page, request, baseURL }) => {
    // One boot, ten routes: the local world persists in the tab, so a reload re-reads rather than
    // rebuilding the chain. The probe of 2026-10-31 measured 10 routes in ~28 s this way.
    test.setTimeout(1_200_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(size)

    let gridsMeasured = 0
    for (const route of ROUTES) {
      await page.goto(route)
      await ready(page)
      const m = await read(page)
      console.log(
        `ONEPAGE @${size.width} ${route}: doc ${m.docW}×${m.docH} / ${m.clientW}×${m.clientH}, ` +
          `sheet ${m.sheet === null ? 'none' : `${m.sheet.h}/${m.sheet.ch}`}, Y ${m.scrollY}, grids ${m.grids.length}`,
      )

      // 1. THE PAGE NEVER SCROLLS, down or sideways, and arrives at the top.
      expect(
        m.docH,
        `${route} scrolls the PAGE down at ${size.width}px: ${m.docH} > ${m.clientH}. ` +
          `Put the long list in a ScrollPane (data-scroll-pane) instead of growing the document.`,
      ).toBeLessThanOrEqual(m.clientH + 1)
      expect(m.docW, `${route} scrolls the PAGE sideways at ${size.width}px: ${m.docW} > ${m.clientW}`).toBeLessThanOrEqual(m.clientW + 1)
      expect(m.scrollY, `${route} is already scrolled on arrival`).toBe(0)

      // 2. THE MAIN LANDMARK IS THERE, on the glass.
      expect(m.main, `${route} rendered no main landmark`).not.toBeNull()
      expect(m.main!.width, `${route}'s main landmark has no width`).toBeGreaterThan(0)
      expect(m.main!.height, `${route}'s main landmark has no height`).toBeGreaterThan(0)
      expect(m.main!.bottom, `${route}'s main landmark hangs below the glass`).toBeLessThanOrEqual(size.height + 1)

      // 2b. THE TAB'S OWN SHEET DOES NOT SCROLL. This is the law the owner feels when he scrolls:
      //     the document was always fixed; the Sheet is what travelled. Fold the secondary blocks
      //     and bound the lists until its scrollHeight is its clientHeight; never clip, never hide.
      if (m.sheet !== null) {
        expect(m.sheet.top, `${route}'s Sheet is already scrolled at ${size.width}px`).toBe(0)
        expect(m.sheet.ch, `${route}'s Sheet has no height at ${size.width}px`).toBeGreaterThan(0)
        expect(
          m.sheet.h,
          `${route} scrolls its own Sheet at ${size.width}px: ${m.sheet.h} > ${m.sheet.ch}. ` +
            `Put the secondary blocks in closed SectionFolds and the long lists in bounded ScrollPanes.`,
        ).toBeLessThanOrEqual(m.sheet.ch + 1)
      }

      // 3. EVERY CHOICE GRID IS ORDERED: its cells share one width, one height and one line, and
      //    every cell clears the reach floor. Non-vacuity is asserted after the walk.
      for (const g of m.grids) {
        if (g.cells.length < 2) continue
        gridsMeasured++
        const [a, b] = g.cells
        expect(Math.abs(a.w - b.w), `grid "${g.label}" at ${size.width}px: its first two cells differ in width (${a.w} vs ${b.w})`).toBeLessThanOrEqual(1)
        expect(Math.abs(a.h - b.h), `grid "${g.label}" at ${size.width}px: its first two cells differ in height (${a.h} vs ${b.h})`).toBeLessThanOrEqual(1)
        expect(Math.abs(a.t - b.t), `grid "${g.label}" at ${size.width}px: its first two cells are not on one line`).toBeLessThanOrEqual(1)
        expect(b.l, `grid "${g.label}" at ${size.width}px: its second cell is not to the right of the first`).toBeGreaterThan(a.l)
        for (const c of g.cells) {
          expect(c.h, `grid "${g.label}" at ${size.width}px: a cell is ${c.h}px tall, under the 44px floor`).toBeGreaterThanOrEqual(44)
          expect(c.w, `grid "${g.label}" at ${size.width}px: a cell is ${c.w}px wide, under the 44px floor`).toBeGreaterThanOrEqual(44)
        }
      }

      // 3b. EVERY FACE INSIDE THE TAB IS STILL ONE PAGE: the desk's four faces and Stats' five.
      if (route === 'command') await walkFaces(page, size, /desk faces/i, ['City', 'Invest', 'Profit', 'Trade'])
      if (route === 'stats') await walkFaces(page, size, null, ['Markets', 'Cities', 'Merchants', 'Me', 'Overview'])

      // 4. A FOLD KEEPS ITS INFORMATION. Stats' "New and moved money" is closed by default with its
      //    figure on the line; one press reveals its body (the press law's reveal, not a deletion).
      if (route === 'stats') {
        const toggle = page.getByTestId('stats-new-money-toggle')
        await expect(toggle, 'the New and moved money section has no fold control').toBeVisible()
        await expect(toggle).toHaveAttribute('aria-expanded', 'false')
        await toggle.click()
        await expect(toggle).toHaveAttribute('aria-expanded', 'true')
        await expect(page.getByTestId('stats-new-money').locator('[role="img"]').first(), 'the folded block revealed no figures').toBeVisible({ timeout: 30_000 })
      }
    }

    // NON-VACUITY: the walk must have met choice grids on several screens (Stats, Command, the
    // Codex, Profile, History, Rank, Routes all draw one). A green that measured nothing is worse
    // than a red (tests/layout.spec.ts's header).
    expect(gridsMeasured, 'the walk met almost no choice grids — did the screens render?').toBeGreaterThan(3)
  })
}

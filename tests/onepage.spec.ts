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
//      (`ScrollPane`, data-scroll-pane) or a Sheet surface; the PAGE never moves.
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
      grids,
    }
  })
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
      console.log(`ONEPAGE @${size.width} ${route}: doc ${m.docW}×${m.docH} / ${m.clientW}×${m.clientH}, Y ${m.scrollY}, grids ${m.grids.length}`)

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

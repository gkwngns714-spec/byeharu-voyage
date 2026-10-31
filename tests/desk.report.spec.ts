import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE REPORT FACE (0286, docs/COMMAND_REDESIGN.md §4–5; owner rows 192, 244) — the phone (390×844)
// and the wide desk (1280×800), on a local build, on the 2026-10-31 compact/pop-up mechanism:
//   · the face opens from its tab (Report) and stands in the desk's frame;
//   · Day / Week / All are ONE ordered grid of three cells, every cell at the 44-px reach floor;
//   · the total has its figure; the EIGHT design sections are summary rows with their figures, and
//     a press opens the section's own full-screen page with its lines and a back press;
//   · a new company's report is the empty shape — its starting money is capital — so the places
//     pane says so instead of inventing figures;
//   · no page or Sheet scroll (the one-page law), and a span press changes the read in place.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 390, height: 844 },
  { width: 1280, height: 800 },
] as const

const SECTIONS = ['trade', 'crew', 'supplies', 'repairs', 'insurance', 'invest', 'ships', 'other'] as const

async function openReport(page: Page, request: Parameters<typeof reachable>[0], baseURL: string | undefined) {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('command')
  await ready(page)
  await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Report', exact: true }).click()
  await expect(page.getByTestId('desk-report')).toBeVisible()
  await expect(page.getByTestId('report-spans')).toBeVisible()
}

for (const size of SIZES) {
  test.describe(`the Report face at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('spans, total, eight section rows (a page each), places; nothing scrolls', async ({ page, request, baseURL }) => {
      await openReport(page, request, baseURL)

      // THE SPANS: one grid, three equal cells, each at the reach floor.
      const spans = page.getByTestId('report-spans').locator('[data-choice-grid] > button')
      await expect(spans).toHaveCount(3)
      const boxes = await spans.evaluateAll((els) =>
        els.map((e) => {
          const r = e.getBoundingClientRect()
          return { l: Math.round(r.left), t: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) }
        }),
      )
      for (const b of boxes) {
        expect(b.h, 'a span cell is under the 44-px floor').toBeGreaterThanOrEqual(44)
        expect(b.w, 'a span cell is under the 44-px floor').toBeGreaterThanOrEqual(44)
      }
      expect(Math.abs(boxes[0].t - boxes[1].t)).toBeLessThanOrEqual(1)
      expect(Math.abs(boxes[0].w - boxes[1].w)).toBeLessThanOrEqual(1)

      // THE TOTAL AND THE EIGHT SECTIONS, each a summary row (the compact screen's one mechanism).
      await expect(page.getByTestId('report-total')).toBeVisible()
      for (const id of SECTIONS) {
        const row = page.getByTestId(`report-section-${id}`)
        await expect(row, `section ${id} is not a summary row`).toHaveAttribute('data-summary-row', '')
      }

      // A PRESS OPENS THE SECTION'S OWN PAGE, with its lines and a back press; the spans do not move.
      const before = await page.getByTestId('report-spans').boundingBox()
      await page.getByTestId('report-section-trade').click()
      const pageEl = page.getByTestId('report-section-trade-page')
      await expect(pageEl).toBeVisible()
      await expect(pageEl.locator('[data-detail-back]')).toBeVisible()
      expect(await page.getByTestId('report-spans').boundingBox()).toEqual(before)
      await pageEl.locator('[data-detail-back]').click()
      await expect(pageEl).toHaveCount(0)

      // THE EMPTY SHAPE SAYS SO: a new company has made nothing; the places pane says it.
      await expect(page.getByTestId('report-places')).toContainText(/Nothing in or out|수입|지출/, { timeout: 30_000 })

      // A SPAN PRESS CHANGES THE READ IN PLACE: Week → All, the grid does not move.
      const spanTabs = page.getByTestId('report-spans').getByRole('tab')
      const gridBefore = await page.getByTestId('report-spans').boundingBox()
      await spanTabs.nth(2).click()
      await expect(spanTabs.nth(2)).toHaveAttribute('aria-selected', 'true')
      expect(await page.getByTestId('report-spans').boundingBox()).toEqual(gridBefore)
      await spanTabs.nth(0).click()
      await expect(spanTabs.nth(0)).toHaveAttribute('aria-selected', 'true')

      // THE ONE-PAGE LAW: the document and the face's own Sheet do not travel.
      const m = await page.evaluate(() => {
        const sheet = document.querySelector('[data-sheet]') as HTMLElement | null
        return {
          dh: document.documentElement.scrollHeight,
          ch: document.documentElement.clientHeight,
          dw: document.documentElement.scrollWidth,
          cw: document.documentElement.clientWidth,
          sh: sheet?.scrollHeight ?? 0,
          sch: sheet?.clientHeight ?? 0,
        }
      })
      expect(m.dh, 'the Report face scrolls the page down').toBeLessThanOrEqual(m.ch + 1)
      expect(m.dw, 'the Report face scrolls the page sideways').toBeLessThanOrEqual(m.cw + 1)
      if (m.sch > 0) expect(m.sh, 'the Report face scrolls its own Sheet').toBeLessThanOrEqual(m.sch + 1)
    })
  })
}

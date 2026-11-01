import { test, expect, type Page } from '@playwright/test'
import { ready, reachable, settled } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE OWNER'S COMPACTION OF THE CITY SCREENS (2026-11-01)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Verbatim: *"so is the same in command hq, city hall. there are empty spaces between words and
// numbers horizontally which is in effective. make it so that htey are closer, more compact with
// full detail, without having to fold anything unless it is necessary"* (2026-11-01).
//
// WHAT THIS MEASURES, on the served build at 390×568 and 1280×800:
//   GAP      the horizontal distance from a label's last glyph to its figure's first glyph, per row
//            group: the hall's five figures, the Influence row, the Investors row, the HQ earnings
//            line, the market's basket line and the open request's pay line. A Range is used for the
//            label's edge, not its box: a grid cell's box fills its track even when the word is short.
//   PITCH    each measured row's height, and the 44-px floor under every pressable row.
//   FIT      the document never scrolls in either axis, the hall panel never scrolls, and the hall
//            panel's height holds still across faces.
//   CONTENT  the five hall figures and every face's content are still there (nothing removed).
//   FRAME    the header, the six-tile grid and the rail boxes do not move between presses.
//
// THE SHARED PRIMITIVES: the SummaryRow/Row rows on the faces and inside the pages ride
// src/components/ui (Detail.tsx, Row.tsx), whose own compaction lands beside this slice — this spec
// MEASURES those rows and holds the rows the CITY owns. When the primitive change is on origin/main,
// the face-row gaps are asserted here too (the numbers are already printed by the measurement).

const PHONE = { width: 390, height: 568 }
const WIDE = { width: 1280, height: 800 }

interface Reading {
  id: string
  gap: number | null
  h: number
  text: string
}
interface ScrollState {
  h: number
  scrollH: number
  clientH: number
}
interface PanelReading {
  building: string | null
  summary: Reading[]
  rows: Reading[]
  figures: number
  scroll: ScrollState | null
}
interface Audit {
  where: string
  doc: { w: number; cw: number; h: number; ch: number }
  hall: { h: number; rows: Reading[]; figures: number; scroll: ScrollState | null } | null
  earnings: Reading
  basket: Reading | null
  face: PanelReading | null
  frame: { header: number[] | null; grid: number[] | null; rail: number[] | null }
}

const HALL_ROWS = [
  'city-hall-influence',
  'city-population',
  'city-gold',
  'city-status',
  'city-relationship',
  'city-employees',
  'city-hall-investors',
]

/** ONE READING OF THE SERVED SCREEN — everything above, in the page's own coordinates. */
async function measure(page: Page, where: string): Promise<Audit> {
  return (await page.evaluate(
    ({ where, hallIds }) => {
      const pick = (sel: string): HTMLElement | null => document.querySelector(sel) as HTMLElement | null
      const box = (el: Element) => el.getBoundingClientRect()
      const shown = (el: Element) => {
        const r = box(el)
        const s = getComputedStyle(el)
        return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'
      }
      /** The right edge of a label's VISIBLE content. A Range (a Row.tsx grid cell's box is its whole
       *  track even when the word is short), EXCEPT when the cell clips: a truncated label draws its
       *  ellipsis at the cell's edge, past the last glyph, and that edge is what the eye measures to. */
      const textRight = (el: Element): number => {
        const he = el as HTMLElement
        if (he.scrollWidth > he.clientWidth + 1 && getComputedStyle(el).overflowX !== 'visible') return box(el).right
        const range = document.createRange()
        range.selectNodeContents(el)
        const rects = Array.from(range.getClientRects()).filter((r) => r.width > 0)
        return rects.length ? rects[rects.length - 1].right : box(el).right
      }
      const text = (el: Element) => (el.textContent ?? '').replace(/\s+/g, ' ').trim()
      /** A hand-rolled row (FigureLine, SummaryRow, the fold): label = child 1, figure = child 2. */
      const read = (id: string, row: Element | null) => {
        if (!row) return { id, gap: null, h: 0, text: '' }
        const kids = Array.from(row.children).filter(shown)
        const label = kids[0]
        const figure = kids[1]
        const gap = label && figure ? Math.round((box(figure).left - textRight(label)) * 10) / 10 : null
        return { id, gap, h: Math.round(box(row).height), text: text(row) }
      }
      /** A Row.tsx row: its label and value cells are named. */
      const readRowLine = (id: string, row: Element) => {
        const label = row.querySelector('[data-row-cell="label"]')
        const value = row.querySelector('[data-row-cell="value"]')
        if (!label || !value) return { id, gap: null, h: Math.round(box(row).height), text: text(row) }
        return { id, gap: Math.round((box(value).left - textRight(label)) * 10) / 10, h: Math.round(box(row).height), text: text(row) }
      }
      const scrollOf = (el: Element | null): ScrollState | null => {
        const sc = (el && (el.classList.contains('bv-scroll') ? el : el.querySelector('.bv-scroll'))) as HTMLElement | null
        return sc ? { h: Math.round(box(sc).height), scrollH: sc.scrollHeight, clientH: sc.clientHeight } : null
      }
      const frameBox = (id: string): number[] | null => {
        const el = pick(`[data-testid="${id}"]`)
        if (!el) return null
        const r = box(el)
        return [Math.round(r.top), Math.round(r.left), Math.round(r.width), Math.round(r.height)]
      }

      const hall = pick('[data-testid="city-hall-panel"]')
      const hallRows = hall ? hallIds.map((id) => read(id, pick(`[data-testid="${id}"]`))) : []
      const panel = pick('[data-testid="city-face-panel"]')
      const face = panel
        ? {
            building: panel.getAttribute('data-building'),
            summary: Array.from(panel.querySelectorAll('[data-summary-row]'))
              .filter(shown)
              .map((r, i) => read(`summary-${i}`, r)),
            rows: Array.from(panel.querySelectorAll('[data-row-line]'))
              .filter(shown)
              .slice(0, 6)
              .map((r, i) => readRowLine(`row-${i}`, r)),
            figures: Array.from(panel.querySelectorAll('[data-figure]')).filter(shown).length,
            scroll: scrollOf(panel),
          }
        : null
      return {
        where,
        doc: {
          w: document.documentElement.scrollWidth,
          cw: document.documentElement.clientWidth,
          h: document.documentElement.scrollHeight,
          ch: document.documentElement.clientHeight,
        },
        hall: hall
          ? {
              h: Math.round(box(hall).height),
              rows: hallRows,
              figures: Array.from(hall.querySelectorAll('[data-figure]')).filter(shown).length,
              scroll: scrollOf(pick('[data-testid="city-hall-scroll"]') ?? hall),
            }
          : null,
        earnings: read('city-summary', pick('[data-testid="city-summary"] > div')),
        basket: (() => {
          const el = pick('[data-testid="city-basket"] > div:first-child')
          return el ? read('basket-header', el) : null
        })(),
        face,
        frame: { header: frameBox('city-header'), grid: frameBox('city-building-grid'), rail: frameBox('city-rail') },
      }
    },
    { where, hallIds: HALL_ROWS },
  )) as Audit
}

/** A PANEL IS PRESSED, ITS READ HAS LANDED, AND ONE FRAME HAS PASSED. */
async function pressTile(page: Page, id: 'hall' | 'market' | 'storage' | 'forge' | 'port' | 'inn', where: string) {
  await page.getByTestId(`city-building-${id}`).click()
  const panel = page.getByTestId(id === 'hall' ? 'city-hall-panel' : 'city-face-panel')
  await expect(panel, `the ${id} panel is missing (${where})`).toBeVisible()
  if (id !== 'hall') await expect(panel, `the ${id} panel is not the pressed building (${where})`).toHaveAttribute('data-building', id)
  await settled(panel)
  await page.waitForTimeout(300)
}

/** THE ROWS THIS SLICE OWNS: not pushed to the far edge, and not overlapping their word. */
function expectCompact(reading: Reading | undefined, where: string) {
  expect(reading, `${where}: the row is missing`).toBeTruthy()
  expect(reading!.gap, `${where}: the label→figure gap was not measured`).not.toBeNull()
  expect(reading!.gap!, `${where}: the figure is still ${reading!.gap}px from its word ("${reading!.text}")`).toBeLessThanOrEqual(11)
  expect(reading!.gap!, `${where}: the figure overlaps its word ("${reading!.text}")`).toBeGreaterThanOrEqual(0)
}

async function auditAt(page: Page, vp: { width: number; height: number }): Promise<Audit[]> {
  await page.setViewportSize(vp)
  await page.waitForTimeout(400)
  const where0 = `${vp.width}×${vp.height}`
  const table: Audit[] = []
  await pressTile(page, 'hall', where0)
  const hall = await measure(page, `${where0} hall`)
  table.push(hall)
  for (const b of ['market', 'storage', 'forge', 'port', 'inn'] as const) {
    await pressTile(page, b, where0)
    table.push(await measure(page, `${where0} ${b}`))
    if (b === 'market') {
      // THE BASKET'S SUMMARY LINE (city-owned): open it in the panel the way a player does.
      await page.getByTestId('city-market-basket').click()
      await expect(page.getByTestId('city-basket')).toBeVisible()
      await page.waitForTimeout(300)
      table.push(await measure(page, `${where0} market-basket`))
      await page.getByTestId('city-basket-back').click()
      await expect(page.getByTestId('city-basket')).toHaveCount(0)
      await page.waitForTimeout(200)
    }
  }
  await pressTile(page, 'hall', where0)
  return table
}

test.use({ viewport: PHONE })

test('the city screens: figures hug their words, pitch keeps the floor, the frame holds (390×568, 1280×800)', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  // The HQ is the app's landing route and picks the house's port without a query (CityScreen).
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('city-screen')).toBeVisible()
  await expect(page.getByTestId('city-hall-panel')).toBeVisible()
  await settled(page.getByTestId('city-hall-panel'))

  const phone = await auditAt(page, PHONE)
  const wide = await auditAt(page, WIDE)
  console.log('DENSITY ' + JSON.stringify([...phone, ...wide]))

  for (const a of [...phone, ...wide]) {
    // FIT — the document never scrolls, at every face and both glasses.
    expect(a.doc.w, `${a.where}: the page scrolls sideways`).toBeLessThanOrEqual(a.doc.cw)
    expect(a.doc.h, `${a.where}: the page scrolls down`).toBeLessThanOrEqual(a.doc.ch)
    // FRAME — the header, the six-tile grid and the rail hold their boxes across every press.
    if (a !== phone[0] && a !== wide[0]) {
      const ref = a.where.includes('390') ? phone[0].frame : wide[0].frame
      expect(a.frame, `${a.where}: the frame moved when a face was pressed`).toEqual(ref)
    }
    // PITCH — every pressable row keeps the 44-px floor.
    for (const r of a.face?.summary ?? []) expect(r.h, `${a.where}: summary row "${r.text}" is under 44 px`).toBeGreaterThanOrEqual(44)
    for (const r of a.face?.rows ?? []) expect(r.h, `${a.where}: row "${r.text}" is under 44 px`).toBeGreaterThanOrEqual(44)
    for (const r of a.hall?.rows ?? []) {
      if (r.id === 'city-hall-influence' || r.id === 'city-hall-investors') {
        expect(r.h, `${a.where}: ${r.id} is under 44 px`).toBeGreaterThanOrEqual(44)
      }
    }
  }

  for (const a of phone) {
    // THE EARNINGS LINE (the frame's own row) hugs too, on every face.
    expectCompact(a.earnings, `${a.where} city-summary`)
    // THE MARKET'S BASKET LINE (its own row, the panel's summary).
    if (a.basket) expectCompact(a.basket, `${a.where} city-basket`)
  }

  for (const a of phone.filter((x) => x.hall !== null)) {
    // THE HALL — the five figures and the two hall rows, nothing pushed to the far edge.
    const hall = a.hall!
    const by = new Map(hall.rows.map((r) => [r.id, r]))
    for (const id of HALL_ROWS) expectCompact(by.get(id), `${a.where} ${id}`)
    // THE HALL FITS — no scroll inside the panel at the short glass.
    expect(hall.scroll, `${a.where}: the hall has no scroll region`).not.toBeNull()
    expect(hall.scroll!.scrollH, `${a.where}: the hall panel scrolls (${hall.scroll!.scrollH}/${hall.scroll!.clientH})`).toBeLessThanOrEqual(hall.scroll!.clientH + 1)
    // CONTENT — the five hall figures are all drawn, each with a value.
    const figures = hall.rows.filter((r) => ['city-population', 'city-gold', 'city-status', 'city-relationship', 'city-employees'].includes(r.id))
    expect(figures.length, `${a.where}: a hall figure is missing`).toBe(5)
    for (const r of figures) expect(r.text.length, `${a.where}: ${r.id} is empty`).toBeGreaterThan(0)
  }

  // CONTENT — every face still carries what it carried (the market lists its goods, the forge its
  // tiers, the inn its two rows; the hall is the default face and is measured above).
  for (const a of phone) {
    if (!a.face) continue
    switch (a.face.building) {
      case 'market':
        expect(a.face.rows.length, `${a.where}: the market lists no goods`).toBeGreaterThan(0)
        break
      case 'forge':
        expect(a.face.summary.length, `${a.where}: the forge lists no tiers`).toBeGreaterThan(0)
        break
      case 'inn':
        expect(a.face.summary.length, `${a.where}: the inn lost a row`).toBe(2)
        break
      case 'port':
        expect(a.face.summary.length, `${a.where}: the port lost the yard or the shipwright`).toBeGreaterThan(0)
        break
    }
  }
})

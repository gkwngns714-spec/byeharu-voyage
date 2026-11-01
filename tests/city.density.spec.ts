import { test, expect, type Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { ready, reachable, settled } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY'S WORDS AND FIGURES SIT TOGETHER — measured on the ONE shared row (2026-11-01)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Owner, verbatim: *"so is the same in command hq, city hall. there are empty spaces between words
// and numbers horizontally which is in effective. make it so that htey are closer, more compact with
// full detail, without having to fold anything unless it is necessary"* (2026-11-01).
//
// BEFORE (#439's measurement, the retired spread): the hall's rows stood 24.5–92.1 px from their
// words at 390×568 and 441.2–537.1 px at 1280×800; the earnings line 187.8 / 1,077.8. AFTER the
// re-point every city-owned row is a shared `Row`/`SummaryRow` and the one shared columns place the
// figure beside its label — the HUG law tests/align.spec.ts now holds app-wide: a value within 16 px
// of its own label. This spec measures the shared slots (`data-row-cell="label|value"`) at
// 390×568 and 1280×800, and holds:
//   HUG      every city row's value within 16 px of its label (the one law, not a city one);
//   PITCH    the 44-px reach floor under every pressable row; the shared 52-px rhythm on list rows
//            (the city-local pitch override is GONE — the market's Basket row must measure 52);
//            the compact size draws a data line at 20 (the hall's five figures, the earnings line);
//   FIT      the document never scrolls, the hall panel never scrolls, and the hall's height holds;
//   CONTENT  the five hall figures and every face's content are still there (nothing removed);
//   FRAME    the header, six-tile grid and rail boxes do not move between presses.

const PHONE = { width: 390, height: 568 }
const WIDE = { width: 1280, height: 800 }

/** align.spec's HUG law: a Row/SummaryRow value sits within 16 px of its own label. */
const HUG = 16
/** `--spacing-row`: the shared list-row rhythm (44 + the 8pt step). */
const ROW = 52
/** The shared compact size's data line. */
const COMPACT = 20

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
const HALL_FIGURES = ['city-population', 'city-gold', 'city-status', 'city-relationship', 'city-employees']

/** ONE READING OF THE SERVED SCREEN — the shared slots, in the page's own coordinates. */
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
      /** The right edge of a label's VISIBLE content: its last line of text, except when the cell
       *  clips — a truncated label draws its ellipsis at the cell's edge, past the last glyph, and
       *  that edge is what the eye measures to. */
      const textRight = (el: Element): number => {
        const he = el as HTMLElement
        if (he.scrollWidth > he.clientWidth + 1 && getComputedStyle(el).overflowX !== 'visible') return box(el).right
        const range = document.createRange()
        range.selectNodeContents(el)
        const rects = Array.from(range.getClientRects()).filter((r) => r.width > 0)
        return rects.length ? rects[rects.length - 1].right : box(el).right
      }
      const text = (el: Element) => (el.textContent ?? '').replace(/\s+/g, ' ').trim()
      /** THE SHARED SLOTS: the value's left edge against its own label's visible right edge. */
      const read = (id: string, el: Element | null) => {
        if (!el) return { id, gap: null, h: 0, text: '' }
        const h = Math.round(box(el).height)
        const label = el.querySelector('[data-row-cell="label"]')
        const value = el.querySelector('[data-row-cell="value"]')
        const gap = label && value ? Math.round((box(value).left - textRight(label)) * 10) / 10 : null
        return { id, gap, h, text: text(el) }
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
              .map((r) => read(r.getAttribute('data-testid') ?? 'summary', r)),
            rows: Array.from(panel.querySelectorAll('[data-row-line]'))
              .filter(shown)
              .slice(0, 8)
              .map((r) => read(r.getAttribute('data-testid') ?? 'row', r)),
            figures: Array.from(panel.querySelectorAll('[data-row-cell="value"]')).filter(shown).length,
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
              figures: Array.from(hall.querySelectorAll('[data-row-cell="value"]')).filter(shown).length,
              scroll: scrollOf(pick('[data-testid="city-hall-scroll"]') ?? hall),
            }
          : null,
        earnings: read('city-summary', pick('[data-testid="city-summary"]')),
        basket: read('city-basket-head', pick('[data-testid="city-basket-head"]')),
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

/** THE HUG LAW, on one city row: the shared columns hold the value beside its label. */
function expectHug(reading: Reading | undefined, where: string) {
  expect(reading, `${where}: the row is missing`).toBeTruthy()
  expect(reading!.gap, `${where}: no shared label/value slots were found`).not.toBeNull()
  expect(reading!.gap!, `${where}: the value sits ${reading!.gap}px from its label ("${reading!.text}")`).toBeLessThanOrEqual(HUG)
  expect(reading!.gap!, `${where}: the value overlaps its label ("${reading!.text}")`).toBeGreaterThanOrEqual(0)
}

async function auditAt(page: Page, vp: { width: number; height: number }): Promise<Audit[]> {
  await page.setViewportSize(vp)
  await page.waitForTimeout(400)
  const where0 = `${vp.width}×${vp.height}`
  const table: Audit[] = []
  await pressTile(page, 'hall', where0)
  table.push(await measure(page, `${where0} hall`))
  for (const b of ['market', 'storage', 'forge', 'port', 'inn'] as const) {
    await pressTile(page, b, where0)
    table.push(await measure(page, `${where0} ${b}`))
    if (b === 'market') {
      // THE BASKET'S SUMMARY LINE (a shared compact row): open it in the panel as a player does.
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

test('the city screens: the shared rows hug, the shared pitch holds, the frame does not move (390×568, 1280×800)', async ({ page, request, baseURL }) => {
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
    for (const r of a.face?.summary ?? []) {
      expect(r.h, `${a.where}: summary row "${r.text}" is under 44 px`).toBeGreaterThanOrEqual(44)
      if (r.gap !== null) expectHug(r, `${a.where} ${r.id}`)
    }
    for (const r of a.face?.rows ?? []) {
      expect(r.h, `${a.where}: row "${r.text}" is under 44 px`).toBeGreaterThanOrEqual(44)
      // The market's trade ledger is a composition of price ACTIONS with its own measured issue
      // (#433: at 390 the two 44-px price cells cannot sit beside a name in the 171-px panel); the
      // shared HUG applies to the label/value rows, and that ledger is logged, not asserted here.
      if (r.gap !== null && r.id !== 'trade-row') expectHug(r, `${a.where} ${r.id}`)
    }
  }

  for (const a of phone) {
    // THE HALL — the five figures, the Influence and the Investors rows: shared rows, shared hug.
    const hall = a.hall!
    expect(hall, `${a.where}: the hall panel is missing`).toBeTruthy()
    const by = new Map(hall.rows.map((r) => [r.id, r]))
    for (const id of HALL_ROWS) expectHug(by.get(id), `${a.where} ${id}`)
    for (const id of HALL_FIGURES) {
      const r = by.get(id)!
      expect(r.h, `${a.where}: ${id} is not the shared compact data line (${r.h} px)`).toBeLessThanOrEqual(COMPACT + 8)
      expect(r.text.length, `${a.where}: ${id} is empty`).toBeGreaterThan(0)
    }
    for (const id of ['city-hall-influence', 'city-hall-investors']) {
      expect(by.get(id)!.h, `${a.where}: ${id} is under the 44-px floor`).toBeGreaterThanOrEqual(44)
    }
    // THE HALL FITS — no scroll inside the panel at the short glass.
    expect(hall.scroll, `${a.where}: the hall has no scroll region`).not.toBeNull()
    expect(hall.scroll!.scrollH, `${a.where}: the hall panel scrolls (${hall.scroll!.scrollH}/${hall.scroll!.clientH})`).toBeLessThanOrEqual(hall.scroll!.clientH + 1)
    // THE EARNINGS LINE (the frame's own row) is a shared compact row too.
    expectHug(a.earnings, `${a.where} city-summary`)
    expect(a.earnings.h, `${a.where}: the earnings line is not a compact data line`).toBeLessThanOrEqual(COMPACT + 8)
    // THE MARKET'S BASKET LINE (a shared compact row).
    if (a.basket.id === 'city-basket-head') expectHug(a.basket, `${a.where} city-basket`)
  }

  // THE SHARED RHYTHM, NOT A CITY ONE: the market's Basket row is a plain shared Row — 52 px. If a
  // city-local pitch override comes back, this row measures 44 and this fails.
  for (const a of phone) {
    const basketRow = a.face?.rows.find((r) => r.id === 'city-market-basket')
    if (basketRow) expect(basketRow.h, `${a.where}: the market's Basket row is not the shared ${ROW}-px rhythm`).toBe(ROW)
  }

  // CONTENT — every face still carries what it carried.
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

test('the city applies no row-size override of its own', () => {
  // THE RE-POINT'S GUARD (2026-11-01): the city draws the shared Row/SummaryRow; a city-local row
  // size or hug (`[&_[data-row-line]]:...`) is the defect this slice deleted. Read the four files
  // that carried one.
  for (const f of ['CityFace.tsx', 'CityHallPanel.tsx', 'CityScreen.tsx', 'MarketFace.tsx']) {
    const src = readFileSync(new URL(`../src/features/city/${f}`, import.meta.url), 'utf8')
    expect(src, `${f} still carries a city-local row treatment`).not.toContain('[&_[data-row-line]]')
  }
})

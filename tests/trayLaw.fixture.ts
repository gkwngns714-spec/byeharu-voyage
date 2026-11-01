import type { Page } from '@playwright/test'

// THE TRAY'S WIDTH LAW, measured in the running build (the layout sweep of 2026-11-02, row 10).
//
// A tray's rows are as wide as the tray. A row that cannot fit its figure beside its label does not push the tray
// sideways and does not squeeze the label to a letter a line — it puts the long text on the row's SECOND line, where
// it wraps. Measured on the sweep of origin/main e6bf38d1: the Codex's officer tray held a 436-px trait sentence in
// a one-line value cell, so its content stood 74 px wider than the tray at 390, 144 px at 320 and 48 px at 1280, and
// "Surgeon" was left 0 px wide, one letter a line. This is that measurement, once, for every spec that opens a tray
// of rows (the Codex's captain tray, the You tab's captain tray), so the two cannot grow two answers.

/** The three glasses every layout law in this project is held to: the phone, the smallest phone, the desk. */
export const GLASSES = [
  { width: 390, height: 844 },
  { width: 320, height: 640 },
  { width: 1280, height: 800 },
] as const

/** A row's text line is 24 px (`.bv-row-line`, src/index.css), so a wrapped label or figure is 48. Anything under a line and a
 *  half is ONE line. */
export const ONE_LINE_PX = 36

export interface TrayRow {
  /** The row's test id, else its label's text. */
  id: string
  label: string
  labelW: number
  labelH: number
  /** The figure cell's height, or null when the row has no figure cell. */
  valueH: number | null
  /** How far the row's painted cells stand past the tray's content edge (its right edge less its gutter); 0 when they fit. */
  pastRight: number
}

export interface TrayRead {
  /** The tray's scroll region's content, wider than the region by this many px (0 = fits). */
  overflowX: number
  /** The tray's own box, the same. */
  trayOverflowX: number
  /** The page's, the same. */
  pageOverflowX: number
  rows: TrayRow[]
}

/** Read the tray `testid` as it stands. Self-contained: Playwright ships the function into the page. */
export async function readTray(page: Page, testid: string): Promise<TrayRead> {
  return page.evaluate((id) => {
    const tray = document.querySelector(`[data-testid="${id}"]`) as HTMLElement | null
    if (tray === null) throw new Error(`no tray ${id} on the glass`)
    // THE ONE SCROLLING REGION of a tray (Tray.tsx): the first descendant that scrolls vertically.
    const scroller = ([...tray.querySelectorAll('*')] as HTMLElement[]).find((el) => /auto|scroll/.test(getComputedStyle(el).overflowY)) ?? tray
    const sr = scroller.getBoundingClientRect()
    const edge = sr.right - parseFloat(getComputedStyle(scroller).paddingRight || '0')
    const rows = ([...scroller.querySelectorAll('[data-row-line]')] as HTMLElement[]).map((row) => {
      const label = row.querySelector('[data-row-cell="label"]') as HTMLElement | null
      const value = row.querySelector('[data-row-cell="value"]') as HTMLElement | null
      const lr = label?.getBoundingClientRect()
      const cells = [...row.querySelectorAll('[data-row-cell]')] as HTMLElement[]
      const right = Math.max(row.getBoundingClientRect().right, ...cells.map((c) => c.getBoundingClientRect().right))
      const text = (label?.textContent ?? '').replace(/\s+/g, ' ').trim()
      return {
        id: row.getAttribute('data-testid') ?? text,
        label: text,
        labelW: Math.round(lr?.width ?? 0),
        labelH: Math.round(lr?.height ?? 0),
        valueH: value === null ? null : Math.round(value.getBoundingClientRect().height),
        pastRight: Math.max(0, Math.round(right - edge)),
      }
    })
    return {
      overflowX: scroller.scrollWidth - scroller.clientWidth,
      trayOverflowX: tray.scrollWidth - tray.clientWidth,
      pageOverflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      rows,
    }
  }, testid)
}

/** Every way a read breaks the law, named. `exempt` is a row whose LABEL is a sentence by design (it wraps, and says so). */
export function trayViolations(read: TrayRead, where: string, exempt: (row: TrayRow) => boolean = () => false): string[] {
  const out: string[] = []
  if (read.overflowX > 0) out.push(`${where}: the tray's content is ${read.overflowX}px wider than the tray`)
  if (read.trayOverflowX > 0) out.push(`${where}: the tray itself scrolls ${read.trayOverflowX}px sideways`)
  if (read.pageOverflowX > 0) out.push(`${where}: the page scrolls ${read.pageOverflowX}px sideways`)
  for (const r of read.rows) {
    if (r.pastRight > 0) out.push(`${where}: row ${r.id} stands ${r.pastRight}px past the tray's edge`)
    if (exempt(r)) continue
    // A LABEL AND ITS FIGURE STAY ON ONE LINE each; a long sentence goes under them, never beside them.
    if (r.labelH >= ONE_LINE_PX) out.push(`${where}: row ${r.id}: the label "${r.label}" wrapped (${r.labelW}px wide, ${r.labelH}px tall)`)
    if (r.valueH !== null && r.valueH >= ONE_LINE_PX) out.push(`${where}: row ${r.id}: its figure wrapped (${r.valueH}px tall)`)
  }
  return out
}

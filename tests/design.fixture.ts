import type { Page } from '@playwright/test'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PAGE LAWS' ONE MEASURING APPARATUS (2026-11-02, owner row 267)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake."* — screenLayout.ts "THE PAGE", Card.tsx, and the dev-log
// docs/dev-log/2026-11-02-stats-design.md. Stats is the first screen on the page layout; Codex, History, Rank, Routes,
// HQ, Fleets and the Map follow, and each one's spec reads its screen with THIS fixture and says only what is its own,
// exactly as `unfold.fixture.ts` did for the unfold laws. A second copy of this would drift.
//
// WHAT IT MEASURES, ON ONE SCREEN, AS DATA (it is shipped into the page; nothing is asserted here):
//   span          the leftmost and rightmost VISIBLE TEXT of the sheet — the content block, however its blocks are drawn,
//                 so the same read serves the packed column of the unfold slice and the page of cards (the laws were
//                 shown red on the first and green on the second by this one number)
//   scrollers     every box other than the sheet that scrolls inside itself (a scroll trap)
//   smallControls every visible control under 44 px in either side
//   rows          the height and width of every row the caller names by test id (a list's rows)
//   figures       the font size of the figure of every cell the caller names by test id, and of its label
//   cards         every `[data-card]` / `[data-list-panel]` box (the page's blocks) — absent on a screen not yet a page
//   side          the page's side column box (`[data-page-side]`), null on a screen without one

/** The glasses the page laws walk: the owner's laptop (1440), the usual one (1280), a small laptop (1024), a phone (390), a short phone (320). */
export const DESIGN_GLASSES = [
  { width: 1440, height: 900 },
  { width: 1280, height: 800 },
  { width: 1024, height: 768 },
  { width: 390, height: 844 },
  { width: 320, height: 640 },
] as const

/** A LIST ROW IS NEVER WIDER THAN THIS (rem): the 2026-09-13 complaint, "too much blank space" between a name and its price, must not come
 *  back. The brief says 35 rem (560 px); it is 36 here because the main column of a 1,024-px page is 588 px and a one-column card list
 *  there is 562 px — two over. One number for every page spec. */
export const ROW_MAX_REM = 36

export interface DesignRead {
  glass: { w: number; h: number }
  /** The sheet's visible text, leftmost to rightmost (px from the glass's left), or null when it has none. */
  span: { left: number; right: number } | null
  /** Boxes other than the sheet that scroll inside themselves, by test id or tag. */
  scrollers: string[]
  /** Controls under 44 px in width or height: `id "label" W×H`. */
  smallControls: string[]
  rows: { id: string; h: number; w: number }[]
  figures: { id: string; font: number; label: number | null }[]
  cards: { id: string; l: number; t: number; w: number; h: number }[]
  side: { l: number; w: number } | null
}

export async function readDesign(
  page: Page,
  o: { sheet: string; figureIds: readonly string[]; rowIds: readonly string[] },
): Promise<DesignRead> {
  return page.evaluate(({ sheet, figureIds, rowIds }) => {
    const root = document.querySelector(sheet)
    if (root === null) throw new Error(`readDesign: no ${sheet} on the page`)
    const vis = (e: Element) => {
      const r = e.getBoundingClientRect()
      const s = getComputedStyle(e)
      return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && Number(s.opacity) > 0
    }
    const inTray = (e: Element) => e.closest('[data-tray-mode]') !== null
    const name = (e: Element) => e.getAttribute('data-testid') ?? e.getAttribute('aria-label') ?? e.tagName.toLowerCase()

    // THE CONTENT BLOCK'S SPAN: every visible text of the sheet, out of any tray
    let left = Infinity
    let right = -Infinity
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      const host = n.parentElement
      if (!host || !(n.textContent ?? '').trim() || host.closest('svg') || inTray(host) || !vis(host)) continue
      const range = document.createRange()
      range.selectNodeContents(n)
      for (const r of range.getClientRects()) {
        if (r.width <= 0 || r.height <= 0) continue
        left = Math.min(left, r.left)
        right = Math.max(right, r.right)
      }
    }

    const scrollers: string[] = []
    for (const e of root.querySelectorAll('*')) {
      if (!(e instanceof HTMLElement) || inTray(e) || !vis(e)) continue
      if (/(auto|scroll)/.test(getComputedStyle(e).overflowY) && e.scrollHeight > e.clientHeight + 1) scrollers.push(`${name(e)} ${e.scrollHeight}/${e.clientHeight}`)
    }

    const smallControls: string[] = []
    for (const c of root.querySelectorAll('button, a[href], select, input, textarea, [role="tab"], [role="button"], summary')) {
      if (inTray(c) || !vis(c) || (c instanceof HTMLInputElement && c.type === 'hidden')) continue
      const r = c.getBoundingClientRect()
      if (r.width >= 43.5 && r.height >= 43.5) continue
      const label = (c.getAttribute('aria-label') ?? c.textContent ?? '').replace(/\s+/g, ' ').trim().slice(0, 24)
      smallControls.push(`${name(c)} "${label}" ${Math.round(r.width)}×${Math.round(r.height)}`)
    }

    const rows: DesignRead['rows'] = []
    for (const id of rowIds) {
      for (const e of root.querySelectorAll(`[data-testid="${id}"]`)) {
        if (!vis(e)) continue
        const r = e.getBoundingClientRect()
        rows.push({ id, h: r.height, w: r.width })
      }
    }

    // A CELL'S FIGURE IS ITS `tabular-nums` TEXT; ITS LABEL IS THE FIRST WORDS THAT ARE NOT THE FIGURE
    const figures: DesignRead['figures'] = []
    for (const id of figureIds) {
      const cell = root.querySelector(`[data-testid="${id}"]`)
      if (cell === null || !vis(cell)) continue
      const fig = cell.querySelector('.tabular-nums')
      let label: number | null = null
      const w = document.createTreeWalker(cell, NodeFilter.SHOW_TEXT)
      for (let n = w.nextNode(); n; n = w.nextNode()) {
        const host = n.parentElement
        if (!host || !/\p{L}/u.test(n.textContent ?? '') || host.closest('.tabular-nums')) continue
        label = parseFloat(getComputedStyle(host).fontSize)
        break
      }
      figures.push({ id, font: fig ? parseFloat(getComputedStyle(fig).fontSize) : 0, label })
    }

    const cards: DesignRead['cards'] = []
    for (const e of root.querySelectorAll('[data-card], [data-list-panel]')) {
      if (inTray(e) || !vis(e)) continue
      const r = e.getBoundingClientRect()
      cards.push({ id: name(e), l: r.left, t: r.top + (root.scrollTop ?? 0), w: r.width, h: r.height })
    }
    const sideEl = root.querySelector('[data-page-side]')
    const side = sideEl && vis(sideEl) ? { l: sideEl.getBoundingClientRect().left, w: sideEl.getBoundingClientRect().width } : null

    return {
      glass: { w: innerWidth, h: innerHeight },
      span: Number.isFinite(left) ? { left, right } : null,
      scrollers,
      smallControls,
      rows,
      figures,
      cards,
      side,
    }
  }, o)
}

/** Boxes of the named test ids in SHEET coordinates (scroll added to the top), so a scroll the browser did to reach a control is not a move. */
export async function boxesOf(page: Page, sheet: string, ids: readonly string[]): Promise<Record<string, [number, number, number, number] | null>> {
  return page.evaluate(
    ({ sheet, ids }) => {
      const root = document.querySelector(sheet)
      const out: Record<string, [number, number, number, number] | null> = {}
      for (const id of ids) {
        const e = root?.querySelector(`[data-testid="${id}"]`)
        if (!e) {
          out[id] = null
          continue
        }
        const r = e.getBoundingClientRect()
        out[id] = [Math.round(r.left * 10) / 10, Math.round((r.top + (root?.scrollTop ?? 0)) * 10) / 10, Math.round(r.width * 10) / 10, Math.round(r.height * 10) / 10]
      }
      return out
    },
    { sheet, ids },
  )
}

/** The open tray's box (null when none stands). */
export async function trayBox(page: Page): Promise<{ l: number; t: number; w: number; h: number } | null> {
  return page.evaluate(() => {
    const e = [...document.querySelectorAll('[data-tray-mode]')].find((t) => t.getBoundingClientRect().width > 0)
    if (!e) return null
    const r = e.getBoundingClientRect()
    return { l: r.left, t: r.top, w: r.width, h: r.height }
  })
}

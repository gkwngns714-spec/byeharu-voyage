import { readFileSync } from 'node:fs'
import type { Page } from '@playwright/test'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE UNFOLD LAWS' ONE MEASURING APPARATUS (2026-11-02)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/dev-log/2026-11-01-ui-unfold.md U1–U8, measured the same way on every screen that unfolds (Stats first,
// then the Codex, the Ledger, Rank and Routes): the three glasses, and one read of a face as data — page and
// Sheet scroll, whether the figure block scrolls, every sideways scroller, text boxes that cross (each clipped by
// the panes that hold it), cut text with no full text, and how many of a list panel's rows stand WHOLE inside
// its body. A second copy of this would drift; each screen's spec says only what is its own.

export interface Glass {
  width: number
  height: number
}
export const GLASSES: readonly Glass[] = [
  { width: 390, height: 844 },
  { width: 320, height: 640 },
  { width: 1280, height: 800 },
]

export interface Flat {
  doc: { sh: number; ch: number; sw: number; cw: number }
  sheet: { sh: number; ch: number; top: number } | null
  above: { sh: number; ch: number } | null
  sideways: string[]
  overlaps: string[]
  cuts: string[]
  rows: { found: boolean; whole: number; total: number; inView: boolean }
}

/** One face as data: scroll, overlap, cut text and the panel's whole rows. Self-contained — it is shipped into the page. */
export async function readGlass(page: Page, panel: string, row: string | null): Promise<Flat> {
  return page.evaluate(
    ({ panel, row }) => {
      const vis = (e: Element) => {
        const r = e.getBoundingClientRect()
        const s = getComputedStyle(e)
        return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && Number(s.opacity) > 0
      }
      const de = document.documentElement
      const sheet = document.querySelector('[data-sheet]') as HTMLElement | null
      const above = document.querySelector('[data-list-above]') as HTMLElement | null

      // every visible box that scrolls sideways
      const sideways = [...document.querySelectorAll('*')]
        .filter((e) => e instanceof HTMLElement && vis(e) && /auto|scroll/.test(getComputedStyle(e).overflowX) && e.scrollWidth > e.clientWidth + 1)
        .map((e) => e.getAttribute('data-testid') ?? e.tagName.toLowerCase())

      // text boxes, each clipped by every ancestor that clips: text scrolled out of a pane is not on the glass
      const leaves: { txt: string; l: number; t: number; r: number; b: number; host: Element }[] = []
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        const txt = (n.textContent ?? '').trim()
        const host = n.parentElement
        if (!txt || !host || !vis(host) || host.closest('svg')) continue
        const range = document.createRange()
        range.selectNodeContents(n)
        const r0 = [...range.getClientRects()].find((x) => x.width > 0 && x.height > 0)
        if (!r0) continue
        let r: { left: number; top: number; right: number; bottom: number } | null = { left: r0.left, top: r0.top, right: r0.right, bottom: r0.bottom }
        for (let a: Element | null = host; a && a !== document.body && r; a = a.parentElement) {
          const s = getComputedStyle(a)
          if (s.overflowX === 'visible' && s.overflowY === 'visible') continue
          const c = a.getBoundingClientRect()
          r = { left: Math.max(r.left, c.left), top: Math.max(r.top, c.top), right: Math.min(r.right, c.right), bottom: Math.min(r.bottom, c.bottom) }
          if (r.right - r.left <= 0 || r.bottom - r.top <= 0) r = null
        }
        if (!r || r.bottom < 0 || r.top > innerHeight) continue
        leaves.push({ txt: txt.slice(0, 32), l: r.left, t: r.top, r: r.right, b: r.bottom, host })
      }
      const overlaps: string[] = []
      for (let i = 0; i < leaves.length; i++) {
        for (let j = i + 1; j < leaves.length; j++) {
          const a = leaves[i]
          const b = leaves[j]
          if (a.host === b.host || a.host.contains(b.host) || b.host.contains(a.host)) continue
          const ox = Math.min(a.r, b.r) - Math.max(a.l, b.l)
          const oy = Math.min(a.b, b.b) - Math.max(a.t, b.t)
          if (ox > 2 && oy > 3) overlaps.push(`"${a.txt}" × "${b.txt}" (${Math.round(ox)}×${Math.round(oy)})`)
        }
      }

      // cut text carries its full text (align.spec's CUT, held here at 320 too); a 1-px screen-reader label is not text on the glass
      const cuts = [...document.querySelectorAll('body *')]
        .filter((e): e is HTMLElement => {
          if (!(e instanceof HTMLElement) || !vis(e) || e.closest('svg') || e.clientWidth <= 2) return false
          if (!(e.textContent ?? '').trim()) return false
          const s = getComputedStyle(e)
          const cut = (s.overflowX === 'hidden' || s.overflowX === 'clip' || s.textOverflow === 'ellipsis') && e.scrollWidth > e.clientWidth + 1
          return cut && !e.closest('[title]')?.getAttribute('title')?.trim()
        })
        .map((e) => `${e.getAttribute('data-testid') ?? e.tagName.toLowerCase()} "${(e.textContent ?? '').trim().slice(0, 30)}"`)

      const panelEl = document.querySelector(`[data-testid="${panel}"]`)
      const body = panelEl?.querySelector('[data-list-body]') ?? null
      let whole = 0
      let total = 0
      let inView = false
      if (body !== null) {
        const b = body.getBoundingClientRect()
        inView = b.height > 0 && b.top >= 0 && b.bottom <= innerHeight + 1
        if (row !== null) {
          const rows = [...body.querySelectorAll(`[data-testid="${row}"]`)]
          total = rows.length
          whole = rows.filter((r) => {
            const x = r.getBoundingClientRect()
            return x.top >= b.top - 1 && x.bottom <= b.bottom + 1
          }).length
        }
      }
      return {
        doc: { sh: de.scrollHeight, ch: de.clientHeight, sw: de.scrollWidth, cw: de.clientWidth },
        sheet: sheet ? { sh: sheet.scrollHeight, ch: sheet.clientHeight, top: sheet.scrollTop } : null,
        above: above ? { sh: above.scrollHeight, ch: above.clientHeight } : null,
        sideways,
        overlaps: [...new Set(overlaps)],
        cuts: [...new Set(cuts)],
        rows: { found: body !== null, whole, total, inView },
      }
    },
    { panel, row },
  )
}

export async function openFace(page: Page, tab: string) {
  await page.getByRole('tablist').first().getByRole('tab', { name: tab, exact: true }).click()
  await page
    .waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 })
    .catch(() => {})
  await page.waitForTimeout(600)
}


/** A LIVE-SIZED WORLD, LOCAL ONLY. The canary world a CI run boots serves one ledger entry, no route lane and a short
 *  board; the owner's world serves fifty entries and a board of lanes. `UNFOLD_WORLD=<a world image tarball>` serves that
 *  image in place of the built one (the same one-line route the measuring scripts use), so the unfold laws can be read
 *  on rows a played world has. Unset (CI), it does nothing and the specs read the canary. */
export async function seededWorld(page: Page): Promise<boolean> {
  const file = process.env.UNFOLD_WORLD
  if (!file) return false
  const body = readFileSync(file)
  await page.route('**/db/world-*.tar.gz', (route) => route.fulfill({ body, contentType: 'application/gzip' }))
  return true
}

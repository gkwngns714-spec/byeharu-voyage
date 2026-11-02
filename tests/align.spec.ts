/// <reference types="node" />
import { expect, test, type Page } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'
import { openCityPanel } from './openCity.fixture'

// EVERY LIST LINES UP (owner rows 196, 198, 199, 201 — 2026-10-25).
//
//   196  "at stats, market, risers fallers and all doesn't fit. it is not in the same line."
//   198  "same for stats, best and worst part, not alligned. review all the game and make it allign"
//   199  "on stats, the chart, the gold overlapps with the chart line."
//   201  "some sentences … can't read, and cant find a way to read long sentences that are cut."
//
// This walks every tab and sub-tab at 1280 and 390 and measures, in the running build:
//   LINE     a row's cells share one line: the first line of text in each cell has its vertical
//            centre within 2 px of the others (Row.tsx's line 1; and any hand-rolled repeated row)
//   COLUMN   sibling rows of one list start their cells at the same x, and end their last cell at
//            the same x, within 2 px; every `[data-col]` cell and `[data-track]` bar likewise
//   SPILL    no cell's text runs past its row's box
//   FIGURE   no `[data-figure]` breaks across two lines
//   PAIR     side-by-side sections (risers | fallers | most traded, best | worst) start their
//            headings on one line
//   CHART    no text box intersects a chart's plot area (`[data-plot]`)
//   CUT      any element whose text is cut (scrollWidth > clientWidth, or line-clamped) carries a
//            full-text affordance (`title`), or the spec fails
// The /ui gallery is walked too: it draws the chart, the ranked bars and a long name with data the
// fresh local world does not have yet (its first hour has one count, so no line).
//
// Not walked: COMMAND › Plans (src/features/command/plans/* is being redesigned in its own PR and
// moves onto Row's columns there), and the map's own labels (another PR owns them).

const WIDE = { width: 1280, height: 800 }
/** A local narrowing for a quick look at one screen (`ALIGN_ONLY=Stats`). Unset in CI, where every
 *  screen is walked and the measured-count floor below holds. */
const ONLY = process.env.ALIGN_ONLY ?? ''

interface Screen {
  name: string
  route: string
  /** Faces to press, in order, each measured: [tablist name or null for the first, tab name]. */
  faces?: [string | null, string][]
  /** What to press first to reach the screen (the map's city panel). */
  open?: (page: Page) => Promise<void>
}

const SCREENS: Screen[] = [
  { name: 'Command', route: 'command', faces: [[null, 'Trade'], [null, 'City'], [null, 'Invest'], [null, 'Report']] },
  { name: 'City', route: 'command', faces: [[null, 'City'], ['City buildings', '*']] },
  { name: 'Fleets', route: 'fleets' },
  { name: 'Map › Lisbon', route: 'map', open: (page) => openCityPanel(page, 'LIS', 'Lisbon') },
  { name: 'Stats', route: 'stats', faces: [[null, 'Overview'], [null, 'Markets'], [null, 'Cities'], [null, 'Merchants'], [null, 'Me']] },
  { name: 'Ledger', route: 'ledger', faces: [[null, 'All'], [null, 'Trade'], [null, 'Voyage'], [null, 'Crew']] },
  { name: 'Rank', route: 'rank', faces: [[null, 'Captains'], [null, 'Countries']] },
  // THE BOARD STANDS ON THE GLASS (the unfold slice, 2026-11-02, owner row 260): it was a page behind `routes-open`, which this walk
  // pressed to reach the sort strip; the strip is now in the panel's header, the first tablist, where the walk finds it.
  { name: 'Routes', route: 'routes', faces: [[null, 'Distance'], [null, 'Earnings'], [null, 'Calls']] },
  { name: 'Compendium', route: 'compendium', faces: [[null, 'Goods'], [null, 'Ships'], [null, 'Captains'], [null, 'Nations']] },
  { name: 'You', route: 'you' },
  { name: 'Profile', route: 'profile' },
  { name: 'Gallery', route: 'ui' },
]

/** Runs in the page: every defect on screen, as one line each. */
function measure(): string[] {
  const out: string[] = []
  const visible = (e: Element) => {
    const r = e.getBoundingClientRect()
    if (r.width === 0 || r.height === 0) return false
    const s = getComputedStyle(e)
    return s.visibility !== 'hidden' && s.display !== 'none' && Number(s.opacity) > 0
  }
  const label = (e: Element) => {
    const id = e.closest('[data-testid]')?.getAttribute('data-testid') ?? e.tagName.toLowerCase()
    const text = (e.textContent ?? '').replace(/\s+/g, ' ').trim().slice(0, 40)
    return `${id} "${text}"`
  }
  /** The centre of the first line of text inside `cell`, or its own centre when it has none. */
  const firstLine = (cell: Element): number | null => {
    const walk = document.createTreeWalker(cell, NodeFilter.SHOW_TEXT)
    for (let n = walk.nextNode(); n; n = walk.nextNode()) {
      if (!n.textContent?.trim()) continue
      const host = n.parentElement
      if (!host || !visible(host)) continue
      if (host.closest('svg')) continue
      const range = document.createRange()
      range.selectNodeContents(n)
      const r = [...range.getClientRects()].find((x) => x.width > 0)
      if (r) return r.top + r.height / 2
    }
    const r = cell.getBoundingClientRect()
    return r.height <= 44 ? r.top + r.height / 2 : null
  }
  const horizontal = (e: Element) => {
    const s = getComputedStyle(e)
    if (s.display.includes('flex')) return s.flexDirection === 'row' && s.flexWrap === 'nowrap'
    if (s.display.includes('grid')) return s.gridTemplateColumns.split(' ').length > 1
    return e.tagName === 'TR'
  }
  // a Row's cells are its line-1 cells; a hand-rolled row's are its children
  const cellsOf = (row: Element) =>
    [...row.children].filter(
      (c) =>
        visible(c) &&
        (!row.hasAttribute('data-row-line') || c.hasAttribute('data-row-cell')) &&
        getComputedStyle(c).position !== 'absolute' &&
        getComputedStyle(c).position !== 'fixed',
    )
  /** A cell is read from its end when its text is set to the right: compare that edge. */
  const endAligned = (c: Element) => /right|end/.test(getComputedStyle(c).textAlign) || getComputedStyle(c).justifyContent.includes('end')

  // ── the rows: Row.tsx's line, and any hand-rolled run of look-alike siblings ──────────────────
  const rows = new Set<Element>()
  document.querySelectorAll('[data-row-line]').forEach((e) => visible(e) && rows.add(e))
  document.querySelectorAll('body *').forEach((e) => {
    if (!visible(e) || rows.has(e) || !e.className || typeof e.className !== 'string') return
    if (e.closest('[data-row-line]') && !e.hasAttribute('data-row-line')) return
    // a toolbar (FilterBar's pickers, 0244) is controls side by side, not rows of a list
    if (e.closest('nav, [role="tablist"], [role="toolbar"], [data-testid="map-chart"], svg')) return
    // AN INLINE CHIP IS CONTENT, NOT A ROW (0285, 2026-10-31). A `Figure` is one inline-flex whose
    // two spans are its value and its unit, baseline-aligned by design (Figure.tsx, docs/UI_DIRECTION
    // §4.1), and the gallery draws seven of them side by side. The 120px chip floor below hid them
    // until the ×5 re-base made the hero "40,000🪙" wider than it — MEASURED on the built page at
    // 1280: 139.6px — and the heuristic then read value|unit as a ragged row. Computed display
    // cannot say so (a flex item blockifies: the root computes `flex`), so the primitive's own class
    // is the signal; no list row carries it (a Row is a grid, a hand-rolled row a block flex div).
    if (e.classList.contains('inline-flex')) return
    const sibs = [...(e.parentElement?.children ?? [])].filter((s) => s.tagName === e.tagName && s.className === e.className)
    if (sibs.length < 2) return
    if (!horizontal(e)) return
    const r = e.getBoundingClientRect()
    if (r.height > 160 || r.width < 120 || cellsOf(e).length < 2) return
    rows.add(e)
  })

  for (const row of rows) {
    const cells = cellsOf(row)
    const box = row.getBoundingClientRect()
    // LINE
    const lines = cells.map(firstLine).filter((y): y is number => y !== null)
    if (lines.length >= 2) {
      const spread = Math.max(...lines) - Math.min(...lines)
      if (spread > 2) out.push(`LINE ${label(row)}: its cells' first lines sit ${spread.toFixed(1)}px apart`)
    }
    // SPILL
    for (const c of cells) {
      const r = c.getBoundingClientRect()
      if (r.right > box.right + 1 || r.left < box.left - 1) out.push(`SPILL ${label(c)} runs ${Math.round(Math.max(r.right - box.right, box.left - r.left))}px past its row`)
    }
  }

  // COLUMN: sibling rows of one list
  // A LIST IS A PARENT'S ROWS IN ONE COLUMN (2026-11-02, owner row 267): a card list (ListPanel look="card", columns="fit") lays
  // its rows out in as many columns as the glass holds, and rows in two columns are not one list — each column is compared with itself.
  const lists = new Map<string, Element[]>()
  const parentIds = new Map<Element, number>()
  for (const row of rows) {
    const p = row.closest('[data-row]')?.parentElement ?? row.parentElement
    if (!p) continue
    if (!parentIds.has(p)) parentIds.set(p, parentIds.size)
    const key = `${parentIds.get(p)}@${Math.round(row.getBoundingClientRect().left / 8)}`
    lists.set(key, [...(lists.get(key) ?? []), row])
  }
  for (const [, list] of lists) {
    if (list.length < 2) continue
    // rows of one SHAPE are compared: a Row's slots by name (a chevron is not a value), a hand-rolled
    // row's by count
    const byCount = new Map<string, Element[]>()
    for (const r of list) {
      const n = cellsOf(r).map((c) => c.getAttribute('data-row-cell') ?? '·').join('|')
      byCount.set(n, [...(byCount.get(n) ?? []), r])
    }
    for (const [, same] of byCount) {
      if (same.length < 2) continue
      const first = same[0]
      const firstCells = cellsOf(first)
      for (const other of same.slice(1)) {
        const cs = cellsOf(other)
        for (let k = 0; k < cs.length; k++) {
          const a = firstCells[k].getBoundingClientRect()
          const b = cs[k].getBoundingClientRect()
          // THE FIGURE SITS BESIDE ITS LABEL (owner, 2026-11-01: *"there are empty spaces between
          // words and numbers horizontally which is in effective. make it so that htey are closer,
          // more compact"*). A Row's VALUE cell used to be held in a shared right-edge column; it is
          // now content-placed next to its label, so across sibling rows only its distance from that
          // label is the law — a value more than 16px from its own label is the defect.
          if (cs[k].getAttribute('data-row-cell') === 'action') continue // the edge affordance, not a column
          if (cs[k].getAttribute('data-row-cell') === 'value') {
            // A CARD LIST'S FIGURES STAND ON THE ROW'S RIGHT EDGE (2026-11-02, owner row 267 — the HUG law below was written for the
            // unfold slice, *"empty spaces between words and numbers"*, and the owner called that compaction a mistake: label and
            // figure glued at 12-85 px, where the past held 300-577). A row of a card list is one COLUMN wide (20 rem at the least), so
            // its figure ends where its neighbours' end: compared by the right edge, like any column. Every other list keeps HUG until
            // its own slice takes the card list.
            if (other.closest('[data-list-look="card"]') !== null) {
              const drift = Math.abs(a.right - b.right)
              if (drift > 2) {
                out.push(`COLUMN ${label(other)}: its figure ends ${Math.round(drift)}px from ${label(first)}'s`)
                break
              }
              continue
            }
            const prevA = k > 0 ? firstCells[k - 1]?.getBoundingClientRect() : undefined
            const prevB = k > 0 ? cs[k - 1]?.getBoundingClientRect() : undefined
            if (prevA && prevB) {
              const gap = Math.max(a.left - prevA.right, b.left - prevB.right)
              if (gap > 16) out.push(`HUG ${label(cs[k])}: the figure sits ${Math.round(gap)}px from its label`)
            }
            continue
          }
          // a column is held at the edge its text is set from: a label's start, a figure's end
          const drift = endAligned(cs[k]) ? Math.abs(a.right - b.right) : Math.abs(a.left - b.left)
          if (drift > 2) {
            out.push(`COLUMN ${label(other)}: cell ${k + 1} drifts ${Math.round(drift)}px from ${label(first)}`)
            break
          }
        }
      }
      // THE GALLERY'S COLUMN DEMO IS A SHOWCASE, NOT A GAME LIST: it draws columns INSIDE a Row's
      // label to demonstrate the equal-column pattern; the owner's 2026-11-01 law made that label
      // content-sized (the figure hugs its label), so the demo's columns follow their own content —
      // accurate for the gallery and irrelevant to every game screen. The [data-col] law is about
      // hand-rolled game rows; it does not read the gallery's exhibit.
      const isGalleryDemo = first.closest('[data-testid="gallery-col-row"]') !== null
      if (!isGalleryDemo)
        for (const sel of ['[data-col]', '[data-track]']) {
        const ref = [...first.closest('[data-row]')?.querySelectorAll(sel) ?? first.querySelectorAll(sel)]
        for (const other of same.slice(1)) {
          const mine = [...other.closest('[data-row]')?.querySelectorAll(sel) ?? other.querySelectorAll(sel)]
          for (let k = 0; k < Math.min(ref.length, mine.length); k++) {
            const a = ref[k].getBoundingClientRect()
            const b = mine[k].getBoundingClientRect()
            const d = Math.max(Math.abs(a.left - b.left), Math.abs(a.right - b.right))
            if (d > 2 && visible(mine[k])) out.push(`COLUMN ${label(other)}: ${sel} ${k + 1} drifts ${Math.round(d)}px`)
          }
        }
      }
    }
  }

  // FIGURE
  document.querySelectorAll('[data-figure]').forEach((f) => {
    if (!visible(f)) return
    const lh = parseFloat(getComputedStyle(f).lineHeight) || parseFloat(getComputedStyle(f).fontSize) * 1.3
    if (f.getBoundingClientRect().height > lh * 1.6) out.push(`FIGURE ${label(f)} breaks across lines`)
  })

  // PAIR: sections standing side by side start their headings on one line
  document.querySelectorAll('body *').forEach((p) => {
    const secs = [...p.children].filter((c) => c.tagName === 'SECTION' && visible(c))
    if (secs.length < 2) return
    const tops = secs.map((s) => s.getBoundingClientRect())
    for (let i = 1; i < tops.length; i++) {
      const sideBySide = tops[i].left > tops[i - 1].right - 1
      if (sideBySide && Math.abs(tops[i].top - tops[i - 1].top) > 2) {
        out.push(`PAIR ${label(secs[i])} starts ${Math.round(tops[i].top - tops[i - 1].top)}px below ${label(secs[i - 1])}`)
      }
    }
  })

  // CHART: no text over the plot
  document.querySelectorAll('[data-plot]').forEach((plot) => {
    if (!visible(plot)) return
    const p = plot.getBoundingClientRect()
    const chart = plot.closest('[data-chart]') ?? plot.parentElement!
    const walk = document.createTreeWalker(chart, NodeFilter.SHOW_TEXT)
    for (let n = walk.nextNode(); n; n = walk.nextNode()) {
      if (!n.textContent?.trim() || !n.parentElement || !visible(n.parentElement)) continue
      const range = document.createRange()
      range.selectNodeContents(n)
      for (const r of range.getClientRects()) {
        const overlap = r.right > p.left + 0.5 && r.left < p.right - 0.5 && r.bottom > p.top + 0.5 && r.top < p.bottom - 0.5
        if (overlap) out.push(`CHART "${n.textContent.trim()}" is drawn over the plot of ${label(chart)}`)
      }
    }
  })

  // CUT: cut text carries its full text
  document.querySelectorAll('body *').forEach((e) => {
    if (!(e instanceof HTMLElement) || !visible(e) || e.closest('svg')) return
    if (!e.textContent?.trim() || e.children.length > 0 && e.innerText.trim() === '') return
    const s = getComputedStyle(e)
    const clamped = s.webkitLineClamp !== 'none' && s.webkitLineClamp !== '' && e.scrollHeight > e.clientHeight + 1
    const cutX = s.overflowX !== 'visible' && s.textOverflow === 'ellipsis' && e.scrollWidth > e.clientWidth + 1
    const hiddenX = (s.overflowX === 'hidden' || s.overflowX === 'clip') && s.whiteSpace === 'nowrap' && e.scrollWidth > e.clientWidth + 1
    if (!clamped && !cutX && !hiddenX) return
    if (e.closest('[data-testid="map-chart"]')) return
    const hasFull = e.closest('[title]')?.getAttribute('title')?.trim()
    if (!hasFull) out.push(`CUT ${label(e)} is cut with no way to read the rest`)
  })

  return [...new Set(out)]
}

async function pressFace(page: Page, list: string | null, tab: string): Promise<string[]> {
  const strip = list ? page.getByRole('tablist', { name: list }) : page.getByRole('tablist').first()
  if (tab !== '*') {
    await strip.getByRole('tab', { name: tab, exact: true }).click()
    await page.waitForTimeout(1500)
    return [tab]
  }
  await strip.waitFor({ timeout: 60_000 })
  return strip.getByRole('tab').allInnerTexts()
}

async function audit(page: Page, vp: { width: number; height: number }): Promise<string[]> {
  const found: string[] = []
  let measured = 0
  for (const s of SCREENS) {
    if (ONLY && !s.name.includes(ONLY)) continue
    await page.goto(s.route)
    // the gallery stands outside the shell and reads no world: it is up when its rows are drawn
    if (s.route === 'ui') await page.getByTestId('gallery-row').first().waitFor({ timeout: 60_000 })
    else await ready(page)
    if (s.open) await s.open(page)
    const look = async (where: string) => {
      await page.waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 }).catch(() => {})
      const defects = await page.evaluate(measure)
      measured++
      for (const d of defects) found.push(`${vp.width}px ${where}: ${d}`)
    }
    if (!s.faces) await look(s.name)
    for (const [list, tab] of s.faces ?? []) {
      if (tab !== '*') {
        await pressFace(page, list, tab)
        await look(`${s.name} › ${tab}`)
        continue
      }
      for (const name of await pressFace(page, list, '*')) {
        await pressFace(page, list, name)
        await look(`${s.name} › ${name}`)
      }
    }
  }
  if (!ONLY) expect(measured, 'the walk skipped screens').toBeGreaterThan(SCREENS.length)
  return found
}

for (const vp of [WIDE, PHONE]) {
  test(`every list lines up at ${vp.width}px — one line per row, the figure beside its label, no cut sentence, no label on a chart line`, async ({ page, request, baseURL }, info) => {
    test.setTimeout(900_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(vp)
    const found = await audit(page, vp)
    await info.attach(`align-${vp.width}.txt`, { body: found.join('\n') || 'none', contentType: 'text/plain' })
    console.log(`${vp.width}px: ${found.length} defects\n${found.join('\n')}`)
    expect(found, 'misaligned or unreadable rows').toEqual([])
  })
}

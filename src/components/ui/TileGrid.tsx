import { useLayoutEffect, useRef, type ReactNode } from 'react'
import { WIDE_QUERY } from './screenLayout'
import { COLUMN_CLASS, WORDS_COLUMN_CLASS, WORDS_COLUMN_WIDE_CLASS, tileCellClass, tileWordsGridClass, type ChoiceColumns, type WordColumns } from './tileStyles'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ONE GRID FOR EVERY SET OF TAPPABLE CHOICES (owner, 2026-10-31)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"in stats money log, the tappable thing is not ordered. make it into square and allign properly
// orderly. this applies to all the places throughout the game."*
//
// A filter, a sector, a face, a city: before this each was a shrink-wrapped pill whose width was
// its own word, so a row of them ended ragged at both edges — a chip row read as debris rather
// than as a control. THE GRID IS THE ANSWER: a fixed number of equal columns, every cell the same
// width in its row and the same height (44 px, the reach floor), left edges on the column lines.
//
// WHY A CELL IS `min-h-11` AND NOT `aspect-square`: a literal square of a third of a 390-px glass
// is 120 px tall, and eight of them would be 400 px of a screen the owner asked to pack onto one
// page. "Square" in the owner's sentence is the ORDER (a table of tiles), not the ratio; the cells
// are equal, aligned, and one row per line of words. The spec measures equality and alignment.
//
// THE COLUMN COUNTS ARE A SMALL FIXED SET, and they are literal class names because Tailwind
// cannot see a class built from a number. `columns` is chosen by the caller's cell count, not at
// runtime from width.
//
// `Segmented` (Chip.tsx) composes the same grid for faces, with its own two-state skin: the base
// cell recipe lives here once, so a tab and a filter cannot drift apart.

/** A cell may carry the caller's own data-* hooks (a city code, a filter value) — typed once here
 *  rather than widening each primitive's props with one screen's attribute name. */
type DataAttrs = { [K in `data-${string}`]?: string | number | boolean | undefined }

/** The grid itself: `role` and `label` are the caller's, because a set of choices may be a group,
 *  a radio set or a set of faces. The cells are equal by construction (`1fr` columns).
 *
 *  `words` (tileStyles.ts, THE GRID THAT KEEPS ITS WORDS): for a set of proper names. The cells stand on `words` equal columns
 *  (`wordsWide` of them from `lg`), a name wraps only at its spaces, and a cell is never narrower than its longest word. */
export function TileGrid({
  label,
  columns = 4,
  words,
  wordsWide,
  role = 'group',
  className = '',
  children,
  ...rest
}: {
  /** Names the set for assistive tech. Not painted. */
  label?: string
  columns?: ChoiceColumns
  /** A grid of names that keeps every word whole: its column count (it replaces `columns`). */
  words?: WordColumns
  /** The words grid's column count from `lg`; omitted, the same count at every glass. */
  wordsWide?: WordColumns
  role?: 'group' | 'radiogroup' | 'tablist'
  className?: string
  children: ReactNode
} & { 'data-testid'?: string } & DataAttrs) {
  const grid = useRef<HTMLDivElement | null>(null)
  useWordSpans(grid, words, wordsWide)
  return (
    <div
      ref={grid}
      role={role}
      aria-label={label}
      data-choice-grid=""
      data-words={words ? '' : undefined}
      className={
        words
          ? `${tileWordsGridClass()} ${WORDS_COLUMN_CLASS[words]} ${wordsWide ? WORDS_COLUMN_WIDE_CLASS[wordsWide] : ''} ${className}`
          : `grid ${COLUMN_CLASS[columns]} gap-1.5 narrow:flex narrow:flex-wrap narrow:gap-1 ${className}`
      }
      {...rest}
    >
      {children}
    </div>
  )
}

/** ONE CELL: a tappable choice, selected by the accent wash + hairline (never a solid fill — the
 *  same rule `Tile` and `Chip` carry, so a selected cell stays readable). */
export function TileChoice({
  on = false,
  onClick,
  children,
  className = '',
  ...rest
}: {
  on?: boolean
  onClick?: () => void
  children: ReactNode
  className?: string
} & { 'data-testid'?: string } & DataAttrs) {
  return (
    <button
      type="button"
      aria-pressed={on}
      onClick={onClick}
      className={`${tileCellClass()} ${on ? 'bg-accent-soft text-accent ring-1 ring-accent' : 'bg-surface-2 text-ink-muted hover:text-ink'} ${className}`}
      {...rest}
    >
      {children}
    </button>
  )
}

/**
 * A CELL THAT DOES NOT FIT ONE COLUMN ON ONE LINE TAKES TWO (tileStyles.ts, "ONE LINE A NAME"). Measured off the cells as they
 * stand, never guessed from a letter count: each cell's one-line width against the grid's own column, re-read when the grid's
 * width, its cells or their words change. It writes one inline `flex` (and lifts the one-column cap) on a cell that spans, and
 * nothing on a cell that does not: without it the grid is the wrapping line it always was.
 */
function useWordSpans(grid: { current: HTMLDivElement | null }, base: number | undefined, wide: number | undefined) {
  useLayoutEffect(() => {
    const el = grid.current
    if (base === undefined || !el) return
    const clear = (c: HTMLElement) => {
      for (const p of ['flex', 'max-width', 'width', 'white-space']) c.style.removeProperty(p)
    }
    const lay = () => {
      const cells = [...el.children].filter((c): c is HTMLElement => c instanceof HTMLElement)
      if (cells.length === 0) return
      // every cell at its one-line width, read in one layout
      for (const c of cells) {
        c.style.setProperty('flex', '0 0 auto', 'important')
        c.style.setProperty('max-width', 'none', 'important')
        c.style.width = 'max-content'
        c.style.whiteSpace = 'nowrap'
      }
      const needs = cells.map((c) => c.getBoundingClientRect().width)
      cells.forEach(clear)
      const columns = wide !== undefined && window.matchMedia(WIDE_QUERY).matches ? wide : base
      const gap = parseFloat(getComputedStyle(el).columnGap) || 0
      const column = (el.clientWidth - gap * (columns - 1)) / columns
      if (!(column > 0)) return
      const spans = needs.map((w) => Math.min(columns, Math.max(1, Math.ceil((w - 0.5 + gap) / (column + gap)))))
      // a wide cell that does not fit the rest of its line starts the next; the cell before it takes the rest
      let at = 0
      let lines = 1
      spans.forEach((span, i) => {
        if (at + span > columns) {
          if (i > 0) spans[i - 1] += columns - at
          at = 0
        }
        if (at === 0 && i > 0) lines++
        at = (at + span) % columns
      })
      // NEVER A LINE MORE THAN THE PLAIN GRID: two or three long names would cost the picker a whole line (eight Brazilian
      // harbours in Korean stood on four lines and the Trade face scrolled under way, tests/trade.flow.spec.ts T3). Then the
      // wrapping line stands as it is, where a long cell is a little over its column and the line still holds its count.
      if (lines > Math.ceil(cells.length / columns)) return
      cells.forEach((c, i) => {
        const n = spans[i]
        if (n === 1) return
        c.style.setProperty('flex', `0 0 calc(var(--tile-w) * ${n} + ${gap * (n - 1)}px)`, 'important')
        c.style.setProperty('max-width', 'none', 'important')
      })
    }
    lay()
    const resized = new ResizeObserver(lay)
    resized.observe(el)
    const changed = new MutationObserver(lay)
    changed.observe(el, { childList: true, characterData: true, subtree: true })
    void document.fonts?.ready.then(lay)
    return () => {
      resized.disconnect()
      changed.disconnect()
    }
  }, [grid, base, wide])
}

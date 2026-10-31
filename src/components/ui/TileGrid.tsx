import type { ReactNode } from 'react'
import { COLUMN_CLASS, tileCellClass, type ChoiceColumns } from './tileStyles'

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
 *  a radio set or a set of faces. The cells are equal by construction (`1fr` columns). */
export function TileGrid({
  label,
  columns = 4,
  role = 'group',
  className = '',
  children,
  ...rest
}: {
  /** Names the set for assistive tech. Not painted. */
  label?: string
  columns?: ChoiceColumns
  role?: 'group' | 'radiogroup' | 'tablist'
  className?: string
  children: ReactNode
} & { 'data-testid'?: string } & DataAttrs) {
  return (
    <div
      role={role}
      aria-label={label}
      data-choice-grid=""
      className={`grid ${COLUMN_CLASS[columns]} gap-1.5 ${className}`}
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

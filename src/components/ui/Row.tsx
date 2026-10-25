import type { MouseEvent, ReactNode } from 'react'
import { Icon } from './Icon'

// THE ROW — 52px, and it is what a table was.
//
// ── WHAT IT REPLACES, COUNTED ──────────────────────────────────────────────────────────────────
// docs/UI_DIRECTION.md §3 rule 5 measured FIVE spellings of "label · value" in this tree —
// `StatRow`, `DetailRow`, `EntryTileLine`, the Map panel's private `Line`, and inline
// `grid grid-cols-[auto_1fr]` definition lists in two screens — plus the whole table apparatus
// that exists only so a table can survive a phone: `Table/TH/TD`, `scrollTableClass` with its
// sticky first column and painted scrollbar, `hScrollClass`, the `useClipped` ResizeObserver, and
// `TABLE_SCROLL_HINT` ("Swipe the table for the rest."). On screen the result was a column header
// that read `TRA…`.
//
// A row does not scroll sideways, so none of that machinery has anything to do. That is the whole
// argument: the tables were never carrying more than four facts, and four facts fit in a row.
//
// ── 52px, AND WHY IT IS A TOKEN ────────────────────────────────────────────────────────────────
// `--spacing-row` (src/index.css) is 3.25rem = 52px = the 44px reach floor plus the 8pt rhythm.
// It is a NAMED token rather than an arithmetic class so that a row cannot be spelled `min-h-13`
// in one file and `py-3.5` in another and drift by two pixels. tests/primitives.geometry.spec.ts
// measures it in the running build; this comment is not the guard.
//
// ── THE FOUR SLOTS, AND THE ONE THAT IS NOT ALLOWED ────────────────────────────────────────────
//   mark     a leading `Icon` or `RarityMark` — the row's identity at a glance
//   label    what it is, in `t-label`. Body copy lives here too; an empty section is ONE row of
//            `ink-3` text, which is what `EmptyState` was for
//   value    what it reads, normally a `<Figure>` — or a `<Bar>`, which is a figure you can see
//   chevron  set when the row OPENS something (a `Tray`, another sheet). Drawn, never `›`
// There is no `explain` slot and there never will be: §5 gives the caption voice to `Hint`, with a
// budget of one per section and none on a title. Eighty-one ⓘ dots is what the absence of that
// budget looks like.
//
// ── TAPPABLE IS A DIFFERENT ELEMENT, NOT A DIFFERENT SKIN ──────────────────────────────────────
// Pass `onClick` and the row renders a real `<button>` (`href` renders an `<a>`), so the whole
// 52px band is the target and a keyboard reaches it. A row that merely *looks* pressable is the
// defect this avoids by construction.
//
// THE TWO MAY BE PASSED TOGETHER, and that pairing is what a single-page router needs: the row
// stays a real `<a href>` — middle-click, long-press and assistive technology all keep working —
// while the plain left-click is handed to `onClick`, which calls `preventDefault()` and routes.
// (`Nav.tsx` carries the same pairing for the same reason. This app's database lives in the
// browser; a genuine anchor navigation re-opens PGlite.) The handler is given the event because
// there is no other way to refuse the browser's own navigation.

export type RowTone = 'default' | 'accent' | 'muted'

const TONE: Record<RowTone, string> = {
  default: 'text-ink',
  // Selected / yours. §4.4: gold means "you may act, or this is yours".
  accent: 'text-accent',
  // Absent, refused, not yet — the row is present and says so quietly.
  muted: 'text-ink-faint',
}

export function Row({
  mark,
  label,
  value,
  chevron = false,
  tone = 'default',
  hairline = true,
  onClick,
  href,
  disabled = false,
  className = '',
  children,
  ...rest
}: {
  mark?: ReactNode
  /** What this row is. A string, or a small stack the caller composes. */
  label: ReactNode
  /** What it reads — a `<Figure>`, a `<Bar>`, a word. Right-aligned, never wrapped. */
  value?: ReactNode
  /** Set when pressing the row OPENS something. */
  chevron?: boolean
  tone?: RowTone
  /** The 1px `edge` parting rule under the row. Off for the last row of a group. */
  hairline?: boolean
  /** May be passed WITH `href`, in which case the row stays an anchor and this answers the click. */
  onClick?: (event: MouseEvent<HTMLElement>) => void
  href?: string
  disabled?: boolean
  className?: string
  /** A second line under the label — a `<Bar>`, a `<Hint>`. Rows grow; 52px is the FLOOR. */
  children?: ReactNode
} & { 'data-testid'?: string }) {
  // THE LINE, AND THE LINE UNDER IT (2026-10-25, owner rows 196 and 198: "it is not in the same
  // line"). The row is a GRID, not a flex box. Line 1 holds the mark, the label and the value in
  // fixed tracks, and every cell's first line of text sits in ONE 24px line box (`.bv-row-line`,
  // src/index.css), so a label in `t-label`, a figure in `t-body` and a mark all centre on the same
  // y. Line 2 — `children`, the bar or the caption — spans from the label's start to the row's end,
  // so a list of ranked bars draws every bar on the same track whatever its figure reads. Before
  // this the value was centred against the label AND its bar together, half a line below the name,
  // and each bar was as long as its own row's label column: no two bars started or ended together.
  //
  // A CONTROL AS THE VALUE (a `Button`, 44px to the line's 24) is centred ON the line, hanging 10px
  // above and below it (src/index.css), so "Portugal" and "Change" read as one line rather than one
  // at the top and one centred in a taller box.
  const columns = [mark !== undefined ? 'auto' : null, 'minmax(0,1fr)', value !== undefined ? 'auto' : null, chevron ? 'auto' : null]
    .filter(Boolean)
    .join(' ')
  const body = (
    <>
      {mark !== undefined && (
        <span className="bv-row-line flex h-6 items-center" data-row-cell="mark">
          {mark}
        </span>
      )}
      <span className="bv-row-line min-w-0 break-words text-t-label" data-row-cell="label">
        {label}
      </span>
      {value !== undefined && (
        <span className="bv-row-line whitespace-nowrap text-right text-t-body tabular-nums" data-row-cell="value">
          {value}
        </span>
      )}
      {chevron && (
        <span className="bv-row-line flex h-6 items-center" data-row-cell="chevron">
          <Icon name="chevron" size={20} className="text-ink-faint" />
        </span>
      )}
      {children !== undefined && children !== null && children !== false && (
        <span className="min-w-0 text-t-label" style={{ gridColumn: mark !== undefined ? '2 / -1' : '1 / -1' }}>
          {children}
        </span>
      )}
    </>
  )

  const shell = [
    'grid w-full min-h-row content-center items-start gap-x-3 py-2 text-left',
    hairline ? 'border-b border-edge' : '',
    TONE[tone],
    className,
  ]
    .filter(Boolean)
    .join(' ')
  const grid = { gridTemplateColumns: columns }

  if (href !== undefined) {
    return (
      <a href={href} onClick={onClick} className={shell} style={grid} data-row-line {...rest}>
        {body}
      </a>
    )
  }
  if (onClick !== undefined) {
    return (
      <button type="button" onClick={onClick} disabled={disabled} className={`${shell} disabled:opacity-45`} style={grid} data-row-line {...rest}>
        {body}
      </button>
    )
  }
  return (
    <div className={shell} style={grid} data-row-line {...rest}>
      {body}
    </div>
  )
}

// ── COLUMNS INSIDE THE VALUE ───────────────────────────────────────────────────────────────────
// A row that reads more than one figure (a price AND its move, a sparkline beside them) puts each in
// a `Col`: a FIXED-width, one-line, right-aligned, tabular cell. Fixed is the point — a column whose
// width is its own content starts wherever its row's digits happen to end, and a list of them is a
// ragged edge. One width scale, named here and nowhere else.
//   phone="hide"  the column stands down below the `sm` breakpoint; what it says must be said by
//                 another column or by line 2 of the row. Never a sideways scroll.
export type ColWidth = 'xs' | 'sm' | 'md' | 'lg'
const COL_W: Record<ColWidth, string> = {
  xs: 'w-10', // 40px: a short count
  sm: 'w-16', // 64px: a price, a percent change
  md: 'w-20', // 80px: a sparkline, a seven-digit figure
  lg: 'w-28', // 112px: a figure with its coin or unit
}

export function Col({
  w,
  phone,
  align = 'end',
  className = '',
  children,
}: {
  w: ColWidth
  phone?: 'hide'
  align?: 'start' | 'end'
  className?: string
  children: ReactNode
}) {
  const shown = phone === 'hide' ? 'hidden sm:flex' : 'flex'
  return (
    <span
      className={`${shown} ${COL_W[w]} shrink-0 items-center whitespace-nowrap tabular-nums ${align === 'end' ? 'justify-end text-right' : 'justify-start text-left'} ${className}`}
      data-col={w}
    >
      {children}
    </span>
  )
}

/** Several `Col`s side by side, as a row's `value`. */
export function Cols({ children }: { children: ReactNode }) {
  return <span className="flex items-center gap-3">{children}</span>
}

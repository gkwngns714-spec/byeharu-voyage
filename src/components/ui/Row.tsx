import type { ReactNode } from 'react'
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
  onClick?: () => void
  href?: string
  disabled?: boolean
  className?: string
  /** A second line under the label — a `<Bar>`, a `<Hint>`. Rows grow; 52px is the FLOOR. */
  children?: ReactNode
} & { 'data-testid'?: string }) {
  const body = (
    <>
      {mark !== undefined && <span className="flex shrink-0 items-center">{mark}</span>}
      <span className="min-w-0 flex-1 text-t-label">
        {label}
        {children}
      </span>
      {value !== undefined && <span className="shrink-0 text-right text-t-body">{value}</span>}
      {chevron && <Icon name="chevron" size={20} className="shrink-0 text-ink-faint" />}
    </>
  )

  const shell = [
    'flex w-full min-h-row items-center gap-3 py-2 text-left',
    hairline ? 'border-b border-edge' : '',
    TONE[tone],
    className,
  ]
    .filter(Boolean)
    .join(' ')

  if (href !== undefined) {
    return (
      <a href={href} className={shell} {...rest}>
        {body}
      </a>
    )
  }
  if (onClick !== undefined) {
    return (
      <button type="button" onClick={onClick} disabled={disabled} className={`${shell} disabled:opacity-45`} {...rest}>
        {body}
      </button>
    )
  }
  return (
    <div className={shell} {...rest}>
      {body}
    </div>
  )
}

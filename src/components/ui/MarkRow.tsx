import type { ReactNode } from 'react'
import { Bar, type BarTone } from './Bar'
import { Icon } from './Icon'
import type { IconName } from './icons'

// THE MARK ROW — a glyph, a short word, its figure, and under them a bar (2026-11-23, visual pass 3).
//
// Stats > Pirates' Totals, the Routes overview and History's Money card were columns of label-and-zero lines: a word at the left,
// a figure at the right, every line the same weight. Slice 8 drew Stats > Me as a mark before each line; this is that line made
// once, with the bar the principle asks of every figure that is part of a whole ("a figure is a mark, a figure and a bar"). The
// bar is the caller's share (this figure against the largest of its card), never a sum made here.
//
// No border, no background (a row inside a card, docs/UI_DIRECTION.md §4.3). `aside` is a second, quieter figure (the last 24 h
// beside the 7 days); `tone` is the bar's meaning (§4.4: green and red only for gain and loss).
/** The two figure columns of a row with an `aside`, and of their head, on one edge. */
const COLUMN = 'flex min-w-[4.5rem] shrink-0 justify-end'

/** THE HEAD OF TWO FIGURE COLUMNS (the aside's word, then the figure's), standing over a set of mark rows with an `aside`. */
export function MarkRowHead({ aside, figure }: { aside: ReactNode; figure: ReactNode }) {
  return (
    <div className="flex items-center justify-end gap-2 pb-1 text-t-caption text-ink-faint">
      <span className={COLUMN}>{aside}</span>
      <span className={COLUMN}>{figure}</span>
    </div>
  )
}

export function MarkRow({
  icon,
  label,
  figure,
  aside,
  pct,
  tone = 'neutral',
  className = '',
  ...rest
}: {
  icon: IconName
  /** One or two words: the figure's name. */
  label: ReactNode
  /** The figure (a `Figure` or a `Counter`). */
  figure: ReactNode
  /** A second, quieter figure before the main one. */
  aside?: ReactNode
  /** The bar's fill, 0-100; omitted, no bar. */
  pct?: number
  tone?: BarTone
  className?: string
} & { 'data-testid'?: string }) {
  return (
    <div className={`min-w-0 py-1.5 ${className}`} data-mark-row={icon} {...rest}>
      <div className="flex min-h-8 items-center gap-2">
        <Icon name={icon} size={18} className="shrink-0 text-ink-muted" />
        <span className="min-w-0 flex-1 break-words text-t-label text-ink-muted">{label}</span>
        {aside !== undefined && <span className={COLUMN}>{aside}</span>}
        <span className={aside !== undefined ? COLUMN : 'shrink-0'}>{figure}</span>
      </div>
      {pct !== undefined && <Bar pct={pct} tone={tone} className="ml-[26px] mt-0.5" />}
    </div>
  )
}


import type { ReactNode } from 'react'
import { TileGrid } from './TileGrid'
import { tileCellClass, type ChoiceColumns } from './tileStyles'

// THE CHIP, AND THE SEGMENTED CONTROL — one token in a set, and one set of faces.
//
// THEY ARE TWO THINGS, and the tree proved it by drawing them with one recipe and getting both
// wrong. A CHIP is a token you turn on and off in a set where any number may be on — a filter, a
// preset, a rarity. A SEGMENTED control is 2–5 FACES of one thing where exactly one is on — buy or
// sell, ships or cargo or stores, the seven faces of a port. `buttonClasses('chip'|'chip-on')`,
// the Market's private `Chip`, `PortChip` and `TabRow` were all reaching for one or the other, and
// every caller added an `extra` override, so a chip had no one look (§3 rule 4).
//
// ── WHAT THE SEGMENTED CONTROL FIXES ON SIGHT ──────────────────────────────────────────────────
// PORT once drew seven faces as a `TabRow` that wrapped to two rows, and a bare row of buttons did
// not say there was more. A segmented control is ONE set of faces on a `surface-2` track, the
// selected face a raised `surface` pill — the shape a phone has used for "which side of this am I
// looking at" for fifteen years, read without a label. The owner's law (2026-10-30): NOTHING scrolls
// sideways, so a face set that outgrows one line WRAPS to the next (`flex-wrap`), never `overflow-x-auto`.
//
// BOTH CLEAR 44px. The reach floor does not care how small a control looks — `Input.tsx` learned
// that in August and the same sentence applies.
//
// NO UPPERCASE, NO LETTER-SPACING (§4.1). `TabRow` set its faces in `font-mono text-xs uppercase
// tracking-wider`, which is §2 item 15's "the label voice is louder than the content voice".

export function Chip({
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
} & { 'data-testid'?: string }) {
  return (
    <button
      type="button"
      aria-pressed={on}
      onClick={onClick}
      className={[
        'inline-flex min-h-11 min-w-11 items-center justify-center gap-1.5 rounded-chip px-3 text-t-caption transition',
        on ? 'bg-accent-soft text-accent' : 'bg-surface-2 text-ink-muted',
        className,
      ].join(' ')}
      {...rest}
    >
      {children}
    </button>
  )
}

export interface SegmentSpec<T extends string> {
  id: T
  label: ReactNode
}

// THE SET OF FACES STAND ON THE CHOICE GRID (owner, 2026-10-31: *"make it into square and allign
// properly orderly. this applies to all the places throughout the game."*). Before this a face
// bar was a row of shrink-wrapped pills whose widths were their own words; the grid gives every
// face one column width, one 44-px line and left edges on the column lines. The base cell recipe
// is `TileGrid`'s (`tileCellClass`), so a face and a filter cannot drift apart; only the state
// skin differs — a selected face is the raised `surface` on the track, a selected filter is the
// accent wash.
//
// COLUMNS: the caller may name them; otherwise the set itself decides — up to five faces share
// one row, and a longer set (eight buildings, ten hull filters) takes four columns and wraps.
export function Segmented<T extends string>({
  segments,
  value,
  onChange,
  label,
  fill = false,
  columns,
  className = '',
}: {
  segments: readonly SegmentSpec<T>[]
  value: T
  onChange: (id: T) => void
  /** Names the set for assistive tech ("Port faces"). Not painted. */
  label: string
  /** The set shares the whole width (a fixed set of faces on a panel's top edge). */
  fill?: boolean
  /** Fixed column count; default: the set's own size up to five, four beyond it. */
  columns?: ChoiceColumns
  className?: string
}) {
  const cols: ChoiceColumns = columns ?? (segments.length <= 5 ? (Math.max(2, segments.length) as 2 | 3 | 4 | 5) : 4)
  return (
    <TileGrid
      role="tablist"
      label={label}
      columns={cols}
      className={['rounded-control bg-surface-2 p-1', fill ? 'w-full' : 'w-fit max-w-full', className].filter(Boolean).join(' ')}
    >
      {segments.map((s) => {
        const on = s.id === value
        return (
          <button
            key={s.id}
            role="tab"
            type="button"
            aria-selected={on}
            onClick={() => onChange(s.id)}
            className={`${tileCellClass()} ${on ? 'bg-surface text-ink' : 'text-ink-muted'}`}
          >
            {s.label}
          </button>
        )
      })}
    </TileGrid>
  )
}

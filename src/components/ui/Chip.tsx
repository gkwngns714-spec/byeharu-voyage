import type { ReactNode } from 'react'

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

export function Segmented<T extends string>({
  segments,
  value,
  onChange,
  label,
  fill = false,
  className = '',
}: {
  segments: readonly SegmentSpec<T>[]
  value: T
  onChange: (id: T) => void
  /** Names the set for assistive tech ("Port faces"). Not painted. */
  label: string
  /** The segments share the whole width — a short fixed set (the map city panel's Market | Port |
   *  Inn), where a scrolling row of shrink-wrapped cells would leave half the bar empty. */
  fill?: boolean
  className?: string
}) {
  return (
    <div
      role="tablist"
      aria-label={label}
      className={`flex flex-wrap gap-1 rounded-control bg-surface-2 p-1 ${className}`}
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
            className={[
              'min-h-11 min-w-11 shrink-0 whitespace-nowrap rounded-control px-3 text-t-caption transition',
              fill ? 'flex-1' : '',
              on ? 'bg-surface text-ink' : 'text-ink-muted',
            ].join(' ')}
          >
            {s.label}
          </button>
        )
      })}
    </div>
  )
}

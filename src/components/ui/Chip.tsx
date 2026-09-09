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
// PORT draws seven faces as a `TabRow` that WRAPS TO TWO ROWS at 390px (§2 item 9: "two rows of
// tabs is a menu, not a face"). A segmented control is ONE row that scrolls its own overflow, on
// a `surface-2` track with the selected face as a raised `surface` pill — the shape a phone has
// used for "which side of this am I looking at" for fifteen years, and one a player reads without
// a label. The strip scrolls, and that is honest here in a way it was not for `TabRow`: a track
// with a visibly clipped pill at its edge says there is more, where a bare row of buttons did not.
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
  className = '',
}: {
  segments: readonly SegmentSpec<T>[]
  value: T
  onChange: (id: T) => void
  /** Names the set for assistive tech ("Port faces"). Not painted. */
  label: string
  className?: string
}) {
  return (
    <div
      role="tablist"
      aria-label={label}
      className={`flex gap-1 overflow-x-auto rounded-control bg-surface-2 p-1 ${className}`}
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

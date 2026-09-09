import type { ReactNode } from 'react'

// THE NUMBER, AND ITS UNIT — the primitive every figure in this game is drawn by.
//
// docs/UI_DIRECTION.md §4.1: "`font-variant-numeric: tabular-nums` on EVERY figure via the
// `Figure` primitive". That is the whole reason this exists rather than a class: a figure is not a
// size, it is a KIND of text, and the three things that make it one — tabular lining, the unit
// riding small and dim beside it, and the value never wrapping away from its unit — were spelled
// out at 91 `font-mono … tabular-nums` sites in features alone before this file.
//
// WHAT IT REPLACES (marked deprecated in index.ts until step 10 deletes them): `HeroFigure`,
// `inlineFigureClass`, and every hand-written `<span className="font-mono tabular-nums …">`.
//
// THREE SIZES, NOT SIX. The type scale has six steps; a FIGURE uses three of them, because the
// other three are the label voice:
//   `body`    16/22  a figure inside a row or a tile — the common case
//   `figure`  24/28  the ONE figure a block is about (a price, an ETA, the purse)
//   `hero`    34/38  the headline figure of a sheet (capacity, passage days)
// A caller who wants a fourth is asking for a layout, not a size.
//
// THE UNIT IS NEVER DROPPED AND NEVER GROWN. It is `t-caption` in `ink-3` at every size, which is
// EVE's rule (a number without its unit is not a number) and also what stops "4,182 d." from
// wrapping a 390px column: the pair is one `inline-flex` with `whitespace-nowrap`, so the break
// happens before the figure or not at all.

export type FigureSize = 'body' | 'figure' | 'hero'

/** The four meanings §4.4 allows a number to carry, plus the two inks. Never a fifth. */
export type FigureTone = 'ink' | 'muted' | 'faint' | 'accent' | 'success' | 'warning' | 'danger' | 'info'

const SIZE: Record<FigureSize, string> = {
  body: 'text-t-body',
  figure: 'text-t-figure',
  hero: 'text-t-hero',
}

const TONE: Record<FigureTone, string> = {
  ink: 'text-ink',
  muted: 'text-ink-muted',
  faint: 'text-ink-faint',
  accent: 'text-accent',
  success: 'text-success',
  warning: 'text-warning',
  danger: 'text-danger',
  info: 'text-info',
}

export function Figure({
  value,
  unit,
  size = 'body',
  tone = 'ink',
  className = '',
}: {
  /** The served number, already formatted (lib/format owns the formatting, this owns the voice). */
  value: ReactNode
  /** `d.`, `t`, `kn`, `days`. Rides small and dim; never inside the value. */
  unit?: ReactNode
  size?: FigureSize
  tone?: FigureTone
  className?: string
}) {
  return (
    <span className={`inline-flex items-baseline gap-1 whitespace-nowrap ${className}`}>
      <span className={`tabular-nums ${SIZE[size]} ${TONE[tone]}`}>{value}</span>
      {unit !== undefined && <span className="text-t-caption text-ink-faint">{unit}</span>}
    </span>
  )
}

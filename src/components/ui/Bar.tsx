import type { ReactNode } from 'react'

// ONE BAR — a proportion, drawn.
//
// This game had THREE spellings of "a bar" and two more of "a bar made of pips": `Meter` (a track
// and a tonal fill), `Gauge` (countable segments with a unit), the Market's `stockBar` text glyphs
// (`▓▓▓░░░` — typewriter art in a game that draws 96 hand-made SVG marks), `DangerMark` and
// `EnduranceBar`. docs/UI_DIRECTION.md §5 folds all of them into this one, and §4.5 bans the text
// glyphs outright.
//
// THE TWO FORMS ARE ONE PRIMITIVE, because they answer the same question at two resolutions:
//   · CONTINUOUS (`pct`)          — how full, as a fraction. Hull condition, hold fullness.
//   · SEGMENTED  (`of` + `value`) — how many, as things you can count. Danger pips, tries left,
//                                   stock in tenths. A player can count six boxes; nobody can
//                                   count 62% of a line.
// A caller passes one or the other. Passing `of` is what selects the segmented form.
//
// 4px TALL, per §4.3 — a hairline with a job, not a widget. It carries no border and no radius
// beyond the pill it already is, and it is separated from what is around it by tone, never by a box.
//
// THE TONE IS THE MEANING, and §4.4's rule holds here more tightly than anywhere else in the game:
// green-red on a bar ONLY ever mean cheap-dear or gain-loss. A bar that is merely *low* is
// `warning`; a bar that is merely *there* is `neutral`. The default is `accent` because the
// commonest bar in this game is one of yours.
//
// IT IS NOT THE TREND LINE. `Sparkline` draws a price's memory and stays its own component
// (index.ts keeps it); §5 names it `Bar.trend` as an eventual home, and the fold waits for the
// screen that needs both in one place.

export type BarTone = 'accent' | 'success' | 'warning' | 'danger' | 'info' | 'neutral'

const FILL: Record<BarTone, string> = {
  accent: 'bg-accent',
  success: 'bg-success',
  warning: 'bg-warning',
  danger: 'bg-danger',
  info: 'bg-info',
  neutral: 'bg-ink-faint',
}

export function Bar({
  pct,
  value,
  of,
  tone = 'accent',
  figure,
  label,
  className = '',
}: {
  /** CONTINUOUS form: 0–100, clamped. Ignored when `of` is given. */
  pct?: number
  /** SEGMENTED form: how many segments are filled. */
  value?: number
  /** SEGMENTED form: how many segments there are. Its presence chooses the form. */
  of?: number
  tone?: BarTone
  /** The trailing read — normally a `<Figure size="body">`. Sits after the bar, never inside it. */
  figure?: ReactNode
  /** Names the proportion for assistive tech ("hull"). Not painted; the caller's label is. */
  label?: string
  className?: string
}) {
  const segmented = typeof of === 'number' && of > 0
  const filled = Math.max(0, Math.min(of ?? 0, Math.round(value ?? 0)))
  const clamped = segmented
    ? (filled / (of as number)) * 100
    : Math.max(0, Math.min(100, pct ?? 0))

  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <div
        role="meter"
        aria-label={label}
        aria-valuenow={segmented ? filled : Math.round(clamped)}
        aria-valuemin={0}
        aria-valuemax={segmented ? (of as number) : 100}
        className="flex h-1 min-w-0 flex-1 items-stretch gap-0.5 overflow-hidden rounded-chip"
      >
        {segmented ? (
          Array.from({ length: of as number }, (_, i) => (
            <span
              key={i}
              className={`h-full flex-1 rounded-chip ${i < filled ? FILL[tone] : 'bg-surface-2'}`}
            />
          ))
        ) : (
          <span className="h-full w-full rounded-chip bg-surface-2">
            <span
              className={`block h-full rounded-chip transition-[width] ${FILL[tone]}`}
              style={{ width: `${clamped}%` }}
            />
          </span>
        )}
      </div>
      {figure !== undefined && <span className="shrink-0">{figure}</span>}
    </div>
  )
}

import type { ReactNode } from 'react'
import { Counter } from './Counter'
import { Figure, type FigureSize, type FigureTone } from './Figure'
import { Sparkline, type SparkTone } from './Sparkline'

// THE STAT CELL — a label, the one figure it is about, and (where it helps) the move and the line.
//
// WHAT IT FOLDS. The Stats tab's five faces had written this by hand FOURTEEN times —
//     <div className="min-w-0">
//       <span className="block text-t-caption text-ink-faint">Laps closed, 24 h</span>
//       <Figure value={formatInt(v.laps_day)} size="figure" />
//     </div>
// — twice as a local `Head` component (Overview.tsx, Cities.tsx) and ten times inline (Merchants,
// Me, the city's detail). That is the shape docs/NO_SPAGHETTI.md §2 is about: not wrong anywhere,
// and already drifting in which of them printed a second line.
//
// IT IS THE DASHBOARD TILE, and it is deliberately not `Tile`: a `Tile` is SELECTABLE — a surface
// with states, something a player presses to choose it. A figure on a sheet is none of that, and
// §4.3 forbids a surface inside a surface, so this carries no box, no border and no background. It
// is type, a figure, and at most two quiet marks under it.
//
// WHICH SIZE. §4.1's three: `body` (16) for a figure in a grid of several, `figure` (24) for the one
// figure a block is about, `hero` (34) for the headline of a face. The rule the Stats tab follows,
// and the reason it is written here: MONEY IN THIS WORLD RUNS TO NINE DIGITS (the cities held 988 M
// on 2026-10-20), and "988,000,000 🪙" at 24px is 200px wide in a 171px column on a 390px glass —
// it would push the sheet sideways. So a row of cells that can hold world-scale money is drawn at
// `body`, counts and percentages at `figure`, and each face keeps ONE `hero`. The game has one
// spelling for money (`formatDucats`, with its coin) and this does not invent a second, shortened
// one for a narrow column.
//
// THE FIGURE COUNTS by default (Counter.tsx): a served number that changed walks to its new value,
// which is the owner's request 188 — *"no number moving around"*. `value` is therefore a NUMBER;
// a reading that is not one (a locked city's purse, a price no city sells) is passed as `text`,
// which prints a plain `Figure` and never animates towards nothing.

export function StatCell({
  label,
  value,
  format,
  text,
  unit,
  size = 'figure',
  tone = 'ink',
  delta,
  trend,
  trendTone = 'even',
  trendBeside = false,
  inline = false,
  children,
  className = '',
  ...rest
}: {
  /** What this figure is, in the caption voice. Sentence case, no colon. */
  label: ReactNode
  /** The served number — it counts to its new value. Omit it and pass `text`. */
  value?: number
  /** How the number reads at every step (lib/format owns the spelling). Required with `value`. */
  format?: (v: number) => string
  /** The reading when it is not a number at all ("—", "locked"). Never animates. */
  text?: string
  unit?: string
  size?: FigureSize
  tone?: FigureTone
  /** The move, already formatted and signed, under the figure — with the tone it means. */
  delta?: { text: string; tone: FigureTone }
  /** Where it has been: the newest readings, oldest first. Under 2 and nothing is drawn. */
  trend?: readonly number[]
  trendTone?: SparkTone
  /** THE LINE STANDS BESIDE THE FIGURE (unfold slice, 2026-11-01: *"compact showing everything possible"*)
   *  instead of under it: the cell stays two lines tall (label, then figure and line) rather than three.
   *  The line takes what the figure leaves; where the figure leaves none it drops under it. */
  trendBeside?: boolean
  /** THE LABEL STANDS BEFORE ITS FIGURE ON ONE LINE (unfold slice, 2026-11-02; owner row 258/260: *"label and
   *  figure close … compact with full detail"*) — a pair that wraps with its neighbours inside a
   *  `flex flex-wrap`, 24 px a line, instead of a cell 40 px tall. For a block of several short figures; a
   *  figure that carries a line or a delta keeps the stacked form. */
  inline?: boolean
  /** A `Bar`, a share, a second caption — whatever this one figure needs and no more. */
  children?: ReactNode
  className?: string
} & { 'data-testid'?: string }) {
  const drawn = trend !== undefined && trend.length > 1
  // `text` wins: a caller that has a reading which is NOT a number ("—", "locked") passes it
  // beside the value it would otherwise have counted to.
  const figure =
    text === undefined && value !== undefined && format !== undefined ? (
      <Counter value={value} format={format} unit={unit} size={size} tone={tone} />
    ) : (
      <Figure value={text ?? '—'} unit={unit} size={size} tone={text === undefined ? 'faint' : tone} />
    )
  if (inline) {
    return (
      <div className={`inline-flex min-w-0 items-baseline gap-2 ${className}`} {...rest}>
        <span className="whitespace-nowrap text-t-caption text-ink-faint">{label}</span>
        {figure}
      </div>
    )
  }
  return (
    <div className={`min-w-0 ${className}`} {...rest}>
      <span className="block text-t-caption text-ink-faint">{label}</span>
      {drawn && trendBeside ? (
        <span className="flex flex-wrap items-center gap-x-2">
          {figure}
          <Sparkline values={trend} tone={trendTone} width={96} height={20} className="min-w-8 flex-1 lg:h-7" />
        </span>
      ) : (
        figure
      )}
      {delta !== undefined && (
        <span className="block">
          <Figure value={delta.text} tone={delta.tone} />
        </span>
      )}
      {drawn && !trendBeside && <Sparkline values={trend} tone={trendTone} width={96} height={20} className="mt-1 w-full" />}
      {children}
    </div>
  )
}

/** A RUN OF INLINE PAIRS — `StatCell inline`s that wrap like words, 24 px a line, with 16 px between pairs.
 *  The one place that line is spelled: the live band, the economy watch, the day's flows, the market's day
 *  and the week all stand on it (five callers, 2026-11-02). */
export function StatRun({
  className = '',
  children,
  ...rest
}: {
  className?: string
  children: ReactNode
} & { 'data-testid'?: string }) {
  return (
    <div className={`flex flex-wrap items-baseline gap-x-4 gap-y-0 ${className}`} {...rest}>
      {children}
    </div>
  )
}

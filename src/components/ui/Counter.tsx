import { useEffect, useRef, useState } from 'react'
import { Figure, type FigureSize, type FigureTone } from './Figure'
import { COUNT_UP_MS, countUpValue } from './countUp'

// THE COUNTER — a `Figure` that WALKS to its new value (countUp.ts says why, and for whom).
//
// It is a Figure in every other respect: the same three sizes, the same tones, the same unit riding
// small beside it, the same tabular lining — which is what keeps the walk legible, because with
// tabular figures the digits do not shuffle sideways while they move.
//
// THE CALLER STILL OWNS THE FORMATTING (lib/format): this takes the NUMBER and the formatter, and
// formats every step with it, so a counting purse reads "4,180 🪙 … 6,920 🪙 … 40,000 🪙" in the
// game's own spelling rather than in a raw digit run.
//
// A PLAYER WHO ASKED FOR LESS MOTION GETS NONE. `prefers-reduced-motion: reduce` sets the figure at
// once (§4.6: reduced motion collapses all of it to zero). Read through `matchMedia` at the moment
// of the change rather than cached, so a player who changes the setting is obeyed without a reload.
//
// IT DOES NOT ANNOUNCE EVERY STEP. The span carries no `aria-live`: a counter that read out twenty
// intermediate numbers would make the figure less accessible, not more. The settled value is in the
// DOM, where a screen reader finds it.

/** True when the player has asked for less motion — or when there is no `matchMedia` to ask. */
function still(): boolean {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return true
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

/** The value on screen: `to` on the first paint, and a walk towards it on every change after.
 *  Private to this file — the react-refresh rule keeps hooks out of component modules' exports, and
 *  nothing outside wants the number without the figure around it. */
function useCountUp(to: number): number {
  const [shown, setShown] = useState(to)
  // What is on the screen right now, so a value that changes mid-walk continues from there instead
  // of jumping back to the one before it.
  const at = useRef(to)

  useEffect(() => {
    if (at.current === to) return
    if (!Number.isFinite(to) || !Number.isFinite(at.current) || still()) {
      at.current = to
      setShown(to)
      return
    }
    const from = at.current
    const started = performance.now()
    let frame = 0
    const step = (now: number) => {
      const p = (now - started) / COUNT_UP_MS
      const v = countUpValue(from, to, p)
      at.current = v
      setShown(v)
      if (p < 1) frame = requestAnimationFrame(step)
    }
    frame = requestAnimationFrame(step)
    return () => cancelAnimationFrame(frame)
  }, [to])

  return shown
}

export function Counter({
  value,
  format,
  unit,
  size = 'figure',
  tone = 'ink',
  className = '',
  ...rest
}: {
  /** The served number. Not a string: this one counts. */
  value: number
  /** How it reads at every step — `formatDucats`, `formatInt`, `formatPctChange`. */
  format: (v: number) => string
  unit?: string
  size?: FigureSize
  tone?: FigureTone
  className?: string
} & { 'data-testid'?: string }) {
  const shown = useCountUp(value)
  return (
    <span {...rest}>
      <Figure value={format(shown)} unit={unit} size={size} tone={tone} className={className} />
    </span>
  )
}

import type { CSSProperties } from 'react'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LOADING METER — a screen's REAL progress, as a percentage (owner, 2026-10-31)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"when reloading, for example opening the city, or loading the map, show percentage of its
// loading time"* — and the number must be MEASURED WORK, never a timed animation: the caller hands
// in the screen's ordered list of REAL steps (the resources it actually reads — the world bundle
// and snapshot, the beat read, the screen's own served reads), each with `done` set at the instant
// its completion event fired. The percentage is completed steps / total steps, weighted by each
// step's measured size where the caller knows one (`weight`; a step without a size counts equally
// with the rest). Nothing here invents a number: there is no timer, no easing, no interval.
//
// IT UPDATES ON STEP COMPLETION ONLY — the props are the only input, so React re-renders this
// component at most once per step, and it unmounts (returns null) the instant every step is done:
// the meter is gone at ready.
//
// ONE COMPONENT FOR EVERY SCREEN. Map composes the same list with its own steps; the city hands
// in World · Sea · Fleets · Hall (worldStore's `boot`, then the hall's served read).

export interface LoadStep {
  /** Stable id (the run's own key; also read by the specs via `data-load-step`). */
  id: string
  /** The step's name in 1-2 plain words, EN+KO through the caller's dict. */
  label: string
  /** Set at the instant the step's completion event fired — never earlier. */
  done: boolean
  /** The step's measured size, when the caller has one (bytes served). Absent: equal weight. */
  weight?: number
}

/** The completed share of the list, 0-100, rounded to a whole percent. Private: the component is
 *  the surface a screen gets (react-refresh keeps a component file component-only). */
function loadPercent(steps: readonly LoadStep[]): number {
  const total = steps.reduce((n, s) => n + (s.weight !== undefined && s.weight > 0 ? s.weight : 1), 0)
  if (total === 0) return 0
  const done = steps.reduce((n, s) => n + (s.done ? (s.weight !== undefined && s.weight > 0 ? s.weight : 1) : 0), 0)
  return Math.round((done / total) * 100)
}

export function LoadMeter({
  steps,
  className = '',
  ...rest
}: {
  steps: readonly LoadStep[]
  className?: string
} & { 'data-testid'?: string }) {
  const current = steps.find((s) => !s.done)
  // GONE AT READY: every step complete means the screen is about to be whole.
  if (current === undefined || steps.length === 0) return null
  const pct = loadPercent(steps)
  return (
    <div
      role="status"
      aria-live="polite"
      data-load-pct={pct}
      data-load-step={current.id}
      className={`flex flex-col gap-1 py-1 ${className}`}
      {...rest}
    >
      <div className="flex items-baseline justify-between gap-2">
        <span className="truncate text-t-caption text-ink-muted">{current.label}</span>
        <span className="shrink-0 text-t-caption tabular-nums text-ink">{pct} %</span>
      </div>
      <div className="h-0.5 w-full overflow-hidden rounded-chip bg-surface-2">
        <div className="h-full bg-accent transition-[width] duration-150" style={{ width: `${pct}%` } as CSSProperties} />
      </div>
    </div>
  )
}

import type { ReactNode } from 'react'

// THE RING — a level or a goal you can feel fill, drawn around its mark (the visual overhaul's principle 5, RuneScape / Melvor).
//
// A Bar is a proportion along a line; a Ring is the same proportion around a mark, for a thing whose LEVEL is the point of it (a
// captain's two levels that matter, slice 6). The track is the inset tone, the fill is lit toward its leading end like the bar's,
// and the centre holds the caller's mark. Pure: the caller hands the served proportion and the accessible name; nothing is worked
// out here but the arc's length.

export type RingTone = 'accent' | 'muted'

const FILL: Record<RingTone, string> = {
  accent: 'var(--color-accent)',
  muted: 'var(--color-ink-faint)',
}

export function Ring({
  pct,
  size = 36,
  tone = 'accent',
  label,
  children,
  className = '',
  ...rest
}: {
  /** 0-100, the served proportion (clamped). */
  pct: number
  size?: number
  tone?: RingTone
  /** What the ring says to a screen reader: the thing, its level, how far to the next. */
  label: string
  /** The mark in the middle. */
  children?: ReactNode
  className?: string
} & { 'data-testid'?: string; 'data-level'?: number; 'data-track'?: string }) {
  const stroke = 3
  const r = (size - stroke) / 2
  const c = 2 * Math.PI * r
  const p = Math.max(0, Math.min(100, Number.isFinite(pct) ? pct : 0))
  return (
    <span
      role="img"
      aria-label={label}
      className={`relative inline-flex shrink-0 items-center justify-center ${className}`}
      style={{ width: size, height: size }}
      {...rest}
    >
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true" className="absolute inset-0 -rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--color-surface-2)" strokeWidth={stroke} />
        {p > 0 && (
          <circle
            cx={size / 2}
            cy={size / 2}
            r={r}
            fill="none"
            stroke={FILL[tone]}
            strokeWidth={stroke}
            strokeLinecap="round"
            strokeDasharray={`${(p / 100) * c} ${c}`}
          />
        )}
      </svg>
      <span className="relative flex items-center justify-center" aria-hidden="true">
        {children}
      </span>
    </span>
  )
}

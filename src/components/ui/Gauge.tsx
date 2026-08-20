// THE QUANTISED GAUGE — a resource drawn as countable segments, not as a smooth bar.
//
// EVE draws its capacitor as fragments rather than a percentage (one per 50 GJ, capped at 18), and
// the reason is the one that matters on a phone: a player can COUNT segments at a glance and reason
// "four blocks left, that is 40 tuns" — where a smooth bar forces mental arithmetic against a
// denominator that is not on screen. This game already had the idea in one place, as the Market's
// six-cell `stockBar` drawn in text; this is that idea as a primitive the whole app can use.
//
// WHERE IT DIFFERS FROM `Meter`. Meter is the CONTINUOUS bar — voyage progress, a fraction of a
// journey, something with no natural unit. Gauge is for a resource with a COUNTABLE unit: tuns of
// hold, days of stores, berths of crew. If you cannot say what one segment is worth, use Meter.
//
// THE PARTIAL SEGMENT IS SHADED, NOT ROUNDED UP. A hold with a sliver free must not read as a hold
// with a whole block free; the Market's stock meter shades for the same reason a shortage should
// not look like a stock.

export type GaugeTone = 'accent' | 'success' | 'warning' | 'danger' | 'neutral'

const FILL: Record<GaugeTone, string> = {
  accent: 'bg-accent',
  success: 'bg-success',
  warning: 'bg-warning',
  danger: 'bg-danger',
  neutral: 'bg-ink-faint/50',
}

export function Gauge({
  value,
  max,
  segments = 8,
  tone = 'accent',
  className = '',
  label,
}: {
  value: number
  max: number
  /** How many countable blocks the whole makes. Keep it small enough to count without counting. */
  segments?: number
  tone?: GaugeTone
  className?: string
  /** Announced to assistive tech, which cannot see blocks ("hold, 34 of 56 tuns"). */
  label?: string
}) {
  const frac = max > 0 ? Math.max(0, Math.min(1, value / max)) : 0
  const exact = frac * segments
  const full = Math.floor(exact)
  const partial = exact - full

  return (
    <span
      className={`inline-flex gap-[2px] ${className}`}
      role="img"
      aria-label={label ?? `${value} of ${max}`}
    >
      {Array.from({ length: segments }, (_, i) => (
        <span
          key={i}
          className={`h-2.5 w-1.5 rounded-[1px] ${
            i < full
              ? FILL[tone]
              : i === full && partial > 0
                ? `${FILL[tone]} opacity-40`
                : 'bg-surface-2'
          }`}
        />
      ))}
    </span>
  )
}

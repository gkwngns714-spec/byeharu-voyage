import { useMemo } from 'react'
import { useT } from '../../lib/i18n'

// THE CITY'S PICTURE — the panel's City Info image: a simple drawn skyline over water that changes
// colour with the hour (night blue-violet → day gold), and the city's people as DOTS along the quay.
//
// WHAT IS REAL AND WHAT IS NOT (the shell slice, 2026-10-30). The hour is the served clock's, so
// day/night is true for every player at once. The skyline is a drawing. The DOTS are sized by the
// city's SERVED `size_tier` (1–5), the only served figure about how big a city is — this world does
// not count people yet (`live/CityInfo.tsx` says the same), and the summary's Population figure is
// honestly a placeholder, so the dots carry no number and claim none.
//
// Tokens only: `fill-info`/`fill-accent` are the game's own inks, never a palette literal.

/** 1 dot = people. The count follows the served size tier, and never a made-up population. */
function dotCount(sizeTier: number): number {
  return 6 + Math.max(1, Math.min(5, sizeTier || 1)) * 6
}

/** A deterministic scatter — same city, same dots on every render and every machine. */
function dotAt(i: number, total: number): { x: number; y: number } {
  const row = i % 3
  const col = Math.floor(i / 3)
  const across = Math.max(1, Math.ceil(total / 3))
  const wobble = Math.sin(i * 12.9898) * 4
  return { x: 16 + (col + 0.5) * (368 / across) + wobble, y: 132 + row * 7 + Math.cos(i * 7.7) * 1.5 }
}

export function CityScene({
  sizeTier,
  night,
  className = '',
}: {
  sizeTier: number
  night: boolean
  className?: string
}) {
  const t = useT()
  const dots = useMemo(() => {
    const total = dotCount(sizeTier)
    return Array.from({ length: total }, (_, i) => dotAt(i, total))
  }, [sizeTier])

  return (
    <svg
      viewBox="0 0 400 160"
      preserveAspectRatio="xMidYMid slice"
      role="img"
      aria-label={`${t('city.title')} · ${night ? t('city.night') : t('city.day')}`}
      data-testid="city-scene"
      data-phase={night ? 'night' : 'day'}
      className={`h-full w-full rounded-tile ${className}`}
    >
      {/* THE SKY — violet-blue at night, warm gold by day. */}
      <rect className={night ? 'fill-info' : 'fill-accent'} opacity={night ? 0.22 : 0.18} width="400" height="160" />
      {/* the sun, or the moon and its stars */}
      {night ? (
        <>
          <circle className="fill-accent" opacity="0.85" cx="322" cy="30" r="12" />
          <circle className="fill-info" cx="328" cy="25" r="11" />
          {[24, 58, 96, 132, 208, 262, 300].map((x, i) => (
            <circle key={x} className="fill-ink-faint" opacity={0.55 + (i % 3) * 0.12} cx={x} cy={18 + (i % 4) * 9} r="1.1" />
          ))}
        </>
      ) : (
        <>
          <circle className="fill-accent" opacity="0.9" cx="322" cy="30" r="13" />
          {[...Array(8)].map((_, i) => (
            <line key={i} className="stroke-accent" strokeWidth="1.4" opacity="0.7" x1={322 + Math.cos((i * Math.PI) / 4) * 18} y1={30 + Math.sin((i * Math.PI) / 4) * 18} x2={322 + Math.cos((i * Math.PI) / 4) * 24} y2={30 + Math.sin((i * Math.PI) / 4) * 24} />
          ))}
        </>
      )}

      {/* THE SKYLINE — six simple buildings, one for each building on the page. */}
      <g className="fill-surface-2" stroke="currentColor" strokeWidth="1">
        <rect className="stroke-edge" x="26" y="82" width="42" height="46" />
        <rect className="stroke-edge" x="74" y="62" width="30" height="66" />
        <polygon className="stroke-edge" points="108,128 130,84 152,128" />
        <rect className="stroke-edge" x="160" y="72" width="48" height="56" />
        <rect className="stroke-edge" x="216" y="92" width="34" height="36" />
        <rect className="stroke-edge" x="258" y="56" width="26" height="72" />
        <polyline className="stroke-edge fill-none" points="284,128 300,96 316,128" />
        <rect className="stroke-edge" x="322" y="86" width="46" height="42" />
      </g>
      {/* windows: lit at night, quiet by day */}
      <g className={night ? 'fill-warning' : 'fill-ink-faint'} opacity={night ? 0.9 : 0.5}>
        {[36, 50, 82, 94, 170, 184, 230, 268, 334, 348].map((x, i) => (
          <rect key={x} x={x} y={92 + (i % 3) * 10} width="5" height="6" />
        ))}
      </g>

      {/* THE WATER */}
      <rect className="fill-bg" opacity="0.55" y="128" width="400" height="32" />
      <g className="stroke-ink-faint" strokeWidth="1" opacity="0.35">
        <line x1="0" y1="136" x2="400" y2="136" />
        <line x1="0" y1="144" x2="400" y2="144" />
      </g>

      {/* THE PEOPLE — one dot for the city's size tier, along the quay. */}
      <g className={night ? 'fill-accent' : 'fill-ink'} opacity="0.8" data-testid="city-dots">
        {dots.map((d, i) => (
          <circle key={i} cx={d.x} cy={d.y} r="1.5" />
        ))}
      </g>
    </svg>
  )
}

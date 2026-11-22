import { useId } from 'react'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LAND SITE, DRAWN (2026-11-23, the visual overhaul's slice 10; principle 7: "HQ, a harbour's tray, the yard and the Land site
// each get one picture: a drawn SVG scene in the night-sea palette, no bitmaps, no new dependency").
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The Party face was a form: label-value rows and a thin bar. Now it opens on the place: the home town at the left, the mountains
// at the right with the mine's mouth lit at their foot, the road between them, and the party ON that road, as far along as the
// served trip says (`at`, the same fill the trip bar draws, `u / trip` of world.land). A far land (the job's `home` false) has the
// sea in the middle of the road: the passage. A make job (the smith, 0461) works at home: the party stands in the town.
//
// Pure props, like `Skyline`: the caller hands what the served read says and this draws it; nothing is worked out here but where on
// the road a fraction falls. Decoration (`aria-hidden`): the rows under it say where the party is and how long it has.

const W = 320
const H = 96
const G = 80

/** The road: a quadratic curve from the town's gate to the mine's mouth. */
const ROAD = { x0: 58, y0: 82, cx: 150, cy: 62, x1: 244, y1: 76 } as const

function along(t: number): { x: number; y: number } {
  const u = Math.max(0, Math.min(1, t))
  const a = (1 - u) * (1 - u)
  const b = 2 * (1 - u) * u
  const c = u * u
  return { x: a * ROAD.x0 + b * ROAD.cx + c * ROAD.x1, y: a * ROAD.y0 + b * ROAD.cy + c * ROAD.y1 }
}

export function LandSite({
  at,
  out,
  far,
  make,
  className = '',
}: {
  /** How far along the trip the party is, 0-100 (the trip bar's own fill). */
  at: number
  /** The party is out on a job (else it rests in the town). */
  out: boolean
  /** The job is on a far land: the sea lies across the road. */
  far: boolean
  /** A make job (the smith): worked at home. */
  make: boolean
  className?: string
}) {
  const id = useId().replace(/:/g, '')
  const home = !out || make
  const p = home ? { x: 40, y: 76 } : along(at / 100)
  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="xMidYMax slice"
      width="100%"
      height={H}
      aria-hidden="true"
      className={`block ${className}`}
      data-testid="land-site"
      data-at={Math.round(at)}
      data-far={far ? 'true' : 'false'}
      data-home={home ? 'true' : 'false'}
    >
      <defs>
        <linearGradient id={`${id}-sky`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="var(--color-surface-2)" />
          <stop offset="0.8" stopColor="color-mix(in srgb, var(--color-accent) 20%, var(--color-surface-2))" />
        </linearGradient>
        <linearGradient id={`${id}-sea`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="color-mix(in srgb, var(--color-chart-sea) 80%, var(--color-accent))" />
          <stop offset="1" stopColor="var(--color-chart-sea)" />
        </linearGradient>
      </defs>
      <rect x="0" y="0" width={W} height={H} fill={`url(#${id}-sky)`} />
      <circle cx={W * 0.2} cy={14} r={1.4} fill="var(--color-accent)" fillOpacity={0.8} />
      {/* the far ridge */}
      <path
        d={`M0 ${G - 18}L40 ${G - 34}L72 ${G - 22}L118 ${G - 44}L160 ${G - 26}L204 ${G - 52}L250 ${G - 30}L290 ${G - 46}L${W} ${G - 30}V${G}H0Z`}
        fill="var(--color-ink-faint)"
        fillOpacity={0.18}
      />
      {/* the mountains of the site, a snow line on the peak */}
      <path d={`M150 ${G}L196 ${G - 40}L214 ${G - 30}L250 ${G - 66}L286 ${G - 34}L302 ${G - 44}L${W} ${G - 30}V${G}Z`} fill="var(--color-bg)" />
      <path d={`M240 ${G - 47}L250 ${G - 66}L262 ${G - 49}L256 ${G - 52}L250 ${G - 47}L245 ${G - 51}Z`} fill="var(--color-ink-faint)" fillOpacity={0.55} />
      {/* the mine's mouth at their foot, its lamp lit */}
      <path d={`M236 ${G}V${G - 8}A8 8 0 0 1 252 ${G - 8}V${G}Z`} fill="var(--color-surface)" stroke="var(--color-accent)" strokeOpacity={0.55} strokeWidth={1} />
      <circle cx={256} cy={G - 13} r={1.6} fill="var(--color-accent)" />
      {/* the ground */}
      <rect x="0" y={G} width={W} height={H - G} fill="var(--color-bg)" />
      {/* the home town: a church, a hall, three houses */}
      <g fill="var(--color-bg)">
        <path d={`M8 ${G}V${G - 12}L15 ${G - 18}L22 ${G - 12}V${G}Z`} />
        <path d={`M22 ${G}V${G - 22}L26 ${G - 32}L30 ${G - 22}V${G}Z`} />
        <path d={`M30 ${G}V${G - 10}H46V${G}Z`} />
        <path d={`M44 ${G}V${G - 14}L51 ${G - 20}L58 ${G - 14}V${G}Z`} />
      </g>
      <g fill="var(--color-accent)" fillOpacity={0.7}>
        <rect x="13" y={G - 8} width="2" height="2" />
        <rect x="35" y={G - 6} width="2" height="2" />
        <rect x="50" y={G - 9} width="2" height="2" />
      </g>
      {/* the road from the town's gate to the mine */}
      <path
        d={`M${ROAD.x0} ${ROAD.y0}Q${ROAD.cx} ${ROAD.cy} ${ROAD.x1} ${ROAD.y1}`}
        fill="none"
        stroke="var(--color-ink-faint)"
        strokeOpacity={0.6}
        strokeWidth={1.2}
        strokeDasharray="3 3"
      />
      {/* a far land: the sea across the road, the passage */}
      {far && (
        <g data-testid="land-site-sea">
          <rect x="112" y={G - 14} width="64" height={H - G + 14} rx="3" fill={`url(#${id}-sea)`} />
          <path d={`M120 ${G - 6}h12M140 ${G - 2}h16M126 ${G + 4}h10M150 ${G + 8}h14`} stroke="var(--color-accent)" strokeOpacity={0.4} strokeLinecap="round" />
        </g>
      )}
      {/* the party: a gold mark on the road, ringed */}
      <g data-testid="land-site-party" transform={`translate(${p.x.toFixed(1)} ${p.y.toFixed(1)})`}>
        <circle r={7} fill="var(--color-accent)" fillOpacity={0.18} />
        <circle r={3.6} fill="var(--color-accent)" stroke="var(--color-bg)" strokeWidth={1} />
      </g>
    </svg>
  )
}

import { useMemo } from 'react'
import { useT } from '../../lib/i18n'

// THE CITY FROM ABOVE — a bird's-eye plan of the harbour town (owner, 2026-10-30: "the city graphic
// should be in bird's eye view"). The page's City Info drawing is now the town LOOKED DOWN ON: the
// sea along the bottom edge, the quay and its two piers, streets between blocks of roofs, and the six
// buildings the page offers standing in their own blocks — the Town Hall with its plaza, the Market's
// stalls, the long quay warehouses (Storage), the Forge with its chimney, the Inn with its courtyard,
// and the Port, which is the quay itself. Fields beyond the north wall.
//
// WHAT IS REAL AND WHAT IS NOT (unchanged from the shell slice). The hour is the served clock's, so
// night is true for every player at once: the town darkens, the streets light their lamps and the
// windows warm. The plan is a drawing, and every city draws the SAME plan from its own NAME — the
// seed gives each harbour a stable, different arrangement (fields, roof heights, a few blocks) while
// one city is identical on every render and every machine. The DOTS are sized by the served
// `size_tier` (1–5) — bigger city, more people in its streets — and claim no count; the summary's
// Population figure is honestly a placeholder (live/CityInfo.tsx says the same).
//
// Tokens only: the game's own inks (fill-info is water, fill-accent is sunlight and lamps,
// fill-surface-2 roofs, stroke-edge streets and outlines) — never a palette literal.

const VIEW_W = 400
const VIEW_H = 170
/** The coast: the waterline across the bottom, a little uneven, with a headland at the east. */
const COAST_Y = 122

/** A small stable hash: the same city name gives the same plan. */
function seedOf(name: string): number {
  let h = 2166136261
  for (let i = 0; i < name.length; i++) {
    h ^= name.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  return h >>> 0
}

function jitter(seed: number, n: number, spread: number): number {
  const x = Math.sin(seed * 0.0001 + n * 12.9898) * 43758.5453
  return ((x - Math.floor(x)) * 2 - 1) * spread
}

/** 1 dot = people. The count follows the served size tier, and never a made-up population. */
function dotCount(sizeTier: number): number {
  return 6 + Math.max(1, Math.min(5, sizeTier || 1)) * 6
}

/** People walk the streets: the quay road and the market square. Deterministic per city. */
function dotAt(i: number, total: number, seed: number): { x: number; y: number } {
  if (i % 3 === 2) {
    // on the market square
    const k = Math.floor(i / 3)
    return { x: 236 + ((k * 37 + jitter(seed, i, 14) + 14) % 50), y: 64 + ((k * 23 + 12) % 22) }
  }
  // along the quay road, and the straight road north from the harbour
  const t = (i + 0.5) / Math.max(1, total)
  const onRoad = i % 3 === 1
  if (onRoad) {
    return { x: 230 + jitter(seed, i, 1.5), y: 28 + t * 82 }
  }
  return { x: 16 + t * 368 + jitter(seed, i, 3), y: 108 + jitter(seed, i + 1, 2.5) }
}

/** The street grid: three roads across the town, five up it, and the quay road along the water. */
const ROADS_H = [26, 62, 96]
const ROADS_V = [34, 98, 164, 230, 296, 362]
/** The blocks a landmark owns — its own roof stands in them, so no block roof is drawn there. */
const LANDMARK_BLOCKS = new Set(['1-0', '2-0', '4-0', '3-1', '0-2', '1-2', '2-2', '3-2', '4-2'])

export function CityScene({
  sizeTier,
  night,
  seed = '',
  className = '',
}: {
  sizeTier: number
  night: boolean
  /** The city's stable name — the same harbour draws the same plan everywhere. */
  seed?: string
  className?: string
}) {
  const t = useT()
  const s = useMemo(() => seedOf(seed), [seed])
  const dots = useMemo(() => {
    const total = dotCount(sizeTier)
    return Array.from({ length: total }, (_, i) => dotAt(i, total, s))
  }, [sizeTier, s])

  // THE BLOCKS: roofs between the roads. Two rows of them behind the quay row; the seed moves a few
  // roofs by a pixel or two, so every harbour plans differently and none of them drifts.
  const blocks: { x: number; y: number; w: number; h: number; key: string }[] = []
  for (let r = 0; r < 2; r++) {
    for (let c = 0; c < ROADS_V.length - 1; c++) {
      const key = `${c}-${r}`
      if (LANDMARK_BLOCKS.has(key)) continue
      const x = ROADS_V[c] + 4 + jitter(s, c * 7 + r, 1.2)
      const y = ROADS_H[r] + 4
      const w = ROADS_V[c + 1] - ROADS_V[c] - 9
      const h = 21 + jitter(s, c * 3 + r * 5, 2)
      blocks.push({ x, y, w, h, key })
    }
  }

  return (
    <svg
      viewBox={`0 0 ${VIEW_W} ${VIEW_H}`}
      preserveAspectRatio="xMidYMid slice"
      role="img"
      aria-label={`${t('city.title')} · ${night ? t('city.night') : t('city.day')}`}
      data-testid="city-scene"
      data-phase={night ? 'night' : 'day'}
      className={`h-full w-full rounded-tile ${className}`}
    >
      {/* THE GROUND — the land, tinted by the hour (warm by day, cold blue at night). */}
      <rect className="fill-bg" width={VIEW_W} height={VIEW_H} />
      <rect className="fill-surface" opacity={night ? 0.55 : 0.8} width={VIEW_W} height={COAST_Y} />
      <rect className={night ? 'fill-info' : 'fill-accent'} opacity={night ? 0.12 : 0.08} width={VIEW_W} height={COAST_Y} />

      {/* THE FIELDS beyond the north wall: furrows, a hedgerow, and a windmill. */}
      <g opacity="0.5">
        <rect className="fill-accent" opacity="0.18" x="6" y="4" width="150" height="16" />
        {[18, 34, 50, 66, 82, 98, 114, 130, 146].map((x) => (
          <line key={x} className="stroke-accent" strokeWidth="0.8" x1={x + jitter(s, x, 1)} y1="5" x2={x} y2="19" />
        ))}
        <rect className="fill-accent" opacity="0.22" x="300" y="4" width="94" height="16" />
        {[318, 342, 366, 390].map((x) => (
          <line key={x} className="stroke-accent" strokeWidth="0.8" x1={x} y1="5" x2={x + jitter(s, x, 1)} y2="19" />
        ))}
      </g>
      {/* the north wall, with its two gates */}
      <line className="stroke-edge" strokeWidth="1.2" x1="0" y1="22" x2={162} y2="22" opacity="0.9" />
      <line className="stroke-edge" strokeWidth="1.2" x1="230" y1="22" x2={VIEW_W} y2="22" opacity="0.9" />
      {[10, 100, 200, 320, 390].map((x) => (
        <rect key={x} className="fill-surface-2 stroke-edge" strokeWidth="0.7" x={x - 2} y="20" width="4" height="4" />
      ))}

      {/* THE STREETS */}
      <g strokeWidth="2.6" opacity="0.5" className="stroke-ink-faint">
        {ROADS_H.map((y) => (
          <line key={`h${y}`} x1="0" y1={y} x2={VIEW_W} y2={y} />
        ))}
        {ROADS_V.map((x) => (
          <line key={`v${x}`} x1={x} y1="22" x2={x} y2={COAST_Y} />
        ))}
      </g>
      <g strokeWidth="1" opacity="0.25" className="stroke-ink-faint">
        {ROADS_H.map((y) => (
          <line key={`hc${y}`} x1="0" y1={y} x2={VIEW_W} y2={y} />
        ))}
      </g>

      {/* THE BLOCKS — roofs, each with its ridge; the seed heights differ per city. */}
      <g data-testid="city-blocks">
        {blocks.map((b) => (
          <g key={b.key}>
            <rect className="fill-surface-2 stroke-edge" strokeWidth="0.9" x={b.x} y={b.y} width={b.w} height={b.h} />
            {/* the ridge, and a lit slope so a roof reads as a roof from above */}
            <line className="stroke-ink-faint" strokeWidth="0.7" opacity="0.45" x1={b.x + 2} y1={b.y + b.h / 2} x2={b.x + b.w - 2} y2={b.y + b.h / 2} />
            <polygon className="fill-ink" opacity="0.06" points={`${b.x + 1},${b.y + 1} ${b.x + b.w - 1},${b.y + 1} ${b.x + b.w - 1},${b.y + b.h / 2 - 1} ${b.x + 1},${b.y + b.h / 2 - 1}`} />
            {/* a garden or two between the houses */}
            {b.key.charCodeAt(0) % 3 === 0 && (
              <circle className="fill-success" opacity="0.35" cx={b.x + b.w - 4} cy={b.y + b.h - 4} r="2.2" />
            )}
          </g>
        ))}
      </g>

      {/* THE TOWN HALL — the page's hall, in its own block: the big roof, the tower, and a plaza. */}
      <g>
        <rect className="fill-surface stroke-edge" strokeWidth="0.9" x="166" y="30" width="46" height="24" />
        <line className="stroke-edge" strokeWidth="0.7" x1="166" y1="42" x2="212" y2="42" />
        <rect className="fill-accent" opacity="0.85" x="186" y="33" width="6" height="6" />
        <circle className="fill-surface-2 stroke-edge" strokeWidth="0.8" cx="170" cy="46" r="4.5" />
        <circle className={night ? 'fill-warning' : 'fill-info'} cx="170" cy="46" r="1.4" opacity="0.9" />
      </g>

      {/* THE MARKET — an open square of stalls beside the avenue. */}
      <g opacity="0.95">
        <rect className="fill-surface-2" opacity="0.55" x="234" y="66" width="56" height="26" />
        {[0, 1, 2].map((cx) =>
          [0, 1].map((cy) => (
            <rect
              key={`st${cx}${cy}`}
              className="fill-accent stroke-edge"
              strokeWidth="0.6"
              opacity="0.75"
              x={238 + cx * 17}
              y={70 + cy * 11}
              width="9"
              height="6"
            />
          )),
        )}
      </g>

      {/* STORAGE — the long warehouses on the quay, where the goods land. */}
      <g>
        {[38, 82, 126].map((x) => (
          <g key={x}>
            <rect className="fill-surface stroke-edge" strokeWidth="0.8" x={x} y="100" width="36" height="13" />
            <line className="stroke-edge" strokeWidth="0.6" x1={x} y1="106.5" x2={x + 36} y2="106.5" opacity="0.7" />
          </g>
        ))}
      </g>

      {/* THE FORGE — its chimney, and the smoke rising over the roofs. */}
      <g>
        <rect className="fill-surface stroke-edge" strokeWidth="0.8" x="106" y="38" width="28" height="18" />
        <rect className="fill-surface-2 stroke-edge" strokeWidth="0.7" x="112" y="31" width="7" height="8" />
        <circle className="fill-ink-faint" opacity={night ? 0.55 : 0.35} cx="115" cy="27" r="2.4" />
        <circle className="fill-ink-faint" opacity={night ? 0.4 : 0.25} cx="118" cy="23" r="1.7" />
        {night && <rect className="fill-warning" opacity="0.85" x="112" y="42" width="5" height="3" />}
      </g>

      {/* THE INN — its courtyard open to the street. */}
      <g>
        <rect className="fill-surface stroke-edge" strokeWidth="0.8" x="302" y="32" width="40" height="22" />
        <rect className="fill-surface-2" x="310" y="37" width="24" height="12" />
        {night && <rect className="fill-warning" opacity="0.85" x="306" y="35" width="4" height="3" />}
      </g>

      {/* THE SEA — the waterline, the quay edge, the two piers and the hulls alongside. */}
      <path
        className={night ? 'fill-info' : 'fill-info'}
        opacity={night ? 0.34 : 0.26}
        d={`M0 ${COAST_Y} C60 ${COAST_Y - 4}, 120 ${COAST_Y + 3}, 190 ${COAST_Y - 1} C250 ${COAST_Y - 5}, 300 ${COAST_Y + 2}, 400 ${COAST_Y - 3} L400 170 L0 170 Z`}
      />
      <g className="stroke-info" strokeWidth="0.7" opacity="0.35">
        {[130, 140, 150, 160].map((y) => (
          <path key={y} d={`M${8 + (y % 20)} ${y} q 12 -2 24 0 q 12 2 24 0 q 12 -2 24 0`} fill="none" />
        ))}
      </g>
      {/* the quay edge */}
      <line className="stroke-edge" strokeWidth="1.6" x1="0" y1={COAST_Y} x2={VIEW_W} y2={COAST_Y} opacity="0.9" />
      {/* piers */}
      <rect className="fill-surface-2 stroke-edge" strokeWidth="0.7" x="120" y={COAST_Y} width="9" height="20" />
      <rect className="fill-surface-2 stroke-edge" strokeWidth="0.7" x="288" y={COAST_Y} width="9" height="26" />
      {/* hulls: the Port building is the quay — ships lie alongside her */}
      <g className="fill-surface stroke-edge" strokeWidth="0.7">
        <path d="M132 128 q 10 -3 20 0 q 2 4 -2 5 l -16 0 q -4 -1 -2 -5 Z" opacity="0.95" />
        <path d="M132 142 q 10 -3 20 0 q 2 4 -2 5 l -16 0 q -4 -1 -2 -5 Z" opacity="0.95" />
        <path d="M300 136 q 10 -3 20 0 q 2 4 -2 5 l -16 0 q -4 -1 -2 -5 Z" opacity="0.95" />
      </g>
      {/* crates on the quay, by the warehouses */}
      <g className="fill-accent" opacity="0.6">
        <rect x="160" y="116" width="5" height="5" />
        <rect x="167" y="117" width="4" height="4" />
        <rect x="256" y="116" width="5" height="5" />
      </g>

      {/* THE LAMPS — lit along the streets at night only. */}
      {night && (
        <g className="fill-warning" opacity="0.9">
          {[60, 120, 180, 240, 300, 350].map((x) => (
            <circle key={`q${x}`} cx={x} cy="110" r="1.3" />
          ))}
          {[40, 140, 210, 330].map((y) => (
            <circle key={`a${y}`} cx="196" cy={30 + (y % 70)} r="1.1" />
          ))}
        </g>
      )}

      {/* THE PEOPLE — dots in the streets, sized by the served tier. */}
      <g className={night ? 'fill-accent' : 'fill-ink'} opacity="0.8" data-testid="city-dots">
        {dots.map((d, i) => (
          <circle key={i} cx={d.x} cy={d.y} r="1.4" />
        ))}
      </g>

      {/* A COMPASS, because a plan is read from a direction. */}
      <g className="stroke-ink-faint fill-ink-faint" opacity="0.55">
        <circle cx="378" cy="34" r="8" fill="none" strokeWidth="0.8" />
        <line x1="378" y1="28" x2="378" y2="40" strokeWidth="0.8" />
        <line x1="372" y1="34" x2="384" y2="34" strokeWidth="0.8" />
        <path d="M378 27 l 2 4 l -2 -1 l -2 1 Z" strokeWidth="0" />
      </g>
    </svg>
  )
}

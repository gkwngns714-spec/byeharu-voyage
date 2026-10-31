import { useMemo } from 'react'
import { useT } from '../../lib/i18n'
import type { CityBuilding } from './CityFace'

// THE CITY, AS A PICTURE — a fine engraved coastal plan seen from above (owner, 2026-10-31:
// "it doesnt have to be attractive, but sophisticated"; before that: "random dots", everything
// "smaller at least 10 times", circular houses, curved roads, "way more dots of population", and
// "these dots are population, it can stop it can go back and forth, random movements, and they
// could be in buildings like houses and more. show a city").
//
// ONE SIDE IS THE SEA. The coast runs the full height of the plate as a precise compound curve; the
// water is a calm tonal mass under a few fine hairlines, never a colour field. Along it the quay
// and the PORT are unmistakable: three piers into the water, moored hulls alongside them, two
// cranes, storehouses and crates on the quay, and the warm lamps that make a harbour read at
// night. Beside it the old town is a field of fine light-on-dark marks: hundreds of tiny circular
// houses, exact ring roads and winding lanes, density falling away from the coast into thinner
// outskirts, with a park and a pond kept as quiet tonal shapes.
//
// THE DOTS ARE PEOPLE. Hundreds of them are scattered through the town, many inside the houses;
// most sit still, some wander short seeded paths, and some walk a line and turn back — never in
// step, each with its own delay, duration and direction. The walkers on the ring roads are the
// served tier's count. The building lights are the brightest thing in the picture: one accent
// colour, warm at night and faint by day. Nothing here is clickable — the six named tiles are the
// only doors (owner: "i dont need to be able to press buildings for building info. it just have to
// be visually attractive").
//
// RESTRAINED, BY CONSTRUCTION. Two grounds (fill-surface land, fill-bg sea), one ink (ink-faint
// for every mark, varied only in opacity), one accent (the lights). No gradients, no glow, no
// palette literal. The whole drawing lives inside the 0..VIEW viewBox and the svg is exactly the
// square frame — `block h-full w-full` inside an `overflow-hidden` square panel — so nothing paints
// outside it (owner: "the map is sticking out of its frame"). Night dims the town as one sheet and
// lets the lights through; every city draws its own picture from its own name.

const VIEW = 240
/** The fine plate border, inset from the panel's edge. */
const PLATE = 4

/** The coast: one precise compound curve, top edge to bottom edge. */
const coastX = (y: number): number => 52 + 9 * Math.sin(0.6 + (y / VIEW) * Math.PI * 2.1)

/** The coast as a polyline sampled every 2 units — the curve is gentle enough to read as one line. */
function coastPath(from: number, to: number): string {
  let d = ''
  for (let y = from; y <= to; y += 2) d += `${d === '' ? 'M' : ' L'}${coastX(y).toFixed(2)} ${y}`
  return d
}

const SEA = `${coastPath(0, VIEW)} L0 ${VIEW} L0 0 Z`
const COAST = coastPath(1, VIEW - 1)

/** The town's plan: three exact ring roads, five winding lanes, one park. */
const CENTRE = { x: 148, y: 120 } as const
const RINGS = [22, 42, 62] as const
const LANES = [
  'M60 74 C 90 86, 100 110, 130 118 S 185 118, 214 96',
  'M64 150 C 96 146, 118 168, 150 172 S 200 168, 222 190',
  'M96 4 C 104 40, 130 60, 150 80 S 190 110, 200 138',
  'M210 4 C 200 40, 170 60, 150 84 S 112 124, 100 160',
  'M80 236 C 96 210, 130 200, 150 192 S 200 180, 220 160',
] as const
const PARK = { x: 196, y: 186, r: 17 } as const
const PARK_TREES = [
  { x: 188, y: 178, r: 1.2 },
  { x: 195, y: 175, r: 1.0 },
  { x: 202, y: 179, r: 1.3 },
  { x: 206, y: 188, r: 1.0 },
  { x: 199, y: 196, r: 1.2 },
  { x: 189, y: 192, r: 1.1 },
  { x: 193, y: 184, r: 0.9 },
  { x: 203, y: 194, r: 0.9 },
] as const

/** The six named places stay as PICTURE marks only (the tiles are the doors). */
const MARKS = [
  { x: 152, y: 112, clear: 8 }, // Town Hall
  { x: 112, y: 152, clear: 7 }, // Market
  { x: 186, y: 122, clear: 7 }, // Forge
  { x: 152, y: 190, clear: 8 }, // Inn
  { x: 66, y: 80, clear: 6 }, // Storage
] as const

/** The port: three piers into the sea, four moored hulls, two cranes, storehouses on the quay. */
const PIERS = [
  { x: 32, y: 90, w: 23, h: 3 },
  { x: 25, y: 122, w: 23, h: 3 },
  { x: 23, y: 152, w: 22, h: 3 },
] as const
const SHIPS = [
  { x: 33, y: 94 },
  { x: 35, y: 101 },
  { x: 26, y: 126 },
  { x: 24, y: 133 },
  { x: 24, y: 156 },
  { x: 20, y: 163 },
] as const
const STORES = [
  { x: 66, y: 80, r: 3.0 },
  { x: 64, y: 108, r: 2.8 },
  { x: 68, y: 164, r: 3.0 },
] as const

/** People walk the ring roads and the winding lanes. Deterministic per city. */
const PEOPLE_TRACKS = [
  'M148 58 a 62 62 0 1 0 0.12 0',
  'M148 98 a 22 22 0 1 1 0.12 0',
  'M64 150 C 96 146, 118 168, 150 172 S 200 168, 222 190',
  'M96 4 C 104 40, 130 60, 150 80 S 190 110, 200 138',
  'M60 74 C 90 86, 100 110, 130 118 S 185 118, 214 96',
] as const

/** A small stable hash: the same city name gives the same picture. */
function seedOf(name: string): number {
  let h = 2166136261
  for (let i = 0; i < name.length; i++) {
    h ^= name.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  return h >>> 0
}

/** A stable 0..1 number from the seed and an index — the one source of every scatter. */
function rand(seed: number, n: number): number {
  const x = Math.sin(seed * 0.0001 + n * 12.9898) * 43758.5453
  return x - Math.floor(x)
}

/** The walkers are people: the count follows the served size tier, and never a made-up population. */
function dotCount(sizeTier: number): number {
  return 6 + Math.max(1, Math.min(5, sizeTier || 1)) * 6
}

type Building = { x: number; y: number; r: number; o: number; ring: boolean }
type Move = { d: string; dur: number; begin: number; back: boolean }
type CrowdDot = { x: number; y: number; r: number; o: number; move: Move | null }
type Lamp = { x: number; y: number; r: number; b: number }

/**
 * THE WHOLE PICTURE'S NUMBERS, drawn once from the seed: the houses (density falling away from
 * the coast), the crowd (still, wandering, turning back), and the lights.
 */
function sceneOf(seed: number): { buildings: Building[]; crowd: CrowdDot[]; lamps: Lamp[] } {
  const buildings: Building[] = []
  for (let i = 0; i < 1600 && buildings.length < 460; i++) {
    const y = 8 + rand(seed, i * 11 + 1) * 224
    const c = coastX(y)
    const t = rand(seed, i * 11 + 2)
    const x = c + 6 + t * (232 - c - 6)
    const near = 1 - t
    if (rand(seed, i * 11 + 3) > 0.16 + 0.82 * near) continue
    if (Math.hypot(x - PARK.x, y - PARK.y) < PARK.r + 2) continue
    let blocked = false
    for (const m of MARKS) {
      if (Math.hypot(x - m.x, y - m.y) < m.clear) {
        blocked = true
        break
      }
    }
    if (blocked) continue
    const r = 0.9 + rand(seed, i * 11 + 4) * (0.9 + 0.8 * near)
    buildings.push({
      x,
      y,
      r,
      o: 0.3 + rand(seed, i * 11 + 5) * 0.35,
      ring: rand(seed, i * 11 + 6) < 0.2,
    })
  }

  const crowd: CrowdDot[] = []
  for (let i = 0; i < 440; i++) {
    const n = 50000 + i * 13
    const home = rand(seed, n + 1)
    let x: number
    let y: number
    if (home < 0.45 && buildings.length > 0) {
      const b = buildings[Math.floor(rand(seed, n + 2) * buildings.length)]
      const a = rand(seed, n + 3) * Math.PI * 2
      const rr = b.r * (0.15 + rand(seed, n + 4) * 0.7)
      x = b.x + Math.cos(a) * rr
      y = b.y + Math.sin(a) * rr
    } else {
      y = 8 + rand(seed, n + 5) * 224
      const c = coastX(y)
      x = c + 4 + rand(seed, n + 6) * (232 - c - 4)
    }
    const r = 0.35 + rand(seed, n + 7) * 0.4
    const o = 0.26 + rand(seed, n + 8) * 0.3
    if (rand(seed, n + 9) >= 0.3) {
      crowd.push({ x, y, r, o, move: null })
      continue
    }
    const a = rand(seed, n + 10) * Math.PI * 2
    const len = 2 + rand(seed, n + 11) * 6
    const dx = Math.cos(a) * len
    const dy = Math.sin(a) * len
    const back = rand(seed, n + 12) < 0.55
    const d = back
      ? `M${x.toFixed(2)} ${y.toFixed(2)} l${dx.toFixed(2)} ${dy.toFixed(2)}`
      : `M${x.toFixed(2)} ${y.toFixed(2)} c ${(dx * 0.5).toFixed(2)} ${(-dy * 0.9).toFixed(2)}, ${(dx * 1.3).toFixed(2)} ${(dy * 0.7).toFixed(2)}, ${dx.toFixed(2)} ${dy.toFixed(2)} c ${(-dx * 0.6).toFixed(2)} ${(dy * 0.8).toFixed(2)}, ${(-dx * 1.2).toFixed(2)} ${(-dy * 0.4).toFixed(2)}, 0 0`
    crowd.push({
      x,
      y,
      r,
      o,
      move: { d, dur: 7 + rand(seed, n + 13) * 12, begin: -rand(seed, n + 14) * 20, back },
    })
  }

  const lamps: Lamp[] = []
  const add = (x: number, y: number, b: number) => {
    lamps.push({ x, y, r: 0.4 + rand(seed, 60000 + lamps.length * 5 + 1) * 0.5, b })
  }
  // the quay's lamps, the pier heads and the crane arms — the port is the lit place
  for (let k = 0; k < 36; k++) {
    const y = 60 + rand(seed, 61000 + k * 7 + 1) * 118
    add(coastX(y) + 1.2 + rand(seed, 61000 + k * 7 + 2) * 4.4, y, 0.55 + rand(seed, 61000 + k * 7 + 3) * 0.45)
  }
  add(47.5, 80, 0.95)
  add(41.5, 136, 0.95)
  add(31, 88, 1)
  add(32.5, 90, 0.85)
  add(25.5, 122, 0.85)
  add(23.5, 152, 0.85)
  // lights on the ring roads, at random angles — never a tidy row
  for (let k = 0; k < 54; k++) {
    const ring = RINGS[k % 3]
    const a = rand(seed, 62000 + k * 7 + 1) * Math.PI * 2
    add(CENTRE.x + Math.cos(a) * ring, CENTRE.y + Math.sin(a) * ring, 0.35 + rand(seed, 62000 + k * 7 + 2) * 0.45)
  }
  // lit windows on the houses
  for (let k = 0; k < 84 && buildings.length > 0; k++) {
    const b = buildings[Math.floor(rand(seed, 63000 + k * 7 + 1) * buildings.length)]
    const a = rand(seed, 63000 + k * 7 + 2) * Math.PI * 2
    add(b.x + Math.cos(a) * b.r * 0.9, b.y + Math.sin(a) * b.r * 0.9, 0.3 + rand(seed, 63000 + k * 7 + 3) * 0.4)
  }
  // a few quiet lamps through the town
  for (let k = 0; k < 30; k++) {
    const y = 8 + rand(seed, 64000 + k * 7 + 1) * 224
    const c = coastX(y)
    add(c + 8 + rand(seed, 64000 + k * 7 + 2) * (230 - c - 8), y, 0.25 + rand(seed, 64000 + k * 7 + 3) * 0.35)
  }
  return { buildings, crowd, lamps }
}

/** A moored hull: a fine outline with one deck line, seen from above. */
function Ship({ x, y }: { x: number; y: number }) {
  return (
    <g>
      <path
        className="fill-surface-2 stroke-ink-faint"
        fillOpacity="0.35"
        strokeWidth="0.45"
        strokeOpacity="0.7"
        d={`M${x} ${y} L${x + 9} ${y} L${x + 11} ${y + 2} L${x + 9} ${y + 4} L${x} ${y + 4} Z`}
      />
      <line className="stroke-ink-faint" strokeWidth="0.3" opacity="0.4" x1={x + 2} y1={y + 2} x2={x + 8.5} y2={y + 2} />
    </g>
  )
}

export function CityScene({
  sizeTier,
  night,
  seed = '',
  className = '',
}: {
  sizeTier: number
  night: boolean
  /** The city's stable name — the same harbour draws the same picture everywhere. */
  seed?: string
  /** Kept for the page's API; the picture itself is not pressable any more — the tiles are the doors. */
  onOpen?: (b: CityBuilding) => void
  className?: string
}) {
  const t = useT()
  const s = useMemo(() => seedOf(seed), [seed])
  const { buildings, crowd, lamps } = useMemo(() => sceneOf(s), [s])
  const people = useMemo(() => Array.from({ length: dotCount(sizeTier) }, (_, i) => i), [sizeTier])
  // Night holds the town down as one sheet; the lights are drawn above it at full glow.
  const dim = night ? 0.62 : 1

  return (
    <svg
      viewBox={`0 0 ${VIEW} ${VIEW}`}
      preserveAspectRatio="xMidYMid slice"
      role="group"
      aria-label={`${t('city.title')} · ${night ? t('city.night') : t('city.day')}`}
      data-testid="city-scene"
      data-phase={night ? 'night' : 'day'}
      className={`block h-full w-full rounded-tile ${className}`}
    >
      {/* THE LAND AND THE SEA — two grounds and one coast line. */}
      <rect className="fill-surface" width={VIEW} height={VIEW} />
      <path className="fill-bg" d={SEA} />
      <g className="stroke-ink-faint" fill="none" strokeWidth="0.35">
        <path d={COAST} transform="translate(-8 0)" opacity="0.14" />
        <path d={COAST} transform="translate(-16 0)" opacity="0.11" />
        <path d={COAST} transform="translate(-24 0)" opacity="0.08" />
        <path d={COAST} transform="translate(-32 0)" opacity="0.05" />
      </g>
      <path className="stroke-ink-faint" fill="none" strokeWidth="0.7" opacity="0.55" d={COAST} />
      <path className="stroke-ink-faint" fill="none" strokeWidth="0.4" opacity="0.3" d={COAST} transform="translate(3.2 0)" />

      <g opacity={dim}>
        {/* THE OLD TOWN — a faint tonal mass under the dense houses by the quay. */}
        <ellipse className="fill-ink-faint" opacity="0.035" cx="130" cy="118" rx="66" ry="70" />

        {/* THE PARK — one quiet tonal shape with its pond and a ring of trees. */}
        <circle className="stroke-ink-faint" fill="none" strokeWidth="0.4" opacity="0.18" cx={PARK.x} cy={PARK.y} r={PARK.r} />
        <circle className="fill-bg" opacity="0.75" cx={PARK.x + 3} cy={PARK.y + 2} r="4.5" />
        <circle className="stroke-ink-faint" fill="none" strokeWidth="0.35" opacity="0.3" cx={PARK.x + 3} cy={PARK.y + 2} r="4.5" />
        {PARK_TREES.map((tr, i) => (
          <circle key={i} className="fill-ink-faint" opacity="0.26" cx={tr.x} cy={tr.y} r={tr.r} />
        ))}

        {/* THE ROADS — three exact rings and five winding lanes, one stroke weight. */}
        {RINGS.map((r) => (
          <circle key={r} className="stroke-ink-faint" fill="none" strokeWidth="0.7" opacity="0.34" cx={CENTRE.x} cy={CENTRE.y} r={r} />
        ))}
        {LANES.map((d, i) => (
          <path key={i} className="stroke-ink-faint" fill="none" strokeWidth="0.6" opacity="0.28" d={d} />
        ))}

        {/* THE HOUSES — hundreds of tiny circular houses, dense by the coast, thinning outward. */}
        {buildings.map((b, i) =>
          b.ring ? (
            <circle key={i} className="stroke-ink-faint" fill="none" strokeWidth="0.35" opacity={b.o} cx={b.x} cy={b.y} r={b.r} />
          ) : (
            <circle key={i} className="fill-ink-faint" opacity={b.o} cx={b.x} cy={b.y} r={b.r} />
          ),
        )}

        {/* THE CROWD — tiny people: most still (many inside the houses), some wandering, some
            walking a short line and turning back, each on its own seeded delay and pace. */}
        <g data-testid="city-crowd" pointerEvents="none" className="fill-ink-faint">
          {crowd.map((c, i) =>
            c.move ? (
              <circle key={i} r={c.r} opacity={c.o}>
                <animateMotion
                  path={c.move.d}
                  dur={`${c.move.dur.toFixed(1)}s`}
                  begin={`${c.move.begin.toFixed(1)}s`}
                  repeatCount="indefinite"
                  {...(c.move.back ? { keyPoints: '0;1;0', keyTimes: '0;0.5;1' } : {})}
                />
              </circle>
            ) : (
              <circle key={i} cx={c.x} cy={c.y} r={c.r} opacity={c.o} />
            ),
          )}
        </g>

        {/* THE SIX NAMED PLACES, AS PICTURE MARKS. Inert by design: the tiles are the only doors. */}
        <g data-testid="city-scene-hall" pointerEvents="none">
          <circle className="stroke-ink-faint" fill="none" strokeWidth="0.6" opacity="0.65" cx="152" cy="112" r="4.8" />
          <circle className="fill-surface-2" opacity="0.45" cx="152" cy="112" r="2.6" />
          <rect className="fill-ink-faint" opacity="0.55" x="150.2" y="104.2" width="3.6" height="5" />
          <line className="stroke-accent" strokeWidth="0.5" opacity="0.9" x1="154.2" y1="105" x2="154.2" y2="102.4" />
          <rect className="fill-accent" opacity="0.9" x="154.4" y="102.1" width="1.7" height="1.2" />
        </g>

        <g data-testid="city-scene-market" pointerEvents="none">
          <circle className="stroke-ink-faint" fill="none" strokeWidth="0.4" opacity="0.3" cx="112" cy="152" r="7.5" />
          {[
            [108, 149],
            [115, 148],
            [110, 154],
            [117, 153],
            [113, 158],
          ].map(([x, y], i) => (
            <circle key={i} className="fill-accent" opacity="0.75" cx={x} cy={y} r="1" />
          ))}
        </g>

        <g data-testid="city-scene-forge" pointerEvents="none">
          <circle className="fill-ink-faint" opacity="0.55" cx="186" cy="122" r="3.6" />
          <circle className="fill-ink-faint" opacity="0.55" cx="188.6" cy="118.4" r="1.7" />
          <rect className="fill-ink-faint" opacity="0.6" x="189.2" y="111.6" width="1.3" height="6.6" />
          <g className="stroke-ink-faint" fill="none" strokeWidth="0.4" opacity="0.3">
            <path d="M191.5 111 c 1.6 -1.2 3 -0.4 3 1.2" />
            <path d="M193.5 107.5 c 1.4 -1 2.6 -0.2 2.6 1.1" />
          </g>
        </g>

        <g data-testid="city-scene-inn" pointerEvents="none">
          <circle className="stroke-ink-faint" fill="none" strokeWidth="0.8" opacity="0.65" cx="152" cy="190" r="4.6" />
          <circle className="fill-surface-2" opacity="0.25" cx="152" cy="190" r="2.2" />
          <circle className="fill-ink-faint" opacity="0.35" cx="152" cy="190" r="0.8" />
        </g>

        <g data-testid="city-scene-storage" pointerEvents="none">
          {STORES.map((st, i) => (
            <g key={i}>
              <circle className="fill-ink-faint" opacity="0.4" cx={st.x} cy={st.y} r={st.r} />
              <circle className="stroke-ink-faint" fill="none" strokeWidth="0.35" opacity="0.35" cx={st.x} cy={st.y} r={st.r} />
              <rect className="fill-ink-faint" opacity="0.5" x={st.x + st.r - 0.7} y={st.y + st.r - 0.7} width="1.8" height="1.8" />
            </g>
          ))}
        </g>

        {/* THE PORT — piers into the water, hulls alongside, two cranes. The clearest shape in town. */}
        <g data-testid="city-scene-port" pointerEvents="none">
          {PIERS.map((p, i) => (
            <rect
              key={i}
              className="fill-ink-faint stroke-ink-faint"
              fillOpacity="0.35"
              strokeOpacity="0.45"
              strokeWidth="0.3"
              x={p.x}
              y={p.y}
              width={p.w}
              height={p.h}
            />
          ))}
          {SHIPS.map((sh, i) => (
            <Ship key={i} x={sh.x} y={sh.y} />
          ))}
          <g className="stroke-ink-faint" fill="none" strokeWidth="0.7" opacity="0.6">
            <path d="M54 86 v-8 h-9 M54 82 l-6 -4" />
            <path d="M48 142 v-8 h-9 M48 138 l-6 -4" />
          </g>
        </g>
      </g>

      {/* THE PLATE'S FINE BORDER — the picture's own frame, inside the panel. */}
      <rect
        className="stroke-ink-faint"
        fill="none"
        strokeWidth="0.4"
        opacity="0.18"
        x={PLATE + 0.5}
        y={PLATE + 0.5}
        width={VIEW - PLATE * 2 - 1}
        height={VIEW - PLATE * 2 - 1}
      />

      {/* THE LIGHTS — the one accent, the brightest thing in the picture. */}
      <g data-testid="city-lights" pointerEvents="none">
        {lamps.map((l, i) => (
          <circle
            key={i}
            className="fill-accent"
            cx={l.x}
            cy={l.y}
            r={l.r}
            opacity={night ? 0.5 + l.b * 0.5 : 0.2 + l.b * 0.28}
          />
        ))}
      </g>

      {/* THE WALKERS — the served tier's count of people on the ring roads and lanes. A dot carries
          NO cx/cy: animateMotion positions it along its path, and a centre would offset it twice. */}
      <g data-testid="city-dots" className="fill-ink-faint" opacity="0.8" pointerEvents="none">
        {people.map((i) => (
          <circle key={i} r="1.2" data-dot={i}>
            <animateMotion
              path={PEOPLE_TRACKS[i % PEOPLE_TRACKS.length]}
              dur={`${13 + (i % 5) * 2.6}s`}
              begin={`${-((i * 1.7) % 11)}s`}
              repeatCount="indefinite"
            />
          </circle>
        ))}
      </g>
    </svg>
  )
}

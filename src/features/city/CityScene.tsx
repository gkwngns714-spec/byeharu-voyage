import { useMemo } from 'react'
import { useT } from '../../lib/i18n'
import type { CityBuilding } from './CityFace'

// THE CITY, LEGIBLE — a coastal town seen from above (owner, 2026-10-31: *"wtf is this city ...
// does this look like a city with citizens?"*, then *"no smaller tiny dots, scale it with
// buildings"*). The picture is built to be read in one second at 200 px:
//
//   · BLOCKS OF BUILDINGS, not a dot field. A curved street network — the quay road, three broad
//     inland streets and three narrower lanes — frames blocks, and each block carries real
//     buildings along its street edges: round towers, long halls and small houses, pale roofs with
//     one consistent thin outline. The six named places are markedly larger: the town hall with
//     its tower and flag, the market square with its stalls, the warehouse rows, the forge with
//     its chimney and smoke, the inn around its courtyard, and the port at the quay.
//   · CITIZENS AT THE BUILDINGS' OWN SCALE. Warm accent dots of r 1.45-1.95 (a small house is
//     r 2.5-3), never pin-pricks, clearly brighter than the window lights. Many walk the street
//     network; the rest gather in clusters at the market, the quay/port and the hall plaza, with a
//     thinner scatter in the outskirts. They are the readable layer; the ~210 window lights stay
//     small and dim as texture.
//   · THE SEA AND THE PORT ON ONE SIDE. The water is a calm tonal mass up the LEFT under one
//     compound curved coast; three piers into it, moored hulls, cranes, crates and the quay lamps
//     make the harbour unmistakable.
//
// Sophistication is kept: two grounds (fill-surface land, fill-bg sea), one ink (fill-ink-faint for
// every building, road, block and outline, varied only by opacity) and one accent (the citizens and
// the lights). No gradients, no glow, no palette literal. Every mark is inside the 0..VIEW viewBox
// and the svg is exactly the square frame (`block h-full w-full` inside an `overflow-hidden`
// square). Nothing on the map is pressable — the six tiles are the only doors. Every arrangement
// is derived from the city's own name (the seed), so a harbour draws the same picture everywhere.

const VIEW = 240
/** The fine plate border, inset from the panel's edge. */
const PLATE = 4

/** The coast: one precise compound curve, top edge to bottom edge. */
const coastX = (y: number): number => 52 + 9 * Math.sin(0.6 + (y / VIEW) * Math.PI * 2.1)

function coastPath(from: number, to: number): string {
  let d = ''
  for (let y = from; y <= to; y += 2) d += `${d === '' ? 'M' : ' L'}${coastX(y).toFixed(2)} ${y}`
  return d
}

const SEA = `${coastPath(0, VIEW)} L0 ${VIEW} L0 0 Z`
const COAST = coastPath(1, VIEW - 1)

type Cubic = readonly [number, number, number, number, number, number, number, number]

/** The street network: the quay road, three broad streets, three narrow lanes. */
const QUAY_ROAD: readonly Cubic[] = [
  [68, 4, 76, 44, 58, 76, 66, 112],
  [66, 112, 74, 148, 60, 196, 66, 236],
]
const STREET_N: readonly Cubic[] = [
  [62, 90, 94, 82, 126, 84, 158, 88],
  [158, 88, 190, 92, 214, 96, 234, 88],
]
const STREET_M: readonly Cubic[] = [
  [62, 134, 94, 140, 126, 132, 158, 134],
  [158, 134, 190, 140, 214, 146, 234, 134],
]
const STREET_S: readonly Cubic[] = [
  [62, 176, 94, 182, 126, 174, 158, 176],
  [158, 176, 190, 182, 214, 188, 234, 176],
]
const LANE_W: readonly Cubic[] = [
  [118, 38, 114, 84, 122, 128, 118, 178],
  [118, 178, 122, 214, 114, 228, 118, 236],
]
const LANE_E: readonly Cubic[] = [
  [160, 38, 156, 84, 164, 128, 160, 178],
  [160, 178, 164, 214, 156, 228, 160, 236],
]
const LANE_F: readonly Cubic[] = [
  [202, 44, 198, 88, 206, 132, 202, 182],
  [202, 182, 206, 214, 198, 228, 202, 232],
]

function pathOf(segs: readonly Cubic[]): string {
  let d = `M${segs[0][0]} ${segs[0][1]}`
  for (const s of segs) d += ` C${s[2]} ${s[3]}, ${s[4]} ${s[5]}, ${s[6]} ${s[7]}`
  return d
}

function cubicAt(s: Cubic, t: number): { x: number; y: number } {
  const u = 1 - t
  const a = u * u * u
  const b = 3 * u * u * t
  const c = 3 * u * t * t
  const d = t * t * t
  return {
    x: a * s[0] + b * s[2] + c * s[4] + d * s[6],
    y: a * s[1] + b * s[3] + c * s[5] + d * s[7],
  }
}

/** A point on a road at t in 0..1, across all its segments. */
function roadPoint(segs: readonly Cubic[], t: number): { x: number; y: number } {
  const k = Math.min(segs.length - 1, Math.floor(t * segs.length))
  return cubicAt(segs[k], Math.min(1, Math.max(0, t * segs.length - k)))
}

const ROADS = [QUAY_ROAD, STREET_N, STREET_M, STREET_S] as const
const LANES = [LANE_W, LANE_E, LANE_F] as const
const ROAD_PATHS = ROADS.map(pathOf)
const LANE_PATHS = LANES.map(pathOf)

/** The blocks between the streets: the six named places and the ordinary town. */
type Kind = 'generic' | 'storage' | 'market' | 'hall' | 'forge' | 'inn'
type Block = { x: number; y: number; w: number; h: number; kind: Kind }
const BLOCKS: readonly Block[] = [
  { x: 76, y: 52, w: 36, h: 30, kind: 'storage' },
  { x: 122, y: 50, w: 34, h: 32, kind: 'generic' },
  { x: 164, y: 52, w: 34, h: 30, kind: 'forge' },
  { x: 206, y: 56, w: 24, h: 26, kind: 'generic' },
  { x: 76, y: 96, w: 36, h: 30, kind: 'generic' },
  { x: 122, y: 94, w: 34, h: 32, kind: 'market' },
  { x: 164, y: 94, w: 34, h: 32, kind: 'hall' },
  { x: 206, y: 98, w: 24, h: 28, kind: 'generic' },
  { x: 76, y: 142, w: 36, h: 28, kind: 'generic' },
  { x: 122, y: 140, w: 34, h: 30, kind: 'generic' },
  { x: 164, y: 142, w: 34, h: 28, kind: 'inn' },
  { x: 206, y: 146, w: 22, h: 24, kind: 'generic' },
  { x: 104, y: 188, w: 28, h: 16, kind: 'generic' },
  { x: 146, y: 190, w: 24, h: 14, kind: 'generic' },
  { x: 186, y: 188, w: 22, h: 16, kind: 'generic' },
]

type Building = {
  kind: 'house' | 'hall' | 'tower'
  x: number
  y: number
  w: number
  h: number
  r: number
  o: number
}

const house = (x: number, y: number, w: number, h: number, o: number): Building => ({ kind: 'house', x, y, w, h, r: 0, o })
const hall = (x: number, y: number, w: number, h: number, o: number): Building => ({ kind: 'hall', x, y, w, h, r: 0, o })

/** The named places' own, larger buildings (also the source of their window lights). */
const STORAGE: readonly Building[] = [hall(80, 56, 30, 6, 0.74), hall(80, 64, 27, 6, 0.72), hall(80, 72, 14, 5, 0.68)]
const HALL: readonly Building[] = [hall(164, 106, 30, 10, 0.72), hall(172, 94, 12, 12, 0.85), house(190, 118, 5, 5, 0.66)]
const FORGE: readonly Building[] = [hall(168, 66, 16, 9, 0.74), house(180, 52, 3, 14, 0.76), house(190, 72, 6, 6, 0.66)]
const INN: readonly Building[] = [hall(168, 146, 20, 13, 0.74), house(190, 150, 5, 8, 0.68)]

/** A stable 0..1 number from the seed and an index — the one source of every variation. */
function seedOf(name: string): number {
  let h = 2166136261
  for (let i = 0; i < name.length; i++) {
    h ^= name.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  return h >>> 0
}

function rand(seed: number, n: number): number {
  const x = Math.sin(seed * 0.0001 + n * 12.9898) * 43758.5453
  return x - Math.floor(x)
}

/** The served tier's walkers, as before: people on the streets, never a made-up population. */
function dotCount(sizeTier: number): number {
  return 6 + Math.max(1, Math.min(5, sizeTier || 1)) * 6
}

/** A generic block's buildings: rows facing its streets, one or two halls, a tower in the yard. */
function blockBuildings(block: Block, seed: number, bi: number): Building[] {
  const out: Building[] = []
  const pad = 2.2
  const innerW = block.w - pad * 2
  const o0 = 0.62 + rand(seed, bi * 131 + 1) * 0.16
  for (let row = 0; row < 2; row++) {
    const n = 2 + Math.floor(rand(seed, bi * 131 + 10 + row) * 3)
    const slot = innerW / n
    for (let i = 0; i < n; i++) {
      const w = Math.min(innerW, Math.max(4.5, slot - 1.4 + (rand(seed, bi * 131 + 20 + row * 10 + i) - 0.5) * 1.6))
      const h = 4.2 + rand(seed, bi * 131 + 40 + row * 10 + i) * 2.6
      const x = Math.min(block.x + pad + i * slot + 0.7, block.x + block.w - pad - w)
      const y = row === 0 ? block.y + pad : block.y + block.h - pad - h
      const o = o0 + rand(seed, bi * 131 + 80 + row * 10 + i) * 0.1
      if (rand(seed, bi * 131 + 55 + row * 10 + i) < 0.18) {
        out.push({ kind: 'tower', x: x + w / 2, y: y + h / 2, w: 0, h: 0, r: Math.min(w, h) * 0.45, o })
        continue
      }
      const isHall = w > 9 && rand(seed, bi * 131 + 60 + row * 10 + i) < 0.4
      out.push({ kind: isHall ? 'hall' : 'house', x, y, w, h, r: 0, o })
    }
  }
  if (rand(seed, bi * 131 + 110) < 0.5) {
    const w = 4 + rand(seed, bi * 131 + 111) * 3
    const h = 4 + rand(seed, bi * 131 + 112) * 2.5
    out.push({
      kind: 'house',
      x: block.x + block.w / 2 - w / 2 + (rand(seed, bi * 131 + 113) - 0.5) * 2,
      y: block.y + block.h / 2 - h / 2,
      w,
      h,
      r: 0,
      o: o0 + 0.03,
    })
  }
  if (rand(seed, bi * 131 + 100) < 0.8) {
    out.push({
      kind: 'tower',
      x: block.x + block.w / 2 + (rand(seed, bi * 131 + 101) - 0.5) * 6,
      y: block.y + block.h / 2 + (rand(seed, bi * 131 + 102) - 0.5) * 4,
      w: 0,
      h: 0,
      r: 2.8 + rand(seed, bi * 131 + 103) * 1.2,
      o: o0 + 0.06,
    })
  }
  return out
}

type Move = { d: string; dur: number; begin: number; back: boolean }
type Citizen = { x: number; y: number; r: number; o: number; move: Move | null }
type Lamp = { x: number; y: number; r: number; b: number }

/** Everything the picture needs, drawn once from the seed. */
function sceneOf(seed: number) {
  const generic: Building[] = []
  for (const [bi, block] of BLOCKS.entries()) {
    if (block.kind === 'generic') generic.push(...blockBuildings(block, seed, bi))
  }
  const all = [...generic, ...STORAGE, ...HALL, ...FORGE, ...INN]

  const crowd: Citizen[] = []
  const addCitizen = (x: number, y: number, n: number) => {
    crowd.push({ x, y, r: 1.55 + rand(seed, n) * 0.4, o: 0.9 + rand(seed, n + 1) * 0.1, move: null })
  }
  // the market crowd
  for (let k = 0; k < 34; k++) addCitizen(127 + rand(seed, 70000 + k * 7) * 23, 100 + rand(seed, 70001 + k * 7) * 21, 70002 + k * 7)
  // the harbour crowd along the quay
  for (let k = 0; k < 24; k++) {
    const y = 72 + rand(seed, 71000 + k * 7) * 86
    addCitizen(coastX(y) + 1.5 + rand(seed, 71001 + k * 7) * 4.5, y, 71002 + k * 7)
  }
  // the town hall plaza
  for (let k = 0; k < 12; k++) addCitizen(169 + rand(seed, 72000 + k * 7) * 19, 117 + rand(seed, 72001 + k * 7) * 6, 72002 + k * 7)
  // people along the streets
  for (let k = 0; k < 40; k++) {
    const road = ROADS[Math.floor(rand(seed, 73000 + k * 7) * ROADS.length)]
    const p = roadPoint(road, rand(seed, 73001 + k * 7))
    addCitizen(p.x + (rand(seed, 73002 + k * 7) - 0.5) * 2.4, p.y + (rand(seed, 73003 + k * 7) - 0.5) * 2.4, 73004 + k * 7)
  }
  // a thinner scatter in the outskirts
  for (let k = 0; k < 10; k++) addCitizen(100 + rand(seed, 74000 + k * 7) * 112, 184 + rand(seed, 74001 + k * 7) * 26, 74002 + k * 7)
  // a few people strolling a short line at the market and the quay
  for (let k = 0; k < 12; k++) {
    const atMarket = k % 2 === 0
    const x = atMarket ? 128 + rand(seed, 75000 + k * 7) * 20 : coastX(110) + 2 + rand(seed, 75000 + k * 7) * 4
    const y = atMarket ? 104 + rand(seed, 75001 + k * 7) * 16 : 82 + rand(seed, 75001 + k * 7) * 60
    const a = rand(seed, 75002 + k * 7) * Math.PI * 2
    const len = 2.5 + rand(seed, 75003 + k * 7) * 4
    crowd.push({
      x,
      y,
      r: 1.55 + rand(seed, 75004 + k * 7) * 0.4,
      o: 0.92,
      move: {
        d: `M${x.toFixed(2)} ${y.toFixed(2)} l${(Math.cos(a) * len).toFixed(2)} ${(Math.sin(a) * len).toFixed(2)}`,
        dur: 6 + rand(seed, 75005 + k * 7) * 8,
        begin: -rand(seed, 75006 + k * 7) * 10,
        back: true,
      },
    })
  }

  // the walkers along the road network; the first one is on the middle street (the spec's witness)
  const walkerPaths = [...ROAD_PATHS, ...LANE_PATHS]
  const walkers: Citizen[] = []
  for (let k = 0; k < 54; k++) {
    const pi = k === 0 ? 2 : Math.floor(rand(seed, 76000 + k * 7) * walkerPaths.length)
    walkers.push({
      x: 0,
      y: 0,
      r: 1.55 + rand(seed, 76001 + k * 7) * 0.4,
      o: 0.92 + rand(seed, 76002 + k * 7) * 0.08,
      move: { d: walkerPaths[pi], dur: 14 + rand(seed, 76003 + k * 7) * 12, begin: -rand(seed, 76004 + k * 7) * 24, back: false },
    })
  }

  // the window lights: small, dim texture on every roof, plus the stalls, the quay and the streets
  const lamps: Lamp[] = []
  const addLamp = (x: number, y: number, b: number) => {
    lamps.push({ x, y, r: 0.35 + rand(seed, 80000 + lamps.length * 5) * 0.3, b })
  }
  for (const [i, b] of all.entries()) {
    if (b.kind === 'tower') {
      addLamp(b.x + (rand(seed, 81000 + i * 9) - 0.5) * b.r, b.y + (rand(seed, 81001 + i * 9) - 0.5) * b.r, 0.35 + rand(seed, 81002 + i * 9) * 0.4)
      continue
    }
    const n = b.kind === 'hall' ? 3 : 2
    for (let k = 0; k < n; k++) {
      addLamp(
        b.x + 1.2 + rand(seed, 81010 + i * 9 + k * 3) * Math.max(0.5, b.w - 2.4),
        b.y + 0.8 + rand(seed, 81011 + i * 9 + k * 3) * Math.max(0.4, b.h - 1.6),
        0.25 + rand(seed, 81012 + i * 9 + k * 3) * 0.4,
      )
    }
  }
  for (let k = 0; k < 6; k++) addLamp(131.5 + (k % 3) * 8, 103.2 + Math.floor(k / 3) * 10, 0.6)
  for (let k = 0; k < 26; k++) {
    const y = 70 + rand(seed, 82000 + k * 5) * 90
    addLamp(coastX(y) + 1.2 + rand(seed, 82001 + k * 5) * 4.2, y, 0.55 + rand(seed, 82002 + k * 5) * 0.45)
  }
  for (let k = 0; k < 25; k++) {
    const road = ROADS[Math.floor(rand(seed, 83000 + k * 5) * ROADS.length)]
    const p = roadPoint(road, rand(seed, 83001 + k * 5))
    addLamp(p.x, p.y, 0.3 + rand(seed, 83002 + k * 5) * 0.35)
  }
  addLamp(31, 88, 0.95)
  addLamp(26, 122, 0.9)
  addLamp(24, 152, 0.9)
  addLamp(48, 80, 0.95)
  addLamp(42, 136, 0.95)
  addLamp(17, 55, 1)
  addLamp(45, 74, 0.95)
  addLamp(39, 108, 0.95)
  addLamp(35, 136, 0.95)

  return { generic, crowd, walkers, lamps }
}

/** A building's roof: pale fill, one consistent thin outline; a ridge on the long halls. */
function Roof({ b }: { b: Building }) {
  const common = {
    className: 'fill-ink-faint stroke-ink-faint',
    fillOpacity: b.o,
    strokeWidth: '0.45',
    strokeOpacity: '0.9',
  }
  if (b.kind === 'tower') return <circle cx={b.x} cy={b.y} r={b.r} {...common} />
  return (
    <g>
      <rect x={b.x} y={b.y} width={b.w} height={b.h} rx="0.7" {...common} />
      {b.kind === 'hall' && (
        <line
          className="stroke-ink-faint"
          strokeWidth="0.3"
          opacity="0.45"
          x1={b.x + 1.5}
          y1={b.y + b.h / 2}
          x2={b.x + b.w - 1.5}
          y2={b.y + b.h / 2}
        />
      )}
    </g>
  )
}

/** A moored hull: a fine outline with one deck line, seen from above. */
function Ship({ x, y, w = 13, h = 5 }: { x: number; y: number; w?: number; h?: number }) {
  return (
    <g>
      <path
        className="fill-ink-faint stroke-ink-faint"
        fillOpacity="0.45"
        strokeWidth="0.55"
        strokeOpacity="0.9"
        d={`M${x} ${y} L${x + w - 4} ${y} L${x + w} ${y + h / 2} L${x + w - 4} ${y + h} L${x} ${y + h} Z`}
      />
      <line className="stroke-ink-faint" strokeWidth="0.4" opacity="0.6" x1={x + 2} y1={y + h / 2} x2={x + w - 3} y2={y + h / 2} />
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
  /** Kept for the page's API; the picture itself is not pressable — the tiles are the doors. */
  onOpen?: (b: CityBuilding) => void
  className?: string
}) {
  const t = useT()
  const s = useMemo(() => seedOf(seed), [seed])
  const { generic, crowd, walkers, lamps } = useMemo(() => sceneOf(s), [s])
  // The served tier's walkers are the count the page has always used; the clusters are the crowd.
  const servedWalkers = useMemo(() => walkers.slice(0, dotCount(sizeTier)), [walkers, sizeTier])
  const dim = night ? 0.72 : 1

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
        {/* THE BLOCKS — a faint ground and one outline each, so the town reads as streets and cells. */}
        {BLOCKS.map((b, i) => (
          <g key={i}>
            <rect className="fill-ink-faint" opacity="0.04" x={b.x} y={b.y} width={b.w} height={b.h} rx="2.5" />
            <rect className="stroke-ink-faint" fill="none" strokeWidth="0.35" opacity="0.22" x={b.x} y={b.y} width={b.w} height={b.h} rx="2.5" />
          </g>
        ))}

        {/* THE STREET NETWORK — broad curved streets and narrower lanes, continuous lighter lines. */}
        {ROAD_PATHS.map((d, i) => (
          <path key={i} d={d} className="stroke-ink-faint" fill="none" strokeWidth="3" opacity="0.6" strokeLinecap="round" />
        ))}
        {LANE_PATHS.map((d, i) => (
          <path key={i} d={d} className="stroke-ink-faint" fill="none" strokeWidth="1.3" opacity="0.42" strokeLinecap="round" />
        ))}

        {/* THE ORDINARY BLOCKS' BUILDINGS — rows facing the streets, a tower in the yard. */}
        {generic.map((b, i) => (
          <Roof key={i} b={b} />
        ))}

        {/* THE SIX NAMED PLACES — larger and distinct, picture marks only: the tiles are the doors. */}
        <g data-testid="city-scene-storage" pointerEvents="none">
          {STORAGE.map((b, i) => (
            <Roof key={i} b={b} />
          ))}
          <g className="fill-ink-faint" opacity="0.5">
            <rect x="78" y="58" width="2" height="2" />
            <rect x="81" y="61" width="2" height="2" />
            <rect x="78" y="67" width="2" height="2" />
          </g>
        </g>

        <g data-testid="city-scene-hall" pointerEvents="none">
          {HALL.map((b, i) => (
            <Roof key={i} b={b} />
          ))}
          <rect className="fill-ink-faint" opacity="0.08" x="166" y="117" width="26" height="7" rx="1" />
          <rect className="stroke-ink-faint" fill="none" strokeWidth="0.35" opacity="0.4" x="166" y="117" width="26" height="7" rx="1" />
          <circle className="fill-ink-faint" opacity="0.14" cx="179" cy="120.5" r="2.2" />
          <circle className="stroke-ink-faint" fill="none" strokeWidth="0.35" opacity="0.5" cx="179" cy="120.5" r="2.2" />
          <line className="stroke-accent" strokeWidth="1" opacity="0.95" x1="178" y1="94" x2="178" y2="90.6" />
          <rect className="fill-accent" opacity="0.95" x="178.4" y="90.2" width="3" height="1.7" />
        </g>

        <g data-testid="city-scene-market" pointerEvents="none">
          <rect className="fill-ink-faint" opacity="0.07" x="125" y="97" width="28" height="26" rx="2" />
          <rect className="stroke-ink-faint" fill="none" strokeWidth="0.35" opacity="0.35" x="125" y="97" width="28" height="26" rx="2" />
          {[0, 1, 2].map((c) =>
            [0, 1].map((r) => (
              <g key={`${c}${r}`}>
                <rect
                  className="fill-ink-faint stroke-ink-faint"
                  fillOpacity="0.68"
                  strokeWidth="0.4"
                  strokeOpacity="0.9"
                  x={128 + c * 8}
                  y={102 + r * 11}
                  width="6"
                  height="4"
                  rx="0.6"
                />
                <circle className="fill-accent" opacity="0.8" cx={131 + c * 8} cy={103.6 + r * 11} r="0.9" />
              </g>
            )),
          )}
        </g>

        <g data-testid="city-scene-forge" pointerEvents="none">
          {FORGE.map((b, i) => (
            <Roof key={i} b={b} />
          ))}
          <g className="stroke-ink-faint" fill="none" strokeWidth="0.35" opacity="0.35">
            <circle cx="182" cy="48" r="2" />
            <circle cx="185" cy="43" r="1.6" />
            <circle cx="188" cy="39" r="1.2" />
          </g>
        </g>

        <g data-testid="city-scene-inn" pointerEvents="none">
          {INN.map((b, i) => (
            <Roof key={i} b={b} />
          ))}
          <rect className="fill-surface" x="174" y="150" width="8" height="6" />
          <rect className="stroke-ink-faint" fill="none" strokeWidth="0.35" opacity="0.5" x="174" y="150" width="8" height="6" />
          <circle className="fill-ink-faint" opacity="0.4" cx="178" cy="153" r="1.4" />
        </g>

        {/* THE PORT — a breakwater and lighthouse, three piers into the water, hulls alongside,
            three cranes on the quay and crates: the harbour is the clearest shape on this side. */}
        <g data-testid="city-scene-port" pointerEvents="none">
          <path d="M54 70 C 42 66, 30 68, 18 64" className="stroke-ink-faint" fill="none" strokeWidth="3.6" opacity="0.45" strokeLinecap="round" />
          <rect className="fill-ink-faint stroke-ink-faint" fillOpacity="0.6" strokeOpacity="0.8" strokeWidth="0.4" x="15" y="56" width="4" height="9" />
          {[
            { x: 32, y: 88, w: 26 },
            { x: 25, y: 120, w: 26 },
            { x: 23, y: 150, w: 25 },
          ].map((p, i) => (
            <rect
              key={i}
              className="fill-ink-faint stroke-ink-faint"
              fillOpacity="0.5"
              strokeOpacity="0.7"
              strokeWidth="0.4"
              x={p.x}
              y={p.y}
              width={p.w}
              height="4"
              rx="1.8"
            />
          ))}
          {[
            { x: 34, y: 93 },
            { x: 36, y: 101 },
            { x: 27, y: 126 },
            { x: 24, y: 132 },
            { x: 25, y: 156 },
            { x: 21, y: 162 },
            { x: 32, y: 76 },
            { x: 18, y: 138 },
          ].map((sh, i) => (
            <Ship key={i} x={sh.x} y={sh.y} w={i === 0 ? 17 : i < 6 ? 15 : 13} h={i === 0 ? 6 : 5.5} />
          ))}
          <g className="stroke-ink-faint" fill="none" strokeWidth="1.1" opacity="0.8">
            <path d="M56 88 v-14 h-11 M56 81 l-8 -5" />
            <path d="M50 122 v-14 h-11 M50 115 l-8 -5" />
            <path d="M46 150 v-14 h-11 M46 143 l-8 -5" />
          </g>
          <g className="fill-ink-faint" opacity="0.5">
            <rect x="60" y="92" width="2.4" height="2.4" />
            <rect x="63" y="94" width="2" height="2" />
            <rect x="55" y="126" width="2.4" height="2.4" />
            <rect x="52" y="153" width="2.2" height="2.2" />
            <rect x="64" y="150" width="2" height="2" />
            <rect x="58" y="162" width="2.2" height="2.2" />
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

      {/* THE WINDOW LIGHTS — small, dim, warm; texture behind the citizens. */}
      <g data-testid="city-lights" pointerEvents="none">
        {lamps.map((l, i) => (
          <circle
            key={i}
            className="fill-accent"
            cx={l.x}
            cy={l.y}
            r={l.r}
            opacity={night ? 0.45 + l.b * 0.35 : 0.18 + l.b * 0.22}
          />
        ))}
      </g>

      {/* THE CROWD — people at the buildings' own scale: warm, larger than the lights, clustered
          at the market and the quay and walking the streets. */}
      <g data-testid="city-crowd" pointerEvents="none" className="fill-accent">
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

      {/* THE WALKERS — the served tier's people on the road network. No cx/cy: animateMotion
          positions each one along its path, and a centre would offset it twice. */}
      <g data-testid="city-dots" pointerEvents="none" className="fill-accent">
        {servedWalkers.map((c, i) =>
          c.move ? (
            <circle key={i} r={c.r} opacity={c.o} data-dot={i}>
              <animateMotion path={c.move.d} dur={`${c.move.dur.toFixed(1)}s`} begin={`${c.move.begin.toFixed(1)}s`} repeatCount="indefinite" />
            </circle>
          ) : null,
        )}
      </g>
    </svg>
  )
}

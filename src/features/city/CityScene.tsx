import { useMemo } from 'react'
import { useT } from '../../lib/i18n'
import type { CityBuilding } from './CityFace'

// THE CLOSED WALLED HARBOUR CITY — a coastal town seen from above, complete inside its own wall
// (owner, 2026-10-31: *"make it a closed city. right now it is only a section"*; before that:
// *"wtf is this city ... does this look like a city with citizens?"*, *"no smaller tiny dots,
// scale it with buildings"*, *"good. more tiny dot with huge number"*).
//
// A city WALL with gate towers encloses the land; a dark margin of ground lies outside the wall on
// the top, right and bottom, and the SEA lies outside the wall on the left, where the wall opens
// into a wide harbour front — the quay gate — with the port outside it: a breakwater and
// lighthouse, three piers, moored hulls, cranes and the quay lamps. Every street and lane ends at
// the wall or the quay, every block and every named place is complete inside the boundary, and the
// whole composition sits inside the 240 plate with a margin on every edge, so nothing is cut by
// the frame.
//
// INSIDE: a curved street network (the quay road, three broad streets, three narrower lanes)
// frames blocks packed with small buildings — three dense rows per block of 3-5-unit houses,
// 6-9-unit halls and r 1.2-1.6 towers, in pale roofs with one consistent thin outline. The six
// named places are markedly larger and distinct (the Town Hall tower and flag, the market square,
// the warehouse rows, the forge chimney and smoke, the inn courtyard, and the port at the harbour
// front). Citizens are warm accent dots one step larger than half a small house (r 0.95-1.25), so
// they stay readable beside the shrunken buildings; the walkers take the streets and the rest
// gather at the market and the quay. A fine stipple of ~2,200 tiny dots (r 0.35-0.7, low opacity)
// fills the blocks and the quay, and the small dim window lights sit beneath them. The crowd is
// the readable layer; the stipple is the teeming texture. Nothing on the map is pressable: the
// six tiles are the only doors.
//
// Restrained palette: fill-surface land, fill-bg sea and margin, fill-ink-faint for every building,
// road, block, wall and outline, and fill-accent for the citizens and the lights. No gradients, no
// glow, no palette literal. Every coordinate is inside 0..VIEW and the svg is exactly the square
// frame. Every arrangement is derived from the city's own name (the seed).

const VIEW = 240
/** The fine plate border, inset from the panel's edge. */
const PLATE = 4
/** The city wall's landward sides; the sea side is the coast itself. */
const WALL = { top: 22, right: 220, bottom: 218 } as const
/** The harbour front — the open quay gate in the coast wall, where the port lies outside. */
const GATE = { from: 84, to: 160 } as const

/** The coast: one precise compound curve, top edge to bottom edge. */
const coastX = (y: number): number => 52 + 9 * Math.sin(0.6 + (y / VIEW) * Math.PI * 2.1)

function coastPts(from: number, to: number): { x: number; y: number }[] {
  const step = from <= to ? 2 : -2
  const out: { x: number; y: number }[] = []
  for (let y = from; step > 0 ? y <= to : y >= to; y += step) out.push({ x: coastX(y), y })
  return out
}

function coastPath(from: number, to: number): string {
  return coastPts(from, to)
    .map((p, i) => `${i === 0 ? 'M' : 'L'}${p.x.toFixed(2)} ${p.y}`)
    .join(' ')
}

/** The land inside the wall: the wall's three landward sides, then the coast back up to the top. */
const LAND = (() => {
  const up = coastPts(WALL.bottom, WALL.top)
  return (
    `M${coastX(WALL.top).toFixed(2)} ${WALL.top} L${WALL.right} ${WALL.top} L${WALL.right} ${WALL.bottom} L${coastX(WALL.bottom).toFixed(2)} ${WALL.bottom} ` +
    up
      .slice(1)
      .map((p) => `L${p.x.toFixed(2)} ${p.y}`)
      .join(' ') +
    ' Z'
  )
})()
const WALL_PATH = `M${coastX(WALL.top).toFixed(2)} ${WALL.top} L${WALL.right} ${WALL.top} L${WALL.right} ${WALL.bottom} L${coastX(WALL.bottom).toFixed(2)} ${WALL.bottom}`
const COAST_WALL_N = coastPath(WALL.top, GATE.from)
const COAST_WALL_S = coastPath(GATE.to, WALL.bottom)
const SEA_LINES = coastPath(1, VIEW - 1)

/** A gate tower at every corner, every road end and the two ends of the harbour front. */
const TOWERS: readonly { x: number; y: number }[] = [
  { x: coastX(WALL.top), y: WALL.top },
  { x: WALL.right, y: WALL.top },
  { x: WALL.right, y: WALL.bottom },
  { x: coastX(WALL.bottom), y: WALL.bottom },
  { x: WALL.right, y: 70 },
  { x: WALL.right, y: 120 },
  { x: WALL.right, y: 170 },
  { x: 116, y: WALL.top },
  { x: 158, y: WALL.top },
  { x: 198, y: WALL.top },
  { x: 116, y: WALL.bottom },
  { x: 158, y: WALL.bottom },
  { x: 198, y: WALL.bottom },
  { x: coastX(GATE.from), y: GATE.from },
  { x: coastX(GATE.to), y: GATE.to },
]

type Cubic = readonly [number, number, number, number, number, number, number, number]

/** The street network, all of it inside the wall: the quay road, three streets, three lanes. */
const QUAY_ROAD: readonly Cubic[] = [
  [64, WALL.top, 72, 60, 54, 92, 62, 126],
  [62, 126, 70, 160, 56, 196, 62, WALL.bottom],
]
const STREET_N: readonly Cubic[] = [
  [coastX(70) + 2, 70, 90, 64, 126, 66, 158, 70],
  [158, 70, 190, 74, 204, 76, WALL.right - 2, 70],
]
const STREET_M: readonly Cubic[] = [
  [coastX(120) + 2, 120, 90, 126, 126, 118, 158, 120],
  [158, 120, 190, 126, 204, 128, WALL.right - 2, 120],
]
const STREET_S: readonly Cubic[] = [
  [coastX(170) + 2, 170, 90, 176, 126, 168, 158, 170],
  [158, 170, 190, 176, 204, 178, WALL.right - 2, 170],
]
const LANE_W: readonly Cubic[] = [
  [116, WALL.top, 112, 66, 120, 110, 116, 154],
  [116, 154, 120, 196, 112, 210, 116, WALL.bottom],
]
const LANE_E: readonly Cubic[] = [
  [158, WALL.top, 154, 66, 162, 110, 158, 154],
  [158, 154, 162, 196, 154, 210, 158, WALL.bottom],
]
const LANE_F: readonly Cubic[] = [
  [198, WALL.top, 194, 66, 202, 110, 198, 154],
  [198, 154, 202, 196, 194, 210, 198, WALL.bottom],
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

/** The blocks inside the wall: the six named places and the ordinary town, all complete. */
type Kind = 'generic' | 'storage' | 'market' | 'hall' | 'forge' | 'inn'
type Block = { x: number; y: number; w: number; h: number; kind: Kind }
const BLOCKS: readonly Block[] = [
  { x: 74, y: 30, w: 36, h: 30, kind: 'storage' },
  { x: 120, y: 28, w: 34, h: 32, kind: 'generic' },
  { x: 162, y: 30, w: 34, h: 30, kind: 'forge' },
  { x: 200, y: 30, w: 16, h: 30, kind: 'generic' },
  { x: 74, y: 78, w: 36, h: 30, kind: 'generic' },
  { x: 120, y: 76, w: 34, h: 32, kind: 'market' },
  { x: 162, y: 76, w: 34, h: 32, kind: 'hall' },
  { x: 200, y: 78, w: 16, h: 30, kind: 'generic' },
  { x: 74, y: 128, w: 36, h: 28, kind: 'generic' },
  { x: 120, y: 126, w: 34, h: 30, kind: 'generic' },
  { x: 162, y: 128, w: 34, h: 28, kind: 'inn' },
  { x: 200, y: 128, w: 16, h: 28, kind: 'generic' },
  { x: 96, y: 178, w: 28, h: 18, kind: 'generic' },
  { x: 136, y: 180, w: 24, h: 16, kind: 'generic' },
  { x: 174, y: 178, w: 22, h: 16, kind: 'generic' },
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
const STORAGE: readonly Building[] = [hall(78, 34, 24, 5, 0.74), hall(78, 41, 21, 5, 0.72), hall(78, 48, 12, 4, 0.68)]
const HALL: readonly Building[] = [hall(166, 86, 24, 8, 0.72), hall(172, 76, 10, 10, 0.85), house(190, 98, 4, 4, 0.66)]
const FORGE: readonly Building[] = [hall(166, 44, 13, 7, 0.74), house(177, 31, 2.4, 13, 0.76), house(188, 50, 5, 5, 0.66)]
const INN: readonly Building[] = [hall(166, 132, 16, 10.5, 0.74), house(188, 136, 4, 7, 0.68)]

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

/** A generic block's buildings: three dense rows of small houses and narrow halls packed along its
 *  lanes, with alleys between and the odd round tower in a courtyard (owner, 2026-10-31: "smaller
 *  more buildngs too"). A small house is 3-5 units long, a hall 6-9, a tower r 1.2-1.6. */
function blockBuildings(block: Block, seed: number, bi: number): Building[] {
  const out: Building[] = []
  const pad = 1.5
  const gap = 1
  const o0 = 0.6 + rand(seed, bi * 131 + 1) * 0.16
  for (let row = 0; row < 3; row++) {
    let x = block.x + pad
    let guard = 0
    while (x < block.x + block.w - pad - 2.6 && guard < 9) {
      guard++
      const n = bi * 131 + row * 40 + guard * 3
      const roll = rand(seed, n + 1)
      const o = o0 + rand(seed, n + 2) * 0.1
      if (roll < 0.58) {
        const w = 3 + rand(seed, n + 3) * 2
        const h = 2.6 + rand(seed, n + 4) * 1.2
        const y = row === 0 ? block.y + pad : row === 2 ? block.y + block.h - pad - h : block.y + block.h / 2 - h / 2 + (rand(seed, n + 5) - 0.5) * 1.6
        if (x + w > block.x + block.w - pad) break
        out.push({ kind: 'house', x, y, w, h, r: 0, o })
        x += w + gap
      } else if (roll < 0.86) {
        const w = 6 + rand(seed, n + 6) * 3
        const h = 3 + rand(seed, n + 7) * 1.2
        const y = row === 0 ? block.y + pad : row === 2 ? block.y + block.h - pad - h : block.y + block.h / 2 - h / 2
        if (x + w > block.x + block.w - pad) break
        out.push({ kind: 'hall', x, y, w, h, r: 0, o })
        x += w + gap
      } else {
        const r = 1.2 + rand(seed, n + 8) * 0.4
        const cx = x + r
        const cy = row === 0 ? block.y + pad + r : row === 2 ? block.y + block.h - pad - r : block.y + block.h / 2
        if (cx + r > block.x + block.w - pad) break
        out.push({ kind: 'tower', x: cx, y: cy, w: 0, h: 0, r, o })
        x += r * 2 + gap
      }
    }
  }
  return out
}

type Move = { d: string; dur: number; begin: number; back: boolean }
type Citizen = { x: number; y: number; r: number; o: number; move: Move | null }
type Lamp = { x: number; y: number; r: number; b: number }
type Speck = { x: number; y: number; r: number; o: number }

/** Everything the picture needs, drawn once from the seed. */
function sceneOf(seed: number) {
  const generic: Building[] = []
  for (const [bi, block] of BLOCKS.entries()) {
    if (block.kind === 'generic') generic.push(...blockBuildings(block, seed, bi))
  }
  const all = [...generic, ...STORAGE, ...HALL, ...FORGE, ...INN]

  const crowd: Citizen[] = []
  const addCitizen = (x: number, y: number, n: number) => {
    crowd.push({ x, y, r: 0.95 + rand(seed, n) * 0.3, o: 0.9 + rand(seed, n + 1) * 0.1, move: null })
  }
  // the market crowd, inside the square
  for (let k = 0; k < 34; k++) addCitizen(125 + rand(seed, 70000 + k * 7) * 23, 82 + rand(seed, 70001 + k * 7) * 20, 70002 + k * 7)
  // the harbour crowd along the quay, inside the wall
  for (let k = 0; k < 24; k++) {
    const y = 70 + rand(seed, 71000 + k * 7) * 90
    addCitizen(coastX(y) + 1.5 + rand(seed, 71001 + k * 7) * 4.5, y, 71002 + k * 7)
  }
  // the town hall plaza
  for (let k = 0; k < 12; k++) addCitizen(169 + rand(seed, 72000 + k * 7) * 19, 99 + rand(seed, 72001 + k * 7) * 5, 72002 + k * 7)
  // people along the streets
  for (let k = 0; k < 40; k++) {
    const road = ROADS[Math.floor(rand(seed, 73000 + k * 7) * ROADS.length)]
    const p = roadPoint(road, rand(seed, 73001 + k * 7))
    addCitizen(p.x + (rand(seed, 73002 + k * 7) - 0.5) * 2.4, p.y + (rand(seed, 73003 + k * 7) - 0.5) * 2.4, 73004 + k * 7)
  }
  // a thinner scatter in the outskirts, still inside the wall
  for (let k = 0; k < 10; k++) addCitizen(100 + rand(seed, 74000 + k * 7) * 112, 178 + rand(seed, 74001 + k * 7) * 28, 74002 + k * 7)
  // a few people strolling a short line at the market and the quay
  for (let k = 0; k < 12; k++) {
    const atMarket = k % 2 === 0
    const x = atMarket ? 128 + rand(seed, 75000 + k * 7) * 20 : coastX(110) + 2 + rand(seed, 75000 + k * 7) * 4
    const y = atMarket ? 86 + rand(seed, 75001 + k * 7) * 16 : 82 + rand(seed, 75001 + k * 7) * 60
    const a = rand(seed, 75002 + k * 7) * Math.PI * 2
    const len = 2.5 + rand(seed, 75003 + k * 7) * 4
    crowd.push({
      x,
      y,
      r: 0.95 + rand(seed, 75004 + k * 7) * 0.3,
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
      r: 0.95 + rand(seed, 76001 + k * 7) * 0.3,
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
  for (let k = 0; k < 6; k++) addLamp(129.5 + (k % 3) * 8, 85.4 + Math.floor(k / 3) * 10, 0.6)
  for (let k = 0; k < 26; k++) {
    const y = 66 + rand(seed, 82000 + k * 5) * 96
    addLamp(coastX(y) + 1.2 + rand(seed, 82001 + k * 5) * 4.2, y, 0.55 + rand(seed, 82002 + k * 5) * 0.45)
  }
  for (let k = 0; k < 25; k++) {
    const road = ROADS[Math.floor(rand(seed, 83000 + k * 5) * ROADS.length)]
    const p = roadPoint(road, rand(seed, 83001 + k * 5))
    addLamp(p.x, p.y, 0.3 + rand(seed, 83002 + k * 5) * 0.35)
  }
  addLamp(17, 66, 1)
  addLamp(49, 72, 0.95)
  addLamp(43, 104, 0.95)
  addLamp(39, 134, 0.95)
  addLamp(35, 90, 0.85)
  addLamp(26, 120, 0.85)
  addLamp(24, 150, 0.85)

  // THE TEEMING TEXTURE — thousands of tiny dots across the built blocks, densest by the blocks and
  // the quay and thinning to the wall (owner: "more tiny dot with huge number"). A stipple, not the
  // readable crowd: r 0.35-0.7, one neutral ink, low opacity; every dot inside the wall.
  const teeming: Speck[] = []
  for (let k = 0; k < 2200; k++) {
    const roll = rand(seed, 84000 + k * 5)
    let x: number
    let y: number
    if (roll < 0.72) {
      const b = BLOCKS[Math.floor(rand(seed, 84001 + k * 5) * BLOCKS.length)]
      x = b.x - 3 + rand(seed, 84002 + k * 5) * (b.w + 6)
      y = b.y - 3 + rand(seed, 84003 + k * 5) * (b.h + 6)
    } else if (roll < 0.86) {
      y = 60 + rand(seed, 84005 + k * 5) * 120
      x = coastX(y) + 0.5 + rand(seed, 84006 + k * 5) * 8
    } else {
      y = 26 + rand(seed, 84007 + k * 5) * 188
      x = coastX(y) + 3 + rand(seed, 84008 + k * 5) * (216 - coastX(y) - 3)
    }
    teeming.push({
      x,
      y,
      r: 0.35 + rand(seed, 84009 + k * 5) * 0.35,
      o: 0.1 + rand(seed, 84010 + k * 5) * 0.18,
    })
  }

  return { generic, crowd, walkers, lamps, teeming }
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
  const { generic, crowd, walkers, lamps, teeming } = useMemo(() => sceneOf(s), [s])
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
      {/* THE MARGIN, THE SEA AND THE LAND — the dark ground outside the wall, the sea hairlines on
          the left, and the walled city's land inside. */}
      <rect className="fill-bg" width={VIEW} height={VIEW} />
      <g className="stroke-ink-faint" fill="none" strokeWidth="0.35">
        <path d={SEA_LINES} transform="translate(-8 0)" opacity="0.14" />
        <path d={SEA_LINES} transform="translate(-16 0)" opacity="0.11" />
        <path d={SEA_LINES} transform="translate(-24 0)" opacity="0.08" />
        <path d={SEA_LINES} transform="translate(-32 0)" opacity="0.05" />
      </g>
      <path className="fill-surface" d={LAND} />
      <path className="stroke-ink-faint" fill="none" strokeWidth="0.4" opacity="0.3" d={coastPath(1, VIEW - 1)} transform="translate(3.2 0)" />

      <g opacity={dim}>
        {/* THE BLOCKS — a faint ground and one outline each. */}
        {BLOCKS.map((b, i) => (
          <g key={i}>
            <rect className="fill-ink-faint" opacity="0.04" x={b.x} y={b.y} width={b.w} height={b.h} rx="2.5" />
            <rect className="stroke-ink-faint" fill="none" strokeWidth="0.35" opacity="0.22" x={b.x} y={b.y} width={b.w} height={b.h} rx="2.5" />
          </g>
        ))}

        {/* THE STREET NETWORK — every road ends at the wall or the quay. */}
        {ROAD_PATHS.map((d, i) => (
          <path key={i} d={d} className="stroke-ink-faint" fill="none" strokeWidth="3" opacity="0.6" strokeLinecap="round" />
        ))}
        {LANE_PATHS.map((d, i) => (
          <path key={i} d={d} className="stroke-ink-faint" fill="none" strokeWidth="1.3" opacity="0.42" strokeLinecap="round" />
        ))}

        {/* THE ORDINARY BLOCKS' BUILDINGS. */}
        {generic.map((b, i) => (
          <Roof key={i} b={b} />
        ))}

        {/* THE SIX NAMED PLACES, PICTURE MARKS ONLY — the tiles are the doors. */}
        <g data-testid="city-scene-storage" pointerEvents="none">
          {STORAGE.map((b, i) => (
            <Roof key={i} b={b} />
          ))}
          <g className="fill-ink-faint" opacity="0.5">
            <rect x="76" y="38" width="2" height="2" />
            <rect x="79" y="40" width="2" height="2" />
            <rect x="76" y="46" width="2" height="2" />
          </g>
        </g>

        <g data-testid="city-scene-hall" pointerEvents="none">
          {HALL.map((b, i) => (
            <Roof key={i} b={b} />
          ))}
          <rect className="fill-ink-faint" opacity="0.08" x="166" y="98" width="22" height="6" rx="1" />
          <rect className="stroke-ink-faint" fill="none" strokeWidth="0.35" opacity="0.4" x="166" y="98" width="22" height="6" rx="1" />
          <circle className="fill-ink-faint" opacity="0.14" cx="177" cy="101" r="1.8" />
          <circle className="stroke-ink-faint" fill="none" strokeWidth="0.35" opacity="0.5" cx="177" cy="101" r="1.8" />
          <line className="stroke-accent" strokeWidth="1" opacity="0.95" x1="177" y1="76" x2="177" y2="73.2" />
          <rect className="fill-accent" opacity="0.95" x="177.4" y="72.8" width="2.6" height="1.5" />
        </g>

        <g data-testid="city-scene-market" pointerEvents="none">
          <rect className="fill-ink-faint" opacity="0.07" x="124" y="80" width="26" height="22" rx="2" />
          <rect className="stroke-ink-faint" fill="none" strokeWidth="0.35" opacity="0.35" x="124" y="80" width="26" height="22" rx="2" />
          {[0, 1, 2].map((c) =>
            [0, 1].map((r) => (
              <g key={`${c}${r}`}>
                <rect
                  className="fill-ink-faint stroke-ink-faint"
                  fillOpacity="0.68"
                  strokeWidth="0.4"
                  strokeOpacity="0.9"
                  x={127 + c * 8}
                  y={84 + r * 10}
                  width="5"
                  height="3.2"
                  rx="0.5"
                />
                <circle className="fill-accent" opacity="0.8" cx={129.5 + c * 8} cy={85.4 + r * 10} r="0.8" />
              </g>
            )),
          )}
        </g>

        <g data-testid="city-scene-forge" pointerEvents="none">
          {FORGE.map((b, i) => (
            <Roof key={i} b={b} />
          ))}
          <g className="stroke-ink-faint" fill="none" strokeWidth="0.3" opacity="0.35">
            <circle cx="179" cy="29" r="1.4" />
            <circle cx="181" cy="27" r="1.1" />
            <circle cx="183" cy="25.2" r="0.8" />
          </g>
        </g>

        <g data-testid="city-scene-inn" pointerEvents="none">
          {INN.map((b, i) => (
            <Roof key={i} b={b} />
          ))}
          <rect className="fill-surface" x="171" y="135" width="6" height="5" />
          <rect className="stroke-ink-faint" fill="none" strokeWidth="0.35" opacity="0.5" x="171" y="135" width="6" height="5" />
          <circle className="fill-ink-faint" opacity="0.4" cx="174" cy="137.5" r="1.2" />
        </g>

        {/* THE PORT — outside the wall, on the harbour front: breakwater, lighthouse, piers, hulls,
            cranes and crates. The quay gate opens onto it. */}
        <g data-testid="city-scene-port" pointerEvents="none">
          <path d="M58 86 C 44 80, 30 82, 18 76" className="stroke-ink-faint" fill="none" strokeWidth="3.6" opacity="0.45" strokeLinecap="round" />
          <rect className="fill-ink-faint stroke-ink-faint" fillOpacity="0.6" strokeOpacity="0.8" strokeWidth="0.4" x="15" y="68" width="4" height="9" />
          {[
            { x: 35, y: 88, w: 26 },
            { x: 26, y: 118, w: 26 },
            { x: 24, y: 148, w: 25 },
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
            { x: 36, y: 100 },
            { x: 27, y: 124 },
            { x: 24, y: 130 },
            { x: 25, y: 154 },
            { x: 21, y: 160 },
            { x: 32, y: 75 },
            { x: 18, y: 136 },
          ].map((sh, i) => (
            <Ship key={i} x={sh.x} y={sh.y} w={i === 0 ? 17 : i < 6 ? 15 : 13} h={i === 0 ? 6 : 5.5} />
          ))}
          <g className="stroke-ink-faint" fill="none" strokeWidth="1.1" opacity="0.8">
            <path d="M60 86 v-14 h-11 M60 79 l-8 -5" />
            <path d="M54 118 v-14 h-11 M54 111 l-8 -5" />
            <path d="M50 148 v-14 h-11 M50 141 l-8 -5" />
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

        {/* THE TEEMING TEXTURE — thousands of tiny dots inside the walls. */}
        <g data-testid="city-teeming" pointerEvents="none" className="fill-ink-faint">
          {teeming.map((d, i) => (
            <circle key={i} cx={d.x} cy={d.y} r={d.r} opacity={d.o} />
          ))}
        </g>

        {/* THE WALL AND ITS GATES — the closed city's boundary; the coast on the left opens at the
            harbour front (the quay gate) onto the port. */}
        <path d={WALL_PATH} className="stroke-ink-faint" fill="none" strokeWidth="2.2" opacity="0.8" strokeLinecap="round" strokeLinejoin="round" />
        <path d={COAST_WALL_N} className="stroke-ink-faint" fill="none" strokeWidth="2" opacity="0.75" strokeLinecap="round" />
        <path d={COAST_WALL_S} className="stroke-ink-faint" fill="none" strokeWidth="2" opacity="0.75" strokeLinecap="round" />
        {TOWERS.map((tw, i) => (
          <rect
            key={i}
            className="fill-ink-faint stroke-ink-faint"
            fillOpacity="0.55"
            strokeOpacity="0.65"
            strokeWidth="0.5"
            x={tw.x - 2}
            y={tw.y - 2}
            width="4"
            height="4"
            rx="0.8"
          />
        ))}
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

      {/* THE CROWD — people at the buildings' own scale, inside the walls. */}
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

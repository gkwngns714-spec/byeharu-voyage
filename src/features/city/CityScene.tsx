import { useMemo, type ReactNode } from 'react'
import { useT } from '../../lib/i18n'
import type { CityBuilding } from './CityFace'

// THE CITY FROM ABOVE — a closed square harbour town drawn as a bird's-eye map (owner, 2026-10-31:
// "make it like this city... simpler but like this", then "much smaller closed square city, with
// lots of small tiny dots like light"). The reference is a straight-down aerial photograph turned
// into a plan: pale extruded blocks over dark streets, a teal water band along the town's top edge
// with piers and boats, two wide avenues and three streets marked with white dashes and tiny cars,
// green park land with a round pond and clustered trees, rows of small houses along the bottom, and
// hundreds of pin-prick lights on roofs and along the streets.
//
// THE TOWN IS ONE WALLED SQUARE, NOT A WALLPAPER. It stands whole inside a dark margin, its rim
// drawn as a wall hairline, and nothing spills past it; that closure is what makes the map read as
// a town at this size. It is drawn square because the page shows it in a square panel: the old
// 400x170 sheet was sliced to its middle by `preserveAspectRatio`, so the harbour's edges were cut
// off (owner: "the page is cut off"). A square viewBox in a square panel crops nothing.
//
// LIGHTS ARE NOT PEOPLE. The lights are static, tiny (0.4-0.9 view units) and dense — roof windows,
// street lamps, park lamps, quay lamps — and they glow warm at night and stay faint by day. The
// people stay the FEW, LARGER, MOVING dots the owner asked for ("see people moving as dots"), drawn
// cool blue and carried on <animateMotion>; the two never read as the same thing. Both are
// deterministic per harbour: the seed decides which windows are lit and how the trees sit, so one
// city is identical on every render and every machine.
//
// EVERY LANDMARK IS A DOOR (owner, 2026-10-30: "the bird's eye view is not just visual, i should be
// able to press buildings"). A press (or Enter / Space, the press a player makes) opens the SAME
// full-screen face the six building tiles below open; the tiles stay as the named list. Each
// landmark owns its whole block as the tap target (a transparent rect), because a roof outline is a
// 1-2 px line at phone size.
//
// THE HOUR is the served clock's (CityScreen). Night dims the whole town as one sheet and lets the
// lights through; day draws it plainly. Tokens only: fill-info is water and the pond, fill-success
// parks and trees, fill-accent / fill-warning lights and awnings, fill-surface / fill-surface-2 /
// fill-bg the town's planes and its extruded blocks, fill-ink-faint markings and smoke. Never a
// palette literal.

const VIEW = 240
/** The town: one closed square slab inside a dark margin, its wall a hairline on the rim. */
const CITY = { x: 24, y: 24, w: 192, h: 192 } as const
/** The plan's bands, top to bottom (view units). */
const WATER = { y: 24, h: 26 } as const
const QUAY = { y: 50, h: 6 } as const
const AVE_1 = { y: 84, h: 6 } as const
const AVE_2 = { y: 178, h: 6 } as const
const LANE = { y: 132, h: 4 } as const
/** Three blocks across, three vertical streets between them. */
const COLS = [30, 90, 150] as const
const V_STREETS = [84, 144, 204] as const
const STREET_W = 6
/** A block's side face, offset down-right: the 2.5D depth that makes a roof a building. */
const DEPTH = 2.5

type Rect = { x: number; y: number; w: number; h: number }

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

/** People walk the avenues and the three streets. Deterministic per city. */
function dotTrack(i: number): string {
  switch (i % 5) {
    case 1:
      return 'M214 87 H26'
    case 2:
      return 'M87 88 V212'
    case 3:
      return 'M147 212 V88'
    case 4:
      return 'M207 88 V212'
    default:
      return 'M26 181 H214'
  }
}

/** Every roof the lights may be lit on: lanes of windows follow these footprints. */
const TOWNHOUSES: readonly Rect[] = [
  { x: 156, y: 141, w: 22, h: 13 },
  { x: 182, y: 141, w: 16, h: 13 },
  { x: 156, y: 159, w: 14, h: 13 },
  { x: 174, y: 159, w: 24, h: 13 },
]

/** The southern districts: two rows of small houses in each block, the "layered" edge of town. */
const HOUSES: readonly Rect[] = COLS.flatMap((col) =>
  [0, 1].flatMap((row) => [0, 1, 2].map((k) => ({ x: col + k * 20, y: 187 + row * 15, w: 14, h: 12 }))),
)

const ROOFS: readonly Rect[] = [
  // the waterfront warehouses (Storage)
  { x: 32, y: 60, w: 44, h: 14 },
  { x: 80, y: 60, w: 26, h: 14 },
  // the Town Hall, its tower and its annex
  { x: 32, y: 94, w: 36, h: 18 },
  { x: 48, y: 92, w: 8, h: 7 },
  { x: 32, y: 114, w: 12, h: 8 },
  // the Forge, its chimney and its outbuilding
  { x: 102, y: 102, w: 30, h: 16 },
  { x: 124, y: 92, w: 6, h: 10 },
  { x: 90, y: 112, w: 8, h: 8 },
  // the Inn's four wings around its courtyard (the hole is deliberately not a roof)
  { x: 158, y: 96, w: 38, h: 8 },
  { x: 158, y: 114, w: 38, h: 8 },
  { x: 158, y: 104, w: 10, h: 10 },
  { x: 186, y: 104, w: 10, h: 10 },
  ...TOWNHOUSES,
  ...HOUSES,
]

/** Trees that line the streets and the park: clustered round crowns, the reference's green. */
const PARK_TREES: readonly { x: number; y: number; r: number }[] = [
  { x: 96, y: 141, r: 2.8 },
  { x: 138, y: 141, r: 2.8 },
  { x: 96, y: 171, r: 2.7 },
  { x: 138, y: 171, r: 2.7 },
  { x: 117, y: 140, r: 2.4 },
  { x: 117, y: 172, r: 2.4 },
  { x: 102, y: 157, r: 2.4 },
  { x: 132, y: 157, r: 2.4 },
]
const STREET_TREES: readonly { x: number; y: number; r: number }[] = [
  { x: 27, y: 100, r: 2.3 },
  { x: 27, y: 148, r: 2.5 },
  { x: 27, y: 196, r: 2.3 },
  { x: 213, y: 96, r: 2.3 },
  { x: 213, y: 144, r: 2.4 },
  { x: 213, y: 192, r: 2.3 },
  { x: 201, y: 146, r: 2.2 },
  { x: 201, y: 170, r: 2.2 },
  { x: 79, y: 143, r: 2 },
  { x: 36, y: 170, r: 2 },
]

type Light = { x: number; y: number; r: number; b: number; warm: boolean }

/**
 * THE LIGHTS: hundreds of static pin-pricks — quay lamps, lamps down both avenues and all three
 * streets, scattered park lamps, and two or three lit windows on every roof. The seed decides where
 * each one falls and how brightly it burns, so a harbour's lights are its own and never change.
 */
function lightsOf(seed: number): Light[] {
  const out: Light[] = []
  let n = 0
  const add = (x: number, y: number, spread: number) => {
    n += 1
    const r = 0.4 + Math.abs(jitter(seed, n * 3, 1)) * 0.5
    const b = Math.abs(jitter(seed, n * 5 + 1, 1))
    out.push({
      x: x + jitter(seed, n, spread),
      y: y + jitter(seed, n + 211, spread),
      r,
      b,
      warm: n % 3 !== 0,
    })
  }
  // lamps along the quay, the two avenues and the three streets
  for (let x = 30; x <= 210; x += 9) add(x, 53, 0.5)
  for (let x = 30; x <= 210; x += 8) {
    add(x, 87, 0.5)
    add(x, 181, 0.5)
  }
  for (let y = 90; y <= 210; y += 9) {
    add(87, y, 0.5)
    add(147, y, 0.5)
    add(207, y, 0.5)
  }
  // the park's own lamps, scattered between the trees (and never in the pond)
  for (let gx = 0; gx < 6; gx++) {
    for (let gy = 0; gy < 4; gy++) {
      if ((gx + gy) % 3 === 0) continue
      const x = 96 + gx * 7.4 + jitter(seed, gx * 31 + gy, 2)
      const y = 142 + gy * 8 + jitter(seed, gx * 17 + gy * 7, 2)
      const dx = x - 117
      const dy = y - 157
      if (dx * dx + dy * dy < 150) continue
      add(x, y, 0.35)
    }
  }
  // lit windows on every roof
  for (const [i, roof] of ROOFS.entries()) {
    const count = roof.w >= 20 ? 3 : 2
    for (let k = 0; k < count; k++) {
      add(
        roof.x + 2 + ((k + 0.5) / count) * (roof.w - 4),
        roof.y + roof.h * (0.3 + 0.4 * ((k + i) % 2)),
        0.5,
      )
    }
  }
  return out
}

/** The extruded block: a dark side face offset down-right, a lit top face over it. */
function Roof({ x, y, w, h, rx = 0 }: Rect & { rx?: number }) {
  return (
    <g>
      <rect className="fill-bg" x={x + DEPTH} y={y + DEPTH} width={w} height={h} rx={rx} />
      <rect
        className="fill-ink-faint stroke-ink-faint"
        fillOpacity="0.5"
        strokeWidth="0.4"
        strokeOpacity="0.3"
        x={x}
        y={y}
        width={w}
        height={h}
        rx={rx}
      />
    </g>
  )
}

/** A clustered round tree: three overlapping crowns, the reference's park green. */
function Tree({ x, y, r }: { x: number; y: number; r: number }) {
  return (
    <g className="fill-success">
      <circle cx={x} cy={y} r={r} opacity="0.85" />
      <circle cx={x + r * 0.9} cy={y + r * 0.5} r={r * 0.66} opacity="0.8" />
      <circle cx={x - r * 0.8} cy={y + r * 0.6} r={r * 0.55} opacity="0.75" />
    </g>
  )
}

/** A little boat: pale hull, a small cabin, seen from straight above. */
function Boat({ x, y, w = 18 }: { x: number; y: number; w?: number }) {
  return (
    <g>
      <path
        className="fill-surface-2"
        d={`M${x} ${y} L${x + w - 4} ${y} L${x + w} ${y + 2.2} L${x + w - 4} ${y + 4.4} L${x} ${y + 4.4} Z`}
      />
      <rect className="fill-info" x={x + w * 0.28} y={y + 1.2} width={w * 0.3} height="2" rx="0.6" opacity="0.9" />
    </g>
  )
}

const CAR_CLASS = {
  accent: 'fill-accent',
  danger: 'fill-danger',
  info: 'fill-info',
  warning: 'fill-warning',
} as const
type CarTone = keyof typeof CAR_CLASS
const CARS: readonly { x: number; y: number; tone: CarTone; down?: boolean }[] = [
  { x: 54, y: 86.6, tone: 'accent' },
  { x: 120, y: 87.4, tone: 'danger' },
  { x: 170, y: 86.6, tone: 'info' },
  { x: 96, y: 180.6, tone: 'warning' },
  { x: 160, y: 181.4, tone: 'info' },
  { x: 87.4, y: 108, tone: 'danger', down: true },
  { x: 146.6, y: 166, tone: 'accent', down: true },
  { x: 207.4, y: 120, tone: 'info', down: true },
]

/** One landmark on the plan: a press or a key opens that building's full-screen face. */
function Landmark({
  id,
  label,
  onOpen,
  hit,
  children,
}: {
  id: CityBuilding
  label: string
  onOpen?: (b: CityBuilding) => void
  /** The whole block is the tap target, not only the roof's outline: x, y, w, h in view units. */
  hit: { x: number; y: number; w: number; h: number }
  children: ReactNode
}) {
  if (!onOpen) return <g>{children}</g>
  return (
    <g
      role="button"
      tabIndex={0}
      aria-label={label}
      data-testid={`city-scene-${id}`}
      className="cursor-pointer outline-none focus-visible:opacity-80"
      onClick={() => onOpen(id)}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          onOpen(id)
        }
      }}
    >
      {children}
      <rect x={hit.x} y={hit.y} width={hit.w} height={hit.h} fill="transparent" />
    </g>
  )
}

export function CityScene({
  sizeTier,
  night,
  seed = '',
  onOpen,
  className = '',
}: {
  sizeTier: number
  night: boolean
  /** The city's stable name — the same harbour draws the same plan everywhere. */
  seed?: string
  /** Pressing a building on the plan opens its face — the same press the tiles below make. */
  onOpen?: (b: CityBuilding) => void
  className?: string
}) {
  const t = useT()
  const s = useMemo(() => seedOf(seed), [seed])
  const dots = useMemo(() => {
    const total = dotCount(sizeTier)
    return Array.from({ length: total }, (_, i) => i)
  }, [sizeTier])
  const lights = useMemo(() => lightsOf(s), [s])

  // Night holds the whole town down as one sheet; the lights are drawn above it at full glow.
  const dim = night ? 0.6 : 1

  return (
    <svg
      viewBox={`0 0 ${VIEW} ${VIEW}`}
      preserveAspectRatio="xMidYMid slice"
      role="group"
      aria-label={`${t('city.title')} · ${night ? t('city.night') : t('city.day')}`}
      data-testid="city-scene"
      data-phase={night ? 'night' : 'day'}
      className={`h-full w-full rounded-tile ${className}`}
    >
      {/* THE MARGIN — dark ground around the closed town. */}
      <rect className="fill-bg" width={VIEW} height={VIEW} />

      <g opacity={dim}>
        {/* THE TOWN — its slab, the wall on its rim, the water and the quay along its top. */}
        <rect className="fill-surface" x={CITY.x} y={CITY.y} width={CITY.w} height={CITY.h} />
        <rect className="fill-info" opacity="0.55" x={CITY.x} y={WATER.y} width={CITY.w} height={WATER.h} />
        <rect className="fill-surface-2" x={CITY.x} y={QUAY.y} width={CITY.w} height={QUAY.h} />
        <rect
          className="stroke-ink-faint"
          fill="none"
          strokeWidth="1.5"
          opacity="0.6"
          x={CITY.x + 0.6}
          y={CITY.y + 0.6}
          width={CITY.w - 1.2}
          height={CITY.h - 1.2}
        />

        {/* THE STREETS — two wide avenues, one lane, three streets, all cut through the blocks. */}
        <rect className="fill-bg" x={CITY.x} y={AVE_1.y} width={CITY.w} height={AVE_1.h} />
        <rect className="fill-bg" x={CITY.x} y={AVE_2.y} width={CITY.w} height={AVE_2.h} />
        <rect className="fill-bg" x={CITY.x} y={LANE.y} width={CITY.w} height={LANE.h} />
        {V_STREETS.map((x) => (
          <rect key={x} className="fill-bg" x={x} y={AVE_1.y} width={STREET_W} height={CITY.y + CITY.h - AVE_1.y} />
        ))}
        {/* the dashes down the middle of every street */}
        <g className="stroke-ink-faint" strokeDasharray="5 5" strokeWidth="0.8" opacity="0.45">
          <line x1={CITY.x + 2} y1={AVE_1.y + AVE_1.h / 2} x2={CITY.x + CITY.w - 2} y2={AVE_1.y + AVE_1.h / 2} />
          <line x1={CITY.x + 2} y1={AVE_2.y + AVE_2.h / 2} x2={CITY.x + CITY.w - 2} y2={AVE_2.y + AVE_2.h / 2} />
          {V_STREETS.map((x) => (
            <line
              key={x}
              x1={x + STREET_W / 2}
              y1={AVE_1.y + 4}
              x2={x + STREET_W / 2}
              y2={CITY.y + CITY.h - 2}
            />
          ))}
        </g>

        {/* THE PARK — one green block with its round pond, walkway ring and tree clusters. */}
        <g pointerEvents="none">
          <rect className="fill-success" opacity="0.16" x="90" y="136" width="54" height="42" rx="2" />
          <circle className="fill-info" opacity="0.65" cx="117" cy="157" r="9" />
          <circle className="stroke-surface-2" fill="none" strokeWidth="1.6" opacity="0.75" cx="117" cy="157" r="11" />
          {PARK_TREES.map((tr, i) => (
            <Tree key={i} x={tr.x + jitter(s, i + 40, 0.8)} y={tr.y + jitter(s, i, 0.8)} r={tr.r} />
          ))}
        </g>

        {/* THE TOWNHOUSES and THE SOUTHERN DISTRICTS — blocks of extruded buildings, then rows of
            small houses, the "grouped and layered" edge of the reference. */}
        <g data-testid="city-blocks" pointerEvents="none">
          {TOWNHOUSES.map((b, i) => (
            <Roof key={`t${i}`} {...b} />
          ))}
          {HOUSES.map((b, i) => (
            <Roof key={`h${i}`} {...b} />
          ))}
        </g>

        {/* THE WATER'S BOAT — one hull out on the open water west of the piers. */}
        <g pointerEvents="none">
          <Boat x={48} y={34} w={16} />
        </g>

        {/* THE WATERFRONT WAREHOUSES — Storage is its long low roofs and the crates on its yard. */}
        <Landmark id="storage" label={t('city.storage')} onOpen={onOpen} hit={{ x: 28, y: 56, w: 84, h: 26 }}>
          <Roof x={32} y={60} w={44} h={14} />
          <Roof x={80} y={60} w={26} h={14} />
          <g className="fill-accent" opacity="0.75">
            <rect x="36" y="77" width="3" height="3" />
            <rect x="40" y="78" width="2.4" height="2.4" />
            <rect x="88" y="77" width="3" height="3" />
          </g>
        </Landmark>

        {/* THE TOWN HALL — the big roof, its tower and flag, the plaza and its fountain. */}
        <Landmark id="hall" label={t('city.cityHall')} onOpen={onOpen} hit={{ x: 30, y: 90, w: 54, h: 42 }}>
          <Roof x={32} y={94} w={36} h={18} />
          <Roof x={48} y={92} w={8} h={7} />
          <Roof x={32} y={114} w={12} h={8} />
          <rect className="fill-surface-2" opacity="0.45" x="68" y="98" width="12" height="28" rx="1.5" />
          <circle className="fill-info" opacity="0.75" cx="74" cy="112" r="2.4" />
          <Tree x={74} y={102} r={2.2} />
          <Tree x={74} y={122} r={2.2} />
          <rect className="fill-accent" x="51" y="89.2" width="1.2" height="2.6" />
        </Landmark>

        {/* THE FORGE — its chimney and the smoke that gives it away from above. */}
        <Landmark id="forge" label={t('city.forge')} onOpen={onOpen} hit={{ x: 90, y: 90, w: 54, h: 42 }}>
          <Roof x={102} y={102} w={30} h={16} />
          <Roof x={124} y={92} w={6} h={10} />
          <Roof x={90} y={112} w={8} h={8} />
          <g className="fill-ink-faint" opacity="0.35" pointerEvents="none">
            <circle cx="127" cy="89" r="1.8" />
            <circle cx="130" cy="85.5" r="1.2" />
          </g>
          {night && <rect className="fill-warning" x="103" y="107" width="4" height="2.4" />}
        </Landmark>

        {/* THE INN — four wings around its open courtyard and the tree in it. */}
        <Landmark id="inn" label={t('city.inn')} onOpen={onOpen} hit={{ x: 150, y: 90, w: 54, h: 42 }}>
          <Roof x={158} y={96} w={38} h={26} />
          <rect className="fill-surface" x="168" y="104" width="18" height="10" />
          <Tree x={177} y={109} r={2.4} />
          {night && <rect className="fill-warning" x="160" y="100" width="3" height="2" />}
        </Landmark>

        {/* THE MARKET — a paved square of stalls with gold awnings, the busiest block in town. */}
        <Landmark id="market" label={t('city.market')} onOpen={onOpen} hit={{ x: 30, y: 136, w: 54, h: 42 }}>
          <rect className="fill-surface-2" opacity="0.45" x="34" y="140" width="46" height="34" rx="1.5" />
          {[0, 1, 2].map((c) =>
            [0, 1].map((r) => (
              <g key={`${c}${r}`}>
                <rect className="fill-surface-2" x={38 + c * 14} y={144 + r * 14} width="10" height="9" rx="0.8" />
                <rect className="fill-accent" opacity="0.9" x={38 + c * 14} y={144 + r * 14} width="10" height="2.6" rx="0.8" />
              </g>
            )),
          )}
          <Tree x={79} y={143} r={2} />
          <Tree x={36} y={170} r={2} />
        </Landmark>

        {/* THE PORT — the piers into the water and the hulls alongside: the waterfront itself. */}
        <Landmark id="port" label={t('city.port')} onOpen={onOpen} hit={{ x: 112, y: 24, w: 101, h: 33 }}>
          <rect className="fill-surface-2" x="128" y="34" width="6" height="22" />
          <rect className="fill-surface-2" x="176" y="30" width="6" height="26" />
          <Boat x={138} y={40} w={20} />
          <Boat x={186} y={36} w={18} />
        </Landmark>

        {/* THE STREET TREES — clustered crowns along the wall's margins and the block edges. */}
        <g pointerEvents="none">
          {STREET_TREES.map((tr, i) => (
            <Tree key={i} x={tr.x + jitter(s, i + 7, 0.9)} y={tr.y + jitter(s, i + 61, 0.9)} r={tr.r} />
          ))}
        </g>

        {/* THE CARS — tiny coloured boxes on the avenues and the streets. */}
        <g pointerEvents="none" opacity="0.92">
          {CARS.map((c, i) => (
            <rect
              key={i}
              className={CAR_CLASS[c.tone]}
              x={c.down ? c.x - 0.75 : c.x - 1.7}
              y={c.down ? c.y - 1.7 : c.y - 0.75}
              width={c.down ? 1.5 : 3.4}
              height={c.down ? 3.4 : 1.5}
              rx="0.6"
            />
          ))}
        </g>
      </g>

      {/* THE LIGHTS — hundreds of static pin-pricks, warm and dense; faint by day, glowing at night. */}
      <g data-testid="city-lights" pointerEvents="none">
        {lights.map((l, i) => (
          <circle
            key={i}
            className={l.warm ? 'fill-accent' : 'fill-warning'}
            cx={l.x}
            cy={l.y}
            r={l.r}
            opacity={night ? 0.38 + l.b * 0.6 : 0.12 + l.b * 0.24}
          />
        ))}
      </g>

      {/* THE PEOPLE — few, larger, MOVING dots walking the streets, sized by the served tier. A dot
          carries NO cx/cy: animateMotion positions it along its track, and a centre would offset it
          a second time. */}
      <g className="fill-info" opacity="0.95" data-testid="city-dots" pointerEvents="none">
        {dots.map((i) => (
          <circle key={i} r="1.7" data-dot={i}>
            <animateMotion
              path={dotTrack(i)}
              dur={`${11 + (i % 5) * 2.4}s`}
              begin={`${-((i * 1.7) % 9)}s`}
              repeatCount="indefinite"
            />
          </circle>
        ))}
      </g>
    </svg>
  )
}

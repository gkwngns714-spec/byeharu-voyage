import { useId } from 'react'
import type { SkylineKind } from './skylineKinds'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A HARBOUR'S SKYLINE — the one picture of a place (docs/design/visual-overhaul-2026-11-23.md, principle 7:
// "HQ, a harbour's tray, the yard and the Land site each get one picture: a drawn SVG skyline or scene in the
// night-sea palette, from a small set of regional silhouettes").
//
// WHAT IT IS   one concept: THE REGIONAL SILHOUETTES. Six skylines, each drawn here from a handful of plain shapes
//              (a house, a gable, a dome, a minaret, a spire, a pagoda's tier, a palm), seen at dusk across the
//              water: a far row in faint ink, a near row in the night's own ground, a gold glow on the horizon and
//              its light on the water. Our own shapes, copied from nowhere; no bitmap, no new dependency.
// WHICH ONE    `skylineOf(culture)`: the served `ports.culture` (13 words, world.culture_faith) folded to six
//              pictures. THIS TABLE IS THE ONE AUTHORITY for which place looks like what; a caller hands the culture
//              and never picks a picture itself. A culture the table does not name is drawn as the latin harbour.
// WHERE        the design system, pure props, like `Flag`: it is handed the kind and draws it, and reads no store.
//              Its callers today: the Map's harbour tray (features/map/SendFleet.tsx). HQ, the yard and the Land
//              site are the overhaul's later slices.
// IT SAYS NOTHING. The picture is decoration (`aria-hidden`): the place's name and flag are the tray's head.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// ── THE FRAME: 320 × 72, the quay at y 54, the water under it ─────────────────────────────────
const W = 320
const H = 72
const G = 54

const r1 = (n: number) => Math.round(n * 10) / 10

/** A house: a box on the quay. */
const box = (x: number, w: number, h: number) => `M${x} ${G}V${r1(G - h)}H${x + w}V${G}Z`
/** A house with a pitched roof. */
const gable = (x: number, w: number, h: number, roof: number) =>
  `M${x} ${G}V${r1(G - h)}L${r1(x + w / 2)} ${r1(G - h - roof)}L${x + w} ${r1(G - h)}V${G}Z`
/** A northern house: its gable stepped. */
const stepped = (x: number, w: number, h: number) => {
  const s = w / 6
  const t = G - h
  return `M${x} ${G}V${t}H${r1(x + s)}V${r1(t - 4)}H${r1(x + 2 * s)}V${r1(t - 8)}H${r1(x + 4 * s)}V${r1(t - 4)}H${r1(x + 5 * s)}V${t}H${x + w}V${G}Z`
}
/** A domed hall: a box with a half-round dome on it, and a finial. */
const dome = (cx: number, w: number, h: number, r: number) =>
  `M${cx - w / 2} ${G}V${G - h}H${cx - r}A${r} ${r} 0 0 1 ${cx + r} ${G - h}H${cx + w / 2}V${G}Z` + `M${cx - 0.6} ${G - h - r + 0.5}V${G - h - r - 5}H${cx + 0.6}V${G - h - r + 0.5}Z`
/** A minaret: a slim shaft, a gallery, a cone. */
const minaret = (cx: number, h: number) =>
  `M${cx - 2} ${G}V${G - h}H${cx - 3}V${G - h - 2}H${cx + 3}V${G - h}H${cx + 2}V${G}Z` +
  `M${cx - 1.8} ${G - h - 2}V${G - h - 8}L${cx} ${G - h - 13}L${cx + 1.8} ${G - h - 8}V${G - h - 2}Z`
/** A church tower and its spire. */
const spire = (cx: number, w: number, h: number, tip: number) =>
  `M${cx - w / 2} ${G}V${G - h}L${cx} ${G - h - tip}L${cx + w / 2} ${G - h}V${G}Z`
/** A campanile: a square tower with a low pyramid cap. */
const campanile = (cx: number, w: number, h: number) =>
  `M${cx - w / 2} ${G}V${G - h}H${cx - w / 2 - 1}V${G - h - 2}L${cx} ${G - h - 8}L${cx + w / 2 + 1} ${G - h - 2}H${cx + w / 2}V${G - h}V${G}Z`
/** A windmill: a tapered tower and its four sails. */
const windmill = (cx: number, h: number) =>
  `M${cx - 4} ${G}L${cx - 2.5} ${G - h}H${cx + 2.5}L${cx + 4} ${G}Z` +
  `M${cx - 0.8} ${G - h - 1}L${cx - 12} ${G - h - 12}L${cx - 10} ${G - h - 13}L${cx + 0.8} ${G - h - 2}Z` +
  `M${cx + 0.8} ${G - h - 1}L${cx + 12} ${G - h - 12}L${cx + 10} ${G - h - 13}L${cx - 0.8} ${G - h - 2}Z` +
  `M${cx - 0.8} ${G - h - 1}L${cx - 12} ${G - h + 10}L${cx - 10} ${G - h + 11}L${cx + 0.8} ${G - h}Z` +
  `M${cx + 0.8} ${G - h - 1}L${cx + 12} ${G - h + 10}L${cx + 10} ${G - h + 11}L${cx - 0.8} ${G - h}Z`
/** A pagoda: `tiers` storeys, each a body under an upswept roof, narrowing upward, and a spire. */
const pagoda = (cx: number, base: number, tiers: number) => {
  let d = ''
  let y = G
  for (let i = 0; i < tiers; i++) {
    const w = base - i * (base / (tiers + 1.5))
    const body = 6
    d += `M${r1(cx - w / 2 + 2)} ${r1(y)}V${r1(y - body)}H${r1(cx + w / 2 - 2)}V${r1(y)}Z`
    y -= body
    const e = w / 2 + 3
    d += `M${r1(cx - e)} ${r1(y + 1)}Q${r1(cx - e * 0.55)} ${r1(y - 1)} ${r1(cx)} ${r1(y - 4)}Q${r1(cx + e * 0.55)} ${r1(y - 1)} ${r1(cx + e)} ${r1(y + 1)}Z`
    y -= 3
  }
  return d + `M${cx - 0.7} ${r1(y)}V${r1(y - 7)}H${cx + 0.7}V${r1(y)}Z`
}
/** An eastern hall: a low body under one wide swept roof. */
const hall = (x: number, w: number, h: number) => {
  const e = 4
  return `M${x + 2} ${G}V${G - h}H${x + w - 2}V${G}Z` + `M${x - e} ${G - h + 1}Q${x + w * 0.2} ${G - h - 2} ${x + w * 0.3} ${G - h - 7}H${x + w * 0.7}Q${x + w * 0.8} ${G - h - 2} ${x + w + e} ${G - h + 1}Z`
}
/** A hut: a low wall under a wide thatched cone. */
const hut = (x: number, w: number, h: number) =>
  `M${x + 1} ${G}V${G - h}H${x + w - 1}V${G}Z` + `M${x - 3} ${G - h + 1}L${r1(x + w / 2)} ${G - h - w * 0.55}L${x + w + 3} ${G - h + 1}Z`
/** A palm: a leaning trunk and five fronds. */
const palm = (x: number, h: number, lean = 1) => {
  const tx = x + 4 * lean
  const ty = G - h
  const frond = (dx: number, dy: number) => `M${tx} ${ty}Q${r1(tx + dx * 0.5)} ${r1(ty + dy - 4)} ${r1(tx + dx)} ${r1(ty + dy)}Q${r1(tx + dx * 0.45)} ${r1(ty + dy - 1.5)} ${tx} ${ty + 1.2}Z`
  return (
    `M${x - 1} ${G}Q${r1(x + 1.5 * lean)} ${r1(G - h / 2)} ${r1(tx - 0.8)} ${ty}H${r1(tx + 0.8)}Q${r1(x + 2.8 * lean)} ${r1(G - h / 2)} ${x + 1} ${G}Z` +
    frond(-12, 4) +
    frond(12, 4) +
    frond(-8, 9) +
    frond(9, 9) +
    frond(1, -6)
  )
}
/** A stupa: a bell on a plinth, and its tiered spire. */
const stupa = (cx: number, r: number) =>
  `M${cx - r - 3} ${G}V${G - 4}H${cx + r + 3}V${G}Z` +
  `M${cx - r} ${G - 4}A${r} ${r} 0 0 1 ${cx + r} ${G - 4}Z` +
  `M${cx - 2} ${G - 4 - r + 1}L${cx - 0.6} ${G - 4 - r - 12}H${cx + 0.6}L${cx + 2} ${G - 4 - r + 1}Z`
/** A temple tower (shikhara): a tall rounded spire on a base. */
const shikhara = (cx: number, w: number, h: number) =>
  `M${cx - w / 2} ${G}V${G - 8}Q${cx - w / 2} ${G - h} ${cx} ${G - h - 4}Q${cx + w / 2} ${G - h} ${cx + w / 2} ${G - 8}V${G}Z` +
  `M${cx - 0.7} ${G - h - 3}V${G - h - 9}H${cx + 0.7}V${G - h - 3}Z`
/** A harbour fort: a squat round tower with a parapet. */
const fortTower = (cx: number, w: number, h: number) => {
  const t = G - h
  const m = w / 5
  return `M${cx - w / 2} ${G}V${t}H${r1(cx - w / 2 + m)}V${t + 2}H${r1(cx - w / 2 + 2 * m)}V${t}H${r1(cx - w / 2 + 3 * m)}V${t + 2}H${r1(cx - w / 2 + 4 * m)}V${t}H${cx + w / 2}V${G}Z`
}
/** A ship at the quay: a hull and two bare masts with their yards. */
const quayShip = (x: number) =>
  `M${x} ${G - 6}H${x + 26}L${x + 22} ${G}H${x + 4}Z` +
  `M${x + 9} ${G - 6}V${G - 26}H${x + 10.2}V${G - 6}Z` +
  `M${x + 17} ${G - 6}V${G - 21}H${x + 18.2}V${G - 6}Z` +
  `M${x + 4} ${G - 20}H${x + 15}V${G - 19}H${x + 4}Z` +
  `M${x + 13} ${G - 16}H${x + 22}V${G - 15}H${x + 13}Z`

/** Each picture: its near row and its far row. The far row is drawn smaller and fainter behind. */
const SKYLINES: Readonly<Record<SkylineKind, { readonly near: readonly string[]; readonly far: readonly string[] }>> = {
  latin: {
    near: [
      fortTower(24, 22, 16),
      gable(44, 18, 12, 6),
      box(62, 14, 16),
      campanile(84, 9, 30),
      gable(92, 20, 14, 6),
      dome(128, 26, 12, 9),
      box(142, 12, 10),
      gable(156, 16, 15, 5),
      box(172, 20, 11),
      quayShip(204),
      gable(240, 18, 13, 6),
      box(258, 12, 18),
      campanile(276, 8, 24),
      gable(284, 22, 12, 6),
    ],
    far: [box(10, 30, 14), gable(60, 40, 12, 8), dome(140, 30, 10, 10), box(190, 50, 12), gable(250, 36, 14, 8), box(290, 30, 10)],
  },
  northern: {
    near: [
      stepped(14, 14, 18),
      stepped(28, 12, 22),
      stepped(40, 14, 16),
      spire(66, 10, 22, 22),
      gable(74, 16, 16, 9),
      stepped(90, 13, 20),
      box(103, 14, 12),
      windmill(136, 22),
      stepped(160, 14, 17),
      stepped(174, 12, 21),
      quayShip(196),
      gable(232, 14, 18, 10),
      stepped(246, 14, 20),
      spire(276, 8, 18, 18),
      stepped(284, 16, 15),
    ],
    far: [gable(6, 40, 12, 10), spire(70, 12, 14, 26), gable(110, 50, 10, 10), box(170, 40, 12), spire(230, 10, 14, 22), gable(260, 50, 12, 10)],
  },
  islamic: {
    near: [
      box(14, 24, 10),
      minaret(46, 28),
      dome(70, 34, 10, 13),
      minaret(94, 28),
      box(104, 18, 14),
      box(122, 14, 9),
      dome(152, 20, 9, 8),
      box(166, 22, 12),
      quayShip(196),
      box(232, 16, 13),
      minaret(256, 22),
      dome(278, 26, 9, 10),
      box(294, 18, 11),
    ],
    far: [box(4, 40, 10), dome(70, 60, 8, 20), box(120, 50, 12), dome(180, 30, 8, 11), box(220, 40, 9), minaret(270, 20), box(280, 40, 10)],
  },
  tropical: {
    near: [
      palm(14, 30, 1),
      hut(26, 16, 7),
      hut(48, 14, 6),
      palm(70, 34, -1),
      box(80, 22, 9),
      hut(108, 18, 7),
      palm(134, 26, 1),
      box(146, 16, 8),
      quayShip(176),
      hut(214, 16, 7),
      palm(240, 32, -1),
      hut(252, 18, 6),
      palm(284, 28, 1),
      hut(294, 14, 6),
    ],
    far: [palm(30, 22, -1), palm(96, 24, 1), box(150, 40, 6), palm(200, 20, 1), palm(260, 24, -1), box(270, 40, 6)],
  },
  indic: {
    near: [
      box(10, 20, 10),
      palm(38, 28, 1),
      shikhara(62, 18, 28),
      box(72, 20, 12),
      stupa(110, 10),
      box(126, 18, 9),
      palm(152, 24, -1),
      box(160, 16, 12),
      quayShip(186),
      box(222, 20, 10),
      shikhara(256, 14, 22),
      palm(278, 26, 1),
      box(288, 22, 11),
    ],
    far: [box(0, 40, 9), shikhara(70, 26, 18), box(90, 40, 8), stupa(150, 14), box(170, 40, 8), palm(240, 20, -1), box(250, 60, 8)],
  },
  eastern: {
    near: [
      hall(10, 30, 8),
      pagoda(64, 22, 4),
      hall(84, 28, 9),
      hall(120, 22, 7),
      box(146, 12, 9),
      hall(160, 24, 8),
      quayShip(194),
      hall(228, 26, 9),
      pagoda(274, 18, 3),
      hall(290, 26, 7),
    ],
    far: [hall(0, 50, 8), pagoda(80, 30, 5), hall(120, 60, 7), hall(200, 50, 8), pagoda(256, 24, 4), hall(276, 50, 7)],
  },
}

/** THE PICTURE. `kind` from `skylineOf(culture)`; the band takes its container's width, at `height` px. */
export function Skyline({
  kind,
  height = 72,
  className = '',
  'data-testid': testId,
}: {
  kind: SkylineKind
  height?: number
  className?: string
  'data-testid'?: string
}) {
  const id = useId().replace(/:/g, '')
  const art = SKYLINES[kind]
  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="xMidYMax slice"
      width="100%"
      height={height}
      aria-hidden="true"
      className={`block ${className}`}
      data-testid={testId}
      data-skyline={kind}
    >
      <defs>
        <linearGradient id={`${id}-sky`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="var(--color-surface-2)" />
          <stop offset="0.72" stopColor="color-mix(in srgb, var(--color-accent) 22%, var(--color-surface-2))" />
          <stop offset="1" stopColor="color-mix(in srgb, var(--color-accent) 34%, var(--color-surface-2))" />
        </linearGradient>
        <linearGradient id={`${id}-sea`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="color-mix(in srgb, var(--color-chart-sea) 80%, var(--color-accent))" />
          <stop offset="1" stopColor="var(--color-chart-sea)" />
        </linearGradient>
      </defs>
      <rect x="0" y="0" width={W} height={G} fill={`url(#${id}-sky)`} />
      {/* the evening star */}
      <circle cx={W * 0.82} cy={13} r={1.4} fill="var(--color-accent)" fillOpacity={0.8} />
      <g transform={`translate(0 ${G * 0.12}) scale(1 0.88)`} fill="var(--color-ink-faint)" fillOpacity={0.22}>
        {art.far.map((d, i) => (
          <path key={i} d={d} />
        ))}
      </g>
      <g fill="var(--color-bg)">
        {art.near.map((d, i) => (
          <path key={i} d={d} />
        ))}
      </g>
      <rect x="0" y={G} width={W} height={H - G} fill={`url(#${id}-sea)`} />
      {/* the horizon's light on the water */}
      <g stroke="var(--color-accent)" strokeLinecap="round" strokeOpacity={0.4} strokeWidth={1}>
        <path d={`M${W * 0.18} ${G + 4}h22M${W * 0.46} ${G + 6}h30M${W * 0.72} ${G + 4}h18M${W * 0.3} ${G + 10}h14M${W * 0.6} ${G + 12}h20`} />
      </g>
      <path d={`M0 ${G}H${W}`} stroke="var(--color-accent)" strokeOpacity={0.35} strokeWidth={0.8} />
    </svg>
  )
}

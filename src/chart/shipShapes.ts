// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A SHIP LOOKS LIKE WHAT SHE IS (owner, 2026-11-16: *"every pirate ship's graphic is same. the one with
// stronger ships, multiple fleets should have different graphics. this goes to every kinds of ship too"*).
//
// ── §7B ────────────────────────────────────────────────────────────────────────────────────────
// WHAT IT IS   one concept: THE FAMILY OF SHIP PICTURES. A ship's picture is her FAMILY (merchant, cargo,
//              navy, pirate, yours) and her TIER (1 sloop, 2 brig, 3 frigate, 4 flagship). This file owns
//              the tier rule, the kinds' four hulls each, what stands on a deck (masts, sails, a flag,
//              gun ports, a hold) and the mark that says a fleet is several ships. Our own shapes: plain
//              polygons seen from above, drawn here and copied from nowhere.
// WHERE        src/chart, under ./glyphs.ts (which resolves a served class to a silhouette and imports
//              the kinds' hulls from here) and beside nothing else: no React, no DOM, no served type.
// CALLERS      ./glyphs.ts (the chart's hulls), ./FleetsLayer.tsx (the count mark),
//              src/live/battle/ShipArt.tsx (the big picture: the battle stage and the Codex key),
//              tests/ship.look.spec.ts.
// WRONG SHAPE  a tier picked from anything but a served fact (a hash of her id, her name): a picture that
//              says "stronger" about a ship that is not. A hull with no served class keeps the kind's
//              plain hull (./glyphs.ts `PIRATE_HULL` and its sisters), which claims no tier.
//
// EVERY PATH IS BUILT ONCE (`cached`): the chart draws about 1,500 fleets and re-renders on every zoom
// step, so a hull's string is made the first time her shape and length are asked for and handed back
// after that, never built in a render.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** Whose ship it is, as a picture. `yours` is a merchant's hull in the accent. */
export type ShipFamily = 'merchant' | 'cargo' | 'navy' | 'pirate' | 'yours'
/** The three kinds with hulls of their own. */
export type KindFamily = 'cargo' | 'navy' | 'pirate'
/** 1 sloop · 2 brig · 3 frigate · 4 flagship. */
export type ShipTier = 1 | 2 | 3 | 4

export const SHIP_FAMILIES: readonly ShipFamily[] = ['yours', 'merchant', 'cargo', 'navy', 'pirate']
export const SHIP_TIERS: readonly ShipTier[] = [1, 2, 3, 4]

/** The tier's name, as the key of its word (src/lib/i18n/dict/ship.ts `tier_*`). */
export const TIER_NAME: Readonly<Record<ShipTier, 'sloop' | 'brig' | 'frigate' | 'flagship'>> = { 1: 'sloop', 2: 'brig', 3: 'frigate', 4: 'flagship' }

/**
 * THE TIER OF A SERVED SIZE — the one rule. `class_profile.size` runs 1-6 (small, light, medium, heavy,
 * capital, flagship); a battle serves a ship's `ship_classes.tier` on the same scale. Small is a sloop,
 * light a brig, medium and heavy a frigate, capital and flagship a flagship.
 */
export function shipTierOf(size: number): ShipTier {
  const s = Number.isFinite(size) ? Math.round(size) : 1
  return s <= 1 ? 1 : s === 2 ? 2 : s <= 4 ? 3 : 4
}

/**
 * WHOSE PICTURE A SIDE OF A BATTLE WEARS, from the served side (`world.battle_ticks().sides[]`): her kind
 * (`public.fleet_kind`), her nation, and whether she is the reader's. A ship with no served side is a raid's
 * anonymous raider when she attacks (the only ships with no fleet row), else a merchant.
 */
export function familyOfSide(side: { readonly kind?: string | null; readonly nation?: string | null; readonly mine?: boolean } | null | undefined, attacking: boolean): ShipFamily {
  if (!side) return attacking ? 'pirate' : 'merchant'
  const kind = (side.kind ?? '').toUpperCase()
  if (kind.includes('PIRATE')) return 'pirate'
  if (kind.includes('NAVY')) return 'navy'
  if (kind.includes('CARGO')) return 'cargo'
  if (side.mine) return 'yours'
  return side.nation === 'PIR' ? 'pirate' : 'merchant'
}

type Half = readonly (readonly [number, number])[]

const paths = new Map<string, string>()
/** One string per key, built once. */
function cached(key: string, build: () => string): string {
  let d = paths.get(key)
  if (d === undefined) {
    d = build()
    paths.set(key, d)
  }
  return d
}

const r3 = (n: number) => Math.round(n * 1000) / 1000

/** A symmetric closed hull from its starboard half (unit half-length, bow at (0, -1), listed bow to stern), at `l`. */
function mirror(half: Half, l: number): string {
  const right = half.map(([x, y]) => `${r3(x * l)} ${r3(y * l)}`)
  const left = [...half].reverse().filter(([x]) => x !== 0).map(([x, y]) => `${r3(-x * l)} ${r3(y * l)}`)
  return `M${[...right, ...left].join('L')}Z`
}

/**
 * THE KINDS' HULLS, FOUR EACH — the starboard half, half-length 1, bow up. Each kind keeps the one thing she is
 * known by at every tier, and each tier adds to it, so a bigger ship is a longer hull with more to her and never
 * the small one scaled:
 *
 *   pirate  THE FORKED STERN (a fish's tail). 1 a slim cutter · 2 fuller, a raked bow · 3 a beak at the stem and
 *           a long waist · 4 the beak, a gun deck bulging amidships and a tail forked twice.
 *   navy    THE DART: straight sides, a stern swept to two points. 1 a plain dart · 2 a shoulder at the bow ·
 *           3 a beak and a longer run · 4 the beak, and a stern gallery stepped out before the sweep.
 *   cargo   THE TUB: a blunt bow, the beam most of her length, a flat transom. 1 a round lighter · 2 a transom
 *           stepped out · 3 a waist tucked in under a castle · 4 a castle in two steps.
 */
const KIND_HALVES: Readonly<Record<KindFamily, readonly [Half, Half, Half, Half]>> = {
  pirate: [
    [[0, -1], [0.22, -0.66], [0.36, -0.3], [0.32, 0.1], [0.15, 0.58], [0.4, 1], [0.17, 0.82], [0, 0.7]],
    [[0, -1], [0.26, -0.78], [0.46, -0.44], [0.42, -0.04], [0.19, 0.55], [0.5, 1], [0.23, 0.84], [0, 0.7]],
    [[0, -1], [0.07, -0.86], [0.3, -0.72], [0.43, -0.4], [0.43, 0.12], [0.22, 0.56], [0.52, 1], [0.24, 0.84], [0, 0.68]],
    [[0, -1], [0.08, -0.88], [0.33, -0.74], [0.44, -0.46], [0.52, -0.3], [0.52, 0.2], [0.44, 0.3], [0.26, 0.6], [0.58, 1], [0.32, 0.8], [0.16, 0.96], [0, 0.72]],
  ],
  navy: [
    [[0, -1], [0.2, -0.5], [0.3, -0.05], [0.3, 0.6], [0.44, 1], [0.13, 0.76], [0, 0.76]],
    [[0, -1], [0.15, -0.72], [0.29, -0.5], [0.33, -0.1], [0.33, 0.58], [0.48, 1], [0.15, 0.74], [0, 0.74]],
    [[0, -1], [0.05, -0.86], [0.24, -0.62], [0.35, -0.2], [0.35, 0.55], [0.52, 1], [0.16, 0.72], [0, 0.72]],
    [[0, -1], [0.06, -0.88], [0.27, -0.66], [0.38, -0.26], [0.38, 0.44], [0.46, 0.5], [0.46, 0.66], [0.6, 1], [0.2, 0.76], [0, 0.76]],
  ],
  cargo: [
    [[0, -1], [0.42, -0.84], [0.7, -0.3], [0.7, 0.62], [0.56, 1], [0, 1]],
    [[0, -1], [0.44, -0.9], [0.68, -0.6], [0.76, -0.2], [0.76, 0.36], [0.8, 0.5], [0.8, 1], [0, 1]],
    [[0, -1], [0.45, -0.92], [0.7, -0.66], [0.8, -0.24], [0.8, 0.22], [0.72, 0.42], [0.86, 0.5], [0.86, 1], [0, 1]],
    [[0, -1], [0.38, -0.93], [0.68, -0.72], [0.76, -0.3], [0.76, 0.1], [0.68, 0.3], [0.82, 0.38], [0.82, 0.66], [0.9, 0.72], [0.9, 1], [0, 1]],
  ],
}

/**
 * HOW LONG A KIND'S HULL IS ON THE CHART, centre to bow in CSS px, by tier. The first rung is the length the kind
 * has always been drawn at (her deck mark is 2 px thick there, tests/map.kinds.spec.ts), and every tier above is
 * a step longer: the size is what is read first at 1x, the silhouette confirms it.
 */
export const KIND_TIER_HALF_LENGTH: Readonly<Record<KindFamily, readonly [number, number, number, number]>> = {
  pirate: [7, 8, 9.2, 10.8],
  navy: [7, 8, 9.2, 10.8],
  cargo: [5.8, 6.6, 7.4, 8.6],
}

/** One of a kind's four hulls: closed, bow up, `l` from centre to bow. */
export function kindTierHull(family: KindFamily, tier: ShipTier, l: number = KIND_TIER_HALF_LENGTH[family][tier - 1]): string {
  return cached(`${family}${tier}@${l}`, () => mirror(KIND_HALVES[family][tier - 1], l))
}

// ── WHAT STANDS ON HER DECK (the big picture only: the battle stage, the key) ─────────────────────

/** What a ship carries above her hull, in units of her half-length (bow at y = -1). */
export interface ShipRig {
  /** Each mast: where along her it stands, and how far each side its sail reaches. */
  readonly masts: readonly { readonly y: number; readonly span: number }[]
  /** The half-beam her deck is drawn to (gun ports and holds are set inside it). */
  readonly beam: number
  /** Gun ports a side (the navy's stripe of them; a pirate flagship's few). */
  readonly ports: number
  /** Holds on her deck: a merchant's hatch, a cargo ship's crates. */
  readonly holds: number
  /** Where her colours fly, at the stern. */
  readonly stern: number
}

const BEAM: Readonly<Record<ShipFamily, readonly [number, number, number, number]>> = {
  merchant: [0.4, 0.46, 0.52, 0.52],
  yours: [0.4, 0.46, 0.52, 0.52],
  cargo: [0.7, 0.76, 0.8, 0.76],
  navy: [0.3, 0.33, 0.35, 0.38],
  pirate: [0.36, 0.44, 0.43, 0.5],
}
const STERN: Readonly<Record<ShipFamily, number>> = { merchant: 0.95, yours: 0.95, cargo: 1, navy: 0.74, pirate: 0.7 }
/** One mast, two, three; a flagship's three stand taller (a wider sail). */
const MASTS: readonly (readonly number[])[] = [[-0.12], [-0.42, 0.22], [-0.5, -0.02, 0.42], [-0.54, -0.06, 0.4]]

const rigs = new Map<string, ShipRig>()
/** Her rig: more masts and wider sails as the tier rises; the navy's ports and the cargo ship's crates with it. */
export function shipRig(family: ShipFamily, tier: ShipTier): ShipRig {
  const key = `${family}${tier}`
  let rig = rigs.get(key)
  if (!rig) {
    const beam = BEAM[family][tier - 1]
    const reach = beam * (family === 'cargo' ? 1.12 : 1.5) + (tier === 4 ? 0.06 : 0)
    rig = {
      masts: MASTS[tier - 1].map((y, i, all) => ({ y, span: r3(reach * (all.length > 1 && i === all.length - 1 ? 0.86 : 1)) })),
      beam,
      ports: family === 'navy' ? tier + 1 : family === 'pirate' && tier >= 3 ? tier - 1 : 0,
      holds: family === 'cargo' ? tier : family === 'merchant' || family === 'yours' ? (tier >= 3 ? 1 : 0) : 0,
      stern: STERN[family],
    }
    rigs.set(key, rig)
  }
  return rig
}

/** A sail seen from above: a bar across her at `y`, bellied toward the bow, reaching `span` each side. Unit half-length × `l`. */
export function sailPath(y: number, span: number, l: number): string {
  return cached(`sail@${y}@${span}@${l}`, () => {
    const s = span * l
    const top = (y - 0.02) * l
    const belly = (y - 0.17) * l
    const back = (y + 0.045) * l
    const under = (y - 0.085) * l
    return `M${r3(-s)} ${r3(top)}Q0 ${r3(belly)} ${r3(s)} ${r3(top)}L${r3(s)} ${r3(back)}Q0 ${r3(under)} ${r3(-s)} ${r3(back)}Z`
  })
}

// ── A FLEET OF SEVERAL ──────────────────────────────────────────────────────────────────────────

/** How a count mark reads: `pips` one dot for each ship not drawn (one or two), `line` a chevron astern (a formation: four ships or more). */
export type CountMark = 'pips' | 'line'
export function countMarkOf(total: number, drawn: number): CountMark | null {
  if (!(total > drawn)) return null
  return total >= 4 ? 'line' : 'pips'
}

/**
 * THE SHIPS A MARK DOES NOT DRAW, SAID ASTERN OF IT — in the fleet's own frame (bow up), CSS px, in the hull's own
 * ink. The chart draws at most three hulls of a fleet, and one when it is pulled back (./glyphs.ts `hullGroup`), so
 * until now a fleet of two and a fleet of eight were one picture from afar. One ship more is one dot astern, two
 * are two; from four ships a fleet is a FORMATION and wears a chevron (never a number: a mark is read, not counted).
 * `l` is the flagship's half-length, `astern` the y of the aftermost point drawn. Null when every ship is drawn.
 */
export function fleetCountMark(total: number, drawn: number, l: number, astern: number): string | null {
  const kind = countMarkOf(total, drawn)
  if (kind === null) return null
  const n = kind === 'pips' ? total - drawn : 0
  return cached(`count@${kind}@${n}@${l}@${astern}`, () => {
    const y = astern + Math.max(1.6, l * 0.42)
    if (kind === 'pips') {
      const r = Math.max(1, l * 0.2)
      const dot = (x: number) => `M${r3(x - r)} ${r3(y)}a${r3(r)} ${r3(r)} 0 1 0 ${r3(2 * r)} 0a${r3(r)} ${r3(r)} 0 1 0 ${r3(-2 * r)} 0Z`
      return n === 1 ? dot(0) : dot(-r * 1.7) + dot(r * 1.7)
    }
    // the chevron: a solid V, its point toward the bow, as wide as the flagship is long
    const w = Math.max(3.2, l * 0.95)
    const rise = w * 0.62
    const t = Math.max(1.2, l * 0.24)
    return `M0 ${r3(y - rise * 0.35)}L${r3(w)} ${r3(y + rise * 0.65)}L${r3(w)} ${r3(y + rise * 0.65 + t)}L0 ${r3(y - rise * 0.35 + t)}L${r3(-w)} ${r3(y + rise * 0.65 + t)}L${r3(-w)} ${r3(y + rise * 0.65)}Z`
  })
}

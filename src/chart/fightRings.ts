// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A FIGHT'S RING — where the red circle of a battle stands and how big it is. PURE: no React, no store.
// (0364, owner row 321: "i want a fight to be visible in map. in red circle surrounding all fleets. if more fleets
// participate, bigger circle. by clicking that circle, like info i want to see the actual fight".)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SIZE, IN SCREEN PIXELS, THE SAME AT EVERY ZOOM (as every mark of this chart is: ./glyphs.ts):
//
//     radius = max( 22 + 6 × (fleets − 2), capped at 64 ,  reach + 14 )
//
//   · 22 px for the two fleets a battle starts with: a 44 px circle, the touch floor, so the ring is never smaller
//     than a thumb;
//   · 6 px more for every further fleet (an escort, a called navy ship that has come up), to 64 px at nine fleets;
//   · `reach` is how far the farthest fleet lies from the ring's centre on this glass, and 14 px is a hull's own
//     half-length and a little air: a ring always goes ROUND its fleets. An attacker may lie up to 240 nm from the
//     ship she set upon (`attack_reach_nm`), so zoomed in the ring is as wide as the fight is; zoomed out the fleets
//     fall together and the count alone sets it.
// THE CENTRE is the middle of the box round the fleets' served places (`world.fights().sides[].at`) and the battle's
// own place; once the battle is over no place is served and the ring stands on the battle's place.
// Nothing here knows the wire: ./liveWorld.ts turns the served rows into `MapFight`.
// A RAID AND A NAVY FIGHT ARE THE SAME RING. They were settled in an instant, so they have no fleets' places and stand on
// their own place; `fleets` is then the server's `size` (a raid: her fleet and the raiders' ships, so five xebecs are six
// and draw 46 px; a navy fight: the ships on both sides). They are never `over`: the ring is shown for the minutes the
// server serves it, at full strength.
//
// THE PRESS (`fightAt`): the whole disc, never less than a 22 px radius. Among several the nearest centre wins.
// `fightTapWins` says when a press inside a ring means the fight and when it means the mark under it: a SMALL ring
// (its radius within a mark's own reach) is one target and always the fight; a WIDE ring gives a harbour, a merchant
// or a fleet that is not in the battle its own press, and takes the open water and its own fleets.

import { project, shortLonDelta, type LatLon, type Point } from '../lib/geo'

/** A battle as the chart draws it. `fleets` is the server's count of the fleets that are there. */
export interface MapFight {
  readonly id: string
  /** The battle's own place: where the ship set upon was when it began. */
  readonly at: LatLon
  readonly fleets: number
  /** Where each fleet that is there lies now; empty once the battle is over. */
  readonly places: readonly LatLon[]
  /** The ids of every fleet in it, there or on her way. */
  readonly fleetIds: readonly string[]
  /** True once it has ended: the ring is kept a short while with the result, then goes. */
  readonly over: boolean
  /** The caller's own fleet in it, or null. */
  readonly mine: string | null
  /** BATTLE (timed, being fought or just over), RAID (her own, just settled) or NAVY (a navy ship and a pirate ship, just fought). */
  readonly kind: 'BATTLE' | 'RAID' | 'NAVY'
}

export const FIGHT_RING = {
  /** The radius for the two fleets a battle starts with: half the touch floor. */
  basePx: 22,
  /** More radius for every fleet past the second. */
  perFleetPx: 6,
  /** The most the count alone may make it. */
  countCapPx: 64,
  /** Air between the farthest fleet and the line: a hull's half-length and a little. */
  padPx: 14,
  /** The least reach a press has, whatever the ring's size. */
  minHitPx: 22,
  /** A ring this small or smaller is one press target: it takes every press inside it. */
  smallPx: 44,
} as const

/** The radius the count of fleets alone gives, in px. */
export function fightCountRadiusPx(fleets: number): number {
  const n = Math.max(2, Math.floor(Number.isFinite(fleets) ? fleets : 2))
  return Math.min(FIGHT_RING.countCapPx, FIGHT_RING.basePx + FIGHT_RING.perFleetPx * (n - 2))
}

export interface FightRing {
  readonly id: string
  /** Centre, in chart units, on the sheet's own copy (x is longitude). */
  readonly centre: Point
  /** Radius in chart units and in px at this zoom. */
  readonly r: number
  readonly rPx: number
  readonly over: boolean
  readonly mine: boolean
  readonly fleetIds: readonly string[]
  readonly kind: MapFight['kind']
}

/** One battle's ring at a zoom (`unitsPerPx`: chart units a screen pixel covers). */
export function fightRing(fight: MapFight, unitsPerPx: number): FightRing {
  const origin = project(fight.at)
  // every place measured from the battle's own place THE SHORT WAY ROUND, so a fight on the date line is one ring
  const offsets = fight.places.map((p) => {
    const q = project(p)
    return { x: shortLonDelta(origin.x, q.x), y: q.y - origin.y }
  })
  offsets.push({ x: 0, y: 0 })
  const minX = Math.min(...offsets.map((o) => o.x))
  const maxX = Math.max(...offsets.map((o) => o.x))
  const minY = Math.min(...offsets.map((o) => o.y))
  const maxY = Math.max(...offsets.map((o) => o.y))
  const mid = { x: (minX + maxX) / 2, y: (minY + maxY) / 2 }
  const reach = Math.max(...offsets.map((o) => Math.hypot(o.x - mid.x, o.y - mid.y)))
  const upp = unitsPerPx > 0 ? unitsPerPx : 1
  const rPx = Math.max(fightCountRadiusPx(fight.fleets), reach / upp + FIGHT_RING.padPx)
  return {
    id: fight.id,
    centre: { x: origin.x + mid.x, y: origin.y + mid.y },
    r: rPx * upp,
    rPx,
    over: fight.over,
    mine: fight.mine !== null,
    fleetIds: fight.fleetIds,
    kind: fight.kind,
  }
}

export function fightRings(fights: readonly MapFight[], unitsPerPx: number): FightRing[] {
  return fights.map((f) => fightRing(f, unitsPerPx))
}

/** The ring a press at `at` (chart units) is inside, or null. The reach is the ring's radius and never less than
 *  `minHitPx`; among several, the nearest centre. */
export function fightAt(rings: readonly FightRing[], at: Point, unitsPerPx: number): FightRing | null {
  let best: { ring: FightRing; d: number } | null = null
  for (const ring of rings) {
    const d = Math.hypot(shortLonDelta(ring.centre.x, at.x), at.y - ring.centre.y)
    if (d <= Math.max(ring.r, FIGHT_RING.minHitPx * unitsPerPx) && (!best || d < best.d)) best = { ring, d }
  }
  return best?.ring ?? null
}

/** Whether a press inside `ring` opens the fight, given what the chart's own hit test found under it (`under`: the
 *  fleet or merchant id, 'port' for a harbour, null for open water). See the header. */
export function fightTapWins(ring: FightRing, under: { kind: 'fleet' | 'merchant'; id: string } | { kind: 'port' } | null): boolean {
  if (under === null) return true
  if (ring.rPx <= FIGHT_RING.smallPx) return true
  return under.kind !== 'port' && ring.fleetIds.includes(under.id)
}

import { test, expect } from '@playwright/test'
import { FIGHT_RING, fightAt, fightCountRadiusPx, fightRing, fightRings, fightTapWins, type MapFight } from '../src/chart/fightRings'
import { mapFightsOf } from '../src/chart/liveWorld'
import { keepPlaces } from '../src/live/useFights'
import { project } from '../src/lib/geo'
import type { FightCard } from '../src/lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A BATTLE'S RED RING, THE GEOMETRY (0364, owner row 321: "in red circle surrounding all fleets. if more fleets
// participate, bigger circle. by clicking that circle ..."). PURE: plain Node, no browser, no world.
// The law, as src/chart/fightRings.ts states it:
//   radius px = max( 22 + 6 x (fleets - 2) capped at 64 , reach + 14 ), the same at every zoom;
//   the ring goes round every fleet's place; the press is the whole disc, never under a 22 px radius.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const fight = (over: Partial<MapFight> = {}): MapFight => ({ id: 'f1', at: { lat: 38.5, lon: -9.6 }, fleets: 2, places: [], fleetIds: ['a', 'd'], over: false, mine: null, ...over })

test('more fleets, a bigger circle: 22 px for two, 6 px a fleet, capped at 64', () => {
  expect(fightCountRadiusPx(2)).toBe(22)
  expect(fightCountRadiusPx(3)).toBe(28)
  expect(fightCountRadiusPx(5)).toBe(40)
  expect(fightCountRadiusPx(9)).toBe(64)
  expect(fightCountRadiusPx(40)).toBe(64)
  // a count that is absent, one or nonsense is the two a battle always has
  for (const n of [0, 1, -3, Number.NaN]) expect(fightCountRadiusPx(n)).toBe(22)
  // strictly growing to the cap
  for (let n = 2; n < 9; n++) expect(fightCountRadiusPx(n + 1)).toBeGreaterThan(fightCountRadiusPx(n))
  // the smallest ring is a whole touch target across
  expect(2 * fightCountRadiusPx(2)).toBeGreaterThanOrEqual(44)
})

test('the same size on the glass at every zoom, when the fleets lie together', () => {
  for (const upp of [0.001, 0.01, 0.1, 0.5, 2]) {
    const ring = fightRing(fight({ fleets: 4, places: [{ lat: 38.5, lon: -9.6 }, { lat: 38.5, lon: -9.6 }] }), upp)
    expect(ring.rPx).toBe(34)
    expect(ring.r).toBeCloseTo(34 * upp, 9)
    expect(ring.centre).toEqual(project({ lat: 38.5, lon: -9.6 }))
  }
})

test('the ring goes round every fleet: zoomed in it is as wide as the fight, centred on the fleets', () => {
  // the attacker 0.3 degrees north of the ship she set upon (18 nm); at 0.002 units a pixel that is 150 px
  const f = fight({ places: [{ lat: 38.8, lon: -9.6 }, { lat: 38.5, lon: -9.6 }] })
  const near = fightRing(f, 0.002)
  expect(near.centre.x).toBeCloseTo(-9.6, 9)
  expect(near.centre.y).toBeCloseTo(-38.65, 9)
  expect(near.rPx).toBeCloseTo(75 + FIGHT_RING.padPx, 6)
  for (const p of f.places) {
    const q = project(p)
    const dPx = Math.hypot(q.x - near.centre.x, q.y - near.centre.y) / 0.002
    expect(dPx + FIGHT_RING.padPx).toBeLessThanOrEqual(near.rPx + 1e-6)
  }
  // zoomed out the two fall together and the count alone sets it
  expect(fightRing(f, 0.1).rPx).toBe(22)
  // a battle on the date line is one ring, not one as wide as the world
  const seam = fightRing(fight({ at: { lat: 0, lon: 179.9 }, places: [{ lat: 0, lon: 179.9 }, { lat: 0, lon: -179.9 }] }), 0.01)
  expect(seam.rPx).toBeCloseTo(10 + FIGHT_RING.padPx, 6)
  expect(seam.centre.x).toBeCloseTo(180, 6)
})

test('the press: the whole disc, never under 22 px, the nearest ring among several', () => {
  const upp = 0.01
  const rings = fightRings([fight(), fight({ id: 'f2', at: { lat: 38.5, lon: -9.0 }, fleets: 6, fleetIds: ['x', 'y'] })], upp)
  const c1 = project({ lat: 38.5, lon: -9.6 })
  expect(fightAt(rings, c1, upp)?.id).toBe('f1')
  expect(fightAt(rings, { x: c1.x + 21 * upp, y: c1.y }, upp)?.id).toBe('f1')
  expect(fightAt(rings, { x: c1.x - 23 * upp, y: c1.y }, upp)).toBeNull()
  // the second ring is 46 px: its edge is inside it, and a point just past it is open water
  const c2 = project({ lat: 38.5, lon: -9.0 })
  expect(rings[1].rPx).toBe(46)
  expect(fightAt(rings, { x: c2.x, y: c2.y + 45 * upp }, upp)?.id).toBe('f2')
  expect(fightAt(rings, { x: c2.x, y: c2.y + 47 * upp }, upp)).toBeNull()
  // inside both discs, the nearer centre
  expect(fightAt(rings, { x: c1.x + 18 * upp, y: c1.y }, upp)?.id).toBe('f1')
  expect(fightAt(rings, { x: c2.x - 40 * upp, y: c2.y }, upp)?.id).toBe('f1')
  expect(fightAt(rings, { x: c2.x - 29 * upp, y: c2.y }, upp)?.id).toBe('f2')
  expect(fightAt([], c1, upp)).toBeNull()
  // every ring's press reach is at least the touch floor, at every zoom
  for (const u of [0.001, 0.05, 3]) for (const r of fightRings([fight(), fight({ fleets: 9 })], u)) expect(2 * Math.max(r.rPx, FIGHT_RING.minHitPx)).toBeGreaterThanOrEqual(44)
})

test('what a press inside a ring means: open water and its own fleets are the fight; a wide ring leaves other marks their press', () => {
  const small = fightRing(fight(), 0.01)
  const wide = fightRing(fight({ places: [{ lat: 39.5, lon: -9.6 }, { lat: 38.5, lon: -9.6 }] }), 0.002)
  expect(small.rPx).toBeLessThanOrEqual(FIGHT_RING.smallPx)
  expect(wide.rPx).toBeGreaterThan(FIGHT_RING.smallPx)
  for (const ring of [small, wide]) {
    expect(fightTapWins(ring, null)).toBe(true)
    expect(fightTapWins(ring, { kind: 'fleet', id: 'a' })).toBe(true)
    expect(fightTapWins(ring, { kind: 'merchant', id: 'd' })).toBe(true)
  }
  expect(fightTapWins(small, { kind: 'port' })).toBe(true)
  expect(fightTapWins(small, { kind: 'merchant', id: 'stranger' })).toBe(true)
  expect(fightTapWins(wide, { kind: 'port' })).toBe(false)
  expect(fightTapWins(wide, { kind: 'merchant', id: 'stranger' })).toBe(false)
  expect(fightTapWins(wide, { kind: 'fleet', id: 'stranger' })).toBe(false)
})

const card = (over: Partial<FightCard> = {}): FightCard => ({
  id: 'b1', status: 'FIGHTING', lat: 38.5, lon: -9.6, started_at: '2026-11-13T00:00:00Z', resolves_at: '2026-11-13T00:07:00Z', round_seconds: 60, rounds: 6, rounds_done: 1,
  next_at: '2026-11-13T00:02:00Z', fleets: 2, ships: 3, mine: null,
  sides: [
    { fleet: 'a', name: 'Ronda', side: 'ATTACKER', how: 'OPENED', kind: 'COMPANY', company: 'Casa Ronda', nation: 'PRT', ships: 2, here: true, at: [38.8, -9.6] },
    { fleet: 'd', name: 'Cargo ship 1', side: 'DEFENDER', how: 'OPENED', kind: 'CARGO_SHIP', company: null, nation: 'ENG', ships: 1, here: true, at: [38.5, -9.6] },
    { fleet: 'n', name: 'Navy ship 2', side: 'DEFENDER', how: 'CALLED', kind: 'NAVY', company: null, nation: 'ENG', ships: 1, here: false },
  ],
  ...over,
})

test('the served card is the input of the ring field for field, and a battle that is over keeps the places it had', () => {
  const [f] = mapFightsOf([card()])
  expect(f).toEqual({ id: 'b1', at: { lat: 38.5, lon: -9.6 }, fleets: 2, places: [{ lat: 38.8, lon: -9.6 }, { lat: 38.5, lon: -9.6 }], fleetIds: ['a', 'd', 'n'], over: false, mine: null })
  // over: the server serves no place (the fleets sail on); the last places seen are kept, so the ring stays where it was
  const over = card({ status: 'RESOLVED', next_at: null, end: 'A_TOOK', sides: card().sides.map((s) => ({ ...s, at: undefined })) })
  const kept = keepPlaces([over], [card()])
  expect(kept[0].sides.map((s) => s.at)).toEqual([[38.8, -9.6], [38.5, -9.6], undefined])
  const before = fightRing(mapFightsOf([card()])[0], 0.002)
  const after = fightRing(mapFightsOf(kept)[0], 0.002)
  expect(after.centre).toEqual(before.centre)
  expect(after.rPx).toBe(before.rPx)
  expect(after.over).toBe(true)
  // a battle first seen when it is already over stands on its own place
  expect(mapFightsOf(keepPlaces([over], []))[0].places).toEqual([])
  expect(fightRing(mapFightsOf(keepPlaces([over], []))[0], 0.002).centre).toEqual(project({ lat: 38.5, lon: -9.6 }))
})

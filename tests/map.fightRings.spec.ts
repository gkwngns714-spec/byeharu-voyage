import { test, expect } from '@playwright/test'
import { FIGHT_RING, fightAt, fightCountRadiusPx, fightRing, fightRimWins, fightRings, fightTapWins, type MapFight } from '../src/chart/fightRings'
import { mapFightsOf } from '../src/chart/liveWorld'
import { keepPlaces, NO_FIGHTS, sameOrNext } from '../src/live/useFights'
import { project } from '../src/lib/geo'
import type { FightCard } from '../src/lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A BATTLE'S RED RING, THE GEOMETRY (0364, owner row 321: "in red circle surrounding all fleets. if more fleets
// participate, bigger circle. by clicking that circle ..."). PURE: plain Node, no browser, no world.
// The law, as src/chart/fightRings.ts states it:
//   radius px = max( 22 + 6 x (fleets - 2) capped at 64 , reach + 14 ), the same at every zoom;
//   the ring goes round every fleet's place; the press is the whole disc, never under a 22 px radius.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const fight = (over: Partial<MapFight> = {}): MapFight => ({ id: 'f1', at: { lat: 38.5, lon: -9.6 }, fleets: 2, places: [], fleetIds: ['a', 'd'], over: false, mine: null, kind: 'BATTLE', ...over })

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

test("a wide ring's rim is the fight over a harbour's reach, but not on the harbour's own mark; a small ring and the middle are as they were", () => {
  const upp = 0.01
  // seven fleets (an armada of six and the ship she set upon), all in one harbour: a 52-px ring round the harbour
  const harbour = { lat: 38.5, lon: -9.6 }
  const ring = fightRing(fight({ fleets: 7 }), upp)
  expect(ring.rPx).toBe(52)
  const c = project(harbour)
  const at = (px: number) => ({ x: c.x + px * upp, y: c.y })
  // the 12 px inside the line: the fight, though the harbour's 38-px reach found the harbour there
  for (const px of [41, 46, 52, -41, -52]) expect(fightRimWins(ring, at(px), harbour, upp), String(px)).toBe(true)
  // the middle is the harbour's, and past the line is open water
  for (const px of [0, 20, 39, 53]) expect(fightRimWins(ring, at(px), harbour, upp), String(px)).toBe(false)
  // a second harbour whose own mark lies under the rim keeps its press: within 22 px of its centre it is the harbour
  const near = { lat: 38.5, lon: -9.6 + 50 * upp }
  expect(fightRimWins(ring, at(46), near, upp)).toBe(false)
  expect(fightRimWins(ring, { x: c.x, y: c.y + 46 * upp }, near, upp)).toBe(true)
  // nothing known under the press, or a small ring: this rule says nothing (fightTapWins decides)
  expect(fightRimWins(ring, at(46), null, upp)).toBe(false)
  expect(fightRimWins(fightRing(fight(), upp), at(20), harbour, upp)).toBe(false)
  // the same band at every zoom
  for (const u of [0.001, 0.05, 3]) {
    const r = fightRing(fight({ fleets: 7 }), u)
    expect(fightRimWins(r, { x: c.x + 46 * u, y: c.y }, harbour, u)).toBe(true)
    expect(fightRimWins(r, { x: c.x + 30 * u, y: c.y }, harbour, u)).toBe(false)
  }
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
  expect(f).toEqual({ id: 'b1', at: { lat: 38.5, lon: -9.6 }, fleets: 2, places: [{ lat: 38.8, lon: -9.6 }, { lat: 38.5, lon: -9.6 }], fleetIds: ['a', 'd', 'n'], over: false, mine: null, kind: 'BATTLE' })
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

test('a raid and a navy fight are the same ring, on their own place, sized by the ships: five xebecs draw bigger than one', () => {
  const raid = (ships: number): FightCard =>
    card({
      id: `raid:v:${ships}`, kind: 'RAID', size: 1 + ships, status: 'RESOLVED', next_at: null, fleets: 2, ships: 1 + ships, mine: 'a', end: 'TAKEN', lat: 36, lon: -12,
      sides: [
        { fleet: 'raiders', name: 'Xebec', side: 'ATTACKER', how: 'OPENED', kind: 'PIRATE', company: null, nation: null, ships, here: true },
        { fleet: 'a', name: 'Gaivota', side: 'DEFENDER', how: 'OPENED', kind: 'COMPANY', company: 'Casa de Aveiro', nation: 'PRT', ships: 1, here: true },
      ],
    })
  const [one, five] = mapFightsOf([raid(1), raid(5)])
  expect(one).toEqual({ id: 'raid:v:1', at: { lat: 36, lon: -12 }, fleets: 2, places: [], fleetIds: ['raiders', 'a'], over: false, mine: 'a', kind: 'RAID' })
  expect(five.fleets).toBe(6)
  for (const upp of [0.002, 0.05, 1]) {
    const small = fightRing(one, upp)
    const big = fightRing(five, upp)
    expect(small.rPx).toBe(22)
    expect(big.rPx).toBe(46)
    expect(small.centre).toEqual(project({ lat: 36, lon: -12 }))
    // settled in an instant: never drawn as over, the ring is at full strength for the minutes it is served
    expect(small.over).toBe(false)
    expect(small.mine).toBe(true)
    expect(small.kind).toBe('RAID')
  }
  // a press on her own hull inside her raid's ring opens the raid
  expect(fightTapWins(fightRing(five, 0.01), { kind: 'fleet', id: 'a' })).toBe(true)
  const navy = mapFightsOf([card({ id: 'navy:n:1', kind: 'NAVY', size: 4, status: 'RESOLVED', next_at: null, fleets: 2, ships: 4, mine: null, end: 'A_TOOK', sides: [] })])[0]
  expect(navy.kind).toBe('NAVY')
  expect(navy.over).toBe(false)
  expect(fightRing(navy, 0.01).rPx).toBe(34)
  // a card with no kind (a server before raids were served) is a battle
  expect(mapFightsOf([card()])[0].kind).toBe('BATTLE')
})

test('the poll hands the map a new list only when the answer changed: the same answer is the same object, so nothing re-renders', () => {
  const first = [card()]
  // no fight, again no fight: the very list the map already holds
  expect(sameOrNext([], NO_FIGHTS)).toBe(NO_FIGHTS)
  // the same rings served again (a new array, the same content): the list the map already holds
  expect(sameOrNext([card()], first)).toBe(first)
  // a battle over and served without places: with its places kept it is what the map holds, unless its status changed
  const still = keepPlaces([card()], first)
  expect(sameOrNext(still, first)).toBe(first)
  // a round fought, a ring gone, a ring come: a new list
  expect(sameOrNext([card({ rounds_done: 2 })], first)).not.toBe(first)
  expect(sameOrNext([], first)).toEqual([])
  expect(sameOrNext([], first)).not.toBe(first)
  expect(sameOrNext(first, NO_FIGHTS)).toBe(first)
})

import { test, expect } from '@playwright/test'
import { FIGHT_RING, fightAt, fightCountRadiusPx, fightRing, fightRimWins, fightRings, fightTapWins, type MapFight } from '../src/chart/fightRings'
import { fightPinsOf, pinFleets, pinTraffic } from '../src/chart/fightPins'
import { driftedPoint } from '../src/chart/drift'
import { mapFightsOf } from '../src/chart/liveWorld'
import type { MapTraffic, MapVoyage } from '../src/chart/mapTypes'
import { withHoldCut } from '../src/live/fightCuts'
import { endsOf, keepPlaces, NO_FIGHTS, sameOrNext } from '../src/live/useFights'
import { haversineNm, project } from '../src/lib/geo'
import type { FightCard, RosterFleet, RosterVoyage } from '../src/lib/rpc'

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

test('the served card is the input of the ring field for field; a battle that is over has no ring', () => {
  const [f] = mapFightsOf([card()])
  expect(f).toEqual({ id: 'b1', at: { lat: 38.5, lon: -9.6 }, fleets: 2, places: [{ lat: 38.8, lon: -9.6 }, { lat: 38.5, lon: -9.6 }], fleetIds: ['a', 'd', 'n'], over: false, mine: null, kind: 'BATTLE' })
  // over (owner 2026-11-15: the circle goes when the fight ends): the card is still served a minute with the result, and draws no ring
  const over = card({ status: 'RESOLVED', next_at: null, end: 'A_TOOK', sides: card().sides.map((s) => ({ ...s, at: undefined })) })
  expect(mapFightsOf([over])).toEqual([])
  expect(mapFightsOf([card({ status: 'BROKEN_OFF' })])).toEqual([])
  // the places it had are still kept on the card (the open card's own facts)
  expect(keepPlaces([over], [card()])[0].sides.map((s) => s.at)).toEqual([[38.8, -9.6], [38.5, -9.6], undefined])
})

test('a raid and a navy fight, settled in an instant, draw no ring: they are over before one could show', () => {
  const raid = card({
    id: 'raid:v:1', kind: 'RAID', size: 2, status: 'RESOLVED', next_at: null, fleets: 2, ships: 2, mine: 'a', end: 'TAKEN', lat: 36, lon: -12,
    sides: [
      { fleet: 'raiders', name: 'Xebec', side: 'ATTACKER', how: 'OPENED', kind: 'PIRATE', company: null, nation: null, ships: 1, here: true },
      { fleet: 'a', name: 'Gaivota', side: 'DEFENDER', how: 'OPENED', kind: 'COMPANY', company: 'Casa de Aveiro', nation: 'PRT', ships: 1, here: true },
    ],
  })
  const navy = card({ id: 'navy:n:1', kind: 'NAVY', size: 4, status: 'RESOLVED', next_at: null, fleets: 2, ships: 4, mine: null, end: 'A_TOOK', sides: [] })
  expect(mapFightsOf([raid, navy])).toEqual([])
  expect(fightPinsOf([raid, navy]).size).toBe(0)
  // a card with no kind (a server before raids were served) is a battle
  expect(mapFightsOf([raid, card(), navy]).map((x) => x.kind)).toEqual(['BATTLE'])
})

// ── EVERY FLEET OF A FIGHT STANDS AT THE FIGHT (src/chart/fightPins.ts), as prod's raids are served: the raider in her port ──
const raidCard = (over: Partial<FightCard> = {}): FightCard =>
  card({
    id: 'r1', lat: 33.0621, lon: -19.3342, reach_nm: 30, ticks: true, started_at: '2026-11-15T14:52:00Z', resolves_at: '2026-11-15T14:52:40Z',
    sides: [
      // the raider lies in her harbour, 150 nm off: the server serves her roadstead
      { fleet: 'p', name: 'Golden Heron', side: 'ATTACKER', how: 'OPENED', kind: 'PIRATE', company: null, nation: 'PIR', ships: 1, here: true, at: [35.5, -19.3342] },
      { fleet: 'm', name: 'Voyage Ouidah', side: 'DEFENDER', how: 'OPENED', kind: 'MERCHANT', company: 'Casa de Ouidah', nation: 'PRT', ships: 2, here: true, at: [33.0621, -19.3342] },
      { fleet: 'n', name: 'Navy ship 2', side: 'DEFENDER', how: 'CALLED', kind: 'NAVY', company: null, nation: 'PRT', ships: 1, here: false },
    ],
    ...over,
  })

test('while a battle is fought every fleet that is there is pinned inside its circle: her own place when it is inside, else beside the site', () => {
  const pins = fightPinsOf([raidCard()])
  expect([...pins.keys()].sort()).toEqual(['m', 'p'])
  const site = { lat: 33.0621, lon: -19.3342 }
  expect(pins.get('m')!.at).toEqual(site)
  const p = pins.get('p')!.at
  expect(haversineNm(p, site)).toBeGreaterThan(5)
  expect(haversineNm(p, site)).toBeLessThan(30)
  expect(p.lon).toBeGreaterThan(site.lon)
  // two raiders out of the circle stand apart from each other, both inside it; a defender laid out stands on the other side
  const two = fightPinsOf([
    raidCard({
      sides: [
        ...raidCard().sides,
        { fleet: 'p2', name: 'Black Squall', side: 'ATTACKER', how: 'ARMADA', kind: 'PIRATE', company: null, nation: 'PIR', ships: 1, here: true },
        { fleet: 'x', name: 'Far', side: 'DEFENDER', how: 'ESCORT', kind: 'COMPANY', company: 'Casa', nation: 'PRT', ships: 1, here: true, at: [40, -19] },
      ],
    }),
  ])
  expect(haversineNm(two.get('p')!.at, two.get('p2')!.at)).toBeGreaterThan(5)
  for (const id of ['p', 'p2', 'x']) expect(haversineNm(two.get(id)!.at, site)).toBeLessThan(30)
  expect(two.get('x')!.at.lon).toBeLessThan(site.lon)
  // over: nobody is pinned
  expect(fightPinsOf([raidCard({ status: 'RESOLVED' })]).size).toBe(0)
})

test('a pinned ship stands still at her pin: one under sail stops, one in port leaves her berth, one the map has no mark for is given one', () => {
  const pins = fightPinsOf([raidCard()])
  const voyage: MapVoyage = {
    course: [{ lat: 33, lon: -20 }, { lat: 34, lon: -18 }], segIndex: 0, legFrac: 0.3, segNm: 120, at: { lat: 33.3, lon: -19.4 }, sailedNm: 36, totalNm: 120,
    etaMs: 2e12, heldUntilMs: null, departedMs: 1e12, destinationCode: 'LIS', destPoint: null, waters: [],
  }
  const base = { company: 'Casa', ink: 'prt' as const, loop: null, tracked: false, docked: false, berthCode: null, berthIndex: 0, nextLapAtMs: null, lane: null, enduranceDays: Number.NaN }
  const sailing: MapTraffic = { ...base, kind: 'sailing', id: 'm', name: 'Voyage Ouidah', voyage }
  const other: MapTraffic = { ...base, kind: 'sailing', id: 'o', name: 'Passing', voyage }
  const docked: MapTraffic = { ...base, kind: 'anchored', id: 'p', name: 'Golden Heron', at: { lat: 35.5, lon: -19.3 }, ink: 'pir', docked: true, berthCode: 'POR', pirate: true }
  // unpinned, the ship under sail drifts on between reads: that is what the pin stops
  expect(driftedPoint(voyage, { nowMs: 1.5e12, readAtMs: 1.4e12 })).not.toEqual(voyage.at)
  const out = pinTraffic([sailing, other, docked], pins, new Set())
  const m = out.find((t) => t.id === 'm')!
  expect(m.kind === 'sailing' && m.voyage.at).toEqual(pins.get('m')!.at)
  expect(m.kind === 'sailing' && driftedPoint(m.voyage, { nowMs: 1.5e12, readAtMs: 1.4e12 })).toEqual(pins.get('m')!.at)
  expect(out.find((t) => t.id === 'o'), 'a ship that is not in the fight is as she was').toBe(other)
  const p = out.find((t) => t.id === 'p')!
  expect(p.kind === 'anchored' && p.at).toEqual(pins.get('p')!.at)
  expect(p.docked).toBe(false)
  expect(p.pirate).toBe(true)
  // the map has no mark for the raider (the roster has not served her yet): the card gives her one, a pirate hull, at her pin
  const made = pinTraffic([sailing], pins, new Set())
  expect(made.map((t) => t.id)).toEqual(['m', 'p'])
  expect(made[1]).toMatchObject({ kind: 'anchored', name: 'Golden Heron', pirate: true, at: pins.get('p')!.at })
  // her own fleet is on the other list: no second mark is made for it
  expect(pinTraffic([sailing], pins, new Set(['p'])).map((t) => t.id)).toEqual(['m'])
  // no fight: the very list
  const same = [sailing, other]
  expect(pinTraffic(same, new Map(), new Set())).toBe(same)
  // her own fleet under sail stops too; one in port stands at the fight
  const mine = pinFleets(
    [
      { kind: 'sailing', id: 'm', name: 'Mine', enduranceDays: 9, voyage },
      { kind: 'docked', id: 'p', name: 'Mine 2', enduranceDays: 9, portCode: 'LIS' },
    ],
    pins,
  )
  expect(mine[0].kind === 'sailing' && mine[0].voyage.segNm).toBeNull()
  expect(mine[1]).toMatchObject({ kind: 'anchored', at: pins.get('p')!.at })
})

test('a tick battle is asked about at its last tick, and closed then if the server has not: once it is past its end it is due', () => {
  const end = Date.parse('2026-11-15T14:52:40Z')
  expect(endsOf([raidCard()], end - 10_000)).toEqual({ due: [], nextInMs: 10_400 })
  expect(endsOf([raidCard()], end + 1_000)).toEqual({ due: ['r1'], nextInMs: null })
  // an old round battle, and one that is over, are the minute job's
  expect(endsOf([raidCard({ ticks: false }), raidCard({ status: 'RESOLVED' })], end + 1_000)).toEqual({ due: [], nextInMs: null })
})

test('when her fight ends the kept roster row has the hold the server leaves: cut to the fight, the eta back by the difference', () => {
  const cut = { fromMs: Date.parse('2026-11-15T14:52:00.094Z'), untilMs: Date.parse('2026-11-15T14:52:40.094Z') }
  const row = (voyage: Partial<RosterVoyage> | null): RosterFleet =>
    ({
      id: 'm',
      name: 'Voyage Ouidah',
      voyage:
        voyage === null
          ? null
          : { to: 'LIS', dest_point: null, course: [[33, -20], [34, -18]], legs_nm: [120], total_nm: 120, departed_at: '2026-11-15T14:41:56.00304+00:00', eta: '2026-11-15T15:45:23.649119+00:00', ...voyage },
    }) as unknown as RosterFleet
  // the row as prod served it while she was held: a ten-minute hold from the open (microseconds on the wire)
  const held = row({ holds: [{ from: '2026-11-15T14:52:00.094052+00:00', until: '2026-11-15T15:02:00.094052+00:00' }] })
  const done = withHoldCut(held, cut)
  expect(Date.parse(done.voyage!.holds![0].until)).toBe(cut.untilMs)
  expect(Date.parse(held.voyage!.eta) - Date.parse(done.voyage!.eta)).toBe(560_000)
  // the row the server already cut is left as served; so is the cut applied twice
  expect(withHoldCut(done, cut)).toBe(done)
  // a row from before the fight (no hold): the hold is added and the eta moves by the fight's 40 s
  const early = row({ eta: '2026-11-15T15:35:23.649119+00:00' })
  const added = withHoldCut(early, cut)
  expect(added.voyage!.holds).toHaveLength(1)
  expect(Date.parse(added.voyage!.eta) - Date.parse(early.voyage!.eta)).toBe(40_000)
  expect(Date.parse(added.voyage!.eta)).toBe(Date.parse(done.voyage!.eta))
  // a voyage that began after the fight, and a ship with none, are not hers to cut
  const later = row({ departed_at: '2026-11-15T14:55:00+00:00' })
  expect(withHoldCut(later, cut)).toBe(later)
  expect(withHoldCut(row(null), cut).voyage).toBeNull()
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

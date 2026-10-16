// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A FLEET'S MARK READS WHAT SHE IS — owner row 120, 2026-10-11
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   *"the ships, higher ships will have different graphics, such as in size, two ships grouping,
//    different graphics completely etc."*
//
// Before this the chart drew ONE hull at ONE size for a fleet, whether she was a single 60-tun
// barca or three 400-tun naus. Two channels answer it and this file holds both of them apart:
//
//   WHAT SHE IS   the hull CLASS sets the silhouette and the size — three shapes, not one scaled
//   HOW MANY      the COUNT sets how many marks are drawn — one, two, or a squadron of three
//
// UNIT: the three silhouettes are genuinely three paths and none of them is another one scaled;
// the size ramp is the cube root of the burthen and the middling hull did not move; a fleet of
// several draws several with her flagship at the SERVED point; the arrangement is a pure function
// of her own hulls and cannot be moved by a neighbour arriving or leaving (the `berthSlotOf`
// lesson, ./map.merchants.spec.ts); the group collapses to her flagship at a stated density and
// the CLASS survives that collapse; the halo holds whatever is drawn and a lone hull's halo is the
// circle that was there before row 120, to the pixel; both wire readers always say how many hulls;
// and there is ONE renderer, which the merchants and your own fleets both go through.
//
// BROWSER, with the merchants switched on (./npcOn.fixture.ts): at 390 and at 1280, in both
// schemes, every merchant on the glass draws as many hulls as she has ships, a multi-ship merchant
// really is several marks clustered about one point, and pulling back past the stated density
// collapses every group on the sheet to one mark each. Screenshots land in docs/npc-traders/.
//
// WHAT IT MEASURED when it was written (76 merchant fleets, `vite preview`, chromium, 2026-10-11):
//
//   390 px, opening frame   0.0382 °/px   13 merchant marks on the glass, 7 of them several hulls,
//                                         marks 5-23 px wide
//   1280 px, same world     0.0116 °/px    7 marks, 5 of them several
//   390 px, at the globe                  76 marks, EVERY ONE of them one hull
//
// The figures are not pinned — a fixture that sails her merchants has every right to a different
// sea next run — but the PROPERTIES they came from are, below, and the last row is the one the
// collapse exists for: 76 marks at the globe rather than 228 on a phone.

import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { PHONE, reachable, ready } from './appReady.fixture'
import { serveNpcOn } from './npcOn.fixture'
import { pullBackUntilMerchants } from './seaFrame.fixture'
import {
  buildChartModel,
  GLYPH,
  HULL_GROUP_MAX,
  HULL_GROUP_MAX_UNITS_PER_PX,
  hullGroup,
  hullGroupHalo,
  hullClassOfCode,
  hullHalfLengthOf,
  hullPath,
  hullShapeOf,
  mapFleetsOf,
  registerHullClasses,
  mapTrafficOf,
  shipPath,
  type HullClass,
  type HullMark,
  type MapPort,
} from '../src/chart'
import type { FleetShip, FleetView, TrafficFleet } from '../src/lib/rpc'

const SHOTS = path.resolve('docs', 'npc-traders')

/** Tight enough that a group is drawn: a harbour approach on a phone. */
const GROUPED = HULL_GROUP_MAX_UNITS_PER_PX / 10
/** Pulled back past the stated density, where a group is weather. */
const PULLED_BACK = HULL_GROUP_MAX_UNITS_PER_PX * 1.01

const CLASSES: readonly HullClass[] = ['barca', 'carlat', 'nau']

/** Every vertex of a glyph path, in order — the three silhouettes are compared as geometry rather
 *  than as strings, so a reformat of the path source cannot pass or fail a shape test. */
function vertices(d: string): { x: number; y: number }[] {
  return [...d.matchAll(/[ML](-?[\d.]+) (-?[\d.]+)/g)].map((m) => ({ x: Number(m[1]), y: Number(m[2]) }))
}

/** A shape in its own units: every vertex divided by the glyph's half-length, so two hulls of
 *  different sizes are compared as SHAPES. Two entries that match are one shape scaled. */
function normalised(cls: HullClass | null): string {
  const l = hullHalfLengthOf(cls)
  return vertices(hullPath(cls))
    .map((p) => `${(p.x / l).toFixed(4)},${(p.y / l).toFixed(4)}`)
    .join(' ')
}

// ── UNIT: WHAT SHE IS ──────────────────────────────────────────────────────────────────────────

test('the three hulls are three silhouettes, and no two of them are one shape scaled', () => {
  // THE REQUIREMENT IN ONE ASSERTION. Three genuinely different shapes — so dividing each by its
  // own size must NOT make any two of them equal, which is exactly what "one shape scaled" means.
  const shapes = CLASSES.map(normalised)
  expect(new Set(shapes).size).toBe(3)
  // …and none of them is the class-less hull scaled either, or there would be four names for two
  // pictures (the class-less hull is `shipPath`, which the minimap still draws).
  expect(shapes).not.toContain(normalised(null))
  expect(hullPath(null)).toBe(shipPath(GLYPH.shipHalfLength))

  for (const cls of CLASSES) {
    const d = hullPath(cls)
    const l = hullHalfLengthOf(cls)
    // Every hull is CLOSED (she is a filled body, not a line) and her BOW is at −y, so the layer's
    // one `rotate` turns her onto her heading.
    expect(d.startsWith(`M0 ${-l}`)).toBe(true)
    expect(d.endsWith('Z')).toBe(true)
    // And she is a hull and not a sliver of nothing: longer than she is wide, and wide enough to
    // have a body at all.
    const vs = vertices(d)
    const beam = Math.max(...vs.map((p) => Math.abs(p.x)))
    expect(beam).toBeGreaterThan(l * 0.25)
    expect(beam).toBeLessThan(l * 0.8)
  }

  // THE SILHOUETTES ARE DISTINGUISHABLE BY COMPLEXITY TOO, which is what "a castle you can see"
  // amounts to on a path: the barca is the plainest of the three and the carrack the most stepped.
  const corners = CLASSES.map((c) => vertices(hullPath(c)).length)
  expect(corners[0]).toBeLessThan(corners[1])
  expect(corners[1]).toBeLessThan(corners[2])
})

test('0135: eight silhouettes by rig family × size, not 55 — the live three are three of them', () => {
  // THE SERVED CLASSES (world.snapshot ship_classes: rig + size) placed by the one rule. Two codes per
  // shape, through both rigs of each family, so the rule — not a code list — is what is held.
  const shapes = ['fore-1', 'fore-2', 'fore-3', 'fore-4', 'square-1', 'square-2', 'square-3', 'square-4'] as const
  const served = shapes.flatMap((sh, i) => {
    const size = Number(sh.slice(-1))
    const rigs = sh.startsWith('square') ? ['square', 'mixed'] : ['lateen', 'oared']
    return rigs.map((rig, j) => ({ code: `wave-a-${i}-${j}`, rig, tier: Math.min(size, 5), size }))
  })
  try {
    registerHullClasses([...served, { code: 'barca', rig: 'lateen', tier: 1, size: 1 },
      { code: 'carlat', rig: 'lateen', tier: 2, size: 2 }, { code: 'nau', rig: 'square', tier: 3, size: 3 },
      { code: 'flag', rig: 'square', tier: 5, size: 6 }])
    for (const c of served) expect(hullShapeOf(c.code)).toBe(`${c.rig === 'square' || c.rig === 'mixed' ? 'square' : 'fore'}-${c.size}`)
    expect([hullShapeOf('barca'), hullShapeOf('carlat'), hullShapeOf('nau')]).toEqual(['fore-1', 'fore-2', 'square-3'])
    // a size above heavy draws as heavy; a code nobody served is the class-less hull
    expect(hullShapeOf('flag')).toBe('square-4')
    expect(hullClassOfCode('no-such-hull')).toBeNull()
    expect(hullPath('no-such-hull')).toBe(shipPath(GLYPH.shipHalfLength))
    // EIGHT shapes, none of them another scaled (or the class-less hull), every one closed, bow up
    const one = shapes.map((_, i) => `wave-a-${i}-0`)
    const norm = one.map(normalised)
    expect(new Set(norm).size).toBe(8)
    expect(norm).not.toContain(normalised(null))
    for (const code of one) {
      const d = hullPath(code)
      const l = hullHalfLengthOf(code)
      expect(d.startsWith(`M0 ${-l}`)).toBe(true)
      expect(d.endsWith('Z')).toBe(true)
      const beam = Math.max(...vertices(d).map((p) => Math.abs(p.x)))
      expect(beam).toBeGreaterThan(l * 0.25)
      expect(beam).toBeLessThan(l * 0.8)
      // both rigs of a family draw the same picture
      expect(hullPath(code.replace(/-0$/, '-1'))).toBe(d)
    }
    // the live three draw exactly as they did before any snapshot was registered
    const live = CLASSES.map((c) => hullPath(c))
    registerHullClasses([])
    expect(CLASSES.map((c) => hullPath(c))).toEqual(live)
    // length by size: small < light < medium < heavy
    registerHullClasses(served)
    const len = [1, 2, 3, 4].map((sz) => hullHalfLengthOf(`wave-a-${sz - 1}-0`))
    expect(len).toEqual([...len].sort((a, b) => a - b))
    expect(new Set(len).size).toBe(4)
  } finally {
    registerHullClasses([])
  }
})

test('a bigger ship is a bigger, heavier mark — the ramp is the cube root of her burthen', () => {
  const [barca, carlat, nau] = CLASSES.map(hullHalfLengthOf)
  expect(barca).toBeLessThan(carlat)
  expect(carlat).toBeLessThan(nau)
  // THE MIDDLING HULL DID NOT MOVE: row 90 measured the 13 px hull against the halo, the roadstead
  // ring and the port marks, and that measurement is still about a real hull on this sheet.
  expect(carlat).toBe(GLYPH.shipHalfLength)
  // A HULL'S LENGTH GROWS AS THE CUBE ROOT OF HER BURTHEN — 60 / 90 / 400 tuns
  // (…0003_the_real_world_and_the_water_between_it.sql:2089-2091). Held to 2%, because the three
  // numbers in ./glyphs.ts are px sizes rounded to a tenth and not the arithmetic itself.
  expect(barca / carlat).toBeCloseTo(Math.cbrt(60 / 90), 2)
  expect(nau / carlat).toBeCloseTo(Math.cbrt(400 / 90), 2)
  // AND IT IS A DIFFERENCE YOU READ, not one you could measure if it occurred to you to try —
  // `portMarkScale`'s own ramp was widened to 1.75× for exactly this reason.
  expect(nau / barca).toBeGreaterThan(1.75)
  // HEAVIER AND NOT MERELY LONGER: the carrack's beam is a bigger share of her own length than the
  // barca's is of hers, so she reads broad before her length is noticed.
  const relBeam = (cls: HullClass) =>
    Math.max(...vertices(hullPath(cls)).map((p) => Math.abs(p.x))) / hullHalfLengthOf(cls)
  expect(relBeam('nau')).toBeGreaterThan(relBeam('carlat'))
  expect(relBeam('carlat')).toBeGreaterThan(relBeam('barca'))
})

// ── UNIT: HOW MANY ─────────────────────────────────────────────────────────────────────────────

test('a fleet of several is drawn as several, with her flagship on the served point', () => {
  expect(HULL_GROUP_MAX).toBe(3)
  const of = (n: number) => hullGroup(Array.from({ length: n }, () => 'carlat' as HullClass), GROUPED)
  expect(of(1)).toHaveLength(1)
  expect(of(2)).toHaveLength(2)
  expect(of(3)).toHaveLength(3)
  // A fleet of eight is a SQUADRON and says so; it does not promise a count nobody could read.
  expect(of(8)).toHaveLength(HULL_GROUP_MAX)

  // THE FLAGSHIP IS THE SERVED POINT, in every group size — which is why the hit test, the label
  // anchor and the framing never had to learn that a group exists.
  for (const n of [1, 2, 3, 8]) {
    expect(of(n)[0].dx).toBe(0)
    expect(of(n)[0].dy).toBe(0)
  }
  // …and the rest are ASTERN of her and clear of each other. "Astern" is +y in her own frame,
  // because her bow is at −y.
  const three = of(3)
  for (const m of three.slice(1)) expect(m.dy).toBeGreaterThan(0)
  expect(Math.abs(three[1].dx - three[2].dx)).toBeGreaterThan(
    2 * Math.max(...vertices(hullPath('carlat')).map((p) => Math.abs(p.x))),
  )

  // A FLEET THE SERVER SAID NOTHING ABOUT is still one hull at her served point, claiming nothing
  // — the mark this chart drew before row 120, not a blank patch of sea.
  const none = hullGroup([], GROUPED)
  expect(none).toHaveLength(1)
  expect(none[0]).toEqual({ cls: null, halfLength: GLYPH.shipHalfLength, dx: 0, dy: 0 })

  // MIXED FLEETS KEEP EACH HULL'S OWN SIZE, and the group is spaced off the LONGEST of them, so a
  // barca leading two carracks is not run down by them.
  const mixed = hullGroup(['barca', 'nau', 'nau'], GROUPED)
  expect(mixed.map((m) => m.halfLength)).toEqual([
    hullHalfLengthOf('barca'),
    hullHalfLengthOf('nau'),
    hullHalfLengthOf('nau'),
  ])
  // …and the formation is spaced off the LONGEST hull in it and not off the one leading, so the
  // two carracks astern are held apart by their own beam rather than by the barca's.
  const barcas = hullGroup(['barca', 'barca', 'barca'], GROUPED)
  expect(Math.abs(mixed[1].dx)).toBeGreaterThan(Math.abs(barcas[1].dx))
  const nauBeam = Math.max(...vertices(hullPath('nau')).map((p) => Math.abs(p.x)))
  expect(Math.abs(mixed[1].dx - mixed[2].dx)).toBeGreaterThan(2 * nauBeam)
})

test('the arrangement is hers — the same every read, and no neighbour can move it', () => {
  // THE `berthSlotOf` LESSON (./liveWorld.ts, the 2026-10-10 review): a first cut of the berth fan
  // took a merchant's place from her POSITION IN THE SERVED LIST, so a hull shifted whenever
  // another merchant docked at or left the same harbour. The rule here obeys that lesson by having
  // no free parameter at all — a fleet's arrangement is a pure function of her own hull list — and
  // these are the two halves of that claim.

  // SAME INPUT, SAME ANSWER, every read: there is no hidden state to creep.
  const hulls: HullClass[] = ['nau', 'carlat', 'barca']
  const once = hullGroup(hulls, GROUPED)
  for (let i = 0; i < 5; i++) expect(hullGroup(hulls, GROUPED)).toEqual(once)
  // …and it does not depend on where she sits in a list of them.
  expect(hullGroup(hulls, GROUPED)).toEqual(hullGroup([...hulls], GROUPED))

  // AND THROUGH THE WHOLE MODEL: one merchant's mark is byte-identical whether she is alone on the
  // sea, first of a crowd, or last of a different crowd — including a crowd berthed at her own
  // roadstead, which is the case that broke the berth fan.
  // Read off the MAPPED rows: a merchant resting in port is not on the chart (owner, 2026-10-13),
  // but her berth and hull list are still worked out here for her card, and must not move either.
  const markOf = (rows: readonly TrafficFleet[], id: string) => {
    const t = mapTrafficOf(rows).find((r) => r.id === id)!
    const her = { at: t.kind === 'anchored' ? t.at : null, fleet: t }
    // HER HULL LIST AS WELL AS HER MARK. The group caps at three, so a neighbour that added a
    // fourth hull to her list would be invisible in the mark alone — and a list that moves with
    // the neighbours is the defect itself, whether this zoom happens to draw the difference.
    return { at: her.at, hulls: her.fleet.hulls, group: hullGroup(her.fleet.hulls ?? [], GROUPED) }
  }
  const her = dockedMerchant('m-her', 3)
  const alone = markOf([her], 'm-her')
  expect(markOf([dockedMerchant('m-a', 1), her], 'm-her')).toEqual(alone)
  expect(markOf([her, dockedMerchant('m-b', 2), dockedMerchant('m-c', 8)], 'm-her')).toEqual(alone)
  expect(markOf([dockedMerchant('m-c', 8), dockedMerchant('m-b', 2), her], 'm-her')).toEqual(alone)
  // and her group really is three hulls, so the equality above is not the equality of two blanks
  expect(alone.group).toHaveLength(3)
})

test('the group collapses to her flagship at a stated density, and the CLASS survives it', () => {
  // 0.115 °/px — 45° across a 390 px phone, which is `PORT_TIER_BANDS`' own boundary between "a
  // sea" and "the world" measured on the narrowest glass the UI promises. The count channel is
  // what multiplies the ink, so the count is what is given up.
  expect(HULL_GROUP_MAX_UNITS_PER_PX).toBeCloseTo(45 / 390, 10)

  const squadron: HullClass[] = ['nau', 'carlat', 'carlat']
  expect(hullGroup(squadron, HULL_GROUP_MAX_UNITS_PER_PX)).toHaveLength(3)
  const collapsed = hullGroup(squadron, PULLED_BACK)
  expect(collapsed).toHaveLength(1)
  // THE CLASS CHANNEL SURVIVES: a carrack is still a carrack-sized mark on the globe, which costs
  // one mark either way. Only "how many" is withheld.
  expect(collapsed[0].cls).toBe('nau')
  expect(collapsed[0].halfLength).toBe(hullHalfLengthOf('nau'))
  expect(collapsed[0]).toEqual({ cls: 'nau', halfLength: hullHalfLengthOf('nau'), dx: 0, dy: 0 })

  // A DENSITY AND NOT A SPAN, which is the whole reason it is this number and in these units: a
  // phone and a 1280 sheet looking at the SAME WATER are judged differently (1280 px of glass
  // really can hold three times the hulls), and looking at the same DENSITY they agree.
  const degPerPx = (spanDeg: number, glassPx: number) => spanDeg / glassPx
  expect(hullGroup(squadron, degPerPx(45, 390))).toHaveLength(3) // a sea, on a phone
  expect(hullGroup(squadron, degPerPx(60, 390))).toHaveLength(1) // the world, on a phone
  expect(hullGroup(squadron, degPerPx(60, 1280))).toHaveLength(3) // the same water, with the room
  expect(hullGroup(squadron, degPerPx(360, 1280))).toHaveLength(1) // the globe has no room either

  // A DEGENERATE SCALE IS NOT A LICENCE TO TRIPLE THE INK: an unmeasured surface draws one hull.
  expect(hullGroup(squadron, Number.NaN)).toHaveLength(1)
})

test('one halo per fleet, sized to the hulls drawn — and a lone hull keeps the old circle exactly', () => {
  // A SINGLE CLASS-LESS HULL gives back what was on the sheet before row 120, to the pixel.
  const before = hullGroupHalo(hullGroup([], GROUPED))
  expect(before).toEqual({ cx: 0, cy: 0, r: GLYPH.fleetHaloRadius })

  // AND IT HOLDS WHATEVER IS DRAWN. Every vertex of every hull in the group must lie inside the
  // one circle, or the halo would stop being the ground that keeps a hull legible over land.
  const encloses = (hulls: readonly (HullClass | null)[]) => {
    const marks = hullGroup(hulls, GROUPED)
    const halo = hullGroupHalo(marks)
    const outside = marks.flatMap((m: HullMark) =>
      vertices(hullPath(m.cls, m.halfLength))
        .map((p) => Math.hypot(m.dx + p.x - halo.cx, m.dy + p.y - halo.cy))
        .filter((d) => d > halo.r + 1e-9),
    )
    return { outside, halo, marks }
  }
  for (const hulls of [['barca'], ['nau'], ['nau', 'nau', 'nau'], ['barca', 'nau', 'carlat']] as HullClass[][]) {
    const { outside, marks } = encloses(hulls)
    expect(marks.length).toBe(hulls.length)
    expect(outside).toEqual([])
  }
  // ONE CIRCLE AND NOT THREE: the halo of a squadron is bigger than the halo of one hull of her,
  // and it has moved astern with the formation rather than staying on the flagship.
  const squadron = hullGroupHalo(hullGroup(['nau', 'nau', 'nau'], GROUPED))
  expect(squadron.r).toBeGreaterThan(hullGroupHalo(hullGroup(['nau'], GROUPED)).r)
  expect(squadron.cy).toBeGreaterThan(0)
  expect(squadron.cx).toBeCloseTo(0, 10)
})

// ── UNIT: THE WIRE ─────────────────────────────────────────────────────────────────────────────

const LIS: MapPort = {
  code: 'LIS', name: 'Lisbon', country: 'Portugal', lat: 38.7, lon: -9.14, sizeTier: 5, kind: 'HARBOUR',
  roadstead: { lat: 38.6, lon: -9.4 }, roadsteadNm: 12,
}

/** A docked merchant as `world.sea_traffic` serves her. `hulls` defaults to NO classes — the
 *  fallback the chart drew before 0102 carried them — so a caller that cares about the classes
 *  passes them, and one that cares only about the count does not have to invent any. */
function dockedMerchant(id: string, ships: number, hulls: readonly string[] = []): TrafficFleet {
  return {
    id, company: 'Casa da Prova', nation_code: 'PRT', ink: 'prt', name: `Prova ${id}`, status: 'DOCKED',
    ships, hulls: [...hulls], port: 'LIS', roadstead: [38.6, -9.4], anchor: null, voyage: null,
    next_lap_at: null,
    lane: null,
  }
}

function ship(name: string, cls: string, flagship = false, code?: string): FleetShip {
  return {
    id: `s-${name}`, name, class: cls, class_code: code, is_flagship: flagship, durability: 100, max_durability: 100,
    crew: 10, crew_required: 8, crew_max: 20, hold: 60, hold_rated: 60, speed: 5, speed_rated: 5,
    handling: 1, armour: 1, attack: 0, accuracy: 1, reach: 1, sighting: 1, fittings: [], slots: {},
    cabins: 1, cargo: {}, cargo_tuns: 0, water_t: 0, food_t: 0,
  }
}

function ownFleet(ships: readonly FleetShip[]): FleetView {
  return {
    id: 'own-1', name: 'Gaivota', status: 'DOCKED', version: 1, port: 'LIS', anchor: null, busy_until: null,
    speed_kn: 5, endurance_days: 20, free_hold: 60, cargo_basis: {},
    officer_pct: {} as FleetView['officer_pct'], voyage: null, ships: [...ships], queue: [],
  }
}

test('both reads always say how many hulls, and only one of them can say what they are', () => {
  // YOURS: `world.fleets` serves every ship's class CODE beside its name (`class_code`, 0124 —
  // world.ship_view), so the three codes the chain seeds resolve and the FLAGSHIP comes first
  // whatever order the server sent them in.
  const [mine] = mapFleetsOf([
    ownFleet([ship('Segunda', 'Caravela latina', false, 'carlat'), ship('Capitania', 'Nau / Carrack', true, 'nau'), ship('Terceira', 'Barca', false, 'barca')]),
  ])
  expect(mine.hulls).toEqual(['nau', 'carlat', 'barca'])

  // AN UNKNOWN CODE IS NULL AND NOT THE NEAREST GUESS — a fourth hull draws the class-less hull,
  // visibly saying nothing; and the NAME is never read for the class (a server older than 0124,
  // which serves no code, draws class-less hulls rather than guessing from ' BARCA ').
  const [odd] = mapFleetsOf([ownFleet([ship('Galeao', 'Galleon', true, 'galleon'), ship('Barca Velha', 'Barca', false, 'barca'), ship('Velha', 'Barca')])])
  expect(odd.hulls).toEqual([null, 'barca', null])

  // A FLEET WITH NO SHIPS SERVED still reaches the paper, as one class-less hull (`hullGroup([])`).
  const [bare] = mapFleetsOf([ownFleet([])])
  expect(bare.hulls).toEqual([])
  expect(hullGroup(bare.hulls ?? [], GROUPED)).toHaveLength(1)

  // THE MERCHANTS, AND WHAT CLOSED THE GAP. This test read "sea_traffic serves count(*) and NO
  // class, so her list is her count of class-less hulls" until 2026-10-11, when 0102 was re-cut to
  // serve `hulls` — one `ship_classes.code` per hull, flagship first. So a merchant's silhouettes
  // are now HERS, copied off the wire, and the class channel works for the whole world and not only
  // for the captain's own four fleets.
  const traffic = mapTrafficOf([
    dockedMerchant('m-1', 3, ['nau', 'carlat', 'barca']),
    dockedMerchant('m-2', 1, ['barca']),
  ])
  expect(traffic[0].hulls).toEqual(['nau', 'carlat', 'barca'])
  expect(traffic[1].hulls).toEqual(['barca'])
  expect(hullGroup(traffic[0].hulls ?? [], GROUPED)).toHaveLength(3)
  // A CODE THIS CHART DOES NOT KNOW draws the class-less hull rather than the nearest guess — the
  // same ruling `hullClassOfCode` keeps for your own fleets, and the reason a new class may ship on
  // the server before the chart has a silhouette for it.
  expect(mapTrafficOf([dockedMerchant('m-3', 2, ['galleon', 'nau'])])[0].hulls).toEqual([null, 'nau'])
  // AND THE FALLBACK IS STILL THERE AND STILL TRUE: a merchant served no list at all is her count
  // of class-less hulls, which is exactly what this chart drew for her before 0102.
  expect(mapTrafficOf([dockedMerchant('m-4', 3)])[0].hulls).toEqual([null, null, null])
  // and the model carries it through to the mark without the merchants touching anything of yours
  // …and resting in port, neither is drawn: RESTING MERCHANTS ARE NOT ON THE CHART (owner, 2026-10-13): a merchant in port is counted in her city's tray instead.
  const model = buildChartModel([], [LIS], [], null, traffic)
  expect(model.traffic).toHaveLength(0)
})

// ── UNIT: ONE RENDERER ────────────────────────────────────────────────────────────────────────

test('one renderer draws every hull on this chart — the merchants and your own fleets alike', async () => {
  const src = await (await import('node:fs/promises')).readFile('src/chart/FleetsLayer.tsx', 'utf8')
  // ONE path call site and ONE arrangement, composed twice — once per list. A second `hullPath` or
  // a second set of offsets in this file would be the copy docs/NO_SPAGHETTI.md §1 forbids: two
  // authorities for what a fleet's mark is, agreeing today.
  expect(src.match(/hullPath\(/g)).toHaveLength(1)
  expect(src.match(/<HullGroup/g)).toHaveLength(2)
  // The merchants' hooks are on the GROUP, so there is exactly one `map-merchant` element per
  // merchant however many hulls she sails — which is what every spec that asks for her box needs.
  expect(src).toMatch(/hooks=\{\{[\s\S]*?'data-testid': 'map-merchant'/)
  expect(src.match(/'data-merchant-id'/g)).toHaveLength(1)
})

// ── BROWSER ────────────────────────────────────────────────────────────────────────────────────

test.use({ viewport: PHONE })

/** Every merchant mark on the glass: how many hulls she draws, and how wide her whole mark is. */
async function hullsOnTheGlass(page: Page) {
  return page.evaluate(() => {
    const chart = document.querySelector('[data-testid="map-chart"]')!.getBoundingClientRect()
    const out: { id: string; hulls: number; paths: number; w: number; h: number }[] = []
    for (const g of document.querySelectorAll('[data-testid="map-merchant"]')) {
      const r = g.getBoundingClientRect()
      const cx = r.left + r.width / 2
      const cy = r.top + r.height / 2
      if (!(cx >= chart.left && cx <= chart.right && cy >= chart.top && cy <= chart.bottom)) continue
      out.push({
        id: g.getAttribute('data-merchant-id') ?? '',
        hulls: Number(g.getAttribute('data-hulls')),
        paths: g.querySelectorAll('path[data-hull-class]').length,
        w: r.width,
        h: r.height,
      })
    }
    return out
  })
}

test('the sea shows how many ships each merchant is, and lets go of it when pulled back', async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  mkdirSync(SHOTS, { recursive: true })
  await serveNpcOn(page)
  await page.goto('map')
  await ready(page)
  await expect.poll(async () => (await hullsOnTheGlass(page)).length, { timeout: 60_000 }).toBeGreaterThanOrEqual(2)

  for (const width of [390, 1280]) {
    await page.setViewportSize({ width, height: 844 })
    await page.waitForTimeout(400)
    // TWO MERCHANTS ON THIS GLASS ARE SET, NOT ASSUMED (2026-10-17, ./seaFrame.fixture.ts). A resize
    // keeps the view's centre and horizontal span, so the 1280 glass is a band 8.8° tall where the
    // phone's was 28.8°, and CI run 38917698523's band held ONE of the 13 merchants the phone drew —
    // drawn, correctly, for 60 s. Pulled back a press at a time instead, and never past the density
    // at which a group collapses to its flagship, because every claim below is about the group.
    await pullBackUntilMerchants(page, { maxUnitsPerPx: HULL_GROUP_MAX_UNITS_PER_PX })
    for (const theme of ['dark', 'light'] as const) {
      await page.evaluate((t) => document.documentElement.setAttribute('data-theme', t), theme)
      await page.waitForTimeout(200)

      // EVERY MARK DRAWS EXACTLY THE HULLS IT CLAIMS, and claims at least one: a merchant is never
      // an empty patch of sea, and the group is never a path that was dropped.
      // AT LEAST TWO, WAITED FOR, as the opening of this test waits for them (2026-10-16). The
      // merchants sail while the page is open, so how many hulls stand on the glass at one instant
      // is the sea's business: CI run 38780770200 caught a frame with one, two of them having
      // sailed off a 390 px glass since the opening poll. The claim below is still made of every
      // mark on a frame holding two or more — the frame is waited for, not assumed.
      let marks: Awaited<ReturnType<typeof hullsOnTheGlass>> = []
      await expect
        .poll(async () => (marks = await hullsOnTheGlass(page)).length, { timeout: 60_000 })
        .toBeGreaterThanOrEqual(2)
      for (const m of marks) {
        expect(m.hulls).toBeGreaterThanOrEqual(1)
        expect(m.hulls).toBeLessThanOrEqual(3)
        expect(m.paths).toBe(m.hulls)
        // And it is legible rather than a smudge: a mark is at least a hull ACROSS on a 390 px
        // phone and never a quarter of the glass.
        //
        // ACROSS HER LONGEST AXIS, not her width (corrected 2026-10-12). This read `m.w` and went
        // red at 3.762022 px on a frame that was perfectly correct: a barca is a SPINDLE, her beam
        // a third of her half-length by this file's own design note above, so 5.7 x 0.33 x 2 =
        // 3.762 is a lone barca measured across the beam while she is 11.4 px long — and which of
        // the two a bounding box reports is decided by HER HEADING. The old assertion therefore
        // held or failed on where a merchant happened to be pointing, and 0105's roster (76 fleets
        // to 761) was simply the first sea crowded enough to put a north-bound barca in the opening
        // frame. A hull's legibility is her longest dimension; the box's width is an accident of
        // the compass.
        const across = Math.max(m.w, m.h)
        expect(across).toBeGreaterThan(4)
        expect(across).toBeLessThan(width / 4)
      }
      // A MULTI-SHIP MERCHANT IS SEVERAL MARKS ABOUT ONE POINT — the whole of "two ships grouping".
      // The seeded roster has multi-ship fleets; if this frame happens to hold none, the claim is
      // not made rather than faked.
      const several = marks.filter((m) => m.hulls > 1)
      for (const m of several) expect(Math.max(m.w, m.h)).toBeGreaterThan(8)

      await page.screenshot({ path: path.join(SHOTS, `map-hulls-${width}-${theme}.png`) })
    }
  }

  // PULLED BACK PAST THE STATED DENSITY, EVERY GROUP ON THE SHEET LETS GO. Zoom out to the globe:
  // 0.115 °/px is crossed long before the last press, so no mark may still be drawing a squadron.
  await page.setViewportSize(PHONE)
  await page.evaluate(() => document.documentElement.setAttribute('data-theme', 'dark'))
  const out = page.getByLabel('Zoom out')
  for (let i = 0; i < 12; i++) await out.click()
  await page.waitForTimeout(600)
  const wide = await hullsOnTheGlass(page)
  expect(wide.length).toBeGreaterThanOrEqual(2)
  expect([...new Set(wide.map((m) => m.hulls))]).toEqual([1])
  await page.screenshot({ path: path.join(SHOTS, 'map-hulls-390-collapsed.png') })
})

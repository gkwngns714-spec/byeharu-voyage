import { test, expect } from '@playwright/test'
import { project, type Point } from '../src/lib/geo'
import { WIDE_SCALE } from '../src/chart/glyphs'
import { NAME_HIT_PAD_PX } from '../src/chart/placedNames'
import {
  buildChartModel,
  dotPorts,
  fitView,
  GLYPH,
  hitTest,
  LABEL_SPAN_LIMIT,
  mapFleetsOf,
  mapLabelRequests,
  mapPortsOf,
  minTierForSpan,
  openingBounds,
  planLabels,
  unitsPerPixel,
  viewBoxOf,
  visiblePorts,
} from '../src/chart'
import type { ChartModel } from '../src/chart/chartModel'
import { REAL_PORTS, dockedFleet } from './mapWorld.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A TAP ON "GIBRALTAR" OPENS GIBRALTAR (2026-11-15, the owner: at 1280 px a tap on Gibraltar opened Ceuta).
//
// The opening frame at 1280×800, the house at Lisbon, planned exactly as ChartCanvas plans it. Ceuta's mark stands 22 px
// under Gibraltar's, right below the start of the word "Gibraltar": a tap on the word's lower edge, a pixel or two outside
// the name's box, was nearer Ceuta's MARK than Gibraltar's and opened Ceuta. A drawn name now answers a few pixels past
// its letters (src/chart/placedNames.ts `NAME_HIT_PAD_PX`), the nearer name winning where two margins meet.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const PORTS = mapPortsOf(REAL_PORTS)
const MODEL = buildChartModel(mapFleetsOf([dockedFleet('house', 'House', 'LIS')]), PORTS)
const [W, H] = [1280, 800]

function frame() {
  const aspect = W / H
  const view = fitView(openingBounds(MODEL.focusPoints, MODEL.motionPoints, PORTS, aspect), aspect)
  const viewBox = viewBoxOf(view, aspect)
  const upp = unitsPerPixel(view, W)
  const minTier = minTierForSpan(viewBox.width)
  const named = visiblePorts(PORTS, MODEL.portRoles, viewBox, minTier)
  const dots = dotPorts(PORTS, MODEL.portRoles, viewBox, minTier)
  const flags = new Map(PORTS.map((p) => [p.code, 'GBR']))
  const placed = planLabels(mapLabelRequests(MODEL, named, null, viewBox.width <= LABEL_SPAN_LIMIT, flags), {
    viewBox,
    unitsPerPx: upp,
    fontSizePx: GLYPH.labelSize,
    gapPx: GLYPH.labelGapX,
    glyphRadiusPx: GLYPH.fleetHaloRadius,
    centredOnMark: upp > WIDE_SCALE.fromUnitsPerPx,
  })
  // what LabelsLayer hands the map's tap (src/chart/placedNames.ts `setPlacedNames`)
  const names = placed.filter((l) => l.id.startsWith('port:')).map((l) => ({ code: l.id.slice(5), box: l.box, pad: NAME_HIT_PAD_PX * upp }))
  const tap = (at: Point, traffic: ChartModel['traffic'] = []) => {
    const hit = hitTest(MODEL, named, at, GLYPH.hitRadius * upp, dots, GLYPH.dotHitRadius * upp, traffic, names)
    return hit?.kind === 'port' ? hit.code : hit
  }
  return { upp, placed, named, tap }
}

test('at 1280×800 a tap on Gibraltar — its mark, its word, the word\'s lower edge — opens Gibraltar, and Ceuta stays Ceuta', () => {
  const { upp, placed, named, tap } = frame()
  const gib = project(PORTS.find((p) => p.code === 'GIB')!)
  const ceu = project(PORTS.find((p) => p.code === 'CEU')!)
  expect(named.map((p) => p.code), 'both harbours wear their full mark on the opening frame').toEqual(expect.arrayContaining(['GIB', 'CEU']))
  const word = placed.find((l) => l.id === 'port:GIB')
  expect(word, 'Gibraltar is named on the opening frame').toBeDefined()
  const box = word!.box

  // the precondition that made the bug: under the start of the word, Ceuta's mark is nearer than Gibraltar's
  const underWord: Point = { x: box.x + 10 * upp, y: box.y + box.height + 2 * upp }
  expect(Math.hypot(underWord.x - ceu.x, underWord.y - ceu.y), 'Ceuta\'s mark is the nearer mark under the word').toBeLessThan(
    Math.hypot(underWord.x - gib.x, underWord.y - gib.y),
  )

  expect(tap(gib), 'the mark').toBe('GIB')
  expect(tap({ x: box.x + box.width / 2, y: box.y + box.height / 2 }), 'the word').toBe('GIB')
  expect(tap({ x: box.x + 2 * upp, y: box.y + box.height - upp }), 'the word\'s first letters').toBe('GIB')
  expect(tap(underWord), 'just under the word').toBe('GIB')
  expect(tap({ x: box.x + box.width / 2, y: box.y + box.height + 2 * upp }), 'just under the middle of the word').toBe('GIB')
  // and the margin takes nothing from the neighbour: Ceuta's own mark and word still open Ceuta
  expect(tap(ceu), 'Ceuta\'s mark').toBe('CEU')
  const ceuWord = placed.find((l) => l.id === 'port:CEU')
  if (ceuWord) expect(tap({ x: ceuWord.box.x + ceuWord.box.width / 2, y: ceuWord.box.y + ceuWord.box.height / 2 }), 'Ceuta\'s word').toBe('CEU')
})

// THE MARGIN SETTLES A NAME AGAINST ANOTHER HARBOUR'S MARK, NOT AGAINST A HULL (2026-11-16). With the margin, a cargo ship lying
// just past the end of a word could not be pressed at any zoom: tests/battle.live.spec.ts presses one a few miles out of Seville
// and got Seville, from the day the margin came. On the letters the name still wins.
test("a merchant under the thumb in a name's margin is the merchant; on the letters, and with no hull there, it is still the name", () => {
  const { upp, placed, tap } = frame()
  const box = placed.find((l) => l.id === 'port:GIB')!.box
  const underWord: Point = { x: box.x + 10 * upp, y: box.y + box.height + 2 * upp }
  const hullAt = (at: Point, id: string) =>
    ({ fleet: { id }, at: { lat: -at.y, lon: at.x }, merchant: { docked: false, berthCode: null } }) as unknown as ChartModel['traffic'][number]
  expect(project({ lat: -underWord.y, lon: underWord.x }), 'the probe hull stands where it is put').toEqual(underWord)
  expect(tap(underWord), 'no hull: the margin is the name').toBe('GIB')
  expect(tap(underWord, [hullAt(underWord, 'm1')]), 'a hull under the thumb, in the margin').toEqual({ kind: 'merchant', id: 'm1' })
  // a hull that is near but not under the thumb (over half a touch off) leaves the margin to the name
  const off: Point = { x: underWord.x, y: underWord.y + (GLYPH.dotHitRadius + 4) * upp }
  expect(tap(underWord, [hullAt(off, 'm2')]), 'a hull over half a touch away').toBe('GIB')
  // on the letters' own box the name wins, a hull under the thumb or not
  const onWord: Point = { x: box.x + box.width / 2, y: box.y + box.height / 2 }
  expect(tap(onWord, [hullAt(onWord, 'm3')]), 'on the letters').toBe('GIB')
})

// A WORD OVER A NEIGHBOUR'S MARK (2026-11-16). At 44 % on a phone "Santa Cruz de Tenerife" is set under Las Palmas's mark, and a press on
// that mark opened Tenerife (tests/map.routebuilder.spec.ts). The mark dead under the thumb is its own harbour; the rest of the word is the name.
test("a press on a harbour's own mark is that harbour even where another harbour's name runs across it", () => {
  const { upp, named } = frame()
  const ceu = project(PORTS.find((p) => p.code === 'CEU')!)
  // a word of Gibraltar's laid right across Ceuta's mark
  const across = [{ code: 'GIB', box: { x: ceu.x - 40 * upp, y: ceu.y - 8 * upp, width: 80 * upp, height: 16 * upp }, pad: NAME_HIT_PAD_PX * upp }]
  const tap = (at: Point) => {
    const hit = hitTest(MODEL, named, at, GLYPH.hitRadius * upp, [], GLYPH.dotHitRadius * upp, [], across)
    return hit?.kind === 'port' ? hit.code : hit
  }
  expect(tap(ceu), 'on the mark').toBe('CEU')
  expect(tap({ x: ceu.x + 3 * upp, y: ceu.y - 2 * upp }), 'within the mark').toBe('CEU')
  expect(tap({ x: ceu.x + 20 * upp, y: ceu.y }), 'along the word, off the mark').toBe('GIB')
  expect(tap({ x: ceu.x - 30 * upp, y: ceu.y + 4 * upp }), 'the word\'s other end').toBe('GIB')
})

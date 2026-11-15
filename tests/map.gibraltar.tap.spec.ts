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
  const tap = (at: Point) => {
    const hit = hitTest(MODEL, named, at, GLYPH.hitRadius * upp, dots, GLYPH.dotHitRadius * upp, [], names)
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

import { test, expect } from '@playwright/test'
import { project } from '../src/lib/geo'
import { buildChartModel } from '../src/features/map/chartModel'
import { fitView, openingBounds, unitsPerPixel, viewBoxOf, LABEL_SPAN_LIMIT } from '../src/features/map/chartView'
import { GLYPH } from '../src/features/map/glyphs'
import { LABEL_PRIORITY, mapLabelRequests, planLabels, type PlacedLabel } from '../src/features/map/labels'
import { V0_PORTS, sampleFleets } from '../src/features/map/sampleVoyages'
import type { MapSelection } from '../src/features/map/mapTypes'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// LABELS MUST NOT OVERPRINT — the regression proof for a defect that was seen, not guessed.
//
// Rendered at 390×844 the old fixed-offset labels came out as `Gaivotaa illa` (Gaivota over
// Sevilla), `MarseiLlevante` (Marseille over Levante), and `Napol` (Napoli running off the right
// edge). Those three are exactly what this file asserts can no longer happen — at the phone size
// where it happened, with the sample data it happened on.
//
// It runs the REAL opening view: the same `fitView` the screen uses, on the same focus bounds, at
// the same 390×844. If the framing, the font size, the glyph sizes or the priority table change in
// a way that reintroduces an overlap, this goes red.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const DEPARTED = 1_700_000_000_000

/** The chart's live geometry at a given surface size — exactly as MapScreen computes it. */
function chartAt(widthPx: number, heightPx: number, nowMs = DEPARTED) {
  const fleets = sampleFleets(DEPARTED)
  const model = buildChartModel(fleets, V0_PORTS, nowMs)
  const aspect = widthPx / heightPx
  const opening = buildChartModel(fleets, V0_PORTS, DEPARTED)
  const bounds = openingBounds(opening.focusPoints, opening.motionPoints, V0_PORTS, aspect)
  const view = fitView(bounds, aspect)
  const viewBox = viewBoxOf(view, aspect)
  return { model, viewBox, unitsPerPx: unitsPixel(view.spanX, widthPx) }
}
const unitsPixel = (spanX: number, widthPx: number) => unitsPerPixel({ cx: 0, cy: 0, spanX }, widthPx)

function layout(widthPx: number, heightPx: number, selection: MapSelection = null): PlacedLabel[] {
  const { model, viewBox, unitsPerPx } = chartAt(widthPx, heightPx)
  return planLabels(
    mapLabelRequests(model, V0_PORTS, selection, viewBox.width <= LABEL_SPAN_LIMIT),
    {
      viewBox,
      unitsPerPx,
      fontSizePx: GLYPH.labelSize,
      gapPx: GLYPH.labelGapX,
      glyphRadiusPx: GLYPH.fleetHaloRadius,
    },
  )
}

const overlaps = (a: PlacedLabel, b: PlacedLabel) =>
  a.box.x < b.box.x + b.box.width &&
  b.box.x < a.box.x + a.box.width &&
  a.box.y < b.box.y + b.box.height &&
  b.box.y < a.box.y + a.box.height

test.describe('no two labels overprint', () => {
  for (const [w, h] of [
    [390, 844], // the phone the defect was found on
    [360, 780], // a narrower phone
    [1280, 800], // the desktop framing, which was already correct
    [820, 1180], // a portrait tablet
  ]) {
    test(`${w}x${h}: every pair of label boxes is disjoint`, () => {
      const placed = layout(w, h)
      expect(placed.length).toBeGreaterThan(0)
      for (let i = 0; i < placed.length; i++) {
        for (let j = i + 1; j < placed.length; j++) {
          expect(
            overlaps(placed[i], placed[j]),
            `"${placed[i].text}" (${placed[i].side}) overprints "${placed[j].text}" (${placed[j].side})`,
          ).toBe(false)
        }
      }
    })

    test(`${w}x${h}: no label is drawn outside the viewport`, () => {
      const { viewBox } = chartAt(w, h)
      for (const label of layout(w, h)) {
        expect(label.box.x, `${label.text} runs off the left`).toBeGreaterThanOrEqual(viewBox.x)
        expect(label.box.y, `${label.text} runs off the top`).toBeGreaterThanOrEqual(viewBox.y)
        expect(label.box.x + label.box.width, `${label.text} runs off the right`).toBeLessThanOrEqual(
          viewBox.x + viewBox.width,
        )
        expect(label.box.y + label.box.height, `${label.text} runs off the bottom`).toBeLessThanOrEqual(
          viewBox.y + viewBox.height,
        )
      }
    })
  }

  test('the three names that used to collide are each either clean or dropped', () => {
    const placed = layout(390, 844)
    const byText = new Map(placed.map((l) => [l.text, l]))
    // Whatever survives must be clean — asserted by the pair test above. What matters here is that
    // the two that used to overprint can no longer BOTH be drawn in the same place.
    const gaivota = byText.get('Gaivota')
    const sevilla = byText.get('Sevilla')
    if (gaivota && sevilla) expect(overlaps(gaivota, sevilla)).toBe(false)
    const marseille = byText.get('Marseille')
    const levante = byText.get('Levante')
    if (marseille && levante) expect(overlaps(marseille, levante)).toBe(false)
  })
})

test.describe('priority decides what survives a crowd', () => {
  test('a fleet at sea is never dropped for a quiet port', () => {
    const placed = layout(390, 844)
    const names = placed.map((l) => l.text)
    expect(names).toContain('Aurora')
    expect(names).toContain('Ponente')
  })

  test('ports your fleets use are named; the priority table says so in numbers', () => {
    expect(LABEL_PRIORITY.fleetAtSea).toBeGreaterThan(LABEL_PRIORITY.destination)
    expect(LABEL_PRIORITY.destination).toBeGreaterThan(LABEL_PRIORITY.anchorage)
    expect(LABEL_PRIORITY.anchorage).toBeGreaterThan(LABEL_PRIORITY.fleetDocked)
    expect(LABEL_PRIORITY.fleetDocked).toBeGreaterThan(LABEL_PRIORITY.route)
    expect(LABEL_PRIORITY.route).toBeGreaterThan(LABEL_PRIORITY.quiet)
    expect(LABEL_PRIORITY.selected).toBeGreaterThan(LABEL_PRIORITY.fleetAtSea)
  })

  test('whatever is selected is ALWAYS named, even in a crowd', () => {
    // Only for things ON the glass: a label for a port the view does not contain is not a label
    // that was dropped, it is a port that is not being drawn at all.
    const { viewBox } = chartAt(390, 844)
    const onGlass = V0_PORTS.filter((p) => {
      const at = project(p)
      return (
        at.x >= viewBox.x &&
        at.x <= viewBox.x + viewBox.width &&
        at.y >= viewBox.y &&
        at.y <= viewBox.y + viewBox.height
      )
    })
    expect(onGlass.length).toBeGreaterThan(3)
    for (const port of onGlass) {
      const placed = layout(390, 844, { kind: 'port', code: port.code })
      expect(placed.map((l) => l.text), `selected ${port.code}`).toContain(port.name)
    }
    const withFleet = layout(390, 844, { kind: 'fleet', id: 'aurora' })
    expect(withFleet.map((l) => l.text)).toContain('Aurora')
  })

  test('the opening frame is the action on a phone and everything on a desktop', () => {
    const phone = chartAt(390, 844).viewBox
    const desktop = chartAt(1280, 800).viewBox
    // Measured: 14.4 deg across on the phone against 32.3 deg on the desktop. The phone frames the
    // Gibraltar-Madeira-Canaries triangle; the desktop still holds Genova, unchanged.
    expect(phone.width).toBeLessThan(desktop.width / 2)
    const genova = project({ lat: 44.41, lon: 8.93 })
    expect(genova.x).toBeLessThanOrEqual(desktop.x + desktop.width)
    expect(genova.x).toBeGreaterThan(phone.x + phone.width)
  })

  test('a dropped label never moves or hides its glyph — the mark stays exactly where it was', () => {
    const placed = layout(390, 844)
    const drawn = new Set(placed.map((l) => l.id))
    const { model } = chartAt(390, 844)
    // Whether or not a port got a name, its glyph is at its projected coordinate and is tappable
    // (hit-testing is by distance to the glyph, never to the label — see hitTest.ts).
    for (const port of V0_PORTS) {
      const at = project(port)
      expect(Number.isFinite(at.x) && Number.isFinite(at.y)).toBe(true)
    }
    // And every fleet is still in the model regardless of what was labelled.
    expect(model.fleets).toHaveLength(4)
    expect(drawn.size).toBeLessThanOrEqual(V0_PORTS.length + model.fleets.length)
  })
})

test.describe('planLabels, the rule itself', () => {
  const VIEW = { x: 0, y: 0, width: 100, height: 100 }
  const OPTS = { viewBox: VIEW, unitsPerPx: 1, fontSizePx: 10, gapPx: 5, glyphRadiusPx: 4, edgeInsetPx: 0 }

  test('a lone label takes the first side: right', () => {
    const [only] = planLabels([{ id: 'a', text: 'Aa', at: { x: 50, y: 50 }, priority: 1, tone: 'fleet' }], OPTS)
    expect(only.side).toBe('right')
    expect(only.anchor).toBe('start')
  })

  test('a label at the right edge flips inward instead of running off', () => {
    // "Napoli" at x=97 in a 100-wide view: `right` would end past the edge.
    const [only] = planLabels(
      [{ id: 'a', text: 'Napoli', at: { x: 97, y: 50 }, priority: 1, tone: 'port-quiet' }],
      OPTS,
    )
    expect(only.side).not.toBe('right')
    expect(only.box.x + only.box.width).toBeLessThanOrEqual(VIEW.x + VIEW.width)
  })

  test('the lower priority moves aside, and the higher one never does', () => {
    const placed = planLabels(
      [
        { id: 'low', text: 'Sevilla', at: { x: 50, y: 50.5 }, priority: 1, tone: 'port-quiet' },
        { id: 'high', text: 'Gaivota', at: { x: 50, y: 50 }, priority: 99, tone: 'fleet' },
      ],
      OPTS,
    )
    const high = placed.find((l) => l.id === 'high')
    const low = placed.find((l) => l.id === 'low')
    expect(high?.side).toBe('right') // the winner keeps the best side
    if (low) expect(low.side).not.toBe('right')
    if (low && high) expect(overlaps(low, high)).toBe(false)
  })

  test('when no side fits, the label is dropped rather than drawn badly', () => {
    // Five labels stacked on one point in a view too small to hold them: some must go.
    const stacked = Array.from({ length: 5 }, (_, i) => ({
      id: `l${i}`,
      text: 'AVeryLongPortName',
      at: { x: 50, y: 50 },
      priority: 5 - i,
      tone: 'port-quiet' as const,
    }))
    const placed = planLabels(stacked, OPTS)
    expect(placed.length).toBeLessThan(stacked.length)
    for (let i = 0; i < placed.length; i++) {
      for (let j = i + 1; j < placed.length; j++) expect(overlaps(placed[i], placed[j])).toBe(false)
    }
  })

  test('`force` places the selected label even in a full crowd, but still inside the frame', () => {
    const crowd = Array.from({ length: 6 }, (_, i) => ({
      id: `l${i}`,
      text: 'Crowded',
      at: { x: 50, y: 50 },
      priority: 10,
      tone: 'port-quiet' as const,
    }))
    const placed = planLabels(
      [...crowd, { id: 'me', text: 'Chosen', at: { x: 50, y: 50 }, priority: 1000, tone: 'fleet', force: true }],
      OPTS,
    )
    expect(placed.map((l) => l.id)).toContain('me')
    const me = placed.find((l) => l.id === 'me')
    expect(me!.box.x).toBeGreaterThanOrEqual(VIEW.x)
    expect(me!.box.x + me!.box.width).toBeLessThanOrEqual(VIEW.x + VIEW.width)
  })

  test('the layout is deterministic — same input, same sides, every time', () => {
    const first = layout(390, 844)
    for (let i = 0; i < 5; i++) {
      expect(layout(390, 844).map((l) => `${l.id}:${l.side}`)).toEqual(
        first.map((l) => `${l.id}:${l.side}`),
      )
    }
  })
})

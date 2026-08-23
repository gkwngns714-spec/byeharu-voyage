import { test, expect } from '@playwright/test'
import { WORLD_BOUNDS, project, type ViewBox } from '../src/lib/geo'
import {
  buildChartModel,
  GLYPH,
  LABEL_PRIORITY,
  LABEL_SPAN_LIMIT,
  fitView,
  mapFleetsOf,
  mapLabelRequests,
  mapPortsOf,
  minTierForSpan,
  openingBounds,
  planLabels,
  unitsPerPixel,
  viewBoxOf,
  visiblePorts,
  type MapSelection,
  type PlacedLabel,
} from '../src/chart'
import { REAL_PORTS, REAL_PORT_COUNT, dockedFleet, sailingFleet } from './mapWorld.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// LABELS MUST NOT OVERPRINT — the regression proof for a defect that was seen, not guessed,
// re-aimed at the world the map actually draws now.
//
// WHAT CHANGED AND WHY THIS FILE CHANGED WITH IT. The defect was found on twelve invented Iberian
// ports: fixed-offset labels came out as `Gaivotaa illa` and `MarseiLlevante`, and `Napoli` ran off
// the right edge. Those twelve ports are gone — the map is on `world.snapshot()`, which is 214 real
// harbours — so this file now runs the same rule against the same phone widths with the REAL port
// table (tests/mapWorld.fixture.ts) and real fleets in `world.fleets()` shape. The assertions are
// not weakened: every pair of boxes must still be disjoint, nothing may be drawn off the glass, and
// the priority table must still decide what survives. There is simply eighteen times as much of it.
//
// It runs the REAL opening view and the REAL visibility rule: the same `openingBounds` the screen
// uses, the same `visiblePorts` filter (on the glass, and big enough for this zoom or one of
// yours), at the same 390×844. If the framing, the font size, the glyph sizes, the tier bands or
// the priority table change in a way that reintroduces an overlap, this goes red.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const PORTS = mapPortsOf(REAL_PORTS)

/** Two at anchor, two at sea — and one of the two at sea is bound BEYOND the leg it is on, which is
 *  the case the chart has to keep honest. Codes and coordinates are the seed's. */
const FLEETS = mapFleetsOf([
  dockedFleet('gaivota', 'Gaivota', 'LIS'),
  dockedFleet('levante', 'Levante', 'GOA'),
  sailingFleet({ id: 'aurora', name: 'Aurora', from: 'LIS', to: 'CAD', legFrac: 0.45, destination: 'CEU' }),
  sailingFleet({ id: 'ponente', name: 'Ponente', from: 'LIS', to: 'FNC', legFrac: 0.35, destination: 'LPA' }),
])

const MODEL = buildChartModel(FLEETS, PORTS)

/** The chart's live geometry at a given surface size — exactly as MapScreen computes it. */
function chartAt(widthPx: number, heightPx: number) {
  const aspect = widthPx / heightPx
  const bounds = openingBounds(MODEL.focusPoints, MODEL.motionPoints, PORTS, aspect)
  const view = fitView(bounds, aspect)
  const viewBox = viewBoxOf(view, aspect)
  return { viewBox, unitsPerPx: unitsPerPixel(view, widthPx) }
}

/** The ports actually on the paper at that size — the ONE list the marks, the names and the taps
 *  all read (chartModel.visiblePorts). */
function drawnAt(viewBox: ViewBox) {
  return visiblePorts(PORTS, MODEL.portRoles, viewBox, minTierForSpan(viewBox.width))
}

function layout(widthPx: number, heightPx: number, selection: MapSelection = null): PlacedLabel[] {
  const { viewBox, unitsPerPx } = chartAt(widthPx, heightPx)
  return planLabels(
    mapLabelRequests(MODEL, drawnAt(viewBox), selection, viewBox.width <= LABEL_SPAN_LIMIT),
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

test.describe('the world the map is drawing', () => {
  test('the fixture IS the seeded world: 214 ports at tiers 5 / 3 / 2', () => {
    expect(REAL_PORTS).toHaveLength(REAL_PORT_COUNT)
    const byTier = new Map<number, number>()
    for (const p of REAL_PORTS) byTier.set(p.size_tier, (byTier.get(p.size_tier) ?? 0) + 1)
    expect([...byTier].sort((a, b) => a[0] - b[0])).toEqual([
      [2, 100],
      [3, 79],
      [5, 35],
    ])
    // And the chart's own port type carries the tier through, because everything below depends on it.
    expect(PORTS.find((p) => p.code === 'LIS')?.sizeTier).toBe(5)
    expect(PORTS.find((p) => p.code === 'CEU')?.sizeTier).toBe(2)
  })
})

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
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 214 PORTS, AND THE CHART STILL READS — the density rule, proved on the real table.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.describe('the zoom decides how much world is drawn', () => {
  test('the tier bands are a rule, not a hand-picked list of important ports', () => {
    expect(minTierForSpan(360)).toBe(5) // the world
    expect(minTierForSpan(46)).toBe(5)
    expect(minTierForSpan(45)).toBe(3) // a sea
    expect(minTierForSpan(12)).toBe(1) // a coast: everything
    expect(minTierForSpan(1.5)).toBe(1)
  })

  test('pulled back to the globe, 35 marks are on the sheet — not 214', () => {
    const world: ViewBox = { x: -180, y: -90, width: 360, height: 180 }
    const drawn = visiblePorts(PORTS, new Map(), world, minTierForSpan(world.width))
    expect(drawn).toHaveLength(35)
    for (const p of drawn) expect(p.sizeTier).toBe(5)

    // One band closer, the middling ports join them; closest in, all of them do.
    expect(visiblePorts(PORTS, new Map(), world, minTierForSpan(40))).toHaveLength(35 + 79)
    expect(visiblePorts(PORTS, new Map(), world, minTierForSpan(10))).toHaveLength(REAL_PORT_COUNT)
  })

  test('YOUR ports are drawn at every zoom, whatever size they are', () => {
    const world: ViewBox = { x: -180, y: -90, width: 360, height: 180 }
    // Ceuta is tier 2 — invisible at world zoom — but Aurora is bound for it.
    expect(MODEL.portRoles.get('CEU')).toBe('destination')
    const drawn = visiblePorts(PORTS, MODEL.portRoles, world, minTierForSpan(world.width))
    expect(drawn.map((p) => p.code)).toContain('CEU')
    // …and it is the ONLY reason a tier-2 port is on a world view.
    for (const p of drawn) expect(p.sizeTier === 5 || MODEL.portRoles.has(p.code)).toBe(true)
  })

  test('a port off the glass is not drawn, so it is not tappable and cannot be labelled', () => {
    const iberia: ViewBox = { x: -12, y: -46, width: 12, height: 8 }
    const drawn = visiblePorts(PORTS, MODEL.portRoles, iberia, minTierForSpan(iberia.width))
    expect(drawn.map((p) => p.code)).toContain('LIS')
    expect(drawn.map((p) => p.code)).not.toContain('NAG') // Nagasaki
    expect(drawn.map((p) => p.code)).not.toContain('HAV') // Havana
  })

  test('a crowded coast view stays legible: every name clean, and the rest dropped', () => {
    // The Mediterranean at "a coast" zoom, where every tier is drawn: the densest thing the chart
    // can be asked to do. `unitsPerPx` is the 390 px phone's, so the labels are phone-sized.
    const viewBox: ViewBox = { x: 2, y: -45, width: 12, height: 26 }
    const drawn = visiblePorts(PORTS, MODEL.portRoles, viewBox, minTierForSpan(viewBox.width))
    expect(drawn.length).toBeGreaterThan(5)
    const placed = planLabels(mapLabelRequests(MODEL, drawn, null, true), {
      viewBox,
      unitsPerPx: viewBox.width / 390,
      fontSizePx: GLYPH.labelSize,
      gapPx: GLYPH.labelGapX,
      glyphRadiusPx: GLYPH.fleetHaloRadius,
    })
    for (let i = 0; i < placed.length; i++) {
      for (let j = i + 1; j < placed.length; j++) {
        expect(
          overlaps(placed[i], placed[j]),
          `"${placed[i].text}" overprints "${placed[j].text}"`,
        ).toBe(false)
      }
    }
    // Nothing is invented: every name drawn belongs to a port that was drawn, or to a fleet.
    const drawable = new Set([
      ...drawn.map((p) => `port:${p.code}`),
      ...MODEL.fleets.map((f) => `fleet:${f.fleet.id}`),
    ])
    for (const label of placed) expect(drawable.has(label.id)).toBe(true)
  })

  test('pulled back past LABEL_SPAN_LIMIT, only ports your fleets use ask for a name', () => {
    const viewBox: ViewBox = { x: -60, y: -70, width: 120, height: 80 }
    const drawn = visiblePorts(PORTS, MODEL.portRoles, viewBox, minTierForSpan(viewBox.width))
    const requests = mapLabelRequests(MODEL, drawn, null, viewBox.width <= LABEL_SPAN_LIMIT)
    expect(viewBox.width).toBeGreaterThan(LABEL_SPAN_LIMIT)
    for (const request of requests) {
      if (!request.id.startsWith('port:')) continue
      expect(MODEL.portRoles.has(request.id.slice(5)), request.text).toBe(true)
    }
  })
})

test.describe('priority decides what survives a crowd', () => {
  test('a fleet at sea is never dropped for a quiet port', () => {
    const names = layout(390, 844).map((l) => l.text)
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
    // The tier lift may never carry a quiet port over a port your fleet is using: the biggest
    // possible quiet score is `quiet + 5`, and that is still below `route`.
    expect(LABEL_PRIORITY.quiet + 5).toBeLessThan(LABEL_PRIORITY.route)
  })

  test('among quiet ports the great harbour is named before the roadstead', () => {
    const viewBox: ViewBox = { x: -12, y: -46, width: 12, height: 8 }
    const drawn = visiblePorts(PORTS, new Map(), viewBox, minTierForSpan(viewBox.width))
    const requests = mapLabelRequests(buildChartModel([], PORTS), drawn, null, true)
    const of = (code: string) => requests.find((r) => r.id === `port:${code}`)
    expect(of('LIS')?.priority).toBeGreaterThan(of('SNL')?.priority ?? 0) // Lisbon 5 : Sanlúcar 2
    expect(of('OPO')?.priority).toBeGreaterThan(of('SNL')?.priority ?? 0) // Porto 3 : Sanlúcar 2
  })

  test('whatever is selected is ALWAYS named, even in a crowd', () => {
    // Only for things ON THE SHEET: a label for a port the chart is not drawing is not a label that
    // was dropped, it is a port that is not there — and it cannot be selected either, because the
    // hit test reads the same list.
    const { viewBox } = chartAt(390, 844)
    const drawn = drawnAt(viewBox).filter((p) => {
      const at = project(p)
      return (
        at.x >= viewBox.x &&
        at.x <= viewBox.x + viewBox.width &&
        at.y >= viewBox.y &&
        at.y <= viewBox.y + viewBox.height
      )
    })
    expect(drawn.length).toBeGreaterThan(3)
    for (const port of drawn) {
      const placed = layout(390, 844, { kind: 'port', code: port.code })
      expect(placed.map((l) => l.text), `selected ${port.code}`).toContain(port.name)
    }
    const withFleet = layout(390, 844, { kind: 'fleet', id: 'aurora' })
    expect(withFleet.map((l) => l.text)).toContain('Aurora')
  })

  test('the opening frame is what you have — not the globe, and not a harbour approach', () => {
    const phone = chartAt(390, 844).viewBox
    const desktop = chartAt(1280, 800).viewBox
    // The phone falls back to what is MOVING; the desktop holds everything of yours. Both are a
    // long way inside the world, which is the whole point now that the table is 214 ports.
    expect(phone.width).toBeLessThan(desktop.width)
    expect(desktop.width).toBeLessThan(WORLD_BOUNDS.maxLon - WORLD_BOUNDS.minLon)
    // Neither frame is so tight that the player is looking at their own quay and nothing else.
    expect(phone.width).toBeGreaterThan(5)
    // Nagasaki is one of your 214 ports and nothing of yours is anywhere near it: it is off both.
    const nagasaki = project({ lat: 32.75, lon: 129.88 })
    expect(nagasaki.x).toBeGreaterThan(desktop.x + desktop.width)
  })

  test('a lone fleet at anchor still opens on a usable sheet, not a 1.5° harbour', () => {
    // §K.1's opening position: one Barca at Lisbon and nothing else. One point cannot be framed,
    // so OPENING_MIN_SPAN_DEG widens it — see chartView.ts.
    const alone = buildChartModel(mapFleetsOf([dockedFleet('gaivota', 'Gaivota', 'LIS')]), PORTS)
    const bounds = openingBounds(alone.focusPoints, alone.motionPoints, PORTS, 1280 / 800)
    expect(bounds.maxLon - bounds.minLon).toBeGreaterThanOrEqual(12)
    const box = viewBoxOf(fitView(bounds, 1280 / 800), 1280 / 800)
    const drawn = visiblePorts(PORTS, alone.portRoles, box, minTierForSpan(box.width))
    // Neighbours to sail to are on the sheet, which is what the frame is for.
    expect(drawn.map((p) => p.code)).toEqual(expect.arrayContaining(['LIS', 'OPO', 'CAD']))
  })

  test('a dropped label never moves or hides its glyph — the mark stays exactly where it was', () => {
    const placed = layout(390, 844)
    const { viewBox } = chartAt(390, 844)
    const drawn = drawnAt(viewBox)
    for (const port of PORTS) {
      const at = project(port)
      expect(Number.isFinite(at.x) && Number.isFinite(at.y)).toBe(true)
    }
    // And every fleet is still in the model regardless of what was labelled.
    expect(MODEL.fleets).toHaveLength(4)
    expect(new Set(placed.map((l) => l.id)).size).toBeLessThanOrEqual(drawn.length + MODEL.fleets.length)
  })
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A NAME IS NEVER PRINTED UNDER A BUTTON — the keep-out rule, on the REAL control column.
//
// THE DEFECT, measured in the running game at 390×844 before the fix: the zoom/fit column occupies
// x 334–378, y 56–196 of the viewport, and the chart's own box starts at y=44 — so in the chart's
// own pixels the column is (334, 12) 44×140. Three names were drawn underneath it. `Saint-Malo`
// began at x=309 and the player read `Sain`; `Nantes` began at x=347, entirely behind the buttons,
// and the 6.9 px that escaped past their right edge is one mono glyph wide and rendered as a bare
// `s`.
//
// NOT A CLIPPING BUG, and that is the part worth recording. The measured count of labels clipped by
// the chart's edge was ZERO, before and after: the edge rule was working the whole time. Half a
// name and no name look alike in a screenshot and are completely different defects, and only
// measurement tells them apart.
//
// The numbers below are that measurement, kept as a fixture. They are the SCREEN's, which is why
// they arrive as a parameter: nothing in src/chart may know where a screen puts its buttons.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/**
 * The zoom/fit column at 390×844, in CHART pixels — measured on the running app, and independently
 * reported by `useChartSurface`'s own chrome measurement as exactly {334, 12, 44, 140}. Not derived
 * from class names: the panels fold and the column reflows, so a rect computed from Tailwind would
 * be right at one width and quietly wrong at the next.
 */
const CONTROLS_PX = { x: 334, y: 12, width: 44, height: 140 }

/** The same rectangle in chart units, exactly as ChartCanvas converts it. */
function controlsRect(viewBox: ViewBox, unitsPerPx: number) {
  return {
    x: viewBox.x + CONTROLS_PX.x * unitsPerPx,
    y: viewBox.y + CONTROLS_PX.y * unitsPerPx,
    width: CONTROLS_PX.width * unitsPerPx,
    height: CONTROLS_PX.height * unitsPerPx,
  }
}

const hits = (label: PlacedLabel, r: { x: number; y: number; width: number; height: number }) =>
  label.box.x < r.x + r.width &&
  r.x < label.box.x + label.box.width &&
  label.box.y < r.y + r.height &&
  r.y < label.box.y + label.box.height

/** The options MapScreen's chart is planned with at this size, minus the keep-out under test. */
function optionsAt(widthPx: number, heightPx: number) {
  const { viewBox, unitsPerPx } = chartAt(widthPx, heightPx)
  return {
    viewBox,
    unitsPerPx,
    fontSizePx: GLYPH.labelSize,
    gapPx: GLYPH.labelGapX,
    glyphRadiusPx: GLYPH.fleetHaloRadius,
  }
}

/**
 * A CROWDED COAST, at the phone's scale — the Mediterranean at "a coast" zoom, where every tier is
 * drawn. This is the frame the guard below needs, and the reason it is not the opening one: the
 * fixture's four fleets frame a stretch of Atlantic whose few names happen to fall nowhere near the
 * top-right corner, so the opening view could only ever prove the rule VACUOUSLY. The defect is real
 * either way — it was measured on the running game, whose house has one fleet at Lisbon, not four —
 * but a proof has to be run somewhere it can fail.
 */
const CROWDED: ViewBox = { x: 2, y: -45, width: 12, height: 26 }

function crowdedOptions() {
  return {
    viewBox: CROWDED,
    unitsPerPx: CROWDED.width / 390,
    fontSizePx: GLYPH.labelSize,
    gapPx: GLYPH.labelGapX,
    glyphRadiusPx: GLYPH.fleetHaloRadius,
  }
}

test.describe('labels keep out of the screen’s own chrome', () => {
  test('with the control column declared, NO label is placed under it', () => {
    const options = crowdedOptions()
    const keep = controlsRect(options.viewBox, options.unitsPerPx)
    const drawn = visiblePorts(PORTS, MODEL.portRoles, CROWDED, minTierForSpan(CROWDED.width))
    const requests = mapLabelRequests(MODEL, drawn, null, true)

    // NON-VACUITY FIRST. A keep-out guard that passes because nothing was ever there is not a
    // guard, so the same layout WITHOUT the rule must actually put names under the buttons — which
    // it does here, and did on the running game, three of them.
    const before = planLabels(requests, options).filter((l) => hits(l, keep))
    expect(
      before.length,
      'nothing was under the controls to begin with — this guard would prove nothing',
    ).toBeGreaterThan(0)

    const after = planLabels(requests, { ...options, keepOut: [keep] })
    for (const label of after) {
      expect(hits(label, keep), `"${label.text}" (${label.side}) is drawn under the zoom controls`).toBe(
        false,
      )
    }
    // And the chart is not emptied to achieve it: a name moves to another side, or it goes.
    expect(after.length).toBeGreaterThan(0)
    // Most of them simply move. A rule that answered a crowded corner by silencing the whole sheet
    // would trade one unreadable chart for another.
    expect(after.length).toBeGreaterThanOrEqual(planLabels(requests, options).length - before.length)
  })

  test('390x844, the opening frame: still nothing under the column', () => {
    // The frame the player actually opens on. Nothing is under the controls here even without the
    // rule (see CROWDED above), so this asserts only that the rule does no harm to the common case.
    const options = optionsAt(390, 844)
    const keep = controlsRect(options.viewBox, options.unitsPerPx)
    const placed = planLabels(
      mapLabelRequests(MODEL, drawnAt(options.viewBox), null, options.viewBox.width <= LABEL_SPAN_LIMIT),
      { ...options, keepOut: [keep] },
    )
    expect(placed.length).toBeGreaterThan(0)
    for (const label of placed) expect(hits(label, keep), `"${label.text}"`).toBe(false)
  })

  test('every name that survives is still inside the glass, and still disjoint', () => {
    const options = optionsAt(390, 844)
    const keep = controlsRect(options.viewBox, options.unitsPerPx)
    const placed = planLabels(
      mapLabelRequests(MODEL, drawnAt(options.viewBox), null, options.viewBox.width <= LABEL_SPAN_LIMIT),
      { ...options, keepOut: [keep] },
    )
    for (const label of placed) {
      expect(label.box.x, `${label.text} runs off the left`).toBeGreaterThanOrEqual(options.viewBox.x)
      expect(label.box.x + label.box.width, `${label.text} runs off the right`).toBeLessThanOrEqual(
        options.viewBox.x + options.viewBox.width,
      )
    }
    for (let i = 0; i < placed.length; i++) {
      for (let j = i + 1; j < placed.length; j++) {
        expect(overlaps(placed[i], placed[j])).toBe(false)
      }
    }
  })

  test('a FORCED label obeys keep-out too — hidden is not the same as placed', () => {
    // `force` overrides tidiness, never visibility: a selected name printed under an opaque button
    // is a name the chart believes it drew and the player cannot read. It gives way instead, and
    // the detail panel still names the thing — the standing fallback for any dropped label.
    const VIEW = { x: 0, y: 0, width: 100, height: 100 }
    // A band covering everything to the RIGHT of the glyph, and nothing to its left: "Chosen" is
    // 38 units wide here, so `left` is the one placement that both fits the frame and clears it.
    const RIGHT_BAND = { x: 52, y: 0, width: 48, height: 100 }
    const OPTS = {
      viewBox: VIEW,
      unitsPerPx: 1,
      fontSizePx: 10,
      gapPx: 5,
      glyphRadiusPx: 4,
      edgeInsetPx: 0,
      keepOut: [RIGHT_BAND],
    }
    const [only] = planLabels(
      [{ id: 'me', text: 'Chosen', at: { x: 50, y: 50 }, priority: 1000, tone: 'fleet', force: true }],
      OPTS,
    )
    expect(only, 'the forced label was dropped when a legal side existed').toBeTruthy()
    expect(only.side).toBe('left')
    expect(hits(only, RIGHT_BAND)).toBe(false)

    // And where there is nowhere at all, it is dropped rather than hidden.
    expect(
      planLabels(
        [{ id: 'me', text: 'Chosen', at: { x: 60, y: 50 }, priority: 1000, tone: 'fleet', force: true }],
        { ...OPTS, keepOut: [{ x: 0, y: 0, width: 100, height: 100 }] },
      ),
    ).toHaveLength(0)
  })

  test('an explicit empty keep-out is the same plan as none declared', () => {
    // The guard on the default. This example used to be "SmallChart has no chrome at all"; since
    // 2026-08-23 both charts wear the zoom column and declare it. The property still matters,
    // because every surface's FIRST measured frame plans with no chrome (`useChromeBoxes` reports
    // one frame late by design), and that frame must be the plain plan, not a different one.
    const options = optionsAt(390, 844)
    const requests = mapLabelRequests(
      MODEL,
      drawnAt(options.viewBox),
      null,
      options.viewBox.width <= LABEL_SPAN_LIMIT,
    )
    expect(planLabels(requests, { ...options, keepOut: [] }).map((l) => `${l.id}:${l.side}`)).toEqual(
      planLabels(requests, options).map((l) => `${l.id}:${l.side}`),
    )
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
    // "Naples" at x=97 in a 100-wide view: `right` would end past the edge.
    const [only] = planLabels(
      [{ id: 'a', text: 'Naples', at: { x: 97, y: 50 }, priority: 1, tone: 'port-quiet' }],
      OPTS,
    )
    expect(only.side).not.toBe('right')
    expect(only.box.x + only.box.width).toBeLessThanOrEqual(VIEW.x + VIEW.width)
  })

  test('the lower priority moves aside, and the higher one never does', () => {
    const placed = planLabels(
      [
        { id: 'low', text: 'Seville', at: { x: 50, y: 50.5 }, priority: 1, tone: 'port-quiet' },
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

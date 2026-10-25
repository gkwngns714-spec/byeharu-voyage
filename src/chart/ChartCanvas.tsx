import { memo, useEffect, useMemo, useState, type CSSProperties } from 'react'
import { CHART_WIDTH, sheetCopies, type Point, type ViewBox } from '../lib/geo'
import { CoastlineLayer } from './CoastlineLayer'
import { project } from '../lib/geo'
import { FleetsLayer, TracksLayer } from './FleetsLayer'
import { LabelsLayer } from './LabelsLayer'
import { PortsLayer } from './PortsLayer'
import { RoadsteadsLayer } from './RoadsteadsLayer'
import { DaylightSheet } from './DaylightSheet'
import { DaySeaLayer, GraticuleLayer, SEA_VIEWBOX, SeaLayer } from './SeaLayer'
import { DOT_SPAN_DEG, LANE_SPAN_DEG } from './chartView'
import { portMarks, type ChartModel, type PortRole } from './chartModel'
import type { CoastlineData } from './coastlineBuild'
import {
  coastPaperBox,
  LABEL_SPAN_LIMIT,
  minTierForSpan,
  nextCoastPaper,
  PAPER_SETTLE_MS,
  settleCoastPaper,
  type CoastPaper,
} from './chartView'
import { coastStrokeWidth, GLYPH } from './glyphs'
import { mapLabelRequests, planLabels, type LabelRequest, type Rect } from './labels'
import type { MapPort, MapSea, MapSelection } from './mapTypes'
import { regionNameRequests, type RegionTint } from './regions'
import { seaNameRequests } from './seaNames'
import { shipMarks } from './shipMarks'
import type { ChromeBox } from './useChartSurface'
import { useSunlight } from './useSunlight'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT IS ON THE PAPER, AND IN WHAT ORDER — the whole chart, drawn once, wherever it is drawn.
//
// PAINT ORDER IS THE ONLY STACKING SVG HAS, so it is a RULE and not a preference: sea, coast,
// tracks, ROADSTEADS, port marks, fleet hulls, names. Every name therefore sits on top of every
// mark and no mark sits on a name; the roads go under the ports, because a dotted line crossing a
// harbour should pass behind it.
//
// ── THE SEA IS PAINTED HERE, AND THAT IS NEW (2026-08-23) ──────────────────────────────────────
// "Sea" used to be the first word of that list and no line of code. The chart drew straight onto
// whatever its container happened to be — the `.bv-sea` gradient on both callers — so the sheet had
// no ground of its own, and three things followed. The coast's contrast varied with WHERE on the
// glass it fell (1.03 : 1 against the gradient's top stop, ~1.6 : 1 against its bottom). The label
// halo, `stroke-chart-sea`, punched a hole in a colour that was nowhere behind it. And a token
// named "the chart's sea" described nothing the eye ever met. One `<rect>` makes all three true at
// once, and it is why the contrast figures in src/index.css are one number rather than a range.
// It also means the chart's legibility no longer depends on what any screen puts behind it.
//
// ── WHY THIS IS A COMPONENT AND NOT SEVEN LINES INSIDE MapScreen ───────────────────────────────
// It was seven lines inside MapScreen while the map tab was the only place a chart appeared. The
// Command tab now shows one too (./SmallChart.tsx, on SAIL), and the second `<svg>` would have had
// to restate the same stack — a copy that no import check can see, because a copy imports nothing
// (`docs/NO_SPAGHETTI.md` §2, and `docs/SECTIONS.md`'s note on the trap a boundary sets). Two
// stacks can DISAGREE, which is question 3 of §1's checklist, so there is one.
//
// The derivations that decide what is drawn ride with it for the same reason. Each one is a rule
// about density, not about a screen:
//   · WHICH PORTS      `portMarks` — EVERY port on the glass (row 94), each FULL when it is big
//                      enough for this zoom (`minTierForSpan`) or one of yours, else a DOT. ONE
//                      list: the marks layer draws it whole, the label planner and the roads read
//                      its full half, so a name can never float over a mark drawn as a dot.
//   · WHICH SHIPS      `shipMarks` (2026-10-14) — your fleets on the glass, every one; the
//                      merchants on the glass, thinned to one per cell; ALL of them as ships.
//   · WHICH NAMES      planned as a SET over the drawn ports (./labels.ts), which is the only way
//                      two labels can know about each other.
// MapScreen's hit test asks `visiblePorts` and `shipMarks` — the same questions with the same box
// at the moment of a tap, which is what keeps "what you can touch" and "what is drawn" the same
// list (a dot is a picture; chartModel.ts records the tap that decided it).
//
// ── 2026-10-14: THE SHEET REPEATS, AND THE SUN IS ON IT ────────────────────────────────────────
// THE COPIES (owner: *"the map is not continuous from left to right. i want it to be continuous"*).
// The view is no longer clamped east–west (./chartView.ts `clampView`); its box may run past
// ±180°, and `sheetCopies(box)` (src/lib/geo, the projection's own periodicity) says which copies
// of the world it touches — one, or two at a seam. The marks are drawn ONCE PER COPY, in a group
// translated by 360k, from the copy's own WINDOW (the box shifted back by 360k and clipped to one
// world, so a harbour is drawn in exactly the copy it falls in). The coast is one `<use>` per copy
// (./CoastlineLayer.tsx). The names are planned ONCE over the whole box, every copy's requests
// shifted into place, so a name at 179°E and a mark at 179°W cannot be set on top of each other
// across the seam. A route across the Pacific — `sheetPieces` cuts it at ±180 — meets itself where
// the two copies meet, and the sheet has no edge anywhere.
// THE SUN (owner: *"sunlight based on real science… colors similar to daytime earth"*). ONE hook,
// `useSunlight`, reads the real clock once a minute and hands every layer two things: the subsolar
// point, so each mark can set its own `--night`, and the daylight raster, through which SeaLayer
// and CoastlineLayer paint the day picture over the night one. Nothing else on this chart knows
// what time it is.
//
// ── ROW 93: THE REGIONS, ONLY WHEN HANDED IN ───────────────────────────────────────────────────
// `regions` is null unless the surface's filter is on. Null reaches CoastlineLayer as "paint no
// tint" and this file as "ask for no region name", so the filter off is the chart exactly as it
// was — element for element (tests/map.regions.spec.ts holds that). On, the tints are painted
// with the coast and the 25 names join the ONE plan below every harbour's, above the seas'.
//
// ── IT IS A PICTURE ────────────────────────────────────────────────────────────────────────────
// There is no handler on this component and no prop that could carry one. Selection is resolved by
// the surface that owns the gestures (./hitTest.ts, ./useChartSurface.ts) and arrives here as a
// `MapSelection`, which is a name and not a verb. A chart that accepted an order would be a second
// place orders come from, and there is exactly one (`docs/DESIGN.md`, MapScreen's own header).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** One frozen empty list, so a chart handed no seas does not allocate one per frame. */
const NO_SEAS: readonly MapSea[] = []
const NO_ISLETS: readonly Point[] = []

/** The slack `portMarks` keeps beyond the glass, applied to a fleet's name request too. */
const REQUEST_MARGIN = 0.06

/**
 * ONE COPY'S WINDOW: the view shifted back onto the base copy and clipped to one world, so a thing
 * is listed in exactly the copy it falls in. A view that runs 170° → 200° has the window 170 → 180
 * on copy 0 and −180 → −160 on copy 1.
 */
function copyWindow(box: ViewBox, k: number): ViewBox {
  const left = Math.max(box.x - k * CHART_WIDTH, -CHART_WIDTH / 2)
  const right = Math.min(box.x + box.width - k * CHART_WIDTH, CHART_WIDTH / 2)
  return { x: left, y: box.y, width: Math.max(0, right - left), height: box.height }
}

export function ChartCanvas({
  model,
  ports,
  box,
  unitsPerPx,
  coast,
  seas = NO_SEAS,
  regions = null,
  portFlags = null,
  islets = NO_ISLETS,
  selection,
  keepOut,
  plannedD = null,
  ariaLabel,
  className,
}: {
  model: ChartModel
  /** The WHOLE port table, as `useBackdrop` hands it (set on the drawn shore, row 92). What is
   *  drawn out of it is this component's decision, not the caller's. */
  ports: readonly MapPort[]
  box: ViewBox
  /** Chart units per CSS pixel — every glyph and label size is in pixels and scaled by it. */
  unitsPerPx: number
  /** The world's land, built, or null while it is still being fetched (./useBackdrop.ts). */
  coast: CoastlineData | null
  /** The named waters (row 90), or none while the backdrop is still being fetched — which draws
   *  no names, truthfully. Which of them are set at this zoom is ./seaNames.ts's decision. */
  seas?: readonly MapSea[]
  /** The regions' tints and names (row 93) — null while the filter is off, which is the default
   *  and the map exactly as it was. */
  regions?: readonly RegionTint[] | null
  /** 0143 — each harbour's flag by port code, set before its name (D14). The screen passes it only
   *  while the Regions filter is on; null is the map exactly as it was. */
  portFlags?: ReadonlyMap<string, string> | null
  /** Harbours the drawn coast has no land for (row 92): a speck of land is painted under each. */
  islets?: readonly Point[]
  selection: MapSelection
  /**
   * OPAQUE CHROME THE SCREEN HAS PUT OVER THIS CHART, in CSS pixels from the chart's top-left
   * corner — hand `useChartSurface`'s `chromeBoxes` straight through. No name will be placed inside
   * one of these, which is how `Saint-Malo` stops rendering as `Sain` behind the zoom column.
   *
   * A PARAMETER, because a chart may not know what a screen is (src/chart/index.ts). Both figures
   * in it are the screen's: the chart converts them to chart units and asks nothing else about
   * them, and it never learns what the box CONTAINS. Omit it and the chart assumes nothing is over
   * it, which is exactly true of `SmallChart`.
   */
  keepOut?: readonly ChromeBox[]
  /**
   * A PLAN'S COURSE, not yet sailed (owner row 183, the Plans face's chart): the legs the plan would
   * queue, as one path (`loopD` over the courses `planLines` proposes — the same water the queued SAIL
   * lines carry, which the server re-verifies when each runs). Dashed in the accent, under the marks.
   * Null — every other chart — draws nothing.
   */
  plannedD?: string | null
  ariaLabel: string
  className?: string
}) {
  // THE SUN, NOW — the one clock this picture reads (./useSunlight.ts).
  const sunlight = useSunlight()
  const sun = sunlight.sun

  // THE ROLES, HELD STILL WHILE NOTHING ABOUT THEM CHANGES (2026-10-12: *"the game looks stuck.
  // optimize it so that it is smoothe"*).
  //
  // `buildChartModel` is re-run on every DRIFT TICK — `MapScreen`'s memo takes `nowMs` — so
  // `model.portRoles` was a BRAND NEW MAP several times a second even when not one port had
  // changed role. Every memo below keyed on it therefore missed, every frame: `portMarks` walked
  // all 252 harbours, `fullPorts` re-filtered them, and `PortsLayer` re-rendered the lot — which
  // at the globe is now three circles of light apiece. The roles themselves change when a fleet
  // ARRIVES or is SENT, which is a read, not a frame.
  //
  // THE CONTENT IS THE KEY, so the identity follows the content and nothing is held in a ref (a ref
  // read during render is a different bug, and eslint's `react-hooks/refs` is right about it). The
  // roles are a handful of entries — only the ports some fleet is using — so spelling them as a
  // string and rebuilding the Map when that string changes costs nothing next to the 252 marks and
  // 252 lights it stops re-rendering.
  const rolesKey = [...model.portRoles]
    .map(([code, role]) => `${code}:${role}`)
    .sort()
    .join('|')
  const portRoles = useMemo<ReadonlyMap<string, PortRole>>(
    () =>
      new Map(
        rolesKey === ''
          ? []
          : rolesKey.split('|').map((pair) => pair.split(':') as [string, PortRole]),
      ),
    [rolesKey],
  )
  // THE TWO RUNGS OF THE WIDE SHEET, read off the SPAN and handed down (owner row 125). Decided
  // once, here, so the lanes and the dots cannot disagree about where the sheet changes character
  // — and in degrees rather than in pixels per degree, because the same world on a phone and on a
  // desktop is the same zoom and must be the same picture. ./chartView.ts says what that cost when
  // it was keyed on density instead.
  // A HARBOUR CARRIES HER LIGHT AT EVERY ZOOM (owner, 2026-10-12: *"when zoomed in, i want to see
  // the lights also"*) — and since 2026-10-14 only where the Sun is down (./sun.ts), which is the
  // Sun's call and not the zoom's.
  // THE LANES still wait for the pulled-back sheet: 49 thinned loops laid over a working chart is a
  // thicket, and a lane IS thinned — straight where the real course bends — so close in it would be
  // a visibly wrong line on water somebody is reading.
  const laneBand = box.width >= LANE_SPAN_DEG
  const dotsOnly = box.width >= DOT_SPAN_DEG

  // THE COPIES OF THE SHEET ON THE GLASS, and each one's window (header).
  const copies = useMemo(() => sheetCopies(box), [box])
  const windows = useMemo(() => copies.map((k) => ({ k, window: copyWindow(box, k) })), [copies, box])

  const minTier = minTierForSpan(box.width)
  // WHICH PORTS, per copy — `portMarks` on the copy's own window, so each harbour is drawn once.
  const marksByCopy = useMemo(
    () => windows.map(({ k, window }) => ({ k, marks: portMarks(ports, portRoles, window, minTier) })),
    [windows, ports, portRoles, minTier],
  )
  // WHICH SHIPS, per copy — your fleets, and the merchants thinned (./shipMarks.ts).
  const shipsByCopy = useMemo(
    () => windows.map(({ k, window }) => ({ k, ships: shipMarks(model.fleets, model.traffic, window, unitsPerPx) })),
    [windows, model, unitsPerPx],
  )

  // THE SCREEN'S PIXELS, TURNED INTO CHART UNITS — the one line of arithmetic the keep-out contract
  // needs, done here so no screen ever has to hold a scale or a viewBox origin. `unitsPerPx` is the
  // same on both axes (viewBoxOf derives the height from the surface's aspect), so one factor does
  // both.
  const keepOutUnits = useMemo<readonly Rect[] | undefined>(() => {
    if (!keepOut || keepOut.length === 0) return undefined
    return keepOut.map((r) => ({
      x: box.x + r.x * unitsPerPx,
      y: box.y + r.y * unitsPerPx,
      width: r.width * unitsPerPx,
      height: r.height * unitsPerPx,
    }))
  }, [keepOut, box, unitsPerPx])

  // ONE plan for every name on the sheet — the places AND the waters (row 90), on EVERY copy
  // (2026-10-14). Each copy's requests are built on its own window and shifted into place, so the
  // planner sees the whole glass at once and a name can never be set across the seam onto a mark
  // on the other copy. The seas' requests are appended, not merged in a second planner: they carry
  // the lowest priority, so `planLabels` places them last and a water's name can only ever fill
  // water no port has claimed.
  const labels = useMemo(() => {
    const requests: LabelRequest[] = []
    for (const { k, marks } of marksByCopy) {
      const window = copyWindow(box, k)
      const fullPorts = marks.filter((m) => m.full).map((m) => m.port)
      const padX = window.width * REQUEST_MARGIN
      const padY = window.height * REQUEST_MARGIN
      const inWindow = (r: LabelRequest) =>
        r.at.x >= window.x - padX && r.at.x <= window.x + window.width + padX && r.at.y >= window.y - padY && r.at.y <= window.y + window.height + padY
      const shift = (r: LabelRequest): LabelRequest => (k === 0 ? r : { ...r, at: { x: r.at.x + k * CHART_WIDTH, y: r.at.y } })
      // A fleet's name is asked for on the copy her hull is drawn in, and on that one only — the
      // ports and the waters are already culled to the window by their own builders.
      for (const r of mapLabelRequests(model, fullPorts, selection, box.width <= LABEL_SPAN_LIMIT, portFlags)) {
        if (r.tone === 'fleet' && !inWindow(r)) continue
        requests.push(shift(r))
      }
      if (regions) for (const r of regionNameRequests(regions, window)) requests.push(shift(r))
      for (const r of seaNameRequests(seas, window)) requests.push(shift(r))
    }
    return planLabels(requests, {
      viewBox: box,
      unitsPerPx,
      fontSizePx: GLYPH.labelSize,
      gapPx: GLYPH.labelGapX,
      glyphRadiusPx: GLYPH.fleetHaloRadius,
      keepOut: keepOutUnits,
    })
  }, [model, marksByCopy, seas, regions, portFlags, selection, box, unitsPerPx, keepOutUnits])

  // THE COAST'S SHEET (./chartView.ts, `paperOf` and `nextCoastPaper`) — wide at rest and in a pan,
  // the view itself just after a zoom. The state is only "was the last change a zoom": it is advanced
  // during render (the documented derive-from-the-previous-render pattern; `nextCoastPaper` returns
  // the same object when nothing changed, so this sets state only on a transition) and settled wide
  // by a timer once a zoom has stopped.
  const [paperState, setPaperState] = useState<CoastPaper | null>(null)
  const coastPaper = nextCoastPaper(paperState, box)
  if (coastPaper !== paperState) setPaperState(coastPaper)
  const narrow = coastPaper.narrow !== null
  useEffect(() => {
    if (!narrow) return
    const timer = setTimeout(() => setPaperState(settleCoastPaper), PAPER_SETTLE_MS)
    return () => clearTimeout(timer)
  }, [narrow, coastPaper.width])
  // The same OBJECT for as long as it holds the same four numbers, which is every frame of a pan
  // until the view has travelled half a glass. The sheet is memoised on it, so between those frames
  // React re-renders no coast and the browser moves its composited layer instead of repainting it.
  const sheet = coastPaperBox(coastPaper, box)
  const paper = useMemo<ViewBox>(
    () => ({ x: sheet.x, y: sheet.y, width: sheet.width, height: sheet.height }),
    [sheet.x, sheet.y, sheet.width, sheet.height],
  )
  const paperCopies = useMemo(() => sheetCopies(paper), [paper])

  const selectedFleetId = selection?.kind === 'fleet' ? selection.id : null
  const selectedMerchantId = selection?.kind === 'merchant' ? selection.id : null
  const selectedPortCode = selection?.kind === 'port' ? selection.code : null

  // Where the coast's sheet sits on the glass, in CSS pixels: its top-left corner relative to the
  // view's, rounded to the DEVICE pixel so the composited layer is never sampled between pixels
  // (a layer moved by a fraction of a pixel is resampled, and a 0.9 px hairline goes soft). The
  // rounding is at most half a device pixel; the marks are drawn exactly, and nothing on this sheet
  // is aligned to a mark closer than that.
  const dpr = typeof window !== 'undefined' && window.devicePixelRatio > 0 ? window.devicePixelRatio : 1
  const snap = (px: number) => Math.round(px * dpr) / dpr
  const sheetLeft = snap((paper.x - box.x) / unitsPerPx)
  const sheetTop = snap((paper.y - box.y) / unitsPerPx)

  // FIVE SHEETS, ONE PICTURE, in the one paint order (header): the night sea, the day sea through
  // the Sun's mask, the night chart (graticule and coast), the day coast through the Sun's mask, the
  // marks. Only the marks are the view: their viewBox is `box` and they re-render with it, which
  // costs little — they are small. The seas are the glass's own picture and never change on a pan. The two charts — the only expensive things
  // on the paper (every frame of a pan used to re-rasterise them, 25–55 ms of GPU) — are drawn over
  // `paper`, not the view, and moved by a CSS transform, so a pan MOVES them on the compositor and
  // repaints them only when the view crosses into the next half-glass of the grid (`paperOf`) or
  // zooms (docs/MAP_ATMOSPHERE.md §10).
  return (
    <div
      // `bv-chart-night` is the chart's own palette (src/index.css, owner row 171): the night map
      // in both schemes. It says nothing in the dark scheme — there it is the colours this element
      // already inherits — and in the light one it keeps the water, the land and every mark the
      // colour the player knows, while the page around the chart stays the scheme they chose.
      className={`bv-chart-night ${className ?? ''}`}
      role="img"
      aria-label={ariaLabel}
      data-sheet-copies={copies.join(' ')}
      // THE SUN THE PICTURE WAS DRAWN FOR, written on the picture — so a spec reads the instant and
      // the subsolar point the chart actually used rather than guessing at the clock.
      data-sun-at={sunlight.atMs}
      data-sun-lat={sun.lat.toFixed(4)}
      data-sun-lon={sun.lon.toFixed(4)}
    >
      {/* THE SEA — the ground everything else is measured against, and its depth (./SeaLayer.tsx).
          The same picture at every pan, so it is drawn on the glass's unit square and never moves. */}
      <svg className="absolute inset-0 h-full w-full" viewBox={SEA_VIEWBOX} preserveAspectRatio="none" aria-hidden="true">
        <SeaLayer />
      </svg>
      {/* THE DAY'S WATER, where the Sun is up (./DaylightSheet.tsx) — a picture of the glass, so a
          pan slides only its mask and never repaints the picture. */}
      {sunlight.rasterUrl && (
        <DaylightSheet rasterUrl={sunlight.rasterUrl} x={box.x} y={box.y} unitsPerPx={unitsPerPx} className="absolute inset-0">
          <svg className="block h-full w-full" viewBox={SEA_VIEWBOX} preserveAspectRatio="none" aria-hidden="true">
            <DaySeaLayer />
          </svg>
        </DaylightSheet>
      )}
      {/* THE NIGHT CHART — the graticule over both waters, then the coast, on the paper, moved by a
          translate. */}
      <CoastSheet
        coast={coast}
        paper={paper}
        copies={paperCopies}
        left={sheetLeft}
        top={sheetTop}
        strokeWidth={coastStrokeWidth(box.width)}
        regions={regions}
        islets={islets}
        unitsPerPx={unitsPerPx}
      />
      {/* THE DAY COAST — the same coast in the Earth's colours, where the Sun is up. Its mask stands
          still on the glass like the day sea's, and the paper moves under it by the night sheet's
          own translate (CoastSheet's header says why the mask may not ride on the moving sheet). */}
      {sunlight.rasterUrl && coast && (
        <DaylightSheet rasterUrl={sunlight.rasterUrl} x={box.x} y={box.y} unitsPerPx={unitsPerPx} className="absolute inset-0">
          <CoastSheet
            coast={coast}
            paper={paper}
            copies={paperCopies}
            left={sheetLeft}
            top={sheetTop}
            strokeWidth={coastStrokeWidth(box.width)}
            regions={regions}
            islets={islets}
            unitsPerPx={unitsPerPx}
            face="day"
          />
        </DaylightSheet>
      )}
      {/* THE VIEW SHEET — the one svg whose viewBox IS the view (`map-view`, which the specs read). */}
      <svg
        className="absolute inset-0 h-full w-full"
        viewBox={`${box.x} ${box.y} ${box.width} ${box.height}`}
        aria-hidden="true"
        data-testid="map-view"
      >
        {/* THE MARKS, ONCE PER COPY OF THE SHEET (header): each copy's group is the world drawn at
            x + 360k, from that copy's own window, in the one paint order. */}
        {windows.map(({ k }) => {
          const marks = marksByCopy.find((m) => m.k === k)?.marks ?? []
          const ships = shipsByCopy.find((s) => s.k === k)?.ships ?? { fleets: [], traffic: [] }
          const fullPorts = marks.filter((m) => m.full).map((m) => m.port)
          return (
            <g key={k} transform={k === 0 ? undefined : `translate(${k * CHART_WIDTH} 0)`} data-sheet-copy={k}>
              <TracksLayer model={model} unitsPerPx={unitsPerPx} lanes={laneBand} />
              {plannedD && (
                <path
                  data-testid="map-plan-course"
                  d={plannedD}
                  className="fill-none stroke-accent/80"
                  strokeWidth={GLYPH.trackStroke}
                  strokeDasharray="4 4"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  vectorEffect="non-scaling-stroke"
                  pointerEvents="none"
                />
              )}
              {/* THE ROADS (0076) — the dotted helper line out to the one point of open water each
                  port is reached from, and the hollow circle on it. UNDER the port marks, because a
                  dotted line crossing a harbour should pass behind it (FleetsLayer.tsx:6-9) and a city
                  standing on its own roads is the right picture. It is handed the FULL half of the
                  same list PortsLayer gets, so a line can never run out of a mark that was not drawn
                  — a dot (row 94) has no roads. */}
              <RoadsteadsLayer ports={fullPorts} unitsPerPx={unitsPerPx} sun={sun} />
              {/* THE PINPOINT (0039) — the tapped spot of open water, marked exactly like a selected
                  port is ringed, because it is the same act one step earlier: naming a destination. */}
              {selection?.kind === 'sea' &&
                (() => {
                  const at = project(selection.at)
                  return (
                    <g pointerEvents="none" data-testid="map-sea-point">
                      <circle
                        cx={at.x}
                        cy={at.y}
                        r={GLYPH.destinationRingRadius * unitsPerPx}
                        className="fill-none stroke-ink/70"
                        strokeWidth={GLYPH.glyphStroke}
                        vectorEffect="non-scaling-stroke"
                      />
                      <circle cx={at.x} cy={at.y} r={2 * unitsPerPx} className="fill-ink/70" />
                    </g>
                  )
                })()}
              <PortsLayer
                marks={marks}
                portRoles={portRoles}
                selectedCode={selectedPortCode}
                unitsPerPx={unitsPerPx}
                dotsOnly={dotsOnly}
                sun={sun}
              />
              <FleetsLayer
                fleets={ships.fleets}
                traffic={ships.traffic}
                selectedId={selectedFleetId}
                selectedMerchantId={selectedMerchantId}
                unitsPerPx={unitsPerPx}
                sun={sun}
              />
            </g>
          )
        })}
        {/* THE NAMES — one plan over the whole glass, drawn once, over every copy. */}
        <LabelsLayer labels={labels} unitsPerPx={unitsPerPx} sun={sun} />
      </svg>
    </div>
  )
}

/**
 * THE COAST'S SHEET — one face of the coast (./CoastlineLayer.tsx: shallows, body, relief, line,
 * tints, islets — or, `face="day"`, the same coast in the Earth's colours) in its own `<svg>` over
 * `paper`, on its own compositor layer (`will-change: transform`), placed by a translate of
 * `left`/`top` CSS pixels. Memoised, and CoastlineLayer inside it too, so a pan — which changes only
 * `left`/`top` — writes one `transform` and the browser moves the layer. The svg's viewBox IS `paper`
 * and its size is `paper` in pixels, so a chart unit is exactly the pixel it is on the view sheets
 * and every coordinate inside is the chart's own. `copies` is `sheetCopies` of the PAPER, which is
 * wider than the view: the coast is drawn once and <use>d for the rest.
 *
 * TWO OF THEM, AND NO MASK ON EITHER (2026-10-18, owner: *"when i move map, it blinks too much"*
 * — *"move the map faster, it will show blink, way faster"*). The night face is drawn straight on
 * the glass, with the graticule under its coast; the day face is a sheet INSIDE a DaylightSheet
 * that is the glass itself, so the Sun's mask is the glass's and only the picture under it moves.
 * Before, the day coast's mask sheet was nested inside the night sheet and rode its translate, the
 * graticule was a glass-sized svg of its own, and both seas re-drew a glass on every frame: eight
 * compositor layers the size of the glass and two mask surfaces. On a fast drag in headed Chrome on
 * the GPU (3,000 px in 300 ms) that ran past the tile-memory budget, and Chrome put frames on the
 * glass with tiles it had not rasterised — the land flashing to sea in rectangles, the day side
 * going to night and back, once the whole page dark. Proved by the budget, not guessed: the same
 * drag with `--force-gpu-mem-available-mb=4096` showed no such frame; the default showed 4 to 17 a
 * run (docs/dev-log/2026-10-18-map-no-blink.md has the frames and the layer lists). Now the
 * graticule rides this paper, the seas are still pictures, and the day coast's mask is the
 * glass's: seven such layers, none re-drawn by a pan, and no blank frame in any run.
 */
const CoastSheet = memo(function CoastSheet({
  coast,
  paper,
  copies,
  left,
  top,
  strokeWidth,
  regions,
  islets,
  unitsPerPx,
  face = 'night',
}: {
  coast: CoastlineData | null
  paper: ViewBox
  copies: readonly number[]
  /** Where the sheet's top-left corner is on the glass, in CSS pixels (device-pixel snapped). */
  left: number
  top: number
  strokeWidth: number
  regions: readonly RegionTint[] | null
  islets: readonly Point[]
  unitsPerPx: number
  face?: 'night' | 'day'
}) {
  const style: CSSProperties = {
    width: paper.width / unitsPerPx,
    height: paper.height / unitsPerPx,
    transform: `translate(${left}px, ${top}px)`,
  }
  return (
    <div
      className="absolute top-0 left-0 will-change-transform"
      style={style}
      data-testid={face === 'day' ? 'map-coast-sheet-day' : 'map-coast-sheet'}
    >
      {/* The svg's own viewport clips at `paper` (an inline svg is overflow: hidden), which is what
          bounds the layer to 1.5 views square instead of the whole world at harbour zoom. */}
      <svg
        className="block h-full w-full"
        viewBox={`${paper.x} ${paper.y} ${paper.width} ${paper.height}`}
        preserveAspectRatio="none"
        aria-hidden="true"
      >
        {/* The grid, on the night sheet only: it is over both waters and under every coast. */}
        {face === 'night' && <GraticuleLayer box={paper} />}
        <CoastlineLayer
          coast={coast}
          strokeWidth={strokeWidth}
          regions={regions}
          islets={islets}
          unitsPerPx={unitsPerPx}
          copies={copies}
          face={face}
        />
      </svg>
    </div>
  )
})

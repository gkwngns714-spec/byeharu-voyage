import { useMemo, useRef, type MouseEvent } from 'react'
import {
  boundsOf,
  fitToViewBox,
  project,
  unproject,
  WORLD_BOUNDS,
  type LatLon,
  type ViewBox,
} from '../lib/geo'
import type { ChartModel } from './chartModel'
import { CoastlineLayer } from './CoastlineLayer'
import { GLYPH, trianglePath } from './glyphs'
import type { MapPort } from './mapTypes'
import { CHART_CHROME } from './useChartSurface'
import { useElementSize } from './useElementSize'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MINIMAP — the whole world at a glance: your fleets on it, and the window the main chart is
// looking through.
//
// The owner, 2026-08-23: *"in map - make a small miniturized map at the corner of the map, that
// shows where my fleets are in color + symbol."* The main chart shows one region at a time; a
// fleet outside its frame is a fleet the screen says nothing about. This inset never pans and
// never zooms — showing ALL of it, always, is its entire job.
//
// ── §7B, ANSWERED BEFORE IT WAS WRITTEN ────────────────────────────────────────────────────────
// WHAT IT IS   one concept: a LOCATOR — a fixed world-wide frame with three kinds of ink on it:
//              the coast, your fleets, and the main chart's current window.
// WHERE        src/chart, because every line of it is the chart's own vocabulary — `project`,
//              the ChartModel's fleets, `CoastlineLayer`, the GLYPH metrics, `fitToViewBox` —
//              and a screen may not reach past the entrance for any of those.
// SECOND CALLER  none is plausible, and that is a decision, not an omission: the only other chart
//              surface, `SmallChart`, already re-frames itself onto the order being composed —
//              it IS a locator for the order — and an inset inside a 3/2 card would land below
//              legibility. A future second full-tab chart would mount this as MapScreen does:
//              everything it needs arrives as a parameter.
// WRONG SHAPE  a second chart: its own camera, its own port list, its own projection, its own
//              glyph language. None exist here — the frame is computed (never stored, never
//              steered), no port mark is drawn at all, the projection is `lib/geo`'s, and the
//              fleet marks are §E.5's own two symbols.
//
// ── WHY IT COMPOSES THE CHART'S PARTS AND NOT `ChartCanvas` WHOLE ──────────────────────────────
// `ChartCanvas` at a world frame was the first design, and it fails on a MEASURED fact: at the
// world span the density rules draw the 35 great ports, and on a 144 px inset 30 of those 35
// marks have a neighbour under 5 px away — 16 of them inside a 20×13 px patch of Europe. That is
// a blob of ink, not an instrument. The density rules (`PORT_TIER_BANDS`, `LABEL_SPAN_LIMIT`) are
// keyed on SPAN because they were tuned for a full-tab sheet; a 144 px surface is a regime they
// never met, and the honest answer there is that NO port mark survives. So the minimap draws the
// three things its question needs — coast, fleets, window — from the same modules the big chart
// draws them with, and nothing else.
//
// ── THE TWO STATES OF A FLEET, IN THE CHART'S OWN LANGUAGE ─────────────────────────────────────
// Colour AND symbol, both taken from the main chart rather than minted here (the rarity work
// landed the same both-channels rule: colour alone fails a colourblind player and a greyscale
// screenshot):
//   at anchor   the filled brass triangle — §E.5's "a fleet at anchor IS the loud port mark"
//   at sea      the brass dot in its sea-coloured halo — FleetsLayer's own mark
// Both are `fill-accent` because brass already means "yours" on the sheet; a new hue would be a
// second answer to a question the chart has answered. Docked fleets converging on one harbour
// draw one overlapping mark at this scale, and that is honest: they ARE in one place, and the
// main chart is the instrument that separates them.
//
// ── IT IS TAPPABLE, AND WHY THAT IS SAFE ───────────────────────────────────────────────────────
// A tap hands the tapped place to the caller (`onJump`), and MapScreen wires that to
// `surface.centreOn` — the ONE existing camera move. Nothing appears, vanishes or resizes: only
// the main chart's viewBox moves, which docs/OWNER_REQUESTS.md row 32 records as NOT a
// restructure. It is also the one minimap behaviour players of the reference game consistently
// praise (docs/UI_DIRECTION.md §3a: "tap the minimap → he walks there"). The whole inset is the
// target (well over 44 px); there is no smaller control inside it. Keyboard reach is unharmed:
// everything a jump reaches is also reachable from the fleet list and the find control, which is
// the same decision MapScreen's header records for the chart's own pan.
//
// ── WHAT IT DELIBERATELY DOES NOT DO ───────────────────────────────────────────────────────────
// No pan, no zoom, no selection, no labels, no lanes, no destination rings, no port marks. Every
// one of those is the main chart's job, done properly there. And it invents no number: fleet
// positions are the model's (`voyage.position`, the server's closed form, copied), the frame is
// `fitToViewBox` over the port table's own bounds, and the window is the surface's real viewBox.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** Breathing room around the world frame — enough that a mark on the outermost harbour
 *  (Arkhangelsk, 78°N) is not clipped by the inset's edge. */
const FRAME_PADDING = 0.05

/** Fleet marks at 0.8× the main chart's metrics. MEASURED on the 144 px inset: at 1.0× the at-sea
 *  halo is 16 px — 11% of the inset's width — which reads as a badge, not a position. At 0.8× the
 *  triangle is 8 px and the halo 12.8 px: still unmissable, no longer shouting. */
const MARK_SCALE = 0.8

/** The window rectangle never draws smaller than this on the glass. At the chart's tightest zoom
 *  (1.5° of a ~325° frame) the true rectangle is under 0.7 px — invisible, which turns the
 *  instrument back into a picture. A 6 px floor keeps it a mark; the centre stays true. */
const VIEWPORT_MIN_PX = 6

export function Minimap({
  model,
  ports,
  coastlineD,
  viewport,
  onJump,
  ariaLabel,
  className = 'h-13 w-36',
}: {
  /** The SAME model the main chart draws — one classification of docked/at-sea, never a second. */
  model: ChartModel
  /** The whole port table, used ONLY to bound the world frame. No port mark is drawn (see header). */
  ports: readonly MapPort[]
  /** The one backdrop, or '' while it loads or when it failed — the inset works without it. */
  coastlineD: string
  /** Where the main chart is currently looking. Null before the surface is measured. */
  viewport: ViewBox | null
  /** The tapped place — the caller's one camera move (`surface.centreOn`). Omit for an inert inset. */
  onJump?: (at: LatLon) => void
  ariaLabel: string
  className?: string
}) {
  const ref = useRef<HTMLDivElement>(null)
  const size = useElementSize(ref)

  // The WORLD frame: the port table's own bounds, fitted once to the inset's glass. A function of
  // the world, so it never moves — the fixity is the point.
  const bounds = useMemo(() => boundsOf(ports) ?? WORLD_BOUNDS, [ports])
  const measured = size.width > 0 && size.height > 0
  const box = useMemo(
    () => (measured ? fitToViewBox(bounds, size.width / size.height, FRAME_PADDING) : null),
    [measured, bounds, size.width, size.height],
  )
  const unitsPerPx = box && measured ? box.width / size.width : 1
  const px = (n: number) => n * unitsPerPx * MARK_SCALE

  // The window, floored to stay visible (see VIEWPORT_MIN_PX). Drawn from the surface's true
  // viewBox — the same box the main chart is rendering this frame, not a copy of its state.
  const windowRect = useMemo(() => {
    if (!viewport || !box) return null
    const minUnits = VIEWPORT_MIN_PX * unitsPerPx
    const width = Math.max(viewport.width, minUnits)
    const height = Math.max(viewport.height, minUnits)
    return {
      x: viewport.x + viewport.width / 2 - width / 2,
      y: viewport.y + viewport.height / 2 - height / 2,
      width,
      height,
    }
  }, [viewport, box, unitsPerPx])

  const jump = (event: MouseEvent<HTMLDivElement>) => {
    if (!onJump || !box) return
    const rect = event.currentTarget.getBoundingClientRect()
    if (rect.width <= 0 || rect.height <= 0) return
    onJump(
      unproject({
        x: box.x + ((event.clientX - rect.left) / rect.width) * box.width,
        y: box.y + ((event.clientY - rect.top) / rect.height) * box.height,
      }),
    )
  }

  return (
    <div
      ref={ref}
      // CHART_CHROME does two jobs at once, both load-bearing: a press here never pans the chart
      // underneath, and `useChromeBoxes` measures this box into `keepOut`, so a port's name is
      // never printed under the inset (the Saint-Malo defect's fix, applied by marker rather than
      // re-stated). `bg-chart-sea` paints the frame before the box is measured, exactly as the
      // big chart's `.bv-sea` does.
      {...CHART_CHROME}
      onClick={jump}
      className={`pointer-events-auto relative overflow-hidden rounded-sm border border-edge bg-chart-sea ${onJump ? 'cursor-pointer' : ''} ${className}`}
      data-testid="map-minimap"
    >
      {box && (
        <svg
          viewBox={`${box.x} ${box.y} ${box.width} ${box.height}`}
          role="img"
          aria-label={ariaLabel}
          className="pointer-events-none absolute inset-0 h-full w-full"
        >
          <rect
            x={box.x}
            y={box.y}
            width={box.width}
            height={box.height}
            className="fill-chart-sea"
          />
          <CoastlineLayer d={coastlineD} />

          {/* THE WINDOW — what turns a picture into an instrument. Parchment ink, because it is
              information about the VIEW, and brass on this sheet already means "yours". */}
          {windowRect && (
            <rect
              x={windowRect.x}
              y={windowRect.y}
              width={windowRect.width}
              height={windowRect.height}
              className="fill-ink/10 stroke-ink/80"
              strokeWidth={1}
              vectorEffect="non-scaling-stroke"
              data-testid="minimap-window"
            />
          )}

          {/* THE FLEETS — §E.5's two symbols, in §E.5's one colour (see header). */}
          <g data-testid="minimap-fleets">
            {model.fleets.map((f) => {
              const { x, y } = project(f.at)
              return f.dockedAtCode !== null ? (
                <path
                  key={f.fleet.id}
                  d={trianglePath(x, y, px(GLYPH.loudPortHalfWidth), px(GLYPH.loudPortHeight))}
                  className="fill-accent stroke-chart-sea"
                  strokeWidth={GLYPH.glyphStroke}
                  strokeLinejoin="round"
                  vectorEffect="non-scaling-stroke"
                />
              ) : (
                <g key={f.fleet.id}>
                  <circle
                    cx={x}
                    cy={y}
                    r={px(GLYPH.fleetHaloRadius)}
                    className="fill-chart-sea/70 stroke-accent/40"
                    strokeWidth={GLYPH.glyphStroke}
                    vectorEffect="non-scaling-stroke"
                  />
                  <circle cx={x} cy={y} r={px(GLYPH.fleetDotRadius)} className="fill-accent" />
                </g>
              )
            })}
          </g>
        </svg>
      )}
    </div>
  )
}

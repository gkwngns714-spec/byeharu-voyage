import { memo } from 'react'
import { project } from '../lib/geo'
import type { PortMark, PortRole } from './chartModel'
import { GREAT_PORT_TIER } from './chartView'
import {
  GLYPH,
  harbourLightGlow,
  harbourLightHalo,
  lozengePath,
  portMarkScale,
  portStrokeWidth,
  trianglePath,
} from './glyphs'

// GLYPH 1 — THE PORT, in two weights and five RANKS.
//
// DESIGN §E.5: "Ports the fleet is not using are quieter than ports it is." So one shape, two
// WEIGHTS: a hollow triangle in faint ink for a port nothing of yours touches, a filled brass one
// for a port a fleet is at or bound for. Which is which comes from `portRoles` on the chart model —
// the same table the label engine ranks by, so a loud glyph and a high-priority label can never
// disagree.
//
// On top of the weight, the RANK is the port's own `size_tier`, on two channels that ./glyphs.ts
// owns: `portMarkScale` (how big) and `portStrokeWidth` (how firm the line). That is what keeps 214
// harbours legible — the eye reads the great ports first because they are drawn bigger and firmer,
// not because someone hand-picked a list.
//
// IT WAS ONE CHANNEL AND TOO NARROW A ONE. Measured on the running chart at 390 px, a tier-3 mark
// came out 6.77 px wide against a tier-5 at 8.50 px, in the same colour and at the same 1.2 px line
// weight: 26% apart, which at arm's length is 214 identical triangles. Both ramps widened together
// (glyphs.ts carries the numbers and what was rejected); nothing here decides anything new, and no
// new notion of "important" was invented — `size_tier` was already the metric, and PORT_TIER_BANDS
// was already using it to decide which ports are on the sheet at all.
//
// `marks` is EVERY port on the glass (chartModel.portMarks), each already decided FULL or DOT by
// the zoom's tier floor. This layer draws exactly what it is handed and makes no decision of its
// own about what belongs on the sheet.
//
// ROW 94 (2026-09-14, the owner: "all the ports in the game when i zoom out, it can be a dot,
// then once zoomed in i will be able to see the marker"): a port below the zoom's tier floor is
// not left off the sheet any more — it is drawn as a DOT, `GLYPH.portDotRadius`, in the quiet
// ink, no ring, no name, no roads, no tap. Same `<g data-port-code>`, same identity, the dot is that
// harbour's rendering at this zoom and it becomes the triangle on the zoom ladder the tier bands
// already define. `data-port-mark` says which it is, so a drive can count both.
//
// THE MARK'S POSITION IS WRITTEN ON THE GROUP (`data-port-x`, `data-port-y`, chart units) for
// the same reason `data-port-code` is: a mark's `d` is a shape and not a coordinate, and the
// landfall spec (row 92) has to read where each harbour was actually drawn.
//
// THIS LAYER DRAWS MARKS AND NOTHING ELSE. No text (labels are placed as a set by ./labels.ts and
// drawn by LabelsLayer — a label placed here could not know what the next port is about to print)
// and no handler at all (taps are resolved by one nearest-wins hit test on the surface,
// ./hitTest.ts). There is nothing in this file that could ever grow into an order.

/**
 * A HARBOUR'S LIGHT — bloom, glow, core (owner row 125, rebuilt 2026-10-12).
 *
 * THE FIRST CUT WAS NOT A LIGHT AND THE OWNER SAID SO. It was one halo at 20% ink, 3.4x the core,
 * which at the globe is a 1.6 px dot inside a 5.4 px smudge: on a dark sheet that is a slightly
 * fuzzy speck and nothing at all like *"cities to be bright light… visually beautiful"*. What
 * makes a point read as a SOURCE is falloff, and falloff needs more than one step. Three circles
 * now — 6.5 to 14.4 px of bloom by tier, a tighter glow inside it, the hard core inside that —
 * and the ink climbs as the rings tighten, which is what an eye reads as brightness rather than
 * as size.
 *
 * STILL NO SVG FILTER. A gaussian blur would be prettier and would repaint its filtered region
 * every time this layer renders, with up to 252 harbours on the glass; docs/MAP_ATMOSPHERE.md §7
 * measured this chart's frame budget instead of guessing at it. Three static circles that never
 * move are cheaper than one filter that does — and `PortsLayer` is memoised precisely so they do
 * not re-render while a fleet drifts.
 */
function HarbourLight({ x, y, tier, unitsPerPx }: { x: number; y: number; tier: number; unitsPerPx: number }) {
  return (
    <>
      <circle cx={x} cy={y} r={harbourLightHalo(tier, unitsPerPx)} className="fill-harbour-light/15" pointerEvents="none" />
      <circle cx={x} cy={y} r={harbourLightGlow(tier, unitsPerPx)} className="fill-harbour-light/35" pointerEvents="none" />
    </>
  )
}

/**
 * MEMOISED, AND THAT IS A FRAME-RATE DECISION (2026-10-12: *"the game looks stuck. optimize it so
 * that it is smoothe"*). A harbour does not move. A fleet drifts between reads, so the chart
 * re-renders on a clock — and without this, every one of those frames also rebuilt 252 harbours,
 * which at the globe is now 252 x 3 circles of light for a picture that is identical to the last
 * one. The props here change only when the zoom, the pan or the roles change; `marks` and
 * `portRoles` are already memoised upstream by ./chartModel.ts, so the comparison holds.
 */
export const PortsLayer = memo(function PortsLayer({
  marks,
  portRoles,
  selectedCode,
  unitsPerPx,
  lightsOnly,
}: {
  marks: readonly PortMark[]
  portRoles: ReadonlyMap<string, PortRole>
  selectedCode: string | null
  unitsPerPx: number
  /** Pulled back past `PURE_LIGHT_SPAN_DEG`: a city is light and NOTHING else — no triangle, no
   *  ring. Her LIGHT is drawn at every zoom either way (owner, 2026-10-12). */
  lightsOnly: boolean
}) {
  const px = (n: number) => n * unitsPerPx

  return (
    <g data-testid="map-ports">
      {marks.map(({ port, full: hasMark }) => {
        const { x, y } = project(port)
        // AT THE WIDEST SPAN A CITY IS LIGHT AND NOTHING ELSE (owner, 2026-10-12, on seeing the
        // first lit sheet: *"i told you to show in lights"*). `PORT_TIER_BANDS` keeps the great
        // ports drawn as MARKS longest, which is right on a working chart and wrong past the point
        // where the ships have already given up their hulls: 35 little triangles outlined on top of
        // 35 blooms is a hybrid, and it fights the one thing this band exists to show. Past the
        // same rung the fleets use, every harbour renders as its light.
        //
        // THE SAME RUNG, DELIBERATELY. The sheet changes character once — hulls to embers, marks to
        // lights — so there is never a frame showing a 10 px triangle beside a 1.6 px ember.
        const full = hasMark && !lightsOnly
        if (!full) {
          // THE LIGHT — the harbour at a zoom too wide for its mark. Nameless, roadless, and not
          // a target (chartModel.ts says why): zoom in, and it is the marker.
          //
          // OWNER ROW 125 (2026-10-12): *"when i zoom out, i want cities to be bright light, in a
          // dark map, visually beautiful."* Row 94 made this a dot; it is now a dot WITH ITS LIGHT
          // — a halo several times the core's radius at low opacity, under the same core radius the
          // dot already had, so nothing moved or grew and what was added is the glow. Brightness
          // follows size_tier (glyphs.ts `harbourLightHalo`), so the great entrepôts read first on
          // a wide sheet and a one-quay coast is a faint spark: the owner's "bright light" with no
          // legend and no second colour, which is MAP_ATMOSPHERE §4's rule.
          //
          // TWO CIRCLES AND NO FILTER, deliberately. An SVG blur would look better and would
          // repaint its filtered region on every drift frame, with up to 252 harbours on the glass
          // — and §7 of that document measured this chart's frame budget rather than guessing at it.
          return (
            <g
              key={port.code}
              data-port-code={port.code}
              data-port-tier={port.sizeTier}
              data-port-kind={port.kind}
              data-port-mark="dot"
              data-port-lit="yes"
              data-port-x={x}
              data-port-y={y}
            >
              <HarbourLight x={x} y={y} tier={port.sizeTier} unitsPerPx={unitsPerPx} />
              <circle
                cx={x}
                cy={y}
                r={px(GLYPH.portDotRadius)}
                className="fill-harbour-light"
                pointerEvents="none"
              />
            </g>
          )
        }
        const active = portRoles.has(port.code)
        const selected = selectedCode === port.code
        const scale = portMarkScale(port.sizeTier)
        // 0036: a SEA PLACE — a bank, a strait, a belt of wind — is a lozenge, never the harbour
        // triangle: the triangle promises a town, and out there is only water. Same ramps, same
        // weight rule, same everything else; the SHAPE is the one honest difference.
        const mark = port.kind === 'SEA_PLACE' ? lozengePath : trianglePath

        // `data-port-code` is the mark's IDENTITY, beside the tier and kind that were already
        // here. A harbour's printed NAME is a rendering decision — the declutterer drops it when a
        // fleet's own label takes that spot, which is precisely the case OWNER_REQUESTS row 49
        // lives in — so a drive that can only aim by the word can never aim at the harbour a fleet
        // is standing in. The code can.
        return (
          <g
            key={port.code}
            data-port-code={port.code}
            data-port-tier={port.sizeTier}
            data-port-kind={port.kind}
            data-port-mark="full"
            data-port-lit="yes"
            data-port-x={x}
            data-port-y={y}
          >
            {/* HER LIGHT, UNDER HER MARK (owner row 125). The great ports are exactly the ones the
                tier bands keep drawing as marks longest, so gating the glow on `full` left the
                biggest cities in the world as the only unlit harbours at the globe — 35 of them,
                counted by tests/map.night.spec.ts. The mark is unchanged and still drawn on top;
                the halo is behind it, and the TRIANGLE keeps its own ink, because the weight rule
                (quiet vs a port a fleet is using) is a different channel from how big a place is
                and row 125 was not asked to merge them. */}
            <HarbourLight x={x} y={y} tier={port.sizeTier} unitsPerPx={unitsPerPx} />
            <path
              d={
                active
                  ? mark(x, y, px(GLYPH.loudPortHalfWidth * scale), px(GLYPH.loudPortHeight * scale))
                  : mark(x, y, px(GLYPH.quietPortHalfWidth * scale), px(GLYPH.quietPortHeight * scale))
              }
              // The quiet mark's ink went from `/70` to `/85` in the same change that gave the coast
              // a real body: a hollow triangle at 70% ink stands on the new land at 1.74 : 1, which
              // is a mark you have to look for. At 85% it is 2.33 : 1 on land and 4.87 : 1 on water,
              // still visibly quieter than the brass a port your fleet is using is filled with.
              className={active ? 'fill-accent stroke-chart-sea' : 'fill-transparent stroke-ink-faint/85'}
              strokeWidth={portStrokeWidth(port.sizeTier)}
              strokeLinejoin="round"
              vectorEffect="non-scaling-stroke"
              pointerEvents="none"
            />

            {/* ROW 90 — A GREAT HARBOUR WEARS A RING. The two ramps make Lisbon 1.75× Setúbal,
                which is a difference you measure; a thin ring round the 35 tier-5 marks is one
                you see from across the room. Hollow, faint ink, never brass: brass is "yours". */}
            {port.sizeTier >= GREAT_PORT_TIER && (
              <circle
                cx={x}
                cy={y}
                r={px(GLYPH.greatPortRingRadius)}
                className="fill-none stroke-ink-faint/45"
                strokeWidth={GLYPH.glyphStroke * 0.7}
                vectorEffect="non-scaling-stroke"
                pointerEvents="none"
                data-testid="map-port-ring"
              />
            )}

            {selected && (
              <circle
                cx={x}
                cy={y}
                r={px(GLYPH.destinationRingRadius + 4)}
                className="fill-none stroke-ink/60"
                strokeWidth={GLYPH.glyphStroke}
                vectorEffect="non-scaling-stroke"
                pointerEvents="none"
              />
            )}
          </g>
        )
      })}
    </g>
  )
})

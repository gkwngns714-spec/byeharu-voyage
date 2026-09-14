import { project } from '../lib/geo'
import type { PortMark, PortRole } from './chartModel'
import { GREAT_PORT_TIER } from './chartView'
import { GLYPH, lozengePath, portMarkScale, portStrokeWidth, trianglePath } from './glyphs'

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
// ROW 93 (2026-09-14, the owner: "all the ports in the game when i zoom out, it can be a dot,
// then once zoomed in i will be able to see the marker"): a port below the zoom's tier floor is
// not left off the sheet any more — it is drawn as a DOT, `GLYPH.portDotRadius`, in the quiet
// ink, no ring, no name, no roads, no tap. Same `<g data-port-code>`, same identity, the dot is that
// harbour's rendering at this zoom and it becomes the triangle on the zoom ladder the tier bands
// already define. `data-port-mark` says which it is, so a drive can count both.
//
// THE MARK'S POSITION IS WRITTEN ON THE GROUP (`data-port-x`, `data-port-y`, chart units) for
// the same reason `data-port-code` is: a mark's `d` is a shape and not a coordinate, and the
// landfall spec (row 91) has to read where each harbour was actually drawn.
//
// THIS LAYER DRAWS MARKS AND NOTHING ELSE. No text (labels are placed as a set by ./labels.ts and
// drawn by LabelsLayer — a label placed here could not know what the next port is about to print)
// and no handler at all (taps are resolved by one nearest-wins hit test on the surface,
// ./hitTest.ts). There is nothing in this file that could ever grow into an order.

export function PortsLayer({
  marks,
  portRoles,
  selectedCode,
  unitsPerPx,
}: {
  marks: readonly PortMark[]
  portRoles: ReadonlyMap<string, PortRole>
  selectedCode: string | null
  unitsPerPx: number
}) {
  const px = (n: number) => n * unitsPerPx

  return (
    <g data-testid="map-ports">
      {marks.map(({ port, full }) => {
        const { x, y } = project(port)
        if (!full) {
          // THE DOT — the harbour at a zoom too wide for its mark. Nameless, roadless, and not
          // a target (chartModel.ts says why): zoom in, and it is the marker.
          return (
            <g
              key={port.code}
              data-port-code={port.code}
              data-port-tier={port.sizeTier}
              data-port-kind={port.kind}
              data-port-mark="dot"
              data-port-x={x}
              data-port-y={y}
            >
              <circle cx={x} cy={y} r={px(GLYPH.portDotRadius)} className="fill-ink-faint/85" pointerEvents="none" />
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
            data-port-x={x}
            data-port-y={y}
          >
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
}

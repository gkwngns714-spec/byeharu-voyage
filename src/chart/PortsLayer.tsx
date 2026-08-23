import { project } from '../lib/geo'
import type { PortRole } from './chartModel'
import { GLYPH, lozengePath, portMarkScale, portStrokeWidth, trianglePath } from './glyphs'
import type { MapPort } from './mapTypes'

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
// `ports` is the VISIBLE set (chartModel.visiblePorts) — already filtered by the glass and by the
// zoom's tier floor. This layer draws exactly what it is handed and makes no decision of its own
// about what belongs on the sheet.
//
// THIS LAYER DRAWS MARKS AND NOTHING ELSE. No text (labels are placed as a set by ./labels.ts and
// drawn by LabelsLayer — a label placed here could not know what the next port is about to print)
// and no handler at all (taps are resolved by one nearest-wins hit test on the surface,
// ./hitTest.ts). There is nothing in this file that could ever grow into an order.

export function PortsLayer({
  ports,
  portRoles,
  selectedCode,
  unitsPerPx,
}: {
  ports: readonly MapPort[]
  portRoles: ReadonlyMap<string, PortRole>
  selectedCode: string | null
  unitsPerPx: number
}) {
  const px = (n: number) => n * unitsPerPx

  return (
    <g data-testid="map-ports">
      {ports.map((port) => {
        const { x, y } = project(port)
        const active = portRoles.has(port.code)
        const selected = selectedCode === port.code
        const scale = portMarkScale(port.sizeTier)
        // 0036: a SEA PLACE — a bank, a strait, a belt of wind — is a lozenge, never the harbour
        // triangle: the triangle promises a town, and out there is only water. Same ramps, same
        // weight rule, same everything else; the SHAPE is the one honest difference.
        const mark = port.kind === 'SEA_PLACE' ? lozengePath : trianglePath

        return (
          <g key={port.code} data-port-tier={port.sizeTier} data-port-kind={port.kind}>
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

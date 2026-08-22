import { project } from '../lib/geo'
import type { PortRole } from './chartModel'
import { GLYPH, portMarkScale, trianglePath } from './glyphs'
import type { MapPort } from './mapTypes'

// GLYPH 1 — THE PORT, in two weights and five sizes.
//
// DESIGN §E.5: "Ports the fleet is not using are quieter than ports it is." So one shape, two
// WEIGHTS: a hollow triangle in faint ink for a port nothing of yours touches, a filled brass one
// for a port a fleet is at or bound for. Which is which comes from `portRoles` on the chart model —
// the same table the label engine ranks by, so a loud glyph and a high-priority label can never
// disagree.
//
// On top of the weight, the SIZE is the port's own `size_tier` (./glyphs.ts, portMarkScale). That
// is what keeps 214 harbours legible: the eye reads the great ports first because they are drawn
// first-sized, not because someone hand-picked a list.
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

        return (
          <g key={port.code}>
            <path
              d={
                active
                  ? trianglePath(x, y, px(GLYPH.loudPortHalfWidth * scale), px(GLYPH.loudPortHeight * scale))
                  : trianglePath(x, y, px(GLYPH.quietPortHalfWidth * scale), px(GLYPH.quietPortHeight * scale))
              }
              className={active ? 'fill-accent stroke-chart-sea' : 'fill-transparent stroke-ink-faint/70'}
              strokeWidth={GLYPH.glyphStroke}
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

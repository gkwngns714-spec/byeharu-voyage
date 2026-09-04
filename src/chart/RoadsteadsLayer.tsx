import { GLYPH } from './glyphs'
import type { MapPort } from './mapTypes'
import { roadsteadMarks } from './roadsteads'

// THE ROADS — chart furniture, drawn under the ports (0076).
//
// The owner, OWNER_REQUESTS row 72: *"create a perpendicular helper line (dotted) that is the
// shortest point between the land city and nearby shore - sea. Then create a point there, and when
// the ship arrive at that point, consider it as the ship have landed on land."* The arrival half of
// that sentence is the server's — `cmd.do_sail` now ends a course at the roads and `voyage.settle`
// docks her at the port, unchanged since 0007. This file is the line and the point.
//
// WHAT IT DECIDES: nothing. ./roadsteads.ts decides which ports show their roads and where the two
// ends are; this maps that list to SVG, exactly as LabelsLayer maps `planLabels`. Both numbers on
// `MapPort` are SERVED — the chart never computes a roadstead (./roadsteads.ts's header).
//
// PAINT ORDER, which is a rule and not a habit (FleetsLayer.tsx:6-9: *"a dotted line crossing a
// port should pass behind it"*): coastline → tracks → ROADSTEADS → ports → fleets → labels.
// `ChartCanvas` is the only composer, and this file is exported to nobody (src/chart/index.ts,
// docs/SECTIONS.md:108).
//
// THE DASH IS `1 5`, borrowed rather than invented — it is the water AHEAD of a fleet
// (FleetsLayer.tsx:40), the sparsest dot in the vocabulary, and it already means *"a line not yet
// made good"*. Not `1 3` (the passage she has SAILED) and not `3 3` (a destination ring).
//
// THE INK IS FAINT, NOT ACCENT. Brass means *yours* on this chart; a roadstead is true of every
// harbour whether you use it or not, so it is drawn like the coastline is.
//
// THE HIT TEST IS DELIBERATELY NOT TOUCHED. `hitTest.ts` keeps its three subjects — port, fleet,
// open sea — and a tap near the roads still selects the nearest port, as today. A fourth subject
// inside the 38 px reach would make *"which port is this?"* ambiguous, which glyphs.ts:72 and
// docs/OWNER_REQUESTS.md:102 both name as worse than no button. Stated as an omission, not missed.

export function RoadsteadsLayer({
  ports,
  unitsPerPx,
}: {
  /** The VISIBLE set — `visiblePorts`, the same list `PortsLayer` is handed. */
  ports: readonly MapPort[]
  unitsPerPx: number
}) {
  return (
    <g pointerEvents="none" data-testid="map-roadsteads">
      {roadsteadMarks(ports, unitsPerPx).map((mark) => (
        <g key={mark.code} data-roadstead-code={mark.code}>
          <path
            d={mark.lineD}
            className="fill-none stroke-ink-faint/70"
            strokeWidth={GLYPH.trackStroke}
            strokeDasharray="1 5"
            strokeLinecap="round"
            vectorEffect="non-scaling-stroke"
          />
          <circle
            cx={mark.at.x}
            cy={mark.at.y}
            r={GLYPH.roadsteadRadius * unitsPerPx}
            className="fill-none stroke-ink-faint/85"
            strokeWidth={GLYPH.glyphStroke}
            vectorEffect="non-scaling-stroke"
          />
        </g>
      ))}
    </g>
  )
}

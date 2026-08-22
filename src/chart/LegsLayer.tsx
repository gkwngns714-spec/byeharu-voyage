import { GLYPH } from './glyphs'

// THE SEA LANES — where a ship can actually go, drawn as quietly as a thing can be drawn.
//
// `snapshot.legs` is the water: 782 crossings whose distances are SAILED distances, so the graph is
// the real answer to "where can I sail from here". A player who cannot see it has to guess, and a
// player who sees all of it at once sees a spiderweb — §E.5's chart is a quiet one.
//
// So: ONE hairline path, at 12% opacity, and only when the view is inside LEG_SPAN_LIMIT
// (./chartView.ts). Pulled back, the whole layer is not rendered — MapScreen does not pass a `d` at
// all, so there is no faded ghost of it and nothing to reconcile.
//
// It is UNDER every MARK: the paint order in MapScreen puts it above the pale coastline (so a lane
// is visible where it runs past a headland) and beneath the tracks, the port marks, the fleets and
// the names — it is the paper's grain, not a thing drawn on it.
//
// It carries no handler and no key: it is one <path> for every lane in view, built by
// `legWebPath` (./route.ts). Nothing here is tappable — a lane is a fact about the sea, not a
// control, and tapping it could only ever mean "sail this", which the map does not do.

export function LegsLayer({ d }: { d: string }) {
  if (!d) return null
  return (
    <path
      d={d}
      className="fill-none stroke-ink-faint/25"
      strokeWidth={GLYPH.coastStroke}
      vectorEffect="non-scaling-stroke"
      pointerEvents="none"
      data-testid="map-legs"
    />
  )
}

import { GLYPH } from './glyphs'
import type { LabelTone, PlacedLabel } from './labels'

// EVERY NAME ON THE CHART, DRAWN IN ONE PLACE.
//
// The positions are not computed here — they arrive already placed from ./labels.ts, which sees
// all of them at once and is the only thing that can therefore keep two apart. This layer just
// paints what it is handed, last of all, so a name is never under a coastline or a glyph.
//
// The `paint-order: stroke` trick draws a sea-coloured halo BEHIND the letters, which is what
// keeps a name readable where it crosses land without putting a box round it.
//
// ROW 90: the seas' names are in the SAME plan — placed last, at the lowest priority, centred on
// their anchors (./seaNames.ts) — and painted FIRST here, in their own group, so a water's name
// is ground under every place's name. ROW 93: a region's name (./regions.ts) is ground the same
// way, in the same group, and is only in the plan while the regions filter is on. Each label
// carries the size and spacing it was planned at
// (`sizePx`, `spacingEm`), so the box the planner kept clear is the box that is drawn.

const TONE: Record<LabelTone, string> = {
  fleet: 'fill-accent',
  'port-active': 'fill-ink',
  'port-quiet': 'fill-ink-faint',
  sea: 'fill-chart-sea-name',
  // A region's name (row 93) is ground like a sea's, in the same thinned ink, a size up.
  region: 'fill-chart-sea-name',
}

function Name({ label, unitsPerPx }: { label: PlacedLabel; unitsPerPx: number }) {
  return (
    <text
      x={label.x}
      y={label.y}
      fontSize={label.sizePx * unitsPerPx}
      textAnchor={label.anchor}
      dominantBaseline="middle"
      className={`stroke-chart-sea font-mono ${TONE[label.tone]}`}
      strokeWidth={GLYPH.labelHaloWidth * unitsPerPx}
      style={{ paintOrder: 'stroke', letterSpacing: label.spacingEm > 0 ? `${label.spacingEm}em` : undefined }}
      data-label-id={label.id}
      data-label-side={label.side}
    >
      {label.text}
    </text>
  )
}

export function LabelsLayer({ labels, unitsPerPx }: { labels: readonly PlacedLabel[]; unitsPerPx: number }) {
  const ground = labels.filter((l) => l.tone === 'sea' || l.tone === 'region')
  const places = labels.filter((l) => l.tone !== 'sea' && l.tone !== 'region')
  return (
    <>
      <g pointerEvents="none" data-testid="map-sea-names">
        {ground.map((label) => (
          <Name key={label.id} label={label} unitsPerPx={unitsPerPx} />
        ))}
      </g>
      <g pointerEvents="none" data-testid="map-labels">
        {places.map((label) => (
          <Name key={label.id} label={label} unitsPerPx={unitsPerPx} />
        ))}
      </g>
    </>
  )
}

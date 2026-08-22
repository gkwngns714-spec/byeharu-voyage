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

const TONE: Record<LabelTone, string> = {
  fleet: 'fill-accent',
  'port-active': 'fill-ink',
  'port-quiet': 'fill-ink-faint',
}

export function LabelsLayer({ labels, unitsPerPx }: { labels: readonly PlacedLabel[]; unitsPerPx: number }) {
  return (
    <g pointerEvents="none" data-testid="map-labels">
      {labels.map((label) => (
        <text
          key={label.id}
          x={label.x}
          y={label.y}
          fontSize={GLYPH.labelSize * unitsPerPx}
          textAnchor={label.anchor}
          dominantBaseline="middle"
          className={`stroke-chart-sea font-mono ${TONE[label.tone]}`}
          strokeWidth={GLYPH.labelHaloWidth * unitsPerPx}
          style={{ paintOrder: 'stroke' }}
          data-label-id={label.id}
          data-label-side={label.side}
        >
          {label.text}
        </text>
      ))}
    </g>
  )
}

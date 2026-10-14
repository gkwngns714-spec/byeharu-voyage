import { unproject, type LatLon } from '../lib/geo'
import { GLYPH } from './glyphs'
import type { LabelTone, PlacedLabel } from './labels'
import { nightStyle } from './sun'

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
//
// THE SUN (2026-10-14): a name carries `--night` for the point it names, and its ink and halo mix
// from the night's tokens toward the day's dark mark on the day's water (`.bv-sun-name-*`,
// src/index.css) — the same one number every mark on this sheet reads.

/** Each tone's night class (the token the scheme defines) beside its Sun-mixing rule. */
const TONE: Record<LabelTone, string> = {
  fleet: 'fill-accent',
  'port-active': 'bv-sun-name-active fill-ink',
  'port-quiet': 'bv-sun-name-quiet fill-ink-faint',
  sea: 'bv-sun-name-water fill-chart-sea-name',
  // A region's name (row 93) is ground like a sea's, in the same thinned ink, a size up.
  region: 'bv-sun-name-water fill-chart-sea-name',
}

function Name({ label, unitsPerPx, sun }: { label: PlacedLabel; unitsPerPx: number; sun: LatLon }) {
  return (
    <text
      x={label.x}
      y={label.y}
      fontSize={label.sizePx * unitsPerPx}
      textAnchor={label.anchor}
      dominantBaseline="middle"
      className={`bv-sun-name-halo stroke-chart-sea font-mono ${TONE[label.tone]}`}
      strokeWidth={GLYPH.labelHaloWidth * unitsPerPx}
      style={{
        paintOrder: 'stroke',
        letterSpacing: label.spacingEm > 0 ? `${label.spacingEm}em` : undefined,
        ...nightStyle(unproject({ x: label.x, y: label.y }), sun),
      }}
      data-label-id={label.id}
      data-label-side={label.side}
    >
      {label.text}
    </text>
  )
}

export function LabelsLayer({
  labels,
  unitsPerPx,
  sun,
}: {
  labels: readonly PlacedLabel[]
  unitsPerPx: number
  /** Where the Sun is overhead (./sun.ts). */
  sun: LatLon
}) {
  const ground = labels.filter((l) => l.tone === 'sea' || l.tone === 'region')
  const places = labels.filter((l) => l.tone !== 'sea' && l.tone !== 'region')
  return (
    <>
      <g pointerEvents="none" data-testid="map-sea-names">
        {ground.map((label) => (
          <Name key={label.id} label={label} unitsPerPx={unitsPerPx} sun={sun} />
        ))}
      </g>
      <g pointerEvents="none" data-testid="map-labels">
        {places.map((label) => (
          <Name key={label.id} label={label} unitsPerPx={unitsPerPx} sun={sun} />
        ))}
      </g>
    </>
  )
}

import { useLayoutEffect } from 'react'
import { unproject, type LatLon } from '../lib/geo'
import { GLYPH } from './glyphs'
import { MapFlagDefs } from './MapFlagDefs'
import { flagSymbolId } from './flagSymbolStore'
import { FLAG_ADVANCE_EM, FLAG_HEIGHT_EM, type LabelTone, type PlacedLabel } from './labels'
import { setPlacedNames } from './placedNames'
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
//
// A HARBOUR'S FLAG (2026-10-18, the owner: "beside the name show flag"; then "the flag is too far
// away from the name of city, it looks unnatural") stands FIRST and SNUG: the flag at the box's
// left edge, the name set from FLAG_ADVANCE_EM after it, so the gap between them is FLAG_GAP_EM
// (~3.5 px) at every zoom — the name is anchored to the flag, never to an estimated far end (the
// estimate is a monospace advance and the face is a sans, so a flag placed at the box's far end
// stood a word's slack away from the letters). Flag and name are one unit, and a tap anywhere on it
// opens the city (./placedNames.ts → hitTest.ts `names`). The picture is one `<symbol>` per nation
// (./flagSymbolStore.ts), the same bundled file a tray's Flag draws, in the same 3:2 box.

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
  const size = label.sizePx * unitsPerPx
  const text = (
    <text
      x={label.flag ? label.box.x + FLAG_ADVANCE_EM * size : label.x}
      y={label.y}
      fontSize={size}
      textAnchor={label.flag ? 'start' : label.anchor}
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
  if (!label.flag) return text
  const flagHeight = FLAG_HEIGHT_EM * size
  return (
    <g data-label-flag={label.flag}>
      {/* Drawn at a 30×20 box and scaled down to the label's size: the chart's units are tiny (a
          name is ~0.15 units tall), and Chrome rasterises a fraction of a unit to nothing. */}
      <use
        href={`#${flagSymbolId(label.flag)}`}
        width={30}
        height={20}
        transform={`translate(${label.box.x} ${label.y - flagHeight / 2}) scale(${flagHeight / 20})`}
        data-testid="map-label-flag"
      />
      {text}
    </g>
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
  // The names actually drawn, for the map's tap (./placedNames.ts): a tap on a name opens its city.
  useLayoutEffect(() => setPlacedNames(labels), [labels])
  return (
    <>
      <MapFlagDefs codes={places.flatMap((l) => (l.flag ? [l.flag] : []))} />
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

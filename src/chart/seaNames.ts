// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SEAS' NAMES — which waters ask to be named at this zoom, and where. PURE.
//
// ── §7B, ANSWERED FIRST ────────────────────────────────────────────────────────────────────────
// WHAT IT IS   one concept: A NAMED WATER AS A LABEL REQUEST — data/seas.json's 51 seas turned
//              into the same `LabelRequest`s a port's name is, so the ONE planner (./labels.ts)
//              keeps a sea's name off every harbour's mark and name. There is no second collision
//              rule and no second text layer: `LabelsLayer` paints what `planLabels` returns.
// WHERE        src/chart, beside ./labels.ts and ./roadsteads.ts — the DECISION about what is on
//              the paper is data, and data is what a plain Node spec can hold to account
//              (tests/map.atmosphere.spec.ts reads data/seas.json off disk and runs this).
// SECOND CALLER  `ChartCanvas` today; the minimap deliberately not (its 144 px cannot set a word).
//              A future "waters ahead" highlight would read `MapSea.at` from here, not re-parse.
// WRONG SHAPE  a sea-name layer with its own placement — two planners that disagree about which
//              names fit, which is the defect ./labels.ts was written to end.
//
// ── WHAT THE DATA IS, AND IS NOT ───────────────────────────────────────────────────────────────
// `centroid` is, in the file's own words, "a hand-placed label anchor for map rendering, NOT a
// surveyed centroid". That is exactly a label's anchor, copied. `kind` is READ OFF THE NAME —
// the file has no rank column, and a water the data calls an Ocean is set at every zoom while a
// sea waits for `SEA_NAME_SPAN_LIMIT`. If the file ever grows a rank, this is the one place to
// read it instead. `danger` and `note` are the server's business on a voyage (`MapWater`), not a
// backdrop's, and are not carried.
//
// Tolerant like ./coastlineBuild.ts: a malformed row is skipped, never thrown — a backdrop may
// not take the chart down.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { project } from '../lib/geo'
import { SEA_NAME_SPAN_LIMIT } from './chartView'
import { GLYPH } from './glyphs'
import { LABEL_PRIORITY, type LabelRequest } from './labels'
import type { MapSea } from './mapTypes'

interface SeaSource {
  readonly id?: unknown
  readonly name?: unknown
  readonly centroid?: { readonly lat?: unknown; readonly lon?: unknown }
}

/** Every well-formed sea in a parsed data/seas.json, in the file's own order. */
export function mapSeasOf(json: unknown): MapSea[] {
  const rows = (json as { seas?: unknown })?.seas
  if (!Array.isArray(rows)) return []
  const out: MapSea[] = []
  for (const row of rows as SeaSource[]) {
    const lat = row?.centroid?.lat
    const lon = row?.centroid?.lon
    if (typeof row?.id !== 'string' || typeof row?.name !== 'string') continue
    if (typeof lat !== 'number' || typeof lon !== 'number' || !Number.isFinite(lat) || !Number.isFinite(lon)) continue
    out.push({
      id: row.id,
      name: row.name,
      at: { lat, lon },
      kind: /\bOcean\b/.test(row.name) ? 'ocean' : 'sea',
    })
  }
  return out
}

/**
 * The names the water asks for at this span — an ocean at every zoom, a sea once the frame is
 * inside `SEA_NAME_SPAN_LIMIT`. Every request is CENTRED on its anchor (there is no glyph), set
 * in the sea tone at the sea sizes, and at `LABEL_PRIORITY.sea`, below every harbour, so the
 * planner places them last and drops any that would touch a name or a mark.
 *
 * Off-glass anchors are dropped here rather than by the frame test, for the reason
 * `mapLabelRequests` gives: asking the planner about water that is not on the paper is a
 * question whose answer is already known.
 */
export function seaNameRequests(seas: readonly MapSea[], view: { x: number; y: number; width: number; height: number }): LabelRequest[] {
  const requests: LabelRequest[] = []
  const showSeas = view.width <= SEA_NAME_SPAN_LIMIT
  for (const sea of seas) {
    if (sea.kind === 'sea' && !showSeas) continue
    const at = project(sea.at)
    if (at.x < view.x || at.x > view.x + view.width || at.y < view.y || at.y > view.y + view.height) continue
    requests.push({
      id: `sea:${sea.id}`,
      text: sea.name,
      at,
      priority: LABEL_PRIORITY.sea,
      tone: 'sea',
      placement: 'centred',
      sizePx: sea.kind === 'ocean' ? GLYPH.oceanNameSize : GLYPH.seaNameSize,
      spacingEm: GLYPH.seaNameSpacingEm,
    })
  }
  return requests
}

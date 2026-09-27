// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT DID THEY TAP — nearest wins, decided in ONE place.
//
// THE BUG THIS EXISTS TO PREVENT. The obvious way to make a glyph tappable is to give each one an
// invisible 44 px circle (the mobile touch floor) and let the browser sort it out. Measured on the
// opening view of a 390 px phone, the chart shows 38.7° across, so one pixel is 0.099° — and Cádiz
// to Sevilla is 54 nm, about 9 px. Every one of those 44 px circles overlaps three of its
// neighbours, and which port you get is decided by SVG paint order, not by where your thumb is.
// A player would tap Cádiz and open Sevilla, at the default zoom, on the commonest phone width.
//
// So the map does not hit-test with elements at all. One pure function takes the point the thumb
// landed on and returns the nearest thing to it, or nothing. Nearest is nearest at every zoom, and
// there is no paint order to lose to.
//
// TIES GO TO THE FLEET: a fleet at anchor is drawn ON its port, so their distances are equal. The
// fleet is the thing the player put there, so it is the thing they meant.
//
// TIES BETWEEN TWO HARBOURS are broken by the harbour, never by the array. Two ports exactly
// equidistant from a thumb used to be resolved by whichever came first in `ports` — which is seed
// order, i.e. the same "decided by something that is not where your thumb is" this file exists to
// abolish, one layer down from paint order. So: the GREATER harbour wins (`sizeTier` — it is drawn
// bigger and firmer, so it is the one the eye was on), and if they rank equally the lower `code`
// wins, which is a fact about the world and cannot be reordered by a later read. It matters more
// since the reach grew to 38 px (./glyphs.ts): more pairs are inside it at once.
//
// A DOT IS A CITY TOO (row 104, 2026-09-18), AT A SHORTER REACH. The names keep the full reach
// (`GLYPH.hitRadius`, mark + gap + word); a dot answers only within `GLYPH.dotHitRadius` — half
// a touch — because there is nothing beside it to aim at. Between a name and a dot both within
// their reach: the name wins outright when the thumb is within half a touch of its MARK, else
// the nearer of the two. So the owner's zoomed-out tap on a lone dot opens that city instead of
// the sea's coordinates, and the Cádiz/Sanlúcar theft (a dot 5 px north of the mark, nearer to
// the WORD "Cadiz" than the mark it names, row 94) cannot recur: that tap is well within half a
// touch of Cádiz's mark, so Cádiz it is.
//
// This is selection, and selection is a VIEW change (DESIGN §E.5). It cannot issue an order — the
// only value it can return is a `MapSelection`, which is a name, not a verb.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { project, type Point } from '../lib/geo'
import type { ChartModel } from './chartModel'
import type { MapPort, MapSelection } from './mapTypes'

function distance(a: Point, b: Point): number {
  return Math.hypot(a.x - b.x, a.y - b.y)
}

/**
 * The nearest fleet or port to `at`, within `radius`. All three are in CHART UNITS — the caller
 * converts the touch reach from pixels (`GLYPH.hitRadius`, derived there and measured), so the
 * reach stays the same number of SCREEN pixels at every zoom while the paper under it scales.
 *
 * `ports` is the FULL half of the sheet (chartModel.visiblePorts — the marks that wear a name and
 * their roads), within `radius`. `dots` is the other half (chartModel.dotPorts), within
 * `dotRadius` — a smaller reach, because a dot has no name beside it to aim at — and behind a
 * name whose mark is within `dotRadius` of the thumb (see the header). A port not on the sheet at all is not tappable, which is the only
 * answer that can never surprise anyone: with 224 harbours in the table, hit-testing ports the
 * player cannot see would open a detail card for a mark that is not there.
 *
 * Returns `null` when the tap landed on open water, which clears the selection: tapping the sea to
 * dismiss is the gesture every map has, and it costs nothing.
 */
export function hitTest(
  model: ChartModel,
  ports: readonly MapPort[],
  at: Point,
  radius: number,
  dots: readonly MapPort[] = [],
  dotRadius = 0,
): MapSelection {
  let nearestFleet: { id: string; d: number } | null = null
  for (const f of model.fleets) {
    const d = distance(project(f.at), at)
    if (d <= radius && (!nearestFleet || d < nearestFleet.d)) nearestFleet = { id: f.fleet.id, d }
  }

  const named = nearestOf(ports, at, radius)
  const dot = nearestOf(dots, at, dotRadius)
  // A name within HALF A TOUCH of its mark is what the thumb meant, whatever dot is nearer (the
  // Cádiz/Sanlúcar theft: the name's word lies to the right of the mark, the dot 5 px north).
  // Beyond that — the thumb out on the tail of a word, or in open water inside the name's wide
  // reach — a dot under it is the nearer thing, and the nearer thing wins as it does everywhere.
  const nearestPort = !dot ? named : !named ? dot : named.d <= dotRadius || named.d <= dot.d ? named : dot

  if (nearestFleet && (!nearestPort || nearestFleet.d <= nearestPort.d)) {
    return { kind: 'fleet', id: nearestFleet.id }
  }
  if (nearestPort) return { kind: 'port', code: nearestPort.port.code }
  return null
}

/** The nearest of `ports` to `at` within `radius`, ties broken by `beats` — the one rule for
 *  choosing among harbours, asked of the named half and then of the dots. */
function nearestOf(ports: readonly MapPort[], at: Point, radius: number): { port: MapPort; d: number } | null {
  let nearest: { port: MapPort; d: number } | null = null
  for (const p of ports) {
    const d = distance(project(p), at)
    if (d > radius) continue
    if (!nearest || d < nearest.d || (d === nearest.d && beats(p, nearest.port))) nearest = { port: p, d }
  }
  return nearest
}

/** Which of two EXACTLY equidistant harbours the tap meant — see the header. Never consulted for
 *  anything else: a nearer port has already won on distance before this is asked. */
function beats(candidate: MapPort, held: MapPort): boolean {
  if (candidate.sizeTier !== held.sizeTier) return candidate.sizeTier > held.sizeTier
  return candidate.code < held.code
}

/** Tapping the thing that is already selected clears it — one gesture, both directions, so nothing
 *  can get stuck open on a phone. */
export function toggleSelection(current: MapSelection, next: MapSelection): MapSelection {
  if (!next) return null
  if (current && current.kind === next.kind) {
    if (current.kind === 'fleet' && next.kind === 'fleet' && current.id === next.id) return null
    if (current.kind === 'port' && next.kind === 'port' && current.code === next.code) return null
  }
  return next
}

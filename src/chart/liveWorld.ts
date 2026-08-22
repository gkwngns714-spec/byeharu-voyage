// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WIRE, TURNED INTO A CHART — the ONE module in this folder that knows what an RPC looks like.
//
// This replaces src/features/map/sampleVoyages.ts, which is deleted. That file held twelve invented
// Iberian ports and four invented fleets and said, in its own header, that deleting it was the
// whole of "switch the map onto live data". This is the other half of that sentence.
//
// ── WHERE EVERY MARK ON THE CHART NOW COMES FROM ───────────────────────────────────────────────
//   ports    `world.snapshot().ports` — 214 real harbours, Wikidata coordinates, `size_tier` for
//            how loud each one is drawn.
//   legs     `world.snapshot().legs` — 782 SAILED distances (Lisboa→Cádiz is 248 nm, not the 188 nm
//            of the straight line, because Cape St Vincent is in the way). Drawn faint, close in.
//   fleets   `world.fleets()` — and for one at sea, `voyage.position`: the closed form of §D.2,
//            computed inside the transaction that owns it.
//
// ── THE RULE THIS MODULE EXISTS TO KEEP ────────────────────────────────────────────────────────
// THE POSITION IS COPIED, NEVER COMPUTED. `position.lat` / `position.lon` go straight onto the
// chart. There is no departure time here, no TIME_COMPRESSION, no speed profile and no progress
// formula, because the live store's third rule says so in as many words: "Speed, endurance, prices,
// %NBR, voyage position: all of them are computed inside the transaction that owns them. The
// client's job is to print them. There is no second implementation of any of it on this side of
// the wire." The old ./voyage.ts was that second implementation, and it is deleted.
//
// The consequence, stated plainly rather than papered over: BETWEEN READS THE FLEET DOES NOT MOVE.
// A read is the catch-up (worldStore rule 1), so the chart advances when the world is read again —
// and the caption prints how long ago that was, so the picture is never silently stale. Tweening
// towards a guessed position would put a second, wrong movement rule in the client, which is worse
// than a picture that is honest about being a reading.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { FleetView, SnapshotPort } from '../lib/rpc'
import type { MapFleet, MapPort } from './mapTypes'
import { voyageEtaMs } from '../domain/fleet'

/** The port table the chart draws. Field-for-field; nothing derived, nothing dropped but the
 *  columns a chart has no use for. */
export function mapPortsOf(ports: readonly SnapshotPort[]): MapPort[] {
  return ports.map((p) => ({
    code: p.code,
    name: p.name,
    country: p.country,
    lat: p.lat,
    lon: p.lon,
    sizeTier: p.size_tier,
  }))
}

/**
 * The player's fleets, reduced to the two states the chart can draw.
 *
 * A fleet is SAILING to the chart when the server placed it — `voyage.position` present. Otherwise
 * it lies in `port`. A fleet with neither (a voyage row the server could not place: degenerate
 * data, not a game state) is left off the chart rather than parked at a guessed coordinate; the
 * Fleets tab still holds the whole roster.
 */
export function mapFleetsOf(fleets: readonly FleetView[]): MapFleet[] {
  const out: MapFleet[] = []
  for (const f of fleets) {
    const position = f.voyage?.position
    if (f.voyage && position) {
      out.push({
        kind: 'sailing',
        id: f.id,
        name: f.name,
        leg: {
          fromCode: position.from_code,
          toCode: position.to_code,
          at: { lat: position.lat, lon: position.lon },
          legFrac: position.leg_frac,
          sailedNm: position.nm_done,
          totalNm: position.total_nm,
          // domain/fleet owns the parse (`eta` is an ISO string, not ms). A voyage WITH a served
          // position always has an eta, so the null arm is unreachable here — it is spelt rather
          // than asserted because a second Date.parse is how the three copies happened.
          etaMs: voyageEtaMs(f) ?? 0,
          destinationCode: f.voyage.to,
        },
      })
      continue
    }
    if (f.port) out.push({ kind: 'docked', id: f.id, name: f.name, portCode: f.port })
  }
  return out
}

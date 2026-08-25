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
//   courses  `world.fleets().voyage.course` — the WHOLE verified water polyline each voyage
//            sails (0039). The old 782-leg lane layer is deleted with the graph it drew.
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
    kind: p.kind,
  }))
}

/**
 * The player's fleets, reduced to the three states the chart can draw (0039).
 *
 * A fleet is SAILING to the chart when the server placed it — `voyage.position` present and the
 * served course drawable. At an open anchor she holds `anchor`. Otherwise she lies in `port`. A
 * fleet with none of those (degenerate data, not a game state) is left off the chart rather than
 * parked at a guessed coordinate; the Fleets tab still holds the whole roster.
 */
export function mapFleetsOf(fleets: readonly FleetView[]): MapFleet[] {
  const out: MapFleet[] = []
  for (const f of fleets) {
    const position = f.voyage?.position
    const course = f.voyage?.course
    if (f.voyage && position && course && course.length >= 2) {
      out.push({
        kind: 'sailing',
        id: f.id,
        name: f.name,
        voyage: {
          course: course.map(([lat, lon]) => ({ lat, lon })),
          segIndex: position.seg_index,
          at: { lat: position.lat, lon: position.lon },
          sailedNm: position.nm_done,
          totalNm: position.total_nm,
          // domain/fleet owns the parse (`eta` is an ISO string, not ms). A voyage WITH a served
          // position always has an eta, so the null arm is unreachable here — it is spelt rather
          // than asserted because a second Date.parse is how the three copies happened.
          etaMs: voyageEtaMs(f) ?? 0,
          destinationCode: f.voyage.to,
          destPoint: f.voyage.dest_point
            ? { lat: f.voyage.dest_point[0], lon: f.voyage.dest_point[1] }
            : null,
          // 0055 — THE WATERS AHEAD. Field for field, and NOTHING is derived here: the tier, the
          // note and both distances are `voyage.waters_ahead`'s, measured over the course the
          // server froze at departure. A build talking to a server that predates 0055 gets an
          // empty list and draws no rows, which is a truthful lesser answer rather than a crash
          // (docs/NO_SPAGHETTI.md §7C's mirror rule).
          waters: (f.voyage.waters ?? []).map((w) => ({
            code: w.sea,
            name: w.name,
            danger: w.danger,
            note: w.note,
            nmTo: w.nm_to,
            nmIn: w.nm_in,
            now: w.now,
          })),
        },
      })
      continue
    }
    if (f.anchor) {
      out.push({
        kind: 'anchored',
        id: f.id,
        name: f.name,
        at: { lat: f.anchor[0], lon: f.anchor[1] },
      })
      continue
    }
    if (f.port) out.push({ kind: 'docked', id: f.id, name: f.name, portCode: f.port })
  }
  return out
}

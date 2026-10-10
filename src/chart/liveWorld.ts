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

import type { FleetView, SnapshotPort, TrafficFleet } from '../lib/rpc'
import type { MapFleet, MapPort, MapTraffic } from './mapTypes'
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
    // 0076 — THE ROADS, field for field. `roadstead.nm` is the SERVED distance and the only thing
    // that decides whether a helper line is drawn at all; this module has no snap and wants none.
    roadstead: { lat: p.roadstead.lat, lon: p.roadstead.lon },
    roadsteadNm: p.roadstead.nm,
  }))
}

/** What `mapFleetOf` reads off a served fleet — a fleet of yours (`world.fleets`) or a merchant's
 *  (`world.sea_traffic`, 0099), which serve the voyage in the SAME shape (world.voyage_view). */
interface ServedFleet {
  readonly id: string
  readonly name: string
  /** Served for yours; a merchant's stores are not a player's business and are not served. */
  readonly endurance_days?: number
  readonly voyage: Omit<FleetView['voyage'] & object, 'id'> | null
  readonly anchor: [number, number] | null
  readonly port: string | null
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
    const m = mapFleetOf(f)
    if (m) out.push(m)
  }
  return out
}

/**
 * THE MERCHANTS (0099, docs/NPC_TRADERS.md §8.2), through the SAME per-fleet mapping as yours. A
 * merchant at sea is placed from the served position, copied, like every position here. A merchant
 * lying IN PORT is drawn at her own BERTH on the served roads: the anchorage is an area and the
 * server serves one point for it, so each hull takes her own deterministic place on a small ring
 * round that point (`fannedBerth`). That is the one place this module puts a mark somewhere the
 * server did not name, it is bounded by BERTH_FAN_DEG, and it exists because hulls drawn on one
 * pinpoint are one hull to the eye and to the hit test. `selected` is the open card's FULL course for one fleet: that row alone
 * carries more than the current segment, so her leg can be drawn while she is selected.
 *
 * THE CARD LENDS A TRACK AND NEVER A POSITION (see `trackedVoyage`).
 */
export function mapTrafficOf(
  traffic: readonly TrafficFleet[],
  selected: {
    readonly id: string
    readonly voyage: Omit<FleetView['voyage'] & object, 'id'> | null
    /** Her whole loop, leg by leg (0099, owner row 112) — the card's, so only ever the open one. */
    readonly legs?: readonly { readonly course: readonly [number, number][] }[] | null
  } | null = null,
): MapTraffic[] {
  const out: MapTraffic[] = []
  for (const t of traffic) {
    const docked = t.voyage === null && t.port !== null && t.roadstead !== null
    const voyage = selected && selected.id === t.id && t.voyage ? trackedVoyage(t.voyage, selected.voyage) : t.voyage
    // DOCKED MERCHANTS ARE FANNED, NOT STACKED — and the place is HERS, not her neighbours'. A
    // first cut counted her position in the served list, so a hull shifted along the ring whenever
    // another merchant docked at or left the same harbour (measured: ~6 px in the 1280 Lisbon
    // frame, more when zoomed in — the 2026-10-10 review). Derived from her own id, a merchant
    // keeps one place at a berth for as long as she exists, whoever else is lying there.
    const berthIndex = docked ? berthSlotOf(t.id) : 0
    const m = mapFleetOf({
      id: t.id,
      name: t.name,
      voyage,
      anchor: docked ? fannedBerth(t.roadstead!, berthIndex) : t.anchor,
      port: null,
    })
    if (!m) continue
    const nextLap = t.next_lap_at ? Date.parse(t.next_lap_at) : NaN
    out.push({
      ...m,
      company: t.company,
      ink: t.ink,
      docked,
      berthCode: docked ? t.port : null,
      nextLapAtMs: Number.isFinite(nextLap) ? nextLap : null,
      berthIndex,
      // THE LOOP SHE RUNS, not merely the leg she is on (owner row 112). Copied leg by leg from the
      // card, like every other position here; a leg of fewer than two points draws nothing rather
      // than a guessed line.
      loop:
        selected && selected.id === t.id && selected.legs
          ? selected.legs
              .filter((l) => l.course.length >= 2)
              .map((l) => l.course.map(([lat, lon]) => ({ lat, lon })))
          : null,
    })
  }
  return out
}

/**
 * THE SELECTED MERCHANT'S WHOLE LEG, WITHOUT LETTING THE CARD MOVE HER (2026-10-10).
 *
 * `world.sea_traffic` serves every merchant the CURRENT SEGMENT only — course `[p[seg], p[seg+1]]`,
 * `seg_index` re-based to 0 — which is all ./drift.ts needs. `world.npc_fleet_card` serves the open
 * merchant's FULL course, so her remaining leg can be drawn. The card is re-asked on the beat and
 * lands AFTER it, so taking the card's `position` as well made the ONE hull the player is looking at
 * jump backwards on every beat and then leap forward when the new card arrived (measured at 390px:
 * −25.2 / −20.0 / −6.5 px, each followed ~70 ms later by a +20.9…+24.6 px leap; no other hull ever
 * moved backwards). That is the teleport ./drift.ts exists to remove, reintroduced for the selected
 * hull alone.
 *
 * So: the POSITION is always the traffic row's — the same row every other merchant is placed from,
 * on the same beat as `readAt`. The card contributes nothing but the polyline, and only when the
 * row's own segment can be FOUND in it; if the card is a beat behind across a segment change (or
 * names another voyage), the row's two points stand and she is drawn exactly where she was served.
 */
function trackedVoyage(
  row: NonNullable<ServedFleet['voyage']>,
  card: Omit<FleetView['voyage'] & object, 'id'> | null,
): NonNullable<ServedFleet['voyage']> {
  const full = card?.course
  if (!full || full.length < 2 || row.course.length < 2 || !row.position) return row
  const seg = segmentIn(full, row.course[0], row.course[1])
  if (seg === null) return row
  return { ...row, course: full, position: { ...row.position, seg_index: seg } }
}

/** Where `[a, b]` sits in `course` as a consecutive pair, or null. Exact equality: both points are
 *  copies of the same served numbers, never re-derived on either side of the wire. */
function segmentIn(course: readonly [number, number][], a: [number, number], b: [number, number]): number | null {
  for (let i = 0; i + 1 < course.length; i++) {
    if (course[i][0] === a[0] && course[i][1] === a[1] && course[i + 1][0] === b[0] && course[i + 1][1] === b[1]) {
      return i
    }
  }
  return null
}

/** How far off her roadstead a berthed merchant lies, in degrees. Small enough that she is plainly
 *  AT that harbour at every zoom the hull is drawn at, large enough that two hulls are two hulls —
 *  and deterministic, so nothing creeps between reads. */
const BERTH_FAN_DEG = 0.045

/** HOW MANY PLACES THERE ARE round a berth: twelve, two rings of six. More places means two
 *  merchants share one less often; they are only ever drawn where the harbour is, so the ring stays
 *  small whatever the count. */
const BERTH_SLOTS = 12

/** HER OWN PLACE AT A BERTH, from her own id and nothing else — so a hull never moves because a
 *  neighbour arrived or sailed. Two merchants can draw the same slot and overlap, which is the
 *  stack this replaced and no worse than it; the harbour is what the picture is telling you. */
function berthSlotOf(fleetId: string): number {
  let h = 2166136261
  for (let i = 0; i < fleetId.length; i++) {
    h ^= fleetId.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  return Math.abs(h) % BERTH_SLOTS
}

/** One of the places on the rings round a berth. 0 IS the roadstead itself — where the server put
 *  her — and 1.. fan clockwise from north, a second ring further out after six. */
function fannedBerth(roadstead: [number, number], n: number): [number, number] {
  if (n <= 0) return roadstead
  const ring = Math.floor((n - 1) / 6) + 1
  const slot = (n - 1) % 6
  const theta = (slot / 6) * 2 * Math.PI
  const r = BERTH_FAN_DEG * ring
  // lon is scaled by the latitude so the ring stays a ring on a Mercator-ish chart near the poles.
  const lat = roadstead[0] + r * Math.cos(theta)
  const lon = roadstead[1] + (r * Math.sin(theta)) / Math.max(0.2, Math.cos((roadstead[0] * Math.PI) / 180))
  return [lat, lon]
}

/** ONE served fleet, in the chart's words — the body both lists above are made of. */
function mapFleetOf(f: ServedFleet): MapFleet | null {
  // A merchant's stores are not served (they are not a player's business); nothing prints them.
  const enduranceDays = f.endurance_days ?? Number.NaN
  const position = f.voyage?.position
  const course = f.voyage?.course
  if (f.voyage && position && course && course.length >= 2) {
    return {
      kind: 'sailing',
      id: f.id,
      name: f.name,
      enduranceDays,
      voyage: {
        course: course.map(([lat, lon]) => ({ lat, lon })),
        segIndex: position.seg_index,
        // 0075 — HOW FAR ALONG THIS LEG SHE IS, and HOW LONG THE LEG IS. Copied like everything
        // else here. Together with `course` they are the whole licence the chart has to draw her
        // between reads: `voyage.position` placed her linearly between `course[segIndex]` and
        // `course[segIndex + 1]`, and these two numbers say where on that line and how much line
        // there is. `segNm` is null on a server older than 0075, and ./drift.ts then leaves her
        // exactly where the server put her.
        legFrac: position.leg_frac,
        segNm: typeof position.seg_nm === 'number' ? position.seg_nm : null,
        at: { lat: position.lat, lon: position.lon },
        sailedNm: position.nm_done,
        totalNm: position.total_nm,
        // domain/fleet owns the parse (`eta` is an ISO string, not ms). A voyage WITH a served
        // position always has an eta, so the null arm is unreachable here — it is spelt rather
        // than asserted because a second Date.parse is how the three copies happened.
        etaMs: voyageEtaMs(f) ?? 0,
        // 0063: parsed HERE and once, beside the eta, for the reason the line above gives.
        // `Date.parse` of an absent field is NaN, not 0 — a fleet whose server predates 0063
        // must draw no elapsed figure rather than one counted from 1970.
        departedMs: f.voyage.departed_at ? Date.parse(f.voyage.departed_at) : null,
        destinationCode: f.voyage.to,
        destPoint: f.voyage.dest_point ? { lat: f.voyage.dest_point[0], lon: f.voyage.dest_point[1] } : null,
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
    }
  }
  if (f.anchor) {
    return { kind: 'anchored', id: f.id, name: f.name, enduranceDays, at: { lat: f.anchor[0], lon: f.anchor[1] } }
  }
  if (f.port) return { kind: 'docked', id: f.id, name: f.name, enduranceDays, portCode: f.port }
  return null
}

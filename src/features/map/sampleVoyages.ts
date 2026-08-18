// ═══════════════════════════════════════════════════════════════════════════════════════════════
// SAMPLE DATA — a stand-in for the server, and labelled as one.
//
// The chart is finished; the RPC that will feed it is not. So the Map tab draws THIS until there
// is a real `voyages` row to draw, and every line of it is here rather than in a fixture the rest
// of the app shares, so that deleting this file is the whole of "switch the map onto live data".
//
// The PORT TABLE is not invented: it is DESIGN §B.2's twelve V0 ports, with §B.2's coordinates,
// verbatim. It is duplicated here only because the shared fixtures are being written by another
// hand at this moment; when they land, `V0_PORTS` becomes an import and nothing else in this
// folder changes (the chart only ever sees `MapPort`).
//
// The LEG DISTANCES are the §B.3 published figures where §B.3 publishes one (Lisboa→Cádiz 188 nm,
// Cádiz→Ceuta 61 nm, Lisboa→Funchal 525 nm) and the haversine of §B.2's own coordinates otherwise.
// The real ones will come from the `legs` table, which may exceed the great circle where the route
// detours (§B.3) — that is exactly why the chart times the authored number and draws the arc.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { MapFleet, MapPort } from './mapTypes'

/** DESIGN §B.2 — the twelve ports of V0 (§K.1). Iberia, the Atlantic islands, the Maghreb, the
 *  western Mediterranean. Decimal degrees, WGS84, to 0.01°. */
export const V0_PORTS: readonly MapPort[] = [
  { code: 'LIS', name: 'Lisboa', country: 'Portugal', lat: 38.71, lon: -9.14 },
  { code: 'OPO', name: 'Porto', country: 'Portugal', lat: 41.15, lon: -8.61 },
  { code: 'SVQ', name: 'Sevilla', country: 'Castile', lat: 37.39, lon: -5.99 },
  { code: 'CAD', name: 'Cádiz', country: 'Castile', lat: 36.53, lon: -6.29 },
  { code: 'CEU', name: 'Ceuta', country: 'Portugal', lat: 35.89, lon: -5.32 },
  { code: 'SAF', name: 'Safi', country: 'Morocco', lat: 32.3, lon: -9.24 },
  { code: 'FNC', name: 'Funchal', country: 'Madeira', lat: 32.65, lon: -16.91 },
  { code: 'LPA', name: 'Las Palmas', country: 'Canarias', lat: 28.13, lon: -15.43 },
  { code: 'MRS', name: 'Marseille', country: 'France', lat: 43.3, lon: 5.37 },
  { code: 'GOA', name: 'Genova', country: 'Genoa', lat: 44.41, lon: 8.93 },
  { code: 'TUN', name: 'Tunis', country: 'Ifriqiya', lat: 36.8, lon: 10.18 },
  { code: 'NAP', name: 'Napoli', country: 'Naples', lat: 40.85, lon: 14.27 },
]

/** Port lookup by code. Built once; the chart resolves a code to a place through this and only this. */
export const V0_PORTS_BY_CODE: ReadonlyMap<string, MapPort> = new Map(
  V0_PORTS.map((p) => [p.code, p]),
)

const MINUTE = 60_000

/**
 * Four fleets in the two states the chart can draw — two at sea, two at anchor.
 *
 * `originMs` is the instant the sample is anchored to (the caller passes its mount time ONCE, in a
 * `useState` initializer, so the fleets do not restart on every render). Departure times are set
 * back from it, which is the point: the two voyages are already part-sailed when the tab opens, and
 * they keep going because their positions are derived, not ticked.
 *
 * At 5 knots and TIME_COMPRESSION 480, Lisboa→Cádiz→Ceuta (249 nm) is a ~6 minute passage and
 * Lisboa→Funchal→Las Palmas (807 nm) is a ~20 minute one — §D.4's "do three while you sit there"
 * and "a commute", side by side, which is the cadence the map exists to make visible.
 */
export function sampleFleets(originMs: number): readonly MapFleet[] {
  return [
    {
      kind: 'sailing',
      id: 'aurora',
      name: 'Aurora',
      voyage: {
        departedAtMs: originMs - 2 * MINUTE,
        legs: [
          { fromPort: 'LIS', toPort: 'CAD', distanceNm: 188, speedKn: 5.0 },
          { fromPort: 'CAD', toPort: 'CEU', distanceNm: 61, speedKn: 5.0 },
        ],
      },
    },
    {
      kind: 'sailing',
      id: 'ponente',
      name: 'Ponente',
      voyage: {
        departedAtMs: originMs - 7 * MINUTE,
        legs: [
          { fromPort: 'LIS', toPort: 'FNC', distanceNm: 525, speedKn: 4.2 },
          { fromPort: 'FNC', toPort: 'LPA', distanceNm: 282, speedKn: 4.2 },
        ],
      },
    },
    { kind: 'docked', id: 'gaivota', name: 'Gaivota', portCode: 'LIS' },
    { kind: 'docked', id: 'levante', name: 'Levante', portCode: 'GOA' },
  ]
}

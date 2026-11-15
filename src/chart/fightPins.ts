// ═══════════════════════════════════════════════════════════════════════════════════════════════
// EVERY SHIP OF A FIGHT STANDS AT THE FIGHT (owner 2026-11-15: "ships inside the circle still move" and "fight was made
// even though there was no pirate"). PURE: no React, no store.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT PROD SERVED (read 2026-11-15, 116 raids in the hour):
//   · THE RAIDER LIES IN HER PORT. A pirate strikes from where she is (`attack_reach_nm`, 240 nm), and every raider read was
//     DOCKED / IN_BATTLE in her own harbour with no voyage: the circle (30 nm round the ship set upon) had no pirate in it.
//   · THE SHIP SET UPON IS HELD BY THE SERVER (her point is the same at the open, the middle and the end), but the map
//     places her from the roster's frozen facts, asked every 30 s: for up to half a minute of a fight that lasts 1 to 73 s
//     she sailed on, and at a wide zoom she was one of the merchants the map thins out, so the circle stood empty.
// SO, WHILE A BATTLE IS BEING FOUGHT, every fleet on its card that is there (`here`) is drawn AT THE BATTLE and stands
// still, from the card alone (`world.fights()`, asked every 5 s while a fight is on):
//   · at her own served place (`sides[].at`) when that lies inside the circle (`reach_nm` round the battle's site): the
//     ship set upon, a ship that joined;
//   · otherwise beside the site: the attackers a third of the circle east of it, the defenders west, one under another.
// A fleet the map has no mark for (another company's) is given one from the card. When the fight ends the pins go with
// the ring and every ship is placed by her own read again. Nothing here stops a ship: the server did.

import { haversineNm, type LatLon } from '../lib/geo'
import type { FightCard, FightSide } from '../lib/rpc'
import { CARGO_HULL, NAVY_HULL, PIRATE_HULL } from './glyphs'
import type { MapFleet, MapTraffic, MerchantInk } from './mapTypes'

/** One fleet of a battle being fought: where the map draws her, and what the card says she is. */
export interface FightPin {
  readonly id: string
  readonly at: LatLon
  readonly battle: string
  readonly side: FightSide
}

/** How far from the site a laid-out fleet stands, as a share of the circle's radius; and the step between two of a side. */
const BESIDE = 0.35
const STEP = 0.3
/** The circle's radius when a card serves none (a battle from before 0435). */
const REACH_NM = 30

function offsetNm(site: LatLon, eastNm: number, northNm: number): LatLon {
  const lat = site.lat + northNm / 60
  const lon = site.lon + eastNm / (60 * Math.max(0.2, Math.cos((site.lat * Math.PI) / 180)))
  return { lat, lon: lon > 180 ? lon - 360 : lon < -180 ? lon + 360 : lon }
}

/** Every fleet that is there on a card being fought, by id, with the place the map draws her at. */
export function fightPinsOf(cards: readonly FightCard[]): ReadonlyMap<string, FightPin> {
  const pins = new Map<string, FightPin>()
  for (const c of cards) {
    if ((c.kind ?? 'BATTLE') !== 'BATTLE' || c.status !== 'FIGHTING') continue
    const site = { lat: c.lat, lon: c.lon }
    const reach = typeof c.reach_nm === 'number' && c.reach_nm > 0 ? c.reach_nm : REACH_NM
    for (const which of ['DEFENDER', 'ATTACKER'] as const) {
      const laid: FightSide[] = []
      for (const s of c.sides) {
        if (s.side !== which || s.here === false) continue
        const own = s.at ? { lat: s.at[0], lon: s.at[1] } : null
        if (own && haversineNm(own, site) <= reach) pins.set(s.fleet, { id: s.fleet, at: own, battle: c.id, side: s })
        else laid.push(s)
      }
      laid.forEach((s, i) => {
        const east = (which === 'ATTACKER' ? 1 : -1) * BESIDE * reach
        const north = ((laid.length - 1) / 2 - i) * STEP * reach
        pins.set(s.fleet, { id: s.fleet, at: offsetNm(site, east, north), battle: c.id, side: s })
      })
    }
  }
  return pins
}

/** A fleet of the player's own, stood at her pin: a ship under sail keeps her course and stops (no drift: `segNm` null). */
export function pinFleets(fleets: readonly MapFleet[], pins: ReadonlyMap<string, FightPin>): readonly MapFleet[] {
  if (pins.size === 0 || !fleets.some((f) => pins.has(f.id))) return fleets
  return fleets.map((f) => {
    const pin = pins.get(f.id)
    if (!pin) return f
    if (f.kind === 'sailing') return { ...f, voyage: { ...f.voyage, at: pin.at, segNm: null } }
    return { kind: 'anchored', id: f.id, name: f.name, enduranceDays: f.enduranceDays, hulls: f.hulls, at: pin.at }
  })
}

const INKS: readonly MerchantInk[] = ['prt', 'esp', 'nld', 'eng', 'han', 'ita', 'ott', 'east', 'pir']

/** A mark for a fleet of the fight that no read of the map carries, from the card's own facts. */
function markOf(pin: FightPin): MapTraffic {
  const s = pin.side
  const nation = (s.nation ?? '').toLowerCase() as MerchantInk
  return {
    kind: 'anchored',
    id: pin.id,
    name: s.name,
    enduranceDays: Number.NaN,
    hulls:
      s.kind === 'CARGO_SHIP' ? [CARGO_HULL] : s.kind === 'NAVY' ? [NAVY_HULL] : s.kind === 'PIRATE' ? [PIRATE_HULL] : Array.from({ length: Math.max(1, Math.trunc(s.ships) || 1) }, () => null),
    at: pin.at,
    company: s.company ?? '',
    ink: s.kind === 'PIRATE' ? 'pir' : INKS.includes(nation) ? nation : 'eng',
    loop: null,
    tracked: false,
    docked: false,
    berthCode: null,
    berthIndex: 0,
    nextLapAtMs: null,
    lane: null,
    ...(s.kind === 'CARGO_SHIP' ? { cargo: true as const } : {}),
    ...(s.kind === 'NAVY' ? { navy: true as const } : {}),
    ...(s.kind === 'PIRATE' ? { pirate: true as const } : {}),
  }
}

/** The ships of the world with every fleet of a fight stood at her pin: one in port leaves her berth for the fight, one
 *  under sail stops; and a fleet of the fight that neither list carries (`mine`: the player's own ids) is given a mark. */
export function pinTraffic(traffic: readonly MapTraffic[], pins: ReadonlyMap<string, FightPin>, mine: ReadonlySet<string>): readonly MapTraffic[] {
  if (pins.size === 0) return traffic
  const seen = new Set<string>()
  const out = traffic.map((t): MapTraffic => {
    const pin = pins.get(t.id)
    if (!pin) return t
    seen.add(t.id)
    if (t.kind === 'sailing') return { ...t, voyage: { ...t.voyage, at: pin.at, segNm: null } }
    const { company, ink, loop, tracked, berthIndex, nextLapAtMs, lane } = t
    return {
      kind: 'anchored',
      id: t.id,
      name: t.name,
      enduranceDays: t.enduranceDays,
      hulls: t.hulls,
      at: pin.at,
      company,
      ink,
      loop,
      tracked,
      docked: false,
      berthCode: null,
      berthIndex,
      nextLapAtMs,
      lane,
      ...(t.cargo ? { cargo: true as const } : {}),
      ...(t.navy ? { navy: true as const } : {}),
      ...(t.pirate ? { pirate: true as const } : {}),
    }
  })
  for (const pin of pins.values()) if (!seen.has(pin.id) && !mine.has(pin.id)) out.push(markOf(pin))
  return out
}

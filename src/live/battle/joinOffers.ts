import { haversineNm, type LatLon } from '../../lib/geo'
import type { FightCard, FleetStatus } from '../../lib/rpc'
import { BATTLE_JOIN_REFUSALS, type BattleSide } from '../../lib/rpc/battleJoin'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHO MAY JOIN, ON WHICH SIDE (docs/design/tick-combat.md section 8). PURE: no React, no store.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The Join bar lists the player's fleets that are
//   · IN REACH: within the card's `reach_nm` of the battle's site (`lat`, `lon`, = battles.site). A card with no
//     `reach_nm` (a battle from before 0435) offers nothing;
//   · FREE: not already in a battle (on a FIGHTING card, or IN_BATTLE), not held (`busy_until` ahead), not at peace
//     (`peace_until` ahead);
// and for each, the sides she may take:
//   · NO PvP: a side whose OTHER side has a player's fleet (kind COMPANY) is never offered;
//   · a RAID (pirates set upon a ship) is joined only on the side set upon, against the pirates.
// The server judges again and refuses with its own code (E_HUMAN_TARGET, E_BAD_SIDE, ...): this only keeps a
// choice that would be refused off the bar. Nothing here ever stops a ship: one that does not join sails on.

/** One of the player's fleets, as the Join bar weighs her. */
export interface JoinFleet {
  readonly id: string
  readonly name: string
  /** Where she is now (the chart's own place for her); null when not known. */
  readonly at: LatLon | null
  readonly status: FleetStatus
  readonly busyUntil: string | null
  readonly peaceUntil: string | null
}

export interface JoinOffer {
  readonly fleet: JoinFleet
  /** How far she lies from the battle's site, nm. */
  readonly nm: number
  /** The sides she may join, DEFENDER first. Never empty. */
  readonly sides: readonly BattleSide[]
}

const SIDES: readonly BattleSide[] = ['DEFENDER', 'ATTACKER']

/** The sides a player may join on this card: never one whose other side has a player's fleet; a raid's set-upon side only. */
export function joinSides(card: FightCard): BattleSide[] {
  const raid = card.sides.some((s) => s.side === 'ATTACKER' && s.kind === 'PIRATE')
  return SIDES.filter((side) => {
    if (raid && side !== 'DEFENDER') return false
    return !card.sides.some((s) => s.side !== side && s.kind === 'COMPANY')
  })
}

/** Every fleet id on a FIGHTING card that is there (`here`): the ships the map draws red. */
export function fleetsInFight(cards: readonly FightCard[]): ReadonlySet<string> {
  const ids = new Set<string>()
  for (const c of cards) {
    if (c.status !== 'FIGHTING') continue
    for (const s of c.sides) if (s.here !== false) ids.add(s.fleet)
  }
  return ids
}

/** Whether her fleet is free to join anything at `nowMs`. `fighting`: every fleet on a FIGHTING card. */
export function fleetFree(f: JoinFleet, nowMs: number, fighting: ReadonlySet<string>): boolean {
  if (f.status === 'IN_BATTLE' || fighting.has(f.id)) return false
  if (f.busyUntil && Date.parse(f.busyUntil) > nowMs) return false
  if (f.peaceUntil && Date.parse(f.peaceUntil) > nowMs) return false
  return true
}

/** The Join bar's rows for one battle: her free fleets within reach, nearest first, each with the sides she may take. */
export function joinOffers(card: FightCard, fleets: readonly JoinFleet[], nowMs: number, allCards: readonly FightCard[] = [card]): JoinOffer[] {
  if ((card.kind ?? 'BATTLE') !== 'BATTLE' || card.status !== 'FIGHTING') return []
  const reach = card.reach_nm
  if (typeof reach !== 'number' || !(reach > 0)) return []
  const sides = joinSides(card)
  if (sides.length === 0) return []
  const fighting = new Set(fleetsInFight(allCards))
  for (const s of card.sides) fighting.add(s.fleet)
  const site = { lat: card.lat, lon: card.lon }
  const out: JoinOffer[] = []
  for (const f of fleets) {
    if (!f.at || !fleetFree(f, nowMs, fighting)) continue
    const nm = haversineNm(f.at, site)
    if (nm <= reach) out.push({ fleet: f, nm, sides })
  }
  return out.sort((a, b) => a.nm - b.nm || a.fleet.name.localeCompare(b.fleet.name))
}

/** The dictionary key of a refusal's short word: its own for every code the contract names, else the one fallback. */
export function joinRefusalKey(code: string): `join.${(typeof BATTLE_JOIN_REFUSALS)[number] | 'E_OTHER'}` {
  return (BATTLE_JOIN_REFUSALS as readonly string[]).includes(code) ? (`join.${code}` as `join.${(typeof BATTLE_JOIN_REFUSALS)[number]}`) : 'join.E_OTHER'
}

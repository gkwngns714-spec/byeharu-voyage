import type { TickAbilityCode, TickEvent, TickShip, TickTimeline } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TIMELINE, READ (0435, docs/design/tick-combat.md 9.3). The ONE reader of `battles.ticks` on the client.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The server sends events, never a state: everything the battle screen draws at tick T (each hull, each side's Fury,
// the cooldowns, who is braced or running, who has come up, who is down, the end) is the fold of the events up to T,
// written here once. Pure: no React, no clock. Side 0 is `a` (the DEFENDER side), side 1 is `b` (the ATTACKER side).

export const SHOT_KINDS = ['A', 'BS', 'CH', 'RK', 'GR'] as const
export type ShotKind = (typeof SHOT_KINDS)[number]
/** The action bar's order (section 4). */
export const BAR_CODES: TickAbilityCode[] = ['BS', 'CH', 'RK', 'GR', 'BR', 'PT', 'RN', 'PY']

/** One event, read into named fields. `id` is its index in `e`: stable across a re-run for the past (section 10). */
export type BattleEvent =
  | { id: number; t: number; s: number; kind: 'shot'; code: ShotKind; i: number; j: number; dmg: number; crit: boolean; left: number }
  | { id: number; t: number; s: number; kind: 'use'; code: TickAbilityCode; fury: number }
  | { id: number; t: number; s: number; kind: 'patch'; i: number; amount: number; hull: number }
  | { id: number; t: number; s: number; kind: 'roll'; chance: number; away: boolean }
  | { id: number; t: number; s: number; kind: 'join'; i: number }
  | { id: number; t: number; s: number; kind: 'struck'; i: number }
  | { id: number; t: number; s: number; kind: 'breakOff' }
  | { id: number; t: number; s: number; kind: 'slipped' }
  | { id: number; t: number; s: number; kind: 'noFight' }
  | { id: number; t: number; s: number; kind: 'boarding'; ratio: number; surrender: boolean }
  | { id: number; t: number; s: number; kind: 'end'; outcome: string }

const num = (v: unknown): number => (typeof v === 'number' && Number.isFinite(v) ? v : Number(v) || 0)
const flag = (v: unknown): boolean => v === true || v === 1 || v === '1'

/** One raw event, read; null for a kind this client does not know (a later version's), which is skipped, never guessed. */
export function readEvent(raw: TickEvent, id: number): BattleEvent | null {
  if (!Array.isArray(raw) || raw.length < 3) return null
  const t = num(raw[0])
  const s = num(raw[1])
  const k = String(raw[2])
  const r = raw as unknown[]
  if ((SHOT_KINDS as readonly string[]).includes(k)) {
    return { id, t, s, kind: 'shot', code: k as ShotKind, i: num(r[3]), j: num(r[4]), dmg: num(r[5]), crit: flag(r[6]), left: num(r[7]) }
  }
  switch (k) {
    case 'U':
      return { id, t, s, kind: 'use', code: String(r[3]) as TickAbilityCode, fury: num(r[4]) }
    case 'P':
      return { id, t, s, kind: 'patch', i: num(r[3]), amount: num(r[4]), hull: num(r[5]) }
    case 'X':
      return { id, t, s, kind: 'roll', chance: num(r[3]), away: flag(r[4]) }
    case 'J':
      return { id, t, s, kind: 'join', i: num(r[3]) }
    case 'S':
      return { id, t, s, kind: 'struck', i: num(r[3]) }
    case 'K':
      return { id, t, s, kind: 'breakOff' }
    case 'L':
      return { id, t, s, kind: 'slipped' }
    case 'O':
      return { id, t, s, kind: 'noFight' }
    case 'B':
      return { id, t, s, kind: 'boarding', ratio: num(r[3]), surrender: flag(r[4]) }
    case 'E':
      return { id, t, s, kind: 'end', outcome: String(r[3] ?? '') }
    default:
      return null
  }
}

/** Every event of a timeline, read, in the server's order. */
export function readEvents(tl: TickTimeline): BattleEvent[] {
  const out: BattleEvent[] = []
  ;(tl.e ?? []).forEach((raw, id) => {
    const ev = readEvent(raw, id)
    if (ev) out.push(ev)
  })
  return out
}

/** A timeline this client can play, or null (a version it does not know, or a shape that is not one). */
export function playableTimeline(v: unknown): TickTimeline | null {
  if (!v || typeof v !== 'object') return null
  const tl = v as TickTimeline
  if (tl.v !== 1 || !Array.isArray(tl.a) || !Array.isArray(tl.b) || !Array.isArray(tl.e)) return null
  if (!(num(tl.ms) > 0) || !Number.isFinite(num(tl.n))) return null
  return tl
}

export interface ShipState {
  ship: TickShip
  hull: number
  /** she has come up (from 0, or her `J`) */
  up: boolean
  /** the tick she came up */
  upAt: number
  struck: boolean
  struckAt: number
}

export interface SideState {
  fury: number
  /** the tick each ability was last used */
  used: Partial<Record<TickAbilityCode, number>>
  bracedUntil: number
  /** the tick her current (or last) run began, and its roll */
  runFrom: number | null
  rollAt: number | null
  away: boolean | null
  escaped: boolean
}

export interface BattleState {
  tick: number
  ships: [ShipState[], ShipState[]]
  sides: [SideState, SideState]
  ended: boolean
  outcome: string | null
  boarded: { ratio: number; surrender: boolean } | null
  brokeOff: boolean
}

function freshSide(): SideState {
  return { fury: 0, used: {}, bracedUntil: -1, runFrom: null, rollAt: null, away: null, escaped: false }
}

/** The fold: the battle as it stands after every event at or before `tick`. */
export function stateAt(tl: TickTimeline, events: BattleEvent[], tick: number): BattleState {
  const ships: [ShipState[], ShipState[]] = [
    tl.a.map((ship) => ({ ship, hull: num(ship.h), up: num(ship.f) <= 0, upAt: num(ship.f), struck: false, struckAt: -1 })),
    tl.b.map((ship) => ({ ship, hull: num(ship.h), up: num(ship.f) <= 0, upAt: num(ship.f), struck: false, struckAt: -1 })),
  ]
  const sides: [SideState, SideState] = [freshSide(), freshSide()]
  const st: BattleState = { tick, ships, sides, ended: false, outcome: null, boarded: null, brokeOff: false }
  const brFor = num(tl.ab?.BR?.for) || 10
  for (const ev of events) {
    if (ev.t > tick) break
    const side = ev.s === 0 || ev.s === 1 ? sides[ev.s] : null
    switch (ev.kind) {
      case 'shot': {
        const target = ships[1 - ev.s]?.[ev.j]
        if (target) target.hull = Math.max(0, ev.left)
        break
      }
      case 'use':
        if (!side) break
        side.fury = ev.fury
        side.used[ev.code] = ev.t
        if (ev.code === 'BR') side.bracedUntil = ev.t + brFor
        if (ev.code === 'RN') {
          side.runFrom = ev.t
          side.rollAt = null
          side.away = null
        }
        break
      case 'patch': {
        const ship = ships[ev.s]?.[ev.i]
        if (ship) ship.hull = ev.hull
        break
      }
      case 'roll':
        if (!side) break
        side.rollAt = ev.t
        side.away = ev.away
        if (ev.away) side.escaped = true
        break
      case 'join': {
        const ship = ships[ev.s]?.[ev.i]
        if (ship) {
          ship.up = true
          ship.upAt = ev.t
        }
        break
      }
      case 'struck': {
        const ship = ships[ev.s]?.[ev.i]
        if (ship) {
          ship.struck = true
          ship.struckAt = ev.t
          ship.hull = 0
        }
        break
      }
      case 'breakOff':
        st.brokeOff = true
        break
      case 'slipped':
        sides[0].escaped = true
        break
      case 'boarding':
        st.boarded = { ratio: ev.ratio, surrender: ev.surrender }
        break
      case 'end':
        st.ended = true
        st.outcome = ev.outcome || tl.out
        break
      default:
        break
    }
  }
  return st
}

/** The last tick anything happens on (the `E`, or `n`). Playback has reached the end once it is past it. */
export function lastTick(tl: TickTimeline, events: BattleEvent[]): number {
  const end = events.find((e) => e.kind === 'end')
  return Math.max(end ? end.t : 0, num(tl.n))
}

/** Ticks left on an ability's cooldown at `tick` (0 = ready), and the share of it still to run (for the sweep). */
export function cooldownAt(tl: TickTimeline, side: SideState, code: TickAbilityCode, tick: number): { left: number; share: number } {
  const used = side.used[code]
  const cd = num(tl.ab?.[code]?.cd)
  if (used === undefined || cd <= 0) return { left: 0, share: 0 }
  const left = Math.max(0, used + cd - tick)
  return { left, share: left / cd }
}

/** Why a button of her action bar cannot be pressed for the next tick (0439), as the timeline tells it; the server judges. */
export type BarLock = 'ready' | 'cooldown' | 'fury' | 'running' | 'role'

/** Her side's lock on one ability for the tick after `tick`. `setUpon`: her fleet is the ship set upon (only she pays);
 *  `opened`: her fleet began the fight (a run is her whole side's, so a ship that joined does not order it). */
export function barLock(tl: TickTimeline, side: SideState, code: TickAbilityCode, tick: number, role: { setUpon: boolean; opened: boolean }): BarLock {
  if ((code === 'PY' && !role.setUpon) || (code === 'RN' && !role.opened)) return 'role'
  const next = tick + 1
  if (cooldownAt(tl, side, code, next).left > 0) return 'cooldown'
  const runFor = num(tl.ab?.RN?.for) || 20
  const running = side.runFrom !== null && side.rollAt === null && side.runFrom + runFor >= next
  if (running && code !== 'BR' && code !== 'PT') return 'running'
  if (side.fury < num(tl.ab?.[code]?.cost)) return 'fury'
  return 'ready'
}

/** The tick the server's clock is at, from a read: floor((now - started_at) / ms), never under 0. */
export function serverTick(startedAt: string, now: string, ms: number): number {
  const d = Date.parse(now) - Date.parse(startedAt)
  return Number.isFinite(d) ? Math.max(0, Math.floor(d / ms)) : 0
}

/** "m:ss" for a tick: the time into the fight. */
export function tickClock(tick: number, ms: number): string {
  const s = Math.floor((tick * ms) / 1000)
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}

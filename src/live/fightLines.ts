import type { FightEnd, FightLog, FightLoss, FightRound, FightVolley } from '../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A RAID'S LOG, READ (0353, owner row 315; docs/COMBAT_LOG.md 1.1, 1.4, 1.5). PURE: no React, no store.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The server keeps a company's raid as one compact `log` (voyage.raid_extras, shape v 1): the engine's own numbers in
// positional arrays. This file is the ONE place that knows those positions. `parseFightLog` is STRICT: version 1,
// every array the right length, every figure a number, or null — and a null draws the report's English sentences as
// before (an old event, an NPC's, a shape this bundle does not know). Nothing here computes an outcome: `fightRows`
// only says which of the server's figures a cell prints, and `barCells` turns a percent into text cells.

const ENDS: readonly FightEnd[] = ['STOOD', 'SLIP', 'BROKE', 'THREW', 'TERMS', 'TAKEN', 'GAVE', 'FLED', 'PAID']
const ROUND_CELLS = 14

const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)
const isRec = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === 'object' && !Array.isArray(v)

function volley(a: unknown[], at: number): FightVolley | null {
  const [can, fired, hits, dealt] = [a[at], a[at + 1], a[at + 2], a[at + 3]]
  return isNum(can) && isNum(fired) && isNum(hits) && isNum(dealt) ? { can, fired, hits, dealt } : null
}

function round(v: unknown): FightRound | null {
  if (!Array.isArray(v) || v.length !== ROUND_CELLS) return null
  const range = v[1]
  const you = volley(v, 2)
  const them = volley(v, 6)
  const struck = v[12]
  const slip = v[13]
  if (!isNum(v[0]) || (range !== 'L' && range !== 'M' && range !== 'C') || !you || !them || !isNum(v[10]) || !isNum(v[11])) return null
  if (!Array.isArray(struck) || !struck.every((s) => Array.isArray(s) && s.length === 2 && isNum(s[0]) && isNum(s[1]))) return null
  if (slip !== null && !isNum(slip)) return null
  return { round: v[0], range, you, them, hull: v[10], foeHull: v[11], struck: struck as [number, number][], slip }
}

/** The log of a fight entry, or null when it is absent or not a shape this bundle knows. */
export function parseFightLog(v: unknown): FightLog | null {
  if (!isRec(v) || v['v'] !== 1) return null
  const order = v['order'] ?? 'FIGHT'
  const noPay = v['no_pay'] ?? null
  const first = v['first']
  const end = v['end']
  const foe = v['foe']
  if (order !== 'FIGHT' && order !== 'FLEE' && order !== 'PAY') return null
  if (noPay !== null && noPay !== 'EMPTY' && noPay !== 'NO_PAYEE') return null
  if (first !== 'YOU' && first !== 'THEY' && first !== 'BOTH') return null
  if (typeof end !== 'string' || !ENDS.includes(end as FightEnd)) return null
  if (!isRec(foe) || typeof foe['n'] !== 'string' || !isNum(foe['k']) || !isNum(foe['crew']) || !isNum(foe['hull'])) return null
  const ship = foe['ship'] ?? null
  if (ship !== null && typeof ship !== 'string') return null

  const youRaw = v['you']
  const afterRaw = v['after']
  const roundsRaw = v['r']
  if (!Array.isArray(youRaw) || !Array.isArray(afterRaw) || !Array.isArray(roundsRaw) || youRaw.length !== afterRaw.length) return null
  const you: FightLog['you'] = []
  for (const s of youRaw) {
    if (!Array.isArray(s) || s.length !== 4 || typeof s[0] !== 'string' || !isNum(s[1]) || !isNum(s[2]) || !isNum(s[3])) return null
    you.push({ name: s[0], hull: s[1], full: s[2], crew: s[3] })
  }
  const after: FightLog['after'] = []
  for (const s of afterRaw) {
    if (!Array.isArray(s) || s.length !== 2 || typeof s[0] !== 'string' || !isNum(s[1])) return null
    after.push({ name: s[0], hull: s[1] })
  }
  const rounds: FightRound[] = []
  for (const r of roundsRaw) {
    const one = round(r)
    if (!one) return null
    rounds.push(one)
  }
  const boardRaw = v['board'] ?? null
  let board: FightLog['board'] = null
  if (boardRaw !== null) {
    if (!Array.isArray(boardRaw) || boardRaw.length !== 3 || !boardRaw.every(isNum)) return null
    board = { crew: boardRaw[0], foeCrew: boardRaw[1], ratio: boardRaw[2] }
  }
  return {
    order,
    noPay,
    first,
    foe: { name: foe['n'], ships: foe['k'], crew: foe['crew'], hull: foe['hull'], ship },
    you,
    rounds,
    end: end as FightEnd,
    board,
    after,
  }
}

/** The day's losses beside a log. Null when absent; a missing figure is null, never a guess. */
export function parseFightLoss(v: unknown): FightLoss | null {
  if (!isRec(v)) return null
  const cargoRaw = v['cargo']
  const cargo: Record<string, number> = {}
  if (isRec(cargoRaw)) for (const [k, n] of Object.entries(cargoRaw)) if (isNum(n)) cargo[k] = n
  const ransom = v['ransom']
  return {
    crewBefore: isNum(v['crew_before']) ? v['crew_before'] : null,
    crew: isNum(v['crew']) ? v['crew'] : null,
    cargo,
    ransom: isNum(ransom) ? ransom : 0,
  }
}

/** What one side's cell of a round says: a reason, or the shots. */
export type FightCell =
  | { kind: 'run' | 'noGuns' | 'outOfRange' | 'unready' }
  | { kind: 'shots'; hits: number; fired: number; dealt: number }

export interface FightRow {
  round: number
  range: FightRound['range']
  you: FightCell
  them: FightCell
  /** Her hull left, as a percent of her fleet's full hull; the raiders' the same of their hull at the start. */
  hullPct: number
  foePct: number
  /** The chance she rolled to slip that round, in percent; null when she did not run. */
  slipPct: number | null
}

const pct = (part: number, whole: number): number => (whole > 0 ? Math.max(0, Math.min(100, Math.round((part / whole) * 100))) : 0)

function cell(v: FightVolley, unready: boolean, ran: boolean): FightCell {
  if (ran) return { kind: 'run' }
  if (unready) return { kind: 'unready' }
  if (v.can === 0) return { kind: 'noGuns' }
  if (v.fired === 0) return { kind: 'outOfRange' }
  return { kind: 'shots', hits: v.hits, fired: v.fired, dealt: v.dealt }
}

/** The log as rows: which figure each cell prints. The side that saw second is caught unready in round 1. */
export function fightRows(log: FightLog): FightRow[] {
  const full = log.you.reduce((n, s) => n + s.full, 0)
  return log.rounds.map((r) => ({
    round: r.round,
    range: r.range,
    you: cell(r.you, r.round === 1 && log.first === 'THEY', r.slip !== null),
    them: cell(r.them, r.round === 1 && log.first === 'YOU', false),
    hullPct: pct(r.hull, full),
    foePct: pct(r.foeHull, log.foe.hull),
    slipPct: r.slip === null ? null : Math.round(r.slip * 100),
  }))
}

/** The whole fight in four figures: hull before and after (summed over her ships), the points lost and their share of her full hull. */
export function fightHull(log: FightLog): { before: number; after: number; lost: number; lostPct: number; full: number } {
  const before = log.you.reduce((n, s) => n + s.hull, 0)
  const after = log.after.reduce((n, s) => n + s.hull, 0)
  const full = log.you.reduce((n, s) => n + s.full, 0)
  const lost = Math.max(0, before - after)
  return { before, after, lost, lostPct: full > 0 ? Math.round((lost / full) * 100) : 0, full }
}

export const BAR_FULL = '▮'
export const BAR_EMPTY = '▯'

/** A percent as `width` text cells. ROUNDED DOWN, so a bar is full only at 100 %; and never empty while anything is
 *  left (1 % of a hull still shows one cell). The percent is always printed beside it: the cells are the glance. */
export function barCells(percent: number, width: number): string {
  const p = Math.max(0, Math.min(100, percent))
  const on = p <= 0 ? 0 : Math.max(1, Math.floor((p / 100) * width + 1e-9))
  return BAR_FULL.repeat(on) + BAR_EMPTY.repeat(width - on)
}

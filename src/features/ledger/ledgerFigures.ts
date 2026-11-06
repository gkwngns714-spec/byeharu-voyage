import type { LedgerEvent } from '../../lib/rpc'
import type { TKey } from '../../lib/i18n'

// THE RECORD'S FIGURES — what the History page's side column prints, derived from the SERVED entries and nothing else
// (2026-11-03, the page slice; owner row 267: *"too packed"* — the side column is the tray's and is used).
//
// WHAT THIS IS. Pure readings of `world.ledger`'s page: which face an entry belongs to, the entries under their day, the money
// of a set of entries (in, out, net, every move as a bar), the record's shape by kind, and the biggest moves. Every figure is a
// sum or a count over `ducats_delta` — the movement the server wrote beside each line — so nothing here is a second authority
// for anything: not the purse (the You screen's, served), not a day's earnings (world.report's). docs/NO_SPAGHETTI.md §2: a
// reading of a served payload with no React, no store and no screen in it, kept beside the one screen that asks for it.
//
// WHERE IT LIVES, AND WHY. It is the History screen's own vocabulary (its faces, its kinds) over its own read; no other screen
// reads the ledger page (Stats' Me face reads world.report; the desk's Report face too). THE SECOND CALLER is implausible
// by construction — a second screen printing the ledger's money would be the duplicate "one fact, one home" refuses
// (tests/consistency.spec.ts) — so it stays in the screen rather than in src/domain; the day it is wanted twice, it moves there
// whole. In its own file rather than LedgerScreen.tsx so the screen file holds one component and the arithmetic can be read
// without a browser.

export type Face = 'all' | 'trade' | 'voyage' | 'crew'

/** The four faces, by id and the dictionary key of their word (the Codex's words: one spelling of Trade / Voyage / Crew). */
export const FACES: readonly { id: Face; label: TKey }[] = [
  { id: 'all', label: 'codex.all' },
  { id: 'trade', label: 'codex.trade' },
  { id: 'voyage', label: 'codex.voyage' },
  { id: 'crew', label: 'codex.crew' },
]

/** Which face a served kind belongs to. A kind not named here (the founding, a gift, a change of flag) is on the All face only. */
export const FACE_OF: Record<string, Exclude<Face, 'all'>> = {
  BOUGHT: 'trade',
  SOLD: 'trade',
  FULFILLED: 'trade',
  DEPARTED: 'voyage',
  VOYAGE_REPORT: 'voyage',
  PROVISIONED: 'voyage',
  PROVISION_REFUSED: 'voyage',
  REPAIRING: 'voyage',
  REPAIRED: 'voyage',
  BATTLE_REPORT: 'voyage',
  TOWED: 'voyage',
  FORCED_HOME: 'voyage',
  ROUTE_LAP: 'voyage',
  ROUTE_PAUSED: 'voyage',
  HIRED: 'crew',
  DISMISSED: 'crew',
  SIGNED_OFFICER: 'crew',
  STUDIED: 'crew',
  ENROLLED: 'crew',
  WAGES: 'crew',
}

/** The entries of a face: every entry on All, else those whose kind the face claims. */
export function onFace(events: readonly LedgerEvent[], face: Face): LedgerEvent[] {
  return face === 'all' ? [...events] : events.filter((e) => FACE_OF[e.kind] === face)
}

/** The served movement of an entry, whole — null for an entry that moved no money. */
export function moveOf(e: LedgerEvent): number | null {
  return e.ducats_delta === null ? null : Math.round(e.ducats_delta)
}

/** The entries under the day each happened on, in the served order (newest first); `dayOf` is the viewer's spelling of a
 *  day (lib/format `formatDate`), so one date stands once per group and never on every row. */
export function byDay(events: readonly LedgerEvent[], dayOf: (atMs: number) => string): { day: string; rows: LedgerEvent[] }[] {
  const out: { day: string; rows: LedgerEvent[] }[] = []
  for (const e of events) {
    const atMs = Date.parse(e.at)
    const day = Number.isFinite(atMs) ? dayOf(atMs) : '—'
    const last = out[out.length - 1]
    if (last && last.day === day) last.rows.push(e)
    else out.push({ day, rows: [e] })
  }
  return out
}

export interface Money {
  /** How many entries moved money. */
  moved: number
  /** The sum of the gains, the sum of the losses (≤ 0), and the two together. */
  inSum: number
  outSum: number
  net: number
  /** The newest `bars` moves as a bar each, OLDEST FIRST (SignedBars reads them left to right). */
  bars: { id: string; value: number }[]
}

/** The money of a set of entries — served movements only, summed; nothing is re-derived from a payload. */
export function moneyOf(events: readonly LedgerEvent[], bars: number): Money {
  const moved = events.map(moveOf).filter((m): m is number => m !== null)
  const inSum = moved.filter((m) => m > 0).reduce((a, b) => a + b, 0)
  const outSum = moved.filter((m) => m < 0).reduce((a, b) => a + b, 0)
  return {
    moved: moved.length,
    inSum,
    outSum,
    net: inSum + outSum,
    bars: moved
      .slice(0, bars)
      .reverse()
      .map((value, i) => ({ id: String(i), value })),
  }
}

export type Kind = Exclude<Face, 'all'> | 'other'

/** The record by kind: how many entries each face holds and their money together, biggest first. `other` is the entries no
 *  face claims; a kind with no entry is absent (a bar of nothing is not a bar). */
export function kindsOf(events: readonly LedgerEvent[]): { kind: Kind; n: number; sum: number }[] {
  const count = new Map<Kind, { n: number; sum: number }>()
  for (const e of events) {
    const k: Kind = FACE_OF[e.kind] ?? 'other'
    const c = count.get(k) ?? { n: 0, sum: 0 }
    c.n += 1
    c.sum += moveOf(e) ?? 0
    count.set(k, c)
  }
  return [...count.entries()].sort((a, b) => b[1].n - a[1].n).map(([kind, c]) => ({ kind, n: c.n, sum: c.sum }))
}

/** The `n` biggest moves either way, largest first — an entry that moved nothing takes no part. */
export function biggestOf(events: readonly LedgerEvent[], n: number): { event: LedgerEvent; move: number }[] {
  return events
    .map((event) => ({ event, move: moveOf(event) }))
    .filter((x): x is { event: LedgerEvent; move: number } => x.move !== null && x.move !== 0)
    .sort((a, b) => Math.abs(b.move) - Math.abs(a.move))
    .slice(0, n)
}

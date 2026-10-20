import { isDockedAt, whereabouts } from '../domain/fleet'
import type { PortMerchant } from '../lib/rpc'
import { restEndsAt } from './merchantWords'
import { t } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A HARBOUR'S MERCHANTS, SPLIT INTO THE TWO LISTS THE OWNER ASKED FOR — in port, and incoming
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-15: *"when i click on a city, i don't want to see stupid useless info …
// by clicking on [port] it should show incomming ships, resting ships."*
//
// HISTORY. Until 2026-10-15 this file cut the harbour's read into FIVE headed groups by the
// server's `doing` word — In port · Leaving · Arriving · Passing · Away (owner rows 121/128 and the
// 2026-10-14 "i see no ship info"). Two of those headings answered the same question as another
// (a `starting` merchant lies here exactly as a `resting` one does; a `passing` one is either
// lying here or bound here), and `Away` — merchants on the far side of their loop — was the list
// the owner now calls useless. So the split is by WHERE SHE IS, not by the word for what she is
// doing, and the word stays on her row (`MerchantRow` prints `DOING_WORD` beside the level).
//
// THE ONE RULE FOR "WHERE". In port is `isDockedAt` and incoming is `whereabouts(…).kind ===
// 'sailing'` bound for this code — src/domain/fleet/where.ts, the same rule every screen and the
// chart ask, for a merchant exactly as for a fleet of yours. Nothing here re-reads `m.port`.
//
// THE ORDER. In port: the merchant whose rest ends soonest first (row 128), the ones with no
// served instant after them in the server's order. Incoming: soonest ETA first. A sort is a VIEW;
// no figure is changed by it. A merchant who is neither (away on her loop) is in neither list.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export interface HarbourSides {
  /** Lying in this harbour — resting, laid up, or about to start her lap. Soonest rest-end first. */
  inPort: PortMerchant[]
  /** At sea and bound for this harbour. Soonest arrival first. */
  incoming: PortMerchant[]
}

/** The harbour's read, split by where each merchant is. Rows that are neither are left out. */
export function harbourSides(rows: readonly PortMerchant[], portCode: string): HarbourSides {
  const inPort: { m: PortMerchant; i: number; ends: number | null }[] = []
  const incoming: { m: PortMerchant; i: number; eta: number | null }[] = []
  rows.forEach((m, i) => {
    if (isDockedAt(m, portCode)) {
      inPort.push({ m, i, ends: restEndsAt(m) })
      return
    }
    const w = whereabouts(m)
    if (w.kind === 'sailing' && w.to === portCode) incoming.push({ m, i, eta: w.etaMs })
  })
  return {
    inPort: inPort.sort((a, b) => byInstant(a.ends, b.ends) || a.i - b.i).map((x) => x.m),
    incoming: incoming.sort((a, b) => byInstant(a.eta, b.eta) || a.i - b.i).map((x) => x.m),
  }
}

/** A served instant before none; two instants by time. */
function byInstant(a: number | null, b: number | null): number {
  if (a !== null && b !== null) return a - b
  if (a !== null) return -1
  if (b !== null) return 1
  return 0
}

/**
 * THE CITY'S ONE LINE under its name: `27 merchants · 2 in port`, `1 merchant`, or '' when the
 * harbour concerns nobody. "In port" is `harbourSides`' — the same count the Port tab lists, so
 * the line and the list cannot disagree.
 */
export function merchantsSummary(rows: readonly PortMerchant[], portCode: string): string {
  if (rows.length === 0) return ''
  const inPort = harbourSides(rows, portCode).inPort.length
  const all = t('town.merchants', { n: rows.length })
  return inPort > 0 ? t('town.inPort', { all, n: inPort }) : all
}

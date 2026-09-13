// THE BASKET BEING STAGED — the lines a player has put on the market's basket, and the receipt of
// the last basket that landed. docs/QUAY_LEDGER.md §3 C/E (owner row 76, slice 2).
//
// ── THE CONCEPT, IN ONE NOUN PHRASE (docs/NO_SPAGHETTI.md §7B) ─────────────────────────────────
// "What the player has staged, and not yet traded." It is a CHOICE, like the harbour beside it
// (harbour.ts) — not a fact the server holds (`src/live` keeps only what the server last said, and
// no payload carries a half-written basket), and not a rule of the game (`src/domain` decides
// nothing, and this decides nothing either: legality is `cmd.preview_basket`'s, one line per good
// is `E_MANIFEST_DUPLICATE`'s, and `stageLine` below merely keeps the list tidy for the eye).
//
// ── NOT PERSISTED, ON PURPOSE ───────────────────────────────────────────────────────────────────
// harbourStore survives a reload because a harbour you are reading is still the same harbour
// tomorrow. A basket is priced against a market that STEPS every fifteen minutes and against a
// ship that may have sailed; a line remembered across a reload is a stale byte dressed as a
// choice. So this lives in memory and dies with the tab.
//
// ── ONE KEY: (fleet, port) — FOR THE LINES AND FOR THE RECEIPT ──────────────────────────────────
// A basket is one fleet's, at one market — exactly the two arguments `cmd.trade_basket` takes.
// Staging a line for a different key DROPS the old lines rather than mixing them: a basket that
// straddled two ports could never land as one order, so it must never exist here either.
//
// The RECEIPT carries the same key, and this is the adversarial review of PR #59 (MUST-FIX 2):
// there the receipt was a global with no key, cleared only by its own ✕, so a player who traded,
// saw the chit, then pressed a price and `Add to basket` was shown "Settled · 14:32" instead of
// their basket — and the chit came back on another tab and at another port. Now `stage()` drops
// the receipt (a new basket is a new story), `receiptFor` answers only for the (fleet, port) it
// was settled at, and a basket with lines is always the face shown (ManifestPanel.tsx).

import { create } from 'zustand'
import type { ManifestLine, ManifestReceipt } from '../lib/rpc'

export interface ManifestKey {
  fleet: string
  port: string
}

export interface ManifestState {
  /** Whose basket this is, or null while nothing is staged. */
  key: ManifestKey | null
  /** In INPUT order — the order `cmd.preview_basket` reports a refusing `line` against. */
  lines: ManifestLine[]
  /** The last committed basket's receipt, keyed to where it was settled, until dismissed or the
   *  next line is staged. */
  receipt: { key: ManifestKey; receipt: ManifestReceipt } | null
  /** Put a line on the basket. Replaces the line for the same good; a new key drops old lines;
   *  any standing receipt is dismissed. */
  stage: (fleet: string, port: string, line: ManifestLine) => void
  remove: (good: string) => void
  clear: () => void
  /** The basket landed: the lines are spent and the receipt stands in their place. */
  settle: (fleet: string, port: string, receipt: ManifestReceipt) => void
  dismissReceipt: () => void
}

/** The ONE empty list, so a selector that finds nothing returns the same reference every time
 *  (zustand compares by identity; a fresh `[]` per read is a render loop). */
const NONE: ManifestLine[] = []

const sameKey = (key: ManifestKey | null, fleet: string, port: string): boolean =>
  key !== null && key.fleet === fleet && key.port === port

/**
 * ONE LINE PER GOOD, replaced in place. A second line for a good already staged — on either side —
 * takes that line's position rather than appending, so re-choosing a quantity does not shuffle
 * the list under the finger. Pure and exported so a Node spec pins it.
 */
export function stageLine(lines: readonly ManifestLine[], line: ManifestLine): ManifestLine[] {
  const at = lines.findIndex((l) => l.good === line.good)
  if (at < 0) return [...lines, line]
  return lines.map((l, i) => (i === at ? line : l))
}

/** The staged lines, but ONLY for this fleet at this port — any other board reads an empty basket. */
export function linesFor(s: Pick<ManifestState, 'key' | 'lines'>, fleet: string, port: string): ManifestLine[] {
  return sameKey(s.key, fleet, port) ? s.lines : NONE
}

/** The standing receipt, but ONLY where it was settled — another board reads none. */
export function receiptFor(s: Pick<ManifestState, 'receipt'>, fleet: string, port: string): ManifestReceipt | null {
  return s.receipt !== null && sameKey(s.receipt.key, fleet, port) ? s.receipt.receipt : null
}

export const useManifest = create<ManifestState>()((set) => ({
  key: null,
  lines: NONE,
  receipt: null,
  stage: (fleet, port, line) =>
    set((s) => ({
      key: { fleet, port },
      lines: stageLine(sameKey(s.key, fleet, port) ? s.lines : NONE, line),
      receipt: null,
    })),
  remove: (good) =>
    set((s) => {
      const lines = s.lines.filter((l) => l.good !== good)
      return lines.length === 0 ? { key: null, lines: NONE } : { lines }
    }),
  clear: () => set({ key: null, lines: NONE }),
  settle: (fleet, port, receipt) => set({ key: null, lines: NONE, receipt: { key: { fleet, port }, receipt } }),
  dismissReceipt: () => set({ receipt: null }),
}))

// THE MANIFEST BEING STAGED — the lines a player has put on the quay's basket, and the receipt of
// the last one that landed. docs/QUAY_LEDGER.md §3 C/E (owner row 76, slice 2).
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
// tomorrow. A manifest is priced against a market that STEPS every fifteen minutes and against a
// hold that may have sailed; a line remembered across a reload is a stale byte dressed as a
// choice. So this lives in memory and dies with the tab.
//
// ── ONE KEY: (fleet, port) ──────────────────────────────────────────────────────────────────────
// A manifest is one fleet's, at one quay — exactly the two arguments `cmd.trade_basket` takes.
// Staging a line for a different key DROPS the old lines rather than mixing them: a basket that
// straddled two quays could never land as one order, so it must never exist here either.

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
  /** The last committed manifest's receipt, until the player dismisses it. */
  receipt: ManifestReceipt | null
  /** Put a line on the manifest. Replaces the line for the same good; a new key drops old lines. */
  stage: (fleet: string, port: string, line: ManifestLine) => void
  remove: (good: string) => void
  clear: () => void
  /** The manifest landed: the lines are spent and the receipt stands in their place. */
  settle: (receipt: ManifestReceipt) => void
  dismissReceipt: () => void
}

/** The ONE empty list, so a selector that finds nothing returns the same reference every time
 *  (zustand compares by identity; a fresh `[]` per read is a render loop). */
const NONE: ManifestLine[] = []

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

/** The staged lines, but ONLY for this fleet at this quay — any other board reads an empty manifest. */
export function linesFor(s: Pick<ManifestState, 'key' | 'lines'>, fleet: string, port: string): ManifestLine[] {
  return s.key !== null && s.key.fleet === fleet && s.key.port === port ? s.lines : NONE
}

export const useManifest = create<ManifestState>()((set) => ({
  key: null,
  lines: NONE,
  receipt: null,
  stage: (fleet, port, line) =>
    set((s) => {
      const same = s.key !== null && s.key.fleet === fleet && s.key.port === port
      return { key: { fleet, port }, lines: stageLine(same ? s.lines : NONE, line) }
    }),
  remove: (good) =>
    set((s) => {
      const lines = s.lines.filter((l) => l.good !== good)
      return lines.length === 0 ? { key: null, lines: NONE } : { lines }
    }),
  clear: () => set({ key: null, lines: NONE }),
  settle: (receipt) => set({ key: null, lines: NONE, receipt }),
  dismissReceipt: () => set({ receipt: null }),
}))

import { formatNm } from '../../lib/format'
import type { MapWater } from '../../chart'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WATERS-AHEAD ROW MODEL — every decision the panel makes, as data, with no React in it.
//
// The same split `rarityTiers.ts` / `Rarity.tsx` and `goodTileLayout.ts` / `GoodTile.tsx` already
// use in this repo, and it exists for the same two reasons: the contract becomes something a test
// can READ rather than something a screenshot must be squinted at, and the component is left with
// nothing in it but markup — so a change to WHAT a row says cannot hide inside a change to how it
// looks. `WatersAhead.tsx` is the one renderer; this is the one decider.
//
// WHAT IT DECIDES, and it is a short list on purpose:
//   · how many rows fit the glass, and how many did not,
//   · what the hero figure on a row SAYS,
//   · which row carries the sea's character.
//
// WHAT IT MAY NEVER DECIDE: the tier, the note, or either distance. Those are the server's
// (`voyage.waters_ahead`, migration 0055) and they are copied. In particular the tier is the same
// `seas.danger_level` the per-sea encounter mix is keyed on, so a tier derived here would make the
// picture and the rules two authorities for one number.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/**
 * How many waters fit a corner panel on a 390 px phone before it stops being a corner panel. A LAW
 * OF THE INTERFACE, not a fact about content (docs/NO_SPAGHETTI.md §6, case 3): four rows plus the
 * character line is the tallest this can be and leave the chart visible underneath it.
 */
export const WATERS_SHOWN = 4

/** THE NAME for the water she is in. A distance of zero printed as a figure ("0 nm") reads as a
 *  broken number, so the one row whose distance is nothing says where she is instead. One word. */
export const HERE = 'here'

export interface WaterRow {
  readonly code: string
  readonly name: string
  /** 1–5, the server's `seas.danger_level`, copied. `DangerMark` draws it. */
  readonly danger: number
  /** What the row's hero figure says — `here`, or `2,170 nm` with its unit attached. */
  readonly figure: string
  /** The sea's character in the world's own words — only for the water she is in; null elsewhere.
   *  Where she IS earns four facts; where she is going earns three. */
  readonly note: string | null
}

export interface WatersView {
  readonly rows: readonly WaterRow[]
  /** Every water still ahead of her, including the ones that did not fit. */
  readonly total: number
  /** How many did not fit. Printed, never swallowed: a truncated list that does not admit it is
   *  a lie about the sea. */
  readonly hidden: number
}

export function watersView(waters: readonly MapWater[]): WatersView {
  const rows = waters.slice(0, WATERS_SHOWN).map((w) => ({
    code: w.code,
    name: w.name,
    danger: w.danger,
    figure: w.now ? HERE : formatNm(w.nmTo),
    note: w.now ? w.note : null,
  }))
  return { rows, total: waters.length, hidden: Math.max(0, waters.length - rows.length) }
}

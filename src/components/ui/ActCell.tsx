import type { ReactNode } from 'react'

// THE ACT CELL — one act on a row, with the figure it is about, and why it is dead when it is.
//
// ── ONE RECIPE, TWO CALLERS (docs/NO_SPAGHETTI.md §1) ──────────────────────────────────────────
// It was `PriceCell`, private to TradeRow.tsx: the buy and sell cells of the ledger, a fixed box
// so a column of them reads straight (7rem holds "not traded here" on one line at t-caption;
// 3.5rem is label + figure + reason, so a live cell stands as tall as a dead one). The Storage
// face (owner row 88, 2026-09-13: *"make it like trading graphic, where i can put, or pull"*)
// wanted the same cell for `Put in storage` / `Take on board` with a count where the price was.
// Written a second time → it becomes a function: this is that function, and TradeRow composes it.
//
// ── WHAT IT DOES NOT KNOW ──────────────────────────────────────────────────────────────────────
// What the figure is (a price, a count), what a press opens, or why a cell is dead — all three
// arrive as props. A dead cell ALWAYS says why on its own face: a cell that goes grey with no
// reason is the defect tests/layout.spec.ts was written to stop.

export function ActCell({
  label,
  figure,
  onPress,
  dead,
  selected = false,
  ...rest
}: {
  /** The act, in the caption voice: `buy`, `sell`, `Put in storage`, `Take on board`. */
  label: string
  /** The figure the act is about — normally a `<Figure>`. */
  figure: ReactNode
  onPress: () => void
  /** Why this cell cannot be pressed, or null when it can. */
  dead: string | null
  /** Accent wash while what this cell opens is open. */
  selected?: boolean
} & { 'data-testid'?: string }) {
  return (
    <button
      type="button"
      onClick={onPress}
      disabled={dead !== null}
      aria-pressed={selected}
      className={`w-28 min-h-14 rounded-control px-2 py-1 text-left disabled:opacity-45 ${selected ? 'bg-accent-soft' : 'bg-surface-2'}`}
      {...rest}
    >
      <span className="block text-t-caption text-ink-faint">{label}</span>
      {figure}
      {dead !== null && <span className="block text-t-caption text-ink-faint">{dead}</span>}
    </button>
  )
}

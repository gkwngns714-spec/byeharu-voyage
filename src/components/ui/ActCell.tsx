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
  // TOP-ALIGNED, not centred (2026-10-25, owner row 198): a button centres its content, so a cell
  // with a reason line under its figure stood 12px higher than its neighbour without one, and the
  // two prices of one row did not share a line. A column, from the top.
  // A CELL NEVER RUNS PAST ITS ROW (2026-11-02, the desk's Requests: a dead `deliver` cell read "0 / 20 units on board" on
  // ONE line, 15 px past its 112-px box and past the row's edge, and the pane scrolled sideways). The cell sits in a
  // `Row` value, which is `whitespace-nowrap`, and the reason inherited it; the reason is a SENTENCE and wraps inside the
  // cell (`whitespace-normal`, `break-words` — the cell grows by a line, the row with it), and the cell itself yields to
  // the room it stands in (`max-w-full`, `min-w-0`) — the HQ's narrow panel gives a pair 67 px each.
  return (
    <button
      type="button"
      onClick={onPress}
      disabled={dead !== null}
      aria-pressed={selected}
      data-act-cell=""
      className={`flex w-28 min-h-14 min-w-0 max-w-full flex-col items-start justify-start whitespace-normal rounded-control px-2 py-1 text-left disabled:opacity-45 narrow:px-1.5 tight:min-h-11 tight:flex-row tight:flex-wrap tight:content-center tight:items-baseline tight:gap-x-2 ${selected ? 'bg-accent-soft' : 'bg-surface-2'}`}
      {...rest}
    >
      <span className="block text-t-caption text-ink-faint">{label}</span>
      {figure}
      {dead !== null && <span className="block break-words text-t-caption text-ink-faint tight:basis-full">{dead}</span>}
    </button>
  )
}

/** THE PAIR OF ACT CELLS — a good's BUY and SELL, a stored good's PUT and TAKE — as a row's value (two callers, so one
 *  function: the Market's `TradeRow` and the Storage's row each spelt `grid grid-cols-2 gap-1`).
 *
 *  ITS WIDTH IS KNOWN, AND SAID: two 7-rem cells and the 0.25 rem between them, 14.25 rem — what the grid's own `max-content`
 *  came to, so a wide row is exactly what it was. It yields to the room (`max-w-full`): where a query container is
 *  narrower than 15 rem (`narrow:`, index.css — the HQ's panel on a phone) the two cells share what there is (67 px each at
 *  390), and below 8.25 rem (`tight:` — 320, where each would be 50 px, under what a four-digit price needs) they stand one
 *  over the other, each the width of the panel. Nothing is cut and nothing overlaps at either. */
export function ActPair({ children }: { children: ReactNode }) {
  return <span className="grid w-[14.25rem] max-w-full grid-cols-2 gap-1 tight:grid-cols-1">{children}</span>
}

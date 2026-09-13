import { Bar } from './Bar'
import { Figure } from './Figure'
import { RarityMark } from './Rarity'
import { Row } from './Row'
import { formatInt, formatUnits } from '../../lib/format'
import type { MarketGood } from '../../lib/rpc'

// THE LEDGER ROW — one good, its two prices as its two acts, and the tide. docs/QUAY_LEDGER.md §3
// screen A (owner row 76, 2026-09-11).
//
// A COMPOSITION, NOT A THIRTEENTH PRIMITIVE. `Row` + `Figure` + `Bar` + `RarityMark`, exactly as
// the `TradeTile` it replaces was `Tile` + `Figure` + `Bar`. It stands in the design system for the
// reason that one did: PORT's Trade face draws it for the quay she lies at and PORT's read-only
// ledger draws it for a quay she is not on, and a good may not look different on the two.
//
// ── WHAT CHANGED FROM THE TILE, AND WHY ────────────────────────────────────────────────────────
// The owner's 2026-08-26 grid rule ("organized not in lines") is REVERSED by row 76: the approved
// board is ONE ROW PER GOOD, the reference game's own card list re-read as a ledger. A tile spent
// its height on a stock meter and a range with two figures under it; the row keeps the two things
// a glance needs — the two prices, and WHERE TODAY'S MID SITS inside the served range, as a 4px
// tide (QUAY_LEDGER §2 move 2: "price + tide, not `96% · 1,124 (1,110)`"). Stock moves into the
// tray ("On the quay"), where the quantity it bounds is chosen.
//
// The owner's row 6 is kept literally: *"i want to be able to click on buy and sell itself and do
// trades."* Both prices are real 44px buttons, and a dead one says WHY on its own face — a cell
// that goes grey with no reason is the defect tests/layout.spec.ts was written to stop. What a
// press OPENS is the caller's affair; this row inserts nothing into the list it stands in, which
// is what lets the ledger hold still under the finger.
//
// `native` IS A CAPTION WORD, NOT A TAG (0084, slice 2). The served flag — "this is grown here",
// 0062's own word — is appended to the caption the row already carries (`· 40 units on board ·
// native`), in the caption voice. Not a coloured tag: docs/UI_DIRECTION.md §4.4 gives rarity its
// hues as a 10-px MARK only and never as text colour, and a second badge vocabulary beside it
// would be a second one. A server predating 0084 sends no flag and the row draws nothing — never
// a guess from origin_regions on this side of the wire. The rarity mark IS drawn, mark only, when
// the tier is served — never as a text tag.

export function TradeRow({
  good,
  aboard,
  canBuy,
  selected = null,
  onBuy,
  onSell,
}: {
  good: MarketGood
  /** Tuns of THIS good aboard — the reader's own manifest, folded ONCE by the caller. */
  aboard: number
  /** 0061's one answer to "can this be bought at this quay" — `buyableHere`, folded by the caller. */
  canBuy: boolean
  /** Which of the two cells is open in a tray, if either. */
  selected?: 'buy' | 'sell' | null
  onBuy: () => void
  onSell: () => void
}) {
  return (
    <Row
      label={
        // THE CAPTION WRAPS UNDER THE NAME WHEN IT DOES NOT FIT, and never squeezes it: at 390px a
        // row with cargo on board once read `◇ · 10 units on board` with the name truncated to
        // nothing (seen in the basket proof's end frame, 2026-09-13). `flex-wrap` keeps a short
        // caption on the name's line (`· native` fits), so no other row's height moves.
        <span className="flex flex-wrap items-center gap-x-1.5 text-t-body">
          <span className="max-w-full truncate">{good.name}</span>
          <RarityMark rarity={good.rarity} />
          {(aboard > 0 || good.native === true) && (
            <span className="text-t-caption text-ink-faint">
              {[aboard > 0 ? `${formatUnits(aboard)} on board` : null, good.native === true ? 'native' : null]
                .filter(Boolean)
                .map((w) => `· ${w}`)
                .join(' ')}
            </span>
          )}
        </span>
      }
      value={
        <span className="grid grid-cols-2 gap-1">
          <PriceCell
            label="buy"
            price={good.buy}
            onPress={onBuy}
            dead={canBuy ? null : 'not traded here'}
            selected={selected === 'buy'}
          />
          <PriceCell
            label="sell"
            price={good.sell}
            onPress={onSell}
            dead={aboard > 0 ? null : 'none on board'}
            selected={selected === 'sell'}
          />
        </span>
      }
      data-testid="trade-row"
    >
      <Bar pct={tidePct(good)} tone="neutral" label={`${good.name} price range`} className="mt-1 max-w-40" />
    </Row>
  )
}

/** WHERE TODAY'S MID STANDS INSIDE THE SERVED RANGE, 0–100 — pure formatting of three served
 *  figures, spelt in this ONE place. A band of zero width reads as full. */
function tidePct(g: MarketGood): number {
  const width = g.range_hi - g.range_lo
  if (!(width > 0)) return 100
  return ((g.mid - g.range_lo) / width) * 100
}

/** One price, and the tap that makes it a trade. The label and the figure are what layout.spec
 *  counts; the reason line is what keeps a dead cell honest. Moved unchanged from TradeTile, plus
 *  the accent wash while its tray is open.
 *
 *  The cell is a fixed box — `w-28 min-h-14` — and not sized by its text, because a ledger is read
 *  down a column. The first canary drive (2026-09-11) showed why: a good with 10 t aboard lost its
 *  "none aboard" line and its whole row shrank narrower and shorter than its neighbours, so the
 *  price column zig-zagged. 7rem holds "not traded here" on ONE line at t-caption (5.5rem wrapped it and every cell grew to 78px); 3.5rem is label + figure
 *  + reason, so a live cell stands as tall as a dead one. */
function PriceCell({
  label,
  price,
  onPress,
  dead,
  selected,
}: {
  label: 'buy' | 'sell'
  price: number
  onPress: () => void
  /** Why this cell cannot be pressed, or null when it can. */
  dead: string | null
  selected: boolean
}) {
  return (
    <button
      type="button"
      onClick={onPress}
      disabled={dead !== null}
      aria-pressed={selected}
      className={`w-28 min-h-14 rounded-control px-2 py-1 text-left disabled:opacity-45 ${selected ? 'bg-accent-soft' : 'bg-surface-2'}`}
    >
      <span className="block text-t-caption text-ink-faint">{label}</span>
      <Figure value={formatInt(price)} />
      {dead !== null && <span className="block text-t-caption text-ink-faint">{dead}</span>}
    </button>
  )
}

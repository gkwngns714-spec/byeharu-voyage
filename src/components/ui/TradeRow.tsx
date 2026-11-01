import { ActCell } from './ActCell'
import { Figure } from './Figure'
import { Icon } from './Icon'
import { goodIcon } from './goodIcons'
import { goodClassRow } from './goodClassTiers'
import { GoodKind } from './GoodKind'
import { Row } from './Row'
import { StockGauge } from './StockGauge'
import { formatPriceFigure, formatUnits } from '../../lib/format'
import type { MarketGood } from '../../lib/rpc'
import { useT } from '../../lib/i18n'

// THE LEDGER ROW — one good, its two prices as its two acts, and the tide. docs/QUAY_LEDGER.md §3
// screen A (owner row 76, 2026-09-11).
//
// A COMPOSITION, NOT A THIRTEENTH PRIMITIVE. `Row` + `Figure` + `Bar` + `GoodKind`, exactly as
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
// NO `native` WORD (owner, 2026-10-17: "remove native"; 0141 took the key off world.market). The
// caption carries one fact — `· 40 units on board` — and docs/UI_DIRECTION.md §4.4 gives rarity
// its hues as a 10-px MARK only: the rarity mark IS drawn, mark only, when the tier is served —
// never as a text tag. THE PREMIUM CLASS (0294) IS DRAWN THE SAME WAY, beside it: `GoodKind compact`
// is the two marks STACKED in one unbreakable cluster inside the name's own line (so it adds no track
// and no gap to the Row — docs/dev-log/2026-11-01-main-red-row-tracks.md — and no line to the label),
// and from class 4 the row wears a soft wash of the class's tone from its start edge (`goodClassRow`),
// a background, which costs no pixel.
//
// AND THE GOOD'S KIND IS NOT HERE, THOUGH THE OWNER ASKED FOR IT (row 177, 2026-10-20: "what class?
// What sort it is classified, such as food, weapon, spice etc."). It was added as one caption word
// on 2026-10-20 and taken straight back out: this row's HEIGHT is a measured contract —
// tests/layout.spec.ts requires three complete rows above the fold on City › Trade and five on
// Markets, measured at 390×844 — and at that width the label column is ~130px, so one more word
// wraps the name to a second line on most goods and spends that budget. The kind is said where
// there is room for it: the tray a press opens (`PriceRows`' Kind row, both words) and the desk's
// markets list, whose caption line truncates instead of wrapping. Put it back here only with a
// re-measured fold.

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
  const t = useT()
  return (
    <Row
      {...goodClassRow(good.class)}
      label={
        // THE CAPTION WRAPS UNDER THE NAME WHEN IT DOES NOT FIT, and never squeezes it: at 390px a
        // row with cargo on board once read `◇ · 10 units on board` with the name truncated to
        // nothing (seen in the basket proof's end frame, 2026-09-13). `flex-wrap` keeps a short
        // caption on the name's line (`· 4 units on board` often fits), so no other row's height moves.
        // THE GOOD'S OWN MARK LEADS THE NAME (2026-10-01, owner: "it is like a text game"). The 96
        // hand-drawn goods marks were already drawn on the Codex and the cargo rows, and missing
        // from the one list a player reads most — so the ledger was a column of words. It rides
        // INSIDE the name's line rather than in Row's `mark` slot: that slot's 12px gap would take
        // 32px from a name that has ~118px at 390, and `Black Pepper` would truncate. The icon
        // holds the first line; the name, its mark and its caption flow as TEXT beside it, so a
        // long name wraps under itself (never under the icon, never truncated) — two lines still
        // stand inside the height the price cells already give the row.
        <span className="flex items-start gap-1.5 text-t-body">
          <Icon name={goodIcon(good.code, good.category)} size={18} className="mt-0.5 shrink-0 text-ink-muted" />
          <span className="min-w-0 break-words">
            {good.name} <GoodKind compact rarity={good.rarity} goodClass={good.class} />
            {/* 0255 (E6b): the city wants this good and pays a multiple for it this period */}
            {good.wanted != null && (
              <span className="text-t-caption text-accent" data-testid="trade-row-wanted">
                {' '}
                {t('ui.wanted', { mult: String(Number(good.wanted)) })}
              </span>
            )}
            {/* The caption keeps its dot — a no-break space, so `·` never ends a line alone. */}
            {aboard > 0 && (
              <span className="text-t-caption text-ink-faint">
                {' '}
                {t('ui.onBoard', { nbsp: NBSP, units: formatUnits(aboard) })}
              </span>
            )}
          </span>
        </span>
      }
      value={
        <span className="grid grid-cols-2 gap-1">
          <PriceCell
            label="buy"
            price={good.buy}
            onPress={onBuy}
            dead={canBuy ? null : t('ui.notTraded')}
            selected={selected === 'buy'}
          />
          <PriceCell
            label="sell"
            price={good.sell}
            onPress={onSell}
            dead={aboard > 0 ? null : t('ui.noneOnBoard')}
            selected={selected === 'sell'}
          />
        </span>
      }
      under="label"
      data-testid="trade-row"
    >
      {/* THE CITY'S STOCK AGAINST ITS NORMAL LEVEL (owner, 2026-10-18: "i don't see stock of the trade
          goods"). It replaces the tide-in-range bar: the stock IS why the price stands where it does. */}
      <StockGauge stock={good.stock} target={good.stock_target} label={good.name} className="mt-1" />
    </Row>
  )
}

/** A no-break space, spelled as an escape so the source carries no invisible character. */
const NBSP = String.fromCharCode(0xa0)

/** One price, and the tap that makes it a trade. The label and the figure are what layout.spec
 *  counts; the reason line is what keeps a dead cell honest. Moved unchanged from TradeTile, plus
 *  the accent wash while its tray is open.
 *
 *  THE BOX IS `ActCell` (2026-09-13): the fixed `w-28 min-h-14` cell — 7rem holds "not traded
 *  here" on one line at t-caption, 3.5rem is label + figure + reason so a live cell stands as
 *  tall as a dead one and the column never zig-zags (the first canary drive, 2026-09-11) — was
 *  written here and wanted a second time by the Storage face (owner row 88), so it moved down to
 *  its own file and this is one of its two callers. What stays here is what a PRICE cell is: the
 *  figure is a price. */
export function PriceCell({
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
  const t = useT()
  return <ActCell label={t(label === 'buy' ? 'ui.buy' : 'ui.sell')} figure={<Figure value={formatPriceFigure(price)} />} onPress={onPress} dead={dead} selected={selected} />
}

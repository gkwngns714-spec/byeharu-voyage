import { formatOfTotal } from '../../lib/format'
import { stockLevel, stockFillPct, type StockLevel } from './stockLevel'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A CITY'S STOCK AGAINST ITS NORMAL LEVEL — the one gauge every market row draws
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE OWNER, 2026-10-18: *"i don't see stock of the trade goods so there needs fixing"*. A price in
// this game is centred on a city's NORMAL stock (`port_goods.stock_target`). Below it the price
// stands high, and above it the price stands low. So a stock figure means nothing without its
// normal level beside it, and this gauge always draws the two together: `240 / 300` and a thin bar
// whose tick is the normal level.
//
// ONE COMPONENT, EVERY CALLER: the desk's watchlist, its Buy at / Sell at ladders, the City face's
// trade board and the map city panel's Market tab (both draw `TradeRow`), and the trade tray's "In
// stock" row (`PriceRows`). Never a copy.
//
// BOTH FIGURES ARE SERVED (world.market, world.good_board, world.watchlist, 0183). The bar's fill and
// the tone are formatting of those two numbers, spelt once in `stockLevel.ts`:
//   · the track is 0 … 2 × normal, so the tick (normal) stands in the middle;
//   · LOW (scarce, so the price is high) is `danger`, HIGH (plenty, so the price is low) is
//     `success`, near normal is `ink-faint`. This is the desk's own reading of the two tones
//     (COMMAND_DESK §5.3: danger = dearer, success = cheaper).
// The word ("low" / "high") is in the accessible name, so the colour is never the only signal.

const FILL: Record<StockLevel, string> = {
  low: 'bg-danger',
  normal: 'bg-ink-faint',
  high: 'bg-success',
}
const TEXT: Record<StockLevel, string> = {
  low: 'text-danger',
  normal: 'text-ink-muted',
  high: 'text-success',
}
const WORD: Record<StockLevel, string> = {
  low: 'low, so the price is high',
  normal: 'about normal',
  high: 'high, so the price is low',
}

export function StockGauge({
  stock,
  target,
  label,
  showFigure = true,
  className = '',
}: {
  /** The city's stock, served. */
  stock: number
  /** Its normal level (`stock_target`), served. */
  target: number
  /** Whose stock, for assistive tech: "Coffee at Mocha". */
  label: string
  /** The `240 / 300` figure beside the bar. Off only where a column already prints it. */
  showFigure?: boolean
  className?: string
}) {
  const level = stockLevel(stock, target)
  const fill = stockFillPct(stock, target)
  return (
    <span
      role="meter"
      aria-valuemin={0}
      aria-valuemax={Math.round(target * 2)}
      aria-valuenow={Math.round(stock)}
      aria-label={`${label} stock ${formatOfTotal(stock, target)} of normal, ${WORD[level]}`}
      data-testid="stock-gauge"
      data-level={level}
      className={`inline-flex min-w-0 items-center gap-1.5 ${className}`}
    >
      <span className="relative h-1 w-12 shrink-0 overflow-hidden rounded-chip bg-edge" aria-hidden>
        <span className={`absolute inset-y-0 left-0 rounded-chip ${FILL[level]}`} style={{ width: `${fill}%` }} />
        <span className="absolute inset-y-0 left-1/2 w-px bg-ink-muted" />
      </span>
      {showFigure && (
        <span className={`whitespace-nowrap text-t-caption tabular-nums ${TEXT[level]}`}>{formatOfTotal(stock, target)}</span>
      )}
    </span>
  )
}

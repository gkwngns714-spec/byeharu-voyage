import { useState } from 'react'
import { Bar } from './Bar'
import { Figure } from './Figure'
import { PriceChart } from './PriceChart'
import { Row } from './Row'
import { Sparkline } from './Sparkline'
import { formatInt, formatOfTotal } from '../../lib/format'
import type { MarketGood, PricePoint } from '../../lib/rpc'

// WHAT A PRICE HAS BEEN, HOW FAR IT CAN GO, AND HOW MUCH IS THERE — the three rows under a good,
// wherever it is read: Trend · Range · In stock.
//
// MOVED HERE 2026-09-11 from features/market/PriceTray.tsx (owner row 76, the Quay Ledger). Two
// trays draw these rows: the design system's `TradeTray` (a row unfolded on the quay she lies at)
// and PORT's read-only `PriceTray` (a quay she is not on). A component may not import a screen
// (tests/sections.spec.ts, "machinery knows nothing above it"), so the rows both compose moved DOWN
// to where both can reach them — never copied. Trend, Range and In stock are spelt HERE and
// nowhere else: the stock row was drawn two ways for a day (a figure in one tray, a figure and the
// served `stock_band` bar in the other), and it is one row now. The bar stays — since the ledger
// row lost its stock meter (docs/QUAY_LEDGER.md §3 A) this is the only place stock is drawn.
//
// THE TREND HAS TWO FORMS, ONE ROW (slice 3, 2026-09-13). Folded, it is the `Sparkline` — the
// shape of the move, no axes, nothing below two points. A press on the row unfolds the same served
// line as `PriceChart`: a scale of three served figures, an axis in hours before now, and the low,
// high and latest points marked. A second press folds it back. What the press changes is which
// form is drawn; the points are the same served array either way, and nothing above the row moves
// (what is below moves down, which is what an unfold IS). The axis ends at the instant the chart
// was opened — recorded once on the press, so a re-render does not creep the axis.
//
// THE RANGE IS THIS QUAY'S, TODAY. `range_lo … range_hi` (0071) is how far this price can travel
// here, at this reading — it is never a fortnight's low and high, and the label does not claim one.

/** ONE good's remembered prices at ONE port, as `src/live/usePortHistory.ts` reads them: the served
 *  points (undefined until the read lands) and the served cadence the axis is labelled in. Declared
 *  here, below both callers, so the trays and the hook share one shape (docs/NO_SPAGHETTI.md §2). */
export interface PriceTrend {
  /** Oldest first; the served array reference, never a fresh literal. */
  points: readonly PricePoint[] | undefined
  /** `PriceHistory.slot_seconds`; null until the read lands. */
  slotSeconds: number | null
}

export function PriceRows({
  good,
  trend,
}: {
  good: MarketGood
  /** The remembered mids for THIS good at THIS port, and their cadence. */
  trend: PriceTrend
}) {
  const points = trend.points ?? []
  const mids = points.map((pt) => pt.mid)
  const drawable = mids.length >= 2 && trend.slotSeconds !== null
  // The instant the chart was opened, or null while folded. One state for "is it open" and "when".
  const [openedAt, setOpenedAt] = useState<number | null>(null)
  const open = drawable && openedAt !== null

  return (
    <>
      <Row
        label="Trend"
        tone={mids.length < 2 ? 'muted' : 'default'}
        chevron={drawable}
        onClick={drawable ? () => setOpenedAt(open ? null : Date.now()) : undefined}
        aria-expanded={drawable ? open : undefined}
        data-testid="trend-row"
      >
        {mids.length < 2 ? (
          <span className="block text-t-caption">No price history yet.</span>
        ) : open ? (
          <PriceChart
            points={points}
            slotSeconds={trend.slotSeconds as number}
            nowMs={openedAt as number}
            label={`${good.name}: ${mids.length} past prices, ${formatInt(Math.min(...mids))} to ${formatInt(Math.max(...mids))}, with an axis`}
          />
        ) : (
          <Sparkline
            values={mids}
            width={320}
            height={40}
            className="mt-1 h-10 w-full"
            label={`${good.name}: ${mids.length} past prices, ${formatInt(Math.min(...mids))} to ${formatInt(Math.max(...mids))}`}
          />
        )}
      </Row>
      <Row label="Range" value={<Figure value={`${formatInt(good.range_lo)}–${formatInt(good.range_hi)}`} />} />
      <Row
        label="In stock"
        value={<Figure value={formatOfTotal(good.stock, good.stock_target)} unit="units" />}
        data-testid="quay-stock"
      >
        <Bar
          value={good.stock_band}
          of={6}
          tone={good.stock_band <= 1 ? 'warning' : 'neutral'}
          label={`${good.name} in stock`}
          className="mt-1"
        />
      </Row>
    </>
  )
}

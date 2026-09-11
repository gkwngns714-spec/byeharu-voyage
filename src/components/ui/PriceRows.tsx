import { Bar } from './Bar'
import { Figure } from './Figure'
import { Row } from './Row'
import { Sparkline } from './Sparkline'
import { formatInt, formatTuns } from '../../lib/format'
import type { MarketGood, PricePoint } from '../../lib/rpc'

// WHAT A PRICE HAS BEEN, HOW FAR IT CAN GO, AND HOW MUCH IS THERE — the three rows under a good,
// wherever it is read: Trend · Range · On the quay.
//
// MOVED HERE 2026-09-11 from features/market/PriceTray.tsx (owner row 76, the Quay Ledger). Two
// trays draw these rows: the design system's `TradeTray` (a row unfolded on the quay she lies at)
// and PORT's read-only `PriceTray` (a quay she is not on). A component may not import a screen
// (tests/sections.spec.ts, "machinery knows nothing above it"), so the rows both compose moved DOWN
// to where both can reach them — never copied. Trend, Range and On the quay are spelt HERE and
// nowhere else: the stock row was drawn two ways for a day (a figure in one tray, a figure and the
// served `stock_band` bar in the other), and it is one row now. The bar stays — since the ledger
// row lost its stock meter (docs/QUAY_LEDGER.md §3 A) this is the only place stock is drawn.
//
// THE TREND KEEPS ITS AUSTERITY (Sparkline.tsx): the shape of the move, no axes, no interpolation,
// nothing below two points. A good the record has not sampled twice says so in a row rather than
// drawing a dot on an empty box.
//
// THE RANGE IS THIS QUAY'S, TODAY. `range_lo … range_hi` (0071) is how far this price can travel
// here, at this reading — it is never a fortnight's low and high, and the label does not claim one.

export function PriceRows({
  good,
  points,
}: {
  good: MarketGood
  /** The remembered mids for THIS good at THIS port, oldest first; undefined until the read lands. */
  points: readonly PricePoint[] | undefined
}) {
  const mids = (points ?? []).map((pt) => pt.mid)
  return (
    <>
      <Row label="Trend" tone={mids.length < 2 ? 'muted' : 'default'}>
        {mids.length < 2 ? (
          <span className="block text-t-caption">Not remembered here yet.</span>
        ) : (
          <Sparkline
            values={mids}
            width={320}
            height={40}
            className="mt-1 h-10 w-full"
            label={`${good.name}: ${mids.length} remembered prices, ${formatInt(Math.min(...mids))} to ${formatInt(Math.max(...mids))}`}
          />
        )}
      </Row>
      <Row label="Range" value={<Figure value={`${formatInt(good.range_lo)}–${formatInt(good.range_hi)}`} />} />
      <Row
        label="On the quay"
        value={<Figure value={formatTuns(good.stock)} unit={`of ${formatTuns(good.stock_target)}`} />}
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

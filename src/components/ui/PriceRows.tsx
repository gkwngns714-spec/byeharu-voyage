import { useState } from 'react'
import { StockGauge } from './StockGauge'
import { Figure } from './Figure'
import { GoodKind } from './GoodKind'
import { PriceChart } from './PriceChart'
import { Row } from './Row'
import { Sparkline } from './Sparkline'
import { formatOfTotal, formatPriceFigure } from '../../lib/format'
import type { MarketGood, PricePoint } from '../../lib/rpc'
import { useT } from '../../lib/i18n'

// WHAT A GOOD IS, WHAT ITS PRICE HAS BEEN, HOW FAR IT CAN GO, AND HOW MUCH IS THERE — the four
// rows under a good, wherever it is read: Kind · Trend · Range · In stock.
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
//
// THE KIND ROW came first on 2026-10-20 (owner row 177: *"The trade goods should show rarity, and
// what class?"*). Both words are served on the market row itself — `category` and the 0032 tier —
// so this costs no read, and it lands in BOTH trays at once, which is why it was put here rather
// than in either of them. `GoodKind` is the one composition of the two words.

/** ONE good's remembered prices at ONE port, as `src/live/usePortHistory.ts` reads them: the served
 *  points (undefined until the read lands) and the served cadence the axis is labelled in. Declared
 *  here, below both callers, so the trays and the hook share one shape (docs/NO_SPAGHETTI.md §2). */
export interface PriceTrend {
  /** Oldest first; the served array reference, never a fresh literal. */
  points: readonly PricePoint[] | undefined
  /** `PriceHistory.slot_seconds`; null until the read lands. */
  slotSeconds: number | null
  /** `PriceHistory.slots` — how many slots the SERVER was willing to serve, which is how far back the
   *  record truly reaches (`public.price_history_window` clamps every ask to what it retains). Null
   *  until the read lands; a caller that asks for one window and is given a shorter one says so rather
   *  than drawing an empty stretch of axis (2026-10-20, owner request 178). */
  slots?: number | null
}

export function PriceRows({
  good,
  trend,
}: {
  good: MarketGood
  /** The remembered mids for THIS good at THIS port, and their cadence. */
  trend: PriceTrend
}) {
  const t = useT()
  const points = trend.points ?? []
  const mids = points.map((pt) => pt.mid)
  const drawable = mids.length >= 2 && trend.slotSeconds !== null
  // The instant the chart was opened, or null while folded. One state for "is it open" and "when".
  const [openedAt, setOpenedAt] = useState<number | null>(null)
  const open = drawable && openedAt !== null

  return (
    <>
      {/* WHAT IT IS, before what it costs — the kind, then how rare a source is (owner row 177). */}
      <Row label={t('ui.kind')} value={<GoodKind category={good.category} rarity={good.rarity} />} data-testid="good-kind-row" />
      <Row
        label={t('ui.trend')}
        tone={mids.length < 2 ? 'muted' : 'default'}
        chevron={drawable}
        onClick={drawable ? () => setOpenedAt(open ? null : Date.now()) : undefined}
        aria-expanded={drawable ? open : undefined}
        data-testid="trend-row"
      >
        {mids.length < 2 ? (
          <span className="block text-t-caption">{t('ui.noHistory')}</span>
        ) : open ? (
          <PriceChart
            points={points}
            slotSeconds={trend.slotSeconds as number}
            nowMs={openedAt as number}
            label={t('ui.pastPricesAxis', { name: good.name, n: mids.length, lo: formatPriceFigure(Math.min(...mids)), hi: formatPriceFigure(Math.max(...mids)) })}
          />
        ) : (
          <Sparkline
            values={mids}
            width={320}
            height={40}
            className="mt-1 h-10 w-full"
            label={t('ui.pastPrices', { name: good.name, n: mids.length, lo: formatPriceFigure(Math.min(...mids)), hi: formatPriceFigure(Math.max(...mids)) })}
          />
        )}
      </Row>
      <Row label={t('ui.range')} value={<Figure value={`${formatPriceFigure(good.range_lo)}–${formatPriceFigure(good.range_hi)}`} />} />
      <Row
        label={t('ui.inStock')}
        value={<Figure value={formatOfTotal(good.stock, good.stock_target)} unit={t('ui.unitUnits')} />}
        data-testid="quay-stock"
      >
        <StockGauge stock={good.stock} target={good.stock_target} label={good.name} showFigure={false} className="mt-1" />
      </Row>
    </>
  )
}

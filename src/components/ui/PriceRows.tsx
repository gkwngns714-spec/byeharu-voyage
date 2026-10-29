import { useState } from 'react'
import { StockGauge } from './StockGauge'
import { Figure } from './Figure'
import { GoodKind } from './GoodKind'
import { PriceChart } from './PriceChart'
import { primarySide, primaryValue } from './priceChartModel'
import { Row } from './Row'
import { Skeleton } from './Skeleton'
import { SpanPicker } from './SpanPicker'
import { Sparkline } from './Sparkline'
import { formatOfTotal, formatPriceFigure } from '../../lib/format'
import type { MarketGood, NewsMark, PriceSeries, PriceSpan } from '../../lib/rpc'
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
// record as `PriceChart`: a scale of three served figures, an axis in time before now, and the low,
// high and latest points marked. A second press folds it back. What the press changes is which
// form is drawn; the points are the same served array either way, and nothing above the row moves
// (what is below moves down, which is what an unfold IS). The axis ends at the instant the chart
// was opened — recorded once on the press, so a re-render does not creep the axis.
//
// THE SPAN (0226, owner row 205): a `SpanPicker` stands in the row in BOTH forms — a day, a week, a
// month, a year, all — and a press on it SELECTS: the store asks the server for that span and the
// same row redraws; the picker keeps its height, so nothing under it moves. BOTH SIDES (owner row
// 189): the chart draws what the city asks and what it pays; the folded sparkline follows the
// primary side (the ask where the city sells the good, else the bid). A span with nothing in it yet
// — a city that only buys the good, just asked for; a month on a record two days old — says
// "No data yet" in the line's place and nothing else. WHILE THE READ IS ON THE WIRE the line's place
// is held at the sparkline's own height (a skeleton), so the rows under it do not move when it lands:
// since 0226 the record is read per (city, good) on the press, not per city ahead of it.
//
// THE RANGE IS THIS QUAY'S, TODAY. `range_lo … range_hi` (0071) is how far this price can travel
// here, at this reading — it is never a fortnight's low and high, and the label does not claim one.
//
// THE KIND ROW came first on 2026-10-20 (owner row 177: *"The trade goods should show rarity, and
// what class?"*). Both words are served on the market row itself — `category` and the 0032 tier —
// so this costs no read, and it lands in BOTH trays at once, which is why it was put here rather
// than in either of them. `GoodKind` is the one composition of the two words.

/** ONE good's price at ONE port over the chosen span, as `src/live/usePriceSeries.ts` reads it: the
 *  served series (undefined until the read lands), the span it was asked for and the one way to change
 *  it. Declared here, below every caller, so the trays, the desk and the hook share one shape
 *  (docs/NO_SPAGHETTI.md §2). */
export interface PriceTrend {
  /** The served series reference, never a fresh literal; undefined until the read lands. */
  series: PriceSeries | undefined
  /** The span every chart is on (`useChartSpan`). */
  span: PriceSpan
  setSpan: (span: PriceSpan) => void
}

export function PriceRows({
  good,
  trend,
  startOpen = false,
  compactChart = false,
  marks = null,
  onOpenCity,
}: {
  good: MarketGood
  /** The remembered mids for THIS good at THIS port, and their cadence. */
  trend: PriceTrend
  /** The trend stands unfolded as the chart from the first paint — the MAP's good panel, whose whole
   *  point is the chart (owner row 220), and the COMMAND desk's Buy / Sell good page (owner row 218). A press on
   *  the row still folds it. */
  startOpen?: boolean
  /** The chart as a compact panel (owner row 226) — the COMMAND good page's, in a column wider than a tray. */
  compactChart?: boolean
  /** The news markers the unfolded chart draws (0279, owner row 216); the caller reads them over the
   *  window the chart draws. Null draws none — the row is exactly what it was. */
  marks?: readonly NewsMark[] | null
  /** Opens a marker's city (the caller's navigation); absent, the card offers no link. */
  onOpenCity?: (portCode: string) => void
}) {
  const t = useT()
  const points = trend.series?.points ?? []
  const side = primarySide(points)
  const values = points.map((pt) => primaryValue(pt, side))
  const drawable = values.length >= 2 && trend.series !== undefined
  // The instant the chart was opened, or null while folded. One state for "is it open" and "when".
  const [openedAt, setOpenedAt] = useState<number | null>(() => (startOpen ? Date.now() : null))
  const open = drawable && openedAt !== null

  return (
    <>
      {/* WHAT IT IS, before what it costs — the kind, then how rare a source is (owner row 177). */}
      <Row label={t('ui.kind')} value={<GoodKind category={good.category} rarity={good.rarity} />} data-testid="good-kind-row" />
      <Row
        label={t('ui.trend')}
        tone={trend.series !== undefined && values.length < 2 ? 'muted' : 'default'}
        chevron={drawable}
        onClick={drawable ? () => setOpenedAt(open ? null : Date.now()) : undefined}
        aria-expanded={drawable ? open : undefined}
        data-testid="trend-row"
      >
        {/* the span, in both forms; a press on it must not fold or unfold the row */}
        <div onClick={(e) => e.stopPropagation()} className="mt-1">
          <SpanPicker value={trend.span} onChange={trend.setSpan} />
        </div>
        {trend.series === undefined ? (
          <Skeleton className="mt-1 h-10 w-full" />
        ) : values.length < 2 ? (
          <span className="mt-1 block h-10 text-t-caption" data-testid="trend-empty">
            {t('ui.noData')}
          </span>
        ) : open ? (
          <PriceChart
            points={points}
            slotSeconds={(trend.series as PriceSeries).step_seconds}
            nowMs={openedAt as number}
            compact={compactChart}
            marks={marks}
            onOpenCity={onOpenCity}
            label={t('ui.pastPricesAxis', { name: good.name, n: values.length, lo: formatPriceFigure(Math.min(...values)), hi: formatPriceFigure(Math.max(...values)) })}
          />
        ) : (
          <Sparkline
            values={values}
            width={320}
            height={40}
            className="mt-1 h-10 w-full"
            label={t('ui.pastPrices', { name: good.name, n: values.length, lo: formatPriceFigure(Math.min(...values)), hi: formatPriceFigure(Math.max(...values)) })}
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

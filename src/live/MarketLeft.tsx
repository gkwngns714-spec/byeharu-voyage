import { Figure, Note, PriceChart, Row, Skeleton, SpanPicker, StockGauge } from '../components/ui'
import { useShellState } from '../app/shellState'
import { formatOfTotal, formatPriceFigure } from '../lib/format'
import type { MarketGood, SnapshotPort } from '../lib/rpc'
import { useT } from '../lib/i18n'
import { usePickedGood } from './marketPick'
import { usePortMarket } from './usePortMarket'
import { usePriceSeries } from './usePriceSeries'

// THE MARKET'S LEFT REGION — the chart, instead of the city picture (owner, 2026-10-31: *"when
// pressing a market, instead of city, i would like to have a graph shown, that is changed when
// pressed a trade good"*). It paints the SAME served series every chart in the game paints
// (usePriceSeries over world.price_series) and decides nothing: the good in hand is the pick store's
// answer (marketPick.ts), the points are the read's, the words are the dictionaries'.
//
// THE CHART IS ALWAYS DRAWN, never folded (the owner's "enough with folding things"): the row set
// under it is the design system's Row/StockGauge with the same ui.* words PriceRows prints, so this
// panel is a column of the same facts, not a second price block. The span control is the one
// SpanPicker over the one chart-span store.
export function MarketLeft({ port, good: given = null }: { port: SnapshotPort; good?: MarketGood | null }) {
  const t = useT()
  const { nowMs } = useShellState()
  // One market read for the port; the panel reads the same cached answer (usePortMarket).
  const quay = usePortMarket(port.kind === 'HARBOUR' ? port.id : null)
  const goods = quay.market?.goods ?? []
  const picked = usePickedGood(port.id, goods)
  const good = given ?? picked
  const trend = usePriceSeries(port.id, good?.good_id ?? null)

  if (!good) {
    return (
      <div className="flex h-full min-h-0 flex-col rounded-tile bg-surface p-2" data-testid="city-market-chart">
        {quay.market === undefined ? (
          <Skeleton className="h-24 w-full" />
        ) : (
          <Note tone="neutral">{t('city.noMarket')}</Note>
        )}
      </div>
    )
  }
  const series = trend.series
  return (
    <div className="flex h-full min-h-0 flex-col rounded-tile bg-surface px-2 py-1" data-testid="city-market-chart">
      <div className="flex min-h-6 items-baseline justify-between gap-2">
        <span className="min-w-0 truncate text-t-caption text-ink-faint" data-testid="city-market-chart-good">
          {good.name}
        </span>
        <span className="shrink-0 text-t-caption tabular-nums text-ink-muted">
          {formatPriceFigure(good.buy)} · {formatPriceFigure(good.sell)}
        </span>
      </div>
      <div className="shrink-0">
        {series !== undefined ? (
          <PriceChart
            points={series.points}
            slotSeconds={series.step_seconds}
            nowMs={nowMs}
            compact
            label={good.name}
          />
        ) : (
          <Skeleton className="mt-1 h-24 w-full" />
        )}
        <SpanPicker value={trend.span} onChange={trend.setSpan} className="mt-1" />
      </div>
      <div className="min-h-0 flex-1 overflow-hidden">
        <Row
          label={t('ui.range')}
          value={<Figure value={`${formatPriceFigure(good.range_lo)}–${formatPriceFigure(good.range_hi)}`} />}
        />
        <Row
          label={t('ui.inStock')}
          value={<Figure value={formatOfTotal(good.stock, good.stock_target)} unit={t('ui.unitUnits')} />}
          data-testid="city-market-stock"
        >
          <StockGauge stock={good.stock} target={good.stock_target} label={good.name} showFigure={false} className="mt-1" />
        </Row>
      </div>
    </div>
  )
}

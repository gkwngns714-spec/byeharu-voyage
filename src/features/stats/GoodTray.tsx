import { useMemo, useState } from 'react'
import { Figure, FactsLine, GoodKind, Row, Segmented, SeriesChart, SpanPicker, StockGauge, Tray, categoryLabel, type TrayDetent } from '../../components/ui'
import { formatInt, formatPctChange, formatPriceFigure } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { StatsGood } from '../../lib/rpc'
import { usePriceSeries } from '../../live/usePriceSeries'
import { useWorld } from '../../live/worldStore'
import { useChartSpan } from '../../store/chartSpan'
import { goodName, portName, toSeries } from './statsFaces'
import { GoodPrices, HistoryChart } from '../../live/HistoryChart'
import { goodLines } from '../../live/historyLines'

// A GOOD'S DETAIL TRAY (owner, 2026-11-02: *"on stats, market - trade goods. nothing opened… when i click i want to see
// the charts and info"*). Pressing a good on Stats → Markets opens the SAME `Tray` the Buy / Sell page and the Stats
// charts open, over the page (`position: fixed`, so the list under it never moves). It holds the good's figures (price,
// move, sold and bought, stock) and its charts. THE WORLD CHART IS ALWAYS THERE: the server already serves every good's
// newest 24 recorded mids across all markets (`StatsGood.spark`), so the chart needs no extra read. A city's own chart
// (the SAME `SpanPicker` over the SAME `SeriesChart`, read through the SAME `usePriceSeries`) stands as a choice for
// every city whose book is ALREADY in the store (`markets`): the tray asks for no city's book itself (a first draft
// asked for all of them when it opened, and drew nothing until one landed). A good with fewer than two recorded mids
// has no chart and says so; it is never a dash where a chart is owed.

const WORLD = 'world'

export function GoodTray({ g, move, goodClass, onClose }: { g: StatsGood; move: number | null; goodClass: number | undefined; onClose: () => void }) {
  const t = useT()
  const [detent, setDetent] = useState<TrayDetent>('full')
  const ports = useWorld((s) => s.snapshot?.ports)
  const markets = useWorld((s) => s.markets)
  const cities = useMemo(
    () =>
      (ports ?? [])
        .map((p) => ({ port: p, row: markets[p.id]?.goods.find((m) => m.code === g.code) }))
        .filter((c) => c.row !== undefined)
        .map((c) => ({ id: c.port.id, name: portName(c.port.name), goodId: c.row!.good_id })),
    [ports, markets, g.code],
  )
  const [picked, setPicked] = useState<string>(WORLD)
  const city = cities.find((c) => c.id === picked) ?? null
  const trend = usePriceSeries(city?.id ?? null, city?.goodId ?? null)
  const { span, setSpan } = useChartSpan()
  const points = city === null ? g.spark.map((value, i) => ({ atMs: i, value })) : toSeries(trend.series?.points ?? [], (p) => p.ask ?? p.bid)
  return (
    <Tray detent={detent} onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))} title={goodName(g)} data-testid="stats-good-tray" data-good={g.code}>
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 pt-1 text-t-caption text-ink-muted">
        <span>{categoryLabel(g.category)}</span>
        <GoodKind goodClass={goodClass} />
      </div>
      {g.mid !== null && <Row label={t('stats.priceNow')} value={<Figure value={formatPriceFigure(g.mid)} size="figure" />} />}
      {move !== null && <Row label={t('stats.moveLabel')} value={<Figure value={formatPctChange(move)} size="figure" tone={move > 0 ? 'success' : move < 0 ? 'danger' : 'ink'} />} />}
      <FactsLine>
        <span>{t('stats.sold', { n: formatInt(g.sold_1d) })}</span>
        <span>{t('stats.bought', { n: formatInt(g.bought_1d) })}</span>
        {g.markets > 0 && <StockGauge stock={g.stock} target={g.stock_target} label={t('stats.everyMarket', { name: goodName(g) })} className="shrink-0" />}
        {g.markets === 0 && <span>{t('stats.noCitySells')}</span>}
      </FactsLine>
      <div className="mt-3" data-testid="stats-good-chart" data-city={city?.id ?? WORLD} data-points={points.length}>
        {cities.length > 0 && (
          <Segmented segments={[{ id: WORLD, label: t('stats.goodWorld') }, ...cities.map((c) => ({ id: c.id, label: c.name }))]} value={city?.id ?? WORLD} onChange={setPicked} label={t('stats.goodCities')} />
        )}
        {city !== null && (
          <div className="mt-3">
            <SpanPicker value={span} onChange={setSpan} />
          </div>
        )}
        {points.length >= 2 ? (
          <SeriesChart
            points={points}
            format={formatPriceFigure}
            label={city === null ? t('stats.goodWorldSeries', { name: goodName(g) }) : t('stats.goodSeries', { name: goodName(g), city: city.name })}
            size={{ width: 640, height: 280 }}
            className="mt-3"
          />
        ) : (
          <span className="mt-3 block text-t-caption text-ink-faint">{t('ui.noData')}</span>
        )}
      </div>
      <HistoryChart what="good" subject={g.code} title={t('stats.marketHistory')} lines={goodLines(t)} under={GoodPrices} className="mt-3" data-testid="history-good" />
    </Tray>
  )
}

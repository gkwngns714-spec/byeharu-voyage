import { useEffect, useMemo, useState } from 'react'
import { Figure, FactsLine, GoodKind, Row, Segmented, SeriesChart, SpanPicker, StockGauge, Tray, categoryLabel, type TrayDetent } from '../../components/ui'
import { formatInt, formatPctChange, formatPriceFigure } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { StatsGood } from '../../lib/rpc'
import { usePriceSeries } from '../../live/usePriceSeries'
import { useWorld } from '../../live/worldStore'
import { useChartSpan } from '../../store/chartSpan'
import { goodName, portName, toSeries } from './statsFaces'

// A GOOD'S DETAIL TRAY (owner, 2026-11-02: *"on stats, market - trade goods. nothing opened… when i click i want to see
// the charts and info"*). Pressing a good on Stats → Markets opens the SAME `Tray` the Buy / Sell page and the Stats
// charts open, over the page (`position: fixed`, so the list under it never moves). It holds the good's figures (price,
// move, sold and bought, stock) and its price chart: the SAME `SpanPicker` over the SAME `SeriesChart`, read through the
// SAME `usePriceSeries`. The server keeps a price series per city and none for the whole world, so the chart is ONE city's:
// the cities whose book lists the good stand as a choice (the store's `markets`, read when the tray opens), and the
// first is drawn. A good no city lists has no chart and says so; it is never a dash where a chart is owed.

export function GoodTray({ g, move, goodClass, onClose }: { g: StatsGood; move: number | null; goodClass: number | undefined; onClose: () => void }) {
  const t = useT()
  const [detent, setDetent] = useState<TrayDetent>('full')
  const ports = useWorld((s) => s.snapshot?.ports)
  const markets = useWorld((s) => s.markets)
  const loadMarket = useWorld((s) => s.loadMarket)
  useEffect(() => {
    for (const p of ports ?? []) if (markets[p.id] === undefined) void loadMarket(p.id)
    // read once when the tray opens: the book of a city that has landed is not asked for again
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ports, loadMarket])
  const cities = useMemo(
    () =>
      (ports ?? [])
        .map((p) => ({ port: p, row: markets[p.id]?.goods.find((m) => m.code === g.code) }))
        .filter((c) => c.row !== undefined)
        .map((c) => ({ id: c.port.id, name: portName(c.port.name), goodId: c.row!.good_id })),
    [ports, markets, g.code],
  )
  const [picked, setPicked] = useState<string | null>(null)
  const city = cities.find((c) => c.id === picked) ?? cities[0] ?? null
  const trend = usePriceSeries(city?.id ?? null, city?.goodId ?? null)
  const { span, setSpan } = useChartSpan()
  const points = toSeries(trend.series?.points ?? [], (p) => p.ask ?? p.bid)
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
      {city !== null && (
        <div className="mt-3" data-testid="stats-good-chart" data-city={city.id}>
          <Segmented segments={cities.map((c) => ({ id: c.id, label: c.name }))} value={city.id} onChange={setPicked} label={t('stats.goodCities')} />
          <div className="mt-3">
            <SpanPicker value={span} onChange={setSpan} />
          </div>
          {points.length >= 2 ? (
            <SeriesChart points={points} format={formatPriceFigure} label={t('stats.goodSeries', { name: goodName(g), city: city.name })} size={{ width: 640, height: 280 }} className="mt-3" />
          ) : (
            <span className="mt-3 block text-t-caption text-ink-faint">{t('ui.noData')}</span>
          )}
        </div>
      )}
    </Tray>
  )
}

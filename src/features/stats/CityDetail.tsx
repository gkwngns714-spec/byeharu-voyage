import {
  Empty,
  FactsLine,
  Figure,
  Flag,
  Hint,
  Note,
  RankBars,
  Row,
  SeriesChart,
  SheetSection,
  SignedBars,
  Skeleton,
  Sparkline,
  StatCell,
  StockGauge,
  categoryLabel,
  deltaTone,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatPctChange, formatPriceFigure } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldStatsCity, type StatsCity } from '../../lib/rpc'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { STATS_BARS, flowRanks, goodName, movePct, portName, toSeries } from './statsFaces'
import { useLiveRead } from './statsLive'

// ONE CITY, OPEN TO EVERYONE — the row the Cities face opens (0214; 0223 removed the investment gate, the
// owner's row 197: *"on cities, i want to see all the info without investment"*).
//
// Nothing here decides what you may see: `overview` and `detail` are both served once the job has written
// the city's first rollup row, and are absent only before that (drawn as nothing, not as a failure).
//
// THE PICTURE: the purse as one line over the counts, income against spending as bars from a zero line,
// what the city buys and sells most as ranked bars; then every good, each with its own sparkline — the
// shape the Markets face uses, so a good does not look different here.
//
// EVERY SECOND (0232, owner row 213): the purse and each good's price and stock are live, every day-figure is the
// last 24 h up to this second, the purse line and each spark end at now(); asked every second while open.

export function CityDetail({ portId, onClose }: { portId: string; onClose: () => void }) {
  const t = useT()
  const read = useLiveRead<StatsCity>(`stats:city:${portId}`, () => worldStatsCity(portId))
  const v = read.view
  const nationByCode = useWorld((s) => s.nationByCode)
  if (read.loading && !v) return <Skeleton className="mt-4 h-40 w-full" />
  if (!v) return <Note tone="danger" className="mt-4">{t('stats.cityFailed')}</Note>
  const flag = v.city.nation === null ? undefined : <Flag code={v.city.nation} name={nationNameOf(nationByCode, v.city.nation)} size="body" />
  const o = v.overview

  return (
    <SheetSection
      heading={
        <span className="flex items-center gap-2">
          {flag}
          {portName(v.city.name)}
        </span>
      }
      trailing={
        <button type="button" className="min-h-11 px-2 text-t-caption text-accent" onClick={onClose} data-testid="stats-city-close">
          {t('common.close')}
        </button>
      }
      data-testid="stats-city"
    >
      {o && (
        <div data-testid="stats-city-overview">
          <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
            <StatCell label={t('town.i_purse')} value={o.purse} format={formatDucats} size="body" tone="accent" />
            <StatCell label={t('town.i_in')} value={o.income_1d} format={formatDucatsDelta} size="body" tone="success" />
            <StatCell label={t('town.i_out')} value={-o.spending_1d} format={formatDucatsDelta} size="body" tone="danger" />
            <StatCell label={t('town.i_taxes')} value={o.taxes_1d} format={formatDucats} size="body" />
          </div>
          <SeriesChart
            points={toSeries(o.series, (p) => p.purse)}
            format={formatDucats}
            label={t('stats.citySeries', { city: portName(v.city.name) })}
            tone="accent"
            className="mt-4"
            empty={<Hint className="mt-3">{t('stats.lineSoon')}</Hint>}
          />
          <SignedBars
            bars={o.series.slice(-STATS_BARS).map((p) => ({ id: p.at, value: p.income - p.spending }))}
            label={t('stats.cityNet', { city: portName(v.city.name) })}
            height="h-20"
            className="mt-4"
          />
          <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
            <div className="min-w-0">
              <span className="block text-t-caption text-ink-faint">{t('stats.soldCityMost')}</span>
              <RankBars
                rows={o.top_sold.map((r) => ({ id: r.code, label: goodName(r), value: r.units, text: t('format.units', { n: formatInt(r.units), count: r.units }), note: formatDucats(r.ducats) }))}
                format={formatInt}
              />
            </div>
            <div className="min-w-0">
              <span className="block text-t-caption text-ink-faint">{t('stats.boughtCityMost')}</span>
              <RankBars
                rows={o.top_bought.map((r) => ({ id: r.code, label: goodName(r), value: r.units, text: t('format.units', { n: formatInt(r.units), count: r.units }), note: formatDucats(r.ducats) }))}
                format={formatInt}
              />
            </div>
          </div>
          {o.flows_1d.length > 0 && (
            <div className="mt-4">
              <span className="block text-t-caption text-ink-faint">{t('stats.cityMoney')}</span>
              <RankBars rows={flowRanks(o.flows_1d)} format={formatDucatsDelta} />
            </div>
          )}
          <span className="mt-3 block text-t-caption text-ink-faint">
            {t('stats.works', { list: o.works.map((w) => `${w.kind} ${w.level}`).join(' · ') || t('stats.noWorks') })}
          </span>
        </div>
      )}
      {v.detail && (
        <div className="mt-4" data-testid="stats-city-detail">
          <span className="block text-t-caption text-ink-faint">{t('stats.goodsHere', { n: formatInt(v.detail.goods.length) })}</span>
          {v.detail.goods.length === 0 ? (
            <Empty className="mt-2">{t('stats.nothingHere')}</Empty>
          ) : (
            v.detail.goods.map((g, i, all) => {
              const move = movePct(g.mid, g.mid_1d)
              return (
                <Row
                  key={g.code}
                  label={
                    <span className="flex min-w-0 items-center gap-2">
                      <span className="min-w-0 break-words text-ink">{goodName(g)}</span>
                      <span className="shrink-0 text-t-caption text-ink-faint">{categoryLabel(g.category)}</span>
                    </span>
                  }
                  value={
                    <span className="flex items-center gap-3">
                      <Sparkline
                        values={g.spark}
                        tone={move === null || move === 0 ? 'even' : move > 0 ? 'dear' : 'cheap'}
                        width={48}
                        height={18}
                        label={t('stats.atCity', { name: goodName(g), city: portName(v.city.name), n: g.spark.length })}
                      />
                      <span className="flex w-24 flex-col items-end">
                        <Figure value={g.mid === null ? '—' : formatPriceFigure(g.mid)} />
                        <Figure value={move === null ? '—' : formatPctChange(move)} tone={move === null ? 'faint' : deltaTone(move)} />
                      </span>
                    </span>
                  }
                  hairline={i < all.length - 1}
                  data-testid="stats-city-good"
                >
                  <FactsLine>
                    <span>{t('stats.sold', { n: formatInt(g.sold_1d) })}</span>
                    <span>{t('stats.bought', { n: formatInt(g.bought_1d) })}</span>
                    {g.stock !== null && g.stock_target !== null && g.stock_target > 0 && (
                      <StockGauge stock={g.stock} target={g.stock_target} label={t('stats.stockAt', { name: goodName(g), city: portName(v.city.name) })} className="shrink-0" />
                    )}
                    {g.stock === null && <span>{t('stats.notSoldHere')}</span>}
                  </FactsLine>
                </Row>
              )
            })
          )}
        </div>
      )}
    </SheetSection>
  )
}

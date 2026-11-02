import {
  Card,
  Empty,
  FactsLine,
  Figure,
  Hint,
  ListPanel,
  Note,
  PAGE_GAP,
  RankBars,
  Row,
  SignedBars,
  Skeleton,
  Sparkline,
  StatCard,
  StatStrip,
  StockGauge,
  categoryLabel,
  deltaTone,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatPctChange, formatPriceFigure } from '../../lib/format'
import { useEffect } from 'react'
import { useT } from '../../lib/i18n'
import { worldStatsCity, type StatsCity } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { CARD_CHART_H, STATS_BARS, flowRanks, goodName, movePct, portName, toSeries } from './statsFaces'
import { useLiveRead } from './statsLive'
import { StatsChart } from './StatsChart'
import { useChartSpan } from '../../store/chartSpan'

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
// A PAGE, NOT A SECTION (the unfold slice, 2026-11-02): a city's row on the Cities list opens this inside a
// `DetailPage` — its title, its purse and its Back are the page's own, so the old heading and its Close are gone.
//
// THE PAGE PATTERN (2026-11-02, owner row 267: *"it looks so wrong … everything is on left, too packed"*): the page's
// content is a centred container of at most 80 rem on the page's own margins; the four figures are a strip of stat
// cards (24 px), the purse line and the net bars are cards with a 176-px chart, what it sold and bought most are two
// cards across, and the goods are ONE list card in as many columns as the page holds. (The page is the shared
// `DetailPage` primitive and keeps its own header and its one bounded scroll; nothing of it is touched.)
//
// EVERY SECOND (0232, owner row 213): the purse and each good's price and stock are live, every day-figure is the
// last 24 h up to this second, the purse line and each spark end at now(); asked every second while open.

/** The page's container inside a `DetailPage`'s body (which already has 16 px of side padding): 80 rem at most, and the page's
 *  own margins (24 · 32 · 40 from 768 · 1,024 · 1,280) made up with the extra side padding. */
const CITY_PAGE = `mx-auto flex w-full max-w-[80rem] flex-col pt-1 md:pt-3 ${PAGE_GAP} md:px-2 lg:px-4 xl:px-6`
/** Two cards across from 768. */
const PAIR = `grid grid-cols-1 ${PAGE_GAP} md:grid-cols-2`

export function CityDetail({ portId }: { portId: string }) {
  const t = useT()
  const { span } = useChartSpan()   // 0246: one span for every chart
  const read = useLiveRead<StatsCity>(`stats:city:${portId}`, () => worldStatsCity(portId, span), span)
  const v = read.view
  // 0263 (CLOSED_ECONOMY §4b, "Stats → Cities: a city's wants"): what this city wants now, from the market read the
  // quay already uses (world.market `wants`, the store's one copy). Read once when the city opens: wants re-draw
  // twice a game-day, not every second. Absent while city wants are dark, so nothing is drawn.
  const wants = useWorld((s) => s.markets[portId]?.wants)
  const loadMarket = useWorld((s) => s.loadMarket)
  useEffect(() => {
    void loadMarket(portId)
  }, [portId, loadMarket])
  if (read.loading && !v) return <Skeleton className="mt-4 h-40 w-full" />
  if (!v) return <Note tone="danger" className="mt-4">{t('stats.cityFailed')}</Note>
  const o = v.overview

  return (
    <div className={CITY_PAGE} data-testid="stats-city">
      {wants && wants.length > 0 && (
        <Note tone="neutral" data-testid="stats-city-wants">
          {t('ui.wanted', { mult: String(Number(wants[0].mult)) })}: {wants.map((w) => goodName(w)).join(' · ')}
        </Note>
      )}
      {o && (
        <div className={`flex flex-col ${PAGE_GAP}`} data-testid="stats-city-overview">
          <StatStrip>
            <StatCard label={t('town.i_purse')} value={o.purse} format={formatDucats} tone="accent" />
            <StatCard label={t('town.i_in')} value={o.income_1d} format={formatDucatsDelta} tone="success" />
            <StatCard label={t('town.i_out')} value={-o.spending_1d} format={formatDucatsDelta} tone="danger" />
            <StatCard label={t('town.i_taxes')} value={o.taxes_1d} format={formatDucats} />
          </StatStrip>
          <div className={PAIR}>
            <Card title={portName(v.city.name)}>
              <StatsChart
                title={portName(v.city.name)}
                points={toSeries(o.series, (p) => p.purse)}
                format={formatDucats}
                label={t('stats.citySeries', { city: portName(v.city.name) })}
                tone="accent"
                look="chart"
                height={CARD_CHART_H}
                empty={<Hint>{t('stats.lineSoon')}</Hint>}
              />
            </Card>
            <Card title={t('stats.netShort')}>
              <SignedBars
                bars={o.series.slice(-STATS_BARS).map((p) => ({ id: p.at, value: p.income - p.spending }))}
                label={t('stats.cityNet', { city: portName(v.city.name) })}
                height="h-28"
              />
              <span className="mt-3 block text-t-caption text-ink-muted">
                {t('stats.works', { list: o.works.map((w) => `${w.kind} ${w.level}`).join(' · ') || t('stats.noWorks') })}
              </span>
            </Card>
          </div>
          <div className={PAIR}>
            <Card title={t('stats.soldCityMost')}>
              <div>
                <RankBars
                  rules={false}
                  rows={o.top_sold.map((r) => ({ id: r.code, label: goodName(r), value: r.units, text: t('format.units', { n: formatInt(r.units), count: r.units }), note: formatDucats(r.ducats) }))}
                  format={formatInt}
                />
              </div>
            </Card>
            <Card title={t('stats.boughtCityMost')}>
              <div>
                <RankBars
                  rules={false}
                  rows={o.top_bought.map((r) => ({ id: r.code, label: goodName(r), value: r.units, text: t('format.units', { n: formatInt(r.units), count: r.units }), note: formatDucats(r.ducats) }))}
                  format={formatInt}
                />
              </div>
            </Card>
          </div>
          {o.flows_1d.length > 0 && (
            <Card title={t('stats.cityMoney')}>
              <div>
                <RankBars rows={flowRanks(o.flows_1d)} format={formatDucatsDelta} rules={false} />
              </div>
            </Card>
          )}
        </div>
      )}
      {v.detail && (
        <div data-testid="stats-city-detail">
          {v.detail.goods.length === 0 ? (
            <Card title={t('stats.goodsHere', { n: formatInt(0) })}>
              <Empty>{t('stats.nothingHere')}</Empty>
            </Card>
          ) : (
            <ListPanel look="card" columns="fit" title={t('stats.goodsHere', { n: formatInt(v.detail.goods.length) })}>
              {v.detail.goods.map((g) => {
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
                    hairline={false}
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
              })}
            </ListPanel>
          )}
        </div>
      )}
    </div>
  )
}

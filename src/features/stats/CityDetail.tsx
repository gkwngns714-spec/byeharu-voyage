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
import { worldStatsCity, type StatsCity } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { STATS_BARS, flowRanks, movePct, toSeries } from './statsFaces'

// ONE CITY, AT YOUR TIER — the row the Cities face opens (0214; its header carries the gate).
//
// Nothing here decides what you may see: `v.tier` is the server's answer, `overview` and `detail` are
// present only at the tier that bought them, and a tier-0 city arrives with figures for nothing — which
// is CORRECT, and is drawn as the lock rather than as a failure.
//
// THE PICTURE AT TIER 1: the purse as one line over the counts, income against spending as bars from a
// zero line, and what the city buys and sells most as ranked bars. At tier 2 every good follows, each
// with its own sparkline — the shape the Markets face uses, so a good does not look different here.

export function CityDetail({ portId, beat, onClose }: { portId: string; beat: number; onClose: () => void }) {
  const read = useServedRead<StatsCity>(`stats:city:${portId}`, () => worldStatsCity(portId), { trigger: beat })
  const v = read.view
  const nationByCode = useWorld((s) => s.nationByCode)
  if (read.loading && !v) return <Skeleton className="mt-4 h-40 w-full" />
  if (!v) return <Note tone="danger" className="mt-4">This city's figures could not be read.</Note>
  const flag = v.city.nation === null ? undefined : <Flag code={v.city.nation} name={nationNameOf(nationByCode, v.city.nation)} size="body" />
  const o = v.overview

  return (
    <SheetSection
      heading={
        <span className="flex items-center gap-2">
          {flag}
          {v.city.name}
        </span>
      }
      trailing={
        <button type="button" className="min-h-11 px-2 text-t-caption text-accent" onClick={onClose} data-testid="stats-city-close">
          Close
        </button>
      }
      data-testid="stats-city"
    >
      {v.tier === 0 && (
        <Note tone="neutral" data-testid="stats-city-lock">
          {`Locked. Invest ${formatDucats(v.need ?? v.tier1)} in ${v.city.name} to see its purse, income, taxes and trade.`}
        </Note>
      )}
      {o && (
        <div data-testid="stats-city-overview">
          <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
            <StatCell label="Purse" value={o.purse} format={formatDucats} size="body" tone="accent" />
            <StatCell label="In, 24 h" value={o.income_1d} format={formatDucatsDelta} size="body" tone="success" />
            <StatCell label="Out, 24 h" value={-o.spending_1d} format={formatDucatsDelta} size="body" tone="danger" />
            <StatCell label="Taxes, 24 h" value={o.taxes_1d} format={formatDucats} size="body" />
          </div>
          <SeriesChart
            points={toSeries(o.series, (p) => p.purse)}
            format={formatDucats}
            label={`${v.city.name}'s purse, count by count`}
            tone="accent"
            className="mt-4"
            empty={<Hint className="mt-3">The line starts with the next count.</Hint>}
          />
          <SignedBars
            bars={o.series.slice(-STATS_BARS).map((p) => ({ id: p.at, value: p.income - p.spending }))}
            label={`What ${v.city.name} took in less what it spent, one bar a count`}
            height="h-20"
            className="mt-4"
          />
          <Hint className="mt-2">One bar a count: up is money into the city, down is money out of it.</Hint>
          <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
            <div className="min-w-0">
              <span className="block text-t-caption text-ink-faint">Sold to the city most, 24 h</span>
              <RankBars
                rows={o.top_sold.map((r) => ({ id: r.code, label: r.name, value: r.units, text: `${formatInt(r.units)} units`, note: formatDucats(r.ducats) }))}
                format={formatInt}
              />
            </div>
            <div className="min-w-0">
              <span className="block text-t-caption text-ink-faint">Bought from the city most, 24 h</span>
              <RankBars
                rows={o.top_bought.map((r) => ({ id: r.code, label: r.name, value: r.units, text: `${formatInt(r.units)} units`, note: formatDucats(r.ducats) }))}
                format={formatInt}
              />
            </div>
          </div>
          {o.flows_1d.length > 0 && (
            <div className="mt-4">
              <span className="block text-t-caption text-ink-faint">The city's money, last 24 h</span>
              <RankBars rows={flowRanks(o.flows_1d)} format={formatDucatsDelta} />
            </div>
          )}
          <span className="mt-3 block text-t-caption text-ink-faint">
            {`Works: ${o.works.map((w) => `${w.kind} ${w.level}`).join(' · ') || 'none built'}`}
          </span>
          {v.tier === 1 && (
            <Hint className="mt-2">{`Invest ${formatDucats(v.need ?? 0)} more to see every good's price, stock and trade here.`}</Hint>
          )}
        </div>
      )}
      {v.detail && (
        <div className="mt-4" data-testid="stats-city-detail">
          <span className="block text-t-caption text-ink-faint">{`Every good here · ${formatInt(v.detail.goods.length)}`}</span>
          {v.detail.goods.length === 0 ? (
            <Empty className="mt-2">Nothing recorded here yet.</Empty>
          ) : (
            v.detail.goods.map((g, i, all) => {
              const move = movePct(g.mid, g.mid_1d)
              return (
                <Row
                  key={g.code}
                  label={
                    <span className="flex min-w-0 items-center gap-2">
                      <span className="min-w-0 truncate text-ink">{g.name}</span>
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
                        label={`${g.name} at ${v.city.name}, ${g.spark.length} readings`}
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
                    <span>{`sold ${formatInt(g.sold_1d)}`}</span>
                    <span>{`bought ${formatInt(g.bought_1d)}`}</span>
                    {g.stock !== null && g.stock_target !== null && g.stock_target > 0 && (
                      <StockGauge stock={g.stock} target={g.stock_target} label={`${g.name} at ${v.city.name}`} className="shrink-0" />
                    )}
                    {g.stock === null && <span>not sold here</span>}
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

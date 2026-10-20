import { useEffect, useState } from 'react'
import { Empty, FactsLine, Figure, Flag, Hint, Note, Row, SeriesChart, SheetSection, Skeleton, Sparkline, StockGauge, categoryLabel, deltaTone } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatPctChange, formatPriceFigure } from '../../lib/format'
import { worldStatsCities, worldStatsCity, type StatsCities, type StatsCity, type StatsCityRow } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import { nationNameOf, useWorld } from '../../live/worldStore'
import type { FaceProps } from './StatsScreen'
import { movePct, toSeries } from './statsFaces'

// CITIES — every harbour, at YOUR tier there. The owner, 2026-10-20: *"a statistic info of a city is added
// only when you invest certain amount."* The server (public.stats_city_tier) decides the tier from your
// stake in that city and sends figures only for the tier you hold; this face draws a LOCK where none came,
// and the stake that opens the next tier. It has nothing to hide, because it never received it.
//   tier 0  name, flag, "Invest N 🪙 more to see this city's figures"
//   tier 1  purse, income and spending, taxes, what it buys and sells most
//   tier 2  every good: price and its move, stock against normal, bought and sold

export function CitiesFace({ beat, onAge }: FaceProps) {
  const read = useServedRead<StatsCities>('stats:cities', () => worldStatsCities(), { trigger: beat })
  const v = read.view
  useEffect(() => onAge(v?.age_seconds ?? null), [v, onAge])
  const [open, setOpen] = useState<string | null>(null)
  const nationByCode = useWorld((s) => s.nationByCode)

  if (read.loading && !v) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">The cities' figures could not be read.</Note>

  const unlocked = v.cities.filter((c) => c.tier > 0)
  const locked = v.cities.filter((c) => c.tier === 0)
  const flag = (c: StatsCityRow) =>
    c.nation === null ? undefined : <Flag code={c.nation} name={nationNameOf(nationByCode, c.nation)} size="body" />

  return (
    <div data-testid="stats-cities">
      <Hint>
        {`A city's figures are intelligence you buy by investing there: ${formatDucats(v.tier1)} opens its overview, ${formatDucats(v.tier2)} every good's detail.`}
      </Hint>

      {open !== null && <CityDetail portId={open} beat={beat} onClose={() => setOpen(null)} />}

      {unlocked.length > 0 && (
        <SheetSection heading={`Your cities · ${formatInt(unlocked.length)}`} surface data-testid="stats-cities-open">
          {unlocked.map((c, i) => (
            <Row
              key={c.id}
              mark={flag(c)}
              label={c.name}
              value={<Figure value={formatDucats(c.purse ?? 0)} />}
              chevron
              tone={open === c.id ? 'accent' : 'default'}
              onClick={() => setOpen(c.id)}
              hairline={i < unlocked.length - 1}
              data-testid="stats-city-open"
            >
              <span className="block text-t-caption text-ink-faint">
                {`${c.tier === 2 ? 'full detail' : 'overview'} · in ${formatDucatsDelta(c.income_1d ?? 0)} · out ${formatDucatsDelta(-(c.spending_1d ?? 0))} · taxes ${formatDucats(c.taxes_1d ?? 0)} today`}
              </span>
            </Row>
          ))}
        </SheetSection>
      )}

      <SheetSection heading={`Locked · ${formatInt(locked.length)}`} surface data-testid="stats-cities-locked">
        {locked.length === 0 ? (
          <Row label="Every city is open to you." tone="muted" hairline={false} />
        ) : (
          locked.map((c, i) => (
            <Row
              key={c.id}
              mark={flag(c)}
              label={c.name}
              value={<span className="text-t-caption text-ink-faint">locked</span>}
              chevron
              tone={open === c.id ? 'accent' : 'default'}
              onClick={() => setOpen(c.id)}
              hairline={i < locked.length - 1}
              data-testid="stats-city-locked"
            >
              <span className="block text-t-caption text-ink-faint">{`Invest ${formatDucats(c.need ?? v.tier1)} to see this city's figures`}</span>
            </Row>
          ))
        )}
      </SheetSection>
    </div>
  )
}

function CityDetail({ portId, beat, onClose }: { portId: string; beat: number; onClose: () => void }) {
  const read = useServedRead<StatsCity>(`stats:city:${portId}`, () => worldStatsCity(portId), { trigger: beat })
  const v = read.view
  const nationByCode = useWorld((s) => s.nationByCode)
  if (read.loading && !v) return <Skeleton className="mt-4 h-40 w-full" />
  if (!v) return <Note tone="danger" className="mt-4">This city's figures could not be read.</Note>
  const flag = v.city.nation === null ? undefined : <Flag code={v.city.nation} name={nationNameOf(nationByCode, v.city.nation)} size="body" />

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
      {v.overview && (
        <div data-testid="stats-city-overview">
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
            <Head label="Purse" value={formatDucats(v.overview.purse)} />
            <Head label="In, 24 h" value={formatDucatsDelta(v.overview.income_1d)} tone="success" />
            <Head label="Out, 24 h" value={formatDucatsDelta(-v.overview.spending_1d)} tone="danger" />
            <Head label="Taxes, 24 h" value={formatDucats(v.overview.taxes_1d)} />
          </div>
          <SeriesChart
            points={toSeries(v.overview.series, (p) => p.purse)}
            format={formatDucats}
            label={`${v.city.name}'s purse, the last days`}
            tone="success"
            className="mt-3"
          />
          <div className="mt-3 grid grid-cols-1 gap-4 lg:grid-cols-2">
            <TopGoods heading="Sold to the city most, 24 h" rows={v.overview.top_sold} />
            <TopGoods heading="Bought from the city most, 24 h" rows={v.overview.top_bought} />
          </div>
          {v.overview.flows_1d.length > 0 && (
            <div className="mt-3">
              <span className="block text-t-caption text-ink-faint">The city's money, last 24 h</span>
              {v.overview.flows_1d.map((f, i) => (
                <Row key={f.kind} label={f.word} value={<Figure value={formatDucatsDelta(f.ducats)} tone={deltaTone(f.ducats)} />} hairline={i < v.overview!.flows_1d.length - 1} />
              ))}
            </div>
          )}
          <span className="mt-3 block text-t-caption text-ink-faint">
            {`Works: ${v.overview.works.map((w) => `${w.kind} ${w.level}`).join(' · ') || 'none built'}`}
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
            v.detail.goods.map((g, i) => {
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
                      <Sparkline values={g.spark} tone={move === null || move === 0 ? 'even' : move > 0 ? 'dear' : 'cheap'} width={48} height={18} />
                      <span className="flex w-24 flex-col items-end">
                        <Figure value={g.mid === null ? '—' : formatPriceFigure(g.mid)} />
                        <Figure value={move === null ? '—' : formatPctChange(move)} tone={move === null ? 'faint' : deltaTone(move)} />
                      </span>
                    </span>
                  }
                  hairline={i < v.detail!.goods.length - 1}
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

function Head({ label, value, tone = 'ink' }: { label: string; value: string; tone?: 'ink' | 'success' | 'danger' }) {
  return (
    <div className="min-w-0">
      <span className="block text-t-caption text-ink-faint">{label}</span>
      <Figure value={value} size="figure" tone={tone} />
    </div>
  )
}

function TopGoods({ heading, rows }: { heading: string; rows: { code: string; name: string; units: number; ducats: number }[] }) {
  return (
    <div className="min-w-0">
      <span className="block text-t-caption text-ink-faint">{heading}</span>
      {rows.length === 0 ? (
        <Row label="Nothing yet" tone="muted" hairline={false} />
      ) : (
        rows.map((r, i) => (
          <Row key={r.code} label={r.name} value={<Figure value={formatInt(r.units)} unit="units" />} hairline={i < rows.length - 1}>
            <span className="block text-t-caption text-ink-faint">{formatDucats(r.ducats)}</span>
          </Row>
        ))
      )}
    </div>
  )
}

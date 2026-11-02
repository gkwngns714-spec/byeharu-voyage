import { useState } from 'react'
import {
  Button,
  Card,
  CardRow,
  Clip,
  Counter,
  Empty,
  FactsLine,
  FilterBar,
  Figure,
  Flag,
  Hint,
  ListPanel,
  Note,
  PageSplit,
  RankBars,
  Row,
  Segmented,
  Skeleton,
  StackedBar,
  StatCell,
  deltaTone,
  oneOf,
  useFilterChoice,
  type RankRow,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatPct } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldStatsMerchants, type StatsMerchantHouse, type StatsMerchants } from '../../lib/rpc'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { CARD_CHART_H, toSeries } from './statsFaces'
import { useLiveRead } from './statsLive'
import { StatsChart } from './StatsChart'
import { useChartSpan } from '../../store/chartSpan'
import { ALL, MERCHANT_SORTS, countriesOf, sortMerchants } from './statsFilters'

// MERCHANTS — the companies the world keeps, ALL ON THE FACE (owner, 2026-11-01, row 260), in cards (2026-11-02, row 267:
// *"it looks so wrong … too packed"*). MAIN | SIDE (screenLayout.ts "THE PAGE"): the SIDE — the tray's column — holds the
// companies' day (what they earned, with its chart, the loss share, the laps closed) and where the fleets are (the stacked bar
// and its five states); MAIN holds two charts side by side (their money, the fleets at sea) over ONE list card with three views
// of the same companies: every company (with its country and its sort), the five best days and the five worst. None is behind a
// page; a press on the strip changes what the card lists. On a phone the side comes first.

const FIRST = 60
type View = 'companies' | 'best' | 'worst'

export function MerchantsFace() {
  const t = useT()
  const { span } = useChartSpan()
  const read = useLiveRead<StatsMerchants>('stats:merchants', () => worldStatsMerchants(span), span)
  const v = read.view
  const nationByCode = useWorld((s) => s.nationByCode)
  const [choice, choose] = useFilterChoice('stats.merchants', { country: ALL, sort: 'richest' })
  const [all, setAll] = useState(false)
  const [view, setView] = useState<View>('companies')

  if (read.loading && !v) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">{t('stats.merchantsFailed')}</Note>
  if (v.houses === undefined) return <Empty data-testid="stats-empty">{t('stats.noFigures')}</Empty>

  const states = [
    { id: 'sailing', label: t('stats.sailing'), value: v.sailing ?? 0, tone: 'info' as const },
    { id: 'docked', label: t('stats.inPort'), value: v.docked ?? 0, tone: 'success' as const },
    { id: 'repairing', label: t('stats.repairing'), value: v.repairing ?? 0, tone: 'warning' as const },
    { id: 'unable', label: t('stats.cannotSail'), value: v.unable ?? 0, tone: 'danger' as const },
    { id: 'laid_up', label: t('stats.laidUp'), value: v.laid_up ?? 0, tone: 'neutral' as const },
  ]
  const houses = (list: readonly StatsMerchantHouse[]): RankRow[] =>
    list.map((h) => ({
      id: h.name,
      label: (
        <span className="flex min-w-0 items-center gap-2">
          {h.nation !== null && <Flag code={h.nation} name={nationNameOf(nationByCode, h.nation)} size="body" />}
          <Clip>{h.name}</Clip>
        </span>
      ),
      value: h.day,
      tone: h.day >= 0 ? ('success' as const) : ('danger' as const),
      note: t('stats.laps', { n: formatInt(h.laps), count: h.laps }),
    }))

  const list = v.list ?? []
  const countries = countriesOf(list.map((h) => h[1]))
    .map((code) => ({ id: code, label: nationNameOf(nationByCode, code) }))
    .sort((a, b) => a.label.localeCompare(b.label))
  const country = oneOf(choice.country, [ALL, ...countries.map((c) => c.id)], ALL)
  const sort = oneOf(choice.sort, MERCHANT_SORTS, 'richest')
  const rows = sortMerchants(country === ALL ? list : list.filter((h) => h[1] === country), sort)
  const shown = all ? rows : rows.slice(0, FIRST)

  return (
    <PageSplit
      data-testid="stats-merchants"
      sideFirst
      main={
        <>
          <CardRow>
            <Card title={t('stats.theirPurses')} data-testid="stats-chart-purses">
              {/* THE TITLE IS THE LABEL: a card called "Their money" does not say it again over its figure */}
              <Counter value={v.purse ?? 0} format={formatDucats} size="figure" />
              <StatsChart
                look="chart"
                title={t('stats.theirPurses')}
                points={toSeries(v.series, (p) => p.purse)}
                format={formatDucats}
                label={t('stats.theirPurses')}
                tone="accent"
                height={CARD_CHART_H}
                className="mt-3"
                empty={<Hint className="mt-3">{t('stats.lineSoon')}</Hint>}
              />
            </Card>
            <Card title={t('stats.fleetsAtSea')} data-testid="stats-chart-sea">
              <Counter value={v.sailing ?? 0} format={formatInt} size="figure" />
              <StatsChart
                look="chart"
                title={t('stats.fleetsAtSea')}
                points={toSeries(v.series, (p) => p.sailing)}
                format={formatInt}
                label={t('stats.atSeaLabel')}
                tone="info"
                height={CARD_CHART_H}
                className="mt-3"
                empty={<Hint className="mt-3">{t('stats.lineSoon')}</Hint>}
              />
            </Card>
          </CardRow>

          <ListPanel
            look="card"
            columns="fit"
            controls={
              <>
                <Segmented
                  segments={[
                    { id: 'companies', label: t('stats.companies') },
                    { id: 'best', label: t('stats.bestDay') },
                    { id: 'worst', label: t('stats.worstDay') },
                  ]}
                  value={view}
                  onChange={setView}
                  label={t('stats.everyCompany')}
                  columns={3}
                  className="shrink-0"
                />
                {view === 'companies' && (
                  <>
                    <FilterBar
                      compact
                      data-testid="stats-merchants-filters"
                      picks={[
                        {
                          id: 'country',
                          label: t('stats.country'),
                          options: [{ id: ALL, label: t('stats.allCountries') }, ...countries],
                          value: country,
                          onChange: (id) => choose({ country: id }),
                        },
                      ]}
                    />
                    <FilterBar
                      compact
                      data-testid="stats-merchants-sort"
                      sort={{
                        id: 'sort',
                        label: t('stats.sortLabel'),
                        options: MERCHANT_SORTS.map((id) => ({
                          id,
                          label: t(id === 'richest' ? 'stats.richest' : id === 'earned' ? 'stats.bestEarned' : id === 'laps' ? 'stats.mostLaps' : id === 'fleet' ? 'stats.biggestFleet' : 'stats.name'),
                        })),
                        value: sort,
                        onChange: (id) => choose({ sort: id }),
                      }}
                    />
                  </>
                )}
              </>
            }
            footer={
              view === 'companies' && !all && rows.length > FIRST ? (
                <Button variant="secondary" onClick={() => setAll(true)} data-testid="stats-merchants-show-all">
                  {t('stats.showAll')}
                </Button>
              ) : undefined
            }
            data-testid={view === 'companies' ? 'stats-merchants-all' : view === 'best' ? 'stats-merchants-top' : 'stats-merchants-bottom'}
          >
            {view === 'best' && <RankBars rows={houses(v.top ?? [])} format={formatDucatsDelta} empty={t('stats.noLaps')} className="contents" />}
            {view === 'worst' && <RankBars rows={houses(v.bottom ?? [])} format={formatDucatsDelta} empty={t('stats.noLaps')} className="contents" />}
            {view === 'companies' && (
              <>
                {rows.length === 0 && (
                  <Empty className="my-1 md:col-span-full" data-testid="stats-no-match">
                    {t('stats.noMatch')}
                  </Empty>
                )}
                {shown.map(([name, nation, purse, fleets, day, laps]) => (
                  <Row
                    key={name}
                    mark={nation === null ? undefined : <Flag code={nation} name={nationNameOf(nationByCode, nation)} size="body" />}
                    label={<Clip>{name}</Clip>}
                    value={<Figure value={formatDucats(purse)} />}
                    hairline={false}
                    data-testid="stats-merchant"
                  >
                    <FactsLine>
                      <span>{t('stats.fleetsN', { n: formatInt(fleets), count: fleets })}</span>
                      <span>{t('stats.earnedFigure', { amount: formatDucatsDelta(day) })}</span>
                      <span>{t('stats.laps', { n: formatInt(laps), count: laps })}</span>
                    </FactsLine>
                  </Row>
                ))}
              </>
            )}
          </ListPanel>
        </>
      }
      side={
        <>
          <Card title={t('stats.companiesFleets', { houses: formatInt(v.houses), fleets: formatInt(v.fleets ?? 0) })} data-testid="stats-merchant-figures">
            <StatCell look="stacked" label={t('stats.earned24')} value={v.profit_day ?? 0} format={formatDucatsDelta} tone={deltaTone(v.profit_day ?? 0)} />
            <StatsChart
              look="chart"
              title={t('stats.earnedDay')}
              points={toSeries(v.series, (p) => p.profit_day)}
              format={formatDucats}
              label={t('stats.earnedLabel')}
              tone="info"
              height={CARD_CHART_H}
              className="mt-3"
              empty={<Hint className="mt-3">{t('stats.lineSoon')}</Hint>}
            />
            <div className="mt-3">
              <StatCell look="line" label={t('stats.lapsLost')} value={(v.losing_pct ?? 0) / 100} format={(x) => formatPct(x, 1)} tone={(v.losing_pct ?? 0) > 50 ? 'danger' : 'ink'} />
              <StatCell look="line" label={t('stats.lapsClosed')} value={v.laps_day ?? 0} format={formatInt} />
            </div>
          </Card>

          <Card title={t('stats.whereFleets')} data-testid="stats-merchant-fold">
            <Figure value={formatInt(v.fleets ?? 0)} size="figure" />
            <StackedBar parts={states} format={formatInt} label={t('stats.whereFleets')} className="mt-4" data-testid="stats-merchant-states" />
          </Card>
        </>
      }
    />
  )
}

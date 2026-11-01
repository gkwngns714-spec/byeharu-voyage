import { useState } from 'react'
import {
  Button,
  Clip,
  Empty,
  FactsLine,
  FilterBar,
  Figure,
  Flag,
  ListPanel,
  Note,
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
import { toSeries } from './statsFaces'
import { useLiveRead } from './statsLive'
import { Block } from './StatsBlock'
import { StatsChart } from './StatsChart'
import { useChartSpan } from '../../store/chartSpan'
import { ALL, MERCHANT_SORTS, countriesOf, sortMerchants } from './statsFilters'

// MERCHANTS — the companies the world keeps, ALL ON THE FACE (owner, 2026-11-01, row 260). It was four day
// figures and four summary rows (the fleets' chart, the best day, the worst day, every company), each
// opening a page. It is now the figures and where the fleets are, with their two small charts, over ONE
// list panel with three views of the same companies: every company (with its country and its sort), the
// five best days and the five worst. None is behind a page; a press on the strip changes what the panel lists.

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

  const above = (
    <>
      <Block title={t('stats.companiesFleets', { houses: formatInt(v.houses), fleets: formatInt(v.fleets ?? 0) })} data-testid="stats-merchant-figures">
        <div className="grid grid-cols-[repeat(auto-fit,minmax(9.5rem,1fr))] gap-x-4 gap-y-1">
          <StatCell
            label={t('stats.earned24')}
            value={v.profit_day ?? 0}
            format={formatDucatsDelta}
            size="body"
            tone={deltaTone(v.profit_day ?? 0)}
            trend={v.series.map((p) => p.profit_day)}
            trendBeside
          />
          <StatCell label={t('stats.lapsLost')} value={(v.losing_pct ?? 0) / 100} format={(x) => formatPct(x, 1)} size="body" tone={(v.losing_pct ?? 0) > 50 ? 'danger' : 'ink'} />
          <StatCell label={t('stats.lapsClosed')} value={v.laps_day ?? 0} format={formatInt} size="body" />
          <StatCell label={t('stats.theirPurses')} value={v.purse ?? 0} format={formatDucats} size="body" trend={v.series.map((p) => p.purse)} trendBeside />
        </div>
      </Block>

      <Block title={t('stats.whereFleets')} figure={formatInt(v.fleets ?? 0)} data-testid="stats-merchant-fold">
        <StackedBar parts={states} format={formatInt} label={t('stats.whereFleets')} data-testid="stats-merchant-states" />
        <div className="mt-1 grid grid-cols-2 gap-x-3">
          <StatsChart title={t('stats.earnedDay')} points={toSeries(v.series, (p) => p.profit_day)} format={formatDucats} label={t('stats.earnedLabel')} tone="info" />
          <StatsChart title={t('stats.fleetsAtSea')} points={toSeries(v.series, (p) => p.sailing)} format={formatInt} label={t('stats.atSeaLabel')} tone="accent" />
        </div>
      </Block>
    </>
  )

  return (
    <ListPanel
      above={above}
      face={{ 'data-testid': 'stats-merchants' }}
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
      data-testid={view === 'companies' ? 'stats-merchants-all' : view === 'best' ? 'stats-merchants-top' : 'stats-merchants-bottom'}
    >
      {view === 'best' && <RankBars rows={houses(v.top ?? [])} format={formatDucatsDelta} empty={t('stats.noLaps')} />}
      {view === 'worst' && <RankBars rows={houses(v.bottom ?? [])} format={formatDucatsDelta} empty={t('stats.noLaps')} />}
      {view === 'companies' && (
        <>
          {rows.length === 0 && (
            <Empty className="my-1" data-testid="stats-no-match">
              {t('stats.noMatch')}
            </Empty>
          )}
          {shown.map(([name, nation, purse, fleets, day, laps], i) => (
            <Row
              key={name}
              mark={nation === null ? undefined : <Flag code={nation} name={nationNameOf(nationByCode, nation)} size="body" />}
              label={<Clip>{name}</Clip>}
              value={<Figure value={formatDucats(purse)} />}
              hairline={i < shown.length - 1 || (!all && rows.length > FIRST)}
              data-testid="stats-merchant"
            >
              <FactsLine>
                <span>{t('stats.fleetsN', { n: formatInt(fleets), count: fleets })}</span>
                <span>{t('stats.earnedFigure', { amount: formatDucatsDelta(day) })}</span>
                <span>{t('stats.laps', { n: formatInt(laps), count: laps })}</span>
              </FactsLine>
            </Row>
          ))}
          {!all && rows.length > FIRST && (
            <div className="py-2">
              <Button variant="secondary" onClick={() => setAll(true)} data-testid="stats-merchants-show-all">
                {t('stats.showAll')}
              </Button>
            </div>
          )}
        </>
      )}
    </ListPanel>
  )
}

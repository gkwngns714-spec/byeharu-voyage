import { useState } from 'react'
import {
  Button,
  DetailPage,
  Empty,
  FactsLine,
  FilterBar,
  Figure,
  Flag,
  Hint,
  Note,
  RankBars,
  Row,
  SheetSection,
  Skeleton,
  StackedBar,
  StatCell,
  SummaryRow,
  deltaTone,
  type RankRow,
  Clip,
  oneOf,
  useFilterChoice,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatPct } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldStatsMerchants, type StatsMerchantHouse, type StatsMerchants } from '../../lib/rpc'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { toSeries } from './statsFaces'
import { useLiveRead } from './statsLive'
import { StatsChart } from './StatsChart'
import { useChartSpan } from '../../store/chartSpan'
import { ALL, MERCHANT_SORTS, countriesOf, sortMerchants } from './statsFilters'

// MERCHANTS — the companies the world keeps. THE COMPACT SCREEN (owner, 2026-10-31): the four day
// figures stand; the fleet chart, the two day boards and the company list are summary rows with
// their key figures, each opening its own full-screen page.

const FIRST = 60
type Page = 'charts' | 'top' | 'bottom' | 'all' | null

export function MerchantsFace() {
  const t = useT()
  const { span } = useChartSpan()
  const read = useLiveRead<StatsMerchants>('stats:merchants', () => worldStatsMerchants(span), span)
  const v = read.view
  const nationByCode = useWorld((s) => s.nationByCode)
  const [choice, choose] = useFilterChoice('stats.merchants', { country: ALL, sort: 'richest' })
  const [all, setAll] = useState(false)
  const [page, setPage] = useState<Page>(null)

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

  const allTitle = t('stats.everyCompany')
  const topTitle = t('stats.bestDay')
  const bottomTitle = t('stats.worstDay')

  return (
    <div data-testid="stats-merchants">
      <SheetSection heading={t('stats.companiesFleets', { houses: formatInt(v.houses), fleets: formatInt(v.fleets ?? 0) })}>
        <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
          <StatCell label={t('stats.earned24')} value={v.profit_day ?? 0} format={formatDucatsDelta} size="body" tone={deltaTone(v.profit_day ?? 0)} trend={v.series.map((p) => p.profit_day)} />
          <StatCell label={t('stats.lapsLost')} value={(v.losing_pct ?? 0) / 100} format={(x) => formatPct(x, 1)} size="body" tone={(v.losing_pct ?? 0) > 50 ? 'danger' : 'ink'} />
          <StatCell label={t('stats.lapsClosed')} value={v.laps_day ?? 0} format={formatInt} size="body" />
          <StatCell label={t('stats.theirPurses')} value={v.purse ?? 0} format={formatDucats} size="body" trend={v.series.map((p) => p.purse)} />
        </div>
      </SheetSection>

      <div className="mt-2 flex flex-col gap-2">
        <SummaryRow title={t('stats.whereFleets')} figure={formatInt(v.fleets ?? 0)} word={t('common.open')} onClick={() => setPage('charts')} data-testid="stats-merchant-fold" />
        <SummaryRow title={topTitle} figure={formatDucatsDelta(v.top?.[0]?.day ?? 0)} word={t('common.open')} onClick={() => setPage('top')} data-testid="stats-merchants-top" />
        <SummaryRow title={bottomTitle} figure={formatDucatsDelta(v.bottom?.[0]?.day ?? 0)} word={t('common.open')} onClick={() => setPage('bottom')} data-testid="stats-merchants-bottom" />
        {list.length > 0 && (
          <SummaryRow title={allTitle} figure={formatInt(rows.length)} word={t('common.open')} onClick={() => setPage('all')} data-testid="stats-merchants-all" />
        )}
      </div>

      {page === 'charts' && (
        <DetailPage title={t('stats.whereFleets')} figure={formatInt(v.fleets ?? 0)} onClose={() => setPage(null)} data-testid="stats-merchant-fold-page">
          <StackedBar parts={states} format={formatInt} label={t('stats.whereFleets')} data-testid="stats-merchant-states" />
          <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
            <div className="min-w-0">
              <span className="block text-t-caption text-ink-faint">{t('stats.earnedDay')}</span>
              <StatsChart title={t('stats.earnedDay')} points={toSeries(v.series, (p) => p.profit_day)} format={formatDucats} label={t('stats.earnedLabel')} tone="info" empty={<Hint className="mt-2">{t('stats.lineSoon')}</Hint>} />
            </div>
            <div className="min-w-0">
              <span className="block text-t-caption text-ink-faint">{t('stats.fleetsAtSea')}</span>
              <StatsChart title={t('stats.fleetsAtSea')} points={toSeries(v.series, (p) => p.sailing)} format={formatInt} label={t('stats.atSeaLabel')} tone="accent" empty={<Hint className="mt-2">{t('stats.lineSoon')}</Hint>} />
            </div>
          </div>
        </DetailPage>
      )}

      {page === 'top' && (
        <DetailPage title={topTitle} figure={formatDucatsDelta(v.top?.[0]?.day ?? 0)} onClose={() => setPage(null)} data-testid="stats-merchants-top-page">
          <RankBars rows={houses(v.top ?? [])} format={formatDucatsDelta} empty={t('stats.noLaps')} />
        </DetailPage>
      )}

      {page === 'bottom' && (
        <DetailPage title={bottomTitle} figure={formatDucatsDelta(v.bottom?.[0]?.day ?? 0)} onClose={() => setPage(null)} data-testid="stats-merchants-bottom-page">
          <RankBars rows={houses(v.bottom ?? [])} format={formatDucatsDelta} empty={t('stats.noLaps')} />
        </DetailPage>
      )}

      {page === 'all' && (
        <DetailPage title={allTitle} figure={formatInt(rows.length)} onClose={() => setPage(null)} data-testid="stats-merchants-all-page">
          <FilterBar
            className="mb-2"
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
          {rows.length === 0 && <Empty data-testid="stats-no-match">{t('stats.noMatch')}</Empty>}
          {shown.map(([name, nation, purse, fleets, day, laps], i) => (
            <Row
              key={name}
              mark={nation === null ? undefined : <Flag code={nation} name={nationNameOf(nationByCode, nation)} size="body" />}
              label={<Clip>{name}</Clip>}
              value={<Figure value={formatDucats(purse)} />}
              hairline={i < shown.length - 1}
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
            <div className="pt-3">
              <Button variant="secondary" onClick={() => setAll(true)} data-testid="stats-merchants-show-all">
                {t('stats.showAll')}
              </Button>
            </div>
          )}
        </DetailPage>
      )}
    </div>
  )
}

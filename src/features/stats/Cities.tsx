import { useMemo, useState } from 'react'
import { DetailPage, Empty, FactsLine, FilterBar, Figure, Flag, ListPanel, Note, Row, Skeleton, oneOf, useFilterChoice } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldStatsCities, type StatsCities, type StatsCityRow } from '../../lib/rpc'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { CityDetail } from './CityDetail'
import { portName } from './statsFaces'
import { useLiveRead } from './statsLive'
import { ALL, CITY_SORTS, STATS_AREAS, areaWord, countriesOf, filterCities, sortCities, type CitySort } from './statsFilters'

// CITIES — every harbour, open to everyone (0223, owner row 197), ALL ON THE FACE (owner, 2026-11-01, row 260). It
// was two summary rows — the filters on one page, the 246 cities on another. It is now ONE list panel: the
// cities, with the filters (area · country · sort · mine) in the panel's own header. A press on a city opens
// THAT city's page (its purse over time, what it buys and sells, every good it holds); Back returns to the list.

export function CitiesFace() {
  const t = useT()
  const read = useLiveRead<StatsCities>('stats:cities', () => worldStatsCities())
  const v = read.view
  const [open, setOpen] = useState<StatsCityRow | null>(null)
  const nationByCode = useWorld((s) => s.nationByCode)
  const [choice, choose] = useFilterChoice('stats.cities', { area: ALL, country: ALL, mine: '0', sort: 'richest' })
  const sortOptions = useMemo(
    () =>
      CITY_SORTS.map((id) => ({
        id,
        label: t(id === 'richest' ? 'stats.richest' : id === 'traded' ? 'stats.mostTraded' : id === 'invested' ? 'stats.mostInvested' : id === 'stock' ? 'stats.biggestStock' : 'stats.name'),
      })),
    [t],
  )

  if (read.loading && !v) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">{t('stats.citiesFailed')}</Note>

  const flag = (c: StatsCityRow) =>
    c.nation === null ? undefined : <Flag code={c.nation} name={nationNameOf(nationByCode, c.nation)} size="body" />
  const sort = oneOf(choice.sort, CITY_SORTS, 'richest')
  const area = oneOf(choice.area, [ALL, ...STATS_AREAS], ALL)
  const countries = countriesOf(v.cities.map((c) => c.nation))
    .map((code) => ({ id: code, label: nationNameOf(nationByCode, code) }))
    .sort((a, b) => a.label.localeCompare(b.label))
  const country = oneOf(choice.country, [ALL, ...countries.map((c) => c.id)], ALL)
  const rows = sortCities(filterCities(v.cities, { area, country, mine: choice.mine === '1' }), sort, (c) => portName(c.name))

  return (
    <>
      <ListPanel
        title={t('stats.citiesCount')}
        count={formatInt(rows.length)}
        trailing={
          <FilterBar
            compact
            data-testid="stats-cities-sort"
            sort={{ id: 'sort', label: t('stats.sortLabel'), options: sortOptions, value: sort, onChange: (id) => choose({ sort: id as CitySort }) }}
          />
        }
        controls={
          <FilterBar
            compact
            data-testid="stats-cities-filters"
            picks={[
              {
                id: 'area',
                label: t('stats.area'),
                options: [{ id: ALL, label: t('stats.area') }, ...STATS_AREAS.map((a) => ({ id: a, label: t(areaWord(a)) }))],
                value: area,
                onChange: (id) => choose({ area: id }),
              },
              {
                id: 'country',
                label: t('stats.country'),
                options: [{ id: ALL, label: t('stats.allCountries') }, ...countries],
                value: country,
                onChange: (id) => choose({ country: id }),
              },
            ]}
            toggles={[{ id: 'mine', label: t('stats.myCities'), on: choice.mine === '1', onChange: (on) => choose({ mine: on ? '1' : '0' }) }]}
          />
        }
        data-testid="stats-cities"
      >
        {rows.length === 0 && (
          <Empty className="my-1" data-testid="stats-no-match">
            {t('stats.noMatch')}
          </Empty>
        )}
        {rows.map((c, i) => (
          <Row
            key={c.id}
            mark={flag(c)}
            label={
              <span data-testid="stats-city-name" data-area={c.area ?? ''} data-purse={c.purse ?? 0}>
                {portName(c.name)}
              </span>
            }
            value={<Figure value={formatDucats(c.purse ?? 0)} />}
            chevron
            onClick={() => setOpen(c)}
            hairline={i < rows.length - 1}
            data-testid="stats-city-open"
          >
            <FactsLine>
              <span>{t('stats.inFigure', { amount: formatDucatsDelta(c.income_1d ?? 0) })}</span>
              <span>{t('stats.outFigure', { amount: formatDucatsDelta(-(c.spending_1d ?? 0)) })}</span>
              <span>{t('stats.taxesFigure', { amount: formatDucats(c.taxes_1d ?? 0) })}</span>
              {sort === 'traded' && <span>{t('stats.tradedFigure', { n: formatInt((c.sold_1d ?? 0) + (c.bought_1d ?? 0)) })}</span>}
              {sort === 'invested' && <span>{t('stats.investedFigure', { amount: formatDucats(c.invested ?? 0) })}</span>}
              {sort === 'stock' && c.stock != null && <span>{t('stats.stockFigure', { n: formatInt(c.stock) })}</span>}
            </FactsLine>
          </Row>
        ))}
      </ListPanel>

      {open !== null && (
        <DetailPage
          title={
            <span className="flex items-center gap-2">
              {flag(open)}
              {portName(open.name)}
            </span>
          }
          figure={<Figure value={formatDucats(open.purse ?? 0)} />}
          onClose={() => setOpen(null)}
          data-testid="stats-city-page"
        >
          <CityDetail portId={open.id} />
        </DetailPage>
      )}
    </>
  )
}

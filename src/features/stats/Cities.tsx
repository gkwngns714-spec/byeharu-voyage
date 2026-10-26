import { useMemo, useState } from 'react'
import { Empty, FactsLine, FilterBar, Figure, Flag, Note, Row, SheetSection, Skeleton, oneOf, useFilterChoice } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldStatsCities, type StatsCities, type StatsCityRow } from '../../lib/rpc'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { CityDetail } from './CityDetail'
import { portName } from './statsFaces'
import { useLiveRead } from './statsLive'
import { ALL, CITY_SORTS, STATS_AREAS, areaWord, countriesOf, filterCities, sortCities, type CitySort } from './statsFilters'

// CITIES — every harbour, open to everyone. The owner, 2026-10-25 (docs/OWNER_REQUESTS.md row 197): *"on cities,
// i want to see all the info without investment"*. Until 0223 a city's figures were bought (0214's tier gate drew
// a lock here, the overview at one stake and every good at a higher one); 0223 removed the gate and its knobs, so
// every row carries the purse and the day's figures, and a press opens the whole city (CityDetail). Nothing here
// decides what you may see: the server serves it all. Investing in a city is still a game action, not a key.
//
// EVERY SECOND (0232, owner row 213): each purse is the live balance and each day-figure the last 24 h up to this
// second; the list and an open city are each asked again every second while on screen.
//
// FILTERS AND SORTS (0241, owner row 228: *"filter … in cities such as by area (continents), or by richest"*): by
// area (the server's public.region_area), by country, "My cities" (where I hold shares); sorted by richest (the
// purse), most traded in 24 h, most invested, biggest stock (as of the last count), or name. Remembered per face.

export function CitiesFace() {
  const t = useT()
  const read = useLiveRead<StatsCities>('stats:cities', () => worldStatsCities())
  const v = read.view
  const [open, setOpen] = useState<string | null>(null)
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
    <div data-testid="stats-cities">
      {open !== null && <CityDetail portId={open} onClose={() => setOpen(null)} />}

      <FilterBar
        className="mb-3"
        data-testid="stats-cities-filters"
        chips={{
          label: t('stats.area'),
          options: [{ id: ALL, label: t('stats.all') }, ...STATS_AREAS.map((a) => ({ id: a, label: t(areaWord(a)) }))],
          value: area,
          onChange: (id) => choose({ area: id }),
        }}
        toggles={[{ id: 'mine', label: t('stats.myCities'), on: choice.mine === '1', onChange: (on) => choose({ mine: on ? '1' : '0' }) }]}
        picks={[
          {
            id: 'country',
            label: t('stats.country'),
            options: [{ id: ALL, label: t('stats.allCountries') }, ...countries],
            value: country,
            onChange: (id) => choose({ country: id }),
          },
        ]}
        sort={{ id: 'sort', label: t('stats.sortLabel'), options: sortOptions, value: sort, onChange: (id) => choose({ sort: id as CitySort }) }}
      />

      <SheetSection heading={t('stats.citiesCount', { n: formatInt(rows.length) })} surface data-testid="stats-cities-open">
        {rows.length === 0 && <Empty data-testid="stats-no-match">{t('stats.noMatch')}</Empty>}
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
            tone={open === c.id ? 'accent' : 'default'}
            onClick={() => setOpen(c.id)}
            hairline={i < rows.length - 1}
            data-testid="stats-city-open"
          >
            <FactsLine>
              <span>{t('stats.inFigure', { amount: formatDucatsDelta(c.income_1d ?? 0) })}</span>
              <span>{t('stats.outFigure', { amount: formatDucatsDelta(-(c.spending_1d ?? 0)) })}</span>
              <span>{t('stats.taxesFigure', { amount: formatDucats(c.taxes_1d ?? 0) })}</span>
              {sort === 'traded' && <span>{t('stats.tradedFigure', { n: formatInt((c.sold_1d ?? 0) + (c.bought_1d ?? 0)) })}</span>}
              {sort === 'invested' && <span>{t('stats.investedFigure', { amount: formatDucats(c.invested ?? 0) })}</span>}
              {sort === 'stock' && <span>{t('stats.stockFigure', { n: c.stock == null ? '—' : formatInt(c.stock) })}</span>}
            </FactsLine>
          </Row>
        ))}
      </SheetSection>
    </div>
  )
}

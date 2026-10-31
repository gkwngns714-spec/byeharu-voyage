import {
  FactsLine,
  Note,
  Row,
  Skeleton,
  StatCell,
  stockLevel,
  type StockLevel,
} from '../components/ui'
import { buyableHere } from '../domain/market'
import { CityFlag } from './CityFlag'
import { usePortMarket } from './usePortMarket'
import { useServedRead } from './useServedRead'
import { useTownHall } from './useTownHall'
import { nationNameOf, portNationOf, useWorld } from './worldStore'
import { worldStatsCity } from '../lib/rpc'
import type { MarketGood, SnapshotPort, StatsCity } from '../lib/rpc'
import { formatDucats, formatDucatsDelta, formatInt, formatPct } from '../lib/format'
import { properName, useT, type TKey } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY PANEL'S INFO TAB — a city in a handful of lines (owner row 174, 2026-10-20)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, verbatim: *"When pressing a city, I want Info page(tab) added. This will show you what
// country it is, what it is influenced by, population, economy situation, market situation and so
// on – not too much word, but very concise."*
//
// CONCISE IS THE BRIEF, so this face is three rows and one block, and every one of them is a figure
// the server ALREADY serves. Nothing here is a second authority:
//
//   Country    `CityFlag` — `world.allegiance` (0143), the same words the panel's own title line
//              carries: the country that holds it, Home city or Contested, and the local ruler a
//              minor nation founded it under (0187). Under it, the INFLUENCE on it:
//              `world.town_hall(port).influence.shares` (0144), the top TWO countries and their
//              served shares. The bars, your own standing and Donate stay on the Town Hall tab,
//              which is where the act is; this is the glance.
//   Where      the snapshot's `sea`, `culture` and `size_tier`.
//   Market     `world.market(port)` — how many goods this city trades (`buyableHere`, the one
//              reading of that), and how many of them are short or well stocked (`stockLevel`, the
//              one reading of stock against normal). Its market tax rides the same line.
//   Economy    `world.stats_city(port)` (0214) — the purse, money in and out over a day and the
//              taxes it took. OPEN TO EVERYONE since 0223 (the owner, 2026-10-25, row 197: "on
//              cities, i want to see all the info without investment"): the figures are absent only
//              before the job's first rollup row, and that is drawn as nothing, not as an error.
//
// THERE IS NO POPULATION IN THIS WORLD. Nothing on the wire or in `data/ports.json` counts a city's
// people (docs/PRICE_FACTORS.md turned consumption-per-head down as "a world-data change of its
// own"), so this face does not print one and does not invent one. The nearest honest fact about a
// city's size is its served `size_tier`, the rank the chart already draws its mark and its light
// from, and it is printed as a WORD — a bare level is what the owner refused in row 83.
//
// ONE ASK A VISIT. The figures behind `world.stats_city` are a fifteen-minute rollup, so this tab
// asks for them when it is opened and does not poll: `trigger` never moves. The live, by-the-second
// reading of the world is the STATS tab's job (features/stats), not a city panel's.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** A read asked once a visit — the rollup behind it is written every fifteen minutes. */
const ONE_ASK = 1

/** `size_tier` (1–5) as a word. The chart ranks every harbour by it (src/chart/glyphs.ts). */
const SIZE_WORD: Record<number, TKey> = {
  1: 'town.i_size1',
  2: 'town.i_size2',
  3: 'town.i_size3',
  4: 'town.i_size4',
  5: 'town.i_size5',
}

/** A traded good in the player's own language — the served name where Korean has no entry. */
function goodName(good: { code: string; name: string }): string {
  return properName('good', good.code, good.name)
}

/** How many of this city's goods stand short of, at, or above their normal stock. */
function stocks(goods: readonly MarketGood[]): Record<StockLevel, number> {
  const out: Record<StockLevel, number> = { low: 0, normal: 0, high: 0 }
  for (const g of goods) out[stockLevel(g.stock, g.stock_target)] += 1
  return out
}

export function CityInfo({ port }: { port: SnapshotPort }) {
  const t = useT()
  const nationByCode = useWorld((s) => s.nationByCode)
  const allegiance = useWorld((s) => s.allegiance)
  const held = portNationOf(allegiance, port.code)
  const harbour = port.kind === 'HARBOUR' ? port.id : null
  const hall = useTownHall(harbour)
  const quay = usePortMarket(harbour)
  const figures = useServedRead<StatsCity>(
    harbour === null ? null : `info:city:${harbour}`,
    () => worldStatsCity(harbour as string),
    { trigger: ONE_ASK, name: 'worldStatsCity' },
  )

  if (port.kind !== 'HARBOUR') return <Note tone="neutral">{t('town.i_noCity')}</Note>

  const influence = hall.view?.view?.influence ?? null
  const shares = (influence?.shares ?? []).slice(0, 2)
  // WHAT THIS CITY DEALS IN: `buyableHere` (src/domain/market), the one reading of 0061's roster
  // and the culture mask together — a row is in the payload for a hold of yours as well.
  const offered = (quay.market?.goods ?? []).filter(buyableHere)
  const band = stocks(offered)
  const v = figures.view
  const o = v?.overview ?? null
  const sizeWord = SIZE_WORD[port.size_tier]

  return (
    <div data-testid="city-info">
      {/* WHOSE CITY, AND WHO IS PUSHING ON IT. The country and the shares both ride the LABEL and
          its second line, never the value slot: a value is never wrapped (Row.tsx), and two country
          names and two percentages would push a 390 px panel sideways. */}
      <Row
        label={held ? <CityFlag allegiance={held} /> : t('town.i_country')}
        data-testid="city-info-country"
      >
        <FactsLine data-testid="city-info-influence">
          {shares.length === 0 ? (
            <span>{t('town.i_nobody')}</span>
          ) : (
            shares.map((s) => (
              <span key={s.nation}>{`${nationNameOf(nationByCode, s.nation)} ${formatPct(s.share)}`}</span>
            ))
          )}
        </FactsLine>
      </Row>

      <Row label={t('town.i_sea')} value={port.sea} data-testid="city-info-sea">
        <FactsLine>
          <span>{t('town.i_culture', { culture: properName('culture', port.culture, port.culture) })}</span>
          {/* A rank this build has never heard of says nothing, rather than guessing a middling one. */}
          {sizeWord !== undefined && <span>{t(sizeWord)}</span>}
        </FactsLine>
      </Row>

      <Row
        label={t('town.i_market')}
        value={quay.market === undefined ? '—' : t('town.i_goods', { n: formatInt(offered.length) })}
        hairline={false}
        data-testid="city-info-market"
      >
        <FactsLine>
          {band.low > 0 && <span>{t('town.i_short', { n: formatInt(band.low) })}</span>}
          {band.high > 0 && <span>{t('town.i_plenty', { n: formatInt(band.high) })}</span>}
          <span>{t('town.i_tax', { pct: formatPct(port.tax_rate, 1) })}</span>
        </FactsLine>
      </Row>

      {/* the city's money, served to everyone (0223) */}
      {figures.loading && !v && <Skeleton className="mt-3 h-20 w-full" />}
      {o && (
        <div className="mt-3" data-testid="city-info-economy">
          <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
            <StatCell label={t('town.i_purse')} value={o.purse} format={formatDucats} size="body" tone="accent" />
            <StatCell label={t('town.i_in')} value={o.income_1d} format={formatDucatsDelta} size="body" tone="success" />
            <StatCell label={t('town.i_out')} value={-o.spending_1d} format={formatDucatsDelta} size="body" tone="danger" />
            <StatCell label={t('town.i_taxes')} value={o.taxes_1d} format={formatDucats} size="body" />
          </div>
          <FactsLine>
            {o.top_sold[0] && <span>{t('town.i_buys', { good: goodName(o.top_sold[0]) })}</span>}
            {o.top_bought[0] && <span>{t('town.i_sells', { good: goodName(o.top_bought[0]) })}</span>}
          </FactsLine>
        </div>
      )}
    </div>
  )
}

import { useMemo } from 'react'
import { Chip, Hint, Icon, Note, Skeleton, Sparkline, goodIcon } from '../../../components/ui'
import { PortFlag } from '../../../live/PortFlag'
import type { PortMarketState } from '../../../live/usePortMarket'
import { usePriceWhy } from '../../../live/useDesk'
import { usePriceSeries } from '../../../live/usePriceSeries'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { haversineNm } from '../../../lib/geo/greatCircle'
import { sailOrigin } from '../../../domain/passage'
import { formatFixed, formatInt, formatPriceFigure } from '../../../lib/format'
import type { FleetView, MarketGood } from '../../../lib/rpc'
import { useT } from '../../../lib/i18n'
import { dayLine } from './dayLine'

// THE CITY'S BOARD — under the map on the Buy and Sell faces (owner row 229, 2026-10-26: *"I want to click on cities,
// see the selling prices when i click on the city, not give a bunch of list … for buying and selling i want both to be
// … similar mechanism. similar screen, buttons to press etc. make it like a true game."*).
//
//   CITY CHIPS  a short strip of the harbours nearest her, for a thumb that misses on the small map — names only,
//               never a price: what a city pays is found by pressing it (no cross-city list, the owner's rule).
//   CARDS       ONE card per good, the same card on both faces: the good's icon and name, THE SIDE'S PRICE (Buy — the
//               city's ask; Sell — its bid), ▲▼ against a day ago, the day's line (world.price_series, always drawn —
//               "selling i cannot even see charts"), and her units aboard. On Sell a good the city does not buy is
//               greyed "No buyer" and does not press. At a city she is NOT at, a carried good its quay does not list
//               (public.quay_shows: offered there, or she lies there with it) is bid for by world.price_why — the
//               server buys it there all the same (owner row 231: "i can't sell because i can't dock").
//
// Which cards stand is the caller's (BuySell.tsx); this file draws them and hands a press up. Nothing is priced here.

export interface CityGoodRow {
  code: string
  /** The good's id (the price reads ask by it); null only while the catalogue has not loaded. */
  goodId: string | null
  name: string
  category: string
  units: number
  /** The city's market row for the good, or null where its quay lists none (Sell, at a city she is not at: the card
   *  asks world.price_why for the bid — owner row 231). */
  row: MarketGood | null
  /** The side's price, or null. */
  price: number | null
}

/** How many harbours the chip strip names — a short strip, not a directory. */
const CHIPS = 8

/** ▲ +3.2 % / ▼ 1.4 % — green up, red down, nothing else coloured (owner row 229). */
export function DayChange({ change, className = '' }: { change: number | null; className?: string }) {
  if (change === null) return <span className={`text-t-caption text-ink-faint ${className}`}>—</span>
  const pts = Math.abs(change * 100)
  if (pts < 0.05) return <span className={`text-t-caption tabular-nums text-ink-faint ${className}`}>0.0%</span>
  const up = change > 0
  return (
    <span className={`whitespace-nowrap text-t-caption tabular-nums ${up ? 'text-success' : 'text-danger'} ${className}`} data-testid="day-change" data-dir={up ? 'up' : 'down'}>
      {up ? '▲' : '▼'} {formatFixed(pts, 1)}%
    </span>
  )
}

export function CityBoard({
  side,
  fleet,
  city,
  docked,
  quay,
  rows,
  picked,
  onPick,
  onCity,
}: {
  side: 'buy' | 'sell'
  fleet: FleetView
  city: string | null
  docked: boolean
  quay: PortMarketState
  rows: readonly CityGoodRow[]
  picked: string | null
  onPick: (code: string) => void
  onCity: (code: string) => void
}) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const ports = useWorld((s) => s.snapshot?.ports)
  const portId = city ? (portByCode[city]?.id ?? null) : null

  // THE CHIPS: the city in hand, where she lies, then the harbours nearest where she departs from
  const chips = useMemo(() => {
    const from = sailOrigin(fleet, portByCode)
    // harbours only: a sea place (a cape, a strait) keeps no market
    const harbours = (ports ?? []).filter((p) => p.kind !== 'SEA_PLACE')
    const near = from ? [...harbours].sort((a, b) => haversineNm(from, a) - haversineNm(from, b)).map((p) => p.code) : harbours.map((p) => p.code)
    const head = [fleet.status === 'DOCKED' ? fleet.port : null, city].filter((c): c is string => !!c)
    return [...new Set([...head, ...near])].slice(0, CHIPS)
  }, [fleet, portByCode, ports, city])

  return (
    <div data-testid="city-goods" data-city={city ?? ''} data-side={side} data-docked={docked ? 'true' : 'false'}>
      <div className="-mx-1 mb-2 flex gap-1.5 overflow-x-auto px-1 pb-1" role="group" aria-label={t('desk.cityChips')} data-testid="city-chips">
        {chips.map((c) => (
          <Chip key={c} on={c === city} onClick={() => onCity(c)} className="shrink-0 whitespace-nowrap" data-testid="city-chip" data-port={c}>
            <PortFlag code={c} /> {portNameOf(portByCode, c)}
          </Chip>
        ))}
      </div>
      {!city ? (
        <Hint>{t('desk.pickCity')}</Hint>
      ) : (
        <>
          {/* where she lies, the strip's lit chip says it all; anywhere else the city is named, "Not docked" */}
          {!docked && (
            <div className="mb-2 flex flex-wrap items-baseline gap-x-2" data-testid="city-goods-head">
              <span className="text-t-body font-semibold text-ink" data-testid="city-goods-name">
                <PortFlag code={city} /> {portNameOf(portByCode, city)}
              </span>
              <span className="text-t-caption text-ink-faint" data-testid="city-goods-not-docked">
                {t('desk.notDocked')}
              </span>
            </div>
          )}
          {side === 'buy' && quay.market === undefined ? (
            quay.refusal ? (
              <Note tone="danger">{quay.refusal.sentence}</Note>
            ) : (
              <div className="grid grid-cols-2 gap-2 lg:grid-cols-3">
                {Array.from({ length: 6 }, (_, i) => (
                  <Skeleton key={i} className="h-20 w-full" />
                ))}
              </div>
            )
          ) : rows.length === 0 ? (
            <Hint data-testid="city-goods-none">{t(side === 'buy' ? 'desk.noBuy' : 'desk.holdEmpty')}</Hint>
          ) : (
            <div className="grid grid-cols-2 gap-2 lg:grid-cols-3" data-testid="city-goods-grid">
              {rows.map((r) => (
                <GoodCard key={r.code} side={side} portId={portId} row={r} bidElsewhere={side === 'sell' && !docked} on={picked === r.code} loading={quay.market === undefined} onPick={() => onPick(r.code)} />
              ))}
            </div>
          )}
        </>
      )}
    </div>
  )
}

function GoodCard({
  side,
  portId,
  row: r,
  bidElsewhere,
  on,
  loading: quayLoading,
  onPick,
}: {
  side: 'buy' | 'sell'
  portId: string | null
  row: CityGoodRow
  /** Sell, at a city she is not at: a good its quay does not list is bid for by world.price_why. */
  bidElsewhere: boolean
  on: boolean
  loading: boolean
  onPick: () => void
}) {
  const t = useT()
  const ask = bidElsewhere && r.row === null
  const why = usePriceWhy(ask ? portId : null, ask ? r.goodId : null)
  const price = r.price ?? (ask ? (why.view?.bid ?? null) : null)
  const priced = r.row !== null || price !== null
  const trend = usePriceSeries(priced ? portId : null, priced ? r.goodId : null, '1d')
  const line = dayLine(trend.series, side, price)
  const dead = price === null
  const loading = quayLoading || (ask && why.loading)
  return (
    <button
      type="button"
      onClick={dead ? undefined : onPick}
      disabled={dead}
      aria-pressed={on}
      title={r.name}
      className={[
        // a tone step, never a border (UI_DIRECTION §4.3); the pressed card is lit and ringed
        'flex min-w-0 flex-col gap-1 rounded-md p-2 text-left transition active:scale-[0.97]',
        on ? 'bg-accent-soft ring-1 ring-accent' : 'bg-surface-2 hover:bg-surface-2/70',
        dead ? 'cursor-default opacity-50' : '',
      ].join(' ')}
      data-testid="city-good"
      data-good={r.code}
    >
      <span className="flex min-w-0 items-start gap-1.5">
        <Icon name={goodIcon(r.code, r.category)} size={18} className="mt-px shrink-0 text-ink-muted" />
        <span className="min-w-0 break-words text-t-label font-medium leading-tight text-ink" data-testid="city-good-name">{r.name}</span>
      </span>
      <span className="flex items-baseline justify-between gap-1">
        <span className={`text-t-body font-semibold tabular-nums ${dead ? 'text-ink-faint' : 'text-ink'}`} data-testid="city-good-price">
          {dead ? (loading ? '…' : t('desk.noBuyer')) : formatPriceFigure(price as number)}
        </span>
        {!dead && <DayChange change={line.change} />}
      </span>
      <span className="flex items-center justify-between gap-2">
        <span className="flex h-4 min-w-0 flex-1 items-center" data-testid="city-good-spark" data-points={line.values.length}>
          {!dead && <Sparkline values={line.values} width={96} height={16} className="h-4 w-full" />}
        </span>
        <span className={`shrink-0 text-t-caption tabular-nums ${r.units > 0 ? 'text-ink' : 'text-ink-faint'}`} data-testid="city-good-aboard">
          {t('desk.aboardN', { n: formatInt(r.units) })}
        </span>
      </span>
    </button>
  )
}

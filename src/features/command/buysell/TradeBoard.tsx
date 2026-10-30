import { useMemo } from 'react'
import { Button, Chip, Hint, Icon, Note, Skeleton, Sparkline, goodIcon } from '../../../components/ui'
import { PortFlag } from '../../../live/PortFlag'
import { usePriceWhy } from '../../../live/useDesk'
import { usePriceSeries } from '../../../live/usePriceSeries'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { haversineNm } from '../../../lib/geo/greatCircle'
import { sailOrigin } from '../../../domain/passage'
import { formatInt, formatPriceFigure } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import type { FleetView } from '../../../lib/rpc'
import type { PortMarketState } from '../../../live/usePortMarket'
import { dayLine } from './dayLine'
import type { TradeGoodRow } from './tradeRows'

// THE COMBINED TRADE BOARD (owner 2026-10-30: *"removing the map, just have combined buy and sell tab with trade
// goods when docked"*) — the city in hand's goods in ONE list, each row showing the city's ASK (Buy) and BID (Sell)
// side by side, so a trade is one press, not a face turn. It replaced the mirrored Buy / Sell cards
// (CityBoard.tsx, deleted 2026-10-30 — one board, not two).
//
//   CITY CHIPS  a short strip of the harbours nearest her, for a thumb that misses on the small map — names only,
//               never a price: what a city pays is found by pressing it (owner row 229, no cross-city list on Buy).
//               The short strip of nearest harbours CityBoard drew.
//   CARDS       ONE card per good: its icon and name, BOTH prices (the city's ask on the left, its bid on the right),
//               ▲▼ against a day ago, the day's line, and her units aboard. At a city she is NOT at, a carried good
//               its quay does not list is bid for by world.price_why — the server buys it there all the same (owner
//               row 231: "i can't sell because i can't dock").
//
// The rows are tradeRows.ts — a pure function, so this file holds only the cards and the strip.

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

function formatFixed(pts: number, d: number) {
  return pts.toFixed(d)
}

/** How many harbours the chip strip names — a short strip, not a directory. */
const CHIPS = 8

export function TradeBoard({
  fleet,
  city,
  docked,
  quay,
  rows,
  picked,
  onBuy,
  onSell,
  onCity,
}: {
  fleet: FleetView
  /** The city in hand (port CODE); the board reads its market. */
  city: string | null
  /** She lies at the city in hand. */
  docked: boolean
  quay: PortMarketState
  rows: readonly TradeGoodRow[]
  /** The good whose panel is open. */
  picked: string | null
  onBuy: (code: string) => void
  onSell: (code: string) => void
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
    <div data-testid="trade-board" data-city={city ?? ''} data-docked={docked ? 'true' : 'false'}>
      <div className="-mx-1 mb-2 flex flex-wrap gap-1.5 px-1 pb-1" role="group" aria-label={t('desk.cityChips')} data-testid="city-chips">
        {chips.map((c) => (
          <Chip key={c} on={c === city} onClick={() => onCity(c)} className="max-w-full" data-testid="city-chip" data-port={c}>
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
            <div className="mb-2 flex flex-wrap items-baseline gap-x-2" data-testid="trade-board-head">
              <span className="text-t-body font-semibold text-ink" data-testid="trade-board-name">
                <PortFlag code={city} /> {portNameOf(portByCode, city)}
              </span>
              <span className="text-t-caption text-ink-faint" data-testid="trade-board-not-docked">
                {t('desk.notDocked')}
              </span>
            </div>
          )}
          {quay.market === undefined ? (
            quay.refusal ? (
              <Note tone="danger">{quay.refusal.sentence}</Note>
            ) : (
              <div className="grid grid-cols-2 gap-2 lg:grid-cols-3">
                {Array.from({ length: 6 }, (_, i) => (
                  <Skeleton key={i} className="h-28 w-full" />
                ))}
              </div>
            )
          ) : rows.length === 0 ? (
            <Hint data-testid="trade-board-empty">{t('desk.noBuy')}</Hint>
          ) : (
            <div className="grid grid-cols-2 gap-2 lg:grid-cols-3">
              {rows.map((r) => (
                <TradeCard key={r.code} portId={portId} r={r} docked={docked} on={picked === r.code} onBuy={onBuy} onSell={onSell} />
              ))}
            </div>
          )}
        </>
      )}
    </div>
  )
}

/** ONE good's card. Named TradeCard, not TradeRow: `TradeRow` is the design system's row
 *  (components/ui) and a screen may not re-declare its name (tests/duplication.spec.ts). */
function TradeCard({
  portId,
  r,
  docked,
  on,
  onBuy,
  onSell,
}: {
  portId: string | null
  r: TradeGoodRow
  /** She lies at the city in hand. */
  docked: boolean
  /** This good's panel is open. */
  on: boolean
  onBuy: (code: string) => void
  onSell: (code: string) => void
}) {
  const t = useT()
  // Sell, at a city she is NOT at: a carried good its quay does not list is bid for by world.price_why (owner row 231)
  const askBid = !docked && r.sell === null && r.units > 0 && r.goodId !== null
  const why = usePriceWhy(askBid ? portId : null, askBid ? r.goodId : null)
  const sell = r.sell ?? (askBid ? (why.view?.bid ?? null) : null)
  const priced = r.goodId !== null && r.buy !== null
  const trend = usePriceSeries(priced ? portId : null, priced ? r.goodId : null, '1d')
  const line = dayLine(trend.series, 'buy', r.buy)
  const buyDead = r.buy === null
  const sellDead = sell === null || r.units <= 0
  return (
    <div
      className={[
        'flex min-w-0 flex-col gap-1 rounded-md p-2 text-left transition',
        on ? 'bg-accent-soft ring-1 ring-accent' : 'bg-surface-2',
      ].join(' ')}
      data-testid="trade-good"
      data-good={r.code}
    >
      <span className="flex min-w-0 items-start gap-1.5">
        <Icon name={goodIcon(r.code, r.category)} size={18} className="mt-px shrink-0 text-ink-muted" />
        <span className="min-w-0 break-words text-t-label font-medium leading-tight text-ink" data-testid="trade-good-name">{r.name}</span>
        <span className={`ml-auto shrink-0 text-t-caption tabular-nums ${r.units > 0 ? 'text-ink' : 'text-ink-faint'}`} data-testid="trade-good-aboard">
          {t('desk.aboardN', { n: formatInt(r.units) })}
        </span>
      </span>
      <span className="flex items-baseline justify-between gap-1">
        <span className={`text-t-body font-semibold tabular-nums ${buyDead ? 'text-ink-faint' : 'text-ink'}`} data-testid="trade-good-buy">
          {buyDead ? '—' : formatPriceFigure(r.buy as number)}
        </span>
        <span className={`text-t-body font-semibold tabular-nums ${sellDead ? 'text-ink-faint' : 'text-ink'}`} data-testid="trade-good-sell">
          {sellDead ? t('desk.noBuyer') : formatPriceFigure(sell as number)}
        </span>
      </span>
      <span className="flex h-4 min-w-0 flex-1 items-center" data-testid="trade-good-spark" data-points={line.values.length}>
        {!buyDead && <Sparkline values={line.values} width={96} height={16} className="h-4 w-full" />}
      </span>
      <span className="flex items-center gap-2">
        <Button variant="secondary" className="flex-1" onClick={() => onBuy(r.code)} disabled={buyDead} data-testid="trade-buy">
          {t('desk.buy')}
        </Button>
        <Button variant="secondary" className="flex-1" onClick={() => onSell(r.code)} disabled={sellDead} data-testid="trade-sell">
          {t('desk.sell')}
        </Button>
      </span>
    </div>
  )
}

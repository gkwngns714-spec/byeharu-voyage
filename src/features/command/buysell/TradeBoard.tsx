import { useMemo, type ReactNode } from 'react'
import { Button, Hint, Icon, Note, ScrollPane, Skeleton, Sparkline, TileChoice, TileGrid, goodIcon } from '../../../components/ui'
import { PortFlag } from '../../../live/PortFlag'
import { usePriceWhy } from '../../../live/useDesk'
import { usePriceSeries } from '../../../live/usePriceSeries'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { haversineNm } from '../../../lib/geo/greatCircle'
import { sailOrigin } from '../../../domain/passage'
import { formatInt, formatPriceDelta, formatPriceFigure } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import type { BestSale, FleetView } from '../../../lib/rpc'
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
//   BEST SALE   0348 (owner row 307): under the prices, the good's best sale from the city in hand — the city and the
//               served PROFIT (world.best_sales: ONE read for the board, never one per card — Trade.tsx asks it). Green
//               when it pays, red "No gain" when no city she can sail to pays. A press opens the trip to that city at
//               the units the figure was priced for, so the tray's first figure is the card's.
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
  sales,
  onBest,
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
  /** 0348: each good's best sale from the city in hand, by good CODE; null while it has not landed. */
  sales: ReadonlyMap<string, BestSale> | null
  onBest: (sale: BestSale) => void
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
      {/* THE CITY PICKER IS A GRID (owner, 2026-10-31) — equal cells, fixed columns, in the same
          nearest-first order; a flag and a name per cell, never a ragged strip. */}
      <TileGrid label={t('desk.cityChips')} columns={4} className="mb-2 lg:grid-cols-[repeat(auto-fill,minmax(min(100%,7.5rem),1fr))]!" data-testid="city-chips">
        {chips.map((c) => (
          <TileChoice key={c} on={c === city} onClick={() => onCity(c)} data-testid="city-chip" data-port={c}>
            {/* one child: the flag and the name stay ONE group, centred — and no `truncate`, so a
                long harbour wraps rather than hiding its tail (tests/align.spec.ts's CUT rule). */}
            <span className="flex min-w-0 items-center gap-1">
              <PortFlag code={c} /> <span className="min-w-0 break-words">{portNameOf(portByCode, c)}</span>
            </span>
          </TileChoice>
        ))}
      </TileGrid>
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
              <div className="grid grid-cols-2 gap-2 lg:grid-cols-[repeat(auto-fill,minmax(min(100%,9.5rem),1fr))]">
                {Array.from({ length: 6 }, (_, i) => (
                  <Skeleton key={i} className="h-28 w-full" />
                ))}
              </div>
            )
          ) : rows.length === 0 ? (
            <Hint data-testid="trade-board-empty">{t('desk.noBuy')}</Hint>
          ) : (
            // THE CARDS ARE THE ONE LONG LIST ON THIS FACE: at a busy quay they run past the
            // glass, so they scroll inside their own bounded pane (the page above stays put).
            // From lg the desk's centre pane is already the scroller — no second bound there.
            // 0348: the bound grew by what the best sale added to a card (28 px), so the first row's buttons stand inside it as before
            <ScrollPane className="max-h-[10.75rem] lg:max-h-none">
              <div className="grid grid-cols-2 gap-2 lg:grid-cols-[repeat(auto-fill,minmax(min(100%,9.5rem),1fr))]">
                {rows.map((r) => (
                  <TradeCard
                    key={r.code}
                    portId={portId}
                    r={r}
                    docked={docked}
                    on={picked === r.code}
                    onBuy={onBuy}
                    onSell={onSell}
                    sale={sales?.get(r.code)}
                    onBest={onBest}
                  />
                ))}
              </div>
            </ScrollPane>
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
  sale,
  onBest,
}: {
  portId: string | null
  r: TradeGoodRow
  /** She lies at the city in hand. */
  docked: boolean
  /** This good's panel is open. */
  on: boolean
  onBuy: (code: string) => void
  onSell: (code: string) => void
  /** 0348: its best sale from the city in hand; undefined while the read is out (or for a good the city does not sell). */
  sale: BestSale | undefined
  onBest: (sale: BestSale) => void
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
      <span className="flex min-w-0 flex-wrap items-start gap-x-1.5 gap-y-0.5">
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
      <SaleBlock sale={sale} onPress={onBest}>
        {/* THE SPARK ROW RESERVES ITS HEIGHT WHATEVER THE READ HAS LANDED (2026-10-31). `h-4` alone
            did not: `flex-1` set a flex-basis of 0 and the item's automatic minimum came from its
            CHILD, so a card whose price series had not landed was 16 px SHORTER — the card grew the
            moment the read arrived, and a press that opened the ticket moved the rows below it
            (desk.terminal's "a press moved the list": measured spark 0→16 px, card 113→129 px).
            `shrink-0` makes h-4 the height in every state, so the list is the same list before and
            after any read or press. */}
        <span className="flex h-4 min-w-0 shrink-0 items-center" data-testid="trade-good-spark" data-points={line.values.length}>
          {!buyDead && <Sparkline values={line.values} width={96} height={16} className="h-4 w-full" />}
        </span>
      </SaleBlock>
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

/** 0348: ONE GOOD'S BEST SALE — the city and the served profit (world.best_sales) — over the good's day line, the two as
 *  ONE 44-px block (the tap-target floor) whose height is held whatever has landed, so the card is the same card before and
 *  after the read: nothing below moves. With a sale the whole block is the press. Green: it pays. Red "No gain": no city she
 *  can sail to pays (the figure is the least loss, still pressable — the tray says why); with no city at all, no press;
 *  "Cargo full": no room for one. A long city name is cut and read whole from the block's title. */
function SaleBlock({ sale, onPress, children }: { sale: BestSale | undefined; onPress: (sale: BestSale) => void; children: ReactNode }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const block = 'flex h-11 w-full min-w-0 shrink-0 flex-col justify-center gap-1'
  const line = 'flex h-5 w-full min-w-0 items-center gap-1 text-t-caption tabular-nums'
  if (!sale || sale.port === null || sale.profit === null) {
    return (
      <div className={block}>
        {sale ? (
          <span className={`${line} text-danger`} data-testid="best-sale" data-state="none" data-pays="false">
            {t(sale.basis === 'step' ? 'desk.holdFull' : 'desk.noGain')}
          </span>
        ) : (
          <span className={line} data-testid="best-sale" data-state="wait" aria-hidden="true" />
        )}
        {children}
      </div>
    )
  }
  const city = portNameOf(portByCode, sale.port)
  const words = `${sale.pays ? '' : `${t('desk.noGain')} · `}${city} ${formatPriceDelta(sale.profit)}`
  return (
    <button
      type="button"
      onClick={() => onPress(sale)}
      title={words}
      aria-label={`${t('desk.bestSale')}: ${words}`}
      className={`${block} rounded text-left transition hover:bg-surface-1 active:scale-[0.99]`}
    >
      <span
        className={`${line} ${sale.pays ? 'text-success' : 'text-danger'}`}
        data-testid="best-sale"
        data-state="sale"
        data-port={sale.port}
        data-pays={sale.pays ? 'true' : 'false'}
        data-profit={sale.profit}
        data-units={sale.units ?? ''}
      >
        {!sale.pays && <span className="shrink-0 font-medium">{t('desk.noGain')}</span>}
        <span className="min-w-0 truncate">
          <PortFlag code={sale.port} /> {city}
        </span>
        <span className="ml-auto shrink-0 font-semibold" data-testid="best-sale-profit">
          {formatPriceDelta(sale.profit)}
        </span>
      </span>
      {children}
    </button>
  )
}

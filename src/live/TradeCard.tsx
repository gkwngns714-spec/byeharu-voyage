import type { ReactNode } from 'react'
import { Button, GoodKind, Icon, Sparkline, goodClassRow, goodIcon } from '../components/ui'
import { PortFlag } from './PortFlag'
import { usePriceWhy } from './useDesk'
import { usePriceSeries } from './usePriceSeries'
import { portNameOf, useWorld } from './worldStore'
import { dayLine } from '../domain/market/dayLine'
import type { TradeGoodRow } from '../domain/market/tradeRows'
import { formatInt, formatPriceDelta, formatPriceFigure } from '../lib/format'
import { useT } from '../lib/i18n'
import type { BestSale } from '../lib/rpc'

// THE GOODS CARD — ONE card per good, wherever a good is traded (S5, 2026-11-11: the owner's remaster). The Trade board
// (features/command/buysell/TradeBoard.tsx) and the HQ Market (features/city/MarketFace.tsx) both draw it; until S5 the
// HQ drew a second card for the same good (`TradeRow`). It lives here, not in a screen, because two screens share it and
// it reads the store (a price series, a bid, the world's ports), which the design system may not.

/** The HQ's card has no trip to open (see `sale`); with no sale drawn, nothing calls it. */
const NO_TRIP = () => {}

/** ONE good's card. Named TradeCard, not TradeRow: `TradeRow` is the design system's row
 *  (components/ui) and a screen may not re-declare its name (tests/duplication.spec.ts). */
export function TradeCard({
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
  /** 0348: its best sale from the city in hand; undefined while the read is out (or for a good the city does not sell),
   *  and always at the HQ Market, which does not ask world.best_sales: its press opens the Trade screen's trip, and the
   *  HQ has no trip to open — the line's place stays held, empty, so the card is the same card. */
  sale?: BestSale
  onBest?: (sale: BestSale) => void
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
  // THE GOOD'S CLASS (0294) rides on the card as on every list a good stands in: the mark beside the name, the wash from
  // class 4 (goodClassRow) — tests/good.class.spec.ts. A good the city does not list has no class served here.
  const { className: wash = '', ...cls } = goodClassRow(r.row?.class)
  return (
    <div
      className={[
        'flex min-w-0 flex-col gap-1 rounded-md p-2 text-left transition',
        on ? 'bg-accent-soft ring-1 ring-accent' : 'bg-surface-2',
        wash,
      ].join(' ')}
      {...cls}
      data-testid="trade-good"
      data-good={r.code}
    >
      <span className="flex min-w-0 flex-wrap items-start gap-x-1.5 gap-y-0.5">
        <Icon name={goodIcon(r.code, r.category)} size={18} className="mt-px shrink-0 text-ink-muted" />
        <span className="min-w-0 break-words text-t-label font-medium leading-tight text-ink" data-testid="trade-good-name">
          {r.name}
          {/* 0255 (E6b): the city wants this good and pays a multiple for it this period */}
          {r.row?.wanted != null && (
            <span className="text-t-caption text-accent" data-testid="trade-good-wanted">
              {' '}
              {t('ui.wanted', { mult: String(Number(r.row.wanted)) })}
            </span>
          )}
        </span>
        {/* THE CLASS MARKS beside the name, in a box the height of the icon's line: the stacked cluster (GoodKind compact,
            20 px) may stand past it by a pixel but never grows the card, and the name's own box never carries the cluster's
            give-back margin (which read as a cut name: tests/desk.terminal.spec.ts). */}
        {r.row && (
          <span className="flex h-[1.1875rem] shrink-0 items-center" data-testid="trade-good-marks">
            <GoodKind compact rarity={r.row.rarity} goodClass={r.row.class} />
          </span>
        )}
        <span className={`ml-auto shrink-0 text-t-caption tabular-nums ${r.units > 0 ? 'text-ink' : 'text-ink-faint'}`} data-testid="trade-good-aboard">
          {t('desk.aboardN', { n: formatInt(r.units) })}
        </span>
      </span>
      {/* 0348: THE PRICES, THE BEST SALE AND THE DAY LINE ARE ONE 44-PX BLOCK (the tap-target floor) in the room the prices
          and the day line took before (22 + 4 + 16 px): a card grows 2 px, so four cards still stand above a phone's fold
          (tests/layout.spec.ts, K.1). With a sale, the block is the press that opens its trip. */}
      <SaleBlock
        // no press to open (the HQ Market): no sale is drawn either — the line's place stays held, empty
        sale={onBest ? sale : undefined}
        onPress={onBest ?? NO_TRIP}
        prices={
          <>
            <span className={`text-t-body font-semibold tabular-nums ${buyDead ? 'text-ink-faint' : 'text-ink'}`} data-testid="trade-good-buy">
              {buyDead ? '—' : formatPriceFigure(r.buy as number)}
            </span>
            <span className={`text-t-body font-semibold tabular-nums ${sellDead ? 'text-ink-faint' : 'text-ink'}`} data-testid="trade-good-sell">
              {sellDead ? t('desk.noBuyer') : formatPriceFigure(sell as number)}
            </span>
          </>
        }
        spark={
          // THE SPARK SLOT RESERVES ITS SIZE WHATEVER THE READ HAS LANDED (2026-10-31): `shrink-0` with a fixed h-4 (and,
          // since 0348, a fixed w-12 beside the best sale), so a card is the same card before and after any read or press
          // (desk.terminal's "a press moved the list": a spark that landed late once grew a card 16 px).
          <span className="flex h-4 w-12 shrink-0 items-center" data-testid="trade-good-spark" data-points={line.values.length}>
            {!buyDead && <Sparkline values={line.values} width={48} height={16} className="h-4 w-full" />}
          </span>
        }
      />
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

/** 0348: THE CARD'S MIDDLE — its two prices over ONE GOOD'S BEST SALE (world.best_sales: the city and the served profit)
 *  and its day line — as ONE 44-px block (the tap-target floor) whose height is held whatever has landed. With a sale the
 *  block is the press that opens its trip. Green: it pays. Red "No gain": no city she can sail to pays (the figure is the
 *  least loss, still pressable — the tray says why); with no city at all, no press; "Cargo full": no room for one. A long
 *  city name is cut and read whole from the block's title. */
function SaleBlock({
  sale,
  onPress,
  prices,
  spark,
}: {
  sale: BestSale | undefined
  onPress: (sale: BestSale) => void
  prices: ReactNode
  spark: ReactNode
}) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const block = 'flex h-11 w-full min-w-0 shrink-0 flex-col justify-between'
  const top = 'flex h-[1.375rem] w-full items-baseline justify-between gap-1'
  const row = 'flex h-[1.125rem] w-full min-w-0 items-center gap-1'
  const line = 'flex min-w-0 flex-1 items-center gap-1 text-t-caption tabular-nums'
  if (!sale || sale.port === null || sale.profit === null) {
    return (
      <div className={block}>
        <span className={top}>{prices}</span>
        <span className={row}>
          {sale ? (
            <span className={`${line} text-danger`} data-testid="best-sale" data-state="none" data-pays="false">
              {t(sale.basis === 'step' ? 'desk.holdFull' : 'desk.noGain')}
            </span>
          ) : (
            <span className={line} data-testid="best-sale" data-state="wait" aria-hidden="true" />
          )}
          {spark}
        </span>
      </div>
    )
  }
  const city = portNameOf(portByCode, sale.port)
  const words = `${t('desk.bestSale')}: ${sale.pays ? '' : `${t('desk.noGain')} · `}${city} ${formatPriceDelta(sale.profit)}`
  return (
    <button type="button" onClick={() => onPress(sale)} title={words} className={`${block} rounded text-left transition hover:bg-surface-1 active:scale-[0.99]`}>
      <span className={top}>{prices}</span>
      <span className={row}>
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
        {spark}
      </span>
    </button>
  )
}

import type { ReactNode } from 'react'
import { Button, GoodKind, Icon, KEEP_WORDS_CLASS, Sparkline, goodClassRow, goodIcon } from '../components/ui'
import { PortFlag } from './PortFlag'
import { usePriceWhy } from './useDesk'
import { usePriceSeries } from './usePriceSeries'
import { portNameOf, useWorld } from './worldStore'
import { dayLine } from '../domain/market'
import type { TradeGoodRow } from '../domain/market'
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
        // FOUR LINES, SHARED ACROSS A ROW OF CARDS (2026-11-11, the trade-layout slice): the head, the prices, the best sale
        // and the buttons are four rows of the board's own grid (`grid-rows-subgrid`), so in a row of cards each of the
        // four is one height: the prices stand level, the buttons stand level, and a card whose name or whose best sale's
        // city runs a second line makes that line taller for its whole row instead of standing out of step. Where the
        // card is not in a grid the four rows are simply its own.
        // ONE COLUMN, AS WIDE AS THE CARD AND NO WIDER (`grid-cols-1` = minmax(0, 1fr)): a grid's own column is as wide as
        // its widest line wants, so in a 123-px card (the HQ Market at 320 px) the prices line stood 21 px past the card's
        // edge and "안 삼" crossed the next card's price (tests/city.phone.spec.ts caught it).
        'row-span-4 grid min-w-0 grid-cols-1 grid-rows-subgrid gap-y-1 rounded-md p-2 text-left transition',
        on ? 'bg-accent-soft ring-1 ring-accent' : 'bg-surface-2',
        wash,
      ].join(' ')}
      {...cls}
      data-testid="trade-good"
      data-good={r.code}
    >
      <span className="flex min-w-0 flex-wrap content-start items-start gap-x-1.5 gap-y-0.5">
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
      {/* 0348: THE PRICES, THE BEST SALE AND THE DAY LINE ARE ONE BLOCK, never under 44 px (the tap-target floor). With a
          sale, the block is the press that opens its trip. Since 2026-11-11 the best sale's city is printed WHOLE (it was
          cut to "Hag…"), so the block holds room for two lines: the city, then the profit and the day line. */}
      <SaleBlock
        // no press to open (the HQ Market): no sale is drawn either — the line's place stays held, empty
        sale={onBest ? sale : undefined}
        canLand={onBest !== undefined}
        onPress={onBest ?? NO_TRIP}
        prices={
          <>
            <span className={`text-t-body font-semibold tabular-nums ${buyDead ? 'text-ink-faint' : 'text-ink'}`} data-testid="trade-good-buy">
              {buyDead ? '—' : formatPriceFigure(r.buy as number)}
            </span>
            {/* THE CITY'S BID IS PRINTED WHEREVER IT IS SERVED (2026-11-11, the trade-flow slice). With none aboard this cell said
                "No buyer", which was false: the city buys it, at the bid the Map's tray printed for the same good. It is the bid
                now, quiet, and its title says why Sell is dead ("None on board"; the card's own "On board 0" stands above it).
                "No buyer" stays for the one case it is true: the city serves no bid for the good. */}
            <span
              className={`text-t-body font-semibold tabular-nums ${sellDead ? 'text-ink-faint' : 'text-ink'}`}
              data-testid="trade-good-sell"
              data-state={sell === null ? 'no-buyer' : r.units <= 0 ? 'none-aboard' : 'sell'}
              title={sell !== null && r.units <= 0 ? t('desk.noneAboard') : undefined}
            >
              {sell === null ? t('desk.noBuyer') : formatPriceFigure(sell)}
            </span>
          </>
        }
        spark={
          // THE SPARK SLOT RESERVES ITS SIZE WHATEVER THE READ HAS LANDED (2026-10-31): `shrink-0` with a fixed h-4 (and,
          // since 0348, a fixed w-12 beside the best sale), so a card is the same card before and after any read or press
          // (desk.terminal's "a press moved the list": a spark that landed late once grew a card 16 px).
          <span className="flex h-4 w-12 min-w-0 items-center" data-testid="trade-good-spark" data-points={line.values.length}>
            {!buyDead && <Sparkline values={line.values} width={48} height={16} className="h-4 w-full" />}
          </span>
        }
      />
      {/* THE TWO BUTTONS FIT THE NARROWEST CARD (2026-11-12): each fills half the line, so its side padding only decides how
          narrow it can go. At the button's own 16 px a Korean button is 64 px and two of them are 136 px in a 107-px line (the
          HQ Market at 320 px): Sell stood 21 px past the card, over the next card's Buy. At 8 px it is 48 px (still over the
          44-px reach floor) and two are 104. In every wider card the buttons are the same boxes as before. */}
      <span className="flex min-w-0 items-center gap-2">
        <Button variant="secondary" className="min-w-0 flex-1 px-2!" onClick={() => onBuy(r.code)} disabled={buyDead} data-testid="trade-buy">
          {t('desk.buy')}
        </Button>
        <Button variant="secondary" className="min-w-0 flex-1 px-2!" onClick={() => onSell(r.code)} disabled={sellDead} data-testid="trade-sell">
          {t('desk.sell')}
        </Button>
      </span>
    </div>
  )
}

/** 0348: THE CARD'S MIDDLE — its two prices over ONE GOOD'S BEST SALE (world.best_sales: the city and the served profit)
 *  and its day line — as ONE block of at least 44 px (the tap-target floor) whose height is held whatever has landed. With a
 *  sale the block is the press that opens its trip. Green: it pays. Red "No gain": no city she can sail to pays (the figure
 *  is the least loss, still pressable — the tray says why); with no city at all, no press; "Cargo full": no room for one.
 *
 *  THE CITY IS PRINTED WHOLE (2026-11-11; the owner's rule: a name is never cut with "…"). The line under the prices is a
 *  wrapping line: the city (its flag and its name, by the design system's keeps-its-words rule: it turns only at a space
 *  and is never narrower than its longest word), then the profit and the day line together at the right. Where the three
 *  fit one line they stand on one; in a 175-px card the city takes the first line and the profit and the day line the
 *  second. Where a sale can land the line holds two lines' height (36 px) whatever has landed, so a card does not grow
 *  when its sale lands; at the HQ Market, where none ever does, it holds the one line the day line needs. */
function SaleBlock({
  sale,
  canLand,
  onPress,
  prices,
  spark,
}: {
  sale: BestSale | undefined
  /** A sale may land here (the Trade board asks world.best_sales); false at the HQ Market, which never asks. */
  canLand: boolean
  onPress: (sale: BestSale) => void
  prices: ReactNode
  spark: ReactNode
}) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  // two of the card's four shared rows: the prices, and the line under them
  const block = 'row-span-2 grid w-full min-w-0 grid-cols-1 grid-rows-subgrid gap-y-0'
  const top = 'flex h-[1.375rem] w-full items-baseline justify-between gap-1'
  // the line holds two lines' height where a sale can land (the Trade board); one where none ever does (the HQ Market)
  const line = `flex ${canLand ? 'min-h-9' : 'min-h-[1.125rem]'} w-full min-w-0 flex-wrap content-between items-center gap-x-1 text-t-caption tabular-nums`
  // the profit and the day line stay together, at the right of whichever line they stand on
  // (in a 140-px card a six-figure profit and the 48-px day line are 13 px too many: the day line gives way, the figure never)
  const tail = 'ml-auto flex min-w-0 max-w-full items-center gap-1'
  if (!sale || sale.port === null || sale.profit === null) {
    return (
      <div className={block}>
        <span className={top}>{prices}</span>
        {sale ? (
          <span className={`${line} text-danger`} data-testid="best-sale" data-state="none" data-pays="false">
            {t(sale.basis === 'step' ? 'desk.holdFull' : 'desk.noGain')}
            <span className={tail}>{spark}</span>
          </span>
        ) : (
          <span className={line} data-testid="best-sale" data-state="wait">
            <span className={tail}>{spark}</span>
          </span>
        )}
      </div>
    )
  }
  const city = portNameOf(portByCode, sale.port)
  const words = `${t('desk.bestSale')}: ${sale.pays ? '' : `${t('desk.noGain')} · `}${city} ${formatPriceDelta(sale.profit)}`
  return (
    <button type="button" onClick={() => onPress(sale)} title={words} className={`${block} rounded text-left transition hover:bg-surface-1 active:scale-[0.99]`}>
      <span className={top}>{prices}</span>
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
        {/* the flag and the name stand together; in a card too narrow for both (산타크루스데테네리페 is 130 px, a 158-px card
            has 142 inside) the name takes the next line whole rather than being cut */}
        <span className={`flex flex-wrap items-center gap-x-1 ${KEEP_WORDS_CLASS}`} data-testid="best-sale-city">
          <PortFlag code={sale.port} /> <span data-testid="best-sale-city-name">{city}</span>
        </span>
        <span className={tail}>
          <span className="shrink-0 font-semibold" data-testid="best-sale-profit">
            {formatPriceDelta(sale.profit)}
          </span>
          {spark}
        </span>
      </span>
    </button>
  )
}

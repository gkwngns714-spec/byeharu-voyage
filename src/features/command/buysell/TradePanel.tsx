import { useEffect, useRef, useState, type ReactNode } from 'react'
import { Button, Chip, Figure, GoodKind, Hint, Note, PLAN_LINE_CLASS, PriceChart, Row, Skeleton, SpanPicker, Stepper, Tray, type TrayDetent, type TrayMode, WRAP_ROW_CLASS } from '../../../components/ui'
import { fleetCargoByCode, paidPerTun } from '../../../domain/fleet'
import { taxFactorWords } from '../../../domain/port'
import { CityGoodTrades } from '../../../live/CityGoodTrades'
import { IfAttacked } from '../../../live/IfAttacked'
import { PortFlag } from '../../../live/PortFlag'
import { usePriceWhy } from '../../../live/useDesk'
import { usePriceSeries } from '../../../live/usePriceSeries'
import { useTrade } from '../../../live/useTrade'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { useShellState } from '../../../app/shellState'
import { formatCountdown, formatDaysReal, formatInt, formatPctDelta, formatPrice, formatPriceDelta, formatPriceFigure, instantMs, moneyFigure, moneyWord } from '../../../lib/format'
import type { BoardSellRow, FleetView, MarketGood, PriceSeries, Refusal } from '../../../lib/rpc'
import { properName, useT } from '../../../lib/i18n'
import { WhyThisPrice } from '../markets/WhyThisPrice'
import type { PlanDraft } from '../../../domain/plan'
import { useDeskPlan } from '../plans/planDraft'
import { PlanVoyage } from '../plans/PlanVoyage'
import { useTripGo } from '../plans/useTripGo'
import type { useTripBoard } from '../plans/useTripBoard'
import { BargainPress } from './BargainPress'
import { DayChange } from './TradeBoard'
import { dayLine } from '../../../domain/market'
import type { TradeDone } from './tradeDone'
import { firstAtMs, useChartNews } from '../../../live/useChartNews'
import { seaWallOf } from '../../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRADE PANEL — ONE GOOD AT ONE CITY, THE SAME PANEL ON BUY AND ON SELL (owner row 229, 2026-10-26)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"for buying and selling i want both to be... similar mechanism. similar screen, buttons to press etc."* A card
// pressed on the Trade board (TradeBoard.tsx) opens this, top to bottom:
//
//   the price this side trades at, ▲▼ against a day ago, the good's kind
//   Aboard · the units (Stepper, with Max)
//   THE CHART — the span picker and the compact PriceChart (world.price_series, the chosen span)
//   the money total, pinned with the button
//   [ ONE BIG BUTTON ]   docked at this city → Buy / Sell        (cmd.issue through useTrade — the one act)
//                        anywhere else      → Sail & buy / Sail & sell (the trip: planLines → cmd.issue_lines,
//                                             useTripGo — with its estimate: days, supplies, fees, profit)
//   why the price is what it is (0185) · who bought what here (0227) · on a trip, can she go there (PlanVoyage)
//
// 0348 (owner row 307): a card's best sale pressed opens the TRIP — Buy & sell: bought at the city in hand, sold at
// `sellAt` — in this same panel, with the sale's wages, dues and profit (the served sell row, as Sail & sell shows them).
// A good whose best sale does not pay (`noGain`, world.best_sales) says so above the units, before Max is pressed.
//
// 0351 (SUCCESS_PLAN T5): the card names the sale that pays best per day within her purse.
// 2026-11-22 (P1, A CHOICE OF WHERE TO SELL; saleChoice.ts): the trip's tray offers the best three places to sell under the
// city line — "City  time  +profit" each, the open one lit (the card's sale, the default). Pressed, the same trip to that city
// at the same units. It replaced 0351's one quiet "Far"/"Near" row.
//
// The button stands in the same place, the same size, the same colour in all four cases; only its word changes.
// A phone: a bottom sheet (Tray, docked). A wide glass: the desk's right pane. EVERY FIGURE IS SERVED.

type Trip = ReturnType<typeof useTripBoard>

/** THE GOOD THE PANEL TRADES, AND THE SIDE'S PRICE AT THE CITY (owner row 231). Where she lies, the quay's own row
 *  (world.market) — DockedAct trades through it. At another city a carried good the city's quay does not list (the
 *  quay lists a good only where it is offered or she lies with it, public.quay_shows) is still bought there: its
 *  bid is THE served one, world.price_why's (BuySell.tsx reads it). Nothing is priced here. */
export interface PanelGood {
  good_id: string
  code: string
  name: string
  category: string
  rarity?: MarketGood['rarity']
  /** The served premium class (0294), beside the rarity. */
  class?: MarketGood['class']
  price: number
}

/** P1: the places a Buy & sell trip may sell at (saleChoice.ts: rows of the trip's own board), and the press that picks one. */
interface SaleChoice {
  choices?: BoardSellRow[] | null
  onChoose?: (port: string) => void
}

export function TradePanel({
  side,
  fleet,
  city,
  good,
  market,
  docked,
  sellAt = null,
  noGain = false,
  choices = null,
  onChoose,
  trip,
  mode,
  onClose,
  onDone,
}: SaleChoice & {
  side: 'buy' | 'sell'
  fleet: FleetView
  /** The city in hand (port CODE), the good and the side's price there. */
  city: string
  good: PanelGood
  /** The city's market row for the good — what DockedAct trades through; null where the quay lists none. */
  market: MarketGood | null
  /** She lies at this city. */
  docked: boolean
  /** 0348: the trip's sell city (port CODE) — a buy that is sold there, one press; null for a one-ended trade. */
  sellAt?: string | null
  /** 0348: Buy only — no city she can sail to pays more than this costs (world.best_sales' `pays`). */
  noGain?: boolean
  /** The trip's board (BuySell.tsx reads it once; the map draws its legs). Only read when not docked. */
  trip: Trip
  mode: TrayMode
  onClose: () => void
  onDone: (done: TradeDone) => void
}) {
  const portByCode = useWorld((s) => s.portByCode)
  const port = portByCode[city] ?? null
  if (!port) return null
  return docked ? (
    market && <DockedAct side={side} fleet={fleet} portId={port.id} city={city} good={market} noGain={noGain} mode={mode} onClose={onClose} onDone={onDone} />
  ) : (
    <SailAct
      side={side}
      fleet={fleet}
      portId={port.id}
      city={city}
      good={good}
      sellAt={side === 'buy' ? sellAt : null}
      noGain={noGain}
      choices={side === 'buy' && sellAt !== null ? choices : null}
      onChoose={onChoose}
      trip={trip}
      mode={mode}
      onClose={onClose}
      onDone={onDone}
    />
  )
}

/** THE FRAME both acts stand in — one layout, so the two faces cannot drift apart. */
function Frame({
  side,
  fleet,
  portId,
  city,
  good,
  mode,
  onClose,
  warn = false,
  sellAt = null,
  choices = null,
  onChoose,
  units,
  deal,
  sale,
  pair,
  total,
  extra,
  refusal,
  profit,
  button,
  after,
}: SaleChoice & {
  side: 'buy' | 'sell'
  fleet: FleetView
  portId: string
  city: string
  good: PanelGood
  mode: TrayMode
  onClose: () => void
  /** 0348: Buy only — say, above the units, that no city she can sail to pays more than this costs. */
  warn?: boolean
  /** 0348: Buy & sell — the city the buy is sold at. */
  sellAt?: string | null
  /** The units row: the stepper, or why there is none. */
  units: ReactNode
  /** 0506, 0507: the bargain's press and the tax in a purchase, under the units (docked only). */
  deal?: ReactNode
  /** 0490: a sale's lines (Bought, Sells for, the costs, Profit): above the units on a sale, under them on a buy-and-sell trip;
   *  before the chart either way. */
  sale?: ReactNode
  /** 0490: a sale's two unit prices, pinned with the button (what she paid a unit, what it sells for a unit): seen at every height
   *  of the sheet, beside the money and the profit under them. Undefined: no sale. */
  pair?: { bought: number | null; sells: number | null }
  /** The money the units come to, signed (−paid / +got), or null while unknown. */
  total: number | null
  /** Rows under the total (the trip's estimate). */
  extra?: ReactNode
  /** The server's refusal of the last press, pinned above the button. */
  refusal?: Refusal | null
  /** A trip that sells: its served profit (null while unknown), on the money's line, pinned above the fold. Undefined: no sale. */
  profit?: number | null
  button: ReactNode
  /** Under everything (the voyage's reach). */
  after?: ReactNode
}) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const price = good.price
  const trend = usePriceSeries(portId, good.good_id)
  const day = usePriceSeries(portId, good.good_id, '1d')
  const line = dayLine(day.series, side, price)
  const why = usePriceWhy(portId, good.good_id)
  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={good.name}
      mode={mode}
      action={
        <>
          {/* THE MONEY rides with the button, pinned: the figure a trade is decided on never scrolls apart from it */}
          {/* 2026-11-11 (the trade-flow slice): a buy's money is its COST, unsigned; it stood as "Total −856", the way a loss is drawn */}
          {/* 2026-11-22 (P0): A TRIP THAT SELLS CARRIES ITS PROFIT ON THE SAME LINE ("Cost 36,244 · Profit +3,222"). It stood fifth
              in the estimate, under the chart: under the fold of a 390 × 844 sheet, so the number a trip is chosen by was never seen
              before the press. One line, not a row of its own, so the half-raised sheet still shows the units. */}
          {/* 0490: A SALE'S TWO PRICES, pinned above it (the owner, 2026-11-24: "the price i bought, the price i will get"): the half-raised
              sheet at 390 x 844 showed the sale's lines only to the fold (measured), so the two unit prices ride with the money */}
          {/* 0497: THE PRESS'S REFUSAL stands where the two prices stood, by the button that earned it: under the chart (`extra`) a
              half-raised sheet at 390 x 844 never showed it, and "Sold today's limit" read as a press that did nothing */}
          {refusal ? (
            <Note tone="danger" code={refusal.code} figures={refusal.figures} sea={seaWallOf(refusal)} data-testid="trade-tray-refusal">
              {refusal.sentence}
            </Note>
          ) : pair && (
            <div className="flex flex-wrap items-baseline justify-between gap-x-4 pt-1 text-t-caption" data-testid="sale-pair">
              <span className="inline-flex items-baseline gap-1.5">
                <span className="text-ink-muted">{t('trade.bought')}</span>
                <span className="font-semibold tabular-nums text-ink" data-testid="sale-pair-bought">
                  {pair.bought === null ? '—' : formatPrice(pair.bought)}
                </span>
              </span>
              <span className="inline-flex items-baseline gap-1.5">
                <span className="text-ink-muted">{t('trade.sellsFor')}</span>
                <span className="font-semibold tabular-nums text-ink" data-testid="sale-pair-sells">
                  {pair.sells === null ? '—' : formatPrice(pair.sells)}
                </span>
              </span>
            </div>
          )}
          <Row
            // the word whole (2026-11-22 second play-test: in the 1,280 desk's pane the figure and the profit left "Cost" 16 px, and it
            // stood as "Co / st"); whole, the line still fits that pane (measured 286 of 286 px, nothing past the row)
            label={<span className="whitespace-nowrap">{total === null ? t('desk.total') : moneyWord(side === 'buy' ? 'cost' : 'total', total)}</span>}
            value={
              <span className="inline-flex items-baseline gap-2">
                <Figure value={total === null ? '—' : moneyFigure(side === 'buy' ? 'cost' : 'total', total)} size="figure" tone={total === null ? 'faint' : profit !== undefined && profit !== null && profit > 0 ? 'success' : 'ink'} />
                {profit !== undefined && (
                  <span className="inline-flex items-baseline gap-1" data-testid="trade-profit">
                    <span className="text-t-caption text-ink-muted">{t('desk.profit')}</span>
                    <span className={`font-semibold tabular-nums ${profit === null ? 'text-ink-faint' : profit >= 0 ? 'text-success' : 'text-danger'}`}>
                      {profit !== null ? formatPriceDelta(profit) : '—'}
                    </span>
                  </span>
                )}
              </span>
            }
            hairline={false}
            data-testid="good-detail-total"
          />
          {button}
        </>
      }
      data-testid="good-detail"
      data-good={good.code}
      data-side={side}
      data-city={city}
      data-sell-at={sellAt ?? undefined}
    >
      <div className={`${WRAP_ROW_CLASS} pt-1`}>
        <span className="text-t-caption text-ink-muted" data-testid="good-detail-city">
          <PortFlag code={city} /> {portNameOf(portByCode, city)}
        </span>
        <GoodKind category={good.category} rarity={good.rarity} goodClass={good.class} />
      </div>
      {/* P1: WHERE TO SELL — the best three, FIRST under the city line: a half-raised sheet at 390 x 844 shows them before
          the press (under the units they stood below the fold). The open one lit; pressed, the same trip to that city. */}
      {choices && sellAt !== null && onChoose && <SellChoices choices={choices} sellAt={sellAt} onChoose={onChoose} />}
      <Row
        label={t(side === 'buy' ? 'desk.buy' : 'desk.sell')}
        value={
          <span className="inline-flex items-baseline gap-2">
            <Figure value={formatPriceFigure(price)} size="figure" />
            <DayChange change={line.change} side={side} />
          </span>
        }
        data-testid="good-detail-price"
      />
      <Row label={t('desk.aboardLabel')} value={<Figure value={formatInt(fleetCargoByCode(fleet)[good.code] ?? 0)} />} data-testid="good-detail-aboard" />
      {/* 0348: before the units (and their Max), when no sale pays */}
      {warn && (
        <Note tone="warning" className="mt-2" data-testid="trade-no-gain">
          {t('desk.noGainWarn')}
        </Note>
      )}
      {/* the units first, where a half-raised sheet shows them; the chart they are read against under them. 0490 (the owner, 2026-11-24:
          "when i sell, i want to see the price i bought, the price i will get, how much profit"): ON A SALE the sale's lines stand
          ABOVE the units: under them, a half-raised sheet at 390 x 844 cut them off (measured: the stepper's row ended at the fold),
          and a sale's units are all she carries by default. Decided by default. A buy-and-sell trip keeps its units first. */}
      {side === 'sell' && sale}
      {units}
      {deal}
      {side !== 'sell' && sale}
      <Chart name={good.name} trend={trend} portId={portId} goodId={good.good_id} />
      {extra}
      <WhyThisPrice why={why.view ?? null} loading={why.loading} />
      <CityGoodTrades portId={portId} goodId={good.good_id} refresh={fleet.version} />
      {after}
    </Tray>
  )
}

/** THE BIGGER CHART: the span picker and the compact PriceChart over the chosen span. */
function Chart({ name, trend, portId, goodId }: { name: string; trend: ReturnType<typeof usePriceSeries>; portId: string; goodId: string }) {
  const t = useT()
  const [openedAt] = useState(() => Date.now())
  const points = trend.series?.points ?? []
  // 0347 (owner row 216): this city's news of this good and the world's headlines, a dot each on the time axis; a press opens the card
  const news = useChartNews('price', portId, goodId, firstAtMs(points.map((p) => ({ atMs: Date.parse(p.at) }))))
  const values = points.map((p) => p.ask ?? p.bid)
  return (
    <div className="py-2" data-testid="trend-row">
      <SpanPicker value={trend.span} onChange={trend.setSpan} />
      {trend.series === undefined ? (
        <Skeleton className="mt-2 h-40 w-full" />
      ) : points.length < 2 ? (
        <span className="mt-2 block h-10 text-t-caption text-ink-faint" data-testid="trend-empty">
          {t('ui.noData')}
        </span>
      ) : (
        <div className="mt-2">
          <PriceChart
            points={points}
            slotSeconds={(trend.series as PriceSeries).step_seconds}
            nowMs={openedAt}
            compact
            news={news.news}
            label={t('ui.pastPricesAxis', { name, n: values.length, lo: formatPriceFigure(Math.min(...values)), hi: formatPriceFigure(Math.max(...values)) })}
          />
        </div>
      )}
      {news.card}
    </div>
  )
}

/** THE ONE BIG BUTTON — same place, same size, same colour on all four acts. */
function BigButton({ act, label, disabled, busy, onClick }: { act: string; label: string; disabled: boolean; busy: boolean; onClick: () => void }) {
  const t = useT()
  return (
    <Button
      variant="primary"
      className="min-h-14 w-full text-t-title active:scale-[0.98]"
      onClick={onClick}
      disabled={disabled}
      busy={busy}
      busyLabel={t('ui.sending')}
      data-testid="trade-act"
      data-act={act}
    >
      {label}
    </Button>
  )
}

/** DOCKED AT THIS CITY: the trade itself, now (useTrade → cmd.issue — the act the quay's tray issues). */
function DockedAct({
  side,
  fleet,
  portId,
  city,
  good,
  noGain,
  mode,
  onClose,
  onDone,
}: {
  side: 'buy' | 'sell'
  fleet: FleetView
  portId: string
  city: string
  good: MarketGood
  noGain: boolean
  mode: TrayMode
  onClose: () => void
  onDone: (done: TradeDone) => void
}) {
  const t = useT()
  const [qty, setQty] = useState<number | null>(null)
  const sent = useRef<{ units: number; total: number | null } | null>(null)
  const aboard = fleetCargoByCode(fleet)[good.code] ?? 0
  // 0497: selling all she carries is the grammar's ALL (the quay's day limit cuts it; the bare number over the limit is refused whole)
  const trade = useTrade(fleet, side, good, qty, () => {
    const s = sent.current
    onDone({ side, units: s?.units ?? qty ?? 0, good: good.name, total: s?.total ?? null, sailTo: null })
  }, undefined, side === 'sell' && qty !== null && qty > 0 && qty === aboard)
  const { capacity, step, act } = trade
  const lot = Math.max(1, Math.round(step))
  const ceiling = side === 'buy' ? (capacity.bound?.max ?? 0) : aboard
  const ducats = useWorld((s) => s.ducats)
  // Sell: all she carries by default, as Sail & sell sells it (owner row 231: one press sells right here)
  const chosen = Math.min(qty ?? (side === 'sell' ? ceiling : firstBuy(ceiling, ducats, good.buy)), ceiling)
  // the default (Buy: `firstBuy`, what half her coin buys or the most she can, the smaller) and the clamp when the ceiling moves, written back in
  // place (derive-from-the-last-render) so the quantity previewed is the quantity on the button
  if (ceiling > 0 && qty !== chosen) setQty(chosen)
  const refused = side === 'buy' && (good.available === false || good.offered === false)
  const live = !act.sending && chosen > 0 && act.ready && !refused
  const total = act.total === null ? null : side === 'buy' ? -act.total : act.total
  // 0490: THE SALE BEFORE THE PRESS — the dry run of exactly this sale (cmd.do_sell, rolled back): what she paid, what she gets,
  // the tax, wages and dock fee as the sale counts them, and its one profit (`trip_net`, the SOLD event's). Nothing is added up here.
  const sale = side === 'sell' && chosen > 0 ? act.preview : null
  return (
    <Frame
      side={side}
      fleet={fleet}
      portId={portId}
      city={city}
      good={{ ...good, price: side === 'buy' ? good.buy : good.sell }}
      mode={mode}
      onClose={onClose}
      warn={side === 'buy' && noGain}
      total={chosen > 0 ? total : null}
      profit={side === 'sell' ? (act.previewLoading ? null : (sale?.trip_net ?? null)) : undefined}
      pair={side === 'sell' ? { bought: sale?.cost ?? null, sells: sale?.total ?? null } : undefined}
      units={
        ceiling > 0 ? (
          <div className="py-3">
            <Stepper
              value={chosen}
              onChange={setQty}
              max={side === 'buy' ? Math.max(ceiling, Math.floor(good.stock)) : aboard}
              cap={ceiling}
              min={1}
              step={1}
              lot={lot}
              unit={t('ui.unitUnits')}
              label={t('ui.unitsOf', { good: good.name })}
              presets={[{ label: t('desk.max'), value: ceiling }]}
              data-testid="trade-tray-qty"
            />
          </div>
        ) : (
          <Row
            label={t('desk.units')}
            tone="muted"
            value={side === 'sell' ? t('desk.holdEmpty') : capacity.loading ? t('ui.checkingMax') : t('ui.maxUnknown')}
            data-testid="trade-units-none"
          />
        )
      }
      deal={
        <>
          {/* 0507: what of the cost is the city's tax, as the dry run counted it (nothing while it is 0) */}
          {side === 'buy' && act.preview !== null && (act.preview.tax_total ?? 0) > 0 && (
            <Row label={t('desk.taxIn')} value={<Figure value={formatPrice(act.preview.tax_total ?? 0)} tone={act.previewLoading ? 'faint' : 'ink'} />} data-testid="buy-tax" />
          )}
          {chosen > 0 && <BargainPress key={`${good.code}:${side}`} fleet={fleet.id} goodId={good.good_id} code={good.code} side={side} />}
        </>
      }
      sale={
        side === 'sell' && chosen > 0 ? (
            <SaleLines
              boughtEach={sale?.basis ?? null}
              cost={sale?.cost ?? null}
              sellEach={sale?.avg_price ?? null}
              tax={sale?.tax ?? null}
              wages={sale?.wages ?? null}
              dockFee={sale?.dock_fee ?? null}
              profit={sale?.trip_net ?? null}
              dim={act.previewLoading}
            />
        ) : undefined
      }
      refusal={act.refusal}
      button={
        <BigButton
          act={side}
          label={t(side === 'buy' ? 'desk.buy' : 'desk.sell')}
          disabled={!live}
          busy={act.sending}
          onClick={() => {
            // the served total for these units: the settled one, else the last dry run when it was for this count
            sent.current = { units: chosen, total: act.total ?? (act.preview?.qty === chosen ? act.preview.total : null) }
            act.send()
          }}
        />
      }
    />
  )
}

/** NOT DOCKED HERE: the trip there — Sail & buy (SAIL … / BUY) or Sail & sell (SAIL … / SELL ALL), one press. */
function SailAct({
  side,
  fleet,
  portId,
  city,
  good,
  sellAt,
  noGain,
  choices,
  onChoose,
  trip,
  mode,
  onClose,
  onDone,
}: SaleChoice & {
  side: 'buy' | 'sell'
  fleet: FleetView
  portId: string
  city: string
  good: PanelGood
  /** 0348: Buy & sell — the city the buy is sold at; null for Sail & buy / Sail & sell. */
  sellAt: string | null
  noGain: boolean
  trip: Trip
  mode: TrayMode
  onClose: () => void
  onDone: (done: TradeDone) => void
}) {
  const t = useT()
  const plan = useDeskPlan((s) => s.plan)
  const set = useDeskPlan((s) => s.set)
  const b = trip.board
  const aboard = fleetCargoByCode(fleet)[good.code] ?? 0
  // the plan for THIS good and THIS city (BuySell.tsx opens it); until it stands, the panel waits for it
  const mine =
    plan && plan.good === good.code && (side === 'buy' ? plan.buyAt === city && plan.sellAt === sellAt : plan.sellAt === city && plan.buyAt === null) ? plan : null
  // the sale's rows (wages, dues, profit): Sail & sell, and Buy & sell (0348) — the served sell row either way
  const sells = side === 'sell' || sellAt !== null
  const go = useTripGo({
    fleet,
    plan: mine ?? { good: good.code, buyAt: null, sellAt: null, units: null, max: null, min: null },
    board: mine ? b : null,
    units: trip.units,
    onQueued: () => onDone({ side, units: side === 'buy' ? (mine?.units ?? cap ?? 0) : aboard, good: good.name, total: total, sailTo: sellAt ?? city, profit }),
  })
  // THE MOST SHE CAN TAKE THERE: the board sized by her free hold (asked for no units), kept while units are asked
  const capNow = b && (b.qty.basis === 'capacity' || b.qty.basis === 'step') ? b.qty.units : null
  const [cap, setCap] = useState<number | null>(null)
  if (capNow !== null && capNow !== cap) setCap(capNow)
  // THE FIRST COUNT, as the docked tray's (`firstBuy`: what half her coin buys, or all she can take when that is less) — written
  // into the plan once the board has sized her hold, so Go buys exactly the units the board priced; Max asks for all she can take
  const step = useWorld((st) => st.snapshot?.config.trade_step_tuns ?? 1)
  const lot = Math.max(1, Math.round(step))
  const ducats = useWorld((st) => st.ducats)
  const firstCount = side === 'buy' && mine !== null && mine.units === null && cap !== null && cap > 0 ? firstBuy(cap, ducats, good.price) : null
  useEffect(() => {
    if (firstCount !== null) set({ units: firstCount })
  }, [firstCount, set])

  const units = side === 'buy' ? (mine?.units ?? cap) : aboard
  // the money: the buy row's cost for the units asked (not when the board priced what is aboard instead), or the
  // sale's proceeds for what is aboard
  const total =
    side === 'buy'
      ? go.buyRow && b?.qty.basis !== 'on_board'
        ? -go.buyRow.cost
        : null
      : (go.sellRow?.proceeds ?? null)
  const profit = sells ? (go.sellRow?.profit ?? null) : null
  const label = go.stop ?? t(sellAt !== null ? 'desk.buySell' : side === 'buy' ? 'desk.sailBuy' : 'desk.sailSell')
  return (
    <Frame
      side={side}
      fleet={fleet}
      portId={portId}
      city={city}
      good={good}
      mode={mode}
      onClose={onClose}
      warn={side === 'buy' && noGain}
      sellAt={sellAt}
      choices={choices}
      onChoose={onChoose}
      total={mine ? total : null}
      profit={sells ? profit : undefined}
      pair={sells ? { bought: go.sellRow?.cost ?? null, sells: go.sellRow?.proceeds ?? null } : undefined}
      sale={
        sells && mine ? (
          // 0490: the trip's sale, as the served sell row counts it (supplies on their own row below, as before)
          <SaleLines
            boughtEach={side === 'sell' ? paidPerTun(fleet, good.code) : (go.buyRow?.price_each ?? null)}
            cost={go.sellRow?.cost ?? null}
            sellEach={go.sellRow?.price_each ?? null}
            tax={go.sellRow?.profit_tax ?? null}
            wages={go.sellRow?.wages ?? null}
            dockFee={go.sellRow ? dockFeeOf(go.sellRow) : null}
            dockNote={go.sellRow?.dues ? taxFactorWords(go.sellRow.dues) : null}
            profit={profit}
          />
        ) : undefined
      }
      units={
        units !== null && units > 0 ? (
          <div className="py-3">
            <Stepper
              value={units}
              onChange={(n) => (side === 'buy' ? set({ units: n }) : undefined)}
              max={side === 'buy' ? (cap ?? units) : aboard}
              min={side === 'buy' ? 1 : aboard}
              step={1}
              lot={side === 'buy' ? lot : undefined}
              unit={t('ui.unitUnits')}
              label={t('ui.unitsOf', { good: good.name })}
              presets={[{ label: t('desk.max'), value: side === 'buy' ? (cap ?? units) : aboard }]}
              data-testid="trade-tray-qty"
            />
          </div>
        ) : (
          <Row
            label={t('desk.units')}
            tone="muted"
            value={side === 'sell' ? t('desk.holdEmpty') : trip.loading ? '…' : t('desk.unitsAll')}
            data-testid="trade-units-none"
          />
        )
      }
      extra={
        <div data-testid="plan-estimate">
          <Row label={t('desk.time')} value={<Figure value={go.days !== null ? formatDaysReal(go.days) : '—'} />} data-testid="plan-days" />
          <Row
            label={t('desk.supplies')}
            value={<Figure value={go.supplies ? formatPriceDelta(-go.supplies.cost) : '—'} tone={go.supplies && !go.supplies.fits ? 'danger' : 'ink'} />}
            data-testid="plan-supplies"
          />
          {go.onCredit > 0 && (
            <Row label={t('desk.onCredit')} value={<Figure value={formatPriceDelta(-go.onCredit)} tone="warning" />} data-testid="plan-on-credit" />
          )}
          {/* 0475: THE SECOND GOOD (a Trade card's `top`): one line, ticked; the one press buys and sells both. Only for the units it was
              served for: the room and the coin it was sized to go when the first count moves. */}
          {sellAt !== null && mine?.also && mine.units === mine.also.with && (
            <AlsoLine also={mine.also} onToggle={() => mine.also && set({ also: { ...mine.also, on: !mine.also.on } })} />
          )}
          <div className="mt-2 flex items-center gap-3">
            <Chip on={mine?.insure === true} onClick={() => set({ insure: !mine?.insure })} className="shrink-0 whitespace-nowrap" data-testid="plan-insure">
              {t('desk.insure')}
            </Chip>
            <Hint className="mt-0">{mine?.insure ? t('desk.insuredHint') : t('desk.uninsuredHint')}</Hint>
          </div>
          {/* 0477: her standing order when raiders close, one press (drawn only while the early sighting is lit) */}
          <IfAttacked fleetId={fleet.id} />
          {go.noCourse && (
            <Note tone="danger" className="mt-3">
              {t('desk.noWater', { port: portNameOf(useWorld.getState().portByCode, go.noCourse) })}
            </Note>
          )}
          {fleet.ready_at && !fleet.voyage && <ReadyIn at={fleet.ready_at} />}
          {go.refusal && (
            <Note tone="danger" className="mt-3" code={go.refusal.code} figures={go.refusal.figures} sea={seaWallOf(go.refusal)}>
              {go.refusal.sentence}
            </Note>
          )}
          {/* row 231: a button that will not press says why, in a sentence, and what to do */}
          {mine && !go.refusal && go.why && (
            <Note tone="warning" className="mt-3" data-testid="trade-why">
              {go.why}
            </Note>
          )}
        </div>
      }
      button={<BigButton act={sellAt !== null ? 'buy-sell' : side === 'buy' ? 'sail-buy' : 'sail-sell'} label={label} disabled={!mine || !go.ready} busy={go.pending} onClick={go.go} />}
      after={mine ? <PlanVoyage fleet={fleet} board={b} buyRow={go.buyRow} sellRow={go.sellRow} /> : undefined}
    />
  )
}

/** THE BUY SHEET'S FIRST COUNT (2026-11-22, P0 of docs/design/playable-2026-11-22.md; decided by default): the most she can take
 *  (`most`: the served bound, her free hold and her purse) or what HALF her coin buys at this price, whichever is smaller, and at
 *  least one. The sheet opened at one lot, and where the lot was more than she could take, at everything: a new company's first
 *  press spent 39,370 of its 40,000 and left nothing for the next trip. Max still asks for all. Coin or price unknown: `most`. */
function firstBuy(most: number, ducats: number | null, price: number | null | undefined): number {
  if (ducats === null || price == null || !(price > 0)) return most
  return Math.max(1, Math.min(most, Math.floor(ducats / 2 / price)))
}

/** 0475: THE SECOND GOOD'S LINE: a tick ("Also load") and the good, its units and the served profit (sale less buy, tax and the dock fee it
 *  adds). Nothing is priced here. */
function AlsoLine({ also, onToggle }: { also: NonNullable<PlanDraft['also']>; onToggle: () => void }) {
  const t = useT()
  const goodByCode = useWorld((s) => s.goodByCode)
  const name = properName('good', also.good, goodByCode[also.good]?.name ?? also.good)
  return (
    <div className={PLAN_LINE_CLASS} data-testid="plan-also" data-good={also.good} data-units={also.units} data-on={also.on}>
      <Chip on={also.on} onClick={onToggle} className="shrink-0 whitespace-nowrap" data-testid="plan-also-tick">
        {t('desk.alsoLoad')}
      </Chip>
      <span className="text-t-caption text-ink" data-testid="plan-also-good">
        {name} {formatInt(also.units)}
      </span>
      <span className={`ml-auto text-t-caption font-semibold tabular-nums ${also.on ? 'text-success' : 'text-ink-faint'}`} data-testid="plan-also-profit">
        {formatPriceDelta(also.profit)}
      </span>
    </div>
  )
}

/** THE TRIP'S DOCK FEE: the served row's own `dock_fee` (0361: every harbour she calls at, the last included; it is in the profit
 *  under it). A world before 0361 serves no `dock_fee`: the destination's fee, as it was printed then. Nothing is added up here. */
function dockFeeOf(row: BoardSellRow): number | null {
  return row.dock_fee !== undefined ? row.dock_fee : (row.dues?.fee ?? row.port_fee)
}

/** 0490: THE SALE, LINE BY LINE, BEFORE THE PRESS (the owner, 2026-11-24: "when i sell, i want to see the price i bought, the price i
 *  will get, how much profit earn and such"). Figures first, a word or two each: Bought (each, total), Sells for (each, total), the
 *  tax, wages and dock fee the sale pays (each only when not 0), and Profit: the served one profit, green or red, with its share of
 *  the cost. Every figure is handed in served (the sale's dry run, or the trip's sell row); the percent is the one ratio drawn here. */
function SaleLines({
  boughtEach,
  cost,
  sellEach,
  tax,
  wages,
  dockFee,
  dockNote = null,
  profit,
  dim = false,
}: {
  boughtEach: number | null
  cost: number | null
  sellEach: number | null
  tax: number | null
  wages: number | null
  dockFee: number | null
  /** The destination's tax factor words beside a trip's dock fee (closed economy). */
  dockNote?: string | null
  profit: number | null
  /** The figures are the last served, not yet for the units on the button. */
  dim?: boolean
}) {
  const t = useT()
  // ONE PLACE A FIGURE (2026-11-25): the sums (what it cost, what it sells for) ride with the button; here stand the two unit prices
  const unit = (n: number | null) => <Figure value={n === null ? '—' : formatPriceFigure(n)} />
  const cut = (n: number | null, label: string, testid: string, note: string | null = null) =>
    n !== null && n !== 0 ? (
      <Row label={label} value={<Figure value={note ? `${formatPriceDelta(-n)} · ${note}` : formatPriceDelta(-n)} />} data-testid={testid} />
    ) : null
  return (
    <div className={`pb-1 transition-opacity ${dim ? 'opacity-60' : ''}`} data-testid="sale-lines" data-profit={profit ?? undefined}>
      <Row label={t('trade.boughtEach')} value={unit(boughtEach)} data-testid="sale-bought" data-each={boughtEach ?? undefined} />
      <Row label={t('trade.sellsEach')} value={unit(sellEach)} data-testid="sale-sells" data-each={sellEach ?? undefined} />
      {cut(tax, t('desk.tax'), 'sale-tax')}
      {cut(wages, t('desk.wages'), 'sale-wages')}
      {cut(dockFee, t('desk.dockFee'), 'sale-dock', dockNote)}
      <Row
        label={t('desk.profit')}
        value={
          <span className="inline-flex items-baseline gap-1.5 tabular-nums">
            <Figure value={profit === null ? '—' : formatPriceDelta(profit)} size="figure" tone={profit === null ? 'faint' : profit >= 0 ? 'success' : 'danger'} />
            {profit !== null && cost !== null && cost > 0 && (
              <span className={`text-t-caption ${profit >= 0 ? 'text-success' : 'text-danger'}`} data-testid="sale-profit-pct">
                {formatPctDelta(profit / cost)}
              </span>
            )}
          </span>
        }
        hairline={false}
        data-testid="sale-profit"
      />
    </div>
  )
}

/** 0237: "Ready in 0:42" while she is in her port time — a live countdown to the served `ready_at`. */
function ReadyIn({ at: readyAt }: { at: string }) {
  const t = useT()
  const { nowMs } = useShellState()
  const at = instantMs(readyAt)
  if (at === null || at <= nowMs) return null
  return (
    <Hint className="mt-2" data-testid="trade-ready-in">
      {t('domain.readyIn', { t: formatCountdown(at - nowMs) })}
    </Hint>
  )
}

/** THE PLACES TO SELL (P1, 2026-11-22): one pressable line each — the city, the trip's time, the served profit — the open
 *  one lit. The rows are the trip's own board's (saleChoice.ts); nothing is priced here. */
function SellChoices({ choices, sellAt, onChoose }: { choices: BoardSellRow[]; sellAt: string; onChoose: (port: string) => void }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  return (
    <div className="pt-2 pb-1" role="radiogroup" aria-label={t('desk.sellWhere')} data-testid="trade-sale-choices">
      <p className="pb-1 text-t-caption text-ink-muted">{t('desk.sellWhere')}</p>
      <ul className="flex flex-col gap-1">
        {choices.map((r) => {
          const on = r.port === sellAt
          return (
            <li key={r.port}>
              <button
                type="button"
                role="radio"
                aria-checked={on}
                onClick={() => onChoose(r.port)}
                className={[
                  // ONE WRAPPING LINE, as a cargo place (CargoBest.tsx): the city whole, its figures at the right
                  'flex min-h-11 w-full flex-wrap items-center gap-x-3 rounded px-2 py-1.5 text-left transition active:scale-[0.99]',
                  on ? 'bg-accent-soft ring-1 ring-accent' : 'bg-surface-2',
                ].join(' ')}
                data-testid="trade-sale-choice"
                data-port={r.port}
                data-on={on}
              >
                <span className="flex-1 basis-36 text-t-caption text-ink" data-testid="trade-sale-choice-name">
                  <PortFlag code={r.port} /> {portNameOf(portByCode, r.port)}
                </span>
                <span className="ml-auto flex shrink-0 items-baseline gap-x-3">
                  <span className="text-t-caption tabular-nums text-ink-muted" data-testid="trade-sale-choice-time">
                    {r.days == null ? '—' : formatDaysReal(r.days)}
                  </span>
                  <span className="text-t-caption font-semibold tabular-nums text-success" data-testid="trade-sale-choice-profit">
                    {r.profit == null ? '—' : formatPriceDelta(r.profit)}
                  </span>
                </span>
              </button>
            </li>
          )
        })}
      </ul>
    </div>
  )
}

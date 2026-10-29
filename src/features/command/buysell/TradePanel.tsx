import { useEffect, useRef, useState, type ReactNode } from 'react'
import { Button, Chip, Figure, GoodKind, Hint, Note, PriceChart, Row, Skeleton, SpanPicker, Stepper, Tray, type TrayDetent, type TrayMode } from '../../../components/ui'
import { fleetCargoByCode } from '../../../domain/fleet'
import { taxFactorWords } from '../../../domain/port'
import { CityGoodTrades } from '../../../live/CityGoodTrades'
import { PortFlag } from '../../../live/PortFlag'
import { usePriceWhy } from '../../../live/useDesk'
import { useNewsMarks } from '../../../live/useNewsMarks'
import { usePriceSeries } from '../../../live/usePriceSeries'
import { useTrade } from '../../../live/useTrade'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { useShellState } from '../../../app/shellState'
import { formatCountdown, formatInt, formatPriceDelta, formatPriceFigure, formatVoyageDays, instantMs } from '../../../lib/format'
import type { FleetView, MarketGood, PriceSeries } from '../../../lib/rpc'
import { useT } from '../../../lib/i18n'
import { WhyThisPrice } from '../markets/WhyThisPrice'
import { useDeskPlan } from '../plans/planDraft'
import { PlanVoyage } from '../plans/PlanVoyage'
import { useTripGo } from '../plans/useTripGo'
import type { useTripBoard } from '../plans/useTripBoard'
import { DayChange } from './CityBoard'
import { dayLine } from './dayLine'
import type { TradeDone } from './tradeDone'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRADE PANEL — ONE GOOD AT ONE CITY, THE SAME PANEL ON BUY AND ON SELL (owner row 229, 2026-10-26)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"for buying and selling i want both to be... similar mechanism. similar screen, buttons to press etc."* A card
// pressed on the city's board (CityBoard.tsx) opens this, top to bottom, on both faces:
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
  price: number
}

export function TradePanel({
  side,
  fleet,
  city,
  good,
  market,
  docked,
  trip,
  mode,
  onClose,
  onDone,
}: {
  side: 'buy' | 'sell'
  fleet: FleetView
  /** The city in hand (port CODE), the good and the side's price there. */
  city: string
  good: PanelGood
  /** The city's market row for the good — what DockedAct trades through; null where the quay lists none. */
  market: MarketGood | null
  /** She lies at this city. */
  docked: boolean
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
    market && <DockedAct side={side} fleet={fleet} portId={port.id} city={city} good={market} mode={mode} onClose={onClose} onDone={onDone} />
  ) : (
    <SailAct side={side} fleet={fleet} portId={port.id} city={city} good={good} trip={trip} mode={mode} onClose={onClose} onDone={onDone} />
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
  units,
  total,
  extra,
  button,
  after,
}: {
  side: 'buy' | 'sell'
  fleet: FleetView
  portId: string
  city: string
  good: PanelGood
  mode: TrayMode
  onClose: () => void
  /** The units row: the stepper, or why there is none. */
  units: ReactNode
  /** The money the units come to, signed (−paid / +got), or null while unknown. */
  total: number | null
  /** Rows under the total (the trip's estimate). */
  extra?: ReactNode
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
          <Row
            label={t('desk.total')}
            value={<Figure value={total === null ? '—' : formatPriceDelta(total)} size="figure" tone={total === null ? 'faint' : total >= 0 ? 'success' : 'ink'} />}
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
    >
      <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 pt-1">
        <span className="text-t-caption text-ink-muted" data-testid="good-detail-city">
          <PortFlag code={city} /> {portNameOf(portByCode, city)}
        </span>
        <GoodKind category={good.category} rarity={good.rarity} />
      </div>
      <Row
        label={t(side === 'buy' ? 'desk.buy' : 'desk.sell')}
        value={
          <span className="inline-flex items-baseline gap-2">
            <Figure value={formatPriceFigure(price)} size="figure" />
            <DayChange change={line.change} />
          </span>
        }
        data-testid="good-detail-price"
      />
      <Row label={t('desk.aboardLabel')} value={<Figure value={formatInt(fleetCargoByCode(fleet)[good.code] ?? 0)} />} data-testid="good-detail-aboard" />
      {/* the units first, where a half-raised sheet shows them; the chart they are read against under them */}
      {units}
      <Chart name={good.name} portId={portId} goodId={good.good_id} trend={trend} />
      {extra}
      <WhyThisPrice why={why.view ?? null} loading={why.loading} />
      <CityGoodTrades portId={portId} goodId={good.good_id} refresh={fleet.version} />
      {after}
    </Tray>
  )
}

/** THE BIGGER CHART: the span picker and the compact PriceChart over the chosen span, with the chart's
 *  news dots (0279) over the same window the chart draws. */
function Chart({
  name,
  portId,
  goodId,
  trend,
}: {
  name: string
  portId: string
  goodId: string
  trend: ReturnType<typeof usePriceSeries>
}) {
  const t = useT()
  const [openedAt] = useState(() => Date.now())
  const points = trend.series?.points ?? []
  const values = points.map((p) => p.ask ?? p.bid)
  const ats = points.map((p) => Date.parse(p.at)).filter((n) => Number.isFinite(n))
  const marks = useNewsMarks(
    'price',
    portId,
    goodId,
    points.length >= 2 && ats.length >= 2 ? Math.min(...ats) : null,
    points.length >= 2 && ats.length >= 2 ? Math.max(openedAt, Math.max(...ats)) : null,
  )
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
            marks={marks}
            label={t('ui.pastPricesAxis', { name, n: values.length, lo: formatPriceFigure(Math.min(...values)), hi: formatPriceFigure(Math.max(...values)) })}
          />
        </div>
      )}
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
  mode,
  onClose,
  onDone,
}: {
  side: 'buy' | 'sell'
  fleet: FleetView
  portId: string
  city: string
  good: MarketGood
  mode: TrayMode
  onClose: () => void
  onDone: (done: TradeDone) => void
}) {
  const t = useT()
  const [qty, setQty] = useState<number | null>(null)
  const sent = useRef<{ units: number; total: number | null } | null>(null)
  const trade = useTrade(fleet, side, good, qty, () => {
    const s = sent.current
    onDone({ side, units: s?.units ?? qty ?? 0, good: good.name, total: s?.total ?? null, sailTo: null })
  })
  const { capacity, step, act } = trade
  const aboard = fleetCargoByCode(fleet)[good.code] ?? 0
  const lot = Math.max(1, Math.round(step))
  const ceiling = side === 'buy' ? (capacity.bound?.max ?? 0) : aboard
  // Sell: all she carries by default, as Sail & sell sells it (owner row 231: one press sells right here)
  const chosen = Math.min(qty ?? (side === 'sell' ? ceiling : Math.min(ceiling, lot)), ceiling)
  // the default (Buy: one lot, or all she can when that is less) and the clamp when the ceiling moves, written back in
  // place (derive-from-the-last-render) so the quantity previewed is the quantity on the button
  if (ceiling > 0 && qty !== chosen) setQty(chosen)
  const refused = side === 'buy' && (good.available === false || good.offered === false)
  const live = !act.sending && chosen > 0 && act.ready && !refused
  const total = act.total === null ? null : side === 'buy' ? -act.total : act.total
  return (
    <Frame
      side={side}
      fleet={fleet}
      portId={portId}
      city={city}
      good={{ ...good, price: side === 'buy' ? good.buy : good.sell }}
      mode={mode}
      onClose={onClose}
      total={chosen > 0 ? total : null}
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
      extra={
        act.refusal ? (
          <Note tone="danger" code={act.refusal.code} figures={act.refusal.figures} data-testid="trade-tray-refusal">
            {act.refusal.sentence}
          </Note>
        ) : undefined
      }
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
  trip,
  mode,
  onClose,
  onDone,
}: {
  side: 'buy' | 'sell'
  fleet: FleetView
  portId: string
  city: string
  good: PanelGood
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
  const mine = plan && plan.good === good.code && (side === 'buy' ? plan.buyAt === city && plan.sellAt === null : plan.sellAt === city && plan.buyAt === null) ? plan : null
  const go = useTripGo({
    fleet,
    plan: mine ?? { good: good.code, buyAt: null, sellAt: null, units: null, max: null, min: null },
    board: mine ? b : null,
    units: trip.units,
    onQueued: () => onDone({ side, units: side === 'buy' ? (mine?.units ?? cap ?? 0) : aboard, good: good.name, total: total, sailTo: city }),
  })
  // THE MOST SHE CAN TAKE THERE: the board sized by her free hold (asked for no units), kept while units are asked
  const capNow = b && (b.qty.basis === 'capacity' || b.qty.basis === 'step') ? b.qty.units : null
  const [cap, setCap] = useState<number | null>(null)
  if (capNow !== null && capNow !== cap) setCap(capNow)
  // THE FIRST COUNT, as the docked tray's: one lot, or all she can take when that is less — written into the plan
  // once the board has sized her hold, so Go buys exactly the units the board priced; Max asks for all she can take
  const step = useWorld((st) => st.snapshot?.config.trade_step_tuns ?? 1)
  const lot = Math.max(1, Math.round(step))
  const firstCount = side === 'buy' && mine !== null && mine.units === null && cap !== null && cap > 0 ? Math.min(cap, lot) : null
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
  const profit = side === 'sell' ? (go.sellRow?.profit ?? null) : null
  const label = go.stop ?? t(side === 'buy' ? 'desk.sailBuy' : 'desk.sailSell')
  return (
    <Frame
      side={side}
      fleet={fleet}
      portId={portId}
      city={city}
      good={good}
      mode={mode}
      onClose={onClose}
      total={mine ? total : null}
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
          <Row label={t('desk.days')} value={<Figure value={go.days !== null ? formatVoyageDays(go.days) : '—'} />} data-testid="plan-days" />
          <Row
            label={t('desk.supplies')}
            value={<Figure value={go.supplies ? formatPriceDelta(-go.supplies.cost) : '—'} tone={go.supplies && !go.supplies.fits ? 'danger' : 'ink'} />}
            data-testid="plan-supplies"
          />
          {go.onCredit > 0 && (
            <Row label={t('desk.onCredit')} value={<Figure value={formatPriceDelta(-go.onCredit)} tone="warning" />} data-testid="plan-on-credit" />
          )}
          {side === 'sell' && (
            <>
              <Row label={t('desk.wages')} value={<Figure value={go.sellRow?.wages != null ? formatPriceDelta(-go.sellRow.wages) : '—'} />} data-testid="trade-wages" />
              <Row
                label={t('desk.dockFee')}
                value={
                  <Figure
                    value={
                      go.sellRow?.dues
                        ? `${formatPriceDelta(-go.sellRow.dues.fee)} · ${taxFactorWords(go.sellRow.dues)}`
                        : go.sellRow?.port_fee != null
                          ? formatPriceDelta(-go.sellRow.port_fee)
                          : '—'
                    }
                  />
                }
                data-testid="trade-dues"
              />
              <Row
                label={t('desk.profit')}
                value={<Figure value={profit !== null ? formatPriceDelta(profit) : '—'} tone={profit === null ? 'faint' : profit >= 0 ? 'success' : 'danger'} size="figure" />}
                data-testid="trade-profit"
              />
            </>
          )}
          <div className="mt-2 flex items-center gap-3">
            <Chip on={mine?.insure === true} onClick={() => set({ insure: !mine?.insure })} className="shrink-0 whitespace-nowrap" data-testid="plan-insure">
              {t('desk.insure')}
            </Chip>
            <Hint className="mt-0">{mine?.insure ? t('desk.insuredHint') : t('desk.uninsuredHint')}</Hint>
          </div>
          {go.noCourse && (
            <Note tone="danger" className="mt-3">
              {t('desk.noWater', { port: portNameOf(useWorld.getState().portByCode, go.noCourse) })}
            </Note>
          )}
          {fleet.ready_at && !fleet.voyage && <ReadyIn at={fleet.ready_at} />}
          {go.refusal && (
            <Note tone="danger" className="mt-3" code={go.refusal.code} figures={go.refusal.figures}>
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
      button={<BigButton act={side === 'buy' ? 'sail-buy' : 'sail-sell'} label={label} disabled={!mine || !go.ready} busy={go.pending} onClick={go.go} />}
      after={mine ? <PlanVoyage fleet={fleet} board={b} buyRow={go.buyRow} sellRow={go.sellRow} /> : undefined}
    />
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

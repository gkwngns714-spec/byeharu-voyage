import { useCallback, useEffect, useMemo, useState } from 'react'
import { DetailPage, SummaryRow, useWide } from '../../../components/ui'
import { fleetCargoByCode, fleetHoldTotal, fleetHoldUsed } from '../../../domain/fleet'
import { usePriceWhy } from '../../../live/useDesk'
import { usePortMarket } from '../../../live/usePortMarket'
import { portNameOf, useWorld } from '../../../live/worldStore'
import type { FleetView } from '../../../lib/rpc'
import { useDeskGood } from '../../../store/deskGood'
import { formatInt, formatOfTotal } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import type { DeskLayout } from '../DeskFrame'
import { Queue } from '../Queue'
import { RouteFold } from '../RouteFold'
import { InsuredVoyages } from '../plans/InsuredVoyages'
import { useDeskPlan, type PlanDraft } from '../plans/planDraft'
import { TradeMap, type OrderPick } from '../plans/TradeMap'
import { useTripBoard } from '../plans/useTripBoard'
import { CargoBest } from './CargoBest'
import { ShipInfo } from './ShipInfo'
import { TradeBoard } from './TradeBoard'
import { tradeRows, type TradeGoodRow } from './tradeRows'
import { TradePanel } from './TradePanel'
import { doneWords, type TradeDone } from './tradeDone'
import { TradeToast } from './TradeToast'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TRADE — ONE SCREEN, BOTH SIDES, AND THE SMALL MAP AT THE BOTTOM (owner 2026-10-30)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"the map on command - buy and sell - is quiet the bad feeling. i am thinking of removing the map, just have
// combined buy and sell tab with trade goods when docked, choosing a fleet."* → *"make the map small, and show at
// bottom, foldable."*
//
// The Buy and Sell faces (BuySell.tsx, row 218) were two faces over ONE city — picked on a mini-map at the top — and
// the map did the city-picking. They are ONE face now. Its goods stand in ONE list (TradeBoard.tsx): every row carries
// BOTH prices — the city's ask (Buy) and its bid (Sell) side by side — and the panel (TradePanel.tsx) opens on
// whichever button is pressed: Buy / Sell where she lies, Sail & buy / Sail & sell anywhere else (owner row 229/231).
//
//   CHIPS      a short strip of harbours nearest her — a city pressed on it (or on the map) is the city in hand.
//   BOARD      that city's goods as cards: both prices, ▲▼ on the day, the day's line, her units aboard, and a Buy
//              and a Sell button on each (dead where there is no such side).
//   CARGO      her cargo, and the best places to sell it (CargoBest.tsx, owner row 231).
//   MAP        the small map (plans/TradeMap.tsx) at the BOTTOM, FOLDABLE: a thin toggle; expanded, the map and the
//              pressed order's estimate. The fold changes only the map's own height — the board above never moves.
//   PANEL      a button pressed opens THE trade panel (TradePanel.tsx): the chart, the units, the money, ONE button.
//   ORDERS     the standing route, the queue, the insured voyages, and the ship under them.
//
// A city pressed MOVES the map to it (row 231); an order pressed draws its route and estimate on it (row 217).

export function Trade({ fleet, layout }: { fleet: FleetView; layout: DeskLayout }) {
  const t = useT()
  const wide = useWide()
  const cancel = useWorld((s) => s.cancel)
  const clearQueue = useWorld((s) => s.clear)
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const picked = useDeskGood((s) => s.code)
  const pickGood = useDeskGood((s) => s.pick)
  const focus = useDeskGood((s) => s.focus)
  const setFocus = useDeskGood((s) => s.setFocus)
  const plan = useDeskPlan((s) => s.plan)
  const openPlan = useDeskPlan((s) => s.open)

  // The city in hand: pressed on the map or the strip, else where she lies, else her next port.
  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  const city = focus && portByCode[focus] ? focus : (docked ?? fleet.voyage?.to ?? null)
  const cityPort = city ? (portByCode[city] ?? null) : null
  const here = docked !== null && docked === city
  const quay = usePortMarket(cityPort?.id ?? null)
  const aboard = useMemo(() => fleetCargoByCode(fleet), [fleet])

  // THE CARDS: the city's goods in one list, both sides' prices in each row.
  const rows = useMemo<TradeGoodRow[]>(() => tradeRows(quay.market?.goods ?? [], aboard, goodByCode), [quay.market, aboard, goodByCode])

  // THE SIDE OF THE OPEN PANEL — the combined board's Buy and Sell buttons each open one; the same good pressed on
  // the side already open closes it.
  const [side, setSide] = useState<'buy' | 'sell'>('buy')
  const openSide = useCallback(
    (s: 'buy' | 'sell', code: string) => {
      if (picked === code && side === s) pickGood(null)
      else {
        setSide(s)
        pickGood(code)
      }
    },
    [picked, side, pickGood],
  )

  // Sell at a city she is NOT at: a carried good its quay does not list is bid for by world.price_why (owner row 231).
  const pickedAny = rows.find((r) => r.code === picked) ?? null
  const sellUnlisted = side === 'sell' && !here && pickedAny && pickedAny.sell === null && pickedAny.units > 0
  const pickedBid = usePriceWhy(sellUnlisted ? (cityPort?.id ?? null) : null, pickedAny?.goodId ?? null)
  const price = pickedAny ? (side === 'buy' ? pickedAny.buy : (pickedAny.sell ?? (sellUnlisted ? (pickedBid.view?.bid ?? null) : null))) : null
  const pickedRow = pickedAny && pickedAny.goodId && price !== null && (side === 'buy' || pickedAny.sell !== null || sellUnlisted) ? pickedAny : null

  // THE TRIP (not docked at the city in hand): Sail & buy plans buy there; Sail & sell plans sell what is aboard there.
  const want: PlanDraft | null =
    pickedRow && city && !here
      ? { good: pickedRow.code, buyAt: side === 'buy' ? city : null, sellAt: side === 'sell' ? city : null, units: null, max: null, min: null, insure: false }
      : null
  const matches = (p: PlanDraft | null, w: PlanDraft) => p !== null && p.good === w.good && p.buyAt === w.buyAt && p.sellAt === w.sellAt
  const tripPlan = want && matches(plan, want) ? plan : null
  useEffect(() => {
    if (want && !matches(plan, want)) openPlan(want)
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `want` is rebuilt every render; its four keys are the dependency
  }, [want?.good, want?.buyAt, want?.sellAt, plan, openPlan])
  const trip = useTripBoard(fleet, tripPlan)

  // THE ORDER PRESSED (row 217): one of hers, for this fleet. Pressed again, or Close, clears it.
  const [orderPick, setOrderPick] = useState<(OrderPick & { fleet: string }) | null>(null)
  const pickNow: OrderPick | null = orderPick?.fleet === fleet.id ? orderPick : null
  const choose = (p: OrderPick | null) => setOrderPick(p ? { ...p, fleet: fleet.id } : null)

  // A CITY PRESSED (the map, the chip strip, a cargo row): it is the city in hand, and the map glides to it (row 231)
  const [goTo, setGoTo] = useState<{ code: string; n: number } | null>(null)
  const pressCity = (code: string) => {
    setFocus(code)
    setGoTo((g) => ({ code, n: (g?.n ?? 0) + 1 }))
  }
  // a cargo row: that city and that good, ready to go — it is a SELL there (CargoBest is the sell aid, owner row 231).
  // It always OPENS for that city — never the board buttons' toggle (a second row for the same good must switch the
  // city, not close: openSide's `picked === good && side === 'sell'` would read the stale good and close instead).
  const pressCargo = (code: string, good: string) => {
    pressCity(code)
    setSide('sell')
    pickGood(good)
  }

  // THE TOAST after a trade or a trip queued
  const [toast, setToast] = useState<string | null>(null)
  const clearToast = useCallback(() => setToast(null), [])
  const done = (d: TradeDone) => {
    setToast(doneWords(t, d, (c) => portNameOf(portByCode, c)))
    pickGood(null)
  }

  // THE COMPACT FACE (owner, 2026-10-31): the board is the subject; Cargo, Map and Orders are
  // summary rows with their key figures, each opening a full-screen page. Nothing unfolds in place.
  const [page, setPage] = useState<'cargo' | 'map' | 'orders' | null>(null)
  const cargoFigure = formatOfTotal(fleetHoldUsed(fleet), fleetHoldTotal(fleet))
  const mapFigure = city ? portNameOf(portByCode, city) : undefined
  const cargo = <CargoBest fleet={fleet} city={city} picked={pickedRow ? pickedRow.code : null} onPress={pressCargo} />

  const board = (
    <TradeBoard
      fleet={fleet}
      city={city}
      docked={here}
      quay={quay}
      rows={rows}
      picked={pickedRow ? pickedRow.code : null}
      onBuy={(code) => openSide('buy', code)}
      onSell={(code) => openSide('sell', code)}
      onCity={pressCity}
    />
  )

  const panel =
    pickedRow && city ? (
      <TradePanel
        key={`${city}:${pickedRow.code}:${side}:${here ? 'here' : 'trip'}`}
        side={side}
        fleet={fleet}
        city={city}
        good={{
          good_id: pickedRow.goodId as string,
          code: pickedRow.code,
          name: pickedRow.name,
          category: pickedRow.category,
          rarity: pickedRow.row?.rarity,
          price: price as number,
        }}
        market={pickedRow.row}
        docked={here}
        trip={trip}
        mode={wide ? 'pane' : 'docked'}
        onClose={() => pickGood(null)}
        onDone={done}
      />
    ) : null

  // the standing route above the queue (0092, COMMAND_DESK §3.5: the one thing that writes orders by
  // itself); the row opens the route's page (consistency row 38)
  const routeRow = <RouteFold fleet={fleet} picked={pickNow?.kind === 'route'} onPick={(on) => choose(on ? { kind: 'route' } : null)} />
  const queue = (
    <Queue
      fleet={fleet}
      onCancel={(position) => cancel(fleet.id, position)}
      onClear={() => clearQueue(fleet.id)}
      picked={pickNow?.kind === 'order' ? pickNow.id : pickNow?.kind === 'voyage' ? 'voyage' : null}
      onPick={choose}
    />
  )
  // THE CARGO DOOR CARRIES NO FIGURE (owner, 2026-10-31: *"no info duplicate info needed"*): the
  // desk's strip already prints her hold, and Fleets is the cargo fact's home. The door opens the
  // board whole, whose own title carries the figure — one readout, one home.
  const cargoRow = <SummaryRow title={t('desk.cargo')} word={t('common.open')} onClick={() => setPage('cargo')} data-testid="cargo-open" />
  const mapRow = <SummaryRow title={t('shell.tab_Map')} figure={mapFigure} word={t('common.open')} onClick={() => setPage('map')} data-testid="trade-map-open" />
  const ordersRow = <SummaryRow title={t('desk.orders')} figure={formatInt(fleet.queue.length)} word={t('common.open')} onClick={() => setPage('orders')} data-testid="command-queue" />
  const pages = (
    <>
      {page === 'cargo' && (
        <DetailPage title={t('desk.cargo')} figure={cargoFigure} onClose={() => setPage(null)} data-testid="cargo-open-page">
          {cargo}
        </DetailPage>
      )}
      {page === 'map' && (
        <DetailPage title={t('shell.tab_Map')} figure={mapFigure} onClose={() => setPage(null)} data-testid="trade-map-open-page">
          <TradeMap
            fleet={fleet}
            plan={trip.drawing}
            pick={pickNow}
            onClose={() => choose(null)}
            scrollOnPick={!wide}
            city={city}
            onCity={pressCity}
            goTo={goTo}
          />
        </DetailPage>
      )}
      {page === 'orders' && (
        <DetailPage title={t('desk.orders')} figure={formatInt(fleet.queue.length)} onClose={() => setPage(null)} data-testid="command-queue-page">
          {queue}
          {/* 0213: the insured voyages under way and what the insurance paid — only when there are any. */}
          <InsuredVoyages />
          {/* row 233: the ship under the orders */}
          <ShipInfo fleet={fleet} />
        </DetailPage>
      )}
    </>
  )

  const toastLine = <TradeToast text={toast} onGone={clearToast} />

  return layout(
    wide
      ? {
          testid: 'desk-trade',
          list: (
            <>
              {routeRow}
              {ordersRow}
            </>
          ),
          main: (
            <>
              {board}
              {cargoRow}
              {mapRow}
              {toastLine}
              {pages}
            </>
          ),
          side: panel ? (
            <div className="h-full min-h-0" data-testid="here-tray">
              {panel}
            </div>
          ) : (
            <p className="px-4 pt-4 text-t-caption text-ink-faint" data-testid="desk-slot-hint">
              {t('desk.pickGood')}
            </p>
          ),
        }
      : {
          testid: 'desk-trade',
          order: ['list', 'main', 'side'],
          list: (
            <>
              {/* The summaries stand ABOVE the board so they stay reachable while the trade
                  panel (a docked tray) covers the lower half. */}
              {cargoRow}
              {mapRow}
              {board}
            </>
          ),
          main: (
            <>
              {panel}
              {toastLine}
              {pages}
            </>
          ),
          side: (
            <div className="mt-2">
              {routeRow}
              {ordersRow}
            </div>
          ),
        },
  )
}

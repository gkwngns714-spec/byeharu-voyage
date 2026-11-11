import { useCallback, useEffect, useMemo, useState } from 'react'
import { DetailPage, SummaryRow, useWide } from '../../../components/ui'
import { fleetCargoByCode, fleetHoldTotal, fleetHoldUsed } from '../../../domain/fleet'
import { useBestSales, usePriceWhy } from '../../../live/useDesk'
import { usePortMarket } from '../../../live/usePortMarket'
import { portNameOf, useWorld } from '../../../live/worldStore'
import type { BestSale, FleetView } from '../../../lib/rpc'
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
import { CityChips, TradeBoard } from './TradeBoard'
import { tradeRows, type TradeGoodRow } from '../../../domain/market'
import { TradePanel } from './TradePanel'
import { doneWords, type TradeDone } from './tradeDone'
import { useTradeCity } from './tradeCity'
import { TradeStatus } from './TradeStatus'
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
//
// THE BEST SALE (0348, owner row 307): each card names the good's best sale from the city in hand (world.best_sales, ONE
// read here for the whole board). Pressed: a good aboard opens Sail & sell at that city (as a cargo row does); a good
// not aboard opens THE TRIP — bought here (the city in hand), sold there — at the units the figure was priced for, in the
// same panel, even where she lies: its first profit is the card's, from the same served row.

export function Trade({ fleet, layout }: { fleet: FleetView; layout: DeskLayout }) {
  const t = useT()
  const wide = useWide()
  const cancel = useWorld((s) => s.cancel)
  const clearQueue = useWorld((s) => s.clear)
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const picked = useDeskGood((s) => s.code)
  const pickGood = useDeskGood((s) => s.pick)
  const setFocus = useDeskGood((s) => s.setFocus)
  const plan = useDeskPlan((s) => s.plan)
  const openPlan = useDeskPlan((s) => s.open)

  // The city in hand (tradeCity.ts: the one reading; the line that says where she is reads the same)
  const { home, city, here } = useTradeCity(fleet)
  const cityPort = city ? (portByCode[city] ?? null) : null
  const quay = usePortMarket(cityPort?.id ?? null)
  const aboard = useMemo(() => fleetCargoByCode(fleet), [fleet])

  // THE CARDS: the city's goods in one list, both sides' prices in each row.
  const rows = useMemo<TradeGoodRow[]>(() => tradeRows(quay.market?.goods ?? [], aboard, goodByCode), [quay.market, aboard, goodByCode])

  // THE BEST SALES (0348): one read for the board — per city in hand, at the market's edge, never on the beat
  const best = useBestSales(fleet.id, fleet.version, cityPort?.id ?? null)
  const sales = useMemo<ReadonlyMap<string, BestSale> | null>(
    () => (best.view && best.view.port === city ? new Map(best.view.goods.map((g) => [g.good, g])) : null),
    [best.view, city],
  )

  // THE TRIP A BEST SALE OPENS (0348): bought at the city in hand, sold at its best city, for the units it was priced at
  const [tripTo, setTripTo] = useState<{ good: string; buyAt: string; sellAt: string; units: number } | null>(null)

  // THE SIDE OF THE OPEN PANEL — the combined board's Buy and Sell buttons each open one; the same good pressed on
  // the side already open closes it.
  const [side, setSide] = useState<'buy' | 'sell'>('buy')
  // THE PAGES (the compact face, below) and the page a tray was opened from: closing that tray goes back to it
  const [page, setPage] = useState<'cargo' | 'map' | 'orders' | null>(null)
  const [backTo, setBackTo] = useState<'cargo' | null>(null)
  const openSide = useCallback(
    (s: 'buy' | 'sell', code: string) => {
      // the same good's Buy pressed while its best-sale trip is open switches to the plain Buy, never closes (0348)
      const fromTrip = tripTo !== null && tripTo.good === code
      setTripTo(null)
      setBackTo(null)
      if (picked === code && side === s && !fromTrip) pickGood(null)
      else {
        setSide(s)
        pickGood(code)
      }
    },
    [picked, side, pickGood, tripTo],
  )

  // Sell at a city she is NOT at: a carried good its quay does not list is bid for by world.price_why (owner row 231).
  const pickedAny = rows.find((r) => r.code === picked) ?? null
  const sellUnlisted = side === 'sell' && !here && pickedAny && pickedAny.sell === null && pickedAny.units > 0
  const pickedBid = usePriceWhy(sellUnlisted ? (cityPort?.id ?? null) : null, pickedAny?.goodId ?? null)
  const price = pickedAny ? (side === 'buy' ? pickedAny.buy : (pickedAny.sell ?? (sellUnlisted ? (pickedBid.view?.bid ?? null) : null))) : null
  const pickedRow = pickedAny && pickedAny.goodId && price !== null && (side === 'buy' || pickedAny.sell !== null || sellUnlisted) ? pickedAny : null
  // the best-sale trip stands while its good is the one open, on Buy, at the city it was opened from
  const tripNow = tripTo && pickedRow && tripTo.good === pickedRow.code && tripTo.buyAt === city && side === 'buy' ? tripTo : null

  // THE TRIP (not docked at the city in hand): Sail & buy plans buy there; Sail & sell plans sell what is aboard there.
  // A best sale pressed (0348) plans buy here AND sell there, docked or not.
  const want: PlanDraft | null =
    pickedRow && city && tripNow
      ? { good: pickedRow.code, buyAt: city, sellAt: tripNow.sellAt, units: tripNow.units, max: null, min: null, insure: false }
      : pickedRow && city && !here
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
  //
  // IT CLOSES THE PAGE IT WAS PRESSED ON (2026-11-11, the trade-flow slice). Your cargo is a full-screen page and the panel
  // stands on the Trade screen under it, so a row pressed lit up and showed nothing: the tray had opened behind the page.
  // The page closes, the tray shows; closing the tray (its Back) opens the page again, so she is back where she pressed.
  const pressCargo = (code: string, good: string) => {
    setTripTo(null)
    pressCity(code)
    setSide('sell')
    pickGood(good)
    setBackTo(page === 'cargo' ? 'cargo' : null)
    setPage(null)
  }

  // A BEST SALE PRESSED (0348): her cargo — Sail & sell there (the cargo row's press); else the trip from the city in
  // hand, its plan opened at the card's units (the effect above keeps it while its good, buy and sell cities stand)
  const pressBest = (s: BestSale) => {
    if (!city || s.port === null) return
    if (s.basis === 'on_board') {
      pressCargo(s.port, s.good)
      return
    }
    const units = s.units ?? 0
    setTripTo({ good: s.good, buyAt: city, sellAt: s.port, units })
    openPlan({ good: s.good, buyAt: city, sellAt: s.port, units, max: null, min: null, insure: false })
    setSide('buy')
    pickGood(s.good)
    setBackTo(null)
  }
  const pickedSale = pickedRow ? sales?.get(pickedRow.code) : undefined

  // THE TOAST after a trade or a trip queued
  const [toast, setToast] = useState<string | null>(null)
  const clearToast = useCallback(() => setToast(null), [])
  const done = (d: TradeDone) => {
    setToast(doneWords(t, d, (c) => portNameOf(portByCode, c)))
    pickGood(null)
    setBackTo(null)
  }
  // the tray's Back: the good is put down, and a tray opened from a page goes back to that page
  const closePanel = () => {
    pickGood(null)
    if (backTo) setPage(backTo)
    setBackTo(null)
  }

  // THE COMPACT FACE (owner, 2026-10-31): the board is the subject; Cargo, Map and Orders are
  // summary rows with their key figures, each opening a full-screen page. Nothing unfolds in place.
  const cargoFigure = formatOfTotal(fleetHoldUsed(fleet), fleetHoldTotal(fleet))
  const mapFigure = city ? portNameOf(portByCode, city) : undefined
  const cargo = <CargoBest fleet={fleet} city={city} picked={pickedRow ? pickedRow.code : null} onPress={pressCargo} />

  // THE CITY PICKER stands at the head of the board on a phone, and in the wide desk's left pane (the layout below)
  const chips = <CityChips home={home} city={city} onCity={pressCity} />
  // WHERE SHE IS, at the head of the wide desk's left pane: in port, or under way to her destination (TradeStatus.tsx).
  // On a phone the same line stands beside her name (CommandScreen.tsx): the glass has no line to spare (tests/onepage.spec.ts).
  const status = <TradeStatus fleet={fleet} />
  const board = (
    <TradeBoard
      strip={wide ? undefined : chips}
      city={city}
      docked={here}
      quay={quay}
      rows={rows}
      picked={pickedRow ? pickedRow.code : null}
      onBuy={(code) => openSide('buy', code)}
      onSell={(code) => openSide('sell', code)}
      sales={sales}
      onBest={pressBest}
    />
  )

  const panel =
    pickedRow && city ? (
      <TradePanel
        key={`${city}:${pickedRow.code}:${side}:${here && !tripNow ? 'here' : 'trip'}:${tripNow?.sellAt ?? ''}`}
        side={side}
        fleet={fleet}
        city={city}
        good={{
          good_id: pickedRow.goodId as string,
          code: pickedRow.code,
          name: pickedRow.name,
          category: pickedRow.category,
          rarity: pickedRow.row?.rarity,
          // the class is the same served number in both payloads, so a carried good this quay does not list still has one
          class: pickedRow.row?.class ?? goodByCode[pickedRow.code]?.class,
          price: price as number,
        }}
        market={pickedRow.row}
        docked={here && !tripNow}
        sellAt={tripNow?.sellAt ?? null}
        // "no sale pays" is not the word for a good she cannot pay for (0351 `short`): that one's card says "No money"
        noGain={side === 'buy' && pickedSale !== undefined && !pickedSale.pays && !pickedSale.short}
        trip={trip}
        mode={wide ? 'pane' : 'docked'}
        onClose={closePanel}
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
  // ON A PHONE THE TWO DOORS SHARE ONE LINE (2026-11-12; the layout below). Half a line has no room for the word "Open"
  // beside "Your cargo" (177 px of words in 171: it would cut the title), so there that door is its title and its chevron;
  // nor for the map's city (it is the lit cell of the picker right under it). The Map door keeps "Open": alone it would read
  // "Map", the nav's own cell (tests/consistency.spec.ts: two controls never share a label). The wide desk's doors are whole.
  const cargoRow = <SummaryRow title={t('desk.cargo')} word={wide ? t('common.open') : undefined} onClick={() => setPage('cargo')} data-testid="cargo-open" />
  const mapRow = <SummaryRow title={t('shell.tab_Map')} figure={wide ? mapFigure : undefined} word={t('common.open')} onClick={() => setPage('map')} data-testid="trade-map-open" />
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
          // THE WIDE DESK'S THREE PANES (2026-11-11, the trade-layout slice; docs/dev-log/2026-11-11-trade-layout.md). Measured
          // at 1,280 before it: the left pane held two rows (Route, Orders) in 626 px of height, and the centre pane, 430 px
          // wide, held everything else. The frame is the desk's and the same on every face (DeskFrame.tsx), so the parts move,
          // not the panes: WHERE AND WHAT SHE HAS on the left (the city picker, her cargo, the map, the route, the orders), THE
          // GOODS alone in the centre, the trade panel on the right.
          testid: 'desk-trade',
          list: (
            <>
              {status}
              {chips}
              {cargoRow}
              {mapRow}
              {routeRow}
              {ordersRow}
            </>
          ),
          main: (
            <>
              {board}
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
              {/* SIDE BY SIDE, ONE LINE (2026-11-12): the two doors took two 44-px lines of a 390-px glass that has none to
                  spare. The goods card is 14 px taller since its best sale's city is printed whole, and the cards' pane must
                  hold a whole row of them (TradeBoard.tsx); with the doors on one line the face still fits the glass without
                  scrolling (tests/onepage.spec.ts), with 22 px in hand. */}
              <div className="grid grid-cols-2 gap-2">
                {cargoRow}
                {mapRow}
              </div>
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

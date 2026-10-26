import { useCallback, useEffect, useMemo, useState } from 'react'
import { SheetSection, useWide } from '../../../components/ui'
import { fleetCargoByCode } from '../../../domain/fleet'
import { buyableHere, listedHere } from '../../../domain/market'
import { usePriceWhy } from '../../../live/useDesk'
import { usePortMarket } from '../../../live/usePortMarket'
import { portNameOf, useWorld } from '../../../live/worldStore'
import type { FleetView } from '../../../lib/rpc'
import { useDeskGood } from '../../../store/deskGood'
import type { DeskLayout } from '../DeskFrame'
import { useDeskView } from '../deskView'
import { Queue } from '../Queue'
import { RouteFold } from '../RouteFold'
import { InsuredVoyages } from '../plans/InsuredVoyages'
import { useDeskPlan, type PlanDraft } from '../plans/planDraft'
import { TradeMap, type OrderPick } from '../plans/TradeMap'
import { useTripBoard } from '../plans/useTripBoard'
import { CargoBest } from './CargoBest'
import { CityBoard, type CityGoodRow } from './CityBoard'
import { TradePanel } from './TradePanel'
import { doneWords, type TradeDone } from './tradeDone'
import { TradeToast } from './TradeToast'
import { useT } from '../../../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// BUY · SELL — ONE MIRRORED SCREEN, TWO SIDES (owner rows 218 and 229, 2026-10-26)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"buying and selling in command tab is not straight forward … selling i cannot even see charts. I want to click on
// cities, see the selling prices when i click on the city, not give a bunch of list since it will be too easy. for
// buying and selling i want both to be... similar mechanism. similar screen, buttons to press etc. make it like a
// true game."* (row 229)
//
// ONE component, `side` the only difference, so the two faces look and work the same:
//
//   MAP        THE map (plans/TradeMap.tsx, row 207) with every city and her ship; her orders pressed draw their
//              routes and estimate (row 217). A city pressed on it — or on the chip strip under it — is the city in
//              hand (store/deskGood's `focus`; default: where she lies, else her next port).
//   BOARD      that city's goods as cards (CityBoard.tsx): Buy — what it sells, at its ask; Sell — her cargo, at
//              its bid ("No buyer" greyed where it buys none). Each with ▲▼ on the day and its line.
//   PANEL      a card pressed opens THE trade panel (TradePanel.tsx): the chart, the units, the money, ONE button —
//              Buy / Sell docked there, Sail & buy / Sail & sell anywhere else (the trip, queued with Go's lines).
//   ORDERS     the standing route, the queue, the insured voyages.
//
// NO CROSS-CITY LIST ON BUY (row 229: "it will be too easy"): what a city pays is found by pressing it.
//
// SELL OPENS ON HER CARGO (owner row 231, 2026-10-26: *"the command, sell tab is not good enough, i can't sell
// because i can't dock. and i can't move to that location. buying and selling when pressed a city, move the map to
// that location. make the sell tab more convenient. come on!"*):
//   · CARGO (CargoBest.tsx), under the map on Sell: each good aboard with the few best cities she can sail to for
//     it — the served board's own rows (world.good_board: price, days, profit after wages, supplies and tax) — and
//     "Here" where she lies; one press on a row is that city and that good, ready to go.
//   · A CITY SHE IS NOT AT BUYS WHAT SHE CARRIES even where its quay lists no such row: world.market lists a good
//     only where the city offers it or she lies with it (public.quay_shows), and that is why every such city read
//     "No buyer" and could not be pressed — while the server buys there all the same. Its bid is world.price_why's
//     (the served price, the same world.price the quay reads); the card prices and presses, the panel opens.
//   · A CITY PRESSED (the map, the chip strip, a cargo row) MOVES THE MAP TO IT (TradeMap's `goTo`): a glide of the
//     view, nothing re-flowed.
//
// A phone: map, chips, cards, orders, one under the other; the panel is a bottom sheet. A wide glass: orders on the
// left, the map and the cards in the centre, the panel on the right.

export function BuySell({ side, fleet, layout }: { side: 'buy' | 'sell'; fleet: FleetView; layout: DeskLayout }) {
  const t = useT()
  const wide = useWide()
  const cancel = useWorld((s) => s.cancel)
  const clearQueue = useWorld((s) => s.clear)
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const turnTo = useDeskView((s) => s.turnTo)
  const focus = useDeskGood((s) => s.focus)
  const setFocus = useDeskGood((s) => s.setFocus)
  const picked = useDeskGood((s) => s.code)
  const pickGood = useDeskGood((s) => s.pick)
  const plan = useDeskPlan((s) => s.plan)
  const openPlan = useDeskPlan((s) => s.open)

  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  const city = focus && portByCode[focus] ? focus : (docked ?? fleet.voyage?.to ?? null)
  const cityPort = city ? (portByCode[city] ?? null) : null
  const here = docked !== null && docked === city
  const quay = usePortMarket(cityPort?.id ?? null)
  const aboard = useMemo(() => fleetCargoByCode(fleet), [fleet])

  // THE CARDS: Buy — the goods this city sells; Sell — her cargo, each with this city's row when it deals in it
  // (0061: a carried good is listed where she can sell it).
  const rows = useMemo<CityGoodRow[]>(() => {
    const market = quay.market?.goods ?? []
    const byCode = new Map(market.map((g) => [g.code, g]))
    const out: CityGoodRow[] =
      side === 'buy'
        ? market.filter((g) => buyableHere(g)).map((g) => ({ code: g.code, goodId: g.good_id, name: g.name, category: g.category, units: aboard[g.code] ?? 0, row: g, price: g.buy }))
        : Object.entries(aboard)
            .filter(([, units]) => units > 0)
            .map(([code, units]) => {
              const good = goodByCode[code]
              const row = byCode.get(code) ?? null
              const listed = row !== null && listedHere(row, units)
              return { code, goodId: row?.good_id ?? good?.id ?? null, name: row?.name ?? good?.name ?? code, category: row?.category ?? good?.category ?? '', units, row: listed ? row : null, price: listed ? row.sell : null }
            })
    // Sell: the goods this city buys first, "No buyer" after
    return out.sort((a, b) => Number(a.price === null) - Number(b.price === null) || a.name.localeCompare(b.name))
  }, [side, quay.market, aboard, goodByCode])
  // Sell at a city she is not at: a carried good its quay does not list is bid for by world.price_why (the header)
  const bidElsewhere = side === 'sell' && !here
  const pickedAny = rows.find((r) => r.code === picked) ?? null
  const pickedBid = usePriceWhy(bidElsewhere && pickedAny && !pickedAny.row ? (cityPort?.id ?? null) : null, pickedAny?.goodId ?? null)
  const pickedPrice = pickedAny ? (pickedAny.price ?? (bidElsewhere ? (pickedBid.view?.bid ?? null) : null)) : null
  const pickedRow = pickedAny && pickedPrice !== null && pickedAny.goodId && (pickedAny.row !== null || bidElsewhere) ? pickedAny : null

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
  // a cargo row (Sell): that city and that good, ready to go
  const pressCargo = (code: string, good: string) => {
    pressCity(code)
    pickGood(good)
  }

  // THE TOAST after a trade or a trip queued
  const [toast, setToast] = useState<string | null>(null)
  const clearToast = useCallback(() => setToast(null), [])
  const done = (d: TradeDone) => {
    setToast(doneWords(t, d, (c) => portNameOf(portByCode, c)))
    pickGood(null)
    if (d.sailTo) turnTo(side)
  }

  const map = (
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
  )

  const cargo = side === 'sell' ? <CargoBest fleet={fleet} city={city} picked={pickedRow ? pickedRow.code : null} onPress={pressCargo} /> : null

  const board = (
    <CityBoard
      side={side}
      fleet={fleet}
      city={city}
      docked={here}
      quay={quay}
      rows={rows}
      picked={pickedRow ? pickedRow.code : null}
      onPick={(code) => pickGood(picked === code ? null : code)}
      onCity={pressCity}
    />
  )

  const panel =
    pickedRow && pickedPrice !== null && city ? (
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
          price: pickedPrice,
        }}
        market={pickedRow.row}
        docked={here}
        trip={trip}
        mode={wide ? 'pane' : 'docked'}
        onClose={() => pickGood(null)}
        onDone={done}
      />
    ) : null

  const orders = (
    <>
      {/* the standing route above the queue (0092, COMMAND_DESK §3.5: the one thing that writes orders by itself) */}
      <RouteFold fleet={fleet} picked={pickNow?.kind === 'route'} onPick={(on) => choose(on ? { kind: 'route' } : null)} />
      <SheetSection heading={t('desk.orders')} surface data-testid="command-queue">
        <Queue
          fleet={fleet}
          onCancel={(position) => cancel(fleet.id, position)}
          onClear={() => clearQueue(fleet.id)}
          picked={pickNow?.kind === 'order' ? pickNow.id : pickNow?.kind === 'voyage' ? 'voyage' : null}
          onPick={choose}
        />
      </SheetSection>
      {/* 0213: the insured voyages under way and what the insurance paid — only when there are any. */}
      <InsuredVoyages />
    </>
  )

  const toastLine = <TradeToast text={toast} onGone={clearToast} />

  return layout(
    wide
      ? {
          testid: side === 'buy' ? 'desk-buy' : 'desk-sell',
          list: orders,
          main: (
            <>
              {map}
              {cargo}
              {board}
              {toastLine}
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
          testid: side === 'buy' ? 'desk-buy' : 'desk-sell',
          order: ['list', 'main', 'side'],
          list: (
            <>
              {map}
              {cargo}
              {board}
            </>
          ),
          main: (
            <>
              {panel}
              {toastLine}
            </>
          ),
          side: <div className="mt-6">{orders}</div>,
        },
  )
}

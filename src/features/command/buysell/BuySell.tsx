import { useEffect, useMemo, useRef, useState } from 'react'
import { Button, Hint, SheetSection, useWide } from '../../../components/ui'
import { fleetCargoByCode } from '../../../domain/fleet'
import { buyableHere, listedHere } from '../../../domain/market'
import { usePortMarket } from '../../../live/usePortMarket'
import { useWorld } from '../../../live/worldStore'
import type { FleetView } from '../../../lib/rpc'
import { useDeskGood } from '../../../store/deskGood'
import type { DeskLayout } from '../DeskFrame'
import { useDeskView } from '../deskView'
import { DeskTrade } from '../markets/DeskTrade'
import { Queue } from '../Queue'
import { RouteFold } from '../RouteFold'
import { InsuredVoyages } from '../plans/InsuredVoyages'
import { useDeskPlan } from '../plans/planDraft'
import { SellList } from '../plans/SellList'
import { TradeCard } from '../plans/TradeCard'
import { TradeMap, type OrderPick } from '../plans/TradeMap'
import { useTripBoard } from '../plans/useTripBoard'
import { CityGoods, type CityGoodRow } from './CityGoods'
import { GoodDetail } from './GoodDetail'
import { useT } from '../../../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// BUY · SELL — the desk's two trading faces (owner row 218, 2026-10-26)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"in command, there is market, and trade. i want to have buy and sell tab instead of those. with charts, map and
// all. combine the two market and trade tab, separation. in mini map in command, show cities, when pressed upon, show
// trade goods with prices, and charts. get it?"*
//
// ONE PAGE, TWO SIDES (`side`), replacing the Markets face (every good, every city) and the Trade face (Here / Cargo /
// the trip card). Top to bottom on a phone; on a wide glass the desk's three panes (DeskFrame.tsx):
//
//   MAP      THE map (plans/TradeMap.tsx — the small chart at 0 % zoom, row 207) with EVERY city on it; a city pressed is
//            the city in hand (store/deskGood's `focus`; default: where she lies, else her next port). An order pressed
//            in the orders pane draws its route and its served estimate under the map (row 217), on both sides.
//   CITY     the city's goods (CityGoods.tsx): BUY — what it sells, at its ask; SELL — her cargo, at its bid. A good
//            pressed opens its page (GoodDetail.tsx): the price, the chart, why, who bought what, and THE ACT —
//              docked at this city → Buy here / Sell here: THE trade tray (markets/DeskTrade.tsx, one authority);
//              anywhere else       → Plan trip: the trip's card (plans/TradeCard.tsx) and its sell list, Go queues it.
//   ORDERS   the standing route above the queue, and the insured voyages (the right pane on a wide glass).
//
// EVERY FIGURE IS SERVED: the prices world.market's, the chart world.price_series's, the trip world.good_board's. The
// city and the good pressed are one store (store/deskGood.ts), so turning Buy → Sell keeps the city in hand.

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

  // THE ROWS (CityGoods.tsx): Buy — the goods this city sells; Sell — her cargo, each with this city's row when it
  // deals in it (0061: a carried good is listed where she can sell it).
  const rows = useMemo<CityGoodRow[]>(() => {
    const market = quay.market?.goods ?? []
    const byCode = new Map(market.map((g) => [g.code, g]))
    const out: CityGoodRow[] =
      side === 'buy'
        ? market.filter((g) => buyableHere(g)).map((g) => ({ code: g.code, name: g.name, category: g.category, units: aboard[g.code] ?? 0, row: g, price: g.buy }))
        : Object.entries(aboard)
            .filter(([, units]) => units > 0)
            .map(([code, units]) => {
              const good = goodByCode[code]
              const row = byCode.get(code) ?? null
              const listed = row !== null && listedHere(row, units)
              return { code, name: row?.name ?? good?.name ?? code, category: row?.category ?? good?.category ?? '', units, row: listed ? row : null, price: listed ? row.sell : null }
            })
    return out.sort((a, b) => a.name.localeCompare(b.name))
  }, [side, quay.market, aboard, goodByCode])
  const pickedRow = rows.find((r) => r.code === picked) ?? null

  // THE TRADE TRAY: one good, one side, for this fleet while she lies at the city in hand.
  const [trading, setTrading] = useState<{ code: string; fleet: string } | null>(null)
  const tradingNow = here && trading?.fleet === fleet.id ? trading : null
  const tray = tradingNow ? (
    <DeskTrade
      key={`${tradingNow.code}:${side}`}
      mode={wide ? 'pane' : 'docked'}
      fleet={fleet}
      code={tradingNow.code}
      intent={side}
      onClose={() => setTrading(null)}
    />
  ) : null

  // THE TRIP: a plan of this side — Buy plans buy at a city (buyAt), Sell plans sell what is aboard (buyAt null).
  const sidePlan = plan && (side === 'buy' ? plan.buyAt !== null : plan.buyAt === null) ? plan : null
  const trip = useTripBoard(fleet, sidePlan)
  const cardRef = useRef<HTMLDivElement>(null)
  const [planPressed, setPlanPressed] = useState(0)
  useEffect(() => {
    // a phone: Plan trip brings the card up to the thumb
    if (planPressed > 0 && !wide) cardRef.current?.scrollIntoView({ block: 'start', behavior: 'smooth' })
  }, [planPressed, wide])
  const planFrom = (r: CityGoodRow) => () => {
    if (!city) return
    // SELL: the trip ends at the city in hand — unless she lies there or it buys none of this good; then the card's
    // sell list says where (every city the board serves for it).
    const sellAt = side === 'sell' && !here && r.row ? city : null
    openPlan({ good: r.code, buyAt: side === 'buy' ? city : null, sellAt, units: null, max: null, min: null, insure: false })
    setPlanPressed((n) => n + 1)
  }

  // THE ORDER PRESSED (row 217): one of hers, for this fleet. Pressed again, or Close, clears it.
  const [orderPick, setOrderPick] = useState<(OrderPick & { fleet: string }) | null>(null)
  const pickNow: OrderPick | null = orderPick?.fleet === fleet.id ? orderPick : null
  const choose = (p: OrderPick | null) => setOrderPick(p ? { ...p, fleet: fleet.id } : null)

  const map = (
    <TradeMap
      fleet={fleet}
      plan={trip.drawing}
      pick={pickNow}
      onClose={() => choose(null)}
      scrollOnPick={!wide}
      city={city}
      onCity={(code) => {
        setFocus(code)
        setTrading(null)
      }}
    />
  )

  const detail = (r: CityGoodRow) =>
    r.row && cityPort ? (
      <GoodDetail
        key={`${city}:${r.code}:${side}`}
        side={side}
        portId={cityPort.id}
        row={r.row}
        docked={here}
        canAct={side === 'buy' ? buyableHere(r.row) : r.units > 0}
        onAct={() => setTrading({ code: r.code, fleet: fleet.id })}
        onPlan={planFrom(r)}
        refresh={fleet.version}
      />
    ) : (
      // the city keeps no row for a good she carries: say so, and plan where to sell it instead
      <div className="mb-3" data-testid="good-detail-none">
        <Hint>{t('desk.noBuyer')}</Hint>
        <Button variant="primary" className="mt-2" onClick={planFrom(r)} data-testid="good-plan">
          {t('desk.planTrip')}
        </Button>
      </div>
    )

  const goods = (
    <CityGoods
      side={side}
      city={city}
      docked={here}
      quay={quay}
      rows={rows}
      picked={pickedRow ? pickedRow.code : null}
      onPick={(code) => {
        pickGood(code)
        setTrading(null)
      }}
      detail={wide ? undefined : detail}
    />
  )

  const card =
    sidePlan && trip.good ? (
      <div ref={cardRef} className="mt-4 scroll-mt-28" data-testid="trip">
        <TradeCard
          key={`${sidePlan.good}:${sidePlan.buyAt ?? ''}:${fleet.id}`}
          fleet={fleet}
          good={trip.good}
          plan={sidePlan}
          board={trip.board}
          units={trip.units}
          legs={trip.legs}
          onQueued={() => turnTo(side)}
          onRoute={() => turnTo(side)}
        />
        <SellList plan={sidePlan} board={trip.board} loading={trip.loading} />
      </div>
    ) : null

  return layout({
    testid: side === 'buy' ? 'desk-buy' : 'desk-sell',
    order: ['list', 'main', 'side'],
    list: (
      <>
        {/* THE MAP ON TOP (rows 217, 218): the first thing on a phone; the centre pane's head on a wide glass */}
        {!wide && map}
        {goods}
      </>
    ),
    main: (
      <>
        {wide && map}
        {wide && pickedRow && detail(pickedRow)}
        {card}
        {/* a phone: the tray at the bottom edge, over nothing it moves */}
        {!wide && tray}
      </>
    ),
    side:
      wide && tray ? (
        <div className="h-full min-h-0" data-testid="here-tray">
          {tray}
        </div>
      ) : (
        <div className="lg:h-full lg:min-h-0 lg:overflow-y-auto lg:px-4 lg:pb-6 lg:pt-3">
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
        </div>
      ),
  })
}

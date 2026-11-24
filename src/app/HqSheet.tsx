import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { useSearchParams } from 'react-router-dom'
import { DetailPage, Note, Skeleton, useBackLayer } from '../components/ui'
import { alongsideAt, fleetCargoByCode } from '../domain/fleet'
import { useCommandDraft } from '../domain/order'
import { buildingTier, hasBuilding } from '../domain/port'
import { tradeRows } from '../domain/market'
import type { PlanDraft } from '../domain/plan'
import { PORT_FACES } from '../live/cityFaces'
import { PortInn } from '../live/PortInn'
import { PortTrade } from '../live/PortTrade'
import { PortYard } from '../live/PortYard'
import { useTradeFace } from '../live/tradeFace'
import { useBestSales, usePriceWhy } from '../live/useDesk'
import { usePortMarket } from '../live/usePortMarket'
import { portNameOf, useWorld } from '../live/worldStore'
import type { FleetView, SnapshotPort } from '../lib/rpc'
import { useT } from '../lib/i18n'
import type { DeskLayout } from '../features/command/DeskFrame'
import { useYardAsk } from '../features/command/officeView'
import { Invest } from '../features/command/invest/Invest'
import { Report } from '../features/command/report/Report'
import { Queue } from '../features/command/Queue'
import { RouteFold } from '../features/command/RouteFold'
import { CargoBest } from '../features/command/buysell/CargoBest'
import { TradePanel } from '../features/command/buysell/TradePanel'
import { saleChoices } from '../features/command/buysell/saleChoice'
import { doneWords, type TradeDone } from '../features/command/buysell/tradeDone'
import { TradeToast } from '../features/command/buysell/TradeToast'
import { useDeskPlan } from '../features/command/plans/planDraft'
import { useTripBoard } from '../features/command/plans/useTripBoard'
import { askOfParams, HQ_ASK_FIELDS, openHq, useHqPlace, type HqAsk } from './hqPlace'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SHEETS OVER HQ (2026-11-24, docs/design/simplify-2026-11-24.md S1; the one door is hqPlace.ts `openHq`)
// IN THE SHELL, NOT IN A SCREEN: it composes the faces of two screens (features/city's HQ and features/command's desk parts), and no
// screen may import another (tests/sections.spec.ts); the shell may use any screen.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A press on HQ opens its activity HERE, over HQ, never on another tab: the existing face composed, nothing rewritten —
//   invest / report   the Office's two faces (Invest.tsx, Report.tsx), their parts one under the other in a DetailPage;
//   yard              PortYard of that city, a hull's sheet open when the card named one;
//   inn               PortInn of that city, for her fleet lying there;
//   requests          the city's market on its Requests face (PortTrade), where a request is fulfilled;
//   trade             THE trade sheet (TradePanel), composed by its props: Buy / Sell where she lies, Sail & buy / Sail & sell
//                     elsewhere, and a best sale's trip (bought here, sold there) at the units the card was priced for;
//   fleet             her cargo and where it sells (CargoBest), her route (RouteFold), her orders (Queue).
// Each is a layer (useBackLayer): its back arrow, Escape and the browser's back close it, and HQ under it is as it was.

/** The desk's parts, one under the other: a face of the desk read in a sheet. */
const stack: DeskLayout = (p) => (
  <div data-testid={p.testid} className="flex flex-col gap-4" {...p.marks}>
    {(p.order ?? ['list', 'main', 'side']).map((k) => (
      <div key={k} className="min-w-0">
        {p[k]}
      </div>
    ))}
  </div>
)

/** A sheet's identity: a new ask is a new sheet, mounted afresh. */
function askKey(a: HqAsk): string {
  return [a.sheet, 'port' in a ? a.port : '', 'fleet' in a ? (a.fleet ?? '') : '', 'good' in a ? `${a.good}:${a.side}` : '', 'hull' in a ? (a.hull ?? '') : ''].join('|')
}

/** The packed column a page's content stands in (CityFace's own measure). */
function PageBody({ children }: { children: ReactNode }) {
  return <div className="mx-auto w-full max-w-2xl">{children}</div>
}

const faceWord = (id: 'building_yard') => PORT_FACES.find((f) => f.id === id)!.label

/** HQ's sheet host: mounted once by the screen it stands over. */
export function HqSheet() {
  const t = useT()
  const ask = useHqPlace((s) => s.ask)
  const close = useHqPlace((s) => s.close)
  const portByCode = useWorld((s) => s.portByCode)
  const [params, setParams] = useSearchParams()
  const [toast, setToast] = useState<string | null>(null)
  const clearToast = useCallback(() => setToast(null), [])

  // A LINK'S SHEET (hqPlace.ts `hqHref`): opened once, and its fields leave the URL, so the URL stays HQ's own
  useEffect(() => {
    const a = askOfParams(params)
    if (!a) return
    const next = new URLSearchParams(params)
    for (const k of HQ_ASK_FIELDS) next.delete(k)
    setParams(next, { replace: true })
    openHq(a)
  }, [params, setParams])
  // HQ left: nothing stands over it when it comes back
  useEffect(() => () => useHqPlace.getState().clear(), [])

  const done = (d: TradeDone) => setToast(doneWords(t, d, (c) => portNameOf(portByCode, c)))

  return (
    <>
      {ask && <AskSheet key={askKey(ask)} ask={ask} onClose={close} onDone={done} />}
      <TradeToast text={toast} onGone={clearToast} />
    </>
  )
}

function AskSheet({ ask, onClose, onDone }: { ask: HqAsk; onClose: () => void; onDone: (d: TradeDone) => void }) {
  const t = useT()
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const draft = useCommandDraft((s) => s.fleetId)
  const port = 'port' in ask ? (portByCode[ask.port] ?? null) : null
  // the fleet named, else one of hers lying at that city (the one in hand first), else none: a read-only face
  const named = 'fleet' in ask && ask.fleet ? (fleets.find((f) => f.id === ask.fleet) ?? null) : null
  const lying = port ? (alongsideAt(fleets, port.code, draft).docked[0] ?? null) : null
  const fleet = named ?? lying

  switch (ask.sheet) {
    case 'invest': {
      const inHand = fleets.find((f) => f.id === draft) ?? fleets[0] ?? null
      return (
        <DetailPage title={t('command.f_invest')} onClose={onClose} data-testid="hq-sheet-invest">
          {inHand ? <Invest fleet={inHand} layout={stack} /> : <Note tone="neutral">{t('hq.noFleet')}</Note>}
        </DetailPage>
      )
    }
    case 'report':
      return (
        <DetailPage title={t('command.f_report')} onClose={onClose} data-testid="hq-sheet-report">
          <Report layout={stack} />
        </DetailPage>
      )
    case 'yard':
      return port ? <YardSheet port={port} fleet={fleet} hull={ask.hull ?? null} onClose={onClose} /> : null
    case 'inn':
      return port ? (
        <DetailPage title={t('city.inn')} word={port.name} onClose={onClose} data-testid="hq-sheet-inn">
          <PageBody>{hasBuilding(port, 'inn') ? <PortInn port={port} alongside={fleet} /> : <Note tone="neutral">{t('city.noInn')}</Note>}</PageBody>
        </DetailPage>
      ) : null
    case 'requests':
      return port ? <RequestsSheet port={port} fleet={fleet} onClose={onClose} /> : null
    case 'trade':
      return port && named ? <TradeSheet ask={ask} fleet={named} onClose={onClose} onDone={onDone} /> : null
    case 'fleet':
      return named ? <FleetSheet fleet={named} route={ask.route ?? false} onClose={onClose} /> : null
  }
}

/** The yard of that city; a hull named by the card has its sheet opened by the yard itself (PortYard reads `useYardAsk`). */
function YardSheet({ port, fleet, hull, onClose }: { port: SnapshotPort; fleet: FleetView | null; hull: string | null; onClose: () => void }) {
  const t = useT()
  useEffect(() => {
    if (hull) useYardAsk.getState().ask(hull)
  }, [hull])
  return (
    <DetailPage title={faceWord('building_yard')} word={port.name} onClose={onClose} data-testid="hq-sheet-yard">
      <PageBody>
        {hasBuilding(port, 'building_yard') ? (
          <PortYard portId={port.id} fleet={fleet} tier={buildingTier(port, 'building_yard')} />
        ) : (
          <Note tone="neutral">{t('city.noYard')}</Note>
        )}
      </PageBody>
    </DetailPage>
  )
}

/** The city's market turned to its Requests (where a request is fulfilled); a price pressed there opens the trade sheet. */
function RequestsSheet({ port, fleet, onClose }: { port: SnapshotPort; fleet: FleetView | null; onClose: () => void }) {
  const t = useT()
  const quay = usePortMarket(port.id)
  const turnTo = useTradeFace((s) => s.turnTo)
  useEffect(() => turnTo('requests'), [turnTo])
  return (
    <DetailPage title={t('city.jobsHeading')} word={port.name} onClose={onClose} data-testid="hq-sheet-requests">
      <PageBody>
        {!fleet ? (
          <Note tone="neutral">{t('hq.noFleet')}</Note>
        ) : quay.market === undefined ? (
          quay.refusal !== null ? (
            <Note tone="danger" code={quay.refusal.code} figures={quay.refusal.figures}>
              {quay.refusal.sentence}
            </Note>
          ) : (
            <Skeleton className="h-28 w-full" />
          )
        ) : (
          <PortTrade
            goods={quay.market.goods}
            fleet={fleet}
            port={port}
            onTrade={(good, side) => openHq({ sheet: 'trade', port: port.code, fleet: fleet.id, good: good.code, side })}
          />
        )}
      </PageBody>
    </DetailPage>
  )
}

/** A fleet's sheet: her cargo (a row pressed sells it there), her route, her orders. Asked from her row's Route, the route stands
 *  first (its row opens the route's own page). */
function FleetSheet({ fleet, route, onClose }: { fleet: FleetView; route: boolean; onClose: () => void }) {
  const t = useT()
  const cancel = useWorld((s) => s.cancel)
  const clearQueue = useWorld((s) => s.clear)
  const routeRow = (
    <div className="mb-4" data-testid="hq-sheet-fleet-route">
      <RouteFold fleet={fleet} />
    </div>
  )
  return (
    <DetailPage title={fleet.name} onClose={onClose} data-testid="hq-sheet-fleet">
      <PageBody>
        {route && routeRow}
        <h2 className="pb-1 text-t-caption text-ink-faint">{t('hq.cargo')}</h2>
        <CargoBest fleet={fleet} city={null} picked={null} onPress={(city, good) => openHq({ sheet: 'trade', port: city, fleet: fleet.id, good, side: 'sell' })} />
        {!route && <div className="mt-4">{routeRow}</div>}
        <h2 className="pb-1 text-t-caption text-ink-faint">{t('hq.orders')}</h2>
        <Queue fleet={fleet} onCancel={(position) => cancel(fleet.id, position)} onClear={() => clearQueue(fleet.id)} />
      </PageBody>
    </DetailPage>
  )
}

/** THE trade sheet: TradePanel composed by its props, as the desk composes it (Trade.tsx), for one ask. A docked tray: a bottom
 *  sheet on a phone, the side panel on a wide glass; its ✕, Escape and the browser's back close it. */
function TradeSheet({
  ask,
  fleet,
  onClose,
  onDone,
}: {
  ask: Extract<HqAsk, { sheet: 'trade' }>
  fleet: FleetView
  onClose: () => void
  onDone: (d: TradeDone) => void
}) {
  // the tray's ✕ is the sheet's own back (useBackLayer.ts): the close comes on the step back, never beside it
  const back = useBackLayer(onClose)
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const plan = useDeskPlan((s) => s.plan)
  const openPlan = useDeskPlan((s) => s.open)

  // A BEST SALE (the board's card, Trade.tsx `pressBest`): her cargo is sold at its city; else the trip, bought here and sold there
  const sale = ask.best ?? null
  const onBoard = sale?.basis === 'on_board' && sale.port !== null
  const city = onBoard && sale?.port ? sale.port : ask.port
  const side = onBoard ? 'sell' : ask.side
  const cityPort = portByCode[city] ?? null
  const here = fleet.status === 'DOCKED' && fleet.port === city
  const quay = usePortMarket(cityPort?.id ?? null)
  const aboard = useMemo(() => fleetCargoByCode(fleet), [fleet])
  const rows = useMemo(() => tradeRows(quay.market?.goods ?? [], aboard, goodByCode), [quay.market, aboard, goodByCode])
  const row = rows.find((r) => r.code === ask.good) ?? null

  // a carried good the city's quay does not list is bid for by world.price_why (owner row 231)
  const sellUnlisted = side === 'sell' && !here && row !== null && row.sell === null && row.units > 0
  const bid = usePriceWhy(sellUnlisted ? (cityPort?.id ?? null) : null, row?.goodId ?? null)
  const price = row ? (side === 'buy' ? row.buy : (row.sell ?? (sellUnlisted ? (bid.view?.bid ?? null) : null))) : null
  const best = useBestSales(fleet.id, fleet.version, cityPort?.id ?? null)
  const pickedSale = row && best.view?.port === city ? best.view.goods.find((g) => g.good === row.code) : undefined

  // THE TRIP: a best sale's (0348) at the units it was priced for, to the place chosen (P1); a city she is not at, one-ended
  const [sellAt, setSellAt] = useState<{ port: string; units: number } | null>(() =>
    sale && !onBoard && sale.port !== null ? { port: sale.port, units: sale.units ?? 0 } : null,
  )
  const also = sale && sellAt && sellAt.port === sale.port && sale.top ? { ...sale.top, with: sellAt.units, on: true } : null
  const want: PlanDraft | null =
    row && sellAt
      ? { good: row.code, buyAt: city, sellAt: sellAt.port, units: sellAt.units, max: null, min: null, insure: false, also }
      : row && !here
        ? { good: row.code, buyAt: side === 'buy' ? city : null, sellAt: side === 'sell' ? city : null, units: null, max: null, min: null, insure: false }
        : null
  const matches = (p: PlanDraft | null, w: PlanDraft) => p !== null && p.good === w.good && p.buyAt === w.buyAt && p.sellAt === w.sellAt
  const tripPlan = want && matches(plan, want) ? plan : null
  useEffect(() => {
    if (want && !matches(plan, want)) openPlan(want)
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `want` is rebuilt every render; its three keys are the dependency
  }, [want?.good, want?.buyAt, want?.sellAt, plan, openPlan])
  const trip = useTripBoard(fleet, tripPlan)
  const choices = useMemo(() => (sellAt ? saleChoices(trip.board, city, sellAt.port, pickedSale?.port ?? null) : null), [sellAt, trip.board, city, pickedSale])
  const choose = (to: string) => {
    if (!sellAt || to === sellAt.port) return
    setSellAt({ port: to, units: tripPlan?.units ?? sellAt.units })
  }

  if (!row || !row.goodId || price === null) return null
  return (
    <div data-testid="hq-sheet-trade">
      <TradePanel
        key={`${city}:${row.code}:${side}:${here && !sellAt ? 'here' : 'trip'}:${sellAt?.port ?? ''}`}
        side={side}
        fleet={fleet}
        city={city}
        good={{
          good_id: row.goodId,
          code: row.code,
          name: row.name,
          category: row.category,
          rarity: row.row?.rarity,
          class: row.row?.class ?? goodByCode[row.code]?.class,
          price,
        }}
        market={row.row}
        docked={here && !sellAt}
        sellAt={sellAt?.port ?? null}
        noGain={side === 'buy' && pickedSale !== undefined && !pickedSale.pays && !pickedSale.short}
        trip={trip}
        mode="docked"
        choices={choices}
        onChoose={choose}
        onClose={back}
        onDone={(d) => {
          onDone(d)
          // a trip sent: she has left, the sheet goes; a trade where she lies keeps the sheet, for the next lot
          if (d.sailTo !== null) back()
        }}
      />
    </div>
  )
}

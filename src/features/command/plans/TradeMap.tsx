import { useCallback, useEffect, useMemo, useRef } from 'react'
import { openingBounds, SmallChart, type PathStop } from '../../../chart'
import { Button, Figure, Hint, Icon, Row } from '../../../components/ui'
import { routeOfFleet } from '../../../domain/route'
import { useGoodBoard } from '../../../live/useDesk'
import { useRouteBoard } from '../../../live/useRouteBoard'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { formatPriceDelta, formatTwoClocks, formatVoyageDays, instantMs, realMsToVoyageDays } from '../../../lib/format'
import { unwrapLongitudes, WORLD_BOUNDS, type LatLon } from '../../../lib/geo'
import type { FleetView, GoodBoard } from '../../../lib/rpc'
import { useT } from '../../../lib/i18n'
import { orderTrips, tripOf, type OrderTrip } from '../../../domain/order'
import { daysAt, type PlanLeg } from '../../../domain/passage'
import { seaTagWords, tripRows } from './planLines'
import { useSailLegs } from '../../../live/useSailLegs'

// THE MAP ON TOP OF THE BUY AND SELL FACES, AND THE ORDER'S ESTIMATE UNDER IT — the owner, 2026-10-26 (row 217):
//
//     "on command, trade, map should be at top. when i press my order, i should be able to see the route, time,
//      money, profit all on estimate below the map + map"
//
// ONE MAP: `SmallChart`, the chart the Map tab draws with, at 0 % zoom (row 207, `wholeWorld`), only this fleet and
// only the harbours of what it shows (row 183: no merchants, no other city). What it shows, first match wins:
//   · AN ORDER PRESSED (Trade.tsx holds the press) — a queued trip, the voyage under way, or the standing route:
//     its legs and harbours, and under the map THE ESTIMATE: Route, Time, Cost, Supplies, Wages, Tax, Fee, Profit;
//   · the plan being made (the trade card's legs, usePlanCourse.ts);
//   · her position, and her voyage when she is under way (the fleet layer draws her track).
//
// EVERY FIGURE IS SERVED, nothing is added up here:
//   · a queued trip that trades one good is the trade card's plan again (orderTrip.ts), and its figures are THE
//     board's — world.good_board FROM its buy city FOR its units, read through `tripRows`, the card's own reading;
//   · the standing route: its stops' served courses, the route board's served miles a lap (route_nm) and average
//     lap net (route_earnings), and the last closed lap's served bought / supplies / wages;
//   · a raw SAIL (no good traded): the route and the time only, and one line saying no money estimate is served.
// THE CITIES (owner row 218, 2026-10-26: *"in mini map in command, show cities, when pressed upon, show trade goods
// with prices, and charts"*): with no order pressed the map draws EVERY harbour the Map tab draws (no `only`), the
// city in hand ringed and named (`highlight`), and a harbour pressed is handed to `onCity` (SmallChart's `onPort`,
// THE map tab's hit test). An order pressed narrows it back to that order's harbours, as row 183/217 drew them.
//
// ROW 191 (docs/COMMAND_REDESIGN.md §3): WHILE THE PLAN IS BEING MADE the map is THE MINI ROUTE MAP — the plan's
// stops only, numbered 1..n with the start marked "Now", framed on the legs by the chart's own opening rule
// (`openingBounds`), and STILL: no pan, no zoom, no live fleets layer, no controls; it redraws only when the legs
// change. Under it stands one line per leg — its number, from → to, the days, and the sea's one short ask, printed
// from the served `sea` field and never compared (`seaTagWords`). An order pressed still draws its estimate.
//
// Time is printed in both clocks (`formatTwoClocks`); days at sea from miles are `daysAt`, the plan's one arithmetic.

export type OrderPick = { kind: 'order'; id: string } | { kind: 'voyage' } | { kind: 'route' }

export interface MapDrawing {
  legs: readonly PlanLeg[]
  /** Port CODES ringed as the choice. */
  ends: readonly string[]
  /** Row 191: the board the plan's legs were read from — its rows' served `sea` is the legs' tag. */
  board?: GoodBoard | null
}

/** One frozen empty list, so the plan's chart — which draws NO live fleets layer — allocates nothing per frame. */
const NO_FLEETS: readonly FleetView[] = []

export function TradeMap({
  fleet,
  plan,
  pick,
  onClose,
  scrollOnPick,
  city,
  onCity,
  goTo = null,
}: {
  fleet: FleetView
  /** Row 231: the last city PRESSED (map, chip strip, cargo list) and a press count — the map glides to it. */
  goTo?: { code: string; n: number } | null
  /** Row 218: the city in hand (ringed, named). */
  city: string | null
  /** Row 218: a harbour pressed on the map. */
  onCity: (code: string) => void
  /** The plan being made, when its card is up (drawn when no order is pressed). */
  plan: MapDrawing | null
  pick: OrderPick | null
  onClose: () => void
  /** A phone: an order pressed below brings the map up to it. */
  scrollOnPick: boolean
}) {
  const t = useT()
  const snapshot = useWorld((s) => s.snapshot)
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const book = useWorld((s) => s.routes)
  const boxRef = useRef<HTMLDivElement>(null)
  const name = (code: string) => portNameOf(portByCode, code)

  const trips = useMemo(
    () => orderTrips(fleet, (c) => c in portByCode, (c) => c in goodByCode),
    [fleet, portByCode, goodByCode],
  )
  const trip = pick && pick.kind !== 'route' ? tripOf(trips, fleet, pick) : null
  const route = pick?.kind === 'route' ? routeOfFleet(book, fleet.id) : null
  const tripLegs = useSailLegs(fleet, trip?.stops ?? [])

  // WHAT THE MAP DRAWS — the pressed order, else the plan, else where she is.
  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  const routeLegs = useMemo(
    () => (route ? route.stops.map((s, i) => ({ from: s.port, to: route.stops[(i + 1) % route.stops.length].port, path: s.course, nm: 0 })) : null),
    [route],
  )
  const voyageLegs = useMemo(
    () => (fleet.voyage && fleet.voyage.course.length > 1 ? [{ from: docked, to: fleet.voyage.to ?? '', path: fleet.voyage.course, nm: 0 }] : []),
    [fleet.voyage, docked],
  )
  const drawing: MapDrawing = routeLegs
    ? { legs: routeLegs, ends: route?.stops.map((s) => s.port) ?? [] }
    : pick && trip
      ? // a trip whose SAIL has already left (she is on its way): the voyage under way is its course (row 229 —
        // a near city is one leg, and that leg runs at once)
        { legs: tripLegs.length > 0 ? tripLegs : voyageLegs, ends: [trip.plan?.buyAt, trip.plan?.sellAt ?? trip.stops[trip.stops.length - 1]].filter((c): c is string => !!c) }
      : pick?.kind === 'voyage'
        ? { legs: voyageLegs, ends: fleet.voyage?.to ? [fleet.voyage.to] : [] }
        : (plan ?? { legs: [], ends: fleet.voyage?.to ? [fleet.voyage.to] : [] })

  // ROW 191: THE PLAN BEING MADE IS THE PLAN'S OWN MINI ROUTE MAP — its stops only, numbered, and still.
  const planMap = pick === null && plan !== null && plan.legs.length > 0
  const planCodesKey = useMemo(
    () => (planMap && plan ? [...new Set(plan.legs.map((l) => l.to))].join(' ') : ''),
    [planMap, plan],
  )
  // THE FRAME, by the chart's own opening rule (the one the tab and this chart open with), asked for the plan's
  // legs — their water AND their stops' own marks — so a short plan is never framed to nothing, and no stop is
  // left on the glass's edge. The floor and the aspect arithmetic are `openingBounds`'s, never a second fit.
  const frame = useCallback(
    (aspect: number) => {
      if (!planMap || !plan) return WORLD_BOUNDS
      const pts: LatLon[] = []
      for (const l of plan.legs) {
        for (const [lat, lon] of l.path) pts.push({ lat, lon })
        const port = portByCode[l.to]
        if (port) pts.push({ lat: port.lat, lon: port.lon })
      }
      const round = unwrapLongitudes(pts)
      return openingBounds(round, round, round, aspect)
    },
    [planMap, plan, portByCode],
  )
  // THE STOPS, NUMBERED, AND THE START SAID "NOW" — the chart's own path-stop layer (owner row 225) draws them;
  // the days ride the leg lines under the map, not the discs, so the picture stays concise.
  const pathStops = useMemo<readonly PathStop[]>(() => {
    if (!planMap || !plan) return []
    const out: PathStop[] = []
    const start = plan.legs[0]?.path[0]
    if (start) out.push({ at: { lat: start[0], lon: start[1] }, n: 0, days: null, label: t('desk.now') })
    plan.legs.forEach((leg, i) => {
      const end = leg.path[leg.path.length - 1]
      if (end) out.push({ at: { lat: end[0], lon: end[1] }, n: i + 1, days: null })
    })
    return out
  }, [planMap, plan, t])

  const onlyKey = [docked, fleet.voyage?.to ?? null, ...drawing.legs.flatMap((l) => [l.from, l.to]), ...drawing.ends]
    .filter((c): c is string => !!c)
    .filter((c, i, all) => all.indexOf(c) === i)
    .join(' ')
  // every harbour, unless an order is pressed (its harbours only) — and, under a plan, its stops only
  const only = useMemo(() => {
    if (planMap) return planCodesKey ? planCodesKey.split(' ') : undefined
    return pick && onlyKey ? onlyKey.split(' ') : undefined
  }, [planMap, planCodesKey, pick, onlyKey])
  const endsKey = drawing.ends.join(' ')
  const considering = useMemo(
    () => (planMap ? (planCodesKey ? planCodesKey.split(' ') : []) : endsKey ? endsKey.split(' ') : []),
    [planMap, planCodesKey, endsKey],
  )
  const courses = useMemo(() => drawing.legs.map((l) => l.path.map(([lat, lon]) => ({ lat, lon }))), [drawing.legs])

  // A PHONE: the order is pressed at the foot of the page; the map and its estimate come up to meet it.
  const pickKey = pick ? (pick.kind === 'order' ? pick.id : pick.kind) : null
  useEffect(() => {
    if (pickKey && scrollOnPick) boxRef.current?.scrollIntoView({ block: 'start', behavior: 'smooth' })
  }, [pickKey, scrollOnPick])

  return (
    <section ref={boxRef} className="mb-4 scroll-mt-28" data-testid="trade-map" data-cities={only ? only.join(' ') : '*'}>
      <SmallChart
        ports={snapshot?.ports ?? []}
        fleets={planMap ? NO_FLEETS : [fleet]}
        considering={considering}
        highlight={planMap ? null : pick ? null : city}
        only={only}
        legs={courses}
        stops={pathStops}
        still={planMap}
        frame={frame}
        wholeWorld={!planMap}
        onPort={planMap ? undefined : onCity}
        goTo={planMap ? null : goTo}
        ariaLabel={t(planMap ? 'desk.routeChart' : pick ? 'desk.mapChart' : 'desk.citiesChart')}
        className="aspect-[2/1] w-full"
      />
      {planMap && plan && <PlanLegs legs={plan.legs} ends={plan.ends} board={plan.board ?? null} speedKn={fleet.speed_kn} name={name} />}
      {pick && (
        <OrderEstimate
          key={pickKey ?? ''}
          fleet={fleet}
          pick={pick}
          trip={trip}
          legs={pick.kind === 'route' ? [] : trip ? tripLegs : voyageLegs}
          onClose={onClose}
        />
      )}
    </section>
  )
}

/** THE PLAN'S LEGS UNDER ITS MAP (owner row 191, docs/COMMAND_REDESIGN.md §3) — one line per leg: its number,
 *  where it leaves and where it ends, the days at this fleet's speed (`daysAt`, the plan's one arithmetic), and
 *  — where the row the leg ENDS at serves a `sea` — the sea's one short ask, printed from the server's field and
 *  never compared (`seaTagWords`). An intermediate stop wears no tag: it is not the plan's end. */
function PlanLegs({
  legs,
  ends,
  board,
  speedKn,
  name,
}: {
  legs: readonly PlanLeg[]
  /** The plan's own ends (buyAt / sellAt): only a leg ending AT one wears that row's sea tag. */
  ends: readonly string[]
  board: GoodBoard | null
  speedKn: number
  name: (code: string) => string
}) {
  const t = useT()
  return (
    <ol className="mt-2 flex flex-col" data-testid="plan-legs">
      {legs.map((leg, i) => {
        const row =
          board && ends.includes(leg.to)
            ? (board.buy.find((r) => r.port === leg.to) ?? board.sell.find((r) => r.port === leg.to) ?? null)
            : null
        const tag = row?.sea && board?.sea ? seaTagWords(row.sea, board.sea.bite) : null
        const days = speedKn > 0 ? formatVoyageDays(daysAt(leg.nm, speedKn)) : '—'
        return (
          <li
            key={`${i}:${leg.to}`}
            className="text-t-caption tabular-nums text-ink-muted"
            data-testid="plan-leg"
            data-n={i + 1}
            data-from={leg.from ?? ''}
            data-to={leg.to}
          >
            {`${i + 1} ${t('desk.legLine', { from: leg.from ? name(leg.from) : t('desk.atSea'), to: name(leg.to) })} · ${days}${tag ? ` · ${tag}` : ''}`}
          </li>
        )
      })}
    </ol>
  )
}

/** THE ESTIMATE UNDER THE MAP — every row always drawn ("—" while a figure is unknown or not served). */
function OrderEstimate({
  fleet,
  pick,
  trip,
  legs,
  onClose,
}: {
  fleet: FleetView
  pick: OrderPick
  trip: OrderTrip | null
  legs: readonly PlanLeg[]
  onClose: () => void
}) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const name = (c: string) => portNameOf(portByCode, c)
  return (
    <div className="mt-3 rounded-md border border-edge px-3 pb-2 pt-1" data-testid="order-estimate">
      <div className="flex items-center justify-between">
        <h3 className="text-t-body font-semibold text-ink">{t('desk.estimate')}</h3>
        <Button variant="quiet" size="icon" aria-label={t('common.close')} onClick={onClose} data-testid="order-estimate-close">
          <Icon name="close" size={18} />
        </Button>
      </div>
      {pick.kind === 'route' ? (
        <RouteEstimate fleet={fleet} name={name} />
      ) : trip?.plan ? (
        <TripEstimate fleet={fleet} trip={trip} name={name} />
      ) : (
        <PassageEstimate fleet={fleet} trip={trip} legs={legs} name={name} />
      )}
    </div>
  )
}

function RouteLine({ ports }: { ports: string[] }) {
  const t = useT()
  return (
    <Row
      label={t('desk.route')}
      value={undefined}
      data-testid="est-route"
    >
      <span className="block break-words text-t-caption text-ink" data-testid="est-route-stops">
        {ports.length > 0 ? ports.join(' → ') : '—'}
      </span>
    </Row>
  )
}

function TimeLine({ days }: { days: number | null }) {
  const t = useT()
  return (
    <Row label={t('desk.time')} data-testid="est-time" value={undefined}>
      <span className="block text-t-caption text-ink">{days !== null && Number.isFinite(days) ? formatTwoClocks(days) : '—'}</span>
    </Row>
  )
}

function Money({ label, value, id, last = false, profit = false }: { label: string; value: number | null | undefined; id: string; last?: boolean; profit?: boolean }) {
  const shown = value === null || value === undefined ? '—' : formatPriceDelta(profit ? value : -value)
  const tone = !profit || value == null ? 'ink' : value >= 0 ? 'success' : 'danger'
  return <Row label={label} value={<Figure value={shown} tone={tone} size={profit ? 'figure' : undefined} />} hairline={!last} data-testid={id} />
}

/** A trip that trades one good: THE board's figures for it (the trade card's reading). */
function TripEstimate({ fleet, trip, name }: { fleet: FleetView; trip: OrderTrip; name: (c: string) => string }) {
  const t = useT()
  const goodByCode = useWorld((s) => s.goodByCode)
  const portByCode = useWorld((s) => s.portByCode)
  const plan = trip.plan
  const good = plan ? (goodByCode[plan.good] ?? null) : null
  const buyPort = plan?.buyAt ? (portByCode[plan.buyAt] ?? null) : null
  const board = useGoodBoard(good?.id ?? null, fleet.id, fleet.version, plan?.buyAt ? plan.units : null, buyPort?.id ?? null)
  const rows = tripRows(board.view, plan ?? { buyAt: null, sellAt: null })
  const { buyRow, sellRow, supplies } = rows
  // a trip whose SAIL has already left: its time is the voyage under way (its served instants, as PassageEstimate reads them)
  const eta = instantMs(fleet.voyage?.eta)
  const left = instantMs(fleet.voyage?.departed_at)
  const days = rows.days ?? (trip.stops.length === 0 && eta !== null && left !== null ? realMsToVoyageDays(eta - left) : null)
  // a trip whose SAIL has already left: the voyage under way is its route (row 229 — a near city is one leg)
  const ports =
    trip.stops.length > 0 || !fleet.voyage?.to
      ? [trip.start, ...trip.stops].filter((c): c is string => !!c).map(name)
      : [fleet.port ? name(fleet.port) : t('desk.atSea'), name(fleet.voyage.to)]
  return (
    <>
      <RouteLine ports={ports} />
      <TimeLine days={days} />
      <Money label={t('desk.cost')} value={plan?.buyAt ? buyRow?.cost : 0} id="est-cost" />
      <Money label={t('desk.supplies')} value={supplies?.cost} id="est-supplies" />
      <Money label={t('desk.wages')} value={sellRow?.wages} id="est-wages" />
      <Money label={t('desk.tax')} value={sellRow?.profit_tax} id="est-tax" />
      <Money label={t('desk.fee')} value={sellRow?.port_fee} id="est-fee" />
      <Money label={t('desk.profit')} value={sellRow?.profit} id="est-profit" profit last />
    </>
  )
}

/** A raw SAIL, or the voyage under way with no trade behind it: the route and the time; no money is served. */
function PassageEstimate({ fleet, trip, legs, name }: { fleet: FleetView; trip: OrderTrip | null; legs: readonly PlanLeg[]; name: (c: string) => string }) {
  const t = useT()
  const v = fleet.voyage
  const eta = instantMs(v?.eta)
  const left = instantMs(v?.departed_at)
  // the voyage under way: its served instants; a queued SAIL: the legs' days at her speed
  const days =
    !trip && eta !== null && left !== null
      ? realMsToVoyageDays(eta - left)
      : fleet.speed_kn > 0 && legs.length > 0
        ? legs.reduce((d, l) => d + daysAt(l.nm, fleet.speed_kn), 0)
        : null
  const ports = (trip ? [trip.start, ...trip.stops] : [fleet.port, v?.to ?? null]).filter((c): c is string => !!c).map(name)
  return (
    <>
      <RouteLine ports={ports} />
      <TimeLine days={days} />
      <Money label={t('desk.cost')} value={null} id="est-cost" />
      <Money label={t('desk.profit')} value={null} id="est-profit" profit last />
      <Hint data-testid="est-no-money">{t('desk.noMoneyServed')}</Hint>
    </>
  )
}

/** The standing route: the route board's lap (miles, average net) and the last closed lap's money. */
function RouteEstimate({ fleet, name }: { fleet: FleetView; name: (c: string) => string }) {
  const t = useT()
  const book = useWorld((s) => s.routes)
  const route = routeOfFleet(book, fleet.id)
  const board = useRouteBoard()
  const row = route ? (board.board?.routes.find((r) => r.id === route.id) ?? null) : null
  const lap = route?.laps[0] ?? null
  const ports = route ? [...route.stops.map((s) => s.port), route.stops[0]?.port].filter((c): c is string => !!c).map(name) : []
  return (
    <>
      <RouteLine ports={ports} />
      <TimeLine days={row?.nm != null && fleet.speed_kn > 0 ? daysAt(row.nm, fleet.speed_kn) : null} />
      <span className="mt-2 block text-t-caption text-ink-faint">{t('desk.lastLap')}</span>
      <Money label={t('desk.cost')} value={lap?.bought} id="est-cost" />
      <Money label={t('desk.supplies')} value={lap?.supplies} id="est-supplies" />
      <Money label={t('desk.wages')} value={lap?.wages} id="est-wages" />
      <Money label={t('desk.profit')} value={row?.earnings.lap} id="est-profit" profit last />
    </>
  )
}

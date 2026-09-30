import { useEffect, useMemo, useState } from 'react'
import { Button, Chip, Field, Hint, Icon, Note, goodIcon } from '../../components/ui'
import { routeStopQuiet, stopLine, type StopLine } from '../../domain/route'
import { PortField } from '../../live/PortField'
import { usePress } from '../../live/usePress'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { FleetView, Refusal, StandingRoute } from '../../lib/rpc'
import { draftOfRoute, emptyStop, routeName, routePayload, type RouteStopDraft } from './standingRouteDraft'
import { RouteStopBlock, StopLineRow, StopPortRow } from './RouteStop'

// THE ROUTE EDITOR — inside RouteFold, in place (docs/TRADE_ROUTES.md §7). Slice 1's scope, and
// no more: two stops — where the fleet lies, and one port picked with THE port field (the same
// field PORT uses, src/live/PortField.tsx) — and at each stop "sell all" and one BUY (a good this
// port's market offers, how many units, the Max each). Each stop is RouteStop.tsx's block — its
// SELL group above its BUY group, the same skeleton the running route is read in (owner,
// 2026-09-30: "sell all buy all is ... in one line and not distinguished"). The keep level is FLEETS' own control; the
// server refuses a fleet without one (E_NO_KEEP) and the refusal is printed here in its words.
//
// NO FIGURES ARE MADE HERE. The goods offered at a stop are the port's served market; the course of
// each leg comes from the one course author (standingRouteDraft.ts → proposeCourse); whether the
// route is legal, affordable or sensible is the server's to say — at save, at assign, and at every
// stop, where a refused line is written on the lap. The editor never ranks or suggests a port
// (0071: the owner removed cross-port comparison — "the game is to challenge players").

export function RouteEditor({
  fleet,
  route,
  onDone,
}: {
  fleet: FleetView
  /** The route being changed, or null for a new one. */
  route: StandingRoute | null
  onDone: () => void
}) {
  const portByCode = useWorld((s) => s.portByCode)
  const seaNav = useWorld((s) => s.seaNav)
  const markets = useWorld((s) => s.markets)
  const goodByCode = useWorld((s) => s.goodByCode)
  const loadMarket = useWorld((s) => s.loadMarket)
  const saveRoute = useWorld((s) => s.saveRoute)
  const assignRoute = useWorld((s) => s.assignRoute)
  // Start / Save is busy only while ITS press is on the wire — never on the world's beat (the
  // owner, 2026-09-30: "Start route in command ... blinks occasionally on its own").
  const press = usePress()

  const home = fleet.port
  const [stops, setStops] = useState<RouteStopDraft[]>(() =>
    route ? draftOfRoute(route) : home ? [emptyStop(home), emptyStop('')] : [],
  )
  // A route saved but not yet started (its assign was refused) is saved AGAIN on the next press,
  // never duplicated: the id is kept here. Once this editor closes, the fold lists that route
  // under "No fleet" (routesWithoutFleet) and it is started, edited or deleted from there.
  const [savedId, setSavedId] = useState<string | null>(route?.id ?? null)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const [noCourse, setNoCourse] = useState<string | null>(null)

  // The goods a stop may buy are what ITS market offers — read, never assumed.
  const portIds = useMemo(
    () => stops.map((s) => portByCode[s.port]?.id).filter((id): id is string => Boolean(id)),
    [stops, portByCode],
  )
  useEffect(() => {
    for (const id of portIds) if (!markets[id]) void loadMarket(id)
  }, [portIds, markets, loadMarket])

  if (!home && !route) {
    return <Note tone="neutral">Set up a route while {fleet.name} is in port.</Note>
  }

  const set = (i: number, patch: Partial<RouteStopDraft>) =>
    setStops((was) => was.map((s, j) => (j === i ? { ...s, ...patch } : s)))
  const complete = stops.length >= 2 && stops.every((s) => s.port !== '') && stops[0].port !== stops[1].port

  const start = async () => {
    setRefusal(null)
    setNoCourse(null)
    if (!seaNav) return
    const payload = routePayload(stops, seaNav, portByCode)
    if (!payload.ok) {
      setNoCourse(payload.noCourseFrom)
      return
    }
    const id = await saveRoute(savedId, routeName(stops, portByCode), payload.stops)
    if (!id) {
      setRefusal(useWorld.getState().refusal)
      return
    }
    setSavedId(id)
    // An edit of the route this fleet already runs takes effect at the next stop; nothing to start.
    if (route?.fleet?.id === fleet.id) {
      onDone()
      return
    }
    if (await assignRoute(id, fleet.id)) onDone()
    else setRefusal(useWorld.getState().refusal)
  }

  return (
    <div data-testid="route-editor">
      {stops.map((stop, i) => {
        const market = portByCode[stop.port] ? markets[portByCode[stop.port].id] : undefined
        const carried = carriedLines(stop, goodByCode)
        return (
          <div key={i} className="mt-3">
            <RouteStopBlock
              data-testid="route-editor-stop"
              last={i === stops.length - 1}
              header={
                i === 0 || route ? (
                  <StopPortRow port={stop.port} />
                ) : (
                  <PortField
                    current={stop.port ? (portByCode[stop.port] ?? null) : null}
                    anchor={home}
                    onPick={(code) => set(i, { port: code, buyGood: null })}
                  />
                )
              }
              sell={
                <>
                  <div className="py-2">
                    <Chip
                      on={stop.sellAll}
                      onClick={() => set(i, { sellAll: !stop.sellAll })}
                      data-testid="route-sell-all"
                    >
                      <Icon name="ship" size={16} />
                      Everything on board
                    </Chip>
                  </div>
                  {carried.sell.map((l) => (
                    <StopLineRow key={l.key} line={l} />
                  ))}
                </>
              }
              buy={
                <>
                  {/* Only what THIS market sells: a row with `offered: false` is a good a fleet here is
                      carrying (do_buy refuses it, E_UNAVAILABLE), and `available: false` is refused by
                      the port's culture — a BUY of either would be stepped over on every lap. The group
                      already says Buy, so each chip is the good alone, with its own mark. */}
                  <div className="flex min-h-15 flex-wrap gap-2 py-2">
                    {(market?.goods ?? []).filter((g) => g.offered !== false && g.available).map((g) => (
                      <Chip
                        key={g.code}
                        on={stop.buyGood === g.code}
                        onClick={() => set(i, { buyGood: stop.buyGood === g.code ? null : g.code })}
                        data-testid="route-buy-good"
                      >
                        <Icon name={goodIcon(g.code, g.category)} size={16} />
                        {g.name}
                      </Chip>
                    ))}
                  </div>
                  {carried.buy.map((l) => (
                    <StopLineRow key={l.key} line={l} />
                  ))}
                  {/* ALWAYS DRAWN once a port is picked, and only enabled by a picked good: pressing a
                      chip must not push the page down (owner row 15). */}
                  {stop.port !== '' && (
                    <div className="flex gap-2 pb-2" data-testid="route-buy-fields">
                      <Field
                        icon={null}
                        inputMode="numeric"
                        aria-label="Units to buy"
                        placeholder="Units (blank: all that fit)"
                        disabled={!stop.buyGood}
                        value={stop.buyUnits === null ? '' : String(stop.buyUnits)}
                        onChange={(e) => set(i, { buyUnits: wholeOrNull(e.target.value) })}
                        className="flex-1"
                      />
                      <Field
                        icon={null}
                        inputMode="numeric"
                        aria-label="Max price each"
                        placeholder="Max each (blank: any)"
                        disabled={!stop.buyGood}
                        value={stop.buyMax === null ? '' : String(stop.buyMax)}
                        onChange={(e) => set(i, { buyMax: wholeOrNull(e.target.value) })}
                        className="flex-1"
                      />
                    </div>
                  )}
                </>
              }
              quiet={routeStopQuiet(stop.repair)}
            />
          </div>
        )
      })}

      <Hint className="mt-3">The fleet sails this loop by itself, and History shows each lap.</Hint>
      {noCourse && (
        <Note tone="danger" className="mt-2">
          No sea route from {portNameOf(portByCode, noCourse)} to the next stop.
        </Note>
      )}
      {refusal && (
        <Note tone="danger" code={refusal.code} className="mt-2" data-testid="route-refusal">
          {refusal.sentence}
        </Note>
      )}
      <div className="mt-3 flex gap-2">
        <Button
          variant="primary"
          className="flex-1"
          disabled={!complete || !seaNav}
          busy={press.pending}
          onClick={() => void press.run(start)}
          data-testid="route-start"
        >
          {route?.fleet ? 'Save route' : 'Start route'}
        </Button>
        <Button variant="quiet" className="flex-1" onClick={onDone}>
          Cancel
        </Button>
      </div>
    </div>
  )
}

/** What a stop does that the editor has no control for (0093 NIT 11), drawn read-only so nothing
 *  a route does is hidden: a named SELL, a floor on "everything on board", a second BUY. */
function carriedLines(
  stop: RouteStopDraft,
  goodByCode: Parameters<typeof stopLine>[1],
): { sell: StopLine[]; buy: StopLine[] } {
  const floor = stop.sellAllFloor
  const sell = stop.kept.filter((l) => l.kind === 'SELL').map((l) => stopLine(l, goodByCode))
  if (stop.sellAll && (floor.price_limit !== null || floor.at_profit)) {
    sell.push(stopLine({ ord: -1, kind: 'SELL', good: null, qty: null, ...floor }, goodByCode))
  }
  return { sell, buy: stop.kept.filter((l) => l.kind === 'BUY').map((l) => stopLine(l, goodByCode)) }
}

/** A typed whole number, or null for blank / not a number. The server judges whether it is sane. */
function wholeOrNull(text: string): number | null {
  const n = Number.parseInt(text.replace(/[^0-9]/g, ''), 10)
  return Number.isFinite(n) && n > 0 ? n : null
}

import { useEffect, useMemo, useState } from 'react'
import { Button, Chip, Field, Hint, Note, Row } from '../../components/ui'
import { PortField } from '../../live/PortField'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { FleetView, Refusal, StandingRoute } from '../../lib/rpc'
import { draftOfRoute, emptyStop, routeName, routePayload, type RouteStopDraft } from './standingRouteDraft'

// THE ROUTE EDITOR — inside RouteFold, in place (docs/TRADE_ROUTES.md §7). Slice 1's scope, and
// no more: two stops — where the fleet lies, and one port picked with THE port field (the same
// field PORT uses, src/live/PortField.tsx) — and at each stop "sell all" and one BUY (a good this
// port's market offers, how many units, the Max each). The keep level is FLEETS' own control; the
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
  const loadMarket = useWorld((s) => s.loadMarket)
  const busy = useWorld((s) => s.busy)
  const saveRoute = useWorld((s) => s.saveRoute)
  const assignRoute = useWorld((s) => s.assignRoute)

  const home = fleet.port
  const [stops, setStops] = useState<RouteStopDraft[]>(() =>
    route ? draftOfRoute(route) : home ? [emptyStop(home), emptyStop('')] : [],
  )
  // A route saved but not yet started (its assign was refused) is saved AGAIN on the next press,
  // never duplicated: the id is kept here.
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
        return (
          <div key={i} className="mt-3" data-testid="route-editor-stop">
            {i === 0 || route ? (
              <Row label={portNameOf(portByCode, stop.port)} hairline={false} />
            ) : (
              <PortField
                current={stop.port ? (portByCode[stop.port] ?? null) : null}
                anchor={home}
                onPick={(code) => set(i, { port: code, buyGood: null })}
              />
            )}
            {stop.port !== '' && (
              <>
                <div className="mt-2 flex flex-wrap gap-2">
                  <Chip on={stop.sellAll} onClick={() => set(i, { sellAll: !stop.sellAll })}>
                    Sell all
                  </Chip>
                  {(market?.goods ?? []).map((g) => (
                    <Chip
                      key={g.code}
                      on={stop.buyGood === g.code}
                      onClick={() => set(i, { buyGood: stop.buyGood === g.code ? null : g.code })}
                      data-testid="route-buy-good"
                    >
                      Buy {g.name}
                    </Chip>
                  ))}
                </div>
                {stop.buyGood && (
                  <div className="mt-2 flex gap-2">
                    <Field
                      icon={null}
                      inputMode="numeric"
                      aria-label="Units to buy"
                      placeholder="Units (blank: all that fit)"
                      value={stop.buyUnits === null ? '' : String(stop.buyUnits)}
                      onChange={(e) => set(i, { buyUnits: wholeOrNull(e.target.value) })}
                      className="flex-1"
                    />
                    <Field
                      icon={null}
                      inputMode="numeric"
                      aria-label="Max price each"
                      placeholder="Max each (blank: any)"
                      value={stop.buyMax === null ? '' : String(stop.buyMax)}
                      onChange={(e) => set(i, { buyMax: wholeOrNull(e.target.value) })}
                      className="flex-1"
                    />
                  </div>
                )}
              </>
            )}
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
        <Button variant="primary" className="flex-1" disabled={busy || !complete || !seaNav} onClick={() => void start()} data-testid="route-start">
          {route ? 'Save route' : 'Start route'}
        </Button>
        <Button variant="quiet" className="flex-1" onClick={onDone}>
          Cancel
        </Button>
      </div>
    </div>
  )
}

/** A typed whole number, or null for blank / not a number. The server judges whether it is sane. */
function wholeOrNull(text: string): number | null {
  const n = Number.parseInt(text.replace(/[^0-9]/g, ''), 10)
  return Number.isFinite(n) && n > 0 ? n : null
}

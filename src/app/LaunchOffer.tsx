import { useEffect, useRef, useState } from 'react'
import { Button, FLOAT_CARD_CLASS, Icon, Note, glassBesideRailClass } from '../components/ui'
import { fleetCrew, whereabouts } from '../domain/fleet'
import { bestRouteAt, portsLine } from '../domain/route'
import { cmdMoveShip, type FleetView, type LedgerEvent, type Refusal } from '../lib/rpc'
import { str } from '../lib/json'
import { useT } from '../lib/i18n'
import { draftOfRoute, tripRoute, type RouteStopDraft } from '../live/standingRouteDraft'
import { saveAndStartRoute } from '../live/startRoute'
import { servedGoods, useWorld } from '../live/worldStore'
import { ShipPicture } from '../features/fleets/ShipPicture'
import { useShipMoves } from '../features/fleets/useShipMoves'

// THE SECOND HULL EARNS WHILE SHE IS AWAY (2026-11-23, the roadmap's slice 6, docs/design/roadmap-2026-11-23.md; play-test 3
// finding 26: "Andorinha launched" joined Gaivota's fleet and sailed empty beside her). The moment a hull joins her fleet, one card
// asks the one question: "Own fleet" (the hull leads a fleet of its own, running her best route at once) or "Join Gaivota" (it
// stays, as it already is). NO NEW SERVER DOOR: every step is one the game already has.
//
//   1. THE HULL'S OWN FLEET: `cmd.move_ship` with a new name (the Fleets page's New fleet, NewFleet.tsx), the fleet named after
//      the hull. Offered only while the server says this fleet may found one (`world.ship_moves`, `can_new`: fleet room, docked).
//   2. ITS CREW: a hull is laid down with no hands, and a route cannot sail short. When the new fleet is short, `HIRE n` (the yard's
//      "Hire crew · n" count, `fleetCrew(...).short`) through the store's one `issue` door.
//   3. HER BEST ROUTE, REPEATED: a copy of the saved route that calls here with the highest all-time net (domain/route
//      `bestRouteAt`), else her last trip from or to this harbour made a route (`tripRoute`, the arrival card's "Make route"),
//      saved and started on the new fleet through THE one path (startRoute.ts → cmd.standing_route_save, cmd.standing_route_assign).
//      Offered only while routes are lit and under the served `max`.
// A step the server refuses stops there with its sentence; the next press goes on from the step that is not done.
//
// "A HULL JOINED HER FLEET", decided by default: between two reads of the world in this visit, a ship id that no fleet of hers held
// appeared in a fleet she already had, lying in a harbour, of two ships or more. The first read is the baseline (a load announces
// nothing), so a ship moved between fleets (its id was held) or a fleet founded is never an offer. A hull launched, or built, is.
//
// An overlay at the TOP of the glass, as the While away card: fixed, out of the flow; it stays until a press.

interface Launch {
  fleetId: string
  fleetName: string
  shipId: string
  shipName: string
  classCode: string | null
  port: string
}

/** Who holds which ship, in one read. */
function holders(fleets: readonly FleetView[]): Map<string, string> {
  const out = new Map<string, string>()
  for (const f of fleets) for (const s of f.ships) out.set(s.id, f.id)
  return out
}

/** The hull that joined one of her fleets since `before`, or null. */
function launchedSince(before: Map<string, string>, fleets: readonly FleetView[]): Launch | null {
  const known = new Set(before.values())
  for (const f of fleets) {
    if (!known.has(f.id) || f.ships.length < 2) continue
    const w = whereabouts(f)
    if (w.kind !== 'docked') continue
    const fresh = f.ships.find((s) => !before.has(s.id))
    if (fresh) return { fleetId: f.id, fleetName: f.name, shipId: fresh.id, shipName: fresh.name, classCode: fresh.class_code ?? null, port: w.port }
  }
  return null
}

/** Her last trip to or from `port` made a route (`tripRoute`), from the ledger the store holds; null when there is none. */
function lastTripFrom(port: string, fleetName: string, events: readonly LedgerEvent[]): RouteStopDraft[] | null {
  let at = ''
  let trip: { fleet: string; here: string; there: string } | null = null
  for (const e of events) {
    if (e.kind !== 'VOYAGE_REPORT' || str(e.payload, 'fleet') !== fleetName || e.at <= at) continue
    const from = str(e.payload, 'from')
    const to = str(e.payload, 'to')
    if (from === null || to === null || from === to) continue
    if (to === port) trip = { fleet: fleetName, here: port, there: from }
    else if (from === port) trip = { fleet: fleetName, here: port, there: to }
    else continue
    at = e.at
  }
  return trip ? tripRoute(trip, events, servedGoods()) : null
}

/** What the card offers to repeat, decided once when it comes up: the stops, or null for nothing to repeat. */
function routeToRepeat(launch: Launch): RouteStopDraft[] | null {
  const s = useWorld.getState()
  const book = s.routes
  if (!book?.enabled || book.routes.length >= book.max) return null
  const best = bestRouteAt(book, launch.port)
  if (best) return draftOfRoute(best)
  return lastTripFrom(launch.port, launch.fleetName, s.events)
}

export function LaunchOffer() {
  const [launch, setLaunch] = useState<Launch | null>(null)
  const seen = useRef<Map<string, string> | null>(null)

  useEffect(() => {
    const read = (s: ReturnType<typeof useWorld.getState>) => {
      if (s.phase !== 'ready' || s.fleets.length === 0) return
      const now = holders(s.fleets)
      if (seen.current) {
        const found = launchedSince(seen.current, s.fleets)
        if (found) setLaunch((was) => was ?? found)
      }
      seen.current = now
    }
    read(useWorld.getState())
    return useWorld.subscribe(read)
  }, [])

  if (launch === null) return null
  return <OfferCard key={launch.shipId} launch={launch} onClose={() => setLaunch(null)} />
}

function OfferCard({ launch, onClose }: { launch: Launch; onClose: () => void }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const refresh = useWorld((s) => s.refresh)
  const issue = useWorld((s) => s.issue)
  const moves = useShipMoves(launch.fleetId)
  const [stops] = useState(() => routeToRepeat(launch))
  const [own, setOwn] = useState<string | null>(null)
  const [savedId, setSavedId] = useState<string | null>(null)
  const [started, setStarted] = useState(false)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)

  // nothing to repeat, or the server says this fleet may not found one: no question to ask (the hull stays where it is)
  if (stops === null || (own === null && (moves === null || !moves.on || !moves.can_new))) return null

  const go = () => {
    if (busy) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const stop = (r: Refusal | null) => {
        setRefusal(r)
        setBusy(false)
      }
      // 1. her own fleet, named after her
      let fleetId = own
      if (fleetId === null) {
        const r = await cmdMoveShip(launch.shipId, null, launch.shipName.slice(0, 24))
        if (!r.ok) return stop(r.refusal)
        fleetId = r.value.fleet_id
        setOwn(fleetId)
        await refresh()
      }
      // 2. her crew, to what she needs to sail
      const fleet = useWorld.getState().fleets.find((f) => f.id === fleetId)
      const short = fleet ? fleetCrew(fleet).short : 0
      if (short > 0 && !(await issue(fleetId, `HIRE ${short}`, null))) return stop(useWorld.getState().refusal)
      // 3. the route, started on her
      const done = await saveAndStartRoute(stops, fleetId, savedId)
      if (done.id) setSavedId(done.id)
      if (done.ok) {
        setStarted(true)
        setBusy(false)
      } else stop('refusal' in done ? done.refusal : null)
    })()
  }

  return (
    <div className={`pointer-events-none ${glassBesideRailClass()} top-10 z-60 flex justify-center px-4`} data-testid="launch-offer-wrap">
      <div role="dialog" aria-label={t('yard.launched', { name: launch.shipName })} data-testid="launch-offer" className={FLOAT_CARD_CLASS}>
        <div className="flex items-center gap-3">
          <ShipPicture code={launch.classCode} tone="var(--color-accent)" />
          <div className="min-w-0">
            <p className="break-words text-t-label font-semibold">{t('yard.launched', { name: launch.shipName })}</p>
            <p className="flex items-center gap-1 text-t-caption text-ink-muted" data-testid="launch-offer-route">
              <Icon name="route" size={16} className="shrink-0 text-accent" />
              <span className="min-w-0 break-words">{portsLine(stops.map((s) => s.port), portByCode)}</span>
            </p>
          </div>
        </div>
        {refusal && (
          <Note tone="danger" code={refusal.code} figures={refusal.figures} className="mt-2" data-testid="launch-offer-refusal">
            {refusal.sentence}
          </Note>
        )}
        <div className="mt-3 flex gap-2">
          <Button
            variant="primary"
            size="sm"
            className="flex-1"
            busy={busy}
            disabled={started}
            data-testid="launch-offer-own"
            data-started={started ? 'true' : 'false'}
            onClick={go}
          >
            {started ? t('domain.onRoute') : t('fleets.ownFleet')}
          </Button>
          <Button variant="secondary" size="sm" className="flex-1" disabled={busy} data-testid="launch-offer-close" onClick={onClose}>
            {started || own !== null ? t('feed.close') : t('fleets.joinFleet', { name: launch.fleetName })}
          </Button>
        </div>
      </div>
    </div>
  )
}

import { useEffect, useState } from 'react'
import { Button, Note } from '../components/ui'
import { whereabouts } from '../domain/fleet'
import { routeOfFleet } from '../domain/route'
import { seaWallOf, type Refusal } from '../lib/rpc'
import { useT } from '../lib/i18n'
import { tripRoute, type RouteStopDraft } from './standingRouteDraft'
import { saveAndStartRoute } from './startRoute'
import { usePress } from './usePress'
import { portNameOf, servedGoods, useWorld } from './worldStore'

// REPEAT AS A ROUTE, on the arrival card (2026-11-16, the content plan's slice B; docs/design/content-plan-2026-11.md
// §5.3 no. 2). A standing route works, and it was the last row of the Trade screen with nothing leading to it. The door
// is put where the player is when the idea matters: she has just sailed a trip and sold at a profit. One press makes
// the trip a route (`tripRoute`: here and the harbour she came from, each selling everything, buying what she bought
// there and sold at the other) and starts it on her, through THE one path a route editor's Start takes
// (startRoute.ts → cmd.standing_route_save, cmd.standing_route_assign). Every rule — a keep level, the route cap, a leg
// the sea shuts — is the server's, and its refusal is printed here in its words. Edit is on the route's own page.
//
// WHEN IT IS OFFERED, decided ONCE when the card comes up (a beat that brings the new route must not take the button
// away under her finger): one arrival on the card, at a harbour, from another harbour, the card's served profit above 0,
// routes open, this fleet (by the name the events carry, one fleet of that name) lying at that harbour with no route,
// a free route under the served `max`, and a trip worth repeating (`tripRoute` not null).
//
// NOTHING BELOW THE PRESS MOVES: the card stands on its bottom edge (ArrivalCard.tsx), and the one line a press may add
// (a refusal) is drawn ABOVE the button, so the button and the row under it keep their place. After a start the
// button stays where it was and reads On route.

interface Offer {
  fleetId: string
  stops: RouteStopDraft[]
}

function offerOf(trip: { fleet: string; here: string; there: string }): Offer | null {
  const s = useWorld.getState()
  const book = s.routes
  if (!book?.enabled || book.routes.length >= book.max) return null
  const named = s.fleets.filter((f) => f.name === trip.fleet)
  if (named.length !== 1) return null
  const fleet = named[0]
  const w = whereabouts(fleet)
  if (w.kind !== 'docked' || w.port !== trip.here || routeOfFleet(book, fleet.id) !== null) return null
  if (!s.portByCode[trip.here] || !s.portByCode[trip.there]) return null
  const stops = tripRoute(trip, s.events, servedGoods())
  return stops ? { fleetId: fleet.id, stops } : null
}

export function ArrivalRepeat({
  trip,
  onHold,
}: {
  /** The arrival: the fleet's NAME (as the events carry it), the harbour she came in at and the one she sailed from. */
  trip: { fleet: string; here: string; there: string }
  /** True while the card must wait for her (a press on the wire, or a refusal to read). */
  onHold: (held: boolean) => void
}) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const [offer] = useState(() => offerOf(trip))
  const press = usePress()
  const [savedId, setSavedId] = useState<string | null>(null)
  const [started, setStarted] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const [noCourse, setNoCourse] = useState<string | null>(null)
  const held = press.pending || refusal !== null || noCourse !== null

  useEffect(() => {
    onHold(held)
  }, [held, onHold])
  // gone with its card: the next card does not inherit a hold
  useEffect(() => () => onHold(false), [onHold])

  if (!offer) return null
  const start = async () => {
    setRefusal(null)
    setNoCourse(null)
    const done = await saveAndStartRoute(offer.stops, offer.fleetId, savedId)
    if (done.id) setSavedId(done.id)
    if (done.ok) setStarted(true)
    else if ('noCourseFrom' in done) setNoCourse(done.noCourseFrom)
    else setRefusal(done.refusal)
  }
  return (
    <div className="mt-3" data-testid="arrival-repeat">
      {noCourse && (
        <Note tone="danger" className="mb-2">
          {t('command.noCourse', { port: portNameOf(portByCode, noCourse) })}
        </Note>
      )}
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} sea={seaWallOf(refusal)} className="mb-2" data-testid="arrival-repeat-refusal">
          {refusal.sentence}
        </Note>
      )}
      {/* `tonal`: the card is surface-2, and so is a `secondary` button, which read as a bare word on it */}
      <Button
        variant="tonal"
        size="sm"
        className="w-full"
        busy={press.pending}
        disabled={started}
        data-testid="arrival-repeat-press"
        data-started={started ? 'true' : 'false'}
        onClick={() => void press.run(start)}
      >
        {started ? t('domain.onRoute') : t('feed.makeRoute')}
      </Button>
    </div>
  )
}

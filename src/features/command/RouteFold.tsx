import { useEffect, useState } from 'react'
import { Button, Figure, Hint, Note, Row, deltaTone } from '../../components/ui'
import { formatDucats, formatDucatsDelta } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import {
  routeOfFleet,
  routePausedSentence,
  routePorts,
  routesWithoutFleet,
  routeStateWord,
  routeStopWords,
} from '../../domain/route'
import type { FleetView, Refusal } from '../../lib/rpc'
import { RouteEditor } from './RouteEditor'

// THE ROUTE, FOLDED ABOVE HER QUEUE — owner, 2026-09-30: *"i want this game to be a simulating
// based - meaning i set up route, trade routes - going back and forth, afk, running all the time"*.
//
// ── §7B, ANSWERED BEFORE THE FIRST LINE (docs/TRADE_ROUTES.md §2, §7) ──────────────────────────
// CONCEPT     one fleet's standing route, as a row that unfolds in place: what it does at each
//             stop, whether it is running, and the last laps' money. A route is a standing ORDER,
//             so it lives on COMMAND ("the only tab that changes the world", DESIGN §E.1) — never in
//             FleetFold, whose own header names "a fourth thing folded in here (an order queue, a
//             history)" as the wrong shape.
// SECOND CALLERS  FLEETS' caption word and (slice 3) the MAP's route line read the SAME served
//             route through src/domain/route. None of them derives a figure.
// WRONG SHAPE a number computed here. Lap net, sold, bought, wages, the next-lap time: all served
//             by world.standing_routes() and formatted by src/lib/format.
//
// ── THE FOLD RULE (owner rows 6, 15, 25, 28, 45) ───────────────────────────────────────────────
// Pressing the row SELECTS; the row and everything above it stay where they are, and what is
// below — the queue — moves down. tests/layout.spec.ts measures it at 390×844.

export function RouteFold({ fleet }: { fleet: FleetView }) {
  const book = useWorld((s) => s.routes)
  const loadRoutes = useWorld((s) => s.loadRoutes)
  const readAt = useWorld((s) => s.readAt)
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const busy = useWorld((s) => s.busy)
  const pauseRoute = useWorld((s) => s.pauseRoute)
  const deleteRoute = useWorld((s) => s.deleteRoute)
  const assignRoute = useWorld((s) => s.assignRoute)
  const clearQueue = useWorld((s) => s.clear)

  const [open, setOpen] = useState(false)
  // WHICH route the editor is open on: this fleet's own ('own'), a route no fleet runs (its id), a
  // new one ('new'), or none.
  const [editing, setEditing] = useState<string | null>(null)
  // THIS fold's last refusal — never the store's, which may belong to another screen's press.
  const [refusal, setRefusal] = useState<Refusal | null>(null)

  // THE READ IS THE CATCH-UP: every world read (readAt) re-reads the routes, so a lap that closed
  // while you were away is on the row the next time the world is read.
  useEffect(() => {
    void loadRoutes()
  }, [loadRoutes, readAt])

  const route = routeOfFleet(book, fleet.id)
  // NONE IS HIDDEN (0093 review, MUST 1): a route whose Start was refused, or that was taken off its
  // fleet, is listed here — started on THIS fleet by its id, edited, or deleted.
  const spare = routesWithoutFleet(book)
  const editRoute = editing === 'own' ? route : (spare.find((r) => r.id === editing) ?? null)
  const act = async (done: Promise<boolean>) => {
    setRefusal((await done) ? null : useWorld.getState().refusal)
  }

  const lastLap = route?.laps[0] ?? null
  const label = !book
    ? 'Route'
    : !book.enabled
      ? 'Route · Not open yet'
      : route
        ? `Route · ${routePorts(route, portByCode)} · Lap ${route.lap_no}`
        : 'No route'

  return (
    <div data-testid="route-fold">
      <Row
        label={label}
        value={lastLap ? <Figure value={formatDucatsDelta(lastLap.net)} tone={deltaTone(lastLap.net)} /> : undefined}
        chevron
        tone={open ? 'accent' : 'default'}
        onClick={() => setOpen((o) => !o)}
        data-testid="route-row"
      >
        {route && book?.enabled && (
          <span className="block text-t-caption text-ink-faint" data-testid="route-state">
            {routeStateWord(route, portByCode)}
          </span>
        )}
      </Row>

      {open && (
        <div className="pb-3" data-testid="route-unfold">
          {!book ? (
            <Row label="Loading…" tone="muted" hairline={false} />
          ) : !book.enabled ? (
            <Hint>Routes are not open yet. A fleet will sail a loop of ports and trade by itself.</Hint>
          ) : editing ? (
            <RouteEditor key={editing} fleet={fleet} route={editRoute} onDone={() => setEditing(null)} />
          ) : !route ? (
            <>
              {spare.map((r) => (
                <div key={r.id} data-testid="route-spare">
                  <Row label={r.name} hairline={false}>
                    <span className="block text-t-caption text-ink-faint">{routeStateWord(r, portByCode)}</span>
                  </Row>
                  <div className="flex gap-2">
                    <Button variant="secondary" size="sm" className="flex-1" disabled={busy} onClick={() => void act(assignRoute(r.id, fleet.id))}>
                      Start
                    </Button>
                    <Button variant="secondary" size="sm" className="flex-1" disabled={busy} onClick={() => setEditing(r.id)}>
                      Edit
                    </Button>
                    <Button variant="quiet" size="sm" className="flex-1" disabled={busy} onClick={() => void act(deleteRoute(r.id))}>
                      Delete
                    </Button>
                  </div>
                </div>
              ))}
              <Button variant="primary" className="mt-2 w-full" onClick={() => setEditing('new')} data-testid="route-setup">
                Set up route
              </Button>
            </>
          ) : (
            <>
              {route.state === 'stopped' && route.stopped && (
                <Note
                  tone="danger"
                  code={route.stopped.code}
                  action={
                    <Button variant="secondary" size="sm" disabled={busy} onClick={() => void act(clearQueue(fleet.id))}>
                      Clear
                    </Button>
                  }
                  data-testid="route-stopped"
                >
                  {fleet.name} stopped. {route.stopped.sentence ?? ''}
                </Note>
              )}
              {route.state === 'paused' && <Note tone="neutral">{routePausedSentence(route.paused_reason)}</Note>}
              {route.state === 'blocked' && (
                <Note tone="neutral" data-testid="route-blocked">
                  {fleet.name} cannot sail on by itself. The route goes on once it is in port and fit to sail.
                </Note>
              )}

              {route.stops.map((s) => (
                <Row
                  key={s.ord}
                  label={portNameOf(portByCode, s.port)}
                  hairline={false}
                  data-testid="route-stop"
                >
                  <span className="block text-t-caption text-ink-faint">{routeStopWords(s, goodByCode)}</span>
                </Row>
              ))}

              {route.laps.slice(0, 3).map((l) => (
                <Row
                  key={l.lap_no}
                  label={`Lap ${l.lap_no}`}
                  value={<Figure value={formatDucatsDelta(l.net)} tone={deltaTone(l.net)} />}
                  hairline={false}
                  data-testid="route-lap"
                >
                  <span className="block text-t-caption text-ink-faint">
                    Sold {formatDucats(l.sold)} · Bought {formatDucats(l.bought)} · Supplies {formatDucats(l.supplies)}
                    {l.repairs > 0 ? ` · Repairs ${formatDucats(l.repairs)}` : ''} · Wages {formatDucats(l.wages)}
                    {l.skipped.length > 0 ? ` · ${l.skipped.length} skipped` : ''}
                  </span>
                </Row>
              ))}

              <div className="mt-2 flex gap-2">
                <Button
                  variant="secondary"
                  className="flex-1"
                  disabled={busy}
                  onClick={() => void act(pauseRoute(route.id, route.state !== 'paused'))}
                  data-testid="route-pause"
                >
                  {route.state === 'paused' ? 'Resume' : 'Pause'}
                </Button>
                <Button variant="secondary" className="flex-1" disabled={busy} onClick={() => setEditing('own')}>
                  Edit
                </Button>
                <Button variant="quiet" className="flex-1" disabled={busy} onClick={() => void act(deleteRoute(route.id))}>
                  Delete
                </Button>
              </div>
            </>
          )}
          {refusal && (
            <Note tone="danger" code={refusal.code} className="mt-2">
              {refusal.sentence}
            </Note>
          )}
        </div>
      )}
    </div>
  )
}

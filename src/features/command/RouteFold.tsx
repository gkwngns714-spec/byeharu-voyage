import { useState } from 'react'
import { Button, Figure, Hint, Note, Row, deltaTone } from '../../components/ui'
import { formatDucats, formatDucatsDelta } from '../../lib/format'
import { usePress } from '../../live/usePress'
import { useWorld } from '../../live/worldStore'
import {
  routeOfFleet,
  routePausedSentence,
  routePorts,
  routesWithoutFleet,
  routeStateWord,
} from '../../domain/route'
import type { FleetView, Refusal } from '../../lib/rpc'
import { RouteEditor } from './RouteEditor'
import { RouteStopFace } from './RouteStop'

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
//
// ── NO BUTTON HERE WEARS THE WORLD READ (owner, 2026-09-30: "a bar ... blinks on its own") ──────
// Every button in this fold used to be `disabled={busy}` — the store's flag for a world read in
// flight — and the shell reads the world every few seconds, so each one greyed and came back on
// every beat. The fold now wears ONE `usePress` (src/live/usePress.ts): a button is busy only
// while ITS OWN press is on the wire, and never on the beat.

export function RouteFold({ fleet }: { fleet: FleetView }) {
  const book = useWorld((s) => s.routes)
  const portByCode = useWorld((s) => s.portByCode)
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
  // ONE press at a time across the fold's buttons: Start / Delete on a spare route, Clear, Pause /
  // Resume, Delete. A press awaits the world read that re-lists the routes, so a second press on a
  // stale book is dropped rather than queued.
  // Edit waits it out too: opened mid-Delete it would edit a route that is going away — a flip the
  // player's own press causes, never the beat.
  const press = usePress()

  // THE ROUTES RIDE THE WORLD'S BEAT: `refresh()` reads the book with the fleets and keeps the last
  // answer when a read fails (worldStore.ts, the no-blink slice, 2026-09-30). This fold used to
  // re-ask on every `readAt` — a second reader, and one that blanked the book to "Loading…" on a
  // failed read — so it asks nothing of its own now.

  const route = routeOfFleet(book, fleet.id)
  // NONE IS HIDDEN (0093 review, MUST 1): a route whose Start was refused, or that was taken off its
  // fleet, is listed here — started on THIS fleet by its id, edited, or deleted.
  const spare = routesWithoutFleet(book)
  const editRoute = editing === 'own' ? route : (spare.find((r) => r.id === editing) ?? null)
  const act = (done: () => Promise<boolean>) =>
    press.run(async () => {
      setRefusal((await done()) ? null : useWorld.getState().refusal)
    })

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
                    <Button variant="secondary" size="sm" className="flex-1" busy={press.pending} onClick={() => void act(() => assignRoute(r.id, fleet.id))}>
                      Start
                    </Button>
                    <Button variant="secondary" size="sm" className="flex-1" disabled={press.pending} onClick={() => setEditing(r.id)}>
                      Edit
                    </Button>
                    <Button variant="quiet" size="sm" className="flex-1" busy={press.pending} onClick={() => void act(() => deleteRoute(r.id))}>
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
                    <Button variant="secondary" size="sm" busy={press.pending} onClick={() => void act(() => clearQueue(fleet.id))}>
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

              {/* EACH STOP AS ITS SELL AND BUY LINES (owner, 2026-09-30) — RouteStop.tsx. */}
              {route.stops.map((s, i) => (
                <RouteStopFace key={s.ord} stop={s} last={i === route.stops.length - 1} />
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
                  busy={press.pending}
                  onClick={() => void act(() => pauseRoute(route.id, route.state !== 'paused'))}
                  data-testid="route-pause"
                >
                  {route.state === 'paused' ? 'Resume' : 'Pause'}
                </Button>
                <Button variant="secondary" className="flex-1" disabled={press.pending} onClick={() => setEditing('own')}>
                  Edit
                </Button>
                <Button variant="quiet" className="flex-1" busy={press.pending} onClick={() => void act(() => deleteRoute(route.id))}>
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

import { useState } from 'react'
import { Button, Figure, Hint, Note, Row, deltaTone } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatRelative } from '../../lib/format'
import { useShellState } from '../../app/shellState'
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
import { useDeskView } from './deskView'
import { useT } from '../../lib/i18n'

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

export function RouteFold({
  fleet,
  picked = false,
  onPick,
}: {
  fleet: FleetView
  /** OWNER ROW 217: the standing route is the order pressed — Trade.tsx draws it on the map on top, with its
   *  estimate. Pressing the row opens the fold AND selects the route; pressing it again folds it and clears. */
  picked?: boolean
  onPick?: (on: boolean) => void
}) {
  const t = useT()
  // THE ONE CLOCK (src/app/shellState.ts): the last lap's age ticks from it, never from a Date.now() in a render.
  const { nowMs } = useShellState()
  const book = useWorld((s) => s.routes)
  const portByCode = useWorld((s) => s.portByCode)
  const pauseRoute = useWorld((s) => s.pauseRoute)
  const deleteRoute = useWorld((s) => s.deleteRoute)
  const assignRoute = useWorld((s) => s.assignRoute)
  const clearQueue = useWorld((s) => s.clear)

  // Open or folded is the DESK's state (deskView.ts `routeOpen`), so it survives the desk's change of
  // shape at 1024 px; which route the editor is on stays here.
  const open = useDeskView((s) => s.routeOpen)
  const setOpen = useDeskView((s) => s.setRouteOpen)
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
    ? t('command.route')
    : !book.enabled
      ? t('command.routeNotOpen')
      : route
        ? t('command.routeLine', { ports: routePorts(route, portByCode), n: route.lap_no })
        : t('command.noRoute')

  return (
    <div data-testid="route-fold">
      <Row
        label={label}
        value={lastLap ? <Figure value={formatDucatsDelta(lastLap.net)} tone={deltaTone(lastLap.net)} /> : undefined}
        chevron
        tone={open || picked ? 'accent' : 'default'}
        onClick={() => {
          // the fold toggles as it always has; the route is pressed while it stands open
          if (onPick && route && book?.enabled) onPick(!open)
          setOpen(!open)
        }}
        data-testid="route-row"
      >
        {route && book?.enabled && (
          <span className="block text-t-caption text-ink-faint" data-testid="route-state">
            {routeStateWord(route, portByCode)}
            {/* HOW LONG AGO THE LAST LAP CLOSED (owner row 206, 2026-10-26: "like 24 minutes ago, or 1 hour
                ago"): the one formatter, against the shell's clock, beside the figure it dates. */}
            {lastLap?.closed_at && (
              <span data-testid="route-last-lap-age">
                {' · '}
                {t('command.lastLapAgo', { ago: formatRelative(Date.parse(lastLap.closed_at), nowMs) })}
              </span>
            )}
          </span>
        )}
      </Row>

      {open && (
        <div className="pb-3" data-testid="route-unfold">
          {!book ? (
            <Row label={t('command.loading')} tone="muted" hairline={false} />
          ) : !book.enabled ? (
            <Hint>{t('command.routesNotOpen')}</Hint>
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
                      {t('command.start')}
                    </Button>
                    <Button variant="secondary" size="sm" className="flex-1" disabled={press.pending} onClick={() => setEditing(r.id)}>
                      {t('command.edit')}
                    </Button>
                    <Button variant="quiet" size="sm" className="flex-1" busy={press.pending} onClick={() => void act(() => deleteRoute(r.id))}>
                      {t('command.delete')}
                    </Button>
                  </div>
                </div>
              ))}
              <Button variant="primary" className="mt-2 w-full" onClick={() => setEditing('new')} data-testid="route-setup">
                {t('command.setUpRoute')}
              </Button>
            </>
          ) : (
            <>
              {route.state === 'stopped' && route.stopped && (
                <Note
                  tone="danger"
                  code={route.stopped.code} figures={route.stopped.figures}
                  action={
                    <Button variant="secondary" size="sm" busy={press.pending} onClick={() => void act(() => clearQueue(fleet.id))}>
                      {t('command.clear')}
                    </Button>
                  }
                  data-testid="route-stopped"
                >
                  {t('command.fleetStopped', { fleet: fleet.name, sentence: route.stopped.sentence ?? '' })}
                </Note>
              )}
              {route.state === 'paused' && <Note tone="neutral">{routePausedSentence(route.paused_reason)}</Note>}
              {route.state === 'blocked' && (
                <Note tone="neutral" data-testid="route-blocked">
                  {t('command.blockedNote', { fleet: fleet.name })}
                </Note>
              )}

              {/* 0275 (docs/WEEKLY_ROLLOVER.md §5 W4): the weekly counters — the server's week and
                  its sums, printed as served; the face computes neither the week nor the net. */}
              {route.earnings && (
                <div className="pb-1 text-t-caption tabular-nums text-ink-faint" data-testid="route-week-laps">
                  <span>
                    {t('routes.weekLaps', { n: route.earnings.week.laps, net: formatDucatsDelta(route.earnings.week.net) })}
                  </span>
                  {route.earnings.last_week && (
                    <span className="block">
                      {t('routes.lastWeekLaps', {
                        n: route.earnings.last_week.laps,
                        net: formatDucatsDelta(route.earnings.last_week.net),
                      })}
                    </span>
                  )}
                </div>
              )}

              {/* EACH STOP AS ITS SELL AND BUY LINES (owner, 2026-09-30) — RouteStop.tsx. */}
              {route.stops.map((s, i) => (
                <RouteStopFace key={s.ord} stop={s} last={i === route.stops.length - 1} />
              ))}

              {route.laps.slice(0, 3).map((l) => (
                <Row
                  key={l.lap_no}
                  label={t('command.lapN', { n: l.lap_no })}
                  value={<Figure value={formatDucatsDelta(l.net)} tone={deltaTone(l.net)} />}
                  hairline={false}
                  data-testid="route-lap"
                >
                  <span className="block text-t-caption text-ink-faint">
                    {t('command.lapLine', {
                      sold: formatDucats(l.sold),
                      bought: formatDucats(l.bought),
                      supplies: formatDucats(l.supplies),
                      repairs: l.repairs > 0 ? t('command.lapRepairs', { n: formatDucats(l.repairs) }) : '',
                      wages: formatDucats(l.wages),
                      skipped: l.skipped.length > 0 ? t('command.lapSkipped', { n: l.skipped.length }) : '',
                    })}
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
                  {t(route.state === 'paused' ? 'command.resume' : 'command.pause')}
                </Button>
                <Button variant="secondary" className="flex-1" disabled={press.pending} onClick={() => setEditing('own')}>
                  {t('command.edit')}
                </Button>
                <Button variant="quiet" className="flex-1" busy={press.pending} onClick={() => void act(() => deleteRoute(route.id))}>
                  {t('command.delete')}
                </Button>
              </div>
            </>
          )}
          {refusal && (
            <Note tone="danger" code={refusal.code} figures={refusal.figures} className="mt-2">
              {refusal.sentence}
            </Note>
          )}
        </div>
      )}
    </div>
  )
}

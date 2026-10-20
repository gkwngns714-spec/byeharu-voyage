import { Button, Figure, Icon, Note, Row } from '../../components/ui'
import { boundForLabel, fleetRefusedOrder, voyageEtaMs, whereabouts } from '../../domain/fleet'
import { queuedOrderWords, refusalOfOrder } from '../../domain/order'
import { formatCountdown, formatMiles } from '../../lib/format'
import { useShellState } from '../../app/shellState'
import { usePress } from '../../live/usePress'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { FleetView, QueuedOrder } from '../../lib/rpc'
import { useT, t as tNow, translateMaybe, getLocale } from '../../lib/i18n'

// HER QUEUE, AS ROWS ON THE SHEET — the whole of what COMMAND shows about a fleet now.
//
// It was a `Tray` behind a `queued` pill because the verb grid stood on the sheet (§6). The grid
// is gone (CommandScreen.tsx says where each verb went), so the queue is the sheet's own content:
// a halted queue is one Note at the top, the passage is one row while there is one, every order is
// a row in the player's words (domain/order's `queuedOrderWords` — a route's SELL and BUY read as
// its stop does) with a trailing cancel, and the Clear button follows the last row.
// CANCEL and CLEAR are still the server's verbs (domain/order's QUEUE_VERBS), composed here and
// nowhere else. The `> SAIL Gaivota TO CAD` parser line is never printed (§5, §2 item 14).
//
// ONE PRESS AT A TIME, ACROSS THE QUEUE (src/live/usePress.ts). Every ✕ and the Clear button used
// to wear the store's world-read flag as `disabled`, so they greyed on every beat (the owner,
// 2026-09-30: "a bar ... blinks occasionally on its own"). Now the queue wears one gate: a CANCEL
// addresses its order by `seq` and awaits the read that renumbers them, so while one press is on
// the wire no other ✕ may fire on a stale seq — and outside a press, nothing greys anything.
//
// THE ARRIVAL COUNTS DOWN ON THE ONE CLOCK (owner row 170, 2026-10-20):
//
//     "When arriving a city, why is there a waiting time? Arrives in (min)??? This should be gone,
//      meaning it should arrive at city as soon as it reaches it."
//
// There is no wait at the quay to remove. A player's own fleet is docked by the READ that finds her
// arrived — migration 0009's first law, "every read RPC that touches a fleet first calls
// voyage.settle" — so the arrivals sweep never gates her, and the shell reads every 7.5 s at the
// live clock (AppShell.tsx). What the owner was reading as a wait was THIS COUNTDOWN, drawn two
// ways that both made a moving figure look like a stationary one:
//
//   * it counted against `readAt`, the LAST READ'S instant, not against the clock. Between two
//     reads the figure did not move at all — the row said "arrives in 1m" and went on saying it;
//   * it was drawn with `formatRealShort`, which rounds the seconds away (its own doc-comment says
//     "a countdown drawn with it would only move once a minute and read as stuck"). So the last
//     thing a player saw before she docked was a whole minute, standing still. Hence "(min)???".
//
// Both are gone. The countdown now rides the shell's one clock (shellState.ts: "this game is full
// of 'arrives in 4h 12m': each of those is a countdown, and a countdown needs something to
// re-render it") and is drawn with `formatCountdown` — `0:48`, ticking every second — which is what
// MAP's voyage tray has always drawn. Past the instant the word is "due", never "arrived": the next
// read is what lands her, and the client never decides an arrival on its own.
//
// A REFUSED ORDER NO LONGER STOPS HER (0186; the owner, 2026-10-18: "stopped at order 29 and will not skip
// it"). The server cancels what depended on it — the rest of its plan, whatever stood behind a refused SAIL —
// each with the reason, and runs the rest. The refused row stays as a record until it is dismissed, so every
// row, refused or live, has a ✕. The ✕ sends the row's POSITION in the served queue (1-based, what
// cmd.cancel_at counts), never its seq: sending the seq is why the ✕ did nothing once a fleet had a history.

export function Queue({
  fleet,
  onCancel,
  onClear,
}: {
  fleet: FleetView
  /** The verbs, as promises: a press is busy until its own act settles (worldStore's cancel/clear).
   *  `onCancel` takes the row's 1-based position in `fleet.queue` — cmd.cancel_at's index (0186). */
  onCancel: (position: number) => Promise<boolean>
  onClear: () => Promise<boolean>
}) {
  const t = useT()
  // THE ONE CLOCK, not the last read's instant — see the header. A DISPLAY value only: whether she
  // has arrived is the server's, decided by `voyage.settle` inside the read.
  const { nowMs } = useShellState()
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const press = usePress()

  const orders = fleet.queue
  // The refused row, read where the picker's "stuck" dot reads it (domain/fleet), so the two agree.
  const failed = fleetRefusedOrder(fleet)
  const failedRefusal = failed ? refusalOfOrder(failed) : null
  const where = whereabouts(fleet)
  const eta = voyageEtaMs(fleet)
  // Null when nothing is counting; "due" once the instant has passed and the read that lands her
  // has not come back yet — the same wording `fleetLine.ts`'s `fleetDue` uses, for the same reason.
  const due = eta === null ? null : nowMs >= eta ? tNow('domain.due') : formatCountdown(eta - nowMs)

  return (
    <>
      {failedRefusal && (
        <Note tone="danger" code={failedRefusal.code} figures={failedRefusal.figures} data-testid="queue-halt">
          Order {failed?.seq} was refused: {failedRefusal.sentence.replace(/\.$/, '')}. Anything that depended on it was cancelled;
          {' '}{fleet.name} is free.
        </Note>
      )}

      {fleet.voyage && where.kind === 'sailing' && (
        <Row
          mark={<Icon name="ship" size={18} className="text-info" />}
          label={t('command.sailingTo', { place: boundForLabel(where, (c) => portNameOf(portByCode, c)) })}
          value={due !== null ? <Figure value={due} tone="info" /> : undefined}
        >
          <span className="block text-t-caption text-ink-faint">
            {t('command.milesOf', { done: formatMiles(fleet.voyage.nm_done), total: formatMiles(fleet.voyage.total_nm) })}
          </span>
        </Row>
      )}

      {orders.length === 0 ? (
        <Row label={t('command.noOrders')} tone="muted" hairline={false} />
      ) : (
        orders.map((order, i) => {
          const live = order.status === 'pending' || order.status === 'active'
          const refused = order.status === 'failed'
          return (
            <Row
              key={order.id}
              label={queuedOrderWords(order, fleet.name, portByCode, goodByCode)}
              tone={order.status === 'failed' ? 'muted' : order.status === 'active' ? 'accent' : 'default'}
              hairline={i < orders.length - 1}
              data-testid="queue-row"
              value={
                live || refused ? (
                  <span className="inline-flex items-center gap-2">
                    {refused && <span className="text-t-caption text-ink-faint">{statusWord(order.status)}</span>}
                    <Button
                      variant="quiet"
                      size="icon"
                      busy={press.pending}
                      aria-label={t(refused ? 'command.dismissRefused' : 'command.cancelOrder', { n: order.seq })}
                      onClick={() => void press.run(() => onCancel(i + 1))}
                    >
                      <Icon name="close" size={18} />
                    </Button>
                  </span>
                ) : (
                  <span className="text-t-caption text-ink-faint">{statusWord(order.status)}</span>
                )
              }
            >
              {order.status === 'active' && due !== null && (
                <span className="block text-t-caption text-accent">{t('command.arrivesIn', { t: due })}</span>
              )}
            </Row>
          )
        })
      )}

      {orders.length > 0 && (
        <Button
          variant="secondary"
          className="mt-3 w-full"
          busy={press.pending}
          onClick={() => void press.run(onClear)}
          data-testid="queue-clear"
        >
          {t('command.clearAll')}
        </Button>
      )}
    </>
  )
}

function statusWord(status: QueuedOrder['status']): string {
  switch (status) {
    case 'done':
      return tNow('command.st_done')
    case 'failed':
      return tNow('command.st_refused')
    default:
      return translateMaybe(getLocale(), 'command', `st_${status}`) ?? status
  }
}

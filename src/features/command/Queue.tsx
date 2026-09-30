import { Button, Figure, Icon, Note, Row } from '../../components/ui'
import { voyageEtaMs } from '../../domain/fleet'
import { queuedOrderWords, refusalOfOrder } from '../../domain/order'
import { formatMiles, formatRealShort } from '../../lib/format'
import { usePress } from '../../live/usePress'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { FleetView, QueuedOrder } from '../../lib/rpc'

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

export function Queue({
  fleet,
  readAt,
  onCancel,
  onClear,
}: {
  fleet: FleetView
  readAt: number | null
  /** The verbs, as promises: a press is busy until its own act settles (worldStore's cancel/clear). */
  onCancel: (seq: number) => Promise<boolean>
  onClear: () => Promise<boolean>
}) {
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const press = usePress()

  const orders = fleet.queue
  const failed = orders.find((o) => o.status === 'failed')
  const failedRefusal = failed ? refusalOfOrder(failed) : null
  const eta = voyageEtaMs(fleet)
  const etaMs = eta !== null && readAt !== null ? Math.max(0, eta - readAt) : null

  return (
    <>
      {failedRefusal && (
        <Note tone="danger" code={failedRefusal.code} data-testid="queue-halt">
          {fleet.name} stopped at order {failed?.seq} and will not skip it. {failedRefusal.sentence}
        </Note>
      )}

      {fleet.voyage && (
        <Row
          mark={<Icon name="ship" size={18} className="text-info" />}
          label={`Sailing → ${fleet.voyage.to ? portNameOf(portByCode, fleet.voyage.to) : 'open sea'}`}
          value={etaMs !== null ? <Figure value={formatRealShort(etaMs)} tone="info" /> : undefined}
        >
          <span className="block text-t-caption text-ink-faint">
            {formatMiles(fleet.voyage.nm_done)} of {formatMiles(fleet.voyage.total_nm)}
          </span>
        </Row>
      )}

      {orders.length === 0 ? (
        <Row label="No orders queued." tone="muted" hairline={false} />
      ) : (
        orders.map((order, i) => {
          const live = order.status === 'pending' || order.status === 'active'
          return (
            <Row
              key={order.id}
              label={queuedOrderWords(order, fleet.name, portByCode, goodByCode)}
              tone={order.status === 'failed' ? 'muted' : order.status === 'active' ? 'accent' : 'default'}
              hairline={i < orders.length - 1}
              data-testid="queue-row"
              value={
                live ? (
                  <Button
                    variant="quiet"
                    size="icon"
                    busy={press.pending}
                    aria-label={`Cancel order ${order.seq}`}
                    onClick={() => void press.run(() => onCancel(order.seq))}
                  >
                    <Icon name="close" size={18} />
                  </Button>
                ) : (
                  <span className="text-t-caption text-ink-faint">{statusWord(order.status)}</span>
                )
              }
            >
              {order.status === 'active' && etaMs !== null && (
                <span className="block text-t-caption text-accent">arrives in {formatRealShort(etaMs)}</span>
              )}
            </Row>
          )
        })
      )}

      {orders.length > 0 && (
        <Button
          variant={failed ? 'destructive' : 'secondary'}
          className="mt-3 w-full"
          busy={press.pending}
          onClick={() => void press.run(onClear)}
          data-testid="queue-clear"
        >
          {failed ? 'Clear the stopped order' : 'Clear all orders'}
        </Button>
      )}
    </>
  )
}

function statusWord(status: QueuedOrder['status']): string {
  switch (status) {
    case 'done':
      return 'done'
    case 'failed':
      return 'halted'
    default:
      return status
  }
}

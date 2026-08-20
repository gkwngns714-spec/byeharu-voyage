import { Badge, Button, Notice } from '../../components/ui'
import { formatNm, formatRealShort } from '../../lib/format'
import type { FleetView, QueuedOrder } from '../../lib/rpc'

// THE QUEUE — E.1's QUEUES block and F.3's rules, made of the server's own rows.
//
//   [1] BUY sal 50            done
//   [2] SAIL Gaivota TO CAD   ACTIVE   eta 11m   ✕
//   [3] SELL sal ALL          pending            ✕
//
// F.3, and the two rules a player must be able to SEE rather than learn the hard way:
//   · The queue HALTS on a failure. It does not skip. A failed order is drawn in danger tone with
//     the server's code and sentence, and everything behind it is visibly stuck until it is
//     cleared — so CLEAR is drawn as the release, not as a tidy-up.
//   · CANCEL on the ACTIVE voyage does not turn the ship around: RECALL is not a V0 verb, and
//     `cmd.clear()` says so itself in `active_left_running`.
//
// THIS IS ALSO WHERE CANCEL AND CLEAR ARE MADE. They are two of the eight verbs the server serves,
// and their only argument is a row of this list — so they are composed HERE, by tapping that row,
// rather than in the composer. One way to cancel, one way to clear.

export function OrderQueue({
  fleet,
  queueMax,
  busy,
  readAt,
  destination,
  onCancel,
  onClear,
}: {
  fleet: FleetView
  /** Where she is bound, in words. The queue carries a port CODE; the screen knows the name. */
  destination?: string | null
  /** `config.order_queue_max` — twelve, and the server's number, not a constant on this side. */
  queueMax: number
  busy: boolean
  /** When the world was last READ. The ETA is counted from there, not from the wall clock: a read
   *  is the catch-up (D.2), nothing on this screen ticks, and a render is not a clock. */
  readAt: number | null
  onCancel: (seq: number) => void
  onClear: () => void
}) {
  const orders = fleet.queue
  const live = orders.filter((o) => o.status === 'pending' || o.status === 'active')
  const failed = orders.find((o) => o.status === 'failed')
  const etaMs = fleet.voyage && readAt !== null ? Date.parse(fleet.voyage.eta) - readAt : null

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-mono text-sm text-ink">{fleet.name}</span>
        <Badge tone={statusTone(fleet.status)}>{fleet.status}</Badge>
        <span className="font-mono text-[11px] text-ink-faint">
          {live.length}/{queueMax} queued
        </span>
        {failed && <Badge tone="danger">halted</Badge>}
      </div>

      {failed && (
        <Notice tone="danger" className="text-xs">
          <span className="font-mono">{failed.error_code}</span> — {failed.error_message}
          <br />
          {fleet.name} has HALTED at order {failed.seq} and will not skip past it. Clearing the queue
          is what releases her.
        </Notice>
      )}

      {/* THE VOYAGE IS NOT AN ORDER. A SAIL that has begun leaves the queue at once — the passage
          itself lives on the fleet (D.2's closed form), so a queue panel that showed only orders
          would report "nothing waiting" about a ship that is plainly at sea. */}
      {fleet.voyage && (
        <p className="flex flex-wrap items-center gap-2 rounded-md border border-accent/25 bg-accent-soft px-3 py-2 font-mono text-xs text-accent">
          <span aria-hidden>⛵</span>
          at sea → {destination ?? fleet.voyage.to}
          <span className="text-ink-faint">
            {formatNm(fleet.voyage.nm_done)} of {formatNm(fleet.voyage.total_nm)}
          </span>
          {etaMs !== null && <span>arrives in {formatRealShort(Math.max(etaMs, 0))}</span>}
        </p>
      )}

      {orders.length === 0 ? (
        <p className="text-sm text-ink-muted">
          {fleet.status === 'DOCKED'
            ? `${fleet.name} is alongside with nothing to do. A docked fleet earns nothing.`
            : 'Nothing is queued for her arrival — an order made now will run the moment she is alongside.'}
        </p>
      ) : (
        <ul className="space-y-1">
          {orders.map((order) => (
            <li key={order.id} className="flex flex-wrap items-center gap-2 border-b border-edge/50 py-1">
              <span className="font-mono text-xs text-ink-faint">[{order.seq}]</span>
              <code className="min-w-0 flex-1 break-words font-mono text-xs text-ink">{order.text}</code>
              {order.status === 'active' && etaMs !== null && (
                <span className="font-mono text-[11px] text-accent">eta {formatRealShort(Math.max(etaMs, 0))}</span>
              )}
              <Badge tone={orderTone(order.status)}>
                {order.status === 'failed' && order.error_code ? order.error_code : order.status}
              </Badge>
              {(order.status === 'pending' || order.status === 'active') && (
                <Button
                  variant="ghost"
                  size="icon"
                  disabled={busy}
                  aria-label={`Cancel ${fleet.name} order ${order.seq}`}
                  title={
                    order.status === 'active'
                      ? 'A voyage already at sea keeps sailing — RECALL is not a V0 verb (F.3)'
                      : 'Drop this order from the queue'
                  }
                  onClick={() => onCancel(order.seq)}
                >
                  ✕
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}

      <div className="flex flex-wrap gap-2">
        <Button
          variant={failed ? 'danger' : 'secondary'}
          disabled={busy || orders.length === 0}
          onClick={onClear}
        >
          {failed ? `Clear the halt on ${fleet.name}` : `Clear ${fleet.name}'s queue`}
        </Button>
      </div>
    </div>
  )
}

function statusTone(status: FleetView['status']) {
  switch (status) {
    case 'SAILING':
      return 'accent' as const
    case 'DOCKED':
      return 'success' as const
    case 'REPAIRING':
      return 'warning' as const
    case 'ADRIFT':
    case 'UNABLE_TO_SAIL':
      return 'danger' as const
    default:
      return 'neutral' as const
  }
}

function orderTone(status: QueuedOrder['status']) {
  switch (status) {
    case 'active':
      return 'accent' as const
    case 'done':
      return 'success' as const
    case 'failed':
      return 'danger' as const
    default:
      return 'neutral' as const
  }
}

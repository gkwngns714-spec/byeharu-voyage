import { Badge, Button, Notice } from '../../components/ui'
import { formatRealShort } from '../../lib/format'
import type { QueuedOrder } from '../../fixtures/types'
import type { FleetView } from '../fleets/fleetMath'
import { MAX_QUEUE } from './validate'

// THE ORDER QUEUE — E.1's QUEUES block and F.3's rules, rendered.
//
//   Ponente     [1] SAIL→Calicut        pending  ✎ ✕
//   Aurora      [1] SAIL→Amsterdam      ACTIVE  eta 11m  ✕
//   Gaivota     — empty —                              ⚠
//
// F.3, and the two rules a player must be able to SEE rather than learn the hard way:
//   · The queue HALTS on a failure. It does not skip. A failed order is drawn in danger tone with
//     its code, and everything behind it is visibly stuck.
//   · CANCEL on an ACTIVE voyage is a RECALL, not an undo. The button says so.
//
// An empty queue on a docked fleet is the warning E.1 badges: a fleet alongside with nothing to do
// is money not working, and it is the one thing this panel actively complains about.

export function OrderQueue({
  views,
  ordersFor,
  selectedFleetId,
  onSelectFleet,
  onCancel,
}: {
  views: readonly FleetView[]
  ordersFor: (fleetId: string) => readonly QueuedOrder[]
  selectedFleetId: string | null
  onSelectFleet: (id: string) => void
  onCancel: (fleetName: string, order: QueuedOrder) => void
}) {
  return (
    <div className="space-y-4">
      {views.map((view) => {
        const orders = ordersFor(view.fleet.id)
        const live = orders.filter((o) => o.status === 'pending' || o.status === 'active')
        const idle = live.length === 0 && view.fleet.status === 'DOCKED'
        return (
          <div key={view.fleet.id} className="space-y-2">
            <button
              type="button"
              onClick={() => onSelectFleet(view.fleet.id)}
              className={[
                'flex min-h-11 w-full flex-wrap items-center gap-2 rounded-md px-2 text-left transition',
                view.fleet.id === selectedFleetId ? 'bg-surface-2' : 'hover:bg-surface-2',
              ].join(' ')}
            >
              <span className="font-mono text-sm text-ink">{view.fleet.name}</span>
              <Badge tone={statusTone(view.fleet.status)}>{view.fleet.status}</Badge>
              <span className="font-mono text-[11px] text-ink-faint">
                {live.length}/{MAX_QUEUE} queued
              </span>
              {view.fleet.id === selectedFleetId && (
                <span className="ml-auto font-mono text-[11px] uppercase tracking-wider text-accent">
                  commanding
                </span>
              )}
            </button>

            {idle && (
              <Notice tone="warning" className="font-mono text-xs">
                ⚠ {view.fleet.name} is alongside with an empty queue. A docked fleet earns nothing.
              </Notice>
            )}

            <ul className="space-y-1">
              {orders.map((order) => (
                <li
                  key={order.id}
                  className="flex flex-wrap items-center gap-2 border-b border-edge/50 py-1"
                >
                  <span className="font-mono text-xs text-ink-faint">[{order.seq}]</span>
                  <code className="min-w-0 flex-1 break-words font-mono text-xs text-ink">
                    {order.raw}
                  </code>
                  {order.status === 'active' && view.progress && (
                    <span className="font-mono text-[11px] text-accent">
                      eta {formatRealShort(view.progress.remainingMs)}
                    </span>
                  )}
                  <Badge tone={orderTone(order.status)}>
                    {order.status === 'failed' && order.errorCode ? order.errorCode : order.status}
                  </Badge>
                  {(order.status === 'pending' || order.status === 'active') && (
                    <Button
                      variant="ghost"
                      size="icon"
                      aria-label={
                        order.status === 'active'
                          ? `Recall ${view.fleet.name} — cancel order ${order.seq}`
                          : `Cancel ${view.fleet.name} order ${order.seq}`
                      }
                      title={
                        order.status === 'active'
                          ? 'CANCEL on a running voyage is a RECALL (F.3)'
                          : 'Remove from the queue'
                      }
                      onClick={() => onCancel(view.fleet.name, order)}
                    >
                      ✕
                    </Button>
                  )}
                </li>
              ))}
            </ul>

            {orders.some((o) => o.status === 'failed') && (
              <Notice tone="danger" className="text-xs">
                The queue has HALTED at the failed order. It does not skip ahead — a queue that
                quietly continues past a failed BUY sails an empty ship halfway round the world.
              </Notice>
            )}
          </div>
        )
      })}
    </div>
  )
}

function statusTone(status: FleetView['fleet']['status']) {
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

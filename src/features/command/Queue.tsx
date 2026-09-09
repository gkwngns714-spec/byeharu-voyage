import { Button, Figure, Icon, Note, Row } from '../../components/ui'
import { voyageEtaMs } from '../../domain/fleet'
import { refusalOfOrder, verbWord } from '../../domain/order'
import { formatNm, formatRealShort } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { FleetView, QueuedOrder } from '../../lib/rpc'

// HER QUEUE, AS ROWS ON THE SHEET — the whole of what COMMAND shows about a fleet now.
//
// It was a `Tray` behind a `queued` pill because the verb grid stood on the sheet (§6). The grid
// is gone (CommandScreen.tsx says where each verb went), so the queue is the sheet's own content:
// a halted queue is one Note at the top, the passage is one row while there is one, every order is
// a row in the player's words with a trailing cancel, and the Clear button follows the last row.
// CANCEL and CLEAR are still the server's verbs (domain/order's QUEUE_VERBS), composed here and
// nowhere else. The `> SAIL Gaivota TO CAD` parser line is never printed (§5, §2 item 14).

export function Queue({
  fleet,
  busy,
  readAt,
  onCancel,
  onClear,
}: {
  fleet: FleetView
  busy: boolean
  readAt: number | null
  onCancel: (seq: number) => void
  onClear: () => void
}) {
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)

  const orders = fleet.queue
  const failed = orders.find((o) => o.status === 'failed')
  const failedRefusal = failed ? refusalOfOrder(failed) : null
  const eta = voyageEtaMs(fleet)
  const etaMs = eta !== null && readAt !== null ? Math.max(0, eta - readAt) : null

  const humanize = (order: QueuedOrder): string => {
    const tokens = order.text.trim().split(/\s+/)
    const KEYWORDS = new Set(['TO', 'AT', 'VIA', 'ON'])
    const parts = [verbWord(order.verb)]
    for (const t of tokens.slice(1)) {
      if (t === fleet.name || KEYWORDS.has(t.toUpperCase())) continue
      const port = portByCode[t]
      const good = goodByCode[t]
      parts.push(port ? port.name : good ? good.name : t)
    }
    return parts.join(' ')
  }

  return (
    <>
      {failedRefusal && (
        <Note tone="danger" code={failedRefusal.code} data-testid="queue-halt">
          {fleet.name} has halted at order {failed?.seq} and will not skip past it. {failedRefusal.sentence}
        </Note>
      )}

      {fleet.voyage && (
        <Row
          mark={<Icon name="ship" size={18} className="text-info" />}
          label={`At sea → ${fleet.voyage.to ? portNameOf(portByCode, fleet.voyage.to) : 'open sea'}`}
          value={etaMs !== null ? <Figure value={formatRealShort(etaMs)} tone="info" /> : undefined}
        >
          <span className="block text-t-caption text-ink-faint">
            {formatNm(fleet.voyage.nm_done)} of {formatNm(fleet.voyage.total_nm)}
          </span>
        </Row>
      )}

      {orders.length === 0 ? (
        <Row label="Nothing queued." tone="muted" hairline={false} />
      ) : (
        orders.map((order, i) => {
          const live = order.status === 'pending' || order.status === 'active'
          return (
            <Row
              key={order.id}
              label={humanize(order)}
              tone={order.status === 'failed' ? 'muted' : order.status === 'active' ? 'accent' : 'default'}
              hairline={i < orders.length - 1}
              data-testid="queue-row"
              value={
                live ? (
                  <Button
                    variant="quiet"
                    size="icon"
                    disabled={busy}
                    aria-label={`Cancel order ${order.seq}`}
                    onClick={() => onCancel(order.seq)}
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
          disabled={busy}
          onClick={onClear}
          data-testid="queue-clear"
        >
          {failed ? 'Clear the halt' : 'Clear her queue'}
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

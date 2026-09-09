import { useState } from 'react'
import { Button, Figure, Icon, Note, Row, Tray, type TrayDetent } from '../../components/ui'
import { voyageEtaMs } from '../../domain/fleet'
import { refusalOfOrder, verbWord } from '../../domain/order'
import { formatNm, formatRealShort } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { FleetView, QueuedOrder } from '../../lib/rpc'

// HER QUEUE, AS A TRAY OF ROWS — §6: "The queue tray lists orders as rows … with a trailing ✕; a
// halted queue is one Note at the top of it."
//
// What died from the old OrderQueue card (§2 item 10): the `STANDING / Her queue` header, the
// `0/12 queued` count, the `as of 10:39` timestamp, the "A docked fleet earns nothing" scolding
// sentence, and the disabled Clear button standing over an empty queue. An empty queue is one quiet
// line. The `> SAIL Gaivota TO CAD` parser line each row printed (§2 item 14, §14) is gone too: a
// row reads "Sail Cádiz · 20 t aboard" in the player's words. The Clear button is the tray's ONE
// pinned action; CANCEL and CLEAR are still the server's verbs, composed by pressing a row.

export function QueueTray({
  fleet,
  busy,
  readAt,
  onCancel,
  onClear,
  onClose,
}: {
  fleet: FleetView
  busy: boolean
  readAt: number | null
  onCancel: (seq: number) => void
  onClear: () => void
  onClose: () => void
}) {
  const [detent, setDetent] = useState<TrayDetent>('half')
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
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={`${fleet.name} · queue`}
      data-testid="queue-tray"
      action={
        orders.length > 0 ? (
          <Button
            variant={failed ? 'destructive' : 'secondary'}
            className="w-full"
            disabled={busy}
            onClick={onClear}
            data-testid="queue-clear"
          >
            {failed ? 'Clear the halt' : 'Clear her queue'}
          </Button>
        ) : undefined
      }
    >
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
    </Tray>
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

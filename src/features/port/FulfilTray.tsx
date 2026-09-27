import { useState } from 'react'
import { Button, CargoBar, Figure, Note, Row, Tray, type TrayDetent } from '../../components/ui'
import { ManifestTotals } from './ManifestTotals'
import { useShellState } from '../../app/shellState'
import { fleetHoldTotal, fleetHoldUsed } from '../../domain/fleet'
import { formatDucats, formatOfTotal, formatPctDelta, formatRelative, formatUnitPrice, formatUnits } from '../../lib/format'
import type { FleetView, ManifestReceipt, Refusal, TradeRequest } from '../../lib/rpc'
import { useFulfilPreview } from '../../live/useFulfilPreview'
import { useWorld } from '../../live/worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DELIVERY — a request, unfolded: the served preview of meeting it, and ONE button.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/QUAY_LEDGER.md §3 F (owner row 76, slice 4). A press on a request's cell opens this in the
// one slot the trade tray and the basket stand in — docked to the bottom edge on a phone, beside
// the column from `lg` — so nothing above the press moves (owner row 15). It is a `Tray` and it
// takes the same shape the basket takes: what the server would do, printed; one button that does
// it; the receipt handed back to the slot on success.
//
// ── EVERY FIGURE IS THE DRY RUN'S (0087, cmd.preview_fulfil) ───────────────────────────────────
// What you deliver is the request's lot; what you get is the sale line `cmd.do_sell` realised
// inside the dry run (its total and per-unit figure); the premium is the board's own figure as
// `totals.premium`, printed by the ONE totals block (ManifestTotals) as its own row beside Market
// tax, Port fee, Profit vs bought at and Net — the same block the basket and the receipt print.
// The cargo bar's "after" is the served `hold.free_after`. Nothing here adds a premium to a sale
// or a bulk to a count.
//
// A refusal is the answer, not the absence of one: E_CONTRACT_SHORT arrives with have / need in
// units and the Note draws it; E_DAILY_CAP from the sale inside arrives in the server's own words.
// The button is dead while no estimate stands or a delivery is on the wire — never on `loading`.

export function FulfilTray({
  fleet,
  request,
  aboard,
  onClose,
  onSettled,
}: {
  fleet: FleetView
  request: TradeRequest
  /** Units of the requested good on board — the caller's one fold. */
  aboard: number
  onClose: () => void
  /** The delivery landed: the caller keeps the receipt and returns the slot to the basket. */
  onSettled: (receipt: ManifestReceipt) => void
}) {
  const { nowMs } = useShellState()
  const preview = useFulfilPreview(fleet.id, request.id)
  const fulfil = useWorld((s) => s.fulfil)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [sending, setSending] = useState(false)
  // A delivery's refusal belongs to the request that earned it.
  const [refused, setRefused] = useState<{ id: string; refusal: Refusal | null } | null>(null)
  const actRefusal = refused !== null && refused.id === request.id ? refused.refusal : null
  const refusal = actRefusal ?? preview.refusal
  const { estimate } = preview
  const sale = estimate?.lines[0] ?? null

  const send = () => {
    if (!estimate || sending) return
    setSending(true)
    setRefused(null)
    void (async () => {
      const r = await fulfil(fleet.id, request.id)
      setSending(false)
      if (r) onSettled(r)
      else setRefused({ id: request.id, refusal: useWorld.getState().refusal })
    })()
  }

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={`${request.name} · request`}
      data-testid="fulfil-tray"
      action={
        <Button
          variant="primary"
          className="w-full"
          onClick={send}
          disabled={!estimate || sending}
          busy={sending}
          busyLabel="Delivering…"
          data-testid="fulfil-send"
        >
          {estimate ? `Fulfil · ${formatDucats(estimate.totals.net)}` : 'Fulfil'}
        </Button>
      }
    >
      <CargoBar
        used={fleetHoldUsed(fleet)}
        total={fleetHoldTotal(fleet)}
        free={fleet.free_hold}
        after={estimate ? estimate.hold.free_after : null}
        className="py-2"
      />
      <Row label="Requested" value={<Figure value={formatUnits(request.qty)} size="figure" />} data-testid="fulfil-requested">
        <span className="block text-t-caption text-ink-faint">{`ends ${formatRelative(Date.parse(request.expires_at), nowMs)}`}</span>
      </Row>
      <Row label="On board" value={<Figure value={formatOfTotal(aboard, request.qty)} unit="units" />} data-testid="fulfil-aboard" />
      <Row label="Premium" value={<Figure value={formatPctDelta(request.premium_pct)} />} data-testid="fulfil-premium-pct">
        <span className="block text-t-caption text-ink-faint">over the market, per unit</span>
      </Row>
      {sale && (
        <Row label="You get" value={<Figure value={formatDucats(sale.total)} />} data-testid="fulfil-sale">
          <span className="block text-t-caption text-ink-faint">{`${formatUnits(sale.qty)} · ${formatUnitPrice(sale.avg_price)}`}</span>
        </Row>
      )}
      {estimate && <ManifestTotals totals={estimate.totals} testId="fulfil-total" />}
      {preview.loading && !estimate && !refusal && <Row label="Loading…" tone="muted" hairline={false} />}
      {refusal && (
        <Note
          tone="danger"
          code={refusal.code}
          action={
            actRefusal && (actRefusal.code === 'E_BUSY' || actRefusal.code === 'E_STALE') ? (
              <Button size="sm" variant="quiet" onClick={send}>
                Try again
              </Button>
            ) : undefined
          }
          data-testid="fulfil-refusal"
        >
          {refusal.sentence}
        </Note>
      )}
    </Tray>
  )
}

import { useState } from 'react'
import { Button, CargoBar, Figure, Icon, Note, Row, Tray, useWide, type TrayDetent } from '../../components/ui'
import { ManifestTotals } from './ManifestTotals'
import { ReceiptFace } from './ReceiptFace'
import { fleetHoldTotal, fleetHoldUsed } from '../../domain/fleet'
import { formatClock, formatDucats, formatDucatsDelta, formatInt, formatUnitPrice, formatUnits } from '../../lib/format'
import { lineDelta, type FleetView, type ManifestLine, type MarketGood, type Refusal, type SnapshotPort } from '../../lib/rpc'
import type { ManifestPreviewState } from '../../live/useManifestPreview'
import { useWorld } from '../../live/worldStore'
import { linesFor, receiptFor, useManifest } from '../../store/manifest'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BASKET — the centre of the reference the owner pointed at, as the ONE panel beside the goods.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner brought nine screenshots of a trade house — goods on the left, a basket on the right
// with the ship's cargo bar and ONE big button carrying the total — and, on seeing slice 1: *"i
// showed you the pictures and this is not what i've asked for. and look. too much blank space."*
// (docs/OWNER_REQUESTS.md rows 76 and 80). The wide glass put the tray beside the column; THIS is
// what stands in that slot: several lines staged, one total, one press (`cmd.trade_basket`, 0083),
// and the settlement after it — docs/QUAY_LEDGER.md §3 C and E.
//
// ── ONE COMPONENT, TWO GLASSES ─────────────────────────────────────────────────────────────────
// It is a `Tray`, so on a phone it rises from the bottom edge at PEEK (the title is the whole
// basket in one line) and from `lg` it IS the side panel — the same 26-rem slot the trade tray
// stands in, which is why a pick replaces it and closing the pick returns to it (PortTrade.tsx).
// There is no second component tree for the desktop; `screenLayout.ts` docks the same tray.
//
// ── THREE FACES, DECIDED BY THE STORE, NEVER BY A FLAG ─────────────────────────────────────────
//   a receipt stands for this (fleet, port)   → the RECEIPT face, until a press dismisses it
//   lines are staged                          → the BASKET face: cargo bar, the lines, the totals
//                                               block once, ONE button
//   nothing                                   → the EMPTY face: the cargo bar and one sentence.
//                                               On a wide glass the slot is never empty; on a
//                                               phone there is nothing to dock, so nothing is.
// The receipt is keyed to where it was settled and dropped by the next `stage()`
// (store/manifest.ts), so it can never hide a basket behind an old chit (PR #59 MUST-FIX 2).
//
// ── WHAT THIS FILE NEVER COMPUTES ──────────────────────────────────────────────────────────────
// No line total, no sum, no room after: `estimate.totals`, `estimate.hold.free_after` — read from
// the leaves inside the dry run (useManifestPreview, which keeps its answer across the world's
// re-read; PR #59 MUST-FIX 1). No legality: `refusal.line` is the server's own word for which
// line it will not take, and the ONE `Note` renders under that line. The button is never disabled
// on `loading` — only while no estimate stands or a trade is on the wire.
//
// Closing the BASKET face puts it away (the lines are kept; the next press on the board brings it
// back — a ✕ that threw away three lines was PR #59's NIT). Closing the RECEIPT dismisses it.

/** The count of lines, in words. */
const count = (n: number) => `${formatInt(n)} ${n === 1 ? 'line' : 'lines'}`

/** THE ONE BUTTON'S WORDS: the verb the basket is, and the figure it comes to. All buys → `Buy 3
 *  lines · 1,420 d.`; all sells → `Sell 2 lines · 980 d.`; mixed → `Trade 3 lines · +440 d.`, the
 *  net signed because a mixed basket may go either way. Nothing here is summed. */
function buttonLabel(lines: readonly ManifestLine[], totals: { bought: number; sold: number; net: number } | null): string {
  const n = count(lines.length)
  const sides = new Set(lines.map((l) => l.side))
  const verb = sides.size === 1 ? (sides.has('buy') ? 'Buy' : 'Sell') : 'Trade'
  if (!totals) return `${verb} ${n}`
  const figure = verb === 'Buy' ? formatDucats(totals.bought) : verb === 'Sell' ? formatDucats(totals.sold) : formatDucatsDelta(totals.net)
  return `${verb} ${n} · ${figure}`
}

export function ManifestPanel({
  fleet,
  port,
  goods,
  preview,
  onEdit,
  onClose,
}: {
  fleet: FleetView
  port: SnapshotPort
  /** The board's goods, for a staged line's name — never re-read here. */
  goods: readonly MarketGood[]
  /** The ONE reading of `cmd.preview_basket` for these lines, asked by PortTrade. */
  preview: ManifestPreviewState
  /** Re-open the line's price cell with its quantity, to change it. */
  onEdit: (line: ManifestLine) => void
  /** The player put the panel away (a phone), or dismissed the receipt. */
  onClose: () => void
}) {
  const wide = useWide()
  const lines = useManifest((s) => linesFor(s, fleet.id, port.code))
  const receipt = useManifest((s) => receiptFor(s, fleet.id, port.code))
  const remove = useManifest((s) => s.remove)
  const settle = useManifest((s) => s.settle)
  const dismissReceipt = useManifest((s) => s.dismissReceipt)
  const issueManifest = useWorld((s) => s.issueManifest)

  const [detent, setDetent] = useState<TrayDetent>(receipt ? 'half' : 'peek')
  const [sending, setSending] = useState(false)
  // A trade's refusal belongs to the lines that earned it — keyed by the lines' identity, so a
  // changed basket starts clean without anything having to be cleared (useTrade's idiom).
  const [refused, setRefused] = useState<{ lines: readonly ManifestLine[]; refusal: Refusal | null } | null>(null)
  const tradeRefusal = refused !== null && refused.lines === lines ? refused.refusal : null
  const refusal = tradeRefusal ?? preview.refusal
  const { estimate } = preview

  const face = receipt ? 'receipt' : lines.length > 0 ? 'basket' : 'empty'
  // A phone docks a tray only when it has something to say; a wide glass keeps the slot filled.
  if (!wide && face === 'empty') return null
  const atPeek = !wide && detent === 'peek'

  const send = () => {
    if (!estimate || sending || lines.length === 0) return
    setSending(true)
    setRefused(null)
    void (async () => {
      const r = await issueManifest(fleet.id, lines)
      setSending(false)
      if (r) {
        setDetent('half')
        settle(fleet.id, port.code, r)
      } else setRefused({ lines, refusal: useWorld.getState().refusal })
    })()
  }

  const cargo = (
    <CargoBar
      used={fleetHoldUsed(fleet)}
      total={fleetHoldTotal(fleet)}
      free={fleet.free_hold}
      after={face === 'basket' && estimate ? estimate.hold.free_after : null}
      className="py-2"
    />
  )

  if (receipt) {
    // Stamped with the LEDGER's clock (formatClock, the same HH:MM the history rows carry), not
    // with `game_day`: that is an epoch counter no screen prints.
    const atMs = Date.parse(receipt.at)
    const done = () => {
      dismissReceipt()
      onClose()
    }
    return (
      <Tray
        detent={detent}
        onDetentChange={(next) => (next === 'closed' ? done() : setDetent(next))}
        title={`Traded · ${Number.isFinite(atMs) ? formatClock(atMs) : '--:--'}`}
        data-testid="receipt-panel"
        action={
          atPeek ? undefined : (
            <Button variant="secondary" className="w-full" onClick={done} data-testid="receipt-done">
              Done
            </Button>
          )
        }
      >
        <ReceiptFace receipt={receipt} />
      </Tray>
    )
  }

  if (face === 'empty') {
    return (
      <Tray detent={detent} onDetentChange={setDetent} title="Basket" dismissible={false} data-testid="basket-panel">
        {cargo}
        <Row label="Your basket is empty. Press a price to add goods." tone="muted" hairline={false} data-testid="basket-empty" />
      </Tray>
    )
  }

  const note = (
    <Note
      tone="danger"
      code={refusal?.code}
      action={
        tradeRefusal && (tradeRefusal.code === 'E_BUSY' || tradeRefusal.code === 'E_STALE') ? (
          <Button size="sm" variant="quiet" onClick={send}>
            Try again
          </Button>
        ) : undefined
      }
      data-testid="basket-refusal"
    >
      {refusal?.sentence}
    </Note>
  )
  const noteAt = refusal?.line !== undefined && refusal.line >= 0 && refusal.line < lines.length ? refusal.line : null
  const label = buttonLabel(lines, estimate?.totals ?? null)

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      // At peek the title is the whole basket in one line, because the button is not shown there
      // (a pinned action under a peek is 2px of button — PR #59 review SHOULD 5).
      title={atPeek ? label : `Basket · ${count(lines.length)}`}
      dismissible={!wide}
      data-testid="basket-panel"
      action={
        atPeek ? undefined : (
          <Button
            variant="primary"
            className="w-full"
            onClick={send}
            disabled={!estimate || sending}
            busy={sending}
            busyLabel="Trading…"
            data-testid="basket-send"
          >
            {label}
          </Button>
        )
      }
    >
      {cargo}
      {lines.map((line, i) => {
        const served = estimate?.lines.find((l) => l.index === i) ?? null
        const name = goods.find((g) => g.code === line.good)?.name ?? served?.name ?? line.good
        // TWO SIBLING BUTTONS, NEVER NESTED: the row itself (a <button>, Row.tsx) re-opens the
        // line's cell to change it; the ✕ beside it strikes the line.
        return (
          <div key={line.good}>
            <div className="flex items-center border-b border-edge">
              <Row
                label={name}
                value={served ? <Figure value={formatDucatsDelta(lineDelta(served))} /> : undefined}
                onClick={() => onEdit(line)}
                hairline={false}
                className="min-w-0 flex-1"
                data-testid="basket-line"
              >
                <span className="block text-t-caption text-ink-faint">
                  {`${line.side} · ${formatUnits(line.qty)}${served ? ` · ${formatUnitPrice(served.avg_price)}` : ''}`}
                </span>
                {served && line.side === 'sell' && (
                  <span className="block text-t-caption text-ink-faint">
                    {served.profit === null ? 'Purchase price unknown' : `${served.profit < 0 ? 'loss' : 'profit'} ${formatDucatsDelta(served.profit)}`}
                  </span>
                )}
              </Row>
              <Button size="icon" variant="quiet" aria-label={`Remove ${name}`} onClick={() => remove(line.good)}>
                <Icon name="close" size={20} />
              </Button>
            </div>
            {noteAt === i && note}
          </div>
        )
      })}
      {refusal && noteAt === null && note}

      {preview.loading && !estimate && <Row label="Loading…" tone="muted" hairline={false} />}
      {estimate && <ManifestTotals totals={estimate.totals} testId="basket-total" />}
    </Tray>
  )
}

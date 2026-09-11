import { useState } from 'react'
import { Button, deltaTone, Figure, Icon, Note, Row, Tray, type TrayDetent } from '../../components/ui'
import { ReceiptFace } from './ReceiptFace'
import { formatClock, formatDucats, formatDucatsDelta, formatInt, formatTuns } from '../../lib/format'
import type { FleetView, ManifestLine, MarketGood, Refusal, SnapshotPort } from '../../lib/rpc'
import type { ManifestPreviewState } from '../../live/useManifestPreview'
import { useWorld } from '../../live/worldStore'
import { linesFor, useManifest } from '../../store/manifest'

// THE MANIFEST — the tray's other face. docs/QUAY_LEDGER.md §3 C and E (owner row 76, slice 2).
//
// The lines the player staged from either price cell, the SERVED totals `cmd.preview_basket` gave
// for exactly those lines, and ONE button that lands them all or none (`cmd.trade_basket`, 0083).
// After it lands the same tray turns over to the receipt (ReceiptFace.tsx) until the player
// dismisses it; the ledger beneath has already been read back by then (worldStore's one
// post-trade read).
//
// ── ONE TRAY, WHOSE FACE THE BOARD DECIDES ─────────────────────────────────────────────────────
// PortTrade mounts exactly one of TradeTray (a pick is open), this tray's receipt face, this
// tray's manifest face, or nothing. This file never decides that; it draws the face the store
// says is due. It opens at PEEK — the title is the whole manifest in one line ("Manifest · 3
// lines · −23,650 d.") so the board stays the subject — and the player drags it to half to read
// the totals and press the button, which rides in the pinned action region (Tray.tsx).
//
// ── WHAT THIS FILE NEVER COMPUTES ──────────────────────────────────────────────────────────────
// No line total, no sum, no purse after, no hold after: `estimate.totals`, `estimate.purse`,
// `estimate.hold` — all read from the leaves inside the dry run. No legality: `refusal.line` is the
// server's own word for which line it will not take, and the ONE `Note` renders under that line.
// E_BUSY (the quay was locked by the market's clock; nothing decided) offers the one fix the
// server names — ask again — and is otherwise the same Note.
//
// Closing the MANIFEST face (✕, or a drag below peek) discards the manifest: peek is already the
// out-of-the-way stop, so a dismissal past it is the player throwing the basket down. Closing the
// RECEIPT face dismisses the receipt; the world is already read.

export function ManifestTray({
  fleet,
  port,
  goods,
  preview,
  onEdit,
}: {
  fleet: FleetView
  port: SnapshotPort
  /** The board's goods, for a staged line's name — never re-read here. */
  goods: readonly MarketGood[]
  /** The ONE reading of `cmd.preview_basket` for these lines, asked by PortTrade. */
  preview: ManifestPreviewState
  /** Re-open the line's price cell with its quantity, to change it. */
  onEdit: (line: ManifestLine) => void
}) {
  const lines = useManifest((s) => linesFor(s, fleet.id, port.code))
  const receipt = useManifest((s) => s.receipt)
  const remove = useManifest((s) => s.remove)
  const clear = useManifest((s) => s.clear)
  const settle = useManifest((s) => s.settle)
  const dismissReceipt = useManifest((s) => s.dismissReceipt)
  const issueManifest = useWorld((s) => s.issueManifest)

  const [detent, setDetent] = useState<TrayDetent>(receipt ? 'half' : 'peek')
  const [sending, setSending] = useState(false)
  // A trade's refusal belongs to the lines that earned it — keyed by the lines' identity, so a
  // changed manifest starts clean without anything having to be cleared (useTrade's idiom).
  const [refused, setRefused] = useState<{ lines: readonly ManifestLine[]; refusal: Refusal | null } | null>(null)
  const tradeRefusal = refused !== null && refused.lines === lines ? refused.refusal : null
  const refusal = tradeRefusal ?? preview.refusal
  const { estimate } = preview

  const send = () => {
    if (!estimate || sending || lines.length === 0) return
    setSending(true)
    setRefused(null)
    void (async () => {
      const r = await issueManifest(fleet.id, lines)
      setSending(false)
      if (r) {
        setDetent('half')
        settle(r)
      } else setRefused({ lines, refusal: useWorld.getState().refusal })
    })()
  }

  if (receipt) {
    // Stamped with the LEDGER's clock (formatClock, the same HH:MM the ledger rows carry), not with
    // `game_day`: that is an epoch counter (world.game_day, 0005) no screen prints, and "day
    // 621,220" is a config knob wearing a title.
    const atMs = Date.parse(receipt.at)
    return (
      <Tray
        detent={detent}
        onDetentChange={(next) => (next === 'closed' ? dismissReceipt() : setDetent(next))}
        title={`Settled · ${Number.isFinite(atMs) ? formatClock(atMs) : '--:--'}`}
        data-testid="receipt-tray"
      >
        <ReceiptFace receipt={receipt} />
      </Tray>
    )
  }
  if (lines.length === 0) return null

  const count = `${lines.length} ${lines.length === 1 ? 'line' : 'lines'}`
  const net = estimate ? ` · ${formatDucatsDelta(estimate.totals.net)}` : ''
  const note = (
    <Note
      tone="danger"
      code={refusal?.code}
      action={
        refusal?.code === 'E_BUSY' ? (
          <Button size="sm" variant="quiet" onClick={tradeRefusal ? send : preview.reask}>
            Try again
          </Button>
        ) : undefined
      }
      data-testid="manifest-refusal"
    >
      {refusal?.sentence}
    </Note>
  )
  const noteAt = refusal?.line !== undefined && refusal.line >= 0 && refusal.line < lines.length ? refusal.line : null

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? clear() : setDetent(next))}
      title={`Manifest · ${count}${net}`}
      data-testid="manifest-tray"
      action={
        <Button
          variant="primary"
          className="w-full"
          onClick={send}
          disabled={!estimate || sending}
          busy={sending}
          busyLabel="Trading…"
          data-testid="manifest-send"
        >
          {`Trade ${count}${net}`}
        </Button>
      }
    >
      {lines.map((line, i) => {
        const served = estimate?.lines.find((l) => l.index === i) ?? null
        const name = goods.find((g) => g.code === line.good)?.name ?? served?.name ?? line.good
        // TWO SIBLING BUTTONS, NEVER NESTED: the row itself (a <button>, Row.tsx) re-opens the
        // line's cell to change it; the ✕ beside it strikes the line. The hairline rides on the
        // pair so it runs under both.
        return (
          <div key={line.good}>
            <div className="flex items-center border-b border-edge">
              <Row
                label={name}
                value={served ? <Figure value={formatDucatsDelta(line.side === 'sell' ? served.total : -served.total)} /> : undefined}
                onClick={() => onEdit(line)}
                hairline={false}
                className="min-w-0 flex-1"
                data-testid="manifest-line"
              >
                <span className="block text-t-caption text-ink-faint">
                  {`${line.side} · ${formatTuns(line.qty)}${served ? ` @ ${formatInt(served.avg_price)}` : ''}`}
                </span>
                {served && line.side === 'sell' && (
                  <span className="block text-t-caption text-ink-faint">
                    {served.profit !== null ? `${formatDucatsDelta(served.profit)} vs paid` : 'not on record'}
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

      {preview.loading && <Row label="Asking the quay what it comes to" tone="muted" />}
      {estimate && (
        <>
          <Row label="Goods at mid" value={<Figure value={formatDucats(estimate.totals.goods_at_mid)} />} data-testid="manifest-total" />
          <Row label="Market tax" value={<Figure value={formatDucats(estimate.totals.tax)} />} data-testid="manifest-total" />
          <Row label="Spread" value={<Figure value={formatDucats(estimate.totals.spread)} />} data-testid="manifest-total" />
          {estimate.totals.haggle_saved > 0 && (
            <Row label="Haggle saved" value={<Figure value={formatDucats(estimate.totals.haggle_saved)} tone="success" />} data-testid="manifest-total" />
          )}
          {estimate.totals.sold > 0 && (
            <Row
              label="Profit vs paid"
              tone={estimate.totals.profit === null ? 'muted' : 'default'}
              value={
                estimate.totals.profit === null ? (
                  'not on record'
                ) : (
                  <Figure value={formatDucatsDelta(estimate.totals.profit)} tone={deltaTone(estimate.totals.profit)} />
                )
              }
              data-testid="manifest-total"
            />
          )}
          <Row
            label="Net to purse"
            value={<Figure value={formatDucatsDelta(estimate.totals.net)} size="figure" tone={deltaTone(estimate.totals.net)} />}
            data-testid="manifest-total"
          />
          <Row label="Purse after" value={<Figure value={formatDucats(estimate.purse.after)} />} data-testid="manifest-total" />
          <Row
            label="Hold after"
            value={<Figure value={formatInt(estimate.hold.free_after)} unit="t free" />}
            hairline={false}
            data-testid="manifest-total"
          />
        </>
      )}
    </Tray>
  )
}

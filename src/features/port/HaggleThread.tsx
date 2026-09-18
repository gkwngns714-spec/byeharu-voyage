import { useState } from 'react'
import { Bar, Button, Figure, Note, Row, type TradeAct } from '../../components/ui'
import { useHaggleState } from './useHaggleState'
import { formatDucats, formatOfTotal, formatPct, formatPctPoints, formatUnitPrice } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import type { MarketGood, Refusal } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE HAGGLE, AS A THREAD — inside the trade tray, on BOTH sides (docs/QUAY_LEDGER.md §3 D and
// Appendix A, owner row 76, slice 3).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The reference's 협상 scene is a conversation: the merchant names a figure, you press, he answers,
// the stake changes. Here it is one `Row` folded — `Haggle · 2 / 3 tries left · 45%` — that unfolds
// IN PLACE inside the tray body into the turns so far, the stake, and two buttons. Nothing above
// the row moves when it unfolds (what is below moves down, which is what an unfold IS; the tray
// itself is `fixed`, so the ledger never moves at all).
//
// ── EVERY SENTENCE IS THE SERVER'S ─────────────────────────────────────────────────────────────
// A turn is `cmd.haggle`'s own `message`, verbatim — won, won-at-cap or lost, 0022:558-580 writes
// all three. This file composes NO outcome sentence: a client template beside the server's would
// be two authors for what the merchant said, and one of them could lie. A refusal (E_HAGGLE_SPENT,
// E_NO_STOCK, E_NO_CARGO) arrives through the store's `refusal` in the server's words and is a
// `Note`, never a turn.
//
// ── EVERY FIGURE IS SERVED ─────────────────────────────────────────────────────────────────────
//   Port fee   the published spread → the spread this house executes at (`world.haggle_state`),
//              `formatPct` of the served fractions; one figure when they agree.
//   Price      `cmd.preview`'s served `avg_price` for the quantity on the button — the ONLY figure
//              that reflects an open bargain (`world.market`'s buy/sell never do: 0022 refused to
//              move the published price). Across a won attempt the figure remembered at the press
//              is shown before → after, so the player sees what the win was worth per unit.
//   Haggle saved   `preview.haggle_saved` (0083) on THIS lot, when there is any.
//   Tries      the segmented `Bar`, `attempts_left` of `attempts_max`.
//   Next try   `next_odds_pct` — `public.haggle_odds`, the same authority the verb rolls against;
//              muted once the stack is at the floor, because a win there moves nothing.
// No odds are computed here, no spread arithmetic, no "price after". What the server did not say,
// this file does not print.
//
// ── ONE SIDE OR THE OTHER, THE SAME THREAD ─────────────────────────────────────────────────────
// `cmd.haggle(fleet, good, side)` — the side is load-bearing (a BUY bargain needs the stock, a SELL
// one needs the cargo; catalog.ts), and a bargain won on either side is spent on the next trade of
// the good here, either side (0022:670-673). The tray mounts this under the stepper on both its
// faces, keyed per pick so a thread never carries another good's turns.
//
// `HaggleRow.tsx` (buy side only, one figure, one `Try`) is what this REPLACES, and it is deleted
// in the same slice (docs/NO_SPAGHETTI.md §5).

interface Turn {
  won: boolean
  message: string
}

export function HaggleThread({
  fleetId,
  good,
  side,
  preview,
}: {
  fleetId: string
  good: MarketGood
  side: 'buy' | 'sell'
  /** The tray's own dry run for the quantity on the button — `useTrade`'s one reading. */
  preview: TradeAct['preview']
}) {
  const haggle = useWorld((s) => s.haggle)
  const read = useHaggleState(fleetId, good.code)
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [turns, setTurns] = useState<Turn[]>([])
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  /** The served per-unit figure at the press before the first WON attempt of this thread. */
  const [wonFrom, setWonFrom] = useState<number | null>(null)

  const quay = read.state?.docked === true ? read.state : null
  if (!quay) return null

  const press = () => {
    if (busy) return
    setBusy(true)
    setRefusal(null)
    const stake = preview?.avg_price ?? null
    void haggle(fleetId, good.good_id, side).then((r) => {
      setBusy(false)
      if (r === null) {
        setRefusal(useWorld.getState().refusal)
        return
      }
      setTurns((t) => [...t, { won: r.won, message: r.message }])
      if (r.won && stake !== null) setWonFrom((prev) => prev ?? stake)
    })
  }

  const feeSame = Math.abs(quay.spread_effective - quay.spread_published) < 1e-9
  const fee = feeSame
    ? formatPct(quay.spread_published, 1)
    : `${formatPct(quay.spread_published, 1)} → ${formatPct(quay.spread_effective, 1)}`
  const each = preview?.avg_price ?? null
  const price =
    each === null
      ? null
      : wonFrom !== null && wonFrom !== each
        ? `${formatUnitPrice(wonFrom)} → ${formatUnitPrice(each)}`
        : formatUnitPrice(each)
  const saved = preview?.haggle_saved ?? 0
  const oddsTone = quay.at_floor ? 'faint' : quay.next_odds_pct >= 45 ? 'success' : 'warning'

  return (
    <>
      <Row
        label="Bargain"
        chevron
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        data-testid="haggle-row"
        value={
          <span className="flex items-center gap-3">
            <Figure value={formatOfTotal(quay.attempts_left, quay.attempts_max)} unit="tries left" tone={read.loading ? 'faint' : 'muted'} />
            <Figure value={formatPctPoints(quay.next_odds_pct, 0)} tone={oddsTone} />
          </span>
        }
      />
      {open && (
        <div data-testid="haggle-thread">
          {turns.map((t, i) => (
            <Row key={i} label={t.message} tone={t.won ? 'default' : 'muted'} hairline={false} data-testid="haggle-turn" />
          ))}
          {refusal && (
            <Note tone="danger" code={refusal.code} data-testid="haggle-refusal">
              {refusal.sentence}
            </Note>
          )}
          <Row label="Port fee" value={<Figure value={fee} />} data-testid="haggle-fee" />
          {price === null ? (
            <Row label="Price" tone="muted" value="Loading…" data-testid="haggle-price" />
          ) : (
            <Row label="Price" value={<Figure value={price} />} data-testid="haggle-price" />
          )}
          {saved > 0 && (
            <Row label="Bargain saved" value={<Figure value={formatDucats(saved)} tone="success" />} data-testid="haggle-saved" />
          )}
          <Row label="Tries" value={<Figure value={formatOfTotal(quay.attempts_left, quay.attempts_max)} unit="tries" />}>
            <Bar value={quay.attempts_left} of={quay.attempts_max} tone="accent" label="tries left" className="mt-1" />
          </Row>
          <Row
            label="Next try"
            hairline={false}
            value={<Figure value={formatPctPoints(quay.next_odds_pct, 0)} tone={oddsTone} unit={quay.at_floor ? 'at the floor' : undefined} />}
            data-testid="haggle-odds"
          />
          <div className="grid grid-cols-2 gap-2 py-2">
            <Button variant="secondary" className="w-full" onClick={() => setOpen(false)} data-testid="haggle-take">
              Take it
            </Button>
            <Button variant="primary" className="w-full" busy={busy} busyLabel="…" onClick={press} data-testid="haggle-press">
              {turns.length === 0 ? 'Bargain' : 'Try again'}
            </Button>
          </div>
        </div>
      )}
    </>
  )
}

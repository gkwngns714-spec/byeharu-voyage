import { useMemo, useState } from 'react'
import {
  Button,
  Field,
  Figure,
  Note,
  Row,
  TileField,
  TradeTile,
  TradeTray,
} from '../../components/ui'
import { useBuyCapacity } from '../../live/useBuyCapacity'
import { useHaggleState } from './useHaggleState'
import { fleetCargoByCode } from '../../domain/fleet'
import { buyableHere } from '../../domain/market'
import { findVerb, orderText } from '../../domain/order'
import { fold, foldedMatch } from '../../lib/text'
import { formatInt, formatPctPoints } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import type { FleetView, MarketView, Refusal, VerbSpec } from '../../lib/rpc'

// BUY AND SELL — the goods field, and the tray a price cell opens. §6.
//
// This is the whole of what OrderComposer's `good` arm, its rail, its `HaggleBlock` and the trade
// fold were. The tile and the tray are the design system's (TradeTile / TradeTray), the same ones
// PORT draws — one market, drawn one way, on the two quays a player buys from. The FIELD is filtered
// by intent exactly as the old GoodPicker was: a BUY field is this city's quay (`buyableHere`), a
// SELL field is what she is carrying — so every live cell in a field is one the server will honour.
//
// THE PRICE IS THE ACT (the owner, row 6): tapping a cell names the verb AND the good on the one
// draft, and opens the tray under the press. Nothing in the field moves — the tray is `fixed`
// (tests/layout.spec.ts holds this on `good-pick-tile`). The quantity, the ceiling and the cost are
// the tray's; the haggle is one row inside it (§6: "Bargain · 3 left · 45 % [Try]").

export function TradeQuestion({
  intent,
  fleet,
  market,
  step,
  verbs,
  good,
  qty,
  onTrade,
  onSetQty,
  onClose,
}: {
  intent: 'buy' | 'sell'
  fleet: FleetView
  market: MarketView
  step: number
  verbs: readonly VerbSpec[]
  /** The good chosen so far (the draft's `good`), or undefined while the field is open. */
  good: string | undefined
  /** The draft's `qty`, as a number — the one authority the tray steps and the line is issued from. */
  qty: number | null
  /** A price cell was pressed: set the verb and the good on the draft. */
  onTrade: (intent: 'buy' | 'sell', code: string) => void
  onSetQty: (n: number) => void
  onClose: () => void
}) {
  const [filter, setFilter] = useState('')
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const [sending, setSending] = useState(false)
  const issue = useWorld((s) => s.issue)

  const aboard = useMemo(() => fleetCargoByCode(fleet), [fleet])

  const shown = useMemo(() => {
    const q = fold(filter.trim())
    return market.goods
      // A BUY field is the quay's own book; a SELL field is what she carries. The old GoodPicker
      // narrowed exactly this way, so a live cell is never one the server would refuse for the list.
      .filter((g) => (intent === 'buy' ? buyableHere(g) : (aboard[g.code] ?? 0) > 0))
      .filter((g) => foldedMatch(q, g.name, g.code, g.category))
      .sort((a, b) => a.name.localeCompare(b.name))
  }, [market.goods, intent, aboard, filter])

  const picked = good ? market.goods.find((g) => g.code === good) : undefined
  const capacity = useBuyCapacity(intent === 'buy' && picked ? fleet.id : null, picked?.code ?? null)

  const close = () => {
    setRefusal(null)
    onClose()
  }

  return (
    <>
      <Field
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        onClear={() => setFilter('')}
        aria-label="Filter goods"
        placeholder="Filter goods"
        spellCheck={false}
        autoCorrect="off"
      />

      {shown.length === 0 ? (
        <Note tone="neutral" className="mt-3">
          {intent === 'sell'
            ? 'She is carrying nothing this port will trade.'
            : 'Nothing on this quay answers to that.'}
        </Note>
      ) : (
        <TileField className="mt-3">
          {shown.map((g) => (
            <TradeTile
              key={g.code}
              good={g}
              aboard={aboard[g.code] ?? 0}
              canBuy={buyableHere(g)}
              selected={good === g.code}
              onBuy={() => {
                setRefusal(null)
                onTrade('buy', g.code)
              }}
              onSell={() => {
                setRefusal(null)
                onTrade('sell', g.code)
              }}
            />
          ))}
        </TileField>
      )}

      {picked && (
        <TradeTray
          pick={{ good: picked, intent }}
          aboard={aboard[picked.code] ?? 0}
          capacity={capacity}
          step={step}
          qty={{ value: qty, onChange: onSetQty }}
          act={{
            send: () => {
              const spec = findVerb(verbs, intent === 'buy' ? 'BUY' : 'SELL')
              const n = qty ?? 0
              if (!spec || n <= 0 || sending) return
              setRefusal(null)
              setSending(true)
              void (async () => {
                const line = orderText(spec, { good: picked.code, qty: String(n) }, fleet.name)
                const okay = await issue(fleet.id, line, null)
                setSending(false)
                if (okay) close()
                else setRefusal(useWorld.getState().refusal)
              })()
            },
            sending,
            ready: (qty ?? 0) > 0,
            total: intent === 'buy' && capacity.estTotal !== null && qty === (capacity.bound?.max ?? -1)
              ? capacity.estTotal
              : null,
          }}
          onClose={close}
        >
          {intent === 'buy' && <HaggleRow fleetId={fleet.id} good={picked} />}
          {refusal && (
            <Note tone="danger" code={refusal.code} data-testid="trade-tray-refusal">
              {refusal.sentence}
            </Note>
          )}
        </TradeTray>
      )}
    </>
  )
}

// THE BARGAIN, AS ONE ROW (§6). What HaggleBlock was — a bordered card with an Explain, a Meter, a
// Badge and its own Notice — folded to a line: the odds, the tries left, and the one button. The
// act is never disabled by a client rule (the server owns E_HAGGLE_SPENT and its sentence); a lost
// bargain is `ok, won:false`, not an error. `useHaggleState` re-asks when the world is read, so a
// struck concession shows up on the next read.
function HaggleRow({ fleetId, good }: { fleetId: string; good: MarketView['goods'][number] }) {
  const haggle = useWorld((s) => s.haggle)
  const read = useHaggleState(fleetId, good.code)
  const [busy, setBusy] = useState(false)
  const quay = read.state?.docked === true ? read.state : null
  if (!quay) return null

  return (
    <Row
      label="Bargain"
      value={
        <span className="flex items-center gap-3">
          <Figure value={formatInt(quay.attempts_left)} unit="left" tone="muted" />
          <Figure value={formatPctPoints(quay.next_odds_pct, 0)} tone={quay.next_odds_pct >= 45 ? 'success' : 'warning'} />
          <Button
            variant="secondary"
            size="sm"
            busy={busy}
            busyLabel="…"
            onClick={() => {
              setBusy(true)
              void haggle(fleetId, good.good_id, 'buy').finally(() => setBusy(false))
            }}
          >
            Try
          </Button>
        </span>
      }
    >
      {quay.concession > 0 && (
        <span className="block text-t-caption text-success">
          {formatPctPoints(quay.concession_pct, 1)} off his cut, held
        </span>
      )}
    </Row>
  )
}

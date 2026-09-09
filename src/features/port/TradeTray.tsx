import { useState } from 'react'
import { Button, Figure, Note, Row, Stepper, Tray, type TrayDetent } from '../../components/ui'
import { useBuyCapacity } from '../../live/useBuyCapacity'
import { fleetCargoByCode } from '../../domain/fleet'
import { findVerb, orderText } from '../../domain/order'
import { formatDucats, formatInt, formatTuns } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import type { FleetView, MarketGood, Refusal } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRADE TRAY — where a price becomes a quantity, and the quantity becomes an order.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/UI_DIRECTION.md §6, PORT and COMMAND alike: *"TRAY: identical to Command's buy tray (same
// component, same `issue`)"*. It is built here because PORT is step 4 and COMMAND is step 5, and
// the direction says so in as many words: *"Building the tray here settles the 'press moves
// nothing' question for every later screen."* When the composer is rewritten it imports THIS, and
// the quantity rule stops having two spellings.
//
// ── WHY A TRAY AND NOT A FOLD ──────────────────────────────────────────────────────────────────
// The owner's rule, said four times: *"when pressed unfold another so that i can choose how much i
// buy … don't restruct anything."* The fold satisfied the first half and fought the second — a
// block inserted into a grid re-flows the row it lands in, which is why `inRowsOf`, `useTileCols`
// and `tileFieldCols` existed at all: three modules of arithmetic to insert a box after a WHOLE
// row. A tray keeps the second half absolutely — it is docked to the bottom edge, so NOTHING above
// the press moves, ever — and the arithmetic is deleted rather than made cleverer (§5).
//
// ── WHAT THIS FILE DOES NOT KNOW ───────────────────────────────────────────────────────────────
// What she can carry, what she can afford, what a tun of this costs at twenty tuns. All three are
// `world.buy_capacity()`'s and arrive answered; the gauge's TRACK is the stock (the owner, row 63:
// *"the gauge max will be the stock"*) and the server's ceiling is the tick it clamps at. No price
// is multiplied out here: buying moves the market (§G.2), so a client-side `price x qty` is wrong
// by the steps — the only total printed is the server's own `est_total`, and it is printed only
// where it is the total OF the quantity chosen.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export interface TradePick {
  good: MarketGood
  intent: 'buy' | 'sell'
}

export function TradeTray({
  pick,
  fleet,
  culture,
  onClose,
}: {
  /** What was tapped: the good, and which of its two prices. */
  pick: TradePick
  /** The fleet lying here. A tray never opens without one — there is nothing to trade with. */
  fleet: FleetView
  /** This port's culture, for the one Note it explains: a good the quay will not deal in. */
  culture: string
  onClose: () => void
}) {
  const { good, intent } = pick
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [qty, setQty] = useState<number | null>(null)
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)

  // READ AT THE LEAF (worldStore rule 4, and §5's architecture rule): the tray asks the world for
  // the grammar and the step itself rather than taking them down a prop chain.
  const issue = useWorld((s) => s.issue)
  // A SELECTOR RETURNS A SERVED REFERENCE, never a fresh literal: `?? []` builds a new array on
  // every read and zustand compares by identity, which is a render loop (React error #185).
  const verbs = useWorld((s) => s.snapshot?.verbs)
  const step = useWorld((s) => s.snapshot?.config.trade_step_tuns ?? 1)
  // Her own manifest, folded by the one function that folds it (domain/fleet).
  const aboard = fleetCargoByCode(fleet)[good.code] ?? 0

  // ONE reading of world.buy_capacity(), and only while BUYING — a sell has no purse ceiling.
  const capacity = useBuyCapacity(intent === 'buy' ? fleet.id : null, good.code)

  const track = intent === 'buy' ? Math.floor(good.stock) : aboard
  const ceiling = intent === 'buy' ? (capacity.bound?.max ?? 0) : aboard
  const chosen = Math.min(qty ?? Math.min(ceiling, Math.max(1, Math.round(step))), ceiling)
  const spec = findVerb(verbs ?? [], intent === 'buy' ? 'BUY' : 'SELL')
  // WHY THIS QUAY WILL NOT SELL HER ANY, when it will not. Two served flags, two different
  // reasons, and the CULTURE one is the sentence §6 asks for. It is written on the SELL tray
  // because that is the tray a refused good can open at all: her hold is why the good is in this
  // payload (0061), the buy cell beside it is dead, and this is the reason it is dead.
  const refusedBy =
    good.available === false
      ? `A ${culture} quay does not deal in ${good.name.toLowerCase()}. She may land it here; she may never take more on.`
      : good.offered === false
        ? `This city does not trade ${good.name.toLowerCase()}. She may land it here; she may never take more on.`
        : null

  const send = () => {
    if (!spec || sending || chosen <= 0) return
    setSending(true)
    setRefusal(null)
    void (async () => {
      // THE LINE IS COMPOSED AT ISSUE TIME AND NEVER PRINTED (§5). `orderText` walks the server's
      // own verb grammar, so there is one composer on this side of the wire — the screen does not
      // write order strings, and the player never reads one.
      const okay = await issue(fleet.id, orderText(spec, { good: good.code, qty: String(chosen) }, fleet.name), null)
      setSending(false)
      if (okay) onClose()
      else setRefusal(useWorld.getState().refusal)
    })()
  }

  const act = intent === 'buy' ? 'Buy' : 'Sell'
  // The total is the SERVER's, so it is named only where it is the total of what was chosen.
  const total = intent === 'buy' && capacity.estTotal !== null && chosen === ceiling ? capacity.estTotal : null

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={`${good.name} · ${intent}`}
      data-testid="trade-tray"
      action={
        <Button
          variant="primary"
          className="w-full"
          onClick={send}
          disabled={sending || chosen <= 0 || spec === undefined}
          busy={sending}
          busyLabel="Sending…"
          data-testid="trade-tray-send"
        >
          {`${act} ${formatTuns(chosen)}`}
          {total !== null ? ` · ${formatDucats(total)}` : ''}
        </Button>
      }
    >
      {/* CULTURE, WHERE IT ACTUALLY REFUSES SOMETHING (§6: "Culture appears only as a Note on a
          refused good"). `available: false` is the served fact that the port's culture refuses the
          good (B.4) — it is not derived here, and the word appears on no other screen. */}
      {refusedBy !== null && (
        <Note tone="warning" data-testid="trade-tray-refused">
          {refusedBy}
        </Note>
      )}

      {intent === 'buy' ? (
        capacity.bound ? (
          <Row
            label="At most"
            value={<Figure value={formatInt(capacity.bound.max)} unit="t" size="figure" />}
          >
            <span className="block text-t-caption text-ink-faint">{`stopped by ${capacity.bound.binding}`}</span>
          </Row>
        ) : (
          <Row
            label={capacity.loading ? 'Asking the quay what she can take' : 'The most she can take is not known'}
            tone="muted"
          />
        )
      ) : (
        <Row label="Aboard" value={<Figure value={formatTuns(aboard)} size="figure" />} />
      )}

      <div className="py-3">
        <Stepper
          value={chosen}
          onChange={setQty}
          max={track}
          cap={ceiling}
          step={Math.max(1, Math.round(step))}
          unit="t"
          label={`tuns of ${good.name}`}
          presets={ceiling > 0 ? [{ label: 'All she can', value: ceiling }] : undefined}
          data-testid="trade-tray-qty"
        />
      </div>

      <Row
        label="On the quay"
        value={<Figure value={formatTuns(good.stock)} unit={`of ${formatTuns(good.stock_target)}`} />}
        hairline={false}
      />

      {/* The server's refusal, in the server's own sentence. The CODE goes to console.debug and
          never to the quay (§5's Note contract, and §2 item 13: a code is for a log). */}
      {refusal && (
        <Note tone="danger" code={refusal.code} data-testid="trade-tray-refusal">
          {refusal.sentence}
        </Note>
      )}
    </Tray>
  )
}

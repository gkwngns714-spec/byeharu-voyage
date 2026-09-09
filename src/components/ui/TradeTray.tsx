import { useEffect, useState, type ReactNode } from 'react'
import { Button } from './Button'
import { Figure } from './Figure'
import { Note } from './Note'
import { Row } from './Row'
import { Stepper } from './Stepper'
import { Tray } from './Tray'
import type { TrayDetent } from './trayDetents'
import { formatDucats, formatInt, formatTuns } from '../../lib/format'
import type { MarketGood, Refusal } from '../../lib/rpc'
import type { BuyCapacityState } from '../../lib/trade'

// THE TRADE TRAY — where a price becomes a quantity, and the quantity becomes an order.
//
// docs/UI_DIRECTION.md §6, PORT and COMMAND alike: *"TRAY: identical to Command's buy tray (same
// component, same `issue`)"*. So it is ONE component, and it lives here rather than in either
// screen: tests/sections.spec.ts refuses to let COMMAND import PORT, and a tray both quays open is
// neither quay's. The design system may not read the store ("machinery knows nothing above it"),
// so — exactly as the fold this replaces did (tradePickers.tsx) — the server's answer to "how much
// can she take" arrives as a PROP, and the act arrives as a function. Each screen asks
// `useTrade` (src/live/useTrade.ts) once and hands both down: that hook is the one spelling of the
// act, so the two quays cannot issue the same line two ways.
//
// FOR ONE DAY THERE WERE TWO OF THESE. PORT was rewritten first (step 4) and built its own tray;
// COMMAND (step 5) promoted this one into the design system in the same afternoon. Same rows,
// same gauge, same button, two files — the shape the standing law forbids. PORT's copy is deleted
// and PORT composes this, which is what §6 said in the first place.
//
// ── THE OWNER'S RULE, KEPT BY CONSTRUCTION ─────────────────────────────────────────────────────
// *"when pressed unfold another so that i can choose how much i buy … don't restruct anything."*
// The old fold kept the first half and fought the second: a box inserted into a grid re-flows the
// row it lands in, which is why three modules of arithmetic existed to place it after a WHOLE
// row. A docked tray keeps the second half absolutely — nothing above the press moves, ever — and
// the arithmetic is deleted rather than made cleverer (§5).
//
// ── WHAT THIS FILE DOES NOT KNOW ───────────────────────────────────────────────────────────────
// What she can carry, what she can afford, what a tun costs at twenty tuns. All three are
// `world.buy_capacity()`'s and arrive answered. The gauge's TRACK is the quay's stock (the owner,
// row 63: *"the gauge max will be the stock"*) and the server's ceiling is the tick it clamps at.
// No price is multiplied out here — buying walks a stepped book (§G.2) — so the only total on the
// button is one the caller was SERVED for the quantity chosen.
//
// ── THE QUANTITY IS THE CALLER'S ───────────────────────────────────────────────────────────────
// COMMAND writes it into the one order draft (so the dry run prices the exact line that will be
// issued); PORT keeps it in local state. The tray owns the DEFAULT — the first step, or all she
// can when that is less — and materialises it through `onChange`, so a caller never has to know
// the rule and the "first tap on + takes the shown figure" behaviour the old stepper had is kept
// without a second spelling.

export interface TradePick {
  good: MarketGood
  intent: 'buy' | 'sell'
}

export function TradeTray({
  pick,
  aboard,
  capacity,
  step,
  qty,
  act,
  onClose,
  culture,
  children,
}: {
  /** What was tapped: the good, and which of its two prices. */
  pick: TradePick
  /** Tuns of this good aboard — the SELL ceiling, and the one quantity this side may count. */
  aboard: number
  /** The caller's one reading of `world.buy_capacity()` for this good. Idle on a SELL. */
  capacity: BuyCapacityState
  /** `config.trade_step_tuns` — the server reprices every step, so the stepper walks in them. */
  step: number
  qty: { value: number | null; onChange: (next: number) => void }
  /** The act: what pressing the ONE button does, whether it may fire yet, what the chosen quantity
   *  costs when the caller has been served that figure, and what the server last answered. */
  act: { send: () => void; sending: boolean; ready: boolean; total: number | null; refusal: Refusal | null }
  onClose: () => void
  /** This port's culture, for the one sentence that names it: a good the quay will not deal in. */
  culture: string
  /** The caller's own rows under the stock — COMMAND's bargain. */
  children?: ReactNode
}) {
  const { good, intent } = pick
  const [detent, setDetent] = useState<TrayDetent>('half')

  const stepSize = Math.max(1, Math.round(step))
  const track = intent === 'buy' ? Math.floor(good.stock) : aboard
  const ceiling = intent === 'buy' ? (capacity.bound?.max ?? 0) : aboard
  const chosen = Math.min(qty.value ?? Math.min(ceiling, stepSize), ceiling)

  // The default, and the clamp when the ceiling moves under a chosen figure, written back to the
  // caller — so the quantity the caller previews is always the quantity on the button.
  const { value, onChange } = qty
  useEffect(() => {
    if (ceiling > 0 && value !== chosen) onChange(chosen)
  }, [ceiling, chosen, value, onChange])

  // Why this quay will not sell her any, when it will not. Two served flags, two reasons, and the
  // CULTURE one is the sentence §6 asks for — written here because this is the only tray a refused
  // good can open: her hold is why it is in the payload at all (0061), and the buy cell is dead.
  const refusedBy =
    good.available === false
      ? `A ${culture} quay does not deal in ${good.name.toLowerCase()}. She may land it here; she may never take more on.`
      : good.offered === false
        ? `This city does not trade ${good.name.toLowerCase()}. She may land it here; she may never take more on.`
        : null

  const verb = intent === 'buy' ? 'Buy' : 'Sell'

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
          onClick={act.send}
          disabled={act.sending || chosen <= 0 || !act.ready}
          busy={act.sending}
          busyLabel="Sending…"
          data-testid="trade-tray-send"
        >
          {`${verb} ${formatTuns(chosen)}`}
          {act.total !== null ? ` · ${formatDucats(act.total)}` : ''}
        </Button>
      }
    >
      {refusedBy !== null && (
        <Note tone="warning" data-testid="trade-tray-refused">
          {refusedBy}
        </Note>
      )}

      {intent === 'buy' ? (
        capacity.bound ? (
          <Row label="At most" value={<Figure value={formatInt(capacity.bound.max)} unit="t" size="figure" />}>
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
          onChange={onChange}
          max={track}
          cap={ceiling}
          step={stepSize}
          unit="t"
          label={`tuns of ${good.name}`}
          presets={ceiling > 0 ? [{ label: 'All she can', value: ceiling }] : undefined}
          data-testid="trade-tray-qty"
        />
      </div>

      <Row
        label="On the quay"
        value={<Figure value={formatTuns(good.stock)} unit={`of ${formatTuns(good.stock_target)}`} />}
        hairline={children !== undefined || act.refusal !== null}
      />

      {children}

      {/* The server's refusal, in the server's own sentence. The CODE goes to console.debug and
          never to the quay (§5's Note contract, and §2 item 13: a code is for a log). */}
      {act.refusal && (
        <Note tone="danger" code={act.refusal.code} data-testid="trade-tray-refusal">
          {act.refusal.sentence}
        </Note>
      )}
    </Tray>
  )
}

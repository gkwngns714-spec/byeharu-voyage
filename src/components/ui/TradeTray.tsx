import { useEffect, useState, type ReactNode } from 'react'
import { Button } from './Button'
import { Figure } from './Figure'
import { Note } from './Note'
import { PriceRows } from './PriceRows'
import { Row } from './Row'
import { Stepper } from './Stepper'
import { Tray } from './Tray'
import type { TrayDetent } from './trayDetents'
import { formatDucats, formatDucatsDelta, formatInt, formatTons, formatUnitPrice, formatUnits } from '../../lib/format'
import type { MarketGood, PricePoint, Refusal } from '../../lib/rpc'
import type { BuyCapacityState } from '../../lib/trade'

// THE TRADE TRAY — the ledger row, unfolded: where a price becomes a quantity, and the quantity
// becomes an order. docs/QUAY_LEDGER.md §3 screen B (owner row 76).
//
// docs/UI_DIRECTION.md §6, PORT: *"TRAY: identical to Command's buy tray (same component, same
// `issue`)"*. It is ONE component and it lives here rather than in a screen: the design system may
// not read the store ("machinery knows nothing above it"), so the server's answer to "how much can
// she take" arrives as a PROP and the act arrives as a function. The screen asks `useTrade`
// (src/live/useTrade.ts) once and hands the result down: that hook is the one spelling of the act.
//
// FOR ONE DAY THERE WERE TWO OF THESE (2026-09-09), and for one screen there were two callers with
// different rows inside (PORT carried the bargain, MARKET carried the trend — RESUME.md named the
// drift). Both are gone: MARKET folded into PORT on 2026-09-11 and the trend rows (`PriceRows`) are
// composed HERE, so every unfolded row reads the same wherever it was pressed.
//
// ── THE OWNER'S RULE, KEPT BY CONSTRUCTION ─────────────────────────────────────────────────────
// *"when pressed unfold another so that i can choose how much i buy … don't restruct anything."*
// A docked tray keeps the second half absolutely — nothing above the press moves, ever — and the
// row arithmetic that used to place a fold after a whole grid row is deleted rather than made
// cleverer (§5).
//
// ── THE BODY, TOP TO BOTTOM (QUAY_LEDGER §3 B) ─────────────────────────────────────────────────
//   refused · Trend · Range · On the quay · Paid · At most (or Aboard) · Fetches · the Stepper ·
//   the caller's rows (the bargain) · the server's refusal. The Profit row and the ONE button ride
//   in the pinned action region, so the figure a sale is a decision ABOUT cannot scroll apart from
//   the button that commits it (row 74's follow-up, measured on a short desktop window).
//
// ── WHAT THIS FILE DOES NOT KNOW ───────────────────────────────────────────────────────────────
// What she can carry, what she can afford, what a tun costs at twenty tuns. All three are
// `world.buy_capacity()`'s and arrive answered. The gauge's TRACK is the quay's stock (the owner,
// row 63: *"the gauge max will be the stock"*) and the server's ceiling is the tick it clamps at.
// No price is multiplied out here — buying walks a stepped book (§G.2) — so the only total on the
// button is one the caller was SERVED for the quantity chosen (`cmd.preview`, both sides).
//
// THE CHIPS ARE TUN FIGURES, and "All she can" is gone. Row 63: *"how much - all and max is same.
// remove all."* A chip that names the ceiling in tuns is the ceiling, said once; a chip that names
// it in words is the same number said twice.
//
// ── THE QUANTITY IS THE CALLER'S ───────────────────────────────────────────────────────────────
// The tray owns the DEFAULT — the first step, or all she can when that is less — and materialises
// it through `onChange`, so a caller never has to know the rule.
//
// ── WHAT IT COST HER, AND WHAT A SALE MAKES (0081) ─────────────────────────────────────────────
// `paid` is the average per tun the fleet's cargo cost (served on the fleet), and `preview` is the
// order's own dry run for the chosen quantity. This file subtracts nothing. A good whose cost is
// not on record prints "not on record", never zero; a good with nothing aboard prints "none
// aboard" — the row is always there, so the eye always finds the same line.

export interface TradePick {
  good: MarketGood
  intent: 'buy' | 'sell'
}

/** The act: what pressing the ONE button does, whether it may fire yet, what the chosen quantity
 *  costs when the server has priced it, what the server last answered — and what this good cost
 *  her per tun (`paid`) and what the chosen order would come to (`preview`), both the server's.
 *  `src/live/useTrade.ts` is the one spelling of this shape; it imports the type from here. */
export interface TradeAct {
  send: () => void
  sending: boolean
  ready: boolean
  /** What the chosen quantity comes to, when the server has priced exactly that quantity. */
  total: number | null
  refusal: Refusal | null
  /** The average ducats per tun she paid for what is aboard of this good — `FleetView.cargo_basis`
   *  through the one reading. Null when none is aboard or its cost is not on record. */
  paid: number | null
  /** The order the button would issue, run for real and rolled back: tuns and total on either
   *  side; cost and profit on a sale. Null while the answer for THIS quantity is on its way, or
   *  when the quay refused the dry run (the press then states the refusal in full). */
  preview: { qty: number | null; total: number | null; cost: number | null; profit: number | null } | null
  /** True while a dry run for the chosen quantity has been asked and not yet answered. */
  previewLoading: boolean
}

/** What the caller knows about THIS market and THIS ship — four served facts, folded once. */
export interface TradeQuay {
  /** UNITS of this good on board — the SELL ceiling, and the one quantity this side may count. */
  aboard: number
  /** Tons of cargo space ONE unit takes (`SnapshotGood.bulk`) — so the tray can say what the
   *  chosen quantity does to the ship's `51 / 60 tons`, which is the number the player has. */
  bulk: number
  /** This port's culture, for the one sentence that names it: a good the quay will not deal in. */
  culture: string
  /** `world.price_history` for this good at this port, oldest first; undefined until it lands. */
  history: readonly PricePoint[] | undefined
}

/** What `useTrade` returns, passed down whole. */
export interface TradeControls {
  /** The caller's one reading of `world.buy_capacity()` for this good. Idle on a SELL. */
  capacity: BuyCapacityState
  /** `config.trade_step_tuns` — the server reprices every step, so the stepper walks in them. */
  step: number
  act: TradeAct
}

/** THE MIDDLE CHIP, in steps. The server reprices every `trade_step_tuns` (10 t on the shipped
 *  config, migration 0001:155), and the first two hulls hold 60 and 90 t (0003:2089-2090), so five
 *  steps — 50 t — is the round lot that fills or empties most of a starting hold, halfway between
 *  "one step" and "all she can". A chip is a shortcut to a figure the stepper reaches anyway; it
 *  decides nothing. */
const LOT_STEPS = 5

export function TradeTray({
  pick,
  quay,
  trade,
  qty,
  onClose,
  children,
}: {
  /** What was tapped: the good, and which of its two prices. */
  pick: TradePick
  quay: TradeQuay
  trade: TradeControls
  qty: { value: number | null; onChange: (next: number) => void }
  onClose: () => void
  /** The caller's own rows under the stepper — the bargain. */
  children?: ReactNode
}) {
  const { good, intent } = pick
  const { aboard, bulk, culture, history } = quay
  const { capacity, step, act } = trade
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
      ? `${culture} ports do not trade ${good.name.toLowerCase()}. You can sell it here, but not buy it.`
      : good.offered === false
        ? `This port does not sell ${good.name.toLowerCase()}. You can sell it here, but not buy it.`
        : null

  // QUANTITY CHIPS: one step, a lot, the ceiling — whichever of those are distinct and within
  // reach. A bare count: the stepper's own unit word says what it counts.
  const presets = [...new Set([stepSize, LOT_STEPS * stepSize, ceiling])]
    .filter((v) => v > 0 && v <= ceiling)
    .sort((a, b) => a - b)
    .map((v) => ({ label: formatInt(v), value: v }))

  const verb = intent === 'buy' ? 'Buy' : 'Sell'

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={`${good.name} · ${intent}`}
      data-testid="trade-tray"
      action={
        <>
          {intent === 'sell' && chosen > 0 && act.preview !== null && act.preview.profit !== null && (
            <Row
              label={act.preview.profit < 0 ? 'Loss' : 'Profit'}
              value={
                <Figure
                  value={formatDucatsDelta(act.preview.profit)}
                  size="figure"
                  tone={act.preview.profit < 0 ? 'danger' : act.preview.profit > 0 ? 'success' : 'ink'}
                />
              }
              hairline={false}
              data-testid="trade-tray-profit"
            />
          )}
          <Button
            variant="primary"
            className="w-full"
            onClick={act.send}
            disabled={act.sending || chosen <= 0 || !act.ready}
            busy={act.sending}
            busyLabel="Sending…"
            data-testid="trade-tray-send"
          >
            {`${verb} ${formatUnits(chosen)}`}
            {act.total !== null ? ` · ${formatDucats(act.total)}` : ''}
          </Button>
        </>
      }
    >
      {refusedBy !== null && (
        <Note tone="warning" data-testid="trade-tray-refused">
          {refusedBy}
        </Note>
      )}

      <PriceRows good={good} points={history} />

      {/* What this good cost her, per tun, for what is aboard — served, never remembered here.
          Always a row, so the eye finds the same line: the figure, or why there is none. */}
      {aboard === 0 ? (
        <Row label="Bought at" tone="muted" value="none on board" data-testid="trade-tray-paid-none" />
      ) : act.paid !== null ? (
        <Row label="Bought at" value={<Figure value={formatUnitPrice(act.paid)} />} data-testid="trade-tray-paid">
          <span className="block text-t-caption text-ink-faint">{`for the ${formatUnits(aboard)} on board`}</span>
        </Row>
      ) : (
        <Row label="Purchase price unknown" tone="muted" data-testid="trade-tray-paid-unknown" />
      )}

      {intent === 'buy' ? (
        capacity.bound ? (
          <Row label="Max" value={<Figure value={formatUnits(capacity.bound.max)} size="figure" />}>
            <span className="block text-t-caption text-ink-faint">{`limited by ${capacity.bound.binding}`}</span>
          </Row>
        ) : (
          <Row
            label={capacity.loading ? 'Checking how much you can buy…' : 'Max amount unknown'}
            tone="muted"
          />
        )
      ) : (
        <Row label="On board" value={<Figure value={formatUnits(aboard)} size="figure" />} />
      )}

      {/* THE SALE, AS THE SERVER WOULD REALISE IT for the quantity chosen (0081). On a buy the
          button already carries the served total, so nothing is said twice. */}
      {intent === 'sell' &&
        chosen > 0 &&
        (act.preview !== null ? (
          <>
            {act.preview.total !== null && (
              <Row label="You get" value={<Figure value={formatDucats(act.preview.total)} />} data-testid="trade-tray-fetches" />
            )}
          </>
        ) : (
          act.previewLoading && <Row label="Checking the price…" tone="muted" />
        ))}

      <div className="py-3">
        <Stepper
          value={chosen}
          onChange={onChange}
          max={track}
          cap={ceiling}
          step={stepSize}
          unit="units"
          label={`units of ${good.name}`}
          presets={presets.length > 0 ? presets : undefined}
          data-testid="trade-tray-qty"
        />
      </div>
      {/* WHAT IT DOES TO THE SHIP — the chosen count in the unit the ship is measured in. This is
          the line that lets "Buy 20 units" be read against "Cargo 51 / 60 tons" on COMMAND. */}
      {chosen > 0 && (
        <Row
          label="Cargo space"
          tone="muted"
          value={<Figure value={formatTons(chosen * bulk, 1)} />}
          hairline={false}
          data-testid="trade-tray-space"
        />
      )}

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

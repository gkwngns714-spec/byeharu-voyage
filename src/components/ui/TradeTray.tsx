import { useEffect, useState, type ReactNode } from 'react'
import { Button } from './Button'
import { deltaTone } from './deltaTone'
import { Figure } from './Figure'
import { Note } from './Note'
import { PriceRows, type PriceTrend } from './PriceRows'
import { Row } from './Row'
import { Stepper } from './Stepper'
import { Tray } from './Tray'
import type { TrayDetent } from './trayDetents'
import { formatDucats, formatDucatsDelta, formatInt, formatPctDelta, formatTons, formatUnitPrice, formatUnits } from '../../lib/format'
import type { MarketGood, Refusal } from '../../lib/rpc'
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
// ── THE BODY, TOP TO BOTTOM (QUAY_LEDGER §3 B), SINCE 2026-09-14 ───────────────────────────────
//   SELL: the Stepper · Bought at (per unit; the served cost of the chosen units under it) ·
//         Sells at (served per unit, this quantity) · You get (served total; the gain as a share of
//         the cost under it) · the caller's rows (the haggle thread) · the server's refusal.
//   BUY:  refused · Max · the Stepper · Cargo space · Bought at · Trend · Range · In stock · the
//         caller's rows · the server's refusal.
//   The Profit row (ducats AND the share) and the ONE button ride in the pinned action region, so
//   the figure a sale is a decision ABOUT cannot scroll apart from the button that commits it (row
//   74's follow-up, measured on a short desktop window).
//   The owner, 2026-09-14, on the sell face as it was (refused · Trend · Range · In stock · Bought
//   at · On board · You get · Stepper · Cargo space): *"show necessary info only. For example i
//   will be able to choose first how many i sell, then it will show only how much bought price,
//   selling price with underneath showing the percentage. right now units? in stock? range? WTF
//   man."* So the sell face is the count and three prices, in that order, and nothing else. On BUY
//   the market's context (PriceRows) moved BELOW the count rather than out: a buy is read against
//   the trend, but it is decided on the ceiling and the count, so those come first.
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
  /** Put this line on the BASKET instead of trading it now (docs/QUAY_LEDGER.md §3 B, slice 2):
   *  the caller stages `{side, good, qty}` for the quantity chosen and the pick closes; nothing is
   *  bought until the basket's own button. Absent where there is no basket to stage into (the
   *  read-only face never mounts this tray). Beside `send` so the one condition that gates a
   *  trade gates a stage too (PR #59 review SHOULD 6). */
  stage?: () => void
  sending: boolean
  ready: boolean
  /** What the chosen quantity comes to, when the server has priced exactly that quantity. */
  total: number | null
  refusal: Refusal | null
  /** The average ducats per tun she paid for what is aboard of this good — `FleetView.cargo_basis`
   *  through the one reading. Null when none is aboard or its cost is not on record. */
  paid: number | null
  /** The order the button would issue, run for real and rolled back: units and total on either
   *  side; cost and profit on a sale; and since 0083 the served per-unit figure (`avg_price`) and
   *  what an open bargain took off this very lot (`haggle_saved`) — the two figures the haggle
   *  thread stakes. THE LAST SERVED for this good (2026-09-14): a new quantity or a world read
   *  re-asks and these stand, `previewLoading`, until the new ones land — the tray dims them and
   *  never blanks them. Null before the first answer, or when the market refused the dry run (the
   *  press then states the refusal in full). */
  preview: {
    qty: number | null
    total: number | null
    cost: number | null
    profit: number | null
    avg_price: number | null
    haggle_saved: number | null
  } | null
  /** True while `preview` is not yet the figures for the quantity on the button — the finger has
   *  not rested, or the dry run for the settled quantity is on the wire. NOT true on a re-ask of
   *  the same quantity on the world's beat. */
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
  /** `world.price_history` for this good at this port — the points and their cadence, as the one
   *  history hook reads them; the points are undefined until the read lands. */
  history: PriceTrend
}

/** What `useTrade` returns, passed down whole. */
export interface TradeControls {
  /** The caller's one reading of `world.buy_capacity()` for this good. Idle on a SELL. */
  capacity: BuyCapacityState
  /** `config.trade_step_tuns` — the server reprices every step of the book. Since 2026-09-14 the
   *  stepper walks by ONE and this is the LOT: a chip, and PageUp/PageDown on the slider. */
  step: number
  act: TradeAct
}

/** THE LOT CHIP. The server reprices every `trade_step_tuns` (10 on the shipped config, migration
 *  0001:155) — that is how the BOOK walks, not a rule about what a player may choose: `cmd.do_sell`
 *  and `cmd.do_buy` take any count above nought (0007:211, 0007:447; 0083:400 asks only for a whole
 *  number). So the stepper moves by ONE, and the served step survives as a chip: one lot, beside
 *  the ceiling. The owner, 2026-09-14: *"it only moves in like 10? wtf. i should be able to sell
 *  only 1."* A chip is a shortcut to a figure the stepper reaches anyway; it decides nothing. */
const UNIT_STEP = 1

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

  const lot = Math.max(1, Math.round(step))
  const track = intent === 'buy' ? Math.floor(good.stock) : aboard
  const ceiling = intent === 'buy' ? (capacity.bound?.max ?? 0) : aboard
  const chosen = Math.min(qty.value ?? Math.min(ceiling, lot), ceiling)

  // The default, and the clamp when the ceiling moves under a chosen figure, written back to the
  // caller — so the quantity the caller previews is always the quantity on the button.
  const { value, onChange } = qty
  useEffect(() => {
    if (ceiling > 0 && value !== chosen) onChange(chosen)
  }, [ceiling, chosen, value, onChange])

  // Why this quay will not sell her any, when it will not. Two served flags, two reasons, and the
  // CULTURE one is the sentence §6 asks for — written here because this is the only tray a refused
  // good can open: her hold is why it is in the payload at all (0061), and the buy cell is dead.
  // A BUY matter: the sell face says nothing of it.
  const refusedBy =
    intent === 'buy' && good.available === false
      ? `${culture} ports do not trade ${good.name.toLowerCase()}. You can sell it here, but not buy it.`
      : intent === 'buy' && good.offered === false
        ? `This port does not sell ${good.name.toLowerCase()}. You can sell it here, but not buy it.`
        : null

  // QUANTITY CHIPS: one lot and the ceiling — whichever of those are distinct and within reach. A
  // bare count: the stepper's own unit word says what it counts.
  const presets = [...new Set([lot, ceiling])]
    .filter((v) => v > 0 && v <= ceiling)
    .sort((a, b) => a - b)
    .map((v) => ({ label: formatInt(v), value: v }))

  const verb = intent === 'buy' ? 'Buy' : 'Sell'
  // THE ONE CONDITION for both acts: a line that cannot be traded cannot be staged either.
  const live = !act.sending && chosen > 0 && act.ready

  // THE SALE'S FIGURES, all served (0081): what the chosen units cost her, what they fetch, and the
  // gain as a share of that cost — `profit ÷ cost`, two served figures, both printed on this face
  // (WORDS.md law 2: no share without its whole). A served `margin_pct` would be the cleaner
  // authority; that is a migration for a later slice, and until then this is the ONE place the
  // ratio is taken. Dimmed while `previewLoading`: the figures are the last served for this good,
  // not yet for the quantity on the button — never blanked, never a "checking" line (the owner,
  // 2026-09-14: *"a refresh sign of checking the price... keeps showing up"*).
  const sale = intent === 'sell' && chosen > 0 ? act.preview : null
  const gainShare = sale !== null && sale.profit !== null && sale.cost !== null && sale.cost > 0 ? sale.profit / sale.cost : null
  const dim = act.previewLoading ? 'faint' : undefined

  const stepper = (
    <div className="py-3">
      <Stepper
        value={chosen}
        onChange={onChange}
        max={track}
        cap={ceiling}
        min={ceiling > 0 ? 1 : 0}
        step={UNIT_STEP}
        lot={lot}
        unit="units"
        label={`units of ${good.name}`}
        presets={presets.length > 0 ? presets : undefined}
        data-testid="trade-tray-qty"
      />
    </div>
  )

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={`${good.name} · ${intent}`}
      data-testid="trade-tray"
      action={
        <>
          {sale !== null && sale.profit !== null && (
            <Row
              label={sale.profit < 0 ? 'Loss' : 'Profit'}
              value={
                <Figure
                  value={`${formatDucatsDelta(sale.profit)}${gainShare !== null ? ` · ${formatPctDelta(gainShare)}` : ''}`}
                  size="figure"
                  tone={dim ?? deltaTone(sale.profit)}
                />
              }
              hairline={false}
              data-testid="trade-tray-profit"
            />
          )}
          {/* TWO ACTS, ONE ROW: trade this line now, or stage it on the basket. The primary keeps
              the whole width where there is no basket to stage into. */}
          <div className={act.stage ? 'grid grid-cols-2 gap-2' : ''}>
            {act.stage && (
              <Button variant="secondary" className="w-full" onClick={act.stage} disabled={!live} data-testid="trade-tray-stage">
                Add to basket
              </Button>
            )}
            <Button
              variant="primary"
              className="w-full"
              onClick={act.send}
              disabled={!live}
              busy={act.sending}
              busyLabel="Sending…"
              data-testid="trade-tray-send"
            >
              {`${verb} ${formatUnits(chosen)}`}
              {act.total !== null ? ` · ${formatDucats(act.total)}` : ''}
            </Button>
          </div>
        </>
      }
    >
      {intent === 'sell' ? (
        <>
          {/* THE SELL FACE, in the owner's order (2026-09-14): *"i will be able to choose first how
              many i sell, then it will show only how much bought price, selling price with
              underneath showing the percentage."* The count first; then what those units cost her
              (per unit, and the served cost of the chosen units — the whole the share below is
              of); what they sell at (the served per-unit figure for THIS quantity, which is the
              only price a screen may show once a bargain is open); what she gets, with the gain as
              a share of the cost under it. No trend, no range, no stock, no cargo-space row: what
              is on board is the stepper's end and its `All` chip. */}
          {stepper}
          {act.paid !== null ? (
            <Row label="Bought at" value={<Figure value={formatUnitPrice(act.paid)} />} data-testid="trade-tray-paid">
              {sale !== null && sale.cost !== null && sale.qty !== null && (
                <span className="block text-t-caption text-ink-faint">{`${formatDucats(sale.cost)} for ${formatUnits(sale.qty)}`}</span>
              )}
            </Row>
          ) : (
            <Row label="Purchase price unknown" tone="muted" data-testid="trade-tray-paid-unknown" />
          )}
          {sale !== null && sale.avg_price !== null && (
            <Row label="Sells at" value={<Figure value={formatUnitPrice(sale.avg_price)} tone={dim} />} data-testid="trade-tray-sells-at" />
          )}
          {sale !== null && sale.total !== null && (
            <Row label="You get" value={<Figure value={formatDucats(sale.total)} tone={dim} />} data-testid="trade-tray-fetches">
              {gainShare !== null && (
                <span className="block text-t-caption text-ink-faint" data-testid="trade-tray-gain-share">
                  {`${formatPctDelta(gainShare)} on what it cost`}
                </span>
              )}
            </Row>
          )}
        </>
      ) : (
        <>
          {refusedBy !== null && (
            <Note tone="warning" data-testid="trade-tray-refused">
              {refusedBy}
            </Note>
          )}

          {/* THE CEILING STAYS DRAWN while it is re-asked on the world's beat (`capacity.loading`
              with a bound present): useBuyCapacity keeps the last answer for the same good, so
              this row only gives way to the waiting line before the FIRST answer. Until
              2026-09-14 it unmounted every 3 s — the owner: "when i press buy, the max keeps
              refreshing". tests/trade.ceiling.spec.ts watches it across three world reads. */}
          {capacity.bound ? (
            <Row label="Max" value={<Figure value={formatUnits(capacity.bound.max)} size="figure" />} data-testid="trade-tray-max">
              <span className="block text-t-caption text-ink-faint">{`limited by ${capacity.bound.binding}`}</span>
            </Row>
          ) : (
            <Row
              label={capacity.loading ? 'Checking how much you can buy…' : 'Max amount unknown'}
              tone="muted"
              data-testid="trade-tray-max-unknown"
            />
          )}

          {stepper}

          {/* WHAT IT DOES TO THE SHIP — the chosen count in the unit the ship is measured in. This
              is the line that lets "Buy 20 units" be read against "Cargo 51 / 60 tons" on COMMAND. */}
          {chosen > 0 && (
            <Row
              label="Cargo space"
              tone="muted"
              value={<Figure value={formatTons(chosen * bulk, 1)} />}
              data-testid="trade-tray-space"
            />
          )}

          {/* What this good cost her, per unit, for what is on board — served, never remembered
              here. Always a row, so the eye finds the same line: the figure, or why there is none. */}
          {aboard === 0 ? (
            <Row label="Bought at" tone="muted" value="none on board" data-testid="trade-tray-paid-none" />
          ) : act.paid !== null ? (
            <Row label="Bought at" value={<Figure value={formatUnitPrice(act.paid)} />} data-testid="trade-tray-paid">
              <span className="block text-t-caption text-ink-faint">{`for the ${formatUnits(aboard)} on board`}</span>
            </Row>
          ) : (
            <Row label="Purchase price unknown" tone="muted" data-testid="trade-tray-paid-unknown" />
          )}

          {/* THE MARKET'S CONTEXT — trend, range, stock — BELOW the decision, since 2026-09-14:
              the ceiling and the count are what a buy is decided on; these are what it is read
              against. They used to open the tray. */}
          <PriceRows good={good} trend={history} />
        </>
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

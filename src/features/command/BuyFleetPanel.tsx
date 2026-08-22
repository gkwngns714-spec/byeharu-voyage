import { Explain, fineClass, Gauge, SectionLabel, StatRow } from '../../components/ui'
import {
  formatDucats,
  formatInt,
  formatOfTotal,
  formatPct,
  formatPctPoints,
  formatTuns,
} from '../../lib/format'
import type { FleetView, MarketView, SnapshotConfig } from '../../lib/rpc'
import { fleetHoldTotal } from '../../domain/fleet'
import type { BuyCapacityState } from './useBuyCapacity'
import type { HaggleStateRead } from './useHaggleState'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BUYER'S RAIL — her state, beside the goods she is choosing from
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-08-22: *"When buy, i want all the trade goods on left side, and my fleet info on
// the right side, showing how much room, how much negotiation can be done, and so on."*
//
// So this panel answers three questions and nothing else, because "and so on" is how a panel turns
// back into the wall of prose the same instruction was complaining about:
//
//   1. HOW MUCH ROOM — `fleet.free_hold`, the SERVED figure (public.fleet_free_hold, 0017:183),
//      against the fleet's stowed total. Not recomputed here: three client spellings of that
//      subtraction were deleted and one of them had been wrong since it was written
//      (src/domain/fleet/derive.ts's header).
//   2. WHAT THIS ORDER WOULD DO — `world.buy_capacity()`, which walks the same stepped quote a
//      committed trade walks and names the limit that stops her. Asked once by the composer and
//      handed down; see ./useBuyCapacity.ts.
//   3. WHAT MOVES THE PRICE — see below, because this is the part that is easy to lie about.
//
// ── "HOW MUCH NEGOTIATION CAN BE DONE" — THE ANSWER, AND HOW IT CHANGED UNDER THIS FILE ────────
// The reference game (대항해시대 오리진) has a 협상 minigame: a before/after price, a delta, a
// success-probability bar. Inventing a figure of that shape to fill the owner's phrase would be the
// fabricated number docs/UI_DIRECTION.md §4 rule 5 forbids — so every row below is a served number.
//
// FOR AN HOUR THE ANSWER WAS "NONE", AND THIS FILE ALMOST SAID SO. An earlier draft of the ⓘ read
// "there is no haggling in this game", which was true of every migration up to 0017 — whose
// self-assert re-checks that `world.skills()` still reports HAGGLING/SPREAD unread (0017:1088).
// Migration **0022, `a_bargain_is_struck_on_the_quay`, landed while this panel was being written**
// and made it false. The sentence was pulled before it shipped; the ⓘ now explains the thing that
// stays true whatever the chain does — WHICH HALF OF A PRICE CAN MOVE AT ALL.
//
// WHAT 0022 ACTUALLY GIVES, AND WHY THE ROWS ARE ORDERED AS THEY ARE:
//   · THE PORT'S SPREAD, PUBLISHED (`world.spread`, from dev_commerce — 0005:292). Half is added to
//     the ask and half taken off the bid (0005:381-382). It is the same number for everybody, and
//     0017 REFUSED to make it player-aware so that the market screen cannot print a figure that
//     depends on who is looking (0017:66-72). 0022 kept that refusal.
//   · THE SPREAD THIS HOUSE EXECUTES AT (`world.spread_effective`, 0022:286) — the function
//     `world.quote` itself calls, with the purser and any struck bargain already folded in. This is
//     the RESULT; the two rows under it are the CAUSES, which is why they are drawn in that order.
//   · YOUR PURSER (`fleet.officer_pct.PURSER`) — 0017:379, a better FILL inside the port's cut, on
//     this fleet's quotes only. A hire, not a conversation.
//   · YOUR BARGAIN — the concession held, the cap, and the tries left today, all from
//     `world.haggle_state`. 0022 composes it with the purser MULTIPLICATIVELY
//     (`published × (1 − purser) × (1 − concession)`) so the two can never double-count, and floors
//     the stack at 55% of published because a quay must keep more than half its living.
//   · THE MAYOR'S TAX (`port.tax_rate`), which rides the ask beside the spread. No bargain touches it.
//   · THE SIZE OF THE ORDER. `world.quote` fills in `trade_step_tuns` steps and reprices every one
//     (0005:412-420, §G.2), so the price on the row is the price of the FIRST step only.
//
// THE ACT OF BARGAINING IS NOT IN THIS FILE. `cmd.haggle` is an ACTION, and this rail is
// `md:sticky` — see ./HaggleBlock.tsx, which owns the button, and screenLayout.ts for why it can
// never live here.
//
// ── WHAT THIS PANEL DELIBERATELY DOES NOT PRINT ────────────────────────────────────────────────
//   · THE PURSE. It is in the top bar, on every screen at once (TopBar.tsx), and CommandScreen's
//     own comment records why it was taken off this tab: "one fact shown in two places is two
//     authorities for it". `bound_by` already says when the purse is the thing stopping her.
//   · ANY BUTTON. The rail is `md:sticky`, and a sticky panel taller than the viewport hides its
//     own foot — see src/components/ui/screenLayout.ts. Figures only.

export function BuyFleetPanel({
  fleet,
  market,
  config,
  goodCode,
  capacity,
  bargain,
}: {
  fleet: FleetView | undefined
  /** The market this order will trade in — where she lies, or where she is bound (F.2). */
  market: MarketView | undefined
  config: SnapshotConfig
  /** The good chosen so far, or null while the list is still open. */
  goodCode: string | null
  /** The composer's ONE reading of `world.buy_capacity()`, shared with the quantity stepper. */
  capacity: BuyCapacityState
  /** The composer's ONE reading of `world.haggle_state()`, shared with the haggle button. */
  bargain: HaggleStateRead
}) {
  if (!fleet) return null

  const stowed = fleetHoldTotal(fleet)
  const good = goodCode ? market?.goods.find((g) => g.code === goodCode) : undefined
  const purser = fleet.officer_pct.PURSER
  const quarter = fleet.officer_pct.QUARTERMASTER
  const quay = bargain.state?.docked === true ? bargain.state : null

  return (
    <div className="bv-cut space-y-4 border border-edge bg-surface-2 p-3">
      {/* ── HOW MUCH ROOM ─────────────────────────────────────────────────────────────────── */}
      <section>
        <SectionLabel className="mb-1.5">Room in the hold</SectionLabel>
        {/* Rule 2 — the number is the hero. The figure is the largest thing in the block and the
            words under it are the small ones, never the other way round. */}
        <p className="font-mono text-2xl leading-none text-ink tabular-nums">
          {formatInt(fleet.free_hold)}
          <span className="ml-1 text-sm font-normal text-ink-faint">t free</span>
        </p>
        <div className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1">
          <Gauge
            value={stowed - fleet.free_hold}
            max={stowed}
            segments={10}
            tone={fleet.free_hold <= 0 ? 'danger' : 'accent'}
            label={`hold, ${formatInt(stowed - fleet.free_hold)} of ${formatInt(stowed)} tuns full`}
          />
          <span className={fineClass()}>{formatOfTotal(stowed - fleet.free_hold, stowed)} t laden</span>
        </div>
        <p className={fineClass('mt-1.5')}>
          {quarter > 0
            ? `Your quartermaster is worth ${formatPctPoints(quarter, 1)} of it, and it is already counted.`
            : 'Water and food take the same tuns as cargo.'}
        </p>
      </section>

      {/* ── WHAT THIS ORDER WOULD DO ──────────────────────────────────────────────────────── */}
      <section className="border-t border-edge pt-3">
        <SectionLabel className="mb-1.5">This order</SectionLabel>
        {!goodCode ? (
          <p className={fineClass()}>Choose a good and the quay will price it.</p>
        ) : capacity.bound ? (
          <>
            <p className="font-mono text-2xl leading-none text-ink tabular-nums">
              {formatInt(capacity.bound.max)}
              <span className="ml-1 text-sm font-normal text-ink-faint">t at most</span>
            </p>
            <dl className="mt-2 space-y-1">
              <StatRow label="stopped by" value={capacity.bound.binding} plain />
              {capacity.estTotal !== null && (
                <StatRow label="all of it costs" value={formatDucats(capacity.estTotal)} />
              )}
              {good && <StatRow label="first ten at" value={`${formatInt(good.buy)} d./t`} />}
            </dl>
          </>
        ) : (
          <p className={fineClass()}>
            {capacity.loading
              ? 'Asking what she can carry and afford…'
              : 'The most she can take on is not known yet.'}
          </p>
        )}
      </section>

      {/* ── WHAT MOVES THE PRICE (the honest answer to "how much negotiation") ────────────── */}
      <section className="border-t border-edge pt-3">
        <div className="mb-1.5 flex flex-wrap items-center gap-x-1">
          <SectionLabel className="mb-0">What moves the price</SectionLabel>
          <Explain
            label="What moves the price"
            panelClassName="w-full normal-case tracking-normal"
          >
            A price has two halves. What a good is WORTH is the world's half, and it is the same for
            every house standing on this quay — nothing you do moves it for yourself alone. The
            port's CUT is the other half, and everything below shaves it. So the levers you really
            have are where you trade, how much at once, and who keeps your books.
          </Explain>
        </div>
        {market?.port ? (
          <dl className="space-y-1">
            {/* THE PUBLISHED SPREAD, AND THE ONE THIS HOUSE ACTUALLY EXECUTES AT.
                `spread_effective` is `world.spread_effective(port, good, fleet)` — the very function
                `world.quote` calls (0022:286) — so it already folds the purser AND any bargain held.
                That makes it the row that matters, and it supersedes reading the purser's percentage
                as if it were the outcome: the two rows below it are the CAUSES, this pair is the
                RESULT. Before 0022 there was only one spread and no difference to draw. */}
            <StatRow
              label="the port's spread"
              value={formatPct(quay ? quay.spread_published : market.port.spread, 1)}
              hint="Half of it is added to what you pay and half taken off what you are paid. A busier harbour publishes a narrower one, and it is the same figure for every house in port — a bargain never moves it, only what YOU are filled at inside it."
            />
            {quay && (
              <StatRow
                label="you execute at"
                value={formatPct(quay.spread_effective, 1)}
                hint="What this fleet's own quotes are priced with, purser and bargain already counted. This is the number a BUY charges against, not the published one."
              />
            )}
            <StatRow
              label="your purser"
              value={purser > 0 ? `−${formatPctPoints(purser, 1)} of it` : 'none posted'}
              plain={purser <= 0}
              hint="A purser does not narrow the harbour's spread — he wins a better fill inside it, on this fleet's quotes only. Post one from the Port tab."
            />
            {/* THE BARGAIN — the literal answer to "how much negotiation can be done", finally.
                Every figure the server's: what is held, what the cap is, how many tries remain. */}
            {quay && (
              <StatRow
                label="your bargain"
                value={
                  quay.concession > 0
                    ? `−${formatPctPoints(quay.concession_pct, 1)} of it`
                    : `${quay.attempts_left} tr${quay.attempts_left === 1 ? 'y' : 'ies'} left`
                }
                plain={quay.concession <= 0}
                hint={
                  `A struck bargain shaves the port's cut for you alone, up to ` +
                  `${formatPctPoints(quay.concession_max_pct, 1)}, and is spent on ${quay.spent_on}. ` +
                  `Each win is worth ${formatPctPoints(quay.step_pct, 1)} more, and each refusal ` +
                  `today makes the factor harder.`
                }
              />
            )}
            {/* SHOWN ONLY WHEN TRUE, because it is a real limit and not a standing caption: the
                quay must keep more than half its living whatever stacks against it. */}
            {quay?.at_floor && (
              <StatRow
                label="and no lower"
                value="he is at his floor"
                plain
                hint="Purser and bargain together have taken this as far as the quay allows. A port whose margin could be negotiated away entirely is not a port."
              />
            )}
            <StatRow
              label="the mayor's tax"
              value={formatPct(market.port.tax_rate, 1)}
              hint="Charged on the quay, on top of the spread. No bargain touches it."
            />
            <StatRow
              label="a big order"
              value={`each ${formatTuns(config.trade_step_tuns)} dearer`}
              plain
              hint="An order is filled in steps and every step reprices, so the price you are shown is the price of the first step. Splitting a purchase across two ports beats forcing one market."
            />
          </dl>
        ) : (
          <p className={fineClass()}>Reading this port's terms…</p>
        )}
      </section>
    </div>
  )
}

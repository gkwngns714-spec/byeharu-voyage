import { Explain, fineClass, Gauge, HeroFigure, Meter, SectionLabel, StatRow } from '../../components/ui'
import {
  formatDucats,
  formatInt,
  formatOfTotal,
  formatPct,
  formatPctPoints,
  formatTuns,
  formatVoyageDays,
} from '../../lib/format'
import type { FleetView, MarketView, SnapshotConfig, SnapshotPort } from '../../lib/rpc'
import { fleetCrew, fleetHoldTotal, fleetStores, hullFraction, worstHullFraction } from '../../domain/fleet'
import type { BuyCapacityState } from './useBuyCapacity'
import type { HaggleStateRead } from './useHaggleState'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FLEET RAIL — her state, beside the thing she is being ordered to do
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-08-22: *"When buy, i want all the trade goods on left side, and my fleet info on
// the right side, showing how much room, how much negotiation can be done, and so on."*
// The owner, 2026-08-23: *"hire, repair, provision — I want fleet info like what is in buy."*
//
// ── ONE RAIL, NOT FOUR PANELS ──────────────────────────────────────────────────────────────────
// This file was `BuyFleetPanel.tsx` and it answered BUY's three questions. HIRE, REPAIR and
// PROVISION each turned out to be a decision about the fleet's own state with NOTHING on screen
// about the fleet — and the obvious way to fix that is a `HireFleetPanel`, a `RepairFleetPanel`
// and a `ProvisionFleetPanel`. That is four authorities for "what does the rail look like", and
// docs/NO_SPAGHETTI.md §1 names the alternative: *owned but too narrow → generalise that one owner
// and repoint every caller. Never fork.* So the panel was widened rather than copied: one rail,
// one skin, one set of block rules, and a `verb` deciding which blocks it prints.
//
// The shared block is real and not a pretext — ROOM IN THE HOLD is drawn identically for BUY and
// for PROVISION, because *"water and food take the same tuns as cargo"* (DESIGN C.3) makes filling
// the stores a cargo decision. Everything else is per-verb.
//
//   BUY        room in the hold · what this order would do · what moves the price
//   HIRE       her crew against her berths · the idle men in this port
//   REPAIR     her worst hull, then every hull · whether there is a yard here, and its tier
//   PROVISION  room in the hold · her stores and how many days they are worth
//
// ── WHAT THE RAIL MAY NOT DO, ON ANY VERB ──────────────────────────────────────────────────────
// **INVENT A PRICE.** `src/lib/rpc/types.ts:18-19` states the contract plainly: *"a port carries
// `crew_pool` but no crew RATE, no water/food price and no repair rate … PROVISION/HIRE/REPAIR are
// priced by the server when the order runs."* There is therefore no honest way to print what a
// repair or a barrel of water costs before the order is checked, and a plausible figure would be
// the fabricated number docs/UI_DIRECTION.md §4 rule 5 forbids. The rail says so in the player's
// words instead, and points at the check that DOES name the figure (`cmd.preview()`, PreviewPanel).
//
// So BUY's three questions, which the rest of this header is about:
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

/**
 * ONE SPELLING OF THE RULE BETWEEN BLOCKS. The rail is a stack of `<section>`s with a hairline
 * between them and none above the first — written out once here rather than on each block, so a
 * block can be added, removed or made conditional without anybody having to remember which one is
 * currently on top. `first:` is a child-position variant, and a block React does not render is not
 * a child, so a hidden block never leaves a stray rule behind.
 */
const BLOCK = 'border-t border-edge pt-3 first:border-0 first:pt-0'

/** The list of verbs that reach this component is `./railVerbs.ts` — one place, two callers. */
export function FleetRail({
  verb,
  fleet,
  port,
  market,
  config,
  goodCode,
  capacity,
  bargain,
}: {
  /** The verb being composed. It decides which blocks print — see FLEET_RAIL_VERBS. */
  verb: string
  fleet: FleetView | undefined
  /** Where the order will happen — where she lies, or where she is bound (F.2). The SNAPSHOT port,
   *  which is the one that carries the yard and the idle men; `market.port` carries the prices. */
  port: SnapshotPort | null
  /** The market this order will trade in. Undefined until it has been read. */
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

  const good = goodCode ? market?.goods.find((g) => g.code === goodCode) : undefined
  const purser = fleet.officer_pct.PURSER
  const quay = bargain.state?.docked === true ? bargain.state : null

  return (
    <div className="bv-cut space-y-4 border border-edge bg-surface-2 p-3">
      {/* ROOM IN THE HOLD SERVES TWO VERBS, and that is why it is a component rather than a block
          written twice: stores take the same tuns as cargo (DESIGN C.3), so PROVISION is a hold
          decision as much as BUY is. */}
      {(verb === 'BUY' || verb === 'PROVISION') && <HoldBlock fleet={fleet} />}

      {verb === 'HIRE' && <CrewBlock fleet={fleet} port={port} config={config} />}
      {verb === 'REPAIR' && <HullsBlock fleet={fleet} port={port} />}
      {verb === 'PROVISION' && <StoresBlock fleet={fleet} />}

      {verb === 'BUY' && (
        <>
          {/* ── WHAT THIS ORDER WOULD DO ──────────────────────────────────────────────────── */}
          <BuyOrderBlock good={good} goodCode={goodCode} capacity={capacity} />
          <PriceBlock market={market} config={config} purser={purser} quay={quay} />
        </>
      )}

      {/* THE ONE HONEST ANSWER TO "what will it cost", on the three verbs the client cannot price.
          It is the LAST block on purpose: it is the caveat under the figures, not a figure. */}
      {verb !== 'BUY' && <PricedOnTheDayBlock verb={verb} />}
    </div>
  )
}

/** HOW MUCH ROOM — `fleet.free_hold`, the SERVED figure (public.fleet_free_hold, 0017:183), against
 *  the fleet's stowed total. Never recomputed here: three client spellings of that subtraction were
 *  deleted and one of them had been wrong since it was written (src/domain/fleet/derive.ts). */
function HoldBlock({ fleet }: { fleet: FleetView }) {
  const stowed = fleetHoldTotal(fleet)
  const quarter = fleet.officer_pct.QUARTERMASTER
  return (
    <section className={BLOCK}>
        <SectionLabel className="mb-1.5">Room in the hold</SectionLabel>
        {/* Rule 2 — the number is the hero. The figure is the largest thing in the block and the
            words under it are the small ones, never the other way round. The recipe was written
            out here and again below, and the unfolded good row wanted a third: it is
            `HeroFigure` now (src/components/ui/HeroFigure.tsx), named before the count reached
            the twelve the chip took. */}
        <HeroFigure value={formatInt(fleet.free_hold)} unit="t free" />
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
  )
}

/** WHAT THIS ORDER WOULD DO — `world.buy_capacity()`, which walks the same stepped quote a
 *  committed trade walks and names the limit that stops her. Asked once by the composer and handed
 *  down; see ./useBuyCapacity.ts. */
function BuyOrderBlock({
  good,
  goodCode,
  capacity,
}: {
  good: MarketView['goods'][number] | undefined
  goodCode: string | null
  capacity: BuyCapacityState
}) {
  return (
      <section className={BLOCK}>
        <SectionLabel className="mb-1.5">This order</SectionLabel>
        {/* WHICH GOOD THESE FIGURES ARE ABOUT, NAMED. It used to be unambiguous because `goodCode`
            could only be the CHOSEN good; it now follows the row the player has UNFOLDED in the
            list beside this rail (OrderComposer's `focusGood`), so the block would otherwise print
            a ceiling and a total for a good the player has not committed to, without saying which.
            A figure whose subject is not named is a figure that can be read as the wrong one. */}
        {good && <p className="mb-1.5 text-sm text-ink">{good.name}</p>}
        {!goodCode ? (
          <p className={fineClass()}>Choose a good and the quay will price it.</p>
        ) : capacity.bound ? (
          <>
            <HeroFigure value={formatInt(capacity.bound.max)} unit="t at most" />
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
  )
}

/** WHAT MOVES THE PRICE — the honest answer to "how much negotiation can be done". Every row is a
 *  served number; see this file's header for what each one is and why they are in this order. */
function PriceBlock({
  market,
  config,
  purser,
  quay,
}: {
  market: MarketView | undefined
  config: SnapshotConfig
  purser: number
  quay: Extract<NonNullable<HaggleStateRead['state']>, { docked: true }> | null
}) {
  return (
      <section className={BLOCK}>
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
  )
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HIRE · REPAIR · PROVISION — the three verbs that had no fleet on screen at all
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-08-23: *"hire, repair, provision — I want fleet info like what is in buy."*
//
// Each of these is a decision about the fleet's state, and until this slice the composer showed the
// player NOTHING about it — HIRE offered a slider up to her empty berths without saying how many
// crew she had, REPAIR asked for a percentage without saying what her worst hull stood at, and
// PROVISION asked for days without saying how many she was already carrying.
//
// EVERY FIGURE BELOW IS EITHER SERVED OR A FOLD THAT ALREADY HAS ONE OWNER in `src/domain/fleet` —
// `fleetCrew` (which is the spelling `cmd.do_hire`'s own E_CREW_MAX counts by, 0007:659),
// `worstHullFraction`, `hullFraction`, `fleetStores`, and `fleet.endurance_days` straight off the
// wire. Nothing here re-derives a rule, and nothing here prices anything.

/** HER CREW — what is aboard against what she was built to carry, and the pool this port offers.
 *  `fleetCrew` is the ONE reading of a fleet's crew (domain/fleet); three screens used to fold it
 *  three ways and only one of them matched the server. ("Her hands" until 2026-08-23 — the owner:
 *  "and hands? seriously? change it like crew or something." Sailor's cant is jargon, and the
 *  standing rule is no jargon. The word survives only where the SERVER says it — verb help/note,
 *  refusal sentences — which is a migration's to change, not this file's to paper over.) */
function CrewBlock({
  fleet,
  port,
  config,
}: {
  fleet: FleetView
  port: SnapshotPort | null
  config: SnapshotConfig
}) {
  const crew = fleetCrew(fleet)
  return (
    <section className={BLOCK}>
      <SectionLabel className="mb-1.5">Her crew</SectionLabel>
      <HeroFigure value={formatInt(crew.aboard)} unit={`of ${formatInt(crew.max)} berths`} />
      <div className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1">
        <Gauge
          value={crew.aboard}
          max={crew.max}
          segments={10}
          // SHORT-HANDED IS THE DANGER STATE, NOT FULL. A full crew is the good end of this
          // gauge, which is the opposite of the hold's — so the tone is read off `short`, the
          // server's own refusal condition, rather than off how full the bar looks.
          tone={crew.short > 0 ? 'danger' : 'success'}
          label={`crew, ${formatInt(crew.aboard)} of ${formatInt(crew.max)} berths filled`}
        />
        <span className={fineClass()}>{formatOfTotal(crew.aboard, crew.max)} filled</span>
      </div>
      {/* ONE LIST OF CREW FIGURES (the owner, 2026-08-23: "how many crew? show my ship info
          regarding crew, how many needs, min amount, max amount etc at the right"). Aboard, the
          least she sails with, the most she was built for, the empty berths a HIRE can fill, and
          the men this port can offer — each a bare figure with its label, aligned down one
          column. The idle men used to be a SECOND section with its own hero, which put the one
          figure a HIRE is compared against (berths empty) two blocks away from the pool it is
          compared WITH; they are rows of one list now, and read together. */}
      <dl className="mt-2 space-y-1">
        <StatRow label="aboard" value={formatInt(crew.aboard)} />
        <StatRow
          label="needs to sail"
          value={formatInt(crew.required)}
          hint="Her required complement. Below it SAIL is refused outright (E_CREW_SHORT) — she cannot leave the quay short-handed."
        />
        <StatRow label="berths" value={formatInt(crew.max)} />
        <StatRow
          label="berths empty"
          value={formatInt(crew.berths)}
          hint="The ceiling on a HIRE. The server counts them the same way (E_CREW_MAX, 0007:659)."
        />
        <StatRow
          label="idle in this port"
          value={port ? formatInt(port.crew_pool) : '—'}
          hint="The men idle here sign on at the quay's own rate. Ask for MORE than are idle and the rest must be found at a steeper price a head — dearer, never refused; the quay names the figure when the order runs."
        />
        {/* THE RATE, NOT THE BILL. `config.wage_per_crew_day` is a served knob and this is the
            number a HIRE is decided against: every crew member signed on adds this much to every
            day at sea, for as long as she is out. The fleet's TOTAL daily wage is a different
            fact and it is already printed on the Fleets tab (FleetsScreen.tsx:529,
            `aboard × rate`) — one product, one place; this row is the rate the product is made
            of. */}
        <StatRow
          label="crew wage"
          value={`${formatDucats(config.wage_per_crew_day)} a day each`}
          hint="Paid to every crew member aboard for every day at sea, whatever she is doing. What it costs to SIGN one on is the port's own rate and is settled when the order runs."
        />
      </dl>
      {/* REASONS STAY VISIBLE — these are things she cannot do right now, so neither goes behind
          a dot (Explain.tsx's law: refusals are never folded away). */}
      {crew.short > 0 && (
        <p className={fineClass('mt-1.5')}>
          She is {formatInt(crew.short)} crew short of her complement — SAIL is refused until they
          are signed on.
        </p>
      )}
      {!port && <p className={fineClass('mt-1.5')}>She is at sea. Crew are signed on in port.</p>}
    </section>
  )
}

/** HER HULLS — the worst one, which is what a REPAIR order is really about, and then every one of
 *  them. `worstHullFraction` and `hullFraction` are domain/fleet's; the ratio is not served. */
function HullsBlock({ fleet, port }: { fleet: FleetView; port: SnapshotPort | null }) {
  const worst = worstHullFraction(fleet)
  return (
    <>
      <section className={BLOCK}>
        <SectionLabel className="mb-1.5">Her hulls</SectionLabel>
        <HeroFigure value={formatPct(worst, 0)} unit="worst hull" />
        {/* EVERY HULL, NOT JUST THE WORST — because REPAIR mends the fleet TO a percentage, so the
            hull that is already above it is the one that will not be touched, and the player can
            only see that if the whole roster is on screen. It is a list of figures with no control
            in it, which is what a sticky rail may carry (screenLayout.ts). */}
        <ul className="mt-2 space-y-1.5">
          {fleet.ships.map((ship) => {
            const pct = hullFraction(ship) * 100
            return (
              <li key={ship.id}>
                <div className="flex items-baseline justify-between gap-2 text-sm">
                  <span className="min-w-0 flex-1 truncate text-ink-faint">{ship.name}</span>
                  <span className="shrink-0 font-mono text-ink">{Math.round(pct)}%</span>
                </div>
                <Meter pct={pct} tone={pct < 50 ? 'danger' : pct < 90 ? 'warning' : 'success'} />
              </li>
            )
          })}
        </ul>
        {fleet.ships.length === 0 && <p className={fineClass('mt-1.5')}>She has no hulls.</p>}
      </section>

      <section className={BLOCK}>
        {/* "SHIPYARD", NEVER "YARD" (the owner, 2026-08-23: "what is yard?"). A word the player
            has to ask about is jargon, and the no-jargon rule applies to the game's own nouns
            first. The full word says what the place IS; the sentence says what it does. */}
        <SectionLabel className="mb-1.5">The shipyard here</SectionLabel>
        {!port ? (
          <p className={fineClass()}>She is at sea. A hull is mended alongside.</p>
        ) : port.has_yard ? (
          <>
            <HeroFigure value={`Tier ${formatInt(port.yard_tier)}`} />
            <p className={fineClass('mt-1.5')}>
              {port.name} keeps a shipyard, where hulls are mended. A better one works better —
              what it charges for this hull is the port's own affair, and it is named when you
              check the order.
            </p>
          </>
        ) : (
          // NOT HIDDEN, AND WITH ITS REASON (docs/UI_DIRECTION.md §4 rule 5). The refusal itself is
          // still the server's; this only stops the order being a surprise.
          <p className="text-sm text-ink-muted">
            There is no shipyard at {port.name}. She must lie at a port that keeps one before she
            can be mended.
          </p>
        )}
      </section>
    </>
  )
}

/** HER STORES — how many days she can stay at sea, and what is in the barrels. `endurance_days` is
 *  SERVED: the client never divides stores by a burn rate to arrive at it. */
function StoresBlock({ fleet }: { fleet: FleetView }) {
  const stores = fleetStores(fleet)
  return (
    <section className={BLOCK}>
      {/* THE STANDING EXPLANATION IS BEHIND THE DOT (Explain.tsx). The "after" figure is still not
          invented here: how many days she would have once provisioned depends on the port's prices
          and on what actually fits, both of which are the server's — `cmd.preview()` runs the real
          verb and rolls it back, so it can say. Guessing it with `(water + days × crew × rate)`
          would be a client rule for a server decision. */}
      <div className="mb-1.5 flex flex-wrap items-center gap-x-1">
        <SectionLabel className="mb-0">Her stores</SectionLabel>
        <Explain label="her stores" panelClassName="w-full normal-case tracking-normal">
          Every tun of water is a tun of pepper she did not carry. What the stores would be worth
          after this order is named when you check it.
        </Explain>
      </div>
      <HeroFigure value={formatVoyageDays(fleet.endurance_days)} unit="at sea" />
      <dl className="mt-2 space-y-1">
        <StatRow label="water" value={formatTuns(stores.waterT)} />
        <StatRow label="food" value={formatTuns(stores.foodT)} />
      </dl>
    </section>
  )
}

/**
 * WHAT IT WILL COST — the honest answer, which is "not yet known", said in the player's words.
 *
 * `src/lib/rpc/types.ts:18-19`: *"a port carries `crew_pool` but no crew RATE, no water/food price
 * and no repair rate; those live in world_config, which snapshot() serves only as an allow-list …
 * PROVISION/HIRE/REPAIR are priced by the server when the order runs."* So there is no figure to
 * print, and the block that would have printed one says where the figure DOES come from instead.
 */
function PricedOnTheDayBlock({ verb }: { verb: string }) {
  const what =
    verb === 'HIRE'
      ? 'What a crew member costs'
      : verb === 'REPAIR'
        ? "What the shipyard's work costs"
        : 'What water and food cost'
  return (
    <section className={BLOCK}>
      {/* One sentence stays — it is the block's whole answer. The second, which explains WHERE the
          figure does come from, is standing prose and lives behind the dot (Explain.tsx). */}
      <div className="mb-1.5 flex flex-wrap items-center gap-x-1">
        <SectionLabel className="mb-0">What it will cost</SectionLabel>
        <Explain label="what it will cost" panelClassName="w-full normal-case tracking-normal">
          Finish the order and the check below the composer runs the real thing and rolls it back,
          so it can tell you the price before a ducat moves.
        </Explain>
      </div>
      <p className="text-sm text-ink-muted">
        {what} is the port's own affair, settled on the day the order runs — no figure for it is
        published in advance.
      </p>
    </section>
  )
}

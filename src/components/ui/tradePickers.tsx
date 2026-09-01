import { Fragment, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import {
  Badge,
  Button,
  buttonClasses,
  categoryLabel,
  EntryTileLine,
  fineClass,
  GoodTile,
  HeroFigure,
  Meter,
  PriceIndex,
  SectionLabel,
  StatRow,
  tileFieldClass,
  useTileCols,
} from './index'
import {
  formatDucats,
  formatInt,
  formatTuns,
} from '../../lib/format'
import type { MarketGood } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { inRowsOf } from './inRows'
import { sellBound, type BuyCapacityState, type QtyBound } from '../../lib/trade'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRADE FOLD — the goods field, its price cells, and the quantity step that opens under one.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// MOVED HERE 2026-09-01, whole, from features/command/ArgPickers.tsx. Not refactored on the way:
// every line below is the line that was there, so the fold COMMAND has been trading through for
// weeks is the identical fold, not a lookalike.
//
// WHY IT MOVED. The owner's row 53 puts buy and sell on PORT — "i want buy and sell on port tab
// … where i press market, then choose to trade" — and a second screen needed this fold.
// `tests/sections.spec.ts` refuses to let one screen import another, and its message names the
// cure: *"whatever is being shared is not that screen's."* It never was COMMAND's. It is how this
// game draws a market, and it belongs where both quays can reach it through the one entrance.
//
// It takes `capacity` as a PROP and asks for nothing: the design system may not import the store
// (`machinery knows nothing above it`), so `useBuyCapacity` stays in src/live and each screen
// hands its one reading down. The shapes both sides name live in src/lib/trade, below them both.
// ═══════════════════════════════════════════════════════════════════════════════════════════════


export function FilterBox({
  value,
  onChange,
  label,
}: {
  value: string
  onChange: (v: string) => void
  label: string
}) {
  return (
    <input
      value={value}
      onChange={(e) => onChange(e.target.value)}
      spellCheck={false}
      autoCorrect="off"
      aria-label={label}
      placeholder={label}
      className="min-h-11 w-full rounded-md border border-edge bg-app px-3 text-sm text-ink outline-none placeholder:text-ink-faint/60 focus:border-accent"
    />
  )
}

export function TruncationNote({ hidden }: { hidden: number }) {
  if (hidden <= 0) return null
  return (
    <p className={fineClass()}>
      {hidden} more — narrow the filter to bring them into reach.
    </p>
  )
}

/**
 * What to trade, priced. E.4's whole reading room in a TILE: what it costs, what it fetches, how
 * that compares with the ports within 600 nm (%NBR), and the server's own buy/hold/sell advice —
 * so the choice is informed before it is made rather than explained after it.
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════
 * GOODS ARE A FIELD OF TILES, NOT A COLUMN OF LINES.
 * ═══════════════════════════════════════════════════════════════════════════════════════════════
 * The owner, 2026-08-26: *"i told trade goods to be in grid like shape - organized not in lines.
 * Yet this also did not occur."* Said twice, and they were right about this list: MARKET and the
 * 도감 converted their goods to `GoodTile` on 2026-08-23 and this picker — the biggest list of
 * trade goods in the game, and the only one you actually BUY from — did not. GoodTile's own header
 * had named it "the named next caller" and it never arrived. MEASURED at 390px before this change:
 * 243 goods as 324px full-width rows, a list 44,212px tall. It is now the design system's tile in
 * the design system's field (`tileFieldClass`), two abreast at 390px, ~158px each.
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════
 * A TILE UNFOLDS TO BE READ; THE PRICE ITSELF IS THE ACT.
 * ═══════════════════════════════════════════════════════════════════════════════════════════════
 * The owner, 2026-08-23, twice in one day:
 *   · *"click a trade good → it unfolds showing how much I can buy, and more."*
 *   · *"i want to be able to click on buy and sell itself and do trades. when pressed unfold
 *      another so that i can choose how much i buy."*
 *
 * So the tile carries TWO kinds of tap and they never share a target: the HEAD opens the tile for
 * reading (capacity, the quay's stock), and the BUY / SELL figure cells are the trade itself.
 * Tapping a cell names both the verb and the good — through the one draft the composer already
 * writes — and opens THIS good's fold, where the quantity step is (GoodDetail). The list never
 * moves: an earlier shape answered the cell by unmounting all seventy rows and standing a qty row
 * where they had been, which is the "tab disappears and opens a new one" the owner refused four
 * times, and it is deleted. The `Choose <good>` button the fold used to carry is DELETED too, not
 * kept alongside: two ways to pick one good is two authorities for the pick
 * (docs/NO_SPAGHETTI.md §5).
 *
 * FOUR RULES THIS KEEPS, and each of them is the reason the shape is what it is:
 *
 * 1. **One good open at a time.** The open code is held by the COMPOSER, not by this list, and it is
 *    a single value rather than a set. A list where every tile can be open is a list nobody can
 *    scan, and 243 goods is a list that must stay scannable. It lives upstairs because the same
 *    open good is what `world.buy_capacity()` is asked about — see OrderComposer's `focusGood`.
 * 2. **Opening never commits.** `onInspect` moves what is being LOOKED at; only a price cell
 *    answers the argument. Tapping an open tile's head closes it again, which is the same gesture
 *    undone rather than a second meaning for one tap.
 * 3. **Nothing folds behind a scroll box.** THE REACH LAW (CORE_REUSE §1.5) — the price cells are
 *    actions, so nothing between them and the page's own scroll may cap or clip. The fold has no
 *    `max-h` and no `overflow`; it simply makes the page longer, which is honest.
 * 4. **THE FOLD LANDS AFTER THE WHOLE ROW OF TILES**, never beside the pressed one. A panel
 *    spanning the grid mid-row re-flows that row and shoves its neighbour down — which is the
 *    restructure-on-press the owner has refused three times (docs/OWNER_REQUESTS.md row 15: "when
 *    pressing sail, stop folding the sail… don't restruct anything"). `useTileCols()` is how this
 *    file knows where a row ends, and PortPicker above already answers SAIL's confirm the same way.
 *
 * EVERY FIGURE IN THE FOLD IS SERVED. Nothing here multiplies a price by a quantity: buying walks a
 * stepped book (§G.2), so the client's arithmetic would disagree with the charge. `max_qty`,
 * `est_total` and the phrase for what stops her are `world.buy_capacity()`. What is ABOARD is the
 * one number this side may count, and it is the fleet's own manifest.
 */
export function GoodPicker({
  goods,
  value,
  /** Tuns aboard by good code — the fleet's own manifest, whenever a fleet is chosen. On a SELL it
   *  also narrows the list to what she carries; on every row it is what lets a sell cell say
   *  "none aboard" instead of going silently dead. */
  aboard,
  intent,
  inspecting,
  onInspect,
  capacity,
  onTrade,
  step,
  qtyValue,
  onPickQty,
}: {
  goods: readonly MarketGood[]
  value: string | undefined
  aboard?: Record<string, number>
  intent: 'buy' | 'sell'
  /** The ONE row that is unfolded, held upstairs so the capacity read can follow it. */
  inspecting: string | null
  onInspect: (code: string | null) => void
  /** The composer's ONE reading of `world.buy_capacity()`, asked about `inspecting`. */
  capacity: BuyCapacityState
  /** THE PRICE IS THE ACT. Fired by a row's buy or sell cell; the composer answers it by setting
   *  the verb AND the good on the one draft, so the cell can never become a second way an order
   *  comes into being — the same line is composed, previewed and issued as ever. */
  onTrade: (verb: 'BUY' | 'SELL', code: string) => void
  /** `config.trade_step_tuns` — the fold's quantity stepper walks in the server's own steps. */
  step: number
  /** The draft's `qty`, drawn ONLY in the chosen good's fold — the list itself never says it. */
  qtyValue: string | undefined
  /** Answers the verb's `qty` argument, through the composer's one `answer`. */
  onPickQty: (value: string) => void
}) {
  const [filter, setFilter] = useState('')
  const cols = useTileCols()

  const rows = useMemo(() => {
    const q = fold(filter.trim())
    return goods
      .filter((g) => g.available)
      // 0061 — A BUY LIST IS THIS CITY'S QUAY, NOT THE CATALOGUE. `offered` is the server's one
      // answer (public.port_offers) to "does this city trade this?", and cmd.do_buy refuses
      // anything else with E_UNAVAILABLE, so a row the verb would refuse never reaches the list.
      // A SELL list is deliberately NOT narrowed the same way: a city buys what is offered to it,
      // and the market read carries the goods she is carrying here precisely so they can be sold.
      .filter((g) => intent === 'sell' || g.offered !== false)
      // A SELL list is what she carries; a BUY list is the whole quay. `aboard` itself no longer
      // decides — it is given on BUY too now, so the sell cells can say why they are dead.
      .filter((g) => (intent === 'sell' && aboard ? (aboard[g.code] ?? 0) > 0 : true))
      .filter((g) => foldedMatch(q, g.name, g.code, g.category))
      .sort((a, b) => {
        // The advice the server gave, first: a BUY list opens on what is cheap here, a SELL list on
        // what this port pays over the odds for.
        const want = intent === 'buy' ? 'buy' : 'sell'
        const rank = (g: MarketGood) => (g.advice === want ? 0 : g.advice === 'hold' ? 1 : 2)
        const byAdvice = rank(a) - rank(b)
        if (byAdvice !== 0) return byAdvice
        const an = a.pct_nbr ?? 100
        const bn = b.pct_nbr ?? 100
        return intent === 'buy' ? an - bn : bn - an
      })
  }, [goods, filter, aboard, intent])

  // EVERY GOOD THIS PORT TRADES, not a page of them — see MAX_PORT_ROWS for why the ports list
  // still caps and this one does not. The count rides above the list so the length is a stated
  // fact rather than a surprise, and the filter is still the way to one row by name.
  const shown = rows

  return (
    <div className="space-y-2">
      <FilterBox value={filter} onChange={setFilter} label="Filter goods" />
      {shown.length > 0 && (
        <p className={fineClass()}>
          {shown.length} {shown.length === 1 ? 'good' : 'goods'}
          {intent === 'sell' ? ' aboard and traded here' : ' traded here'}
          {filter.trim() ? ' answer to that filter' : ", the quay's own advice first"}
        </p>
      )}
      {shown.length === 0 && (
        <p className="text-sm text-ink-muted">
          {intent === 'sell' && !filter.trim()
            ? 'This fleet is carrying nothing this port will trade.'
            : 'Nothing here answers to that.'}
        </p>
      )}
      {/* THE FIELD OF GOODS — the design system's tile in the design system's field, chunked into
          ROWS so the fold can land after a whole one (rule 4 in this component's header). The order
          inside the field is unchanged: the quay's own advice first, then the price index. */}
      {inRowsOf(shown, cols).map((row) => (
        <Fragment key={row[0].code}>
          <div className={tileFieldClass()}>
            {row.map((g) => {
              const isOpen = inspecting === g.code
              return (
                <GoodTile
                  key={g.code}
                  // A MARK PER GOOD, AND IT IS LITERALLY PER GOOD (the owner, 2026-08-22: "i want a
                  // picture or an icon for each trade good") — the tile draws it from `code`, so
                  // there is no second `goodIcon` call here. THE NAME STAYS BESIDE THE MARK: at
                  // 18px a handful of pairs — ivory/tea, nutmeg/cacao, silk cloth/muslin, musk/furs
                  // — are only just apart. The glyph makes 243 goods scannable; the word makes them
                  // unambiguous. Neither replaces the other. `rarity` is SERVED (0032) and the tile
                  // draws it in the corner through the one RarityMark, which is why nothing here
                  // renders it a second time.
                  code={g.code}
                  category={g.category}
                  name={g.name}
                  rarity={g.rarity}
                  // THE HEAD IS THE BUTTON, NOT THE TILE: the buy and sell cells below are buttons
                  // of their own, and a button inside a button is not markup a browser will honour
                  // (EntryTile.tsx's third tap shape).
                  tapTarget="head"
                  // TWO STATES, ONE TINT, DELIBERATELY. The soft tint means "this good is the one
                  // you are dealing with" — whether that is because it is CHOSEN or because it is
                  // OPEN. They are never ambiguous in practice, because the word under the name
                  // says which: an open tile says "open", a chosen one says "chosen".
                  selected={value === g.code || isOpen}
                  expanded={isOpen}
                  // OPENING, NOT CHOOSING. This tap used to call `onPick` and commit the argument.
                  onTap={() => onInspect(isOpen ? null : g.code)}
                  tapTitle={`${g.name} (${categoryLabel(g.category)}) — open to read what she can carry`}
                  testId="good-pick-tile"
                >
                  {/* THE KIND, THE QUAY'S WORD, AND WHICH TILE THIS IS. The name is not printed
                      twice: `g.code` is DERIVED from it ("Black Pepper" → "black-pepper"), and the
                      composed order line above still carries the parser's spelling. */}
                  <span className="flex w-full flex-wrap items-center gap-1.5">
                    <span className={fineClass()}>{categoryLabel(g.category)}</span>
                    <Badge tone={g.advice === 'buy' ? 'success' : g.advice === 'sell' ? 'accent' : 'neutral'}>
                      {g.advice}
                    </Badge>
                    <span aria-hidden className="ml-auto font-mono text-[10px] uppercase tracking-wider text-accent">
                      {isOpen ? 'open' : value === g.code ? 'chosen' : 'look'}
                    </span>
                  </span>
                  <GoodFigures
                    good={g}
                    aboard={aboard ? (aboard[g.code] ?? 0) : undefined}
                    intent={intent}
                    onTrade={(verb) => onTrade(verb, g.code)}
                  />
                </GoodTile>
              )
            })}
          </div>
          {/* THE FOLD, AFTER THE WHOLE ROW holding the open tile — so the tile beside it holds
              perfectly still and only what is BELOW moves down, which is what an unfold IS. Same
              placement PortPicker gives SAIL's confirm, for the same reason. */}
          {row.map((g) =>
            inspecting === g.code ? (
              <GoodDetail
                key={`${g.code}-fold`}
                good={g}
                intent={intent}
                capacity={capacity}
                // THE QUANTITY STEP RIDES IN THE CHOSEN GOOD'S FOLD AND NOWHERE ELSE. Tapping a
                // price cell chooses the good AND opens this fold (the composer's `trade`), so
                // "how much" appears right under the press — with the whole field still standing
                // above and below it to change your mind with. A good merely being LOOKED at gets
                // the reading (capacity, the quay's stock) and no stepper: sizing an order is an
                // act over the CHOSEN good only.
                qty={
                  value === g.code
                    ? { step, value: qtyValue, aboard: aboard?.[g.code] ?? 0, onPick: onPickQty }
                    : null
                }
              />
            ) : null,
          )}
        </Fragment>
      ))}
    </div>
  )
}

/**
 * THE UNFOLDED PANEL — the reading, and, for the CHOSEN good only, the quantity step. Opening the
 * fold is still looking (capacity, the quay's stock) and still commits nothing; choosing is still
 * the tile's own price cells (GoodFigures). What the cells' tap opens is THIS fold — which lands
 * after the whole ROW OF TILES holding the pressed one, so its neighbour holds still and only what
 * is below moves down, and the field never restructures.
 * The `Choose <good>` button the fold once held stays deleted — a second way to pick a good is two
 * authorities for the pick (docs/NO_SPAGHETTI.md §5) — and the stepper is not a second way either:
 * it answers `qty`, not `good`, through the composer's one `answer`.
 *
 * ── WHAT IS HERE, AND WHOSE NUMBER EACH ONE IS ─────────────────────────────────────────────────
 *   HOW MANY SHE CAN TAKE   `world.buy_capacity(fleet, good)` — `max_qty`, `est_total` and
 *                           `bound_by`, the server's own PHRASE for what stops her. On a SELL the
 *                           ceiling is what is aboard, which is the fleet's own manifest and the
 *                           one quantity this side may count (fleetLimits.ts).
 *   ON THE QUAY             `stock` against `stock_target`, the figures behind the tile's meter.
 *
 * ── AND WHAT IS DELIBERATELY NOT ───────────────────────────────────────────────────────────────
 *   · NO PRODUCT OF A PRICE AND A QUANTITY. A BUY reprices every `trade_step_tuns` (§G.2), so
 *     `buy × qty` is always too low — that exact arithmetic is what offered 91 tuns of pepper
 *     against a purse that could carry 50 (useBuyCapacity.ts). `est_total` is the served answer.
 *   · NO "WHERE IT PAYS MORE". The fold used to name the reachable port that pays most, from
 *     `world.trade_routes()` — the owner, 2026-08-23: "where it pays more does not need to be
 *     given in buy." The comparison belongs to the Market tab, which still draws it; the block,
 *     its props and the screen's per-port fetch went together (docs/NO_SPAGHETTI.md §5).
 *   · NO ADVICE. The server already gives one word of it on the row; a paragraph arguing for a
 *     trade would be this screen having an opinion about a price, which is the thing it may not do.
 */
function GoodDetail({
  good,
  intent,
  capacity,
  qty,
}: {
  good: MarketGood
  intent: 'buy' | 'sell'
  // NO bare `aboard` PROP. It was here to draw a SELL hero reading "20 t aboard" — a third
  // rendering of a figure the row above already carries. What rides in instead is `qty.aboard`,
  // and only for the CHOSEN good, because it is the sell stepper's CEILING — an input to a
  // control, not a rendering of a fact.
  capacity: BuyCapacityState
  /**
   * THE QUANTITY STEP — present only when this fold belongs to the CHOSEN good (the owner,
   * 2026-08-23: *"i want to be able to click on buy and sell itself and do trades. when pressed
   * unfold another so that i can choose how much i buy"*). The old shape answered that by
   * UNMOUNTING the goods list and standing a qty row where it had been — the exact
   * "tab disappears and opens a new one" the owner refused four times — so the step now unfolds
   * HERE, under the pressed row, and the list never moves. `aboard` is the SELL ceiling (the one
   * quantity this side may count); a BUY's ceiling stays `capacity`, the server's own answer.
   */
  qty: { step: number; value: string | undefined; aboard: number; onPick: (v: string) => void } | null
}) {
  return (
    <div className="mt-1 space-y-3 rounded-md border border-accent/40 bg-app p-3">
      {/* ── HOW MANY SHE CAN TAKE — BUY ONLY, AND THE ABSENCE ON SELL IS THE POINT ───────────────
          A SELL block here would print "20 t aboard" as a hero, and that number is ALREADY on the
          tile above it (GoodFigures' `aboard` line, under the stock meter) and again in the
          quantity stepper's caption ("up to 20 t — what is aboard stops you there"). Three
          renderings of one fact, so the two that were added here are the ones that go
          (docs/NO_SPAGHETTI.md §5). */}
      {/* … AND NOT WHEN THE STEPPER IS. For the CHOSEN good the quantity step below already
          states the same ceiling and the same binding in its own caption ("up to 74 t — hold
          stops you there"), so drawing the hero figure above it would be two renderings of one
          fact in one fold (docs/NO_SPAGHETTI.md §5). The reading serves the row being LOOKED at;
          the stepper serves the row that was chosen; a fold carries one of them. What the hero
          block says that the caption does not — what all of it costs — is the rail's THIS ORDER
          figure, drawn there under a label (see QtyPicker's header for that measurement). */}
      {intent === 'buy' && !qty && (
        <section>
          {/* "Capacity", not "How much she can take" — the owner's 2026-08-23 label sweep: a label
              names a thing, it is not a question. The word is `world.buy_capacity()`'s own. */}
          <SectionLabel className="mb-1.5">Capacity</SectionLabel>
          {capacity.bound ? (
            <>
              <HeroFigure value={formatInt(capacity.bound.max)} unit="t at most" />
              <dl className="mt-2 space-y-1">
                {/* THE SERVER'S WORD FOR WHAT STOPS HER — 'hold' · 'stock' · 'daily cap' · 'purse' ·
                    'at sea'. This is the whole of "and why not more", and it is not worked out here:
                    a client that guessed would guess wrong the moment a quartermaster is posted. */}
                <StatRow label="stopped by" value={capacity.bound.binding} plain />
                {capacity.estTotal !== null && (
                  <StatRow label="all of it costs" value={formatDucats(capacity.estTotal)} />
                )}
              </dl>
            </>
          ) : (
            <p className={fineClass()}>
              {capacity.loading
                ? 'Asking the quay what she can carry and afford…'
                : 'The most she can take on is not known yet.'}
            </p>
          )}
        </section>
      )}

      {/* ── HOW MUCH — the act's own size, in the fold the act opened ──────────────────────────
          "How much", the same words the argument row used to carry (LABELS.qty), so the concept
          keeps its one name. On a BUY the ceiling is the server's (`capacity.bound`, §G.2 — the
          book steps, so nothing here multiplies a price out); on a SELL it is what is aboard,
          the one quantity this side may count. */}
      {qty && (
        <section className="border-t border-edge pt-3 first:border-0 first:pt-0">
          <SectionLabel className="mb-1.5">How much</SectionLabel>
          {intent === 'sell' ? (
            <QtyPicker bound={sellBound(qty.aboard)} step={qty.step} value={qty.value} onPick={qty.onPick} />
          ) : capacity.bound ? (
            <QtyPicker bound={capacity.bound} step={qty.step} value={qty.value} onPick={qty.onPick} />
          ) : (
            <p className={fineClass()}>
              {capacity.loading
                ? 'Asking what she can carry and afford…'
                : 'The most she can take on is not known yet.'}
            </p>
          )}
        </section>
      )}

      {/* `first:` because on a SELL there is no capacity block above, and a rule with nothing over
          it is a line the eye trips on. */}
      <section className="border-t border-edge pt-3 first:border-0 first:pt-0">
        <dl className="space-y-1">
          {/* THE FIGURES BEHIND THE ROW'S OWN METER, and ONLY those. The first draft of this block
              also printed "this port asks 87 d./t" and "this port pays 80 d./t" — which are the
              BUY and SELL columns of the row this fold is hanging off, 200px above it. Two
              renderings of one fact, so this is the copy that goes (docs/NO_SPAGHETTI.md §5; the
              same call `TradedRow`'s `block` prop lost, docs/DEV_LOG.md:305). The stock FIGURES
              are not a second rendering: the row carries a six-block meter and no numbers. */}
          <StatRow
            label="on the quay"
            value={`${formatTuns(good.stock)} of ${formatTuns(good.stock_target)}`}
          />
        </dl>
      </section>
    </div>
  )
}


/**
 * THE FIGURES INSIDE A GOOD'S TILE, EACH ON ITS OWN LINE — the owner, 2026-08-22: *"for each info -
 * buy, sell, 81% of neighbours i want a separate tab - graphics. bigger."*
 *
 * They used to be one run-on mono line under the name — `buy 7 d./t · sell 6 d./t · 81% of
 * neighbours` — at 11px, which is docs/UI_DIRECTION.md §1's second diagnosis exactly: prose where
 * the game wants a number. Rule 2 says **the number is the hero**, so each figure gets its own
 * box: the label small-caps, mono and dim; the figure bright and a clear size larger than it.
 *
 * THREE COLUMNS ACROSS A ROW BECAME FOUR LINES DOWN A TILE on 2026-08-26, when the goods became a
 * field (see GoodPicker's header). It is the same three figures — nothing was dropped and nothing
 * was added — re-laid for a 158px box instead of a 324px one, and the measurement that forced it is
 * on the stack below.
 *
 * THE UNIT RIDES SMALL BESIDE THE FIGURE rather than inside it. `formatUnitPrice` renders
 * "3,500 d./t", which at this size does not fit beside its own label — and dropping the unit is
 * not an option (EVE's rule, §3: units are always attached). So the figure is the grouped number
 * and the unit is a 10px suffix, which is the same shape NumberPicker already uses for its
 * suggestion chips.
 *
 * %NBR IS <PriceIndex>, NOT A FOURTH RENDERING OF IT. The pill is the one treatment of that number
 * and its tone comes from the server's own `advice` (PriceIndex.tsx) — never from comparing `pct`
 * against a threshold here, because the thresholds live in migration 0009.
 *
 * THE BUY AND SELL CELLS ARE THE TRADE (the owner, 2026-08-23: "i want to be able to click on buy
 * and sell itself and do trades"). Both are real buttons at the 44px floor, and each answers the
 * verb AND the good in one tap, through `onTrade` — never through a second path.
 *
 *   · A SELL of what she does not carry is not an order, so that cell is disabled AND says why —
 *     "none aboard", on the cell — never a grey square with no explanation. `aboard` is the
 *     fleet's own manifest, the one quantity this side may count.
 *   · A BUY the purse cannot afford is NOT decided here. That answer is `world.buy_capacity()`'s,
 *     read once for the good in focus — never 243 times for 243 tiles — and the quantity step
 *     names it in the server's own word ("purse allows none").
 */
function GoodFigures({
  good,
  aboard,
  intent,
  onTrade,
}: {
  good: MarketGood
  /** Tuns of THIS good aboard, when a fleet is chosen; undefined when none is. */
  aboard: number | undefined
  intent: 'buy' | 'sell'
  onTrade: (verb: 'BUY' | 'SELL') => void
}) {
  const sellDead = aboard !== undefined && aboard <= 0
  return (
    <span className="mt-0.5 grid gap-1.5">
      {/* THE TWO PRICE CELLS ARE STACKED, NOT SIDE BY SIDE — and that is a MEASUREMENT, not a
          preference. A tile is 158px wide at 390px (tileLayout.ts), ~138px inside its padding; two
          cells abreast leaves each ~48px of text, and a four-figure price in the mono face is 42px
          before its `d./t`. MARKET's own tile learned this on 2026-08-23 and its header records it:
          "`buy · sell — 364 · 334` wrapped mid-figure at 390px … a figure is one token". Full width
          each, so no price can ever shear, and each cell is its own ≥44px tap target. */}
      <Figure label="buy" title="Buy this here — what she pays, per tun" onPress={() => onTrade('BUY')}>
        <span className="tabular-nums">{formatInt(good.buy)}</span>
        <span className="ml-1 text-[10px] font-normal text-ink-faint">d./t</span>
      </Figure>
      <Figure
        label="sell"
        title="Sell this here — what this port pays her, per tun"
        onPress={() => onTrade('SELL')}
        disabled={sellDead}
        note={sellDead ? 'none aboard' : undefined}
      >
        <span className="tabular-nums">{formatInt(good.sell)}</span>
        <span className="ml-1 text-[10px] font-normal text-ink-faint">d./t</span>
      </Figure>
      {/* "nearby", NOT "neighbours". Measured at 390px: a third of the old row was ~96px and
          `neighbours` rendered as `NEIGHBOUR…` — a label truncated by its own cell, which is a
          label that has stopped working. Not `%NBR` either: that is the column name in the data
          and in migration 0009, and the map-UX rule is that the player never reads the schema.
          It is a LINE rather than a cell now: it is not an action, and giving a reading the same
          44px box as the two acts beside it said it was one. */}
      <EntryTileLine label="nearby">
        <PriceIndex pct={good.pct_nbr} advice={good.advice} />
      </EntryTileLine>
      <EntryTileLine label="stock">
        <Meter
          pct={(good.stock_band / 6) * 100}
          tone={good.stock_band >= 4 ? 'success' : 'warning'}
          className="w-14 min-w-0"
        />
      </EntryTileLine>
      {/* The aboard figure is a SELL list's caption, as it always was — on a BUY the manifest is
          here only to reason about the sell cell, and printing "0 t aboard" on 243 buy tiles would
          be 243 answers to a question nobody asked. */}
      {intent === 'sell' && aboard !== undefined && (
        <EntryTileLine label="aboard">{formatTuns(aboard)}</EntryTileLine>
      )}
    </span>
  )
}

/**
 * One labelled figure cell. Label above, figure below — never the other way round (rule 2).
 *
 * Given `onPress` it is a BUTTON — the buy/sell cells are the trade since 2026-08-23 — at the 44px
 * floor, with the chip's own hover grammar and the system's disabled treatment
 * (`disabled:opacity-45`, buttonStyles.ts), and `note` is the one line that says why a dead cell
 * is dead. This component is the single authority for the cell's recipe in both shapes.
 */
function Figure({
  label,
  title,
  children,
  onPress,
  disabled,
  note,
}: {
  label: string
  title: string
  children: ReactNode
  onPress?: () => void
  disabled?: boolean
  note?: string
}) {
  const cell = 'min-w-0 rounded border border-edge/60 bg-app/40 px-2 py-1'
  const inner = (
    <>
      <span className="block truncate font-mono text-[10px] uppercase tracking-wider text-ink-faint">
        {label}
      </span>
      <span className="block truncate font-mono text-sm text-ink">{children}</span>
      {/* The note WRAPS, never truncates: it is the reason a dead cell is dead, and "none abo…"
          is not a reason. MEASURED at 390px — a third of the row truncated it. */}
      {note && <span className={fineClass('block')}>{note}</span>}
    </>
  )
  if (!onPress) {
    return (
      <span className={`block ${cell}`} title={title}>
        {inner}
      </span>
    )
  }
  return (
    <button
      type="button"
      onClick={onPress}
      disabled={disabled}
      title={title}
      className={`block min-h-11 text-left transition hover:border-accent/60 disabled:cursor-not-allowed disabled:opacity-45 ${cell}`}
    >
      {inner}
    </button>
  )
}

// ── qty ────────────────────────────────────────────────────────────────────────────────────────

/**
 * A quantity, between nothing and what is actually possible. ALL and HALF are the server's own
 * tokens and are read when the order RUNS, not when it is made (F.2) — which is why they are
 * offered beside the slider rather than instead of it: a queued `SELL cloves ALL` sells whatever
 * arrived, and that is usually what a player means.
 *
 * ── WHAT THE CAPTION NO LONGER SAYS, 2026-08-22 ────────────────────────────────────────────────
 * It read `up to 50 t — your purse stops you there (6,916 d. for all of it)`, and it took an
 * `estTotal` prop to say the money part. MEASURED on the running BUY screen: the same 6,916 d. was
 * printed 400px away in the fleet rail's THIS ORDER block, under a label, in a column, beside the
 * price of the first step — the better of the two renderings by some distance. Two renderings of
 * one fact, so this was the copy to delete (docs/NO_SPAGHETTI.md §5), and the prop went with it
 * rather than being left unused.
 *
 * The ceiling itself stays, because a control should say what stops it and because SELL has no
 * rail at all: what is aboard is aboard, the client can count it, and nothing else on the screen
 * says so.
 */
export function QtyPicker({
  bound,
  step,
  value,
  onPick,
}: {
  bound: QtyBound
  /** `config.trade_step_tuns` — the server reprices every step, so the stepper walks in them. */
  step: number
  value: string | undefined
  onPick: (value: string) => void
}) {
  const numeric = value && /^[0-9]+$/.test(value) ? Number(value) : null
  const max = bound.max
  const stepSize = Math.max(1, Math.round(step))
  const current = numeric ?? Math.min(max, stepSize)

  const setNumber = (n: number) => onPick(String(Math.max(0, Math.min(max, Math.round(n)))))
  /** The first tap on + or − takes the shown figure, not one step past it. */
  const bump = (delta: number) => setNumber(numeric === null ? current : current + delta)

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        {/* Three of the hand-written chip recipes the D12 audit found, now the design system's own
            `chip` / `chip-on` variants (buttonStyles.ts). MAX has no ON state — it SETS the number
            rather than becoming the value — so it is always the OFF variant, and the disabled
            treatment it used to spell out (`disabled:opacity-45`) is already in the base recipe. */}
        {(['ALL', 'HALF'] as const).map((token) => (
          <button
            key={token}
            type="button"
            onClick={() => onPick(token)}
            className={buttonClasses(
              value === token ? 'chip-on' : 'chip',
              'md',
              'font-mono text-xs uppercase tracking-wider',
            )}
          >
            {token}
          </button>
        ))}
        {/* JUST "MAX" (the owner, 2026-08-23: "what is max 12 in hire? just max is enough").
            The chip means "as much as possible"; the figure it lands on is already stated in the
            caption under the slider, and printing it on the chip too was two renderings of the
            ceiling 60px apart. */}
        <button
          type="button"
          disabled={max <= 0}
          onClick={() => setNumber(max)}
          className={buttonClasses('chip', 'md', 'font-mono text-xs uppercase tracking-wider')}
        >
          max
        </button>
      </div>

      {max > 0 && (
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            {/* THE STEPPER IS `Button variant="chip" size="icon"`. `icon` is exactly the
                `h-11 w-11 p-0` these two used to spell out, and `chip` is exactly their skin, so
                the pair is now the design system's and cannot drift from the chips beside it.
                `text-lg` stays: the size sets `text-base`, and a stepper glyph wants to be the
                largest thing in its own square.

                THE GLYPHS STAY AS TEXT, BOTH OF THEM. `icons.ts` has a `plus` and no minus, and a
                stepper whose + is 1.5px SVG line work while its − is a font glyph would not match
                in weight at any size. The pair is one control, so it is drawn one way — and the
                icon set's own header says a glyph "never replaces a word". A minus is closer to a
                word than to a mark. */}
            <Button
              variant="chip"
              size="icon"
              aria-label={`Less by ${stepSize} tuns`}
              onClick={() => bump(-stepSize)}
              className="shrink-0 text-lg"
            >
              −
            </Button>
            <span
              className={`min-w-0 flex-1 text-center font-mono text-lg ${numeric === null ? 'text-ink-faint' : 'text-ink'}`}
            >
              {/* Nothing chosen yet still SHOWS the figure the stepper would land on, faintly —
                  a bare dash tells the player nothing about what + is about to do. */}
              {numeric === null ? (value ?? formatTuns(current)) : formatTuns(numeric)}
            </span>
            <Button
              variant="chip"
              size="icon"
              aria-label={`More by ${stepSize} tuns`}
              onClick={() => bump(stepSize)}
              className="shrink-0 text-lg"
            >
              +
            </Button>
          </div>
          <input
            type="range"
            min={0}
            max={max}
            step={stepSize}
            value={numeric ?? 0}
            aria-label="Tuns"
            onChange={(e) => setNumber(Number(e.target.value))}
            className="h-11 w-full accent-accent"
          />
        </div>
      )}

      <p className={fineClass()}>
        {max > 0
          ? `up to ${formatTuns(max)} — ${bound.binding} stops you there`
          : `nothing is possible here: ${bound.binding} allows none`}
      </p>
    </div>
  )
}

import { useMemo, useState } from 'react'
import {
  Badge,
  Button,
  Explain,
  fineClass,
  Icon,
  Notice,
  SectionLabel,
  splitClass,
  splitMainClass,
  splitRailClass,
} from '../../components/ui'
import { VERB_ICON } from './verbIcons'
import { formatTuns } from '../../lib/format'
import type {
  FleetView,
  MarketView,
  SnapshotPort,
  TradeRoutes,
  VerbArg,
  VerbSpec,
  WorldSnapshot,
} from '../../lib/rpc'
// THE CHART IS A LAYER OF ITS OWN (src/chart), not the Map tab's. SAIL's rail draws the SAME chart
// the Map tab draws, out of the same modules — a chart copied across the screen boundary is the
// silent copy docs/NO_SPAGHETTI.md §2 calls worse than the import. src/chart/index.ts records why
// the carve-out line falls where it does.
import { SmallChart } from '../../chart'
import { EnumPicker, GoodPicker, NumberPicker, PortPicker, PricePicker, QtyPicker } from './ArgPickers'
import { useBuyCapacity, type BuyCapacityState } from './useBuyCapacity'
import { FleetRail } from './FleetRail'
import { railKind } from './railVerbs'
import { HaggleBlock } from './HaggleBlock'
import { useHaggleState } from './useHaggleState'
import { sellBound } from './fleetLimits'
// THE FLEET'S OWN ARITHMETIC COMES FROM THE FLEET SECTION. What is aboard, how many berths stand
// empty and how sound the worst hull is are properties of a FLEET, not of the tab composing an
// order about one. ./fleetLimits.ts used to answer all three and every answer had a twin somewhere
// else in src/ — its header is the ledger of what moved where.
import { fleetCargoByCode, fleetCrew, fleetPortCode, worstHullFraction } from '../../domain/fleet'
import { missingArgs, visibleArgs } from '../../domain/order'

// THE COMPOSER — an order is MADE, never typed.
//
// The player picks, in order, from things that really exist: a verb the server serves, then one
// value per argument THE SERVER'S OWN SCHEMA declares (`world.snapshot().verbs`, which is
// `cmd.verb_schema()` — F.4: "cmd.verb_schema() exists so the tap-builder READS the grammar
// instead of restating it"). There is no verb table on this side of the wire: add a verb to the
// chain and it appears here, with its arguments, without an edit.
//
// Every value comes from the world as it is — the ports in the snapshot, the goods in THIS port's
// market with their prices and the server's own advice, a quantity bounded by the hold, the purse
// and the stock. A picker that cannot offer an impossible value is worth more than a refusal that
// explains one.
//
// WHAT IS DELIBERATELY NOT HERE:
//   · No text input for an order. That was the thing the owner told me to remove.
//   · No fleet picker per argument: the fleet is chosen ONCE, on the screen above, because it is
//     what `cmd.issue(fleet_id, …)` is called with. Two places to answer "whose order is this?"
//     would be two authorities for one question.
//   · No legality check. `cmd.preview()` runs the real verb and rolls it back; this file only
//     bounds the pickers.

/** Display copy for the server's argument names. Copy only — the NAMES are the server's. */
const LABELS: Record<string, string> = {
  dest: 'Where to',
  via: 'Call on the way',
  good: 'Which good',
  qty: 'How much',
  limit: 'Price limit',
  mode: 'How much',
  days: 'Days of stores',
  count: 'How many hands',
  to_pct: 'Mend her to',
}

function labelOf(arg: VerbArg): string {
  return LABELS[arg.name] ?? arg.name
}

export function OrderComposer({
  verbs,
  spec,
  args,
  fleet,
  snapshot,
  port,
  market,
  routes,
  onChooseVerb,
  onSetArg,
}: {
  /** The composable verbs, already served by the world (CANCEL/CLEAR live on the queue). */
  verbs: readonly VerbSpec[]
  spec: VerbSpec | undefined
  args: Record<string, string>
  fleet: FleetView | undefined
  snapshot: WorldSnapshot
  /** Where the order will happen — where she lies, or where she is bound (F.2). The screen already
   *  resolves it for the market read, so it is handed down rather than looked up a second time. */
  port: SnapshotPort | null
  /** The market of the port this fleet is in (or bound for). Undefined until it has been read. */
  market: MarketView | undefined
  /** `world.trade_routes()` for that same port — ONE read for the whole goods list, fetched by the
   *  screen beside the market. Undefined while it is in flight. */
  routes: TradeRoutes | undefined
  onChooseVerb: (verb: string | null) => void
  onSetArg: (name: string, value: string | null) => void
}) {
  // WHICH PICKER IS OPEN IS DERIVED, NOT REMEMBERED. The open one is simply the next question the
  // order still needs — so choosing a verb opens its first question, answering one advances to the
  // next, and a complete order closes up, with no effect and no state to fall out of step.
  //
  // `override` is only the player disagreeing with that: opening an optional argument by hand, or
  // folding a row away. It is discarded the moment they answer anything, and it is stamped with the
  // verb it was made under so a new verb starts clean.
  const [override, setOverride] = useState<{ verb: string; name: string | null } | null>(null)
  const auto = spec ? (missingArgs(spec, args)[0]?.name ?? null) : null
  const open = override && override.verb === spec?.verb ? override.name : auto

  const toggle = (name: string) => {
    if (!spec) return
    setOverride({ verb: spec.verb, name: open === name ? null : name })
  }

  // WHICH GOOD ROW IS UNFOLDED — ONE, AND IT IS HELD HERE RATHER THAN INSIDE THE LIST.
  //
  // The owner, 2026-08-23: "click a trade good → it unfolds showing how much I can buy, and more."
  // The fold's headline figure is `world.buy_capacity()`, and that is a ROUND TRIP — so it must be
  // asked for the OPEN row and no other, which means the open row has to be known where the hook
  // lives. A `useBuyCapacity` inside the row component would put seventy reads on the wire.
  //
  // It is stamped with the verb, like `override` above and for the same reason: a good inspected
  // under BUY is not still being inspected when the player switches to SELL. And it is only
  // meaningful while the good picker is the open argument — `open === 'good'` — so folding the
  // argument row away drops the inspection with no second piece of state to keep in step.
  const [inspect, setInspect] = useState<{ verb: string; good: string } | null>(null)
  const inspecting =
    inspect && open === 'good' && inspect.verb === spec?.verb ? inspect.good : null

  // WHICH PORT ROW THE PLAYER IS ON — the same shape as `inspect` above, one argument type over.
  //
  // A port row COMMITS on tap (unlike a good row, which unfolds), so on a phone the chart follows
  // the choice and this is never set. It is what a POINTER and a KEYBOARD can say that a thumb
  // cannot: running down the list names each harbour on the chart as you reach it. It is stamped
  // with the verb for the same reason `inspect` is — a port considered under SAIL is not still
  // being considered when the player switches verb.
  //
  // IT DOES NOT MOVE THE FRAME. Only the CHOICE frames the chart (see `chartPorts` below): a
  // picture that jumped as the pointer ran down twelve rows would be unreadable, and the reach law
  // has nothing to do with it — this is simply the difference between looking and choosing.
  const [consider, setConsider] = useState<{ verb: string; port: string } | null>(null)
  const considering = consider && consider.verb === spec?.verb ? consider.port : null

  const answer = (arg: VerbArg, value: string) => {
    onSetArg(arg.name, value)
    setOverride(null)
    // Choosing ENDS the looking. Without this, re-opening the good row later would unfold whatever
    // was last peeked at rather than the row that was actually chosen.
    setInspect(null)
    setConsider(null)
  }

  // FOUR ORDERS HAVE A SECOND HALF. BUY was the first — the goods on the left, her state on the
  // right — and the owner then asked for the same on the three verbs that are equally decisions
  // about the fleet: *"hire, repair, provision — I want fleet info like what is in buy."* The rail
  // itself decides what it prints for each (see ./FleetRail.tsx); this only decides whether the
  // composer lays out in two columns. SAIL and SELL still have no rail, and `hasRail` is the one
  // place that list is written.
  const buying = spec?.verb === 'BUY'
  const rail = railKind(spec?.verb)
  const railed = rail !== null

  // THE PORTS THIS ORDER IS ABOUT — read off the SERVER'S OWN SCHEMA, never off a list of argument
  // names typed here. SAIL declares `dest` and an optional `via`; a verb that one day declares a
  // third port argument gets it on the chart without an edit, which is the same rule the pickers
  // are built on (F.4: the grammar is served, not restated).
  //
  // They are what the chart RINGS and what it FRAMES, so the picture always holds both ends of the
  // decision: where she lies, and where this order would put her.
  const chartPorts = useMemo(() => {
    if (!spec) return []
    const codes = spec.args
      .filter((a) => a.type === 'port')
      .map((a) => args[a.name])
      .filter((code): code is string => code !== undefined && code !== '')
    return [...new Set(codes)]
  }, [spec, args])

  // ONE READING OF `world.buy_capacity()` PER COMPOSED ORDER, and it is made here.
  //
  // It used to be called inside `QtyArg`, which was the only consumer. The rail wants the same
  // answer — the same fleet, the same good, the same read — and two components calling the hook
  // would put TWO identical round trips on the wire for one question. So it is asked once, at the
  // top, and handed to both. (It is not a second authority either way; the server answers it. This
  // is about not asking twice.) `null` for anything but a BUY, which makes the hook idle.
  //
  // AND IT FOLLOWS THE ROW BEING LOOKED AT, NOT ONLY THE ONE CHOSEN. `focusGood` is the unfolded
  // row while the list is open and the chosen good otherwise, so ONE hook serves the fold, the
  // stepper and the rail — and the rail updates as the player reads down the list, which is the
  // whole point of putting her state beside the goods.
  const focusGood = inspecting ?? args.good ?? null
  const capacity = useBuyCapacity(buying ? (fleet?.id ?? null) : null, focusGood)

  // AND THE SAME ARRANGEMENT FOR THE BARGAIN (0022). Asked once, here; the RAIL draws the figures
  // and the WORKING PANE draws the act, both from this one answer. Idle unless this is a BUY with a
  // good in focus — a bargain is struck over a named good, at a named quay.
  const bargain = useHaggleState(buying ? (fleet?.id ?? null) : null, focusGood)
  // THE ACT IS ONLY EVER OVER THE CHOSEN GOOD. The rail may show the figures for a good that is
  // merely being INSPECTED, because figures are looking; `cmd.haggle` spends one of three tries a
  // day and is not. So the block draws only when the focus and the choice are the same good —
  // which also guarantees `bargain` above is the read for the good this block names.
  const buyingGood =
    buying && args.good && focusGood === args.good
      ? market?.goods.find((g) => g.code === args.good)
      : undefined

  return (
    <div className="space-y-4">
      <div>
        <SectionLabel>What she is to do</SectionLabel>
        {/* THE ACTION CARD (docs/UI_DIRECTION.md §2). These were six text chips in a row, which is
            a menu — the reference draws an action as a CARD carrying its own mark and a line of
            what it does, so the choice is legible before it is made.

            THE CARD IS A CONTROL, NOT A PARAGRAPH (the owner, 2026-08-22: "MAKE An order - Command.
            too much unncessary info. So is Sail, Sell, Hire etc. Too long explanation. this is a
            game, make it so."). The VERB is the hero — set at `text-base`, which is larger than
            anything else on the tile — the mark rides beside it, and `spec.help` is one dim line
            under it. Migrations 0020 and then 0021 cut those strings for exactly this slot: 85-242
            characters became 33-43, and the mechanics they used to carry moved into `spec.note`,
            which the ⓘ under the grid prints and the card never does. The clamp stays at two lines
            anyway, because the card must not become a paragraph again the day a verb is added with
            a longer line — the card is a fixed shape and the dot is where prose goes.

            THE LINE IS `spec.help`, WHICH THE SERVER ALREADY SERVES. Nothing is authored here: add
            a verb to the chain and its card appears, with its own sentence, without an edit (F.4).
            The mark is the one presentational thing this file adds, and a verb with no mark in the
            table still draws — with its initial — rather than breaking the grid.

            THREE ACROSS FROM `sm`. Six verbs are three rows of two on a phone and two rows of three
            on anything wider, so the grid never leaves a card stranded on a line of its own. */}
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
          {verbs.map((v) => {
            const on = v.verb === spec?.verb
            const mark = VERB_ICON[v.verb]
            return (
              <button
                key={v.verb}
                type="button"
                onClick={() => onChooseVerb(on ? null : v.verb)}
                className={[
                  'bv-cut flex min-h-11 flex-col gap-1.5 border p-3 text-left transition',
                  on
                    ? 'border-accent bg-accent-soft'
                    : 'border-edge bg-surface-2 hover:border-accent/60',
                ].join(' ')}
              >
                <span className="flex items-center gap-2">
                  {mark ? (
                    <Icon
                      name={mark}
                      size={18}
                      className={`shrink-0 ${on ? 'text-accent' : 'text-ink-faint'}`}
                    />
                  ) : (
                    <span
                      className={`w-[18px] shrink-0 text-center font-mono text-base ${on ? 'text-accent' : 'text-ink-faint'}`}
                    >
                      {v.verb.slice(0, 1)}
                    </span>
                  )}
                  <span
                    className={`truncate font-mono text-base uppercase tracking-wide ${on ? 'text-accent' : 'text-ink'}`}
                  >
                    {v.verb}
                  </span>
                </span>
                <span className="line-clamp-2 text-[11px] leading-snug text-ink-faint">
                  {v.help}
                </span>
              </button>
            )
          })}
        </div>
      </div>

      {spec && (
        // ── THE ORDER ITSELF, AND — ON FIVE VERBS — WHAT IT IS A DECISION ABOUT BESIDE IT ─────
        // One column on a phone, two from `md` up (src/components/ui/screenLayout.ts). SELL keeps
        // the single column: neither a hold gauge nor a chart answers anything about it — what is
        // aboard is aboard, and the stepper states it in full.
        <div className={railed ? splitClass() : undefined}>
          {railed && (
            // FIGURES AND PICTURES ONLY IN HERE — see splitRailClass()'s header for why a sticky
            // rail may not carry a control, and why the rail is written BEFORE the pane it sits
            // beside (on a phone the working pane can be eleven thousand pixels tall).
            <aside className={splitRailClass()}>
              {rail === 'chart' ? (
                // ── SAIL: THE WORLD, NOT THE FLEET ─────────────────────────────────────────────
                // The owner, 2026-08-23: "sail — a small map + current location on the left side."
                // Choosing a destination from a list of names asks the player to hold a map in
                // their head. This is that map, and it is the Map tab's, drawn by the same modules.
                //
                // NOTHING IN THIS BLOCK IS TAPPABLE — not the chart (it takes no handler at all)
                // and not the ⓘ's contents. The destination is still chosen in the list beside it,
                // in words, because the map never accepts an order (docs/DESIGN.md §E.5).
                <div className="space-y-1" data-testid="sail-chart-rail">
                  <div className="flex flex-wrap items-center gap-x-1">
                    <SectionLabel className="mb-0">Where she is</SectionLabel>
                    <Explain label="the chart" panelClassName="w-full normal-case tracking-normal">
                      Her berth is the filled mark; a ring is a harbour this order would send her
                      to. The hairlines are the sea lanes — the water she can actually take. No line
                      is drawn between the two, because a straight one across this sheet is not the
                      passage and is not its length: Lisbon to Cádiz is 248 miles sailed against 188
                      as the gull flies, and the list beside this prints the sailed figure.
                    </Explain>
                  </div>
                  <SmallChart
                    ports={snapshot.ports}
                    legs={snapshot.legs}
                    // Just this fleet. The order is hers, and every other hull on the chart would
                    // be an answer to a question nobody asked here (the Map tab has the roster).
                    fleets={fleet ? [fleet] : []}
                    considering={chartPorts}
                    highlight={considering}
                    ariaLabel={`Chart showing where ${fleet?.name ?? 'the fleet'} lies and where this order would send her`}
                  />
                </div>
              ) : (
                <FleetRail
                  verb={spec.verb}
                  fleet={fleet}
                  port={port}
                  market={market}
                  config={snapshot.config}
                  goodCode={focusGood}
                  capacity={capacity}
                  bargain={bargain}
                />
              )}
            </aside>
          )}

          <div className={railed ? splitMainClass() : undefined}>
            {/* ⓘ IS `spec.note`, AND THE CARD IS `spec.help`. THIS IS THE CLIENT HALF OF 0021.
                A paragraph of `spec.help` stood here, so a chosen verb said the card's own sentence
                a second time within 200px — two renderings of one fact, and that was the copy to
                delete (docs/NO_SPAGHETTI.md §5). But deleting it alone would have LOST the fine
                print, and a `help` string discloses real mechanics: the stepped book, ALL and HALF
                being counted when she reaches the quay, hands beyond the idle men costing two and a
                half times.

                Migration 0021 split the string for exactly this: `help` is one line for the card
                (33-43 characters now, was 85-242) and `note` is the fine print, and its self-assert
                proves six mechanics MOVED rather than were deleted. Its own type comment says the
                note "belongs behind the info dot, never on the card" — so this dot is where it
                lands, and until this line it was served and printed nowhere.

                `?? spec.help` because `note` is optional against a server older than 0021 — a
                client that blanked the dot on such a server would be losing the disclosure a second
                way. The row also gives the argument list the label it never had. */}
            <div className="mb-2 flex flex-wrap items-center gap-x-1">
              <SectionLabel className="mb-0">What {spec.verb} needs</SectionLabel>
              <Explain label={spec.verb} panelClassName="w-full normal-case tracking-normal">
                {spec.note ?? spec.help}
              </Explain>
            </div>
            <div className="space-y-2">
              {visibleArgs(spec, args).map((arg) => {
              const value = args[arg.name]
              const isOpen = open === arg.name
              return (
                <div key={arg.name} className="rounded-md border border-edge bg-app p-3">
                  <div className="flex flex-wrap items-center gap-2">
                    <button
                      type="button"
                      onClick={() => toggle(arg.name)}
                      className="flex min-h-11 min-w-0 flex-1 items-center justify-between gap-3 text-left"
                      aria-expanded={isOpen}
                    >
                      <span className="min-w-0">
                        <span className={fineClass('block uppercase tracking-wider')}>
                          {labelOf(arg)}
                          {!arg.required && <span className="ml-2 lowercase tracking-normal">optional</span>}
                        </span>
                        <span className="block text-sm text-ink">
                          {value === undefined ? (
                            <span className="text-ink-faint">not chosen yet</span>
                          ) : (
                            describe(arg, value, snapshot, market)
                          )}
                        </span>
                      </span>
                      {/* OPEN IS A MARK, CLOSED IS A WORD, and the asymmetry is deliberate: a
                          closed row still has something to SAY — "choose" or "change", i.e.
                          whether this argument has been answered — while an open one only has to
                          point. So the open state is the design system's chevron turned down, the
                          same glyph and the same `rotate-90` Collapsible.tsx:92 uses for a fold,
                          instead of the literal ▾ this used to print: the one typographic
                          character on the screen pretending to be an icon. */}
                      <span aria-hidden className="flex shrink-0 items-center font-mono text-xs text-accent">
                        {isOpen ? (
                          <Icon name="chevron" size={14} className="rotate-90" />
                        ) : value === undefined ? (
                          'choose'
                        ) : (
                          'change'
                        )}
                      </span>
                    </button>
                    {value !== undefined && !arg.required && (
                      <Button
                        variant="ghost"
                        size="icon"
                        aria-label={`Leave ${labelOf(arg)} out`}
                        onClick={() => onSetArg(arg.name, null)}
                      >
                        {/* The dismiss mark is `close` from the icon set, drawn at the same 14px
                            as every other dismiss in the app (MapPanel.tsx:99). It was a literal ✕,
                            which is a different X at a different weight in every font a phone
                            might fall back to. */}
                        <Icon name="close" size={14} />
                      </Button>
                    )}
                  </div>

                  {isOpen && (
                    // The row above already names what is being chosen; repeating it over the
                    // picker cost a line of a phone screen and said nothing.
                    <div className="mt-3 space-y-2 border-t border-edge pt-3">
                      <ArgPicker
                        spec={spec}
                        arg={arg}
                        args={args}
                        fleet={fleet}
                        snapshot={snapshot}
                        market={market}
                        routes={routes}
                        capacity={capacity}
                        inspecting={inspecting}
                        onInspect={(code) =>
                          setInspect(spec && code ? { verb: spec.verb, good: code } : null)
                        }
                        onConsider={(code) =>
                          setConsider(spec && code ? { verb: spec.verb, port: code } : null)
                        }
                        onPick={(v) => answer(arg, v)}
                      />
                    </div>
                  )}
                </div>
              )
              })}
            </div>

            {/* THE ACT LIVES IN THE WORKING PANE, under the quantity stepper. The figures are in
                the rail; the button may never be, because the rail is sticky and a sticky panel
                taller than the viewport hides its own foot (screenLayout.ts, CORE_REUSE §1.5). */}
            <HaggleBlock fleetId={fleet?.id ?? null} good={buyingGood} read={bargain} />
          </div>
        </div>
      )}
    </div>
  )
}

/** What a chosen value reads as on the closed row: the name, not the token. */
function describe(
  arg: VerbArg,
  value: string,
  snapshot: WorldSnapshot,
  market: MarketView | undefined,
): string {
  if (arg.type === 'port') {
    const port = snapshot.ports.find((p) => p.code === value)
    return port ? `${port.name} (${port.code})` : value
  }
  if (arg.type === 'good') {
    const good = market?.goods.find((g) => g.code === value) ?? snapshot.goods.find((g) => g.code === value)
    return good ? `${good.name} (${value})` : value
  }
  if (arg.type === 'qty') {
    return /^[0-9]+$/.test(value) ? formatTuns(Number(value)) : value
  }
  return value
}

/**
 * HOW MUCH — the one picker whose ceiling comes from the server.
 *
 * Selling is arithmetic the client can do honestly: what is aboard is aboard. BUYING is not — the
 * price climbs as the order walks the book (§G.2), so a ceiling divided out of the spot price
 * offers more than the purse can carry. That is exactly what happened: MAX offered 91 tuns of
 * pepper and the trade was refused at 8,130 against 8,000. So the buy ceiling is world.buy_capacity().
 *
 * THE ANSWER IS HANDED IN, NOT ASKED FOR HERE. This component used to call `useBuyCapacity` itself,
 * which was fine while it was the only consumer; the rail now shows the same ceiling and the same
 * estimate, and two hooks for one question means two identical round trips. `OrderComposer` asks
 * once and passes the state to both. (Not a spaghetti fix — there was only ever one authority, the
 * server — a duplicate-request fix.)
 */
function QtyArg({
  selling,
  fleet,
  goodCode,
  step,
  value,
  capacity,
  onPick,
}: {
  selling: boolean
  fleet: FleetView | undefined
  goodCode: string | null
  step: number
  value: string | undefined
  /** The composer's reading of `world.buy_capacity()`. Idle on a SELL, which never consults it. */
  capacity: BuyCapacityState
  onPick: (value: string) => void
}) {
  if (!goodCode) {
    return <Notice tone="neutral" className="text-xs">Pick the good first — how much depends on which.</Notice>
  }
  if (selling) {
    return (
      <QtyPicker
        bound={sellBound(fleet ? (fleetCargoByCode(fleet)[goodCode] ?? 0) : 0)}
        step={step}
        value={value}
        onPick={onPick}
      />
    )
  }
  if (!capacity.bound) {
    return (
      <p className="font-mono text-xs text-ink-faint">
        {capacity.loading ? 'Asking what she can carry and afford…' : 'The most she can take on is not known yet.'}
      </p>
    )
  }
  // The MONEY is not passed on: `capacity.estTotal` is printed by the fleet rail, under a label and
  // beside the price of the first step. See QtyPicker's header for the measurement.
  return <QtyPicker bound={capacity.bound} step={step} value={value} onPick={onPick} />
}

/**
 * The picker for one argument, chosen by the TYPE the server declared for it. A type this screen
 * has never seen says so, plainly, instead of quietly offering nothing.
 */
function ArgPicker({
  spec,
  arg,
  args,
  fleet,
  snapshot,
  market,
  routes,
  capacity,
  inspecting,
  onInspect,
  onConsider,
  onPick,
}: {
  spec: VerbSpec
  arg: VerbArg
  args: Record<string, string>
  fleet: FleetView | undefined
  snapshot: WorldSnapshot
  market: MarketView | undefined
  /** `world.trade_routes()` for this port; only the `good` arm consults it. */
  routes: TradeRoutes | undefined
  /** The composer's ONE reading of `world.buy_capacity()` — the `qty` arm draws its ceiling from
   *  it, and the `good` arm's unfolded row draws the same answer for the row being looked at. */
  capacity: BuyCapacityState
  /** The unfolded good row, and how to move it. Only the `good` arm has anything to unfold. */
  inspecting: string | null
  onInspect: (code: string | null) => void
  /** The port row a pointer or the keyboard is ON. Only the `port` arm raises it — it names that
   *  harbour on SAIL's chart while the player runs down the list, and it chooses nothing. */
  onConsider: (code: string | null) => void
  onPick: (value: string) => void
}) {
  const selling = spec.verb === 'SELL'

  switch (arg.type) {
    case 'port':
      return (
        <PortPicker
          ports={snapshot.ports}
          legs={snapshot.legs}
          // Where she IS, or is bound — one answer, from the fleet section. A SAIL composed at sea
          // leaves from the port she is arriving at, so that is the port the legs are measured from.
          origin={fleet ? fleetPortCode(fleet) : null}
          value={args[arg.name]}
          onPick={onPick}
          onConsider={onConsider}
        />
      )

    case 'good': {
      if (!market) return <MarketPending />
      return (
        <GoodPicker
          goods={market.goods}
          value={args[arg.name]}
          onPick={onPick}
          intent={selling ? 'sell' : 'buy'}
          aboard={selling && fleet ? fleetCargoByCode(fleet) : undefined}
          inspecting={inspecting}
          onInspect={onInspect}
          capacity={capacity}
          routes={routes}
        />
      )
    }

    case 'qty':
      // Still its own component, because a BUY ceiling is a different question from a SELL one and
      // the two answers are drawn differently. It no longer holds the hook — the composer does.
      return (
        <QtyArg
          selling={selling}
          fleet={fleet}
          goodCode={args.good ?? null}
          step={snapshot.config.trade_step_tuns}
          value={args[arg.name]}
          capacity={capacity}
          onPick={onPick}
        />
      )

    case 'price': {
      const row = market?.goods.find((g) => g.code === args.good)
      if (!row) return <MarketPending />
      return (
        <PricePicker
          reference={selling ? row.sell : row.buy}
          op={arg.op}
          value={args[arg.name]}
          onPick={onPick}
        />
      )
    }

    case 'enum':
      return <EnumPicker values={arg.values ?? []} value={args[arg.name]} onPick={onPick} />

    case 'number':
      return <BoundedNumber arg={arg} fleet={fleet} value={args[arg.name]} onPick={onPick} />

    default:
      return (
        <Notice tone="warning" className="text-xs">
          The server declares this argument as <span className="font-mono">{arg.type}</span>, which this
          screen has no picker for yet. It is left out of the order rather than guessed at.
        </Notice>
      )
  }
}

function MarketPending() {
  return (
    <p className="font-mono text-xs text-ink-faint">
      Reading this port's market…
    </p>
  )
}

/**
 * A number, bounded by what the fleet can actually take. Each bound mirrors the refusal the server
 * would otherwise raise (0007): berths for HIRE (E_CREW_MAX), a hull that cannot be mended past
 * whole, days of stores that fit the hold. These bound a SLIDER; they do not decide anything.
 */
function BoundedNumber({
  arg,
  fleet,
  value,
  onPick,
}: {
  arg: VerbArg
  fleet: FleetView | undefined
  value: string | undefined
  onPick: (value: string) => void
}) {
  if (arg.name === 'count') {
    const crew = fleet ? fleetCrew(fleet) : null
    const berths = crew?.berths ?? 0
    const short = crew?.short ?? 0
    if (berths <= 0) {
      return <Notice tone="neutral" className="text-xs">Every berth in this fleet is filled.</Notice>
    }
    const suggestions = [...new Set([short, 4, 8, 12, 20, 40, berths].filter((n) => n > 0))].sort((a, b) => a - b)
    return (
      <div className="space-y-2">
        {short > 0 && (
          <p className="flex flex-wrap items-center gap-2 text-xs text-ink-muted">
            <Badge tone="warning">short</Badge>
            she is {short} hands under her required crew.
          </p>
        )}
        <NumberPicker min={1} max={berths} step={1} suggestions={suggestions} unit="hands" value={value} onPick={onPick} />
      </div>
    )
  }

  if (arg.name === 'to_pct') {
    // A fleet with no hulls reads 100%: `worstHullFraction` returns 1 for an empty roster, which is
    // the same floor the deleted `hullPct` kept, arrived at once instead of twice.
    const now = Math.round((fleet ? worstHullFraction(fleet) : 1) * 100)
    return (
      <div className="space-y-2">
        <p className="text-xs text-ink-muted">Her worst hull stands at {now}%.</p>
        <NumberPicker min={Math.min(now + 1, 100)} max={100} step={5} suggestions={[80, 90, 100]} unit="%" value={value} onPick={onPick} />
      </div>
    )
  }

  if (arg.name === 'days') {
    return <NumberPicker min={1} max={120} step={5} suggestions={[15, 30, 45, 60, 90]} unit="days" value={value} onPick={onPick} />
  }

  return <NumberPicker min={1} max={100} step={1} suggestions={[1, 2, 3, 4]} value={value} onPick={onPick} />
}

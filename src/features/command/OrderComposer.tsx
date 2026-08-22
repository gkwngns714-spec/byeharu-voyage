import { useState } from 'react'
import { Badge, Button, Icon, Notice, SectionLabel } from '../../components/ui'
import { VERB_ICON } from './verbIcons'
import { formatTuns } from '../../lib/format'
import type { FleetView, MarketView, VerbArg, VerbSpec, WorldSnapshot } from '../../lib/rpc'
import { EnumPicker, GoodPicker, NumberPicker, PortPicker, PricePicker, QtyPicker } from './ArgPickers'
import { useBuyCapacity } from './useBuyCapacity'
import {
  cargoAboard,
  cargoManifest,
  crewBerths,
  crewShort,
  hullPct,
  sellBound,
} from './fleetLimits'
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
  market,
  onChooseVerb,
  onSetArg,
}: {
  /** The composable verbs, already served by the world (CANCEL/CLEAR live on the queue). */
  verbs: readonly VerbSpec[]
  spec: VerbSpec | undefined
  args: Record<string, string>
  fleet: FleetView | undefined
  snapshot: WorldSnapshot
  /** The market of the port this fleet is in (or bound for). Undefined until it has been read. */
  market: MarketView | undefined
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

  const answer = (arg: VerbArg, value: string) => {
    onSetArg(arg.name, value)
    setOverride(null)
  }

  return (
    <div className="space-y-4">
      <div>
        <SectionLabel>What she is to do</SectionLabel>
        {/* THE ACTION CARD (docs/UI_DIRECTION.md §2). These were six text chips in a row, which is
            a menu — the reference draws an action as a CARD carrying its own mark and a line of
            what it does, so the choice is legible before it is made.
            
            THE LINE IS `spec.help`, WHICH THE SERVER ALREADY SERVES. It used to appear only AFTER
            a verb was chosen, which is the wrong side of the decision. Nothing is authored here:
            add a verb to the chain and its card appears, with its own sentence, without an edit
            (F.4). The mark is the one presentational thing this file adds, and a verb with no mark
            in the table still draws — with its initial — rather than breaking the grid. */}
        <div className="grid grid-cols-2 gap-2">
          {verbs.map((v) => {
            const on = v.verb === spec?.verb
            const mark = VERB_ICON[v.verb]
            return (
              <button
                key={v.verb}
                type="button"
                onClick={() => onChooseVerb(on ? null : v.verb)}
                className={[
                  'bv-cut flex min-h-11 flex-col gap-1 border p-2.5 text-left transition',
                  on
                    ? 'border-accent bg-accent-soft'
                    : 'border-edge bg-surface-2 hover:border-accent/60',
                ].join(' ')}
              >
                <span className="flex items-center gap-2">
                  {mark ? (
                    <Icon
                      name={mark}
                      size={16}
                      className={on ? 'text-accent' : 'text-ink-faint'}
                    />
                  ) : (
                    <span
                      className={`w-4 text-center font-mono text-xs ${on ? 'text-accent' : 'text-ink-faint'}`}
                    >
                      {v.verb.slice(0, 1)}
                    </span>
                  )}
                  <span
                    className={`font-mono text-xs uppercase tracking-wider ${on ? 'text-accent' : 'text-ink'}`}
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
        <>
          <p className="text-sm text-ink-muted">{spec.help}</p>
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
                        <span className="block font-mono text-[11px] uppercase tracking-wider text-ink-faint">
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
                        onPick={(v) => answer(arg, v)}
                      />
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        </>
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
 */
function QtyArg({
  selling,
  fleet,
  goodCode,
  step,
  value,
  onPick,
}: {
  selling: boolean
  fleet: FleetView | undefined
  goodCode: string | null
  step: number
  value: string | undefined
  onPick: (value: string) => void
}) {
  const capacity = useBuyCapacity(selling ? null : (fleet?.id ?? null), goodCode)

  if (!goodCode) {
    return <Notice tone="neutral" className="text-xs">Pick the good first — how much depends on which.</Notice>
  }
  if (selling) {
    return (
      <QtyPicker
        bound={sellBound(cargoAboard(fleet, goodCode))}
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
  return (
    <QtyPicker
      bound={capacity.bound}
      step={step}
      value={value}
      onPick={onPick}
      estTotal={capacity.estTotal}
    />
  )
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
  onPick,
}: {
  spec: VerbSpec
  arg: VerbArg
  args: Record<string, string>
  fleet: FleetView | undefined
  snapshot: WorldSnapshot
  market: MarketView | undefined
  onPick: (value: string) => void
}) {
  const selling = spec.verb === 'SELL'

  switch (arg.type) {
    case 'port':
      return (
        <PortPicker
          ports={snapshot.ports}
          legs={snapshot.legs}
          origin={fleet?.port ?? fleet?.voyage?.to ?? null}
          value={args[arg.name]}
          onPick={onPick}
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
          aboard={selling ? cargoManifest(fleet) : undefined}
        />
      )
    }

    case 'qty':
      // Its own component, because a BUY ceiling has to be ASKED FOR (the server prices the whole
      // stepped order), and a hook cannot be called from inside a switch.
      return (
        <QtyArg
          selling={selling}
          fleet={fleet}
          goodCode={args.good ?? null}
          step={snapshot.config.trade_step_tuns}
          value={args[arg.name]}
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
    const berths = crewBerths(fleet)
    const short = crewShort(fleet)
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
    const now = hullPct(fleet)
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

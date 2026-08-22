import { useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { Badge, Button, buttonClasses, categoryLabel, fineClass, goodIcon, Icon, Meter, PriceIndex } from '../../components/ui'
import { formatInt, formatNm, formatTuns, formatUnitPrice } from '../../lib/format'
// `haversineNm` is deliberately NOT imported any more: the only thing this file used it for was a
// destination's distance, and that number belongs to the server's leg (see PortPicker's header).
import type { MarketGood, SnapshotLeg, SnapshotPort } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import type { QtyBound } from './fleetLimits'

// THE PICKERS — one per argument TYPE the server's verb schema declares (`port`, `good`, `qty`,
// `number`, `price`, `enum`). Every one of them offers REAL options read out of the world, and
// every option is a row you tap. Nothing here accepts a typed order.
//
// THE ONE TEXT BOX IN THE WHOLE TAB is the port/good FILTER, and it composes nothing: it narrows
// a list of real rows, and the choice is still a tap. With 996 ports in the chain, a list without
// a filter is a list nobody can reach the bottom of.
//
// THE REACH LAW (CORE_REUSE 1.5): "an action may never live inside a region that can scroll or
// clip it." Every option here is an action, so no picker has a max-height and none of them
// scrolls. A long list is TRUNCATED instead — the rows that are shown are whole and pressable, and
// the screen says how many more the filter is hiding. A scroll box would have hidden them too, and
// less honestly.

/**
 * How many PORTS a list may render before it starts asking the player to narrow the filter.
 *
 * IT IS NOT A GENERAL LIST LENGTH, AND IT USED TO BE. The same twelve capped the goods list too,
 * which meant a market of 68 tradeable goods offered twelve and printed "56 more — narrow the
 * filter" — the owner, 2026-08-22: *"When buy, i want all the trade goods on left side."* Twelve of
 * sixty-eight is not all of them.
 *
 * The two lists are not the same question and that is why they no longer share an answer:
 *   · PORTS are the whole world — 214 today and 996 in an earlier chain — and no sort can put the
 *     one you mean near the top, so the FILTER is the way in and a cap is honest about that.
 *   · GOODS are one port's book. It is bounded by what this harbour actually trades, and the list
 *     is already sorted by the server's own `advice`, so the rows worth buying are at the top and
 *     the rest is the tail of a catalogue rather than a haystack. GoodPicker therefore renders
 *     every row it has, and keeps the filter for reaching one by name.
 */
const MAX_PORT_ROWS = 12

function PickerRow({
  onClick,
  selected,
  mark,
  left,
  right,
  hint,
  under,
}: {
  onClick: () => void
  selected: boolean
  /** A glyph at the head of the row. A good carries one (see GoodPicker); a port does not. */
  mark?: ReactNode
  left: ReactNode
  right?: ReactNode
  hint?: ReactNode
  under?: ReactNode
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      // ONE CONTROL, ONE RECIPE, in both states. This used to be hand-written with a note saying
      // it was waiting on a soft-selected variant: the OFF arm was character for character the
      // design system's `chip`, but the ON arm could not be `chip-on` — a picker row is a
      // full-width ROW carrying a badge, a %NBR pill and a stock meter, and `chip-on`'s solid
      // brass swallows all three. `chip-soft` (buttonStyles.ts) is that variant, and it is the
      // same soft tint TabRow uses for a selected face, so a selected row and a selected tab
      // cannot drift apart.
      className={buttonClasses(
        selected ? 'chip-soft' : 'chip',
        'md',
        'flex w-full flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2 text-left',
      )}
    >
      {mark}
      <span className="min-w-0 flex-1">
        <span className="block text-sm">{left}</span>
        {hint && <span className={fineClass('block')}>{hint}</span>}
      </span>
      {right && <span className="shrink-0 font-mono text-xs text-ink-muted">{right}</span>}
      {under && <span className="w-full">{under}</span>}
    </button>
  )
}

function FilterBox({
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

function TruncationNote({ hidden }: { hidden: number }) {
  if (hidden <= 0) return null
  return (
    <p className={fineClass()}>
      {hidden} more — narrow the filter to bring them into reach.
    </p>
  )
}

// ── port ───────────────────────────────────────────────────────────────────────────────────────

/**
 * Somewhere to sail. Ports one leg away come first — the authored leg graph is what a voyage is
 * routed over (D.1), so a one-leg destination is the difference between a passage and a haul.
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════
 * THE DISTANCE IS THE SERVER'S SAILED LEG. IT USED TO BE A STRAIGHT LINE, AND IT WAS SHORT.
 * ═══════════════════════════════════════════════════════════════════════════════════════════════
 * This picker called `haversineNm(here, there)` while `legs` — which carries the real sailed `nm`,
 * the one the voyage is costed and timed on — was already in the same `useMemo`. Measured in the
 * running game, same instant, same fleet lying at Lisbon:
 *
 *     destination   this picker   the server
 *     Porto             149 nm        195 nm
 *     Seville           169 nm        286 nm   (+69%)
 *     Cádiz             188 nm        248 nm
 *
 * 188 against 248 for Lisbon → Cádiz is precisely the Cape St Vincent detour that the water-raster
 * world generation exists to produce (docs/WORLD_DATA.md §7): a great circle sails through Iberia
 * and no ship does. The number was wrong on every row and it also drove the SORT, so "nearest
 * first" was not nearest — it was "shortest as the gull flies", which is a different list.
 *
 * WHERE THERE IS NO DIRECT LEG, THERE IS NO NUMBER. `world.snapshot()` serves the leg graph and
 * nothing else about distance; a multi-leg passage is routed by `voyage.route` INSIDE the server
 * and is not on the RPC surface, so the client cannot know what it is worth. Substituting a great
 * circle there would put back the exact lie this comment records, on the rows where it is worst
 * (a Lisbon → Aden straight line is under half the real passage round the Cape). So those rows
 * print no distance and the list says why. A number that is wrong is worse than a dash.
 *
 * WHAT THAT COSTS THE SORT, honestly: only the one-leg rows can be ordered by distance. The rest
 * fall back to region and name — the same grouping the Market tab's port list uses — which is at
 * least a stable, readable order rather than a false ranking. `SAIL`'s own preview names the real
 * figure the moment a destination is picked (PreviewPanel's `distance` row), so the number is one
 * tap away and it comes from the server.
 */
export function PortPicker({
  ports,
  legs,
  origin,
  value,
  onPick,
}: {
  ports: readonly SnapshotPort[]
  legs: readonly SnapshotLeg[]
  /** The port CODE the fleet is at (or bound for). Null when it is not known. */
  origin: string | null
  value: string | undefined
  onPick: (code: string) => void
}) {
  const [filter, setFilter] = useState('')

  const rows = useMemo(() => {
    // ONE WALK OF THE LEG GRAPH, and it now yields the DISTANCE as well as the fact of a leg. The
    // old code built a `Set` of one-leg codes here and then computed the distance a second way; the
    // sailed `nm` was sitting on the very row it was throwing away.
    const legNm = new Map<string, number>()
    if (origin) {
      for (const leg of legs) {
        if (leg.from === origin) legNm.set(leg.to, leg.nm)
        else if (leg.to === origin) legNm.set(leg.from, leg.nm)
      }
    }
    const q = fold(filter.trim())
    return ports
      .filter((p) => p.code !== origin)
      .filter((p) => foldedMatch(q, p.name, p.code, p.country))
      .map((p) => ({ port: p, nm: legNm.get(p.code) ?? null }))
      .sort(
        (a, b) =>
          // One-leg destinations first, ordered by what she will actually sail. Everything else is
          // a routed passage whose length this side of the wire does not know, so it is grouped by
          // region and named — never ranked by a number that was invented to rank it.
          Number(b.nm !== null) - Number(a.nm !== null) ||
          (a.nm ?? 0) - (b.nm ?? 0) ||
          a.port.region.localeCompare(b.port.region) ||
          a.port.name.localeCompare(b.port.name),
      )
  }, [ports, legs, origin, filter])

  const shown = rows.slice(0, MAX_PORT_ROWS)
  const routed = shown.some((r) => r.nm === null)

  return (
    <div className="space-y-2">
      <FilterBox value={filter} onChange={setFilter} label="Filter ports by name or country" />
      {shown.length === 0 && (
        <p className="text-sm text-ink-muted">No port answers to that. Clear the filter to see them all.</p>
      )}
      {shown.map(({ port, nm }) => (
        <PickerRow
          key={port.code}
          selected={value === port.code}
          onClick={() => onPick(port.code)}
          left={
            <span className="flex flex-wrap items-center gap-2">
              {port.name}
              <span className={fineClass()}>{port.code}</span>
              {nm !== null && <Badge tone="accent">one leg</Badge>}
              {port.is_ice_closed && <Badge tone="warning">ice</Badge>}
            </span>
          }
          hint={`${port.country}${port.has_yard ? ' · yard' : ''}`}
          // The sailed leg, or a dash. Never a great circle — see this component's header for the
          // three measurements that dash replaces.
          right={nm === null ? <span className="text-ink-faint">—</span> : formatNm(nm)}
        />
      ))}
      {routed && (
        <p className={fineClass()}>
          A figure is the leg she would sail. A dash is a harbour with no direct leg from here — your
          navigator will take her round by others, and the real distance is named the moment you
          check the order.
        </p>
      )}
      <TruncationNote hidden={rows.length - shown.length} />
    </div>
  )
}

// ── good ───────────────────────────────────────────────────────────────────────────────────────

/**
 * What to trade, priced. E.4's whole reading room in a row: what it costs, what it fetches, how
 * that compares with the ports within 600 nm (%NBR), and the server's own buy/hold/sell advice —
 * so the choice is informed before it is made rather than explained after it.
 */
export function GoodPicker({
  goods,
  value,
  onPick,
  /** SELL only: tuns aboard by good code. When given, only what is aboard can be picked. */
  aboard,
  intent,
}: {
  goods: readonly MarketGood[]
  value: string | undefined
  onPick: (code: string) => void
  aboard?: Record<string, number>
  intent: 'buy' | 'sell'
}) {
  const [filter, setFilter] = useState('')

  const rows = useMemo(() => {
    const q = fold(filter.trim())
    return goods
      .filter((g) => g.available)
      .filter((g) => (aboard ? (aboard[g.code] ?? 0) > 0 : true))
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
      <FilterBox value={filter} onChange={setFilter} label="Filter goods by name or kind" />
      {shown.length > 0 && (
        <p className={fineClass()}>
          {shown.length} {shown.length === 1 ? 'good' : 'goods'}
          {aboard ? ' aboard and traded here' : ' traded here'}
          {filter.trim() ? ' answer to that filter' : ", the quay's own advice first"}
        </p>
      )}
      {shown.length === 0 && (
        <p className="text-sm text-ink-muted">
          {aboard
            ? 'This fleet is carrying nothing this port will trade.'
            : 'Nothing here answers to that.'}
        </p>
      )}
      {shown.map((g) => (
        <PickerRow
          key={g.code}
          selected={value === g.code}
          onClick={() => onPick(g.code)}
          // A MARK PER GOOD (the owner, 2026-08-22: "i want a picture or an icon for each trade
          // good"). The glyph comes from goodIcons.ts, which carries it on the CATEGORY axis
          // because there are seventy goods and no art in this repository — read that file's
          // header before reaching for a seventy-row table here.
          mark={<Icon name={goodIcon(g.code, g.category)} size={22} className="shrink-0 text-ink-faint" />}
          left={g.name}
          // THE NAME USED TO BE PRINTED TWICE. This slot held `g.code`, and the code is DERIVED
          // from the name ("Black Pepper" → "black-pepper"), so the row read "Black Pepper
          // black-pepper" and spent its second line saying nothing. The owner: "beside the name i
          // see again, a name repeated … i want beside the name show category of what the trade
          // good is in." Nothing is lost: the code is the parser's spelling, and the composed
          // order line above still shows it (CommandScreen's "What will be sent").
          hint={categoryLabel(g.category)}
          right={
            <Badge tone={g.advice === 'buy' ? 'success' : g.advice === 'sell' ? 'accent' : 'neutral'}>
              {g.advice}
            </Badge>
          }
          under={<GoodFigures good={g} aboard={aboard ? (aboard[g.code] ?? 0) : undefined} />}
        />
      ))}
    </div>
  )
}

/**
 * THE THREE FIGURES, EACH IN ITS OWN COLUMN — the owner, 2026-08-22: *"for each info - buy, sell,
 * 81% of neighbours i want a separate tab - graphics. bigger."*
 *
 * They used to be one run-on mono line under the name — `buy 7 d./t · sell 6 d./t · 81% of
 * neighbours` — at 11px, which is docs/UI_DIRECTION.md §1's second diagnosis exactly: prose where
 * the game wants a number. Rule 2 says **the number is the hero**, so each figure gets its own
 * column: the label small-caps, mono and dim; the figure bright and a clear size larger than it.
 *
 * THE UNIT RIDES SMALL BESIDE THE FIGURE rather than inside it. `formatUnitPrice` renders
 * "3,500 d./t", which at this size does not fit a third of a 390px row — and dropping the unit is
 * not an option (EVE's rule, §3: units are always attached). So the figure is the grouped number
 * and the unit is a 10px suffix, which is the same shape NumberPicker already uses for its
 * suggestion chips.
 *
 * %NBR IS <PriceIndex>, NOT A FOURTH RENDERING OF IT. The pill is the one treatment of that number
 * and its tone comes from the server's own `advice` (PriceIndex.tsx) — never from comparing `pct`
 * against a threshold here, because the thresholds live in migration 0009.
 */
function GoodFigures({ good, aboard }: { good: MarketGood; aboard: number | undefined }) {
  return (
    <span className="mt-1.5 grid gap-2">
      <span className="grid grid-cols-3 gap-2">
        <Figure label="buy" title="What she pays here, per tun">
          <span className="tabular-nums">{formatInt(good.buy)}</span>
          <span className="ml-1 text-[10px] font-normal text-ink-faint">d./t</span>
        </Figure>
        <Figure label="sell" title="What this port pays her, per tun">
          <span className="tabular-nums">{formatInt(good.sell)}</span>
          <span className="ml-1 text-[10px] font-normal text-ink-faint">d./t</span>
        </Figure>
        <Figure label="neighbours" title="This port's price as a percentage of the ports within 600 nm">
          <PriceIndex pct={good.pct_nbr} advice={good.advice} />
        </Figure>
      </span>
      <span className="flex items-center gap-2">
        <span className="shrink-0 font-mono text-[10px] uppercase tracking-wider text-ink-faint">stock</span>
        <Meter
          pct={(good.stock_band / 6) * 100}
          tone={good.stock_band >= 4 ? 'success' : 'warning'}
          className="min-w-0 flex-1"
        />
        {aboard !== undefined && (
          <span className="shrink-0 font-mono text-[11px] text-ink-muted">{formatTuns(aboard)} aboard</span>
        )}
      </span>
    </span>
  )
}

/** One labelled figure cell. Label above, figure below — never the other way round (rule 2). */
function Figure({ label, title, children }: { label: string; title: string; children: ReactNode }) {
  return (
    <span className="block min-w-0 rounded border border-edge/60 bg-app/40 px-2 py-1" title={title}>
      <span className="block truncate font-mono text-[10px] uppercase tracking-wider text-ink-faint">
        {label}
      </span>
      <span className="block truncate font-mono text-sm text-ink">{children}</span>
    </span>
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
        <button
          type="button"
          disabled={max <= 0}
          onClick={() => setNumber(max)}
          className={buttonClasses('chip', 'md', 'font-mono text-xs uppercase tracking-wider')}
        >
          max {formatInt(max)}
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

// ── number / price / enum ──────────────────────────────────────────────────────────────────────

/** A bounded whole number — crew, a repair percentage, days of stores. Never a free-form field. */
export function NumberPicker({
  min,
  max,
  step,
  suggestions,
  unit,
  value,
  onPick,
}: {
  min: number
  max: number
  step: number
  suggestions: readonly number[]
  unit?: string
  value: string | undefined
  onPick: (value: string) => void
}) {
  const numeric = value && /^[0-9]+$/.test(value) ? Number(value) : null
  const current = numeric ?? min
  const clamp = (n: number) => String(Math.max(min, Math.min(max, Math.round(n))))

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        {suggestions
          .filter((n) => n >= min && n <= max)
          .map((n) => (
            <button
              key={n}
              type="button"
              onClick={() => onPick(String(n))}
              // Another of the audit's hand-written chips. `md` already carries `text-sm`, so the
              // only thing this recipe still asks for by name is the mono face every figure wears.
              className={buttonClasses(numeric === n ? 'chip-on' : 'chip', 'md', 'font-mono')}
            >
              {n}
              {unit && <span className="ml-1 text-[11px] opacity-70">{unit}</span>}
            </button>
          ))}
      </div>
      {max > min && (
        <div className="flex items-center gap-2">
          {/* The same stepper pair as QtyPicker's, drawn the same way and for the same reasons —
              see the comment there for why both glyphs stay as text. */}
          <Button
            variant="chip"
            size="icon"
            aria-label="Less"
            onClick={() => onPick(clamp(current - step))}
            className="shrink-0 text-lg"
          >
            −
          </Button>
          <input
            type="range"
            min={min}
            max={max}
            step={step}
            value={current}
            aria-label={unit ?? 'Amount'}
            onChange={(e) => onPick(clamp(Number(e.target.value)))}
            className="h-11 min-w-0 flex-1 accent-accent"
          />
          <Button
            variant="chip"
            size="icon"
            aria-label="More"
            onClick={() => onPick(clamp(current + step))}
            className="shrink-0 text-lg"
          >
            +
          </Button>
        </div>
      )}
      <p className={fineClass()}>
        {formatInt(min)}–{formatInt(max)}
        {unit ? ` ${unit}` : ''} · now {numeric === null ? '—' : formatInt(numeric)}
      </p>
    </div>
  )
}

/** A price ceiling or floor. Offered around the market's own price, never as an empty box. */
export function PricePicker({
  reference,
  op,
  value,
  onPick,
}: {
  /** What the good costs (BUY) or fetches (SELL) right now. */
  reference: number
  op: string | undefined
  value: string | undefined
  onPick: (value: string) => void
}) {
  const offers = [0.9, 0.95, 1, 1.05, 1.1].map((m) => Math.round(reference * m))
  const min = Math.max(1, Math.round(reference * 0.5))
  const max = Math.max(min + 1, Math.round(reference * 1.5))
  return (
    <div className="space-y-2">
      <p className={fineClass()}>
        the market is at {formatUnitPrice(reference)} · your limit {op ?? ''}
      </p>
      <NumberPicker
        min={min}
        max={max}
        step={Math.max(1, Math.round(reference / 50))}
        suggestions={offers}
        unit="d."
        value={value}
        onPick={onPick}
      />
    </div>
  )
}

/** One of a fixed set of words the server's schema itself names. */
export function EnumPicker({
  values,
  value,
  onPick,
}: {
  values: readonly string[]
  value: string | undefined
  onPick: (value: string) => void
}) {
  return (
    <div className="flex flex-wrap gap-2">
      {values.map((v) => (
        <button
          key={v}
          type="button"
          onClick={() => onPick(v)}
          // The last of the audit's hand-written chips in this file. Same recipe as QtyPicker's
          // ALL/HALF, which is the whole point: one word from the server's schema, drawn the one way.
          className={buttonClasses(
            value === v ? 'chip-on' : 'chip',
            'md',
            'font-mono text-xs uppercase tracking-wider',
          )}
        >
          {v}
        </button>
      ))}
    </div>
  )
}


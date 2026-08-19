import { useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { Badge, Meter } from '../../components/ui'
import { formatDucats, formatInt, formatNm, formatTuns, formatUnitPrice } from '../../lib/format'
import { haversineNm } from '../../lib/geo'
import type { MarketGood, SnapshotLeg, SnapshotPort } from '../../lib/rpc'
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

/** How many rows a list may render before it starts asking the player to narrow the filter. */
const MAX_ROWS = 12

/** Case- and accent-insensitive, the way the server's `cmd.fold()` matches a name. */
function fold(text: string): string {
  return text
    .normalize('NFD')
    .replace(new RegExp('[\\u0300-\\u036f]', 'g'), '')
    .toLowerCase()
}

function PickerRow({
  onClick,
  selected,
  left,
  right,
  hint,
  under,
}: {
  onClick: () => void
  selected: boolean
  left: ReactNode
  right?: ReactNode
  hint?: ReactNode
  under?: ReactNode
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={[
        'flex min-h-11 w-full flex-wrap items-center gap-x-3 gap-y-1 rounded-md border px-3 py-2 text-left transition',
        selected
          ? 'border-accent bg-accent-soft text-ink'
          : 'border-edge bg-surface-2 text-ink hover:border-accent/60',
      ].join(' ')}
    >
      <span className="min-w-0 flex-1">
        <span className="block text-sm">{left}</span>
        {hint && <span className="block font-mono text-[11px] text-ink-faint">{hint}</span>}
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
    <p className="font-mono text-[11px] text-ink-faint">
      {hidden} more — narrow the filter to bring them into reach.
    </p>
  )
}

// ── port ───────────────────────────────────────────────────────────────────────────────────────

/**
 * Somewhere to sail. Ports one leg away come first — the authored leg graph is what a voyage is
 * routed over (D.1), so a one-leg destination is the difference between a passage and a haul — and
 * the rest follow by great-circle distance from where the fleet is lying.
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
    const here = origin ? ports.find((p) => p.code === origin) : undefined
    const direct = new Set<string>()
    if (origin) {
      for (const leg of legs) {
        if (leg.from === origin) direct.add(leg.to)
        else if (leg.to === origin) direct.add(leg.from)
      }
    }
    const q = fold(filter.trim())
    return ports
      .filter((p) => p.code !== origin)
      .filter((p) => q === '' || fold(p.name).includes(q) || fold(p.code).includes(q) || fold(p.country).includes(q))
      .map((p) => ({
        port: p,
        direct: direct.has(p.code),
        nm: here ? haversineNm({ lat: here.lat, lon: here.lon }, { lat: p.lat, lon: p.lon }) : null,
      }))
      .sort(
        (a, b) =>
          Number(b.direct) - Number(a.direct) ||
          (a.nm ?? Infinity) - (b.nm ?? Infinity) ||
          a.port.name.localeCompare(b.port.name),
      )
  }, [ports, legs, origin, filter])

  const shown = rows.slice(0, MAX_ROWS)

  return (
    <div className="space-y-2">
      <FilterBox value={filter} onChange={setFilter} label="Filter ports by name or country" />
      {shown.length === 0 && (
        <p className="text-sm text-ink-muted">No port answers to that. Clear the filter to see them all.</p>
      )}
      {shown.map(({ port, direct, nm }) => (
        <PickerRow
          key={port.code}
          selected={value === port.code}
          onClick={() => onPick(port.code)}
          left={
            <span className="flex flex-wrap items-center gap-2">
              {port.name}
              <span className="font-mono text-[11px] text-ink-faint">{port.code}</span>
              {direct && <Badge tone="accent">one leg</Badge>}
              {port.is_ice_closed && <Badge tone="warning">ice</Badge>}
            </span>
          }
          hint={`${port.country}${port.has_yard ? ' · yard' : ''}`}
          right={nm === null ? undefined : formatNm(nm)}
        />
      ))}
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
      .filter((g) => q === '' || fold(g.name).includes(q) || fold(g.code).includes(q) || fold(g.category).includes(q))
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

  const shown = rows.slice(0, MAX_ROWS)

  return (
    <div className="space-y-2">
      <FilterBox value={filter} onChange={setFilter} label="Filter goods by name or kind" />
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
          left={
            <span className="flex flex-wrap items-center gap-2">
              {g.name}
              <span className="font-mono text-[11px] text-ink-faint">{g.code}</span>
              <Badge tone={g.advice === 'buy' ? 'success' : g.advice === 'sell' ? 'accent' : 'neutral'}>
                {g.advice}
              </Badge>
            </span>
          }
          hint={
            <>
              buy {formatUnitPrice(g.buy)} · sell {formatUnitPrice(g.sell)}
              {g.pct_nbr !== null && ` · ${Math.round(g.pct_nbr)}% of neighbours`}
              {aboard && ` · ${formatTuns(aboard[g.code] ?? 0)} aboard`}
            </>
          }
          under={<Meter pct={(g.stock_band / 6) * 100} tone={g.stock_band >= 4 ? 'success' : 'warning'} />}
        />
      ))}
      <TruncationNote hidden={rows.length - shown.length} />
    </div>
  )
}

// ── qty ────────────────────────────────────────────────────────────────────────────────────────

/**
 * A quantity, between nothing and what is actually possible. ALL and HALF are the server's own
 * tokens and are read when the order RUNS, not when it is made (F.2) — which is why they are
 * offered beside the slider rather than instead of it: a queued `SELL cloves ALL` sells whatever
 * arrived, and that is usually what a player means.
 */
export function QtyPicker({
  bound,
  step,
  value,
  onPick,
  estTotal,
}: {
  bound: QtyBound
  /** `config.trade_step_tuns` — the server reprices every step, so the stepper walks in them. */
  step: number
  value: string | undefined
  onPick: (value: string) => void
  /** What the server says the MAXIMUM would cost, at the stepped price. Buy side only. */
  estTotal?: number | null
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
        {(['ALL', 'HALF'] as const).map((token) => (
          <button
            key={token}
            type="button"
            onClick={() => onPick(token)}
            className={[
              'min-h-11 rounded-md border px-4 font-mono text-xs uppercase tracking-wider transition',
              value === token
                ? 'border-accent bg-accent text-app'
                : 'border-edge bg-surface-2 text-ink hover:border-accent/60',
            ].join(' ')}
          >
            {token}
          </button>
        ))}
        <button
          type="button"
          disabled={max <= 0}
          onClick={() => setNumber(max)}
          className="min-h-11 rounded-md border border-edge bg-surface-2 px-4 font-mono text-xs uppercase tracking-wider text-ink transition hover:border-accent/60 disabled:opacity-45"
        >
          max {formatInt(max)}
        </button>
      </div>

      {max > 0 && (
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <button
              type="button"
              aria-label={`Less by ${stepSize} tuns`}
              onClick={() => bump(-stepSize)}
              className="h-11 w-11 shrink-0 rounded-md border border-edge bg-surface-2 text-lg text-ink transition hover:border-accent/60"
            >
              −
            </button>
            <span
              className={`min-w-0 flex-1 text-center font-mono text-lg ${numeric === null ? 'text-ink-faint' : 'text-ink'}`}
            >
              {/* Nothing chosen yet still SHOWS the figure the stepper would land on, faintly —
                  a bare dash tells the player nothing about what + is about to do. */}
              {numeric === null ? (value ?? formatTuns(current)) : formatTuns(numeric)}
            </span>
            <button
              type="button"
              aria-label={`More by ${stepSize} tuns`}
              onClick={() => bump(stepSize)}
              className="h-11 w-11 shrink-0 rounded-md border border-edge bg-surface-2 text-lg text-ink transition hover:border-accent/60"
            >
              +
            </button>
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

      <p className="font-mono text-[11px] text-ink-faint">
        {max > 0
          ? `up to ${formatTuns(max)} — ${bound.binding} stops you there` +
            (estTotal ? ` (${formatDucats(estTotal)} for all of it)` : '')
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
              className={[
                'min-h-11 rounded-md border px-4 font-mono text-sm transition',
                numeric === n
                  ? 'border-accent bg-accent text-app'
                  : 'border-edge bg-surface-2 text-ink hover:border-accent/60',
              ].join(' ')}
            >
              {n}
              {unit && <span className="ml-1 text-[11px] opacity-70">{unit}</span>}
            </button>
          ))}
      </div>
      {max > min && (
        <div className="flex items-center gap-2">
          <button
            type="button"
            aria-label="Less"
            onClick={() => onPick(clamp(current - step))}
            className="h-11 w-11 shrink-0 rounded-md border border-edge bg-surface-2 text-lg text-ink transition hover:border-accent/60"
          >
            −
          </button>
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
          <button
            type="button"
            aria-label="More"
            onClick={() => onPick(clamp(current + step))}
            className="h-11 w-11 shrink-0 rounded-md border border-edge bg-surface-2 text-lg text-ink transition hover:border-accent/60"
          >
            +
          </button>
        </div>
      )}
      <p className="font-mono text-[11px] text-ink-faint">
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
      <p className="font-mono text-[11px] text-ink-faint">
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
          className={[
            'min-h-11 rounded-md border px-4 font-mono text-xs uppercase tracking-wider transition',
            value === v
              ? 'border-accent bg-accent text-app'
              : 'border-edge bg-surface-2 text-ink hover:border-accent/60',
          ].join(' ')}
        >
          {v}
        </button>
      ))}
    </div>
  )
}

/** A purse line, so a cost can be read against what there is. */
export function PurseLine({ ducats }: { ducats: number | null }) {
  if (ducats === null) return null
  return <span className="font-mono text-sm text-accent">{formatDucats(ducats)}</span>
}

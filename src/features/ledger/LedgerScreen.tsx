import { useMemo, useState } from 'react'
import {
  Badge,
  Card,
  EmptyState,
  Icon,
  Notice,
  PageHeader,
  Screen,
} from '../../components/ui'
import {
  formatClock,
  formatDucats,
  formatDucatsDelta,
  formatNm,
  formatRelative,
} from '../../lib/format'
import { useShellState } from '../../app/shellState'
import { useWorld } from '../../live/worldStore'
import type { LiveWorld } from '../../live/worldStore'
import type { LedgerEvent } from '../../lib/rpc'
import { ReadAgain, WorldFailed, WorldLoading } from '../fleets/worldGate'

// LEDGER — E.6. "The narrative organ of the game. This is where combat lives, as prose."
//
// TWO THINGS ARE TRUE OF THIS SCREEN AT ONCE, and both matter:
//
//   1. It is a LEDGER. Reverse-chronological, every row an immutable event, every money movement
//      carrying the balance it produced. I.4: "the Ledger is not a UI convenience — it is the
//      source of truth from which rank is computed."
//
//   2. It is the AFTER-ACTION REPORT. B.6: "Nothing here renders. Everything here writes." A storm
//      is not a bar that went down; it is a paragraph about a night under bare poles, and the hull
//      figure is a line UNDER the paragraph, not instead of it.
//
// No commands. No filters that hide money. Nothing animates except a newly-arrived line.
//
// ── THE BALANCE IS PRINTED, NEVER ADDED UP ──────────────────────────────────────────────────────
// The old screen said "the balance column runs: every entry is the one before it plus its own
// movement", and it could say that because a fixture had been written so it was true. IT IS NOT
// TRUE OF THE REAL CHAIN, and `tests/rpc.firstSession.spec.ts` asserts the gap: `WAGES` (and other
// costs) are credited through `public.credit()` with NO event behind them (migration 0007:855), so
// they move the purse and reconcile inside `ducats` while never appearing as a row here. Summing
// the visible rows does NOT give the purse.
//
// So this screen prints `balance_after` — the balance the SERVER recorded for that entry — and says
// out loud that the gaps between consecutive balances are the unrecorded costs. A running total
// computed on this side would be a second, wrong, authority for the player's money.
//
// ── THE VOCABULARY IS THE SERVER'S ──────────────────────────────────────────────────────────────
// FOUNDED · BOUGHT · SOLD · DEPARTED · VOYAGE_REPORT · PROVISIONED · HIRED · REPAIRING · REPAIRED.
// The fixture's TRADE / VOYAGE / PORT / MARKET kinds do not exist and are not translated into — a
// mapping layer would be a second name for every event. The filter chips are built FROM the kinds
// actually present in the page, so a migration that adds a kind needs no edit here.
//
// The headline is not served either (README §4.12): the client composes it from `kind` + `payload`,
// once, in `headline()` below. The prose report IS served — `payload.lines`, already sentences.

export function LedgerScreen() {
  const world = useWorld()

  if (world.phase === 'failed') {
    return <WorldFailed eyebrow="Record" title="Ledger" refusal={world.fatal} />
  }
  if (world.phase !== 'ready') {
    return (
      <WorldLoading
        eyebrow="Record"
        title="Ledger"
        subtitle="Everything that happened, in the order it happened."
        panels={4}
      />
    )
  }
  return <LedgerBody world={world} />
}

function LedgerBody({ world }: { world: LiveWorld }) {
  const { nowMs } = useShellState()
  const [filter, setFilter] = useState<string>('all')

  // `world.ledger()` already answers newest-first (0009: `order by e.created_at desc`). The screen
  // does not re-sort it: the server's order is the record's order.
  const events = world.events
  const kinds = useMemo(() => {
    const seen: string[] = []
    for (const e of events) if (!seen.includes(e.kind)) seen.push(e.kind)
    seen.sort()
    return ['all', ...seen]
  }, [events])

  const shown = filter === 'all' ? events : events.filter((e) => e.kind === filter)
  const portName = (code: string) => world.portByCode[code]?.name ?? code

  return (
    <Screen>
      <PageHeader
        eyebrow="Record"
        title="Ledger"
        explain="Everything that happened, in the order it happened. The ledger is the server's record, not a client log: it is the same one your standing is judged from."
        actions={
          <>
            <span className="font-mono text-sm text-accent">
              {world.ducats === null ? '—' : formatDucats(world.ducats)}
            </span>
            <ReadAgain world={world} />
          </>
        }
      />

      {events.length > 0 && (
        <Card>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex flex-wrap items-center gap-1.5">
              {kinds.map((k) => (
                <button
                  key={k}
                  type="button"
                  onClick={() => setFilter(k)}
                  className={[
                    'min-h-11 rounded-md px-3 font-mono text-xs uppercase tracking-wider transition',
                    k === filter
                      ? 'bg-accent text-app'
                      : 'border border-edge bg-surface-2 text-ink-muted hover:text-ink',
                  ].join(' ')}
                >
                  {k === 'all' ? 'all' : k.toLowerCase().replace('_', ' ')}
                </button>
              ))}
            </div>
            <div className="text-right font-mono text-[11px] text-ink-faint">
              <div>
                {shown.length} of {events.length} entries
              </div>
              {world.readAt !== null && <div>read {formatRelative(world.readAt, nowMs)}</div>}
            </div>
          </div>
        </Card>
      )}

      {events.length === 0 ? (
        <EmptyState
          icon={<Icon name="ledger" size={28} />}
          title="Nothing has happened yet"
          body="The log fills itself: found a house, buy a parcel, put to sea. Every one of those writes a line here."
        />
      ) : shown.length === 0 ? (
        <EmptyState icon={<Icon name="ledger" size={28} />} title="Nothing under that filter" />
      ) : (
        <div className="space-y-3">
          {shown.map((event) => (
            <Entry key={event.id} event={event} nowMs={nowMs} portName={portName} />
          ))}
        </div>
      )}

      {events.length > 0 && (
        <Notice tone="neutral" className="text-xs">
          Each entry prints the balance the server recorded for it. The purse now stands at{' '}
          {world.ducats === null ? 'an unread figure' : formatDucats(world.ducats)} — and it will
          NOT equal the sum of the movements above: wages are paid every voyage-day without writing
          an entry of their own, so a gap between two consecutive balances is a crew that has been
          paid.
        </Notice>
      )}
    </Screen>
  )
}

function Entry({
  event,
  nowMs,
  portName,
}: {
  event: LedgerEvent
  nowMs: number
  portName: (code: string) => string
}) {
  const atMs = Date.parse(event.at)
  const report = payloadLines(event.payload)
  const delta = event.ducats_delta
  const fleet = str(event.payload, 'fleet')

  return (
    <Card tone={report.length > 0 ? 'accent' : 'default'} className="bv-fade-in">
      <div className="mb-2 flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span className="font-mono text-xs text-ink-faint">
          {Number.isFinite(atMs) ? formatClock(atMs) : '--:--'}
        </span>
        {fleet && (
          <span className="font-mono text-xs uppercase tracking-wider text-ink">{fleet}</span>
        )}
        <Badge tone={kindTone(event.kind)}>{event.kind.replace('_', ' ')}</Badge>
        <span className="ml-auto font-mono text-[11px] text-ink-faint">
          {Number.isFinite(atMs) ? formatRelative(atMs, nowMs) : ''}
        </span>
      </div>

      <p className="font-serif text-base text-ink">{headline(event, portName)}</p>

      {report.length > 0 && (
        <div className="mt-3 space-y-3 border-l-2 border-accent/30 pl-3">
          {/* Served prose, already whole sentences ("Day 1. A quiet watch; nothing to report.") —
              the client neither parses the day out of them nor re-words them. Serif, larger,
              leading-relaxed: this is the one place in the game that is READING rather than
              scanning, and it is typeset to be read. */}
          {report.map((line, i) => (
            <p key={i} className="font-serif text-[15px] leading-relaxed text-ink-muted">
              {line}
            </p>
          ))}
        </div>
      )}

      <div className="mt-3 flex flex-wrap items-baseline justify-between gap-2 border-t border-edge pt-2">
        <span
          className={[
            'font-mono text-sm',
            delta === null || delta === 0
              ? 'text-ink-faint'
              : delta > 0
                ? 'text-success'
                : 'text-danger',
          ].join(' ')}
        >
          {delta === null ? 'no movement' : formatDucatsDelta(delta)}
        </span>
        <span className="font-mono text-xs text-ink-muted">
          {event.balance_after === null ? 'no balance recorded' : `balance ${formatDucats(event.balance_after)}`}
        </span>
      </div>
    </Card>
  )
}

// ── THE ONE HEADLINE COMPOSER ───────────────────────────────────────────────────────────────────
// One sentence per server kind, built from that kind's payload and nothing else. The payloads are
// written by `public.emit_event()` in migration 0007 and 0004 and are exactly:
//
//   FOUNDED       {company, port}                             (port is a CODE)
//   BOUGHT/SOLD   {fleet, good, qty, avg_price, total}        (good is the NAME)
//   DEPARTED      {fleet, voyage_id, total_nm, legs, eta}     (no destination in the payload)
//   VOYAGE_REPORT {fleet, voyage_id, from, to, total_nm, lines[]}   (from/to are CODES)
//   PROVISIONED   {fleet, water_t, food_t, cost}
//   HIRED         {fleet, count, urgent, cost}
//   REPAIRING     {fleet, points, cost, sim_hours}
//   REPAIRED      {fleet}
//
// An unknown kind falls through to the kind itself rather than to an invented sentence — a new
// migration's event shows up as a legible row on the day it lands, without lying about its content.

function headline(event: LedgerEvent, portName: (code: string) => string): string {
  const p = event.payload
  const fleet = str(p, 'fleet') ?? 'A fleet'

  switch (event.kind) {
    case 'FOUNDED': {
      const company = str(p, 'company') ?? 'The house'
      const port = str(p, 'port')
      return `${company} opens its books${port ? ` at ${portName(port)}` : ''}.`
    }
    case 'BOUGHT': {
      const qty = num(p, 'qty')
      const good = str(p, 'good') ?? 'cargo'
      const price = num(p, 'avg_price')
      return `${fleet} took aboard ${qty === null ? 'a parcel of' : formatQty(qty)} ${good}${
        price === null ? '' : ` at ${Math.round(price)} d. the tun`
      }.`
    }
    case 'SOLD': {
      const qty = num(p, 'qty')
      const good = str(p, 'good') ?? 'cargo'
      const price = num(p, 'avg_price')
      return `${fleet} sold ${qty === null ? 'a parcel of' : formatQty(qty)} ${good}${
        price === null ? '' : ` at ${Math.round(price)} d. the tun`
      }.`
    }
    case 'DEPARTED': {
      const nm = num(p, 'total_nm')
      const legs = num(p, 'legs')
      return `${fleet} put to sea${nm === null ? '' : ` — ${formatNm(nm)}`}${
        legs === null ? '' : ` over ${legs} leg${legs === 1 ? '' : 's'}`
      }.`
    }
    case 'VOYAGE_REPORT': {
      const from = str(p, 'from')
      const to = str(p, 'to')
      const nm = num(p, 'total_nm')
      const leg = from && to ? ` from ${portName(from)}` : ''
      return `${fleet} came in${to ? ` to ${portName(to)}` : ''}${leg}${
        nm === null ? '' : ` — ${formatNm(nm)} sailed`
      }.`
    }
    case 'PROVISIONED': {
      const water = num(p, 'water_t')
      const food = num(p, 'food_t')
      return `${fleet} watered and victualled${
        water === null || food === null ? '' : ` — ${water.toFixed(1)} t of water, ${food.toFixed(1)} t of food`
      }.`
    }
    case 'HIRED': {
      const count = num(p, 'count')
      const urgent = p['urgent'] === true || num(p, 'urgent') === 1
      return `${count === null ? 'Hands' : `${formatQty(count)} hands`} signed for ${fleet}${
        urgent ? ', at the urgent rate' : ''
      }.`
    }
    case 'REPAIRING': {
      const points = num(p, 'points')
      return `${fleet} went into the yard${points === null ? '' : ` for ${Math.round(points)} points of hull`}.`
    }
    case 'REPAIRED':
      return `${fleet} came out of the yard, sound again.`
    case 'WAGES':
      return `Wages paid to ${fleet}.`
    default:
      return `${fleet} · ${event.kind.toLowerCase().replace('_', ' ')}.`
  }
}

function kindTone(kind: string) {
  switch (kind) {
    case 'VOYAGE_REPORT':
    case 'DEPARTED':
      return 'accent' as const
    case 'SOLD':
    case 'FOUNDED':
      return 'success' as const
    case 'BOUGHT':
      return 'warning' as const
    case 'REPAIRING':
    case 'REPAIRED':
      return 'danger' as const
    default:
      return 'neutral' as const
  }
}

// ── PAYLOAD READERS ─────────────────────────────────────────────────────────────────────────────
// `payload` is `Record<string, unknown>` because it genuinely is: one jsonb column, a different
// shape per kind. These three readers are the only place this screen touches it, so a payload that
// is missing a key produces a shorter sentence rather than "undefined" on the page.

function str(payload: Record<string, unknown>, key: string): string | null {
  const v = payload[key]
  return typeof v === 'string' && v !== '' ? v : null
}

/** jsonb numerics can arrive as a JSON number or as a string, depending on the transport. */
function num(payload: Record<string, unknown>, key: string): number | null {
  const v = payload[key]
  if (typeof v === 'number') return Number.isFinite(v) ? v : null
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v)
    return Number.isFinite(n) ? n : null
  }
  return null
}

/** The after-action prose: `string[]`, composed server-side by `voyage.report_line()`. */
function payloadLines(payload: Record<string, unknown>): string[] {
  const v = payload['lines']
  return Array.isArray(v) ? v.filter((line): line is string => typeof line === 'string') : []
}

/** A whole-number count reads as a count; a fractional one keeps its tenth. */
function formatQty(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(1)
}

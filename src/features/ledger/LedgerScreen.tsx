import { useMemo, useState } from 'react'
import {
  Badge,
  buttonClasses,
  Card,
  EmptyState,
  Explain,
  Icon,
  Notice,
  PageHeader,
  Screen,
  fineClass,
  headRowClass,
} from '../../components/ui'
import {
  formatClock,
  formatDucats,
  formatDucatsDelta,
  formatInt,
  formatNm,
  formatPctPoints,
  formatRelative,
} from '../../lib/format'
import { useShellState } from '../../app/shellState'
// THE ONE READER OF A JSONB FIELD (2026-08-23). `num`/`str` were declared here AND in
// features/command/PreviewPanel.tsx, and they had already drifted; docs/NO_SPAGHETTI.md §2 listed
// the pair as debt to fold. See src/lib/json.ts for why the stronger version is the one that
// survived — this screen's behaviour is unchanged by the move.
import { num, str } from '../../lib/json'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { LedgerEvent } from '../../lib/rpc'
import { ReadAgain, WorldFailed, WorldLoading } from '../../live/WorldGate'

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
// FOUNDED · BOUGHT · SOLD · DEPARTED · VOYAGE_REPORT · PROVISIONED · HIRED · REPAIRING · REPAIRED
// · SIGNED_OFFICER · STUDIED. The fixture's TRADE / VOYAGE / PORT / MARKET kinds do not exist and
// are not translated into — a mapping layer would be a second name for every event. The filter
// chips are built FROM the kinds actually present in the page, so a migration that adds a kind
// needs no edit here.
//
// A kind is spelled for a human in exactly ONE place, `kindWords()` below. It used to be written
// three times — the filter chip, the badge and the fallback headline — each with
// `.replace('_', ' ')`, which replaces the FIRST underscore only. Nothing has three words in it
// today, so all three copies agreed and none of them was right.
//
// The headline is not served either (README §4.12): the client composes it from `kind` + `payload`,
// once, in `headline()` below. The prose report IS served — `payload.lines`, already sentences.

export function LedgerScreen() {
  // FIELDS, NOT THE STORE (worldStore.ts rule 4). The Ledger is the screen that made the rule: it
  // is the longest list in the game and it re-rendered whole, twice, on every read — and reading
  // is how time passes here, so that is every few seconds while the tab is open.
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)

  if (phase === 'failed') {
    return <WorldFailed eyebrow="Record" title="Ledger" refusal={fatal} />
  }
  if (phase !== 'ready') {
    return (
      <WorldLoading
        eyebrow="Record"
        title="Ledger"
        subtitle="Everything that happened, in the order it happened."
        panels={4}
      />
    )
  }
  return <LedgerBody />
}

function LedgerBody() {
  const events = useWorld((s) => s.events)
  const portByCode = useWorld((s) => s.portByCode)
  const readAt = useWorld((s) => s.readAt)
  const ducats = useWorld((s) => s.ducats)
  const { nowMs } = useShellState()
  const [filter, setFilter] = useState<string>('all')

  // `world.ledger()` already answers newest-first (0009: `order by e.created_at desc`). The screen
  // does not re-sort it: the server's order is the record's order.
  const kinds = useMemo(() => {
    const seen: string[] = []
    for (const e of events) if (!seen.includes(e.kind)) seen.push(e.kind)
    seen.sort()
    return ['all', ...seen]
  }, [events])

  const shown = filter === 'all' ? events : events.filter((e) => e.kind === filter)
  // A CALLER, not a second author: `portNameOf` is the one reading of "what is this code called"
  // (worldStore.ts). This screen used to re-derive it, and so do five other screens — see the
  // note on `portNameOf` for the copies still to be folded.
  const portName = (code: string) => portNameOf(portByCode, code)

  return (
    <Screen>
      <PageHeader
        eyebrow="Record"
        title="Ledger"
        explain="Everything that happened, newest first. This is the server's record, not a client log — the same one your standing is judged from."
        /* The purse readout moved to the top bar (TopBar.tsx), where it is on screen on every tab
           instead of only this one. The balance still appears in this screen's prose, which is a
           different thing: a sentence that explains reconciliation, not a readout. */
        actions={<ReadAgain />}
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
                  // One of the twelve hand-written chip recipes the D12 audit found. It is the
                  // design system's `chip` variant now, so a filter chip here and a verb chip on
                  // Command cannot drift apart again.
                  className={buttonClasses(
                    k === filter ? 'chip-on' : 'chip',
                    'md',
                    'font-mono text-xs uppercase tracking-wider',
                  )}
                >
                  {k === 'all' ? 'all' : kindWords(k)}
                </button>
              ))}
            </div>
            <div className={fineClass('text-right')}>
              <div>
                {shown.length} of {events.length} entries
              </div>
              {readAt !== null && <div>read {formatRelative(readAt, nowMs)}</div>}
            </div>
          </div>
        </Card>
      )}

      {events.length === 0 ? (
        <EmptyState
          icon={<Icon name="ledger" size={28} />}
          title="Nothing has happened yet"
          body="Buy a parcel, put to sea — each writes a line here."
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

      {/* THE DISCLOSURE IS INTACT AND THE PARAGRAPH IS NOT. Fifty-five words stood at the foot of
          every ledger, permanently, to say two things: what the purse is, and that the rows do not
          add up to it. The first is live and stays printed; the second is a standing RULE about the
          record and goes behind the dot, which is what docs/UI_DIRECTION.md §4 rule 4 says a rule
          does. Nothing about wages was cut — it is one tap away instead of read three hundred
          times. */}
      {events.length > 0 && (
        <Notice tone="neutral" className="text-xs">
          {/* NO FULL STOP AFTER THE FIGURE: `formatDucats` already ends in "d.", and adding one
              printed "Purse 8,000 d.." — seen at 390px. An em dash carries the join instead. */}
          Purse {ducats === null ? '—' : formatDucats(ducats)} — the balances above will not sum to
          it.
          <Explain label="why the balances do not sum" dotClassName="ml-1">
            Each entry prints the balance the server recorded for it. Wages are paid every
            voyage-day without writing an entry of their own, so a gap between two consecutive
            balances is a crew that has been paid.
          </Explain>
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
      <div className={headRowClass(false)}>
        <span className="font-mono text-xs text-ink-faint">
          {Number.isFinite(atMs) ? formatClock(atMs) : '--:--'}
        </span>
        {fleet && (
          <span className="font-mono text-xs uppercase tracking-wider text-ink">{fleet}</span>
        )}
        {/* Badge upper-cases in CSS, so it takes the same lowercase words the chip does. */}
        <Badge tone={kindTone(event.kind)}>{kindWords(event.kind)}</Badge>
        <span className={fineClass('ml-auto')}>
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

      {/* THE DELTA IS THE HERO (docs/UI_DIRECTION.md rule 2). It used to be text-sm — the same
          size as the "balance" caption beside it — which made the one number a player scans a
          ledger FOR the same weight as the one they merely check. It is text-xl now, and the
          balance stays small: what changed is the news, what it stands at is the footnote.

          THE BALANCE IS STILL `balance_after`, NEVER A RUNNING TOTAL. WAGES move the purse without
          an event row, so summing the rows this screen renders does not reach the purse — the
          served balance is the only honest figure and the Notice below the feed says so. */}
      <div className="mt-3 flex flex-wrap items-baseline justify-between gap-2 border-t border-rule pt-2">
        <span
          className={[
            'font-mono text-xl',
            delta === null || delta === 0
              ? 'text-ink-faint'
              : delta > 0
                ? 'text-success'
                : 'text-danger',
          ].join(' ')}
        >
          {delta === null ? <span className="text-sm">no movement</span> : formatDucatsDelta(delta)}
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
//   SIGNED_OFFICER {officer, code, specialty, bonus_pct, cost}   (0015:231 — NO fleet key)
//   STUDIED       {skill, code, level, port, cost}               (0016:239 — port is a CODE)
//
// An unknown kind falls through to the kind itself rather than to an invented sentence — a new
// migration's event shows up as a legible row on the day it lands, without lying about its content.
//
// ── WHY THE FALLBACK NO LONGER SUPPLIES A SUBJECT ───────────────────────────────────────────────
// The last two kinds shipped without their half of this composer and fell to the default, which
// read `${fleet} · …` off a `fleet` that defaulted to "A fleet". So signing Bartolomeu Dias
// printed "A fleet · signed officer." — legible, and about a fleet that had nothing to do with it.
// NEITHER PAYLOAD CONTAINS A FLEET AT ALL: an officer signs with the HOUSE (0015 refuses to put an
// officer column on `fleets`), and a trade is learned by the CAPTAIN. So the fallback now names a
// fleet only when the payload names one, and the default that invented it is gone. The rule the
// header states is intact — an unknown kind still prints its own name — it just no longer prints
// somebody else's.

function headline(event: LedgerEvent, portName: (code: string) => string): string {
  const p = event.payload
  // The fallback for a payload that IS about a fleet and has lost the key. Not read by the
  // default branch: see the note above.
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
    // A STANDING ORDER THAT COULD NOT RUN IS AN EVENT, not a silence. 0034 writes this row when a
    // fleet makes port under a preset and the purse or the hold cannot carry it — and the whole
    // reason the server writes it rather than shrugging is so the player can find out WHY their
    // ship is under-provisioned. Rendering it through the generic fallback ("provision refused")
    // would keep the row and lose the reason, which is the half-fix §7C names.
    case 'PROVISION_REFUSED': {
      const preset = str(p, 'preset')
      const reason = str(p, 'reason')
      return `${fleet} made port under her ${preset ?? 'standing'} order, but ${
        reason ?? 'she could not be provisioned'
      }.`
    }
    case 'HIRED': {
      const count = num(p, 'count')
      const urgent = p['urgent'] === true || num(p, 'urgent') === 1
      // "crew", NOT "hands" — the owner's no-jargon rule (2026-08-23). This headline is composed
      // CLIENT-side, so the word is this file's to choose; the served `payload.lines` prose is not.
      return `${count === null ? 'Crew' : `${formatQty(count)} crew`} signed for ${fleet}${
        urgent ? ', at the urgent rate' : ''
      }.`
    }
    case 'REPAIRING': {
      const points = num(p, 'points')
      return `${fleet} went into the shipyard${points === null ? '' : ` for ${Math.round(points)} points of hull`}.`
    }
    case 'REPAIRED':
      return `${fleet} came out of the shipyard, sound again.`
    case 'SIGNED_OFFICER': {
      // The three facts a player chose this officer BY, in the order the roster card showed them
      // (PortFaces.tsx:85-95): who, what they are, what they are worth. The wage is deliberately
      // absent — it is the delta printed under this sentence, and saying it twice would make one
      // movement look like two. `cost` is in the payload for the record, not for the headline.
      //
      // It says "worth", never "makes her faster": three of the four specialties are read by no
      // rule yet (0015's header), the payload does not carry `takes_effect`, and a ledger line
      // that claimed an effect the world does not apply would be exactly the fabricated figure
      // this screen exists to refuse. The roster card is where that limitation is disclosed.
      const officer = str(p, 'officer') ?? 'An officer'
      const specialty = str(p, 'specialty')
      const bonus = num(p, 'bonus_pct')
      return `${officer} signed on${specialty ? ` as ${specialty.toLowerCase()}` : ''}${
        bonus === null ? '' : `, worth +${formatPctPoints(bonus)}`
      }.`
    }
    case 'STUDIED': {
      // The SKILL is the subject: the payload has no captain in it and this house has exactly one,
      // so "The captain studied…" would add a word carrying no information. Tuition is the delta
      // below, for the same reason the officer's wage is not repeated here.
      const skill = str(p, 'skill') ?? 'A trade'
      const level = num(p, 'level')
      const port = str(p, 'port')
      return `${skill} studied${level === null ? '' : ` to level ${formatInt(level)}`}${
        port ? ` at ${portName(port)}` : ''
      }.`
    }
    case 'WAGES':
      return `Wages paid to ${fleet}.`
    default: {
      const named = str(p, 'fleet')
      const what = kindWords(event.kind)
      return named ? `${named} · ${what}.` : `${what}.`
    }
  }
}

/** How a server kind is spelled for a human, in one place. Lowercase: the two surfaces that want
 *  capitals (the filter chip and the Badge) upper-case in CSS, and the fallback headline needs it
 *  mid-sentence. `/_/g`, not `'_'` — the old spelling stopped at the first underscore. */
function kindWords(kind: string): string {
  return kind.toLowerCase().replace(/_/g, ' ')
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
// shape per kind, so a payload that is missing a key produces a shorter sentence rather than
// "undefined" on the page. `num` and `str` USED TO BE DECLARED HERE and were deleted on
// 2026-08-23 — they lived here and in `features/command/PreviewPanel.tsx` and had drifted apart.
// They are `src/lib/json.ts` now, imported at the head of this file. Only `payloadLines` is left,
// and it stays because it reads THIS payload's own `report` shape and nothing else does.

/** The after-action prose: `string[]`, composed server-side by `voyage.report_line()`. */
function payloadLines(payload: Record<string, unknown>): string[] {
  const v = payload['lines']
  return Array.isArray(v) ? v.filter((line): line is string => typeof line === 'string') : []
}

/** A whole-number count reads as a count; a fractional one keeps its tenth. */
function formatQty(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(1)
}

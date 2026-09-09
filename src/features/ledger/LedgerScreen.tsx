import { useState } from 'react'
import { Figure, Row, Segmented, Sheet, Tray, type TrayDetent } from '../../components/ui'
import { MINUS, formatClock, formatInt } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { LedgerEvent } from '../../lib/rpc'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { headline, payloadLines } from './headline'

// LEDGER — E.6. "The narrative organ of the game. This is where combat lives, as prose."
//
// Rows, not cards (docs/UI_DIRECTION.md §6 LEDGER, 2026-09-09). Every row is one served event,
// newest first, in the server's own order: the clock it happened at, one sentence about it, and
// the movement of money it made. A row whose event carries a report — the served after-action
// prose, `payload.lines` — opens that report in a tray. Nothing else is on the screen.
//
// ── WHAT §2 ITEM 19 COUNTED, AND WHERE EACH THING WENT ─────────────────────────────────────────
//   the filter card, `1 of 1 entries`, `read just now`   → a Segmented in the sheet header; the
//                                                          counts and the read-age are gone. The
//                                                          world re-reads itself every thirty
//                                                          seconds and this feed rides that read;
//                                                          a screen that reports on its own
//                                                          freshness is telemetry (§5).
//   the second timestamp on every row (`just now`)        → gone. One clock per row.
//   `balance 8,000 d.` on every row                       → gone. The purse is in the status strip
//                                                          on every tab; a balance beside every
//                                                          row is the same fact restated.
//   the footer notice about balances not summing          → gone with the balances it explained.
//                                                          The rule it stated is still true and
//                                                          still asserted (tests/rpc.firstSession
//                                                          .spec.ts): WAGES move the purse through
//                                                          `public.credit()` with no event behind
//                                                          them, so the rows never sum to the
//                                                          purse. Nothing here adds them up, so
//                                                          nothing here has to say so.
//
// ── THE FACES ARE A GROUPING, NOT A SECOND NAME ────────────────────────────────────────────────
// The old chips were built from the kinds present on the page, and the header of that file
// refused to translate the server's kinds into the fixture's TRADE / VOYAGE / PORT / MARKET
// because "a mapping layer would be a second name for every event". §6 asks for four faces —
// All · Trade · Voyage · Crew — so the grouping exists, ONCE, below, and it groups rather than
// renames: the headline still says what the event was. A kind the table does not know shows
// under All and under nothing else, which is the honest reading of "we have not filed this yet".

type Face = 'all' | 'trade' | 'voyage' | 'crew'

const FACES: readonly { id: Face; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'trade', label: 'Trade' },
  { id: 'voyage', label: 'Voyage' },
  { id: 'crew', label: 'Crew' },
]

/** The server's kinds (emit_event, 0004/0007/0015/0016/0034) under the four faces. FOUNDED is the
 *  house's own line and belongs to no face but All. */
const FACE_OF: Record<string, Exclude<Face, 'all'>> = {
  BOUGHT: 'trade',
  SOLD: 'trade',
  DEPARTED: 'voyage',
  VOYAGE_REPORT: 'voyage',
  PROVISIONED: 'voyage',
  PROVISION_REFUSED: 'voyage',
  REPAIRING: 'voyage',
  REPAIRED: 'voyage',
  HIRED: 'crew',
  SIGNED_OFFICER: 'crew',
  STUDIED: 'crew',
  WAGES: 'crew',
}

export function LedgerScreen() {
  // FIELDS, NOT THE STORE (worldStore.ts rule 4). The Ledger is the screen that made the rule: it
  // is the longest list in the game and it re-rendered whole, twice, on every read.
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
  const [face, setFace] = useState<Face>('all')
  const [open, setOpen] = useState<LedgerEvent | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('closed')

  // `world.ledger()` already answers newest-first (0009: `order by e.created_at desc`). The screen
  // does not re-sort it: the server's order is the record's order.
  const shown = face === 'all' ? events : events.filter((e) => FACE_OF[e.kind] === face)
  // A CALLER, not a second author: `portNameOf` is the one reading of "what is this code called".
  const portName = (code: string) => portNameOf(portByCode, code)

  const show = (event: LedgerEvent) => {
    setOpen(event)
    setDetent('half')
  }

  return (
    <Sheet
      title="Ledger"
      data-testid="ledger"
      trailing={<Segmented segments={FACES} value={face} onChange={setFace} label="Ledger" />}
    >
      {events.length === 0 ? (
        <Row label="Nothing has happened yet." tone="muted" hairline={false} />
      ) : shown.length === 0 ? (
        <Row label="Nothing here yet." tone="muted" hairline={false} />
      ) : (
        shown.map((event) => {
          const atMs = Date.parse(event.at)
          const report = payloadLines(event.payload)
          return (
            <Row
              key={event.id}
              data-testid="ledger-row"
              mark={
                <span className="w-11 text-t-caption tabular-nums text-ink-faint">
                  {Number.isFinite(atMs) ? formatClock(atMs) : '--:--'}
                </span>
              }
              label={headline(event, portName)}
              value={movement(event.ducats_delta)}
              chevron={report.length > 0}
              onClick={report.length > 0 ? () => show(event) : undefined}
            />
          )
        })
      )}

      {/* THE REPORT IS READ, NOT SCANNED. The served prose is whole sentences about a night under
          bare poles; it is the one place in the game that is reading rather than checking, and
          it opens at half so a long passage can be dragged to full. The headline is the tray's
          title, so the reader knows which voyage they are reading without the row behind it. */}
      {open !== null && (
        <Tray
          detent={detent}
          onDetentChange={setDetent}
          title={headline(open, portName)}
          data-testid="ledger-report"
        >
          <div className="space-y-3 pb-2">
            {payloadLines(open.payload).map((line, i) => (
              <p key={i} className="text-t-label text-ink-muted">
                {line}
              </p>
            ))}
          </div>
        </Tray>
      )}
    </Sheet>
  )
}

/** THE MOVEMENT IS THE FIGURE (§4.1: the one figure a row is about). Signed, tabular, green or red
 *  by meaning — gain and loss are the only things those two colours may ever mean (§4.4). The unit
 *  is not repeated on every row: the column is money, and the purse in the status strip says `d.`
 *  once. `balance_after` is served and true, and is deliberately not printed — see the header. */
function movement(delta: number | null) {
  if (delta === null) return undefined
  const rounded = Math.round(delta)
  if (rounded === 0) return <Figure value="0" tone="faint" />
  return (
    <Figure
      value={`${rounded > 0 ? '+' : MINUS}${formatInt(Math.abs(rounded))}`}
      tone={rounded > 0 ? 'success' : 'danger'}
    />
  )
}

import { ActCell, Figure, RarityMark, Row } from '../../components/ui'
import { useShellState } from '../../app/shellState'
import { formatDucatsDelta, formatOfTotal, formatPctDelta, formatRelative, formatUnits } from '../../lib/format'
import type { TradeRequest } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE REQUEST BOARD — what this port asks for, one row per request, shaped like the ledger.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/QUAY_LEDGER.md §3 F (owner row 76, slice 4, 2026-09-14): the reference's 의뢰 board as the
// third face of the trade board — *"what this port pays a premium for, by when, how much is
// already aboard"*. Each row is the board's own shape (TradeRow's): the good and its rarity mark,
// a caption, and ONE cell where the ledger has its two — `fulfil`, carrying the premium the
// delivery pays, dead with its reason when it cannot be pressed.
//
// ── EVERY FIGURE IS SERVED (0087, world.contracts) ─────────────────────────────────────────────
// The lot (`qty`), the premium as a fraction and for the whole lot (`premium_pct`,
// `premium_ducats`), and WHEN it closes (`expires_at`, an instant on the calendar clock — printed
// the way the fair row prints its end, `formatRelative`, never as a count of "days" the voyage
// clock would be read on; 0028). What is ON BOARD is the fleet's own manifest, folded once by the
// caller (`fleetCargoByCode`), and the row prints it as a share of the lot — `12 / 20 units on
// board` — because a share never prints without its whole (docs/WORDS.md, law 2). Nothing here
// subtracts, multiplies or judges: whether the lot can land is the server's (`cmd.preview_fulfil`),
// and the cell is dead only for the two things a row can see — nobody of yours is here, or the
// lot is not all on board.
//
// What a press OPENS is the caller's affair (the FulfilTray, in the one slot); this component
// inserts nothing into the list it stands in, so the board holds still under the finger.

export function RequestBoard({
  requests,
  loading,
  aboard,
  docked,
  pick,
  onPick,
}: {
  /** The served board's rows, or null before the first read lands. */
  requests: readonly TradeRequest[] | null
  loading: boolean
  /** Units on board by good code — the reader's manifest, folded once by the caller. */
  aboard: Readonly<Record<string, number>>
  /** A fleet of yours is docked here — the only place a request can be delivered. */
  docked: boolean
  /** The request whose tray is open, if any — its cell draws the wash. */
  pick: string | null
  onPick: (request: TradeRequest) => void
}) {
  const { nowMs } = useShellState()
  if (requests === null) {
    return <Row label={loading ? 'Loading…' : 'No requests.'} tone="muted" hairline={false} className="mt-3" />
  }
  if (requests.length === 0) {
    return <Row label="This port is asking for nothing today." tone="muted" hairline={false} className="mt-3" data-testid="request-board-empty" />
  }
  return (
    <div className="mt-3" data-testid="request-board">
      {requests.map((r) => {
        const have = aboard[r.good] ?? 0
        const dead = !docked ? 'no ship here' : have < r.qty ? `${formatOfTotal(have, r.qty)} units on board` : null
        return (
          <Row
            key={r.id}
            label={
              <span className="flex flex-wrap items-center gap-x-1.5 text-t-body">
                <span className="max-w-full truncate">{r.name}</span>
                <RarityMark rarity={r.rarity} />
                <span className="text-t-caption text-ink-faint">
                  {`· ${formatUnits(r.qty)} · ends ${formatRelative(Date.parse(r.expires_at), nowMs)}`}
                </span>
              </span>
            }
            value={
              <ActCell
                label="fulfil"
                figure={<Figure value={formatDucatsDelta(r.premium_ducats)} tone="success" />}
                onPress={() => onPick(r)}
                dead={dead}
                selected={pick === r.id}
                data-testid="request-fulfil"
              />
            }
            data-testid="request-row"
          >
            <span className="block text-t-caption text-ink-faint">
              {`${formatPctDelta(r.premium_pct)} over the market · ${formatOfTotal(have, r.qty)} units on board`}
            </span>
          </Row>
        )
      })}
    </div>
  )
}

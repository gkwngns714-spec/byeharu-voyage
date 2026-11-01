import { ActCell, Figure, GoodKind, goodClassRow, Row, Clip } from '../components/ui'
import { useShellState } from '../app/shellState'
import { formatDucatsDelta, formatOfTotal, formatPctDelta, formatRelative, formatUnits } from '../lib/format'
import type { TradeRequest } from '../lib/rpc'
import { useT } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE REQUEST BOARD — what this port asks for, one row per request, shaped like the ledger.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/QUAY_LEDGER.md §3 F (owner row 76, slice 4, 2026-09-14): the reference's 의뢰 board as the
// third face of the trade board — *"what this port pays a premium for, by when, how much is
// already aboard"*. Each row is the board's own shape (TradeRow's): the good and its marks (rarity
// and, since 0294, premium class — `GoodKind compact`), a caption, and ONE cell where the ledger
// has its two — `fulfil`, carrying the premium the delivery pays, dead with its reason when it
// cannot be pressed.
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
  const t = useT()
  const { nowMs } = useShellState()
  if (requests === null) {
    return <Row label={t(loading ? 'trade.loading' : 'trade.noRequests')} tone="muted" hairline={false} className="mt-3" />
  }
  if (requests.length === 0) {
    return <Row label={t('trade.askingNothing')} tone="muted" hairline={false} className="mt-3" data-testid="request-board-empty" />
  }
  return (
    <div className="mt-3" data-testid="request-board">
      {requests.map((r) => {
        const have = aboard[r.good] ?? 0
        const dead = !docked ? t('trade.noShipHere') : have < r.qty ? t('trade.unitsAboard', { of: formatOfTotal(have, r.qty) }) : null
        return (
          <Row
            key={r.id}
            {...goodClassRow(r.class)}
            label={
              <span className="flex flex-wrap items-center gap-x-1.5 text-t-body">
                <Clip>{r.name}</Clip>
                <GoodKind compact rarity={r.rarity} goodClass={r.class} />
                <span className="text-t-caption text-ink-faint">
                  {`· ${formatUnits(r.qty)} · ends ${formatRelative(Date.parse(r.expires_at), nowMs)}`}
                </span>
              </span>
            }
            value={
              <ActCell
                label={t('trade.fulfilCell')}
                figure={<Figure value={formatDucatsDelta(r.premium_ducats)} tone="success" />}
                onPress={() => onPick(r)}
                dead={dead}
                selected={pick === r.id}
                data-testid="request-fulfil"
              />
            }
            under="label"
            data-testid="request-row"
          >
            <span className="block text-t-caption text-ink-faint">
              {t('trade.premiumLine', { pct: formatPctDelta(r.premium_pct), of: formatOfTotal(have, r.qty) })}
            </span>
          </Row>
        )
      })}
    </div>
  )
}

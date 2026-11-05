import { ActCell, Figure, GoodKind, goodClassRow, Row, Clip } from '../components/ui'
import { useShellState } from '../app/shellState'
import { formatCountdown, formatDucats, formatInt, formatPrice, formatPriceFigure } from '../lib/format'
import type { TradeRequest } from '../lib/rpc'
import { useT } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE REQUEST BOARD — what this port asks for, one row per request, shaped like the ledger.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/QUAY_LEDGER.md §3 F (owner row 76, slice 4, 2026-09-14): the reference's 의뢰 board as the
// third face of the trade board. Each row is the board's own shape (TradeRow's): the good and its
// marks (rarity and, since 0294, premium class — `GoodKind compact`), a caption, and ONE cell where
// the ledger has its two — `fulfil`, carrying THE PRICE EACH, dead with its reason when it cannot
// be pressed.
//
// ── EVERY FIGURE IS SERVED (0311, world.contracts) ─────────────────────────────────────────────
// Owner, 2026-11-05: *"the +300 gold should be on top of the prices. for example soju sold at 1000
// each would be 1300."* `price_each` is that one figure, `sale_price` the market small under it;
// the server adds them, this file never does. `qty` is what the budget still pays for, `premium_ducats`
// the budget left, `premium_per_unit` the bonus each. The TIME is `expires_at` against the shell's clock,
// a countdown in tabular figures on a line of its own, so a tick moves no row. What is ON BOARD is the
// fleet's own manifest, folded once by the caller. Whether a delivery lands, and how much of what she
// holds, is the server's (`cmd.preview_fulfil`); a cell is dead only for the two things a row can see:
// nobody of yours is here, or she holds none of it.
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
        const dead = !docked ? t('trade.noShipHere') : have < 1 ? t('trade.noneHeld') : null
        return (
          <Row
            key={r.id}
            {...goodClassRow(r.class)}
            label={
              <span className="flex flex-wrap items-center gap-x-1.5 text-t-body">
                <Clip>{r.name}</Clip>
                <GoodKind compact rarity={r.rarity} goodClass={r.class} />
              </span>
            }
            value={
              <ActCell
                label={t('trade.fulfilCell')}
                figure={
                  <span className="block">
                    <Figure value={formatPrice(r.price_each)} tone="success" />
                    <span className="block text-t-caption text-ink-faint">{t('trade.eachMarket', { price: formatPriceFigure(r.sale_price) })}</span>
                  </span>
                }
                onPress={() => onPick(r)}
                dead={dead}
                selected={pick === r.id}
                data-testid="request-fulfil"
              />
            }
            under="label"
            data-testid="request-row"
            data-price-each={r.price_each}
            data-sale-price={r.sale_price}
            data-bonus={r.premium_per_unit}
          >
            <span className="block text-t-caption text-ink-faint" data-testid="request-want">
              {t('trade.wantHeld', { want: formatInt(r.qty), held: formatInt(have) })}
            </span>
            <span className="block text-t-caption text-ink-faint" data-testid="request-budget">
              {t('trade.bonusLine', { price: formatPrice(r.premium_per_unit), left: formatDucats(r.premium_ducats) })}
            </span>
            <span className="block text-t-caption tabular-nums text-ink-faint" data-testid="request-time">
              {t('trade.timeLeft', { time: formatCountdown(Date.parse(r.expires_at) - nowMs) })}
            </span>
          </Row>
        )
      })}
    </div>
  )
}

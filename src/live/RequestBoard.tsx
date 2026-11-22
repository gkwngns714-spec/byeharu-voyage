import { ActCell, Figure, GoodKind, goodClassRow, Icon, Row, Clip } from '../components/ui'
import { useShellState } from '../app/shellState'
import { formatDucats, formatInt, formatPrice, formatPriceFigure, formatRealShort, formatTimeLeft } from '../lib/format'
import type { TradeRequest } from '../lib/rpc'
import { properName, useT } from '../lib/i18n'
import { useNavigate } from 'react-router-dom'
import { useGoTo } from '../chart'
import { useRouteSeed } from '../features/map/routeSeed'
import { useWorld } from './worldStore'

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
// ── A HOLD JOB'S SOURCE IS A PRESS (2026-11-23, third play-test finding 4) ─────────────────────
// "Buy at Bristol · 19m" (0473's served `from`) was plain text, and nothing else on the screen led to Bristol. It is now the press
// that plans the trip as the yard's "Plan trip" does (features/map/routeSeed.ts): her fleet lying at this board's harbour (else her
// first), the source harbour, then back here, handed to the Map's route builder as a draft. Nothing is sent: Final is still hers.
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
  at,
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
  /** This board's harbour (CODE): where a hold job's trip comes back to. */
  at: string
}) {
  const t = useT()
  const { nowMs } = useShellState()
  const fleets = useWorld((s) => s.fleets)
  const navigate = useNavigate()
  const fleet = fleets.find((f) => f.port === at) ?? fleets[0] ?? null
  const planFrom = (from: string) => {
    if (!fleet) return
    useRouteSeed.getState().plan(fleet.id, fleet.port === from ? [at] : [from, at])
    const { openMap } = useGoTo.getState()
    if (openMap) openMap()
    else navigate('/map')
  }
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
        // 0466: a hold-sized job (a load a small ship can carry) says so, and reads its one served total in place of the budget line
        const hold = r.size === 'hold'
        return (
          <Row
            key={r.id}
            {...goodClassRow(r.class)}
            label={
              <span className="flex flex-wrap items-center gap-x-1.5 text-t-body">
                <Clip>{properName('good', r.good, r.name)}</Clip>
                <GoodKind compact rarity={r.rarity} goodClass={r.class} />
                {hold && (
                  <span className="text-t-caption font-semibold text-accent" data-testid="request-hold">
                    {t('trade.holdJob')}
                  </span>
                )}
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
            data-size={r.size ?? 'city'}
          >
            <span className="block text-t-caption text-ink-faint" data-testid="request-want">
              {t('trade.wantHeld', { want: formatInt(r.qty), held: formatInt(have) })}
            </span>
            <span className="block text-t-caption text-ink-faint" data-testid="request-budget">
              {hold && r.total != null
                ? t('trade.holdPays', { total: formatDucats(r.total) })
                : t('trade.bonusLine', { price: formatPrice(r.premium_per_unit), left: formatDucats(r.premium_ducats) })}
            </span>
            {/* 0473: where a hold job's good is sold, and a Barca's sailing time there: both served (world.contracts `from`) */}
            {hold && r.from && (
              <button
                type="button"
                className="flex min-h-11 min-w-11 items-center gap-1 text-left text-t-caption text-accent disabled:text-ink-faint"
                disabled={!fleet}
                onClick={() => r.from && planFrom(r.from.code)}
                data-testid="request-from"
                data-from={r.from.code}
              >
                {r.from.sail_seconds != null
                  ? t('trade.holdFrom', { city: properName('port', r.from.name, r.from.name), time: formatRealShort(r.from.sail_seconds * 1000) })
                  : t('trade.holdFromCity', { city: properName('port', r.from.name, r.from.name) })}
                <Icon name="chevron" size={14} />
              </button>
            )}
            <span className="block text-t-caption tabular-nums text-ink-faint" data-testid="request-time">
              {t('trade.timeLeft', { time: formatTimeLeft(Date.parse(r.expires_at) - nowMs) })}
            </span>
          </Row>
        )
      })}
    </div>
  )
}

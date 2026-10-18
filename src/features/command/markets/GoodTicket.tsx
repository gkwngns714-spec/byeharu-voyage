import { useState } from 'react'
import { Button, Figure, Note, SheetSection, Skeleton, StockGauge } from '../../../components/ui'
import { PortFlag } from '../../../live/PortFlag'
import { portNameOf, useWorld } from '../../../live/worldStore'
import {
  formatClock,
  formatFixed,
  formatInt,
  formatPctChange,
  formatPrice,
  formatPriceDelta,
  formatUnits,
  formatVoyageDays,
} from '../../../lib/format'
import type { BoardBuyRow, BoardPassage, BoardSellRow, GoodBoard, SnapshotGood } from '../../../lib/rpc'
import type { PlanDraft } from '../plans/planDraft'
import type { GoodDesk } from './useGoodDesk'
import { WhyThisPrice } from './WhyThisPrice'

// THE TICKET — the right pane of the desk (docs/COMMAND_DESK.md §3.9): what a broker's order ticket is
// to a stock. The owner, 2026-10-17: *"i will be able to see the estimated price movement so that i can
// plan buying and selling for max profit"*.
//
//   BEST TRADE  the board's own answer, said plainly: buy at A for X, sell at B for Y, net per ton and
//               for the hold, days at sea, the arrival, and the best time to sell. A is where the board
//               priced the amount (`qty.bought_at`, or what is on board); B is the board's first sell
//               row (it is SORTED by net, server-side). Nothing here ranks or adds — the card only
//               picks the board's first answer and prints it.
//   BUY AT      every city that sells it: the price for the amount, its stock against normal, how far.
//   SELL AT     every harbour that buys it: what you get, net per ton, stock against normal, the
//               arrival and the best time.
//   The acts    Buy / Sell here (the trade tray, docked only), Plan (the plan builder: queue it once,
//               or make it a route).
//
// A PRESS SELECTS: a row's city becomes the chart's city (the centre pane changes in place; this pane
// does not move). `All N cities` APPENDS below.

export function GoodTicket({
  good,
  desk,
  onTrade,
  onPlan,
}: {
  good: SnapshotGood
  desk: GoodDesk
  onTrade: (intent: 'buy' | 'sell') => void
  onPlan: (plan: PlanDraft) => void
}) {
  const portByCode = useWorld((s) => s.portByCode)
  const { board, b, docked, aboard, focus, setFocus } = desk
  const [all, setAll] = useState(false)
  const name = (c: string) => portNameOf(portByCode, c)
  const loading = board.loading && !b
  const plan = (buyAt: string | null, sellAt: string | null) =>
    onPlan({ good: good.code, buyAt, sellAt, units: null, max: null, min: null })

  return (
    <div data-testid="good-ticket">
      <BestTrade
        board={b}
        loading={loading}
        docked={docked}
        aboard={aboard}
        name={name}
        onTrade={onTrade}
        onPlan={plan}
        onFocus={setFocus}
      />
      <BuyAt
        board={b}
        loading={loading}
        docked={docked}
        focus={focus}
        name={name}
        goodName={good.name}
        onFocus={setFocus}
        onTrade={() => onTrade('buy')}
        onPlan={(buyAt) =>
          plan(
            buyAt,
            (focus && b?.sell.some((r) => r.port === focus) && !b.buy.some((r) => r.port === focus) ? focus : null) ??
              b?.sell.find((r) => r.quoted)?.port ??
              null,
          )
        }
      />
      <SellAt
        board={b}
        loading={loading}
        docked={docked}
        aboard={aboard}
        all={all}
        onAll={() => setAll(true)}
        focus={focus}
        name={name}
        goodName={good.name}
        onFocus={setFocus}
        onTrade={() => onTrade('sell')}
      />
      {/* 0185: why the focus city's price is what it is (docs/PRICE_FACTORS.md §5) */}
      <WhyThisPrice why={desk.why.view} loading={desk.why.loading} />
    </div>
  )
}

/** Days and the clock time she would be there; `here` when she lies there now. */
function away(row: { miles: number | null; days: number | null; arrive_at: string | null }, here: boolean): string {
  if (here) return 'here'
  const parts = [
    row.days !== null ? formatVoyageDays(row.days) : row.miles !== null ? `${formatInt(row.miles)} miles` : null,
    row.arrive_at ? formatClock(Date.parse(row.arrive_at)) : null,
  ].filter(Boolean)
  return parts.length ? parts.join(' · ') : 'no course'
}

function BestTrade({
  board,
  loading,
  docked,
  aboard,
  name,
  onTrade,
  onPlan,
  onFocus,
}: {
  board: GoodBoard | null
  loading: boolean
  docked: string | null
  aboard: number
  name: (c: string) => string
  onTrade: (intent: 'buy' | 'sell') => void
  onPlan: (buyAt: string | null, sellAt: string | null) => void
  onFocus: (port: string) => void
}) {
  if (loading || !board) {
    return (
      <section className="rounded-tile bg-surface-2 p-4" data-testid="best-trade">
        <Skeleton className="h-[148px] w-full" />
      </section>
    )
  }
  const onBoard = board.qty.basis === 'on_board'
  const buy: BoardBuyRow | null = onBoard ? null : (board.buy.find((r) => r.port === board.qty.bought_at) ?? null)
  // ONLY A PASSAGE SHE CAN SAIL (2026-10-19: the card offered Monterey → Antalya, 275.8 days at sea, to
  // a 1,700-nm captain with 36 days of supplies). The server marks every row `sailable` — the passage
  // gate run per leg and her supplies — and prices the reachable passage (through `stops`). The board
  // is sorted by net; the card takes its first quoted row she can sail, and names the dearer one it
  // passed over with the server's reason. A board from before that read (no `sailable`) is taken as is.
  const quoted = board.sell.filter((r) => r.quoted)
  const sell: BoardSellRow | null = quoted.find((r) => r.sailable !== false) ?? null
  const passed = quoted[0] && quoted[0].sailable === false ? quoted[0] : null
  const beyond = passed ? (
    <p className="mt-2 text-t-caption text-warning" data-testid="best-trade-beyond">
      {sell ? 'Dearer, out of reach: ' : 'The best, '}
      <PortFlag code={passed.port} /> {name(passed.port)}
      {passed.net_per_ton !== null ? ` (${formatPriceDelta(passed.net_per_ton)} / t)` : ''} — {whyNot(passed, board.supplies)}.
    </p>
  ) : null
  if (!sell && passed) {
    return (
      <section className="rounded-tile bg-surface-2 p-4" data-testid="best-trade">
        <span className="text-t-caption font-semibold uppercase tracking-wide text-ink-faint">Best trade</span>
        <p className="mt-1 text-t-body text-ink">No buyer you can reach from here.</p>
        {beyond}
      </section>
    )
  }
  if (!sell || (!onBoard && !buy)) {
    return (
      <section className="rounded-tile bg-surface-2 p-4" data-testid="best-trade">
        <span className="block text-t-caption text-ink-faint">Best trade</span>
        <p className="mt-1 text-t-body text-ink-muted">
          {!sell ? 'No city buys it within reach.' : 'No city sells it with stock to fill your hold.'}
        </p>
      </section>
    )
  }
  const net = sell.net
  const perTon = sell.net_per_ton
  const tone = net === null ? 'muted' : net >= 0 ? 'success' : 'danger'
  const buyHere = buy !== null && buy.port === docked
  const sellHere = onBoard && sell.port === docked && aboard > 0
  return (
    <section className="rounded-tile bg-surface-2 p-4" data-testid="best-trade" data-sailable={sell.sailable === undefined ? "unserved" : String(sell.sailable)}>
      <div className="flex items-center justify-between">
        <span className="text-t-caption font-semibold uppercase tracking-wide text-ink-faint">Best trade</span>
        <span className="text-t-caption text-ink-faint">for {formatUnits(board.qty.units)}</span>
      </div>

      <div className="mt-2 grid grid-cols-[auto_1fr_auto] items-center gap-x-3 gap-y-1">
        <span className="text-t-caption text-ink-faint">Buy</span>
        {buy ? (
          <button type="button" onClick={() => onFocus(buy.port)} className="min-h-11 min-w-0 truncate text-left text-t-body text-ink">
            <PortFlag code={buy.port} /> {name(buy.port)}
          </button>
        ) : (
          <span className="text-t-body text-ink">On board</span>
        )}
        <span className="text-right text-t-body tabular-nums text-ink">
          {buy?.price_each != null
            ? formatPrice(buy.price_each)
            : board.qty.cost_each != null
              ? formatPrice(board.qty.cost_each)
              : '—'}
        </span>

        <span className="text-t-caption text-ink-faint">Sell</span>
        <button type="button" onClick={() => onFocus(sell.port)} className="min-h-11 min-w-0 truncate text-left text-t-body text-ink">
          <PortFlag code={sell.port} /> {name(sell.port)}
        </button>
        <span className="text-right text-t-body tabular-nums text-ink">
          {sell.price_each !== null ? formatPrice(sell.price_each) : formatPrice(sell.mid)}
        </span>
      </div>

      <div className="mt-3 flex items-end justify-between gap-3 border-t border-edge pt-3">
        <div className="min-w-0">
          <span className="block text-t-caption text-ink-faint">Net per ton</span>
          <Figure value={perTon !== null ? formatPriceDelta(perTon) : '—'} tone={tone} size="figure" />
        </div>
        <div className="min-w-0 text-right">
          <span className="block text-t-caption text-ink-faint">Net, the hold</span>
          <Figure value={net !== null ? formatPriceDelta(net) : '—'} tone={tone} />
        </div>
      </div>
      <p className="mt-2 text-t-caption text-ink-muted" data-testid="best-trade-when">
        {[
          sell.days !== null ? `${formatVoyageDays(sell.days)} at sea` : null,
          sell.arrive_at ? `arrive ${formatClock(Date.parse(sell.arrive_at))}` : null,
          sell.best
            ? `best to sell ${formatClock(Date.parse(sell.best.at))} (+${formatFixed(sell.best.gain_pct, 1)} %)`
            : 'sell on arrival',
        ]
          .filter(Boolean)
          .join(' · ')}
      </p>
      {viaLine(sell, name) && (
        <p className="mt-1 text-t-caption text-ink-muted" data-testid="best-trade-via">
          {viaLine(sell, name)}
        </p>
      )}
      {beyond}

      <div className="mt-3 grid grid-cols-2 gap-2">
        {buyHere ? (
          <Button variant="primary" onClick={() => onTrade('buy')} data-testid="best-trade-buy">
            Buy here
          </Button>
        ) : sellHere ? (
          <Button variant="primary" onClick={() => onTrade('sell')} data-testid="best-trade-sell">
            Sell here
          </Button>
        ) : null}
        <Button
          variant={buyHere || sellHere ? 'secondary' : 'primary'}
          onClick={() => onPlan(buy?.port ?? null, sell.port)}
          className={buyHere || sellHere ? '' : 'col-span-2'}
          data-testid="best-trade-plan"
        >
          Plan this trade
        </Button>
      </div>
    </section>
  )
}

/** The harbours a passage calls at between, in the server's order: "via Lisbon · Funchal". */
function viaLine(row: BoardPassage, name: (c: string) => string): string | null {
  return row.stops && row.stops.length > 0 ? `via ${row.stops.map(name).join(' · ')}` : null
}

/** Why a row cannot be sailed, from the server's own figures (0188): no passage within her reach —
 *  and the Navigation the direct leg would need — or a passage whose longest leg her stores do not
 *  carry. */
function whyNot(row: BoardPassage & { miles: number | null }, supplies: { days: number } | undefined): string {
  // No passage: no stops served, or (as 0188 serves a buy row it cannot reach) stops `[]` with no miles.
  if (row.stops == null || row.miles === null) {
    if (row.needs) {
      return row.needs.navigation !== null
        ? `needs Navigation ${row.needs.navigation} (reach ${formatInt(row.needs.reach_nm)} nm a leg)`
        : 'no captain can sail it in one leg, and no passage through harbours is in reach'
    }
    return 'no passage within your reach'
  }
  if (row.longest_leg && row.longest_leg.days > 0 && supplies) {
    return `its longest leg is ${formatVoyageDays(row.longest_leg.days)} at sea, more than your ${formatVoyageDays(supplies.days)} of supplies`
  }
  return 'not within your reach and stores'
}

function RowsSkeleton({ n }: { n: number }) {
  return (
    <>
      {Array.from({ length: n }, (_, i) => (
        <Skeleton key={i} className="my-1 h-[56px] w-full" />
      ))}
    </>
  )
}

function BuyAt({
  board,
  loading,
  docked,
  focus,
  name,
  goodName,
  onFocus,
  onTrade,
  onPlan,
}: {
  board: GoodBoard | null
  loading: boolean
  docked: string | null
  focus: string | null
  name: (code: string) => string
  goodName: string
  onFocus: (port: string) => void
  onTrade: () => void
  onPlan: (buyAt: string) => void
}) {
  return (
    <SheetSection
      heading="Buy at"
      trailing={<span className="text-t-caption text-ink-faint">price · stock · away</span>}
      data-testid="buy-at"
    >
      {loading ? (
        <RowsSkeleton n={2} />
      ) : !board || board.buy.length === 0 ? (
        <Note tone="neutral">No city sells it.</Note>
      ) : (
        board.buy.map((r) => (
          <div key={r.port} className="flex min-h-row items-center gap-2 border-b border-edge py-1.5" data-testid="buy-row">
            <button
              type="button"
              onClick={() => onFocus(r.port)}
              aria-pressed={r.port === focus}
              className={`flex min-h-11 min-w-0 flex-1 flex-col justify-center rounded-control px-1.5 text-left ${r.port === focus ? 'bg-accent-soft' : 'hover:bg-surface-2'}`}
            >
              <span className="flex items-center justify-between gap-2">
                <span className={`truncate text-t-body ${r.here ? 'text-accent' : 'text-ink'}`}>
                  <PortFlag code={r.port} /> {name(r.port)}
                </span>
                <Figure value={r.price_each !== null ? formatPrice(r.price_each) : '—'} className="shrink-0" />
              </span>
              <span className="mt-0.5 flex items-center justify-between gap-2">
                {typeof r.stock_target === 'number' ? (
                  <StockGauge stock={r.stock} target={r.stock_target} label={`${goodName} at ${name(r.port)}`} />
                ) : (
                  <span className="text-t-caption text-ink-faint">{formatUnits(r.stock)}</span>
                )}
                <span className="truncate text-t-caption text-ink-faint">
                  {r.sailable === false ? whyNot(r, board?.supplies) : away(r, r.port === docked)}
                  {r.sailable !== false && viaLine(r, name) ? ` · ${viaLine(r, name)}` : ''}
                  {r.best ? ` · ◆ ${formatClock(Date.parse(r.best.at))} ${formatPctChange(-r.best.gain_pct)}` : ''}
                </span>
              </span>
            </button>
            {r.port === docked ? (
              <Button variant="primary" onClick={onTrade} className="shrink-0" data-testid="desk-buy">
                Buy
              </Button>
            ) : (
              <Button variant="secondary" onClick={() => onPlan(r.port)} className="shrink-0" data-testid="desk-plan">
                Plan
              </Button>
            )}
          </div>
        ))
      )}
    </SheetSection>
  )
}

function SellAt({
  board,
  loading,
  docked,
  aboard,
  all,
  onAll,
  focus,
  name,
  goodName,
  onFocus,
  onTrade,
}: {
  board: GoodBoard | null
  loading: boolean
  docked: string | null
  aboard: number
  all: boolean
  onAll: () => void
  focus: string | null
  name: (code: string) => string
  goodName: string
  onFocus: (port: string) => void
  onTrade: () => void
}) {
  const rows = board ? (all ? board.sell : board.sell.filter((r) => r.quoted)) : []
  const rest = board ? board.sell.length - rows.length : 0
  const via = board?.fleet.where.kind === 'at_sea' ? (board.fleet.where.via ?? null) : null
  return (
    <SheetSection
      heading={board ? `Sell at · ${formatUnits(board.qty.units)}` : 'Sell at'}
      trailing={<span className="text-t-caption text-ink-faint">you get · net / ton</span>}
      data-testid="sell-at"
    >
      {via && (
        <p className="mb-1 text-t-caption text-ink-faint" data-testid="sell-at-via">
          At sea: reckoned from {name(via)}, {formatInt(board?.fleet.where.miles_left ?? 0)} miles off.
        </p>
      )}
      {loading ? (
        <RowsSkeleton n={5} />
      ) : !board || board.sell.length === 0 ? (
        <Note tone="neutral">No city buys it.</Note>
      ) : (
        <>
          {rows.map((r) => (
            <div key={r.port} className="flex min-h-row items-center gap-2 border-b border-edge py-1.5" data-testid="sell-row">
              <button
                type="button"
                onClick={() => onFocus(r.port)}
                aria-pressed={r.port === focus}
                className={`flex min-h-11 min-w-0 flex-1 flex-col justify-center rounded-control px-1.5 text-left ${r.port === focus ? 'bg-accent-soft' : 'hover:bg-surface-2'}`}
              >
                <span className="flex items-center justify-between gap-2">
                  <span className="truncate text-t-body text-ink">
                    <PortFlag code={r.port} /> {name(r.port)}
                    {r.request ? (
                      <span className="ml-1.5 text-t-caption text-warning">wanted +{formatInt(r.request.premium_pct)}%</span>
                    ) : null}
                  </span>
                  <Figure
                    value={r.quoted && r.price_each !== null ? formatPrice(r.price_each) : formatPrice(r.mid)}
                    className="shrink-0"
                  />
                </span>
                <span className="mt-0.5 flex items-center justify-between gap-2">
                  <span className="flex min-w-0 items-center gap-2">
                    {typeof r.stock === 'number' && typeof r.stock_target === 'number' && (
                      <StockGauge stock={r.stock} target={r.stock_target} label={`${goodName} at ${name(r.port)}`} />
                    )}
                    <span className="truncate text-t-caption text-ink-faint">
                      <span className={r.sailable === false ? 'text-warning' : undefined}>
                        {r.sailable === false ? whyNot(r, board?.supplies) : away(r, r.port === docked)}
                      </span>
                      {r.sailable !== false && viaLine(r, name) ? ` · ${viaLine(r, name)}` : ''}
                      {r.best ? ` · ◆ ${formatClock(Date.parse(r.best.at))} +${formatFixed(r.best.gain_pct, 1)}%` : ''}
                    </span>
                  </span>
                  {r.net_per_ton !== null ? (
                    <span
                      className={`shrink-0 whitespace-nowrap text-t-caption tabular-nums ${r.net_per_ton >= 0 ? 'text-success' : 'text-danger'}`}
                    >
                      {formatPriceDelta(r.net_per_ton)} / t
                    </span>
                  ) : (
                    <span className="shrink-0 text-t-caption text-ink-faint">{r.quoted ? 'cost unknown' : 'market price'}</span>
                  )}
                </span>
              </button>
              {r.port === docked && aboard > 0 && (
                <Button variant="primary" onClick={onTrade} className="shrink-0" data-testid="desk-sell">
                  Sell
                </Button>
              )}
            </div>
          ))}
          {rest > 0 && (
            <Button variant="quiet" onClick={onAll} className="mt-2 w-full" data-testid="sell-all-cities">
              All {formatInt(board.sell.length)} cities
            </Button>
          )}
        </>
      )}
    </SheetSection>
  )
}

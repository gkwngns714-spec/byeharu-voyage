import { useState } from 'react'
import { Button, Figure, Note, PricePair, SheetSection, Skeleton, StockGauge, Clip } from '../../../components/ui'
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
import type { BoardBuyRow, BoardSellRow, GoodBoard, SnapshotGood } from '../../../lib/rpc'
import type { PlanDraft } from '../plans/planDraft'
import { reachBoard, reachWords, viaWords } from '../plans/planLines'
import { sidesAt, type CitySides } from './citySides'
import type { GoodDesk } from './useGoodDesk'
import { WhyThisPrice } from './WhyThisPrice'
import { useT, t as tg } from '../../../lib/i18n'

// THE TICKET — the right pane of the desk (docs/COMMAND_DESK.md §3.9): what a broker's order ticket is
// to a stock. The owner, 2026-10-17: *"i will be able to see the estimated price movement so that i can
// plan buying and selling for max profit"*.
//
//   BEST TRADE  the board's own answer, said plainly: buy at A for X, sell at B for Y, net per ton and
//               for the hold, days at sea, the arrival, and the best time to sell. A is where the board
//               priced the amount (`qty.bought_at`, or what is on board); B is the board's first sell
//               row (it is SORTED by net, server-side). Nothing here ranks or adds — the card only
//               picks the board's first answer and prints it.
//   BUY AT      every city that sells it: BOTH SIDES of its price (what you pay, what you get — the
//               board's own two lists joined by city, citySides.ts), its stock against normal, how far.
//   SELL AT     every harbour that buys it: both sides again, net per ton, stock against normal, the
//               arrival and the best time — and, since 0225 (owner row 190: "i can only plan on buying
//               but not for selling"), its own Plan press, which opens Trade with that city as the sell. A side the board did not price prints as a dash and the
//               middle price stands in its place, dim, under its own word — never as a trader's price
//               (owner request 178, 2026-10-20: *"I want both for all cities"*).
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
  const { board, b, docked, aboard, focus, setFocus, sides } = desk
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
        sides={sides}
        name={name}
        goodName={good.name}
        onFocus={setFocus}
        onTrade={() => onTrade('buy')}
        // The buyer a buy row's Plan starts on: the city in focus when it buys, else the dearest quoted city she
        // can SAIL — BestTrade's own pick. Since 0218 (no region door) the dearest quoted buyer can lie past her
        // stores (sailable false) and a plan on it cannot be queued; it stays a chip the player may press, with
        // its reason.
        onPlan={(buyAt) =>
          plan(
            buyAt,
            (focus && b?.sell.some((r) => r.port === focus) && !b.buy.some((r) => r.port === focus) ? focus : null) ??
              b?.sell.find((r) => r.quoted && r.sailable !== false)?.port ??
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
        sides={sides}
        name={name}
        goodName={good.name}
        onFocus={setFocus}
        onTrade={() => onTrade('sell')}
        onPlan={(sellAt) => plan(aboard > 0 ? null : b?.buy.some((r) => r.port === docked) ? docked : (b?.qty.bought_at ?? null), sellAt)}
      />
      {/* 0185: why the focus city's price is what it is (docs/PRICE_FACTORS.md §5) */}
      <WhyThisPrice why={desk.why.view} loading={desk.why.loading} />
    </div>
  )
}

/** Days and the clock time she would be there; `here` when she lies there now. */
function away(row: { miles: number | null; days: number | null; arrive_at: string | null }, here: boolean): string {
  if (here) return tg('markets.awayHere')
  const parts = [
    row.days !== null ? formatVoyageDays(row.days) : row.miles !== null ? tg('markets.miles', { n: formatInt(row.miles) }) : null,
    row.arrive_at ? formatClock(Date.parse(row.arrive_at)) : null,
  ].filter(Boolean)
  return parts.length ? parts.join(' · ') : tg('markets.noCourse')
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
  const t = useT()
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
      {t(sell ? 'markets.dearer' : 'markets.theBest')}
      <PortFlag code={passed.port} /> {name(passed.port)}
      {passed.net_per_ton !== null ? t('markets.perTon', { price: formatPriceDelta(passed.net_per_ton) }) : ''} —{' '}
      {reachWords(passed, reachBoard(board))}.
    </p>
  ) : null
  if (!sell && passed) {
    return (
      <section className="rounded-tile bg-surface-2 p-4" data-testid="best-trade">
        <span className="text-t-caption font-semibold uppercase tracking-wide text-ink-faint">{t('markets.bestTrade')}</span>
        <p className="mt-1 text-t-body text-ink">{t('markets.noBuyerReach')}</p>
        {beyond}
      </section>
    )
  }
  if (!sell || (!onBoard && !buy)) {
    return (
      <section className="rounded-tile bg-surface-2 p-4" data-testid="best-trade">
        <span className="block text-t-caption text-ink-faint">{t('markets.bestTrade')}</span>
        <p className="mt-1 text-t-body text-ink-muted">
          {t(!sell ? 'markets.noCityBuys' : 'markets.noCityStock')}
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
        <span className="text-t-caption font-semibold uppercase tracking-wide text-ink-faint">{t('markets.bestTrade')}</span>
        <span className="text-t-caption text-ink-faint">{t('markets.forUnits', { units: formatUnits(board.qty.units) })}</span>
      </div>

      <div className="mt-2 grid grid-cols-[auto_1fr_auto] items-center gap-x-3 gap-y-1">
        <span className="text-t-caption text-ink-faint">{t('markets.buy')}</span>
        {buy ? (
          <button type="button" onClick={() => onFocus(buy.port)} className="min-h-11 min-w-0 text-left text-t-body text-ink">
            <Clip>
              <PortFlag code={buy.port} /> {name(buy.port)}
            </Clip>
          </button>
        ) : (
          <span className="text-t-body text-ink">{t('markets.onBoard')}</span>
        )}
        <span className="text-right text-t-body tabular-nums text-ink">
          {buy?.price_each != null
            ? formatPrice(buy.price_each)
            : board.qty.cost_each != null
              ? formatPrice(board.qty.cost_each)
              : '—'}
        </span>

        <span className="text-t-caption text-ink-faint">{t('markets.sell')}</span>
        <button type="button" onClick={() => onFocus(sell.port)} className="min-h-11 min-w-0 text-left text-t-body text-ink">
          <Clip>
            <PortFlag code={sell.port} /> {name(sell.port)}
          </Clip>
        </button>
        <span className="text-right text-t-body tabular-nums text-ink">
          {sell.price_each !== null ? formatPrice(sell.price_each) : formatPrice(sell.mid)}
        </span>
      </div>

      <div className="mt-3 flex items-end justify-between gap-3 border-t border-edge pt-3">
        <div className="min-w-0">
          <span className="block text-t-caption text-ink-faint">{t('markets.netPerTon')}</span>
          <Figure value={perTon !== null ? formatPriceDelta(perTon) : '—'} tone={tone} size="figure" />
        </div>
        <div className="min-w-0 text-right">
          <span className="block text-t-caption text-ink-faint">{t('markets.netHold')}</span>
          <Figure value={net !== null ? formatPriceDelta(net) : '—'} tone={tone} />
        </div>
      </div>
      <p className="mt-2 text-t-caption text-ink-muted" data-testid="best-trade-when">
        {[
          sell.days !== null ? t('markets.atSea', { days: formatVoyageDays(sell.days) }) : null,
          sell.arrive_at ? t('markets.arrive', { time: formatClock(Date.parse(sell.arrive_at)) }) : null,
          sell.best
            ? t('markets.bestToSell', { time: formatClock(Date.parse(sell.best.at)), pct: formatFixed(sell.best.gain_pct, 1) })
            : t('markets.sellOnArrival'),
        ]
          .filter(Boolean)
          .join(' · ')}
      </p>
      {viaWords(sell.stops ?? [], name) && (
        <p className="mt-1 text-t-caption text-ink-muted" data-testid="best-trade-via">
          {viaWords(sell.stops ?? [], name)}
        </p>
      )}
      {beyond}

      <div className="mt-3 grid grid-cols-2 gap-2">
        {buyHere ? (
          <Button variant="primary" onClick={() => onTrade('buy')} data-testid="best-trade-buy">
            {t('markets.buyHere')}
          </Button>
        ) : sellHere ? (
          <Button variant="primary" onClick={() => onTrade('sell')} data-testid="best-trade-sell">
            {t('markets.sellHere')}
          </Button>
        ) : null}
        <Button
          variant={buyHere || sellHere ? 'secondary' : 'primary'}
          onClick={() => onPlan(buy?.port ?? null, sell.port)}
          className={buyHere || sellHere ? '' : 'col-span-2'}
          data-testid="best-trade-plan"
        >
          {t('markets.planTrade')}
        </Button>
      </div>
    </section>
  )
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
  sides,
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
  /** Both sides of every city's price, as the board serves them (citySides.ts). */
  sides: Record<string, CitySides>
  name: (code: string) => string
  goodName: string
  onFocus: (port: string) => void
  onTrade: () => void
  onPlan: (buyAt: string) => void
}) {
  const t = useT()
  return (
    <SheetSection
      heading={t('markets.buyAt')}
      trailing={<span className="text-t-caption text-ink-faint">{t('markets.buyCols')}</span>}
      data-testid="buy-at"
    >
      {loading ? (
        <RowsSkeleton n={2} />
      ) : !board || board.buy.length === 0 ? (
        <Note tone="neutral">{t('markets.noCitySells')}</Note>
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
                <Clip className={`text-t-body ${r.here ? 'text-accent' : 'text-ink'}`}>
                  <PortFlag code={r.port} /> {name(r.port)}
                </Clip>
                <PricePair {...sidesAt(sides, r.port)} className="shrink-0" />
              </span>
              <span className="mt-0.5 flex items-center justify-between gap-2">
                {typeof r.stock_target === 'number' ? (
                  <StockGauge stock={r.stock} target={r.stock_target} label={`${goodName} at ${name(r.port)}`} />
                ) : (
                  <span className="text-t-caption text-ink-faint">{formatUnits(r.stock)}</span>
                )}
                <span className="break-words text-t-caption text-ink-faint">
                  {r.sailable === false ? reachWords(r, reachBoard(board)) : away(r, r.port === docked)}
                  {r.sailable !== false && viaWords(r.stops ?? [], name) ? ` · ${viaWords(r.stops ?? [], name)}` : ''}
                  {r.best ? ` · ◆ ${formatClock(Date.parse(r.best.at))} ${formatPctChange(-r.best.gain_pct)}` : ''}
                </span>
              </span>
            </button>
            {r.port === docked ? (
              <Button variant="primary" onClick={onTrade} className="shrink-0" data-testid="desk-buy">
                {t('markets.buy')}
              </Button>
            ) : (
              <Button variant="secondary" onClick={() => onPlan(r.port)} className="shrink-0" data-testid="desk-plan">
                {t('markets.plan')}
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
  sides,
  name,
  goodName,
  onFocus,
  onTrade,
  onPlan,
}: {
  board: GoodBoard | null
  loading: boolean
  docked: string | null
  aboard: number
  all: boolean
  onAll: () => void
  focus: string | null
  /** Both sides of every city's price, as the board serves them (citySides.ts). */
  sides: Record<string, CitySides>
  name: (code: string) => string
  goodName: string
  onFocus: (port: string) => void
  onTrade: () => void
  /** Plan a trade that sells at this city (opens Trade). */
  onPlan: (sellAt: string) => void
}) {
  const t = useT()
  const rows = board ? (all ? board.sell : board.sell.filter((r) => r.quoted)) : []
  const rest = board ? board.sell.length - rows.length : 0
  const via = board?.fleet.where.kind === 'at_sea' ? (board.fleet.where.via ?? null) : null
  return (
    <SheetSection
      heading={board ? t('markets.sellAtN', { units: formatUnits(board.qty.units) }) : t('markets.sellAt')}
      trailing={<span className="text-t-caption text-ink-faint">{t('markets.sellCols')}</span>}
      data-testid="sell-at"
    >
      {via && (
        <p className="mb-1 text-t-caption text-ink-faint" data-testid="sell-at-via">
          {t('markets.reckoned', { port: name(via), n: formatInt(board?.fleet.where.miles_left ?? 0) })}
        </p>
      )}
      {loading ? (
        <RowsSkeleton n={5} />
      ) : !board || board.sell.length === 0 ? (
        <Note tone="neutral">{t('markets.noCityBuysIt')}</Note>
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
                  <Clip className="text-t-body text-ink">
                    <PortFlag code={r.port} /> {name(r.port)}
                    {r.request ? (
                      <span className="ml-1.5 text-t-caption text-warning">{t('markets.wanted', { pct: formatInt(r.request.premium_pct) })}</span>
                    ) : null}
                  </Clip>
                  <PricePair {...sidesAt(sides, r.port)} className="shrink-0" />
                </span>
                <span className="mt-0.5 flex items-center justify-between gap-2">
                  <span className="flex min-w-0 items-center gap-2">
                    {typeof r.stock === 'number' && typeof r.stock_target === 'number' && (
                      <StockGauge stock={r.stock} target={r.stock_target} label={`${goodName} at ${name(r.port)}`} />
                    )}
                    <span className="break-words text-t-caption text-ink-faint">
                      <span className={r.sailable === false ? 'text-warning' : undefined}>
                        {r.sailable === false ? reachWords(r, reachBoard(board)) : away(r, r.port === docked)}
                      </span>
                      {r.sailable !== false && viaWords(r.stops ?? [], name) ? ` · ${viaWords(r.stops ?? [], name)}` : ''}
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
                    <span className="shrink-0 text-t-caption text-ink-faint">{t(r.quoted ? 'markets.costUnknown' : 'markets.marketPriceLower')}</span>
                  )}
                </span>
              </button>
              {r.port === docked && aboard > 0 ? (
                <Button variant="primary" onClick={onTrade} className="shrink-0" data-testid="desk-sell">
                  {t('markets.sell')}
                </Button>
              ) : (
                <Button variant="secondary" onClick={() => onPlan(r.port)} className="shrink-0" data-testid="desk-plan-sell">
                  {t('markets.plan')}
                </Button>
              )}
            </div>
          ))}
          {rest > 0 && (
            <Button variant="quiet" onClick={onAll} className="mt-2 w-full" data-testid="sell-all-cities">
              {t('markets.allCities', { n: formatInt(board.sell.length) })}
            </Button>
          )}
        </>
      )}
    </SheetSection>
  )
}

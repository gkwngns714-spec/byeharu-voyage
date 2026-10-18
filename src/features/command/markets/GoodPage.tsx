import { useMemo, useState } from 'react'
import {
  Button,
  Chip,
  Figure,
  Hint,
  Note,
  PriceChart,
  RarityMark,
  SheetSection,
  Skeleton,
  Tray,
  type TrayDetent,
} from '../../../components/ui'
import { fleetCargoByCode } from '../../../domain/fleet'
import { useGoodBoard, usePriceOutlook } from '../../../live/useDesk'
import { PortFlag } from '../../../live/PortFlag'
import { usePortHistory } from '../../../live/usePortHistory'
import { portNameOf, useWorld } from '../../../live/worldStore'
import {
  formatClock,
  formatPriceDelta,
  formatFixed,
  formatInt,
  formatPctChange,
  formatPrice,
  formatPriceFigure,
  formatUnits,
  formatVoyageDays,
  COIN,
} from '../../../lib/format'
import type { BoardBuyRow, BoardSellRow, FleetView, GoodBoard, SnapshotGood } from '../../../lib/rpc'
import { useDeskGood } from '../../../store/deskGood'
import type { PlanDraft } from '../plans/planDraft'

// ONE GOOD, EVERY CITY — the good's page on the desk (docs/COMMAND_DESK.md §3.3). The owner, 2026-10-17:
// *"when i press coffee trade goods, it will show chart, where i can buy, the price if i sell to other
// cities. at which time and so on."*
//
//   the hero      the focus city's market price now (the estimate's k = 0, which IS world.price's mid)
//                 and its move across the record;
//   the chart     the record (world.price_history) and the server's estimate (world.price_outlook) with
//                 its band, the best time ◆ and the arrival rule — one model, PriceChart's;
//   the one line  the server's assumption and the likely range where the fleet would arrive;
//   Buy at        every city that sells it (world.good_board `buy`): what the amount costs there, its
//                 stock, how far, and — docked there — the Buy cell, which opens THE trade tray;
//   Sell at       every harbour that buys it: the dearest priced in full — what you get, net per ton
//                 after the tax and the wages, when you would arrive, and the best time to sell.
//
// EVERY FIGURE IS SERVED. This file sorts nothing the server did not sort and adds nothing up: the net
// is the board's, the band the outlook's. A FOCUS CHIP SELECTS (the chart's data changes in place;
// nothing above or below moves); a sell row's tap makes that city the focus. `All N cities` APPENDS
// below. While the board is asked (~0.3–0.5 s on prod) its rows stand as skeletons at their final
// height, and a re-ask keeps the old figures drawn (§5.8).

const CHART = { width: 380, height: 200 }

export function GoodPage({
  fleet,
  good,
  onTrade,
  onPlan,
}: {
  fleet: FleetView
  good: SnapshotGood
  /** The docked city's Buy / Sell cell: the desk opens the trade tray in this slot. */
  onTrade: (intent: 'buy' | 'sell') => void
  /** A Buy at row's Plan: the desk opens the plan builder in this slot, buying there. */
  onPlan: (plan: PlanDraft) => void
}) {
  const portByCode = useWorld((s) => s.portByCode)
  const close = useDeskGood((s) => s.close)
  const focusCode = useDeskGood((s) => s.focus)
  const setFocus = useDeskGood((s) => s.setFocus)
  const [detent, setDetent] = useState<TrayDetent>('full')
  const [allCities, setAllCities] = useState(false)

  const board = useGoodBoard(good.id, fleet.id, fleet.version, null)
  const b = board.view
  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  const aboard = fleetCargoByCode(fleet)[good.code] ?? 0

  // THE FOCUS: the tapped city, else the docked city when it sells the good, else the cheapest seller,
  // else the dearest buyer.
  const focus =
    focusCode ?? (b ? (b.buy.find((r) => r.here)?.port ?? b.buy[0]?.port ?? b.sell[0]?.port ?? null) : docked)
  const focusPort = focus ? (portByCode[focus] ?? null) : null
  const history = usePortHistory(focusPort?.id ?? '', focusPort ? good.code : null)
  const outlook = usePriceOutlook(focusPort?.id ?? null, good.id, 'mid', 24)
  const o = outlook.view

  const focusRow: BoardBuyRow | BoardSellRow | null =
    (b && focus && (b.buy.find((r) => r.port === focus) ?? b.sell.find((r) => r.port === focus))) || null
  const arriveMs = focusRow?.arrive_at ? Date.parse(focusRow.arrive_at) : null

  const chips = useMemo(() => {
    const codes = (b?.buy ?? []).map((r) => r.port)
    if (focus && !codes.includes(focus)) codes.push(focus)
    return codes
  }, [b, focus])

  const now = o?.points[0]?.value ?? null
  const first = history.points?.[0]?.mid ?? null
  const move = now !== null && first ? ((now - first) / first) * 100 : null
  const likely = likelyLine(o, focusRow, docked === focus)

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? close() : setDetent(next))}
      title={
        <span className="flex items-center gap-2">
          {good.name} <RarityMark rarity={good.rarity} />
        </span>
      }
      data-testid="good-page"
    >
      {/* THE HERO: the focus city's market price, now — and its move across the record */}
      <div className="flex items-end justify-between gap-3" data-testid="good-hero">
        <div className="min-w-0">
          <span className="block truncate text-t-caption text-ink-faint">
            {focusPort ? `${focusPort.name} · Market price` : 'Market price'}
          </span>
          {now !== null ? (
            <Figure value={formatPriceFigure(now)} unit={COIN} size="hero" />
          ) : (
            <Skeleton className="h-[38px] w-40" />
          )}
        </div>
        {move !== null && (
          <span
            className={[
              'mb-1 shrink-0 rounded-chip px-2 text-t-caption tabular-nums',
              move > 0 ? 'bg-success-soft text-success' : move < 0 ? 'bg-danger-soft text-danger' : 'text-ink-faint',
            ].join(' ')}
          >
            {formatPctChange(move)}
          </span>
        )}
      </div>

      {/* THE FOCUS: a chip per city that sells it (and the sell city tapped) — a press selects */}
      {chips.length > 1 && (
        <div className="-mx-gutter mt-3 flex gap-2 overflow-x-auto px-gutter pb-1" role="group" aria-label="Chart city">
          {chips.map((c) => (
            <Chip key={c} on={c === focus} onClick={() => setFocus(c)} className="shrink-0 whitespace-nowrap">
              <PortFlag code={c} />
              {portNameOf(portByCode, c)}
            </Chip>
          ))}
        </div>
      )}

      <div className="mt-3 min-h-[230px]" data-testid="good-chart">
        {o ? (
          <PriceChart
            points={history.points ?? []}
            slotSeconds={o.slot_seconds}
            nowMs={Date.parse(o.now)}
            outlook={{ points: o.points, bestAt: o.best?.at ?? null, arriveMs }}
            size={CHART}
            label={`${good.name} at ${focusPort?.name ?? 'this city'}: the record and the estimate`}
          />
        ) : outlook.loading ? (
          <Skeleton className="h-[200px] w-full" />
        ) : (
          <Note tone="neutral">No estimate for this city.</Note>
        )}
      </div>
      {likely && (
        <Hint className="mt-1" data-testid="good-likely">
          {likely}
        </Hint>
      )}

      <BuyAt
        onPlan={(buyAt) =>
          onPlan({
            good: good.code,
            buyAt,
            // where to sell: the city the chart follows when it is a buyer, else the board's best net
            sellAt:
              (focus && b?.sell.some((r) => r.port === focus) && !b.buy.some((r) => r.port === focus) ? focus : null) ??
              b?.sell.find((r) => r.quoted)?.port ??
              null,
            units: null,
            max: null,
            min: null,
          })
        }
        board={b}
        loading={board.loading && !b}
        docked={docked}
        onFocus={setFocus}
        onTrade={() => onTrade('buy')}
        portName={(c) => portNameOf(portByCode, c)}
      />
      <SellAt
        board={b}
        loading={board.loading && !b}
        docked={docked}
        aboard={aboard}
        all={allCities}
        onAll={() => setAllCities(true)}
        focus={focus}
        onFocus={setFocus}
        onTrade={() => onTrade('sell')}
        portName={(c) => portNameOf(portByCode, c)}
      />
    </Tray>
  )
}

/** The one line under the chart: the server's assumption, and the likely range where (and when) she
 *  would be there — the arrival for a city she must sail to, the best time for the city she is in. */
function likelyLine(
  o: {
    assumes: string
    points: { at: string; lo: number; hi: number }[]
    best: { at: string } | null
  } | null,
  row: BoardBuyRow | BoardSellRow | null,
  here: boolean,
): string | null {
  if (!o || o.points.length < 2) return null
  const at = here
    ? (o.best?.at ?? o.points[o.points.length - 1].at)
    : (row?.arrive_at ?? o.points[o.points.length - 1].at)
  const atMs = Date.parse(at)
  const p = o.points.find((x) => Date.parse(x.at) >= atMs) ?? o.points[o.points.length - 1]
  return `${o.assumes}, the price is likely ${formatPriceFigure(p.lo)}–${formatPrice(p.hi)} at ${formatClock(Date.parse(p.at))}.`
}

function away(row: { miles: number | null; days: number | null }, here: boolean): string {
  if (here) return 'here'
  if (row.days === null) return row.miles === null ? '—' : `${formatInt(row.miles)} miles`
  return formatVoyageDays(row.days)
}

function RowsSkeleton({ n }: { n: number }) {
  return (
    <>
      {Array.from({ length: n }, (_, i) => (
        <Skeleton key={i} className="my-1 h-[50px] w-full" />
      ))}
    </>
  )
}

function BuyAt({
  onPlan,
  board,
  loading,
  docked,
  onFocus,
  onTrade,
  portName,
}: {
  board: GoodBoard | null
  loading: boolean
  docked: string | null
  onFocus: (port: string) => void
  onTrade: () => void
  onPlan: (buyAt: string) => void
  portName: (code: string) => string
}) {
  return (
    <SheetSection
      heading="Buy at"
      trailing={<span className="text-t-caption text-ink-faint">price · stock · away</span>}
      data-testid="buy-at"
    >
      {loading ? (
        <RowsSkeleton n={3} />
      ) : !board || board.buy.length === 0 ? (
        <Note tone="neutral">No city sells it.</Note>
      ) : (
        board.buy.map((r) => (
          <div
            key={r.port}
            className="flex min-h-row items-center gap-3 border-b border-edge py-2"
            data-testid="buy-row"
          >
            <button
              type="button"
              onClick={() => onFocus(r.port)}
              className="flex min-h-11 min-w-0 flex-1 items-center gap-3 text-left"
            >
              <span className="min-w-0 flex-1">
                <span className={`block truncate text-t-body ${r.here ? 'text-accent' : 'text-ink'}`}>
                  <PortFlag code={r.port} /> {portName(r.port)}
                </span>
                <span className="block truncate text-t-caption text-ink-faint">
                  {formatUnits(r.stock)} · {away(r, r.port === docked)}
                  {r.best ? ` · best ${formatClock(Date.parse(r.best.at))} ${formatPctChange(-r.best.gain_pct)}` : ''}
                </span>
              </span>
              <span className="shrink-0 whitespace-nowrap text-right text-t-body tabular-nums text-ink">
                {r.price_each !== null ? formatPrice(r.price_each) : '—'}
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
  onFocus,
  onTrade,
  portName,
}: {
  board: GoodBoard | null
  loading: boolean
  docked: string | null
  aboard: number
  all: boolean
  onAll: () => void
  focus: string | null
  onFocus: (port: string) => void
  onTrade: () => void
  portName: (code: string) => string
}) {
  const rows = board ? (all ? board.sell : board.sell.filter((r) => r.quoted)) : []
  const rest = board ? board.sell.length - rows.length : 0
  return (
    <SheetSection
      heading={board ? `Sell at · for ${formatUnits(board.qty.units)}` : 'Sell at'}
      trailing={<span className="text-t-caption text-ink-faint">you get · net per ton</span>}
      data-testid="sell-at"
    >
      {loading ? (
        <RowsSkeleton n={6} />
      ) : !board || board.sell.length === 0 ? (
        <Note tone="neutral">No city buys it.</Note>
      ) : (
        <>
          {rows.map((r) => (
            <div
              key={r.port}
              className="flex min-h-row items-center gap-3 border-b border-edge py-2"
              data-testid="sell-row"
            >
              <button
                type="button"
                onClick={() => onFocus(r.port)}
                aria-pressed={r.port === focus}
                className={`flex min-h-11 min-w-0 flex-1 items-center gap-3 rounded-control px-1 text-left ${r.port === focus ? 'bg-accent-soft' : ''}`}
              >
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-t-body text-ink">
                    <PortFlag code={r.port} /> {portName(r.port)}
                    {r.request ? (
                      <span className="ml-2 text-t-caption text-warning">
                        wanted · +{formatInt(r.request.premium_pct)}%
                      </span>
                    ) : null}
                  </span>
                  <span className="block truncate text-t-caption text-ink-faint">
                    {[
                      away(r, r.port === docked),
                      r.arrive_at && r.port !== docked ? `arrive ${formatClock(Date.parse(r.arrive_at))}` : null,
                      r.best ? `best ${formatClock(Date.parse(r.best.at))} +${formatFixed(r.best.gain_pct, 1)}%` : null,
                    ]
                      .filter(Boolean)
                      .join(' · ')}
                  </span>
                </span>
                <span className="flex shrink-0 flex-col items-end">
                  <span className="whitespace-nowrap text-t-body tabular-nums text-ink">
                    {r.quoted && r.price_each !== null ? formatPrice(r.price_each) : formatPrice(r.mid)}
                  </span>
                  {r.net_per_ton !== null ? (
                    <span
                      className={`whitespace-nowrap text-t-caption tabular-nums ${r.net_per_ton >= 0 ? 'text-success' : 'text-danger'}`}
                    >
                      {formatPriceDelta(r.net_per_ton)} / ton
                    </span>
                  ) : (
                    <span className="text-t-caption text-ink-faint">{r.quoted ? '—' : 'market price'}</span>
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

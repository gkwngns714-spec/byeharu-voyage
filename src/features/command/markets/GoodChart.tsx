import { useLayoutEffect, useMemo, useRef, useState } from 'react'
import {
  Chip,
  Figure,
  Hint,
  Icon,
  Note,
  PriceChart,
  RarityMark,
  Segmented,
  Skeleton,
  StockGauge,
  goodIcon,
} from '../../../components/ui'
import { PortFlag } from '../../../live/PortFlag'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { COIN, formatClock, formatFixed, formatPctChange, formatPrice, formatPriceFigure } from '../../../lib/format'
import type { BoardBuyRow, BoardSellRow, PriceOutlook, SnapshotGood } from '../../../lib/rpc'
import type { GoodDesk } from './useGoodDesk'

// THE GOOD'S CHART — the centre of the desk (docs/COMMAND_DESK.md §3.3, §3.9). The owner, 2026-10-17:
// *"when i press coffee trade goods, it will show chart … at which time"*; 2026-10-18: *"i don't see
// stock of the trade goods"*.
//
//   the head     the good, the city the chart follows (its flag), the market price there now in the
//                hero figure, its move across the window, and the city's stock against its normal level;
//   the cities   a chip per city (flag + name) — a press SELECTS: the chart's data changes in place;
//   the window   1 h · 6 h · 12 h of the record (the served points, cut to the window — nothing derived);
//   the chart    the record and the server's estimate with its band, the best time ◆ and the arrival
//                rule, and under it the city's STOCK on the same time axis with its normal level dashed;
//   the foot     the best time to trade there (the board's, only when it beats the band) and the likely
//                range on arrival (the estimate's, in the server's words).
//
// THE PLANE IS MEASURED, not fixed: on a wide glass the chart fills its pane (ResizeObserver), so the
// SVG's units are screen pixels and its labels stand at their true size. On a phone it is the tray's
// width and 220 px tall.

const WINDOWS = [
  { id: '1', label: '1 h' },
  { id: '6', label: '6 h' },
  { id: '12', label: '12 h' },
] as const
type WindowId = (typeof WINDOWS)[number]['id']

function useBoxSize<T extends HTMLElement>() {
  const ref = useRef<T | null>(null)
  const [size, setSize] = useState<{ width: number; height: number } | null>(null)
  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    const read = () => {
      const r = el.getBoundingClientRect()
      const next = { width: Math.round(r.width), height: Math.round(r.height) }
      setSize((s) => (s && s.width === next.width && s.height === next.height ? s : next))
    }
    read()
    const ro = new ResizeObserver(read)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])
  return [ref, size] as const
}

export function GoodChart({
  good,
  desk,
  fill = false,
  showName = true,
}: {
  /** The good's name in the head — off in a phone's tray, whose title already names it. */
  showName?: boolean
  good: SnapshotGood
  desk: GoodDesk
  /** Fill the pane's height (a wide glass); otherwise a fixed 220-px plane (a phone's tray). */
  fill?: boolean
}) {
  const portByCode = useWorld((s) => s.portByCode)
  const { b, focus, focusPort, setFocus, history, outlook, focusRow, chips, docked } = desk
  const o = outlook.view
  const [win, setWin] = useState<WindowId>('12')
  const [box, boxSize] = useBoxSize<HTMLDivElement>()

  // THE WINDOW: the served record cut to its last N hours (the record is ≤ 12 h — price_history_window).
  const nowMs = o ? Date.parse(o.now) : Number.NaN
  const points = useMemo(() => {
    const all = history.points ?? []
    if (!Number.isFinite(nowMs)) return all
    const from = nowMs - Number(win) * 3_600_000
    return all.filter((p) => Date.parse(p.at) >= from)
  }, [history.points, nowMs, win])

  const arriveMs = focusRow?.arrive_at ? Date.parse(focusRow.arrive_at) : null
  const now = o?.points[0]?.value ?? null
  const first = points[0]?.mid ?? null
  const move = now !== null && first ? ((now - first) / first) * 100 : null
  const stock = stockOf(focusRow, o)
  const best = focusRow?.best ?? null
  const sells = focusRow ? 'quoted' in focusRow : false
  const likely = likelyLine(o, focusRow, docked === focus)

  const size = boxSize
    ? { width: Math.max(280, boxSize.width), height: fill ? Math.max(220, boxSize.height - 28) : 220 }
    : null

  return (
    <div className={fill ? 'flex h-full min-h-0 flex-col' : ''} data-testid="good-chart-pane">
      {/* THE HEAD */}
      <div className="flex items-start justify-between gap-4" data-testid="good-hero">
        <div className="min-w-0">
          {showName && (
            <span className="flex items-center gap-1.5 text-t-body font-semibold">
              <Icon name={goodIcon(good.code, good.category)} size={18} className="shrink-0 text-ink-muted" />
              <span className="truncate">{good.name}</span>
              <RarityMark rarity={good.rarity} />
            </span>
          )}
          <span className="mt-0.5 flex items-center gap-1.5 truncate text-t-caption text-ink-faint">
            {focusPort && <PortFlag code={focusPort.code} />}
            {focusPort ? `${focusPort.name} · market price` : 'Market price'}
          </span>
          <span className="mt-1 flex items-baseline gap-3">
            {now !== null ? (
              <Figure value={formatPriceFigure(now)} unit={COIN} size="hero" />
            ) : (
              <Skeleton className="h-[38px] w-40" />
            )}
            {move !== null && (
              <span
                className={[
                  'shrink-0 rounded-chip px-2 text-t-caption tabular-nums',
                  move > 0 ? 'bg-success-soft text-success' : move < 0 ? 'bg-danger-soft text-danger' : 'text-ink-faint',
                ].join(' ')}
              >
                {formatPctChange(move)} · {win} h
              </span>
            )}
          </span>
        </div>
        {stock && focusPort && (
          <div className="shrink-0 pt-1 text-right" data-testid="good-stock">
            <span className="block text-t-caption text-ink-faint">Stock · normal</span>
            <StockGauge stock={stock.stock} target={stock.target} label={`${good.name} at ${focusPort.name}`} />
          </div>
        )}
      </div>

      {/* THE CITIES AND THE WINDOW — one row; a press selects, nothing moves */}
      <div className="mt-3 flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-3">
        <div className="bv-scroll-x flex min-w-0 flex-1 gap-2 overflow-x-auto" role="group" aria-label="Chart city">
          {chips.map((c) => (
            <Chip key={c} on={c === focus} onClick={() => setFocus(c)} className="shrink-0 whitespace-nowrap">
              <PortFlag code={c} />
              {portNameOf(portByCode, c)}
            </Chip>
          ))}
        </div>
        <Segmented<WindowId> segments={WINDOWS} value={win} onChange={setWin} label="Chart window" className="shrink-0 self-start" />
      </div>

      {/* THE CHART — fills the pane on a wide glass. On a phone the box keeps room for the plot (220 px) and a
          legend wrapped to two lines (2026-10-19: a city's estimate drawn at once, asked ahead, wrapped its
          legend and pushed the ticket down 10 px; the skeleton it replaced had no legend). */}
      <div
        ref={box}
        className={fill ? 'mt-3 min-h-[260px] flex-1' : 'mt-3 min-h-[260px]'}
        data-testid="good-chart"
      >
        {o && size ? (
          <PriceChart
            points={points}
            slotSeconds={o.slot_seconds}
            nowMs={nowMs}
            outlook={{ points: o.points, bestAt: o.best?.at ?? null, arriveMs }}
            size={size}
            stockTarget={o.stock_target ?? stock?.target ?? null}
            label={`${good.name} at ${focusPort?.name ?? 'this city'}: the record, the estimate and the stock`}
          />
        ) : outlook.loading || !size ? (
          <Skeleton className="h-[220px] w-full" />
        ) : (
          <Note tone="neutral">No estimate for this city.</Note>
        )}
      </div>

      {/* THE FOOT: when, and how likely. On a phone the likely line wraps to two (16 px each): room for
          three lines is kept, so a city's estimate landing (at once, when it was asked ahead — 2026-10-19)
          never pushes the ticket below it down. */}
      <div className="mt-1 min-h-[3.25rem] space-y-0.5 sm:min-h-11">
        {best ? (
          <p className="text-t-caption text-warning" data-testid="good-best-time">
            ◆ Best time to {sells ? 'sell' : 'buy'} at {focusPort?.name ?? 'this city'}: {formatClock(Date.parse(best.at))} ·{' '}
            {formatPrice(best.value)} ({sells ? '+' : '−'}
            {formatFixed(Math.abs(best.gain_pct), 1)} %)
          </p>
        ) : focusRow && b ? (
          <p className="text-t-caption text-ink-faint">No better time ahead: it is as likely to fall as to rise.</p>
        ) : null}
        {likely && <Hint data-testid="good-likely">{likely}</Hint>}
      </div>
    </div>
  )
}

/** The focus city's stock and normal level: the board's row when it carries them, else the estimate's. */
function stockOf(row: BoardBuyRow | BoardSellRow | null, o: PriceOutlook | null): { stock: number; target: number } | null {
  if (row && typeof row.stock === 'number' && typeof row.stock_target === 'number') {
    return { stock: row.stock, target: row.stock_target }
  }
  const s = o?.points[0]?.stock
  if (o && typeof s === 'number' && typeof o.stock_target === 'number') return { stock: s, target: o.stock_target }
  return null
}

/** The one line under the chart: the server's assumption, and the likely range where (and when) she
 *  would be there — the arrival for a city she must sail to, the best time for the city she is in. */
function likelyLine(o: PriceOutlook | null, row: BoardBuyRow | BoardSellRow | null, here: boolean): string | null {
  if (!o || o.points.length < 2) return null
  const at = here ? (o.best?.at ?? o.points[o.points.length - 1].at) : (row?.arrive_at ?? o.points[o.points.length - 1].at)
  const atMs = Date.parse(at)
  const p = o.points.find((x) => Date.parse(x.at) >= atMs) ?? o.points[o.points.length - 1]
  return `${o.assumes}, the price is likely ${formatPriceFigure(p.lo)}–${formatPrice(p.hi)} at ${formatClock(Date.parse(p.at))}.`
}

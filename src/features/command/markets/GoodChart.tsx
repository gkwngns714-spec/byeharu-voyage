import { useCallback, useLayoutEffect, useMemo, useRef, useState } from 'react'
import {
  Chip,
  Hint,
  Icon,
  Note,
  PriceChart,
  PricePair,
  RarityMark,
  Segmented,
  Skeleton,
  StockGauge,
  goodIcon,
  panBackMs,
  panView,
} from '../../../components/ui'
import { PortFlag } from '../../../live/PortFlag'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { formatClock, formatFixed, formatPctChange, formatPrice, formatPriceFigure } from '../../../lib/format'
import type { BoardBuyRow, BoardSellRow, PriceOutlook, PricePoint, SnapshotGood } from '../../../lib/rpc'
import { DESK_WINDOW_HOURS, type GoodDesk } from './useGoodDesk'
import { useT, t as tg } from '../../../lib/i18n'

// THE GOOD'S CHART — the centre of the desk (docs/COMMAND_DESK.md §3.3, §3.9). The owner, 2026-10-17:
// *"when i press coffee trade goods, it will show chart … at which time"*; 2026-10-18: *"i don't see
// stock of the trade goods"*.
//
//   the head     the good, the city the chart follows (its flag), BOTH SIDES of its price there now —
//                what you pay, what you get, each under its own word (owner request 178, 2026-10-20) —
//                the middle price with its move across the window, and the city's stock against normal;
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

/** One frozen empty record, so "the read has not landed" never hands the chart a fresh array. */
const NO_POINTS: readonly PricePoint[] = []

/** How long a window reads, in the owner's words: hours up to a day, then days and weeks. */
function windowWord(hours: number): string {
  if (hours % (24 * 7) === 0) return tg('markets.weeks', { n: hours / (24 * 7) })
  if (hours % 24 === 0) return tg('markets.days', { n: hours / 24 })
  return tg('markets.hours', { n: hours })
}

/** How long a stretch of the record actually is, in the axis's voice: `12 h`, `11.8 h`, `2 days`. The
 *  move beside the price is labelled with THIS and not with the chip, because a week-wide chip over a
 *  twelve-hour record is still a twelve-hour move (owner request 178). */
function spanWord(hours: number): string {
  if (hours >= 24 && Number.isInteger(hours / 24)) return windowWord(hours)
  const r = Math.round(hours * 10) / 10
  return tg('markets.hours', { n: Number.isInteger(r) ? r : r.toFixed(1) })
}

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
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const { b, focus, focusPort, setFocus, history, outlook, focusRow, chips, docked } = desk
  const o = outlook.view
  const why = desk.why.view
  const { winHours, setWinHours } = desk
  const [box, boxSize] = useBoxSize<HTMLDivElement>()

  // THE WINDOW AND THE DRAG. The chips choose how WIDE the window is (to a week); the drag chooses how
  // far BACK it sits (`panMs`, reset when the window or the city changes). The whole record is handed
  // to the chart and the window tells it which stretch to draw, so the line enters and leaves the
  // plot's edges instead of being cut to the window first. How much of a chosen window the record can
  // fill is the SERVER's answer (useGoodDesk asks for the slots the window needs and
  // `world.price_history` clamps the ask to what it keeps); a window wider than the record would leave
  // most of the plane empty, so the drawn window is the narrower of the two and the foot says in words
  // how far back the record truly reaches.
  const nowMs = o ? Date.parse(o.now) : Number.NaN
  const points = history.points ?? NO_POINTS
  // THE DRAG IS REMEMBERED AGAINST WHAT IT WAS MADE ON — the city and the width. A new city or a new
  // width is a new question, so the window goes back to now; it is DERIVED from the pair rather than
  // reset by an effect, so there is no render that draws the old offset on the new window.
  const panKey = `${focus ?? '-'}|${winHours}`
  const [pan, setPan] = useState({ key: panKey, ms: 0 })
  const panMs = pan.key === panKey ? pan.ms : 0
  const setPanMs = useCallback((ms: number) => setPan({ key: panKey, ms }), [panKey])

  const times = useMemo(() => points.map((p) => Date.parse(p.at)), [points])
  const oldestMs = times.length ? Math.min(...times) : nowMs
  const estEndMs = o?.points.length ? Date.parse(o.points[o.points.length - 1].at) : nowMs
  // The chips say how far BACK the window reaches, and the estimate always stands to the right of now,
  // so the window is the two together — the same plane the chart drew before a window existed. Asking
  // for more record than there is would only leave the plate empty, so the reach back stops at the
  // oldest served point and the foot says how far that is.
  const limits = useMemo(() => {
    const back = Math.min(winHours * 3_600_000, Math.max(1, nowMs - oldestMs))
    return { oldestMs, newestMs: Math.max(nowMs, estEndMs), spanMs: back + Math.max(0, estEndMs - nowMs) }
  }, [oldestMs, estEndMs, nowMs, winHours])
  const view = useMemo(() => (Number.isFinite(nowMs) ? panView(panMs, limits) : null), [nowMs, panMs, limits])
  const canPan = panBackMs(limits) > 0

  // HOW FAR BACK THE RECORD TRULY REACHES — derived from the served points, never from the window
  // asked for. Said only when the window is more than one slot wider than the record.
  const recordHours = times.length && Number.isFinite(nowMs) ? (nowMs - oldestMs) / 3_600_000 : null
  const slotHours = o ? o.slot_seconds / 3600 : 0
  const shortRecord = recordHours !== null && winHours - recordHours > slotHours

  const arriveMs = focusRow?.arrive_at ? Date.parse(focusRow.arrive_at) : null
  const now = o?.points[0]?.value ?? null
  const firstShown = view ? points.find((_, i) => times[i] >= view.fromMs) : points[0]
  const first = firstShown?.mid ?? null
  const move = now !== null && first ? ((now - first) / first) * 100 : null
  const moveHours = firstShown && Number.isFinite(nowMs) ? (nowMs - Date.parse(firstShown.at)) / 3_600_000 : null
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
            {focusPort ? t('markets.perUnitAt', { port: focusPort.name }) : t('markets.marketPrice')}
          </span>
          {/* BOTH SIDES OF THE PRESSED CITY'S PRICE (owner request 178). `world.price_why` serves the
              ask and the bid for this city and this good — the one authority's own two sides — and the
              page already asks it for the breakdown below, so there is no new read and no derivation
              here. The MIDDLE price keeps its own line under them, because the middle is what the
              chart's line and the record are made of. */}
          <div className="mt-1">
            <PricePair pay={why?.ask ?? null} get={why?.bid ?? null} size="figure" block />
          </div>
          <span className="mt-1 flex flex-wrap items-baseline gap-x-2 gap-y-1 text-t-caption text-ink-faint">
            {now !== null && <span className="tabular-nums">{t('markets.midPrice', { price: formatPrice(now) })}</span>}
            {move !== null && moveHours !== null && (
              <span
                className={[
                  'shrink-0 rounded-chip px-2 text-t-caption tabular-nums',
                  move > 0 ? 'bg-success-soft text-success' : move < 0 ? 'bg-danger-soft text-danger' : 'text-ink-faint',
                ].join(' ')}
              >
                {formatPctChange(move)} · {spanWord(moveHours)}
              </span>
            )}
          </span>
        </div>
        {stock && focusPort && (
          <div className="shrink-0 pt-1 text-right" data-testid="good-stock">
            <span className="block text-t-caption text-ink-faint">{t('markets.stockNormal')}</span>
            <StockGauge stock={stock.stock} target={stock.target} label={t('markets.goodAt', { good: good.name, port: focusPort.name })} />
          </div>
        )}
      </div>

      {/* THE CITIES AND THE WINDOW — one row; a press selects, nothing moves */}
      <div className="mt-3 flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-3">
        <div className="bv-scroll-x flex min-w-0 flex-1 gap-2 overflow-x-auto" role="group" aria-label={t('markets.chartCity')}>
          {chips.map((c) => (
            <Chip key={c} on={c === focus} onClick={() => setFocus(c)} className="shrink-0 whitespace-nowrap">
              <PortFlag code={c} />
              {portNameOf(portByCode, c)}
            </Chip>
          ))}
        </div>
        <Segmented<string>
          segments={DESK_WINDOW_HOURS.map((h) => ({ id: String(h), label: windowWord(h) }))}
          value={String(winHours)}
          onChange={(id) => setWinHours(Number(id))}
          label={t('markets.chartWindow')}
          className="shrink-0 self-start"
        />
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
            view={view}
            pan={{ offsetMs: panMs, limits, onChange: setPanMs }}
            label={t('markets.chartLabel', { good: good.name, port: focusPort?.name ?? t('markets.thisCity') })}
          />
        ) : outlook.loading || !size ? (
          <Skeleton className="h-[220px] w-full" />
        ) : (
          <Note tone="neutral">{t('markets.noEstimate')}</Note>
        )}
      </div>

      {/* THE FOOT: when, how likely, and how far the chart can look. On a phone the likely line wraps to
          two (16 px each): room for FOUR lines is kept, so neither a city's estimate landing (at once,
          when it was asked ahead — 2026-10-19) nor the record's reach / the drag's hint (2026-10-20)
          ever pushes the ticket below it down. Those last two are mutually exclusive by arithmetic —
          one needs a window narrower than the record, the other a window wider — so four is the most
          that can ever stand here: 4 × 16 px and three 2-px gaps = 70 px = 4.375rem (the old figure
          was the same sum over three lines), and 62 px where the likely line does not wrap. */}
      <div className="mt-1 min-h-[4.375rem] space-y-0.5 sm:min-h-[3.875rem]">
        {best ? (
          <p className="text-t-caption text-warning" data-testid="good-best-time">
            {t('markets.bestTime', {
              act: t(sells ? 'markets.act_sell' : 'markets.act_buy'),
              port: focusPort?.name ?? t('markets.thisCity'),
              time: formatClock(Date.parse(best.at)),
            })}
            {formatPrice(best.value)} ({sells ? '+' : '−'}
            {formatFixed(Math.abs(best.gain_pct), 1)} %)
          </p>
        ) : focusRow && b ? (
          <p className="text-t-caption text-ink-faint">{t('markets.noBetter')}</p>
        ) : null}
        {likely && <Hint data-testid="good-likely">{likely}</Hint>}
        {canPan && panMs === 0 && (
          <p className="text-t-caption text-ink-faint" data-testid="good-drag-hint">
            {t('markets.dragBack')}
          </p>
        )}
        {shortRecord && recordHours !== null && (
          <p className="text-t-caption text-ink-faint" data-testid="good-record-reach">
            {t('markets.recordBackTo', { span: t('markets.hours', { n: formatFixed(recordHours, 1) }) })}
          </p>
        )}
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
  return tg('markets.likely', { assumes: o.assumes, lo: formatPriceFigure(p.lo), hi: formatPrice(p.hi), time: formatClock(Date.parse(p.at)) })
}

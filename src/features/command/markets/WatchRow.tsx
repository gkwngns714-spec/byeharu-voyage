import { useEffect, useRef } from 'react'
import { Icon, RarityMark, Sparkline, StockGauge, categoryLabel, goodIcon } from '../../../components/ui'
import { formatInt, formatPctChange, formatPrice } from '../../../lib/format'
import type { SnapshotGood, WatchGood } from '../../../lib/rpc'
import { useT } from '../../../lib/i18n'

// ONE GOOD ON THE MARKETS LIST (docs/COMMAND_DESK.md §3.2) — a broker's row: the mark and the name, a
// sub-line of facts, the record's line, the price, and its move. 52 px, two lines, every figure tabular.
//
// Everything printed is served: the cheapest seller's market price and its hourly record are
// world.watchlist's, the name and the mark are the snapshot's. The change chip carries a sign and a
// tone — green up, red down, read as dearer / cheaper only in tone; a buyer reads red as good news, so
// the chip says the figure, not a verdict.
//
// A PRESS SELECTS (the owner's law): the whole row is one button that opens the good's page in its own
// slot (a tray; beside the column on a wide glass). The row takes the accent wash and nothing on the
// list moves.
//
// A REST ASKS AHEAD (2026-10-19): the pointer resting on a row for PREFETCH_DWELL_MS, or the keyboard's
// focus, calls `onPrefetch` — the good page's reads start before the press (Markets.tsx). A pointer only
// passing over the list asks nothing.

const PREFETCH_DWELL_MS = 150

export function WatchRow({
  good,
  watch,
  on,
  onOpen,
  onPrefetch,
  portName,
}: {
  good: SnapshotGood
  watch: WatchGood | undefined
  /** This good's page is open. */
  on: boolean
  onOpen: () => void
  /** Ask the good page's reads ahead (a rest on the row, or its focus). */
  onPrefetch?: () => void
  portName: (code: string) => string
}) {
  const t = useT()
  const dwell = useRef<number | null>(null)
  const prefetchRef = useRef(onPrefetch)
  useEffect(() => {
    prefetchRef.current = onPrefetch
  })
  const rest = () => {
    if (dwell.current !== null || !prefetchRef.current) return
    dwell.current = window.setTimeout(() => {
      dwell.current = null
      prefetchRef.current?.()
    }, PREFETCH_DWELL_MS)
  }
  const leave = () => {
    if (dwell.current !== null) window.clearTimeout(dwell.current)
    dwell.current = null
  }
  useEffect(() => leave, [])
  const best = watch?.best ?? null
  const change = watch?.change_pct ?? null
  const stock =
    best && typeof best.stock === 'number' && typeof best.stock_target === 'number'
      ? { stock: best.stock, target: best.stock_target }
      : null
  const facts = [
    // WHAT SORT OF GOOD IT IS, first (owner row 177, 2026-10-20): the served `category` through
    // `categoryLabel`, the one reading of it. The rarity keeps its MARK beside the name above.
    categoryLabel(good.category),
    watch ? t('markets.cities', { n: formatInt(watch.sellers), count: watch.sellers }) : null,
    watch && watch.on_board > 0 ? t('markets.onBoardN', { n: formatInt(watch.on_board) }) : null,
    watch && watch.wanted_at.length > 0 ? t('markets.wantedIn', { port: portName(watch.wanted_at[0]) }) : null,
  ].filter(Boolean)
  // The hairline is the row's parting rule (an outer line); the wash is the press's (the button) — two
  // elements, so no className draws a surface with a border (tests/duplication.spec.ts).
  return (
    <div className="border-b border-edge">
      <button
        type="button"
        onClick={onOpen}
        onPointerEnter={rest}
        onPointerLeave={leave}
        onFocus={() => onPrefetch?.()}
        aria-pressed={on}
        className={[
          'flex min-h-row w-full items-center gap-2.5 rounded-control px-2 py-2 text-left transition',
          on ? 'bg-accent-soft' : 'hover:bg-surface-2',
        ].join(' ')}
        data-testid="watch-row"
        data-good={good.code}
      >
        <Icon name={goodIcon(good.code, good.category)} size={20} className="shrink-0 text-ink-muted" />
        <span className="min-w-0 flex-1">
          {/* THE NAME WRAPS, never truncates (2026-10-19: "Abalone …", "Adire Cl…" at 1280): two lines
              at most, the rarity mark riding at its end. */}
          <span className="break-words text-t-body leading-tight text-ink">
            {good.name} <RarityMark rarity={good.rarity} />
          </span>
          {/* THE CHEAPEST SELLER'S STOCK against its normal level (owner, 2026-10-18), then the facts */}
          <span className="mt-0.5 flex min-w-0 items-center gap-2">
            {stock && best && (
              <StockGauge stock={stock.stock} target={stock.target} label={t('markets.goodAt', { good: good.name, port: portName(best.port) })} />
            )}
            {/* ONE LINE, always (2026-10-26): the facts used to wrap, so a row was 58 px or 74 px by how many
                facts the served data happened to carry (a 'wanted in' port, an 'on board' count) and the
                fifth good slid under the fold on some runs. The row is two lines, every row — K.1's
                'five goods above the fold' is a promise about height, so height must not depend on data.
                What does not fit is cut with an ellipsis; the whole line is the title. */}
            <span className="min-w-0 flex-1 truncate text-t-caption text-ink-faint" title={facts.join(' · ')}>
              {facts.join(' · ') || t('markets.soldNowhere')}
            </span>
          </span>
        </span>
        <Sparkline
          values={watch?.spark ?? []}
          tone="even"
          width={40}
          height={18}
          label={t('markets.lastHours', { good: good.name, port: best ? portName(best.port) : t('markets.noCity') })}
          className="hidden shrink-0 min-[360px]:inline-block"
        />
        <span className="flex shrink-0 flex-col items-end">
          <span className="whitespace-nowrap text-t-body tabular-nums text-ink">{best ? formatPrice(best.mid) : '—'}</span>
          {change !== null && (
            <span
              className={[
                'rounded-chip px-1.5 text-t-caption tabular-nums',
                change > 0
                  ? 'bg-success-soft text-success'
                  : change < 0
                    ? 'bg-danger-soft text-danger'
                    : 'text-ink-faint',
              ].join(' ')}
            >
              {formatPctChange(change)}
            </span>
          )}
        </span>
      </button>
    </div>
  )
}

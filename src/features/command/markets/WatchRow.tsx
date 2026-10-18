import { Icon, RarityMark, Sparkline, StockGauge, goodIcon } from '../../../components/ui'
import { formatInt, formatPctChange, formatPrice } from '../../../lib/format'
import type { SnapshotGood, WatchGood } from '../../../lib/rpc'

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

export function WatchRow({
  good,
  watch,
  on,
  onOpen,
  portName,
}: {
  good: SnapshotGood
  watch: WatchGood | undefined
  /** This good's page is open. */
  on: boolean
  onOpen: () => void
  portName: (code: string) => string
}) {
  const best = watch?.best ?? null
  const change = watch?.change_pct ?? null
  const stock =
    best && typeof best.stock === 'number' && typeof best.stock_target === 'number'
      ? { stock: best.stock, target: best.stock_target }
      : null
  const facts = [
    watch ? `${formatInt(watch.sellers)} ${watch.sellers === 1 ? 'city' : 'cities'}` : null,
    watch && watch.on_board > 0 ? `${formatInt(watch.on_board)} on board` : null,
    watch && watch.wanted_at.length > 0 ? `Wanted in ${portName(watch.wanted_at[0])}` : null,
  ].filter(Boolean)
  // The hairline is the row's parting rule (an outer line); the wash is the press's (the button) — two
  // elements, so no className draws a surface with a border (tests/duplication.spec.ts).
  return (
    <div className="border-b border-edge">
      <button
        type="button"
        onClick={onOpen}
        aria-pressed={on}
        className={[
          'flex min-h-row w-full items-center gap-3 rounded-control px-2 py-2 text-left transition',
          on ? 'bg-accent-soft' : 'hover:bg-surface-2',
        ].join(' ')}
        data-testid="watch-row"
        data-good={good.code}
      >
        <Icon name={goodIcon(good.code, good.category)} size={20} className="shrink-0 text-ink-muted" />
        <span className="min-w-0 flex-1">
          <span className="flex items-center gap-1.5 truncate text-t-body text-ink">
            <span className="truncate">{good.name}</span>
            <RarityMark rarity={good.rarity} />
          </span>
          {/* THE CHEAPEST SELLER'S STOCK against its normal level (owner, 2026-10-18), then the facts */}
          <span className="flex min-w-0 items-center gap-2">
            {stock && best && (
              <StockGauge stock={stock.stock} target={stock.target} label={`${good.name} at ${portName(best.port)}`} />
            )}
            <span className="truncate text-t-caption text-ink-faint">{facts.join(' · ') || 'Sold nowhere'}</span>
          </span>
        </span>
        <Sparkline
          values={watch?.spark ?? []}
          tone="even"
          width={56}
          height={20}
          label={`${good.name}, the last hours at ${best ? portName(best.port) : 'no city'}`}
          className="hidden shrink-0 min-[360px]:inline-block"
        />
        <span className="flex min-w-20 shrink-0 flex-col items-end">
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

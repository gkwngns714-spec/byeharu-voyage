import { Button, Hint, Icon, Skeleton, Sparkline, goodIcon } from '../../../components/ui'
import { usePriceSeries } from '../../../live/usePriceSeries'
import { formatInt, formatPriceFigure } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import { dayLine } from './dayLine'
import type { TradeGoodRow } from './tradeRows'

// THE COMBINED TRADE BOARD (owner 2026-10-30: *"removing the map, just have combined buy and sell tab with trade
// goods when docked"*) — the docked city's goods in ONE list, each row showing the city's ASK (Buy) and BID (Sell)
// side by side, so a trade is one press, not a face turn. It replaces the mirrored Buy / Sell cards (CityBoard.tsx),
// and with them the mini-map and the cross-city chips: trade happens where she lies, nowhere else. The rows are
// tradeRows.ts — a pure function, so this file holds only the cards.

/** ▲ +3.2 % / ▼ 1.4 % — green up, red down, nothing else coloured (owner row 229). */
export function DayChange({ change, className = '' }: { change: number | null; className?: string }) {
  if (change === null) return <span className={`text-t-caption text-ink-faint ${className}`}>—</span>
  const pts = Math.abs(change * 100)
  if (pts < 0.05) return <span className={`text-t-caption tabular-nums text-ink-faint ${className}`}>0.0%</span>
  const up = change > 0
  return (
    <span className={`whitespace-nowrap text-t-caption tabular-nums ${up ? 'text-success' : 'text-danger'} ${className}`} data-testid="day-change" data-dir={up ? 'up' : 'down'}>
      {up ? '▲' : '▼'} {formatFixed(pts, 1)}%
    </span>
  )
}

function formatFixed(pts: number, d: number) {
  return pts.toFixed(d)
}

export function TradeBoard({
  portId,
  rows,
  picked,
  onBuy,
  onSell,
}: {
  /** The docked city's id, for each good's 1-day line. */
  portId: string | null
  rows: readonly TradeGoodRow[]
  /** The good whose panel is open. */
  picked: string | null
  onBuy: (code: string) => void
  onSell: (code: string) => void
}) {
  const t = useT()
  if (rows.length === 0) {
    return <Hint data-testid="trade-board-empty">{t('desk.noBuy')}</Hint>
  }
  return (
    <div className="grid grid-cols-2 gap-2 lg:grid-cols-3" data-testid="trade-board">
      {rows.map((r) => (
        <TradeRow key={r.code} portId={portId} r={r} on={picked === r.code} onBuy={onBuy} onSell={onSell} />
      ))}
    </div>
  )
}

function TradeRow({
  portId,
  r,
  on,
  onBuy,
  onSell,
}: {
  portId: string | null
  r: TradeGoodRow
  /** This good's panel is open. */
  on: boolean
  onBuy: (code: string) => void
  onSell: (code: string) => void
}) {
  const t = useT()
  const priced = r.goodId !== null && r.buy !== null
  const trend = usePriceSeries(priced ? portId : null, priced ? r.goodId : null, '1d')
  const line = dayLine(trend.series, 'buy', r.buy)
  const buyDead = r.buy === null
  const sellDead = r.sell === null || r.units <= 0
  return (
    <div
      className={[
        'flex min-w-0 flex-col gap-1 rounded-md p-2 text-left transition',
        on ? 'bg-accent-soft ring-1 ring-accent' : 'bg-surface-2',
      ].join(' ')}
      data-testid="trade-good"
      data-good={r.code}
    >
      <span className="flex min-w-0 items-start gap-1.5">
        <Icon name={goodIcon(r.code, r.category)} size={18} className="mt-px shrink-0 text-ink-muted" />
        <span className="min-w-0 break-words text-t-label font-medium leading-tight text-ink" data-testid="trade-good-name">{r.name}</span>
        <span className={`ml-auto shrink-0 text-t-caption tabular-nums ${r.units > 0 ? 'text-ink' : 'text-ink-faint'}`} data-testid="trade-good-aboard">
          {t('desk.aboardN', { n: formatInt(r.units) })}
        </span>
      </span>
      <span className="flex items-baseline justify-between gap-1">
        <span className={`text-t-body font-semibold tabular-nums ${buyDead ? 'text-ink-faint' : 'text-ink'}`} data-testid="trade-good-buy">
          {buyDead ? '—' : formatPriceFigure(r.buy as number)}
        </span>
        <span className={`text-t-body font-semibold tabular-nums ${sellDead ? 'text-ink-faint' : 'text-ink'}`} data-testid="trade-good-sell">
          {sellDead ? t('desk.noBuyer') : formatPriceFigure(r.sell as number)}
        </span>
      </span>
      <span className="flex h-4 min-w-0 flex-1 items-center" data-testid="trade-good-spark" data-points={line.values.length}>
        {!buyDead && <Sparkline values={line.values} width={96} height={16} className="h-4 w-full" />}
      </span>
      <span className="flex items-center gap-2">
        <Button variant="secondary" className="flex-1" onClick={() => onBuy(r.code)} disabled={buyDead} data-testid="trade-buy">
          {t('desk.buy')}
        </Button>
        <Button variant="secondary" className="flex-1" onClick={() => onSell(r.code)} disabled={sellDead} data-testid="trade-sell">
          {t('desk.sell')}
        </Button>
      </span>
    </div>
  )
}

// The Skeleton for a quay still reading (the board's loading state is the caller's — the rows are empty until then).
export function TradeBoardSkeleton() {
  return (
    <div className="grid grid-cols-2 gap-2 lg:grid-cols-3">
      {Array.from({ length: 6 }, (_, i) => (
        <Skeleton key={i} className="h-28 w-full" />
      ))}
    </div>
  )
}

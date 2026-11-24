// A price's move over the day: an arrow and a percentage, toned by whether it is good for the side read (here since H3,
// 2026-11-24: it stood in TradeBoard.tsx, the desk's goods board, which went with the desk).

export function DayChange({ change, side = 'sell', className = '' }: { change: number | null; side?: 'buy' | 'sell'; className?: string }) {
  if (change === null) return <span className={`text-t-caption text-ink-faint ${className}`}>—</span>
  const pts = Math.abs(change * 100)
  if (pts < 0.05) return <span className={`text-t-caption tabular-nums text-ink-faint ${className}`}>0.0%</span>
  const up = change > 0
  const good = up === (side === 'sell')
  return (
    <span className={`whitespace-nowrap text-t-caption tabular-nums ${good ? 'text-success' : 'text-danger'} ${className}`} data-testid="day-change" data-dir={up ? 'up' : 'down'}>
      {up ? '▲' : '▼'} {formatFixed(pts, 1)}%
    </span>
  )
}

function formatFixed(pts: number, d: number) {
  return pts.toFixed(d)
}

/** How many harbours the chip strip names — a short strip, not a directory. */

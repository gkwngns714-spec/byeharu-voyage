// SIGNED BARS — one bar a period, up for a gain and down for a loss, from the one zero line.
//
// THE IDIOM IS THE COMMAND DESK'S (features/command/profit/Profit.tsx, 2026-10-17): "seven bars,
// one a day, green or red by sign, the zero line their only axis; the bars' heights are the served
// nets scaled to the tallest — presentation, not arithmetic about money." It was written by hand
// there, and the Stats tab wants exactly it three more times (your own last days, the world's new
// money a quarter hour, a city's income against its spending), so it is the system's now and
// Profit composes this instead of its own grid.
//
// WHY BARS AND NOT A LINE. A line is for a LEVEL that moves (a purse, a price); these are
// PER-PERIOD AMOUNTS, each one its own thing, and a line drawn through them invents a path between
// two separate facts. The zero line is the axis, so the sign is read from which way the bar grows
// before any colour is involved.
//
// WHAT IT REFUSES. No labels on the bars (a number on every bar is unreadable at this size — the
// figures beside the chart carry the sizes), no interpolation, and nothing at all below one bar.
// The whole row is one `role="img"` with the caller's sentence, because twenty bars are one picture
// to anybody who cannot see them.

export function SignedBars({
  bars,
  label,
  height = 'h-24',
  className = '',
  ...rest
}: {
  /** Oldest first. `value` may be negative; zero draws no bar, only the line. A caller with more
   *  periods than a phone has pixels hands over the LAST ones — a bar narrower than its own gap is
   *  not a bar (about forty is the most that reads at 390px). */
  bars: readonly { id: string; value: number }[]
  /** The picture, in one sentence, for assistive tech ("what you earned each of the last 7 days"). */
  label: string
  /** The row's height as a utility class — the only thing a caller tunes. */
  height?: string
  className?: string
} & { 'data-testid'?: string }) {
  if (bars.length === 0) return null
  const top = Math.max(1, ...bars.map((b) => Math.abs(b.value)))

  return (
    <div
      className={`grid ${height} gap-0.5 ${className}`}
      style={{ gridTemplateColumns: `repeat(${bars.length}, minmax(0, 1fr))` }}
      role="img"
      aria-label={label}
      {...rest}
    >
      {bars.map((b) => (
        <div key={b.id} className="relative h-full">
          <div className="absolute inset-x-0 top-1/2 h-px bg-edge" />
          {b.value !== 0 && (
            // CAPPED AT 24px AND CENTRED IN ITS SLOT: a bar is a mark, and a bar that fills its
            // whole slot is a block. Seven days across a sheet would be 47px slabs otherwise.
            <div
              className={`absolute left-1/2 w-full max-w-6 -translate-x-1/2 rounded-chip ${b.value > 0 ? 'bottom-1/2 bg-success' : 'top-1/2 bg-danger'}`}
              style={{ height: `${(Math.abs(b.value) / top) * 50}%` }}
            />
          )}
        </div>
      ))}
    </div>
  )
}

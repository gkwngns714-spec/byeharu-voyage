import { useState } from 'react'
import { Figure, PriceRows, Row, Tray, type TrayDetent } from '../../components/ui'
import { formatInt, formatMiles } from '../../lib/format'
import type { MarketGood, PricePoint } from '../../lib/rpc'

// A GOOD, READ ON A QUAY SHE IS NOT ON — the tray a price cell opens when nobody of yours is
// alongside. MOVED 2026-09-11 from features/market/ with the MARKET tab, which folded into PORT
// (owner row 76, docs/QUAY_LEDGER.md §6 slice 1; RESUME.md had carried the fold as owed).
//
// The two prices, then the same Trend, Range and On-the-quay rows the trade tray draws —
// `PriceRows`, the design system's, composed from the one entrance and never retyped here — then
// how far this quay is from where she lies, as a figure. This file is not a third trade tray: it
// steps nothing, prices nothing and issues nothing.
//
// ── `Sail here` IS GONE (2026-09-09) ───────────────────────────────────────────────────────────
// It was a button that handed a SAIL intent to COMMAND's composer. The owner: *"they should be
// located accordingly at different locations"* — and SAIL's location is the MAP, where the owner
// drove it on production (docs/OWNER_REQUESTS.md rows 45/46). The passage stays as the figure it
// always was, and the act is one tab over, where every other passage is ordered from.

export function PriceTray({
  good,
  points,
  passage,
  onClose,
}: {
  good: MarketGood
  points: readonly PricePoint[] | undefined
  /** The sailed distance from where she lies to this quay, or null when there is no figure. */
  passage: number | null
  onClose: () => void
}) {
  const [detent, setDetent] = useState<TrayDetent>('half')
  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={good.name}
      data-testid="price-tray"
    >
      <Row label="Buy" value={<Figure value={formatInt(good.buy)} size="figure" />} />
      <Row label="Sell" value={<Figure value={formatInt(good.sell)} size="figure" />} />
      <PriceRows good={good} points={points} />
      {passage !== null && (
        <Row
          label="Distance"
          value={<Figure value={formatMiles(passage)} />}
          hairline={false}
          data-testid="price-tray-passage"
        />
      )}
    </Tray>
  )
}

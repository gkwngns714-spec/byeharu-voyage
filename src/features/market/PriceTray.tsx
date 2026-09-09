import { useState } from 'react'
import { Bar, Figure, Row, Sparkline, Tray, type TrayDetent } from '../../components/ui'
import { formatInt, formatNm, formatTuns } from '../../lib/format'
import type { MarketGood, PricePoint } from '../../lib/rpc'

// WHAT A PRICE HAS BEEN, AND HOW FAR IT CAN GO — the rows under a good, on a quay she is not on.
//
// docs/UI_DIRECTION.md §6, MARKET: "tap → tray: 30-day trend, range, stock". The tile carries
// today's two prices and the range as a bar; the tray carries what does not fit on a tile — the
// remembered line, the range as figures, the stock as figures — and how far this quay is from
// where she lies, as a figure.
//
// ── `Sail here` IS GONE (2026-09-09) ───────────────────────────────────────────────────────────
// It was a button that handed a SAIL intent to COMMAND's composer. The owner: *"they should be
// located accordingly at different locations"* — and SAIL's location is the MAP, where the owner
// drove it on production (docs/OWNER_REQUESTS.md rows 45/46): tap a harbour, `Send fleet`, pick
// her, send. COMMAND composes nothing now, so a button that led there would lead nowhere; the
// passage stays as the figure it always was, and the act is one tab over, where every other
// passage is ordered from. A second doorway to a door that exists is the thing this slice deletes.
//
// TWO TRAYS, ONE SET OF ROWS. When a fleet of yours is alongside the harbour being read, a price
// cell opens the design system's `TradeTray` exactly as PORT opens it, and `PriceRows` rides
// inside it as its `children`. When nobody is alongside there is no quantity to step and nothing
// to issue, so the rows stand in this plain `Tray`. This file is not a third trade tray: it steps
// nothing, prices nothing and issues nothing.
//
// THE TREND KEEPS ITS AUSTERITY (Sparkline.tsx): the shape of the move, no axes, no interpolation,
// nothing below two points. A good the record has not sampled twice says so in a row rather than
// drawing a dot on an empty box.

export function PriceRows({
  good,
  points,
}: {
  good: MarketGood
  /** The remembered mids for THIS good at THIS port, oldest first; undefined until the read lands. */
  points: readonly PricePoint[] | undefined
}) {
  const mids = (points ?? []).map((pt) => pt.mid)
  return (
    <>
      <Row label="Trend" tone={mids.length < 2 ? 'muted' : 'default'}>
        {mids.length < 2 ? (
          <span className="block text-t-caption">Not remembered here yet.</span>
        ) : (
          <Sparkline
            values={mids}
            width={320}
            height={40}
            className="mt-1 h-10 w-full"
            label={`${good.name}: ${mids.length} remembered prices, ${formatInt(Math.min(...mids))} to ${formatInt(Math.max(...mids))}`}
          />
        )}
      </Row>
      <Row label="Range" value={<Figure value={`${formatInt(good.range_lo)}–${formatInt(good.range_hi)}`} />} />
    </>
  )
}

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
        <Row label="Passage" value={<Figure value={formatNm(passage)} />} data-testid="price-tray-passage" />
      )}
      <Row
        label="On the quay"
        value={<Figure value={formatTuns(good.stock)} unit={`of ${formatTuns(good.stock_target)}`} />}
        hairline={false}
      >
        <Bar
          value={good.stock_band}
          of={6}
          tone={good.stock_band <= 1 ? 'warning' : 'neutral'}
          label={`${good.name} in stock`}
          className="mt-1"
        />
      </Row>
    </Tray>
  )
}

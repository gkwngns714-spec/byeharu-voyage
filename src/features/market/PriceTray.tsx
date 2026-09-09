import { useState } from 'react'
import { Bar, Button, Figure, Row, Sparkline, Tray, type TrayDetent } from '../../components/ui'
import { formatInt, formatNm, formatTuns } from '../../lib/format'
import type { MarketGood, PricePoint } from '../../lib/rpc'

// WHAT A PRICE HAS BEEN, AND HOW FAR IT CAN GO — the rows under a good, on a quay she is not on.
//
// docs/UI_DIRECTION.md §6, MARKET: "tap → tray: 30-day trend, range, stock; [Sail here] if not
// docked". The tile carries today's two prices and the range as a bar; the tray carries what does
// not fit on a tile — the remembered line, the range as figures, the stock as figures — and the
// ONE act a distant price can lead to, which is a passage.
//
// TWO TRAYS, ONE SET OF ROWS. When a fleet of yours is alongside the harbour being read, a price
// cell opens the design system's `TradeTray` exactly as PORT and COMMAND open it, and `PriceRows`
// rides inside it as its `children` — the same rows, under the same stock line, above the same
// button. When nobody is alongside there is no quantity to step and nothing to issue, so the rows
// stand in this plain `Tray` with `Sail here` at the bottom edge. This file is not a third trade
// tray: it steps nothing, prices nothing and issues nothing.
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
  sail,
  onClose,
}: {
  good: MarketGood
  points: readonly PricePoint[] | undefined
  /** The passage this price is worth, or null when no fleet of yours can be sent. */
  sail: { nm: number | undefined; onSail: () => void } | null
  onClose: () => void
}) {
  const [detent, setDetent] = useState<TrayDetent>('half')
  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={good.name}
      data-testid="price-tray"
      action={
        sail ? (
          <Button variant="primary" className="w-full" onClick={sail.onSail} data-testid="price-tray-sail">
            {sail.nm === undefined ? 'Sail here' : `Sail here · ${formatNm(sail.nm)}`}
          </Button>
        ) : undefined
      }
    >
      <Row label="Buy" value={<Figure value={formatInt(good.buy)} size="figure" />} />
      <Row label="Sell" value={<Figure value={formatInt(good.sell)} size="figure" />} />
      <PriceRows good={good} points={points} />
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

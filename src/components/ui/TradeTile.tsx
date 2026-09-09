import { Bar } from './Bar'
import { Figure } from './Figure'
import { goodIcon } from './goodIcons'
import { Icon } from './Icon'
import { Tile } from './Tile'
import { formatInt } from '../../lib/format'
import type { MarketGood } from '../../lib/rpc'

// THE GOOD'S TILE, WITH ITS TWO PRICES AS THE TWO ACTS — docs/UI_DIRECTION.md §6.
//
// One tile for every quay that trades: PORT's Trade face and COMMAND's BUY/SELL question compose
// THIS, so a good cannot look different on the two screens a player buys it from. It lives in the
// design system for the reason tradePickers.tsx gave the fold it replaces: tests/sections.spec.ts
// refuses to let one screen import another, and a tile both quays draw was never either quay's.
//
// The owner's row 6, kept literally: *"i want to be able to click on buy and sell itself and do
// trades."* Both prices are real 44px buttons, and a dead one says WHY on its own face — a cell
// that goes grey with no reason is the defect tests/layout.spec.ts was written to stop. What a
// press OPENS is the caller's affair (a `TradeTray`); this tile never inserts anything into the
// grid it stands in, which is what lets the field hold still under the finger.
//
// Under the prices: where today's ask stands inside the range this quay can reach (0071), and the
// stock in the six blocks the server bands it into. Neutral until it is nearly out — §4.4 keeps
// green and red for cheap-and-dear, and a full quay painted green on every tile would spend the
// one colour that means "gain" on a quantity.

export function TradeTile({
  good,
  aboard,
  canBuy,
  selected = false,
  onBuy,
  onSell,
}: {
  good: MarketGood
  /** Tuns of THIS good aboard — the fleet's own manifest, folded by the caller. */
  aboard: number
  /** 0061's one answer to "can this be bought at this quay" — `buyableHere`, folded by the caller. */
  canBuy: boolean
  selected?: boolean
  onBuy: () => void
  onSell: () => void
}) {
  return (
    <Tile
      mark={<Icon name={goodIcon(good.code, good.category)} size={20} className="text-ink-muted" />}
      name={good.name}
      state={selected ? 'selected' : canBuy || aboard > 0 ? 'rest' : 'muted'}
      data-testid="good-pick-tile"
    >
      <span className="grid grid-cols-2 gap-1">
        <PriceCell label="buy" price={good.buy} onPress={onBuy} dead={canBuy ? null : 'not traded here'} />
        <PriceCell label="sell" price={good.sell} onPress={onSell} dead={aboard > 0 ? null : 'none aboard'} />
      </span>
      <Bar pct={span(good)} tone="neutral" label={`${good.name} price range`} />
      <span className="flex justify-between text-t-caption text-ink-faint">
        <span className="tabular-nums">{formatInt(good.range_lo)}</span>
        <span className="tabular-nums">{formatInt(good.range_hi)}</span>
      </span>
      <Bar
        value={good.stock_band}
        of={6}
        tone={good.stock_band <= 1 ? 'warning' : 'neutral'}
        label={`${good.name} in stock`}
      />
    </Tile>
  )
}

/** Where today's ask stands inside the range, 0–100. A band of zero width reads as full. */
function span(g: MarketGood): number {
  const width = g.range_hi - g.range_lo
  if (!(width > 0)) return 100
  return ((g.buy - g.range_lo) / width) * 100
}

/** One price, and the tap that makes it a trade. The label and the figure are what layout.spec
 *  counts; the reason line is what keeps a dead cell honest. */
function PriceCell({
  label,
  price,
  onPress,
  dead,
}: {
  label: 'buy' | 'sell'
  price: number
  onPress: () => void
  /** Why this cell cannot be pressed, or null when it can. */
  dead: string | null
}) {
  return (
    <button
      type="button"
      onClick={onPress}
      disabled={dead !== null}
      className="min-h-11 rounded-control bg-surface-2 px-2 py-1 text-left disabled:opacity-45"
    >
      <span className="block text-t-caption text-ink-faint">{label}</span>
      <Figure value={formatInt(price)} />
      {dead !== null && <span className="block text-t-caption text-ink-faint">{dead}</span>}
    </button>
  )
}

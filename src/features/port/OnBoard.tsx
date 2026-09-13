import { Bar, Figure, PriceCell, Row, SheetSection } from '../../components/ui'
import { fleetCargo, paidPerTun } from '../../domain/fleet'
import { buyableHere } from '../../domain/market'
import { formatDucatsDelta, formatInt, formatTons, formatUnits } from '../../lib/format'
import type { FleetView, MarketGood } from '../../lib/rpc'
import { useSellEstimate } from '../../live/useSellEstimate'
import { useWorld } from '../../live/worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT THE SHIP CARRIES — beside the basket, as rows shaped like the board, with the sale drawn.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-09-13: *"in trade, basket, show what i own right now too"* (row 81), then *"show
// buy, sell price in trade, on board, and show how much loss/profit the action will do. make it
// graphic not in words ordered in line"* (row 82). So each good on board that this market lists is
// a row of the board's own shape — the name, the lot, the two price cells as the tap targets — and
// under it THE SALE AS A PICTURE: a bar from what it was bought at to what it sells for now, green
// past the cost or red short of it, with the served profit of selling the whole lot beside it.
//
// ── WHAT IS SERVED, WHAT IS DRAWN ──────────────────────────────────────────────────────────────
// Bought-at is `FleetView.cargo_basis` through `paidPerTun`; the sell price is the market row's;
// the profit is `cmd.preview` of SELL-all (useSellEstimate.ts) — never `(sell − paid) × units` on
// this side of the wire, because a sale walks the book. The bar only PLACES the two served prices
// on one track: the larger of the two fills it, so the wash is exactly the gap between them.
//
// A good this market does not list has no price here: its row is the lot and `not traded here`,
// and no cell. A lot whose cost is not on record draws the sell price alone and says so.

export function OnBoard({
  fleet,
  goods,
  onBuy,
  onSell,
}: {
  fleet: FleetView
  /** This market's rows — a good among them can be traded from here. */
  goods: readonly MarketGood[]
  onBuy: (good: MarketGood) => void
  onSell: (good: MarketGood) => void
}) {
  const goodByCode = useWorld((s) => s.goodByCode)
  const lines = fleetCargo(fleet)
  return (
    <SheetSection heading="On board" data-testid="on-board">
      {lines.length === 0 ? (
        <Row label="No cargo on board." tone="muted" hairline={false} />
      ) : (
        lines.map((line, i) => (
          <OnBoardRow
            key={line.code}
            fleet={fleet}
            code={line.code}
            units={line.qty}
            name={goodByCode[line.code]?.name ?? line.code}
            bulk={goodByCode[line.code]?.bulk ?? 1}
            here={goods.find((g) => g.code === line.code) ?? null}
            last={i === lines.length - 1}
            onBuy={onBuy}
            onSell={onSell}
          />
        ))
      )}
    </SheetSection>
  )
}

function OnBoardRow({
  fleet,
  code,
  units,
  name,
  bulk,
  here,
  last,
  onBuy,
  onSell,
}: {
  fleet: FleetView
  code: string
  units: number
  name: string
  bulk: number
  here: MarketGood | null
  last: boolean
  onBuy: (good: MarketGood) => void
  onSell: (good: MarketGood) => void
}) {
  const paid = paidPerTun(fleet, code)
  const sale = useSellEstimate(fleet, here, units)
  const profit = sale.estimate?.profit ?? null
  const gain = profit === null ? null : profit >= 0
  // THE PICTURE: both prices on one track; the larger fills it; the wash is the gap, in the sign's
  // colour. Placement only — no figure on screen comes from this arithmetic.
  const track = here ? Math.max(paid ?? 0, here.sell) : 0
  const paidPct = track > 0 && paid !== null ? (paid / track) * 100 : 0
  const gapPct = track > 0 && paid !== null && here ? ((here.sell - paid) / track) * 100 : 0

  return (
    // THE ROW, THEN THE PICTURE UNDER IT AT FULL WIDTH. Row's own child slot sits under the label
    // column, which in a 26-rem panel beside two price cells is too narrow for a bar to be read.
    <div data-testid={`on-board-${code}`} className={last ? '' : 'border-b border-edge'}>
      <Row
        label={
          <span className="flex flex-wrap items-center gap-x-1.5 text-t-body">
            <span className="max-w-full truncate">{name}</span>
            <span className="text-t-caption text-ink-faint">{`· ${formatUnits(units)} · ${formatTons(units * bulk, 1)}`}</span>
          </span>
        }
        value={
          here ? (
            <span className="grid grid-cols-2 gap-1">
              <PriceCell label="buy" price={here.buy} onPress={() => onBuy(here)} dead={buyableHere(here) ? null : 'not traded here'} selected={false} />
              <PriceCell label="sell" price={here.sell} onPress={() => onSell(here)} dead={null} selected={false} />
            </span>
          ) : (
            <span className="text-t-caption text-ink-faint">not traded here</span>
          )
        }
        hairline={false}
      />
      {here && (
        <div className="flex items-center gap-2 pb-2" data-testid={`on-board-sale-${code}`}>
          <span className="shrink-0 text-t-caption text-ink-faint">{paid === null ? 'cost unknown' : `bought ${formatInt(paid)}`}</span>
          <Bar
            pct={paid === null ? 100 : paidPct}
            pending={paid === null ? undefined : gapPct}
            tone="neutral"
            pendingTone={gain === false ? 'danger' : 'success'}
            label={`${name}: bought at ${paid === null ? 'unknown' : formatInt(paid)}, sells at ${formatInt(here.sell)}`}
            className="min-w-0 flex-1"
          />
          <span className="shrink-0 text-t-caption text-ink-faint">{`sells ${formatInt(here.sell)}`}</span>
          {profit !== null && <Figure value={formatDucatsDelta(profit)} tone={gain ? 'success' : 'danger'} />}
        </div>
      )}
    </div>
  )
}

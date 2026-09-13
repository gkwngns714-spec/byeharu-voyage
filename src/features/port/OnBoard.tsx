import { Figure, Row, SheetSection } from '../../components/ui'
import { fleetCargo, paidPerTun } from '../../domain/fleet'
import { formatTons, formatUnitPrice, formatUnits } from '../../lib/format'
import type { FleetView, MarketGood } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT THE SHIP CARRIES — beside the basket, because a trader decides what to SELL by looking at
// what is on board, not by scrolling the board for the rows that say "N units on board".
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-09-13: *"in trade, basket, show what i own right now too"* (row 81). The reference
// trade house shows the hold beside the basket for the same reason. One row per good aboard: the
// name, the units and the tons they take, and what it was bought at when the record has it
// (`FleetView.cargo_basis` through `paidPerTun` — served, never remembered). A row whose good this
// market lists is a press: it opens that good's SELL side in the same slot. A good this market does
// not list has no price here, so its row is a fact and not a press, and says so.
//
// Nothing here is folded: `fleetCargo` is the one reading of the cargo map, `goodByCode` the
// catalogue's bulk and name, and the market rows the caller already holds decide pressability.

export function OnBoard({
  fleet,
  goods,
  onSell,
}: {
  fleet: FleetView
  /** This market's rows — a good among them can be sold from here. */
  goods: readonly MarketGood[]
  onSell: (good: MarketGood) => void
}) {
  const goodByCode = useWorld((s) => s.goodByCode)
  const lines = fleetCargo(fleet)
  return (
    <SheetSection heading="On board" data-testid="on-board">
      {lines.length === 0 ? (
        <Row label="No cargo on board." tone="muted" hairline={false} />
      ) : (
        lines.map((line, i) => {
          const catalogue = goodByCode[line.code]
          const here = goods.find((g) => g.code === line.code) ?? null
          const paid = paidPerTun(fleet, line.code)
          const tons = formatTons(line.qty * (catalogue?.bulk ?? 1), 1)
          return (
            <Row
              key={line.code}
              label={catalogue?.name ?? here?.name ?? line.code}
              value={<Figure value={formatUnits(line.qty)} />}
              chevron={here !== null}
              onClick={here ? () => onSell(here) : undefined}
              hairline={i < lines.length - 1}
              data-testid={`on-board-${line.code}`}
            >
              <span className="block text-t-caption text-ink-faint">
                {[tons, paid === null ? null : `bought at ${formatUnitPrice(paid)}`, here ? null : 'not traded here']
                  .filter(Boolean)
                  .join(' · ')}
              </span>
            </Row>
          )
        })
      )}
    </SheetSection>
  )
}

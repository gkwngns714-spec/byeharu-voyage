import { Figure, goodIcon, Icon, Row } from '../../components/ui'
import { formatFixed, formatInt } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import type { FleetView } from '../../lib/rpc'
import { fleetCargo } from '../../domain/fleet'

// WHAT SHE CARRIES, AS ROWS — and every row is the act of selling it.
//
// It was a three-column table (Good · Units · Bulk) with the name as a link and a `stowed` total
// row. A `Row` is the whole 52px band as the tap target, with the chevron saying it opens
// something: SELL on COMMAND, aimed at this fleet and this good, the quantity picker open.
//
// THE FIGURE IS A COUNT, NOT A TONNAGE. `FleetShip.cargo` counts a good as the market counts it,
// and bulk (0.2–1.5 t a unit across data/goods.json) is applied by the server into `cargo_tuns`.
// Printing the count with a `t` after it would be wrong by the bulk on 397 of 523 goods, so the
// count rides bare and the hold-space truth — the served tuns — is the one closing row, where it
// agrees with the hold figures the tray prints elsewhere. No average-cost column: the server
// carries what is aboard, not what it cost; the price paid is on the Ledger.

export function FleetCargo({ fleet, onSell }: { fleet: FleetView; onSell: (goodCode: string) => void }) {
  const goodByCode = useWorld((s) => s.goodByCode)
  const cargo = fleetCargo(fleet)

  if (cargo.length === 0) {
    return <Row label="Her hold is empty." tone="muted" hairline={false} />
  }

  return (
    <>
      {cargo.map((line) => {
        const good = goodByCode[line.code]
        return (
          <Row
            key={line.code}
            mark={<Icon name={goodIcon(line.code, good?.category ?? '')} size={20} />}
            label={good?.name ?? line.code}
            value={<Figure value={formatInt(line.qty)} />}
            chevron
            onClick={() => onSell(line.code)}
            data-testid="fleet-cargo-row"
          />
        )
      })}
      <Row
        label="Stowed"
        tone="muted"
        value={<Figure value={formatFixed(fleet.ships.reduce((n, s) => n + s.cargo_tuns, 0), 1)} unit="t" />}
        hairline={false}
      />
    </>
  )
}

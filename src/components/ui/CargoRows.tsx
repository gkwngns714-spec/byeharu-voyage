import { formatFixed, formatInt } from '../../lib/format'
import { Figure } from './Figure'
import { goodIcon } from './goodIcons'
import { Icon } from './Icon'
import { Row } from './Row'

// WHAT A FLEET CARRIES, AS ROWS — moved here from features/fleets/FleetCargo.tsx (2026-10-08) so
// your fleet and a merchant's print one shape (docs/NPC_TRADERS.md §8.3). PURE PROPS: the caller
// resolves each good's name and category (FLEETS through the world's goods, the merchant sheet the
// same way), and hands the served total tuns.
//
// THE FIGURE IS A COUNT, NOT A TONNAGE: a good is counted as the market counts it, and the hold
// truth — the served tuns — is the one closing row.
export function CargoRows({
  rows,
  totalTons,
  testId = 'fleet-cargo-row',
}: {
  rows: readonly { code: string; name: string; category: string; qty: number }[]
  totalTons: number
  testId?: string
}) {
  if (rows.length === 0) {
    return <Row label="No cargo on board." tone="muted" hairline={false} />
  }
  return (
    <>
      {rows.map((line) => (
        <Row
          key={line.code}
          mark={<Icon name={goodIcon(line.code, line.category)} size={20} />}
          label={line.name}
          value={<Figure value={formatInt(line.qty)} />}
          data-testid={testId}
        />
      ))}
      <Row label="Total" tone="muted" value={<Figure value={formatFixed(totalTons, 1)} unit="tons" />} hairline={false} />
    </>
  )
}

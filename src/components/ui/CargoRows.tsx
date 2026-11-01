import { formatFixed, formatInt } from '../../lib/format'
import { Figure } from './Figure'
import { goodIcon } from './goodIcons'
import { goodClassRow } from './goodClassTiers'
import { GoodKind } from './GoodKind'
import { Icon } from './Icon'
import { Row } from './Row'
import { useT } from '../../lib/i18n'

// WHAT A FLEET CARRIES, AS ROWS — moved here from features/fleets/FleetCargo.tsx (2026-10-08) so
// your fleet and a merchant's print one shape (docs/NPC_TRADERS.md §8.3). PURE PROPS: the caller
// resolves each good's name and category (FLEETS through the world's goods, the merchant sheet the
// same way), and hands the served total tuns.
//
// THE FIGURE IS A COUNT, NOT A TONNAGE: a good is counted as the market counts it, and the hold
// truth — the served tuns — is the one closing row.
//
// THE PREMIUM CLASS (0294) RIDES WITH THE NAME, as the Market rows draw it: `class` is the served number
// the caller read off the catalogue by code (the same lookup that gave it the name and the category),
// and a good the catalogue has no class for draws nothing.
export function CargoRows({
  rows,
  totalTons,
  testId = 'fleet-cargo-row',
}: {
  rows: readonly { code: string; name: string; category: string; qty: number; class?: number }[]
  totalTons: number
  testId?: string
}) {
  const t = useT()
  if (rows.length === 0) {
    return <Row label={t('ui.noCargo')} tone="muted" hairline={false} />
  }
  return (
    <>
      {rows.map((line) => (
        <Row
          key={line.code}
          {...goodClassRow(line.class)}
          mark={<Icon name={goodIcon(line.code, line.category)} size={20} />}
          label={<>{line.name} <GoodKind compact goodClass={line.class} /></>}
          value={<Figure value={formatInt(line.qty)} />}
          data-testid={testId}
        />
      ))}
      <Row label={t('ui.total')} tone="muted" value={<Figure value={formatFixed(totalTons, 1)} unit={t('ui.unitTons')} />} hairline={false} />
    </>
  )
}

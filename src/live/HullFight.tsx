import { Figure, Row } from '../components/ui'
import { formatInt } from '../lib/format'
import { useT } from '../lib/i18n'
import type { SnapshotShipClass } from '../lib/rpc'

// WHAT A HULL FIGHTS WITH (0366, owner row 322: "especially combat related ships"): attack, accuracy, reach, armour and sighting, the five
// figures the fight reads (public.fight_sides), as the class has them: before gear, skills and captains. ONE renderer for the Codex's ship
// sheet and the build yard's, so a combat hull is chosen by the same figures in both. The class row is the snapshot's (served whole since
// 0074); a class the snapshot has not named, or a server that sends no figures, draws nothing.

export function HullFight({ cls }: { cls: SnapshotShipClass | null | undefined }) {
  const t = useT()
  if (!cls || cls.attack === undefined || cls.armour === undefined) return null
  const rows: readonly (readonly [string, number | undefined])[] = [
    [t('ship.attack'), cls.attack],
    [t('ship.accuracy'), cls.accuracy],
    [t('ship.reach'), cls.reach],
    [t('ship.armour'), cls.armour],
    [t('ship.sighting'), cls.sighting],
  ]
  return (
    <div data-testid="hull-fight">
      {rows.map(([label, value]) => (value === undefined ? null : <Row key={label} label={label} value={<Figure value={formatInt(value)} />} />))}
    </div>
  )
}

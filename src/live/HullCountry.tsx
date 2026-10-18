import { Flag, type FlagSize } from '../components/ui'
import { nationNameOf, useWorld } from './worldStore'

// A HULL'S COUNTRY (0130) — the flag of the country whose line it belongs to, and that country's
// name, small. ONE renderer for the Codex and the build yard, so the two can never show a hull
// under different flags. Since 0143 it is THE nation-flag renderer of the game for anything that
// is not a city: a merchant's company (MerchantSheet, MerchantRow, ShipPanel), your own company
// (Profile, your fleet's tray), a city's influence standings (TownHallInfluence), the countries
// board and the country picker (NationPicker). A city's own flag is PortFlag, which reads the
// city's holder and draws the same `Flag`. The nation code is served (snapshot
// `ship_classes[].line_nation`, `world.building_yard` `hulls[].line_nation`, `company.nation_code`
// …); the name comes from the one nation catalogue (`nationByCode`) and the picture from the one
// design-system `Flag` (2026-10-18: a bundled picture per code, public/flags) — never a table here.

/** `compact`: the flag alone (the name as its label and tooltip) — for a tile line that must keep its figures. */
export function HullCountry({
  nation,
  compact = false,
  size = 'body',
}: {
  nation: string | null | undefined
  compact?: boolean
  size?: FlagSize
}) {
  const nationByCode = useWorld((s) => s.nationByCode)
  if (!nation) return null
  const name = nationNameOf(nationByCode, nation)
  if (compact) {
    return (
      <span className="inline-flex items-center" data-testid="hull-country">
        <Flag code={nation} name={name} size={size} />
      </span>
    )
  }
  return (
    <span className="inline-flex items-center gap-1.5" data-testid="hull-country">
      <Flag code={nation} name={name} size={size} />
      <span>{name}</span>
    </span>
  )
}

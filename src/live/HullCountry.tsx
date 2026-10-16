import { Note } from '../components/ui'
import { nationNameOf, useWorld } from './worldStore'

// A HULL'S COUNTRY (0130) — the flag of the country whose line it belongs to, and that country's
// name, small. ONE renderer for the Codex and the build yard, so the two can never show a hull
// under different flags. The nation code is served (snapshot `ship_classes[].line_nation`,
// `world.building_yard` `hulls[].line_nation`); the flag and the name come from the one nation
// catalogue (`nationByCode`), never from a table kept here.

/** `compact`: the flag alone (the name as its label) — for a tile line that must keep its figures. */
export function HullCountry({ nation, compact = false }: { nation: string | null | undefined; compact?: boolean }) {
  const nationByCode = useWorld((s) => s.nationByCode)
  if (!nation) return null
  const flag = nationByCode[nation]?.flag_char
  const name = nationNameOf(nationByCode, nation)
  if (compact) {
    return (
      <span role="img" aria-label={name} title={name} data-testid="hull-country">
        {flag ?? name}
      </span>
    )
  }
  return (
    <span className="inline-flex items-center gap-1" data-testid="hull-country">
      {flag && <span aria-hidden>{flag}</span>}
      <span>{name}</span>
    </span>
  )
}

/** THE COUNTRY REFUSAL, said before the order is sent: the countries whose build yards may build
 *  this hull, by name ("A, B or C"). Shown where the server answered `right_yard: false`. */
export function WrongYardNote({ builders }: { builders: readonly string[] | undefined }) {
  const nationByCode = useWorld((s) => s.nationByCode)
  const names = (builders ?? []).map((c) => nationNameOf(nationByCode, c))
  const list = names.length <= 1 ? (names[0] ?? '') : `${names.slice(0, -1).join(', ')} or ${names[names.length - 1]}`
  return (
    <Note tone="warning" data-testid="yard-country">
      {`Only build yards in ${list} can build this ship.`}
    </Note>
  )
}

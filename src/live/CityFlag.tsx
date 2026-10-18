import type { PortAllegiance } from '../lib/rpc'
import { nationNameOf, useWorld } from './worldStore'

// A CITY'S COUNTRY, IN WORDS (0143, docs/INFLUENCE.md D14) — the country that holds a harbour today
// and whether it can change hands: `Portugal · Home city`, `Castile-Spain · Contested`, `No country`.
// The flag itself stands beside the city's NAME on the line above (PortFlag, 2026-10-18), so this
// line prints the words only — one flag per city on the tray, not two. The fact is `portNationOf`
// (worldStore), which is `world.allegiance`, which is `public.port_nation`. Words: docs/WORDS.md
// (Home city / Contested / No country).

/** The title line's part. The caller passes the allegiance it read with `portNationOf`, so a city
 *  whose flag has not been read yet prints nothing here — never a guessed country. */
export function CityFlag({ allegiance }: { allegiance: PortAllegiance }) {
  const nationByCode = useWorld((s) => s.nationByCode)
  if (allegiance.nation === null) return <span data-testid="city-flag">No country</span>
  return (
    <span data-testid="city-flag">
      {`${nationNameOf(nationByCode, allegiance.nation)} · ${allegiance.home ? 'Home city' : 'Contested'}`}
    </span>
  )
}

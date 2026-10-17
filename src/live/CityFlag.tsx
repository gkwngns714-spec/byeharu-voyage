import type { PortAllegiance } from '../lib/rpc'
import { HullCountry } from './HullCountry'

// A CITY'S FLAG (0143, docs/INFLUENCE.md D14) — the country that holds a harbour today and whether
// it can change hands: `⚓ Portugal · Home city`, `⚔ Castile-Spain · Contested`, `No country`.
// The flag and the name are HullCountry's (the one nation-flag renderer — a hull's, a merchant's and
// a city's flag can never be drawn two ways); the fact is `portNationOf` (worldStore), which is
// `world.allegiance`, which is `public.port_nation`. Words: docs/WORDS.md (Home city / Contested /
// No country).

/** The title line's part. The caller passes the allegiance it read with `portNationOf`, so a city
 *  whose flag has not been read yet prints nothing here — never a guessed flag. */
export function CityFlag({ allegiance }: { allegiance: PortAllegiance }) {
  if (allegiance.nation === null) return <span data-testid="city-flag">No country</span>
  return (
    <span className="inline-flex items-center gap-1" data-testid="city-flag">
      <HullCountry nation={allegiance.nation} />
      <span>· {allegiance.home ? 'Home city' : 'Contested'}</span>
    </span>
  )
}

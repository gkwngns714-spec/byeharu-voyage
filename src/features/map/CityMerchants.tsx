import { useMemo } from 'react'
import { SheetSection } from '../../components/ui'
import { formatInt } from '../../lib/format'
import { MerchantRow } from '../../live/MerchantRow'
import { groupMerchants } from '../../live/merchantGroups'
import type { PortMerchant } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY'S MERCHANTS — every merchant the harbour concerns, grouped by what each is doing
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-11: *"By clicking the city, i get to see what trading ships started, resting,
// ending etc."* — 2026-10-13: *"i want there to be a list, showing the total level, and its current
// time till the resting finishes."* — 2026-10-14: *"i press a city and i see no ship info. Why did
// this revert back?"*
//
// This file was `RestingHere.tsx` and printed only the merchants LYING in the city. Since 0116 a
// merchant rests two real minutes, so a harbour the server answers with twenty-five merchants —
// two to nine of them starting, ending or passing — printed nothing at all. Both of the owner's
// sentences hold now: the tray lists EVERY merchant `world.port_merchants` serves for the city, in
// headed groups — In port (soonest rest-end first, with the time it ends) · Leaving · Arriving ·
// Passing · Away — and a city with merchants is never blank.
//
// THE GROUPING IS NOT THIS FILE'S (`src/live/merchantGroups.ts`): which word stands under which
// heading, in what order, is one table PORT can read the day its section groups too. The row is
// `src/live/MerchantRow`, the same one PORT prints, and the words are `src/live/merchantWords.ts`,
// so the two screens cannot drift. A tap opens the same read-only sheet from both.
export function CityMerchants({
  rows,
  portCode,
  nowMs,
  onOpen,
}: {
  /** The harbour's whole read — every merchant whose loop calls at the tapped city, in the
   *  server's rank — handed down by MapScreen, which is the one place that knows which city. */
  rows: readonly PortMerchant[]
  /** The tapped city's code — what decides whether a row's merchant lies HERE (`m.port`), the
   *  same rule PORT's section applies. */
  portCode: string | null
  nowMs: number
  onOpen: (fleetId: string) => void
}) {
  const groups = useMemo(() => groupMerchants(rows), [rows])
  if (groups.length === 0) return null
  return (
    <div data-testid="map-merchants">
      {groups.map((g) => (
        <SheetSection
          key={g.key}
          heading={g.heading}
          trailing={
            <span className="text-t-caption text-ink-muted" data-testid="map-merchants-count">
              {formatInt(g.rows.length)}
            </span>
          }
          surface
          data-testid={`map-merchants-${g.key.replace('_', '-')}`}
        >
          {g.rows.map((m, i) => (
            <MerchantRow
              key={m.id}
              m={m}
              here={portCode !== null && m.port === portCode}
              nowMs={nowMs}
              onOpen={onOpen}
              hairline={i < g.rows.length - 1}
            />
          ))}
        </SheetSection>
      ))}
    </div>
  )
}
